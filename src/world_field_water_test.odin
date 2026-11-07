package game

import "core:math"
import "core:testing"

// The water tests' chunks lie far up the +y axis, so the potential falls
// along -y and a shell is a level layer of samples.
WATER_TEST_CHUNK_Y :: 100

// The plain rule: pressure off and no band, so the older tests assert the
// same bytes as before 0292.
water_test_tuning :: proc() -> Field_Water_Tuning {
	return {rate = 64, still_ticks = 20, minimum_fill = 8, dry_ticks = 60, pressure = false, pressure_visit_budget = 128, pressure_visit_budget_per_tick = 20000, minimum_head = 0}
}

// The shipped pressure values (0292) over the plain tuning.
water_pressure_test_tuning :: proc() -> Field_Water_Tuning {
	tuning := water_test_tuning()
	tuning.pressure, tuning.minimum_head = true, 4
	return tuning
}

field_water_level_at :: proc(world: ^Field_World, sample: Sample_Coordinate) -> i64 {
	return field_water_level(field_water_span(sample), water_fill_at(world, sample))
}

// The level of the highest wet sample of the column, in the test chunks'
// local coordinates.
highest_wet_level_in_column :: proc(world: ^Field_World, x, z, low_y, high_y: i32) -> (level: i64, found: bool) {
	for y := high_y; y >= low_y; y -= 1 {
		sample := water_test_sample({x, y, z})
		if water_fill_at(world, sample) > 0 {
			return field_water_level_at(world, sample), true
		}
	}
	return 0, false
}

// A lake, a sealed tunnel from its bed and a shaft open to air at the
// tunnel's end: the lake at x lake_x..lake_x+7, the tunnel at the bed's
// height, the shaft the sample past it. The lake's twelve lowest layers
// are poured full (768 samples).
carve_water_test_u_tube :: proc(world: ^Field_World, lake_x: i32, tunnel_length: i32) {
	carve_water_test_box(world, water_test_sample({lake_x, 3, 4}), water_test_sample({lake_x + 7, 20, 11}))
	carve_water_test_box(world, water_test_sample({lake_x + 8, 3, 7}), water_test_sample({lake_x + 8 + tunnel_length - 1, 3, 7}))
	carve_water_test_box(world, water_test_sample({lake_x + 8 + tunnel_length, 3, 7}), water_test_sample({lake_x + 8 + tunnel_length, 25, 7}))
	pour_test_water(world, water_test_sample({lake_x, 3, 4}), water_test_sample({lake_x + 7, 14, 11}), FIELD_WATER_FULL)
}

// Steps until no chunk is awake, summing the tick's teleports; returns
// the ticks run, or limit.
settle_test_water_counting_teleports :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: ^u64, limit: int, teleports: ^i64) -> int {
	for ticks in 0 ..< limit {
		if len(world.water_awake_chunks) == 0 {
			return ticks
		}
		tick^ += 1
		step_field_water(world, tuning, tick^)
		teleports^ += world.water_pressure.teleports
	}
	return limit
}

// 0292: a lateral head at or under minimum_head moves nothing, one above
// it moves; a drop into a cell entirely below is never banded.
@(test)
test_the_dead_band_holds_a_head_at_or_under_the_minimum_but_not_a_drop :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	chunk := world.chunks[{0, WATER_TEST_CHUNK_Y, 0}]
	first, second := Sample_Coordinate{0, 3200, 0}, Sample_Coordinate{1, 3200, 0}
	carve_water_test_box(&world, first, second)
	testing.expect_value(t, field_water_span(first), field_water_span(second))
	first_index, second_index := sample_to_field_index(first), sample_to_field_index(second)
	neighbour := Field_Water_Neighbour{chunk = chunk, index = second_index, sample = second, span = field_water_span(second)}
	tuning := water_pressure_test_tuning()
	chunk.water[first_index], chunk.water[second_index] = 100, 96
	testing.expect_value(t, field_water_share(chunk, first_index, field_water_span(first), neighbour, tuning, 100), 0)
	chunk.water[second_index] = 95
	testing.expect_value(t, field_water_share(chunk, first_index, field_water_span(first), neighbour, tuning, 100), 2)
	chunk.water[second_index] = 96
	tuning.minimum_head = 0
	testing.expect_value(t, field_water_share(chunk, first_index, field_water_span(first), neighbour, tuning, 100), 2)

	above := Sample_Coordinate{0, 3201, 0}
	carve_water_test_box(&world, above, above)
	above_index := sample_to_field_index(above)
	chunk.water[above_index], chunk.water[first_index] = 1, 253
	testing.expect(t, field_water_is_drop(field_water_span(above), field_water_span(first)), "the cell below lies entirely under the cell above")
	below := Field_Water_Neighbour{chunk = chunk, index = first_index, sample = first, span = field_water_span(first)}
	tuning.minimum_head = 4
	testing.expect_value(t, field_water_share(chunk, above_index, field_water_span(above), below, tuning, 1), 1)
}

