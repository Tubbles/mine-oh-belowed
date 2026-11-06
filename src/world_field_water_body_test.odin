package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Work item 0293: the water bodies. The worlds are 0292's test chunks far
// up the +y axis (WATER_TEST_CHUNK_Y), under the bodies model.

// The pressure test tuning with the shipped body keys; no film dries
// inside a test, so the conserved sum is exact.
water_body_test_tuning :: proc() -> Field_Water_Tuning {
	tuning := water_pressure_test_tuning()
	tuning.dry_ticks = 1_000_000
	tuning.weir_rate_per_head, tuning.weir_cap, tuning.weir_floor, tuning.weir_dead_band = 51, 63, 15, 8
	tuning.flood_visit_budget, tuning.flood_rise_samples = 4000, 64
	return tuning
}

make_bodies_world :: proc(world: ^Field_World) {
	world.water_model = .Bodies
	make_sea_water_body(world)
}

make_body_test_world :: proc(chunk_count: i32 = 1) -> Field_World {
	world := make_water_test_world(chunk_count)
	make_bodies_world(&world)
	return world
}

alive_water_body_count :: proc(world: ^Field_World) -> int {
	count := 0
	for body in world.water_bodies {
		if body.alive && !body.sea {
			count += 1
		}
	}
	return count
}

// The one live body beside the sea.
only_water_body :: proc(t: ^testing.T, world: ^Field_World) -> (^Water_Body, Water_Body_Id) {
	testing.expect_value(t, alive_water_body_count(world), 1)
	for &body, id in world.water_bodies {
		if body.alive && !body.sea {
			return &body, Water_Body_Id(id)
		}
	}
	return nil, 0
}

// The body that owns the sample; false for none.
water_body_at :: proc(world: ^Field_World, sample: Sample_Coordinate) -> (id: Water_Body_Id, found: bool) {
	chunk, index := field_world_cell(world, sample)
	return water_owner_body(world, chunk.water_owner[index])
}

// The front's fill: samples no one owns, and front water in a body's air.
front_total :: proc(world: ^Field_World) -> i64 {
	total: i64 = 0
	for _, chunk in world.chunks {
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			owner := chunk.water_owner[index]
			if owner == WATER_OWNER_NONE || (owner != WATER_OWNER_SEA && field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index)) {
				total += i64(chunk.water[index])
			}
		}
	}
	return total
}

conserved_water :: proc(world: ^Field_World) -> i64 {
	total := front_total(world)
	for body in world.water_bodies {
		if body.alive && !body.sea {
			total += body.volume
		}
	}
	return total
}

water_body_frozen_equal :: proc(first, second: []Water_Body_Frozen) -> bool {
	if len(first) != len(second) {
		return false
	}
	for part, index in first {
		other := second[index]
		if part.chunk != other.chunk || part.owner != other.owner || !slice.equal(part.bands[:], other.bands[:]) {
			return false
		}
	}
	return true
}

// The records, the curves and the pending flood; not the chunk lists,
// which are derived and may name chunks a body left (a load's rebuild
// drops those).
water_bodies_equal :: proc(first, second: ^Field_World) -> bool {
	if len(first.water_bodies) != len(second.water_bodies) || first.water_to_sea != second.water_to_sea {
		return false
	}
	for &body, id in first.water_bodies {
		other := &second.water_bodies[id]
		same :=
			body.alive == other.alive &&
			body.sea == other.sea &&
			body.dirty == other.dirty &&
			body.spill_to_sea == other.spill_to_sea &&
			body.volume == other.volume &&
			body.level == other.level &&
			body.written_level == other.written_level &&
			body.seed == other.seed &&
			body.spill == other.spill &&
			body.spill_level == other.spill_level &&
			body.spill_volume == other.spill_volume &&
			body.flood_visits == other.flood_visits &&
			body.base == other.base &&
			slice.equal(body.loaded[:], other.loaded[:]) &&
			water_body_frozen_equal(body.frozen[:], other.frozen[:])
		if !same {
			return false
		}
	}
	a, b := &first.water_flood, &second.water_flood
	if a.active != b.active || a.body != b.body || a.sill != b.sill || a.rise_limit != b.rise_limit || a.seeding != b.seeding || a.redirty != b.redirty || !slice.equal(a.heap[:], b.heap[:]) || len(a.pushed) != len(b.pushed) {
		return false
	}
	for coordinate, bits in a.pushed {
		other := b.pushed[coordinate] or_else nil
		if other == nil || bits^ != other^ {
			return false
		}
	}
	return true
}

// Steps until nothing is awake, no flood is pending and no body is
// dirty; returns the ticks run, or limit. visits sums the floods' visits.
settle_body_test_water :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: ^u64, limit: int, visits: ^i64 = nil) -> int {
	for ticks in 0 ..< limit {
		dirty := false
		for body in world.water_bodies {
			dirty = dirty || (body.alive && body.dirty)
		}
		if len(world.water_awake_chunks) == 0 && !world.water_flood.active && !dirty {
			return ticks
		}
		tick^ += 1
		step_field_water(world, tuning, tick^)
		if visits != nil {
			visits^ += world.water_body_counts.flood_visits
		}
	}
	return limit
}

// The basin of 0292's tests poured full from y 3 to top_y and settled.
settled_body_test_lake :: proc(t: ^testing.T, top_y: i32, tick: ^u64, visits: ^i64 = nil) -> Field_World {
	world := make_body_test_world()
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	pour_test_water(&world, water_test_sample(BASIN_LOW), water_test_sample({BASIN_HIGH.x, top_y, BASIN_HIGH.z}), FIELD_WATER_FULL)
	ticks := settle_body_test_water(&world, water_body_test_tuning(), tick, 200, visits)
	testing.expectf(t, ticks < 200, "the lake settles (%d ticks)", ticks)
	return world
}

