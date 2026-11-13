package game

import "core:strings"
import "core:testing"

// Work item 0376: the field's offshore pumps and their water. The world
// is 0292's test chunk far up the +y axis at 1 m spacing: the land's
// surface between local y 11 and 12, and a pond dug into it, air from
// (16, 8, 4) to (23, 11, 11), full water to y 10. A pier is two
// foundations on a free frame standing on a column's top; a pump at cell
// (0, 1, 0) of it stands one cell over the floor, its intake cell's
// centre a pitch and a half over the hit and 2 m from it along the
// frame's right, inside the pond for any yaw.

OFFSHORE_TEST_POND_COLUMN :: [3]i32{19, 10, 7}
OFFSHORE_TEST_DRY_COLUMN :: [3]i32{6, 11, 24}
OFFSHORE_TEST_POND_LOW :: [3]i32{16, 8, 4}
OFFSHORE_TEST_POND_HIGH :: [3]i32{23, 10, 11}

make_offshore_pump_test_state :: proc(model: Water_Model) -> (state: Simulation_State, content: Simulation_Content) {
	world := model == .Bodies ? make_body_test_world() : make_water_test_world()
	carve_water_test_box(&world, water_test_sample({0, 12, 0}), water_test_sample({31, 31, 31}))
	carve_water_test_box(&world, water_test_sample(OFFSHORE_TEST_POND_LOW), water_test_sample({23, 11, 11}))
	items := make_test_items()
	content = test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	water := model == .Bodies ? water_body_test_tuning() : water_test_tuning()
	// No film dries inside a test, so the sums are exact.
	water.dry_ticks = 1_000_000
	water.offshore_pump_keep_depth_millimetres = 500
	water.offshore_pump_start_depth_millimetres = 750
	content.field.water = water
	content.field.foundation_pitch_millimetres = 1000
	content.field.bare_ground = make_bare_ground_tuning(test_game_config())
	content.field.bare_ground.flatness_millimetres = 250
	state = make_test_field_state(world, WATER_TOOL_TEST_SPACING)
	pour_test_water(&state.field.world, water_test_sample(OFFSHORE_TEST_POND_LOW), water_test_sample(OFFSHORE_TEST_POND_HIGH), FIELD_WATER_FULL)
	if model == .Bodies {
		settle_body_test_water(&state.field.world, water, &state.tick, 400)
	} else {
		settle_test_water(&state.field.world, water, &state.tick, 400)
	}
	add_test_miner(&state, items, FAR_FEET, {item = "offshore_pump", count = 3}, {item = "tar_pit_pump", count = 1})
	return
}

// The hit on the top of a column's sample along the radial.
offshore_pump_test_hit :: proc(column: [3]i32, spacing_millimetres: int) -> World_Position {
	position := sample_to_world_position(water_test_sample(column), spacing_millimetres)
	up, _ := normalize_fixed(cast([3]i64)position)
	return position + World_Position(fixed_scale(up, sample_axis_to_position(1, spacing_millimetres) / 2))
}

offshore_pump_test_pier :: proc(t: ^testing.T, state: ^Simulation_State, content: Simulation_Content, column: [3]i32) -> Frame_Id {
	foundation := test_machine(content.machines, "wooden_foundation")
	hit := offshore_pump_test_hit(column, state.field.spacing_millimetres)
	_, frame := place_free_foundation(&state.world.entities, content.machines, foundation, hit, {UNIT_VECTOR_ONE, 0, 0}, 1000)
	_, refusal := place_on_frame(&state.world.entities, content.machines, foundation, frame, {1, 0, 0}, 0)
	testing.expect_value(t, refusal, Frame_Placement_Refusal.None)
	return frame
}

// A pump of the machine queued at cell (0, 1, 0) of the frame and drained;
// the player's refusal.
queue_test_pier_pump :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, machine_id: string) -> Field_Edit_Refusal {
	placement := Field_Placement{kind = .Machine, machine = test_machine(content.machines, machine_id), frame = frame, cell = {0, 1, 0}}
	state.players[0].field_refusal = .None
	append(&state.field.placements, Queued_Field_Placement{player = 0, placement = placement})
	drain_field_placements(state, content)
	return state.players[0].field_refusal
}

