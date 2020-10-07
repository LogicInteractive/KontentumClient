package utils;


/**
 * ...
 * @author Tommy S.
 */

class KCUtils
{
	/////////////////////////////////////////////////////////////////////////////////////

	function onLoadXMLComplete(l:Loader)
	{
		try
		{
			var dd:ConfigXML = cast ObjUtils.fromXML(l.contentXML);		
			trace(dd);
		}
		catch(e:Dynamic)
		{
			trace(e);
		}
	}

	/////////////////////////////////////////////////////////////////////////////////////
}
