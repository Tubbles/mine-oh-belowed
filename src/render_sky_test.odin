package game

import "core:math"
import "core:math/linalg"
import "core:testing"
import rl "shared:raylib"

@(test)
test_fog_ends_one_chunk_inside_the_load_radius :: proc(t: ^testing.T) {
	start, end := fog_distances(6)
	testing.expect_value(t, end, 160)
	testing.expect_value(t, start, 96)
	start, end = fog_distances(10)
	testing.expect_value(t, end, 9 * CHUNK_SIZE)
	testing.expect_value(t, start, end * FOG_START_SHARE)
	_, end = fog_distances(LOAD_RADIUS_HORIZONTAL)
	testing.expect(t, end < LOAD_RADIUS_HORIZONTAL * CHUNK_SIZE)
}

// Work item 0313: the dome reaches SKY_DOME_RINGS_BELOW rings under the
// horizon, 22.5 degrees, and is closed but for its lowest ring.
@(test)
test_the_sky_dome_closes_down_to_its_lowest_ring :: proc(t: ^testing.T) {
	geometry := build_sky_dome()
	defer destroy_sky_dome(geometry)
	testing.expect_value(t, len(geometry.positions), SKY_DOME_VERTEX_COUNT)
	testing.expect_value(t, len(geometry.positions), 481)
	testing.expect_value(t, len(geometry.indices), SKY_DOME_TRIANGLE_COUNT * 3)
	lowest := -SKY_DOME_RADIUS * math.sin(f32(22.5 * math.RAD_PER_DEG))
	for position in geometry.positions {
		testing.expect(t, abs(linalg.length(position) - SKY_DOME_RADIUS) < 1e-3)
		testing.expect(t, position.y >= lowest - 1e-3)
	}
	testing.expect(t, abs(geometry.positions[0].y - lowest) < 1e-3, "the first ring is the lowest")
	testing.expect_value(t, geometry.positions[SKY_DOME_VERTEX_COUNT - 1], [3]f32{0, SKY_DOME_RADIUS, 0})
	// Every edge is shared by two triangles, except the lowest ring's,
	// which each belong to one: no holes, no seam.
	uses := make(map[[2]u16]int)
	defer delete(uses)
	for triangle := 0; triangle < len(geometry.indices); triangle += 3 {
		for corner in 0 ..< 3 {
			a := geometry.indices[triangle + corner]
			b := geometry.indices[triangle + (corner + 1) % 3]
			uses[{min(a, b), max(a, b)}] += 1
		}
	}
	open_edges := 0
	for edge, count in uses {
		if count == 1 {
			open_edges += 1
			testing.expect(t, int(edge[1]) < SKY_DOME_SEGMENTS, "an open edge off the lowest ring")
		} else {
			testing.expect_value(t, count, 2)
		}
	}
	testing.expect_value(t, open_edges, SKY_DOME_SEGMENTS)
}

@(test)
test_the_dome_blends_horizon_to_zenith :: proc(t: ^testing.T) {
	colors := sky_colors(0.25)
	vertex_colors := make([]rl.Color, SKY_DOME_VERTEX_COUNT)
	defer delete(vertex_colors)
	fill_sky_dome_colors(colors, vertex_colors)
	testing.expect_value(t, vertex_colors[0], colors.horizon)
	testing.expect_value(t, vertex_colors[SKY_DOME_RINGS_BELOW * SKY_DOME_SEGMENTS], colors.horizon)
	testing.expect_value(t, vertex_colors[SKY_DOME_VERTEX_COUNT - 1], colors.zenith)
}

// Work item 0313: the field's glow adds the haze's lobe round the sun:
// the horizon towards a setting sun takes the whole glow, the opposite
// side none, and the zero glow changes nothing.
@(test)
test_the_dome_glows_towards_a_low_sun :: proc(t: ^testing.T) {
	colors := sky_colors(0.25)
	glow := Sky_Glow{direction = sun_direction(0.5), color = {0.1, 0.05, 0.02}}
	glowing := make([]rl.Color, SKY_DOME_VERTEX_COUNT)
	defer delete(glowing)
	fill_sky_dome_colors(colors, glowing, glow)
	horizon := SKY_DOME_RINGS_BELOW * SKY_DOME_SEGMENTS
	towards := glowing[horizon + SKY_DOME_SEGMENTS / 2]
	expected := color_to_vector3(colors.horizon) * 255 + glow.color * 255
	got := [3]f32{f32(towards.r), f32(towards.g), f32(towards.b)}
	for channel in 0 ..< 3 {
		testing.expectf(t, abs(got[channel] - expected[channel]) <= 1, "towards the sun %v, expected %v", got, expected)
	}
	testing.expect_value(t, glowing[horizon], colors.horizon)
	plain := make([]rl.Color, SKY_DOME_VERTEX_COUNT)
	defer delete(plain)
	unglowing := make([]rl.Color, SKY_DOME_VERTEX_COUNT)
	defer delete(unglowing)
	fill_sky_dome_colors(colors, plain)
	fill_sky_dome_colors(colors, unglowing, Sky_Glow{})
	for color, index in plain {
		testing.expect_value(t, unglowing[index], color)
		testing.expect_value(t, color, sky_color_towards(colors, sky_dome_vertex_direction(index)))
	}
}

