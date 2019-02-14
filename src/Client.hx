package;

import utils.ClientUtils;
import utils.CrashHandler;
import utils.NetworkHandler;

/**
 * ...
 * @author Tommy S.
 */

//@:cppFileCode('
//#include <Windows.h>
//')
class Client 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	static public var settings	: Dynamic;
	var restartAutomatic		: String;
	var delayTime				: Float			= 0.0;
	
	//===================================================================================
	// ClientFunctions 
	//-----------------------------------------------------------------------------------
	
	public function new(configXml:String) 
	{
		settings = ClientUtils.loadSettings(configXml);
		
		if (settings.config.debug!=true)
			ClientUtils.freeConsole();
			
		var networkHandler = new NetworkHandler();
		networkHandler.init(settings);
		
		if (settings.config.killexplorer == "true")
			ClientUtils.KillExplorer();
		
		var delayTime = Std.parseFloat(settings.config.kontentum.delay);
		var args = Sys.args();
		if (args != null && args.length > 1)
		{
			if (args[0] == "delay")
			{
				var dly:Float = Std.parseFloat(args[1]);
				if (dly > 0.0)
					delayTime = dly;
			}
		}
		
		restartAutomatic = settings.config.restartAutomatic;

		if (settings.config.killexplorer == "true")
			ClientUtils.KillExplorer();
		
		if (delayTime > 0)
			Sys.sleep(delayTime);
			
		networkHandler.intervalTime = settings.config.kontentum.interval;
		networkHandler.startNet();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	static public function subprocessDidCrash() 
	{
		ClientUtils.debug("Subprocess crashes. Restarting.");
	}
	
	static public function subprocessDidExit() 
	{
		ClientUtils.debug("Subprocess exited. Restarting.");
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