// 0292: with pressure on, a shaft joined to a lake's bed, beside it or
// through a tunnel, fills to the lake's level.
@(test) // slow
test_a_shaft_joined_to_a_lake_bed_rises_to_the_lake_level :: proc(t: ^testing.T) {
	for tunnel_length in ([2]i32{1, 8}) {
		world := make_water_test_world()
		defer destroy_field_world(&world)
		carve_water_test_u_tube(&world, 4, tunnel_length)
		poured := total_test_water(&world)
		testing.expect_value(t, poured, 768 * FIELD_WATER_FULL)
		tuning := water_pressure_test_tuning()
		tick: u64 = 0
		teleports: i64 = 0
		ticks := settle_test_water_counting_teleports(&world, tuning, &tick, 1500, &teleports)
		testing.expectf(t, ticks < 1500, "tunnel %d: the shaft settles in %d ticks", tunnel_length, ticks)
		testing.expectf(t, teleports > 0, "tunnel %d: the shaft fills by teleports", tunnel_length)
		testing.expect_value(t, total_test_water(&world), poured)
		// The band's staircase tilts the lake's surface away from the
		// tunnel's corner (its far corner stands up to 19 fill over the
		// shaft), so the shaft is held against the surface's mean.
		highest, sum := min(i64), i64(0)
		for z in i32(4) ..= 11 {
			for x in i32(4) ..= 11 {
				level, found := highest_wet_level_in_column(&world, x, z, 3, 20)
				testing.expect(t, found, "every lake column holds water")
				highest, sum = max(highest, level), sum + level
			}
		}
		lake := sum / 64
		shaft_x := 12 + tunnel_length
		shaft, shaft_wet := highest_wet_level_in_column(&world, shaft_x, 7, 3, 25)
		testing.expectf(t, shaft_wet, "tunnel %d: the shaft holds water", tunnel_length)
		testing.expectf(t, lake - shaft <= 12 && shaft <= highest + 2, "tunnel %d: the shaft at %d against the lake's mean %d and highest %d (ticks %d, teleports %d)", tunnel_length, shaft, lake, highest, ticks, teleports)
		highest_wet := i32(-1)
		for y in i32(3) ..= 25 {
			if water_fill_at(&world, water_test_sample({shaft_x, y, 7})) > 0 {
				highest_wet = y
			}
		}
		for y in i32(3) ..< highest_wet {
			testing.expect_value(t, water_fill_at(&world, water_test_sample({shaft_x, y, 7})), FIELD_WATER_FULL)
		}
	}
}

// 0292: with pressure off the plain rule fills the tunnel to the band's
// staircase (each sample up to minimum_head under the one before it) and
// nothing rises in the shaft.
@(test)
test_the_shaft_stays_at_the_tunnel_with_pressure_off :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_u_tube(&world, 4, 8)
	poured := total_test_water(&world)
	tuning := water_pressure_test_tuning()
	tuning.pressure = false
	tick: u64 = 0
	for _ in 0 ..< 1500 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect(t, water_fill_at(&world, water_test_sample({19, 3, 7})) >= FIELD_WATER_FULL - 8 * tuning.minimum_head, "the tunnel's end holds the staircase's fill")
	testing.expect_value(t, water_fill_at(&world, water_test_sample({20, 4, 7})), 0)
	testing.expect_value(t, total_test_water(&world), poured)
}

// 0292: a settled lake is still: no awake sample, no search, no move.
@(test)
test_a_settled_lake_stays_asleep :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	pour_test_water(&world, water_test_sample({4, 3, 4}), water_test_sample({8, 3, 7}), FIELD_WATER_FULL)
	poured := total_test_water(&world)
	testing.expect_value(t, poured, 20 * FIELD_WATER_FULL)
	tuning := water_pressure_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 5000) < 5000, "the lake settles")
	for _ in 0 ..< 3000 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect_value(t, len(world.water_awake_chunks), 0)
		testing.expect_value(t, total_test_water(&world), poured)
		testing.expect_value(t, world.water_pressure, Field_Water_Pressure_Counts{})
	}
}

// 0292: a film at a sill dries alone and sleeps; the lake beside it is
// never woken to top it up (the old rule woke the lake every dry step).
@(test)
test_a_film_at_a_sill_dries_without_waking_the_lake :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	pour_test_water(&world, water_test_sample({4, 3, 4}), water_test_sample({11, 9, 11}), FIELD_WATER_FULL)
	// A top layer of 10 fill: the lake gives the sill half, then tops the
	// cell beside it up and levels the sill to the minimum fill, where the
	// band holds (a pour of 12 lifts the sill to 9, no film).
	pour_test_water(&world, water_test_sample({4, 10, 4}), water_test_sample({11, 10, 11}), 10)
	tuning := water_pressure_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 5000) < 5000, "the lake settles")

	// The sill: a hole in the wall at the top layer's height, ground under
	// it, on the wall nearer the centre, so the lake cell beside it lies
	// farther out and the sill is a film by field_water_is_film (on the
	// far wall the lake cell beside it counts as nearer, with room, and the
	// sill never dries).
	sill := water_test_sample({3, 10, 7})
	testing.expect(t, field_world_set_sample(&world, sill, FIELD_AIR_SAMPLE))
	film_seen := false
	for _ in 0 ..< 20 {
		tick += 1
		step_field_water(&world, tuning, tick)
		fill := water_fill_at(&world, sill)
		film_seen ||= fill >= 1 && fill <= tuning.minimum_fill
	}
	testing.expect(t, film_seen, "the lake tops the sill up to a film")
	for _ in 0 ..< 600 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect_value(t, len(world.water_awake_chunks), 0)
	testing.expect_value(t, water_fill_at(&world, sill), 0)
	total := total_test_water(&world)
	for _ in 0 ..< 3000 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect_value(t, len(world.water_awake_chunks), 0)
		testing.expect_value(t, total_test_water(&world), total)
	}
}

