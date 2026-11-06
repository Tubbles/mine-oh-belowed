package game

import "core:fmt"
import "core:math"
import "core:slice"
import "core:testing"

// Work item 0294: the water's look. The worlds are 0292's and 0293's test
// chunks far up the +y axis; a mesh's positions at spacing 1000 are in
// samples from the chunk's origin.

LOOK_TEST_CHUNK :: Field_Chunk_Coordinate{0, WATER_TEST_CHUNK_Y, 0}

// The water mesh of the chunk, gathered as the streaming gathers it.
look_test_mesh :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, waves: Field_Wave_Heights = nil) -> Field_Mesh_Data {
	grid := gather_field_grid(world, coordinate, waves, context.temp_allocator)
	return mesh_field_water_grid(grid, TEST_FIELD_PALETTE[:], 1000, context.temp_allocator)
}

nearest_water_vertex_distance :: proc(mesh: Field_Mesh_Data, local: [3]f32) -> f32 {
	nearest := max(f32)
	for position in mesh.positions {
		difference := position - local
		nearest = min(nearest, math.sqrt(difference.x * difference.x + difference.y * difference.y + difference.z * difference.z))
	}
	return nearest
}

mesh_data_equal :: proc(first, second: Field_Mesh_Data) -> bool {
	return(
		slice.equal(first.positions[:], second.positions[:]) &&
		slice.equal(first.normals[:], second.normals[:]) &&
		slice.equal(first.colors[:], second.colors[:]) &&
		slice.equal(first.lights[:], second.lights[:]) &&
		slice.equal(first.weights[:], second.weights[:]) &&
		slice.equal(first.looks[:], second.looks[:]) &&
		slice.equal(first.indices[:], second.indices[:]) \
	)
}

// The shipped water_look (data/game.sjson), checked against the file in
// test_water_look_values_are_bounded.
SHIPPED_WATER_LOOK :: Water_Look_Config {
	waves                = true,
	wave_speed_percent   = 25,
	wave_damping_percent = 98,
	wave_clamp_percent   = 15,
	wave_kick_percent    = 20,
}

// The highest surface sample of the column at local x, z.
look_test_surface_sample :: proc(world: ^Field_World, x, z: i32) -> (Sample_Coordinate, bool) {
	for y := i32(FIELD_CHUNK_SIZE - 1); y >= 0; y -= 1 {
		sample := water_test_sample({x, y, z})
		if field_wave_surface_sample(world, sample) {
			return sample, true
		}
	}
	return {}, false
}

// 0293's trough between two lakes: once the trough holds A's water, A's
// weir pours a stream from its spill into B's air, which falls two
// samples onto B's water and joins it. Every tick for 20 ticks, every
// moving front sample has the water mesh within a sample of its centre.
@(test)
test_a_moving_stream_has_mesh_within_a_sample_of_every_wet_sample :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_trough_test_lakes(&world, 0)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 300) < 300)
	dig_test_trough(&world, 0)
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
		if water_fill_at(&world, water_test_sample({11, 9, 7})) > 0 {
			break
		}
	}
	testing.expect(t, water_fill_at(&world, water_test_sample({11, 9, 7})) > 0, "the trough holds water")
	chunk := world.chunks[LOOK_TEST_CHUNK]
	moving := 0
	farthest: f32 = 0
	for _ in 0 ..< 20 {
		tick += 1
		step_field_water(&world, tuning, tick)
		mesh := look_test_mesh(&world, LOOK_TEST_CHUNK)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water[index] == 0 || chunk.water_moved[index] == 0 || !field_water_is_front(chunk, index) {
				continue
			}
			local := field_index_to_local(index)
			distance := nearest_water_vertex_distance(mesh, {f32(local.x), f32(local.y), f32(local.z)})
			testing.expectf(t, distance <= 1.0, "tick %d: the moving sample %v (fill %d) has its nearest water vertex %v samples away", tick, local, chunk.water[index], distance)
			farthest = max(farthest, distance)
			moving += 1
		}
	}
	fmt.printfln("0294: %d moving front samples over 20 ticks, the farthest %v samples from the water mesh", moving, farthest)
	testing.expectf(t, moving >= 4, "the stream runs (%d moving samples)", moving)
}

