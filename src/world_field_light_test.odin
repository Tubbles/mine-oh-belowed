package game

import "core:slice"
import "core:testing"

// The light tests' chunks lie far up the +y axis, so the radial is +y
// within a few hundredths of a sample over a chunk.
LIGHT_TEST_CHUNK_Y :: 100
LIGHT_TEST_SPACINGS :: [3]int{333, 500, 1000}
LIGHT_TEST_STONE :: Field_Sample{MAXIMUM_DENSITY, .Stone, 0}

test_lighting_file :: proc() -> Lighting_File {
	lighting, problem := parse_lighting_file(#load("../data/lighting.sjson"), LIGHTING_FILE_NAME, context.temp_allocator)
	assert(problem == "", problem)
	return lighting
}

test_emitter_level :: proc(id: string) -> u8 {
	level, found := find_lighting_emitter(test_lighting_file(), id)
	assert(found, id)
	return u8(level)
}

// Chunks x and z from 0 to last, at LIGHT_TEST_CHUNK_Y, every sample
// stone with no light.
make_light_test_world :: proc(last_x, last_z: i32) -> Field_World {
	world: Field_World
	for z in 0 ..= last_z {
		for x in 0 ..= last_x {
			chunk := new(Field_Chunk)
			chunk.coordinate = {x, LIGHT_TEST_CHUNK_Y, z}
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				field_chunk_set_sample(chunk, index, LIGHT_TEST_STONE)
			}
			field_world_insert_chunk(&world, chunk)
		}
	}
	clear(&world.light.arrived_chunks)
	return world
}

// Missing chunks read as 0.
field_world_get_light :: proc(world: ^Field_World, sample: Sample_Coordinate, channel: Field_Light_Channel) -> u8 {
	cell, loaded := field_light_cell(world, sample)
	return loaded ? field_cell_light(cell, channel) : 0
}

light_test_origin :: proc() -> Sample_Coordinate {
	return field_chunk_origin({0, LIGHT_TEST_CHUNK_Y, 0})
}

// Air in the box, set straight into the chunks with no light (nothing
// queues).
carve_light_test_box :: proc(world: ^Field_World, low, high: Sample_Coordinate) {
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				sample := Sample_Coordinate{x, y, z}
				chunk := world.chunks[sample_to_field_chunk_coordinate(sample)]
				field_chunk_set_sample(chunk, sample_to_field_index(sample), FIELD_AIR_SAMPLE)
			}
		}
	}
}

run_test_light :: proc(world: ^Field_World, tuning: Field_Light_Tuning) {
	for pending_field_light_nodes(world) > 0 {
		propagate_field_light(world, tuning, max(int))
	}
}

// The box of samples a metres measure from centre: half_width across x
// and z, from below under to above over it.
Light_Test_Room :: struct {
	low, high: Sample_Coordinate,
}

metres_to_samples :: proc(millimetres, spacing: int) -> i32 {
	return i32((millimetres + spacing / 2) / spacing)
}

light_test_room :: proc(centre: Sample_Coordinate, half_width_millimetres, spacing: int) -> Light_Test_Room {
	half := metres_to_samples(half_width_millimetres, spacing)
	below := metres_to_samples(1000, spacing)
	above := metres_to_samples(2000, spacing)
	return {centre - {half, below, half}, centre + {half, above, half}}
}

// Whether every sample of the room is brighter than dark (all), or any
// is (not all).
room_samples_lit :: proc(world: ^Field_World, room: Light_Test_Room, dark: u8) -> (lit, total: int) {
	for z in room.low.z ..= room.high.z {
		for y in room.low.y ..= room.high.y {
			for x in room.low.x ..= room.high.x {
				total += 1
				lit += field_world_get_light(world, {x, y, z}, .Block) > dark ? 1 : 0
			}
		}
	}
	return lit, total
}

// The room lit by one emitter at its centre: the samples above dark and
// all of them.
light_test_room_with_emitter :: proc(spacing, half_width_millimetres: int, emitter: string) -> (lit, total: int) {
	world := make_light_test_world(2, 2)
	defer destroy_field_world(&world)
	tuning := make_field_light_tuning(test_lighting_file(), spacing)
	centre := light_test_origin() + {48, 16, 48}
	room := light_test_room(centre, half_width_millimetres, spacing)
	carve_light_test_box(&world, room.low, room.high)
	add_field_light_source(&world, centre, test_emitter_level(emitter))
	run_test_light(&world, tuning)
	return room_samples_lit(&world, room, tuning.dark_level)
}

