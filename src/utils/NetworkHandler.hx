package utils;

import com.akifox.asynchttp.HttpRequest;
import com.akifox.asynchttp.HttpResponse;
import com.akifox.asynchttp.URL;
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
import no.logic.nativelibs.windows.SystemUtils;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import utils.ClientUtils;
import utils.CrashHandler;
import utils.NetworkHandler;

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
	
	static public var i			: NetworkHandler;
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	var jsonPing				: Dynamic;
	var timer					: Timer;
	
	var token					: String;
	var restIP					: String;
	var restAPI					: String;
	var restID					: String;
	var restToken				: String;
	var restURL					: String;
	var restURLBase				: String;
	var ipIsSent				: Bool;
	var firstCommand			: String;
	var launch					: String;
	var localIP					: String;
	var localMAC				: String;

	var http					: Http;
	var restStr					: String;
	var waitForResponse			: Bool;
	var pingTimer				: Timer;
	
	var submitActionHttpReq		: HttpRequest;
	var httpRequest				: HttpRequest;
	
	public var intervalTime		: Float				= 1.0;
	
	var settings				: Dynamic;
	
	//===================================================================================
	// ClientFunctions 
	//-----------------------------------------------------------------------------------
	
	public function new() 
	{
		i = this;
	}
	
	//===================================================================================
	// Init
	//-----------------------------------------------------------------------------------

	public function init(settings:Dynamic) 
	{
		this.settings = settings;
		intervalTime = Std.parseFloat(settings.config.kontentum.interval);
		
		token = settings.config.kontentum.token;
		restIP = settings.config.kontentum.ip;
		restAPI = settings.config.kontentum.api;
		restID = settings.config.kontentum.clientID;
		restToken = settings.config.kontentum.clientToken;
		
		if (token == null)
			token = "_";
		
		if (restIP == null || restAPI == null || restID == null)
		{
			ClientUtils.debug("Malformed config xml! Exiting.");
			Sys.exit(1);			
		}
		
		restURLBase = restIP + "/" + restAPI +"/" + restID + "/" + token;
		
		submitActionHttpReq = new HttpRequest( { url:restIP, callback:onSubmitActionHttpResponse });		
	}
	
	public function startNet()
	{
		var adapter = ClientUtils.getNetworkAdapterInfo( ClientUtils.ADAPTER_TYPE_ANY );
		if (adapter.ip == "0.0.0.0")
		{
			ClientUtils.debug("Network adapter not found!");
			Timer.delay(startNet, 5000);
		}
		else
		{
			restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname);
			httpRequest = new HttpRequest( { url:restURL, callback:onHttpResponse });
			
			ClientUtils.debug("REST: "+ restURL);
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
			ClientUtils.debug("Request error..");
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
			if (settings.config.debug == "true")
				ClientUtils.debug("Response : " + restStr);
				
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
				ClientUtils.parseCommand(command);
				
				if (launch == null)
				{
					if (jsonPing.launch!=null && jsonPing.launch!="")
						launch = jsonPing.launch;
						
					ClientUtils.setPersistentProcess(launch);
				}
				if (!ipIsSent)
				{
					restURL = restURLBase;
					ipIsSent = true;
				}
			}
			else
			{
				ClientUtils.debug("Error: ClientID " + restID + " not found! ");
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
						ClientUtils.debug("Changing ping time to : " + jsonPing.ping);
					
					intervalTime = jsonPing.ping;
					createTimer();
				}
			}
		}
	}

	function onPingError(response:HttpResponse) 
	{
		if (settings.config.debug=="true")
			ClientUtils.debug("Response - error: "+ response.status + " " + response.error);
		// no valid data...
		
		Sys.sleep(10);
		requestComplete();
	}
	
	function onPingCorruptData(response:HttpResponse) 
	{
		if (settings.config.debug=="true")
			ClientUtils.debug("Response - not valid response data: "+ response.status + " " + response.content);
		// no valid data...
		Sys.sleep(10);
		requestComplete();
	}

	/////////////////////////////////////////////////////////////////////////////////////
	
	public function submitAction(action:String)
	{
		var submitURL:URL = new URL(restIP +'/rest/submitAction/' + restToken + '/' + StringTools.urlEncode(action) + '/' + StringTools.urlEncode(""));
		submitActionHttpReq = submitActionHttpReq.clone();
		submitActionHttpReq.url = submitURL;
		submitActionHttpReq.timeout = 20;
		submitActionHttpReq.send();
		
		ClientUtils.debug("Submit action: " + submitURL);
	}
	
	function onSubmitActionHttpResponse(response:HttpResponse)
	{
		if (response.isOK)
		{
			ClientUtils.debug("Submit action: " + response.content);
		}
		else
			ClientUtils.debug("Submit action error: "+response.error);
	}  
	
	/////////////////////////////////////////////////////////////////////////////////////
}

