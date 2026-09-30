#+build linux
#+build !linux:android
package game

import "core:testing"

// Work item 0133: the Steam keyboard's availability and deep link.

@(test)
test_steam_keyboard_available_from_either_variable :: proc(t: ^testing.T) {
	testing.expect(t, steam_keyboard_available("1", ""))
	testing.expect(t, steam_keyboard_available("", "1"))
	testing.expect(t, steam_keyboard_available("1", "1"))
	testing.expect(t, !steam_keyboard_available("", ""))
	testing.expect(t, !steam_keyboard_available("0", "0"))
}

@(test)
test_steam_keyboard_link_carries_the_field_rectangle :: proc(t: ^testing.T) {
	link := steam_keyboard_link({120.6, 340, 800.4, 72})
	testing.expect_value(t, link, "steam://open/keyboard?XPosition=120&YPosition=340&Width=800&Height=72&Mode=0")
}
