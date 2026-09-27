package game

// The world HUD, drawn through the UI draw list under any open screen:
// crosshair, hotbar with the held item's name, the hotbar radial and the
// glyph bar. The targeted block name comes later.

CROSSHAIR_SIZE :: 18.0
CROSSHAIR_THICKNESS :: 3.0
CROSSHAIR_COLOR :: Ui_Color{255, 255, 255, 200}
HUD_SELECTED_SLOT_SCALE :: 1.25
HUD_SLOT_COLOR :: Ui_Color{24, 26, 34, 180}
// Distance of the radial's slot centres from the screen centre.
HUD_RADIAL_RADIUS :: UI_SLOT_SIZE * 2.5

draw_crosshair :: proc(state: ^Ui_State) {
	centre := state.screen_units / 2
	draw_fill(state, {centre.x - CROSSHAIR_SIZE, centre.y - CROSSHAIR_THICKNESS / 2, 2 * CROSSHAIR_SIZE, CROSSHAIR_THICKNESS}, CROSSHAIR_COLOR)
	draw_fill(state, {centre.x - CROSSHAIR_THICKNESS / 2, centre.y - CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, 2 * CROSSHAIR_SIZE}, CROSSHAIR_COLOR)
}

hud_slot_size :: proc(index, selected: int) -> f32 {
	return index == selected ? UI_SLOT_SIZE * HUD_SELECTED_SLOT_SCALE : UI_SLOT_SIZE
}

// Slots bottom centre on a common baseline, the selected one enlarged.
hud_hotbar_rectangles :: proc(area: Ui_Rectangle, selected: int) -> [HOTBAR_SLOT_COUNT]Ui_Rectangle {
	width := f32(HOTBAR_SLOT_COUNT - 1) * (UI_SLOT_SIZE + UI_GAP) + UI_SLOT_SIZE * HUD_SELECTED_SLOT_SCALE
	x := area.x + (area.width - width) / 2
	bottom := area.y + area.height
	rectangles: [HOTBAR_SLOT_COUNT]Ui_Rectangle
	for index in 0 ..< HOTBAR_SLOT_COUNT {
		size := hud_slot_size(index, selected)
		rectangles[index] = {x, bottom - size, size, size}
		x += size + UI_GAP
	}
	return rectangles
}

draw_hud_hotbar :: proc(state: ^Ui_State, player: Player, items: Item_Registry) {
	hotbar := inventory_hotbar(player.inventory)
	rectangles := hud_hotbar_rectangles(ui_safe_area(state), player.selected_hotbar_slot)
	for stack, index in hotbar {
		draw_fill(state, rectangles[index], HUD_SLOT_COLOR)
		selected := index == player.selected_hotbar_slot
		draw_outline(state, rectangles[index], selected ? UI_ACCENT_COLOR : UI_PANEL_BORDER_COLOR, selected ? UI_FOCUS_BORDER : UI_BORDER)
		draw_item_stack(state, rectangles[index], stack, items)
	}
	held := selected_hotbar_stack(player)
	if stack_is_empty(held) {
		return
	}
	selected_rectangle := rectangles[player.selected_hotbar_slot]
	name_area := Ui_Rectangle{0, selected_rectangle.y - UI_GAP - UI_ROW_HEIGHT, state.screen_units.x, UI_ROW_HEIGHT}
	draw_text(state, name_area, item_name(items, held.item), UI_BODY_TEXT_SIZE, .Centre)
}

hotbar_radial_source :: proc(input: Ui_Input) -> Radial_Source {
	return input.left_touchpad.down ? .Touchpad : .Held_Button
}

// The left pad (or Tab and the right stick) shows the hotbar as a wheel
// around the screen centre, slot 0 at the top, clockwise. Release selects.
hotbar_radial :: proc(state: ^Ui_State, player: ^Player, items: Item_Registry) {
	source := hotbar_radial_source(state.input)
	touching, position := radial_input(state.input, source)
	result: Radial_Result
	state.radial, result = advance_radial(state.radial, touching, position, source, HOTBAR_SLOT_COUNT)
	if result.closed && result.selected >= 0 {
		player.selected_hotbar_slot = result.selected
	}
	if state.radial.open {
		draw_hotbar_radial(state, inventory_hotbar(player.inventory), items)
	}
}

draw_hotbar_radial :: proc(state: ^Ui_State, hotbar: []Item_Stack, items: Item_Registry) {
	centre := state.screen_units / 2
	for stack, index in hotbar {
		point := radial_slot_offset(index, len(hotbar)) * HUD_RADIAL_RADIUS + centre
		highlighted := index == state.radial.highlight
		size := hud_slot_size(index, state.radial.highlight)
		box := Ui_Rectangle{point.x - size / 2, point.y - size / 2, size, size}
		draw_fill(state, box, UI_PANEL_COLOR)
		draw_outline(state, box, highlighted ? UI_ACCENT_COLOR : UI_PANEL_BORDER_COLOR, highlighted ? UI_FOCUS_BORDER : UI_BORDER)
		draw_item_stack(state, box, stack, items)
	}
	highlight := state.radial.highlight
	if highlight >= 0 && highlight < len(hotbar) && !stack_is_empty(hotbar[highlight]) {
		name_area := Ui_Rectangle{centre.x - HUD_RADIAL_RADIUS, centre.y - UI_ROW_HEIGHT / 2, 2 * HUD_RADIAL_RADIUS, UI_ROW_HEIGHT}
		draw_text(state, name_area, item_name(items, hotbar[highlight].item), UI_BODY_TEXT_SIZE, .Centre)
	}
}

draw_hud :: proc(state: ^Ui_State, player: ^Player, items: Item_Registry) {
	draw_crosshair(state)
	draw_hud_hotbar(state, player^, items)
	if state.screens.count > 0 {
		state.radial = {}
		return
	}
	hotbar_radial(state, player, items)
	hints := [?]Glyph_Hint{{.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
	ui_glyph_bar(state, hints[:])
}