@(test)
test_a_poured_basin_settles_into_one_body_at_one_level :: proc(t: ^testing.T) {
	tick: u64 = 0
	visits: i64 = 0
	world := settled_body_test_lake(t, 10, &tick, &visits)
	defer destroy_field_world(&world)
	fmt.printfln("0293: the poured basin settled in %d ticks, its flood %d visits", tick, visits)
	// One seeding flood over the basin's 1856 samples, in one tick.
	testing.expect_value(t, visits, i64(8 * 8 * 29))
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	testing.expect_value(t, body.volume, i64(512 * FIELD_WATER_FULL))
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..= BASIN_HIGH.y {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				sample := water_test_sample({x, y, z})
				span := field_water_span(sample)
				if field_water_bottom(span) < body.level {
					owner, owned := water_body_at(&world, sample)
					testing.expect(t, owned && owner == id)
					testing.expect_value(t, water_fill_at(&world, sample), field_sea_fill(body.level, span))
				}
			}
		}
	}
	testing.expect_value(t, front_total(&world), 0)
	testing.expect_value(t, conserved_water(&world), i64(512 * FIELD_WATER_FULL))
	chunk := world.chunks[{0, WATER_TEST_CHUNK_Y, 0}]
	hash := field_chunk_state_hash(chunk)
	tuning := water_body_test_tuning()
	for _ in 0 ..< 300 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect_value(t, len(world.water_awake_chunks), 0)
		testing.expect_value(t, world.water_body_counts.flood_visits, 0)
	}
	testing.expect_value(t, field_chunk_state_hash(chunk), hash)
}

@(test)
test_a_hole_dug_under_a_lake_lowers_the_level_in_the_same_tick :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume, level := body.volume, body.level
	for z in i32(6) ..= 7 {
		for y in i32(1) ..= 2 {
			for x in i32(6) ..= 7 {
				field_world_set_sample(&world, water_test_sample({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	tick += 1
	step_field_water(&world, water_body_test_tuning(), tick)
	body = &world.water_bodies[id]
	testing.expect(t, body.alive)
	testing.expect_value(t, body.volume, volume)
	// Eight full cells over the 64-cell surface, within one band.
	drop := level - body.level
	expected := i64(8 * FIELD_WATER_FULL / 64)
	fmt.printfln("0293: the hole lowered the level by %d fill units (%d expected)", drop, expected)
	testing.expectf(t, drop >= expected - WATER_BODY_BAND && drop <= expected + WATER_BODY_BAND, "the level fell by %d", drop)
	for z in i32(6) ..= 7 {
		for y in i32(1) ..= 2 {
			for x in i32(6) ..= 7 {
				sample := water_test_sample({x, y, z})
				owner, owned := water_body_at(&world, sample)
				testing.expect(t, owned && owner == id)
				testing.expect_value(t, water_fill_at(&world, sample), FIELD_WATER_FULL)
			}
		}
	}
}

// Two lakes in one chunk side by side: A at x 2..9 poured to y 10, B at
// x 14..21 poured to y 4 (the trough's whole excess lands in B below the
// sill, so the lakes stay two), offset along x by chunk_x samples.
TROUGH_LAKE_A :: [2]i32{2, 9}
TROUGH_LAKE_B :: [2]i32{14, 21}

carve_trough_test_lakes :: proc(world: ^Field_World, offset: i32) {
	carve_water_test_box(world, water_test_sample({TROUGH_LAKE_A.x + offset, 3, 4}), water_test_sample({TROUGH_LAKE_A.y + offset, 31, 11}))
	carve_water_test_box(world, water_test_sample({TROUGH_LAKE_B.x + offset, 3, 4}), water_test_sample({TROUGH_LAKE_B.y + offset, 31, 11}))
	pour_test_water(world, water_test_sample({TROUGH_LAKE_A.x + offset, 3, 4}), water_test_sample({TROUGH_LAKE_A.y + offset, 10, 11}), FIELD_WATER_FULL)
	pour_test_water(world, water_test_sample({TROUGH_LAKE_B.x + offset, 3, 4}), water_test_sample({TROUGH_LAKE_B.y + offset, 4, 11}), FIELD_WATER_FULL)
}

dig_test_trough :: proc(world: ^Field_World, offset: i32) {
	for x in TROUGH_LAKE_A.y + 1 ..< TROUGH_LAKE_B.x {
		field_world_set_sample(world, water_test_sample({x + offset, 9, 7}), FIELD_AIR_SAMPLE)
	}
}

@(test)
test_a_trough_between_two_lakes_runs_a_front_stream_to_the_sill :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_trough_test_lakes(&world, 0)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 300) < 300)
	testing.expect_value(t, alive_water_body_count(&world), 2)
	a, a_found := water_body_at(&world, water_test_sample({5, 3, 7}))
	b, b_found := water_body_at(&world, water_test_sample({17, 3, 7}))
	testing.expect(t, a_found && b_found && a != b)
	if !a_found || !b_found {
		return
	}
	total := conserved_water(&world)
	b_volume := world.water_bodies[b].volume
	dig_test_trough(&world, 0)
	testing.expect(t, world.water_bodies[a].dirty)
	tick += 1
	step_field_water(&world, tuning, tick)
	lake := &world.water_bodies[a]
	trough_bottom := field_water_bottom(field_water_span(water_test_sample({10, 9, 7})))
	fmt.printfln("0293: A's spill %v at %d, the trough's bottom %d", lake.spill - water_test_sample({}), lake.spill_level, trough_bottom)
	testing.expect(t, !lake.dirty && lake.spill_level >= trough_bottom && lake.spill_level < trough_bottom + FIELD_WATER_FULL / 8)
	testing.expect(t, lake.spill.x - water_test_sample({}).x >= TROUGH_LAKE_B.x)
	stream_ticks := 0
	for _ in 0 ..< 3000 {
		tick += 1
		step_field_water(&world, tuning, tick)
		if front_total(&world) > 0 {
			stream_ticks += 1
		}
		if conserved_water(&world) != total {
			testing.expectf(t, false, "tick %d: %d is not %d", tick, conserved_water(&world), total)
			break
		}
	}
	fmt.printfln("0293: the trough's stream ran %d ticks; B %d -> %d", stream_ticks, b_volume, world.water_bodies[b].volume)
	testing.expect(t, stream_ticks > 0, "a front stream ran")
	testing.expect(t, world.water_bodies[b].volume > b_volume)
	lake = &world.water_bodies[a]
	testing.expectf(t, lake.spill_volume <= lake.volume && lake.volume <= lake.spill_volume + i64(tuning.weir_dead_band), "A %d over its sill's %d", lake.volume, lake.spill_volume)
	testing.expect_value(t, alive_water_body_count(&world), 2)
}

@(test)
test_a_pump_intake_lowers_the_level_to_the_litre :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	total := conserved_water(&world)
	intake := water_test_sample({7, 4, 7})
	for round in 1 ..= 3 {
		volume := body.volume
		testing.expect_value(t, displace_water_body_volume(&world, id, intake, 1000), 1000)
		testing.expect_value(t, body.volume, volume - 1000)
		testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
		testing.expect(t, volume_of_water_body_level(body, body.level) <= body.volume)
		testing.expect(t, volume_of_water_body_level(body, body.level + 1) > body.volume)
		_ = round
	}
	testing.expect_value(t, floor_divide_i64(body.written_level, WATER_BODY_BAND), floor_divide_i64(body.level, WATER_BODY_BAND))
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..= 12 {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				sample := water_test_sample({x, y, z})
				testing.expect_value(t, water_fill_at(&world, sample), field_sea_fill(body.written_level, field_water_span(sample)))
			}
		}
	}
	testing.expect_value(t, conserved_water(&world), total - 3000)
}

