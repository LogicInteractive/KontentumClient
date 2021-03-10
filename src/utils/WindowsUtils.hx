package utils;

import client.ServerCommunicator;
import cpp.Char;
import cpp.ConstCharStar;
import cpp.ConstPointer;
import cpp.Lib;
import cpp.Native;
import cpp.NativeArray;
import cpp.NativeSocket;
import cpp.NativeString;
import cpp.RawConstPointer;
import cpp.Reference;
import haxe.CallStack;
import haxe.Http;
import haxe.Json;
import haxe.Timer;
import haxe.io.Bytes;
import haxe.io.Output;
import haxe.macro.Expr.Error;
import no.logic.fox.hwintegration.windows.Chrome;
import sys.FileSystem;
import sys.io.File;
import sys.io.FileOutput;
import sys.net.Host;


/**
 * ...
 * @author Tommy S.
 */

typedef NetworkAdapterInfo =
{
	@:optional	var ip			: String;
	@:optional	var mac			: String;
	@:optional	var hostname	: String;
}

#if windows
@:cppFileCode('
#include <winsock2.h>
#include <iostream>
#include <fstream>
#include <string.h>
#include <windows.h>
#pragma comment(lib, "winmm")

#pragma comment(lib, "PowrProf.lib")
#include <powrprof.h>

#pragma comment(lib, "iphlpapi.lib")
#include <Iphlpapi.h>

#include <endpointvolume.h>
#include <mmdeviceapi.h>
#pragma comment(lib, "Ole32")

/*
#ifndef max
#define max(a,b) (((a) > (b)) ? (a) : (b))
#else
#error max macro is already defined
#endif
#ifndef min
#define min(a,b) (((a) < (b)) ? (a) : (b))
#else
#error min macro is already defined
#endif

// #include <afxstr.h>
#include <gdiplus.h>
#include <atlimage.h>
#undef min
#undef max
#undef byte

// using namespace Gdiplus;
// #pragma comment (lib,"Gdiplus.lib")
using namespace std;
*/
// int getEncoderClsid(const wchar_t *format, CLSID *pClsid)
// {
//   UINT num = 0;   /* number of image encoders */
//   UINT size = 0;  /* size of the image encoder array in bytes */

//   Gdiplus::ImageCodecInfo *pImageCodecInfo = NULL;

//   Gdiplus::GetImageEncodersSize(&num, &size);
//   if (size == 0) {
//     return -1;  /* Failure */
//   }

//   pImageCodecInfo = (Gdiplus::ImageCodecInfo *)(malloc(size));
//   if (pImageCodecInfo == NULL) {
//     return -1;  /* Failure */
//   }

//   GetImageEncoders(num, size, pImageCodecInfo);

//   for (UINT j = 0; j < num; ++j) {
//     if (wcscmp(pImageCodecInfo[j].MimeType, format) == 0 ) {
//       *pClsid = pImageCodecInfo[j].Clsid;
//       free(pImageCodecInfo);
//       return j;  /* Success */
//     }
//   }

//   free(pImageCodecInfo);
//   return -1;  /* Failure */
// }

// int screenshotSaveBitmap(Gdiplus::Bitmap *b, const wchar_t *filename, const wchar_t *format, long quality)
// {
//   if (filename == NULL) {
//     return -1;  /* Failure */
//   }

//   CLSID encoderClsid;
//   Gdiplus::EncoderParameters encoderParameters;
//   Gdiplus::Status stat = Gdiplus::GenericError;

//   if (b) {
//     if (getEncoderClsid(format, &encoderClsid) != -1) {
//       if (quality >= 0 && quality <= 100 && wcscmp(format, L"image/jpeg") == 0) {
//         encoderParameters.Count = 1;
//         encoderParameters.Parameter[0].Guid = Gdiplus::EncoderQuality;
//         encoderParameters.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
//         encoderParameters.Parameter[0].NumberOfValues = 1;
//         encoderParameters.Parameter[0].Value = &quality;
//         stat = b->Save(filename, &encoderClsid, &encoderParameters);
//       } else {
//         stat = b->Save(filename, &encoderClsid, NULL);
//       }
//     }
//     delete b;
//   }

//   return (stat == Gdiplus::Ok) ? 0 : 1;
// }
')
#elseif linux
@:cppFileCode('
#include <stdio.h>
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <string.h>
#include <iostream>
#include <netdb.h>
#include <sys/param.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <fstream>
#include <ifaddrs.h>
#include <net/if.h> 
#include <unistd.h>
#include <netpacket/packet.h>
')
#end
//@:buildXml('<include name="../../src/utils/cpp/build.xml" />')
class WindowsUtils
{
	/////////////////////////////////////////////////////////////////////////////////////

	static var subProcess			: SubProcess;
	static var isExplorerKilled		: Bool;

	/////////////////////////////////////////////////////////////////////////////////////
	//===================================================================================
	// SystemFunctions 
	//-----------------------------------------------------------------------------------
	
	static public function systemReboot() 
	{
		if (subProcess!=null)
			subProcess.forceQuitNoRestart();
			
		#if windows
		Sys.command("shutdown", ["/r", "/f", "/t", "0"]);
		#elseif (linux || mac)
		Sys.command("sudo reboot");
		#end
		
		//#end
	}
	
	static public function systemShutdown() 
	{
		if (subProcess!=null)
			subProcess.forceQuitNoRestart();

		#if windows
		Sys.command("shutdown",["/s","/f","/t","0"]);
		#elseif (linux || mac)
		Sys.command("sudo shutdown -P");
		#end
	}
	
	static public function systemSleep(bHibernate:Bool=false,bWakeupEventsDisabled:Bool=false)
	{
		#if windows		
		setSuspendState(bHibernate,false,bWakeupEventsDisabled);
		#end
	}
	
	static public function killExplorer() 
	{
		#if windows
		isExplorerKilled = true;
		Sys.command("taskkill",["/F","/IM","explorer.exe"]);
		#end
	}
	
	static public function launchExplorer() 
	{
		#if windows
		if (isExplorerKilled)
		{
			Sys.command("explorer.exe");
			isExplorerKilled = false;
		}
		#end
	}

	
	//old
/* 	static public function runProcess(exeName:String, hidden:Bool=false)
	{
		if (!hidden)
			untyped __cpp__('WinExec(exeName, SW_SHOW)');
		else
			untyped __cpp__('WinExec(exeName, SW_HIDE)');
	}
 */	
	/////////////////////////////////////////////////////////////////////////////////////

	//===================================================================================
	// Utils
	//-----------------------------------------------------------------------------------
	
	static public function setPersistentProcess(exeName:String)
	{
		if (exeName==null || exeName=="")
			return;

		if (subProcess != null)
			subProcess.terminate();
			
		subProcess = new SubProcess(exeName);
		subProcess.launchDelay = 0;
		// subProcess.monitor = KontentumClient.config.appMonitor;
		subProcess.restartDelay = KontentumClient.config.kontentum.restartdelay;
		subProcess.subprocessDidCrash = subprocessDidCrash;
		subProcess.subprocessDidExit = subprocessDidExit;
		var success = subProcess.run();
		
		if (!success)
			if (KontentumClient.debug)
				trace("process failed to start....");
	}	
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static function subprocessDidCrash() 
	{
		if (KontentumClient.debug)
			trace("Subprocess crashes. Restarting.");
		// Network.i.submitAction("APP_CRASH");
	}
	
	static function subprocessDidExit() 
	{
		if (KontentumClient.debug)
			trace("Subprocess exited. Restarting.");
		//NetworkHandler.i.submitAction("APP_EXIT");
	}	
	
	/////////////////////////////////////////////////////////////////////////////////////
	
	static public function handleRestart() 
	{
		if (subProcess != null)
			subProcess.restart();
	}	

	static public function handleQuit() 
	{
		if (subProcess != null)
		{
			subProcess.forceQuitNoRestart();
		}
		if (Chrome.isRunning)
			Chrome.kill();
			
		launchExplorer();
	}	

	/////////////////////////////////////////////////////////////////////////////////////

	static public inline var ADAPTER_TYPE_ANY			: Int		= 0;
	static public inline var ADAPTER_TYPE_ETHERNET		: Int		= 6;
	static public inline var ADAPTER_TYPE_WIFI			: Int		= 71;

	/////////////////////////////////////////////////////////////////////////////////////

	static public function getNetworkAdapterInfo(adaptertype:Int):NetworkAdapterInfo
	{
		#if windows
		var ip:ConstPointer<Char> = null;
		var mac:ConstPointer<Char> = null;

		untyped __cpp__('
		
			PIP_ADAPTER_INFO AdapterInfo;
			DWORD dwBufLen = sizeof(AdapterInfo);
			char* mac_addr = (char*)malloc(17);
			std::string ipstr;

			AdapterInfo = (IP_ADAPTER_INFO*) malloc(sizeof(IP_ADAPTER_INFO));
			
			if (AdapterInfo != NULL)
			{
				if (GetAdaptersInfo(AdapterInfo, & dwBufLen) == ERROR_BUFFER_OVERFLOW)
				{
					AdapterInfo = (IP_ADAPTER_INFO*) malloc(dwBufLen);
					if (AdapterInfo != NULL)
					{
						if (GetAdaptersInfo(AdapterInfo, & dwBufLen) == NO_ERROR)
						{
							PIP_ADAPTER_INFO pAdapterInfo = AdapterInfo;// Contains pointer to current adapter info
							do
							{
								//Prints mac-adress to a string..
								sprintf(mac_addr, "%02X:%02X:%02X:%02X:%02X:%02X", pAdapterInfo->Address[0], pAdapterInfo->Address[1], pAdapterInfo->Address[2], pAdapterInfo->Address[3], pAdapterInfo->Address[4], pAdapterInfo->Address[5]);
								//printf("Address: %s, mac: %s\\n", pAdapterInfo->IpAddressList.IpAddress.String, mac_addr);
								
								if (adaptertype == pAdapterInfo->Type || adaptertype == 0) // Is adapter type matching? 6 : Ethernet, 71 : Wifi
								{
									mac = mac_addr;
									ip = pAdapterInfo->IpAddressList.IpAddress.String;
									if ((int)ip[0] != 48) //Is first char in ip string "0" ? If not, break!
										break;
								}
								pAdapterInfo = pAdapterInfo->Next;        
							}
							while(pAdapterInfo);                        
						}
					}
				}
			}
			free(AdapterInfo);
		');
		return { ip:NativeString.fromPointer(ip), mac:NativeString.fromPointer(mac), hostname:Sys.getEnv("COMPUTERNAME") };
		#elseif linux

		var ip:String = "";
		var mac:String = "";

		// Get Local IP
		untyped __cpp__('
			struct ifaddrs * ifAddrStruct=NULL;
			struct ifaddrs * ifa=NULL;
			void * tmpAddrPtr=NULL;

			getifaddrs(&ifAddrStruct);

			for (ifa = ifAddrStruct; ifa != NULL; ifa = ifa->ifa_next)
			{
				if (!ifa->ifa_addr)
				{
					continue;
				}
				if (ifa->ifa_addr->sa_family == AF_INET) //IP4
				{
					tmpAddrPtr=&((struct sockaddr_in *)ifa->ifa_addr)->sin_addr;
					char addressBuffer[INET_ADDRSTRLEN];
					inet_ntop(AF_INET, tmpAddrPtr, addressBuffer, INET_ADDRSTRLEN);
					ip = addressBuffer;
				}
			}
			if (ifAddrStruct!=NULL) 
				freeifaddrs(ifAddrStruct);
		');

		// Find mac adress
		var foundMac:Bool = false;
		untyped __cpp__('
			int fd;
			struct ifreq ifr;
			char const *iface = "enp0s3";
			unsigned char *maca = NULL;

			memset(&ifr, 0, sizeof(ifr));
			fd = socket(AF_INET, SOCK_DGRAM, 0);
			ifr.ifr_addr.sa_family = AF_INET;
			strncpy(ifr.ifr_name , iface , IFNAMSIZ-1);

			if (0 == ioctl(fd, SIOCGIFHWADDR, &ifr))
			{
				maca = (unsigned char *)ifr.ifr_hwaddr.sa_data;
				foundMac=true;
			}
			close(fd);
		');
		if (foundMac)
		{
			mac=StringTools.hex(untyped __cpp__('maca[0]'),2);
			mac+=":"+StringTools.hex(untyped __cpp__('maca[1]'),2);
			mac+=":"+StringTools.hex(untyped __cpp__('maca[2]'),2);
			mac+=":"+StringTools.hex(untyped __cpp__('maca[3]'),2);
			mac+=":"+StringTools.hex(untyped __cpp__('maca[4]'),2);
			mac+=":"+StringTools.hex(untyped __cpp__('maca[5]'),2);
		}

		return { ip:ip, mac:mac, hostname:Host.localhost() };
		#else
		return { ip:"", mac:"", hostname:"" };
		#end
	}

	/////////////////////////////////////////////////////////////////////////////////////


	static public function setVolume(newVolume:Float)
	{		
		#if windows
		untyped __cpp__('
			HRESULT hr=NULL;

			CoInitialize(NULL);
			IMMDeviceEnumerator *deviceEnumerator = NULL; 
			hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_INPROC_SERVER, __uuidof(IMMDeviceEnumerator), (LPVOID *)&deviceEnumerator);
			IMMDevice *defaultDevice = NULL;

			hr = deviceEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &defaultDevice);
			deviceEnumerator->Release();
			deviceEnumerator = NULL;

			IAudioEndpointVolume *endpointVolume = NULL;
			hr = defaultDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_INPROC_SERVER, NULL, (LPVOID *)&endpointVolume);
			defaultDevice->Release();
			defaultDevice = NULL;

			hr = endpointVolume->SetMasterVolumeLevelScalar((float)newVolume, NULL);
			endpointVolume->Release();

			CoUninitialize();
		');
		#elseif linux
		var pstVol:Int = Std.int(newVolume*31);
		//Requires alsa-utils to be installed : "sudo apt-get install alsa-utils"
		Sys.command('amixer --quiet set Master $pstVol');
		#end
	}


	
	
	static public function getVolume():Float
	{		
		var rVolume:Float = -1;
		
		#if windows
		untyped __cpp__('
			HRESULT hr=NULL;

			CoInitialize(NULL);
			IMMDeviceEnumerator *deviceEnumerator = NULL; 
			hr = CoCreateInstance(__uuidof(MMDeviceEnumerator), NULL, CLSCTX_INPROC_SERVER, __uuidof(IMMDeviceEnumerator), (LPVOID *)&deviceEnumerator);
			IMMDevice *defaultDevice = NULL;

			hr = deviceEnumerator->GetDefaultAudioEndpoint(eRender, eConsole, &defaultDevice);
			deviceEnumerator->Release();
			deviceEnumerator = NULL;

			IAudioEndpointVolume *endpointVolume = NULL;
			hr = defaultDevice->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_INPROC_SERVER, NULL, (LPVOID *)&endpointVolume);
			defaultDevice->Release();
			defaultDevice = NULL;

			float currentVolume = 0;
			endpointVolume->GetMasterVolumeLevel(&currentVolume);
			hr = endpointVolume->GetMasterVolumeLevelScalar(&currentVolume);
			endpointVolume->Release();

			CoUninitialize();
			rVolume = (Float)currentVolume;
		');
		#elseif linux
		//Requires alsa-utils to be installed : "sudo apt-get install alsa-utils"
		rVolume = Std.parseFloat(new sys.io.Process("amixer -D pulse get Master | awk -F 'Left:|[][]' 'BEGIN "+'{RS=""} '+"{ print $3 }'", []).stdout.readAll().toString().split("%").join(""));
		#end
		return rVolume;
	}

	static public function takeScreenshot()
	{
		/*
		var screenshotGdiplusToken:UlongPtr = null;
		var screenshotGdiplusStartupInput:GdiplusStartupInput = null;
		Gdiplus.startUp(Native.addressOf(screenshotGdiplusToken),Native.addressOf(screenshotGdiplusStartupInput),null);

		var filename:ConstStarWCharT = untyped __cpp__('L"screenshot.png"');
		var format:ConstStarWCharT = untyped __cpp__('L"png"');
		var encoder:ConstStarWCharT = untyped __cpp__('L"image/png"');
		var quality:Int = -1;

		var desktop:HWND = getDesktopWindow();
		var desktopDeviceContext:HDC = getDC(desktop);
		var compatdeviceContext:HDC = createCompatibleDC(desktopDeviceContext);
		var width:Int = getSystemMetrics(SystemMetrics.SM_CXSCREEN);
		var height:Int = getSystemMetrics(SystemMetrics.SM_CYSCREEN);
		var newbmp:HBITMAP = createCompatibleBitmap(desktopDeviceContext, width, height);
		var oldbmp:HBITMAP = cast selectObject(compatdeviceContext, newbmp);

		bitBlt(compatdeviceContext,0,0,width,height,desktopDeviceContext, 0, 0, untyped SRCCOPY|CAPTUREBLT);
		selectObject(compatdeviceContext, oldbmp);
		var b:cpp.Star<GdiBitmap> = Gdiplus.fromHBITMAP(newbmp, null);

		releaseDC(desktop, desktopDeviceContext);
		deleteObject(newbmp);
		deleteDC(compatdeviceContext);

		screenshotSaveBitmap(b, filename, encoder, quality);

		Gdiplus.shutdown(screenshotGdiplusToken);
		*/
	}

	/////////////////////////////////////////////////////////////////////////////////////

	// @:native("screenshotSaveBitmap")			extern static public function screenshotSaveBitmap(b:cpp.Star<GdiBitmap>, filename:ConstStarWCharT, format:ConstStarWCharT, quality:Int):Int;

	/////////////////////////////////////////////////////////////////////////////////////

	#if windows

	@:native("SetSuspendState")					extern static public function setSuspendState(bHibernate:Bool=false,bForce:Bool,bWakeupEventsDisabled:Bool=false):Bool;
	@:native("SetConsoleTitle")					extern static public function setConsoleTitle(title:String):Void;
	@:native("FreeConsole")						extern static public function freeConsole():Bool;
	@:native("AllocConsole")					extern static public function allocConsole():Bool;
	@:native("GetDesktopWindow")				extern static public function getDesktopWindow():HWND;
	@:native("GetDC")							extern static public function getDC(handle:HWND):HDC;
	@:native("CreateCompatibleDC")				extern static public function createCompatibleDC(hdc:HDC):HDC;
	@:native("GetSystemMetrics")				extern static public function getSystemMetrics(nIndex:SystemMetrics):Int;
	@:native("CreateCompatibleBitmap")			extern static public function createCompatibleBitmap(hdc:HDC,cx:Int,cy:Int):HBITMAP;
	@:native("SelectObject")					extern static public function selectObject(hdc:HDC,h:HBITMAP):HGDIOBJ;
	@:native("ReleaseDC")						extern static public function releaseDC(hWnd:HWND,hDC:HDC):Int;
	@:native("DeleteObject")					extern static public function deleteObject(ho:HBITMAP):Bool;
	@:native("DeleteDC")						extern static public function deleteDC(hdc:HDC):Bool;
	@:native("BitBlt")							extern static public function bitBlt(hdc:HDC,x:Int,y:Int,cx:Int,cy:Int,hdcSrc:HDC,x1:Int,y1:Int,rop:DWord):Bool;
	#end

	/////////////////////////////////////////////////////////////////////////////////////
}

/* extern class Gdiplus
{
	@:native("Gdiplus::GdiplusStartup")			static public function startUp(screenshotGdiplusToken:cpp.Star<UlongPtr>, screenshotGdiplusStartupInput:cpp.ConstStar<GdiplusStartupInput>, output:cpp.Star<GdiplusStartupOutput>):Int;
	@:native("Gdiplus::GdiplusShutdown")		static public function shutdown(screenshotGdiplusToken:UlongPtr):Int;
	@:native("Gdiplus::Bitmap::FromHBITMAP")	static public function fromHBITMAP(hbm:HBITMAP,hpal:HPALETTE):cpp.Star<GdiBitmap>;
} */

@:native("DWORD") 								extern class DWord {}
@:native("ULONG_PTR") 							extern class UlongPtr {}
@:native("HWND") 								extern class HWND {}
@:native("HDC") 								extern class HDC {}
// @:native("Gdiplus::GdiplusStartupInput") 		extern class GdiplusStartupInput {}
// @:native("Gdiplus::GdiplusStartupOutput") 		extern class GdiplusStartupOutput {}
// @:native("Gdiplus::Bitmap") 					extern class GdiBitmap {}
@:native("HBITMAP") 							extern class HBITMAP {}
@:native("HGDIOBJ")								extern class HGDIOBJ {}
@:native("HPALETTE") 							extern class HPALETTE {}
@:native("const wchar_t *") 					extern class ConstStarWCharT {}

//https://docs.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getsystemmetrics
enum abstract SystemMetrics(Int)
{
	var SM_CXSCREEN = 0;
	var SM_CYSCREEN = 1;
}