@(test)
test_a_settled_lakes_water_mesh_repeats_byte_for_byte :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	chunk := world.chunks[LOOK_TEST_CHUNK]
	chunk.dirty = false
	tuning := water_body_test_tuning()
	first: Field_Mesh_Data
	for round in 0 ..< 4 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect(t, !chunk.dirty, "a settled lake marks nothing")
		mesh := look_test_mesh(&world, LOOK_TEST_CHUNK)
		testing.expect(t, len(mesh.positions) > 0)
		if round == 0 {
			first = mesh
		} else {
			testing.expect(t, mesh_data_equal(mesh, first), "the mesh repeats")
		}
	}
}

@(test)
test_a_one_sample_wall_holds_the_water_in :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	carve_water_test_box(&world, water_test_sample({2, 3, 4}), water_test_sample({2, 31, 11}))
	pour_test_water(&world, water_test_sample(BASIN_LOW), water_test_sample({BASIN_HIGH.x, 12, BASIN_HIGH.z}), FIELD_WATER_FULL)
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, water_body_test_tuning(), &tick, 300) < 300)
	_, _ = only_water_body(t, &world)
	mesh := look_test_mesh(&world, LOOK_TEST_CHUNK)
	lowest := max(f32)
	drawn := false
	for position in mesh.positions {
		lowest = min(lowest, position.x)
		drawn ||= position.x > 3.5
	}
	fmt.printfln("0294: the lake's water mesh reaches x %v against the wall's outer face at 2.5", lowest)
	testing.expectf(t, lowest >= 2.55, "a water vertex at x %v lies beyond the wall", lowest)
	testing.expect(t, drawn, "the lake is drawn")
}

@(test)
test_a_drained_basin_leaves_no_film_on_its_walls :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	// A puddle of 1500 fill on the floor's 64 cells.
	intake := water_test_sample({7, 3, 7})
	for body.volume > 1500 {
		displace_water_body_volume(&world, id, intake, min(10_000, body.volume - 1500))
	}
	tuning := water_body_test_tuning()
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body = &world.water_bodies[id]
	volume := conserved_water(&world)
	depth := f32(body.level - field_water_bottom(field_water_span(intake))) / FIELD_WATER_FULL
	mesh := look_test_mesh(&world, LOOK_TEST_CHUNK)
	testing.expect(t, len(mesh.positions) > 0, "the puddle is drawn")
	highest: f32 = 0
	for position in mesh.positions {
		highest = max(highest, position.y)
		testing.expectf(t, position.y <= 2.5 + depth + 0.1, "a water vertex at %v stands over the puddle's %v", position, 2.5 + depth)
		// The plane reaches a sample into the ground round the floor, where
		// the terrain covers it; nothing climbs the walls.
		testing.expectf(t, position.x >= 2.5 && position.x <= 12.5 && position.z >= 2.5 && position.z <= 12.5, "a water vertex at %v lies off the basin's floor", position)
	}
	fmt.printfln("0294: the drained basin's water mesh tops out at y %v over the puddle's %v", highest, 2.5 + depth)
	testing.expect_value(t, conserved_water(&world), volume)
}

