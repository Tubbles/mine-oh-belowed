package game

import "core:fmt"

// The launch pad's panel inside the machine panel (ui_machine.odin) and
// the Shipments tab of the statistics screen (work item 0040). Panel: the
// part slots with a line per part, the fuel port's level and flow, the
// cargo slots, the progress bar (assembly or ascent), the state, the
// Assemble and Launch buttons and the power line, on the Rocket tab; the
// Contracts and Catalogue tabs are in ui_contracts.odin. Shipments: the
// launches newest first with their game time and cargo, and the totals
// shipped per item.

// Parts label, part lines, fuel rows, cargo label, bar, state, power.
launch_pad_text_rows :: proc(machine: Machine) -> int {
	return 1 + machine.launch_part_count + FLUID_ROWS_PER_BUFFER + 1 + 3
}

launch_pad_area_width :: proc() -> f32 {
	return max(slot_grid_width(LAUNCH_PAD_CARGO_SLOTS), FLUID_AREA_WIDTH)
}

// The Rocket tab's rows below the tab row at a width, whose slot rows
// wrap; the other tabs share the height.
launch_pad_area_height :: proc(machine: Machine, width: f32) -> f32 {
	columns := slot_columns(width)
	slot_rows := slot_rows_height(machine.launch_part_count, columns) + slot_rows_height(LAUNCH_PAD_CARGO_SLOTS, columns)
	button_rows := 2 * f32(UI_ROW_HEIGHT + UI_GAP)
	tab_row := f32(UI_ROW_HEIGHT + UI_GAP)
	return UI_ROW_HEIGHT + tab_row + f32(launch_pad_text_rows(machine)) * UI_ROW_HEIGHT + slot_rows + button_rows
}

// Rocket, Contracts and Catalogue (work item 0041), switched with the
// bumpers or a click.
launch_pad_tab :: proc(state: ^Ui_State, content: ^Ui_Rectangle) -> int {
	labels := [?]string{text("launch_pad_tab_rocket"), text("launch_pad_tab_contracts"), text("launch_pad_tab_catalogue")}
	tab := ui_tabs(state, cut_top(content, UI_ROW_HEIGHT), "launch_pad_tabs", labels[:])
	cut_top(content, UI_GAP)
	return tab
}

// "Rocket structure: 7 / 10"
launch_part_line :: proc(pad: Launch_Pad, machine: Machine, items: Item_Registry, index: int) -> string {
	part := machine.launch_parts[index]
	held := pad.slots[index].item == part.item ? pad.slots[index].count : 0
	return fmt.tprintf("%s: %d / %d", item_name(items, part.item), held, part.count)
}

launch_pad_state_text :: proc(pad: ^Launch_Pad) -> string {
	switch {
	case pad.state == .Assembling && pad.missing_parts:
		return text("launch_pad_state_missing_parts")
	case pad.state == .Rocket_Ready && cargo_is_empty(pad):
		return text("launch_pad_state_needs_cargo")
	}
	return text(launch_pad_state_keys[pad.state])
}

launch_pad_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, pad: ^Launch_Pad, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	content := area
	switch launch_pad_tab(state, &content) {
	case 1:
		launch_pad_contracts_tab(state, content, screen_context)
		return result
	case 2:
		launch_pad_catalogue_tab(state, content, pad, screen_context)
		return result
	}
	machine := screen_context.machines.machines[pad.machine]
	items := screen_context.items
	slots := pad.slots[:launch_pad_slot_count(pad^)]
	detail_line(state, &content, text("launch_pad_parts"), UI_DIM_TEXT_COLOR)
	machine_slot_rows(state, &content, 0, pad.part_count, slots, items, &result)
	for index in 0 ..< machine.launch_part_count {
		detail_line(state, &content, launch_part_line(pad^, machine, items, index))
	}
	port := machine.fluid_ports[LAUNCH_PAD_FUEL_PORT]
	fluid_buffer_rows(state, &content, screen_context.fluids, pad.buffers[LAUNCH_PAD_FUEL_PORT], port.filter, port.capacity, pad.closed[LAUNCH_PAD_FUEL_PORT], screen_context.tick_rate)
	detail_line(state, &content, text("launch_pad_cargo"), UI_DIM_TEXT_COLOR)
	machine_slot_rows(state, &content, pad.part_count, LAUNCH_PAD_CARGO_SLOTS, slots, items, &result)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), launch_pad_progress(pad^, machine, screen_context.tick_rate))
	detail_line(state, &content, launch_pad_state_text(pad), UI_DIM_TEXT_COLOR)
	// The tick counts a refused press (Assembly_Command, Launch_Command).
	if ui_button(state, cut_row(&content), text("launch_pad_assemble")) {
		queue_player_command(screen_context.player_commands, screen_context.player_index, Assembly_Command{pad = pad.handle})
	}
	if ui_button(state, cut_row(&content), text("launch_pad_launch")) {
		queue_player_command(screen_context.player_commands, screen_context.player_index, Launch_Command{pad = pad.handle})
	}
	power_line := power_status_line(&screen_context.world.entities.electric_networks, pad.handle)
	detail_line(state, &content, power_line, UI_DIM_TEXT_COLOR)
	return result
}

// "12:05  Iron plate 50, Steel 20"
shipment_line :: proc(shipment: Shipment, items: Item_Registry, tick_rate: int) -> string {
	return fmt.tprintf("%s  %s", format_game_time(shipment.tick, tick_rate), shipment_cargo_text(shipment, items))
}

shipment_list :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	shipments := screen_context.records.shipments[:]
	if len(shipments) == 0 {
		ui_label(state, {area.x, area.y, area.width, UI_ROW_HEIGHT}, text("statistics_no_shipments"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	list := scroll_list_begin(state, "shipment_list", area, len(shipments))
	for position in 0 ..< len(shipments) {
		shipment := shipments[len(shipments) - 1 - position]
		row := scroll_list_row(list, position)
		id := ui_id(state, "shipment", position)
		interaction := ui_interact(state, id, row)
		if interaction.focused {
			scroll_list_keep_visible(&list, position)
		}
		widget_background(state, row, id, interaction)
		draw_text_fitted(state, inset(row, UI_PADDING), shipment_line(shipment, screen_context.items, screen_context.tick_rate), UI_BODY_TEXT_SIZE, .Left)
	}
	scroll_list_end(state, &list)
}

shipments_tab :: proc(state: ^Ui_State, area: Ui_Rectangle, screen_context: Screen_Context) {
	content := area
	statistics := screen_context.records.statistics
	list_area := cut_left(&content, statistics_list_width(content))
	cut_left(&content, 2 * UI_PADDING)
	header := cut_top(&list_area, UI_ROW_HEIGHT)
	draw_text_fitted(state, inset(header, UI_PADDING), text("statistics_shipments"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	shipment_list(state, list_area, screen_context)
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text("statistics_shipped_totals"), UI_HEADING_TEXT_SIZE, .Left)
	detail_line(state, &content, fmt.tprintf("%s: %d", text("statistics_rockets_launched"), statistics.rockets_launched))
	for total in shipped_totals(statistics.shipped) {
		detail_line(state, &content, fmt.tprintf("%s: %d", item_name(screen_context.items, total.item), total.count))
	}
}