@(test)
test_a_cave_under_a_lake_fills_when_the_floor_is_dug_through :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	carve_water_test_box(&world, water_test_sample({5, 0, 5}), water_test_sample({10, 1, 10}))
	pour_test_water(&world, water_test_sample(BASIN_LOW), water_test_sample({BASIN_HIGH.x, 12, BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume, level := body.volume, body.level
	field_world_set_sample(&world, water_test_sample({7, 2, 7}), FIELD_AIR_SAMPLE)
	tick += 1
	step_field_water(&world, tuning, tick)
	check :: proc(t: ^testing.T, world: ^Field_World, id: Water_Body_Id) {
		for z in i32(5) ..= 10 {
			for y in i32(0) ..= 1 {
				for x in i32(5) ..= 10 {
					sample := water_test_sample({x, y, z})
					owner, owned := water_body_at(world, sample)
					testing.expect(t, owned && owner == id)
					testing.expect_value(t, water_fill_at(world, sample), FIELD_WATER_FULL)
				}
			}
		}
	}
	body = &world.water_bodies[id]
	check(t, &world, id)
	testing.expect_value(t, body.volume, volume)
	testing.expect(t, body.level < level)
	after := body.level
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	check(t, &world, id)
	testing.expect_value(t, world.water_bodies[id].level, after)
	testing.expect_value(t, len(world.water_awake_chunks), 0)
}

@(test)
test_a_lake_straddling_a_chunk_the_set_drops_keeps_its_volume :: proc(t: ^testing.T) {
	world := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	pour_test_water(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume, level := body.volume, body.level
	leaving := Field_Chunk_Coordinate{1, WATER_TEST_CHUNK_Y, 0}
	bytes := encode_field_chunk(world.chunks[leaving], context.temp_allocator)
	field_world_remove_chunk(&world, leaving)
	body = &world.water_bodies[id]
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, body.level, level)
	testing.expect_value(t, body_level_of_volume(body, body.volume), level)
	testing.expect_value(t, len(body.frozen), 1)
	testing.expect_value(t, len(body.chunks), 1)
	for _ in 0 ..< 50 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body = &world.water_bodies[id]
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, body.level, level)
	testing.expect_value(t, len(world.water_awake_chunks), 0)
	arriving := new(Field_Chunk)
	testing.expect_value(t, decode_field_chunk_delta(bytes, arriving), "")
	field_world_insert_chunk(&world, arriving)
	body = &world.water_bodies[id]
	testing.expect_value(t, len(body.frozen), 0)
	testing.expect(t, body.dirty)
	tick += 1
	step_field_water(&world, tuning, tick)
	body = &world.water_bodies[id]
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, body.level, level)
	owner, owned := water_body_at(&world, water_test_sample({FIELD_CHUNK_SIZE + 5, 3, 7}))
	testing.expect(t, owned && owner == id)
}

