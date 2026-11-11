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
			body.spill_outside == other.spill_outside &&
			body.volume == other.volume &&
			body.level == other.level &&
			body.written_level == other.written_level &&
			body.seed == other.seed &&
			body.spill == other.spill &&
			body.spill_level == other.spill_level &&
			body.spill_volume == other.spill_volume &&
			body.flood_visits == other.flood_visits &&
			body.base == other.base &&
			body.joined_sill == other.joined_sill &&
			slice.equal(body.loaded[:], other.loaded[:]) &&
			water_body_frozen_equal(body.frozen[:], other.frozen[:])
		if !same {
			return false
		}
	}
	a, b := &first.water_flood, &second.water_flood
	if a.active != b.active || a.body != b.body || a.sill != b.sill || a.rise_limit != b.rise_limit || a.seeding != b.seeding || a.redirty != b.redirty || a.has_candidate != b.has_candidate || a.candidate != b.candidate || a.join_level != b.join_level || a.joined_sill != b.joined_sill || !slice.equal(a.heap[:], b.heap[:]) || len(a.pushed) != len(b.pushed) {
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

@(test) // slow
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

@(test) // slow
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
	testing.expect_value(t, world.water_to_sea - to_sea, i64(2000) * i64(tuning.spring_rate))
	testing.expect_value(t, alive_water_body_count(&world), 0)
	testing.expect(t, world.water_bodies[WATER_BODY_SEA].alive)
	testing.expect_value(t, field_sample_bits_count(&chunk.water_awake), 1)
}

@(test) // slow
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

@(test) // slow
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
@(test) // slow
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
		// The refill is capped by the spring's rate (0367), so the sender
		// may pour into the spring too.
		refill := min(FIELD_WATER_FULL, water_fill_at(&world, spring) + tuning.spring_rate)
		step_field_water(&world, tuning, tick)
		poured, returned := i32(chunk.water_flow[spring_index]), i32(chunk.water_flow[sender_index])
		testing.expectf(t, water_fill_at(&world, spring) == refill - poured + returned, "tick %d: the spring %d poured %d, took %d", tick, water_fill_at(&world, spring), poured, returned)
		testing.expectf(t, water_fill_at(&world, sender) == before + poured - returned, "tick %d: the sender %d from %d", tick, water_fill_at(&world, sender), before)
	}
}

// A spring under a body's level pours its rate (spring_rate, 0367) into
// the body and nothing more, and the level follows the volume.
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
	testing.expect_value(t, body.volume, volume + 300 * i64(tuning.spring_rate))
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

// A table written before 0300, whose body records lack joined_sill and
// spill_outside (94 bytes each), loads with many dead slots and little
// after the list: its count is checked at the record size its schema
// gives, not at the 95 bytes 0370's least record size took. A list cut
// short is still refused.
@(test)
test_an_old_water_body_table_with_many_dead_slots_loads :: proc(t: ^testing.T) {
	Old_Water_Body_Record :: struct {
		id:                             u16,
		alive, sea, dirty, spill_to_sea: bool,
		volume, level, written_level:   i64,
		spill_level, spill_volume:      i64,
		flood_visits, base:             i64,
		seed, spill:                    Sample_Coordinate,
	}
	CHECKED_RECORD_BYTES :: 2 + 5 + 8 * 8 + 2 * 12
	SLOTS :: 2000
	bodies := make([]Old_Water_Body_Record, SLOTS, context.temp_allocator)
	for &body, id in bodies {
		body.id = u16(id)
	}
	bodies[0].alive = true
	bodies[0].sea = true
	table := make([dynamic]byte, context.temp_allocator)
	append_u64(&table, 0)
	write_list(&table, bodies)
	list_end := len(table)
	write_list(&table, []Water_Body_Band_Record{})
	write_list(&table, []Water_Flood_Record{{}})
	write_list(&table, []Water_Flood_Entry{})
	write_list(&table, []Water_Flood_Pushed_Record{})
	after_count := len(table) - size_of(u64) - size_of(u32)
	testing.expect(t, after_count < SLOTS * CHECKED_RECORD_BYTES, "the bytes after the count hold fewer records than the count at 95 bytes")
	testing.expect(t, reads_water_body_table(table[:]), "the old table reads")
	testing.expect(t, !reads_water_body_table(table[:list_end - 1]), "a list one byte short is refused")
	testing.expect(t, !reads_water_body_table(table[:list_end / 2]), "a list cut in half is refused")
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

// Work item 0299: no body outlives its last cell, and a seed's sample its
// flood missed joins the new body.

// A body alive with no cell (no loaded band, no frozen part), not the
// sea and not pending; -1 for none.
empty_water_body :: proc(world: ^Field_World) -> int {
	for body, id in world.water_bodies {
		if body.alive && !body.sea && len(body.loaded) == 0 && len(body.frozen) == 0 && !water_body_is_pending(world, Water_Body_Id(id)) {
			return id
		}
	}
	return -1
}

// A body owning the one dry sample, taken from the body that owned it,
// at the level of its base so the cell reads dry whatever the volume.
make_dry_water_body :: proc(world: ^Field_World, sample: Sample_Coordinate, volume: i64) -> Water_Body_Id {
	id, _ := allocate_water_body_id(world)
	span := field_water_span(sample)
	base := floor_divide_i64(field_water_bottom(span), WATER_BODY_BAND) * WATER_BODY_BAND
	world.water_bodies[id] = Water_Body {
		alive         = true,
		volume        = volume,
		level         = base,
		written_level = base,
		base          = base,
		seed          = sample,
		spill_level   = max(i64),
		spill_volume  = max(i64),
		meshed_level  = min(i64),
	}
	chunk, index := field_world_cell(world, sample)
	if previous, owned := water_owner_body(world, chunk.water_owner[index]); owned && previous != WATER_BODY_SEA {
		remove_water_body_cell(&world.water_bodies[previous], &world.water_bodies[previous].loaded, span)
	}
	chunk.water_owner[index] = water_owner_of(id)
	body := &world.water_bodies[id]
	add_water_body_cell(body, &body.loaded, span)
	insert_sorted_field_chunk(&body.chunks, chunk.coordinate)
	return id
}

// The scenario 0298's verifier found: front water 4 deep drains through a
// hole into a cave and settles, then a second cave is joined to the first
// by a passage. Before 0299 seven bodies stayed alive with no cell, and a
// residue above the floor's lake seeded and merged 21 times a tick for
// good.
@(test) // slow
test_a_drained_lake_joined_to_a_second_cave_comes_to_rest :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	carve_water_test_box(&world, water_test_sample({4, 0, 4}), water_test_sample({11, 1, 11}))
	pour_test_water(&world, water_test_sample({4, 3, 4}), water_test_sample({11, 6, 11}), FIELD_WATER_FULL)
	field_world_set_sample(&world, water_test_sample({7, 2, 7}), FIELD_AIR_SAMPLE)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	ticks := settle_body_test_water(&world, tuning, &tick, 400)
	testing.expectf(t, ticks < 400, "the drained lake settles (%d ticks)", ticks)
	carve_water_test_box(&world, water_test_sample({13, 0, 4}), water_test_sample({20, 1, 11}))
	field_world_set_sample(&world, water_test_sample({12, 1, 7}), FIELD_AIR_SAMPLE)
	field_world_set_sample(&world, water_test_sample({13, 1, 7}), FIELD_AIR_SAMPLE)
	total := conserved_water(&world)
	dropped, to_sea := world.water_dropped, world.water_to_sea
	last_active := 0
	for step in 1 ..= 2500 {
		tick += 1
		step_field_water(&world, tuning, tick)
		counts := world.water_body_counts
		if counts.seeded != 0 || counts.merged != 0 || counts.flood_visits != 0 {
			last_active = step
			if step > 1500 {
				testing.expectf(t, false, "tick %d after the carve seeds %d, merges %d, visits %d", step, counts.seeded, counts.merged, counts.flood_visits)
				break
			}
		}
		if conserved_water(&world) != total || world.water_dropped != dropped || world.water_to_sea != to_sea {
			testing.expectf(t, false, "tick %d after the carve: %d is not %d (dropped %d, to the sea %d)", step, conserved_water(&world), total, world.water_dropped - dropped, world.water_to_sea - to_sea)
			break
		}
		if empty := empty_water_body(&world); empty >= 0 {
			testing.expectf(t, false, "tick %d after the carve: body %d is alive with no cell", step, empty)
			break
		}
	}
	fmt.printfln("0299: the joined caves' last seed, merge or flood visit was %d ticks after the carve", last_active)
	testing.expect(t, alive_water_body_count(&world) > 0, "a body holds the water")
	for body, id in world.water_bodies {
		testing.expectf(t, !body.alive || body.sea || body.volume > 0, "body %d is alive with volume 0", id)
	}
}

