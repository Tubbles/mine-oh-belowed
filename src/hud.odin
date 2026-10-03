package game

import "core:fmt"

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
// Rows of run boxes beside the hotbar at most (0138).
HUD_QUEUE_MAXIMUM_ROWS :: 4
// Distance of the radial's slot centres from the screen centre.
HUD_RADIAL_RADIUS :: UI_SLOT_SIZE * 2.5
// The mining progress bar above the crosshair.
HUD_MINING_BAR_WIDTH :: 4 * CROSSHAIR_SIZE
HUD_MINING_BAR_HEIGHT :: 6.0
// The touch tap scheme's ring around the mined block (0118).
HUD_MINING_RING_DIAMETER :: 3 * CROSSHAIR_SIZE
HUD_MINING_RING_THICKNESS :: 6.0

// What only the HUD reads, derived by the frame loop (make_hud_context):
// the touch derivations and the biome under the player. Its world and
// content reads come through Screen_Context, since the quest objective
// shares the journal's procedures. The zero value draws no banner.
Hud_Context :: struct {
	// The touch overlay's tap scheme is on (touch_overlay_aims): the HUD
	// draws no crosshair and rings the mined block, whose centre
	// mining_ring_centre is in render pixels.
	touch_aims:               bool,
	mining_ring_centre:       [2]f32,
	// The HUD's touch buttons shown (0134, frame_hud_touch_buttons_shown):
	// none unless the touch overlay is on in a world.
	touch_hud_buttons:        bit_set[Hud_Touch_Button],
	// The discovery card's lowest top, a UI y below the touch overlay's
	// Back and Start while it is drawn, else 0 (0123).
	discovery_card_clearance: f32,
	// Kept by the frame loop across frames (biome_banner.odin). Nil
	// without a world.
	biome_banner:             ^Biome_Banner,
	// The biome under the player, sampled once per frame, and the
	// generator's biomes it indexes, for the banner's name.
	biome:                    int,
	biomes:                   []Biome,
	// The viewport's field player as its camera and ghost show it, the
	// prediction while the lockstep window runs ahead
	// (lockstep_view_player), for the tool line. Unset (field_view_set
	// false), the line reads the screen context's player.
	field_view:               Field_Player,
	field_view_set:           bool,
	// What the tool line says of field_view's machine over bare ground
	// (0201, bare_ground_line), read against the field once per frame.
	bare_ground:              Bare_Ground_Line,
}

// The field player the tool line describes.
hud_field_player :: proc(screen_context: Screen_Context, hud: Hud_Context) -> Field_Player {
	return hud.field_view_set ? hud.field_view : screen_context.player.field
}

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

// Left of the hotbar, newest run nearest to it, in up to
// HUD_QUEUE_MAXIMUM_ROWS rows going up when the queue is wider than the
// room beside the hotbar (craft_queue_shown_runs): the recipe's first
// output per run with the run's crafts in the corner like a stack count,
// a progress bar over the front run, and above it why it waits
// (craft_queue_waiting_text).
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
	shown := craft_queue_shown_runs(queue.count, columns * HUD_QUEUE_MAXIMUM_ROWS)
	first: Ui_Rectangle
	for index, position in shown {
		place := len(shown) - 1 - position
		x := right - f32(place % columns + 1) * step
		y := bottom - HUD_QUEUE_SLOT_SIZE - f32(place / columns) * step
		box := Ui_Rectangle{x, y, HUD_QUEUE_SLOT_SIZE, HUD_QUEUE_SLOT_SIZE}
		if index == 0 {
			first = box
		}
		draw_fill(state, box, HUD_SLOT_COLOR)
		draw_outline(state, box, index == 0 ? UI_ACCENT_COLOR : UI_PANEL_BORDER_COLOR)
		draw_item_stack(state, box, craft_run_stack(queue.runs[index], screen_context.recipes), screen_context.items)
	}
	bar := Ui_Rectangle{first.x, first.y - UI_GAP - 8, first.width, 8}
	ui_progress_bar(state, bar, craft_progress_fraction(queue, screen_context.recipes, screen_context.tick_rate))
	waiting := craft_queue_waiting_text(queue, screen_context.items)
	if waiting == "" {
		return
	}
	lines := wrap_text_lines(state, waiting, UI_BODY_TEXT_SIZE, right - safe.x, HUD_WAITING_MAXIMUM_LINES)
	line_bottom := bar.y - UI_GAP
	#reverse for line in lines {
		draw_text(state, {safe.x, line_bottom - UI_LINE_HEIGHT, right - safe.x, UI_LINE_HEIGHT}, line, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
		line_bottom -= UI_LINE_HEIGHT
	}
}

