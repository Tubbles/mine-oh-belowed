package game

import "core:strings"
import "core:testing"

// Work item 0295: the demo's pump, and the fixture the bucket tests share
// (field_water_tools_test.odin). The worlds are 0292's test chunk far up
// the +y axis at 1 m spacing, under either water model: the basin of
// samples (4, 3, 4) to (11, 10, 11), its floor the ground at local y 2.

WATER_TOOL_TEST_SPACING :: 1000
// The lake: the basin's floor layer of 8 by 8 samples poured full and
// settled, 16256 fill.
WATER_TOOL_TEST_LAKE :: 64 * FIELD_WATER_FULL

make_water_tool_test_state :: proc(model: Water_Model) -> (state: Simulation_State, content: Simulation_Content) {
	world := model == .Bodies ? make_body_test_world() : make_water_test_world()
	carve_water_test_box(&world, water_test_sample({4, 3, 4}), water_test_sample({11, 10, 11}))
	items := make_test_items()
	content = test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	water := model == .Bodies ? water_body_test_tuning() : water_test_tuning()
	// No film dries inside a test, so the sums are exact.
	water.dry_ticks = 1_000_000
	water.bucket_fill_per_press, water.bucket_repeat_ticks = 254, 6
	content.field.water = water
	content.field.foundation_pitch_millimetres = 1000
	content.field.bare_ground = make_bare_ground_tuning(test_game_config())
	state = make_test_field_state(world, WATER_TOOL_TEST_SPACING)
	add_test_miner(&state, items, FAR_FEET, {item = "water_pump", count = 1})
	return
}

// The lake, settled.
pour_water_tool_test_lake :: proc(t: ^testing.T, state: ^Simulation_State, content: Simulation_Content) {
	world := &state.field.world
	pour_test_water(world, water_test_sample({4, 3, 4}), water_test_sample({11, 3, 11}), FIELD_WATER_FULL)
	ticks := 0
	if world.water_model == .Bodies {
		ticks = settle_body_test_water(world, content.field.water, &state.tick, 400)
		only_water_body(t, world)
	} else {
		ticks = settle_test_water(world, content.field.water, &state.tick, 400)
	}
	testing.expectf(t, ticks < 400, "the lake settles (%d ticks)", ticks)
	testing.expect_value(t, water_tool_total(world), WATER_TOOL_TEST_LAKE)
}

// The water the model conserves: the bytes under teleport, the bodies'
// volumes and the front's fill under bodies.
water_tool_total :: proc(world: ^Field_World) -> i64 {
	return world.water_model == .Bodies ? conserved_water(world) : total_test_water(world)
}

// A pump queued on the bed under floor (the lowest air sample) and
// drained: the hit on the bed's surface, half a sample under floor along
// the radial, shifted so the bottom row's centre (between the footprint's
// two cells) stands over floor.
place_test_water_pump :: proc(t: ^testing.T, state: ^Simulation_State, content: Simulation_Content, floor: Sample_Coordinate) -> Entity_Handle {
	machine := test_machine(content.machines, "water_pump")
	spacing := state.field.spacing_millimetres
	position := sample_to_world_position(floor, spacing)
	up, _ := normalize_fixed(cast([3]i64)position)
	surface := position - World_Position(fixed_scale(up, sample_axis_to_position(1, spacing) / 2))
	heading := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	pitch := content.field.foundation_pitch_millimetres
	_, axes := free_frame_at(surface, heading, pitch)
	hit := surface - World_Position(fixed_scale(axes[FRAME_RIGHT], millimetres_to_position_units(pitch) / 2))
	footprint := content.machines.machines[machine].footprint
	placement := Field_Placement{kind = .Machine, machine = machine, rotation = 0, new_frame = true, cell = field_footprint_origin({}, footprint, 0), hit = hit, heading = heading}
	append(&state.field.placements, Queued_Field_Placement{player = 0, placement = placement})
	drain_field_placements(state, content)
	testing.expect_value(t, state.players[0].field_refusal, Field_Edit_Refusal.None)
	found := NO_ENTITY
	count := 0
	for pump in state.world.entities.fluid_machines.entries {
		if pump.alive && content.machines.machines[pump.machine].kind == .Water_Pump {
			found = pump.handle
			count += 1
		}
	}
	testing.expect_value(t, count, 1)
	return found
}

