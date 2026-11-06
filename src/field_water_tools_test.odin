package game

import "core:testing"

// Work item 0295: the demo's buckets, through the players' tick
// (tick_field_simulation queues queue_field_water_edit), on the fixture of
// field_water_pump_test.odin under both water models.

// The miner stands on the basin's floor under floor (the lowest air
// sample) looking straight down, the bucket held.
stand_water_tool_test_miner :: proc(state: ^Simulation_State, content: Simulation_Content, floor: Sample_Coordinate, item: string) {
	spacing := state.field.spacing_millimetres
	position := sample_to_world_position(floor, spacing)
	up, _ := normalize_fixed(cast([3]i64)position)
	feet := position - World_Position(fixed_scale(up, sample_axis_to_position(1, spacing) / 2))
	miner := &state.players[0]
	pitch := miner.field.pitch
	miner.field = make_field_player(feet, {UNIT_VECTOR_ONE, 0, 0})
	miner.field.pitch = pitch
	hold_test_item(miner, content, item)
}

// No ground sample holds water: a pour fills room only.
ground_holds_no_water :: proc(world: ^Field_World) -> bool {
	for _, chunk in world.chunks {
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.density[index] > 0 && chunk.water[index] > 0 {
				return false
			}
		}
	}
	return true
}

// Five presses into the empty basin pour five press fills, the first
// into the air sample in front of the hit; a hold of 1 + 3 * 6 ticks
// pours four times more.
@(test)
test_a_pour_of_n_presses_raises_the_total_by_n_times_the_press_fill :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		stand_water_tool_test_miner(&state, content, water_test_sample({7, 3, 7}), "water_bucket")
		testing.expect_value(t, state.players[0].field.tool, Field_Held_Tool.Water)
		press := []Field_Player_Input{{just_pressed = {.Place}}}
		tick_field_simulation(&state, content, press)
		sample, found := field_water_tool_sample(&state.field.world, state.field.spacing_millimetres, state.players[0].field, content.field.tuning)
		testing.expect(t, found, "the bucket aims at the floor's air")
		testing.expect_value(t, sample, water_test_sample({7, 3, 7}))
		testing.expectf(t, water_tool_total(&state.field.world) == 254, "%v: one press pours one fill", model)
		for _ in 1 ..< 5 {
			tick_field_simulation(&state, content, press)
		}
		run_water_tool_test_ticks(&state, content, 30)
		testing.expectf(t, water_tool_total(&state.field.world) == 5 * 254, "%v: total %d", model, water_tool_total(&state.field.world))
		testing.expect_value(t, state.players[0].field.poured_fill, 5 * 254)
		testing.expect(t, ground_holds_no_water(&state.field.world), "no ground sample holds water")
		tick_field_simulation(&state, content, []Field_Player_Input{{held = {.Place}, just_pressed = {.Place}}})
		for _ in 1 ..< 1 + 3 * 6 {
			tick_field_simulation(&state, content, []Field_Player_Input{{held = {.Place}}})
		}
		testing.expect_value(t, state.players[0].field.poured_fill, 9 * 254)
		run_water_tool_test_ticks(&state, content, 30)
		testing.expectf(t, water_tool_total(&state.field.world) == 9 * 254, "%v: total %d", model, water_tool_total(&state.field.world))
		testing.expect(t, ground_holds_no_water(&state.field.world), "no ground sample holds water")
		// Mine with a bucket digs nothing.
		tick_field_simulation(&state, content, []Field_Player_Input{{held = {.Dig}, just_pressed = {.Dig}}})
		testing.expect_value(t, len(state.field.edits), 0)
		testing.expect_value(t, len(state.field.water_edits), 0)
	}
}

