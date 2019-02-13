package client;

import com.akifox.asynchttp.HttpRequest;
import com.akifox.asynchttp.HttpResponse;
import cpp.Char;
import cpp.ConstCharStar;
import cpp.ConstPointer;
import cpp.Lib;
import cpp.NativeString;
import cpp.RawConstPointer;
import cpp.vm.Thread;
import haxe.CallStack;
import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.io.Output;
import haxe.macro.Expr.Error;
import no.logic.nativelibs.windows.SystemUtils;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import system.ClientUtils;
import system.CrashHandler;

/**
 * ...
 * @author Tommy S.
 */

@:cppFileCode('
#include <Windows.h>
')
class KontentumClient 
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
		var appUtils = AppUtils();
		settings = appUtils.loadSettings(configXml);
		
		if (settings.config.debug!="true")
			untyped __cpp__('FreeConsole();');
			
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
			
		networkHandler.intervalTime = 
		networkHandler.startNet();
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

