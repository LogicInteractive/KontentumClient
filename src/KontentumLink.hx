package;

import com.akifox.asynchttp.AsyncHttp;
import fox.compile.CompileTime;
import fox.utils.DateUtils;
import haxe.Exception;
import sys.FileSystem;
import utils.WindowsUtils;

class KontentumLink
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public function init()
	{
		AsyncHttp.logErrorEnabled = false;
		var c = Settings.config;

		timerDirty = false;
		// restURLBase = c.kontentum.ip+'/'+c.kontentum.api+'/'+c.kontentum.clientID+'/'+c.kontentum.exhibitToken;
		// submitActionHttpReq = new HttpRequest( { url:c.kontentum.ip, callback:onSubmitActionHttpResponse });		
	}

	/////////////////////////////////////////////////////////////////////////////////////

}