@(test)
test_the_sea_does_not_rise_under_a_spring :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	world.water_planet = water_test_sea_planet()
	make_bodies_world(&world)
	chunk := make_ground_water_test_chunk(0)
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..= BASIN_HIGH.y {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				field_chunk_set_sample(chunk, field_local_to_index({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	field_world_insert_chunk(&world, chunk)
	testing.expect(t, len(world.water_sea_seeds) > 0, "the arrival seeds the claim")
	tuning := water_body_test_tuning()
	tick: u64 = 1
	step_field_water(&world, tuning, tick)
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..= BASIN_HIGH.y {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				sample := water_test_sample({x, y, z})
				index := field_local_to_index({x, y, z})
				testing.expect_value(t, chunk.water_owner[index], WATER_OWNER_SEA)
				testing.expect_value(t, i32(chunk.water[index]), field_sea_fill(world.water_planet.sea_level, field_water_span(sample)))
			}
		}
	}
	spring := field_local_to_index({7, 3, 7})
	set_field_sample_bit(&chunk.water_source, spring)
	force_wake_field_water_sample(&world, chunk, spring)
	bytes := chunk.water
	to_sea := world.water_to_sea
	for _ in 0 ..< 2000 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect(t, chunk.water == bytes, "no byte changed")
	testing.expect_value(t, world.water_to_sea - to_sea, i64(2000) * i64(tuning.rate))
	testing.expect_value(t, alive_water_body_count(&world), 0)
	testing.expect(t, world.water_bodies[WATER_BODY_SEA].alive)
	testing.expect_value(t, field_sample_bits_count(&chunk.water_awake), 1)
}

@(test)
test_the_breach_conserves_body_volume_plus_front_fill_over_5000_ticks :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_trough_test_lakes(&world, 0)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	total := conserved_water(&world)
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect_value(t, conserved_water(&world), total)
	dig_test_trough(&world, 0)
	for _ in 0 ..< 5000 {
		tick += 1
		step_field_water(&world, tuning, tick)
		if conserved_water(&world) != total {
			testing.expectf(t, false, "tick %d: %d is not %d", tick, conserved_water(&world), total)
			break
		}
	}
	testing.expect_value(t, front_total(&world), 0)
}

// The trough laid across the border of two chunks inserted in either
// order: A in chunk 0, B in chunk 1.
run_body_test_trough_across_chunks :: proc(world: ^Field_World) {
	make_bodies_world(world)
	carve_trough_test_lakes(world, 18)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(world, tuning, tick)
	}
	dig_test_trough(world, 18)
	for _ in 0 ..< 1500 {
		tick += 1
		step_field_water(world, tuning, tick)
	}
}

@(test)
test_two_bodies_worlds_stepped_alike_hash_alike :: proc(t: ^testing.T) {
	first := make_ground_chunks_water_world({0, 1})
	defer destroy_field_world(&first)
	second := make_ground_chunks_water_world({1, 0})
	defer destroy_field_world(&second)
	run_body_test_trough_across_chunks(&first)
	run_body_test_trough_across_chunks(&second)
	testing.expect_value(t, alive_water_body_count(&first), 2)
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
	testing.expect(t, water_bodies_equal(&first, &second))
	testing.expect_value(t, first.water_body_counts, second.water_body_counts)
	testing.expect(t, water_box_total(&first, water_test_sample({FIELD_CHUNK_SIZE, 0, 0}), water_test_sample({2 * FIELD_CHUNK_SIZE - 1, 31, 31})) > 0)
}

@(test)
test_a_save_during_a_pending_flood_loads_and_hashes_alike :: proc(t: ^testing.T) {
	first := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&first)
	make_bodies_world(&first)
	pour_test_water(&first, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tuning.flood_visit_budget = 1000
	tick: u64 = 0
	for _ in 0 ..< 100 {
		if first.water_flood.active {
			break
		}
		tick += 1
		step_field_water(&first, tuning, tick)
	}
	testing.expect(t, first.water_flood.active, "a flood is pending")
	table := make([dynamic]byte, context.temp_allocator)
	write_water_body_table(&table, &first)
	second: Field_World
	defer destroy_field_world(&second)
	second.water_model = .Bodies
	reader := Byte_Reader {
		data = table[:],
	}
	testing.expect(t, read_water_body_table(&reader, &second))
	testing.expect_value(t, bytes_left(reader), 0)
	for coordinate in sorted_field_chunk_coordinates(first.chunks) {
		chunk := new(Field_Chunk)
		testing.expect_value(t, decode_field_chunk_delta(encode_field_chunk(first.chunks[coordinate], context.temp_allocator), chunk), "")
		restore_field_chunk(&second, chunk)
	}
	rebuild_water_body_chunks(&second)
	testing.expect(t, water_bodies_equal(&first, &second))
	for coordinate, chunk in first.chunks {
		testing.expect(t, field_chunk_equals(chunk, second.chunks[coordinate]))
	}
	finished := 0
	for _ in 0 ..< 20 {
		tick += 1
		step_field_water(&first, tuning, tick)
		step_field_water(&second, tuning, tick)
		testing.expect_value(t, first.water_flood.active, second.water_flood.active)
		if finished == 0 && !first.water_flood.active {
			finished = int(tick)
		}
	}
	testing.expect(t, finished > 0, "the flood finished")
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
	testing.expect(t, water_bodies_equal(&first, &second))
}

