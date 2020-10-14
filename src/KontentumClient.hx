package;

import client.Network;
import haxe.macro.Expr.Catch;
import hxbitmini.CompileTime;
import no.logic.fox.hwintegration.windows.Chrome;
import no.logic.fox.loader.Loader;
import no.logic.fox.utils.ObjUtils;
import utils.WindowsUtils;

/**
 * ...
 * @author Tommy S.
 */

class KontentumClient 
{
	/////////////////////////////////////////////////////////////////////////////////////

	static var i					: KontentumClient;
	static public var config		: ConfigXML;
	static public var buildDate		: Date				= CompileTime.buildDate();

	var waitDelay					: Float				= 0.0;
	static var firstCommand			: String;
	static var chrome				: Chrome;

	/////////////////////////////////////////////////////////////////////////////////////
	
	static public function main() 
	{
		if (i==null)
			i = new KontentumClient();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	public function new()
	{
		Loader.LoadXML("config.xml",null,onLoadXMLComplete,onLoadXMLFailed);
	}

	/////////////////////////////////////////////////////////////////////////////////////

	function onLoadXMLFailed(l:Loader)
	{
		debug("Config XML failed to load! ("+l.source+")");
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
			debug("Error : Failed to process XML:",true);
			debug(l.contentRAW,true);
		}

		initSettings();
		Network.init();
	}

	/////////////////////////////////////////////////////////////////////////////////////

	inline function initSettings()
	{
 		if (config.kontentum==null || config.kontentum.ip == null || config.kontentum.api == null || config.kontentum.clientID == 0)
		{
			trace("Malformed config xml! Exiting.",true);
			KontentumClient.exitWithError();
		}

		if (config.kontentum.token==null)
			config.kontentum.token = "_";

		if (!config.debug)
			WindowsUtils.freeConsole();

		if (config.killexplorer)
			WindowsUtils.killExplorer();

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
			Sys.sleep(config.kontentum.delay);	 

	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function parseCommand(cmd:SystemCommand) 
	{
		if (firstCommand != null)
		{
			switch (cmd) 
			{
				case SystemCommand.reboot:		WindowsUtils.systemReboot();
				case SystemCommand.shutdown:	WindowsUtils.systemShutdown();
				case SystemCommand.restart:		WindowsUtils.handleRestart();
				case SystemCommand.quit:		WindowsUtils.handleQuit();

			}
		}
		else
			firstCommand = cmd;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function exit()
	{
		Sys.exit(0);		
	}

	static public function exitWithError()
	{
		Sys.exit(1);		
	}

	static public inline function debug(value:Dynamic,?force:Bool=false)
	{
		if (config==null || config.debug || force)
			trace(value);
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function launchChrome(url:String)
	{
		if (chrome==null)
			chrome = Chrome.launch(url,config.chrome);
		else
			chrome.open(url);
	}

	/////////////////////////////////////////////////////////////////////////////////////
}

typedef ConfigXML =
{
	var kontentum			: KontentumConfig;
	var killexplorer		: Bool;
	var debug				: Bool;
	var restartAutomatic	: Bool;
	var appMonitor			: Bool;
	var overridelaunch		: String;
	var chrome				: String;
}

typedef KontentumConfig =
{
	var ip					: String;
	var api					: String;
	var clientID			: Int;
	var exhibitToken		: String;
	var token				: String;
	var interval			: Float;
	var delay				: Float;
	var restartdelay		: Float;
}