@(test)
test_a_torch_lights_an_eight_metre_room_and_not_a_twenty_metre_hall :: proc(t: ^testing.T) {
	for spacing in LIGHT_TEST_SPACINGS {
		lit, total := light_test_room_with_emitter(spacing, 4000, "torch")
		testing.expectf(t, lit == total, "%d mm: %d of %d samples of the 8 m room lit", spacing, lit, total)
		lit, total = light_test_room_with_emitter(spacing, 10000, "torch")
		testing.expectf(t, lit < total, "%d mm: the 20 m hall is lit whole", spacing)
	}
}

@(test)
test_a_lamp_lights_a_sixteen_metre_hall_and_not_a_thirty_metre_one :: proc(t: ^testing.T) {
	for spacing in LIGHT_TEST_SPACINGS {
		lit, total := light_test_room_with_emitter(spacing, 8000, "lamp")
		testing.expectf(t, lit == total, "%d mm: %d of %d samples of the 16 m hall lit", spacing, lit, total)
		lit, total = light_test_room_with_emitter(spacing, 15000, "lamp")
		testing.expectf(t, lit < total, "%d mm: the 30 m hall is lit whole", spacing)
	}
}

// The farthest metres along a straight corridor from the emitter whose
// light is above dark.
light_test_reach_millimetres :: proc(spacing: int, emitter: string) -> int {
	world := make_light_test_world(2, 0)
	defer destroy_field_world(&world)
	tuning := make_field_light_tuning(test_lighting_file(), spacing)
	start := light_test_origin() + {0, 16, 16}
	carve_light_test_box(&world, start, start + {3 * FIELD_CHUNK_SIZE - 1, 0, 0})
	add_field_light_source(&world, start, test_emitter_level(emitter))
	run_test_light(&world, tuning)
	reach: i32 = 0
	for field_world_get_light(&world, start + {reach + 1, 0, 0}, .Block) > tuning.dark_level {
		reach += 1
	}
	return int(reach) * spacing
}

// The curve gives the same radius in metres at every spacing: a torch
// reads as a room of about 10 m (its reach along a corridor 10 to 12 m,
// a room's corner lies farther along the face neighbours than across),
// a lamp as a hall of about 20 m.
@(test)
test_the_light_radius_in_metres_is_the_same_at_every_spacing :: proc(t: ^testing.T) {
	for spacing in LIGHT_TEST_SPACINGS {
		torch := light_test_reach_millimetres(spacing, "torch")
		lamp := light_test_reach_millimetres(spacing, "lamp")
		testing.expectf(t, torch >= 10000 && torch <= 12000, "%d mm: the torch reaches %d mm", spacing, torch)
		testing.expectf(t, lamp >= 20000 && lamp <= 23000, "%d mm: the lamp reaches %d mm", spacing, lamp)
	}
}

every_block_light_is_zero :: proc(world: ^Field_World) -> bool {
	for _, chunk in world.chunks {
		for level in chunk.block_light {
			if level != 0 {
				return false
			}
		}
	}
	return true
}

@(test)
test_removing_the_torch_returns_every_sample_to_dark :: proc(t: ^testing.T) {
	for spacing in LIGHT_TEST_SPACINGS {
		world := make_light_test_world(2, 2)
		defer destroy_field_world(&world)
		tuning := make_field_light_tuning(test_lighting_file(), spacing)
		centre := light_test_origin() + {48, 16, 48}
		room := light_test_room(centre, 4000, spacing)
		carve_light_test_box(&world, room.low, room.high)
		// A second torch's light overlaps the first's, so the removal has
		// to give its share back.
		other := centre + {metres_to_samples(3000, spacing), 0, 0}
		add_field_light_source(&world, centre, test_emitter_level("torch"))
		add_field_light_source(&world, other, test_emitter_level("torch"))
		run_test_light(&world, tuning)
		remove_field_light_source(&world, centre)
		run_test_light(&world, tuning)
		testing.expect_value(t, field_world_get_light(&world, other, .Block), test_emitter_level("torch"))
		testing.expect(t, field_world_get_light(&world, centre, .Block) < test_emitter_level("torch"))
		remove_field_light_source(&world, other)
		run_test_light(&world, tuning)
		testing.expectf(t, every_block_light_is_zero(&world), "%d mm: light is left", spacing)
	}
}

