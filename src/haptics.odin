package game

// The haptics types of every target, shared by the backends and by
// haptics_android.odin and haptics_desktop.odin.

// What the backend plays this frame (work item 0038), strength 0 to 1.
// The SDL3 backend rumbles the controller; SDL exposes no haptics per
// trackpad for the Steam Controller, only whole controller rumble. On
// Android the raylib backend plays it on the phone's vibrator (0122).
Haptic_Request :: struct {
	strength: f32,
}

// A rumble or a vibration lasts this long unless the next frame renews
// it, so it stops by itself when frames stop.
HAPTIC_RUMBLE_MILLISECONDS :: 100

rumble_level :: proc(strength: f32) -> u16 {
	return u16(clamp(strength, 0, 1) * f32(max(u16)))
}

// The phone vibrator's amplitude for a strength (work item 0122): 0 stops
// the vibrator, a strength above 0 plays at 1 to 255, the range of
// VibrationEffect.createOneShot.
vibration_amplitude :: proc(strength: f32) -> i32 {
	if strength <= 0 {
		return 0
	}
	return clamp(i32(min(strength, 1) * 255 + 0.5), 1, 255)
}
