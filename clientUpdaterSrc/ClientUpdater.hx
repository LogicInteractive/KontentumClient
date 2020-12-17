package;

import sys.FileSystem;
import sys.io.File;

/**
 * ...
 * @author Tommy S.
 */

class ClientUpdater 
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public function main() 
	{
		Sys.println('KontentumClient updater starting.');
		Sys.sleep(2);
		if (FileSystem.exists("clientUpdate") && FileSystem.exists("clientUpdate\\KontentumClient.exe") )
		{
			try 
			{
				File.copy("clientUpdate\\KontentumClient.exe","KontentumClient.exe");
			}
			catch(e:Dynamic)
			{
				Sys.println('Filed copy update file');
			}
		}
		Sys.command("shutdown", ["/r", "/f", "/t", "0"]); //reboot
	}

	/////////////////////////////////////////////////////////////////////////////////////
}
