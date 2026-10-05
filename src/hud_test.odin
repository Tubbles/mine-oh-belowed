package game

import "core:slice"
import "core:testing"

// Glyph buttons of a hint list.
hint_buttons :: proc(hints: []Glyph_Hint) -> []Glyph_Button {
	buttons := make([]Glyph_Button, len(hints), context.temp_allocator)
	for hint, index in hints {
		buttons[index] = hint.button
	}
	return buttons
}

// Work item 0197: aimed at a trunk the glyph bar's Mine says Fell, with
// the inventory glyph and Pause; without a trunk no Fell hint. The Fell
// hint is the one the bar keeps (0219).
@(test)
test_the_fell_hint_shows_on_an_aimed_tree :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	screen_context := Screen_Context{world = &world, player = &player}
	hud := Hud_Context{field_view_set = true}
	testing.expect(t, !field_fell_hint_shown(screen_context, hud))
	hints, kept := world_glyph_hints(screen_context, hud)
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Mine))
	testing.expect_value(t, kept, 0)
	hud.field_view.tree_target = {hit = true, key = {1, 2, 3}, distance = POSITION_UNITS_PER_METRE}
	testing.expect(t, field_fell_hint_shown(screen_context, hud))
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Mine, .Inventory, .Pause}), "Fell, Inventory, Pause")
	testing.expect_value(t, hints[0].label, "Fell")
	testing.expect_value(t, kept, 1)
}

// Work item 0219: Place for every tool but the hand and a shovel, pickaxe
// or axe (0265), Turn for a machine alone, Brush for a material, the hand
// or a shovel, pickaxe or axe; outside a field session a held
// furnace adds no held hints.
@(test)
test_the_held_hints_follow_the_tool :: proc(t: ^testing.T) {
	for tool in Field_Held_Tool {
		testing.expectf(t, field_held_tool_places(tool) == (tool != .Hand && tool != .Tool), "%v places", tool)
		testing.expectf(t, field_held_tool_turns(tool) == (tool == .Machine), "%v turns", tool)
		testing.expectf(t, field_held_tool_cycles_brush(tool) == (tool == .Material || tool == .Hand || tool == .Tool), "%v cycles the brush", tool)
	}
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	items := make_test_items()
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	inventory_hotbar(player.inventory)[0] = Item_Stack{test_item(items, "stone_furnace"), 1}
	screen_context := Screen_Context{world = &world, player = &player, items = items}
	hud := Hud_Context{field_view_set = true}
	hud.field_view.tool = .Machine
	hints, kept := world_glyph_hints(screen_context, hud)
	buttons := hint_buttons(hints)
	for button in ([3]Glyph_Button{.Use_Item, .Tools, .Rotate}) {
		testing.expectf(t, !slice.contains(buttons, button), "%v outside a field session", button)
	}
	testing.expect_value(t, kept, 0)
	hud.field_session = true
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Use_Item, .Tools, .Rotate, .Inventory, .Pause}), "Place, Tools, Turn, Inventory, Pause")
	testing.expect_value(t, kept, 3)
	hud.field_view.tool = .Material
	hints, kept = world_glyph_hints(screen_context, hud)
	testing.expect_value(t, hints[2].label, "Brush")
	testing.expect_value(t, kept, 3)
}