@(test)
test_a_body_whose_last_cell_a_flood_claims_dies :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&world)
	sample := water_test_sample({7, 6, 7})
	lake, owned := water_body_at(&world, sample)
	testing.expect(t, owned, "the lake owns its air")
	volume := world.water_bodies[lake].volume
	dry := make_dry_water_body(&world, sample, 37)
	total := conserved_water(&world)
	mark_water_body_dirty(&world, lake)
	tick += 1
	step_field_water(&world, water_body_test_tuning(), tick)
	testing.expect(t, !world.water_bodies[dry].alive, "the dry body died")
	testing.expect_value(t, world.water_bodies[lake].volume, volume + 37)
	owner, found := water_body_at(&world, sample)
	testing.expect(t, found && owner == lake, "the lake owns the sample again")
	testing.expect_value(t, conserved_water(&world), total)
}

@(test)
test_a_body_whose_last_cell_absorption_takes_dies :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&world)
	sample := water_test_sample({7, 4, 7})
	lake, owned := water_body_at(&world, sample)
	testing.expect(t, owned, "the lake owns its air")
	volume := world.water_bodies[lake].volume
	dry := make_dry_water_body(&world, sample, 37)
	chunk, index := field_world_cell(&world, sample)
	set_front_water(&world, chunk, index, sample, 100)
	total := conserved_water(&world)
	changed := make([]bool, len(world.water_bodies), context.temp_allocator)
	absorb_front_water(&world, chunk, index, sample, field_water_span(sample), lake, changed)
	testing.expect(t, !world.water_bodies[dry].alive, "the dry body died at once")
	testing.expect_value(t, world.water_bodies[lake].volume, volume + 137)
	testing.expect_value(t, conserved_water(&world), total)
}

@(test)
test_a_body_whose_last_cell_the_sea_claims_dies :: proc(t: ^testing.T) {
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
	dry := make_dry_water_body(&world, water_test_sample({16, 6, 6}), 37)
	field_world_set_sample(&world, water_test_sample({12, 6, 5}), FIELD_AIR_SAMPLE)
	field_world_set_sample(&world, water_test_sample({13, 6, 5}), FIELD_AIR_SAMPLE)
	testing.expect(t, world.water_bodies[dry].alive, "the body lives until the sea claims its cell")
	to_sea := world.water_to_sea
	tick += 1
	step_field_water(&world, tuning, tick)
	testing.expect(t, !world.water_bodies[dry].alive, "the dry body died")
	testing.expect_value(t, world.water_to_sea - to_sea, 37)
}

@(test)
test_a_body_whose_last_cell_turns_ground_dies :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&world)
	sample := water_test_sample({7, 6, 7})
	dry := make_dry_water_body(&world, sample, 37)
	dropped := world.water_dropped
	field_world_set_sample(&world, sample, Field_Sample{MAXIMUM_DENSITY, .Stone, 0})
	testing.expect(t, !world.water_bodies[dry].alive, "the dry body died before any step")
	testing.expect_value(t, world.water_dropped - dropped, 37)
}

@(test)
test_a_pending_or_frozen_body_without_loaded_cells_lives :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&world)
	tuning := water_body_test_tuning()
	_, lake := only_water_body(t, &world)
	testing.expect(t, start_water_body_flood(&world, lake, tuning, true), "the flood starts")
	testing.expect_value(t, len(world.water_bodies[lake].loaded), 0)
	testing.expect(t, !free_empty_water_body(&world, lake), "a pending body is not freed")
	budget := tuning.flood_visit_budget
	testing.expect(t, run_water_body_flood(&world, tuning, &budget), "the flood ends")
	finish_water_body_flood(&world, tuning)
	testing.expect(t, world.water_bodies[lake].alive, "the lake lives")

	id, _ := allocate_water_body_id(&world)
	frozen_chunk := Field_Chunk_Coordinate{5, WATER_TEST_CHUNK_Y, 0}
	seed := field_chunk_origin(frozen_chunk) + Sample_Coordinate{7, 3, 7}
	base := floor_divide_i64(field_water_bottom(field_water_span(seed)), WATER_BODY_BAND) * WATER_BODY_BAND
	world.water_bodies[id] = Water_Body {
		alive         = true,
		volume        = 254,
		level         = base,
		written_level = base,
		base          = base,
		seed          = seed,
		spill_level   = max(i64),
		spill_volume  = max(i64),
		meshed_level  = min(i64),
	}
	bands := make([dynamic]Water_Body_Band)
	append(&bands, Water_Body_Band{opens = 1}, Water_Body_Band{closes = 1})
	append(&world.water_bodies[id].frozen, Water_Body_Frozen{chunk = frozen_chunk, owner = water_owner_of(id), bands = bands})
	testing.expect(t, !free_empty_water_body(&world, id), "a frozen body is not freed")
	tick += 1
	step_field_water(&world, tuning, tick)
	testing.expect(t, world.water_bodies[id].alive, "the frozen body lives")
}

// A table saved before 0299 can hold a body with no cell: the reader
// takes it, and the first tick frees it on every machine alike.
@(test)
test_a_saved_empty_body_loads_and_dies_on_the_first_tick :: proc(t: ^testing.T) {
	tick: u64 = 0
	first := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&first)
	_, lake := only_water_body(t, &first)
	id, _ := allocate_water_body_id(&first)
	base := first.water_bodies[lake].base
	first.water_bodies[id] = Water_Body {
		alive         = true,
		base          = base,
		level         = base,
		written_level = base,
		spill_level   = max(i64),
		spill_volume  = max(i64),
		meshed_level  = min(i64),
	}
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
	testing.expect(t, int(id) < len(second.water_bodies) && second.water_bodies[id].alive, "the empty body loads alive")
	tuning := water_body_test_tuning()
	tick += 1
	step_field_water(&first, tuning, tick)
	step_field_water(&second, tuning, tick)
	testing.expect(t, !first.water_bodies[id].alive, "the empty body died on the first world")
	testing.expect(t, !second.water_bodies[id].alive, "the empty body died on the second world")
	testing.expect_value(t, second.water_bodies[lake].volume, first.water_bodies[lake].volume)
	testing.expect_value(t, second.water_bodies[lake].level, first.water_bodies[lake].level)
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
}

// Front water on the basin floor's far corner; with no rise the seed's
// flood claims only samples no higher than the seed, which the walk moved
// to the floor's lowest, so it never reaches the sample.
seed_candidate_test_world :: proc() -> (world: Field_World, sample: Sample_Coordinate, tuning: Field_Water_Tuning) {
	world = make_body_test_world()
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	sample = water_test_sample({11, 3, 11})
	chunk, index := field_world_cell(&world, sample)
	set_front_water(&world, chunk, index, sample, 100)
	tuning = water_body_test_tuning()
	tuning.flood_rise_samples = 0
	return
}

@(test)
test_a_seed_whose_flood_misses_its_sample_takes_its_fill :: proc(t: ^testing.T) {
	world, sample, tuning := seed_candidate_test_world()
	defer destroy_field_world(&world)
	budget := tuning.flood_visit_budget
	testing.expect(t, seed_water_body(&world, sample, tuning, &budget), "a body is seeded")
	testing.expect(t, !world.water_flood.active, "no flood is pending")
	chunk, index := field_world_cell(&world, sample)
	testing.expect_value(t, chunk.water[index], 0)
	testing.expect(t, !field_sample_bit(&chunk.water_awake, index), "the sample sleeps")
	testing.expect_value(t, chunk.water_owner[index], WATER_OWNER_NONE)
	body, _ := only_water_body(t, &world)
	if body != nil {
		testing.expect_value(t, body.volume, 100)
		testing.expect(t, body.seed != sample, "the walk moved the seed")
	}
	testing.expect_value(t, conserved_water(&world), 100)
	tick: u64 = 0
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
		testing.expect_value(t, world.water_body_counts.seeded, 0)
		testing.expect_value(t, conserved_water(&world), 100)
	}
}

@(test)
test_a_pending_seed_flood_saved_takes_its_sample_alike :: proc(t: ^testing.T) {
	first, sample, tuning := seed_candidate_test_world()
	defer destroy_field_world(&first)
	budget: i64 = 1
	testing.expect(t, seed_water_body(&first, sample, tuning, &budget), "a body is seeded")
	testing.expect(t, first.water_flood.active, "the flood is pending")
	testing.expect(t, first.water_flood.has_candidate, "the flood keeps its sample")
	testing.expect_value(t, first.water_flood.candidate, sample)
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
	testing.expect(t, second.water_flood.has_candidate, "the loaded flood keeps its sample")
	testing.expect_value(t, second.water_flood.candidate, sample)
	tick: u64 = 1
	for world in ([]^Field_World{&first, &second}) {
		step_field_water(world, tuning, tick)
		chunk, index := field_world_cell(world, sample)
		testing.expect_value(t, chunk.water[index], 0)
		testing.expect(t, !world.water_flood.active, "the flood finished")
		testing.expect_value(t, conserved_water(world), 100)
	}
	testing.expect(t, water_bodies_equal(&first, &second))
}

// Work item 0300: bodies joined under water merge. The world is 0299's
// scenario: a lake drained into cave 1 through a hole, then cave 2 joined
// to it by a passage, both caves filling over the passage.