test_water_pump :: proc(state: ^Simulation_State, handle: Entity_Handle) -> ^Fluid_Machine {
	return pool_get(&state.world.entities.fluid_machines, handle)
}

run_water_tool_test_ticks :: proc(state: ^Simulation_State, content: Simulation_Content, ticks: int) {
	for _ in 0 ..< ticks {
		tick_field_simulation(state, content, {})
	}
}

// The pump on the lake's bed takes its intake there and its outlet a
// sample over it; as a sink for 600 ticks (10 s at 300 L/s) it moves
// exactly 762 fill, 3000 L, and the lake falls by as much.
@(test)
test_a_sink_pump_empties_a_lake_at_its_rate :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		pour_water_tool_test_lake(t, &state, content)
		level_before: i64 = 0
		if model == .Bodies {
			body, _ := only_water_body(t, &state.field.world)
			if body != nil {
				level_before = body.level
			}
		}
		handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
		pump := test_water_pump(&state, handle)
		if pump == nil {
			continue
		}
		testing.expect_value(t, pump.water_pump.intake, water_test_sample({5, 3, 6}))
		testing.expect_value(t, pump.water_pump.outlet, water_test_sample({5, 4, 6}))
		testing.expect_value(t, pump.water_pump.sample_millilitres, 1_000_000)
		testing.expect_value(t, pump.water_pump.mode, Water_Pump_Mode.Off)
		testing.expect(t, cycle_water_pump_mode(&state.world.entities, content.machines, handle))
		testing.expect_value(t, pump.water_pump.mode, Water_Pump_Mode.Sink)
		run_water_tool_test_ticks(&state, content, 600)
		pump = test_water_pump(&state, handle)
		testing.expectf(t, pump.water_pump.moved_fill == 762, "%v: moved %d", model, pump.water_pump.moved_fill)
		testing.expectf(t, water_tool_total(&state.field.world) == WATER_TOOL_TEST_LAKE - 762, "%v: total %d", model, water_tool_total(&state.field.world))
		testing.expect_value(t, pump.state, Fluid_Machine_State.Pumping)
		line := water_pump_status_text(pump^, "Water pump")
		testing.expectf(t, strings.contains(line, text("water_pump_mode_sink")) && strings.contains(line, "3000 L"), "%v: %q", model, line)
		if model == .Bodies {
			body, _ := only_water_body(t, &state.field.world)
			if body != nil {
				testing.expect(t, body.level < level_before, "the level falls")
				testing.expect_value(t, body.level, body_level_of_volume(body, body.volume))
			}
		}
	}
}

// After the sink's 600 ticks the pump as a source for 600 more puts the
// lake back to the fill: under teleport through its outlet, which held
// water on the way down; under bodies into the body's volume.
@(test)
test_a_source_pump_refills_it :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		pour_water_tool_test_lake(t, &state, content)
		handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
		if test_water_pump(&state, handle) == nil {
			continue
		}
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		run_water_tool_test_ticks(&state, content, 600)
		volume_before: i64 = 0
		if model == .Bodies {
			if body, _ := only_water_body(t, &state.field.world); body != nil {
				volume_before = body.volume
			}
		}
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		testing.expect_value(t, test_water_pump(&state, handle).water_pump.mode, Water_Pump_Mode.Source)
		outlet := test_water_pump(&state, handle).water_pump.outlet
		outlet_wet := false
		for _ in 0 ..< 600 {
			tick_field_simulation(&state, content, {})
			outlet_wet = outlet_wet || water_fill_at(&state.field.world, outlet) > 0
		}
		testing.expectf(t, test_water_pump(&state, handle).water_pump.moved_fill == 1524, "%v: moved %d", model, test_water_pump(&state, handle).water_pump.moved_fill)
		switch model {
		case .Teleport:
			testing.expect(t, outlet_wet, "the outlet held the water it poured")
			settle_test_water(&state.field.world, content.field.water, &state.tick, 400)
		case .Bodies:
			if body, _ := only_water_body(t, &state.field.world); body != nil {
				testing.expect_value(t, body.volume, volume_before + 762)
			}
			settle_body_test_water(&state.field.world, content.field.water, &state.tick, 400)
		}
		testing.expectf(t, water_tool_total(&state.field.world) == WATER_TOOL_TEST_LAKE, "%v: total %d", model, water_tool_total(&state.field.world))
	}
}

