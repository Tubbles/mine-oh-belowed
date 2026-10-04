package game

import "core:testing"

// A research the check refuses toasts and never queues; an accepted one
// queues, changes nothing in the frame and applies at the next tick.
@(test)
test_a_refused_action_never_queues_and_an_accepted_one_applies_at_the_next_tick :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	research := &audit.simulation.records.research
	research.queued = false
	locked, available := NO_TECHNOLOGY, NO_TECHNOLOGY
	for _, index in audit.content.technologies.technologies {
		switch technology_status(audit.content.technologies, audit.simulation.unlocks, index) {
		case .Available:
			available = available == NO_TECHNOLOGY ? index : available
		case .Locked:
			locked = locked == NO_TECHNOLOGY ? index : locked
		case .Researched:
		}
	}
	if !testing.expect(t, locked != NO_TECHNOLOGY && available != NO_TECHNOLOGY) {
		return
	}
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	screen_context := audit_screen_context(audit)
	queue_focused_research(&state, screen_context, locked)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, len(state.toasts), 1)
	queue_focused_research(&state, screen_context, available)
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	testing.expect(t, !research.queued)
	run_audit_tick(audit)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect(t, research.queued)
	testing.expect_value(t, research.technology, available)
}

// The commands apply in order for their player; one for a player the
// simulation lacks is dropped.
@(test)
test_player_commands_apply_in_order_for_their_player :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	queue_player_command(&simulation.player_commands, 0, Hotbar_Slot_Command{slot = 3})
	queue_player_command(&simulation.player_commands, 0, Hotbar_Slot_Command{slot = 5})
	queue_player_command(&simulation.player_commands, 4, Hotbar_Slot_Command{slot = 1})
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 5)
	testing.expect_value(t, len(simulation.player_commands), 0)
	queue_player_command(&simulation.player_commands, 1, Add_Player_Command{start = player_start_on({4, 10, 4})})
	queue_player_command(&simulation.player_commands, 1, Hotbar_Slot_Command{slot = 2})
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, len(simulation.players), 2)
	testing.expect_value(t, simulation.players[1].selected_hotbar_slot, 2)
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 5)
}

// The radial's release queues the slot; the HUD writes no player field.
@(test)
test_the_hotbar_slot_command_selects_at_the_next_tick :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {left_touchpad = {down = true, position = {0.95, 0.5}}})
	hotbar_radial(&state, &simulation.players[0], 0, &simulation.player_commands, content.items)
	test_ui_frame(&state, {left_touchpad = {down = false, position = {0.95, 0.5}}})
	hotbar_radial(&state, &simulation.players[0], 0, &simulation.player_commands, content.items)
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 0)
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 2)
}

// A finger's tap on the label a frame drew, after a frame without a
// touch (a tap right after another one would be a double tap).
tap_labelled_widget :: proc(audit: ^Ui_Audit, state: ^Ui_State, label: string) -> bool {
	screen_test_frame(audit, state, {pointer_is_touch = true})
	for command in state.draw_list {
		if command.kind == .Text && command.text == label {
			at := rectangle_centre(command.rectangle)
			screen_test_frame(audit, state, touch_input(at, true, pressed = true))
			screen_test_frame(audit, state, touch_input(at, false, moved = false))
			return true
		}
	}
	return false
}

// The machine panel of handle open and drawn once.
open_test_panel :: proc(audit: ^Ui_Audit, state: ^Ui_State, handle: Entity_Handle) {
	audit.simulation.players[0].open_machine = handle
	push_screen(&state.screens, .Machine)
	screen_test_frame(audit, state, {pointer_is_touch = true})
}

