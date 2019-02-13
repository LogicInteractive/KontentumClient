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
class NetworkHandler 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	var jsonPing				: Dynamic;
	var timer					: Timer;
	var thread					: Thread;
	
	var token					: String;
	var restIP					: String;
	var restAPI					: String;
	var restID					: String;
	var restURL					: String;
	var restURLBase				: String;
	var ipIsSent				: Bool;
	public var intervalTime			: Float			= 1.0;
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
	
	public function new() 
	{
	}
	
	//===================================================================================
	// Init
	//-----------------------------------------------------------------------------------

	public function init(settings:Dynamic) 
	{
		intervalTime = Std.parseFloat(settings.config.kontentum.interval);
		
		token = settings.config.kontentum.token;
		restIP = settings.config.kontentum.ip;
		restAPI = settings.config.kontentum.api;
		restID = settings.config.kontentum.clientID;
		
		if (token == null)
			token = "_";
		
		if (restIP == null || restAPI == null || restID == null)
		{
			trace("Malformed config xml! Exiting.");
			Sys.exit(1);			
		}
		
		restURLBase = restIP + "/" + restAPI +"/" + restID + "/" + token;
	}
	
	public function startNet()
	{
		var adapter = ClientUtils.getNetworkAdapterInfo( ClientUtils.ADAPTER_TYPE_ANY );
		if (adapter.ip == "0.0.0.0")
		{
			trace("Network adapter not found!");
			Timer.delay(startNet, 5000);
		}
		else
		{
			restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname);
			httpRequest = new HttpRequest( { url:restURL, callback:onHttpResponse });
			
			createTimer();
		}
	}
	
	function createTimer() 
	{
		if (pingTimer != null)
			pingTimer.stop();
			
		pingTimer = new Timer(Std.int(intervalTime*1000));
		pingTimer.run = pingCallback;		
	}
	
	function pingCallback() 
	{
		if (!waitForResponse)
			makeRequest();
	}

	function makeRequest() 
	{
		AppUtils.d
		
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
			if (jsonPing == null)
			{
				onPingCorruptData(response);	
				return;
			}
			
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

	/////////////////////////////////////////////////////////////////////////////////////
}