// The live fluid machine of the kind on the frame, nil when none.
test_pump_on_frame :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Frame_Id, kind: Machine_Kind) -> ^Fluid_Machine {
	for &pump in state.world.entities.fluid_machines.entries {
		if pump.alive && pump.frame == frame && content.machines.machines[pump.machine].kind == kind {
			return &pump
		}
	}
	return nil
}

count_live_offshore_pumps :: proc(state: ^Simulation_State, content: Simulation_Content) -> int {
	count := 0
	for pump in state.world.entities.fluid_machines.entries {
		if pump.alive && content.machines.machines[pump.machine].kind == .Offshore_Pump {
			count += 1
		}
	}
	return count
}

// A pump queued on the pond's pier, which must pass.
place_test_pond_pump :: proc(t: ^testing.T, state: ^Simulation_State, content: Simulation_Content) -> ^Fluid_Machine {
	pier := offshore_pump_test_pier(t, state, content, OFFSHORE_TEST_POND_COLUMN)
	testing.expect_value(t, queue_test_pier_pump(state, content, pier, "offshore_pump"), Field_Edit_Refusal.None)
	return test_pump_on_frame(state, content, pier, .Offshore_Pump)
}

// Every sample of the pond's top layer (local y 10) at the fill, the
// layer over it empty (the settled level crosses it on the sphere).
set_test_pond_surface :: proc(world: ^Field_World, fill: i32) {
	pour_test_water(world, water_test_sample({16, 11, 4}), water_test_sample({23, 11, 11}), 0)
	pour_test_water(world, water_test_sample({16, 10, 4}), water_test_sample({23, 10, 11}), fill)
}

// A frame with identity axes whose cell (2, 0, 0) is centred on the
// sample.
offshore_test_frame_over :: proc(local: [3]i32, spacing_millimetres: int) -> Frame {
	half := millimetres_to_position_units(1000) / 2
	position := sample_to_world_position(water_test_sample(local), spacing_millimetres)
	return Frame{origin = position - World_Position{5 * half, half, half}, axes = {{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}}, pitch_millimetres = 1000}
}

@(test)
test_an_offshore_intake_reads_the_water_under_it :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	world := &state.field.world
	spacing := state.field.spacing_millimetres
	keep := content.field.water.offshore_pump_keep_depth_millimetres
	read :: proc(world: ^Field_World, spacing: int, local: [3]i32, depth: i64, generation := false) -> Offshore_Intake_Reading {
		return read_offshore_pump_intake(world, spacing, offshore_test_frame_over(local, spacing), {2, 0, 0}, depth, generation)
	}
	testing.expect_value(t, read(world, spacing, {19, 12, 7}, keep), Offshore_Intake_Reading.Wet)
	testing.expect_value(t, read(world, spacing, {6, 12, 24}, keep), Offshore_Intake_Reading.Dry)
	testing.expect_value(t, read(world, spacing, {19, 13, 7}, keep), Offshore_Intake_Reading.Dry)
	// The settled pond's level crosses the sample over its top layer on
	// the sphere (a fill there), so that sample is emptied: the walk then
	// meets water at local y 10 alone.
	above := water_test_sample({19, 11, 7})
	above_chunk, above_index := field_world_cell(world, above)
	set_field_water(world, above_chunk, above_index, above, 0)
	surface := water_test_sample({19, 10, 7})
	chunk, index := field_world_cell(world, surface)
	set_field_water(world, chunk, index, surface, 127)
	testing.expect_value(t, read(world, spacing, {19, 12, 7}, keep), Offshore_Intake_Reading.Wet)
	set_field_water(world, chunk, index, surface, 126)
	testing.expect_value(t, read(world, spacing, {19, 12, 7}, keep), Offshore_Intake_Reading.Dry)
	detached := field_world_detach_chunk(world, chunk.coordinate)
	testing.expect_value(t, read(world, spacing, {19, 12, 7}, keep), Offshore_Intake_Reading.Unloaded)
	testing.expect_value(t, read(world, spacing, {19, 12, 7}, keep, true), Offshore_Intake_Reading.Dry)
	field_world_insert_chunk(world, detached)
}

