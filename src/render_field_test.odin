package game

import "core:testing"
import rl "shared:raylib"

// Work item 0307: with a climate the globe takes the temperate moderate
// grass as the grass tile shows it, so the far planet reads green;
// without one the palette's first colour, as before.
@(test)
test_the_globe_takes_the_temperate_grass :: proc(t: ^testing.T) {
	planet := make_test_planet()
	gray := [3]f32{0.5, 0.5, 0.5}
	testing.expect_value(t, field_globe_color(planet, gray), opaque_test_color(planet.palette[0]))
	planet.climate = SHIPPED_TEST_CLIMATE
	temperate := planet.climate.grass_colors[4]
	testing.expect_value(t, field_globe_color(planet, gray), opaque_test_color(temperate))
	darker := field_globe_color(planet, {0.25, 0.25, 0.25})
	testing.expectf(t, abs(int(darker.g) * 2 - temperate.g) <= 1, "the grass tile's mean scales the globe: %v", darker)
}

opaque_test_color :: proc(color: [3]int) -> rl.Color {
	return {u8(color.r), u8(color.g), u8(color.b), 255}
}
