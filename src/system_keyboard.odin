package game

// A text field's rectangle in window pixels, for the system keyboard of
// system_keyboard_linux.odin, system_keyboard_android.odin and
// system_keyboard_windows.odin.
System_Keyboard_Field :: struct {
	x, y, width, height: f32,
}
