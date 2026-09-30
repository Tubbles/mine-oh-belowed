#+build !linux:android
package game

// Outside Android the raylib backend plays no haptics (work item 0122):
// these stand in for haptics_android.odin.

Vibrator_State :: struct {}

start_vibrator :: proc() -> Vibrator_State {return {}}

apply_vibrator_haptics :: proc(state: ^Vibrator_State, request: Haptic_Request) {}

stop_vibrator :: proc(state: ^Vibrator_State) {}
