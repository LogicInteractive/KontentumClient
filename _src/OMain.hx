package;

/**
 * ...
 * @author Tommy S.
 */
@:cppFileCode('
#define WIN32_LEAN_AND_MEAN		// Exclude rarely-used stuff from Windows headers

#include<windows.h>
#include<shellapi.h>
#include<iostream>	
#include <map>
#include <string>
//#include "../../src/cpp/tray.h"
#include "../../src/cpp/tray.cpp"

using namespace std;

NOTIFYICONDATA Tray;
HWND hWnd;

/*  Declare Windows procedure  */
LRESULT CALLBACK WindowProcedure (HWND, UINT, WPARAM, LPARAM);

/*  Class name and window title  */
char szClassName[ ] = "Tray It :P";
char szTitleText[ ] = "Right click, plz :)";

EXTERN_C IMAGE_DOS_HEADER __ImageBase;

#define HINST_THISCOMPONENT ((HINSTANCE) & __ImageBase)

#define TEST_ICON       0 //icon

LRESULT CALLBACK WindowProcedure (HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam)
{
    switch (message)
    {
		case WM_CREATE:{       
            TRAY_Init(hwnd); // Create tray icon and popup menu              
		}break;
    	case WM_SIZE:
    	     OnSizeTray(wParam); // Minimize/Restore to/from tray
        break;            
    	case WM_NOTIFYICONTRAY:
    	     OnNotifyTray(lParam); // Manages message from tray
        return TRUE;       
    	case WM_COMMAND:
	    { 
          // Manage popup menu message (before switch statement)
          if (OnCommandTrayMenu(wParam)) break;
          
//	      switch(LOWORD(wParam))
//	      {
//	              //Another way (into switch statement)	          
//                case IDM_MINIMIZE:
//                case IDM_ONTOP:
//                case IDM_ABOUT:
//                case IDM_CLOSE:
//                    OnCommandTrayMenu(wParam);
//                break;
//                case IDC_SOMETHING: // other command events...
//                break;  
//	      }//end switch(LOWORD(wParam))	
	      
	      //Still another way (after switch statement)
          //OnCommandTrayMenu(wParam);
	      
	    }break;//end WM_COMMAND	     
	    case WM_RBUTTONDOWN:{          
	        TRAY_Menu_Show();//load POPUP menu in main window (why?)
        }break;
	    case WM_LBUTTONDOWN:{          
	        MessageBox(hwnd,MY_MSG,"Info",MB_ICONINFORMATION);
        }break;                           
        case WM_DESTROY:
            OnDestroyTray();//Clean Tray related
            PostQuitMessage (0);       // send a WM_QUIT to the message queue
            break;
        default:                      // for messages that we dont deal with
            return DefWindowProc (hwnd, message, wParam, lParam);
    }

    return 0;
}



')
@:buildXml("
<target id='haxe'>
	<lib name='${HXCPP}/lib/${BINDIR}/libstd${LIBEXTRA}${LIBEXT}'/>
	<lib name='shell32.lib' if='windows' unless='static_link' />
	<lib name='Kernel32.lib' if='windows' unless='static_link' />
</target>
<files id='haxe'>
	<file name='C:/projects/Logic/KontentumClient/build/src/Traytest.rc' if='windows' />
</files>
")
class Main 
{
	//===================================================================================
	// Main 
	//-----------------------------------------------------------------------------------
	
	/////////////////////////////////////////////////////////////////////////////////////

	static function main() 
	{
		//new Client("config.xml");
		
		var hupp = haxe.Resource.getBytes("TEST_ICON");
		untyped __cpp__('
		
/*			cout<<"Window will be minimised in system tray for 10 seconds and reappear.";
			Sleep(2000);

			//window handle
			hWnd=FindWindow("ConsoleWindowClass",NULL);

			//hide the window
			ShowWindow(hWnd,0);

			//tray info
			Tray.cbSize=sizeof(Tray);
			Tray.hIcon=LoadIcon(NULL,IDI_WINLOGO);
			Tray.hWnd=hWnd;
			strcpy(Tray.szTip,"My Application");
			Tray.uCallbackMessage=WM_LBUTTONDOWN;
			Tray.uFlags=NIF_ICON | NIF_TIP | NIF_MESSAGE;
			Tray.uID=1;

			//set the icon in tasbar tray
			Shell_NotifyIcon(NIM_ADD, &Tray);

			
			Sleep(10000);

			//remove the icon
			Shell_NotifyIcon(NIM_DELETE, &Tray);
			ShowWindow(hWnd,1);*/
			
			
			HWND hwnd;               /* This is the handle for our window */
			MSG messages;            /* Here messages to the application are saved */
			WNDCLASSEX wincl;        /* Data structure for the windowclass */

			/* The Window structure */
			wincl.hInstance = HINST_THISCOMPONENT;
			wincl.lpszClassName = szClassName;
			wincl.lpfnWndProc = WindowProcedure;      /* This function is called by windows */
			wincl.style = CS_DBLCLKS;                 /* Catch double-clicks */
			wincl.cbSize = sizeof (WNDCLASSEX);

			/* Use default icon and mouse-pointer */
			wincl.hIcon = LoadIcon (NULL, IDI_APPLICATION);
			wincl.hIconSm = LoadIcon (NULL, IDI_APPLICATION);
			wincl.hCursor = LoadCursor (NULL, IDC_ARROW);
			wincl.lpszMenuName = NULL;                 /* No menu */
			wincl.cbClsExtra = 0;                      /* No extra bytes after the window class */
			wincl.cbWndExtra = 0;                      /* structure or the window instance */
			
			wincl.hbrBackground = (HBRUSH) COLOR_3DSHADOW; //COLOR_BACKGROUND;

			/* Register the window class, and if it fails quit the program */
			if (!RegisterClassEx (&wincl))
				return;
			
			/* The class is registered, lets create the program*/
			hwnd = CreateWindowEx (
				   0,                   /* Extended possibilites for variation */
				   szClassName,         /* Classname */
				   szTitleText,         /* Title Text */
				   WS_OVERLAPPEDWINDOW, /* default window */
				   CW_USEDEFAULT,       /* Windows decides the position */
				   CW_USEDEFAULT,       /* where the window ends up on the screen */
				   230,                 /* The programs width */
				   200,                 /* and height in pixels */
				   HWND_DESKTOP,        /* The window is a child-window to desktop */
				   NULL,                /* No menu */
				   HINST_THISCOMPONENT, /* Program Instance handler */
				   NULL                 /* No Window Creation data */
				   );

				/* Make the window visible on the screen */
				ShowWindow(hwnd, SW_SHOW);

				/* Run the message loop. It will run until GetMessage() returns 0 */
				while (GetMessage (&messages, NULL, 0, 0))
				{
					/* Translate virtual-key messages into character messages */
					TranslateMessage(&messages);
					/* Send message to WindowProcedure */
					DispatchMessage(&messages);
				}

				/* The program return-value is 0 - The value that PostQuitMessage() gave */
				//return messages.wParam;				
					
		
		');
	}
	
	/////////////////////////////////////////////////////////////////////////////////////
}

