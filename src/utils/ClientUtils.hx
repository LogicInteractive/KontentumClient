package utils;

import utils.SubProcess;
import cpp.Char;
import cpp.ConstCharStar;
import cpp.ConstPointer;
import cpp.Lib;
import cpp.NativeString;
import cpp.RawConstPointer;
import haxe.CallStack;
import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.io.Output;
import haxe.macro.Expr.Error;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;

import com.akifox.asynchttp.*;

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
#include <string.h>
#include <Windows.h>
#include <Iphlpapi.h>
#pragma comment(lib, "iphlpapi.lib")

')
class ClientUtils 
{
	static public inline var ADAPTER_TYPE_ANY			: Int		= 0;
	static public inline var ADAPTER_TYPE_ETHERNET		: Int		= 6;
	static public inline var ADAPTER_TYPE_WIFI			: Int		= 71;
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static var settings				: Dynamic;
	static var subProcess			: SubProcess;
	
	static var firstCommand			: String;
	static var explorerKilled		: Bool;
	
	/////////////////////////////////////////////////////////////////////////////////////

	//===================================================================================
	// Load settings 
	//-----------------------------------------------------------------------------------

	static public function loadSettings(configXml:String):Dynamic
	{
		var configFile = "";
		try
		{
			configFile = File.getContent(configXml);
		}
		catch (e:Error)
		{
			debug("Config file not found");
			Sys.exit(1);
		}
		
		settings = ClientUtils.fromXML(Xml.parse(configFile));
		return settings;
	}
	
	//===================================================================================
	// SystemFunctions 
	//-----------------------------------------------------------------------------------
	
	static public function SystemReboot() 
	{
		if (subProcess!=null)
			subProcess.forceQuitNoRestart();
			
		//#if win
		//trace("REBOOT");
		Sys.command("shutdown", ["/r", "/f", "/t", "0"]);
		//#elseif mac
		
		//#end
	}
	
	static public function SystemShutdown() 
	{
		if (subProcess!=null)
			subProcess.forceQuitNoRestart();

		//#if win
		//trace("SHUTDOWN");
		Sys.command("shutdown",["/s","/f","/t","0"]);
		//#elseif mac
		//
		//#end
	}
	
	static public function KillExplorer() 
	{
		explorerKilled = true;
		Sys.command("taskkill",["/F","/IM","explorer.exe"]);
	}
	
	static public function launchExplorer() 
	{
		if (explorerKilled)
		{
			Sys.command("explorer.exe");
			explorerKilled = false;
		}
	}
	
	static public function freeConsole()
	{
		untyped __cpp__('FreeConsole();');
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
	
	static public function setPersistentProcess(exeName:String)
	{
		if (subProcess != null)
			subProcess.terminate();
			
		if (Reflect.field(settings.config, "overridelaunch") != null)
			exeName = settings.config.overridelaunch;
			
		subProcess = new SubProcess(exeName);
		subProcess.launchDelay = 0;
		subProcess.monitor = true;
		subProcess.restartDelay = Std.parseFloat(settings.config.kontentum.restartdelay);
		subProcess.subprocessDidCrash = subprocessDidCrash;
		subProcess.subprocessDidExit = subprocessDidExit;
		var success = subProcess.run();
		
		if (!success)
			debug("process failed to start....");
	}	
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static function subprocessDidCrash() 
	{
		ClientUtils.debug("Subprocess crashes. Restarting.");
		NetworkHandler.i.submitAction("APP_CRASH");
	}
	
	static function subprocessDidExit() 
	{
		ClientUtils.debug("Subprocess exited. Restarting.");
		//NetworkHandler.i.submitAction("APP_EXIT");
	}	
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static function handleRestart() 
	{
		if (subProcess != null)
			subProcess.restart();
	}	

	static function handleQuit() 
	{
		if (subProcess != null)
		{
			subProcess.forceQuitNoRestart();
		}
		launchExplorer();
	}	


	/////////////////////////////////////////////////////////////////////////////////////
	//===================================================================================
	// Utils
	//-----------------------------------------------------------------------------------
	
	//old
	static public function runProcess(exeName:String, hidden:Bool=false)
	{
		if (!hidden)
			untyped __cpp__('WinExec(exeName, SW_SHOW)');
		else
			untyped __cpp__('WinExec(exeName, SW_HIDE)');
	}
		
	static public function getNetworkAdapterInfo(adaptertype:Int):NetworkAdapterInfo
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
	
	function startCrashHandler()
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
				debug("Could not write to log!");
				debug(stackDump);
			}
		}
		
		if (settings.config.debug=="true")
			debug("Exception occured. Restarting client");
		
		if (settings.config.restartAutomatic == "false")
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
	
	static public function debug(str:String)
	{
		if (settings.config.debug == true)
			trace(str);
	}
	
	static public function parseCommand(cmd:String) 
	{
		if (firstCommand != null)
		{
			switch (cmd) 
			{
				case "reboot":		SystemReboot();
				case "shutdown":	SystemShutdown();
				case "restart":		handleRestart();
				case "quit":		handleQuit();
			}
		}
		else
			firstCommand = cmd;
	}
		
	/////////////////////////////////////////////////////////////////////////////////////
	
}

