#+build linux:android
package game

// Android has no SDL (work item 0114): input_sdl3.odin is left out and
// these stand in for what the rest of the game calls from it, so
// start_input_backend falls back to the raylib backend and logs why.
// raylib reads Bluetooth and USB gamepads on Android itself.

Sdl3_Input_State :: struct {}

init_sdl3_input :: proc() -> (ok: bool, error_message: string) {return false, "no SDL on Android"}

read_sdl3_input_frame :: proc(state: ^Sdl3_Input_State, previous: Input_Frame, frame_seconds: f32, settings: Settings, bindings: Input_Bindings, overlay: Touch_Overlay_Frame) -> Input_Frame {return previous}

apply_sdl3_haptics :: proc(state: ^Sdl3_Input_State, request: Haptic_Request) {}

shutdown_sdl3_input :: proc(state: ^Sdl3_Input_State) {}

sdl3_gamepad_axis_label :: proc(index: int) -> string {return ""}

sdl3_gamepad_button_label :: proc(index: int) -> string {return ""}

right_pad_click_down :: proc(raw: Raw_Input) -> bool {return false}