// Three presses of the drain bucket on the settled lake take three press
// fills; seventy more empty what the brush reaches, never more than the
// lake held. Under bodies the body gives it all and its level follows its
// volume; under teleport the films the brush does not reach stay.
@(test)
test_a_drain_lowers_the_total_by_what_it_takes :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		pour_water_tool_test_lake(t, &state, content)
		stand_water_tool_test_miner(&state, content, water_test_sample({5, 3, 6}), "drain_bucket")
		volume_before: i64 = 0
		if model == .Bodies {
			if body, _ := only_water_body(t, &state.field.world); body != nil {
				volume_before = body.volume
			}
		}
		press := []Field_Player_Input{{just_pressed = {.Place}}}
		for _ in 0 ..< 3 {
			tick_field_simulation(&state, content, press)
			run_water_tool_test_ticks(&state, content, 30)
		}
		testing.expect_value(t, state.players[0].field.drained_fill, 762)
		testing.expectf(t, water_tool_total(&state.field.world) == WATER_TOOL_TEST_LAKE - 762, "%v: total %d", model, water_tool_total(&state.field.world))
		if model == .Bodies {
			if body, _ := only_water_body(t, &state.field.world); body != nil {
				testing.expect_value(t, body.volume, volume_before - 762)
				testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
			}
		}
		for _ in 0 ..< 70 {
			tick_field_simulation(&state, content, press)
			run_water_tool_test_ticks(&state, content, 30)
		}
		drained := state.players[0].field.drained_fill
		testing.expectf(t, water_tool_total(&state.field.world) + drained == WATER_TOOL_TEST_LAKE, "%v: the drain counts what it took (%d left, %d drained)", model, water_tool_total(&state.field.world), drained)
		testing.expect(t, drained > 762 && drained <= WATER_TOOL_TEST_LAKE)
		if model == .Bodies {
			testing.expect_value(t, drained, WATER_TOOL_TEST_LAKE)
			testing.expect_value(t, water_tool_total(&state.field.world), 0)
		}
	}
}

// The world side: a pour into a full column climbs nowhere (no room in
// the brush, nothing poured), and a drain of a dry brush takes nothing.
@(test)
test_a_pour_finds_room_only_and_a_dry_drain_takes_nothing :: proc(t: ^testing.T) {
	world := make_water_test_world()
	defer destroy_field_world(&world)
	carve_water_test_box(&world, water_test_sample({4, 3, 4}), water_test_sample({6, 3, 6}))
	centre := water_test_sample({5, 3, 5})
	radius := sample_axis_to_position(1, WATER_TOOL_TEST_SPACING)
	testing.expect_value(t, drain_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 254), 0)
	brush := field_water_brush_samples(&world, WATER_TOOL_TEST_SPACING, centre, radius)
	testing.expect_value(t, len(brush), 5)
	testing.expect_value(t, brush[0].sample, centre)
	testing.expect_value(t, pour_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 6 * 254), 5 * 254)
	testing.expect_value(t, total_test_water(&world), 5 * 254)
	testing.expect_value(t, pour_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 254), 0)
	testing.expect_value(t, drain_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 300), 300)
	testing.expect_value(t, total_test_water(&world), 5 * 254 - 300)
}

// Fix round: on the sea's samples the sea gives and takes without limit
// and nothing else changes: a pour (into full sea water, so the whole
// press goes to the sea), a drain, a sink and a source.
@(test)
test_the_sea_gives_and_takes_without_limit :: proc(t: ^testing.T) {
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
	step_field_water(&world, water_body_test_tuning(), 1)
	centre := water_test_sample({7, 10, 7})
	index := sample_to_field_index(centre)
	testing.expect_value(t, chunk.water_owner[index], WATER_OWNER_SEA)
	bytes := chunk.water
	owners := chunk.water_owner
	to_sea := world.water_to_sea
	radius := sample_axis_to_position(1, WATER_TOOL_TEST_SPACING)
	up := [3]i64{0, UNIT_VECTOR_ONE, 0}
	testing.expect_value(t, pour_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 254), 254)
	testing.expect_value(t, world.water_to_sea, to_sea + 254)
	testing.expect_value(t, drain_field_water(&world, WATER_TOOL_TEST_SPACING, centre, radius, 16256), 16256)
	testing.expect_value(t, sink_field_water(&world, centre, up, WATER_TOOL_TEST_SPACING, 1_000_000), 1_000_000)
	testing.expect_value(t, source_field_water(&world, centre, up, WATER_TOOL_TEST_SPACING, 1_000_000), 1_000_000)
	testing.expect_value(t, world.water_to_sea, to_sea + 254 + 1_000_000)
	testing.expect(t, chunk.water == bytes, "no byte changed")
	testing.expect(t, chunk.water_owner == owners, "no owner changed")
	testing.expect_value(t, alive_water_body_count(&world), 0)
	testing.expect_value(t, world.water_bodies[WATER_BODY_SEA].level, world.water_planet.sea_level)
}

