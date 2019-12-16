package utils;

import haxe.Timer;
import no.logic.nativelibs.windows.SystemUtils;
import utils.ClientUtils;

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
	public var monitor							: Bool			= true;
	public var waitForStart						: Bool			= false;
	public var lifePingTime						: Int			= 200;		// ms for how often to check if subprocess is alive

	/////////////////////////////////////////////////////////////////////////////////////

	var deathTimer								: Timer;
	var lifePingTimer							: Timer;
	var launchDelayTimer						: Timer;
	
	public var subprocessDidCrash				: Void->Void;
	public var subprocessDidExit				: Void->Void;

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
		waitForStart = false;
		currentProcessID = SystemUtils.createProcess(launchPath);	
		if (currentProcessID == 0)
			return false;
		
		if (lifeSpan > 0)
			setDeathDelay(lifeSpan);
			
		if (monitor)
		{
			if (lifePingTimer != null)
				lifePingTimer.stop();
				
			lifePingTimer = new Timer(lifePingTime);			
			lifePingTimer.run = onLifePingTrigger;
		}
		return true;
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	public function terminate():Bool
	{
		if (currentProcessID == 0) // No process running
			return false;
			
		if (deathTimer != null)
			deathTimer.stop();
			
		return SystemUtils.killProcess(currentProcessID);
	}
	
	public function restart()
	{
/*		launchDelay = restartDelay;
		terminate();
		run();*/
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
		isAlive = false;
		if (!waitForStart)
		{
			var status = checkAliveStatus();
			
			if (status == -1) //  NO_PROCESS_STARTED
			{
			}
			if (status == 259) // STILL_ACTIVE
			{
				isAlive = true;
			}
			else if (status==0) // EXIT_SUCCESS
			{
				if (subprocessDidExit != null)
					subprocessDidExit();
				handleExit();
			}
/*			else if (status==1) // EXIT_FAILURE
			{
				if (subprocessDidCrash != null)
					subprocessDidCrash();
				handleCrash();
			}
			else // HM.....
			{
				if (subprocessDidCrash != null)
					subprocessDidCrash();
			}*/
		}
	}
	
	public function checkAliveStatus():Int
	{
		if (currentProcessID > 0)
			return SystemUtils.checkProcessInfo(currentProcessID);
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
}