TWO_CAVE_NEAR :: [3]i32{4, 0, 4}
TWO_CAVE_FAR :: [3]i32{20, 0, 11}
TWO_CAVE_PASSAGE :: [3]i32{12, 1, 7}

// reserve_first_id keeps body 1 alive with a frozen part in a chunk that
// never loads, so the caves' bodies take higher ids.
joined_two_cave_world :: proc(t: ^testing.T, tick: ^u64, reserve_first_id := false) -> Field_World {
	world := make_body_test_world()
	if reserve_first_id {
		id, _ := allocate_water_body_id(&world)
		frozen_chunk := Field_Chunk_Coordinate{5, WATER_TEST_CHUNK_Y, 0}
		seed := field_chunk_origin(frozen_chunk) + Sample_Coordinate{7, 3, 7}
		base := floor_divide_i64(field_water_bottom(field_water_span(seed)), WATER_BODY_BAND) * WATER_BODY_BAND
		world.water_bodies[id] = Water_Body {
			alive         = true,
			level         = base,
			written_level = base,
			base          = base,
			seed          = seed,
			spill_level   = max(i64),
			spill_volume  = max(i64),
			meshed_level  = min(i64),
		}
		bands := make([dynamic]Water_Body_Band)
		append(&bands, Water_Body_Band{opens = 1}, Water_Body_Band{closes = 1})
		append(&world.water_bodies[id].frozen, Water_Body_Frozen{chunk = frozen_chunk, owner = water_owner_of(id), bands = bands})
	}
	carve_water_test_box(&world, water_test_sample(BASIN_LOW), water_test_sample(BASIN_HIGH))
	carve_water_test_box(&world, water_test_sample({4, 0, 4}), water_test_sample({11, 1, 11}))
	pour_test_water(&world, water_test_sample({4, 3, 4}), water_test_sample({11, 6, 11}), FIELD_WATER_FULL)
	field_world_set_sample(&world, water_test_sample({7, 2, 7}), FIELD_AIR_SAMPLE)
	ticks := settle_body_test_water(&world, water_body_test_tuning(), tick, 400)
	testing.expectf(t, ticks < 400, "the drained lake settles (%d ticks)", ticks)
	carve_water_test_box(&world, water_test_sample({13, 0, 4}), water_test_sample({20, 1, 11}))
	field_world_set_sample(&world, water_test_sample({12, 1, 7}), FIELD_AIR_SAMPLE)
	field_world_set_sample(&world, water_test_sample({13, 1, 7}), FIELD_AIR_SAMPLE)
	return world
}

// The bodies owning the near and the far cave's corners; joined when both
// are found and the same.
two_cave_bodies :: proc(world: ^Field_World) -> (near, far: Water_Body_Id, joined: bool) {
	near_found, far_found: bool
	near, near_found = water_body_at(world, water_test_sample(TWO_CAVE_NEAR))
	far, far_found = water_body_at(world, water_test_sample(TWO_CAVE_FAR))
	return near, far, near_found && far_found && near == far
}

two_cave_passage_bottom :: proc() -> i64 {
	return field_water_bottom(field_water_span(water_test_sample(TWO_CAVE_PASSAGE)))
}

// Runs ticks, the conserved sum checked against total every tick; false
// at the first tick it is not.
step_two_cave_world :: proc(t: ^testing.T, world: ^Field_World, tuning: Field_Water_Tuning, tick: ^u64, ticks: int, total: i64) -> bool {
	for _ in 0 ..< ticks {
		tick^ += 1
		step_field_water(world, tuning, tick^)
		if conserved_water(world) != total {
			testing.expectf(t, false, "tick %d: %d is not %d", tick^, conserved_water(world), total)
			return false
		}
	}
	return true
}

@(test) // slow
test_two_caves_joined_under_water_end_as_one_body :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := joined_two_cave_world(t, &tick)
	defer destroy_field_world(&world)
	tuning := water_body_test_tuning()
	total := conserved_water(&world)
	dropped, to_sea := world.water_dropped, world.water_to_sea
	joined_step := 0
	for step in 1 ..= 2500 {
		tick += 1
		step_field_water(&world, tuning, tick)
		if conserved_water(&world) != total || world.water_dropped != dropped || world.water_to_sea != to_sea {
			testing.expectf(t, false, "tick %d after the carve: %d is not %d (dropped %d, to the sea %d)", step, conserved_water(&world), total, world.water_dropped - dropped, world.water_to_sea - to_sea)
			break
		}
		_, _, joined := two_cave_bodies(&world)
		if joined && joined_step == 0 {
			joined_step = step
		} else if !joined && joined_step > 0 {
			testing.expectf(t, false, "tick %d after the carve: the caves joined at %d are two again", step, joined_step)
			break
		}
		counts := world.water_body_counts
		if step > 1500 && (counts.seeded != 0 || counts.merged != 0 || counts.flood_visits != 0) {
			testing.expectf(t, false, "tick %d after the carve seeds %d, merges %d, visits %d", step, counts.seeded, counts.merged, counts.flood_visits)
			break
		}
	}
	fmt.printfln("0300: the joined caves are one body %d ticks after the carve", joined_step)
	testing.expectf(t, joined_step > 0 && joined_step <= 1000, "the caves are one body within 1000 ticks (%d)", joined_step)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	owner := water_owner_of(id)
	for box in ([][2][3]i32{{{4, 0, 4}, {11, 1, 11}}, {{13, 0, 4}, {20, 1, 11}}, {TWO_CAVE_PASSAGE, TWO_CAVE_PASSAGE}}) {
		for z in box[0].z ..= box[1].z {
			for y in box[0].y ..= box[1].y {
				for x in box[0].x ..= box[1].x {
					chunk, index := field_world_cell(&world, water_test_sample({x, y, z}))
					if chunk.density[index] <= 0 {
						testing.expectf(t, chunk.water_owner[index] == owner, "%v is the body's", [3]i32{x, y, z})
					}
				}
			}
		}
	}
	testing.expectf(t, body.level >= two_cave_passage_bottom(), "the level %d at or over the passage's bottom %d", body.level, two_cave_passage_bottom())
	testing.expectf(t, body.joined_sill > 0 && body.joined_sill <= body.level, "the joined saddle %d under the level %d", body.joined_sill, body.level)
	testing.expect_value(t, body.volume, total - front_total(&world))
}

@(test) // slow
test_a_pump_in_one_of_two_joined_caves_lowers_the_one_body :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := joined_two_cave_world(t, &tick)
	defer destroy_field_world(&world)
	tuning := water_body_test_tuning()
	total := conserved_water(&world)
	if !step_two_cave_world(t, &world, tuning, &tick, 1000, total) {
		return
	}
	id, _, joined := two_cave_bodies(&world)
	testing.expect(t, joined, "the caves are one body")
	if !joined {
		return
	}
	probe := water_test_sample({16, 1, 7})
	probe_chunk, probe_index := field_world_cell(&world, probe)
	probe_before := probe_chunk.water[probe_index]
	level, written := world.water_bodies[id].level, world.water_bodies[id].written_level
	testing.expect_value(t, displace_water_body_volume(&world, id, water_test_sample({7, 0, 7}), 6000), 6000)
	body := &world.water_bodies[id]
	fmt.printfln("0300: pumped 6000, level %d -> %d, written %d -> %d, cave 2's probe %d -> %d", level, body.level, written, body.written_level, probe_before, probe_chunk.water[probe_index])
	testing.expect(t, body.level < level && body.written_level < written, "the one body's level fell")
	testing.expect_value(t, i32(probe_chunk.water[probe_index]), field_sea_fill(body.written_level, field_water_span(probe)))
	testing.expect(t, probe_chunk.water[probe_index] < probe_before, "cave 2's water fell")
	testing.expect(t, !body.dirty, "the body is not dirty")
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&world, tuning, tick)
		near, far, still := two_cave_bodies(&world)
		counts := world.water_body_counts
		if !still || near != id || far != id || counts.seeded != 0 || counts.merged != 0 || counts.flood_visits != 0 {
			testing.expectf(t, false, "tick %d: bodies %d and %d (joined %v), seeds %d, merges %d, visits %d", tick, near, far, still, counts.seeded, counts.merged, counts.flood_visits)
			break
		}
	}
	testing.expect_value(t, conserved_water(&world), total - 6000)
}

