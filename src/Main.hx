package;

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
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;

/**
 * ...
 * @author Tommy S.
 */

typedef NetworkAdapterInfo =
{
	@:optional	var ip			: String;
	@:optional	var mac			: String;
	@:optional	var hostname	: String;
}
 
@:cppFileCode('
#include <winsock2.h>
#include <iostream>
#include <stdio.h>
#include <Windows.h>
#include <Iphlpapi.h>
#pragma comment(lib, "iphlpapi.lib")
')
class Main 
{
	static public inline var ADAPTER_TYPE_ANY			: Int		= 0;
	static public inline var ADAPTER_TYPE_ETHERNET		: Int		= 6;
	static public inline var ADAPTER_TYPE_WIFI			: Int		= 71;
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static var jsonPing			: Dynamic;
	static var settings			: Dynamic;
	static var timer			: Timer;
	static var thread			: Thread;
	
	static var token			: String;
	static var restIP			: String;
	static var restAPI			: String;
	static var restID			: String;
	static var restURL			: String;
	static var restURLBase		: String;
	static var restartAutomatic	: String;
	static var ipIsSent			: Bool;
	static var intervalTime		: Float			= 1.0;
	static var delayTime		: Float			= 0.0;
	static var firstCommand		: String;
	static var launch			: String;
	static var localIP			: String;
	static var localMAC			: String;

	static var http				: Http;
	static var restStr			: String;
	static var waitForResponse	: Bool;
	static var pingTimer		: Timer;

	//===================================================================================
	// Main 
	//-----------------------------------------------------------------------------------
	
	static function main() 
	{
		CrashHandler.setCPPExceptionHandler(onCrash, false);
		
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
		
		if (settings.config.debug!="true")
			untyped __cpp__('FreeConsole();');

		intervalTime = Std.parseFloat(settings.config.kontentum.interval);
		delayTime = Std.parseFloat(settings.config.kontentum.delay);
		
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
		
		token = settings.config.kontentum.token;
		restIP = settings.config.kontentum.ip;
		restAPI = settings.config.kontentum.api;
		restID = settings.config.kontentum.clientID;
		restartAutomatic = settings.config.restartAutomatic;
		
		if (token == null)
			token = "_";
		
		if (restIP == null || restAPI == null || restID == null)
		{
			trace("Malformed config xml! Exiting.");
			Sys.exit(1);			
		}
		
		restURLBase = restIP + "/" + restAPI +"/" + restID + "/" + token;

		if (settings.config.killexplorer == "true")
			KillExplorer();
		
		if (delayTime > 0)
			Sys.sleep(delayTime);
			
		initMain();
	}
	
	static function initMain() 
	{
		//FORCE CRASH!!!!!
/*		untyped __cpp__('
			*((unsigned int*)0) = 0xDEAD;
		');*/
		
		var adapter = getNetworkAdapterInfo( ADAPTER_TYPE_ANY );
		if (adapter.ip == "0.0.0.0")
		{
			trace("Network adapter not found!");
			Timer.delay(initMain, 5000);
		}
		else
		{
			restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname);
			//thread = Thread.create(pingThread);
			//thread.sendMessage(Thread.current());
			
			http = new Http(restURL);
			http.onData = onPingData;
			http.onError = onPingError;
			http.cnxTimeout = 30.0;			
			
			pingTimer = new Timer(Std.int(intervalTime*1000));
			pingTimer.run = pingCallback;
			//while (true)
			//{
				//Sys.sleep(10);
			//}
		}
	}
	
	//static function pingThread() 
	//{
		//http = new Http(restURL);
		//http.onData = onPingData;
		//http.onError = onPingError;
		//http.cnxTimeout = 30.0;
		//
		//makeRequest();
	//}
	
	static function pingCallback() 
	{
		if (!waitForResponse)
			makeRequest();
	}

	static function makeRequest() 
	{
		if (settings.config.debug == "true")
		{
			trace("");
			trace("Ping: " + restURL);
		}
		
		restStr = null;
		try
		{
			waitForResponse = true;
			http.request(false);
		}
		catch (e:Error)
		{
			trace("Error...");
		}
	}
	
	static function requestComplete()
	{
		//Sys.sleep(intervalTime);
		//makeRequest();
		waitForResponse = false;
	}
	
	static function onPingData(data:String) 
	{
		restStr = data;
		if (restStr != null && restStr != "" && restStr.indexOf('{"success":true')!=-1 )
		{
			if (settings.config.debug=="true")
				trace("Response - got data: " + data);
				
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
				if (!ipIsSent)
				{
					restURL = restURLBase;
					ipIsSent = true;
				}
			}
			else
			{
				trace("Error: ClientID " + restID + " not found! ");
			}
			requestComplete();
		}
		else
			onPingCorruptData(data);			
	}
	
	static function onPingError(error) 
	{
		if (settings.config.debug=="true")
			trace("Response - error: "+ error);
		// no valid data...
		
		Sys.sleep(10);
		requestComplete();
	}
	
	static function onPingCorruptData(data) 
	{
		if (settings.config.debug=="true")
			trace("Response - not valid response data: "+ data);
		// no valid data...
		Sys.sleep(10);
		requestComplete();
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
	
	static function onCrash() 
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
			runProcess("KontentumClient.exe",true);
			Sys.exit(1);
		}
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
	
