package;

import client.HostedFileSync;
import client.ServerCommunicator;
import fox.compile.CompileTime;
import fox.kontentum.Kontentum;
import fox.loader.Loader;
import fox.native.windows.Chrome;
import fox.utils.Convert;
import fox.utils.DateUtils;
import fox.utils.ObjUtils;
import fox.utils.Tick;
import haxe.Resource;
import haxe.Timer;
import haxe.io.Bytes;
import haxe.io.Path;
import haxe.macro.Expr.Catch;
import sys.FileSystem;
import sys.io.File;
import utils.Mutex;
import utils.SubProcess;
import utils.WindowsRegistry;
import utils.WindowsUtils;

/**
 * ...
 * @author Tommy S.
 */

#if windows
@:cppFileCode('
#include <iostream>
#include <windows.h>
#include <conio.h>
#include <string>

static std::string g_inputResult;

// Function to read input with timeout and countdown display (Windows only)
static bool KC_ReadLineWithTimeout(int timeoutSeconds, char* buffer, int bufferSize)
{
	DWORD startTime = GetTickCount();
	int pos = 0;
	buffer[0] = 0;
	int lastDisplayedSeconds = timeoutSeconds;
	bool firstDisplay = true;

	// Print initial countdown message
	printf("Y N (auto install in : %d) ", timeoutSeconds);
	fflush(stdout);

	while (true)
	{
		// Calculate elapsed time
		DWORD elapsedMs = GetTickCount() - startTime;
		DWORD elapsedSec = elapsedMs / 1000;
		int remainingSeconds = timeoutSeconds - (int)elapsedSec;

		// Check if timeout expired
		if (remainingSeconds <= 0)
		{
			// Clear the countdown line and show timeout message
			printf("\\r%*s\\r", 50, "");  // Clear line
			printf("Timeout - auto-installing...\\n");
			return false; // Timeout
		}

		// Update countdown display if the second has changed
		if (remainingSeconds != lastDisplayedSeconds)
		{
			// Clear previous line and reprint with updated countdown
			if (pos == 0)
			{
				// No user input yet - update just the countdown
				printf("\\rY N (auto install in : %d) ", remainingSeconds);
				// Pad to clear any extra digits (e.g., going from 10 to 9)
				if (remainingSeconds < 10 && lastDisplayedSeconds >= 10)
					printf(" ");
			}
			else
			{
				// User has started typing - show their input and countdown
				printf("\\rY/N (auto install in : %d) %.*s", remainingSeconds, pos, buffer);
				// Pad to clear any extra characters
				printf("  ");
			}
			fflush(stdout);
			lastDisplayedSeconds = remainingSeconds;
		}

		// Check if key is available (non-blocking)
		if (_kbhit())
		{
			int ch = _getch();

			if (ch == \'\\r\' || ch == \'\\n\')  // Enter key
			{
				buffer[pos] = 0;
				printf("\\r%*s\\r", 50, "");  // Clear line
				return true;
			}
			else if (ch == \'\\b\' && pos > 0)  // Backspace
			{
				pos--;
				buffer[pos] = 0;
				// Redraw the line with updated input
				printf("\\rY N (auto install in : %d) %.*s ", remainingSeconds, pos, buffer);
				fflush(stdout);
			}
			else if ((ch == \'y\' || ch == \'Y\' || ch == \'n\' || ch == \'N\') && pos < bufferSize - 1)
			{
				// Accept only Y/N characters
				buffer[pos++] = (char)ch;
				buffer[pos] = 0;
				// Redraw the line with updated input
				printf("\\rY N (auto install in : %d) %c", remainingSeconds, ch);
				fflush(stdout);
			}
		}

		// Pump Windows messages to keep tray responsive
		MSG msg;
		while (PeekMessageA(&msg, NULL, 0, 0, PM_REMOVE))
		{
			TranslateMessage(&msg);
			DispatchMessageA(&msg);
		}

		Sleep(100);  // Sleep for 100ms to avoid busy-waiting
	}
}

// Wrapper that returns String instead of filling buffer
static ::String KC_ReadLineWithTimeoutWrapper(int timeoutSeconds)
{
	char buffer[256] = {0};
	bool success = KC_ReadLineWithTimeout(timeoutSeconds, buffer, sizeof(buffer));
	return success ? ::String(buffer) : null();
}
')
#end
class KontentumClient 
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public var i					: KontentumClient;
	static public var config			: ConfigXML;
	static public var buildDate			: Date				= CompileTime.buildDate();
	static public var ready				: Bool				= false;
	static public var debug				: Bool				= false;
	static public var downloadFiles		: Bool				= false;
	static public var killExplorer		: Bool				= false;
	static public var enableWatchdog	: Bool				= true;
	static public var consecutiveRestarts: Int				= 0;
	static public var maxConsecutiveRestarts: Int			= 3;
	static public var startupCheckNeeded: Bool				= false;
	static public var appID				: Int				= 0;		// Received from server in first ping response
	static public var skipAppLaunch		: Bool				= false;	// Skip app launch after crash recovery (avoid duplicate launches)

	var waitDelay						: Float				= 0.0;
	static var firstCommand				: String;
	static var chrome					: Chrome;

	static public var offlineLaunchFile	: String			= "c:/temp/kontentum_offlinelaunch";

	static var chromeMonitorTimer		: Timer;
	static var chromeRestartDelay		: Float				= 3.0;
	static var chromeCrashCount			: Int				= 0;
	static var chromeMaxRestarts		: Int				= 10;
	static var chromeCrashHistory		: Array<Float>		= [];		// Track crash timestamps
	static var chromeMaxCrashesPerMinute: Int				= 5;		// Rate limit
	static var chromeStartTime			: Float				= 0.0;		// Track when browser started
	static var chromeRestartPending		: Bool				= false;	// Guard against race condition
	static var watchdogPingTimer		: Timer;						// Timer for pinging watchdog
	static var trayTimer				: Timer;						// Timer for tray message pump

	/////////////////////////////////////////////////////////////////////////////////////

	static public function main()
	{
		// Check if this is a watchdog restart and track consecutive restarts
		checkRestartCount();

		// Parse CLI arguments before anything else
		var args = Sys.args();
		var shouldInstall = false;
		var shouldUninstall = false;
		var skipStartupPrompt = false;

		// Log received arguments for debugging
		var argsStr = (args != null && args.length > 0) ? args.join(", ") : "(none)";
		Sys.println("[STARTUP] Arguments received: " + argsStr);

		for (arg in args)
		{
			switch (arg)
			{
				case "--install":
					shouldInstall = true;
				case "--uninstall":
					shouldUninstall = true;
				case "--skip":
					skipStartupPrompt = true;
				case "--no-watchdog":
					enableWatchdog = false;
				case "--forcedrestart":
					// Flag indicates this is a crash recovery restart
					// Skip app launch - the app is probably still running
					skipAppLaunch = true;
					Sys.println("[STARTUP] --forcedrestart detected, skipAppLaunch = true");
			}
		}

		// Handle install/uninstall commands (these exit immediately, no watchdog needed)
		if (shouldInstall)
		{
			handleStartupInstall();
			return;
		}

		if (shouldUninstall)
		{
			handleStartupUninstall();
			return;
		}

		// Check for duplicate instances using a named mutex
		#if windows
		if (!Mutex.tryAcquire("Local\\KontentumClient_SingleInstance"))
		{
			Sys.println("Another instance of KontentumClient is already running.");
			Sys.exit(0);
		}
		#end

		// Mark that startup check is needed (unless --skip was passed)
		// Actual check happens after config is loaded in initSettings()
		if (!skipStartupPrompt)
		{
			startupCheckNeeded = true;
		}

		try
		{
			if (i == null)
				i = new KontentumClient();
		}
		catch (e:Dynamic)
		{
			// Handle exception: log, submit crash event to server, and restart
			utils.CrashHandler.handleException("[BOOT] Unhandled exception", e);
		}

		// Timer.delay(freeze, 10000);
	}
	
	static function freeze()
	{
		while (true)
		{
			Sys.sleep(1);
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function checkRestartCount():Void
	{
		// Check if this was a watchdog restart
		var wasRestarted = Sys.getEnv("APP_RESTARTED");

		if (wasRestarted == "1")
		{
			// This is a restart - check the restart counter file
			var restartFile = "bin/restart_count.tmp";

			try
			{
				if (sys.FileSystem.exists(restartFile))
				{
					var content = sys.io.File.getContent(restartFile);
					var parts = content.split("|");

					if (parts.length >= 2)
					{
						consecutiveRestarts = Std.parseInt(parts[0]);
						var lastRestartTime = Std.parseFloat(parts[1]);
						var now = haxe.Timer.stamp();

						// Reset counter if last restart was more than 5 minutes ago
						if (now - lastRestartTime > 300)
						{
							consecutiveRestarts = 1;
						}
						else
						{
							consecutiveRestarts++;
						}
					}
					else
					{
						consecutiveRestarts = 1;
					}
				}
				else
				{
					consecutiveRestarts = 1;
				}

				// Save updated count
				var now = haxe.Timer.stamp();
				sys.io.File.saveContent(restartFile, consecutiveRestarts + "|" + now);

				// Check if we've exceeded the limit
				if (consecutiveRestarts >= maxConsecutiveRestarts)
				{
					Sys.println("");
					Sys.println("===============================================");
					Sys.println("CRITICAL: Restart loop detected!");
					Sys.println("App has restarted " + consecutiveRestarts + " times in 5 minutes.");
					Sys.println("Disabling watchdog to prevent infinite restart loop.");
					Sys.println("Please check logs for errors and fix the issue.");
					Sys.println("===============================================");
					Sys.println("");

					// Disable watchdog to break the loop
					enableWatchdog = false;

					// Log to file
					try
					{
						utils.Log.init();
						trace("CRITICAL: Restart loop detected. Disabled watchdog after " + consecutiveRestarts + " restarts.");
					}
					catch (e:Dynamic) {}
				}
				else
				{
					Sys.println("Info: App restarted by watchdog (" + consecutiveRestarts + "/" + maxConsecutiveRestarts + " restarts)");
				}
			}
			catch (e:Dynamic)
			{
				// If we can't read/write the file, assume first restart
				consecutiveRestarts = 1;
			}
		}
		else
		{
			// Normal startup - clear restart counter
			try
			{
				var restartFile = "bin/restart_count.tmp";
				if (sys.FileSystem.exists(restartFile))
				{
					sys.FileSystem.deleteFile(restartFile);
				}
			}
			catch (e:Dynamic) {}

			consecutiveRestarts = 0;
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function handleStartupInstall():Void
	{
		#if windows
		var exePath = Sys.programPath();
		var success = WindowsRegistry.installStartup(exePath, "");

		if (success)
		{
			Sys.println("✓ Startup installed successfully");
			Sys.println("  Registry: HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run\\KontentumClient");
			Sys.println("  Command: \"" + exePath + "\"");
			Sys.exit(0);
		}
		else
		{
			Sys.println("✗ Failed to install startup");
			Sys.exit(1);
		}
		#end
	}

	static function handleStartupUninstall():Void
	{
		#if windows
		var success = WindowsRegistry.uninstallStartup();

		if (success)
		{
			Sys.println("✓ Startup uninstalled successfully");
			Sys.exit(0);
		}
		else
		{
			Sys.println("✗ Failed to uninstall startup (may not be installed)");
			Sys.exit(1);
		}
		#end
	}

	static function checkStartupInstallation():Void
	{
		#if windows
		if (WindowsRegistry.isStartupInstalled())
		{
			// Already installed, nothing to do
			return;
		}

		// Allocate a console if we don't have one (for GUI apps)
		WindowsUtils.allocConsole();
		WindowsUtils.setConsoleTitle("Kontentum Client - Startup Configuration");

		// Temporarily disable watchdog during user interaction
		// The prompt can take up to 30 seconds, which exceeds the 10-second watchdog timeout
		var watchdogWasEnabled = enableWatchdog;
		if (watchdogWasEnabled)
		{
			utils.WatchDog.stop();
		}

		// Not installed - prompt the user with 30-second timeout
		Sys.println("");
		Sys.println("Startup is not installed.");
		Sys.println("Do you want KontentumClient to start automatically at login?");
		Sys.println("");

		// Read input with 30-second timeout (shows countdown inline)
		var input = readInputWithTimeout(30);

		// Re-enable watchdog if it was enabled before
		if (watchdogWasEnabled)
		{
			var exe = Sys.programPath();
			var restartCmd = '"' + exe + '"';
			var timeoutMs = 30000;
			utils.WatchDog.start(timeoutMs, restartCmd);

			// Pass the app mutex handle to watchdog so it can release it before restart
			utils.WatchDog.setAppMutex(utils.Mutex.getHandle());

			// Recreate the ping timer
			if (watchdogPingTimer != null)
			{
				watchdogPingTimer.stop();
			}
			watchdogPingTimer = new haxe.Timer(Std.int(timeoutMs / 3));
			watchdogPingTimer.run = function ()
			{
				utils.WatchDog.ping();
			};
		}

		// Default to "yes" if timeout or empty
		if (input == null || input == "")
		{
			Sys.println("[OK] Auto-installing startup...");
			input = "y";
		}
		else
		{
			Sys.println("");  // Add newline after user input
		}

		input = input.toLowerCase();

		if (input == "y" || input == "yes")
		{
			var exePath = Sys.programPath();
			var success = WindowsRegistry.installStartup(exePath, "");

			if (success)
			{
				Sys.println("[OK] Startup installed successfully");
			}
			else
			{
				Sys.println("[ERROR] Failed to install startup");
			}
		}
		else
		{
			Sys.println("Startup not installed. You can install it later with: KontentumClient.exe --install");
		}

		Sys.println("");

		// Free the console we allocated for the prompt (only in non-debug mode)
		// In debug mode, keep the console so trace logging continues to work
		if (!debug)
			WindowsUtils.freeConsole();

		// NOTE: App continues running (does NOT exit)
		#end
	}

	static function readInputWithTimeout(timeoutSeconds:Int):String
	{
		#if windows
		// Use the C++ non-blocking input function with countdown display
		return untyped __cpp__('KC_ReadLineWithTimeoutWrapper({0})', timeoutSeconds);
		#else
		return Sys.stdin().readLine();
		#end
	}

	/////////////////////////////////////////////////////////////////////////////////////

	public function new()
	{
		utils.Log.init();               // start file logging + override haxe.Log.trace
		#if windows
		// Make the logger path visible to the C++ crash filter
		var dir = haxe.io.Path.directory(utils.Log.path());
		var envDir = StringTools.replace(dir, "/", "\\");
		var envFile = StringTools.replace(utils.Log.path(), "/", "\\");

		var dir = haxe.io.Path.directory(utils.Log.path());
		Sys.putEnv("KC_LOG_DIR", dir);
		Sys.putEnv("KC_LOG_FILE", utils.Log.path());
		utils.CrashHandler.install();
		// utils.CrashHandler.showCrashErrors(debug);

		// Build a restart command. Re-launch the same exe with args:
		var exe = Sys.programPath(); // full path to current exe
		var restartCmd = '"' + exe + '" --forcedrestart'; // Include flag to skip app launch on crash recovery
		var localDir = Path.directory(exe);

		// Set restart command for CrashHandler (handles unhandled exceptions)
		utils.CrashHandler.setRestartCommand(restartCmd);
		utils.Log.write("[CrashHandler] Restart command configured: " + restartCmd);
		#end

		// Start watchdog only if enabled (can be disabled with --no-watchdog flag)
		if (enableWatchdog)
		{
			var timeoutMs = 30000; // 30s watchdog window (needs headroom for Sys.sleep/init)
			utils.WatchDog.start(timeoutMs, restartCmd);

			// Pass the app mutex handle to watchdog so it can release it before restart
			utils.WatchDog.setAppMutex(utils.Mutex.getHandle());

			// Ping it regularly. Use ~timeout/3; don't cut it too close.
			watchdogPingTimer = new haxe.Timer(Std.int(timeoutMs / 3));
			watchdogPingTimer.run = function ()
			{
				try
				{
					utils.WatchDog.ping();
				}
				catch (e:Dynamic)
				{
					// Log but don't crash - watchdog ping is critical
					utils.Log.logException("[WatchdogPing] Exception", e);
				}
			};
		}

		#if windows
		WindowsUtils.setConsoleTitle("Kontentum Client  |  Logic Interactive");
		#end
		printLogo();
		checkOldUpdate();

		// utils.TrayUtils.createTrayIcon("KontentumClient  |  Logic Interactive");
		
		// WindowsUtils.takeScreenshot();

		var pDir:String = "";
		#if linux
		var appDir = Sys.programPath();
		if (appDir.split("KontentumClient").length > 1)
		{
			var si:Int = appDir.lastIndexOf("KontentumClient");
			appDir = appDir.substring(0, si);
			pDir = appDir.split("\\").join("/");
		}
		#else
		pDir = localDir;
		if (pDir != "" && !StringTools.endsWith(pDir, "/") && !StringTools.endsWith(pDir, "\\"))
			pDir += "/";
		#end
		Loader.LoadXML(pDir+"config.xml",null,onLoadXMLComplete,onLoadXMLFailed);

		createTray();
	}

	/////////////////////////////////////////////////////////////////////////////////////

	function onLoadXMLFailed(l:Loader)
	{
		Sys.println("Config XML failed to load! ("+l.source+")");
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	function onLoadXMLComplete(l:Loader)
	{
		try
		{
			config = cast ObjUtils.fromXML(l.contentXML,true);		
		}
		catch(e:Dynamic)
		{
			Sys.println("Error : Failed to process XML:");
			Sys.println(l.contentRAW);
		}

		initSettings();
		utils.WatchDog.ping(); // keep watchdog alive between init steps
		HostedFileSync.init();
		utils.WatchDog.ping();
		Tick.idle();
		utils.WatchDog.ping();
		ServerCommunicator.init();
		if (config.kontentum.download==true)
		{
			KontentumClient.downloadFiles = config.kontentum.download;
		}
		else 
			KontentumClient.ready = true;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	inline function initSettings()
	{
		debug = config.debug;

		// Apply watchdog config (if not already disabled by --no-watchdog flag)
		if (enableWatchdog && config.watchdog != null)
		{
			enableWatchdog = config.watchdog;
			if (!enableWatchdog)
			{
				if (debug)
					trace("Watchdog disabled via config.xml");
			}
		}

		// Set submitEvent URL for crash reporting (CrashHandler and Watchdog)
		// Format: /rest/submitEvent/{token}/{clientID}/ (message appended)
		if (config.kontentum != null && config.kontentum.exhibitToken != null && config.kontentum.clientID > 0)
		{
			var submitEventURL = config.kontentum.ip + "/rest/submitEvent/" +
				config.kontentum.exhibitToken + "/" +
				config.kontentum.clientID + "/";

			// Set for CrashHandler (unhandled exceptions)
			utils.CrashHandler.setSubmitEventURL(submitEventURL);

			// Set for Watchdog (heartbeat timeout, memory critical)
			if (enableWatchdog)
			{
				utils.WatchDog.setSubmitEventURL(submitEventURL);

				// Legacy notification URL: /rest/clientNotify/{token}/{id}/WatchdogCrashDetected
				var idToUse = appID > 0 ? appID : config.kontentum.clientID;
				var notifyURL = config.kontentum.ip + "/rest/clientNotify/" +
					config.kontentum.exhibitToken + "/" +
					idToUse + "/WatchdogCrashDetected";
				utils.WatchDog.setNotifyURL(notifyURL);

				if (debug)
				{
					var source = appID > 0 ? "app_id" : "clientID";
					trace("Watchdog notification URL: " + notifyURL + " (using " + source + ")");
				}
			}

			if (debug)
				trace("Crash/Event submitEvent URL: " + submitEventURL);
		}

		// Check if startup installation check should be performed
		// This happens after config is loaded so we can read disableStartupInstall
		// We delay this slightly to ensure tray is fully initialized first
		#if windows
		if (startupCheckNeeded)
		{
			// Check if disabled in config
			if (config.disableStartupInstall == true)
			{
				if (debug)
					trace("Startup installation prompt disabled via config.xml (disableStartupInstall=true)");
				startupCheckNeeded = false;
			}
			else
			{
				// Delay the startup check by 500ms to let tray initialize
				haxe.Timer.delay(function() {
					checkStartupInstallation();
				}, 500);
				startupCheckNeeded = false; // Mark as processed
			}
		}
		#end

		// Validate config BEFORE accessing its fields
		if (config.kontentum==null || config.kontentum.ip == null || config.kontentum.api == null || config.kontentum.clientID == 0)
		{
			if (debug)
				trace("Malformed config xml! Exiting.",true);

			KontentumClient.exitWithError();
			return; // Prevent further execution after exit call
		}

		// Now safe to access config.kontentum fields
		config.kontentum.interval = 1.0;

		if (config.kontentum.exhibitToken==null)
			config.kontentum.exhibitToken = "_";

		if (config.kontentum.downloadAllFiles!=null)
			Kontentum.forceDownloadAllFiles = Convert.toBool(config.kontentum.downloadAllFiles);

		#if windows
		// Handle console for debug/production mode
		// Crash restarts use DETACHED_PROCESS flag so child processes won't have a console
		// Don't allocate a console after crash restart - keep running silently
		if (!skipAppLaunch)
		{
			if (config.debug || config.kontentum.download)
			{
				// Debug or download mode: ensure we have a console (allocate if needed)
				WindowsUtils.allocConsole();
			}
			else
			{
				// Production mode: free console if present
				WindowsUtils.freeConsole();
			}
		}
		// After crash restart (skipAppLaunch=true): no console operations - continue silently

		if (config.killexplorer!=null)
			KontentumClient.killExplorer = config.killexplorer;

		if (KontentumClient.killExplorer)
			WindowsUtils.killExplorer();
		#end

		var args = Sys.args();
		if (args != null && args.length > 1)
		{
			if (args[0] == "delay")
			{
				var dly:Float = Std.parseFloat(args[1]);
				if (dly > 0.0)
					config.kontentum.delay = dly;
			}
		}
		
		if (config.kontentum.interval == 0)
			config.kontentum.interval = 15;


		if (config.kontentum.delay > 0)
		{
			// Sleep in short intervals so watchdog gets pinged during delay
			var remaining:Float = config.kontentum.delay;
			while (remaining > 0)
			{
				var chunk:Float = remaining > 2.0 ? 2.0 : remaining;
				Sys.sleep(chunk);
				utils.WatchDog.ping();
				remaining -= chunk;
			}
		}

	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function parseCommand(jsonPing:JSONPingData)
	{
		if (jsonPing==null)
			return;

		var meta:Dynamic = null;
		var cbstr:String = Std.string(jsonPing.callback);

		var cmd:SystemCommand = jsonPing.callback;
		if (cmd==null || cmd=="")
			return;

		if (jsonPing.callback==SystemCommand.shutdown&&jsonPing.sleep==true)
			cmd = SystemCommand.sleep;
		else
		{
			if (cbstr!=null && cbstr.indexOf("updateclient|")!=-1)
			{
				var updateURL:String = cbstr.split("updateclient|").join("");
				meta = updateURL;
				cmd = SystemCommand.updateclient;
			}
		}

		switch (cmd) 
		{
			case SystemCommand.none:			{};
			case SystemCommand.reboot:			WindowsUtils.systemReboot();
			case SystemCommand.shutdown:		WindowsUtils.systemShutdown();
			case SystemCommand.restart:			WindowsUtils.handleRestart();
			case SystemCommand.quit:			WindowsUtils.handleQuit();
			case SystemCommand.sleep:			WindowsUtils.systemSleep(false,false);
			case SystemCommand.updateclient:	KontentumClient.updateClient(meta);
		}
		firstCommand = cmd;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function exit()
	{
		// utils.TrayUtils.removeTrayIcon();
		#if windows
		utils.WatchDog.stop();
		Mutex.release();
		#end
		Sys.exit(0);
	}

	static public function exitWithError()
	{
		// utils.TrayUtils.removeTrayIcon();
		#if windows
		utils.WatchDog.stop();
		Mutex.release();
		#end
		Sys.exit(1);
	}

	// static public inline function debug(value:Dynamic,?force:Bool=false)
	// {
	// 	if (config==null || config.debug || force)
	// 		trace(value);
	// }

	/////////////////////////////////////////////////////////////////////////////////////

	static public function launchChrome(url:String)
	{
		if (chrome==null)
		{
			chrome = Chrome.launch(url,config.chrome);
			chromeStartTime = haxe.Timer.stamp();
			startChromeMonitoring();
		}
		else
			chrome.open(url);
	}

	static function startChromeMonitoring()
	{
		if (chromeMonitorTimer != null)
			chromeMonitorTimer.stop();

		// Monitor Chrome every 500ms to detect crashes
		chromeMonitorTimer = new Timer(500);
		chromeMonitorTimer.run = function()
		{
			// Wrap in try/catch to prevent unhandled exceptions from killing the timer
			try
			{
				if (chrome != null)
				{
					if (!chrome.checkAlive())
					{
						// Browser crashed!
						var uptime = haxe.Timer.stamp() - chromeStartTime;

						if (debug)
							trace('Chrome/Edge browser crashed or exited unexpectedly after ${Math.round(uptime)}s uptime.');

						// Stop monitoring to prevent duplicate crash handling
						if (chromeMonitorTimer != null)
							chromeMonitorTimer.stop();

						// Notify server of browser crash
						try
						{
							if (client.ServerCommunicator.i != null)
							{
								client.ServerCommunicator.i.submitAction("BROWSER_CRASH");
								client.ServerCommunicator.i.notifyEvent("BrowserCrash");
							}
						}
						catch (e:Dynamic)
						{
							if (debug)
								trace("Failed to notify server of browser crash");
						}

						handleChromeCrash();
					}
					else
					{
						// Browser is alive - check if it's been stable
						checkChromeStability();
					}
				}
			}
			catch (e:Dynamic)
			{
				utils.Log.logException("[ChromeMonitor] Exception", e);
			}
		};
	}

	static function handleChromeCrash()
	{
		// Guard against race condition - if restart is already pending, skip
		if (chromeRestartPending)
		{
			if (debug)
				trace('Chrome restart already pending, ignoring duplicate crash event');
			return;
		}

		// Record crash in history
		var now = haxe.Timer.stamp();
		chromeCrashHistory.push(now);
		chromeCrashCount++;

		// Clean old crash history (older than 60 seconds)
		cleanChromeCrashHistory();

		// Check if we've hit absolute restart limit
		if (chromeCrashCount >= chromeMaxRestarts)
		{
			if (debug)
				trace('CRITICAL: Chrome crash limit reached (${chromeCrashCount}/${chromeMaxRestarts}). Disabling auto-restart.');

			if (chromeMonitorTimer != null)
			{
				chromeMonitorTimer.stop();
				chromeMonitorTimer = null;
			}
			return;
		}

		// Check if we're in a rapid crash loop
		if (chromeCrashHistory.length >= chromeMaxCrashesPerMinute)
		{
			if (debug)
				trace('WARNING: Chrome crash rate limit exceeded (${chromeCrashHistory.length} crashes in 60s). Pausing restarts for 60s.');

			chromeRestartPending = true;
			// Wait full minute before allowing restart
			Timer.delay(function() {
				chromeRestartPending = false;
				if (chromeCrashCount < chromeMaxRestarts)
				{
					if (debug)
						trace('Resuming after rate limit pause...');
					restartChrome();
				}
			}, 60000);
			return;
		}

		restartChrome();
	}

	static function restartChrome()
	{
		// Set pending flag to prevent race conditions
		chromeRestartPending = true;

		// Calculate restart delay with exponential backoff
		var delay = getChromeRestartDelay();

		if (delay > chromeRestartDelay)
		{
			if (debug)
				trace('Crash loop detected. Restarting in ${delay}s (crash #${chromeCrashCount}, total: ${chromeCrashCount}/${chromeMaxRestarts})');
		}
		else
		{
			if (debug)
				trace('Restarting Chrome/Edge in ${delay}s (crash #${chromeCrashCount})');
		}

		Timer.delay(function()
		{
			// Clear pending flag now that we're actually restarting
			chromeRestartPending = false;

			// Try to get the last launched URL from cached file
			var lastUrl = getCachedLaunchFile();
			if (lastUrl != null && lastUrl != "")
			{
				chrome = Chrome.launch(lastUrl, config.chrome);
				chromeStartTime = haxe.Timer.stamp();
				startChromeMonitoring(); // Restart monitoring after relaunch
			}
			else if (config.kontentum.fallback != null && config.kontentum.fallback != "")
			{
				// Use fallback URL from config if available
				chrome = Chrome.launch(config.kontentum.fallback, config.chrome);
				chromeStartTime = haxe.Timer.stamp();
				startChromeMonitoring(); // Restart monitoring after relaunch
			}
			else
			{
				if (debug)
					trace("No URL available to restart Chrome. Monitoring stopped.");
			}
		}, Math.floor(delay * 1000));
	}

	/**
	 * Check if Chrome has been stable, reset crash counter
	 */
	static function checkChromeStability()
	{
		var uptime = haxe.Timer.stamp() - chromeStartTime;

		// If stable for 10 minutes, reset crash counter
		if (uptime > 600 && chromeCrashCount > 0)
		{
			if (debug)
				trace('Chrome stable for 10min, resetting crash counter (was: ${chromeCrashCount})');
			chromeCrashCount = 0;
			chromeCrashHistory = [];
		}
	}

	/**
	 * Remove crash entries older than 60 seconds
	 */
	static function cleanChromeCrashHistory()
	{
		var now = haxe.Timer.stamp();
		var cutoff = now - 60;
		chromeCrashHistory = chromeCrashHistory.filter(function(t) return t > cutoff);
	}

	/**
	 * Calculate restart delay with exponential backoff
	 */
	static function getChromeRestartDelay():Float
	{
		cleanChromeCrashHistory();

		// Exponential backoff based on consecutive crashes in last 60s
		// 0-1 crashes: chromeRestartDelay (default 3s)
		// 2-3 crashes: 5s
		// 4-5 crashes: 15s
		// 6-7 crashes: 60s
		// 8+ crashes: 300s (5min)
		var recentCrashes = chromeCrashHistory.length;

		if (recentCrashes <= 1)
			return chromeRestartDelay;
		else if (recentCrashes <= 3)
			return 5.0;
		else if (recentCrashes <= 5)
			return 15.0;
		else if (recentCrashes <= 7)
			return 60.0;
		else
			return 300.0;
	}

	static function getCachedLaunchFile():String
	{
		try
		{
			if (FileSystem.exists(offlineLaunchFile))
				return File.getContent(offlineLaunchFile);
		}
		catch (e:Dynamic)
		{
			if (debug)
				trace("Failed to read cached launch file");
		}
		return null;
	}

	static public function cacheLaunchFile(file:String)
	{
		if (file==null || file=="")
			return;
		try 
		{
			if (!FileSystem.exists("c:/temp"))
			{
				try 
				{
					FileSystem.createDirectory("c:/temp");
				}
				catch(e:haxe.Exception)
				{
					
				}
			}
			File.saveContent(offlineLaunchFile,file);
		}
		catch(e:Dynamic)
		{
			if (debug)
				trace("Failed to save offline launch file");
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	public function startFileDownload()
	{
		var bDate:String = DateUtils.getFormattedDate(KontentumClient.buildDate);
		// WindowsUtils.allocConsole();
		Sys.println('/// KONTENTUM ASSET DOWNLOADER /// (Build: $bDate)');
		Sys.println('');
		var token = config.kontentum.exhibitToken;
		Kontentum.onComplete = onKontentumReady;
		Kontentum.onDownloadFilesProgress = onKontentumDownloadProgress;
		Kontentum.onDownloadFilesItemComplete = onKontentumDownloadItemComplete;

		var localFileCache:String = Sys.getCwd()+'/cache/$token';
		if(config.kontentum.localFiles!=null && config.kontentum.localFiles!="")
			localFileCache = config.kontentum.localFiles;

		Kontentum.connect(config.kontentum.exhibitToken,config.kontentum.ip,localFileCache,true,false,false,true);
		Kontentum.fileURL = Kontentum.rest_ip + "/" + Kontentum.remoteFilePath + "/";
	}

	function onKontentumDownloadProgress()
	{
		Sys.print("\r"+Kontentum.downloadFilesProgressString+"    ");
	}

	function onKontentumDownloadItemComplete()
	{
		Sys.print("\n");
	}
	
	function onKontentumReady()
	{
		// trace("Kontenum ready! ");//+Kontentum.RESTJsonStr);

		ready = true;
		#if windows
		// Free console after download completes (download mode needs console for progress output)
		if (!debug)
			WindowsUtils.freeConsole();
		#end
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	static function updateClient(fileURL:String)
	{
		if (fileURL==null || fileURL=="")
			return;

		Loader.Load(fileURL,{saveFile:true,destinationFolder:Sys.getCwd()+"clientUpdate"},
			(l:Loader)-> //onComplete
			{
				if (KontentumClient.debug)
					trace('Client update downloaded: $fileURL to: destinationFolder');

				/*
				var script = '
				xcopy clientUpdate\\KontentumClient.exe KontentumClient.exe /y /q /k /u
				shutdown /r /f /t 0				
				';
				*/
				var updaterExe:Bytes = Resource.getBytes("updater");
				if (updaterExe==null)
				{
					if (KontentumClient.debug)
						trace('Updater failed to extract.');

					return;
				}

				try
				{
					File.saveBytes("clientUpdate/ClientUpdater.exe",updaterExe);
					Sys.command("start "+Sys.getCwd()+"clientUpdate/ClientUpdater.exe");
					
					// File.saveContent("clientUpdate/update.bat",script);
					// Sys.command("start "+Sys.getCwd()+"clientUpdate/update.bat");
					Sys.exit(0);
				}
				catch(err:Dynamic)
				{
					if (KontentumClient.debug)
						trace('Failed to update client.');
				}
			}, 
			(l:Loader)-> //onError
			{
				if (KontentumClient.debug)
					trace('Unable to download client update: $fileURL');
			}
		);
	}

	static function checkOldUpdate()
	{
		if (FileSystem.exists("clientUpdate"))
		{
			try 
			{
				if (FileSystem.exists("clientUpdate\\KontentumClient.exe"))
					FileSystem.deleteFile("clientUpdate\\KontentumClient.exe");
				if (FileSystem.exists("clientUpdate\\update.bat"))
					FileSystem.deleteFile("clientUpdate\\update.bat");
				FileSystem.deleteDirectory("clientUpdate");
			}
			catch(e:Dynamic)
			{
				if (KontentumClient.debug)
					trace('Filed to delete update files...');
			}
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function printLogo()
	{
		var date = DateUtils.getFormattedDate(buildDate);

		Sys.println('__________________________________________________');
		Sys.println('                                                  ');
		Sys.println('    @@                            @@              ');
		Sys.println('    @@                                            ');
		Sys.println('    @@    @@@@@@@@@@@@@@@@@@@@@@@@@@  @@@@@@@@    ');
		Sys.println('    @@    @@      @@  @@          @@  @@          ');
		Sys.println('    @@    @@      @@  @@      @@  @@  @@          ');
		Sys.println('    @@            @@  @@      @@  @@  @@          ');
		Sys.println('    @@@@@@@@@@@@@@@@  @@@@@@  @@  @@  @@@@@@@     ');
		Sys.println('                              @@                  ');
		Sys.println('                              @@                  ');
		Sys.println('                      @@@@@@@@@@                  ');
		Sys.println('                                                  ');
	    Sys.println('    I   N   T   E   R   A   C   T   I   V   E     ');
		Sys.println('                                                  ');
		Sys.print  ('    Build : $date \n');
		Sys.println('__________________________________________________');
		Sys.println('                                                  ');
		
	}

	static function createTray()
	{
		var startedAt = haxe.Timer.stamp();
		// Optional: path to a .ico. If empty, it uses a default icon.
		var exeDir = haxe.io.Path.directory(Sys.programPath());
		// var iconPath = "";//exeDir + "/client.ico"; // or "" to use default
		var iconPath = exeDir + "/kontentum.ico"; // or "" to use default

		utils.Tray.init("Kontentum Client");
		utils.Tray.useEmbeddedIcon();

		// Pass watchdog ping event to tray so it keeps watchdog alive during blocking TrackPopupMenu
		var pingHandle = utils.WatchDog.getPingEventHandle();
		if (pingHandle != 0)
			utils.Tray.setWatchdogPingEvent(pingHandle);

		// Pump tray messages + poll commands + process deferred tasks
		trayTimer = new haxe.Timer(150);
		trayTimer.run = function ()
		{
			// Wrap entire timer callback to prevent unhandled exceptions from killing the timer
			try
			{
				utils.Tray.pump();

				// Process any subprocess monitoring that was deferred from background threads
				utils.SubProcess.processPendingMonitorSetup();

				var secs = Std.int(haxe.Timer.stamp() - startedAt);
				// Handle negative time (clock drift, system time change)
				if (secs < 0) secs = 0;
				var h = Std.int(secs / 3600);
				var m = Std.int((secs % 3600) / 60);
				var s = secs % 60;
				utils.Tray.setStatus('Uptime: ' + StringTools.lpad('$h', "0", 2) + ":" +
									StringTools.lpad('$m', "0", 2) + ":" +
									StringTools.lpad('$s', "0", 2));

				switch (utils.Tray.pollCommand())
				{
					case utils.Tray.CMD_SHOW_LOGS:
					{
						// Open the log file in default text editor
						#if windows
						var logPath = utils.Log.path();
						// Use start command to open with default editor
						Sys.command('cmd', ['/c', 'start', '', logPath]);
						#end
					}
					case utils.Tray.CMD_RESTART:
					{
						// Restart the KontentumClient application
						#if windows
						utils.WatchDog.stop();
						Mutex.release();
						var exe = Sys.programPath();
						// Launch new instance and exit this one
						// Use start with empty title and path without extra quotes
						Sys.command('cmd', ['/c', 'start', '', exe]);
						Sys.exit(0);
						#end
					}
					case utils.Tray.CMD_QUIT:
					{
						// Clean up and exit
						try utils.Tray.destroy() catch (_:Dynamic) {}
						#if windows
						utils.WatchDog.stop();
						Mutex.release();
						#end
						Sys.exit(0);
					}
					case utils.Tray.CMD_TEST_CRASH:
					{
						// DEBUG: Trigger a native crash (ACCESS_VIOLATION) to verify VEH handler
						utils.Log.write("[DEBUG] Test native crash triggered from tray menu");
						utils.CrashHandler.testAccessViolation();
					}
					case utils.Tray.CMD_TEST_HAXE_EX:
					{
						// DEBUG: Trigger a Haxe exception to verify exception handler
						utils.Log.write("[DEBUG] Test Haxe exception triggered from tray menu");
						utils.CrashHandler.testHaxeException();
					}
					case 0:
				}
			}
			catch (e:Dynamic)
			{
				// Handle exception: log, submit crash event to server, and restart
				utils.CrashHandler.handleException("[TrayTimer] Unhandled exception", e);
			}
		};

	}

	/////////////////////////////////////////////////////////////////////////////////////
}

typedef ConfigXML =
{
	var kontentum			: KontentumConfig;
	var killexplorer		: Null<Bool>;
	var debug				: Null<Bool>;
	var watchdog			: Null<Bool>;			// Enable/disable watchdog (null = enabled by default)
	var disableStartupInstall: Null<Bool>;		// Disable startup installation prompt (for shell:startup scenarios)
	// var restartAutomatic	: Bool;
	var overridelaunch		: String;
	var chrome				: String;
}

typedef KontentumConfig =
{
	var ip					: String;
	var api					: String;
	var clientID			: Int;
	var exhibitToken		: String;
	var interval			: Float;
	var delay				: Float;
	var restartdelay		: Float;
	var download			: Null<Bool>;
	var downloadAllFiles	: Null<Bool>;
	var localFiles			: String;
	var hosted				: HostedFileSyncConfig;
	var fallback			: String;
	var fallbackdelay		: Float;
	var appMonitor			: Null<Bool>;			// Enable subprocess monitoring
	var maxCrashesPerMinute	: Null<Int>;			// Max restarts per minute before rate limiting
	var maxTotalRestarts	: Null<Int>;			// Absolute max restarts before disabling (prevents server flooding)
}

typedef HostedFileSyncConfig =
{
	var api					: String;
	var folder				: String;
	var localpath			: String;
}