@(test) // slow
test_two_joined_caves_pumped_under_their_passage_part :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := joined_two_cave_world(t, &tick)
	defer destroy_field_world(&world)
	tuning := water_body_test_tuning()
	total := conserved_water(&world)
	if !step_two_cave_world(t, &world, tuning, &tick, 1000, total) {
		return
	}
	id, _, joined := two_cave_bodies(&world)
	testing.expect(t, joined, "the caves are one body")
	if !joined {
		return
	}
	testing.expect_value(t, displace_water_body_volume(&world, id, water_test_sample({7, 0, 7}), 36000), 36000)
	body := &world.water_bodies[id]
	testing.expectf(t, body.dirty, "the body under its joined saddle (%d under %d) floods again", body.level, body.joined_sill)
	total -= 36000
	parted_after := 0
	for step in 1 ..= 200 {
		if !step_two_cave_world(t, &world, tuning, &tick, 1, total) {
			return
		}
		_, near_found := water_body_at(&world, water_test_sample(TWO_CAVE_NEAR))
		_, far_found := water_body_at(&world, water_test_sample(TWO_CAVE_FAR))
		if _, _, still := two_cave_bodies(&world); near_found && far_found && !still {
			parted_after = step
			break
		}
	}
	testing.expectf(t, parted_after > 0, "the caves part within 200 ticks")
	if parted_after == 0 {
		return
	}
	near, far, _ := two_cave_bodies(&world)
	fmt.printfln("0300: pumped under the passage, the caves part after %d ticks: cave 1 %d, cave 2 %d", parted_after, world.water_bodies[near].volume, world.water_bodies[far].volume)
	testing.expectf(t, world.water_bodies[far].level < two_cave_passage_bottom(), "cave 2's level %d under the passage's bottom %d", world.water_bodies[far].level, two_cave_passage_bottom())
	far_volume := world.water_bodies[far].volume
	testing.expect_value(t, displace_water_body_volume(&world, near, water_test_sample({7, 0, 7}), 1000), 1000)
	total -= 1000
	if !step_two_cave_world(t, &world, tuning, &tick, 100, total) {
		return
	}
	far_after, far_found := water_body_at(&world, water_test_sample(TWO_CAVE_FAR))
	testing.expect(t, far_found, "cave 2 holds a body")
	if far_found {
		testing.expect_value(t, world.water_bodies[far_after].volume, far_volume)
	}
}

@(test) // slow
test_a_lake_rising_to_the_sill_of_the_lake_pouring_into_it_merges_with_it :: proc(t: ^testing.T) {
	world := make_body_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample({TROUGH_LAKE_A.x, 3, 4}), water_test_sample({TROUGH_LAKE_A.y, 31, 11}))
	carve_water_test_box(&world, water_test_sample({TROUGH_LAKE_B.x, 3, 4}), water_test_sample({TROUGH_LAKE_B.y, 31, 11}))
	pour_test_water(&world, water_test_sample({TROUGH_LAKE_A.x, 3, 4}), water_test_sample({TROUGH_LAKE_A.y, 13, 11}), FIELD_WATER_FULL)
	pour_test_water(&world, water_test_sample({TROUGH_LAKE_B.x, 3, 4}), water_test_sample({TROUGH_LAKE_B.y, 4, 11}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 300) < 300, "the lakes settle")
	total := conserved_water(&world)
	dig_test_trough(&world, 0)
	joined_step := 0
	for step in 1 ..= 3000 {
		tick += 1
		step_field_water(&world, tuning, tick)
		if conserved_water(&world) != total {
			testing.expectf(t, false, "step %d: %d is not %d", step, conserved_water(&world), total)
			break
		}
		counts := world.water_body_counts
		if joined_step == 0 {
			a, a_found := water_body_at(&world, water_test_sample({5, 3, 7}))
			b, b_found := water_body_at(&world, water_test_sample({17, 3, 7}))
			if a_found && b_found && a == b {
				joined_step = step
				testing.expectf(t, counts.merged == 1 && counts.seeded == 0, "step %d: the pass merges (merges %d, seeds %d)", step, counts.merged, counts.seeded)
			}
		}
		if step > 2000 && (counts.seeded != 0 || counts.merged != 0 || counts.flood_visits != 0) {
			testing.expectf(t, false, "step %d seeds %d, merges %d, visits %d", step, counts.seeded, counts.merged, counts.flood_visits)
			break
		}
	}
	// Before 0300 this world churned: 100 bodies after 3000 ticks.
	fmt.printfln("0300: the lake rising to the trough's sill merged at step %d", joined_step)
	testing.expectf(t, joined_step > 0 && joined_step <= 2000, "the lakes are one body within 2000 steps (%d)", joined_step)
	body, _ := only_water_body(t, &world)
	if body == nil {
		return
	}
	trough_bottom := field_water_bottom(field_water_span(water_test_sample({10, 9, 7})))
	testing.expectf(t, body.level >= trough_bottom, "the level %d at or over the trough's bottom %d", body.level, trough_bottom)
}

@(test) // slow
test_a_joined_body_saved_and_loaded_parts_alike :: proc(t: ^testing.T) {
	tick: u64 = 0
	first := joined_two_cave_world(t, &tick)
	defer destroy_field_world(&first)
	tuning := water_body_test_tuning()
	if !step_two_cave_world(t, &first, tuning, &tick, 1000, conserved_water(&first)) {
		return
	}
	id, _, joined := two_cave_bodies(&first)
	testing.expect(t, joined, "the caves are one body")
	if !joined {
		return
	}
	table := make([dynamic]byte, context.temp_allocator)
	write_water_body_table(&table, &first)
	second: Field_World
	defer destroy_field_world(&second)
	second.water_model = .Bodies
	second.water_planet = first.water_planet
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
	testing.expect(t, int(id) < len(second.water_bodies), "the body loads")
	if int(id) >= len(second.water_bodies) {
		return
	}
	testing.expect(t, first.water_bodies[id].joined_sill > 0, "the body spans a saddle")
	testing.expect_value(t, second.water_bodies[id].joined_sill, first.water_bodies[id].joined_sill)
	for world in ([]^Field_World{&first, &second}) {
		testing.expect_value(t, displace_water_body_volume(world, id, water_test_sample({7, 0, 7}), 36000), 36000)
	}
	for _ in 0 ..< 100 {
		tick += 1
		step_field_water(&first, tuning, tick)
		step_field_water(&second, tuning, tick)
	}
	testing.expect(t, water_bodies_equal(&first, &second), "the parted bodies are alike")
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
	for world in ([]^Field_World{&first, &second}) {
		near, near_found := water_body_at(world, water_test_sample(TWO_CAVE_NEAR))
		far, far_found := water_body_at(world, water_test_sample(TWO_CAVE_FAR))
		testing.expectf(t, near_found && far_found && near != far, "the caves parted (%d, %d)", near, far)
	}
}

