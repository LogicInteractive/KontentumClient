package;

import client.ServerCommunicator;
import haxe.Resource;
import haxe.io.Bytes;
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

#if windows
@:cppFileCode('
#include <iostream>
#include <windows.h>
')
#end
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
		#end
		Loader.LoadXML(pDir+"config.xml",null,onLoadXMLComplete,onLoadXMLFailed);
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
		if (config.kontentum.download==true)
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

		#if windows
		if (!config.debug && !config.kontentum.download)
			WindowsUtils.freeConsole();

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
			Sys.sleep(config.kontentum.delay);	 

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
		#if windows
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
		Sys.println('                                                  ');
		Sys.print  ('    Build : $date \n');
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
