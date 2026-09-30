package game

// The slots of the JNI function tables the phone's vibrator calls
// (haptics_android.odin, work item 0122). A JNIEnv and a JavaVM are each
// a pointer to a pointer to a table of function pointers; these are the
// indices into those tables. Derived by counting the members of
// struct JNINativeInterface and struct JNIInvokeInterface, in order and
// from 0, in the NDK's jni.h (NDK 27.3.13750724, sysroot/usr/include).
// Each table starts with reserved slots (four and three). Only the
// functions the game calls are named; the work item's Implemented section
// lists the numbers, and jni_indices_test.odin checks them. They build on
// every platform so the test runs on the desktop.

JNI_FIND_CLASS :: 6
JNI_EXCEPTION_CLEAR :: 17
JNI_NEW_GLOBAL_REF :: 21
JNI_DELETE_GLOBAL_REF :: 22
JNI_DELETE_LOCAL_REF :: 23
JNI_GET_METHOD_ID :: 33
// The A variants take the arguments as a jvalue array, so no call from
// Odin goes through C varargs.
JNI_CALL_OBJECT_METHOD_A :: 36
JNI_CALL_BOOLEAN_METHOD_A :: 39
JNI_CALL_VOID_METHOD_A :: 63
JNI_GET_STATIC_METHOD_ID :: 113
JNI_CALL_STATIC_OBJECT_METHOD_A :: 116
JNI_NEW_STRING_UTF :: 167
JNI_EXCEPTION_CHECK :: 228

JNI_INVOKE_ATTACH_CURRENT_THREAD :: 4
JNI_INVOKE_DETACH_CURRENT_THREAD :: 5
