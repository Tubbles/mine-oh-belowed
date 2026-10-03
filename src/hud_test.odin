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