// Work item 0313: with the field's shipped glow the sun disc is per
// channel at least the dome beside it, the vertex nearest the sun and
// the colour in its direction, from sunrise to noon and at sunset.
@(test)
test_the_sun_disc_is_no_darker_than_the_dome_beside_it :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	vertex_colors := make([]rl.Color, SKY_DOME_VERTEX_COUNT)
	defer delete(vertex_colors)
	for fraction in ([4]f64{0, 0.02, 0.5, NOON_FRACTION}) {
		colors := sky_colors(fraction)
		direction := sun_direction(fraction)
		glow := Sky_Glow{direction = direction, color = haze_sun_glow_color(fraction, config.sun_and_torchlight, config.haze)}
		fill_sky_dome_colors(colors, vertex_colors, glow)
		nearest := 0
		for index in 1 ..< SKY_DOME_VERTEX_COUNT {
			if linalg.dot(sky_dome_vertex_direction(index), direction) > linalg.dot(sky_dome_vertex_direction(nearest), direction) {
				nearest = index
			}
		}
		disc := sun_disc_color(colors, direction, glow)
		beside := add_sky_glow(sky_color_towards(colors, direction), sky_glow_towards(glow, direction))
		for dome in ([2]rl.Color{vertex_colors[nearest], beside}) {
			testing.expectf(t, disc.r >= dome.r && disc.g >= dome.g && disc.b >= dome.b, "fraction %v: the disc %v is darker than the dome %v", fraction, disc, dome)
		}
	}
}

@(test)
test_the_stars_are_fixed_and_lie_on_the_dome :: proc(t: ^testing.T) {
	above := 0
	for index in 0 ..< STAR_COUNT {
		testing.expect_value(t, star_direction(index), star_direction(index))
		testing.expect_value(t, star_brightness(index), star_brightness(index))
		for fraction in ([3]f64{0, 0.3, 0.75}) {
			position := star_position(index, fraction)
			testing.expect(t, abs(linalg.length(position) - SKY_DOME_RADIUS) < 1e-3)
		}
		if star_direction(index).y > 0 {
			above += 1
		}
	}
	// Spread over the whole sphere.
	testing.expect(t, above > STAR_COUNT / 3 && above < 2 * STAR_COUNT / 3)
}

// The stars turn with the sun: the same turn carries sunrise to noon.
@(test)
test_the_sky_turns_about_the_sun_path_axis :: proc(t: ^testing.T) {
	for fraction in ([3]f64{0.1, 0.25, 0.6}) {
		turned := rotate_about_axis(sun_direction(0), sun_path_axis(), f32(fraction * math.TAU))
		expect_near_point(t, turned, sun_direction(fraction), "turned sunrise")
	}
}

@(test)
test_the_moon_shows_its_phase :: proc(t: ^testing.T) {
	testing.expect_value(t, moon_phase(0), 0)
	testing.expect_value(t, moon_phase(MOON_CYCLE_DAYS / 2), 0.5)
	testing.expect_value(t, moon_phase(MOON_CYCLE_DAYS + 1), moon_phase(1))
	// New moon: covered. Full moon: the shadow clears the disc.
	testing.expect_value(t, moon_shadow_offset(0), 0)
	testing.expect(t, abs(moon_shadow_offset(0.5)) >= 1)
	// Waxing and waning on opposite sides.
	testing.expect(t, moon_shadow_offset(0.125) > 0 && moon_shadow_offset(0.875) < 0)
	testing.expect(t, abs(moon_shadow_offset(0.125) + moon_shadow_offset(0.875)) < 1e-5)
}

@(test)
test_the_disc_texture_is_round :: proc(t: ^testing.T) {
	pixels := disc_pixels(16)
	defer delete(pixels)
	testing.expect_value(t, pixels[0].a, 0)
	testing.expect_value(t, pixels[8 * 16 + 8].a, 255)
	testing.expect_value(t, pixels[8 * 16 + 8].r, 255)
}

// The sun and moon quads stay square wherever the disc stands: both axes
// unit length and across the direction, at the zenith, on the horizon
// and between.
@(test)
test_disc_axes_are_square_across_the_direction :: proc(t: ^testing.T) {
	directions := [5][3]f32{{0, 1, 0}, {0, -1, 0}, {1, 0, 0}, {0, 0, -1}, sun_direction(0.2)}
	for direction in directions {
		right, up := disc_axes(direction)
		testing.expectf(t, abs(linalg.length(right) - 1) < 1e-5, "right of %v: %v", direction, right)
		testing.expectf(t, abs(linalg.length(up) - 1) < 1e-5, "up of %v: %v", direction, up)
		testing.expectf(t, abs(linalg.dot(right, direction)) < 1e-5, "right across %v: %v", direction, right)
		testing.expectf(t, abs(linalg.dot(up, direction)) < 1e-5, "up across %v: %v", direction, up)
		testing.expectf(t, abs(linalg.dot(right, up)) < 1e-5, "right across up at %v", direction)
	}
	// On the horizon the right stays level and the up points to the zenith.
	right, up := disc_axes({1, 0, 0})
	testing.expect(t, abs(right.y) < 1e-5)
	testing.expect(t, up.y > 0.99)
}
