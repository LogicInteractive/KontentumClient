package;

import client.KontentumClient;
import client.SubProcess;
import system.ClientUtils;

/**
 * ...
 * @author Tommy S.
 */

class Main 
{
	//===================================================================================
	// Main 
	//-----------------------------------------------------------------------------------
	
	static var client : KontentumClient;

	/////////////////////////////////////////////////////////////////////////////////////

	static function main() 
	{
		//client = new KontentumClient("config.xml");
		
		var c = new SubProcess("C:/Windows/System32/notepad.exe");
		c.lifeSpan = 10;
		if (!c.run())
			trace("process failed to start....");
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

