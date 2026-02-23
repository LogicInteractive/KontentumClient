package utils;

#if windows
@:cppFileCode('
#include <windows.h>
')
#end
class Mutex
{
	#if windows
	static var mutexHandle:Int = 0;
	#end

	/**
	 * Create or acquire a named mutex to prevent duplicate instances
	 * @param name The mutex name (should be unique to your app)
	 * @return true if this is the first instance, false if another instance is already running
	 */
	public static function tryAcquire(name:String):Bool
	{
		#if windows
		var isFirst:Bool = false;

		untyped __cpp__('
			// Convert Haxe string to UTF-8 then to wide string
			const char* utf8str = name.__CStr();
			int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8str, -1, NULL, 0);
			wchar_t* wideName = new wchar_t[size_needed];
			MultiByteToWideChar(CP_UTF8, 0, utf8str, -1, wideName, size_needed);

			// Create/open a named mutex
			HANDLE hMutex = CreateMutexW(NULL, FALSE, wideName);
			delete[] wideName;

			if (hMutex != NULL)
			{
				// Check if we created a new mutex or opened an existing one
				DWORD lastError = GetLastError();
				isFirst = (lastError != ERROR_ALREADY_EXISTS);

				// Store the handle (cast to int for Haxe)
				mutexHandle = (int)(size_t)hMutex;
			}
		');

		return isFirst;
		#else
		return true; // On non-Windows, always allow
		#end
	}

	/**
	 * Release the mutex (called on exit)
	 */
	public static function release():Void
	{
		#if windows
		untyped __cpp__('
			if (mutexHandle != 0)
			{
				HANDLE hMutex = (HANDLE)(size_t)mutexHandle;
				CloseHandle(hMutex);
				mutexHandle = 0;
			}
		');
		#end
	}

	/**
	 * Get the raw mutex handle (for passing to native code like watchdog)
	 */
	public static function getHandle():Int
	{
		#if windows
		return mutexHandle;
		#else
		return 0;
		#end
	}
}
