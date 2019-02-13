package client;
import haxe.CallStack;
import haxe.CallStack.StackItem;
import haxe.macro.Expr.Error;
import sys.io.File;
import sys.io.FileOutput;
import system.ClientUtils;
import system.CrashHandler;

/**
 * ...
 * @author Tommy S.
 */

class AppUtils 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	public function new() 
	{
	
	//===================================================================================
	// Setup
	//-----------------------------------------------------------------------------------

	function init()
	{
		CrashHandler.setCPPExceptionHandler(onCrash, false);
	}

	//===================================================================================
	// CrashHandler 
	//-----------------------------------------------------------------------------------
	
	function onCrash() 
	{
		var stack:Array<StackItem> = CallStack.callStack();
		if (stack != null)
		{
			stack.shift(); //Remove crash handler entry
			stack.shift(); //Remove crash handler entry
			stack.reverse(); //Top down
			
			var stackDump = "Exception! (" + Date.now().toString() + ")\n:::::::::::::::::::::::::::::::::::::::::::::::" + CallStack.toString(stack) + "\n";
			
			//if (!FileSystem.exists("log.txt"))
			try
			{
				var output:FileOutput = sys.io.File.append("log.txt", false);
				output.writeString(stackDump+"\n");
				output.close();
			}
			catch (e:Error)
			{
				trace("Could not write to log!");
				trace(stackDump);
			}
		}
		
		if (settings.config.debug=="true")
			trace("Exception occured. Restarting client");
		
		if (restartAutomatic == "false")
		{
		}
		else
		{
			Sys.sleep(10);
			ClientUtils.runProcess("KontentumClient.exe",true);
			Sys.exit(1);
		}
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	public function loadSettings(configXml:String):Dynamic
	{
		var configFile = "";
		try
		{
			configFile = File.getContent(configXml);
		}
		catch (e:Error)
		{
			trace("Config file not found");
			Sys.exit(1);
		}
		
		return ClientUtils.fromXML(Xml.parse(configFile));
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static public function debug(str:String)
	{
		if (KontentumClient.settings.config.debug == "true")
			trace(str);
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

