package game

import "core:math"
import "core:math/linalg"
import "core:testing"
import rl "vendor:raylib"

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

@(test)
test_the_sky_dome_is_a_closed_hemisphere :: proc(t: ^testing.T) {
	geometry := build_sky_dome()
	defer destroy_sky_dome(geometry)
	testing.expect_value(t, len(geometry.positions), SKY_DOME_VERTEX_COUNT)
	testing.expect_value(t, len(geometry.positions), 24 * 8 + 1)
	testing.expect_value(t, len(geometry.indices), SKY_DOME_TRIANGLE_COUNT * 3)
	for position in geometry.positions {
		testing.expect(t, abs(linalg.length(position) - SKY_DOME_RADIUS) < 1e-3)
		testing.expect(t, position.y >= 0)
	}
	testing.expect_value(t, geometry.positions[SKY_DOME_VERTEX_COUNT - 1], [3]f32{0, SKY_DOME_RADIUS, 0})
	// Every edge is shared by two triangles, except the horizon ring's,
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
			testing.expect(t, int(edge[1]) < SKY_DOME_SEGMENTS, "an open edge off the horizon ring")
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
	testing.expect_value(t, vertex_colors[SKY_DOME_VERTEX_COUNT - 1], colors.zenith)
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
