#+build linux:android
package game

// The phone's keyboard, the IME, for text fields (work item 0133,
// doc/android.md, Keyboard). The NDK shows and hides it for the native
// activity (android/native_activity.h, NDK 27.3.13750724); flags 0 is an
// explicit request, as a tap on the field is, and hides it however it
// was shown. The IME's text reaches raylib as key events
// (read_raylib_typed_text in input_raylib.odin).

foreign import android "system:android"

@(default_calling_convention = "c")
foreign android {
	ANativeActivity_showSoftInput :: proc(activity: ^Android_Native_Activity, flags: u32) ---
	ANativeActivity_hideSoftInput :: proc(activity: ^Android_Native_Activity, flags: u32) ---
}

system_keyboard_available :: proc() -> bool {return true}

// The IME places itself; the field's rectangle is Steam's concern.
show_system_keyboard :: proc(field_window: Ui_Rectangle) {
	ANativeActivity_showSoftInput(GetAndroidApp().activity, 0)
}

hide_system_keyboard :: proc() {
	ANativeActivity_hideSoftInput(GetAndroidApp().activity, 0)
}
