package game

import "core:slice"
import "core:strings"
import "core:testing"

@(test)
test_sample_positions_are_the_index_times_the_spacing :: proc(t: ^testing.T) {
	testing.expect_value(t, sample_axis_to_position(0, 333), 0)
	testing.expect_value(t, sample_axis_to_position(1, 1000), POSITION_UNITS_PER_METRE)
	testing.expect_value(t, sample_axis_to_position(-1, 500), -POSITION_UNITS_PER_METRE / 2)
	// 333 mm is 1363.968 units, rounded up.
	testing.expect_value(t, sample_axis_to_position(1, 333), 1364)
	testing.expect_value(t, sample_axis_to_position(-1, 333), -1363)
	testing.expect_value(t, sample_axis_to_position(max(i32), 1000), i64(max(i32)) * POSITION_UNITS_PER_METRE)
	testing.expect_value(t, sample_axis_to_position(min(i32), 1000), i64(min(i32)) * POSITION_UNITS_PER_METRE)
	testing.expect_value(t, metres_to_position_units(-2), -2 * POSITION_UNITS_PER_METRE)
}

@(test)
test_positions_round_trip_to_samples :: proc(t: ^testing.T) {
	for spacing in SAMPLE_SPACING_CHOICES_MILLIMETRES {
		for index in i32(-2000) ..= 2000 {
			position := sample_axis_to_position(index, spacing)
			testing.expect_value(t, position_axis_to_sample(position, spacing), index)
			// One unit below the sample's position lies in the sample below.
			testing.expect_value(t, position_axis_to_sample(position - 1, spacing), index - 1)
		}
	}
	sample := Sample_Coordinate{-7, 24024, 3}
	testing.expect_value(t, world_position_to_sample(sample_to_world_position(sample, 333), 333), sample)
}

@(test)
test_sample_spacing_choices :: proc(t: ^testing.T) {
	testing.expect(t, sample_spacing_is_valid(333))
	testing.expect(t, sample_spacing_is_valid(DEFAULT_SAMPLE_SPACING_MILLIMETRES))
	testing.expect(t, !sample_spacing_is_valid(0))
	testing.expect(t, !sample_spacing_is_valid(334))
}

@(test)
test_field_index_and_chunk_coordinates :: proc(t: ^testing.T) {
	for index in ([?]int{0, 1, FIELD_CHUNK_SIZE, FIELD_CHUNK_SAMPLE_COUNT - 1, 12345}) {
		testing.expect_value(t, field_local_to_index(field_index_to_local(index)), index)
	}
	testing.expect_value(t, sample_to_field_chunk_coordinate({-1, 0, 32}), Field_Chunk_Coordinate{-1, 0, 1})
	testing.expect_value(t, sample_to_field_index({-1, 0, 32}), FIELD_CHUNK_SIZE - 1)
	testing.expect_value(t, field_chunk_origin({-1, 2, 0}), Sample_Coordinate{-32, 64, 0})
}

make_clean_field_world :: proc(coordinates: []Field_Chunk_Coordinate) -> Field_World {
	world: Field_World
	for coordinate in coordinates {
		chunk := new(Field_Chunk)
		chunk.coordinate = coordinate
		field_world_insert_chunk(&world, chunk)
		chunk.dirty = false
	}
	return world
}

@(test)
test_set_sample_marks_the_chunks_that_see_it :: proc(t: ^testing.T) {
	world := make_clean_field_world({{0, 0, 0}, {-1, 0, 0}, {1, 0, 0}, {-1, -1, 0}})
	defer destroy_field_world(&world)
	edited := Field_Sample{density = 40, material = .Stone, tint = 2}

	testing.expect(t, field_world_set_sample(&world, {5, 5, 5}, edited))
	testing.expect_value(t, field_world_get_sample(&world, {5, 5, 5}), edited)
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
	testing.expect(t, !world.chunks[{-1, 0, 0}].dirty && !world.chunks[{1, 0, 0}].dirty)

	world.chunks[{0, 0, 0}].dirty = false
	testing.expect(t, field_world_set_sample(&world, {0, 0, 9}, edited))
	testing.expect(t, world.chunks[{0, 0, 0}].dirty && world.chunks[{-1, 0, 0}].dirty && world.chunks[{-1, -1, 0}].dirty)
	testing.expect(t, !world.chunks[{1, 0, 0}].dirty)

	// Missing chunks read as air and refuse a write.
	testing.expect_value(t, field_world_get_sample(&world, {0, 100, 0}), FIELD_AIR_SAMPLE)
	testing.expect(t, !field_world_set_sample(&world, {0, 100, 0}, edited))
}

