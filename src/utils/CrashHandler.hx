package utils;

#if cpp
@:cppFileCode('
	#include <windows.h>
	#include <dbghelp.h>
	#include <wininet.h>
	#include <stdio.h>
	#include <psapi.h>
	#pragma comment(lib, "dbghelp.lib")
	#pragma comment(lib, "wininet.lib")
	#pragma comment(lib, "psapi.lib")

	static char g_crashSubmitEventURL[1024] = {0};
	static wchar_t* g_crashRestartCommand = NULL;
	static volatile LONG g_crashHandled = 0;  // Prevent re-entry

	// Forward declaration for debug logging
	static void KC_DebugLog(const char* msg);

	// Process creation flags
	#ifndef DETACHED_PROCESS
	#define DETACHED_PROCESS 0x00000008
	#endif
	#ifndef CREATE_NEW_PROCESS_GROUP
	#define CREATE_NEW_PROCESS_GROUP 0x00000200
	#endif

	static void KC_SetCrashRestartCommand(const char* utf8)
	{
		if (g_crashRestartCommand)
		{
			free(g_crashRestartCommand);
			g_crashRestartCommand = NULL;
		}
		if (utf8 && *utf8)
		{
			int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
			if (wlen > 0)
			{
				g_crashRestartCommand = (wchar_t*)malloc(wlen * sizeof(wchar_t));
				MultiByteToWideChar(CP_UTF8, 0, utf8, -1, g_crashRestartCommand, wlen);
			}
		}
	}

	// Check if this exception is a fatal crash we should handle
	static BOOL KC_IsFatalException(DWORD code)
	{
		switch (code)
		{
			case 0xC0000005: // ACCESS_VIOLATION
			case 0xC0000006: // IN_PAGE_ERROR
			case 0xC00000FD: // STACK_OVERFLOW
			case 0xC0000094: // INTEGER_DIVIDE_BY_ZERO
			case 0xC0000095: // INTEGER_OVERFLOW
			case 0xC000001D: // ILLEGAL_INSTRUCTION
			case 0xC0000026: // INVALID_DISPOSITION
			case 0xC000008C: // ARRAY_BOUNDS_EXCEEDED
			case 0xC000008D: // FLOAT_DENORMAL_OPERAND
			case 0xC000008E: // FLOAT_DIVIDE_BY_ZERO
			case 0xC000008F: // FLOAT_INEXACT_RESULT
			case 0xC0000090: // FLOAT_INVALID_OPERATION
			case 0xC0000091: // FLOAT_OVERFLOW
			case 0xC0000092: // FLOAT_STACK_CHECK
			case 0xC0000093: // FLOAT_UNDERFLOW
				return TRUE;
			default:
				return FALSE;
		}
	}

	static const char* KC_GetExceptionName(DWORD code)
	{
		switch (code)
		{
			case 0xC0000005: return "ACCESS_VIOLATION";
			case 0xC0000006: return "IN_PAGE_ERROR";
			case 0xC00000FD: return "STACK_OVERFLOW";
			case 0xC0000094: return "INTEGER_DIVIDE_BY_ZERO";
			case 0xC0000095: return "INTEGER_OVERFLOW";
			case 0xC000001D: return "ILLEGAL_INSTRUCTION";
			case 0xC0000026: return "INVALID_DISPOSITION";
			case 0x80000001: return "GUARD_PAGE_VIOLATION";
			case 0xC0000008: return "INVALID_HANDLE";
			case 0xC000008C: return "ARRAY_BOUNDS_EXCEEDED";
			case 0xC000008D: return "FLOAT_DENORMAL_OPERAND";
			case 0xC000008E: return "FLOAT_DIVIDE_BY_ZERO";
			case 0xC000008F: return "FLOAT_INEXACT_RESULT";
			case 0xC0000090: return "FLOAT_INVALID_OPERATION";
			case 0xC0000091: return "FLOAT_OVERFLOW";
			case 0xC0000092: return "FLOAT_STACK_CHECK";
			case 0xC0000093: return "FLOAT_UNDERFLOW";
			case 0xE06D7363: return "CPP_EXCEPTION";
			case 0x40010005: return "CTRL_C_EXIT";
			default: return "UNKNOWN";
		}
	}

	static void KC_SubmitCrashEvent(const char* message)
	{
		KC_DebugLog("KC_SubmitCrashEvent called");

		if (!g_crashSubmitEventURL[0])
		{
			KC_DebugLog("KC_SubmitCrashEvent: URL not set, skipping");
			return;
		}

		char debugMsg[512];
		sprintf_s(debugMsg, "KC_SubmitCrashEvent: Base URL = %s", g_crashSubmitEventURL);
		KC_DebugLog(debugMsg);

		// Simple URL encode (just spaces and basic chars)
		char encodedMsg[2048] = {0};
		const char* hex = "0123456789ABCDEF";
		int j = 0;
		for (int i = 0; message[i] && j < 2000; i++)
		{
			unsigned char c = (unsigned char)message[i];
			if ((c >= \'A\' && c <= \'Z\') || (c >= \'a\' && c <= \'z\') ||
				(c >= \'0\' && c <= \'9\') || c == \'-\' || c == \'_\' || c == \'.\')
			{
				encodedMsg[j++] = c;
			}
			else if (c == \' \')
			{
				// Use %20 for spaces (+ is only valid in query strings, not paths)
				encodedMsg[j++] = \'%\';
				encodedMsg[j++] = \'2\';
				encodedMsg[j++] = \'0\';
			}
			else
			{
				encodedMsg[j++] = \'%\';
				encodedMsg[j++] = hex[(c >> 4) & 0x0F];
				encodedMsg[j++] = hex[c & 0x0F];
			}
		}
		encodedMsg[j] = 0;

		char fullURL[4096];
		snprintf(fullURL, sizeof(fullURL), "%s%s", g_crashSubmitEventURL, encodedMsg);

		sprintf_s(debugMsg, "KC_SubmitCrashEvent: Calling URL (truncated): %.200s...", fullURL);
		KC_DebugLog(debugMsg);

		// Best effort HTTP request (5 second timeout)
		HINTERNET hInternet = InternetOpenA("KontentumCrashHandler/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
		if (hInternet)
		{
			KC_DebugLog("KC_SubmitCrashEvent: InternetOpen succeeded");
			DWORD timeout = 5000;
			InternetSetOptionA(hInternet, INTERNET_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
			InternetSetOptionA(hInternet, INTERNET_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));

			HINTERNET hConnect = InternetOpenUrlA(hInternet, fullURL, NULL, 0, INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_RELOAD, 0);
			if (hConnect)
			{
				// Read response to ensure HTTP transaction actually completes before we terminate
				char responseBuffer[512];
				DWORD bytesRead = 0;
				InternetReadFile(hConnect, responseBuffer, sizeof(responseBuffer) - 1, &bytesRead);
				responseBuffer[bytesRead] = 0;

				sprintf_s(debugMsg, "KC_SubmitCrashEvent: HTTP response (%lu bytes): %.100s", bytesRead, responseBuffer);
				KC_DebugLog(debugMsg);

				KC_DebugLog("KC_SubmitCrashEvent: HTTP request completed");
				InternetCloseHandle(hConnect);
			}
			else
			{
				sprintf_s(debugMsg, "KC_SubmitCrashEvent: HTTP request FAILED (err=0x%08X)", (unsigned)GetLastError());
				KC_DebugLog(debugMsg);
			}
			InternetCloseHandle(hInternet);
		}
		else
		{
			sprintf_s(debugMsg, "KC_SubmitCrashEvent: InternetOpen FAILED (err=0x%08X)", (unsigned)GetLastError());
			KC_DebugLog(debugMsg);
		}
		KC_DebugLog("KC_SubmitCrashEvent: Done");
	}

	// Core crash handling logic - used by both VEH and UEF
	static void KC_HandleCrash(EXCEPTION_POINTERS* pExceptionInfo, const char* handlerName)
	{
		// Get exception details
		DWORD exceptionCode = pExceptionInfo->ExceptionRecord->ExceptionCode;
		void* exceptionAddr = pExceptionInfo->ExceptionRecord->ExceptionAddress;
		const char* exceptionName = KC_GetExceptionName(exceptionCode);

		// Get memory info
		MEMORYSTATUSEX memStatus;
		memStatus.dwLength = sizeof(memStatus);
		GlobalMemoryStatusEx(&memStatus);

		// Get process memory
		PROCESS_MEMORY_COUNTERS pmc;
		pmc.cb = sizeof(pmc);
		GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc));

		// Build dump path alongside the log directory (taken from env var we set)
		char dumpPath[MAX_PATH] = {0};
		DWORD len = GetEnvironmentVariableA("KC_LOG_DIR", dumpPath, MAX_PATH);
		if (len == 0 || len >= MAX_PATH)
		{
			strcpy_s(dumpPath, "");
		}
		CreateDirectoryA(dumpPath, NULL);

		SYSTEMTIME st; GetLocalTime(&st);
		char fileName[MAX_PATH] = {0};
		sprintf_s(fileName, "client-crash-%04d%02d%02d-%02d%02d%02d.dmp",
			st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

		char fullPath[MAX_PATH] = {0};
		snprintf(fullPath, MAX_PATH, "%s\\\\%s", dumpPath, fileName);

		HANDLE hFile = CreateFileA(fullPath, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (hFile != INVALID_HANDLE_VALUE)
		{
			MINIDUMP_EXCEPTION_INFORMATION mdei;
			mdei.ThreadId = GetCurrentThreadId();
			mdei.ExceptionPointers = pExceptionInfo;
			mdei.ClientPointers = FALSE;

			MINIDUMP_TYPE mtype = (MINIDUMP_TYPE)(
				  MiniDumpWithPrivateReadWriteMemory
				| MiniDumpWithDataSegs
				| MiniDumpWithHandleData
				| MiniDumpWithThreadInfo
				| MiniDumpWithIndirectlyReferencedMemory
			);

			MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), hFile, mtype, &mdei, NULL, NULL);
			CloseHandle(hFile);
		}

		// Build crash message
		char crashMsg[256];
		sprintf_s(crashMsg, "[NATIVE_CRASH] : (%s) %s @ 0x%08X",
			handlerName,
			exceptionName,
			(unsigned)exceptionCode);

		// Also append detailed log line (best effort)
		char logPath[MAX_PATH] = {0};
		len = GetEnvironmentVariableA("KC_LOG_FILE", logPath, MAX_PATH);
		if (len > 0 && len < MAX_PATH)
		{
			HANDLE hLog = CreateFileA(logPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
			if (hLog != INVALID_HANDLE_VALUE)
			{
				char logLine[1200];
				sprintf_s(logLine, "\\r\\n[NATIVE_CRASH] %s\\r\\n", crashMsg);
				DWORD written = 0;
				WriteFile(hLog, logLine, (DWORD)strlen(logLine), &written, NULL);
				CloseHandle(hLog);
			}
		}

		// Submit crash event to server (best effort)
		KC_SubmitCrashEvent(crashMsg);

		// Launch restart command if configured
		if (g_crashRestartCommand && g_crashRestartCommand[0])
		{
			STARTUPINFOW si;
			ZeroMemory(&si, sizeof(si));
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi;
			ZeroMemory(&pi, sizeof(pi));

			// Use DETACHED_PROCESS so child survives parent death
			DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
			if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
			{
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
		}
	}

	// Quick debug log - writes directly to a marker file
	static void KC_DebugLog(const char* msg)
	{
		char path[MAX_PATH] = {0};
		DWORD len = GetEnvironmentVariableA("KC_LOG_DIR", path, MAX_PATH);
		if (len > 0 && len < MAX_PATH)
		{
			strcat_s(path, "\\\\veh_debug.log");
		}
		else
		{
			strcpy_s(path, "C:\\\\temp\\\\veh_debug.log");
		}

		HANDLE hFile = CreateFileA(path, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (hFile != INVALID_HANDLE_VALUE)
		{
			SYSTEMTIME st; GetLocalTime(&st);
			char line[512];
			sprintf_s(line, "[%02d:%02d:%02d] %s\\r\\n", st.wHour, st.wMinute, st.wSecond, msg);
			DWORD written = 0;
			WriteFile(hFile, line, (DWORD)strlen(line), &written, NULL);
			CloseHandle(hFile);
		}
	}

	// Vectored Exception Handler - called FIRST, before hxcpp SEH handlers
	static LONG WINAPI KC_VectoredExceptionHandler(EXCEPTION_POINTERS* pExceptionInfo)
	{
		DWORD exceptionCode = pExceptionInfo->ExceptionRecord->ExceptionCode;

		// Debug: log every exception we see
		char debugMsg[256];
		sprintf_s(debugMsg, "VEH called: code=0x%08X", (unsigned)exceptionCode);
		KC_DebugLog(debugMsg);

		// Only handle fatal exceptions that would terminate the process
		if (!KC_IsFatalException(exceptionCode))
		{
			return EXCEPTION_CONTINUE_SEARCH;
		}

		KC_DebugLog("VEH: Fatal exception detected, handling crash...");

		// Prevent re-entry (crash during crash handling)
		if (InterlockedCompareExchange(&g_crashHandled, 1, 0) != 0)
		{
			KC_DebugLog("VEH: Re-entry detected, skipping");
			return EXCEPTION_CONTINUE_SEARCH;
		}

		// Handle the crash
		KC_DebugLog("VEH: Calling KC_HandleCrash...");
		KC_HandleCrash(pExceptionInfo, "VEH");
		KC_DebugLog("VEH: KC_HandleCrash completed");

		// Terminate the process immediately (dont let hxcpp catch it)
		KC_DebugLog("VEH: Calling TerminateProcess...");
		TerminateProcess(GetCurrentProcess(), exceptionCode);

		// Should never reach here, but just in case
		KC_DebugLog("VEH: TerminateProcess returned (unexpected!)");
		return EXCEPTION_CONTINUE_SEARCH;
	}

	// Unhandled Exception Filter - fallback for anything VEH misses
	static LONG WINAPI KC_UnhandledExceptionFilter(EXCEPTION_POINTERS* pExceptionInfo)
	{
		// Prevent re-entry
		if (InterlockedCompareExchange(&g_crashHandled, 1, 0) != 0)
		{
			return EXCEPTION_EXECUTE_HANDLER;
		}

		// Handle the crash
		KC_HandleCrash(pExceptionInfo, "UEF");

		// Let the process die without Windows error dialog
		return EXCEPTION_EXECUTE_HANDLER;
	}

	static void KC_SetCrashSubmitEventURL(const char* url)
	{
		if (url && strlen(url) < sizeof(g_crashSubmitEventURL))
		{
			strcpy_s(g_crashSubmitEventURL, sizeof(g_crashSubmitEventURL), url);
		}
	}

	static void KC_InstallCrashHandlers()
	{
		// Suppress Windows error dialogs
		SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);

		// Install VEH (called FIRST, before hxcpp SEH handlers)
		// The 1 means add to front of VEH chain
		AddVectoredExceptionHandler(1, KC_VectoredExceptionHandler);

		// Also install UEF as fallback (called if VEH passes through)
		SetUnhandledExceptionFilter(KC_UnhandledExceptionFilter);
	}

	// Handle Haxe exception - submit event and restart
	// Called from Haxe code for non-native exceptions
	static void KC_HandleHaxeException(const char* message)
	{
		KC_DebugLog("KC_HandleHaxeException called");

		// Submit crash event
		KC_SubmitCrashEvent(message);

		// Launch restart command if configured
		if (g_crashRestartCommand && g_crashRestartCommand[0])
		{
			// Log the restart command (convert wide to narrow for logging)
			char cmdLog[512];
			char narrowCmd[256];
			WideCharToMultiByte(CP_UTF8, 0, g_crashRestartCommand, -1, narrowCmd, 256, NULL, NULL);
			sprintf_s(cmdLog, "Restart command: %s", narrowCmd);
			KC_DebugLog(cmdLog);

			STARTUPINFOW si;
			ZeroMemory(&si, sizeof(si));
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi;
			ZeroMemory(&pi, sizeof(pi));

			DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
			if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
			{
				sprintf_s(cmdLog, "Restart process created, PID=%lu", pi.dwProcessId);
				KC_DebugLog(cmdLog);
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
			else
			{
				sprintf_s(cmdLog, "Failed to create restart process, error=%lu", GetLastError());
				KC_DebugLog(cmdLog);
			}
		}
		else
		{
			KC_DebugLog("No restart command configured");
		}
	}
')
#end
class CrashHandler
{
	public static function install():Void
	{
		#if cpp
		untyped __cpp__("KC_InstallCrashHandlers();");
		#end
	}

	/** Set the URL to submit crash events to (base URL, message will be appended). */
	public static function setSubmitEventURL(baseUrl:String):Void
	{
		#if cpp
		if (baseUrl != null && baseUrl.length > 0)
		{
			untyped __cpp__("KC_SetCrashSubmitEventURL({0}.c_str());", baseUrl);
		}
		#end
	}

	/** Set the command to run to restart the application after a crash. */
	public static function setRestartCommand(command:String):Void
	{
		#if cpp
		if (command != null && command.length > 0)
		{
			untyped __cpp__("KC_SetCrashRestartCommand({0}.c_str());", command);
		}
		#end
	}

	/** Wrap callbacks so exceptions are logged and don't silently kill timers/threads. */
	public static inline function safe<T>(fn:Void->T, ?label:String):Void
	{
		try
		{
			fn();
		}
		catch (e:Dynamic)
		{
			utils.Log.logException("[SAFE" + (label != null ? " " + label : "") + "] Exception", e);
		}
	}

	/**
	 * Handle a Haxe exception: log it, submit crash event to server, and restart the app.
	 * Call this from catch blocks for unrecoverable errors.
	 */
	public static function handleException(label:String, e:Dynamic):Void
	{
		// Log the exception
		utils.Log.logException(label, e);

		// Build crash message
		var msg = "[CLIENT_EXCEPTION] : " + label;
		if (e != null)
		{
			msg += " - " + Std.string(e);
		}

		// Truncate if too long (URL limit)
		if (msg.length > 200)
			msg = msg.substr(0, 200) + "...";

		#if cpp
		// Release mutex and stop watchdog BEFORE spawning restart process
		// Otherwise the new process will fail to acquire the single-instance mutex
		utils.WatchDog.stop();
		utils.Mutex.release();

		// Submit event and restart via C++
		untyped __cpp__("KC_HandleHaxeException({0}.c_str())", msg);
		#end

		// Give time for restart process to spawn
		Sys.sleep(0.5);

		// Exit this process
		Sys.exit(1);
	}

	// ==================== TEST FUNCTIONS (for debugging crash handler) ====================

	/** Test: Trigger ACCESS_VIOLATION (null pointer dereference) */
	public static function testAccessViolation():Void
	{
		#if cpp
		untyped __cpp__('
			int* p = nullptr;
			*p = 42;  // ACCESS_VIOLATION
		');
		#end
	}

	/** Test: Trigger STACK_OVERFLOW (infinite recursion) */
	public static function testStackOverflow():Void
	{
		#if cpp
		untyped __cpp__('
			volatile char buf[1024*1024*8];  // 8MB on stack
			buf[0] = 1;
		');
		#end
	}

	/** Test: Trigger INTEGER_DIVIDE_BY_ZERO */
	public static function testDivideByZero():Void
	{
		#if cpp
		untyped __cpp__('
			volatile int x = 0;
			volatile int y = 42 / x;  // DIVIDE_BY_ZERO
			(void)y;
		');
		#end
	}

	/** Test: Trigger a Haxe exception */
	public static function testHaxeException():Void
	{
		// Explicitly throw an exception - this is guaranteed to be caught
		throw "Test Haxe exception triggered from tray menu";
	}
}