// A guard, no change (0299's review): a merged body's frozen part keeps
// the absorbed body's owner tag, and the thaw hands the tagged samples to
// the survivor even after the absorbed id is reused.
@(test)
test_a_merged_bodys_frozen_part_thaws_into_the_survivor_after_its_id_is_reused :: proc(t: ^testing.T) {
	world := make_two_chunk_water_world({0, 1})
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	pour_test_water(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({TWO_CHUNK_BASIN_HIGH.x, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	body, lake := only_water_body(t, &world)
	if body == nil {
		return
	}
	returning := Field_Chunk_Coordinate{1, WATER_TEST_CHUNK_Y, 0}
	bytes := encode_field_chunk(world.chunks[returning], context.temp_allocator)
	field_world_remove_chunk(&world, returning)
	testing.expect_value(t, len(world.water_bodies[lake].frozen), 1)
	tag := water_owner_of(lake)
	total := conserved_water(&world)
	survivor := make_dry_water_body(&world, water_test_sample({22, 15, 7}), 0)
	testing.expect(t, survivor != lake, "a second id")
	merge_water_bodies(&world, survivor, lake)
	testing.expect(t, !world.water_bodies[lake].alive, "the lake was absorbed")
	testing.expect_value(t, len(world.water_bodies[survivor].frozen), 1)
	if len(world.water_bodies[survivor].frozen) == 1 {
		testing.expect_value(t, world.water_bodies[survivor].frozen[0].owner, tag)
	}
	reused := make_dry_water_body(&world, water_test_sample({23, 15, 7}), 0)
	testing.expect_value(t, reused, lake)
	arriving := new(Field_Chunk)
	testing.expect_value(t, decode_field_chunk_delta(bytes, arriving), "")
	field_world_insert_chunk(&world, arriving)
	sample := water_test_sample({FIELD_CHUNK_SIZE + 5, 3, 7})
	owner, owned := water_body_at(&world, sample)
	testing.expect(t, owned && owner == survivor, "the thawed sample is the survivor's")
	testing.expect_value(t, len(world.water_bodies[survivor].frozen), 0)
	named := slice.contains(world.water_bodies[reused].chunks[:], returning)
	testing.expect(t, !named, "the reused body does not name the returned chunk")
	testing.expect_value(t, conserved_water(&world), total)
	for _ in 0 ..< 50 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	owner, owned = water_body_at(&world, sample)
	testing.expect(t, owned && owner == survivor, "the sample is still the survivor's")
	testing.expect_value(t, conserved_water(&world), total)
}

// A settled body whose spill lies in a pending flood's claimed water
// (the flood's own tag, not the released one) waits for the flood: the
// merge pass never merges or kills the pending body, with the waiting
// body's id above the flood's or below it (0300's review).
@(test) // slow
test_the_merge_pass_leaves_a_pending_flood_alone :: proc(t: ^testing.T) {
	for waiting_below in ([]bool{false, true}) {
		pending_flood_beside_a_waiting_body(t, waiting_below)
	}
}

pending_flood_beside_a_waiting_body :: proc(t: ^testing.T, waiting_below: bool) {
	tick: u64 = 0
	first := joined_two_cave_world(t, &tick, waiting_below)
	defer destroy_field_world(&first)
	tuning := water_body_test_tuning()
	if !step_two_cave_world(t, &first, tuning, &tick, 1000, conserved_water(&first)) {
		return
	}
	lake, _, joined := two_cave_bodies(&first)
	testing.expect(t, joined, "the caves are one body")
	if !joined {
		return
	}
	if waiting_below {
		kill_water_body(&first, 1)
	}
	waiting := make_dry_water_body(&first, water_test_sample({7, 20, 7}), 0)
	testing.expect_value(t, waiting < lake, waiting_below)
	tuning.flood_visit_budget = 20
	mark_water_body_dirty(&first, lake)
	total := conserved_water(&first)
	tick += 1
	step_field_water(&first, tuning, tick)
	testing.expect(t, water_body_is_pending(&first, lake), "the lake's flood is pending")
	seed := first.water_bodies[lake].seed
	seed_chunk, seed_index := field_world_cell(&first, seed)
	testing.expect_value(t, seed_chunk.water_owner[seed_index], water_owner_of(lake))
	// Settled, at its sill, spilling into the lake's claimed seed.
	body := &first.water_bodies[waiting]
	body.spill, body.spill_level, body.spill_volume = seed, field_water_bottom(field_water_span(seed)), 0
	table := make([dynamic]byte, context.temp_allocator)
	write_water_body_table(&table, &first)
	second: Field_World
	defer destroy_field_world(&second)
	second.water_model = .Bodies
	second.water_planet = first.water_planet
	reader := Byte_Reader {
		data = table[:],
	}
	testing.expect(t, read_water_body_table(&reader, &second), "the table saved during the flood reads")
	testing.expect_value(t, bytes_left(reader), 0)
	for coordinate in sorted_field_chunk_coordinates(first.chunks) {
		chunk := new(Field_Chunk)
		testing.expect_value(t, decode_field_chunk_delta(encode_field_chunk(first.chunks[coordinate], context.temp_allocator), chunk), "")
		restore_field_chunk(&second, chunk)
	}
	rebuild_water_body_chunks(&second)
	testing.expect(t, second.water_flood.active && second.water_flood.body == lake, "the loaded flood is pending")
	testing.expect(t, water_bodies_equal(&first, &second), "the loaded bodies are alike")
	pending_ticks := 0
	for _ in 0 ..< 3000 {
		if !first.water_flood.active {
			break
		}
		pending_ticks += 1
		tick += 1
		step_field_water(&first, tuning, tick)
		step_field_water(&second, tuning, tick)
		if conserved_water(&first) != total || conserved_water(&second) != total {
			testing.expectf(t, false, "tick %d: %d and %d are not %d", tick, conserved_water(&first), conserved_water(&second), total)
			return
		}
		if first.water_flood.active && (first.water_flood.body != lake || !first.water_bodies[lake].alive || first.water_body_counts.merged != 0) {
			testing.expectf(t, false, "tick %d: the pending flood's body %d (alive %v) was merged (%d merges)", tick, first.water_flood.body, first.water_bodies[lake].alive, first.water_body_counts.merged)
			return
		}
	}
	fmt.printfln("0300: the pending lake (body %d) beside the waiting body %d finished its flood after %d ticks", lake, waiting, pending_ticks)
	testing.expect(t, !first.water_flood.active, "the flood finishes")
	testing.expect(t, water_bodies_equal(&first, &second), "the bodies stepped alike")
	for coordinate, chunk in first.chunks {
		testing.expect_value(t, field_chunk_state_hash(chunk), field_chunk_state_hash(second.chunks[coordinate]))
	}
}

// The trough lakes with B carved deeper (from y 1, so it holds the lower
// seed), A poured to y 13 and B to y 7, and an outlet from B at y 8, under
// the trough's sill at y 9, along to a shaft at x 26 that opens at the
// chunk's floor over a sea just under it. Settled before the trough is dug.
fed_outlet_trough_world :: proc(t: ^testing.T, tick: ^u64) -> Field_World {
	world: Field_World
	planet := water_test_sea_planet()
	planet.sea_level = field_water_bottom(field_water_span(water_test_sample({26, 0, 7}))) - FIELD_WATER_FULL / 2
	world.water_planet = planet
	make_bodies_world(&world)
	field_world_insert_chunk(&world, make_ground_water_test_chunk(0))
	carve_water_test_box(&world, water_test_sample({TROUGH_LAKE_A.x, 3, 4}), water_test_sample({TROUGH_LAKE_A.y, 31, 11}))
	carve_water_test_box(&world, water_test_sample({TROUGH_LAKE_B.x, 1, 4}), water_test_sample({TROUGH_LAKE_B.y, 31, 11}))
	carve_water_test_box(&world, water_test_sample({TROUGH_LAKE_B.y + 1, 8, 7}), water_test_sample({25, 8, 7}))
	carve_water_test_box(&world, water_test_sample({26, 0, 7}), water_test_sample({26, 8, 7}))
	pour_test_water(&world, water_test_sample({TROUGH_LAKE_A.x, 3, 4}), water_test_sample({TROUGH_LAKE_A.y, 13, 11}), FIELD_WATER_FULL)
	pour_test_water(&world, water_test_sample({TROUGH_LAKE_B.x, 1, 4}), water_test_sample({TROUGH_LAKE_B.y, 7, 11}), FIELD_WATER_FULL)
	ticks := settle_body_test_water(&world, water_body_test_tuning(), tick, 300)
	testing.expectf(t, ticks < 300, "the lakes settle (%d ticks)", ticks)
	return world
}

// A fed lake draining through an outlet under the sill of the lake pouring
// into it is not merged with that lake: the union would flood from the fed
// lake's lower seed, stop at the outlet and split the other to the front,
// over and over (0300's review). Before the guard, at inflow 70: 196
// seeds, 168 merges, 29448 flood visits in the 500 ticks; on main before
// 0300 and with the guard: 1 seed, no merge, 456 visits.
@(test) // slow
test_a_fed_lake_draining_under_the_sill_of_the_lake_pouring_into_it_stays_apart :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := fed_outlet_trough_world(t, &tick)
	defer destroy_field_world(&world)
	tuning := water_body_test_tuning()
	trough_sill := field_water_bottom(field_water_span(water_test_sample({10, 9, 7})))
	outlet_sill := field_water_bottom(field_water_span(water_test_sample({23, 8, 7})))
	testing.expect(t, outlet_sill < trough_sill, "the outlet lies under the trough's sill")
	dig_test_trough(&world, 0)
	total := conserved_water(&world)
	to_sea, to_edge, dropped := world.water_to_sea, world.water_to_edge, world.water_dropped
	feed := water_test_sample({17, 1, 7})
	fed, seeds, merges, visits: i64
	for step in 1 ..= 500 {
		if id, found := water_body_at(&world, feed); found {
			fed += credit_water_body_volume(&world, id, feed, 70)
		}
		tick += 1
		step_field_water(&world, tuning, tick)
		counts := world.water_body_counts
		seeds += counts.seeded
		merges += counts.merged
		visits += counts.flood_visits
		if conserved_water(&world) + world.water_to_sea - to_sea + world.water_to_edge - to_edge + world.water_dropped - dropped != total + fed {
			testing.expectf(t, false, "step %d: the water is not conserved", step)
			break
		}
	}
	fmt.printfln("0300: the fed lake under the trough: %d seeds, %d merges, %d flood visits, %d fed, %d to the sea, %d to the edge", seeds, merges, visits, fed, world.water_to_sea - to_sea, world.water_to_edge - to_edge)
	testing.expect_value(t, fed, 500 * 70)
	// Since 0370 the outlet's front water at the shaft's foot moves into the
	// missing sea sample under it over its sea fill, the set's edge.
	testing.expect(t, world.water_to_sea - to_sea + world.water_to_edge - to_edge > 0, "the outlet runs out of the set")
	testing.expectf(t, seeds <= 1 && merges == 0 && visits <= 456, "at most main's 1 seed, 0 merges and 456 visits")
	a, a_found := water_body_at(&world, water_test_sample({5, 3, 7}))
	b, b_found := water_body_at(&world, water_test_sample({17, 3, 7}))
	testing.expect(t, a_found && b_found && a != b, "the lakes stay two")
}

// A merge takes the absorbed body's lower seed only when its chunk is
// loaded, so the survivor's reflood is not held for a missing chunk.
@(test)
test_a_merge_keeps_the_survivors_seed_when_the_lower_one_is_not_loaded :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 3, &tick)
	defer destroy_field_world(&world)
	_, lake := only_water_body(t, &world)
	high := make_dry_water_body(&world, water_test_sample({7, 20, 7}), 0)
	survivor, absorbed := min(lake, high), max(lake, high)
	kept_seed := world.water_bodies[survivor].seed
	// A seed far under both, in a chunk outside the set.
	missing := field_chunk_origin({0, WATER_TEST_CHUNK_Y - 1, 0}) + Sample_Coordinate{7, 3, 7}
	chunk, _ := field_world_cell(&world, missing)
	testing.expect(t, chunk == nil, "the seed's chunk is not loaded")
	world.water_bodies[absorbed].seed = missing
	merge_water_bodies(&world, survivor, absorbed)
	testing.expect_value(t, world.water_bodies[survivor].seed, kept_seed)
	testing.expect(t, world.water_bodies[survivor].dirty, "the survivor floods again")
	tick += 1
	step_field_water(&world, water_body_test_tuning(), tick)
	testing.expect(t, !world.water_bodies[survivor].dirty, "the survivor flooded from its own seed")

	// A loaded lower seed is taken.
	low := make_dry_water_body(&world, water_test_sample({7, 25, 7}), 0)
	survivor, absorbed = min(survivor, low), max(survivor, low)
	lower_seed := water_test_sample({4, 3, 4})
	world.water_bodies[absorbed].seed = lower_seed
	world.water_bodies[survivor].seed = water_test_sample({7, 10, 7})
	merge_water_bodies(&world, survivor, absorbed)
	testing.expect_value(t, world.water_bodies[survivor].seed, lower_seed)
}

