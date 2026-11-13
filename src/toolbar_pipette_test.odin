package game

import "core:testing"

// The pipette (0216): the selected slot when it names the kind, else the
// lowest naming it; with none the kind is named on the selected slot and
// no stack moves, an empty inventory all the same; NO_ITEM changes
// nothing; only the active toolbar is searched.
@(test)
test_the_pipette_selects_the_named_slot_or_names_the_selected_one :: proc(t: ^testing.T) {
	items := make_test_items()
	player := make_player({}, context.temp_allocator)
	dirt, furnace, chest := test_item(items, "dirt"), test_item(items, "steel_furnace"), test_item(items, "wooden_chest")
	player.toolbars[0][0] = dirt
	player.toolbars[0][1] = furnace
	player.toolbars[0][5] = furnace
	player.toolbars[1][0] = chest
	before := player.toolbars
	player.selected_hotbar_slot = 3
	apply_pipette(&player, furnace)
	testing.expect_value(t, player.selected_hotbar_slot, 1)
	testing.expect(t, player.toolbars == before, "a selection names nothing")
	player.selected_hotbar_slot = 5
	apply_pipette(&player, furnace)
	testing.expect_value(t, player.selected_hotbar_slot, 5)
	// Named on another toolbar only: named on the selected slot.
	player.selected_hotbar_slot = 2
	apply_pipette(&player, chest)
	testing.expect_value(t, player.toolbars[0][2], chest)
	testing.expect_value(t, player.selected_hotbar_slot, 2)
	testing.expect(t, player.toolbars[1] == before[1], "the other toolbar unchanged")
	for slot, index in player.inventory.slots {
		testing.expectf(t, stack_is_empty(slot), "inventory slot %d stays empty", index)
	}
	testing.expect_value(t, selected_stack_index(player), -1)
	inventory_add(player.inventory, items, chest, 3)
	chest_slot := -1
	for slot, index in player.inventory.slots {
		if slot.item == chest && !stack_is_empty(slot) {
			chest_slot = index
		}
	}
	testing.expect(t, chest_slot >= 0)
	testing.expect_value(t, selected_stack_index(player), chest_slot)
	named, selected := player.toolbars, player.selected_hotbar_slot
	apply_pipette(&player, NO_ITEM)
	testing.expect(t, player.toolbars == named, "NO_ITEM names nothing")
	testing.expect_value(t, player.selected_hotbar_slot, selected)
	player.active_toolbar = 1
	player.selected_hotbar_slot = 4
	apply_pipette(&player, chest)
	testing.expect_value(t, player.selected_hotbar_slot, 0)
}

// The aimed kind: the block target's or the frame cell's machine's item,
// the frame cell before the block target, an aimed cable's before both;
// nothing for the pod, a crate, nothing aimed and a removed entity.
@(test)
test_the_pipette_reads_the_aimed_things_item :: proc(t: ^testing.T) {
	content := make_test_content()
	machines := content.machines
	// The test world lives in the temp allocator, the pod's rooms do not.
	world := make_floor_world(content.blocks, 32)
	entities := &world.entities
	defer destroy_sealed_rooms(entities)
	machine_item :: proc(machines: Machine_Registry, id: string) -> Item_Id {
		return machines.machines[test_machine(machines, id)].item
	}
	frame_hit :: proc(handle: Entity_Handle) -> Frame_Raycast_Hit {
		return Frame_Raycast_Hit{hit = true, occupant = {handle = entity_occupant_handle(handle)}}
	}
	furnace := add_entity(entities, machines, test_machine(machines, "steel_furnace"), {4, 1, 4}, 0)
	belt := add_entity(entities, machines, test_machine(machines, "belt"), {6, 1, 4}, 0)
	pole := add_entity(entities, machines, test_machine(machines, "belt_pole"), {8, 1, 4}, 0)
	foundation := add_entity(entities, machines, test_foundation(machines), {10, 1, 4}, 0)
	crate := add_entity(entities, machines, test_machine(machines, "schematic_crate"), {12, 1, 4}, 0)
	place_test_pod(entities, machines)
	pod, _, found := find_pod(entities, machines)
	testing.expect(t, found)
	testing.expect(t, machine_item(machines, "steel_furnace") != NO_ITEM)

	testing.expect_value(t, pipette_aimed_item(entities, machines, furnace, {}, -1), machine_item(machines, "steel_furnace"))
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, {}, -1), NO_ITEM)
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(belt), -1), machine_item(machines, "belt"))
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(pole), -1), machine_item(machines, "belt_pole"))
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(foundation), -1), machines.machines[test_foundation(machines)].item)
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(pod.handle), -1), NO_ITEM)
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(crate), -1), NO_ITEM)
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, Frame_Raycast_Hit{}, -1), NO_ITEM)
	// The frame cell before the block target.
	testing.expect_value(t, pipette_aimed_item(entities, machines, furnace, frame_hit(belt), -1), machine_item(machines, "belt"))
	// An aimed cable before the frame cell; an index past the table is none.
	light := test_item(content.items, "light_cable")
	append(&entities.cables.cables, Cable{item = light})
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(belt), 0), light)
	testing.expect_value(t, pipette_aimed_item(entities, machines, NO_ENTITY, frame_hit(belt), 1), machine_item(machines, "belt"))
	testing.expect(t, remove_entity(entities, machines, furnace))
	testing.expect_value(t, pipette_aimed_item(entities, machines, furnace, {}, -1), NO_ITEM)
}