// 0292: the search crosses a chunk border, and the two chunks inserted in
// either order give the same bytes, the same failed bits and counts.
@(test) // slow
test_the_pressure_search_crosses_a_chunk_border_alike_in_either_order :: proc(t: ^testing.T) {
	first := make_ground_chunks_water_world({0, 1})
	defer destroy_field_world(&first)
	second := make_ground_chunks_water_world({1, 0})
	defer destroy_field_world(&second)
	tuning := water_pressure_test_tuning()
	for world in ([2]^Field_World{&first, &second}) {
		carve_water_test_u_tube(world, 20, 8)
		tick: u64 = 0
		for _ in 0 ..< 600 {
			tick += 1
			step_field_water(world, tuning, tick)
		}
	}
	for coordinate, chunk in first.chunks {
		other := second.chunks[coordinate]
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(other))
		testing.expect(t, chunk.water_pressure_failed == other.water_pressure_failed)
		testing.expect(t, chunk.water_flow == other.water_flow)
	}
	testing.expect(t, water_fill_at(&first, water_test_sample({36, 4, 7})) > 0, "the search crossed the border")
	testing.expect_value(t, first.water_pressure, second.water_pressure)
}

water_test_sample :: proc(local: [3]i32, chunk_x: i32 = 0) -> Sample_Coordinate {
	return field_chunk_origin({chunk_x, WATER_TEST_CHUNK_Y, 0}) + Sample_Coordinate(local)
}

// A planet of 1000 m whose sea level lies above the test chunks, so a
// missing sample there is air below sea level: sea.
water_test_sea_planet :: proc() -> Field_Water_Planet {
	planet := make_test_planet()
	planet.radius_metres = 1000
	water := make_field_water_planet(TEST_PLANET_SEED, planet, 1000)
	water.sea_level = (WATER_TEST_CHUNK_Y * FIELD_CHUNK_SIZE + 100) * FIELD_WATER_FULL
	return water
}

make_ground_water_test_chunk :: proc(x: i32) -> ^Field_Chunk {
	chunk := new(Field_Chunk)
	chunk.coordinate = {x, WATER_TEST_CHUNK_Y, 0}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		field_chunk_set_sample(chunk, index, {MAXIMUM_DENSITY, .Stone, 0})
	}
	return chunk
}

// Chunks along x at WATER_TEST_CHUNK_Y, every sample ground; the missing
// chunks round them are walls above sea level (the world has no sea).
make_water_test_world :: proc(chunk_count: i32 = 1) -> Field_World {
	world: Field_World
	for x in 0 ..< chunk_count {
		field_world_insert_chunk(&world, make_ground_water_test_chunk(x))
	}
	return world
}

// Air in the box of samples, set straight into the chunks (nothing wakes).
carve_water_test_box :: proc(world: ^Field_World, low, high: Sample_Coordinate) {
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

pour_test_water :: proc(world: ^Field_World, low, high: Sample_Coordinate, fill: i32) {
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				sample := Sample_Coordinate{x, y, z}
				chunk := world.chunks[sample_to_field_chunk_coordinate(sample)]
				set_field_water(world, chunk, sample_to_field_index(sample), sample, fill)
			}
		}
	}
}

// The tests' sink: takes up to amount of the sample's fill.
take_test_water :: proc(world: ^Field_World, sample: Sample_Coordinate, amount: i32) -> i32 {
	chunk := world.chunks[sample_to_field_chunk_coordinate(sample)]
	index := sample_to_field_index(sample)
	taken := min(amount, i32(chunk.water[index]))
	if taken > 0 {
		set_field_water(world, chunk, index, sample, i32(chunk.water[index]) - taken)
	}
	return taken
}

water_fill_at :: proc(world: ^Field_World, sample: Sample_Coordinate) -> i32 {
	chunk := world.chunks[sample_to_field_chunk_coordinate(sample)]
	return i32(chunk.water[sample_to_field_index(sample)])
}

total_test_water :: proc(world: ^Field_World) -> i64 {
	total: i64 = 0
	for _, chunk in world.chunks {
		for fill in chunk.water {
			total += i64(fill)
		}
	}
	return total
}

water_box_total :: proc(world: ^Field_World, low, high: Sample_Coordinate) -> i64 {
	total: i64 = 0
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				total += i64(water_fill_at(world, {x, y, z}))
			}
		}
	}
	return total
}

// Steps until no sample is awake; returns the ticks run, or limit.
settle_test_water :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: ^u64, limit: int) -> int {
	for ticks in 0 ..< limit {
		if len(world.water_awake_chunks) == 0 {
			return ticks
		}
		tick^ += 1
		step_field_water(world, tuning, tick^)
	}
	return limit
}

any_water_awake :: proc(world: ^Field_World) -> bool {
	for _, chunk in world.chunks {
		if field_sample_bits_any(&chunk.water_awake) {
			return true
		}
	}
	return false
}