// The runs the HUD has boxes for, in queue order: all of them when they
// fit, else the front run and the newest capacity - 1, the middle left
// out. In the temp allocator.
craft_queue_shown_runs :: proc(count, capacity: int) -> []int {
	shown := make([dynamic]int, 0, count, context.temp_allocator)
	for index in 0 ..< count {
		if count <= capacity || index == 0 || index >= count - (capacity - 1) {
			append(&shown, index)
		}
	}
	return shown[:]
}

// The run's box: its recipe's first output with the run's crafts as the
// count.
craft_run_stack :: proc(run: Craft_Run, recipes: Recipe_Registry) -> Item_Stack {
	outputs := recipes.recipes[run.recipe].outputs
	if len(outputs) == 0 {
		return EMPTY_STACK
	}
	return Item_Stack{outputs[0].item, u16(clamp(run.count, 0, int(max(u16))))}
}

// "Crafting waits: inventory full" while the front craft's outputs do not
// fit, "Waiting for Log" while it lacks an ingredient, empty otherwise.
craft_queue_waiting_text :: proc(queue: Craft_Queue, items: Item_Registry) -> string {
	switch {
	case queue.count > 0 && queue.waiting:
		return text("crafting_waiting")
	case craft_queue_waits_for_input(queue):
		return replace_message_mark(text("crafting_waiting_for"), "{name}", item_name(items, queue.waiting_for))
	}
	return ""
}

hotbar_radial_source :: proc(input: Ui_Input) -> Radial_Source {
	return input.left_touchpad.down ? .Touchpad : .Held_Button
}