@(test)
test_a_field_offshore_pump_is_placed_only_over_water :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_offshore_pump_test_state(model)
		defer destroy_simulation(&state)
		item := test_item(content.items, "offshore_pump")
		pump := place_test_pond_pump(t, &state, content)
		testing.expectf(t, pump != nil && pump.source == .Present, "%v: the pond's pump stands with water", model)
		testing.expect_value(t, count_live_offshore_pumps(&state, content), 1)

		machine := test_machine(content.machines, "offshore_pump")
		hit := offshore_pump_test_hit(OFFSHORE_TEST_DRY_COLUMN, state.field.spacing_millimetres)
		bare := Field_Placement{kind = .Machine, machine = machine, new_frame = true, cell = field_footprint_origin({}, content.machines.machines[machine].footprint, 0), hit = hit, heading = {UNIT_VECTOR_ONE, 0, 0}}
		refusal := field_placement_refusal(&state, content, state.players[0], bare)
		testing.expectf(t, refusal == .No_Water_At_Intake, "%v: bare ground %v", model, refusal)
		testing.expect(t, frame_ghost_color(refusal) == GHOST_INVALID_COLOR, "the ghost is red")
		append(&state.field.placements, Queued_Field_Placement{player = 0, placement = bare})
		drain_field_placements(&state, content)
		testing.expect_value(t, state.players[0].field_refusal, Field_Edit_Refusal.No_Water_At_Intake)

		dry := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_DRY_COLUMN)
		testing.expect_value(t, queue_test_pier_pump(&state, content, dry, "offshore_pump"), Field_Edit_Refusal.No_Water_At_Intake)
		testing.expect_value(t, count_live_offshore_pumps(&state, content), 1)
		testing.expect_value(t, inventory_count(state.players[0].inventory, item), 2)
	}
}

@(test)
test_a_field_offshore_pump_stops_when_its_water_is_gone :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	pump := place_test_pond_pump(t, &state, content)
	if pump == nil {
		return
	}
	machine := content.machines.machines[pump.machine]
	pump.power.satisfaction = POWER_FULL
	refresh_offshore_pump_sources(&state, content)
	advance_fluid_machine(pump, machine, content, state.tick_rate)
	testing.expect_value(t, pump.state, Fluid_Machine_State.Producing)
	testing.expect(t, pump.buffers[0].level > 0, "the pump filled its port")

	world := &state.field.world
	pour_test_water(world, water_test_sample(OFFSHORE_TEST_POND_LOW), water_test_sample(OFFSHORE_TEST_POND_HIGH), 0)
	refresh_offshore_pump_sources(&state, content)
	testing.expect_value(t, pump.source, Pump_Source.Missing)
	level := pump.buffers[0].level
	advance_fluid_machine(pump, machine, content, state.tick_rate)
	testing.expect_value(t, pump.state, Fluid_Machine_State.No_Water)
	testing.expect_value(t, pump.buffers[0].level, level)
	testing.expect(t, !fluid_machine_wants_power(pump^, machine, content.fluids), "a pump without water asks no power")
	line := fluid_status_text(&state.world, content.machines, content.fluids, pump.handle, "Offshore pump")
	testing.expectf(t, strings.has_suffix(line, text("machine_state_no_water")), "%q", line)

	pour_test_water(world, water_test_sample(OFFSHORE_TEST_POND_LOW), water_test_sample(OFFSHORE_TEST_POND_HIGH), FIELD_WATER_FULL)
	refresh_offshore_pump_sources(&state, content)
	testing.expect_value(t, pump.source, Pump_Source.Present)
	advance_fluid_machine(pump, machine, content, state.tick_rate)
	testing.expect_value(t, pump.state, Fluid_Machine_State.Producing)
}

