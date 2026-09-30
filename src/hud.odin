package game

// The world HUD, drawn through the UI draw list under any open screen:
// crosshair, under it the targeted entity's name and state or the
// targeted block's name (dim, "Unknown ore" for an ore not discovered
// yet), the pickaxe the block needs and the vein of a targeted drill or of
// a block over a vein footprint (or the deep vein under a bore drill
// ghost), hotbar with the held item's name, the hotbar radial, the active quest objective (top right,
// ui_journal.odin) or, once every quest is done, the oldest open contract
// (ui_contracts.odin), the brownout warning (top centre, ui_power.odin),
// the biome banner below it (biome_banner.odin) and the glyph bar, and the magnetometer's dial while one is selected
// (ui_prospecting.odin). With the touch overlay driving the world, the
// touch buttons right of the hotbar (0134): inventory, map, pause, rotate. With no screen open, Mission Control's panel at
// the top left, the toasts moved below it, and the discovery card at the
// top centre (ui_mission_control.odin).

CROSSHAIR_SIZE :: 18.0
CROSSHAIR_THICKNESS :: 3.0
CROSSHAIR_COLOR :: Ui_Color{255, 255, 255, 200}
HUD_SELECTED_SLOT_SCALE :: 1.25
HUD_SLOT_COLOR :: Ui_Color{24, 26, 34, 180}
HUD_QUEUE_SLOT_SIZE :: 56
HUD_WAITING_MAXIMUM_LINES :: 2
// Distance of the radial's slot centres from the screen centre.
HUD_RADIAL_RADIUS :: UI_SLOT_SIZE * 2.5
// The mining progress bar above the crosshair.
HUD_MINING_BAR_WIDTH :: 4 * CROSSHAIR_SIZE
HUD_MINING_BAR_HEIGHT :: 6.0
// The touch tap scheme's ring around the mined block (0118).
HUD_MINING_RING_DIAMETER :: 3 * CROSSHAIR_SIZE
HUD_MINING_RING_THICKNESS :: 6.0

draw_crosshair :: proc(state: ^Ui_State) {
	centre := state.screen_units / 2
	draw_fill(state, {centre.x - CROSSHAIR_SIZE, centre.y - CROSSHAIR_THICKNESS / 2, 2 * CROSSHAIR_SIZE, CROSSHAIR_THICKNESS}, CROSSHAIR_COLOR)
	draw_fill(state, {centre.x - CROSSHAIR_THICKNESS / 2, centre.y - CROSSHAIR_SIZE, CROSSHAIR_THICKNESS, 2 * CROSSHAIR_SIZE}, CROSSHAIR_COLOR)
}

// A bar above the crosshair that fills while a block is being dug; gone
// the moment the dig stops or finishes.
draw_mining_progress :: proc(state: ^Ui_State, mining: Mining_State) {
	fraction := mining_fraction(mining)
	if fraction <= 0 {
		return
	}
	centre := state.screen_units / 2
	bar := Ui_Rectangle{centre.x - HUD_MINING_BAR_WIDTH / 2, centre.y - CROSSHAIR_SIZE - 2 * UI_GAP - HUD_MINING_BAR_HEIGHT, HUD_MINING_BAR_WIDTH, HUD_MINING_BAR_HEIGHT}
	ui_progress_bar(state, bar, fraction)
}