// A version 5 chunk round trips its owners; version 4 bytes (no owner and
// no failed planes) read with the owners zero and say so; an owner plane
// of a wrong length is refused.
@(test)
test_a_version_4_field_chunk_decodes_with_no_owner :: proc(t: ^testing.T) {
	chunk := new(Field_Chunk, context.temp_allocator)
	chunk.coordinate = {2, 3, 4}
	chunk.water[10] = 200
	chunk.water_owner[10] = 0x1234
	chunk.water_owner[11] = WATER_OWNER_SEA
	set_field_sample_bit(&chunk.water_pressure_failed, 12)
	restored := new(Field_Chunk, context.temp_allocator)
	problem, old := decode_field_chunk(encode_field_chunk(chunk, context.temp_allocator), restored)
	testing.expect_value(t, problem, "")
	testing.expect(t, !old)
	testing.expect(t, field_chunk_equals(restored, chunk))

	version_4 :: proc(chunk: ^Field_Chunk, owner_plane: []u8) -> []byte {
		bytes := make([dynamic]byte, context.temp_allocator)
		append_u16(&bytes, owner_plane == nil ? 4 : FIELD_CHUNK_FORMAT_VERSION)
		for axis in 0 ..< 3 {
			append_i32(&bytes, chunk.coordinate[axis])
		}
		planes := [?][]u8{transmute([]u8)chunk.density[:], transmute([]u8)chunk.material[:], chunk.tint[:], chunk.water[:], chunk.water_still[:], field_sample_bits_to_bytes(chunk.water_awake), field_sample_bits_to_bytes(chunk.water_source)}
		for plane in planes {
			append_field_plane(&bytes, plane)
		}
		if owner_plane != nil {
			append_field_plane(&bytes, owner_plane)
			append_field_plane(&bytes, owner_plane)
			append_field_plane(&bytes, field_sample_bits_to_bytes(chunk.water_pressure_failed))
		}
		append_field_plane(&bytes, chunk.block_light[:])
		append_field_plane(&bytes, chunk.sky_light[:])
		return bytes[:]
	}
	older := new(Field_Chunk, context.temp_allocator)
	problem, old = decode_field_chunk(version_4(chunk, nil), older)
	testing.expect_value(t, problem, "")
	testing.expect(t, old)
	testing.expect_value(t, older.water[10], 200)
	zero: [FIELD_CHUNK_SAMPLE_COUNT]Water_Owner
	testing.expect(t, older.water_owner == zero)
	testing.expect(t, !field_sample_bits_any(&older.water_pressure_failed))

	short := make([]u8, FIELD_CHUNK_SAMPLE_COUNT - 1, context.temp_allocator)
	problem, _ = decode_field_chunk(version_4(chunk, short), new(Field_Chunk, context.temp_allocator))
	testing.expect(t, problem != "")
}

// A dig below the sea level that joins a dry cave to the sea fills the
// cave to the sea's level in the same tick (claim_sea).
@(test)
test_a_dig_joining_a_cave_to_the_sea_fills_it_in_the_tick :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	world.water_planet = water_test_sea_planet()
	make_bodies_world(&world)
	chunk := make_ground_water_test_chunk(0)
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..= BASIN_HIGH.y {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				field_chunk_set_sample(chunk, field_local_to_index({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	// A sealed cave beside the shaft, one wall sample between.
	for z in i32(4) ..= 6 {
		for y in i32(5) ..= 7 {
			for x in i32(14) ..= 16 {
				field_chunk_set_sample(chunk, field_local_to_index({x, y, z}), FIELD_AIR_SAMPLE)
			}
		}
	}
	field_world_insert_chunk(&world, chunk)
	tuning := water_body_test_tuning()
	tick: u64 = 1
	step_field_water(&world, tuning, tick)
	cave := field_local_to_index({15, 6, 5})
	testing.expect_value(t, chunk.water_owner[cave], WATER_OWNER_NONE)
	testing.expect_value(t, chunk.water[cave], 0)
	field_world_set_sample(&world, water_test_sample({12, 6, 5}), FIELD_AIR_SAMPLE)
	field_world_set_sample(&world, water_test_sample({13, 6, 5}), FIELD_AIR_SAMPLE)
	tick += 1
	step_field_water(&world, tuning, tick)
	for z in i32(4) ..= 6 {
		for y in i32(5) ..= 7 {
			for x in i32(14) ..= 16 {
				index := field_local_to_index({x, y, z})
				testing.expect_value(t, chunk.water_owner[index], WATER_OWNER_SEA)
				testing.expect_value(t, chunk.water[index], FIELD_WATER_FULL)
			}
		}
	}
	testing.expect_value(t, alive_water_body_count(&world), 0)
}

// The bodies model on the planet's own terrain: two tech demo sessions at
// the spring run alike, the spring's water a front or a body, the sea
// body 0 and still.
@(test)
test_two_tech_demo_bodies_sessions_run_alike_at_the_spring :: proc(t: ^testing.T) {
	config := test_field_game_config()
	config.field_simulation.chunk_radius, config.field_simulation.chunk_margin = 1, 0
	content := make_field_test_game_content()
	hashes: [2]u64
	water: [2]i64
	for &hash, run in hashes {
		session, problem := start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = .Bodies, planet_radius_metres = 4000, start = .Spring})
		testing.expect_value(t, problem, "")
		if session == nil {
			return
		}
		simulation_content := session_simulation_content(content, session.technologies, session.field_content)
		for _ in 0 ..< 240 {
			tick_field_test_simulation(&session.simulation, simulation_content, {})
		}
		world := &session.simulation.field.world
		testing.expect(t, world.water_bodies[WATER_BODY_SEA].alive && world.water_bodies[WATER_BODY_SEA].sea)
		water[run] = conserved_water(world)
		hash = simulation_state_hash(&session.simulation)
		end_session(session)
	}
	fmt.printfln("0293: the spring's water after 240 ticks: %d fill", water[0])
	testing.expect_value(t, hashes[0], hashes[1])
	testing.expect(t, water[0] > 0, "the spring poured")
}

// Fix round (0293). A spring refills before any planning: a sender
// planned before it never promises water against its tick-start fill, so
// its byte never wraps past full and the sender's water is all accounted.
@(test)
test_a_spring_refills_before_a_sender_plans_against_it :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample({7, 3, 7}), water_test_sample({8, 3, 7}))
	sender := water_test_sample({7, 3, 7})
	spring := water_test_sample({8, 3, 7})
	chunk := world.chunks[sample_to_field_chunk_coordinate(spring)]
	sender_index, spring_index := sample_to_field_index(sender), sample_to_field_index(spring)
	set_field_water(&world, chunk, sender_index, sender, 200)
	set_field_water(&world, chunk, spring_index, spring, 100)
	set_field_sample_bit(&chunk.water_source, spring_index)
	force_wake_field_water_sample(&world, chunk, sender_index)
	force_wake_field_water_sample(&world, chunk, spring_index)
	tuning := water_body_test_tuning()
	for tick in u64(1) ..= 20 {
		before := water_fill_at(&world, sender)
		step_field_water(&world, tuning, tick)
		poured := i32(chunk.water_flow[spring_index])
		testing.expectf(t, water_fill_at(&world, spring) + poured == FIELD_WATER_FULL, "tick %d: the spring %d poured %d", tick, water_fill_at(&world, spring), poured)
		testing.expectf(t, water_fill_at(&world, sender) == before + poured - i32(chunk.water_flow[sender_index]), "tick %d: the sender %d from %d", tick, water_fill_at(&world, sender), before)
	}
}