// A Pipette press in the field tick: aimed at a chest no slot names, the
// selected slot names it and the hand holds nothing; again from another
// slot, the slot naming it is selected; an aimed cable selects its slot;
// the pad cell names its foundation; nothing aimed, a cable run and a
// seat change nothing.
@(test)
test_a_pipette_press_on_the_field_selects_or_names_the_aimed_kind :: proc(t: ^testing.T) {
	simulation, content, items := make_pick_up_test()
	defer destroy_simulation(&simulation)
	entities := &simulation.world.entities
	frame := lay_cable_test_pad(&simulation, content)
	place_on_test_pad(&simulation, content, frame, "power_switch", {2, 1, 0})
	south := place_on_test_pad(&simulation, content, frame, "junction_box", {3, 1, -2})
	north := place_on_test_pad(&simulation, content, frame, "junction_box", {3, 1, 2})
	lay_test_cable(&simulation.world, content, "light_cable", {south, 3}, {north, 2})
	chest_handle := place_on_test_pad(&simulation, content, frame, "wooden_chest", {8, 1, 0})
	stand_test_player_on_cell(&simulation, content, items, frame, {6, 0, 0}, {"light_cable", 100})
	player := &simulation.players[0]
	light, chest := test_item(items, "light_cable"), test_item(items, "wooden_chest")
	testing.expect_value(t, player.toolbars[0][0], light)
	testing.expect_value(t, player.selected_hotbar_slot, 0)
	press :: proc(simulation: ^Simulation_State, content: Simulation_Content, frame: Input_Frame) {
		simulation.tick += 1
		tick_field_session_player(simulation, content, 0, frame)
		finish_field_tick(simulation, content)
	}
	aim :: proc(simulation: ^Simulation_State, content: Simulation_Content, point: World_Position) {
		look_test_player_at(simulation, content, point)
		tick_field_simulation(simulation, content, {})
	}
	pipette := Input_Frame {
		just_pressed = {.Pipette},
	}
	chest_face := frame_face_centre(frame, {8, 1, 0}, .Negative_X)

	aim(&simulation, content, chest_face)
	testing.expect(t, player.field.frame_target.hit && entity_from_occupant(player.field.frame_target.occupant.handle) == chest_handle, "the reticle meets the chest")
	player.selected_hotbar_slot = 2
	press(&simulation, content, pipette)
	testing.expect_value(t, player.toolbars[0][2], chest)
	testing.expect_value(t, player.selected_hotbar_slot, 2)
	testing.expect_value(t, player.toolbars[0][0], light)
	testing.expect_value(t, inventory_count(player.inventory, chest), 0)
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Hand)

	player.selected_hotbar_slot = 5
	before := player.toolbars
	press(&simulation, content, pipette)
	testing.expect_value(t, player.selected_hotbar_slot, 2)
	testing.expect(t, player.toolbars == before, "a selection names nothing")

	// The switch's +x face 150 mm under its centre: the look passes the
	// cable a cell before it.
	below := World_Position(fixed_scale(frame.axes[FRAME_UP], -millimetres_to_position_units(150)))
	switch_point := frame_face_centre(frame, {2, 1, 0}, .Positive_X) + below
	aim(&simulation, content, switch_point)
	testing.expect_value(t, field_aimed_cable(entities, content.machines, player.field, content.field.tuning), 0)
	press(&simulation, content, pipette)
	testing.expect_value(t, player.selected_hotbar_slot, 0)
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Cable)

	player.field.pitch = -FIELD_PITCH_LIMIT
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, player.field.frame_target.hit && player.field.frame_target.cell == World_Coordinate{6, 0, 0}, "the reticle meets the pad cell")
	player.selected_hotbar_slot = 3
	press(&simulation, content, pipette)
	testing.expect_value(t, player.toolbars[0][3], content.machines.machines[test_foundation(content.machines)].item)

	player.field.pitch = FIELD_PITCH_LIMIT
	tick_field_simulation(&simulation, content, {})
	testing.expect(t, !player.field.frame_target.hit, "nothing aimed")
	before = player.toolbars
	selected := player.selected_hotbar_slot
	press(&simulation, content, pipette)
	testing.expect(t, player.toolbars == before, "nothing aimed names nothing")
	testing.expect_value(t, player.selected_hotbar_slot, selected)

	// A cable run holds the hand.
	player.selected_hotbar_slot = 0
	press(&simulation, content, {})
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Cable)
	begin_test_run(&simulation, content, frame, {3, 1, 2})
	testing.expect(t, player.field.cable_run, "Place on the box begins a run")
	aim(&simulation, content, chest_face)
	before = player.toolbars
	press(&simulation, content, pipette)
	testing.expect(t, player.toolbars == before, "the run's pipette names nothing")
	testing.expect_value(t, player.selected_hotbar_slot, 0)
	testing.expect(t, player.field.cable_run, "the run carried")

	for seat in ([2]Field_Seat{.Seated, .Strapped}) {
		testing.expectf(t, .Pipette not_in seated_field_frame(pipette, seat).just_pressed, "%v carries no Pipette", seat)
	}
}