// The left pad (or Tab and the right stick) shows the hotbar as a wheel
// around the screen centre, slot 0 at the top, clockwise. Release selects
// through a Hotbar_Slot_Command for the tick.
hotbar_radial :: proc(state: ^Ui_State, player: ^Player, player_index: int, commands: ^[dynamic]Queued_Player_Command, items: Item_Registry) {
	source := hotbar_radial_source(state.input)
	touching, position := radial_input(state.input, source)
	result: Radial_Result
	state.radial, result = advance_radial(state.radial, touching, position, source, HOTBAR_SLOT_COUNT)
	if result.closed && result.selected >= 0 {
		queue_player_command(commands, player_index, Hotbar_Slot_Command{slot = result.selected})
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
	title, detail, found := contract_objective_lines(screen_context.records.contracts, screen_context.contracts, screen_context.items, screen_context.tick, screen_context.tick_rate)
	if !found {
		return
	}
	area := hud_objective_area(state)
	draw_text_fitted(state, cut_top(&area, UI_ROW_HEIGHT), title, UI_BODY_TEXT_SIZE, .Right, UI_ACCENT_COLOR)
	for line in wrap_text(state, detail, UI_BODY_TEXT_SIZE, area.width) {
		draw_text(state, cut_top(&area, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Right)
	}
}

draw_hud :: proc(state: ^Ui_State, screen_context: Screen_Context, hud: Hud_Context) {
	player, items := screen_context.player, screen_context.items
	if hud.touch_aims {
		draw_mining_ring(state, player.mining, hud.mining_ring_centre)
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
	switch hud_objective_source(screen_context.quest_state, screen_context.records.contracts.open_count) {
	case .Quest:
		draw_quest_objective(state, screen_context)
	case .Contract:
		draw_contract_objective(state, screen_context)
	case .None:
	}
	draw_hud_touch_buttons(state, hud.touch_hud_buttons)
	draw_brownout_warning(state, screen_context.world)
	draw_biome_banner(state, hud)
	if height := draw_mission_control_panel(state); height > 0 {
		state.toast_top_offset = height + UI_GAP
	}
	draw_discovery_card(state, items, hud.discovery_card_clearance)
	obtained := screen_context.unlocks.obtained
	name_status, tool_status, vein_status := target_status_lines(screen_context.world, screen_context.records, screen_context.machines, screen_context.fluids, screen_context.veins, screen_context.blocks, items, obtained, effective_tool_tier(player^, items, screen_context.cheat_speed), player.target)
	if line, shown := field_tool_line(hud_field_player(screen_context, hud), screen_context.content, hud.bare_ground); shown {
		tool_status = line
	}
	if ghost_line, shown := bore_drill_ghost_line(screen_context.world, screen_context.records.assayed_veins[:], screen_context.machines, screen_context.veins, screen_context.blocks, items, obtained, player^); shown {
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
	hotbar_radial(state, player, screen_context.player_index, screen_context.player_commands, items)
	// On touch the gestures and the overlay's buttons are the hints (0137).
	if touch_row_shows(state) {
		return
	}
	if hints, shown := schematic_glyph_hints(screen_context.world, player^, items); shown {
		ui_glyph_bar(state, hints)
		return
	}
	if field_pick_up_hint_shown(screen_context, hud) {
		pick_up := field_target_is_broken(screen_context, hud) ? MACHINE_BROKEN_DOWN_KEY : "hint_pick_up"
		inventory := Glyph_Hint{.Inventory, text(inventory_hint_key(screen_context, hud))}
		// Interact turns a power switch on the field too (0194).
		if field_target_is_power_switch(screen_context, hud) {
			hints := [?]Glyph_Hint{{.Interact, text("hint_toggle")}, {.Mine, text(pick_up)}, inventory, {.Pause, text("hint_pause")}}
			ui_glyph_bar(state, hints[:])
			return
		}
		hints := [?]Glyph_Hint{{.Mine, text(pick_up)}, inventory, {.Pause, text("hint_pause")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	if entity_has_panel(&screen_context.world.entities, player.target.entity) {
		// Inventory opens the panel (0194); Interact turns a power switch.
		if entity_is_power_switch(&screen_context.world.entities, screen_context.machines, player.target.entity) {
			hints := [?]Glyph_Hint{{.Interact, text("hint_toggle")}, {.Inventory, text("hint_open")}, {.Pause, text("hint_pause")}}
			ui_glyph_bar(state, hints[:])
			return
		}
		hints := [?]Glyph_Hint{{.Inventory, text("hint_open")}, {.Pause, text("hint_pause")}}
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

// The field player aims at a frame cell whose entity Mine picks up
// (0195): any but the pod and its pad (field_entity_is_placed_by_world).
// One held up shows it too; the refusal tells why on the press.
field_pick_up_hint_shown :: proc(screen_context: Screen_Context, hud: Hud_Context) -> bool {
	target := hud_field_player(screen_context, hud).frame_target
	if !target.hit || screen_context.world == nil {
		return false
	}
	return !field_entity_is_placed_by_world(&screen_context.world.entities, screen_context.machines, entity_from_occupant(target.occupant.handle))
}

// What the Inventory glyph says: Open while it opens the aimed machine's
// panel (0194, aims_at_panel), else Inventory.
inventory_hint_key :: proc(screen_context: Screen_Context, hud: Hud_Context) -> string {
	aimed := aims_at_panel(&screen_context.world.entities, screen_context.player.target.entity, hud_field_player(screen_context, hud).frame_target)
	return aimed ? "hint_open" : "hint_inventory"
}

// The aimed frame cell holds a power switch, which Interact turns (0194).
field_target_is_power_switch :: proc(screen_context: Screen_Context, hud: Hud_Context) -> bool {
	target := hud_field_player(screen_context, hud).frame_target
	return target.hit && entity_is_power_switch(&screen_context.world.entities, screen_context.machines, entity_from_occupant(target.occupant.handle))
}

// The aimed frame cell holds a broken machine (0201): its pick up hint
// says to tear it down.
field_target_is_broken :: proc(screen_context: Screen_Context, hud: Hud_Context) -> bool {
	target := hud_field_player(screen_context, hud).frame_target
	common := entity_common(&screen_context.world.entities, entity_from_occupant(target.occupant.handle))
	return common != nil && common.broken
}

// The vein's name and what is left of it in total, for the HUD.
vein_size_class_name :: proc(veins: Vein_Content, size_class: int) -> string {
	if size_class < 0 || size_class >= len(veins.size_class_ids) {
		return ""
	}
	return text(fmt.tprintf("vein_size_%s", veins.size_class_ids[size_class]))
}

// The vein's type reads "Unknown ore" until one of its ores was obtained
// (discovery.odin); the size and what is left show either way.
vein_status_text :: proc(world: ^World, assayed_veins: []Assayed_Vein, veins: Vein_Content, blocks: Block_Registry, items: Item_Registry, obtained: []bool, id: Vein_Id) -> string {
	vein := registered_vein(world, id)
	if vein == nil || vein.type >= len(veins.types) {
		return ""
	}
	vein_type := veins.types[vein.type]
	name := text(vein_type_is_discovered(vein_type, blocks, items, obtained) ? vein_type.name_key : UNKNOWN_ORE_KEY)
	if vein_is_assayed(assayed_veins, id) {
		name = fmt.tprintf("%s  %s  %s", name, vein_size_class_name(veins, vein.size_class), text("vein_assayed"))
	}
	if world.settings.veins_infinite {
		return fmt.tprintf("%s  %s", name, text("drill_infinite"))
	}
	return fmt.tprintf("%s  %d %s", name, vein_remaining_total(vein^), text("drill_remaining"))
}

// The name and state of an entity for the HUD, "" when it has none.
entity_status_text :: proc(world: ^World, core_samples: []Core_Sample, machines: Machine_Registry, fluids: Fluid_Registry, items: Item_Registry, handle: Entity_Handle) -> string {
	common := entity_common(&world.entities, handle)
	if common == nil {
		return ""
	}
	name := machine_name(machines, common.machine)
	if common.broken {
		return fmt.tprintf("%s  %s", name, text(MACHINE_BROKEN_DOWN_KEY))
	}
	#partial switch handle.kind {
	case .Furnace:
		furnace := pool_get(&world.entities.furnaces, handle)
		return fmt.tprintf("%s  %s", name, text(furnace_state_keys[furnace.state]))
	case .Inserter:
		inserter := pool_get(&world.entities.inserters, handle)
		return fmt.tprintf("%s  %s", name, inserter_state_text(inserter^, items))
	case .Drill:
		drill := pool_get(&world.entities.drills, handle)
		return fmt.tprintf("%s  %s", name, drill_state_text(drill^, items))
	case .Pipe, .Fluid_Machine:
		return fluid_status_text(world, machines, fluids, handle, name)
	case .Pole, .Lamp:
		return power_entity_status_text(world, machines, handle, name)
	case .Assembler:
		assembler := pool_get(&world.entities.assemblers, handle)
		return fmt.tprintf("%s  %s", name, text(assembler_state_keys[assembler.state]))
	case .Lab:
		lab := pool_get(&world.entities.labs, handle)
		return fmt.tprintf("%s  %s", name, text(lab_state_keys[lab.state]))
	case .Schematic_Crate:
		crate := pool_get(&world.entities.schematic_crates, handle)
		return stack_is_empty(crate.slots[0]) ? fmt.tprintf("%s  %s", name, text("schematic_crate_empty")) : name
	case .Core_Sample_Drill:
		return fmt.tprintf("%s  %s", name, core_sample_state_text(core_samples, pool_get(&world.entities.core_sample_drills, handle)^))
	case .Launch_Pad:
		return fmt.tprintf("%s  %s", name, launch_pad_state_text(pool_get(&world.entities.launch_pads, handle)))
	}
	return name
}

// While a bore drill is being placed, the HUD's vein line names the deep
// vein its ghost would tap, since nothing on the surface marks deep veins.
bore_drill_ghost_line :: proc(world: ^World, assayed_veins: []Assayed_Vein, machines: Machine_Registry, veins: Vein_Content, blocks: Block_Registry, items: Item_Registry, obtained: []bool, player: Player) -> (line: string, shown: bool) {
	vein, found, selected := bore_drill_ghost_vein(world, machines, player)
	if !selected {
		return "", false
	}
	if !found {
		return text("bore_drill_no_deep_vein"), true
	}
	return vein_status_text(world, assayed_veins, veins, blocks, items, obtained, vein), true
}

// What the HUD shows under the crosshair, one line each and "" where
// nothing applies: the targeted entity's name and state, else the block's
// name ("Unknown ore" for an ore not discovered yet, discovery.odin); the
// pickaxe a block above the player's tool_tier needs; and for a drill or
// any block over a surface vein's footprint (mined outcrop or not) the
// vein and what is left. obtained is Recipe_Unlocks.obtained.
target_status_lines :: proc(world: ^World, records: ^Game_Records, machines: Machine_Registry, fluids: Fluid_Registry, veins: Vein_Content, blocks: Block_Registry, items: Item_Registry, obtained: []bool, tool_tier: int, target: Raycast_Hit) -> (name_line, tool_line, vein_line: string) {
	if drill := pool_get(&world.entities.drills, target.entity); drill != nil {
		return entity_status_text(world, records.core_samples[:], machines, fluids, items, target.entity), "", vein_status_text(world, records.assayed_veins[:], veins, blocks, items, obtained, drill.vein)
	}
	if target.entity != NO_ENTITY {
		return entity_status_text(world, records.core_samples[:], machines, fluids, items, target.entity), "", ""
	}
	if !target.hit {
		return "", "", ""
	}
	block := world_get_block(world, target.block)
	name_line = target_block_name(blocks, items, obtained, block)
	tool_line = mining_tool_line(blocks, items, block, tool_tier)
	if vein, found := vein_at_column(world, target.block.x, target.block.z); found {
		vein_line = vein_status_text(world, records.assayed_veins[:], veins, blocks, items, obtained, vein)
	}
	return
}

// On the field (0187): a machine other than a foundation over bare ground
// (0201, bare_ground_line) says how long it lasts there, or the refusal
// Place would toast where the ground is too steep; a held foundation
// names its block (0193, field_foundation_block).
field_tool_line :: proc(player: Field_Player, content: Simulation_Content, bare: Bare_Ground_Line) -> (line: string, shown: bool) {
	switch bare {
	case .None:
	case .Wears_Out:
		machine := content.machines.machines[field_placed_machine(player, content)]
		return bare_ground_wear_line(bare_ground_life_minutes(machine, content.field.bare_ground)), true
	case .Too_Steep:
		return text(field_refusal_keys[.Too_Steep]), true
	}
	if player.tool == .Foundation {
		return foundation_block_line(field_foundation_block(player, content.field)), true
	}
	return "", false
}

// "On bare ground, wears out in 60 min". In the temp allocator.
bare_ground_wear_line :: proc(minutes: int) -> string {
	return replace_message_mark(text(FIELD_TOOL_BARE_GROUND_KEY), "{minutes}", fmt.tprint(minutes))
}

// "Foundation 5x5, 2 high". In the temp allocator.
foundation_block_line :: proc(size, height: i32) -> string {
	line := replace_message_mark(text("field_tool_foundation_block"), "{size}", fmt.tprint(size))
	return replace_message_mark(line, "{height}", fmt.tprint(height))
}

// The loading notice (loading_notice in loop.odin): a panel in the
// middle of the safe area while no tick can run, the text fitted to it.
draw_loading_notice :: proc(state: ^Ui_State, notice: string) {
	safe := ui_safe_area(state)
	width := min(safe.width - 2 * UI_PADDING, LOADING_NOTICE_WIDTH)
	panel := Ui_Rectangle{safe.x + (safe.width - width) / 2, safe.y + (safe.height - UI_ROW_HEIGHT) / 2 - UI_PADDING, width, UI_ROW_HEIGHT + 2 * UI_PADDING}
	draw_panel_art(state, panel, UI_PANEL_COLOR, UI_PANEL_BORDER_COLOR)
	draw_text_fitted(state, inset(panel, UI_PADDING), notice, UI_HEADING_TEXT_SIZE, .Centre)
}

LOADING_NOTICE_WIDTH :: 600
