package client;

import KontentumClient.ConfigXML;
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
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import utils.WindowsUtils;

/**
 * ...
 * @author Tommy S.
 */

@:cppFileCode('
#include <Windows.h>
')
class Network 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	static public var i				: Network;
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	var jsonPing					: JSONPingData;
	var timer						: Timer;
	
	var token						: String;
	var restIP						: String;
	var restAPI						: String;
	var restID						: String;
	var restToken					: String;
	var restURL						: String;
	var restURLBase					: String;
	var ipIsSent					: Bool;
	var firstCommand				: String;
	var launch						: String;
	var localIP						: String;
	var localMAC					: String;

	var http						: Http;
	var restStr						: String;
	var waitForResponse				: Bool;
	var pingTimer					: Timer;
	
	var submitActionHttpReq			: HttpRequest;
	var httpRequest					: HttpRequest;
	
	var c							: ConfigXML;

	/////////////////////////////////////////////////////////////////////////////////////

	static public function init()
	{
		i = new Network();
		i.startNet();
	}
	
	public function new() 
	{
		c = KontentumClient.config;
		
		restURLBase = c.kontentum.ip+'/'+c.kontentum.api+'/'+c.kontentum.clientID+'/'+c.kontentum.exhibitToken;
		submitActionHttpReq = new HttpRequest( { url:c.kontentum.ip, callback:onSubmitActionHttpResponse });		
	}
	
	public function startNet()
	{
 		var adapter = WindowsUtils.getNetworkAdapterInfo( WindowsUtils.ADAPTER_TYPE_ANY );
		if (adapter.ip == "0.0.0.0")
		{
			trace("Network adapter not found!");
			Timer.delay(startNet, 5000);
		}
		else
		{
			restURL = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname) + "/" + StringTools.urlEncode(KontentumClient.buildDate.toString());
			httpRequest = new HttpRequest( { url:restURL, callback:onHttpResponse, callbackError:onHttpError });
			// trace("REST: "+ restURL);
			createTimer();
			makeRequest();
		}
	}
	
	function createTimer() 
	{
		if (pingTimer != null)
			pingTimer.stop();
			
		pingTimer = new Timer(Std.int(c.kontentum.interval*1000));
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
		catch (e:Dynamic)
		{
			trace("Request error..");
		}
	}
	
	function requestComplete()
	{
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
		if (response==null)
			onPingError(null);

 		// if (response.isOK && response.status=200 )
 		if (response.isOK)
		{
			if (!response.isJson)
			{
				onPingCorruptData(response);
				return;
			}

			jsonPing = response.toJson();
			if (jsonPing == null)
			{
				onPingCorruptData(response);	
				return;
			}

			if (jsonPing.success)
			{
				trace("ResponseData : " + jsonPing);
				
				KontentumClient.parseCommand(jsonPing.callback);
				
				if (launch == null)
				{
					if (jsonPing.launch!=null && jsonPing.launch!="")
						launch = jsonPing.launch;
						
					if (KontentumClient.config.overridelaunch!=null)
						launch = KontentumClient.config.overridelaunch;
					else 
						KontentumClient.cacheLaunchFile(launch);

					if (isWeb(launch))
						KontentumClient.launchChrome(launch);
					else
						WindowsUtils.setPersistentProcess(launch);
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
				var newPing:Float = jsonPing.ping;
				if (newPing != KontentumClient.config.kontentum.interval)
				{
					trace("Changing ping time to : " + newPing);
					KontentumClient.config.kontentum.interval = newPing;
					createTimer();
				}
			}
		}
	} 

	function onPingError(response:HttpResponse) 
	{
		if (response==null)
			trace("Response - error - Response is NULL");
		else
		{
			trace("Response - error: "+ response.status + " " + response.error);
			trace(response.contentRaw);
		}
		
		Sys.sleep(10);
		requestComplete();
	}
	
	function onPingCorruptData(response:HttpResponse) 
	{
		trace("Response - not valid response data: "+ response.status + " " + response.content);
		// no valid data...
		Sys.sleep(10);
		requestComplete();
	}

	function onHttpError(response:HttpResponse) 
	{
		trace("HTTP error: "+response.toString());

		if (launch == null)
			launchOffline();
	}

	function launchOffline()
	{
		if (FileSystem.exists(KontentumClient.offlineLaunchFile))
		{
			try 
			{
				launch = File.getContent(KontentumClient.offlineLaunchFile);
			}
			catch(e:Dynamic)
			{
				trace("Failed to get offline launch cache");
			}

			trace("No connection, launching offline: "+launch);
			if (launch!=null && launch!="")
			{
				if (isWeb(launch))
					KontentumClient.launchChrome(launch);
				else
					WindowsUtils.setPersistentProcess(launch);
			}		
		}		
	}		


	/////////////////////////////////////////////////////////////////////////////////////

	public function submitAction(action:String)
	{
 		var submitURL:URL = new URL(restIP +'/rest/submitAction/' + restToken + '/' + StringTools.urlEncode(action) + '/' + StringTools.urlEncode(""));
		submitActionHttpReq = submitActionHttpReq.clone();
		submitActionHttpReq.url = submitURL;
		submitActionHttpReq.timeout = 20;
		submitActionHttpReq.send();
		
		trace("Submit action: " + submitURL);
 	}
	
	function onSubmitActionHttpResponse(response:HttpResponse)
	{
		if (response.isOK)
		{
			trace("Submit action: " + response.content);
		}
		else
			trace("Submit action error: "+response.error);
	}  
	
	/////////////////////////////////////////////////////////////////////////////////////

	inline function isWeb(path:String):Bool
	{
		return (path!=null && (path.indexOf("http://")!=-1 || path.indexOf("https://")!=-1 || path.indexOf("file://")!=-1) );
	}

	/////////////////////////////////////////////////////////////////////////////////////

}

typedef JSONPingData =
{
	var ping		: Float;
	var launch		: String;
	var callback	: SystemCommand;
	var success		: Bool;
}

enum abstract SystemCommand(String) to String
{
	var reboot		= "reboot";	
	var shutdown	= "shutdown";	
	var restart		= "restart";	
	var quit		= "quit";	
}