@(test)
test_a_bodys_chunks_remesh_only_when_the_level_crosses_a_thirty_second :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	chunk := world.chunks[LOOK_TEST_CHUNK]
	testing.expect_value(t, body.meshed_level, body.level)
	chunk.dirty = false
	level := body.level
	intake := water_test_sample({7, 3, 7})
	displace_water_body_volume(&world, id, intake, 64)
	write_water_body_fills(&world, id, false)
	testing.expectf(t, level - body.level < FIELD_WATER_LOOK_LEVEL_STEP, "the level fell by %d", level - body.level)
	testing.expect(t, !chunk.dirty, "a fall under the step marks nothing")
	displace_water_body_volume(&world, id, intake, 64 * (FIELD_WATER_LOOK_LEVEL_STEP + 1))
	testing.expect(t, level - body.level >= FIELD_WATER_LOOK_LEVEL_STEP)
	testing.expect(t, chunk.dirty, "a fall over the step marks the chunk")
	testing.expect_value(t, body.meshed_level, body.level)
}

@(test)
test_the_moved_stamp_expires_after_six_ticks_and_marks_once :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	lower, upper := water_test_sample({7, 3, 7}), water_test_sample({7, 4, 7})
	carve_water_test_box(&world, lower, upper)
	chunk := world.chunks[LOOK_TEST_CHUNK]
	set_field_water(&world, chunk, sample_to_field_index(upper), upper, 100)
	testing.expect_value(t, chunk.water_moved[sample_to_field_index(upper)], u8(FIELD_WATER_MOVED_TICKS))
	tuning := water_test_tuning()
	expiries := 0
	for tick in u64(1) ..= 200 {
		before := [2]u8{chunk.water_moved[sample_to_field_index(lower)], chunk.water_moved[sample_to_field_index(upper)]}
		chunk.dirty = false
		step_field_water(&world, tuning, tick)
		for sample, slot in ([2]Sample_Coordinate{lower, upper}) {
			index := sample_to_field_index(sample)
			if before[slot] == 1 && chunk.water_moved[index] == 0 {
				expiries += 1
				testing.expectf(t, chunk.dirty, "tick %d: the stamp of %v expired without a mark", tick, sample)
			}
			if !field_sample_bit(&chunk.water_awake, index) {
				testing.expect_value(t, chunk.water_moved[index], 0)
			}
		}
	}
	testing.expect(t, expiries >= 2, "both stamps expired")
	testing.expect(t, !any_water_awake(&world), "the water slept")

	first, second := make_ground_water_test_chunk(0), make_ground_water_test_chunk(0)
	defer free(first)
	defer free(second)
	second.water_moved[5] = 3
	testing.expect_value(t, field_chunk_state_hash(first), field_chunk_state_hash(second))
	testing.expect(t, slice.equal(encode_field_chunk(first, context.temp_allocator), encode_field_chunk(second, context.temp_allocator)))
	testing.expect(t, field_chunk_equals(first, second))
}

