package game

import "core:testing"

@(test)
test_weather_fog_scale_per_kind_and_blend :: proc(t: ^testing.T) {
	testing.expect_value(t, weather_look(Weather{kind = .Clear, intensity = 1}, true, 1).fog_scale, 1)
	testing.expect_value(t, weather_look(Weather{kind = .Overcast, intensity = 1}, true, 1).fog_scale, 0.8)
	testing.expect_value(t, weather_look(Weather{kind = .Rain, intensity = 1}, true, 1).fog_scale, 0.5)
	testing.expect_value(t, weather_look(Weather{kind = .Fog, intensity = 1}, true, 1).fog_scale, 0.25)
	testing.expect_value(t, weather_look(Weather{kind = .Fog, intensity = 0}, true, 1).fog_scale, 1)
	testing.expect_value(t, weather_look(Weather{kind = .Rain, intensity = 0.5}, true, 1).fog_scale, 0.75)
	start, end := fog_distances(LOAD_RADIUS_HORIZONTAL)
	scaled_start, scaled_end := weather_fog_distances(LOAD_RADIUS_HORIZONTAL, 0.5)
	testing.expect_value(t, scaled_start, start * 0.5)
	testing.expect_value(t, scaled_end, end * 0.5)
}

// Wind from 0.3 when clear to 1 in rain; cloud shadows 0.15 clear, 0.35
// in rain, none at night; the setting off stills everything.
@(test)
test_weather_wind_and_cloud_shadows :: proc(t: ^testing.T) {
	clear := weather_look(Weather{kind = .Clear, intensity = 0.7}, true, 1)
	testing.expect_value(t, clear.wind_strength, CLEAR_WIND_STRENGTH)
	testing.expect_value(t, clear.cloud_shadow_strength, CLEAR_CLOUD_SHADOW_STRENGTH)
	rain := weather_look(Weather{kind = .Rain, intensity = 1}, true, 1)
	testing.expect_value(t, rain.wind_strength, 1)
	testing.expect_value(t, rain.cloud_shadow_strength, 0.35)
	testing.expect_value(t, weather_look(Weather{kind = .Rain, intensity = 1}, true, 0).cloud_shadow_strength, 0)
	testing.expect_value(t, weather_look(Weather{kind = .Rain, intensity = 1}, false, 1), Weather_Look{fog_scale = 1})
}

// Rain greys and darkens the sky and the sky light; clear weather and
// fog keep the day's colours.
@(test)
test_weather_sky_colors :: proc(t: ^testing.T) {
	colors := sky_colors(NOON_FRACTION)
	testing.expect_value(t, weathered_sky_colors(colors, Weather{kind = .Clear, intensity = 1}), colors)
	testing.expect_value(t, weathered_sky_colors(colors, Weather{kind = .Fog, intensity = 1}), colors)
	rainy := weathered_sky_colors(colors, Weather{kind = .Rain, intensity = 1})
	testing.expect(t, int(rainy.zenith.b) < int(colors.zenith.b))
	testing.expect(t, int(rainy.zenith.b) - int(rainy.zenith.r) < int(colors.zenith.b) - int(colors.zenith.r))
	testing.expect_value(t, rainy.fog, rainy.horizon)
	// Sky light on wet ground: 25 percent darker at full rain.
	testing.expect_value(t, colors.sun_tint, DAY_SUN_TINT)
	testing.expect_value(t, rainy.sun_tint, mix_color(DAY_SUN_TINT, {0, 0, 0, 255}, WET_GROUND_DARKENING))
	testing.expect_value(t, rainy.sun_tint.r, 191)
	overcast := weathered_sky_colors(colors, Weather{kind = .Overcast, intensity = 1})
	testing.expect_value(t, overcast.sun_tint, colors.sun_tint)
	testing.expect(t, int(overcast.zenith.b) > int(rainy.zenith.b))
}

