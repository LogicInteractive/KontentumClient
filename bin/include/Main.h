// Generated by Haxe 3.4.3
#ifndef INCLUDED_Main
#define INCLUDED_Main

#ifndef HXCPP_H
#include <hxcpp.h>
#endif

HX_DECLARE_CLASS0(Main)
HX_DECLARE_CLASS0(Xml)
HX_DECLARE_CLASS2(cpp,vm,Thread)
HX_DECLARE_CLASS1(haxe,Timer)



class HXCPP_CLASS_ATTRIBUTES Main_obj : public hx::Object
{
	public:
		typedef hx::Object super;
		typedef Main_obj OBJ_;
		Main_obj();

	public:
		enum { _hx_ClassId = 0x332f6459 };

		void __construct();
		inline void *operator new(size_t inSize, bool inContainer=false,const char *inName="Main")
			{ return hx::Object::operator new(inSize,inContainer,inName); }
		inline void *operator new(size_t inSize, int extra)
			{ return hx::Object::operator new(inSize+extra,false,"Main"); }

		hx::ObjectPtr< Main_obj > __new() {
			hx::ObjectPtr< Main_obj > __this = new Main_obj();
			__this->__construct();
			return __this;
		}

		static hx::ObjectPtr< Main_obj > __alloc(hx::Ctx *_hx_ctx) {
			Main_obj *__this = (Main_obj*)(hx::Ctx::alloc(_hx_ctx, sizeof(Main_obj), false, "Main"));
			*(void **)__this = Main_obj::_hx_vtable;
			return __this;
		}

		static void * _hx_vtable;
		static Dynamic __CreateEmpty();
		static Dynamic __Create(hx::DynamicArray inArgs);
		//~Main_obj();

		HX_DO_RTTI_ALL;
		static bool __GetStatic(const ::String &inString, Dynamic &outValue, hx::PropertyAccess inCallProp);
		static bool __SetStatic(const ::String &inString, Dynamic &ioValue, hx::PropertyAccess inCallProp);
		static void __register();
		bool _hx_isInstanceOf(int inClassId);
		::String __ToString() const { return HX_HCSTRING("Main","\x59","\x64","\x2f","\x33"); }

		static  ::Dynamic settings;
		static  ::haxe::Timer timer;
		static  ::cpp::vm::Thread thread;
		static void main();
		static ::Dynamic main_dyn();

		static void pingThread();
		static ::Dynamic pingThread_dyn();

		static void SystemReboot();
		static ::Dynamic SystemReboot_dyn();

		static void SystemShutdown();
		static ::Dynamic SystemShutdown_dyn();

		static  ::Dynamic fromXML( ::Xml xml);
		static ::Dynamic fromXML_dyn();

		static void iterateXMLNode( ::Dynamic o, ::Xml xml);
		static ::Dynamic iterateXMLNode_dyn();

		static  ::Dynamic returnTyped(::String d);
		static ::Dynamic returnTyped_dyn();

		static bool isStringBool(::String inp);
		static ::Dynamic isStringBool_dyn();

		static bool toBool( ::Dynamic value);
		static ::Dynamic toBool_dyn();

		static bool isStringInt(::String inp);
		static ::Dynamic isStringInt_dyn();

		static bool isfirstCharNumber(::String _hx_char);
		static ::Dynamic isfirstCharNumber_dyn();

};


#endif /* INCLUDED_Main */ 
