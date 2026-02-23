package utils;

import cpp.ConstPointer;
import cpp.Pointer;
import cpp.RawPointer;
import cpp.NativeString;
import cpp.Char;

#if windows
@:cppFileCode('
#include <windows.h>
#include <string>
')
#end
class WindowsRegistry
{
	static inline var REG_RUN_KEY:String = "Software\\Microsoft\\Windows\\CurrentVersion\\Run";
	static inline var APP_NAME:String = "KontentumClient";

	/**
	 * Install startup entry in HKCU\Software\Microsoft\Windows\CurrentVersion\Run
	 * @param exePath Full path to the executable (will be quoted)
	 * @param args Optional arguments to append (e.g., "--headless")
	 * @return true if successful
	 */
	public static function installStartup(exePath:String, ?args:String):Bool
	{
		#if windows
		if (exePath == null || exePath == "")
			return false;

		// Build command: "C:\path\to\app.exe" --args
		var command = '"' + exePath + '"';
		if (args != null && args != "")
			command += " " + args;

		return setRegistryValue(command);
		#else
		return false;
		#end
	}

	/**
	 * Remove startup entry from registry
	 * @return true if successful
	 */
	public static function uninstallStartup():Bool
	{
		#if windows
		return deleteRegistryValue();
		#else
		return false;
		#end
	}

	/**
	 * Check if startup is currently installed
	 * @return true if registry key exists
	 */
	public static function isStartupInstalled():Bool
	{
		#if windows
		return checkRegistryValueExists();
		#else
		return false;
		#end
	}

	/**
	 * Get the current startup command from registry
	 * @return The command string, or null if not installed
	 */
	public static function getStartupCommand():String
	{
		#if windows
		return getRegistryValue();
		#else
		return null;
		#end
	}

	#if windows
	static function setRegistryValue(value:String):Bool
	{
		var success:Bool = false;

		untyped __cpp__('
			HKEY hKey;
			LONG result;

			// Open/create the Run key (HKCU is per-user, no admin required)
			result = RegCreateKeyExW(
				HKEY_CURRENT_USER,
				L"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run",
				0,
				NULL,
				REG_OPTION_NON_VOLATILE,
				KEY_WRITE,
				NULL,
				&hKey,
				NULL
			);

			if (result == ERROR_SUCCESS)
			{
				// Convert Haxe string to UTF-8 then to wide string
				const char* utf8str = value.__CStr();
				int size_needed = MultiByteToWideChar(CP_UTF8, 0, utf8str, -1, NULL, 0);
				wchar_t* wideValue = new wchar_t[size_needed];
				MultiByteToWideChar(CP_UTF8, 0, utf8str, -1, wideValue, size_needed);

				// Set the value (REG_SZ = null-terminated string)
				result = RegSetValueExW(
					hKey,
					L"KontentumClient",
					0,
					REG_SZ,
					(const BYTE*)wideValue,
					(DWORD)size_needed * sizeof(wchar_t)
				);

				delete[] wideValue;
				success = (result == ERROR_SUCCESS);
				RegCloseKey(hKey);
			}
		');

		return success;
	}

	static function deleteRegistryValue():Bool
	{
		var success:Bool = false;

		untyped __cpp__('
			HKEY hKey;
			LONG result;

			result = RegOpenKeyExW(
				HKEY_CURRENT_USER,
				L"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run",
				0,
				KEY_WRITE,
				&hKey
			);

			if (result == ERROR_SUCCESS)
			{
				result = RegDeleteValueW(hKey, L"KontentumClient");
				success = (result == ERROR_SUCCESS);
				RegCloseKey(hKey);
			}
		');

		return success;
	}

	static function checkRegistryValueExists():Bool
	{
		var exists:Bool = false;

		untyped __cpp__('
			HKEY hKey;
			LONG result;

			result = RegOpenKeyExW(
				HKEY_CURRENT_USER,
				L"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run",
				0,
				KEY_READ,
				&hKey
			);

			if (result == ERROR_SUCCESS)
			{
				// Query the value to check if it exists
				result = RegQueryValueExW(hKey, L"KontentumClient", NULL, NULL, NULL, NULL);
				exists = (result == ERROR_SUCCESS);
				RegCloseKey(hKey);
			}
		');

		return exists;
	}

	static function getRegistryValue():String
	{
		var value:String = null;

		untyped __cpp__('
			HKEY hKey;
			LONG result;

			result = RegOpenKeyExW(
				HKEY_CURRENT_USER,
				L"Software\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run",
				0,
				KEY_READ,
				&hKey
			);

			if (result == ERROR_SUCCESS)
			{
				wchar_t buffer[1024];
				DWORD bufferSize = sizeof(buffer);
				DWORD type;

				result = RegQueryValueExW(
					hKey,
					L"KontentumClient",
					NULL,
					&type,
					(LPBYTE)buffer,
					&bufferSize
				);

				if (result == ERROR_SUCCESS && type == REG_SZ)
				{
					// Convert wide string to std::string (UTF-8)
					int size_needed = WideCharToMultiByte(CP_UTF8, 0, buffer, -1, NULL, 0, NULL, NULL);
					if (size_needed > 0)
					{
						char* utf8_buffer = new char[size_needed];
						WideCharToMultiByte(CP_UTF8, 0, buffer, -1, utf8_buffer, size_needed, NULL, NULL);
						value = ::String(utf8_buffer);
						delete[] utf8_buffer;
					}
				}

				RegCloseKey(hKey);
			}
		');

		return value;
	}
	#end
}