// A spring under a body's level pours its rate into the body and nothing
// more, and the level follows the volume.
@(test)
test_a_spring_under_a_lake_raises_it_by_its_rate :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	spring := water_test_sample({7, 4, 7})
	chunk := world.chunks[sample_to_field_chunk_coordinate(spring)]
	set_field_sample_bit(&chunk.water_source, sample_to_field_index(spring))
	force_wake_field_water_sample(&world, chunk, sample_to_field_index(spring))
	tuning := water_body_test_tuning()
	volume := body.volume
	for _ in 0 ..< 300 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body = &world.water_bodies[id]
	testing.expect_value(t, body.volume, volume + 300 * i64(tuning.rate))
	testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
}

// A machine that saved during a pending flood and one that loaded the
// save decide alike when a chunk the body left (its lists still name it
// on the saving machine) leaves the set.
@(test)
test_a_freeze_after_a_load_during_a_flood_hashes_alike :: proc(t: ^testing.T) {
	first := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&first)
	make_bodies_world(&first)
	pour_test_water(&first, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&first, tuning, &tick, 200) < 200)
	// The lake's part in chunk 1 turned to ground: the body keeps its
	// volume and leaves chunk 1, which its lists still name.
	for z in TWO_CHUNK_BASIN_LOW.z ..= TWO_CHUNK_BASIN_HIGH.z {
		for y in TWO_CHUNK_BASIN_LOW.y ..= TWO_CHUNK_BASIN_HIGH.y {
			for x in i32(FIELD_CHUNK_SIZE) ..= TWO_CHUNK_BASIN_HIGH.x {
				field_world_set_sample(&first, water_test_sample({x, y, z}), {MAXIMUM_DENSITY, .Stone, 0})
			}
		}
	}
	tuning.flood_visit_budget = 500
	tick += 1
	step_field_water(&first, tuning, tick)
	testing.expect(t, first.water_flood.active, "a flood is pending")
	table := make([dynamic]byte, context.temp_allocator)
	write_water_body_table(&table, &first)
	second: Field_World
	defer destroy_field_world(&second)
	second.water_model = .Bodies
	reader := Byte_Reader {
		data = table[:],
	}
	testing.expect(t, read_water_body_table(&reader, &second))
	for coordinate in sorted_field_chunk_coordinates(first.chunks) {
		chunk := new(Field_Chunk)
		testing.expect_value(t, decode_field_chunk_delta(encode_field_chunk(first.chunks[coordinate], context.temp_allocator), chunk), "")
		restore_field_chunk(&second, chunk)
	}
	rebuild_water_body_chunks(&second)
	leaving := Field_Chunk_Coordinate{1, WATER_TEST_CHUNK_Y, 0}
	field_world_remove_chunk(&first, leaving)
	field_world_remove_chunk(&second, leaving)
	testing.expect(t, water_bodies_equal(&first, &second), "the freeze decided alike")
	for _ in 0 ..< 20 {
		tick += 1
		step_field_water(&first, tuning, tick)
		step_field_water(&second, tuning, tick)
		testing.expect_value(t, first.water_flood.active, second.water_flood.active)
	}
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
	testing.expect(t, water_bodies_equal(&first, &second))
}

// A water body table of the given records, no flood.
write_test_water_table :: proc(bodies: []Water_Body_Record, bands: []Water_Body_Band_Record) -> [dynamic]byte {
	bytes := make([dynamic]byte, context.temp_allocator)
	append_u64(&bytes, 0)
	write_list(&bytes, bodies)
	write_list(&bytes, bands)
	write_list(&bytes, []Water_Flood_Record{{}})
	write_list(&bytes, []Water_Flood_Entry{})
	write_list(&bytes, []Water_Flood_Pushed_Record{})
	return bytes
}

reads_water_body_table :: proc(bytes: []byte) -> bool {
	world: Field_World
	defer destroy_field_world(&world)
	reader := Byte_Reader {
		data = bytes,
	}
	return read_water_body_table(&reader, &world) && bytes_left(reader) == 0
}

