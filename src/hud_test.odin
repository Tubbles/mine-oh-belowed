package game

import "core:testing"

// Work item 0197: aimed at a trunk the glyph bar's Mine says Fell, with
// the inventory glyph and Pause; without a trunk no Fell hint.
@(test)
test_the_fell_hint_shows_on_an_aimed_tree :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	world: World
	defer destroy_world(&world)
	player := Player{target = {entity = NO_ENTITY}}
	screen_context := Screen_Context{world = &world, player = &player}
	hud := Hud_Context{field_view_set = true}
	testing.expect(t, !field_fell_hint_shown(screen_context, hud))
	hud.field_view.tree_target = {hit = true, key = {1, 2, 3}, distance = POSITION_UNITS_PER_METRE}
	testing.expect(t, field_fell_hint_shown(screen_context, hud))
	hints := field_fell_hints(screen_context, hud)
	testing.expect_value(t, hints[0].button, Glyph_Button.Mine)
	testing.expect_value(t, hints[0].label, "Fell")
	testing.expect_value(t, hints[1].button, Glyph_Button.Inventory)
	testing.expect_value(t, hints[2].button, Glyph_Button.Pause)
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
