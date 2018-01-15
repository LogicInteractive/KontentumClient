package system;

/**
 * ...
 * @author Tommy S
 */

@:cppFileCode('
#include <iostream>
#include <windows.h>
#include <psapi.h>
')
@:cppNamespaceCode('

HWND hwnd;
std::string winMatch;
HWND foundHwnd;

DEVMODE devPrevMode;
BOOL    bPrevSet = FALSE;
bool (*execeptionHandlerCallBack)(); 

LONG WINAPI UnhandledCB(PEXCEPTION_POINTERS exception)
{
    //printf("EXCEPTION OCCURED FROM HAXE CPP - Do something now?");
	if (execeptionHandlerCallBack != nullptr);
		execeptionHandlerCallBack();
		
    return EXCEPTION_CONTINUE_SEARCH;
}

void setExeptionHandlerCallBack(bool (*cb)())
{
	execeptionHandlerCallBack = cb;
}

')
class CrashHandler
{	
	//===================================================================================
	// Crash handler (Should work for Windows... )
	//-----------------------------------------------------------------------------------		
		
	private static var callbackFunc:Void->Void;
	
	public static function setCPPExceptionHandler(callBackHandler:Void->Void, showCrashErrors:Bool=false)
	{
		CrashHandler.showCrashErrors(showCrashErrors);
		if (callBackHandler != null)
		{
			callbackFunc = callBackHandler;
			enableSimpleCPPExceptionHandler();
		}
	}
	
	private static function exceptCallback():Bool
	{
		//trace("callback from extern c++ lib");
		if (callbackFunc != null)
			callbackFunc();
		return true;
	}
	
	static private function enableSimpleCPPExceptionHandler()
	{
		var cb:cpp.Callable<Void->Bool> = untyped __cpp__("exceptCallback");
		
		untyped __cpp__('
			SetUnhandledExceptionFilter(UnhandledCB);		
			setExeptionHandlerCallBack(cb);
		');
	}	
	
	static public function showCrashErrors(show:Bool)
	{
		if (!show)
		{
			untyped __cpp__('
				SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
			');
		}	
	}	
	
	/////////////////////////////////////////////////////////////////////////////////////
}