// A shaft of 8 by 8 samples from local y 3 to the chunk's top, in ground.
BASIN_LOW :: [3]i32{4, 3, 4}
BASIN_HIGH :: [3]i32{11, FIELD_CHUNK_SIZE - 1, 11}

// The overlay's census (0291) sums the fill over the loaded chunks and
// counts the awake samples of the awake chunks; the cubic metres are
// whole cubes of the spacing per full sample.
@(test)
test_the_water_census_counts_fill_and_awake_samples :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	chunk := world.chunks[{0, WATER_TEST_CHUNK_Y, 0}]
	for index in 0 ..< 3 {
		chunk.water[index] = FIELD_WATER_FULL
	}
	chunk.water[3], chunk.water[4] = 10, 10
	set_field_sample_bit(&chunk.water_awake, 1)
	set_field_sample_bit(&chunk.water_awake, 4)
	world.water_awake_chunks[chunk.coordinate] = {}
	census := field_water_census(&world)
	testing.expect_value(t, census.fill, 3 * i64(FIELD_WATER_FULL) + 20)
	testing.expect_value(t, census.awake_samples, 2)
	testing.expect_value(t, census.awake_chunks, 1)
	testing.expect_value(t, field_water_cubic_metres(FIELD_WATER_FULL * 8, 500), 1)
	testing.expect_value(t, field_water_cubic_metres(FIELD_WATER_FULL * 7, 500), 0)
	testing.expect_value(t, field_water_cubic_metres(FIELD_WATER_FULL * 3, 1000), 3)
}

@(test)
test_water_poured_into_a_basin_settles_level_and_keeps_its_volume :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	// A column of 2 by 2 by 20 full samples: one and a quarter layers.
	pour_test_water(&world, water_test_sample({7, 11, 7}), water_test_sample({8, 30, 8}), FIELD_WATER_FULL)
	poured := total_test_water(&world)
	testing.expect_value(t, poured, 80 * FIELD_WATER_FULL)

	tick: u64 = 0
	tuning := water_test_tuning()
	testing.expect(t, settle_test_water(&world, tuning, &tick, 5000) < 5000, "the basin settles")
	testing.expect_value(t, total_test_water(&world), poured)
	testing.expect(t, !any_water_awake(&world), "a settled basin has no awake samples")
	for _, chunk in world.chunks {
		testing.expect(t, chunk.water_still == {}, "a sleeping sample's still ticks are zero")
	}

	// The bottom layer is full; the rest lies in the layer above at one
	// level (the cell's bottom plus the fill), within a fill a step across
	// the basin since the levelling floors.
	lowest, highest := max(i64), min(i64)
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for x in BASIN_LOW.x ..= BASIN_HIGH.x {
			testing.expect_value(t, water_fill_at(&world, water_test_sample({x, BASIN_LOW.y, z})), FIELD_WATER_FULL)
			testing.expect(t, water_fill_at(&world, water_test_sample({x, BASIN_LOW.y + 1, z})) > 0)
			testing.expect_value(t, water_fill_at(&world, water_test_sample({x, BASIN_LOW.y + 2, z})), 0)
			sample := water_test_sample({x, BASIN_LOW.y + 1, z})
			level := field_water_level(field_water_span(sample), water_fill_at(&world, sample))
			lowest, highest = min(lowest, level), max(highest, level)
		}
	}
	testing.expect(t, highest - lowest <= 14, "the surface is level within a fill a step")
}

@(test) // slow
test_a_breached_basin_drains_into_the_lower_one_keeping_the_volume :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	// The lower basin lies towards the axis, so the channel runs down
	// the floor's slight slope.
	upper_low, upper_high := [3]i32{16, 12, 4}, [3]i32{23, 31, 11}
	lower_low, lower_high := [3]i32{2, 3, 4}, [3]i32{9, 31, 11}
	carve_water_test_box(&world, water_test_sample(upper_low), water_test_sample(upper_high))
	carve_water_test_box(&world, water_test_sample(lower_low), water_test_sample(lower_high))
	pour_test_water(&world, water_test_sample(upper_low), water_test_sample({23, 14, 11}), FIELD_WATER_FULL)
	// No drying, so every bit of the volume is accounted for.
	tuning := water_test_tuning()
	tuning.minimum_fill = 0
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 5000) < 5000)
	poured := total_test_water(&world)
	testing.expect_value(t, water_box_total(&world, water_test_sample(upper_low), water_test_sample(upper_high)), poured)

	// A channel through the wall at the upper basin's floor.
	for x in i32(10) ..= 15 {
		testing.expect(t, field_world_set_sample(&world, water_test_sample({x, 12, 7}), FIELD_AIR_SAMPLE))
	}
	testing.expect(t, settle_test_water(&world, tuning, &tick, 20000) < 20000, "the drained basins settle")
	testing.expect_value(t, total_test_water(&world), poured)
	upper := water_box_total(&world, water_test_sample(upper_low), water_test_sample(upper_high))
	// What stays behind is the level's slack: under a fill a step along
	// the way to the channel.
	testing.expect(t, upper <= 64 * 16, "the upper basin drains")
	testing.expect(t, water_box_total(&world, water_test_sample(lower_low), water_test_sample(lower_high)) >= poured - upper - 6 * 16)
}