// The table's reader bounds what it allocates: a base off the bands or
// out of range, a level out of range, a band index past the cap, a frozen
// band's owner that names no listed body, too many band entries in all and
// a pushed count beyond the bytes left are each refused.
@(test)
test_a_malformed_water_body_table_is_refused :: proc(t: ^testing.T) {
	base := i64(1000 * WATER_BODY_BAND)
	bodies := []Water_Body_Record{{id = 0, alive = true, sea = true}, {id = 1, alive = true, base = base, level = base + 5, written_level = base}}
	bands := []Water_Body_Band_Record{{body = 1, band = 0, opens = 256}, {body = 1, band = 16, closes = 256}, {body = 1, frozen = true, chunk = {1, 2, 3}, owner = 2, band = 3, opens = 256}}
	testing.expect(t, reads_water_body_table(write_test_water_table(bodies, bands)[:]), "the valid table reads")

	with_body :: proc(bodies: []Water_Body_Record, change: proc(record: ^Water_Body_Record)) -> []Water_Body_Record {
		changed := slice.clone(bodies, context.temp_allocator)
		change(&changed[1])
		return changed
	}
	with_band :: proc(bands: []Water_Body_Band_Record, change: proc(record: ^Water_Body_Band_Record)) -> []Water_Body_Band_Record {
		changed := slice.clone(bands, context.temp_allocator)
		change(&changed[2])
		return changed
	}
	refused := [?][]Water_Body_Record {
		with_body(bodies, proc(record: ^Water_Body_Record) {record.base += 3}),
		with_body(bodies, proc(record: ^Water_Body_Record) {record.base = -WATER_BODY_BAND}),
		with_body(bodies, proc(record: ^Water_Body_Record) {record.base = MAXIMUM_WATER_BODY_LEVEL / WATER_BODY_BAND * WATER_BODY_BAND + WATER_BODY_BAND}),
		with_body(bodies, proc(record: ^Water_Body_Record) {record.level = MAXIMUM_WATER_BODY_LEVEL + 1}),
		with_body(bodies, proc(record: ^Water_Body_Record) {record.level = -1}),
	}
	for changed in refused {
		testing.expect(t, !reads_water_body_table(write_test_water_table(changed, bands)[:]), "a base or level is refused")
	}
	refused_bands := [?][]Water_Body_Band_Record {
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.band = MAXIMUM_WATER_BODY_BAND}),
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.band = -1}),
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.owner = u16(WATER_OWNER_SEA)}),
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.owner = 0}),
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.owner = u16(WATER_OWNER_RELEASED)}),
		with_band(bands, proc(record: ^Water_Body_Band_Record) {record.owner = 3}),
	}
	for changed in refused_bands {
		testing.expect(t, !reads_water_body_table(write_test_water_table(bodies, changed)[:]), "a band is refused")
	}
	// Every frozen part at the highest band: more entries in all than the
	// cap.
	many := make([dynamic]Water_Body_Band_Record, context.temp_allocator)
	for part in 0 ..< MAXIMUM_WATER_BODY_BAND_ENTRIES / MAXIMUM_WATER_BODY_BAND + 1 {
		append(&many, Water_Body_Band_Record{body = 1, frozen = true, chunk = {i32(part), 0, 0}, owner = 2, band = MAXIMUM_WATER_BODY_BAND - 1, closes = 256})
	}
	testing.expect(t, !reads_water_body_table(write_test_water_table(bodies, many[:])[:]), "too many band entries are refused")
	// A pushed count within the bytes left but beyond what they hold at a
	// record's size (read_list alone takes it).
	cut := make([dynamic]byte, context.temp_allocator)
	append_u64(&cut, 0)
	write_list(&cut, bodies)
	write_list(&cut, bands)
	write_list(&cut, []Water_Flood_Record{{}})
	write_list(&cut, []Water_Flood_Entry{})
	append_u32(&cut, 100)
	for _ in 0 ..< 100 {
		append_u8(&cut, 0)
	}
	testing.expect(t, !reads_water_body_table(cut[:]), "the pushed count is refused")
}

// A pool seeded against a lake's water, below the lake's surface, joins
// the lake: the seeding flood merges with it.
@(test)
test_a_pool_seeded_against_a_lake_merges_with_it :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 9, &tick)
	defer destroy_field_world(&world)
	total := conserved_water(&world)
	// An alcove beside the lake's top layer, carved without an edit, so
	// the lake's basin does not take it.
	carve_water_test_box(&world, water_test_sample({12, 9, 6}), water_test_sample({14, 12, 8}))
	pour_test_water(&world, water_test_sample({12, 9, 6}), water_test_sample({14, 9, 8}), FIELD_WATER_FULL)
	total += 9 * FIELD_WATER_FULL
	tuning := water_body_test_tuning()
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 300) < 300)
	testing.expect_value(t, alive_water_body_count(&world), 1)
	testing.expect_value(t, conserved_water(&world), total)
	lake, _ := water_body_at(&world, water_test_sample({5, 3, 5}))
	alcove, owned := water_body_at(&world, water_test_sample({13, 9, 7}))
	testing.expect(t, owned && alcove == lake)
}

// A body that slept wholly frozen floods again once one of its chunks
// returns: the thaw moves its seed into the loaded chunk.
@(test)
test_a_wholly_frozen_lake_floods_again_when_a_chunk_returns :: proc(t: ^testing.T) {
	world := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	pour_test_water(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume, level := body.volume, body.level
	first := Field_Chunk_Coordinate{0, WATER_TEST_CHUNK_Y, 0}
	bytes := encode_field_chunk(world.chunks[first], context.temp_allocator)
	field_world_remove_chunk(&world, first)
	field_world_remove_chunk(&world, {1, WATER_TEST_CHUNK_Y, 0})
	body = &world.water_bodies[id]
	testing.expect_value(t, sample_to_field_chunk_coordinate(body.seed), Field_Chunk_Coordinate{1, WATER_TEST_CHUNK_Y, 0})
	arriving := new(Field_Chunk)
	testing.expect_value(t, decode_field_chunk_delta(bytes, arriving), "")
	field_world_insert_chunk(&world, arriving)
	body = &world.water_bodies[id]
	testing.expect_value(t, sample_to_field_chunk_coordinate(body.seed), first)
	tick += 1
	step_field_water(&world, tuning, tick)
	body = &world.water_bodies[id]
	testing.expect(t, !body.dirty, "the body flooded")
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, body.level, level)
}

