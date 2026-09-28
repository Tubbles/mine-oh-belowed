package game

import "core:testing"

// The eye's cell decides: under water inside a water cell, above it one
// cell up, whatever the surface level (work item 0065).
@(test)
test_camera_underwater_by_the_eye_cell :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world: World
	world.chunks = make(map[Chunk_Coordinate]^Chunk, context.temp_allocator)
	chunk := make_test_chunk({0, 0, 0})
	world.chunks[chunk.coordinate] = chunk
	chunk_set_block(chunk, {4, 4, 4}, test_block(registry, "water"))
	chunk_set_block(chunk, {6, 4, 4}, test_block(registry, "flowing_water_3"))
	chunk_set_block(chunk, {8, 4, 4}, test_block(registry, "stone"))
	testing.expect(t, camera_underwater(&world, registry, {4.5, 4.9, 4.5}))
	testing.expect(t, camera_underwater(&world, registry, {6.5, 4.1, 4.5}))
	testing.expect(t, !camera_underwater(&world, registry, {4.5, 5.1, 4.5}))
	testing.expect(t, !camera_underwater(&world, registry, {8.5, 4.5, 4.5}))
	// A missing chunk reads as air.
	testing.expect(t, !camera_underwater(&world, registry, {-3.5, 4.5, 4.5}))
}

// Under water the fog is near and blue green, and nearer than the
// thickest weather fog, so it wins over any weather.
@(test)
test_underwater_fog_values :: proc(t: ^testing.T) {
	fog := underwater_fog()
	testing.expect_value(t, fog.start, f32(UNDERWATER_FOG_START))
	testing.expect_value(t, fog.end, f32(UNDERWATER_FOG_END))
	testing.expect_value(t, fog.start, 2)
	testing.expect_value(t, fog.end, 14)
	testing.expect(t, fog.color.g > fog.color.r && fog.color.b > fog.color.r)
	weather_start, _ := weather_fog_distances(LOAD_RADIUS_HORIZONTAL, weather_fog_scales[.Fog])
	testing.expect(t, fog.end < weather_start)
}

// The water time wraps into its period and runs on unchanged inside it.
@(test)
test_water_time_wraps :: proc(t: ^testing.T) {
	testing.expect_value(t, water_time(12.5), f32(12.5))
	testing.expect_value(t, water_time(WATER_TIME_WRAP_SECONDS + 12.5), f32(12.5))
	testing.expect_value(t, water_time(0), f32(0))
}