// Frame, then tick: a panel press changes nothing in its frame and lands
// at the next tick, for the power switch, the launch pad's Assemble and
// Launch, the catalogue order and the splitter's priority and side.
@(test)
test_panel_presses_land_at_the_next_tick :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	entities := &simulation.world.entities

	power := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&power)
	switch_handle := entity_at(entities, {12, 1, 6})
	on := pool_get(&entities.poles, switch_handle).on
	open_test_panel(audit, &power, switch_handle)
	testing.expect(t, tap_labelled_widget(audit, &power, text("power_switch_state")))
	testing.expect_value(t, pool_get(&entities.poles, switch_handle).on, on)
	run_audit_tick(audit)
	testing.expect_value(t, pool_get(&entities.poles, switch_handle).on, !on)

	// An empty pad: Assemble and Launch are both refused for the missing
	// parts, which the tick counts.
	pad_state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&pad_state)
	pad_handle := place_test_entity(&simulation.world, audit.content, "launch_pad", {-28, 1, 14})
	pad := pool_get(&entities.launch_pads, pad_handle)
	open_test_panel(audit, &pad_state, pad_handle)
	missing := simulation.records.statistics.launch_parts_missing
	testing.expect(t, tap_labelled_widget(audit, &pad_state, text("launch_pad_assemble")))
	testing.expect(t, tap_labelled_widget(audit, &pad_state, text("launch_pad_launch")))
	testing.expect_value(t, simulation.records.statistics.launch_parts_missing, missing)
	run_audit_tick(audit)
	testing.expect_value(t, simulation.records.statistics.launch_parts_missing, missing + 2)
	testing.expect_value(t, pad.state, Launch_Pad_State.Waiting_For_Parts)
	testing.expect_value(t, len(simulation.player_commands), 0)

	open_test_panel(audit, &pad_state, entity_at(entities, SAVE_TEST_LAUNCH_PAD))
	testing.expect(t, tap_labelled_widget(audit, &pad_state, text("launch_pad_tab_catalogue")))
	screen_test_frame(audit, &pad_state, {pointer_is_touch = true})
	simulation.records.venture_credit = 1_000_000
	orders := len(simulation.records.catalogue_orders)
	testing.expect(t, tap_labelled_widget(audit, &pad_state, catalogue_entry_label(audit.content.contracts.catalogue[0], audit.content.items)))
	testing.expect_value(t, len(simulation.records.catalogue_orders), orders)
	run_audit_tick(audit)
	testing.expect(t, len(simulation.records.catalogue_orders) > orders || simulation.records.venture_credit < 1_000_000)

	splitter_state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&splitter_state)
	splitter_handle := NO_ENTITY
	for &splitter in entities.splitters.entries {
		if splitter.alive {
			splitter_handle = splitter.handle
			break
		}
	}
	if !testing.expect(t, splitter_handle != NO_ENTITY) {
		return
	}
	splitter := pool_get(&entities.splitters, splitter_handle)
	output, side := splitter.output_priority, splitter.filter_side
	open_test_panel(audit, &splitter_state, splitter_handle)
	testing.expect(t, tap_labelled_widget(audit, &splitter_state, text("splitter_output_priority")))
	testing.expect(t, tap_labelled_widget(audit, &splitter_state, text("splitter_filter_side")))
	testing.expect_value(t, splitter.output_priority, output)
	testing.expect_value(t, splitter.filter_side, side)
	run_audit_tick(audit)
	testing.expect(t, splitter.output_priority != output)
	testing.expect(t, splitter.filter_side != side)
}

// A closed machine panel forgets its machine through a command: the frame
// queues it once, the tick clears open_machine.
@(test)
test_a_closed_panel_clears_the_open_machine_at_the_next_tick :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	handle := entity_at(&audit.simulation.world.entities, {12, 1, 6})
	open_test_panel(audit, &state, handle)
	state.screens = {}
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, audit.simulation.players[0].open_machine, handle)
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	run_audit_tick(audit)
	testing.expect_value(t, audit.simulation.players[0].open_machine, NO_ENTITY)
}