@(test)
test_an_offshore_pump_beyond_the_set_keeps_its_answer :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	pump := place_test_pond_pump(t, &state, content)
	if pump == nil {
		return
	}
	world := &state.field.world
	coordinate := sample_to_field_chunk_coordinate(water_test_sample(OFFSHORE_TEST_POND_LOW))
	chunk := field_world_detach_chunk(world, coordinate)
	testing.expect_value(t, refresh_offshore_pump_sources(&state, content), 0)
	testing.expect_value(t, pump.source, Pump_Source.Present)
	for z in i32(4) ..= 11 {
		for y in i32(8) ..= 10 {
			for x in i32(16) ..= 23 {
				chunk.water[sample_to_field_index(water_test_sample({x, y, z}))] = 0
			}
		}
	}
	field_world_insert_chunk(world, chunk)
	refresh_offshore_pump_sources(&state, content)
	testing.expect_value(t, pump.source, Pump_Source.Missing)
	chunk = field_world_detach_chunk(world, coordinate)
	refresh_offshore_pump_sources(&state, content)
	testing.expect_value(t, pump.source, Pump_Source.Missing)
	field_world_insert_chunk(world, chunk)
}

@(test)
test_an_old_saves_offshore_pump_reads_once :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	machine := test_machine(content.machines, "offshore_pump")
	entities := &state.world.entities
	pond := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_POND_COLUMN)
	dry := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_DRY_COLUMN)
	add_entity(entities, content.machines, machine, {0, 1, 0}, 0, pond)
	add_entity(entities, content.machines, machine, {0, 1, 0}, 0, dry)
	testing.expect_value(t, test_pump_on_frame(&state, content, pond, .Offshore_Pump).source, Pump_Source.Unread)
	testing.expect_value(t, refresh_offshore_pump_sources(&state, content), 1)
	testing.expect_value(t, test_pump_on_frame(&state, content, pond, .Offshore_Pump).source, Pump_Source.Present)
	testing.expect_value(t, test_pump_on_frame(&state, content, dry, .Offshore_Pump).source, Pump_Source.Missing)
	testing.expect_value(t, refresh_offshore_pump_sources(&state, content), 0)

	// A missing sample of the sea planet is sea: the generation's sea is
	// read once for a pump whose column is outside the set.
	sea, sea_content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&sea)
	sea.field.world.water_planet = water_test_sea_planet()
	sea_dry := offshore_pump_test_pier(t, &sea, sea_content, OFFSHORE_TEST_DRY_COLUMN)
	add_entity(&sea.world.entities, sea_content.machines, machine, {0, 1, 0}, 0, sea_dry)
	coordinate := sample_to_field_chunk_coordinate(water_test_sample(OFFSHORE_TEST_DRY_COLUMN))
	chunk := field_world_detach_chunk(&sea.field.world, coordinate)
	testing.expect_value(t, refresh_offshore_pump_sources(&sea, sea_content), 0)
	testing.expect_value(t, test_pump_on_frame(&sea, sea_content, sea_dry, .Offshore_Pump).source, Pump_Source.Present)
	field_world_insert_chunk(&sea.field.world, chunk)
}

@(test)
test_pumps_the_offshore_rule_leaves_alone :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	block := add_entity(&state.world.entities, content.machines, test_machine(content.machines, "offshore_pump"), {0, 40, 0}, 0)
	dry := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_DRY_COLUMN)
	testing.expect_value(t, queue_test_pier_pump(&state, content, dry, "tar_pit_pump"), Field_Edit_Refusal.None)
	tar := test_pump_on_frame(&state, content, dry, .Tar_Pit_Pump)
	offshore := pool_get(&state.world.entities.fluid_machines, block)
	if tar == nil || offshore == nil {
		testing.expect(t, false, "both pumps stand")
		return
	}
	refresh_offshore_pump_sources(&state, content)
	for pump in ([2]^Fluid_Machine{offshore, tar}) {
		testing.expect_value(t, pump.source, Pump_Source.Unread)
		pump.power.satisfaction = POWER_FULL
		advance_fluid_machine(pump, content.machines.machines[pump.machine], content, state.tick_rate)
		testing.expect_value(t, pump.state, Fluid_Machine_State.Producing)
	}
}

