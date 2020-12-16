package;

import client.ServerCommunicator;
import haxe.macro.Expr.Catch;
import hxbitmini.CompileTime;
import no.logic.fox.hwintegration.windows.Chrome;
import no.logic.fox.kontentum.Kontentum;
import no.logic.fox.loader.Loader;
import no.logic.fox.utils.DateUtils;
import no.logic.fox.utils.ObjUtils;
import sys.FileSystem;
import sys.io.File;
import utils.WindowsUtils;

/**
 * ...
 * @author Tommy S.
 */

@:cppFileCode('
#include <iostream>
#include <windows.h>
')
class KontentumClient 
{
	/////////////////////////////////////////////////////////////////////////////////////

	static var i						: KontentumClient;
	static public var config			: ConfigXML;
	static public var buildDate			: Date				= CompileTime.buildDate();
	static public var ready				: Bool				= false;
	static public var debug				: Bool				= false;
	static public var downloadFiles		: Bool				= false;
	static public var killExplorer		: Bool				= false;

	var waitDelay						: Float				= 0.0;
	static var firstCommand				: String;
	static var chrome					: Chrome;

	static public var offlineLaunchFile	: String			= "c:/temp/kontentum_offlinelaunch";

	/////////////////////////////////////////////////////////////////////////////////////
	
	static public function main() 
	{
		if (i==null)
			i = new KontentumClient();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	public function new()
	{
		WindowsUtils.setConsoleTitle("Kontentum Client  |  Logic Interactive");
		printLogo();

		// utils.TrayUtils.createTrayIcon("KontentumClient  |  Logic Interactive");
		
		// WindowsUtils.takeScreenshot();
		// return;

		Loader.LoadXML("config.xml",null,onLoadXMLComplete,onLoadXMLFailed);
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
		ServerCommunicator.init();
		if (config.kontentum.download!=null)
		{
			KontentumClient.downloadFiles = config.kontentum.download;
			if (KontentumClient.downloadFiles)
				startFileDownload();
		}
		else 
			KontentumClient.ready = true;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	inline function initSettings()
	{
		debug = config.debug;
		config.kontentum.interval = 1.0;
		
 		if (config.kontentum==null || config.kontentum.ip == null || config.kontentum.api == null || config.kontentum.clientID == 0)
		{
			if (debug)
				trace("Malformed config xml! Exiting.",true);
				
			KontentumClient.exitWithError();
		}

		if (config.kontentum.exhibitToken==null)
			config.kontentum.exhibitToken = "_";

		if (!config.debug && !config.kontentum.download)
			WindowsUtils.freeConsole();

		if (config.killexplorer!=null)
			KontentumClient.killExplorer = config.killexplorer;

		if (KontentumClient.killExplorer)
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
				case SystemCommand.sleep:		WindowsUtils.systemSleep(false,false);
			}
		}
		else
			firstCommand = cmd;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function exit()
	{
		// utils.TrayUtils.removeTrayIcon();
		Sys.exit(0);		
	}

	static public function exitWithError()
	{
		// utils.TrayUtils.removeTrayIcon();
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
			chrome = Chrome.launch(url,config.chrome);
		else
			chrome.open(url);
	}

	static public function cacheLaunchFile(file:String)
	{
		if (file==null || file=="")
			return;
		try 
		{
			File.saveContent(offlineLaunchFile,file);
		}
		catch(e:Dynamic)
		{
			if (debug)
				trace("Failed to save offline launch file");
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	function startFileDownload()
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

		Kontentum.connect(config.kontentum.exhibitToken,null,localFileCache,true,false,false,true);
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
		WindowsUtils.freeConsole();		
	}
	
	/////////////////////////////////////////////////////////////////////////////////////

	static function printLogo()
	{
		Sys.println('__________________________________________________');
		Sys.println('                                                  ');
		Sys.println('    ##                            ##              ');
		Sys.println('    ##                                            ');
		Sys.println('    ##    ##########################  ########    ');
		Sys.println('    ##    ##      ##  ##          ##  ##          ');
		Sys.println('    ##    ##      ##  ##      ##  ##  ##          ');
		Sys.println('    ##            ##  ##      ##  ##  ##          ');
		Sys.println('    ################  ######  ##  ##  ######      ');
		Sys.println('                              ##                  ');
		Sys.println('                              ##                  ');
		Sys.println('                      ##########                  ');
		Sys.println('                                                  ');
	    Sys.println('    I   N   T   E   R   A   C   T   I   V   E     ');
		Sys.println('__________________________________________________');
		Sys.println('                                                  ');
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
}
