package platform

import "core:testing"

// The numbers written down from jni.h in doc/work/0122-android-haptics.md
// (Implemented) and doc/work/0131-export-data-files.md (Implementation
// notes), so a changed constant fails here.
@(test)
test_jni_indices_match_the_header :: proc(t: ^testing.T) {
	testing.expect_value(t, JNI_FIND_CLASS, 6)
	testing.expect_value(t, JNI_EXCEPTION_CLEAR, 17)
	testing.expect_value(t, JNI_NEW_GLOBAL_REF, 21)
	testing.expect_value(t, JNI_DELETE_GLOBAL_REF, 22)
	testing.expect_value(t, JNI_DELETE_LOCAL_REF, 23)
	testing.expect_value(t, JNI_NEW_OBJECT_A, 30)
	testing.expect_value(t, JNI_GET_METHOD_ID, 33)
	testing.expect_value(t, JNI_CALL_OBJECT_METHOD_A, 36)
	testing.expect_value(t, JNI_CALL_BOOLEAN_METHOD_A, 39)
	testing.expect_value(t, JNI_CALL_VOID_METHOD_A, 63)
	testing.expect_value(t, JNI_GET_STATIC_METHOD_ID, 113)
	testing.expect_value(t, JNI_CALL_STATIC_OBJECT_METHOD_A, 116)
	testing.expect_value(t, JNI_CALL_STATIC_BOOLEAN_METHOD_A, 119)
	testing.expect_value(t, JNI_NEW_STRING_UTF, 167)
	testing.expect_value(t, JNI_EXCEPTION_CHECK, 228)
	testing.expect_value(t, JNI_INVOKE_ATTACH_CURRENT_THREAD, 4)
	testing.expect_value(t, JNI_INVOKE_DETACH_CURRENT_THREAD, 5)
}
