package game

import "core:testing"

@(test)
test_vibration_amplitude_follows_the_strength :: proc(t: ^testing.T) {
	testing.expect_value(t, vibration_amplitude(0), 0)
	testing.expect_value(t, vibration_amplitude(-1), 0)
	testing.expect_value(t, vibration_amplitude(0.001), 1)
	testing.expect_value(t, vibration_amplitude(0.5), 128)
	testing.expect_value(t, vibration_amplitude(1), 255)
	testing.expect_value(t, vibration_amplitude(2), 255)
}