// Work item 0312: every water sample of the world the body's, none awake.
expect_body_owns_the_water :: proc(t: ^testing.T, world: ^Field_World, id: Water_Body_Id, location := #caller_location) {
	for _, chunk in world.chunks {
		testing.expect(t, !field_sample_bits_any(&chunk.water_awake), "no sample is awake", loc = location)
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water[index] > 0 {
				testing.expectf(t, chunk.water_owner[index] == water_owner_of(id), "the sample %v is the body's", field_chunk_sample(chunk, index), loc = location)
			}
		}
	}
}

// Work item 0312: the samples of still water no one owns in the world.
still_unowned_water_samples :: proc(world: ^Field_World) -> int {
	count := 0
	for _, chunk in world.chunks {
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if field_sample_is_still_unowned_water(chunk, index) {
				count += 1
			}
		}
	}
	return count
}

// Work item 0312: the generated lake of make_test_lake_chunk over x 4 to
// 12, with a ground ridge at x 8 of ridge_samples layers up from the
// basin's floor (to the chunk's top it parts the lake in two); the bytes'
// sum.
make_split_test_lake_chunk :: proc(ridge_samples: i32) -> (chunk: ^Field_Chunk, total: i64) {
	chunk, total = make_test_lake_chunk(0, {4, BASIN_LOW.y, BASIN_LOW.z}, {12, BASIN_HIGH.y, BASIN_HIGH.z}, test_lake_level())
	for z in BASIN_LOW.z ..= BASIN_HIGH.z {
		for y in BASIN_LOW.y ..< min(BASIN_LOW.y + ridge_samples, FIELD_CHUNK_SIZE) {
			index := field_local_to_index({8, y, z})
			total -= i64(chunk.water[index])
			chunk.water[index] = 0
			field_chunk_set_sample(chunk, index, {MAXIMUM_DENSITY, .Stone, 0})
		}
	}
	return
}

// Work item 0312: a generated lake settles into bodies with nothing awake
// and no still water no one owns, whole or over a ridge under its level
// (one pocket, one wake, one body); parted to the chunk's top, each half
// is a pocket of its own, woken and settled into a body of its own.
@(test) // slow
test_a_generated_lake_settles_into_its_bodies :: proc(t: ^testing.T) {
	for ridge in ([4]i32{0, 2, 4, FIELD_CHUNK_SIZE}) {
		world: Field_World
		make_bodies_world(&world)
		chunk, total := make_split_test_lake_chunk(ridge)
		field_world_insert_chunk(&world, chunk)
		pockets := ridge == FIELD_CHUNK_SIZE ? 2 : 1
		testing.expectf(t, field_sample_bits_count(&chunk.water_awake) == pockets, "ridge %d: a sample wakes per pocket (%d)", ridge, field_sample_bits_count(&chunk.water_awake))
		tick: u64 = 0
		ticks := settle_body_test_water(&world, water_body_test_tuning(), &tick, 200)
		testing.expectf(t, ticks < 200, "ridge %d: the lake settles", ridge)
		testing.expectf(t, alive_water_body_count(&world) == pockets, "ridge %d: %d bodies", ridge, alive_water_body_count(&world))
		testing.expectf(t, !any_water_awake(&world), "ridge %d: nothing is awake", ridge)
		testing.expectf(t, still_unowned_water_samples(&world) == 0, "ridge %d: %d samples of still water no one owns", ridge, still_unowned_water_samples(&world))
		testing.expectf(t, conserved_water(&world) == total, "ridge %d: %d of %d conserved", ridge, conserved_water(&world), total)
		destroy_field_world(&world)
	}
}

// Work item 0312: a lake chunk arriving beside a settled body at its level
// wakes nothing and floods the body again, which takes its water.
@(test)
test_an_arriving_lake_chunk_joins_the_lake_beside_it :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	field_world_insert_chunk(&world, make_ground_water_test_chunk(0))
	carve_water_test_box(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({FIELD_CHUNK_SIZE - 1, TWO_CHUNK_BASIN_HIGH.y, TWO_CHUNK_BASIN_HIGH.z}))
	pour_test_water(&world, water_test_sample(TWO_CHUNK_BASIN_LOW), water_test_sample({FIELD_CHUNK_SIZE - 1, 8, TWO_CHUNK_BASIN_HIGH.z}), FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	chunk, _ := make_test_lake_chunk(1, {0, TWO_CHUNK_BASIN_LOW.y, TWO_CHUNK_BASIN_LOW.z}, {TWO_CHUNK_BASIN_HIGH.x - FIELD_CHUNK_SIZE, TWO_CHUNK_BASIN_HIGH.y, TWO_CHUNK_BASIN_HIGH.z}, body.level)
	field_world_insert_chunk(&world, chunk)
	testing.expect(t, !field_sample_bits_any(&chunk.water_awake), "no sample of the arriving lake wakes")
	testing.expect(t, world.water_bodies[id].dirty, "the body beside it floods again")
	total := conserved_water(&world)
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 200) < 200)
	_, joined := only_water_body(t, &world)
	testing.expect_value(t, joined, id)
	expect_body_owns_the_water(t, &world, id)
	testing.expect_value(t, conserved_water(&world), total)
}

// Work item 0334: a ground chunk on the diagonal, where a slab is about
// 1.73 samples tall, holding two pits across a ridge.
RIDGE_TEST_CHUNK :: Field_Chunk_Coordinate{58, 58, 58}

// The bottom of the ridge chunk's sample {16, 16, 16}, which the floors
// and the levels are measured from.
ridge_test_reference :: proc() -> i64 {
	return field_water_bottom(field_water_span(field_chunk_origin(RIDGE_TEST_CHUNK) + Sample_Coordinate{16, 16, 16}))
}

// The pit's poured level, both under the ridge: A 127 fill units under
// the reference, B 76.
ridge_test_level :: proc(pit: int) -> i64 {
	return ridge_test_reference() - (pit == 1 ? 127 : 76)
}

// The part a local sample lies in, across u along (1, -1, 0) and v along
// (1, 1, -2): 0 for none, 1 for pit A, 2 for pit B, 3 for the ridge.
ridge_test_part :: proc(local: [3]i32) -> int {
	u := local.x - local.y
	v := local.x + local.y - 2 * local.z
	if abs(u) > 10 || abs(v) > 14 {
		return 0
	}
	if u < -1 {
		return 1
	}
	if u > 1 {
		return 2
	}
	return 3
}

// Ground but for the parts, air from each part's floor (pit A 6 samples
// under the reference, pit B 5, the ridge at it) to 8 samples over the
// reference.
make_ridge_test_chunk :: proc() -> ^Field_Chunk {
	chunk := new(Field_Chunk)
	chunk.coordinate = RIDGE_TEST_CHUNK
	reference := ridge_test_reference()
	floors := [4]i64{0, reference - 6 * FIELD_WATER_FULL, reference - 5 * FIELD_WATER_FULL, reference}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		local := field_index_to_local(index)
		part := ridge_test_part(local)
		bottom := field_water_bottom(field_water_span(field_chunk_origin(RIDGE_TEST_CHUNK) + Sample_Coordinate(local)))
		if part != 0 && bottom >= floors[part] && bottom <= reference + 8 * FIELD_WATER_FULL {
			field_chunk_set_sample(chunk, index, FIELD_AIR_SAMPLE)
		} else {
			field_chunk_set_sample(chunk, index, {MAXIMUM_DENSITY, .Stone, 0})
		}
	}
	return chunk
}

// Pours the pit's air samples no one owns to level (a sample another body
// owns keeps its byte); the fill poured.
pour_ridge_test_pit :: proc(world: ^Field_World, chunk: ^Field_Chunk, pit: int, level: i64) -> (total: i64) {
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if ridge_test_part(field_index_to_local(index)) != pit || chunk.density[index] > 0 || chunk.water_owner[index] != WATER_OWNER_NONE {
			continue
		}
		sample := field_chunk_sample(chunk, index)
		fill := field_sea_fill(level, field_water_span(sample))
		if fill > 0 {
			set_field_water(world, chunk, index, sample, fill)
			total += i64(fill)
		}
	}
	return
}

