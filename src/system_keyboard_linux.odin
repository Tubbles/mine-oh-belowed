#+build linux
#+build !linux:android
package game

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import "platform"

// Steam's on-screen keyboard for text fields (work item 0133, doc/ui.md,
// On-screen keyboard), opened the way SDL's X11 backend opens it: through
// the steam:// deep links, which need no SDL window. Steam sets
// SDL_ENABLE_STEAM_SCREEN_KEYBOARD for the games it starts in gaming mode
// and SteamDeck on a Deck. The keyboard types through a virtual keyboard
// device, so its text arrives as GLFW's key and character events.

STEAM_SCREEN_KEYBOARD_ENVIRONMENT_VARIABLE :: "SDL_ENABLE_STEAM_SCREEN_KEYBOARD"
STEAM_CLOSE_KEYBOARD_LINK :: "steam://close/keyboard"

// The two variables' values, empty when unset.
steam_keyboard_available :: proc(screen_keyboard, steam_deck: string) -> bool {
	return screen_keyboard == "1" || steam_deck == "1"
}

// The field's rectangle in window coordinates, as SDL's X11 backend
// sends it, so Steam docks the keyboard away from it. Mode 0 is a single
// line.
steam_keyboard_link :: proc(field_window: System_Keyboard_Field) -> string {
	return fmt.tprintf(
		"steam://open/keyboard?XPosition=%d&YPosition=%d&Width=%d&Height=%d&Mode=0",
		int(field_window.x),
		int(field_window.y),
		int(field_window.width),
		int(field_window.height),
	)
}

system_keyboard_available :: proc() -> bool {
	screen_keyboard := os.get_env(STEAM_SCREEN_KEYBOARD_ENVIRONMENT_VARIABLE, context.temp_allocator)
	steam_deck := os.get_env(STEAM_DECK_ENVIRONMENT_VARIABLE, context.temp_allocator)
	return steam_keyboard_available(screen_keyboard, steam_deck)
}

show_system_keyboard :: proc(field_window: System_Keyboard_Field) {
	open_steam_link(steam_keyboard_link(field_window))
}

hide_system_keyboard :: proc() {
	open_steam_link(STEAM_CLOSE_KEYBOARD_LINK)
}

open_steam_link :: proc(link: string) {
	if !sdl.OpenURL(strings.clone_to_cstring(link, context.temp_allocator)) {
		platform.log_printf("error: cannot open %s: %s", link, sdl.GetError())
	}
}