@(test)
test_the_developer_place_refuses_an_offshore_pump_off_water :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	machine := test_machine(content.machines, "offshore_pump")
	dry := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_DRY_COLUMN)
	testing.expect_value(t, place_on_frame_for_developer(&state, content, machine, dry, {0, 1, 0}, 0), field_refusal_keys[.No_Water_At_Intake])
	testing.expect_value(t, count_live_offshore_pumps(&state, content), 0)
	pond := offshore_pump_test_pier(t, &state, content, OFFSHORE_TEST_POND_COLUMN)
	testing.expect_value(t, place_on_frame_for_developer(&state, content, machine, pond, {0, 1, 0}, 0), "")
	pump := test_pump_on_frame(&state, content, pond, .Offshore_Pump)
	testing.expect(t, pump != nil && pump.source == .Present, "the developer's pump stands with water")
}

@(test)
test_an_offshore_pumps_source_round_trips :: proc(t: ^testing.T) {
	pump := Fluid_Machine {
		source = .Missing,
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &pump)
	read: Fluid_Machine
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, reader.problem, "")
	testing.expect_value(t, read.source, Pump_Source.Missing)
}

// Decision 4: a surface stepping across the keep depth every tick (0.45
// and 0.55 m) stops a pump with water once and leaves a pump without
// water as it is; one stepping inside the band (0.55 and 0.70 m) leaves
// either as it is. No tick switches the pump back.
@(test)
test_a_surface_waving_at_a_depth_does_not_switch_the_pump :: proc(t: ^testing.T) {
	state, content := make_offshore_pump_test_state(.Teleport)
	defer destroy_simulation(&state)
	pump := place_test_pond_pump(t, &state, content)
	if pump == nil {
		return
	}
	machine := content.machines.machines[pump.machine]
	world := &state.field.world
	spacing := i32(state.field.spacing_millimetres)
	fill :: proc(millimetres, spacing: i32) -> i32 {
		return millimetres * FIELD_WATER_FULL / spacing
	}
	pump.power.satisfaction = POWER_FULL
	Wave :: struct {
		low, high: i32,
		start:     Pump_Source,
		after:     Pump_Source,
	}
	waves := [?]Wave{{450, 550, .Present, .Missing}, {450, 550, .Missing, .Missing}, {550, 700, .Present, .Present}, {550, 700, .Missing, .Missing}}
	for wave in waves {
		pump.source = wave.start
		for tick in 0 ..< 20 {
			set_test_pond_surface(world, fill(tick % 2 == 0 ? wave.high : wave.low, spacing))
			refresh_offshore_pump_sources(&state, content)
			advance_fluid_machine(pump, machine, content, state.tick_rate)
			// The wave starts high, so a pump with water keeps it on the
			// first tick and stops on the first low one.
			expected := tick == 0 ? wave.start : wave.after
			testing.expectf(t, pump.source == expected, "%v tick %d: %v", wave, tick, pump.source)
			testing.expectf(t, (pump.state == .No_Water) == (expected == .Missing), "%v tick %d: %v", wave, tick, pump.state)
			pump.buffers[0].level = 0
		}
	}
}

// Decision 4's keys of field_water are shipped at 500 and 750 mm, bounded
// 1 to the reach, and the start may not lie under the keep.
@(test)
test_field_water_offshore_pump_depths_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	water := config.field_water
	testing.expect_value(t, water.offshore_pump_keep_depth_millimetres, 500)
	testing.expect_value(t, water.offshore_pump_start_depth_millimetres, 750)
	testing.expect_value(t, field_water_problem(water), "")
	cases := [?]struct {
		change: proc(water: ^Field_Water_Config),
		key:    string,
	} {
		{proc(water: ^Field_Water_Config) {water.offshore_pump_keep_depth_millimetres = 0}, "field_water.offshore_pump_keep_depth_millimetres "},
		{proc(water: ^Field_Water_Config) {water.offshore_pump_start_depth_millimetres = FIELD_OFFSHORE_INTAKE_REACH_MILLIMETRES + 1}, "field_water.offshore_pump_start_depth_millimetres "},
		{proc(water: ^Field_Water_Config) {water.offshore_pump_start_depth_millimetres = 499}, "field_water.offshore_pump_start_depth_millimetres "},
	}
	for entry in cases {
		changed := water
		entry.change(&changed)
		problem := field_water_problem(changed)
		testing.expectf(t, strings.has_prefix(problem, entry.key), "%q: %q", entry.key, problem)
	}
}