// The ridge world with the first pit poured and settled into one body.
ridge_test_world_poured_once :: proc(t: ^testing.T, first_pit: int, tick: ^u64) -> (world: Field_World, chunk: ^Field_Chunk, id: Water_Body_Id, total: i64) {
	make_bodies_world(&world)
	chunk = make_ridge_test_chunk()
	field_world_insert_chunk(&world, chunk)
	total = pour_ridge_test_pit(&world, chunk, first_pit, ridge_test_level(first_pit))
	ticks := settle_body_test_water(&world, water_body_test_tuning(), tick, 200)
	testing.expectf(t, ticks < 200, "pit %d settles (%d ticks)", first_pit, ticks)
	_, id = only_water_body(t, &world)
	return
}

// A sample of the pit the body owns under its level that does not join
// its water (the uncapped search): its fringe beyond the ridge.
ridge_test_fringe_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, id: Water_Body_Id, pit: int) -> (sample: Sample_Coordinate, found: bool) {
	not_joined := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		sample = field_chunk_sample(chunk, index)
		if ridge_test_part(field_index_to_local(index)) == pit && chunk.water_owner[index] == water_owner_of(id) && field_water_bottom(field_water_span(sample)) < world.water_bodies[id].level && !water_sample_joins_body_water(world, id, sample, max(int), &not_joined) {
			return sample, true
		}
	}
	return {}, false
}

// The lowest (bottom, then index order) air sample of the pit.
ridge_test_pit_floor :: proc(chunk: ^Field_Chunk, pit: int) -> Sample_Coordinate {
	floor: Sample_Coordinate
	floor_bottom := max(i64)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if ridge_test_part(field_index_to_local(index)) != pit || chunk.density[index] > 0 {
			continue
		}
		sample := field_chunk_sample(chunk, index)
		if bottom := field_water_bottom(field_water_span(sample)); bottom < floor_bottom {
			floor, floor_bottom = sample, bottom
		}
	}
	return floor
}

// Work item 0334: the first pit's flood crosses the ridge through slabs
// taller than the step and owns a fringe in the other pit, under its level
// but joined to its water only over the ridge. The second pit's flood
// takes the fringe instead of merging the first body, so the two settle
// apart in either order, with one seed and no merge (before 0334 neither
// order settled: each body's flood merged the other and released it).
@(test)
test_two_pits_sharing_a_ridge_settle_apart :: proc(t: ^testing.T) {
	tuning := water_body_test_tuning()
	for first_pit in 1 ..= 2 {
		second_pit := 3 - first_pit
		tick: u64 = 0
		world, chunk, first, total := ridge_test_world_poured_once(t, first_pit, &tick)
		_, fringe := ridge_test_fringe_sample(&world, chunk, first, second_pit)
		testing.expectf(t, fringe, "pit %d first: its body owns a fringe in pit %d", first_pit, second_pit)
		total += pour_ridge_test_pit(&world, chunk, second_pit, ridge_test_level(second_pit))
		seeds, merges: i64
		ticks := 0
		for ticks < 200 && settle_body_test_water(&world, tuning, &tick, 1) == 1 {
			ticks += 1
			seeds += world.water_body_counts.seeded
			merges += world.water_body_counts.merged
		}
		testing.expectf(t, ticks < 200, "pit %d first: the two pits settle (%d ticks)", first_pit, ticks)
		testing.expectf(t, alive_water_body_count(&world) == 2, "pit %d first: %d bodies", first_pit, alive_water_body_count(&world))
		a, a_found := water_body_at(&world, ridge_test_pit_floor(chunk, 1))
		b, b_found := water_body_at(&world, ridge_test_pit_floor(chunk, 2))
		testing.expectf(t, a_found && b_found && a != b, "pit %d first: the pits' floors are two bodies' (%d, %d)", first_pit, a, b)
		testing.expectf(t, !any_water_awake(&world), "pit %d first: nothing is awake", first_pit)
		testing.expectf(t, conserved_water(&world) == total, "pit %d first: %d of %d conserved", first_pit, conserved_water(&world), total)
		testing.expectf(t, seeds == 1 && merges == 0, "pit %d first: %d seeds, %d merges", first_pit, seeds, merges)
		destroy_field_world(&world)
	}
}

// Work item 0334: past its limit the join search answers joined, so a
// flood merges as before 0334 where it cannot afford to search further.
@(test)
test_a_join_search_past_its_limit_merges :: proc(t: ^testing.T) {
	tick: u64 = 0
	world, chunk, id, _ := ridge_test_world_poured_once(t, 1, &tick)
	defer destroy_field_world(&world)
	sample, found := ridge_test_fringe_sample(&world, chunk, id, 2)
	testing.expect(t, found, "the first body owns a fringe in the other pit")
	if !found {
		return
	}
	not_joined := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
	testing.expect(t, water_sample_joins_body_water(&world, id, sample, 1, &not_joined), "the search with limit 1 answers joined")
}

// Work item 0334: a search that answers not joined remembers the samples
// it visited, and a remembered sample answers not joined unsearched (with
// limit 1, which a search would answer joined), so a flood searches a
// fringe once a call however many of its samples it meets.
@(test)
test_a_fringe_found_not_joined_is_not_searched_again :: proc(t: ^testing.T) {
	tick: u64 = 0
	world, chunk, id, _ := ridge_test_world_poured_once(t, 1, &tick)
	defer destroy_field_world(&world)
	sample, found := ridge_test_fringe_sample(&world, chunk, id, 2)
	testing.expect(t, found, "the first body owns a fringe in the other pit")
	if !found {
		return
	}
	not_joined := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
	testing.expect(t, !water_sample_joins_body_water(&world, id, sample, max(int), &not_joined), "the fringe does not join")
	testing.expect(t, sample in not_joined, "the search remembers its start")
	for remembered in not_joined {
		testing.expectf(t, !water_sample_joins_body_water(&world, id, remembered, 1, &not_joined), "the remembered %v answers unsearched", remembered)
	}
}

// Work item 0336: the water standing on a generated lake's sample reaches
// the lake's level from any layer, full or half full, and not a unit over
// it; a sample another body owns above ends the column at the top of the
// sample under it.
@(test)
test_a_water_column_reaches_the_level_its_top_stands_at :: proc(t: ^testing.T) {
	world: Field_World
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	chunk, _ := make_test_lake_chunk(0, BASIN_LOW, BASIN_HIGH, test_lake_level())
	field_world_insert_chunk(&world, chunk)
	own := water_owner_of(3)
	level := test_lake_level()
	for y in ([4]i32{BASIN_LOW.y, 6, 9, 10}) {
		index := field_local_to_index({6, y, 6})
		sample := field_chunk_sample(chunk, index)
		testing.expectf(t, field_water_column_reaches(&world, chunk, index, sample, own, level), "from y %d the column reaches the level", y)
		testing.expectf(t, !field_water_column_reaches(&world, chunk, index, sample, own, level + 1), "from y %d the column stays under one over the level", y)
	}
	chunk.water_owner[field_local_to_index({6, 8, 6})] = water_owner_of(5)
	index := field_local_to_index({6, BASIN_LOW.y, 6})
	sample := field_chunk_sample(chunk, index)
	under := field_water_span(field_chunk_sample(chunk, field_local_to_index({6, 7, 6})))
	top := field_water_bottom(under) + under.height
	testing.expect(t, field_water_column_reaches(&world, chunk, index, sample, own, top), "the column reaches the top of the sample under another body's")
	testing.expect(t, !field_water_column_reaches(&world, chunk, index, sample, own, top + 1), "the column ends under another body's sample")
}

// Work item 0336: a generated lake over a ridge under its level is one
// body after its first flood: the flood passes the ridge into the lake's
// water beyond it, which stands over the ridge, instead of spilling there
// (before 0336, 479 and 399 samples stayed no one's, the spill at the
// ridge).
@(test)
test_a_generated_lake_over_a_ridge_is_one_body_after_its_first_flood :: proc(t: ^testing.T) {
	tuning := water_body_test_tuning()
	for ridge in ([2]i32{2, 4}) {
		world: Field_World
		make_bodies_world(&world)
		chunk, _ := make_split_test_lake_chunk(ridge)
		field_world_insert_chunk(&world, chunk)
		flooded := false
		for tick in u64(1) ..= 200 {
			step_field_water(&world, tuning, tick)
			if alive_water_body_count(&world) > 0 && !world.water_flood.active {
				flooded = true
				break
			}
		}
		testing.expectf(t, flooded, "ridge %d: a body lives and no flood is pending", ridge)
		body, _ := only_water_body(t, &world)
		testing.expectf(t, still_unowned_water_samples(&world) == 0, "ridge %d: %d samples of still water no one owns", ridge, still_unowned_water_samples(&world))
		if body != nil {
			testing.expectf(t, body.spill_level == max(i64), "ridge %d: no spill (%d over the level)", ridge, body.spill_level - body.level)
		}
		destroy_field_world(&world)
	}
}