@(test) // slow
test_a_pumped_pond_empties_and_a_sea_edge_sample_never_does :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	pour_test_water(&world, water_test_sample(BASIN_LOW), water_test_sample({11, 4, 11}), FIELD_WATER_FULL)
	tuning := water_test_tuning()
	tuning.dry_ticks = 5
	// The basin's floor is lowest at its corner nearest the axis.
	pump := water_test_sample(BASIN_LOW)
	tick: u64 = 0
	for tick < 20000 && total_test_water(&world) > 0 {
		take_test_water(&world, pump, 40)
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect_value(t, total_test_water(&world), 0)

	// The same chunk below sea level: a sample beside the missing chunk at
	// -x is the sea's edge and refills whatever is taken.
	sea := make_water_test_world()
	defer destroy_field_world(&sea)
	carve_water_test_box(&sea, water_test_sample({0, 0, 0}), water_test_sample({31, 31, 31}))
	pour_test_water(&sea, water_test_sample({0, 0, 0}), water_test_sample({31, 31, 31}), FIELD_WATER_FULL)
	sea.water_planet = water_test_sea_planet()
	edge := water_test_sample({0, 10, 10})
	for _ in 0 ..< 50 {
		testing.expect_value(t, take_test_water(&sea, edge, 100), 100)
		tick += 1
		step_field_water(&sea, tuning, tick)
		testing.expect_value(t, water_fill_at(&sea, edge), FIELD_WATER_FULL)
	}
}

@(test)
test_a_film_below_the_minimum_stops_and_dries :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	film := water_test_sample({7, BASIN_LOW.y, 7})
	pour_test_water(&world, film, film, 5)
	tuning := water_test_tuning()
	tuning.dry_ticks = 3
	tick: u64 = 0
	for _ in 0 ..< 3 * 5 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect_value(t, total_test_water(&world), i64(water_fill_at(&world, film)))
	}
	testing.expect_value(t, water_fill_at(&world, film), 0)
	testing.expect(t, settle_test_water(&world, tuning, &tick, 100) < 100, "the dry sample sleeps")
}

// Two ground chunks along x, inserted in the order given, with a basin
// across their border.
TWO_CHUNK_BASIN_LOW :: [3]i32{20, 3, 4}
TWO_CHUNK_BASIN_HIGH :: [3]i32{FIELD_CHUNK_SIZE + 11, 20, 11}

make_ground_chunks_water_world :: proc(order: [2]i32) -> Field_World {
	world: Field_World
	for x in order {
		field_world_insert_chunk(&world, make_ground_water_test_chunk(x))
	}
	return world
}

make_two_chunk_water_world :: proc(order: [2]i32) -> Field_World {
	world := make_ground_chunks_water_world(order)
	carve_water_test_box(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample(TWO_CHUNK_BASIN_HIGH))
	return world
}

// One sequence: a pour, ticks, a dig into the water, a place onto it,
// ticks.
run_water_test_sequence :: proc(world: ^Field_World) {
	pour_test_water(world, water_test_sample({21, 12, 5}), water_test_sample({25, 20, 6}), 200)
	tuning := water_test_tuning()
	tick: u64 = 0
	for _ in 0 ..< 40 {
		tick += 1
		step_field_water(world, tuning, tick)
	}
	field_world_set_sample(world, water_test_sample({FIELD_CHUNK_SIZE + 3, 2, 8}), FIELD_AIR_SAMPLE)
	field_world_set_sample(world, water_test_sample({22, 4, 6}), {MAXIMUM_DENSITY, .Stone, 0})
	for _ in 0 ..< 200 {
		tick += 1
		step_field_water(world, tuning, tick)
	}
}

// The chunks inserted in another order run the same sequence to the same
// bytes, the water crossing the chunks' border.
@(test) // slow
test_the_same_water_sequence_gives_the_same_bytes :: proc(t: ^testing.T) {
	first := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&first)
	second := make_two_chunk_water_world({1, 0})
	defer destroy_field_world(&second)
	run_water_test_sequence(&first)
	run_water_test_sequence(&second)
	for coordinate, chunk in first.chunks {
		other := second.chunks[coordinate]
		testing.expect(t, field_chunk_equals(chunk, other))
		testing.expect(t, chunk.water_flow == other.water_flow)
	}
	testing.expect(t, water_box_total(&first, water_test_sample({FIELD_CHUNK_SIZE, 0, 0}), water_test_sample({2 * FIELD_CHUNK_SIZE - 1, 31, 31})) > 0, "water crossed into the second chunk")
	testing.expect_value(t, first.water_dropped, second.water_dropped)
}

// Water poured in one chunk flows and wakes across the border and settles
// in both.
@(test) // slow
test_water_flows_across_a_chunk_border :: proc(t: ^testing.T) {
	world := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&world)
	pour_test_water(&world, water_test_sample({20, 3, 4}), water_test_sample({23, 10, 11}), FIELD_WATER_FULL)
	poured := total_test_water(&world)
	tuning := water_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 10000) < 10000)
	testing.expect_value(t, total_test_water(&world), poured)
	for x in i32(20) ..= FIELD_CHUNK_SIZE + 11 {
		testing.expect(t, water_fill_at(&world, water_test_sample({x, 3, 8})) > 100)
	}
}