@(test)
test_an_unedited_field_chunk_encodes_to_nothing :: proc(t: ^testing.T) {
	chunk := generate_test_field_chunk({250, 0, 0})
	generated := generate_test_field_chunk({250, 0, 0})
	testing.expect(t, encode_field_chunk_delta(chunk, generated, context.temp_allocator) == nil)
}

@(test)
test_an_edited_field_chunk_round_trips_through_the_codec :: proc(t: ^testing.T) {
	coordinate := Field_Chunk_Coordinate{250, -1, 3}
	chunk := generate_test_field_chunk(coordinate)
	generated := generate_test_field_chunk(coordinate)
	index := field_local_to_index({7, 8, 9})
	field_chunk_set_sample(chunk, index, {density = -3, material = .Air, tint = 0})
	field_chunk_set_sample(chunk, FIELD_CHUNK_SAMPLE_COUNT - 1, {density = 90, material = .Bedrock, tint = 2})
	// The world's set clears the light of a sample turned to ground.
	chunk.block_light[FIELD_CHUNK_SAMPLE_COUNT - 1], chunk.sky_light[FIELD_CHUNK_SAMPLE_COUNT - 1] = 0, 0
	chunk.water[index] = 200
	chunk.water_still[index] = 3
	set_field_sample_bit(&chunk.water_awake, index)
	set_field_sample_bit(&chunk.water_source, FIELD_CHUNK_SAMPLE_COUNT - 1)
	chunk.block_light[index] = 180
	chunk.sky_light[index] = 77

	bytes := encode_field_chunk_delta(chunk, generated, context.temp_allocator)
	// Smaller than the three planes as they are.
	testing.expect(t, len(bytes) > 0 && len(bytes) < 3 * FIELD_CHUNK_SAMPLE_COUNT)
	restored := new(Field_Chunk, context.temp_allocator)
	testing.expect_value(t, decode_field_chunk_delta(bytes, restored), "")
	testing.expect_value(t, restored.coordinate, coordinate)
	testing.expect(t, field_chunk_equals(restored, chunk))
	testing.expect_value(t, field_chunk_get_sample(restored, index), Field_Sample{density = -3, material = .Air, tint = 0})
	testing.expect_value(t, restored.water[index], 200)
	testing.expect_value(t, restored.block_light[index], 180)
	testing.expect_value(t, restored.sky_light[index], 77)
	testing.expect(t, field_sample_bit(&restored.water_awake, index) && field_sample_bit(&restored.water_source, FIELD_CHUNK_SAMPLE_COUNT - 1))
	testing.expect(t, restored.dirty)
}

@(test)
test_field_chunk_decode_refuses_malformed_bytes :: proc(t: ^testing.T) {
	chunk := new(Field_Chunk, context.temp_allocator)
	field_chunk_set_sample(chunk, 3, {density = 5, material = .Stone, tint = 1})
	bytes := encode_field_chunk_delta(chunk, new(Field_Chunk, context.temp_allocator), context.temp_allocator)
	restored := new(Field_Chunk, context.temp_allocator)

	testing.expect(t, decode_field_chunk_delta(nil, restored) != "")
	// Block chunk bytes carry version 1.
	older := slice.clone(bytes, context.temp_allocator)
	older[0], older[1] = 1, 0
	problem := decode_field_chunk_delta(older, restored)
	testing.expect(t, strings.contains(problem, "version 1 "), problem)
	testing.expect(t, decode_field_chunk_delta(bytes[:len(bytes) - 1], restored) != "")
	testing.expect(t, decode_field_chunk_delta(slice.concatenate([][]byte{bytes, {0}}, context.temp_allocator), restored) != "")
	// A run count far beyond the bytes is refused before reading.
	huge_count := slice.clone(bytes, context.temp_allocator)
	huge_count[14], huge_count[15], huge_count[16], huge_count[17] = 0xff, 0xff, 0xff, 0x7f
	testing.expect(t, decode_field_chunk_delta(huge_count, restored) != "")
	for malformed in malformed_field_chunk_runs() {
		testing.expect(t, decode_field_chunk_delta(malformed, restored) != "")
	}
	// A fill above full.
	overfull := new(Field_Chunk, context.temp_allocator)
	overfull.water[0] = FIELD_WATER_FULL + 1
	overfull_bytes := encode_field_chunk_delta(overfull, new(Field_Chunk, context.temp_allocator), context.temp_allocator)
	problem = decode_field_chunk_delta(overfull_bytes, restored)
	testing.expect(t, strings.contains(problem, "water fill 255"), problem)
	// None of the refusals touched the chunk.
	testing.expect(t, field_chunk_equals(restored, new(Field_Chunk, context.temp_allocator)))
}

