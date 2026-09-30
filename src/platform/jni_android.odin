#+build linux:android
package platform

// The JNI helpers the vibrator (haptics_android.odin in the game package,
// work item 0122) and the export's All files access check
// (export_access_android.odin, work item 0131) call through. The game
// thread is raylib's android_main thread, which the VM does not know, so
// every use attaches it first: attaching an attached thread only returns
// its JNIEnv, and raylib's GetCurrentMonitor (rcore_android.c, called by
// current_monitor_size) detaches the thread when it is done, so an
// environment kept across frames could be stale. The references and
// method ids stay valid across a detach. Local references are never freed
// by a return to Java on this thread, so every one is deleted by hand.
// The table indices are in jni_indices.odin.

JNI_OK :: 0

// jvalue (jni.h): one argument of a Call...MethodA.
Jni_Value :: struct #raw_union {
	integer: i32,
	long:    i64,
	object:  rawptr,
}

Jni_Attach_Current_Thread :: #type proc "c" (vm: rawptr, environment: ^rawptr, arguments: rawptr) -> i32
Jni_Detach_Current_Thread :: #type proc "c" (vm: rawptr) -> i32
Jni_Find_Class :: #type proc "c" (environment: rawptr, name: cstring) -> rawptr
Jni_Get_Method_Id :: #type proc "c" (environment, class: rawptr, name, signature: cstring) -> rawptr
Jni_Call_Object_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value) -> rawptr
Jni_Call_Boolean_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value) -> u8
Jni_Call_Void_Method :: #type proc "c" (environment, object, method: rawptr, arguments: [^]Jni_Value)
Jni_New_String_Utf :: #type proc "c" (environment: rawptr, text: cstring) -> rawptr
Jni_New_Reference :: #type proc "c" (environment, object: rawptr) -> rawptr
Jni_Delete_Reference :: #type proc "c" (environment, object: rawptr)
Jni_Exception_Check :: #type proc "c" (environment: rawptr) -> u8
Jni_Exception_Clear :: #type proc "c" (environment: rawptr)

// An environment and the first call that failed in a run of calls: after
// a failure every further call does nothing and returns nil.
Jni_Calls :: struct {
	environment: rawptr,
	failed:      cstring,
}

// Slot index of the function table a JNIEnv or a JavaVM points at.
jni_function :: proc(table_owner: rawptr, index: int) -> rawptr {
	return (cast(^[^]rawptr)table_owner)^[index]
}

// This thread's JNIEnv, attaching the thread when it is not; nil when the
// VM refuses.
jni_environment :: proc() -> rawptr {
	vm := GetAndroidApp().activity.vm
	attach := cast(Jni_Attach_Current_Thread)jni_function(vm, JNI_INVOKE_ATTACH_CURRENT_THREAD)
	environment: rawptr
	if attach(vm, &environment, nil) != JNI_OK {
		return nil
	}
	return environment
}

// Clears a pending exception and records the call as failed when one was
// thrown or the call gave no object.
jni_checked :: proc(calls: ^Jni_Calls, result: rawptr, what: cstring, needs_result := true) -> rawptr {
	check := cast(Jni_Exception_Check)jni_function(calls.environment, JNI_EXCEPTION_CHECK)
	if check(calls.environment) != 0 {
		clear_exception := cast(Jni_Exception_Clear)jni_function(calls.environment, JNI_EXCEPTION_CLEAR)
		clear_exception(calls.environment)
		calls.failed = what
		return nil
	}
	if needs_result && result == nil {
		calls.failed = what
	}
	return result
}

jni_find_class :: proc(calls: ^Jni_Calls, name: cstring) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	find_class := cast(Jni_Find_Class)jni_function(calls.environment, JNI_FIND_CLASS)
	return jni_checked(calls, find_class(calls.environment, name), name)
}

jni_method :: proc(calls: ^Jni_Calls, class: rawptr, name, signature: cstring, is_static := false) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	index := is_static ? JNI_GET_STATIC_METHOD_ID : JNI_GET_METHOD_ID
	get_method := cast(Jni_Get_Method_Id)jni_function(calls.environment, index)
	return jni_checked(calls, get_method(calls.environment, class, name, signature), name)
}

jni_call_object :: proc(calls: ^Jni_Calls, object, method: rawptr, arguments: []Jni_Value, what: cstring, is_static := false) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	index := is_static ? JNI_CALL_STATIC_OBJECT_METHOD_A : JNI_CALL_OBJECT_METHOD_A
	call := cast(Jni_Call_Object_Method)jni_function(calls.environment, index)
	return jni_checked(calls, call(calls.environment, object, method, raw_data(arguments)), what)
}

jni_call_boolean :: proc(calls: ^Jni_Calls, object, method: rawptr, what: cstring) -> bool {
	if calls.failed != nil {
		return false
	}
	call := cast(Jni_Call_Boolean_Method)jni_function(calls.environment, JNI_CALL_BOOLEAN_METHOD_A)
	result := call(calls.environment, object, method, nil)
	jni_checked(calls, nil, what, needs_result = false)
	return calls.failed == nil && result != 0
}

jni_call_void :: proc(calls: ^Jni_Calls, object, method: rawptr, arguments: []Jni_Value, what: cstring) {
	if calls.failed != nil {
		return
	}
	call := cast(Jni_Call_Void_Method)jni_function(calls.environment, JNI_CALL_VOID_METHOD_A)
	call(calls.environment, object, method, raw_data(arguments))
	jni_checked(calls, nil, what, needs_result = false)
}

jni_new_string :: proc(calls: ^Jni_Calls, text: cstring) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	new_string := cast(Jni_New_String_Utf)jni_function(calls.environment, JNI_NEW_STRING_UTF)
	return jni_checked(calls, new_string(calls.environment, text), "NewStringUTF")
}

jni_new_global_reference :: proc(calls: ^Jni_Calls, object: rawptr) -> rawptr {
	if calls.failed != nil {
		return nil
	}
	new_reference := cast(Jni_New_Reference)jni_function(calls.environment, JNI_NEW_GLOBAL_REF)
	return jni_checked(calls, new_reference(calls.environment, object), "NewGlobalRef")
}

// Deleting nil is allowed by JNI, so a run that failed half way cleans up
// the same way.
jni_delete_reference :: proc(environment, object: rawptr, index := JNI_DELETE_LOCAL_REF) {
	delete_reference := cast(Jni_Delete_Reference)jni_function(environment, index)
	delete_reference(environment, object)
}
