package;

import cpp.Char;
import cpp.ConstCharStar;
import cpp.ConstPointer;
import cpp.Lib;
import cpp.NativeString;
import cpp.RawConstPointer;
import cpp.vm.Thread;
import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.io.Output;
import haxe.macro.Expr.Error;
import sys.io.File;

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
	static var ipIsSent			: Bool;
	static var intervalTime		: Float;
	static var firstCommand		: String;
	static var launch			: String;
	static var localIP			: String;
	static var localMAC			: String;

	//===================================================================================
	// Main 
	//-----------------------------------------------------------------------------------
	
	static function main() 
	{
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

		intervalTime = Std.parseFloat(settings.config.kontentum.intervalMS) * 0.001;
		
		token = settings.config.kontentum.token;
		restIP = settings.config.kontentum.ip;
		restAPI = settings.config.kontentum.api;
		restID = settings.config.kontentum.exhibitID;
		
		if (token == null)
			token = "_";
		
		restURLBase = restIP + "/" + restAPI +"/" + restID + "/" + token;

		var adapter = getNetworkAdapterInfo( ADAPTER_TYPE_ANY );
		restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname);
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
			if (settings.config.debug=="true")
				trace(restURL);
				
			var restStr = Http.requestUrl(restURL);
			if (restStr != null && restStr != "")
			{
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