// The settled lake's waves: the centre's impact, then the waves' own
// steps, the water and the hash untouched throughout.
@(test)
test_waves_change_no_fill_byte_and_no_hash :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	chunk := world.chunks[LOOK_TEST_CHUNK]
	waves := Field_Waves {
		tuning    = make_field_wave_tuning(SHIPPED_WATER_LOOK),
		last_tick = tick,
	}
	defer destroy_field_waves(&waves)
	still := look_test_mesh(&world, LOOK_TEST_CHUNK)
	hash := field_chunk_state_hash(chunk)
	bytes := chunk.water
	centre, found := look_test_surface_sample(&world, 7, 7)
	testing.expect(t, found, "the lake has a surface")
	clear(&world.water_events)
	push_field_water_event(&world, .Impact, centre, FIELD_WATER_FULL)
	tick += 1
	advance_field_waves(&waves, &world, tick)
	centre_velocity := waves.heights[LOOK_TEST_CHUNK].velocity[sample_to_field_index(centre)]
	testing.expectf(t, centre_velocity < 0, "the impact pushed the centre down (%v)", centre_velocity)
	for neighbour in field_wave_tangential_neighbours(centre) {
		testing.expect(t, waves.heights[LOOK_TEST_CHUNK].velocity[sample_to_field_index(neighbour)] > 0)
	}
	tuning := water_body_test_tuning()
	differed := false
	emptied_tick: u64 = 0
	peak: f32 = 0
	marks, wave_ticks := 0, 0
	for _ in 0 ..< 600 {
		tick += 1
		step_field_water(&world, tuning, tick)
		chunk.wave_dirty = false
		advance_field_waves(&waves, &world, tick)
		marks += chunk.wave_dirty ? 1 : 0
		if entry := waves.heights[LOOK_TEST_CHUNK] or_else nil; entry != nil {
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				if abs(entry.height[index]) > waves.tuning.clamp || abs(entry.velocity[index]) > waves.tuning.velocity_clamp {
					testing.expectf(t, false, "tick %d: a wave over its clamp", tick)
				}
				peak = max(peak, abs(entry.height[index]))
			}
		}
		testing.expect(t, chunk.water == bytes, "the waves write no fill byte")
		testing.expect_value(t, field_chunk_state_hash(chunk), hash)
		if len(waves.active) > 0 {
			wave_ticks += 1
			if !differed && !mesh_data_equal(look_test_mesh(&world, LOOK_TEST_CHUNK, waves.heights), still) {
				differed = true
			}
		} else if emptied_tick == 0 {
			emptied_tick = tick
		}
	}
	fmt.printfln("0294: the impact's waves peaked at %v samples and came to rest after %d ticks, the chunk marked on %d of them", peak, emptied_tick, marks)
	testing.expect(t, differed, "the waves move the mesh")
	testing.expect(t, marks > 0 && marks <= wave_ticks + 1, "the chunk is marked while its offsets change")
	testing.expect_value(t, len(waves.active), 0)
	testing.expect_value(t, len(waves.heights), 0)
	testing.expect(t, mesh_data_equal(look_test_mesh(&world, LOOK_TEST_CHUNK, waves.heights), still), "at rest the mesh is the still one")

	off := Field_Waves {
		tuning    = make_field_wave_tuning(Water_Look_Config{waves = false, wave_speed_percent = 25, wave_damping_percent = 98, wave_clamp_percent = 15, wave_kick_percent = 20}),
		last_tick = tick,
	}
	defer destroy_field_waves(&off)
	push_field_water_event(&world, .Impact, centre, FIELD_WATER_FULL)
	advance_field_waves(&off, &world, tick + 1)
	testing.expect_value(t, len(off.heights), 0)
}

field_waves_equal :: proc(first, second: ^Field_Waves) -> bool {
	if len(first.heights) != len(second.heights) || len(first.active) != len(second.active) {
		return false
	}
	for coordinate, entry in first.heights {
		other := second.heights[coordinate] or_else nil
		if other == nil || entry.active != other.active || entry.height != other.height || entry.velocity != other.velocity {
			return false
		}
	}
	return true
}

@(test)
test_the_wave_cadence_follows_the_tick :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	tuning := make_field_wave_tuning(SHIPPED_WATER_LOOK)
	caught_up := Field_Waves {
		tuning    = tuning,
		last_tick = tick,
	}
	stepped := caught_up
	defer destroy_field_waves(&caught_up)
	defer destroy_field_waves(&stepped)
	centre, _ := look_test_surface_sample(&world, 7, 7)
	clear(&world.water_events)
	push_field_water_event(&world, .Impact, centre, FIELD_WATER_FULL)
	advance_field_waves(&caught_up, &world, tick + 1)
	advance_field_waves(&stepped, &world, tick + 1)
	clear(&world.water_events)
	testing.expect(t, len(caught_up.active) > 0)
	testing.expect(t, field_waves_equal(&caught_up, &stepped))
	before := new(Field_Wave_Chunk, context.temp_allocator)
	before^ = caught_up.heights[LOOK_TEST_CHUNK]^
	advance_field_waves(&caught_up, &world, tick + 1)
	after := caught_up.heights[LOOK_TEST_CHUNK]
	testing.expect(t, before.height == after.height && before.velocity == after.velocity, "a frame without a tick moves nothing")
	advance_field_waves(&caught_up, &world, tick + 11)
	for step in u64(2) ..= 5 {
		advance_field_waves(&stepped, &world, tick + step)
	}
	testing.expect(t, field_waves_equal(&caught_up, &stepped), "ten ticks ahead step four times")
}