// Over dry ground a sink moves nothing, says no water and keeps no
// credit; a source there pours the credit's floor, 76 fill in 60 ticks.
@(test)
test_a_pump_over_dry_ground_moves_nothing_and_says_dry :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
		if test_water_pump(&state, handle) == nil {
			continue
		}
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		run_water_tool_test_ticks(&state, content, 60)
		pump := test_water_pump(&state, handle)
		testing.expect_value(t, pump.water_pump.moved_fill, 0)
		testing.expect_value(t, pump.state, Fluid_Machine_State.No_Water)
		testing.expect_value(t, pump.water_pump.credit, 0)
		testing.expect(t, strings.contains(water_pump_status_text(pump^, "Water pump"), text("machine_state_no_water")), "the line says no water")
		testing.expect_value(t, water_tool_total(&state.field.world), 0)
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		run_water_tool_test_ticks(&state, content, 60)
		pump = test_water_pump(&state, handle)
		testing.expectf(t, pump.water_pump.moved_fill == 76, "%v: moved %d", model, pump.water_pump.moved_fill)
		testing.expect_value(t, pump.state, Fluid_Machine_State.Pumping)
		testing.expectf(t, water_tool_total(&state.field.world) == 76, "%v: total %d", model, water_tool_total(&state.field.world))
	}
}

// Mine's pick up takes the pump back into the inventory and its frame
// with it; nothing moves afterwards. A pump placed where the miner stands
// is refused as burying the player, though it stands on the ground.
@(test)
test_a_pump_picked_up_returns_its_item :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		pour_water_tool_test_lake(t, &state, content)
		handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
		pump := test_water_pump(&state, handle)
		if pump == nil {
			continue
		}
		item := test_item(content.items, "water_pump")
		testing.expect_value(t, inventory_count(state.players[0].inventory, item), 0)
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		frame, origin := pump.frame, pump.origin
		drain_field_pick_up(&state, content, &state.players[0], frame, origin)
		testing.expect(t, test_water_pump(&state, handle) == nil, "the pump is gone")
		testing.expect_value(t, inventory_count(state.players[0].inventory, item), 1)
		_, frame_left := find_frame(&state.world.entities.frames, frame)
		testing.expect(t, !frame_left, "the frame went with the pump")
		total := water_tool_total(&state.field.world)
		run_water_tool_test_ticks(&state, content, 10)
		testing.expect_value(t, water_tool_total(&state.field.world), total)

		// Standing on the ground does not let it bury the miner.
		state.players[0].field.position = sample_to_world_position(water_test_sample({5, 3, 6}), WATER_TOOL_TEST_SPACING)
		machine := test_machine(content.machines, "water_pump")
		spacing := state.field.spacing_millimetres
		up, _ := normalize_fixed(cast([3]i64)sample_to_world_position(water_test_sample({5, 3, 6}), spacing))
		hit := sample_to_world_position(water_test_sample({5, 3, 6}), spacing) - World_Position(fixed_scale(up, sample_axis_to_position(1, spacing) / 2))
		placement := Field_Placement{kind = .Machine, machine = machine, new_frame = true, cell = field_footprint_origin({}, content.machines.machines[machine].footprint, 0), hit = hit, heading = {UNIT_VECTOR_ONE, 0, 0}}
		testing.expect_value(t, field_placement_refusal(&state, content, state.players[0], placement), Field_Edit_Refusal.Would_Bury_Player)
	}
}

// Two worlds with a sink running hash alike; one more tick on one does
// not.
@(test)
test_two_worlds_with_a_running_pump_hash_alike :: proc(t: ^testing.T) {
	for model in Water_Model {
		first, content := make_water_tool_test_state(model)
		defer destroy_simulation(&first)
		second, _ := make_water_tool_test_state(model)
		defer destroy_simulation(&second)
		states := [2]^Simulation_State{&first, &second}
		for state in states {
			pour_water_tool_test_lake(t, state, content)
			handle := place_test_water_pump(t, state, content, water_test_sample({5, 3, 6}))
			cycle_water_pump_mode(&state.world.entities, content.machines, handle)
			run_water_tool_test_ticks(state, content, 300)
		}
		testing.expectf(t, simulation_state_hash(&first) == simulation_state_hash(&second), "%v: the worlds hash alike", model)
		tick_field_simulation(&first, content, {})
		testing.expectf(t, simulation_state_hash(&first) != simulation_state_hash(&second), "%v: a tick more differs", model)
	}
}

