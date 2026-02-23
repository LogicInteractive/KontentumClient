package utils;

import fox.native.windows.WindowsSystemUtils;
import haxe.Timer;
import Lambda;
import utils.Log;

/**
 * ...
 * @author Tommy S.
 */

class SubProcess
{
	/////////////////////////////////////////////////////////////////////////////////////

	public var currentProcessID					: UInt			= 0;
	public var launchDelay						: Float			= 3.0;
	public var restartDelay						: Float			= 2.0;
	public var launchPath						: String;
	public var args								: String		= "";
	public var workingDirectory					: String		= "";
	public var waitForProcessToFinish			: Bool			= false;
	public var isAlive							: Bool			= false;

	public var restartIfCrash					: Bool			= true;
	public var restartIfExit					: Bool			= true;
	public var lifeSpan							: Float			= -1;
	public var monitor							: Bool			= false;
	public var waitForStart						: Bool			= false;
	public var lifePingTime						: Int			= 200;		// ms for how often to check if subprocess is alive
	public var maxRestartsPerMinute				: Int			= 5;		// Safety limit for crash loops
	public var maxTotalRestarts					: Int			= 20;		// Absolute limit before giving up

	/////////////////////////////////////////////////////////////////////////////////////

	var deathTimer								: Timer;
	var lifePingTimer							: Timer;
	var launchDelayTimer						: Timer;
	var crashHistory							: Array<Float>	= [];		// Track crash timestamps
	var consecutiveCrashes						: Int			= 0;
	var totalRestarts							: Int			= 0;		// Total restarts since launch
	var processStartTime						: Float			= 0.0;
	var serverNotificationsSent					: Int			= 0;		// Track server notifications
	var disabledDueToExcessiveCrashes			: Bool			= false;	// Shutdown flag
	var monitoringPending						: Bool			= false;	// Flag for deferred monitoring setup

	public var subprocessDidCrash				: Void->Void;
	public var subprocessDidExit				: Void->Void;

	// Static list of subprocesses that need monitoring setup from main thread
	static var pendingMonitorSetup				: Array<SubProcess> = [];

	//===================================================================================
	// Static Methods
	//-----------------------------------------------------------------------------------

	/**
	 * Called from main thread to setup monitoring for subprocesses that were launched
	 * from background threads (e.g., HTTP callbacks) where Timer creation fails.
	 * Should be called periodically from the main event loop.
	 */
	public static function processPendingMonitorSetup():Void
	{
		if (pendingMonitorSetup.length == 0)
			return;

		// Process all pending subprocesses
		var toProcess = pendingMonitorSetup.copy();
		pendingMonitorSetup = [];

		for (sp in toProcess)
		{
			if (sp.monitoringPending && sp.monitor && sp.currentProcessID > 0)
			{
				try
				{
					if (sp.lifePingTimer != null)
						sp.lifePingTimer.stop();

					sp.lifePingTimer = new Timer(sp.lifePingTime);
					sp.lifePingTimer.run = sp.onLifePingTrigger;
					sp.monitoringPending = false;
					trace("[SubProcess] Deferred monitoring setup completed for PID: " + sp.currentProcessID);
				}
				catch (e:Dynamic)
				{
					trace("[SubProcess] ERROR: Failed to setup monitoring even on main thread: " + e);
				}
			}
		}
	}

	//===================================================================================
	// ClientFunctions
	//-----------------------------------------------------------------------------------

