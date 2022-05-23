package;

import KC;
import client.HostedFileSync;
import haxe.MainLoop;

/**
 * ...
 * @author Tommy S.
 */

//=======================================================================================

function main() 
	new KontentumClient();

//=======================================================================================

class KontentumClient 
{
	/////////////////////////////////////////////////////////////////////////////////////

	public function new()
	{
		printLogo();
		Updater.clean();
		Settings.load("config.xml",()->
		{
			HostedFileSync.init();
			KontentumLink.init();
			MainLoop.add(tick);
		});
	}

	function tick()
	{
		
	}

	/////////////////////////////////////////////////////////////////////////////////////
}


