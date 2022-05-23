package;

import fox.compile.CompileTime;
import fox.utils.DateUtils;
import haxe.Exception;
import sys.FileSystem;
import utils.WindowsUtils;

class Updater
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public function clean()
	{
		if (FileSystem.exists("clientUpdate"))
		{
			try 
			{
				if (FileSystem.exists("clientUpdate\\KontentumClient.exe"))
					FileSystem.deleteFile("clientUpdate\\KontentumClient.exe");
				if (FileSystem.exists("clientUpdate\\update.bat"))
					FileSystem.deleteFile("clientUpdate\\update.bat");
				FileSystem.deleteDirectory("clientUpdate");
			}
			catch(e:Exception)
			{
				if (Settings.debug)
					trace(e.stack);
			}
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////

}