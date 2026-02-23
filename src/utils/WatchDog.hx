package utils;

#if cpp
@:cppFileCode('
	#define WIN32_LEAN_AND_MEAN
	#include <windows.h>
	#include <dbghelp.h>
	#include <wininet.h>
	#include <process.h>
	#include <stdio.h>
	#include <time.h>
	#pragma comment(lib, "wininet.lib")
	#pragma comment(lib, "dbghelp.lib")

	// Process creation flags for console independence
	#ifndef DETACHED_PROCESS
	#define DETACHED_PROCESS 0x00000008
	#endif
	#ifndef CREATE_NEW_PROCESS_GROUP
	#define CREATE_NEW_PROCESS_GROUP 0x00000200
	#endif

	static HANDLE g_watchdogThread = NULL;
	static HANDLE g_pingEvent = NULL;
	static volatile BOOL g_isRunning = FALSE;
	static DWORD g_timeoutMs = 5000;
	static wchar_t* g_restartCommand = NULL;
	static HANDLE g_mutexHandle = NULL;
	static HANDLE g_appMutexHandle = NULL;  // App single-instance mutex (to release before restart)
	static char* g_notifyURL = NULL;
	static char* g_submitEventBaseURL = NULL;  // Base URL for submitEvent (message appended)

	static void KC_LogLineA(const char* line)
	{
		// Prefer same folder as app logs if provided via env:
		char logDir[MAX_PATH] = {0};
		char logFile[MAX_PATH] = {0};
		DWORD d1 = GetEnvironmentVariableA("KC_LOG_DIR", logDir, MAX_PATH);
		if (d1 == 0 || d1 >= MAX_PATH)
		{
			strcpy_s(logDir, "");
		}
		CreateDirectoryA(logDir, NULL);

		snprintf(logFile, MAX_PATH, "%s\\\\watchdog.log", logDir);
		HANDLE h = CreateFileA(logFile, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (h != INVALID_HANDLE_VALUE)
		{
			// timestamp
			SYSTEMTIME st; GetLocalTime(&st);
			char ts[64];
			sprintf_s(ts, "[%04d-%02d-%02d %02d:%02d:%02d] ",
				st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

			DWORD w = 0;
			WriteFile(h, ts, (DWORD)strlen(ts), &w, NULL);
			WriteFile(h, line, (DWORD)strlen(line), &w, NULL);
			const char* nl = "\\r\\n";
			WriteFile(h, nl, 2, &w, NULL);
			CloseHandle(h);
		}
	}

	static void KC_LogCrash(const char* reason, DWORD errorCode)
	{
		char buf[512];
		sprintf_s(buf, "Watchdog: %s (err=0x%08X)", reason, (unsigned)errorCode);
		KC_LogLineA(buf);

		char msg[256] = {0};
		FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL, errorCode, 0, msg, sizeof(msg), NULL);
		if (msg[0]) KC_LogLineA(msg);
	}

	// Write a minidump of the current process (called from watchdog thread on timeout)
	static void KC_WriteWatchdogDump(const char* reason)
	{
		// Build dump directory: prefer KC_LOG_DIR, fallback to exe directory
		char dumpDir[MAX_PATH] = {0};
		DWORD len = GetEnvironmentVariableA("KC_LOG_DIR", dumpDir, MAX_PATH);
		if (len == 0 || len >= MAX_PATH)
		{
			// Fallback: use directory of the running executable
			GetModuleFileNameA(NULL, dumpDir, MAX_PATH);
			char* lastSlash = strrchr(dumpDir, (char)0x5C);
			if (lastSlash) *lastSlash = 0;
			else strcpy_s(dumpDir, ".");
		}
		CreateDirectoryA(dumpDir, NULL);

		SYSTEMTIME st; GetLocalTime(&st);
		char dumpPath[MAX_PATH] = {0};
		sprintf_s(dumpPath, "%s\\\\watchdog-dump-%04d%02d%02d-%02d%02d%02d.dmp",
			dumpDir, st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);

		char logBuf[512];
		sprintf_s(logBuf, "Writing minidump to: %s", dumpPath);
		KC_LogLineA(logBuf);

		HANDLE hFile = CreateFileA(dumpPath, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (hFile != INVALID_HANDLE_VALUE)
		{
			MINIDUMP_TYPE mtype = (MINIDUMP_TYPE)(
				  MiniDumpWithPrivateReadWriteMemory
				| MiniDumpWithDataSegs
				| MiniDumpWithHandleData
				| MiniDumpWithThreadInfo
				| MiniDumpWithIndirectlyReferencedMemory
			);

			BOOL ok = MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), hFile, mtype, NULL, NULL, NULL);
			CloseHandle(hFile);

			if (ok)
			{
				KC_LogLineA("Minidump written successfully");
			}
			else
			{
				sprintf_s(logBuf, "MiniDumpWriteDump failed (err=0x%08X)", (unsigned)GetLastError());
				KC_LogLineA(logBuf);
			}
		}
		else
		{
			sprintf_s(logBuf, "Failed to create dump file (err=0x%08X)", (unsigned)GetLastError());
			KC_LogLineA(logBuf);
		}
	}

	static void KC_SetRestartCommandUTF8(const char* utf8)
	{
		if (g_restartCommand)
		{
			free(g_restartCommand);
			g_restartCommand = NULL;
		}
		int wlen = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, NULL, 0);
		if (wlen > 0)
		{
			g_restartCommand = (wchar_t*)malloc(wlen * sizeof(wchar_t));
			MultiByteToWideChar(CP_UTF8, 0, utf8, -1, g_restartCommand, wlen);
		}
	}

	static void KC_SetNotifyURL(const char* url)
	{
		if (g_notifyURL)
		{
			free(g_notifyURL);
			g_notifyURL = NULL;
		}
		if (url && *url)
		{
			size_t len = strlen(url) + 1;
			g_notifyURL = (char*)malloc(len);
			strcpy_s(g_notifyURL, len, url);
		}
	}

	static void KC_SetSubmitEventURL(const char* baseUrl)
	{
		if (g_submitEventBaseURL)
		{
			free(g_submitEventBaseURL);
			g_submitEventBaseURL = NULL;
		}
		if (baseUrl && *baseUrl)
		{
			size_t len = strlen(baseUrl) + 1;
			g_submitEventBaseURL = (char*)malloc(len);
			strcpy_s(g_submitEventBaseURL, len, baseUrl);
		}
	}

	// Set the app single-instance mutex handle (so we can release it before restart)
	static void KC_SetAppMutexHandle(HANDLE h)
	{
		g_appMutexHandle = h;
	}

	// Simple URL encoding for crash messages
	static void KC_UrlEncode(const char* input, char* output, size_t outputSize)
	{
		const char* hex = "0123456789ABCDEF";
		size_t j = 0;
		for (size_t i = 0; input[i] && j < outputSize - 4; i++)
		{
			unsigned char c = (unsigned char)input[i];
			if ((c >= \'A\' && c <= \'Z\') || (c >= \'a\' && c <= \'z\') ||
				(c >= \'0\' && c <= \'9\') || c == \'-\' || c == \'_\' || c == \'.\' || c == \'~\')
			{
				output[j++] = c;
			}
			else if (c == \' \')
			{
				// Use %20 for spaces (+ is only valid in query strings, not paths)
				output[j++] = \'%\';
				output[j++] = \'2\';
				output[j++] = \'0\';
			}
			else
			{
				output[j++] = \'%\';
				output[j++] = hex[(c >> 4) & 0x0F];
				output[j++] = hex[c & 0x0F];
			}
		}
		output[j] = 0;
	}

	static void KC_SubmitEvent(const char* message)
	{
		// Send crash event with message to submitEvent endpoint
		if (!g_submitEventBaseURL || !*g_submitEventBaseURL) return;

		// URL-encode the message
		char encodedMsg[1024];
		KC_UrlEncode(message, encodedMsg, sizeof(encodedMsg));

		// Build full URL: baseURL + encodedMessage
		char fullURL[2048];
		snprintf(fullURL, sizeof(fullURL), "%s%s", g_submitEventBaseURL, encodedMsg);

		char logMsg[512];
		sprintf_s(logMsg, "Submitting event: %s", fullURL);
		KC_LogLineA(logMsg);

		HINTERNET hInternet = InternetOpenA("KontentumWatchdog/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
		if (hInternet)
		{
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

				sprintf_s(logMsg, "Event submitted (%lu bytes): %.100s", bytesRead, responseBuffer);
				KC_LogLineA(logMsg);

				InternetCloseHandle(hConnect);
			}
			else
			{
				sprintf_s(logMsg, "Failed to submit event (err=0x%08X)", (unsigned)GetLastError());
				KC_LogLineA(logMsg);
			}
			InternetCloseHandle(hInternet);
		}
	}

	static void KC_NotifyServer(const char* reason)
	{
		// Send HTTP GET request to notify server about crash/timeout
		// This is a best-effort attempt - we don\'t wait for response
		if (!g_notifyURL || !*g_notifyURL) return;

		char logMsg[512];
		sprintf_s(logMsg, "Notifying server: %s", g_notifyURL);
		KC_LogLineA(logMsg);

		HINTERNET hInternet = InternetOpenA("KontentumWatchdog/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
		if (hInternet)
		{
			// 5 second timeout for the request
			DWORD timeout = 5000;
			InternetSetOptionA(hInternet, INTERNET_OPTION_CONNECT_TIMEOUT, &timeout, sizeof(timeout));
			InternetSetOptionA(hInternet, INTERNET_OPTION_RECEIVE_TIMEOUT, &timeout, sizeof(timeout));

			HINTERNET hConnect = InternetOpenUrlA(hInternet, g_notifyURL, NULL, 0, INTERNET_FLAG_NO_CACHE_WRITE | INTERNET_FLAG_RELOAD, 0);
			if (hConnect)
			{
				// Read response to ensure HTTP transaction actually completes
				char responseBuffer[512];
				DWORD bytesRead = 0;
				InternetReadFile(hConnect, responseBuffer, sizeof(responseBuffer) - 1, &bytesRead);
				KC_LogLineA("Server notification completed");
				InternetCloseHandle(hConnect);
			}
			else
			{
				sprintf_s(logMsg, "Failed to notify server (err=0x%08X)", (unsigned)GetLastError());
				KC_LogLineA(logMsg);
			}
			InternetCloseHandle(hInternet);
		}
		else
		{
			sprintf_s(logMsg, "Failed to initialize WinINet (err=0x%08X)", (unsigned)GetLastError());
			KC_LogLineA(logMsg);
		}
	}

	static BOOL KC_IsMemoryCritical()
	{
		MEMORYSTATUSEX m; m.dwLength = sizeof(m);
		if (!GlobalMemoryStatusEx(&m)) return FALSE;
		BOOL overLoad = (m.dwMemoryLoad > 90);
		double virtUse = 0.0;
		if (m.ullTotalVirtual) virtUse = (double)(m.ullTotalVirtual - m.ullAvailVirtual) / (double)m.ullTotalVirtual;
		return overLoad || (virtUse > 0.95);
	}

	static unsigned __stdcall KC_WatchdogThread(void* data)
	{
		KC_LogLineA("Watchdog thread started");
		while (g_isRunning)
		{
			DWORD wr = WaitForSingleObject(g_pingEvent, g_timeoutMs);
			if (wr == WAIT_TIMEOUT || KC_IsMemoryCritical())
			{
				const char* reason = wr == WAIT_TIMEOUT ? "Heartbeat timeout" : "Memory critical";
				KC_LogCrash(reason, GetLastError());

				// Write minidump before doing anything else (shows what threads are doing)
				KC_WriteWatchdogDump(reason);

				// Submit event with crash reason (best effort, 5s timeout)
				KC_SubmitEvent(reason);

				// Also notify server (legacy notification URL)
				KC_NotifyServer(reason);

				if (g_restartCommand && g_restartCommand[0])
				{
					// Log the restart command for debugging
					char cmdBuf[512];
					WideCharToMultiByte(CP_UTF8, 0, g_restartCommand, -1, cmdBuf, sizeof(cmdBuf), NULL, NULL);
					char logBuf[600];
					sprintf_s(logBuf, "Restart command: %s", cmdBuf);
					KC_LogLineA(logBuf);

					// Build environment block with APP_RESTARTED=1
					// Get current environment
					wchar_t* currentEnv = GetEnvironmentStringsW();

					// Calculate size needed for new environment (current + our variable + null terminators)
					size_t envSize = 0;
					wchar_t* p = currentEnv;
					while (*p)
					{
						size_t len = wcslen(p) + 1;
						envSize += len;
						p += len;
					}
					envSize++; // Final null terminator

					// Add space for APP_RESTARTED=1
					const wchar_t* newVar = L"APP_RESTARTED=1";
					size_t newVarLen = wcslen(newVar) + 1;

					// Allocate new environment block
					wchar_t* newEnv = (wchar_t*)malloc((envSize + newVarLen + 1) * sizeof(wchar_t));
					if (newEnv)
					{
						// Copy existing environment
						memcpy(newEnv, currentEnv, envSize * sizeof(wchar_t));

						// Add our variable at the end (before final null)
						wcscpy_s(newEnv + envSize - 1, newVarLen + 1, newVar);
						newEnv[envSize + newVarLen - 1] = 0; // Null terminator
						newEnv[envSize + newVarLen] = 0; // Double null terminator for end of environment
					}
					FreeEnvironmentStringsW(currentEnv);

					STARTUPINFOW si; ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
					PROCESS_INFORMATION pi; ZeroMemory(&pi, sizeof(pi));

					// Release the app single-instance mutex BEFORE spawning restart process
					// so the new process can acquire it
					if (g_appMutexHandle)
					{
						KC_LogLineA("Releasing app mutex before restart");
						ReleaseMutex(g_appMutexHandle);
						CloseHandle(g_appMutexHandle);
						g_appMutexHandle = NULL;
					}

					// Use DETACHED_PROCESS to ensure child is independent from parent console
					// CREATE_UNICODE_ENVIRONMENT is required when passing wide-char env block
					DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_UNICODE_ENVIRONMENT;
					if (CreateProcessW(NULL, g_restartCommand, NULL, NULL, FALSE, creationFlags, newEnv, NULL, &si, &pi))
					{
						CloseHandle(pi.hThread);
						CloseHandle(pi.hProcess);
						KC_LogLineA("Restart command launched");
					}
					else
					{
						char errBuf[256];
						sprintf_s(errBuf, "CreateProcessW failed for restart (err=0x%08X)", (unsigned)GetLastError());
						KC_LogLineA(errBuf);
					}

					// Free the environment block
					if (newEnv) free(newEnv);
				}
				else
				{
					KC_LogLineA("No restart command set");
				}

				// Kill current process; watchdog is inside same process, so this will end everything.
				TerminateProcess(GetCurrentProcess(), 1);
				break;
			}
			ResetEvent(g_pingEvent);
		}
		KC_LogLineA("Watchdog thread exiting");
		return 0;
	}

	static BOOL KC_StartWatchdog(DWORD timeoutMs)
	{
		// Single instance guard (within process)
		if (g_isRunning) return TRUE;

		g_mutexHandle = CreateMutexW(NULL, FALSE, L"Local\\KontentumClient_Watchdog_Mutex");
		if (GetLastError() == ERROR_ALREADY_EXISTS)
		{
			if (g_mutexHandle) CloseHandle(g_mutexHandle);
			g_mutexHandle = NULL;
			return FALSE;
		}

		g_timeoutMs = timeoutMs;
		g_pingEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
		if (!g_pingEvent) return FALSE;

		g_isRunning = TRUE;
		uintptr_t th = _beginthreadex(NULL, 0, KC_WatchdogThread, NULL, 0, NULL);
		if (!th)
		{
			g_isRunning = FALSE;
			CloseHandle(g_pingEvent); g_pingEvent = NULL;
			if (g_mutexHandle) { CloseHandle(g_mutexHandle); g_mutexHandle = NULL; }
			return FALSE;
		}
		g_watchdogThread = (HANDLE)th;
		return TRUE;
	}

	static BOOL KC_StopWatchdog()
	{
		if (!g_isRunning) return TRUE;
		g_isRunning = FALSE;
		if (g_watchdogThread)
		{
			SetEvent(g_pingEvent);
			WaitForSingleObject(g_watchdogThread, INFINITE);
			CloseHandle(g_watchdogThread);
			g_watchdogThread = NULL;
		}
		if (g_pingEvent) { CloseHandle(g_pingEvent); g_pingEvent = NULL; }
		if (g_mutexHandle) { CloseHandle(g_mutexHandle); g_mutexHandle = NULL; }
		if (g_restartCommand) { free(g_restartCommand); g_restartCommand = NULL; }
		if (g_notifyURL) { free(g_notifyURL); g_notifyURL = NULL; }
		if (g_submitEventBaseURL) { free(g_submitEventBaseURL); g_submitEventBaseURL = NULL; }
		return TRUE;
	}

	static void KC_PingWatchdog()
	{
		if (g_isRunning && g_pingEvent) SetEvent(g_pingEvent);
	}

	static BOOL KC_IsWatchdogRunning()
	{
		return g_isRunning && g_watchdogThread != NULL;
	}

	// Expose the ping event handle (so Tray can signal it during blocking calls)
	static HANDLE KC_GetPingEventHandle()
	{
		return g_pingEvent;
	}
')
#end
class WatchDog
{
	/** Start the watchdog (timeout in ms). If already running, returns true. */
	public static function start(timeoutMs:Int, ?restartCommand:String):Bool
	{
		#if cpp
		if (restartCommand != null && restartCommand.length > 0)
		{
			untyped __cpp__("KC_SetRestartCommandUTF8({0}.c_str());", restartCommand);
		}
		return untyped __cpp__("KC_StartWatchdog({0})", timeoutMs);
		#else
		return false;
		#end
	}

	/** Stop the watchdog. */
	public static function stop():Bool
	{
		#if cpp
		return untyped __cpp__("KC_StopWatchdog()");
		#else
		return true;
		#end
	}

	/** Set the server notification URL (called when watchdog detects crash/timeout). */
	public static function setNotifyURL(url:String):Void
	{
		#if cpp
		if (url != null && url.length > 0)
		{
			untyped __cpp__("KC_SetNotifyURL({0}.c_str());", url);
		}
		#end
	}

	/** Set the submitEvent base URL (watchdog will append URL-encoded crash message). */
	public static function setSubmitEventURL(baseUrl:String):Void
	{
		#if cpp
		if (baseUrl != null && baseUrl.length > 0)
		{
			untyped __cpp__("KC_SetSubmitEventURL({0}.c_str());", baseUrl);
		}
		#end
	}

	/** Heartbeat ping (call this periodically, e.g., every timeout/3 ms). */
	public static function ping():Void
	{
		#if cpp
		untyped __cpp__("KC_PingWatchdog()");
		#end
	}

	/** Is the watchdog active. */
	public static function isRunning():Bool
	{
		#if cpp
		return untyped __cpp__("KC_IsWatchdogRunning()");
		#else
		return false;
		#end
	}

	/** Set the app single-instance mutex handle (so watchdog can release it before restart). */
	public static function setAppMutex(handle:Int):Void
	{
		#if cpp
		untyped __cpp__("KC_SetAppMutexHandle((HANDLE)(intptr_t){0})", handle);
		#end
	}

	/** Get the ping event handle (so Tray can signal it during blocking calls like TrackPopupMenu). */
	public static function getPingEventHandle():Int
	{
		#if cpp
		return untyped __cpp__("(intptr_t)KC_GetPingEventHandle()");
		#else
		return 0;
		#end
	}
}
