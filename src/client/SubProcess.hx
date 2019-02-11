package client;
import haxe.Timer;
import no.logic.nativelibs.windows.SystemUtils;
import system.ClientUtils;

/**
 * ...
 * @author Tommy S.
 */

class SubProcess 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	public var currentProcessID					: UInt			= 0;
	public var launchPath						: String;
	public var args								: String		= "";
	public var workingDirectory					: String		= "";
	public var waitForProcessToFinish			: Bool			= false;
	public var isAlive							: Bool			= false;
	
	public var relaunchIfCrash					: Bool			= true;
	public var lifeSpan							: Float			= -1;
	public var monitor							: Bool			= true;
	public var lifePingTime						: Int			= 200;		// ms for how often to check if subprocess is alive

	/////////////////////////////////////////////////////////////////////////////////////

	var deathTimer								: Timer;
	var lifePingTimer							: Timer;

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
	
	public function terminate():Bool
	{
		if (currentProcessID == 0) // No process running
			return false;
			
		if (deathTimer != null)
			deathTimer.stop();
			
		return SystemUtils.killProcess(currentProcessID);
	}
	
	function onLifePingTrigger()
	{
		isAlive = false;
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
			doRst();
		}
		else if (status==1) // EXIT_FAILURE
		{
			doRst();
		}
		else // HM.....
		{
			doRst();
		}
	}
	
	function doRst() 
	{
		if (relaunchIfCrash)
		{
			terminate();
			run();
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

