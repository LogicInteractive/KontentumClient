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
import no.logic.fox.kontentum.Kontentum;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import utils.WindowsUtils;

/**
 * ...
 * @author Tommy S.
 */

#if windows
@:cppFileCode('
// #include <Windows.h>
')
#end
class ServerCommunicator 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	static public var i				: ServerCommunicator;
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	var jsonPing					: JSONPingData;
	var timer						: Timer;
	
	var token						: String;
	var restIP						: String;
	var restAPI						: String;
	var restID						: String;
	var restToken					: String;
	var restURL						: String;
	var restURLFirst				: String;
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
	var httpRequestFirst			: HttpRequest;
	
	var c							: ConfigXML;

	/////////////////////////////////////////////////////////////////////////////////////

	static public function init()
	{
		i = new ServerCommunicator();
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
			if (KontentumClient.debug)
				trace("Network adapter not found!");
			Timer.delay(startNet, 5000);
		}
		else
		{
			var vol:Int = Math.round(WindowsUtils.getVolume()*100);
			httpRequest = new HttpRequest( { url:restURLBase, callback:onHttpResponse, callbackError:onHttpError });
			httpRequest.timeout = 30;

			restURLFirst = restURLBase + "/" +  StringTools.urlEncode(adapter.ip) + "/" + StringTools.urlEncode(adapter.mac) + "/" + StringTools.urlEncode(adapter.hostname) + "/" + StringTools.urlEncode(KontentumClient.buildDate.toString()) + "/" + vol;
			httpRequestFirst = new HttpRequest( { url:restURLFirst, callback:onHttpResponse, callbackError:onHttpError });
			httpRequestFirst.timeout = 30;
			// trace("REST: "+ restURL);
			createTimer();
			
			restStr = null;
			try
			{
				waitForResponse = true;
				httpRequestFirst.send();
			}
			catch (e:Dynamic)
			{
				if (KontentumClient.debug)
					trace("First request error..");
			}
		}
	}
	
	@:keep
	function createTimer() 
	{
		if (pingTimer != null)
			pingTimer.stop();
			
		pingTimer = new Timer(Std.int(c.kontentum.interval*1000));
		pingTimer.run = pingCallback;		
	}
	
	@:keep
	function pingCallback() 
	{
		if (!waitForResponse && KontentumClient.ready)
			makeRequest();
	}

	function makeRequest() 
	{
		if (KontentumClient.debug)
			trace("Send ping request");
		restStr = null;
		try
		{
			waitForResponse = true;
			//http.request(false);
			httpRequest = httpRequest.clone();
			// httpRequest.timeout = 30;
			httpRequest.send();
		}
		catch (e:Dynamic)
		{
			if (KontentumClient.debug)
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
 		// if (response.isOK)
		// {
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
				if (jsonPing.client != null)
				{
					var clientInfo:ClientInfo = jsonPing.client;
					clientInfo.download = jsonPing.client.download==1?true:false;
					if (KontentumClient.debug==false)
						clientInfo.debug = jsonPing.client.debug==1?true:false;
					else 
						clientInfo.debug = true;
						
					processClientInfoParams(clientInfo);
				}

				if (KontentumClient.debug)
					trace("ResponseData : " + jsonPing);
				

				adjustParams(jsonPing);
				KontentumClient.parseCommand(jsonPing);
				
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
				if (KontentumClient.debug)
					trace("Error: ClientID " + restID + " not found! ");
			}
			checkAttributes();
			requestComplete();
		// }
		// else
			// onPingCorruptData(response);	
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
					if (KontentumClient.debug)
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
		{
			if (KontentumClient.debug)
				trace("Response - error - Response is NULL");
		}
		else if (KontentumClient.debug)
		{
			trace("Response - error: "+ response.status + " " + response.error);
			trace(response.contentRaw);
		}
		
		Sys.sleep(10);
		requestComplete();
	}
	
	function onPingCorruptData(response:HttpResponse) 
	{
		if (KontentumClient.debug)
			trace("Response - not valid response data: "+ response.status + " " + response.content);
		// no valid data...
		Sys.sleep(10);
		requestComplete();
	}

	function onHttpError(response:HttpResponse) 
	{
		if (KontentumClient.debug)
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
				if (KontentumClient.debug)				
					trace("Failed to get offline launch cache");
			}

			if (KontentumClient.debug)
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
		
		if (KontentumClient.debug)
			trace("Submit action: " + submitURL);
 	}
	
	function onSubmitActionHttpResponse(response:HttpResponse)
	{
		if (response.isOK)
		{
			if (KontentumClient.debug)
				trace("Submit action: " + response.content);
		}
		else
			if (KontentumClient.debug)
				trace("Submit action error: "+response.error);
	}  
	
	/////////////////////////////////////////////////////////////////////////////////////

	function processClientInfoParams(ci:ClientInfo)
	{
		if (ci.debug!=null)
			KontentumClient.debug = ci.debug;

		if (ci.download!=null)
			KontentumClient.downloadFiles = ci.download;

		if (ci.killexplorer!=null)
			KontentumClient.killExplorer = ci.killexplorer;
	}


	/////////////////////////////////////////////////////////////////////////////////////

	function adjustParams(pingData:JSONPingData)
	{
		if (pingData.volume!=null || pingData.volume!=-1)
		{
			var newVol:Float = pingData.volume*0.01;
			WindowsUtils.setVolume(newVol);
			if (KontentumClient.debug)
				trace("Setting volume to : "+pingData.volume);
		}
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
	var client		: Dynamic;
	var sleep		: Bool;
	var volume		: Null<Int>;
}

enum abstract SystemCommand(String) to String
{
	var none			= "none";	
	var reboot			= "reboot";	
	var shutdown		= "shutdown";	
	var restart			= "restart";	
	var quit			= "quit";	
	var sleep			= "sleep";	
	var updateclient	= "updateclient";	
}

typedef ClientInfo =
{
	var id				: Int;
	var app_id			: Int;
	var exhibit_id		: Int;
	var client_type		: String;
	var name			: String;
	var hostname		: String;
	var ip				: String;
	var mac				: String;
	var client_version	: String;
	var launch			: String;
	var last_ping		: String;
	var description		: String;
	var callback		: String;
	var download		: Null<Bool>;
	var killexplorer	: Null<Bool>;
	var debug			: Null<Bool>;
	var volume			: Null<Int>;
	var token			: String;
	var exhibit_name	: String;
}

/* 
	var id": "370",
	var app_id": "14",
	var exhibit_id": "148",
	var client_type": "cmp",
	var name": "Vannkraftverket",
	var hostname": "DESKTOP-0VD7TTL",
	var ip": "95.130.220.50",
	var mac": "50:3E:AA:E1:BD:E7",
	var client_version": "2020-11-26 16:50:11",
	var launch": "c:\/Logic\/app\/TM_Vannkraft2.exe",
	var last_ping": "2020-12-04 11:00:25",
	var description": "",
	var callback": "",
	var appctrl": "0",
	var shutdown": "0",
	var reboot": "1",
	var download": "0",
	var killexplorer": "0",
	var debug": "0",
	var token": "rke0d6",
	var exhibit_name": "Vannkraftverket"
 */