// Only a tap of the tools control or the radial's Pipette entry reaches
// the block world's tick as Pipette: a hold released in the dead centre
// and a release on the editor's entry select nothing.
@(test)
test_only_a_tap_of_the_tools_control_pipettes :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {4, 1, 4}, 0)
	players := []Player{make_test_player(content.blocks, {4.5, 1, 1.5})}
	players[0].pitch, players[0].yaw = -30, 90
	tick_player(&world, &records, content, players, 0, {}, TEST_TICK_RATE, 0)
	testing.expect_value(t, players[0].target.entity, handle)
	players[0].toolbars[0][3] = content.machines.machines[test_machine(content.machines, "steel_furnace")].item
	players[0].selected_hotbar_slot = 0
	state: Ui_State
	defer destroy_ui_state(&state)
	Step :: struct {
		down:       bool,
		first:      bool,
		look_delta: [2]f32,
		seconds:    f32,
	}
	step :: proc(state: ^Ui_State, world: ^World, records: ^Game_Records, content: Simulation_Content, players: []Player, entry: Step) -> int {
		test_ui_frame(state, {tools_radial_down = entry.down, look_delta = entry.look_delta}, entry.seconds > 0 ? entry.seconds : 1.0 / 60)
		tools_radial(state, nil)
		raw: Input_Frame
		if entry.down {
			raw.pressed += {.Pipette}
		}
		if entry.first {
			raw.just_pressed += {.Pipette}
		}
		tick_player(world, records, content, players, 0, tools_radial_world_frame(raw, state.tools_radial), TEST_TICK_RATE, 0)
		state.tools_radial.pipette_selected = false
		return players[0].selected_hotbar_slot
	}
	// Held past the show and released in the dead centre.
	testing.expect_value(t, step(&state, &world, &records, content, players, {down = true, first = true}), 0)
	testing.expect_value(t, step(&state, &world, &records, content, players, {down = true, seconds = TOOLS_RADIAL_SHOW_SECONDS + 0.1}), 0)
	testing.expect_value(t, step(&state, &world, &records, content, players, {}), 0)
	// Released on the editor's entry, with no editor.
	testing.expect_value(t, step(&state, &world, &records, content, players, {down = true, first = true, look_delta = {0, 200}}), 0)
	testing.expect_value(t, step(&state, &world, &records, content, players, {}), 0)
	// Released on the Pipette entry.
	testing.expect_value(t, step(&state, &world, &records, content, players, {down = true, first = true, look_delta = {0, -200}}), 0)
	testing.expect_value(t, step(&state, &world, &records, content, players, {}), 3)
	// A tap.
	players[0].selected_hotbar_slot = 0
	testing.expect_value(t, step(&state, &world, &records, content, players, {down = true, first = true}), 0)
	testing.expect_value(t, step(&state, &world, &records, content, players, {}), 3)
}
