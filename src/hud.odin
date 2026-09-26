package game

// The world HUD, drawn through the UI draw list under any open screen.
// The hotbar and the targeted block name come with work item 0010.

CROSSHAIR_SIZE :: 18.0
CROSSHAIR_THICKNESS :: 3.0
CROSSHAIR_COLOR :: Ui_Color{255, 255, 255, 200}

draw_crosshair :: proc(state: ^Ui_State) {
	centre := state.screen_units / 2
	draw_fill(state, {centre.x - CROSSHAIR_SIZE, centre.y - CROSSHAIR_THICKNESS / 2, 2 * CROSSHAIR_SIZE, CROSSHAIR_THICKNESS}, CROSSHAIR_COLOR)
	draw_fill(state, {centre.x - CROSSHAIR_THICKNESS / 2, centre.y - CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, 2 * CROSSHAIR_SIZE}, CROSSHAIR_COLOR)
}

draw_hud :: proc(state: ^Ui_State) {
	draw_crosshair(state)
	if state.screens.count == 0 {
		hints := [?]Glyph_Hint{{.Pause, text("hint_pause")}}
		ui_glyph_bar(state, hints[:])
	}
}
