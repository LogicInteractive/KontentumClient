package;

import cpp.Lib;
import cpp.vm.Thread;
import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.macro.Expr.Error;
import sys.io.File;

/**
 * ...
 * @author Tommy S.
 */
@:cppFileCode('#include <Windows.h>')
class Main 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	static var jsonPing			: Dynamic;
	static var settings			: Dynamic;
	static var timer			: Timer;
	static var thread			: Thread;
	
	static var restIP			: String;
	static var restAPI			: String;
	static var restID			: String;
	static var restURL			: String;
	static var intervalTime		: Float;
	static var firstCommand		: String;
	static var launch			: String;

	//===================================================================================
	// Main 
	//-----------------------------------------------------------------------------------
	
	static function main() 
	{
		untyped __cpp__('FreeConsole();');
		
		var configFile = "";
		try
		{
			configFile = File.getContent("config.xml");
		}
		catch (e:Error)
		{
			trace("Config file not found");
			Sys.exit(1);
		}
		
		settings = fromXML(Xml.parse(configFile));

		intervalTime = Std.parseFloat(settings.config.kontentum.intervalMS) * 0.001;
		
		restIP = settings.config.kontentum.ip;
		restAPI = settings.config.kontentum.api;
		restID = settings.config.kontentum.exhibitID;
		restURL = restIP + "/" + restAPI +"/" + restID;

		thread = Thread.create(pingThread);
		thread.sendMessage(Thread.current());
		
		if (settings.config.killexplorer == "true")
			KillExplorer();
		
		while (true)
		{
			Sys.sleep(10);
		}
	}
	
	static function pingThread() 
	{
		while (true)
		{
			var restStr = Http.requestUrl(restURL);
			jsonPing = Json.parse(restStr);
			var success = jsonPing.success;
			if (success == "true")
			{
				var command = jsonPing.callback;
				parseCommand(command);
				
				if (launch == null)
				{
					if (jsonPing.launch!=null && jsonPing.launch!="")
						launch = jsonPing.launch;
						
					runProcess(launch);
				}
			}
			else
			{
				trace("Error: ClientID " + restID + " not found! ");
			}
			Sys.sleep(intervalTime);
		}
	}
	
	static function parseCommand(cmd:String) 
	{
		if (firstCommand != null)
		{
			switch (cmd) 
			{
				case "reboot":		SystemReboot();
				case "shutdown":	SystemShutdown();
			}
		}
		else
			firstCommand = cmd;
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function SystemReboot() 
	{
		//#if win
		//trace("REBOOT");
		Sys.command("shutdown", ["/r", "/f", "/t", "0"]);
		//#elseif mac
		
		//#end
	}
	
	static function SystemShutdown() 
	{
		//#if win
		//trace("SHUTDOWN");
		Sys.command("shutdown",["/s","/f","/t","0"]);
		//#elseif mac
		//
		//#end
	}
	
	static function KillExplorer() 
	{
		Sys.command("taskkill",["/F","/IM","explorer.exe"]);
	}
	
	static function launchExplorer() 
	{
		Sys.command("explorer.exe");
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
	//===================================================================================
	// Utils
	//-----------------------------------------------------------------------------------
	
	static function runProcess(exeName:String)
	{
		untyped __cpp__('WinExec(exeName, SW_SHOW)');
	}
		
	static function fromXML(xml:Xml):Dynamic
	{
		var o:Dynamic = {};
		if (xml != null)
		{
			iterateXMLNode(o, xml);
		}
		return o;
	}
	
	static function iterateXMLNode(o:Dynamic, xml:Xml) 
	{
		for ( node in xml.elements() )
		{
			if (node!=null)
			{	
				var nodeChildren = 0;
				for ( nc in node.elements() )
					nodeChildren++;
					
				if (nodeChildren>0)
				{
					Reflect.setField(o, node.nodeName, {});
					iterateXMLNode(Reflect.field(o, node.nodeName), node);
				}
				else
					Reflect.setField(o, node.nodeName, returnTyped(Std.string(node.firstChild())));
			}
		}		
	}
	
	static function returnTyped(d:String):Dynamic
	{
		if (d == null)
			return d;
			
		if (isStringBool(d))
			return toBool(d);
		else if (isStringInt(d))
			return Std.parseInt(d);
		else if (isStringInt(d))
			return Std.parseFloat(d);
		else
			return Std.string(d);
	}
	
	static function isStringBool(inp:String):Bool
	{
		if (inp == null)
			return false;
			
		inp.split(" ").join(""); // strip spaces
			
		if ((inp.toLowerCase() == "true") || (inp.toLowerCase() == "false"))
			return true;
		else
			return false;
	}	
		
	static function toBool( value:Dynamic ):Bool
	{
		var isBoolean:Bool = false;
		var strVal:String = Std.string(value);
		
		switch ( strVal.toLowerCase() )
		{
			case "1":
				isBoolean = true;
			case "true":
				isBoolean = true;
			case "yes":
				isBoolean = true;
			case "y":
				isBoolean = true;
			case "on":
				isBoolean = true;
			case "enabled":
				isBoolean = true;
		}

		return isBoolean;
	}
	
	static function isStringInt(inp:String):Bool
	{
		if (inp == null || inp.indexOf(".")!=-1)
			return false;
			
		inp.split(" ").join(""); // strip spaces
		for (i in 0...inp.length) 
		{
			if (!isfirstCharNumber(inp.substr(i, 1)))
				return false;
		}
		return true;
	}
	
	static function isfirstCharNumber(char:String):Bool
	{
		if (char==null || char.length<1)
			return false;
			
		var isNumber = false;
		var fc = char.substr(0, 1);
		switch (fc) 
		{
			case "0":
				isNumber = true;
			case "1":
				isNumber = true;
			case "2":
				isNumber = true;
			case "3":
				isNumber = true;
			case "4":
				isNumber = true;
			case "5":
				isNumber = true;
			case "6":
				isNumber = true;
			case "7":
				isNumber = true;
			case "8":
				isNumber = true;
			case "9":
				isNumber = true;
			default:
				isNumber = false;
		}
		
		return isNumber;
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

