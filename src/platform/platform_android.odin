#+build linux:android
package platform

import "core:strings"
// Exports the C functions bionic lacks (android_libc.odin).
@(require) import "../android_libc"

// What the Android build needs from the system and from raylib's Android
// archive beyond the binding (work item 0114). The struct layouts are the
// leading fields of the NDK's headers, checked against NDK 27.3.13750724:
// android_app in sources/android/native_app_glue/android_native_app_glue.h
// and ANativeActivity in sysroot/usr/include/android/native_activity.h.
// Only the leading fields are declared, so only pointers to them are used.

Android_Native_Activity :: struct {
	callbacks:          rawptr,
	vm:                 rawptr,
	env:                rawptr,
	clazz:              rawptr,
	internal_data_path: cstring,
	external_data_path: cstring,
	sdk_version:        i32,
	instance:           rawptr,
	asset_manager:      rawptr,
	obb_path:           cstring,
}

// The fields up to destroyRequested (work item 0116), in the order of
// android_native_app_glue.h, NDK 27.3.13750724; content_rect is ARect,
// four int32_t (android/rect.h).
Android_App :: struct {
	user_data:         rawptr,
	on_app_cmd:        rawptr,
	on_input_event:    rawptr,
	activity:          ^Android_Native_Activity,
	config:            rawptr,
	saved_state:       rawptr,
	saved_state_size:  uint,
	looper:            rawptr,
	input_queue:       rawptr,
	window:            rawptr,
	content_rect:      [4]i32,
	activity_state:    i32,
	// Non-zero while the activity is being destroyed.
	destroy_requested: i32,
}

// rcore_android.c: the android_app raylib's android_main was given. Set
// before android_main calls main, so it is valid from main on.
foreign import raylib_android "shared:raylib/android/libraylib.a"

@(default_calling_convention = "c")
foreign raylib_android {
	GetAndroidApp :: proc() -> ^Android_App ---
}

foreign import android_log "system:log"

// Priority 4 is ANDROID_LOG_INFO (android/log.h).
ANDROID_LOG_INFO :: 4
ANDROID_LOG_TAG :: "mine-oh-belowed"

@(default_calling_convention = "c")
foreign android_log {
	__android_log_write :: proc(priority: i32, tag, text: cstring) -> i32 ---
}

foreign import gles "system:GLESv3"

@(default_calling_convention = "c")
foreign gles {
	glGetString :: proc(name: u32) -> cstring ---
}

// The app's private directory and its folder under Android/data, as the
// activity reports them. Either may be empty.
android_data_paths :: proc() -> (internal, external: string) {
	activity := GetAndroidApp().activity
	return string(activity.internal_data_path), string(activity.external_data_path)
}

// log_printf's copy for logcat.
write_logcat :: proc(line: string) {
	__android_log_write(ANDROID_LOG_INFO, ANDROID_LOG_TAG, strings.clone_to_cstring(line, context.temp_allocator))
}
