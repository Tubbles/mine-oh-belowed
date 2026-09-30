#+build !linux:android
package game

import "core:testing"

@(test)
test_sdl3_joystick_line_names_the_device_and_its_mapping :: proc(t: ^testing.T) {
	testing.expect_value(
		t,
		sdl3_joystick_line(3, "Winlator", 0x045e, 0x028e, "030000005e0400008e02000000007200", false),
		`input: joystick 3 "Winlator" vendor 045e product 028e guid 030000005e0400008e02000000007200 no gamepad mapping`,
	)
	testing.expect_value(
		t,
		sdl3_joystick_line(7, "Steam Controller", 0x28de, 0x1302, "03000000de2800000213000000000000", true),
		`input: joystick 7 "Steam Controller" vendor 28de product 1302 guid 03000000de2800000213000000000000 gamepad`,
	)
}