// The look reach (fix round, 2026-11-06): a tunnel across the border of
// chunks 0 and 1. Water set at chunk 0's local x 31, 30 and 29, and the
// terrain dug beside it, change chunk 1's full resolution grid, and chunk
// 1 is marked every time it does; a change further in marks only chunk 0
// and leaves chunk 1's grid as it was.
@(test)
test_a_change_within_three_samples_of_a_border_marks_the_neighbour :: proc(t: ^testing.T) {
	world := make_water_test_world(2)
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample({24, 3, 6}), water_test_sample({FIELD_CHUNK_SIZE + 6, 6, 8}))
	first := world.chunks[LOOK_TEST_CHUNK]
	second_coordinate := LOOK_TEST_CHUNK + {1, 0, 0}
	second := world.chunks[second_coordinate]
	changed := 0
	for x in ([?]i32{31, 30, 29, 28, 27, 26}) {
		sample := water_test_sample({x, 3, 7})
		// Poured, then taken again, so each probe starts from a dry tunnel.
		for fill in ([2]i32{200, 0}) {
			before := gather_field_grid(&world, second_coordinate, nil, context.temp_allocator)
			first.dirty, second.dirty = false, false
			set_field_water(&world, first, sample_to_field_index(sample), sample, fill)
			after := gather_field_grid(&world, second_coordinate, nil, context.temp_allocator)
			testing.expectf(t, first.dirty, "x %d: the sample's own chunk is marked", x)
			if before.water != after.water {
				changed += 1
				testing.expectf(t, second.dirty, "x %d: the neighbour's grid changed without a mark", x)
			}
			testing.expect_value(t, second.dirty, x >= FIELD_CHUNK_SIZE - FIELD_LOOK_REACH)
		}
	}
	testing.expectf(t, changed >= 4, "the water within reach changed the neighbour's grid (%d)", changed)
	fmt.printfln("0294: %d of the 12 water probes changed the neighbour's grid", changed)
	// The terrain: ground set back under the water at local x 29.
	ground := water_test_sample({29, 4, 6})
	before := gather_field_grid(&world, second_coordinate, nil, context.temp_allocator)
	second.dirty = false
	testing.expect(t, field_world_set_sample(&world, ground, {MAXIMUM_DENSITY, .Stone, 0}))
	after := gather_field_grid(&world, second_coordinate, nil, context.temp_allocator)
	testing.expect(t, second.dirty, "a terrain change within reach marks the neighbour")
	fmt.printfln("0294: the terrain at local x 29 changed the neighbour's water grid: %v", before.water != after.water)
	free_all(context.temp_allocator)
}

// A lake in chunk 0 against its +x border, chunk 1 all ground: a level
// move over the look step and a flood's release mark chunk 1 too, whose
// grid reads the lake's samples; a lake far from the border marks only
// its own chunk.
@(test)
test_a_body_marks_the_neighbours_its_samples_reach :: proc(t: ^testing.T) {
	for near in ([2]bool{true, false}) {
		world := make_body_test_world(2)
		defer destroy_field_world(&world)
		low_x := near ? i32(26) : i32(4)
		low, high := water_test_sample({low_x, 3, 4}), water_test_sample({low_x + 5, 12, 11})
		carve_water_test_box(&world, low, high)
		pour_test_water(&world, low, water_test_sample({low_x + 5, 8, 11}), FIELD_WATER_FULL)
		tick: u64 = 0
		testing.expect(t, settle_body_test_water(&world, water_body_test_tuning(), &tick, 200) < 200)
		body, id := only_water_body(t, &world)
		if body == nil {
			return
		}
		first, second := world.chunks[LOOK_TEST_CHUNK], world.chunks[LOOK_TEST_CHUNK + {1, 0, 0}]
		testing.expect_value(t, len(body.chunks), 1)
		first.dirty, second.dirty = false, false
		displace_water_body_volume(&world, id, water_test_sample({low_x + 2, 3, 7}), 64 * (FIELD_WATER_LOOK_LEVEL_STEP + 1))
		write_water_body_fills(&world, id, false)
		testing.expect(t, first.dirty, "the level's move marks the body's chunk")
		testing.expect_value(t, second.dirty, near)
		first.dirty, second.dirty = false, false
		release_water_body_samples(&world, id)
		testing.expect(t, first.dirty, "the release marks the body's chunk")
		testing.expect_value(t, second.dirty, near)
	}
}

