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

// Work item 0219: Place for every tool but the hand, Turn for a machine
// alone, Brush for a material or the hand; outside a field session a held
// furnace adds no held hints.
@(test)
test_the_held_hints_follow_the_tool :: proc(t: ^testing.T) {
	for tool in Field_Held_Tool {
		testing.expectf(t, field_held_tool_places(tool) == (tool != .Hand), "%v places", tool)
		testing.expectf(t, field_held_tool_turns(tool) == (tool == .Machine), "%v turns", tool)
		testing.expectf(t, field_held_tool_cycles_brush(tool) == (tool == .Material || tool == .Hand), "%v cycles the brush", tool)
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

// Work item 0222: aimed at the closed outer door from the middle of the
// bore while the inner one is open, the glyph bar offers no Open (the
// interlock would refuse the press); the open inner door still says
// Close; once the inner door is closed and has finished its slide the
// outer one says Open again.
@(test)
test_the_open_hint_hides_while_the_airlock_refuses :: proc(t: ^testing.T) {
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
	interact_hint := proc(state: ^Simulation_State, content: Simulation_Content) -> (label: string, shown: bool) {
		screen_context := Screen_Context{content = content, world = &state.world, player = &state.players[0], tick = state.tick}
		for hint in aimed_glyph_hints(screen_context, Hud_Context{}) {
			if hint.button == .Interact {
				return hint.label, true
			}
		}
		return "", false
	}
	sneak := Input_Frame{pressed = {.Sneak}}
	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	tick_field_test_simulation(state, simulation_content, sneak)
	aim(state, frame.id, outer)
	_, shown := interact_hint(state, simulation_content)
	testing.expect(t, !shown, "Open offered on the outer door while the inner one is open")
	aim(state, frame.id, inner)
	label, _ := interact_hint(state, simulation_content)
	testing.expect_value(t, label, "Close")

	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	aim(state, frame.id, outer)
	_, shown = interact_hint(state, simulation_content)
	testing.expect(t, !shown, "Open offered while the inner door still slides closed")
	for _ in 0 ..< simulation_content.field.pod_airlock.door_travel_ticks {
		tick_field_test_simulation(state, simulation_content, sneak)
	}
	testing.expect(t, !hatch_is_open(&state.world.entities, outer), "the outer door opened on its own")
	aim(state, frame.id, outer)
	label, shown = interact_hint(state, simulation_content)
	testing.expect(t, shown, "no Open once the inner door has settled closed")
	testing.expect_value(t, label, "Open")
}