// Interact cycles Sink, Source, Off; a chest takes no cycle. The pump has
// no panel and takes Interact, so X is Interact's alone on it.
@(test)
test_interact_cycles_the_pump_and_a_pump_has_no_panel :: proc(t: ^testing.T) {
	state, content := make_water_tool_test_state(.Teleport)
	defer destroy_simulation(&state)
	handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
	if test_water_pump(&state, handle) == nil {
		return
	}
	entities := &state.world.entities
	for expected in ([3]Water_Pump_Mode{.Sink, .Source, .Off}) {
		testing.expect(t, cycle_water_pump_mode(entities, content.machines, handle))
		testing.expect_value(t, test_water_pump(&state, handle).water_pump.mode, expected)
	}
	testing.expect_value(t, test_water_pump(&state, handle).state, Fluid_Machine_State.Idle)
	chest := add_entity(entities, content.machines, test_machine(content.machines, "wooden_chest"), {40, 0, 40}, 0)
	testing.expect(t, chest != NO_ENTITY)
	testing.expect(t, !cycle_water_pump_mode(entities, content.machines, chest), "a chest takes no cycle")
	testing.expect(t, !entity_has_panel(entities, content.machines, handle), "the pump has no panel")
	testing.expect(t, entity_takes_interact(entities, content.machines, handle), "the pump takes Interact")
	testing.expect(t, !entity_takes_interact(entities, content.machines, chest))
}

// The pump's nested record and the players' bucket counters round-trip
// the value codec by name; a pump and a player written before 0295 read
// zeros for them.
Fluid_Machine_Before_0295 :: struct {
	using common:       Entity_Common,
	buffers:            [MAXIMUM_FLUID_PORTS]Fluid_Buffer,
	closed:             [MAXIMUM_FLUID_PORTS]bool,
	slot_count:         int,
	slots:              [FLUID_MACHINE_SLOT_COUNT]Item_Stack,
	fuel_joules:        u32,
	fuel_item_joules:   u32,
	power:              Power_State,
	generated_joules:   u32,
	state:              Fluid_Machine_State,
	litre_remainder:    u32,
	lets_water_through: bool,
	still_water_ticks:  u32,
}

@(test)
test_a_water_pump_round_trips_the_save :: proc(t: ^testing.T) {
	state, content := make_water_tool_test_state(.Bodies)
	defer destroy_simulation(&state)
	pour_water_tool_test_lake(t, &state, content)
	handle := place_test_water_pump(t, &state, content, water_test_sample({5, 3, 6}))
	pump := test_water_pump(&state, handle)
	if pump == nil {
		return
	}
	cycle_water_pump_mode(&state.world.entities, content.machines, handle)
	run_water_tool_test_ticks(&state, content, 100)
	pump = test_water_pump(&state, handle)
	testing.expect(t, pump.water_pump.moved_fill > 0)
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, pump)
	read: Fluid_Machine
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, reader.problem, "")
	testing.expect_value(t, read.water_pump, pump.water_pump)

	player := &state.players[0].field
	player.water_tool_ticks, player.poured_fill, player.drained_fill = 4, 2540, 762
	clear(&bytes)
	write_value_of(&bytes, player)
	read_player: Field_Player
	reader = Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read_player))
	testing.expect_value(t, [3]i64{i64(read_player.water_tool_ticks), read_player.poured_fill, read_player.drained_fill}, [3]i64{4, 2540, 762})

	old := Fluid_Machine_Before_0295 {
		common = Entity_Common{machine = 3, origin = {1, 2, 3}},
		state = .Pumping,
	}
	clear(&bytes)
	write_value_of(&bytes, &old)
	from_before: Fluid_Machine
	reader = Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &from_before))
	testing.expect_value(t, reader.problem, "")
	testing.expect_value(t, from_before.water_pump, Water_Pump{})
	testing.expect_value(t, from_before.state, Fluid_Machine_State.Pumping)
}