// The tools radial (0215): a tap is Pipette and draws nothing; a steered
// release toggles the editor with a toast; the shown radial's dead centre
// selects nothing; it does not open while the editor is anchored or the
// hotbar radial is open.
@(test)
test_the_tools_radial_selects_pipette_on_a_tap_and_the_editor_on_a_steered_release :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	state: Ui_State
	defer destroy_ui_state(&state)
	editor: Placement_Editor
	frame :: proc(state: ^Ui_State, editor: ^Placement_Editor, input: Ui_Input, seconds: f32 = 1.0 / 60) {
		test_ui_frame(state, input, seconds)
		tools_radial(state, editor)
	}
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, state.tools_radial.radial.open)
	testing.expect_value(t, len(state.draw_list), 0)
	frame(&state, &editor, {tools_radial_down = true})
	frame(&state, &editor, {})
	testing.expect(t, state.tools_radial.pipette_selected)
	testing.expect(t, !editor.on)
	state.tools_radial.pipette_selected = false

	frame(&state, &editor, {tools_radial_down = true, look_delta = {0, 200}})
	testing.expect_value(t, state.tools_radial.radial.highlight, int(Tools_Radial_Entry.Placement_Editor))
	testing.expect(t, len(state.draw_list) > 0)
	frame(&state, &editor, {})
	testing.expect(t, editor.on)
	testing.expect(t, !state.tools_radial.pipette_selected)
	testing.expect_value(t, len(state.toasts), 1)

	frame(&state, &editor, {tools_radial_down = true, right_stick = {0, -1}})
	frame(&state, &editor, {})
	testing.expect(t, !editor.on)
	testing.expect(t, !state.tools_radial.pipette_selected)

	frame(&state, &editor, {tools_radial_down = true, right_stick = {0, -1}})
	testing.expect_value(t, state.tools_radial.radial.highlight, int(Tools_Radial_Entry.Placement_Editor))
	frame(&state, &editor, {tools_radial_down = true}, TOOLS_RADIAL_SHOW_SECONDS + 0.1)
	testing.expect_value(t, state.tools_radial.radial.highlight, -1)
	testing.expect(t, len(state.draw_list) > 0)
	frame(&state, &editor, {})
	testing.expect(t, !state.tools_radial.pipette_selected)
	testing.expect(t, !editor.on)

	editor.anchored = true
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, !state.tools_radial.radial.open)
	frame(&state, &editor, {})
	editor.anchored = false
	state.radial = {open = true, highlight = -1}
	frame(&state, &editor, {tools_radial_down = true})
	testing.expect(t, !state.tools_radial.radial.open)
}

// Work item 0231: the pod's hatch takes no Interact, so the glyph bar
// offers nothing on one, shut or open.
@(test)
test_the_glyph_bar_offers_nothing_on_a_hatch :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	stage_generated_field_set(state)
	pod, frame, found := find_test_pod(&state.world.entities, content.machines)
	testing.expect(t, found)
	if !found {
		return
	}
	machine := content.machines.machines[pod.machine]
	state.players[0].field = test_airlock_player(frame, machine)
	inner_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 1)
	inner := entity_at(&state.world.entities, inner_origin, frame.id)
	outer_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 0)
	outer := entity_at(&state.world.entities, outer_origin, frame.id)
	aim := proc(state: ^Simulation_State, frame: Frame_Id, handle: Entity_Handle) {
		state.players[0].field.frame_target = Frame_Raycast_Hit{hit = true, frame = frame, occupant = {handle = entity_occupant_handle(handle)}}
	}
	aimed_hints := proc(state: ^Simulation_State, content: Simulation_Content) -> []Glyph_Hint {
		screen_context := Screen_Context{content = content, world = &state.world, player = &state.players[0], tick = state.tick}
		return aimed_glyph_hints(screen_context, Hud_Context{})
	}
	aim(state, frame.id, outer)
	testing.expect(t, !hatch_is_open(&state.world.entities, outer))
	testing.expectf(t, len(aimed_hints(state, simulation_content)) == 0, "the shut outer door offers %v", aimed_hints(state, simulation_content))
	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	aim(state, frame.id, inner)
	testing.expectf(t, len(aimed_hints(state, simulation_content)) == 0, "the open inner door offers %v", aimed_hints(state, simulation_content))
}