	public function new(launchPath:String) 
	{
		this.launchPath = launchPath;
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	public function run():Bool
	{
		if (launchDelay > 0)
		{
			if (launchDelayTimer != null)
				launchDelayTimer.stop();
				
			waitForStart = true;
			launchDelayTimer = Timer.delay(processLaunch, Math.floor(launchDelay*1000));
		}
		else 
			return processLaunch();
			
		return true;
	}
	
	function processLaunch():Bool
	{
		try
		{
			waitForStart = false;
			trace("[SubProcess] Launching: " + launchPath);

			// Use the FIXED WindowsSystemUtils.createProcess() which now properly handles
			// mutable command line buffers (CreateProcessA requirement)
			currentProcessID = WindowsSystemUtils.createProcess(launchPath, args, waitForProcessToFinish, workingDirectory);

			trace("[SubProcess] createProcess returned PID: " + currentProcessID);

			if (currentProcessID == 0)
			{
				trace("[SubProcess] Failed to create process");
				return false;
			}

			processStartTime = haxe.Timer.stamp();
			trace("[SubProcess] Process started successfully, PID: " + currentProcessID);

			if (lifeSpan > 0)
			{
				trace("[SubProcess] Setting death delay: " + lifeSpan);
				setDeathDelay(lifeSpan);
			}

			if (monitor)
			{
				trace("[SubProcess] Monitoring requested");
				// Timer creation fails when called from background threads (HTTP callbacks)
				// with "Event loop is not available" error. Use deferred setup via main thread.

				try {
					if (lifePingTimer != null)
						lifePingTimer.stop();

					lifePingTimer = new Timer(lifePingTime);
					lifePingTimer.run = onLifePingTrigger;
					trace("[SubProcess] Monitoring enabled successfully");
				}
				catch (e:Dynamic)
				{
					// Timer creation failed - we're likely on a background thread
					// Queue this subprocess for monitoring setup on the main thread
					trace("[SubProcess] Deferring monitoring setup to main thread");
					monitoringPending = true;
					if (!Lambda.has(pendingMonitorSetup, this))
						pendingMonitorSetup.push(this);
				}
			}

			trace("[SubProcess] processLaunch completed successfully");
			return true;
		}
		catch (e:Dynamic)
		{
			trace("[SubProcess] EXCEPTION in processLaunch: " + e);
			utils.Log.logException("[SubProcess] processLaunch failed", e);
			return false;
		}
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	public function terminate():Bool
	{
		if (currentProcessID == 0) // No process running
			return false;

		if (deathTimer != null)
			deathTimer.stop();

		return WindowsSystemUtils.killProcess(currentProcessID);
	}
	
	public function restart()
	{
		// Check if we've hit absolute restart limit
		if (totalRestarts >= maxTotalRestarts)
		{
			trace('CRITICAL: Maximum restart limit reached (${totalRestarts}/${maxTotalRestarts}). Disabling auto-restart.');
			disabledDueToExcessiveCrashes = true;
			restartIfCrash = false;
			restartIfExit = false;
			return;
		}

		// Check if we're in a rapid crash loop
		cleanCrashHistory();
		if (crashHistory.length >= maxRestartsPerMinute)
		{
			trace('WARNING: Crash rate limit exceeded (${crashHistory.length} crashes in 60s). Pausing restarts for 60s.');
			// Wait full minute before allowing restart
			Timer.delay(() -> {
				if (!disabledDueToExcessiveCrashes)
				{
					trace('Resuming after rate limit pause...');
					restartAfterDelay();
				}
			}, 60000);
			return;
		}

		restartAfterDelay();
	}

	function restartAfterDelay()
	{
		totalRestarts++;

		// Calculate restart delay with exponential backoff for crash loops
		var delay = getRestartDelay();

		if (delay > restartDelay)
		{
			trace('Crash loop detected. Restarting in ${delay}s (crash #${consecutiveCrashes}, total restarts: ${totalRestarts}/${maxTotalRestarts})');
		}

		launchDelay = delay;
		terminate();
		run();
	}
	
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	public function forceQuitNoRestart()
	{
		isAlive = false;
		if (launchDelayTimer != null)
			launchDelayTimer.stop();
			
		if (lifePingTimer != null)
			lifePingTimer.stop();
			
		terminate();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	function onLifePingTrigger()
	{
		// Wrap in try/catch to prevent unhandled exceptions from killing the timer
		try
		{
			isAlive = false;
			if (!waitForStart && !disabledDueToExcessiveCrashes)
			{
				var status = checkAliveStatus();

				if (status == -1) //  NO_PROCESS_STARTED
				{
					// Process not started yet
				}
				else if (status == 259) // STILL_ACTIVE (Windows constant)
				{
					isAlive = true;
					// Process is running fine, check if it's been stable
					checkStability();
				}
				else if (status == 0) // EXIT_SUCCESS
				{
					recordExit(false);
					if (subprocessDidExit != null && shouldNotifyServer())
						subprocessDidExit();
					handleExit();
				}
				else // EXIT_FAILURE (1) or any other abnormal exit code
				{
					recordExit(true);
					if (subprocessDidCrash != null && shouldNotifyServer())
						subprocessDidCrash();
					handleCrash();
				}
			}
		}
		catch (e:Dynamic)
		{
			Log.logException("[SubProcess] Exception in onLifePingTrigger", e);
		}
	}

	/**
	 * Check if we should send server notification (prevent flooding)
	 */
	function shouldNotifyServer():Bool
	{
		// Limit server notifications to prevent flooding
		// Max 10 notifications per subprocess lifecycle
		if (serverNotificationsSent >= 10)
		{
			if (serverNotificationsSent == 10)
				trace('Server notification limit reached. Suppressing further notifications.');
			return false;
		}

		serverNotificationsSent++;
		return true;
	}
	
	public function checkAliveStatus():Int
	{
		if (currentProcessID > 0)
			return WindowsSystemUtils.checkProcessInfo(currentProcessID);
		else
			return -1;
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	function handleExit()
	{
		if (restartIfExit)
			restart();
	}

	function handleCrash()
	{
		if (restartIfCrash)
			restart();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	function setDeathDelay(lifeSpan:Float) 
	{
		if (deathTimer != null)
			deathTimer.stop();
			
		deathTimer = Timer.delay(triggerDeath, Math.floor(lifeSpan * 1000));
	}
	
	function triggerDeath()
	{
		deathTimer = null;
		terminate();
	}

	/////////////////////////////////////////////////////////////////////////////////////

	/**
	 * Track exit/crash events and update crash history
	 */
	function recordExit(isCrash:Bool)
	{
		var now = haxe.Timer.stamp();
		var uptime = now - processStartTime;

		// If crashed quickly (< 10 seconds), it's a bad crash
		if (isCrash || uptime < 10)
		{
			crashHistory.push(now);
			consecutiveCrashes++;

			// Log crash with context
			var msg = 'Subprocess ${isCrash ? "crashed" : "exited quickly"} after ${Math.round(uptime)}s (crash #${consecutiveCrashes})';
			trace(msg);
		}
		else
		{
			// Normal exit after running for a while
			consecutiveCrashes = 0;
		}

		// Clean old crash history (older than 60s)
		cleanCrashHistory();
	}

	/**
	 * Check if process has been stable, reset crash counter
	 */
	function checkStability()
	{
		var uptime = haxe.Timer.stamp() - processStartTime;

		// If stable for 10 minutes, reset crash counter
		if (uptime > 600 && consecutiveCrashes > 0)
		{
			trace('Subprocess stable for 10min, resetting crash counter');
			consecutiveCrashes = 0;
			crashHistory = [];
		}
	}

	/**
	 * Remove crash entries older than 60 seconds
	 */
	function cleanCrashHistory()
	{
		var now = haxe.Timer.stamp();
		var cutoff = now - 60;
		crashHistory = crashHistory.filter(t -> t > cutoff);
	}

	/**
	 * Calculate restart delay with exponential backoff
	 */
	function getRestartDelay():Float
	{
		cleanCrashHistory();

		// Check if too many crashes in last minute
		if (crashHistory.length >= maxRestartsPerMinute)
		{
			trace('Rate limit exceeded: ${crashHistory.length} crashes in 60s');
		}

		// Exponential backoff based on consecutive crashes
		// 0 crashes: restartDelay (default 2s)
		// 1-2 crashes: 5s
		// 3-4 crashes: 15s
		// 5-6 crashes: 60s
		// 7+ crashes: 300s (5min)
		if (consecutiveCrashes == 0)
			return restartDelay;
		else if (consecutiveCrashes <= 2)
			return 5.0;
		else if (consecutiveCrashes <= 4)
			return 15.0;
		else if (consecutiveCrashes <= 6)
			return 60.0;
		else
			return 300.0;
	}

	/////////////////////////////////////////////////////////////////////////////////////
}
