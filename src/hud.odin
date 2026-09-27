package game

// The world HUD, drawn through the UI draw list under any open screen:
// crosshair, the targeted entity's name and state (and the vein of a
// targeted drill or outcrop block), hotbar with the held
// item's name, the hotbar radial, the active quest objective (top right,
// ui_journal.odin), the brownout warning (top centre, ui_power.odin) and
// the glyph bar. Targeted block names come later.

CROSSHAIR_SIZE :: 18.0
CROSSHAIR_THICKNESS :: 3.0
CROSSHAIR_COLOR :: Ui_Color{255, 255, 255, 200}
HUD_SELECTED_SLOT_SCALE :: 1.25
HUD_SLOT_COLOR :: Ui_Color{24, 26, 34, 180}
HUD_QUEUE_SLOT_SIZE :: 56
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

// Left of the hotbar, newest entry nearest to it: the recipe's first
// output per entry, a progress bar under the one in progress, and why it
// waits when its outputs do not fit.
draw_craft_queue :: proc(state: ^Ui_State, player: Player, screen_context: Screen_Context) {
	queue := player.crafting
	if queue.count == 0 {
		return
	}
	hotbar := hud_hotbar_rectangles(ui_safe_area(state), player.selected_hotbar_slot)
	bottom := hotbar[0].y + hotbar[0].height
	right := hotbar[0].x - 3 * UI_GAP
	first: Ui_Rectangle
	for index in 0 ..< queue.count {
		x := right - f32(queue.count - index) * (HUD_QUEUE_SLOT_SIZE + UI_GAP)
		box := Ui_Rectangle{x, bottom - HUD_QUEUE_SLOT_SIZE, HUD_QUEUE_SLOT_SIZE, HUD_QUEUE_SLOT_SIZE}
		if index == 0 {
			first = box
		}
		draw_fill(state, box, HUD_SLOT_COLOR)
		draw_outline(state, box, index == 0 ? UI_ACCENT_COLOR : UI_PANEL_BORDER_COLOR)
		recipe := screen_context.recipes.recipes[queue.recipes[index]]
		draw_item_stack(state, box, recipe.outputs[0], screen_context.items)
	}
	bar := Ui_Rectangle{first.x, first.y - UI_GAP - 8, first.width, 8}
	ui_progress_bar(state, bar, craft_progress_fraction(queue, screen_context.recipes, screen_context.tick_rate))
	if queue.waiting {
		width := ui_text_width(state, text("crafting_waiting"), UI_BODY_TEXT_SIZE)
		draw_text(state, {right - width, bar.y - UI_GAP - UI_ROW_HEIGHT, width, UI_ROW_HEIGHT}, text("crafting_waiting"), UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
	}
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

// Below the crosshair, the second line under the first.
draw_target_status :: proc(state: ^Ui_State, status: string, line: int = 0) {
	if status == "" {
		return
	}
	centre := state.screen_units / 2
	top := centre.y + CROSSHAIR_SIZE + UI_GAP + f32(line) * UI_ROW_HEIGHT
	area := Ui_Rectangle{0, top, state.screen_units.x, UI_ROW_HEIGHT}
	draw_text(state, area, status, UI_BODY_TEXT_SIZE, .Centre)
}

draw_hud :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	draw_crosshair(state)
	draw_hud_hotbar(state, player^, items)
	draw_craft_queue(state, player^, screen_context)
	if state.screens.count > 0 {
		state.radial = {}
		return
	}
	draw_quest_objective(state, screen_context)
	draw_brownout_warning(state, screen_context.world)
	status, vein_status := target_status_lines(screen_context.world, screen_context.machines, screen_context.fluids, screen_context.veins, player.target)
	draw_target_status(state, status)
	draw_target_status(state, vein_status, status == "" ? 0 : 1)
	hotbar_radial(state, player, items)
	if entity_has_panel(&screen_context.world.entities, player.target.entity) {
		// Interact turns a power switch; Sneak with Interact opens it.
		switch_targeted := entity_is_power_switch(&screen_context.world.entities, screen_context.machines, player.target.entity)
		hints := [?]Glyph_Hint{{.Interact, text(switch_targeted ? "hint_toggle" : "hint_open")}, {.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	hints := [?]Glyph_Hint{{.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
	ui_glyph_bar(state, hints[:])
}
