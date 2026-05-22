package utils;

#if cpp
@:cppFileCode('
	#include <windows.h>
	#include <dbghelp.h>
	#include <wininet.h>
	#include <stdio.h>
	#include <psapi.h>
	#include <csignal>
	#include <cstdlib>
	#include <cstring>
	#include <exception>
	#include <typeinfo>
	#pragma comment(lib, "dbghelp.lib")
	#pragma comment(lib, "wininet.lib")
	#pragma comment(lib, "psapi.lib")

	static char g_crashSubmitEventURL[1024] = {0};
	static wchar_t* g_crashRestartCommand = NULL;
	static volatile LONG g_crashHandled = 0;  // Prevent re-entry
	static DWORD g_processStartTickCount = 0; // For uptime in crash events

	// Forward declaration for debug logging
	static void KC_DebugLog(const char* msg);

	// Human-readable name for a Windows exception code. Replaces the raw
	// SEH names ("ACCESS_VIOLATION", "CPP_EXCEPTION") that say nothing to a
	// reader who doesn\'t live in MSDN.
	static const char* KC_GetFriendlyExceptionName(DWORD code)
	{
		switch (code)
		{
			case 0xC0000005: return "Memory access violation";
			case 0xC0000006: return "Memory page error";
			case 0xC00000FD: return "Stack overflow";
			case 0xC0000094: return "Integer divide by zero";
			case 0xC0000095: return "Integer overflow";
			case 0xC000001D: return "Illegal CPU instruction";
			case 0xC0000026: return "Invalid exception disposition";
			case 0xC000008C: return "Array bounds exceeded";
			case 0xC000008E: return "Float divide by zero";
			case 0xC000008F: return "Float inexact result";
			case 0xC0000090: return "Float invalid operation";
			case 0xC0000091: return "Float overflow";
			case 0xC0000092: return "Float stack check";
			case 0xC0000093: return "Float underflow";
			case 0xE06D7363: return "Uncaught C++ exception";
			default:         return "Unknown native crash";
		}
	}

	// Classify an ACCESS_VIOLATION by access type and fault address. Knowing
	// the fault address pattern often identifies the bug class instantly:
	// 0x0 = null deref, 0xDDDD... = use-after-free, 0xCCCC... = uninitialised, etc.
	static const char* KC_DescribeAccessViolation(ULONG_PTR opType, ULONG_PTR faultAddr)
	{
		if (faultAddr == 0)
			return (opType == 1) ? "null pointer write" : (opType == 8) ? "null pointer exec" : "null pointer read";
		if (faultAddr < 0x10000)
			return (opType == 1) ? "near-null write (offset from null ptr)" : "near-null read (offset from null ptr)";
		if (faultAddr == (ULONG_PTR)0xCCCCCCCCCCCCCCCCULL) return "uninitialised stack memory";
		if (faultAddr == (ULONG_PTR)0xCDCDCDCDCDCDCDCDULL) return "uninitialised heap memory";
		if (faultAddr == (ULONG_PTR)0xDDDDDDDDDDDDDDDDULL) return "use-after-free (freed heap)";
		if (faultAddr == (ULONG_PTR)0xFEEEFEEEFEEEFEEEULL) return "use-after-free (debug free)";
		if (faultAddr == (ULONG_PTR)0xFDFDFDFDFDFDFDFDULL) return "buffer overrun past debug fence";
		if (faultAddr == (ULONG_PTR)0xBAADF00DBAADF00DULL) return "uninitialised LocalAlloc memory";
		if (faultAddr == (ULONG_PTR)0xABABABABABABABABULL) return "buffer overrun in HeapAlloc";
		return (opType == 1) ? "invalid memory write" : (opType == 8) ? "invalid code execution" : "invalid memory read";
	}

	// Extract the thrown C++ exception\'s class name from the MSVC RTTI throw info
	// embedded in EXCEPTION_RECORD. Turns the opaque "CPP_EXCEPTION" event into
	// "Uncaught haxe.io.Eof", which is usually enough to know what went wrong.
	// x64 only (HXCPP_M64); on x86 this returns empty.
	static void KC_GetCppExceptionType(const EXCEPTION_RECORD* er, char* outBuf, size_t outSize)
	{
		if (outSize == 0) return;
		outBuf[0] = 0;

		if (er->ExceptionCode != 0xE06D7363) return;
		if (er->NumberParameters < 4) return;

		// EH magic numbers (VS2003+, rethrow variants)
		ULONG_PTR magic = er->ExceptionInformation[0];
		if (magic != 0x19930520 && magic != 0x19930521 && magic != 0x19930522) return;

		DWORD64 imageBase = (DWORD64)er->ExceptionInformation[3];
		DWORD   throwInfoRva = (DWORD)er->ExceptionInformation[2];
		if (imageBase == 0 || throwInfoRva == 0) return;

		// _ThrowInfo: { attrs, unwind RVA, fwdCompat RVA, CatchableTypeArray RVA }
		const int* ti = (const int*)(imageBase + throwInfoRva);
		int ctaRva = ti[3];
		if (ctaRva == 0) return;

		// CatchableTypeArray: { count, RVAs[count] }
		const int* cta = (const int*)(imageBase + (DWORD)ctaRva);
		int nTypes = cta[0];
		if (nTypes <= 0) return;
		int firstRva = cta[1];

		// CatchableType: { props, pType RVA, mdisp, pdisp, vdisp, size, copyFn RVA }
		const int* ct = (const int*)(imageBase + (DWORD)firstRva);
		int typeDescRva = ct[1];
		if (typeDescRva == 0) return;

		// TypeDescriptor: { vftable*, spare*, char name[] } — on x64 name is at offset 16
		const char* mangled = (const char*)(imageBase + (DWORD)typeDescRva) + 16;
		if (mangled[0] != \'.\' || mangled[1] != \'?\' || mangled[2] != \'A\') {
			// Unexpected format — return raw
			size_t n = 0; while (mangled[n] && n < outSize - 1) { outBuf[n] = mangled[n]; n++; }
			outBuf[n] = 0;
			return;
		}

		// Mangled format ".?AV<class>@<ns1>@<ns2>@@" or ".?AU..." — split parts in reverse.
		const char* p = mangled + 4;
		char parts[8][96];
		int nParts = 0;
		while (*p && nParts < 8)
		{
			const char* start = p;
			while (*p && *p != \'@\') p++;
			size_t len = (size_t)(p - start);
			if (len == 0) break; // hit the @@ terminator
			if (len < sizeof(parts[0]))
			{
				memcpy(parts[nParts], start, len);
				parts[nParts][len] = 0;
				nParts++;
			}
			if (*p == \'@\') p++;
		}

		// Join in reverse with "." (Haxe-style namespace separator)
		outBuf[0] = 0;
		for (int i = nParts - 1; i >= 0; i--)
		{
			strcat_s(outBuf, outSize, parts[i]);
			if (i > 0) strcat_s(outBuf, outSize, ".");
		}
	}

	// Is this exception type an expected network blip that we shouldn\'t treat
	// as a bug? AsyncHttp worker threads throw haxe.io.Eof / Error when a server
	// drops the connection — every flaky network surface would otherwise emit a
	// "crash" event. Process still restarts, just no error report.
	// Strict matching (exact for stdlib types, prefix for akifox lib) so we
	// don\'t false-positive on user code that happens to contain "asynchttp".
	static BOOL KC_IsTransientNetworkException(const char* typeName)
	{
		if (!typeName || !*typeName) return FALSE;

		// Strip optional MSVC typeid.name() prefix.
		const char* t = typeName;
		if (strncmp(t, "class ",  6) == 0) t += 6;
		else if (strncmp(t, "struct ", 7) == 0) t += 7;

		// Exact matches for Haxe stdlib network exceptions (both . and :: forms).
		if (strcmp(t, "haxe.io.Eof")    == 0) return TRUE;
		if (strcmp(t, "haxe::io::Eof")  == 0) return TRUE;
		if (strcmp(t, "haxe.io.Error")  == 0) return TRUE;
		if (strcmp(t, "haxe::io::Error")== 0) return TRUE;

		// Anything inside the akifox-asynchttp library namespace.
		if (strstr(t, "com.akifox.asynchttp.")   != NULL) return TRUE;
		if (strstr(t, "com::akifox::asynchttp::") != NULL) return TRUE;

		return FALSE;
	}

	// Resolve a code address to "<module>+0x<offset>" so a crash event tells us
	// *where* the fault occurred (mbedtls.dll, wininet.dll, KontentumClient.exe, ...).
	// Falls back to a hex address if the module can\'t be resolved.
	static void KC_GetModuleAtAddress(void* addr, char* buf, size_t bufSize)
	{
		if (bufSize == 0) return;
		buf[0] = 0;
		if (!addr) { strcpy_s(buf, bufSize, "0x0"); return; }

		MEMORY_BASIC_INFORMATION mbi;
		if (VirtualQuery(addr, &mbi, sizeof(mbi)) == 0 || mbi.AllocationBase == NULL)
		{
			sprintf_s(buf, bufSize, "0x%llX", (unsigned long long)(uintptr_t)addr);
			return;
		}

		HMODULE hMod = (HMODULE)mbi.AllocationBase;
		char modPath[MAX_PATH] = {0};
		if (GetModuleFileNameA(hMod, modPath, MAX_PATH) == 0)
		{
			sprintf_s(buf, bufSize, "0x%llX", (unsigned long long)(uintptr_t)addr);
			return;
		}

		const char* slash = strrchr(modPath, \'\\\\\');
		const char* fname = slash ? slash + 1 : modPath;
		unsigned long long offset = (unsigned long long)((uintptr_t)addr - (uintptr_t)hMod);
		sprintf_s(buf, bufSize, "%s+0x%llX", fname, offset);
	}

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

	// ===== Notify throttle (shared with WatchDog via on-disk timestamp file) =====
	// Prevents the client from spamming the server during a restart loop.
	static __int64 KC_GetUnixTime()
	{
		SYSTEMTIME st; GetSystemTime(&st);
		FILETIME ft; SystemTimeToFileTime(&st, &ft);
		ULARGE_INTEGER u; u.LowPart = ft.dwLowDateTime; u.HighPart = ft.dwHighDateTime;
		return (__int64)((u.QuadPart - 116444736000000000ULL) / 10000000ULL);
	}

	static BOOL KC_IsNotifyThrottled(int windowSec)
	{
		char path[MAX_PATH] = {0};
		DWORD d = GetEnvironmentVariableA("KC_LOG_DIR", path, MAX_PATH);
		if (d == 0 || d >= MAX_PATH) return FALSE;
		strcat_s(path, "\\\\notify_lastsent.tmp");
		HANDLE h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
			NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
		if (h == INVALID_HANDLE_VALUE) return FALSE;
		char buf[32] = {0};
		DWORD read = 0;
		ReadFile(h, buf, sizeof(buf) - 1, &read, NULL);
		CloseHandle(h);
		if (read == 0) return FALSE;
		__int64 last = _atoi64(buf);
		__int64 now = KC_GetUnixTime();
		return (now - last) < (__int64)windowSec;
	}

	static void KC_RecordNotifyTime()
	{
		char path[MAX_PATH] = {0};
		DWORD d = GetEnvironmentVariableA("KC_LOG_DIR", path, MAX_PATH);
		if (d == 0 || d >= MAX_PATH) return;
		strcat_s(path, "\\\\notify_lastsent.tmp");
		HANDLE h = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ,
			NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
		if (h == INVALID_HANDLE_VALUE) return;
		char buf[32];
		int n = sprintf_s(buf, "%lld", (long long)KC_GetUnixTime());
		DWORD w = 0;
		WriteFile(h, buf, (DWORD)n, &w, NULL);
		CloseHandle(h);
	}

	static void KC_SubmitCrashEvent(const char* message)
	{
		if (!g_crashSubmitEventURL[0])
			return;

		// Rate-limit to once per 10 minutes (server protection).
		if (KC_IsNotifyThrottled(600))
			return;
		KC_RecordNotifyTime();

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

		// Best effort HTTP request (5 second timeout)
		HINTERNET hInternet = InternetOpenA("KontentumCrashHandler/1.0", INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
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
				InternetCloseHandle(hConnect);
			}
			InternetCloseHandle(hInternet);
		}
	}

	// True iff config.xml set crashDumps=false (KontentumClient.hx puts KC_NO_DUMPS=1 in env)
	static BOOL KC_DumpsDisabled()
	{
		char v[8] = {0};
		DWORD d = GetEnvironmentVariableA("KC_NO_DUMPS", v, sizeof(v));
		return (d > 0 && d < sizeof(v) && v[0] == \'1\');
	}

	// Core crash handling logic - used by both VEH and UEF
	static void KC_HandleCrash(EXCEPTION_POINTERS* pExceptionInfo, const char* handlerName)
	{
		DWORD exceptionCode = pExceptionInfo->ExceptionRecord->ExceptionCode;
		void* exceptionAddr = pExceptionInfo->ExceptionRecord->ExceptionAddress;
		EXCEPTION_RECORD* er = pExceptionInfo->ExceptionRecord;

		// Classify the crash FIRST (before any dump write) so we can short-circuit
		// transient network blips with zero side effects (no 30 MB dump file, no
		// server event, no veh_debug.log line — just a quiet client.log entry).
		char ripStr[160];
		KC_GetModuleAtAddress(exceptionAddr, ripStr, sizeof(ripStr));
		unsigned uptimeSec = (unsigned)((GetTickCount() - g_processStartTickCount) / 1000);

		char detail[256]; detail[0] = 0;
		char cppTypeName[160]; cppTypeName[0] = 0;
		BOOL isTransientNet = FALSE;

		if (exceptionCode == 0xC0000005 /* ACCESS_VIOLATION */ && er->NumberParameters >= 2)
		{
			ULONG_PTR opType    = er->ExceptionInformation[0];
			ULONG_PTR faultAddr = er->ExceptionInformation[1];
			sprintf_s(detail, "Memory access violation: %s (fault=0x%llX)",
				KC_DescribeAccessViolation(opType, faultAddr),
				(unsigned long long)faultAddr);
		}
		else if (exceptionCode == 0xE06D7363 /* CPP_EXCEPTION */)
		{
			KC_GetCppExceptionType(er, cppTypeName, sizeof(cppTypeName));
			if (cppTypeName[0])
			{
				sprintf_s(detail, "Uncaught %s", cppTypeName);
				isTransientNet = KC_IsTransientNetworkException(cppTypeName);
			}
			else
			{
				strcpy_s(detail, "Uncaught C++ exception (unknown type)");
			}
		}
		else
		{
			strcpy_s(detail, KC_GetFriendlyExceptionName(exceptionCode));
		}

		if (isTransientNet)
		{
			// Network blip — silent restart, NO dump, NO server submit.
			char quietLine[512];
			sprintf_s(quietLine, "[NATIVE_QUIET] %s at %s (uptime %us, %s) - network blip, not reported",
				detail, ripStr, uptimeSec, handlerName);

			char logPath[MAX_PATH] = {0};
			DWORD logLen = GetEnvironmentVariableA("KC_LOG_FILE", logPath, MAX_PATH);
			if (logLen > 0 && logLen < MAX_PATH)
			{
				HANDLE hLog = CreateFileA(logPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
				if (hLog != INVALID_HANDLE_VALUE)
				{
					char line[1024];
					sprintf_s(line, "\\r\\n%s\\r\\n", quietLine);
					DWORD written = 0;
					WriteFile(hLog, line, (DWORD)strlen(line), &written, NULL);
					CloseHandle(hLog);
				}
			}

			if (g_crashRestartCommand && g_crashRestartCommand[0])
			{
				STARTUPINFOW si; ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
				PROCESS_INFORMATION pi; ZeroMemory(&pi, sizeof(pi));
				DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
				if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
				{
					CloseHandle(pi.hThread);
					CloseHandle(pi.hProcess);
				}
			}
			return;
		}

		// Real crash — write the dump (unless disabled), log, submit to server, restart.
		if (!KC_DumpsDisabled())
		{
			char dumpPath[MAX_PATH] = {0};
			DWORD dumpLen = GetEnvironmentVariableA("KC_LOG_DIR", dumpPath, MAX_PATH);
			if (dumpLen == 0 || dumpLen >= MAX_PATH) strcpy_s(dumpPath, "");
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
		}

		char crashMsg[640];
		sprintf_s(crashMsg, "[NATIVE_CRASH] %s at %s (uptime %us, %s)",
			detail, ripStr, uptimeSec, handlerName);

		// Append the crash message verbatim to client.log (it already has the
		// [NATIVE_CRASH] prefix — don\'t double-stamp it).
		char logPath[MAX_PATH] = {0};
		DWORD logLen2 = GetEnvironmentVariableA("KC_LOG_FILE", logPath, MAX_PATH);
		if (logLen2 > 0 && logLen2 < MAX_PATH)
		{
			HANDLE hLog = CreateFileA(logPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
			if (hLog != INVALID_HANDLE_VALUE)
			{
				char logLine[1200];
				sprintf_s(logLine, "\\r\\n%s\\r\\n", crashMsg);
				DWORD written = 0;
				WriteFile(hLog, logLine, (DWORD)strlen(logLine), &written, NULL);
				CloseHandle(hLog);
			}
		}

		// Submit crash event to server (best effort, already throttled)
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
		if (KC_DumpsDisabled()) return;

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

		// Only handle fatal exceptions that would terminate the process
		// Skip 0xE06D7363 (C++ exceptions / Haxe try-catch) - these are normal and harmless
		if (!KC_IsFatalException(exceptionCode))
		{
			return EXCEPTION_CONTINUE_SEARCH;
		}

		char debugMsg[256];
		sprintf_s(debugMsg, "FATAL: %s (0x%08X)", KC_GetExceptionName(exceptionCode), (unsigned)exceptionCode);
		KC_DebugLog(debugMsg);

		// Prevent re-entry (crash during crash handling)
		if (InterlockedCompareExchange(&g_crashHandled, 1, 0) != 0)
			return EXCEPTION_CONTINUE_SEARCH;

		KC_HandleCrash(pExceptionInfo, "VEH");
		TerminateProcess(GetCurrentProcess(), exceptionCode);
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

	// Called when a C++ exception escapes a thread without being caught.
	// This happens when AsyncHttp worker threads throw non-String exceptions
	// (e.g., haxe.io.Eof, haxe.io.Error) that the library\'s catch clause misses.
	// std::terminate bypasses VEH entirely, so without this handler the process
	// dies silently with no crash log or restart.
	static void KC_TerminateHandler()
	{
		// Try to identify the exception type so we can ignore network blips.
		// std::current_exception() is documented to work inside a terminate handler
		// (the exception that triggered terminate is still active).
		char cppType[160] = {0};
		try
		{
			std::exception_ptr ep = std::current_exception();
			if (ep)
			{
				try { std::rethrow_exception(ep); }
				catch (const std::exception& e)
				{
					const char* tn = typeid(e).name();
					if (tn)
					{
						if (strncmp(tn, "class ", 6) == 0) tn += 6;
						strncpy_s(cppType, sizeof(cppType), tn, _TRUNCATE);
					}
				}
				catch (const char* s) { if (s) strncpy_s(cppType, sizeof(cppType), s, _TRUNCATE); }
				catch (...)            { strcpy_s(cppType, "non-std exception"); }
			}
		}
		catch (...) { /* introspection failed — unknown type */ }

		BOOL isTransient = KC_IsTransientNetworkException(cppType);

		// Prevent re-entry
		if (InterlockedCompareExchange(&g_crashHandled, 1, 0) != 0)
			_exit(1);

		unsigned uptimeSec = (unsigned)((GetTickCount() - g_processStartTickCount) / 1000);
		char msg[512];
		if (isTransient)
			sprintf_s(msg, "[NATIVE_QUIET] Uncaught %s via std::terminate (uptime %us) - network blip, not reported", cppType, uptimeSec);
		else if (cppType[0])
			sprintf_s(msg, "[NATIVE_CRASH] Uncaught %s via std::terminate (uptime %us)", cppType, uptimeSec);
		else
			sprintf_s(msg, "[NATIVE_CRASH] Uncaught C++ exception via std::terminate (uptime %us)", uptimeSec);

		// Append to client.log either way (local diagnostics are cheap)
		char logPath[MAX_PATH] = {0};
		DWORD logLen = GetEnvironmentVariableA("KC_LOG_FILE", logPath, MAX_PATH);
		if (logLen > 0 && logLen < MAX_PATH)
		{
			HANDLE hLog = CreateFileA(logPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
			if (hLog != INVALID_HANDLE_VALUE)
			{
				char line[1024];
				sprintf_s(line, "\\r\\n%s\\r\\n", msg);
				DWORD written = 0;
				WriteFile(hLog, line, (DWORD)strlen(line), &written, NULL);
				CloseHandle(hLog);
			}
		}

		// Server submit ONLY if this is a real crash, not a network blip.
		if (!isTransient)
		{
			KC_DebugLog(msg);
			KC_SubmitCrashEvent(msg);
		}

		if (g_crashRestartCommand && g_crashRestartCommand[0])
		{
			STARTUPINFOW si;
			ZeroMemory(&si, sizeof(si));
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi;
			ZeroMemory(&pi, sizeof(pi));

			DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
			if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
			{
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
		}

		_exit(1);
	}

	// SIGABRT handler - called when abort() is invoked (e.g., by default terminate)
	static void KC_AbortHandler(int sig)
	{
		if (InterlockedCompareExchange(&g_crashHandled, 1, 0) != 0)
			_exit(1);

		unsigned uptimeSec = (unsigned)((GetTickCount() - g_processStartTickCount) / 1000);
		char msg[256];
		sprintf_s(msg, "[NATIVE_CRASH] Process aborted via SIGABRT (uptime %us)", uptimeSec);
		KC_DebugLog(msg);
		KC_SubmitCrashEvent(msg);

		if (g_crashRestartCommand && g_crashRestartCommand[0])
		{
			STARTUPINFOW si;
			ZeroMemory(&si, sizeof(si));
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi;
			ZeroMemory(&pi, sizeof(pi));

			DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
			if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
			{
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
		}

		_exit(1);
	}

	static void KC_InstallCrashHandlers()
	{
		// Record process start so crash events can include uptime.
		g_processStartTickCount = GetTickCount();

		// Suppress Windows error dialogs
		SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX);

		// Install VEH (called FIRST, before hxcpp SEH handlers)
		// The 1 means add to front of VEH chain
		AddVectoredExceptionHandler(1, KC_VectoredExceptionHandler);

		// Also install UEF as fallback (called if VEH passes through)
		SetUnhandledExceptionFilter(KC_UnhandledExceptionFilter);

		// Catch unhandled C++ exceptions that escape worker threads
		// (bypasses VEH entirely via std::terminate -> abort)
		std::set_terminate(KC_TerminateHandler);

		// Catch SIGABRT in case abort() is called directly
		signal(SIGABRT, KC_AbortHandler);

		// Suppress the Windows abort error dialog
		_set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
	}

	// Handle Haxe exception - submit event and restart
	// Called from Haxe code for non-native exceptions
	static void KC_HandleHaxeException(const char* message)
	{
		KC_SubmitCrashEvent(message);

		if (g_crashRestartCommand && g_crashRestartCommand[0])
		{
			STARTUPINFOW si;
			ZeroMemory(&si, sizeof(si));
			si.cb = sizeof(si);
			PROCESS_INFORMATION pi;
			ZeroMemory(&pi, sizeof(pi));

			DWORD creationFlags = DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP;
			if (CreateProcessW(NULL, g_crashRestartCommand, NULL, NULL, FALSE, creationFlags, NULL, NULL, &si, &pi))
			{
				CloseHandle(pi.hThread);
				CloseHandle(pi.hProcess);
			}
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
}