// A lake across the border of chunks 0 and 1 struck at chunk 0's local x
// 31: every tick each chunk meshes again when marked (its grid kept), and
// its grid as the gather would make it now is the one kept, so no wave
// is drawn stale on either side; both are marked, and at rest both hold
// the still grid again.
@(test)
test_a_wave_at_a_border_remeshes_both_nodes :: proc(t: ^testing.T) {
	world := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	pour_test_water(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, water_body_test_tuning(), &tick, 200) < 200)
	coordinates := [2]Field_Chunk_Coordinate{LOOK_TEST_CHUNK, LOOK_TEST_CHUNK + {1, 0, 0}}
	still, kept: [2]^Field_Grid
	for coordinate, slot in coordinates {
		still[slot] = gather_field_grid(&world, coordinate)
		kept[slot] = gather_field_grid(&world, coordinate)
	}
	defer {
		for slot in 0 ..< 2 {
			free(still[slot])
			free(kept[slot])
		}
	}
	waves := Field_Waves {
		tuning    = make_field_wave_tuning(SHIPPED_WATER_LOOK),
		last_tick = tick,
	}
	defer destroy_field_waves(&waves)
	surface: Sample_Coordinate
	found := false
	for y := i32(FIELD_CHUNK_SIZE - 1); y >= 0 && !found; y -= 1 {
		surface = water_test_sample({FIELD_CHUNK_SIZE - 1, y, 7})
		found = field_wave_surface_sample(&world, surface)
	}
	testing.expect(t, found, "the lake has a surface at the border")
	clear(&world.water_events)
	push_field_water_event(&world, .Impact, surface, FIELD_WATER_FULL)
	marks: [2]int
	unchanged := 0
	for _ in 0 ..< 600 {
		for coordinate in coordinates {
			world.chunks[coordinate].wave_dirty = false
		}
		tick += 1
		advance_field_waves(&waves, &world, tick)
		clear(&world.water_events)
		for coordinate, slot in coordinates {
			now := gather_field_grid(&world, coordinate, waves.heights, context.temp_allocator)
			if world.chunks[coordinate].wave_dirty {
				marks[slot] += 1
				unchanged += kept[slot].water == now.water ? 1 : 0
				kept[slot]^ = now^
			}
			testing.expectf(t, kept[slot].water == now.water, "tick %d: chunk %v draws a stale wave", tick, coordinate)
		}
		free_all(context.temp_allocator)
		if len(waves.heights) == 0 {
			break
		}
	}
	fmt.printfln("0294: the border wave marked the chunks %v times, %d of the marks on an unchanged grid", marks, unchanged)
	testing.expect_value(t, len(waves.heights), 0)
	for slot in 0 ..< 2 {
		testing.expectf(t, marks[slot] > 0, "chunk %v remeshed for the wave", coordinates[slot])
		testing.expect(t, kept[slot].water == still[slot].water, "at rest the kept grid is the still one")
	}
}