// A world.sjson from before the setting reads the default; another value
// than the choices is refused by name.
@(test)
test_the_sample_spacing_setting_in_the_world_file :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		settings = World_File_Settings{day_length_seconds = 1200},
	}
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.settings.sample_spacing_millimetres, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	file.settings.sample_spacing_millimetres = 334
	_, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, strings.contains(problem, "sample_spacing_millimetres 334"), problem)
}

// Hand built bytes: an unknown material id, a single run past the end of
// the density plane, and runs that fall one sample short of it.
malformed_field_chunk_runs :: proc() -> [3][]byte {
	plane_bytes :: proc(bytes: ^[dynamic]byte, value: u8, count: u32) {
		append_u32(bytes, 1)
		append(bytes, value)
		append_u32(bytes, count)
	}
	// The water's and the light's planes after the first three, all zero.
	water_planes :: proc(bytes: ^[dynamic]byte) {
		plane_bytes(bytes, 0, FIELD_CHUNK_SAMPLE_COUNT)
		plane_bytes(bytes, 0, FIELD_CHUNK_SAMPLE_COUNT)
		plane_bytes(bytes, 0, FIELD_SAMPLE_BIT_BYTES)
		plane_bytes(bytes, 0, FIELD_SAMPLE_BIT_BYTES)
		plane_bytes(bytes, 0, FIELD_CHUNK_SAMPLE_COUNT)
		plane_bytes(bytes, 0, FIELD_CHUNK_SAMPLE_COUNT)
	}
	header :: proc() -> [dynamic]byte {
		bytes := make([dynamic]byte, context.temp_allocator)
		append_u16(&bytes, FIELD_CHUNK_FORMAT_VERSION)
		for _ in 0 ..< 3 {
			append_i32(&bytes, 0)
		}
		return bytes
	}
	unknown_material := header()
	plane_bytes(&unknown_material, 0, FIELD_CHUNK_SAMPLE_COUNT)
	plane_bytes(&unknown_material, u8(max(Field_Material)) + 1, FIELD_CHUNK_SAMPLE_COUNT)
	plane_bytes(&unknown_material, 0, FIELD_CHUNK_SAMPLE_COUNT)
	water_planes(&unknown_material)
	past_the_end := header()
	plane_bytes(&past_the_end, 0, FIELD_CHUNK_SAMPLE_COUNT + 1)
	plane_bytes(&past_the_end, 0, FIELD_CHUNK_SAMPLE_COUNT)
	plane_bytes(&past_the_end, 0, FIELD_CHUNK_SAMPLE_COUNT)
	water_planes(&past_the_end)
	short := header()
	plane_bytes(&short, 0, FIELD_CHUNK_SAMPLE_COUNT - 1)
	plane_bytes(&short, 0, FIELD_CHUNK_SAMPLE_COUNT)
	plane_bytes(&short, 0, FIELD_CHUNK_SAMPLE_COUNT)
	water_planes(&short)
	return {unknown_material[:], past_the_end[:], short[:]}
}

// Light in a ground sample is malformed: the decoder drops it, so it
// cannot spread from inside the ground.
@(test)
test_field_chunk_decode_drops_light_in_ground :: proc(t: ^testing.T) {
	chunk := new(Field_Chunk, context.temp_allocator)
	field_chunk_set_sample(chunk, 3, {density = 5, material = .Stone, tint = 1})
	chunk.block_light[3], chunk.sky_light[3] = 200, 255
	chunk.block_light[4], chunk.sky_light[4] = 100, 50
	bytes := encode_field_chunk_delta(chunk, new(Field_Chunk, context.temp_allocator), context.temp_allocator)
	restored := new(Field_Chunk, context.temp_allocator)
	testing.expect_value(t, decode_field_chunk_delta(bytes, restored), "")
	testing.expect_value(t, restored.block_light[3], 0)
	testing.expect_value(t, restored.sky_light[3], 0)
	testing.expect_value(t, restored.block_light[4], 100)
	testing.expect_value(t, restored.sky_light[4], 50)
}
