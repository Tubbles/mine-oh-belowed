#+build windows
package game

// Windows has no system keyboard for text fields (work item 0133): the
// game's own keys stand in, as they do on Linux outside Steam.

system_keyboard_available :: proc() -> bool {return false}

show_system_keyboard :: proc(field_window: Ui_Rectangle) {}

hide_system_keyboard :: proc() {}