// Fix round: a body credited while its flood is pending keeps the volume
// and its old level; the flood's finish sets the level from the volume.
@(test)
test_a_body_credited_during_its_flood_levels_at_the_finish :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, id := only_water_body(t, &world)
	if body == nil {
		return
	}
	total := conserved_water(&world)
	tuning := water_body_test_tuning()
	tuning.flood_visit_budget = 50
	mark_water_body_dirty(&world, id)
	tick += 1
	step_field_water(&world, tuning, tick)
	testing.expect(t, water_body_is_pending(&world, id), "the flood is pending")
	level, volume := world.water_bodies[id].level, world.water_bodies[id].volume
	testing.expect_value(t, credit_water_body_volume(&world, id, water_test_sample({7, 11, 7}), 1000), 1000)
	testing.expect_value(t, world.water_bodies[id].volume, volume + 1000)
	testing.expect_value(t, world.water_bodies[id].level, level)
	for _ in 0 ..< 200 {
		if !world.water_flood.active {
			break
		}
		tick += 1
		step_field_water(&world, tuning, tick)
	}
	testing.expect(t, !world.water_flood.active, "the flood finished")
	body = &world.water_bodies[id]
	testing.expect_value(t, body.volume, volume + 1000)
	testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
	testing.expect(t, body.level > level, "the level rose at the finish")
	testing.expect_value(t, conserved_water(&world), total + 1000)
}

// Fix round: the water bucket aimed into a full lake deeper than its
// brush pours into the lake's volume, exactly one press, its level
// following; full front water under teleport is left as it is.
@(test)
test_a_pour_into_deep_water_raises_the_lake_by_a_press :: proc(t: ^testing.T) {
	tick: u64 = 0
	world := settled_body_test_lake(t, 10, &tick)
	defer destroy_field_world(&world)
	body, _ := only_water_body(t, &world)
	if body == nil {
		return
	}
	volume, level := body.volume, body.level
	total := conserved_water(&world)
	radius := sample_axis_to_position(1, WATER_TOOL_TEST_SPACING)
	deep := water_test_sample({7, 5, 7})
	for sample in field_water_brush_samples(&world, WATER_TOOL_TEST_SPACING, deep, radius) {
		testing.expect_value(t, i32(sample.chunk.water[sample.index]), FIELD_WATER_FULL)
	}
	testing.expect_value(t, pour_field_water(&world, WATER_TOOL_TEST_SPACING, deep, radius, 254), 254)
	testing.expect_value(t, body.volume, volume + 254)
	testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
	testing.expect(t, body.level > level, "the level rises")
	testing.expect_value(t, conserved_water(&world), total + 254)

	front := make_water_test_world()
	defer destroy_field_world(&front)
	carve_water_test_box(&front, water_test_sample({4, 3, 4}), water_test_sample({10, 9, 10}))
	pour_test_water(&front, water_test_sample({4, 3, 4}), water_test_sample({10, 9, 10}), FIELD_WATER_FULL)
	full := total_test_water(&front)
	testing.expect_value(t, pour_field_water(&front, WATER_TOOL_TEST_SPACING, deep, radius, 254), 0)
	testing.expect_value(t, total_test_water(&front), full)
}