// Fix round: a pump on a slope rising a whole sample under its second cell
// (steeper than 45 degrees), in a lake two samples deep. The centre of its
// bottom row lies in the ground; the intake climbs to the first open
// sample over it, in the water, and the sink moves water.
@(test)
test_a_pump_on_a_steep_slope_takes_its_intake_from_the_water :: proc(t: ^testing.T) {
	for model in Water_Model {
		state, content := make_water_tool_test_state(model)
		defer destroy_simulation(&state)
		world := &state.field.world
		spacing := state.field.spacing_millimetres
		floor := water_test_sample({5, 3, 6})
		position := sample_to_world_position(floor, spacing)
		up, _ := normalize_fixed(cast([3]i64)position)
		surface := position - World_Position(fixed_scale(up, sample_axis_to_position(1, spacing) / 2))
		heading := [3]i64{UNIT_VECTOR_ONE, 0, 0}
		pitch := content.field.foundation_pitch_millimetres
		_, axes := free_frame_at(surface, heading, pitch)
		// The hit a quarter pitch towards the second cell, so the bottom
		// row's centre stands three quarters of a sample beside the floor.
		hit := surface + World_Position(fixed_scale(axes[FRAME_RIGHT], millimetres_to_position_units(pitch) / 4))
		origin, frame_axes := free_frame_at(hit, heading, pitch)
		frame := Frame{origin = origin, axes = frame_axes, pitch_millimetres = pitch}
		first := frame_cell_centre(frame, {0, 0, 0})
		last := frame_cell_centre(frame, {1, 0, 0})
		step := nearest_field_sample(first + (last - first) / 2, spacing)
		testing.expect(t, step != floor, "the centre lies over the next sample")
		chunk, index := field_world_cell(world, step)
		field_chunk_set_sample(chunk, index, {MAXIMUM_DENSITY, .Stone, 0})
		for z in i32(4) ..= 11 {
			for y in i32(3) ..= 4 {
				for x in i32(4) ..= 11 {
					sample := water_test_sample({x, y, z})
					if field_sample_is_open(world, sample) {
						cell_chunk, cell_index := field_world_cell(world, sample)
						set_field_water(world, cell_chunk, cell_index, sample, FIELD_WATER_FULL)
					}
				}
			}
		}
		if model == .Bodies {
			settle_body_test_water(world, content.field.water, &state.tick, 400)
		} else {
			settle_test_water(world, content.field.water, &state.tick, 400)
		}
		machine := test_machine(content.machines, "water_pump")
		placement := Field_Placement{kind = .Machine, machine = machine, new_frame = true, cell = field_footprint_origin({}, content.machines.machines[machine].footprint, 0), hit = hit, heading = heading}
		append(&state.field.placements, Queued_Field_Placement{player = 0, placement = placement})
		drain_field_placements(&state, content)
		testing.expect_value(t, state.players[0].field_refusal, Field_Edit_Refusal.None)
		handle := NO_ENTITY
		for pump in state.world.entities.fluid_machines.entries {
			if pump.alive {
				handle = pump.handle
			}
		}
		pump := test_water_pump(&state, handle)
		if pump == nil {
			testing.expect(t, false, "the pump was placed")
			continue
		}
		intake := pump.water_pump.intake
		testing.expectf(t, intake == step + {0, 1, 0}, "%v: the intake %v climbs over the step %v", model, intake, step)
		testing.expect(t, field_sample_is_open(world, intake), "the intake is open")
		testing.expect(t, water_fill_at(world, intake) > 0, "the intake is in the water")
		cycle_water_pump_mode(&state.world.entities, content.machines, handle)
		total := water_tool_total(world)
		run_water_tool_test_ticks(&state, content, 60)
		pump = test_water_pump(&state, handle)
		testing.expectf(t, pump.water_pump.moved_fill == 76 && pump.state == .Pumping, "%v: moved %d, %v", model, pump.water_pump.moved_fill, pump.state)
		testing.expect_value(t, water_tool_total(world), total - 76)
	}
}

