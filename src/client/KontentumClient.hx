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
	
	var jsonPing				: Dynamic;
	var settings				: Dynamic;
	var timer					: Timer;
	var thread					: Thread;
	
	var token					: String;
	var restIP					: String;
	var restAPI					: String;
	var restID					: String;
	var restURL					: String;
	var restURLBase				: String;
	var restartAutomatic		: String;
	var ipIsSent				: Bool;
	var intervalTime			: Float			= 1.0;
	var delayTime				: Float			= 0.0;
	var firstCommand			: String;
	var launch					: String;
	var localIP					: String;
	var localMAC				: String;

	var http					: Http;
	var restStr					: String;
	var waitForResponse			: Bool;
	var pingTimer				: Timer;
	
	var httpRequest				: HttpRequest;
	
	//===================================================================================
	// ClientFunctions 
	//-----------------------------------------------------------------------------------
	
	public function new(configXml:String) 
	{
		init(configXml);
		startClient();
	}
	
	//===================================================================================
	// Setup
	//-----------------------------------------------------------------------------------

	function init(configXml:String)
	{
		CrashHandler.setCPPExceptionHandler(onCrash, false);
		
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
		
		settings = ClientUtils.fromXML(Xml.parse(configFile));
		
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
			ClientUtils.KillExplorer();
		
		if (delayTime > 0)
			Sys.sleep(delayTime);
			
	}
	
	//===================================================================================
	// Client Loop
	//-----------------------------------------------------------------------------------

	function startClient() 
	{
		//FORCE CRASH!!!!!
/*		untyped __cpp__('
			*((unsigned int*)0) = 0xDEAD;
		');*/
		
		var adapter = ClientUtils.getNetworkAdapterInfo( ClientUtils.ADAPTER_TYPE_ANY );
		if (adapter.ip == "0.0.0.0")
		{
			trace("Network adapter not found!");
			Timer.delay(startClient, 5000);
		}
		else
		{
			restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname);
			//thread = Thread.create(pingThread);
			//thread.sendMessage(Thread.current());
			
/*			http = new Http(restURL);
			http.onData = onPingData;
			http.onError = onPingError;
			http.cnxTimeout = 30.0;		*/	

			httpRequest = new HttpRequest( { url:restURL, callback:onHttpResponse });
			
			createTimer();
			
			//while (true)
			//{
				//Sys.sleep(1);
			//}
		}
	}
	
	function createTimer() 
	{
		if (pingTimer != null)
			pingTimer.stop();
			
		pingTimer = new Timer(Std.int(intervalTime*1000));
		pingTimer.run = pingCallback;		
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
	
	function pingCallback() 
	{
		if (!waitForResponse)
			makeRequest();
	}

	function makeRequest() 
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
			//http.request(false);
			httpRequest = httpRequest.clone();
			httpRequest.timeout = 30;
			httpRequest.send();
		}
		catch (e:Error)
		{
			trace("Error...");
		}
	}
	
	function requestComplete()
	{
		//Sys.sleep(intervalTime);
		//makeRequest();
		waitForResponse = false;
	}
	
	 function onHttpResponse(response:HttpResponse)
	{
		if (response.isOK)
		{
			if (response.content != null)
				onPingData(response);
			else
				onPingCorruptData(response);
		}
		else
			onPingError(response);
			
	}  
			
	function onPingData(response:HttpResponse) 
	{
		restStr = response.toText();
		if (restStr != null && restStr != "" && restStr.indexOf('{"success":true')!=-1 )
		{
			if (settings.config.debug=="true")
				trace("Response - got data: " + restStr);
				
			jsonPing = response.toJson();
			var success = jsonPing.success;
			if (success == "true")
			{
				var command = jsonPing.callback;
				parseCommand(command);
				
				if (launch == null)
				{
					if (jsonPing.launch!=null && jsonPing.launch!="")
						launch = jsonPing.launch;
						
					ClientUtils.runProcess(launch);
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
			checkAttributes();
			requestComplete();
		}
		else
			onPingCorruptData(response);			
	}
	
	function checkAttributes() 
	{
		if (jsonPing != null)
		{
			if (Reflect.hasField(jsonPing,"ping"))
			{
				if (jsonPing.ping != intervalTime)
				{
					if (settings.config.debug=="true")
						trace("Changing ping time to : " + jsonPing.ping);
					
					intervalTime = jsonPing.ping;
					createTimer();
				}
			}
		}
	}

	function onPingError(response:HttpResponse) 
	{
		if (settings.config.debug=="true")
			trace("Response - error: "+ response.status + " " + response.error);
		// no valid data...
		
		Sys.sleep(10);
		requestComplete();
	}
	
	function onPingCorruptData(response:HttpResponse) 
	{
		if (settings.config.debug=="true")
			trace("Response - not valid response data: "+ response.status + " " + response.content);
		// no valid data...
		Sys.sleep(10);
		requestComplete();
	}

	function parseCommand(cmd:String) 
	{
		if (firstCommand != null)
		{
			switch (cmd) 
			{
				case "reboot":		ClientUtils.SystemReboot();
				case "shutdown":	ClientUtils.SystemShutdown();
			}
		}
		else
			firstCommand = cmd;
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
}