// The touch tap scheme's progress: no crosshair shows where the finger
// digs, so a ring around the mined block's centre (render pixels) fills
// clockwise instead of the bar.
draw_mining_ring :: proc(state: ^Ui_State, mining: Mining_State, centre_pixels: [2]f32) {
	fraction := mining_fraction(mining)
	if fraction <= 0 {
		return
	}
	theme := ui_theme(state)
	centre := centre_pixels / state.pixels_per_unit
	ring := Ui_Rectangle{centre.x - HUD_MINING_RING_DIAMETER / 2, centre.y - HUD_MINING_RING_DIAMETER / 2, HUD_MINING_RING_DIAMETER, HUD_MINING_RING_DIAMETER}
	draw_ring(state, ring, theme.colors[.Widget], HUD_MINING_RING_THICKNESS)
	draw_arc(state, ring, theme.colors[.Accent], HUD_MINING_RING_THICKNESS, fraction)
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

// The slots in render pixels, where the touch overlay hit tests them
// (0119).
hud_hotbar_pixel_rectangles :: proc(state: ^Ui_State, selected: int) -> [HOTBAR_SLOT_COUNT]Ui_Rectangle {
	rectangles := hud_hotbar_rectangles(ui_safe_area(state), selected)
	for &rectangle in rectangles {
		rectangle.x *= state.pixels_per_unit
		rectangle.y *= state.pixels_per_unit
		rectangle.width *= state.pixels_per_unit
		rectangle.height *= state.pixels_per_unit
	}
	return rectangles
}

// The HUD's touch buttons (0134), right of the hotbar: the touch
// overlay's way to the inventory, the map, the pause menu and a rotation,
// since its default layout has no gamepad buttons. Each presses the
// gamepad control bound to its action (frame_hud_touch_buttons), so the
// actions stay bindings. Rotate shows only while Rotate_Building acts:
// the selected hotbar slot holds what it turns before placing
// (selected_placement_rotates) or the target is an entity it turns
// (entity_rotates).
Hud_Touch_Button :: enum u8 {
	Inventory,
	Map,
	Pause,
	Rotate,
}

@(rodata)
hud_touch_button_actions := [Hud_Touch_Button]Action {
	.Inventory = .Open_Inventory,
	.Map       = .Open_Map,
	.Pause     = .Pause,
	.Rotate    = .Rotate_Building,
}

@(rodata)
hud_touch_button_icons := [Hud_Touch_Button]Ui_Icon {
	.Inventory = .Backpack,
	.Map       = .Map,
	.Pause     = .Pause,
	.Rotate    = .Rotate,
}

// Right of the hotbar on its baseline, a slot's size each, in the enum's
// order, so Rotate coming and going moves no other button; in rows going
// up when the room beside the hotbar is narrower than the row, like the
// craft queue on the left. The hotbar's width does not depend on the
// selected slot.
hud_touch_button_rectangles :: proc(area: Ui_Rectangle) -> [Hud_Touch_Button]Ui_Rectangle {
	last := hud_hotbar_rectangles(area, 0)[HOTBAR_SLOT_COUNT - 1]
	left := last.x + last.width + 3 * UI_GAP
	bottom := last.y + last.height
	step := f32(UI_SLOT_SIZE + UI_GAP)
	columns := max(int((area.x + area.width - left + UI_GAP) / step), 1)
	rectangles: [Hud_Touch_Button]Ui_Rectangle
	for &rectangle, button in rectangles {
		index := int(button)
		rectangle = {left + f32(index % columns) * step, bottom - UI_SLOT_SIZE - f32(index / columns) * step, UI_SLOT_SIZE, UI_SLOT_SIZE}
	}
	return rectangles
}

// Inventory, map and pause always, rotate while Rotate_Building acts.
hud_touch_buttons_shown :: proc(rotates: bool) -> bit_set[Hud_Touch_Button] {
	return rotates ? {.Inventory, .Map, .Pause, .Rotate} : {.Inventory, .Map, .Pause}
}

draw_hud_touch_buttons :: proc(state: ^Ui_State, shown: bit_set[Hud_Touch_Button]) {
	rectangles := hud_touch_button_rectangles(ui_safe_area(state))
	for button in shown {
		draw_fill(state, rectangles[button], HUD_SLOT_COLOR)
		draw_outline(state, rectangles[button], UI_PANEL_BORDER_COLOR, UI_BORDER)
		draw_ui_icon(state, inset(rectangles[button], UI_SLOT_SIZE / 6), hud_touch_button_icons[button])
	}
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

// Left of the hotbar, newest entry nearest to it, in rows going up when
// the queue is wider than the room beside the hotbar: the recipe's first
// output per entry, a progress bar over the one in progress, and above it
// why it waits when its outputs do not fit.
draw_craft_queue :: proc(state: ^Ui_State, player: Player, screen_context: Screen_Context) {
	queue := player.crafting
	if queue.count == 0 {
		return
	}
	safe := ui_safe_area(state)
	hotbar := hud_hotbar_rectangles(safe, player.selected_hotbar_slot)
	bottom := hotbar[0].y + hotbar[0].height
	right := hotbar[0].x - 3 * UI_GAP
	step := f32(HUD_QUEUE_SLOT_SIZE + UI_GAP)
	columns := max(int((right - safe.x + UI_GAP) / step), 1)
	first: Ui_Rectangle
	for index in 0 ..< queue.count {
		place := queue.count - 1 - index
		x := right - f32(place % columns + 1) * step
		y := bottom - HUD_QUEUE_SLOT_SIZE - f32(place / columns) * step
		box := Ui_Rectangle{x, y, HUD_QUEUE_SLOT_SIZE, HUD_QUEUE_SLOT_SIZE}
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
	if !queue.waiting {
		return
	}
	lines := wrap_text_lines(state, text("crafting_waiting"), UI_BODY_TEXT_SIZE, right - safe.x, HUD_WAITING_MAXIMUM_LINES)
	line_bottom := bar.y - UI_GAP
	#reverse for line in lines {
		draw_text(state, {safe.x, line_bottom - UI_LINE_HEIGHT, right - safe.x, UI_LINE_HEIGHT}, line, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
		line_bottom -= UI_LINE_HEIGHT
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

// A full schematic crate in view takes Interact; a selected usable item
// (a schematic, a prospecting tool) is used with the Place control
// (Use_Item). In the temp allocator.
schematic_glyph_hints :: proc(world: ^World, player: Player, items: Item_Registry) -> (hints: []Glyph_Hint, shown: bool) {
	list := make([dynamic]Glyph_Hint, context.temp_allocator)
	crate := pool_get(&world.entities.schematic_crates, player.target.entity)
	if crate != nil && !stack_is_empty(crate.slots[0]) {
		append(&list, Glyph_Hint{.Interact, text("hint_take_schematic")})
	}
	selected := selected_hotbar_stack(player)
	if !stack_is_empty(selected) && item_is_usable(items, selected.item) {
		append(&list, Glyph_Hint{.Use_Item, text(item_use_hint_keys[items.items[selected.item].use])})
	}
	if len(list) == 0 {
		return nil, false
	}
	append(&list, Glyph_Hint{.Inventory, text("hint_inventory")}, Glyph_Hint{.Pause, text("hint_pause")})
	return list[:], true
}

// Below the crosshair on the line after the last one drawn; an empty
// status takes no line. Returns the next line.
draw_target_status :: proc(state: ^Ui_State, status: string, line: int, color := UI_TEXT_COLOR) -> int {
	if status == "" {
		return line
	}
	centre := state.screen_units / 2
	top := centre.y + CROSSHAIR_SIZE + UI_GAP + f32(line) * UI_ROW_HEIGHT
	area := Ui_Rectangle{0, top, state.screen_units.x, UI_ROW_HEIGHT}
	draw_text(state, area, status, UI_BODY_TEXT_SIZE, .Centre, color)
	return line + 1
}

// Walking on the ground without sprinting: the glyph bar offers Sprint.
sprint_hint_shown :: proc(player: Player) -> bool {
	return !player.flying && !player.sprinting && player.on_ground && (player.velocity.x != 0 || player.velocity.z != 0)
}

// What the HUD's objective column shows.
Hud_Objective_Source :: enum u8 {
	None,
	Quest,
	Contract,
}

// The active quest, else after the last quest the oldest open contract,
// else nothing.
hud_objective_source :: proc(quest_state: ^Quest_State, open_contract_count: i32) -> Hud_Objective_Source {
	switch {
	case quest_state == nil:
		return .None
	case quest_state.active != NO_QUEST:
		return .Quest
	case open_contract_count > 0:
		return .Contract
	}
	return .None
}

// The oldest open contract where the quest objective was: its name and
// one wrapped line of requests and time left.
draw_contract_objective :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	title, detail, found := contract_objective_lines(screen_context.world, screen_context.contracts, screen_context.items, screen_context.tick, screen_context.tick_rate)
	if !found {
		return
	}
	area := hud_objective_area(state)
	draw_text_fitted(state, cut_top(&area, UI_ROW_HEIGHT), title, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
	for line in wrap_text(state, detail, UI_BODY_TEXT_SIZE, area.width) {
		draw_text(state, cut_top(&area, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Right)
	}
}

draw_hud :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	if screen_context.touch_aims {
		draw_mining_ring(state, player.mining, screen_context.mining_ring_centre)
	} else {
		draw_crosshair(state)
		draw_mining_progress(state, player.mining)
	}
	draw_hud_hotbar(state, player^, items)
	draw_craft_queue(state, player^, screen_context)
	if state.screens.count > 0 {
		state.radial = {}
		return
	}
	switch hud_objective_source(screen_context.quest_state, screen_context.world.contracts.open_count) {
	case .Quest:
		draw_quest_objective(state, screen_context)
	case .Contract:
		draw_contract_objective(state, screen_context)
	case .None:
	}
	draw_hud_touch_buttons(state, screen_context.touch_hud_buttons)
	draw_brownout_warning(state, screen_context.world)
	draw_biome_banner(state, screen_context)
	if height := draw_mission_control_panel(state); height > 0 {
		state.toast_top_offset = height + UI_GAP
	}
	draw_discovery_card(state, items, screen_context.discovery_card_clearance)
	obtained := screen_context.unlocks.obtained
	name_status, tool_status, vein_status := target_status_lines(screen_context.world, screen_context.machines, screen_context.fluids, screen_context.veins, screen_context.blocks, items, obtained, effective_tool_tier(player^, items, screen_context.cheat_speed), player.target)
	if ghost_line, shown := bore_drill_ghost_line(screen_context.world, screen_context.machines, screen_context.veins, screen_context.blocks, items, obtained, player^); shown {
		vein_status = ghost_line
	}
	// An entity's line is its state, a block's only says what it is.
	name_color := player.target.entity == NO_ENTITY ? UI_DIM_TEXT_COLOR : UI_TEXT_COLOR
	line := draw_target_status(state, name_status, 0, name_color)
	line = draw_target_status(state, tool_status, line)
	draw_target_status(state, vein_status, line)
	if selected := selected_hotbar_stack(player^); !stack_is_empty(selected) && item_has_use(items, selected.item, .Magnetometer) {
		draw_magnetometer(state, player^)
	}
	hotbar_radial(state, player, items)
	// On touch the gestures and the overlay's buttons are the hints (0137).
	if touch_row_shows(state) {
		return
	}
	if hints, shown := schematic_glyph_hints(screen_context.world, player^, items); shown {
		ui_glyph_bar(state, hints)
		return
	}
	if entity_has_panel(&screen_context.world.entities, player.target.entity) {
		// Interact turns a power switch; Sneak with Interact opens it.
		switch_targeted := entity_is_power_switch(&screen_context.world.entities, screen_context.machines, player.target.entity)
		hints := [?]Glyph_Hint{{.Interact, text(switch_targeted ? "hint_toggle" : "hint_open")}, {.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	if sprint_hint_shown(player^) {
		hints := [?]Glyph_Hint{{.Sprint, text("hint_sprint")}, {.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	hints := [?]Glyph_Hint{{.Inventory, text("hint_inventory")}, {.Pause, text("hint_pause")}}
	ui_glyph_bar(state, hints[:])
}