// The planet of the sky tests: its relief's top is the top sample of the
// test chunks' layer, so a march leaves the shell there and never reads
// the generation.
light_test_sky_planet :: proc() -> Field_Water_Planet {
	spacing := sample_axis_to_position(1, 1000)
	top := sample_axis_to_position(light_test_origin().y + FIELD_CHUNK_SIZE - 1, 1000)
	return Field_Water_Planet{generation = Planet_Generation{radius = top - metres_to_position_units(MAXIMUM_RELIEF_METRES) - spacing, spacing_millimetres = 1000, spacing = spacing}}
}

// Ground up to floor (local y), air above it under full sky, as the
// generation makes it.
make_sky_test_world :: proc(last_x, last_z, floor: i32) -> Field_World {
	world := make_light_test_world(last_x, last_z)
	world.water_planet = light_test_sky_planet()
	origin := light_test_origin()
	carve_light_test_box(&world, origin + {0, floor + 1, 0}, origin + {(last_x + 1) * FIELD_CHUNK_SIZE - 1, FIELD_CHUNK_SIZE - 1, (last_z + 1) * FIELD_CHUNK_SIZE - 1})
	for _, chunk in world.chunks {
		light_generated_field_chunk(chunk)
	}
	return world
}

set_test_samples :: proc(world: ^Field_World, low, high: Sample_Coordinate, value: Field_Sample) {
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				field_world_set_sample(world, {x, y, z}, value)
			}
		}
	}
}

@(test)
test_sky_light_is_full_under_open_sky_and_comes_under_an_overhang_from_its_mouth :: proc(t: ^testing.T) {
	world := make_sky_test_world(1, 0, 8)
	defer destroy_field_world(&world)
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	origin := light_test_origin()
	open := origin + {8, 10, 16}
	testing.expect(t, field_sky_is_open(&world, world.water_planet.generation, open))
	// A 2 m roof from x 16 on, placed as an edit; the air under it opens
	// towards -x only (the other sides are the loaded region's edge).
	set_test_samples(&world, origin + {16, 12, 0}, origin + {63, 13, 31}, LIGHT_TEST_STONE)
	update_field_sky_after_edits(&world)
	run_test_light(&world, tuning)
	testing.expect_value(t, field_world_get_light(&world, open, .Sky), FIELD_LIGHT_FULL)
	mouth := origin + {17, 10, 16}
	testing.expect(t, !field_sky_is_open(&world, world.water_planet.generation, mouth))
	mouth_light := field_world_get_light(&world, mouth, .Sky)
	testing.expectf(t, mouth_light > tuning.dark_level && mouth_light < FIELD_LIGHT_FULL, "the mouth has %d", mouth_light)
	deep := origin + {50, 10, 16}
	testing.expectf(t, field_world_get_light(&world, deep, .Sky) <= tuning.dark_level, "the depth has %d", field_world_get_light(&world, deep, .Sky))
	// Above the roof the sky is still full.
	testing.expect_value(t, field_world_get_light(&world, origin + {30, 14, 16}, .Sky), FIELD_LIGHT_FULL)
}

