package;

import fox.compile.CompileTime;
import fox.loader.Loader;
import fox.utils.DateUtils;
import fox.utils.ObjUtils;
import haxe.Exception;
import sys.FileSystem;
import utils.WindowsUtils;

#if windows
@:cppFileCode('
#include <iostream>
#include <windows.h>
')
#end
class Settings
{
	/////////////////////////////////////////////////////////////////////////////////////

	public static var debug				: Bool			= false;
	static public var config			: ConfigXML;
	static var onLoadedCallback			: Void->Void;

	/////////////////////////////////////////////////////////////////////////////////////

	static public function load(file:String,onLoaded:Void->Void)
	{
		Settings.onLoadedCallback = onLoaded;

		var pDir:String = "";
		#if linux
		var appDir = Sys.programPath();
		if (appDir.split("KontentumClient").length > 1)
		{
			var si:Int = appDir.lastIndexOf("KontentumClient");
			appDir = appDir.substring(0, si);
			pDir = appDir.split("\\").join("/");
		}
		#end
		Loader.LoadXML(pDir+file,null,onLoadXMLComplete,onLoadXMLFailed);
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function onLoadXMLFailed(l:Loader)
	{
		Sys.println("Config XML failed to load! ("+l.source+")");
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	static function onLoadXMLComplete(l:Loader)
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

		setup();

		if (Settings.onLoadedCallback!=null)
			Settings.onLoadedCallback();
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function setup()
	{
		#if windows
		WindowsUtils.setConsoleTitle("Kontentum Client  |  Logic Interactive");
		#end

		debug = config.debug;
		config.kontentum.interval = 1.0;
		
 		if (config.kontentum==null || config.kontentum.ip == null || config.kontentum.api == null || config.kontentum.clientID == 0)
		{
			if (debug)
				trace("Malformed config xml! Exiting.",true);
				
			Sys.exit(1);
		}

		if (config.kontentum.exhibitToken==null)
			config.kontentum.exhibitToken = "_";

		#if windows
		if (!config.debug && !config.kontentum.download)
			WindowsUtils.freeConsole();

		if (config.killexplorer)
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
			Sys.sleep(config.kontentum.delay);	 
		
	}

	/////////////////////////////////////////////////////////////////////////////////////

}

typedef ConfigXML =
{
	var kontentum			: KontentumConfig;
	var killexplorer		: Null<Bool>;
	var debug				: Null<Bool>;
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
	var localFiles			: String;
	var hosted				: HostedFileSyncConfig;
}

typedef HostedFileSyncConfig =
{
	var api					: String;
	var folder				: String;
	var localpath			: String;
}
