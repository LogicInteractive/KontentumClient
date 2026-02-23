package utils;

#if cpp
@:buildXml('
<target id="haxe">
    <!-- No rc.exe needed. Pure Win32 + Shell libs -->
    <lib name="Shell32.lib"/>
    <lib name="User32.lib"/>
    <lib name="Comctl32.lib"/>
</target>
')
#end

#if cpp
@:cppFileCode('
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <shellapi.h>
    #include <commctrl.h>
    #include <stdio.h>

    /////////////////
    // Globals
    /////////////////
    static const UINT KC_TRAY_MSG = WM_APP + 123;
    static const UINT KC_CMD_STATUS   = 1000; // non-clickable info row
    static const UINT KC_CMD_SHOW_LOGS = 1001;
    static const UINT KC_CMD_RESTART   = 1002;
    static const UINT KC_CMD_QUIT      = 1003;
    static const UINT KC_CMD_TEST_CRASH = 1004;
    static const UINT KC_CMD_TEST_HAXE_EX = 1005;

    static HINSTANCE g_hInst = NULL;
    static HWND g_hWnd = NULL;
    static NOTIFYICONDATAA g_nid = {0};
    static HMENU g_hMenu = NULL;
    static volatile LONG g_lastCmd = 0;
    static HICON g_hIcon = NULL;
    static char g_tooltip[128] = "Kontentum Client";
    static char g_status[128] = "Uptime: --:--:--";
    static HANDLE g_watchdogPingEvent = NULL;  // Watchdog ping event (signaled to keep watchdog alive)
    static const UINT_PTR KC_MENU_TIMER_ID = 42;

    /////////////////
    // ICO parsing (from memory)
    /////////////////
    #pragma pack(push, 1)
    typedef struct {
        WORD idReserved; // 0
        WORD idType;     // 1 for icons
        WORD idCount;    // number of images
    } ICONDIR;

    typedef struct {
        BYTE  bWidth;
        BYTE  bHeight;
        BYTE  bColorCount;
        BYTE  bReserved;
        WORD  wPlanes;
        WORD  wBitCount;
        DWORD dwBytesInRes;
        DWORD dwImageOffset;
    } ICONDIRENTRY;
    #pragma pack(pop)

    // Forward declaration for the hxcpp bridge (used below)
    static void KC_SetTrayIconFromBytes(const unsigned char* data, int size);

    static HICON KC_LoadIconFromIcoBytes(const unsigned char* data, int size)
    {
        if (!data || size < (int)sizeof(ICONDIR)) return NULL;

        const ICONDIR* dir = (const ICONDIR*)data;
        if (dir->idReserved != 0 || dir->idType != 1 || dir->idCount == 0) return NULL;

        // Prefer 16x16; otherwise choose smallest area
        int bestIndex = -1;
        int bestScore = 1<<30;

        const ICONDIRENTRY* entries = (const ICONDIRENTRY*)(data + sizeof(ICONDIR));
        for (int i = 0; i < dir->idCount; ++i)
        {
            const ICONDIRENTRY* e = &entries[i];
            int w = (e->bWidth == 0 ? 256 : e->bWidth);
            int h = (e->bHeight == 0 ? 256 : e->bHeight);
            int score = (w == 16 && h == 16) ? 0 : (w*h);
            if (score < bestScore)
            {
                bestScore = score;
                bestIndex = i;
                if (score == 0) break; // perfect
            }
        }

        if (bestIndex < 0) return NULL;

        const ICONDIRENTRY* be = &entries[bestIndex];
        if ((int)(be->dwImageOffset + be->dwBytesInRes) > size) return NULL;

        const BYTE* img = (const BYTE*)(data + be->dwImageOffset);
        DWORD imgSize = be->dwBytesInRes;

        // Create icon from one image blob (DIB/PNG inside ICO)
        HICON h = CreateIconFromResourceEx((PBYTE)img, imgSize, TRUE, 0x00030000, 0, 0, LR_DEFAULTCOLOR);
        return h;
    }

    static void KC_RefreshStatusMenu()
    {
        if (!g_hMenu) return;
        ModifyMenuA(g_hMenu, KC_CMD_STATUS, MF_BYCOMMAND | MF_STRING | MF_GRAYED, KC_CMD_STATUS, g_status);
    }

    static LRESULT CALLBACK KC_WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
    {
        switch (msg)
        {
            case WM_CREATE:
                return 0;

            case WM_COMMAND:
            {
                switch (LOWORD(wParam))
                {
                    case KC_CMD_SHOW_LOGS:   InterlockedExchange(&g_lastCmd, KC_CMD_SHOW_LOGS);   break;
                    case KC_CMD_RESTART:     InterlockedExchange(&g_lastCmd, KC_CMD_RESTART);    break;
                    case KC_CMD_QUIT:        InterlockedExchange(&g_lastCmd, KC_CMD_QUIT);       break;
                    case KC_CMD_TEST_CRASH:  InterlockedExchange(&g_lastCmd, KC_CMD_TEST_CRASH); break;
                    case KC_CMD_TEST_HAXE_EX: InterlockedExchange(&g_lastCmd, KC_CMD_TEST_HAXE_EX); break;
                }
                return 0;
            }

            case WM_TIMER:
            {
                // Keep watchdog alive during blocking TrackPopupMenu
                if (wParam == KC_MENU_TIMER_ID && g_watchdogPingEvent)
                {
                    SetEvent(g_watchdogPingEvent);
                }
                return 0;
            }

            case KC_TRAY_MSG:
            {
                if (lParam == WM_RBUTTONUP || lParam == WM_CONTEXTMENU)
                {
                    POINT pt; GetCursorPos(&pt);
                    SetForegroundWindow(hWnd);
                    KC_RefreshStatusMenu();

                    // Ping watchdog immediately and start a timer to keep pinging
                    // during the blocking TrackPopupMenu call
                    if (g_watchdogPingEvent) SetEvent(g_watchdogPingEvent);
                    SetTimer(hWnd, KC_MENU_TIMER_ID, 3000, NULL);

                    TrackPopupMenu(g_hMenu, TPM_RIGHTBUTTON, pt.x, pt.y, 0, hWnd, NULL);

                    // Menu closed, stop the keepalive timer
                    KillTimer(hWnd, KC_MENU_TIMER_ID);
                    if (g_watchdogPingEvent) SetEvent(g_watchdogPingEvent);

                    PostMessage(hWnd, WM_NULL, 0, 0);
                }
                else if (lParam == WM_LBUTTONDBLCLK)
                {
                    InterlockedExchange(&g_lastCmd, KC_CMD_SHOW_LOGS);
                }
                return 0;
            }

            case WM_DESTROY:
                PostQuitMessage(0);
                return 0;
        }
        return DefWindowProc(hWnd, msg, wParam, lParam);
    }

    static HICON KC_LoadIconFromFileA(const char* path)
    {
        if (!path || !*path) return NULL;
        HICON h = (HICON)LoadImageA(NULL, path, IMAGE_ICON, 0, 0, LR_DEFAULTSIZE | LR_LOADFROMFILE);
        return h;
    }

    // Optional fallback (if you later add a .rc and resource id 101)
    static HICON KC_LoadIconFromResource()
    {
        HINSTANCE h = GetModuleHandleA(NULL);
        HICON ico = LoadIconA(h, MAKEINTRESOURCEA(101));
        if (!ico)
        {
            ico = (HICON)LoadImageA(h, MAKEINTRESOURCEA(101), IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
        }
        if (!ico) ico = LoadIcon(NULL, IDI_APPLICATION);
        return ico;
    }

    // Replace current icon and notify tray
    static void KC_SetTrayIconFromBytes(const unsigned char* data, int size)
    {
        if (!data || size <= 0) return;
        HICON h = KC_LoadIconFromIcoBytes(data, size);
        if (!h) return;

        if (g_hIcon) DestroyIcon(g_hIcon);
        g_hIcon = h;

        if (g_nid.cbSize)
        {
            g_nid.hIcon = g_hIcon;
            Shell_NotifyIconA(NIM_MODIFY, &g_nid);
        }
    }

    // hxcpp bridge: accept Array<unsigned char> from Haxe Bytes.getData()
    static void KC_SetTrayIconFromBytes_Haxe(::Array<unsigned char> data)
    {
        if (!data.mPtr) return;
        unsigned char* base = (unsigned char*)data->GetBase();
        int len = data->length;
        if (!base || len <= 0) return;
        KC_SetTrayIconFromBytes(base, len);
    }

    static void KC_DestroyTray()
    {
        if (g_nid.cbSize)
        {
            Shell_NotifyIconA(NIM_DELETE, &g_nid);
            ZeroMemory(&g_nid, sizeof(g_nid));
        }
        if (g_hIcon) { DestroyIcon(g_hIcon); g_hIcon = NULL; }
        if (g_hMenu) { DestroyMenu(g_hMenu); g_hMenu = NULL; }
        if (g_hWnd)
        {
            DestroyWindow(g_hWnd);
            g_hWnd = NULL;
        }
    }

    static BOOL KC_InitTray(const char* tooltip, const char* iconPath)
    {
        g_hInst = GetModuleHandleA(NULL);

        if (tooltip && *tooltip)
        {
            strncpy_s(g_tooltip, tooltip, sizeof(g_tooltip)-1);
            g_tooltip[sizeof(g_tooltip)-1] = 0;
        }

        // Register hidden window class
        WNDCLASSA wc = {0};
        wc.lpfnWndProc = KC_WndProc;
        wc.hInstance = g_hInst;
        wc.lpszClassName = "KC_TrayWndClass";
        RegisterClassA(&wc);

        g_hWnd = CreateWindowA("KC_TrayWndClass", "KC_TrayWindow", WS_OVERLAPPED, 0,0,0,0, NULL, NULL, g_hInst, NULL);
        if (!g_hWnd) return FALSE;

        // Load icon by file path if provided; otherwise leave null (we will set from embedded bytes)
        if (iconPath && *iconPath)
        {
            g_hIcon = KC_LoadIconFromFileA(iconPath);
        }

        // Build popup menu
        g_hMenu = CreatePopupMenu();
        AppendMenuA(g_hMenu, MF_STRING | MF_GRAYED, KC_CMD_STATUS, g_status);
        AppendMenuA(g_hMenu, MF_SEPARATOR, 0, NULL);
        AppendMenuA(g_hMenu, MF_STRING, KC_CMD_SHOW_LOGS, "Open logs");
        AppendMenuA(g_hMenu, MF_STRING, KC_CMD_RESTART,   "Restart client");
        AppendMenuA(g_hMenu, MF_SEPARATOR, 0, NULL);
        AppendMenuA(g_hMenu, MF_STRING, KC_CMD_TEST_CRASH, "Test Native Crash (DEBUG)");
        AppendMenuA(g_hMenu, MF_STRING, KC_CMD_TEST_HAXE_EX, "Test Haxe Exception (DEBUG)");
        AppendMenuA(g_hMenu, MF_SEPARATOR, 0, NULL);
        AppendMenuA(g_hMenu, MF_STRING, KC_CMD_QUIT,      "Quit");

        // Add tray icon
        ZeroMemory(&g_nid, sizeof(g_nid));
        g_nid.cbSize = sizeof(NOTIFYICONDATAA);
        g_nid.hWnd = g_hWnd;
        g_nid.uID = 1;
        g_nid.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
        g_nid.uCallbackMessage = KC_TRAY_MSG;
        g_nid.hIcon = g_hIcon ? g_hIcon : LoadIcon(NULL, IDI_APPLICATION);
        strncpy_s(g_nid.szTip, g_tooltip, sizeof(g_nid.szTip)-1);

        if (!Shell_NotifyIconA(NIM_ADD, &g_nid))
        {
            KC_DestroyTray();
            return FALSE;
        }

        // Try without setting version - use default behavior
        // g_nid.uVersion = NOTIFYICON_VERSION_4;
        // Shell_NotifyIconA(NIM_SETVERSION, &g_nid);

        return TRUE;
    }

    static void KC_PumpTrayMessages()
    {
        if (!g_hWnd) return;
        MSG msg;
        while (PeekMessageA(&msg, g_hWnd, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&msg);
            DispatchMessageA(&msg);
        }
    }

    static void KC_UpdateTooltip(const char* tooltip)
    {
        if (!g_hWnd) return;
        if (tooltip && *tooltip)
        {
            strncpy_s(g_tooltip, tooltip, sizeof(g_tooltip)-1);
            g_tooltip[sizeof(g_tooltip)-1] = 0;
        }
        strncpy_s(g_nid.szTip, g_tooltip, sizeof(g_nid.szTip)-1);
        g_nid.uFlags = NIF_TIP;
        Shell_NotifyIconA(NIM_MODIFY, &g_nid);
    }

    static LONG KC_GetLastCommand()
    {
        return InterlockedExchange(&g_lastCmd, 0);
    }

    static void KC_SetStatus(const char* text)
    {
        if (!text) return;
        strncpy_s(g_status, text, sizeof(g_status)-1);
        g_status[sizeof(g_status)-1] = 0;
    }

    // Set the watchdog ping event handle (so tray can keep watchdog alive during blocking menus)
    static void KC_SetWatchdogPingEvent(HANDLE h)
    {
        g_watchdogPingEvent = h;
    }
')
#end

class Tray
{
	public static function init(?tooltip:String, ?iconPath:String):Bool
	{
		#if cpp
		var tip = tooltip != null ? tooltip : "Kontentum Client";
		var ico = iconPath != null ? iconPath : "";
		return untyped __cpp__("KC_InitTray({0}.c_str(), {1}.c_str())", tip, ico);
		#else
		return false;
		#end
	}

	public static function destroy():Void
	{
		#if cpp
		untyped __cpp__("KC_DestroyTray()");
		#end
	}

	/** Pump the hidden window\'s message queue. Call ~every 100–250 ms. */
	public static function pump():Void
	{
		#if cpp
		untyped __cpp__("KC_PumpTrayMessages()");
		#end
	}

	public static function setTooltip(tip:String):Void
	{
		#if cpp
		untyped __cpp__("KC_UpdateTooltip({0}.c_str())", tip);
		#end
	}

	/** Returns: 1001=Open logs, 1002=Restart, 1003=Quit, 0=none. */
	public static function pollCommand():Int
	{
		#if cpp
		return untyped __cpp__("KC_GetLastCommand()");
		#else
		return 0;
		#end
	}

	public static function setStatus(text:String):Void
	{
		#if cpp
		untyped __cpp__("KC_SetStatus({0}.c_str())", text);
		#end
	}

	/** Use the embedded ICO (Haxe resource "trayico") for the tray icon. */
	public static function useEmbeddedIcon():Void
	{
		#if cpp
		final b = haxe.Resource.getBytes("trayico");
		if (b != null)
		{
			@:privateAccess
			{
				// b.b : BytesData = Array<cpp.UInt8> → maps to ::Array<unsigned char> in C++
				var raw = b.b;
				untyped __cpp__("KC_SetTrayIconFromBytes_Haxe({0});", raw);
			}
		}
		#end
	}

	/** Set the watchdog ping event handle so tray keeps watchdog alive during blocking menus. */
	public static function setWatchdogPingEvent(handle:Int):Void
	{
		#if cpp
		untyped __cpp__("KC_SetWatchdogPingEvent((HANDLE)(intptr_t){0})", handle);
		#end
	}

	public static inline var CMD_SHOW_LOGS   :Int = 1001;
	public static inline var CMD_RESTART    :Int = 1002;
	public static inline var CMD_QUIT       :Int = 1003;
	public static inline var CMD_TEST_CRASH :Int = 1004;
	public static inline var CMD_TEST_HAXE_EX:Int = 1005;
}