// Water held by a missing chunk flows on when the chunk arrives
// (wake_field_water_facing); a settled sea meeting an arriving sea stays
// asleep.
@(test) // slow
test_an_arriving_chunk_wakes_the_water_it_held :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample({20, 3, 4}), water_test_sample({31, 20, 11}))
	pour_test_water(&world, water_test_sample({20, 3, 4}), water_test_sample({31, 6, 11}), FIELD_WATER_FULL)
	poured := total_test_water(&world)
	tuning := water_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 5000) < 5000)
	arriving := make_ground_water_test_chunk(1)
	for x in i32(0) ..= 11 {
		for y in i32(3) ..= 20 {
			for z in i32(4) ..= 11 {
				field_chunk_set_sample(arriving, field_local_to_index({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	field_world_insert_chunk(&world, arriving)
	testing.expect(t, len(world.water_awake_chunks) > 0, "the held water wakes")
	testing.expect(t, settle_test_water(&world, tuning, &tick, 10000) < 10000)
	testing.expect_value(t, total_test_water(&world), poured)
	testing.expect(t, water_fill_at(&world, water_test_sample({FIELD_CHUNK_SIZE + 8, 3, 8})) > 0)

	sea: Field_World
	defer destroy_field_world(&sea)
	sea.water_planet = water_test_sea_planet()
	for x in i32(0) ..= 1 {
		chunk := make_ground_water_test_chunk(x)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			field_chunk_set_sample(chunk, index, FIELD_AIR_SAMPLE)
			chunk.water[index] = FIELD_WATER_FULL
		}
		field_world_insert_chunk(&sea, chunk)
		testing.expect_value(t, len(sea.water_awake_chunks), 0)
	}
}

// A missing sample below sea level that the generation makes ground is a
// wall, not sea: a tunnel reaching the loaded boundary does not fill.
@(test)
test_a_missing_ground_sample_is_no_sea :: proc(t: ^testing.T) {
	for ground in ([2]bool{true, false}) {
		world: Field_World
		defer destroy_field_world(&world)
		if ground {
			// 7000 m from the centre of the 8000 m test planet is deep rock.
			world.water_planet = make_field_water_planet(TEST_PLANET_SEED, make_test_planet(), 1000)
		} else {
			world.water_planet = water_test_sea_planet()
		}
		world.water_planet.sea_level = 8000 * FIELD_WATER_FULL
		chunk := make_ground_water_test_chunk(0)
		chunk.coordinate = {0, ground ? 7000 / FIELD_CHUNK_SIZE : WATER_TEST_CHUNK_Y, 0}
		field_world_insert_chunk(&world, chunk)
		origin := field_chunk_origin(chunk.coordinate)
		tunnel_end := origin + {0, 10, 10}
		for x in i32(0) ..= 5 {
			field_world_set_sample(&world, tunnel_end + {x, 0, 0}, FIELD_AIR_SAMPLE)
		}
		tuning := water_test_tuning()
		tick: u64 = 0
		for _ in 0 ..< 20 {
			tick += 1
			step_field_water(&world, tuning, tick)
		}
		testing.expect_value(t, total_test_water(&world) > 0, !ground)
	}
}

// Isotropy: a sample moves only what it held when the tick began, so a
// pour on flat ground spreads as far each way.
@(test)
test_a_pour_on_flat_ground_spreads_alike_both_ways :: proc(t: ^testing.T) {
	// Four chunks round the +y axis, the pour on it, so the floor is
	// alike each way.
	world: Field_World
	defer destroy_field_world(&world)
	for coordinate in ([4][2]i32{{-1, -1}, {0, -1}, {-1, 0}, {0, 0}}) {
		chunk := make_ground_water_test_chunk(coordinate.x)
		chunk.coordinate.z = coordinate.y
		field_world_insert_chunk(&world, chunk)
	}
	carve_water_test_box(&world, water_test_sample({-15, 3, -15}), water_test_sample({15, 10, 15}))
	centre := water_test_sample({0, 3, 0})
	pour_test_water(&world, centre, centre, FIELD_WATER_FULL)
	tuning := water_test_tuning()
	tuning.minimum_fill = 1
	tick: u64 = 0
	for _ in 0 ..< 4 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	reach :: proc(world: ^Field_World, centre: Sample_Coordinate, direction: [3]i32) -> i32 {
		distance: i32 = 0
		for water_fill_at(world, centre + Sample_Coordinate(direction * (distance + 1))) > 0 {
			distance += 1
		}
		return distance
	}
	plus_x, minus_x := reach(&world, centre, {1, 0, 0}), reach(&world, centre, {-1, 0, 0})
	plus_z, minus_z := reach(&world, centre, {0, 0, 1}), reach(&world, centre, {0, 0, -1})
	testing.expect(t, plus_x > 1, "the pour spreads")
	testing.expect_value(t, plus_x, minus_x)
	testing.expect_value(t, plus_z, minus_z)
	testing.expect_value(t, plus_x, plus_z)
}

// A dry sample above sea level has nothing to do: a dig in dry ground
// wakes nothing.
@(test)
test_a_dig_in_dry_ground_wakes_nothing :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	field_world_set_sample(&world, water_test_sample({8, 8, 8}), FIELD_AIR_SAMPLE)
	testing.expect_value(t, len(world.water_awake_chunks), 0)
}

// A settled lake on a patch at 30 degrees latitude: the water mesh's top
// surface lies at one radius, though the samples sit at every depth in
// their shells.
@(test) // slow
test_a_settled_lake_off_the_axis_meshes_at_one_radius :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	centre := water_test_ray_sample(30, 3200)
	coordinate := sample_to_field_chunk_coordinate(centre)
	chunk := make_ground_water_test_chunk(0)
	chunk.coordinate = coordinate
	field_world_insert_chunk(&world, chunk)
	origin := field_chunk_origin(coordinate)
	carve_water_test_box(&world, origin + {4, 4, 4}, origin + {27, 27, 27})
	pour_test_water(&world, origin + {4, 4, 4}, origin + {12, 12, 27}, FIELD_WATER_FULL)
	tuning := water_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_test_water(&world, tuning, &tick, 20000) < 20000)

	grid := gather_field_grid(&world, coordinate, nil, context.temp_allocator)
	water := new(Field_Grid, context.temp_allocator)
	water.origin, water.step, water.density = grid.origin, grid.step, grid.water
	surface := mesh_field_surface(water, make_test_planet().palette, context.temp_allocator)
	lowest, highest := max(f64), f64(0)
	for vertex in surface.vertices {
		cell: [3]i32
		for axis in 0 ..< 3 {
			cell[axis] = floor_divide(vertex.position[axis], FIELD_MESH_POSITION_UNITS)
		}
		touches_ground := false
		for corner in 0 ..< 8 {
			touches_ground ||= grid.density[field_grid_index(cell + field_corner_offset(corner))] > 0
		}
		point := [3]f64{f64(origin.x), f64(origin.y), f64(origin.z)} + [3]f64{f64(vertex.position.x), f64(vertex.position.y), f64(vertex.position.z)} / FIELD_MESH_POSITION_UNITS
		upward := f64(vertex.gradient.x) * point.x + f64(vertex.gradient.y) * point.y + f64(vertex.gradient.z) * point.z < 0
		if touches_ground || !upward {
			continue
		}
		radius := math.sqrt(point.x * point.x + point.y * point.y + point.z * point.z)
		lowest, highest = min(lowest, radius), max(highest, radius)
	}
	testing.expect(t, highest > 0, "the lake has a top surface")
	testing.expectf(t, highest - lowest < 0.1, "the surface lies between %v and %v samples from the centre", lowest, highest)
}

@(test)
test_a_place_onto_water_displaces_it :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	wet := water_test_sample({7, BASIN_LOW.y, 7})
	pour_test_water(&world, wet, wet, 200)
	testing.expect(t, field_world_set_sample(&world, wet, {MAXIMUM_DENSITY, .Stone, 0}))
	testing.expect_value(t, water_fill_at(&world, wet), 0)
	testing.expect_value(t, total_test_water(&world), 200)
	testing.expect_value(t, world.water_dropped, 0)

	// Walled in by ground and full water, the fill has nowhere to go.
	pocket := water_test_sample({7, 20, 7})
	pour_test_water(&world, water_test_sample({4, 19, 4}), water_test_sample({11, 21, 11}), FIELD_WATER_FULL)
	before := total_test_water(&world)
	testing.expect(t, field_world_set_sample(&world, pocket, {MAXIMUM_DENSITY, .Stone, 0}))
	testing.expect_value(t, world.water_dropped, i64(FIELD_WATER_FULL))
	testing.expect_value(t, total_test_water(&world), before - FIELD_WATER_FULL)
}

