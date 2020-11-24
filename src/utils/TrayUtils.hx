package utils;


/**
 * ...
 * @author Tommy S.
 */

// @:headerInclude('../../../../src/utils/cpp/tray.h')
/* @:buildXml('<include name="../../src/utils/cpp/build.xml" />')
@:cppFileCode('

#include <iostream>
#include <windows.h>
#include <shellapi.h>

NOTIFYICONDATA Tray;
HWND hWnd;

') */
class TrayUtils
{
	/////////////////////////////////////////////////////////////////////////////////////

	static public function init()
	{
		// trace("hello");

		// untyped __cpp__('

		// 	NOTIFYICONDATA Tray;
		// 	HWND hWnd;

		// 	//window handle
		// 	hWnd=FindWindow("ConsoleWindowClass",NULL);

		// 	//hide the window
		// 	// ShowWindow(hWnd,0);

		// 	//tray info
		// 	Tray.cbSize=sizeof(Tray);
		// 	Tray.hIcon=LoadIcon(NULL,IDI_WINLOGO);
		// 	Tray.hWnd=hWnd;
		// 	strcpy(Tray.szTip,"My Application");
		// 	Tray.uCallbackMessage=WM_LBUTTONDOWN;
		// 	Tray.uFlags=NIF_ICON | NIF_TIP | NIF_MESSAGE;
		// 	Tray.uID=1;

		// 	//set the icon in tasbar tray
		// 	Shell_NotifyIcon(NIM_ADD, &Tray);


		// 	Sleep(5000);

		// 	//remove the icon
		// 	Shell_NotifyIcon(NIM_DELETE, &Tray);
		// 	// ShowWindow(hWnd,1);
		
		// ');
	}

	/////////////////////////////////////////////////////////////////////////////////////

	static public function createTrayIcon(title:String)
	{
/* 		untyped __cpp__('
			hWnd=FindWindow("ConsoleWindowClass",NULL);

			Tray.cbSize=sizeof(Tray);
			Tray.hIcon=LoadIcon(NULL,IDI_WINLOGO);
			Tray.hWnd=hWnd;
			strcpy(Tray.szTip,"Kontentum Client");
			Tray.uCallbackMessage=WM_LBUTTONDOWN;
			Tray.uFlags=NIF_ICON | NIF_TIP | NIF_MESSAGE;
			Tray.uID=1;

			Shell_NotifyIcon(NIM_ADD, &Tray);
		');
		 */
	}

	static public function removeTrayIcon()
	{
/* 		untyped __cpp__('
			Shell_NotifyIcon(NIM_DELETE, &Tray);
		'); */
	}

	/////////////////////////////////////////////////////////////////////////////////////
}