@(test)
test_a_shaft_dug_from_the_surface_lights_the_samples_below_it_and_nothing_beside :: proc(t: ^testing.T) {
	world := make_sky_test_world(0, 0, 20)
	defer destroy_field_world(&world)
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	origin := light_test_origin()
	// A closed pocket beside the shaft, a sample of stone between them.
	carve_light_test_box(&world, origin + {18, 6, 15}, origin + {20, 9, 17})
	set_test_samples(&world, origin + {16, 5, 16}, origin + {16, 20, 16}, FIELD_AIR_SAMPLE)
	update_field_sky_after_edits(&world)
	run_test_light(&world, tuning)
	for y in i32(5) ..= 20 {
		testing.expectf(t, field_world_get_light(&world, origin + {16, y, 16}, .Sky) == FIELD_LIGHT_FULL, "the shaft at %d is not under full sky", y)
		for side in ([4][3]i32{{-1, 0, 0}, {1, 0, 0}, {0, 0, -1}, {0, 0, 1}}) {
			testing.expect_value(t, field_world_get_light(&world, origin + {16, y, 16} + Sample_Coordinate(side), .Sky), 0)
		}
	}
	testing.expect_value(t, field_world_get_light(&world, origin + {18, 7, 16}, .Sky), 0)
	// Filling the shaft's top shades it again, and the fill brings back
	// nothing (the shaft is closed).
	set_test_samples(&world, origin + {16, 20, 16}, origin + {16, 20, 16}, LIGHT_TEST_STONE)
	update_field_sky_after_edits(&world)
	run_test_light(&world, tuning)
	testing.expect_value(t, field_world_get_light(&world, origin + {16, 12, 16}, .Sky), 0)
}

// The edits of the determinism tests: a torch, a dug shaft and a room,
// a roof, the torch moved.
apply_light_test_edits :: proc(world: ^Field_World, tuning: Field_Light_Tuning, steps_per_tick: int) -> (ticks: int) {
	origin := light_test_origin()
	step :: proc(world: ^Field_World, tuning: Field_Light_Tuning, steps_per_tick: int, ticks: ^int) {
		update_field_sky_after_edits(world)
		for {
			ticks^ += 1
			propagate_field_light(world, tuning, steps_per_tick)
			if pending_field_light_nodes(world) == 0 {
				return
			}
		}
	}
	set_test_samples(world, origin + {10, 4, 10}, origin + {24, 8, 24}, FIELD_AIR_SAMPLE)
	set_test_samples(world, origin + {16, 9, 16}, origin + {16, 12, 16}, FIELD_AIR_SAMPLE)
	add_field_light_source(world, origin + {12, 5, 12}, test_emitter_level("torch"))
	step(world, tuning, steps_per_tick, &ticks)
	set_test_samples(world, origin + {0, 14, 0}, origin + {31, 14, 31}, LIGHT_TEST_STONE)
	remove_field_light_source(world, origin + {12, 5, 12})
	add_field_light_source(world, origin + {22, 5, 22}, test_emitter_level("lamp"))
	step(world, tuning, steps_per_tick, &ticks)
	return ticks
}

light_bytes_equal :: proc(first, second: ^Field_World) -> bool {
	for coordinate, chunk in first.chunks {
		other := second.chunks[coordinate] or_else nil
		if other == nil || !slice.equal(chunk.block_light[:], other.block_light[:]) || !slice.equal(chunk.sky_light[:], other.sky_light[:]) {
			return false
		}
	}
	return len(first.chunks) == len(second.chunks)
}

@(test)
test_the_same_edits_on_two_worlds_give_the_same_light_bytes :: proc(t: ^testing.T) {
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	first := make_sky_test_world(0, 0, 12)
	defer destroy_field_world(&first)
	second := make_sky_test_world(0, 0, 12)
	defer destroy_field_world(&second)
	apply_light_test_edits(&first, tuning, tuning.steps_per_tick)
	apply_light_test_edits(&second, tuning, tuning.steps_per_tick)
	testing.expect(t, light_bytes_equal(&first, &second))
	testing.expect(t, field_world_get_light(&first, light_test_origin() + {22, 5, 22}, .Block) == test_emitter_level("lamp"))
}

@(test)
test_a_light_spread_over_ticks_ends_as_one_unbounded_run :: proc(t: ^testing.T) {
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	bounded := make_sky_test_world(0, 0, 12)
	defer destroy_field_world(&bounded)
	unbounded := make_sky_test_world(0, 0, 12)
	defer destroy_field_world(&unbounded)
	ticks := apply_light_test_edits(&bounded, tuning, 50)
	testing.expectf(t, ticks > 10, "the budget spread over %d ticks only", ticks)
	apply_light_test_edits(&unbounded, tuning, max(int))
	testing.expect(t, light_bytes_equal(&bounded, &unbounded))
}