// Every particle lies inside the column around the camera, the same on
// every call, and stays put in the world while the camera moves a little.
@(test)
test_weather_particles_wrap_inside_the_cylinder :: proc(t: ^testing.T) {
	camera := [3]f32{1003.5, 72.25, -48.75}
	inside_count := 0
	for index in 0 ..< WEATHER_PARTICLE_COUNT {
		for seconds in ([?]f64{0, 1.5, 3600.25}) {
			position, inside := weather_particle_position(index, camera, seconds, RAIN_FALL_SPEED)
			again, inside_again := weather_particle_position(index, camera, seconds, RAIN_FALL_SPEED)
			testing.expect_value(t, again, position)
			testing.expect_value(t, inside_again, inside)
			offset := position - camera
			testing.expect(t, abs(offset.x) <= WEATHER_RADIUS && abs(offset.z) <= WEATHER_RADIUS)
			testing.expect(t, offset.y >= -WEATHER_HEIGHT / 2 && offset.y <= WEATHER_HEIGHT / 2)
			testing.expect_value(t, inside, offset.x * offset.x + offset.z * offset.z <= WEATHER_RADIUS * WEATHER_RADIUS)
			if inside && seconds == 0 {
				inside_count += 1
			}
		}
	}
	// About pi / 4 of the square lies inside the circle.
	testing.expect(t, inside_count > WEATHER_PARTICLE_COUNT * 7 / 10 && inside_count < WEATHER_PARTICLE_COUNT * 85 / 100)
	near, _ := weather_particle_position(7, camera, 2, RAIN_FALL_SPEED)
	moved, _ := weather_particle_position(7, camera + {0.5, 0, 0.5}, 2, RAIN_FALL_SPEED)
	if abs(near.x - camera.x) < WEATHER_RADIUS - 1 && abs(near.z - camera.z) < WEATHER_RADIUS - 1 {
		testing.expect_value(t, moved.xz, near.xz)
	}
	// Falling: a little later the particle is lower, unless it wrapped.
	later, _ := weather_particle_position(7, camera, 2.01, RAIN_FALL_SPEED)
	testing.expect(t, later.y < near.y || later.y - near.y > WEATHER_HEIGHT / 2)
}

@(test)
test_weather_particle_count :: proc(t: ^testing.T) {
	testing.expect_value(t, weather_particle_count(1, 1), WEATHER_PARTICLE_COUNT)
	testing.expect_value(t, weather_particle_count(0.5, 1), WEATHER_PARTICLE_COUNT / 2)
	testing.expect_value(t, weather_particle_count(1, 0), 0)
	testing.expect_value(t, weather_particle_count(0, 1), 0)
}

// The cloud texture is the same every time and tiles: its lattice wraps.
@(test)
test_weather_cloud_texture_tiles :: proc(t: ^testing.T) {
	pixels := cloud_pixels(CLOUD_TEXTURE_SIZE, context.temp_allocator)
	again := cloud_pixels(CLOUD_TEXTURE_SIZE, context.temp_allocator)
	testing.expect_value(t, len(pixels), CLOUD_TEXTURE_SIZE * CLOUD_TEXTURE_SIZE)
	clear_count, cloud_count := 0, 0
	for pixel, index in pixels {
		testing.expect_value(t, again[index], pixel)
		clear_count += int(pixel.r == 0)
		cloud_count += int(pixel.r > 128)
	}
	testing.expect(t, clear_count > 0 && cloud_count > 0)
	testing.expect_value(t, cloud_lattice_value(CLOUD_LATTICE_CELLS, 3), cloud_lattice_value(0, 3))
	testing.expect_value(t, cloud_lattice_value(-1, 3), cloud_lattice_value(CLOUD_LATTICE_CELLS - 1, 3))
	testing.expect_value(t, cloud_noise({0, 5}, CLOUD_TEXTURE_SIZE), cloud_noise({CLOUD_TEXTURE_SIZE, 5}, CLOUD_TEXTURE_SIZE))
	for seconds in ([?]f64{0, 10, 1e6}) {
		offset := cloud_offset(seconds)
		testing.expect(t, offset.x >= 0 && offset.x < CLOUD_TILE_BLOCKS && offset.y >= 0 && offset.y < CLOUD_TILE_BLOCKS)
		wind := wind_time(seconds)
		testing.expect(t, wind >= 0 && wind < WIND_TIME_WRAP_SECONDS)
	}
}