// A toggle taken from the frame's queue into the driver's (held or in a
// record not run) still shows as pending, so a second press undoes it.
@(test)
test_a_toggle_held_by_the_driver_is_still_pending :: proc(t: ^testing.T) {
	toggle := Developer_Request{action = .Toggle_Fly_Mode}
	held := [?]Player_Command{toggle}
	testing.expect(t, pending_toggle(false, nil, held[:], 0, .Toggle_Fly_Mode))
	queued := [?]Queued_Player_Command{{player = 0, command = toggle}}
	testing.expect(t, !pending_toggle(false, queued[:], held[:], 0, .Toggle_Fly_Mode))
	testing.expect(t, close_machine_pending(nil, []Player_Command{Close_Machine_Command{}}, 0))
	testing.expect(t, !close_machine_pending(nil, held[:], 0))
}

// A command naming an index this build's content lacks is refused at the
// tick, not applied.
@(test)
test_a_command_with_an_unknown_index_is_refused :: proc(t: ^testing.T) {
	simulation, content := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	testing.expect(t, !player_command_valid(Research_Command{technology = len(content.technologies.technologies)}, content))
	testing.expect(t, !player_command_valid(Craft_Command{recipe = -2, count = 1}, content))
	testing.expect(t, !player_command_valid(Craft_Command{recipe = 0, count = MAXIMUM_CRAFT_COMMAND_COUNT + 1}, content))
	testing.expect(t, !player_command_valid(Catalogue_Order_Command{entry = 1_000_000}, content))
	testing.expect(t, !player_command_valid(Machine_Filter_Command{filter = Item_Id(len(content.items.items))}, content))
	testing.expect(t, !player_command_valid(Splitter_Side_Command{side = Splitter_Side(200)}, content))
	testing.expect(t, !player_command_valid(Developer_Request{action = .Give_Item, grant = {item = Item_Id(60_000), count = 1}}, content))
	testing.expect(t, !player_command_valid(Developer_Request{action = Developer_Action(250)}, content))
	testing.expect(t, player_command_valid(Research_Command{technology = 0}, content))
	testing.expect(t, player_command_valid(Developer_Request{action = .Toggle_Fly_Mode}, content))
	events := len(simulation.events)
	queue_player_command(&simulation.player_commands, 0, Hotbar_Slot_Command{slot = 4})
	queue_player_command(&simulation.player_commands, 0, Research_Command{technology = len(content.technologies.technologies)})
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, simulation.players[0].selected_hotbar_slot, 4)
	testing.expect(t, len(simulation.events) > events)
}

// The placement editor's commit (0215) survives the wire, is refused for
// an index, a rotation, a normal or a run the build cannot take, and is
// refused in a block world.
@(test)
test_a_machine_placement_command_round_trips_and_is_validated :: proc(t: ^testing.T) {
	content := Simulation_Content{machines = make_test_machines()}
	furnace := test_machine(content.machines, "stone_furnace")
	command := Machine_Placement_Command{machine = furnace, rotation = 3, new_frame = true, frame = Frame_Id(7), cell = {-4, 0, -4}, normal = {0, 1, 0}, hit = {1, 2, 3}, heading = {UNIT_VECTOR_ONE, 0, 0}}
	bytes := make([dynamic]byte, context.temp_allocator)
	encode_player_command(&bytes, command)
	reader := Byte_Reader{data = bytes[:]}
	decoded, ok := decode_player_command(&reader)
	testing.expect(t, ok)
	testing.expect_value(t, decoded.(Machine_Placement_Command), command)
	testing.expect(t, player_command_valid(command, content))
	past := command
	past.machine = Machine_Id(len(content.machines.machines))
	testing.expect(t, !player_command_valid(past, content))
	turned := command
	turned.rotation = 4
	testing.expect(t, !player_command_valid(turned, content))
	slanted := command
	slanted.normal = {1, 1, 0}
	testing.expect(t, !player_command_valid(slanted, content))
	belt := command
	belt.machine = find_machine_of_kind(content.machines, .Belt)
	testing.expect(t, !player_command_valid(belt, content))
	state: Simulation_State
	defer destroy_simulation(&state)
	append(&state.players, make_player(Player_Start{}))
	apply_player_command(&state, content, {player = 0, command = command})
	testing.expect_value(t, len(state.events), 1)
	testing.expect_value(t, state.events[0].kind, Player_Event.Action_Refused)
}