@(test)
test_an_arriving_chunk_takes_its_neighbours_light_and_its_emitters_shine :: proc(t: ^testing.T) {
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	world := make_light_test_world(0, 0)
	defer destroy_field_world(&world)
	origin := light_test_origin()
	carve_light_test_box(&world, origin + {20, 10, 10}, origin + {31, 12, 12})
	add_field_light_source(&world, origin + {30, 11, 11}, test_emitter_level("torch"))
	// An emitter registered while its chunk is away.
	away := origin + {40, 11, 11}
	add_field_light_source(&world, away, test_emitter_level("torch"))
	run_test_light(&world, tuning)
	arriving := new(Field_Chunk)
	arriving.coordinate = {1, LIGHT_TEST_CHUNK_Y, 0}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		field_chunk_set_sample(arriving, index, LIGHT_TEST_STONE)
	}
	for z in i32(10) ..= 12 {
		for y in i32(10) ..= 12 {
			for x in i32(0) ..= 12 {
				field_chunk_set_sample(arriving, field_local_to_index({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	field_world_insert_chunk(&world, arriving)
	testing.expect_value(t, field_world_get_light(&world, origin + {32, 11, 11}, .Block), 0)
	for pending_field_light_nodes(&world) > 0 || len(world.light.arrived_chunks) > 0 {
		tick_field_light(&world, tuning)
	}
	testing.expect_value(t, field_world_get_light(&world, away, .Block), test_emitter_level("torch"))
	across := field_world_get_light(&world, origin + {32, 11, 11}, .Block)
	testing.expectf(t, across > tuning.dark_level, "the sample across the border has %d", across)
}

// Ground placed above the relief's shell (a roof on a tall build) shades
// the samples under it: the march goes on through the loaded chunks
// above the shell and ends at the first missing one.
@(test)
test_a_roof_above_the_relief_shell_darkens_the_sky_under_it :: proc(t: ^testing.T) {
	world := make_sky_test_world(0, 0, 8)
	defer destroy_field_world(&world)
	tuning := make_field_light_tuning(test_lighting_file(), 1000)
	above := new(Field_Chunk)
	above.coordinate = {0, LIGHT_TEST_CHUNK_Y + 1, 0}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		field_chunk_set_sample(above, index, FIELD_AIR_SAMPLE)
	}
	light_generated_field_chunk(above)
	field_world_insert_chunk(&world, above)
	clear(&world.light.arrived_chunks)
	origin := light_test_origin()
	under := origin + {16, 12, 16}
	testing.expect_value(t, field_world_get_light(&world, under, .Sky), FIELD_LIGHT_FULL)
	// The whole loaded column is roofed, so no light comes in from a side.
	set_test_samples(&world, origin + {0, FIELD_CHUNK_SIZE + 5, 0}, origin + {31, FIELD_CHUNK_SIZE + 5, 31}, LIGHT_TEST_STONE)
	update_field_sky_after_edits(&world)
	run_test_light(&world, tuning)
	testing.expect(t, !field_sky_is_open(&world, world.water_planet.generation, under))
	testing.expect_value(t, field_world_get_light(&world, under, .Sky), 0)
	testing.expect_value(t, field_world_get_light(&world, origin + {16, FIELD_CHUNK_SIZE + 6, 16}, .Sky), FIELD_LIGHT_FULL)
}

// The arrived chunks are a set: a chunk inserted twice is seeded once,
// and one that left before its turn is dropped without spending the
// budget.
@(test)
test_the_arrived_chunks_are_a_set_that_skips_chunks_gone :: proc(t: ^testing.T) {
	world := make_light_test_world(1, 0)
	defer destroy_field_world(&world)
	gone := Field_Chunk_Coordinate{-1, LIGHT_TEST_CHUNK_Y, 0}
	world.light.arrived_chunks[gone] = {}
	for _ in 0 ..< 2 {
		again := new(Field_Chunk)
		again.coordinate = {1, LIGHT_TEST_CHUNK_Y, 0}
		field_world_insert_chunk(&world, again)
	}
	testing.expect_value(t, len(world.light.arrived_chunks), 2)
	seed_arrived_field_chunks(&world, 1)
	testing.expect_value(t, len(world.light.arrived_chunks), 0)
}