/*	static function getSafe(path:String,type:Any):Any
	{
		if (path == null)
			return null;
			
		var pSplit:Array<String> = path.split(".");
		if (pSplit == null || pSplit.length == 0)
			retun null;
			
	}
*/	
	/////////////////////////////////////////////////////////////////////////////////////
	//===================================================================================
	// Utils
	//-----------------------------------------------------------------------------------
	
	static function runProcess(exeName:String, hidden:Bool=false)
	{
		if (!hidden)
			untyped __cpp__('WinExec(exeName, SW_SHOW)');
		else
			untyped __cpp__('WinExec(exeName, SW_HIDE)');
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
	
	static function getNetworkAdapterInfo(adaptertype:Int):NetworkAdapterInfo
	{
		var ip:ConstPointer<Char> = null;
		var mac:ConstPointer<Char> = null;
		
		untyped __cpp__('
		
			PIP_ADAPTER_INFO AdapterInfo;
			DWORD dwBufLen = sizeof(AdapterInfo);
			char* mac_addr = (char*)malloc(17);
			std::string ipstr;

			AdapterInfo = (IP_ADAPTER_INFO*) malloc(sizeof(IP_ADAPTER_INFO));
			
			if (AdapterInfo != NULL)
			{
				if (GetAdaptersInfo(AdapterInfo, & dwBufLen) == ERROR_BUFFER_OVERFLOW)
				{
					AdapterInfo = (IP_ADAPTER_INFO*) malloc(dwBufLen);
					if (AdapterInfo != NULL)
					{
						if (GetAdaptersInfo(AdapterInfo, & dwBufLen) == NO_ERROR)
						{
							PIP_ADAPTER_INFO pAdapterInfo = AdapterInfo;// Contains pointer to current adapter info
							do
							{
								//Prints mac-adress to a string..
								sprintf(mac_addr, "%02X:%02X:%02X:%02X:%02X:%02X", pAdapterInfo->Address[0], pAdapterInfo->Address[1], pAdapterInfo->Address[2], pAdapterInfo->Address[3], pAdapterInfo->Address[4], pAdapterInfo->Address[5]);
								//printf("Address: %s, mac: %s\\n", pAdapterInfo->IpAddressList.IpAddress.String, mac_addr);
								
								if (adaptertype == pAdapterInfo->Type || adaptertype == 0) // Is adapter type matching? 6 : Ethernet, 71 : Wifi
								{
									mac = mac_addr;
									ip = pAdapterInfo->IpAddressList.IpAddress.String;
									if ((int)ip[0] != 48) //Is first char in ip string "0" ? If not, break!
										break;
								}
								pAdapterInfo = pAdapterInfo->Next;        
							}
							while(pAdapterInfo);                        
						}
					}
				}
			}
			free(AdapterInfo);
		');
		
		return { ip:NativeString.fromPointer(ip), mac:NativeString.fromPointer(mac), hostname:Sys.getEnv("COMPUTERNAME") };
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