// Work item 0233: on the gamepad Interact and Inventory share X, so on a
// power switch the bar shows Turn alone and on a full schematic crate
// Take alone; with separate controls (the keyboard's F and E) Open or
// Inventory shows beside them. A furnace shows Open on X either way.
@(test)
test_x_shows_one_hint_on_a_switch_and_a_crate :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	switch_handle := add_entity(&world.entities, content.machines, test_machine(content.machines, "power_switch"), {4, 1, 4}, 0)
	furnace := add_entity(&world.entities, content.machines, test_machine(content.machines, "steel_furnace"), {8, 1, 4}, 0)
	player := make_test_player(content.blocks, {4.5, 1, 1.5})
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = switch_handle}
	screen_context := Screen_Context{content = content, world = &world, player = &player}
	hints, _ := world_glyph_hints(screen_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Pause}), "Turn, Pause")
	testing.expect_value(t, hints[0].label, "Turn")
	hints, _ = world_glyph_hints(screen_context, {}, false)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Inventory, .Pause}), "Turn, Open, Pause")
	testing.expect_value(t, hints[1].label, "Open")
	player.target = Raycast_Hit{hit = true, block = {8, 1, 4}, entity = furnace}
	hints, _ = world_glyph_hints(screen_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Pause}), "Open, Pause")
	testing.expect_value(t, hints[0].label, "Open")

	crate_world := make_drill_world(content)
	records := make_test_records(content)
	sites := [1]Crate_Site{{region = {0, 0}, position = {4, 1, 4}, choice = 3}}
	register_crate_sites(&records.crate_sites, sites[:])
	place_pending_crates(world_tick_context(&crate_world, &records, content, TEST_TICK_RATE))
	crate := entity_at(&crate_world.entities, {4, 1, 4})
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = crate}
	crate_context := Screen_Context{content = content, world = &crate_world, player = &player}
	hints, _ = world_glyph_hints(crate_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Pause}), "Take, Pause")
	hints, _ = world_glyph_hints(crate_context, {}, false)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Inventory, .Pause}), "Take, Inventory, Pause")
	testing.expect_value(t, hints[1].label, "Inventory")
	// An empty crate takes no Interact: X opens the inventory there.
	pool_get(&crate_world.entities.schematic_crates, crate).slots[0] = EMPTY_STACK
	hints, _ = world_glyph_hints(crate_context, {}, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Inventory, .Pause}), "Inventory, Pause")
}

// Work item 0223: the chair's Interact hint is Unbuckle strapped in,
// Stand seated and Sit standing aimed at the chair, none otherwise, none
// while the world falls; strapped in, the bar shows no held hints and,
// with Interact on the Inventory's control, neither Open nor Inventory.
@(test)
test_the_chair_hints_unbuckle_stand_and_sit :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	machines := make_test_machines()
	items := make_test_items()
	place_test_pod(&world.entities, machines)
	pod, frame, _ := find_pod(&world.entities, machines)
	machine := machines.machines[pod.machine]
	corner := rotate_footprint_cell({machine.seat.cells.from.x, machine.seat.cells.from.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	chair := Frame_Raycast_Hit{hit = true, frame = frame.id, cell = pod.origin + {corner.x, 1, corner.y}, occupant = {handle = entity_occupant_handle(pod.handle)}}
	player := Player{target = {entity = NO_ENTITY}, inventory = make_inventory(HOTBAR_SLOT_COUNT, context.temp_allocator)}
	inventory_hotbar(player.inventory)[0] = Item_Stack{test_item(items, "stone_furnace"), 1}
	screen_context := Screen_Context{world = &world, player = &player, items = items, machines = machines}
	hud := Hud_Context{field_view_set = true, field_session = true}
	hud.field_view.tool = .Machine
	testing.expect_value(t, field_chair_hint_key(screen_context, hud), "")
	hud.field_view.frame_target = chair
	testing.expect_value(t, field_chair_hint_key(screen_context, hud), "hint_sit")
	hud.field_view.frame_target = {}
	hud.field_view.seat = .Seated
	testing.expect_value(t, field_chair_hint_key(screen_context, hud), "hint_stand")
	hud.field_view.seat = .Strapped
	testing.expect_value(t, field_chair_hint_key(screen_context, hud), "hint_unbuckle")
	hints, kept := world_glyph_hints(screen_context, hud, true)
	testing.expect(t, slice.equal(hint_buttons(hints), []Glyph_Button{.Interact, .Pause}), "Unbuckle, Pause")
	testing.expect_value(t, hints[0].label, "Unbuckle")
	testing.expect_value(t, kept, 1)
	falling := screen_context
	falling.arrival_falling = true
	testing.expect_value(t, field_chair_hint_key(falling, hud), "")
	hints, _ = world_glyph_hints(falling, hud)
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Interact), "no Interact while falling")
	testing.expect(t, !slice.contains(hint_buttons(hints), Glyph_Button.Use_Item), "no held hints strapped in")
	hud.field_session = false
	testing.expect_value(t, field_chair_hint_key(screen_context, hud), "")
}