// Marks on change, by sample (fix rounds, 2026-11-06): a wave sample
// whose height rounds to the same density steps marks nothing; a changed
// sample deep inside chunk 0 marks chunk 0 alone though another of its
// samples lies at x 30; a change at x 30 marks both chunks; the step that
// brings the border sample to rest marks both once more and the entry is
// freed.
@(test)
test_waves_mark_a_chunk_only_when_its_baked_offsets_change :: proc(t: ^testing.T) {
	world := make_water_test_world(2)
	defer destroy_field_world(&world)
	first, second := world.chunks[LOOK_TEST_CHUNK], world.chunks[LOOK_TEST_CHUNK + {1, 0, 0}]
	waves := Field_Waves {
		tuning = make_field_wave_tuning(SHIPPED_WATER_LOOK),
	}
	defer destroy_field_waves(&waves)
	entry, inner := activate_field_wave_cell(&waves, water_test_sample({10, 5, 5}))
	_, border := activate_field_wave_cell(&waves, water_test_sample({FIELD_CHUNK_SIZE - 2, 5, 5}))
	marked :: proc(waves: ^Field_Waves, world: ^Field_World, first, second: ^Field_Chunk) -> [2]bool {
		mark_field_wave_changes(waves, world)
		result := [2]bool{first.wave_dirty, second.wave_dirty}
		first.wave_dirty, second.wave_dirty = false, false
		return result
	}
	entry.height[inner] = 0.001
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{false, false})
	entry.height[inner], entry.height[border] = 0.1, 0.1
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{true, true})
	entry.height[inner] = 0.2
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{true, false})
	entry.height[inner] = 0.2001
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{false, false})
	entry.height[border] = -0.05
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{true, true})
	entry.height[inner] = 0
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{true, false})
	// The border sample at rest after one step: no ground sample is on the
	// surface, so neither sample pulls on another.
	entry.height[border] = 0.001
	entry.velocity[inner], entry.velocity[border] = 0, 0
	step_field_waves(&waves, &world)
	testing.expect_value(t, len(waves.active), 0)
	testing.expect_value(t, marked(&waves, &world, first, second), [2]bool{true, true})
	testing.expect_value(t, len(waves.heights), 0)
}

// An owner with no live body (0294's second fix round): its still water
// draws as front water, sheet and all, so the gather is the one with no
// owner, and none of it counts as a body's interior.
@(test)
test_still_water_of_a_dead_owner_draws_as_the_front :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	low, high := water_test_sample(BASIN_LOW), water_test_sample({BASIN_HIGH.x, 10, BASIN_HIGH.z})
	carve_water_test_box(&world, low, high)
	chunk := world.chunks[LOOK_TEST_CHUNK]
	dead := Water_Owner(len(world.water_bodies) + 7)
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				index := sample_to_field_index({x, y, z})
				chunk.water[index] = y < high.y ? FIELD_WATER_FULL : 100
				chunk.water_owner[index] = dead
			}
		}
	}
	_, owned := water_owner_body(&world, dead)
	testing.expect(t, !owned, "the owner has no live body")
	samples := make_field_look_samples(&world, LOOK_TEST_CHUNK)
	inside := field_look_index({7, 6, 7})
	testing.expect_value(t, samples.still_owner[inside], WATER_OWNER_NONE)
	testing.expect_value(t, samples.interior[6 + FIELD_LOOK_REACH + FIELD_LOOK_SIZE * (7 + FIELD_LOOK_REACH)] >> uint(7 + FIELD_LOOK_REACH) & 1, 0)
	with_owner := gather_field_grid(&world, LOOK_TEST_CHUNK, nil, context.temp_allocator)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		chunk.water_owner[index] = WATER_OWNER_NONE
	}
	without := gather_field_grid(&world, LOOK_TEST_CHUNK, nil, context.temp_allocator)
	testing.expect(t, with_owner.water == without.water, "the dead owner's water draws as the front")
	testing.expect(t, with_owner.water_exact == without.water_exact)
	free_all(context.temp_allocator)
}
