#+build linux:android
package game

import "platform"

// The phone's keyboard, the IME, for text fields (work item 0133,
// doc/android.md, Keyboard). The NDK shows and hides it for the native
// activity (android/native_activity.h, NDK 27.3.13750724); flags 0 is an
// explicit request, as a tap on the field is, and hides it however it
// was shown. The IME's text reaches raylib as key events
// (read_raylib_typed_text in input_raylib.odin).

foreign import android "system:android"

@(default_calling_convention = "c")
foreign android {
	ANativeActivity_showSoftInput :: proc(activity: ^platform.Android_Native_Activity, flags: u32) ---
	ANativeActivity_hideSoftInput :: proc(activity: ^platform.Android_Native_Activity, flags: u32) ---
}

system_keyboard_available :: proc() -> bool {return true}

// The IME places itself; the field's rectangle is Steam's concern.
show_system_keyboard :: proc(field_window: System_Keyboard_Field) {
	ANativeActivity_showSoftInput(platform.GetAndroidApp().activity, 0)
}

hide_system_keyboard :: proc() {
	ANativeActivity_hideSoftInput(platform.GetAndroidApp().activity, 0)
}
