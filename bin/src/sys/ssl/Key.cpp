// Generated by Haxe 3.4.3
#include <hxcpp.h>

#ifndef INCLUDED_sys_ssl_Key
#include <sys/ssl/Key.h>
#endif

HX_LOCAL_STACK_FRAME(_hx_pos_6b670876a45951c4_33___init__,"::sys::ssl::Key_obj","__init__",0x25088cc6,"::sys::ssl::Key_obj.__init__","C:\\HaxeToolkit\\haxe\\std/cpp/_std/sys/ssl/Key.hx",33,0x8e85032a)
namespace sys{
namespace ssl{

void Key_obj::__construct() { }

Dynamic Key_obj::__CreateEmpty() { return new Key_obj; }

void *Key_obj::_hx_vtable = 0;

Dynamic Key_obj::__Create(hx::DynamicArray inArgs)
{
	hx::ObjectPtr< Key_obj > _hx_result = new Key_obj();
	_hx_result->__construct();
	return _hx_result;
}

bool Key_obj::_hx_isInstanceOf(int inClassId) {
	return inClassId==(int)0x00000001 || inClassId==(int)0x08cf9428;
}

void Key_obj::__init__(){
            	HX_STACKFRAME(&_hx_pos_6b670876a45951c4_33___init__)
HXDLIN(  33)		_hx_ssl_init();
            	}



Key_obj::Key_obj()
{
}

void Key_obj::__Mark(HX_MARK_PARAMS)
{
	HX_MARK_BEGIN_CLASS(Key);
	HX_MARK_MEMBER_NAME(_hx___k,"__k");
	HX_MARK_END_CLASS();
}

void Key_obj::__Visit(HX_VISIT_PARAMS)
{
	HX_VISIT_MEMBER_NAME(_hx___k,"__k");
}

hx::Val Key_obj::__Field(const ::String &inName,hx::PropertyAccess inCallProp)
{
	switch(inName.length) {
	case 3:
		if (HX_FIELD_EQ(inName,"__k") ) { return hx::Val( _hx___k ); }
	}
	return super::__Field(inName,inCallProp);
}

hx::Val Key_obj::__SetField(const ::String &inName,const hx::Val &inValue,hx::PropertyAccess inCallProp)
{
	switch(inName.length) {
	case 3:
		if (HX_FIELD_EQ(inName,"__k") ) { _hx___k=inValue.Cast<  ::Dynamic >(); return inValue; }
	}
	return super::__SetField(inName,inValue,inCallProp);
}

void Key_obj::__GetFields(Array< ::String> &outFields)
{
	outFields->push(HX_HCSTRING("__k","\x4b","\x69","\x48","\x00"));
	super::__GetFields(outFields);
};

#if HXCPP_SCRIPTABLE
static hx::StorageInfo Key_obj_sMemberStorageInfo[] = {
	{hx::fsObject /*Dynamic*/ ,(int)offsetof(Key_obj,_hx___k),HX_HCSTRING("__k","\x4b","\x69","\x48","\x00")},
	{ hx::fsUnknown, 0, null()}
};
static hx::StaticInfo *Key_obj_sStaticStorageInfo = 0;
#endif

static ::String Key_obj_sMemberFields[] = {
	HX_HCSTRING("__k","\x4b","\x69","\x48","\x00"),
	::String(null()) };

static void Key_obj_sMarkStatics(HX_MARK_PARAMS) {
	HX_MARK_MEMBER_NAME(Key_obj::__mClass,"__mClass");
};

#ifdef HXCPP_VISIT_ALLOCS
static void Key_obj_sVisitStatics(HX_VISIT_PARAMS) {
	HX_VISIT_MEMBER_NAME(Key_obj::__mClass,"__mClass");
};

#endif

hx::Class Key_obj::__mClass;

void Key_obj::__register()
{
	hx::Object *dummy = new Key_obj;
	Key_obj::_hx_vtable = *(void **)dummy;
	hx::Static(__mClass) = new hx::Class_obj();
	__mClass->mName = HX_HCSTRING("sys.ssl.Key","\x7c","\x13","\xb6","\xc7");
	__mClass->mSuper = &super::__SGetClass();
	__mClass->mConstructEmpty = &__CreateEmpty;
	__mClass->mConstructArgs = &__Create;
	__mClass->mGetStaticField = &hx::Class_obj::GetNoStaticField;
	__mClass->mSetStaticField = &hx::Class_obj::SetNoStaticField;
	__mClass->mMarkFunc = Key_obj_sMarkStatics;
	__mClass->mStatics = hx::Class_obj::dupFunctions(0 /* sStaticFields */);
	__mClass->mMembers = hx::Class_obj::dupFunctions(Key_obj_sMemberFields);
	__mClass->mCanCast = hx::TCanCast< Key_obj >;
#ifdef HXCPP_VISIT_ALLOCS
	__mClass->mVisitFunc = Key_obj_sVisitStatics;
#endif
#ifdef HXCPP_SCRIPTABLE
	__mClass->mMemberStorageInfo = Key_obj_sMemberStorageInfo;
#endif
#ifdef HXCPP_SCRIPTABLE
	__mClass->mStaticStorageInfo = Key_obj_sStaticStorageInfo;
#endif
	hx::_hx_RegisterClass(__mClass->mName, __mClass);
}

void Key_obj::__boot()
{
}

} // end namespace sys
} // end namespace ssl