@(test)
test_a_dug_hole_floods_on_the_next_tick :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	pour_test_water(&world, water_test_sample(BASIN_LOW), water_test_sample({11, 5, 11}), FIELD_WATER_FULL)
	tuning := water_test_tuning()
	tick: u64 = 0
	settle_test_water(&world, tuning, &tick, 1000)
	hole := water_test_sample({7, BASIN_LOW.y - 1, 7})
	testing.expect(t, field_world_set_sample(&world, hole, FIELD_AIR_SAMPLE))
	tick += 1
	step_field_water(&world, tuning, tick)
	testing.expect(t, water_fill_at(&world, hole) > 0)
}

// Unloaded, a coarse grid's water is the sea level rule: at or above zero
// exactly where the sample lies at or below the sea level and is not
// ground. Loaded, it takes the chunk's fill.
@(test)
test_a_coarse_water_grid_follows_the_sea_level_where_unloaded :: proc(t: ^testing.T) {
	planet := make_test_planet()
	generation := make_planet_generation(TEST_PLANET_SEED, planet, 1000)
	node := Field_Node{2, {0, 8000 / field_node_samples(2), 0}}
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	seen_sea, seen_air := false, false
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				index := field_grid_index({x, y, z})
				if grid.density[index] > 0 {
					testing.expect_value(t, grid.water[index], -MAXIMUM_DENSITY)
					continue
				}
				position := sample_to_world_position(grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step), 1000)
				squared := position.x * position.x + position.y * position.y + position.z * position.z
				below := i64(integer_square_root(u64(squared))) <= generation.sea_radius
				testing.expect_value(t, grid.water[index] >= 0, below)
				seen_sea ||= below
				seen_air ||= !below
			}
		}
	}
	testing.expect(t, seen_sea && seen_air, "the node crosses the sea level")

	// Far above the sea, a loaded chunk full of water shows as water.
	world: Field_World
	defer destroy_field_world(&world)
	high := Field_Node{1, {0, 10000 / field_node_samples(1), 0}}
	chunk := new(Field_Chunk)
	chunk.coordinate = Field_Chunk_Coordinate(high.coordinate * 2)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		field_chunk_set_sample(chunk, index, FIELD_AIR_SAMPLE)
		chunk.water[index] = FIELD_WATER_FULL
	}
	field_world_insert_chunk(&world, chunk)
	coarse := gather_coarse_field_grid(&world, high, context.temp_allocator)
	generate_field_grid(generation, high, coarse)
	testing.expect(t, coarse.water[field_grid_index({0, 0, 0})] > 0)
	testing.expect_value(t, coarse.water[field_grid_index({FIELD_GRID_CELLS - 1, FIELD_GRID_CELLS - 1, FIELD_GRID_CELLS - 1})], -MAXIMUM_DENSITY)
}