// Work item 0370, the set's edge under bodies, on the edge tests' open
// planet (edge_test_planet) with the shipped tuning, whose films dry.

pour_front_test_water :: proc(world: ^Field_World, low, high: Sample_Coordinate, fill: i32) {
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				sample := Sample_Coordinate{x, y, z}
				chunk := world.chunks[sample_to_field_chunk_coordinate(sample)]
				set_front_water(world, chunk, sample_to_field_index(sample), sample, fill)
			}
		}
	}
}

// 0370: front water that reaches the set's edge where the generation makes
// air leaves the simulation; no water stands against the edge.
@(test) // slow
test_front_water_leaves_through_the_sets_edge :: proc(t: ^testing.T) {
	world := make_edge_test_ground(true)
	defer destroy_field_world(&world)
	make_bodies_world(&world)
	pour_front_test_water(&world, water_test_sample(EDGE_TEST_HEAP_LOW), water_test_sample(EDGE_TEST_HEAP_HIGH), FIELD_WATER_FULL)
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	for tick in u64(1) ..= 600 {
		step_field_water(&world, tuning, tick)
	}
	held := conserved_water(&world) + world.water_to_edge
	testing.expect(t, world.water_to_edge > 0, "the edge took water")
	testing.expectf(t, held <= EDGE_TEST_HEAP_FILL && held >= EDGE_TEST_HEAP_FILL - EDGE_TEST_FILMS_BOUND, "the bodies, the front and the edge hold %d of %d", held, EDGE_TEST_HEAP_FILL)
	testing.expectf(t, edge_test_most_on_a_face(&world) <= tuning.minimum_fill, "front water on a face holds %d", edge_test_most_on_a_face(&world))
	// The water left in the floor's dimples at the edge (the sphere's
	// curve) seeds bodies whose floods claim the face sample beside the
	// edge before they find the spill there: each holds no more than the
	// water under its spill and the weir's dead band.
	for body, id in world.water_bodies {
		if body.alive && !body.sea {
			testing.expectf(t, body.spill_outside && body.volume <= body.spill_volume + i64(tuning.weir_dead_band), "body %d holds %d over its spill's %d", id, body.volume, body.spill_volume)
		}
	}
}

// 0370's spill basin: a cave in an all ground chunk on the open planet,
// floor at y 4, x 8 to 30, z 8 to 23, its roof over y 12, walled in ground
// but at x 31 (the chunk's +x face), where the ground stands to y 9; filled
// to y 11 as front water and settled.
make_edge_spill_test_world :: proc(t: ^testing.T, tuning: Field_Water_Tuning, tick: ^u64) -> Field_World {
	world := make_water_test_world()
	world.water_planet = edge_test_planet(true)
	make_bodies_world(&world)
	carve_water_test_box(&world, water_test_sample({8, 4, 8}), water_test_sample({30, 12, 23}))
	carve_water_test_box(&world, water_test_sample({31, 10, 8}), water_test_sample({31, 12, 23}))
	pour_front_test_water(&world, water_test_sample({8, 4, 8}), water_test_sample({30, 11, 23}), FIELD_WATER_FULL)
	ticks := settle_body_test_water(&world, tuning, tick, 2000)
	testing.expectf(t, ticks < 2000, "the basin settles (%d ticks)", ticks)
	return world
}

// 0370: a basin whose rim meets the set's edge where the generation makes
// dry air spills out of the set there, and its weir pours to the edge.
@(test)
test_a_body_spills_out_where_its_basin_meets_the_sets_edge :: proc(t: ^testing.T) {
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	tick: u64 = 0
	world := make_edge_spill_test_world(t, tuning, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	testing.expect(t, body.spill_outside, "the body spills out of the set")
	// The spill is the sample beyond the edge, across the notch at x 31.
	spill := body.spill - water_test_sample({0, 0, 0})
	testing.expectf(t, spill.x == 32 && spill.y == 10, "the spill at local %v", spill)
	// The settle leaves the water over the notch in the body (the front
	// resting on its water joins it), which the weir pours out at its cap.
	drained := 0
	for ; drained < 8000 && world.water_bodies[id].volume > world.water_bodies[id].spill_volume + i64(tuning.weir_dead_band); drained += 1 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expectf(t, drained < 8000, "the weir drains the body to its spill (%d ticks)", drained)
	to_edge := world.water_to_edge
	pour_front_test_water(&world, water_test_sample({10, 12, 10}), water_test_sample({14, 12, 17}), FIELD_WATER_FULL)
	poured := i64(40 * FIELD_WATER_FULL)
	for _ in 0 ..< 1200 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body = &world.water_bodies[id]
	testing.expectf(t, body.volume <= body.spill_volume + i64(tuning.weir_dead_band), "the volume %d over the spill's %d", body.volume, body.spill_volume)
	testing.expectf(t, world.water_to_edge - to_edge >= poured - i64(tuning.weir_dead_band) - EDGE_TEST_FILMS_BOUND, "the edge took %d of %d poured", world.water_to_edge - to_edge, poured)
}

// 0370: a body's own frozen part beyond the edge is a wall to its flood,
// never a spill out of the set.
@(test)
test_a_frozen_part_keeps_the_sets_edge_a_wall :: proc(t: ^testing.T) {
	world := make_ground_chunks_water_world({0, 1})
	defer destroy_field_world(&world)
	world.water_planet = edge_test_planet(true)
	make_bodies_world(&world)
	carve_water_test_box(&world, water_test_sample({20, 4, 8}), water_test_sample({FIELD_CHUNK_SIZE + 11, 12, 23}))
	pour_front_test_water(&world, water_test_sample({20, 4, 8}), water_test_sample({FIELD_CHUNK_SIZE + 11, 9, 23}), FIELD_WATER_FULL)
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	tick: u64 = 0
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 600) < 600, "the basin settles")
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume := body.volume
	destroy_field_chunk(field_world_detach_chunk(&world, {1, WATER_TEST_CHUNK_Y, 0}))
	mark_water_body_dirty(&world, id)
	for _ in 0 ..< 300 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body = &world.water_bodies[id]
	testing.expect(t, !body.spill_outside, "the frozen part is a wall")
	testing.expect_value(t, body.volume, volume)
	testing.expect_value(t, world.water_to_edge, 0)
}

// 0370: a chunk arriving beside a spill out of the set floods the body
// again at once; with ground there the basin is sealed.
@(test)
test_a_chunk_arriving_where_a_body_spilled_out_floods_it_again :: proc(t: ^testing.T) {
	tuning := make_field_water_tuning(test_field_game_config().field_water)
	tick: u64 = 0
	world := make_edge_spill_test_world(t, tuning, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	testing.expect(t, body.spill_outside, "the body spills out of the set")
	arriving := make_ground_water_test_chunk(1)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if field_index_to_local(index).y > 12 {
			field_chunk_set_sample(arriving, index, FIELD_AIR_SAMPLE)
		}
	}
	field_world_insert_chunk(&world, arriving)
	testing.expect(t, world.water_bodies[id].dirty, "the arrival floods the body again")
	testing.expect(t, settle_body_test_water(&world, tuning, &tick, 600) < 600, "the flood ends")
	testing.expect(t, !world.water_bodies[id].spill_outside, "the basin is sealed")
}

// 0370: a lake whose weir spills into a chunk that leaves the set pours
// to the edge instead of waiting.
@(test)
test_a_weir_whose_spill_chunk_left_pours_out_of_the_set :: proc(t: ^testing.T) {
	world := make_ground_chunks_water_world({0, 1})
	defer destroy_field_world(&world)
	world.water_planet = edge_test_planet(true)
	run_body_test_trough_across_chunks(&world)
	lake := water_test_sample({TROUGH_LAKE_A.x + 18, 3, 7})
	id, found := water_body_at(&world, lake)
	testing.expect(t, found, "lake A is a body")
	if !found {
		return
	}
	leaving := Field_Chunk_Coordinate{1, WATER_TEST_CHUNK_Y, 0}
	testing.expect(t, sample_to_field_chunk_coordinate(world.water_bodies[id].spill) == leaving, "lake A spills into chunk 1")
	destroy_field_chunk(field_world_detach_chunk(&world, leaving))
	to_edge := world.water_to_edge
	pour_front_test_water(&world, water_test_sample({TROUGH_LAKE_A.x + 18, 12, 4}), water_test_sample({TROUGH_LAKE_A.x + 21, 12, 8}), FIELD_WATER_FULL)
	poured := i64(20 * FIELD_WATER_FULL)
	tuning := water_body_test_tuning()
	tick: u64 = 1600
	for _ in 0 ..< 1200 {
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	body := &world.water_bodies[id]
	testing.expectf(t, body.volume >= body.spill_volume && body.volume <= body.spill_volume + i64(tuning.weir_dead_band), "the volume %d against the spill's %d", body.volume, body.spill_volume)
	testing.expectf(t, world.water_to_edge - to_edge >= poured - i64(tuning.weir_dead_band), "the edge took %d of %d poured", world.water_to_edge - to_edge, poured)
}