// Fix round: a pump placed into the pod's cabin, where the next joiner
// spawns, on bare ground under the cabin's floor or snapped onto the
// pod's cell, is refused: the pod's cells are taken (Frame_Cell_Taken),
// the spawn standing inside them, and nothing enters.
@(test) // slow
test_a_pump_over_the_spawn_is_refused :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	state := &session.simulation
	simulation_content := field_test_content(session, content)
	for _ in 0 ..< 30 {
		tick_field_test_simulation(state, simulation_content, {})
	}
	move_test_players_out_of_the_pod(state, content.machines)
	frame, floor := test_pod_cabin_floor(state, content.machines)
	spawn, found := field_pod_spawn(&state.world.entities, content.machines)
	testing.expect(t, found, "the world has a spawn")
	testing.expect(t, vector_length(cast([3]i64)(spawn.position - floor)) <= metres_to_position_units(1), "the spawn stands on the cabin's floor")
	pump := test_machine(content.machines, "water_pump")
	item := content.machines.machines[pump].item
	inventory_add(state.players[0].inventory, simulation_content.items, item, 2)
	footprint := content.machines.machines[pump].footprint
	bare := Field_Placement{kind = .Machine, machine = pump, new_frame = true, cell = field_footprint_origin({}, footprint, 0), hit = floor, heading = frame.axes[FRAME_FORWARD]}
	cell := world_to_frame_cell(frame, floor + World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2)))
	snapped := Field_Placement{kind = .Machine, machine = pump, frame = frame.id, cell = cell}
	pumps_before := len(state.world.entities.fluid_machines.entries)
	for placement in ([2]Field_Placement{bare, snapped}) {
		testing.expect_value(t, field_placement_refusal(state, simulation_content, state.players[0], placement), Field_Edit_Refusal.Frame_Cell_Taken)
		append(&state.field.placements, Queued_Field_Placement{player = 0, placement = placement})
		drain_field_placements(state, simulation_content)
		testing.expect_value(t, state.players[0].field_refusal, Field_Edit_Refusal.Frame_Cell_Taken)
	}
	testing.expect_value(t, len(state.world.entities.fluid_machines.entries), pumps_before)
	testing.expect_value(t, inventory_count(state.players[0].inventory, item), 2)
}

// Fix round: the tick's water events are dropped at the top of
// finish_field_tick, not by the water step, so a dig beside the lake, a
// bucket's pour into the lake's air and a running pump's intake, all
// before the step, reach the waves through water_events.
@(test)
test_a_dig_a_pour_and_a_pump_leave_their_events_for_the_waves :: proc(t: ^testing.T) {
	state, content := make_water_tool_test_state(.Bodies)
	defer destroy_simulation(&state)
	content.field.tech_demo = true
	pour_water_tool_test_lake(t, &state, content)
	handle := place_test_water_pump(t, &state, content, water_test_sample({8, 3, 8}))
	cycle_water_pump_mode(&state.world.entities, content.machines, handle)
	spacing := state.field.spacing_millimetres
	wall := water_test_sample({3, 3, 6})
	up, _ := normalize_fixed(cast([3]i64)sample_to_world_position(wall, spacing))
	dig := Field_Edit{mode = .Dig, brush = test_brush(.Sphere, 500, 127), centre = sample_to_world_position(wall, spacing), up = up}
	append(&state.field.edits, Queued_Field_Edit{player = 0, edit = dig})
	pour := Field_Water_Edit{mode = .Pour, centre = water_test_sample({6, 6, 6}), radius = sample_axis_to_position(1, spacing), amount = FIELD_WATER_FULL}
	append(&state.field.water_edits, Queued_Field_Water_Edit{player = 0, edit = pour})
	push_field_water_event(&state.field.world, .Stream_Mouth, wall, 1)
	state.tick += 1
	finish_field_tick(&state, content)
	kinds: bit_set[Field_Water_Event_Kind]
	poured_at := false
	for event in state.field.world.water_events {
		kinds += {event.kind}
		poured_at = poured_at || (event.kind == .Impact && event.sample == pour.centre)
	}
	testing.expect(t, field_world_get_sample(&state.field.world, wall).density <= 0, "the wall was dug")
	testing.expect(t, .Dig in kinds, "the dig's event is kept")
	testing.expect(t, poured_at, "the pour's splash is kept")
	testing.expect(t, .Pump in kinds, "the pump's event is kept")
	testing.expect_value(t, state.players[0].field.poured_fill, FIELD_WATER_FULL)
	for event in state.field.world.water_events {
		testing.expect(t, !(event.kind == .Stream_Mouth && event.sample == wall && event.amount == 1), "the last tick's events are dropped")
	}
}