// An arriving chunk's still water owned by no live body leaves the world
// counted as dropped.
@(test)
test_a_stale_owner_on_an_arriving_chunk_counts_its_water_dropped :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	arriving := make_ground_water_test_chunk(1)
	index := field_local_to_index({5, 5, 5})
	field_chunk_set_sample(arriving, index, FIELD_AIR_SAMPLE)
	arriving.water[index] = 200
	arriving.water_owner[index] = 7
	field_world_insert_chunk(&world, arriving)
	testing.expect_value(t, arriving.water_owner[index], WATER_OWNER_NONE)
	testing.expect_value(t, arriving.water[index], 0)
	testing.expect_value(t, world.water_dropped, 200)
}

// Work item 0298: a thin layer on the basin's floor (local y 3) settles
// under either model. The bound is over twice the worst measured pour.
THIN_POUR_TICK_BOUND :: 120

thin_pour_test_world :: proc(model: Water_Model) -> Field_World {
	world := model == .Bodies ? make_body_test_world() : make_water_test_world()
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	return world
}

settle_thin_pour :: proc(world: ^Field_World, model: Water_Model, tuning: Field_Water_Tuning, tick: ^u64) -> int {
	return model == .Bodies ? settle_body_test_water(world, tuning, tick, THIN_POUR_TICK_BOUND) : settle_test_water(world, tuning, tick, THIN_POUR_TICK_BOUND)
}

// The settled thin layer under bodies: one body of the volume poured,
// at the level its volume gives, owning the whole floor.
expect_thin_pour_body :: proc(t: ^testing.T, world: ^Field_World, volume: i64) {
	testing.expect_value(t, conserved_water(world), volume)
	body, id := only_water_body(t, world)
	if body == nil {
		return
	}
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for x in BASIN_LOW.x ..= BASIN_HIGH.x {
			owner, owned := water_body_at(world, water_test_sample({x, BASIN_LOW.y, z}))
			testing.expectf(t, owned && owner == id, "the floor sample (%d, %d) is the body's", x, z)
		}
	}
}

// 20 full samples, as the bucket pours them, come still in one body
// under bodies and spread over the floor under teleport (before 0298 the
// bodies front swapped a checkerboard for good and seeded a body of 5).
@(test)
test_a_thin_pour_on_a_flat_floor_settles_into_one_body :: proc(t: ^testing.T) {
	tuning := water_body_test_tuning()
	for model in Water_Model {
		world := thin_pour_test_world(model)
		defer destroy_field_world(&world)
		pour_test_water(&world, water_test_sample({4, 3, 4}), water_test_sample({7, 3, 8}), FIELD_WATER_FULL)
		tick: u64 = 0
		ticks := settle_thin_pour(&world, model, tuning, &tick)
		fmt.printfln("0298: 20 full samples settled under %v in %d ticks", model, ticks)
		testing.expectf(t, ticks < THIN_POUR_TICK_BOUND, "the pour settles under %v (%d ticks)", model, ticks)
		testing.expect(t, !any_water_awake(&world))
		volume := i64(20 * FIELD_WATER_FULL)
		if model == .Bodies {
			expect_thin_pour_body(t, &world, volume)
		} else {
			testing.expect_value(t, total_test_water(&world), volume)
			for z in BASIN_LOW.z ..= BASIN_HIGH.z {
				for x in BASIN_LOW.x ..= BASIN_HIGH.x {
					fill := water_fill_at(&world, water_test_sample({x, BASIN_LOW.y, z}))
					testing.expectf(t, fill > tuning.minimum_fill, "the floor sample (%d, %d) holds %d", x, z, fill)
				}
			}
		}
	}
}

// Full samples on the floor's even cells: the bodies front's first tick
// leaves teleport's bytes, and the layer then settles into one body
// (before 0298 it moved to the odd cells every tick and never came still).
@(test)
test_a_checkerboard_front_does_not_swap :: proc(t: ^testing.T) {
	tuning := water_body_test_tuning()
	worlds: [Water_Model]Field_World
	for model in Water_Model {
		worlds[model] = thin_pour_test_world(model)
		for z in BASIN_LOW.z ..= BASIN_HIGH.z {
			for x in BASIN_LOW.x ..= BASIN_HIGH.x {
				if (x + z) % 2 == 0 {
					sample := water_test_sample({x, BASIN_LOW.y, z})
					pour_test_water(&worlds[model], sample, sample, FIELD_WATER_FULL)
				}
			}
		}
		step_field_water(&worlds[model], tuning, 1)
	}
	defer for &world in worlds {
		destroy_field_world(&world)
	}
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for x in BASIN_LOW.x ..= BASIN_HIGH.x {
			sample := water_test_sample({x, BASIN_LOW.y, z})
			testing.expectf(t, water_fill_at(&worlds[.Bodies], sample) == water_fill_at(&worlds[.Teleport], sample), "the floor sample (%d, %d) holds %d under bodies and %d under teleport", x, z, water_fill_at(&worlds[.Bodies], sample), water_fill_at(&worlds[.Teleport], sample))
		}
	}
	tick: u64 = 1
	ticks := settle_body_test_water(&worlds[.Bodies], tuning, &tick, THIN_POUR_TICK_BOUND)
	fmt.printfln("0298: the checkerboard settled under bodies in %d ticks after the first", ticks)
	testing.expectf(t, ticks < THIN_POUR_TICK_BOUND, "the checkerboard settles (%d ticks)", ticks)
	testing.expect(t, !any_water_awake(&worlds[.Bodies]))
	expect_thin_pour_body(t, &worlds[.Bodies], i64(32 * FIELD_WATER_FULL))
}