// On an axis full water lies half a sample above the sample, empty water
// half a sample below, and ground is -127.
@(test)
test_the_water_density_closes_against_the_terrain :: proc(t: ^testing.T) {
	axis := Sample_Coordinate{0, 3200, 0}
	testing.expect_value(t, field_water_density(-40, FIELD_WATER_FULL, axis), FIELD_WATER_DENSITY_HALF)
	testing.expect_value(t, field_water_density(-40, FIELD_WATER_FULL / 2, axis), 0)
	testing.expect_value(t, field_water_density(-40, 0, axis), -FIELD_WATER_DENSITY_HALF)
	testing.expect_value(t, field_water_density(1, FIELD_WATER_FULL, axis), -MAXIMUM_DENSITY)
	// On a diagonal the cell is taller: full water stands higher above it.
	testing.expect(t, field_water_density(-40, FIELD_WATER_FULL, {2262, 2262, 0}) > FIELD_WATER_DENSITY_HALF + 20)
}

// A sample at a direction in degrees from +x towards +y at distance
// samples from the centre, rounded.
water_test_ray_sample :: proc(degrees: f64, distance: f64) -> Sample_Coordinate {
	radians := degrees * math.PI / 180
	return {i32(math.round(math.cos(radians) * distance)), i32(math.round(math.sin(radians) * distance)), 0}
}

// The fine sea (the generation's sea fill) and the coarse sea rule give
// the same density within two steps near the sea level, on the axis and
// off it, so they cross at one radius.
@(test)
test_the_fine_and_coarse_sea_cross_at_one_radius :: proc(t: ^testing.T) {
	planet := make_test_planet()
	planet.sea_level_metres = -14
	water := make_field_water_planet(TEST_PLANET_SEED, planet, 1000)
	for degrees in ([?]f64{90, 60, 45, 30, 17}) {
		compared := 0
		for step in -16 ..= 16 {
			sample := water_test_ray_sample(degrees, f64(water.sea_level / FIELD_WATER_FULL) + f64(step) / 8)
			fill := field_sea_fill(water.sea_level, field_water_span(sample))
			fine := field_water_density(-MAXIMUM_DENSITY, u8(fill), sample)
			coarse := planet_sea_density(water.generation, sample_to_world_position(sample, 1000), -MAXIMUM_DENSITY)
			if fill > 0 && fill < FIELD_WATER_FULL {
				compared += 1
				testing.expectf(t, abs(i32(fine) - i32(coarse)) <= 2, "at %v degrees, sample %v: fine %d, coarse %d", degrees, sample, fine, coarse)
			}
		}
		testing.expect(t, compared > 0)
	}
}

// Work item 0312: a ground chunk at chunk_x whose local box low..high is
// air holding a generated lake's still bytes under level (field_sea_fill,
// no owner, no awake bit), not yet in a world; the bytes' sum.
make_test_lake_chunk :: proc(chunk_x: i32, low, high: [3]i32, level: i64) -> (chunk: ^Field_Chunk, total: i64) {
	chunk = make_ground_water_test_chunk(chunk_x)
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				index := field_local_to_index({x, y, z})
				field_chunk_set_sample(chunk, index, FIELD_AIR_SAMPLE)
				fill := field_sea_fill(level, field_water_span(field_chunk_sample(chunk, index)))
				chunk.water[index] = u8(fill)
				total += i64(fill)
			}
		}
	}
	return
}

// The level of the test lakes: the middle of the basin's layer 10.
test_lake_level :: proc() -> i64 {
	return field_water_span(water_test_sample({7, 10, 7})).middle
}

// Work item 0312: a generated lake arriving in a teleport world beside a
// loaded chunk is asleep water: nothing wakes it and its bytes stay.
@(test)
test_a_generated_lake_sleeps_under_teleport :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	chunk, total := make_test_lake_chunk(1, BASIN_LOW, BASIN_HIGH, test_lake_level())
	testing.expect(t, total > 0, "the lake holds water")
	written := chunk.water
	field_world_insert_chunk(&world, chunk)
	tuning := water_pressure_test_tuning()
	for tick in u64(1) ..= 40 {
		step_field_water(&world, tuning, tick)
	}
	testing.expect(t, !any_water_awake(&world), "the lake sleeps")
	testing.expect(t, world.chunks[{1, WATER_TEST_CHUNK_Y, 0}].water == written, "the lake's bytes stay as generated")
}
