package;

import cpp.Lib;
import cpp.vm.Thread;
import haxe.Http;
import haxe.Timer;
import haxe.macro.Expr.Error;
import sys.io.File;

/**
 * ...
 * @author Tommy S.
 */
class Main 
{
	/////////////////////////////////////////////////////////////////////////////////////
	
	static var settings		: Dynamic;
	static var timer		: Timer;
	static var thread		: Thread;

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
		}
		
		settings = fromXML(Xml.parse(configFile));
	
		//thread = Thread.create(pingThread);
		//thread.sendMessage(Thread.current());
		
		//while (true)
		//{
			//Sys.sleep(15);
		//}
		
		//Sys.sleep(15);
		//SystemShutdown();
		SystemReboot();
	}
	
	static function pingThread() 
	{
		while (true)
		{
			trace( Http.requestUrl(settings.config.kontentum.ip+"/rest/getExhibit/"+settings.config.kontentum.exhibitID) );
			Sys.sleep(Std.parseFloat(settings.config.intervalMS)*0.001);
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static function SystemReboot() 
	{
		#if windows
		Sys.command("shutdown", ["/r", "/f", "/t", "0"]);
		#elseif osx
		
		#end
	}
	
	static function SystemShutdown() 
	{
		#if windows
		Sys.command("shutdown",["/s","/f","/t","0"]);
		#elseif osx
		
		#end
	}
	
	//===================================================================================
	// Utils
	//-----------------------------------------------------------------------------------
	/////////////////////////////////////////////////////////////////////////////////////
	
	/////////////////////////////////////////////////////////////////////////////////////
	
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

