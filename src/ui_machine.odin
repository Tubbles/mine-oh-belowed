package game

import "core:fmt"

// The machine panel: the player's slots on the left, the machine's on the
// right, in one UI panel so the focus moves across both. The slot
// interaction is the inventory's, plus the slot filters of the machine and
// the distribute gesture.

MACHINE_CHEST_COLUMNS :: 8
MACHINE_BAR_WIDTH :: 160
MACHINE_BAR_HEIGHT :: 20
FURNACE_AREA_WIDTH :: 2 * UI_SLOT_SIZE + MACHINE_BAR_WIDTH + 2 * UI_GAP
DRILL_AREA_WIDTH :: 480
// The vein's name, a line per output, the rate, the output rate and the
// state.
DRILL_TEXT_ROWS :: 4 + MAXIMUM_VEIN_OUTPUTS
SPLITTER_AREA_WIDTH :: 480
// Input priority, output priority and the filter's side.
SPLITTER_CHOICE_ROWS :: 3

@(rodata)
splitter_priority_keys := [Splitter_Priority]string {
	.None  = "splitter_priority_none",
	.Left  = "splitter_side_left",
	.Right = "splitter_side_right",
}

@(rodata)
splitter_side_keys := [Splitter_Side]string {
	.Left  = "splitter_side_left",
	.Right = "splitter_side_right",
}

// The machine's slot indices plus the filter slot of a filter inserter
// or a splitter and an inserter's hand slot, which are not among the
// slots, and the transfer button activated this frame (quick_transfer.odin).
Machine_Slot_Result :: struct {
	using grid:       Slot_Grid_Result,
	filter_activated: bool,
	filter_focused:   bool,
	// The panel has the filter slot (the touch row's Clear filter).
	filter_shown:     bool,
	hand_activated:   bool,
	hand_focused:     bool,
	transfer:         Transfer_Button,
}

// Indices into the machine's slots, -1 for none.
Machine_Slot_Input :: struct {
	activated:      int,
	focused:        int,
	confirm_down:   bool,
	secondary:      bool,
	context_action: bool,
}

machine_slot_filters :: proc(kind: Machine_Kind, slot_count: int) -> []Slot_Filter {
	filters := make([]Slot_Filter, slot_count, context.temp_allocator)
	#partial switch kind {
	case .Furnace:
		filters[FURNACE_FUEL_SLOT] = {kind = .Fuel}
		filters[FURNACE_INPUT_SLOT] = {kind = .Smeltable}
		filters[FURNACE_OUTPUT_SLOT] = {kind = .Output}
		filters[FURNACE_BYPRODUCT_SLOT] = {kind = .Output}
	case .Inserter, .Drill, .Boiler, .Combustion_Generator:
		for &filter in filters {
			filter = {kind = .Fuel}
		}
	}
	return filters
}

// A slot joins the gesture when it takes the held item and has it or nothing.
slot_takes_distribution :: proc(slot: Item_Stack, filter: Slot_Filter, held: Held_Stack, items: Item_Registry, recipes: Recipe_Registry) -> bool {
	if stack_is_empty(held.stack) || !slot_accepts(filter, held.stack.item, items, recipes) {
		return false
	}
	return stack_is_empty(slot) || slot.item == held.stack.item
}

// A with a stack held starts the gesture instead of dropping at once; the
// drop or the spread happens on release (finish_distribute).
apply_machine_slot_input :: proc(gesture: ^Distribute_Gesture, slots: []Item_Stack, filters: []Slot_Filter, held: Held_Stack, input: Machine_Slot_Input, items: Item_Registry, recipes: Recipe_Registry) -> Held_Stack {
	result := held
	if gesture.active {
		if !input.confirm_down {
			result = finish_distribute(gesture^, slots, filters, result, items, recipes)
			gesture^ = {}
		} else if input.focused >= 0 && slot_takes_distribution(slots[input.focused], filters[input.focused], result, items, recipes) {
			gesture^ = gesture_visit(gesture^, input.focused)
		}
		return result
	}
	if input.activated < 0 {
		return result
	}
	if input.confirm_down && slot_takes_distribution(slots[input.activated], filters[input.activated], result, items, recipes) {
		gesture^ = gesture_visit({}, input.activated)
		return result
	}
	return apply_machine_slot_primary(slots, input.activated, filters[input.activated], result, items, recipes)
}

// L2 splits a machine slot's stack onto the cursor, X sorts a chest.
apply_machine_slot_secondary :: proc(slots: []Item_Stack, kind: Machine_Kind, held: Held_Stack, input: Machine_Slot_Input, items: Item_Registry, ranks: []u16) -> Held_Stack {
	result := held
	if input.secondary && input.focused >= 0 && stack_is_empty(result.stack) {
		result = apply_slot_split(Inventory{slots = slots}, result, input.focused)
		if !stack_is_empty(result.stack) {
			result.origin_slot = MACHINE_SLOT_ORIGIN
		}
	}
	if input.context_action && kind == .Chest && stack_is_empty(result.stack) {
		sort_slots(slots, items, ranks)
	}
	return result
}

// The machine side's natural width: its widest row of slots or text.
machine_area_width :: proc(machine: Machine) -> f32 {
	switch machine.kind {
	case .Chest, .Capsule:
		return slot_grid_width(MACHINE_CHEST_COLUMNS)
	case .Furnace, .Inserter:
		return FURNACE_AREA_WIDTH
	case .Drill:
		return DRILL_AREA_WIDTH
	case .Splitter:
		return SPLITTER_AREA_WIDTH
	case .Pipe, .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump, .Tar_Pit_Pump, .Flare_Stack, .Combustion_Generator, .Hydro_Turbine:
		return fluid_area_size(machine).x
	case .Pole, .Power_Switch, .Lamp:
		return power_area_size(machine).x
	case .Crafting_Machine, .Lab:
		return crafting_machine_area_width(machine)
	case .Core_Sample_Drill:
		return core_sample_area_size().x
	case .Launch_Pad:
		return launch_pad_area_width()
	case .Belt, .Schematic_Crate, .Foundation:
	}
	return 0
}

// The machine side's height at a width, to which its slot grids and
// rows wrap.
machine_area_height :: proc(machine: Machine, slot_count: int, width: f32) -> f32 {
	switch machine.kind {
	case .Chest, .Capsule:
		return UI_ROW_HEIGHT + slot_rows_height(slot_count, chest_columns(width))
	case .Furnace:
		return UI_ROW_HEIGHT + 2 * (UI_SLOT_SIZE + UI_GAP) + 2 * UI_ROW_HEIGHT
	case .Inserter:
		return UI_ROW_HEIGHT + 2 * (UI_SLOT_SIZE + UI_GAP) + 3 * UI_ROW_HEIGHT
	case .Drill:
		rows := 1 + DRILL_TEXT_ROWS + drill_extra_rows(machine)
		return UI_ROW_HEIGHT + (UI_SLOT_SIZE + UI_GAP) + f32(rows) * UI_ROW_HEIGHT
	case .Splitter:
		return UI_ROW_HEIGHT + SPLITTER_CHOICE_ROWS * (UI_ROW_HEIGHT + UI_GAP) + (UI_SLOT_SIZE + UI_GAP)
	case .Pipe, .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump, .Tar_Pit_Pump, .Flare_Stack, .Combustion_Generator, .Hydro_Turbine:
		return fluid_area_size(machine).y
	case .Pole, .Power_Switch, .Lamp:
		return power_area_size(machine).y
	case .Crafting_Machine, .Lab:
		return crafting_machine_area_height(machine, slot_count, width)
	case .Core_Sample_Drill:
		return core_sample_area_size().y
	case .Launch_Pad:
		return launch_pad_area_height(machine, width)
	case .Belt, .Schematic_Crate, .Foundation:
	}
	return 0
}

// A chest's columns: MACHINE_CHEST_COLUMNS, or fewer on a narrow screen.
chest_columns :: proc(width: f32) -> int {
	return min(slot_columns(width), MACHINE_CHEST_COLUMNS)
}

// Width of the progress bar between two slots (the furnace's).
bar_between_slots_width :: proc(area_width: f32) -> f32 {
	return clamp(area_width - 2 * (UI_SLOT_SIZE + UI_GAP), 0, MACHINE_BAR_WIDTH)
}

// A bar with its label to the right, vertically centred on the row.
machine_bar :: proc(state: ^Ui_State, row: Ui_Rectangle, fraction: f32) {
	bar := Ui_Rectangle{row.x, row.y + (row.height - MACHINE_BAR_HEIGHT) / 2, min(MACHINE_BAR_WIDTH, row.width), MACHINE_BAR_HEIGHT}
	ui_progress_bar(state, bar, fraction)
}

machine_slot :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, index: int, slots: []Item_Stack, items: Item_Registry, result: ^Slot_Grid_Result) {
	interaction := ui_item_slot(state, rectangle, ui_id(state, "slot", index), slots[index], items)
	if interaction.activated {
		result.activated = index
	}
	if interaction.focused {
		result.focused = index
	}
}

// Input, progress, output on the first row; fuel, the burn bar and the
// byproduct slot under the output on the second; the transfer buttons and
// the state below.
furnace_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, furnace: Furnace, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	slots, items := furnace.slots, screen_context.items
	machine := screen_context.machines.machines[furnace.machine]
	recipes := screen_context.recipes
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	bar_width := bar_between_slots_width(area.width)
	machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_INPUT_SLOT, slots[:], items, &result.grid)
	progress_row := Ui_Rectangle{first.x + UI_SLOT_SIZE + UI_GAP, first.y, bar_width, UI_SLOT_SIZE}
	machine_bar(state, progress_row, furnace_progress_fraction(furnace, machine, recipes, screen_context.tick_rate))
	output := Ui_Rectangle{progress_row.x + bar_width + UI_GAP, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}
	machine_slot(state, output, FURNACE_OUTPUT_SLOT, slots[:], items, &result.grid)
	second := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	machine_slot(state, {second.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_FUEL_SLOT, slots[:], items, &result.grid)
	machine_bar(state, {second.x + UI_SLOT_SIZE + UI_GAP, second.y, bar_width, UI_SLOT_SIZE}, furnace_burn_fraction(furnace))
	machine_slot(state, {output.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_BYPRODUCT_SLOT, slots[:], items, &result.grid)
	result.transfer = transfer_button_rows(state, &content, machine)
	detail_line(state, &content, text(furnace_state_keys[furnace.state]), UI_DIM_TEXT_COLOR)
	output_rate_label(state, &content, furnace.output_rate, screen_context)
	return result
}

// The rate readout of a machine panel: its main output over the last
// minute, from the machine's own ring (statistics.odin).
output_rate_line :: proc(rate: Machine_Output_Rate, second: u64) -> string {
	return fmt.tprintf("%s: %s", text("machine_output_rate"), format_per_minute(f32(machine_output_per_minute(rate, second))))
}

output_rate_label :: proc(state: ^Ui_State, content: ^Ui_Rectangle, rate: Machine_Output_Rate, screen_context: Screen_Context) {
	detail_line(state, content, output_rate_line(rate, screen_context.records.statistics.current_second))
}

// The fuel slot and burn bar of a burner, or the filter slot of a filter
// inserter, on the first row; the hand slot on the second, always drawn
// so the layout does not jump; a burner's Fill button, the cycle bar and
// the state below.
inserter_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, inserter: Inserter, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	machine := screen_context.machines.machines[inserter.machine]
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	slot := Ui_Rectangle{first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}
	slots := inserter.slots
	if inserter.slot_count > 0 {
		machine_slot(state, slot, INSERTER_FUEL_SLOT, slots[:inserter.slot_count], screen_context.items, &result.grid)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, inserter_burn_fraction(inserter))
	} else if inserter_has_filter(machine) {
		shown := inserter.filter == NO_ITEM ? EMPTY_STACK : Item_Stack{item = inserter.filter, count = 1}
		interaction := ui_item_slot(state, slot, ui_id(state, "filter", 0), shown, screen_context.items)
		result.filter_activated, result.filter_focused, result.filter_shown = interaction.activated, interaction.focused, true
		draw_text_fitted(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, text("inserter_filter"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	second := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	hand := ui_item_slot(state, {second.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, ui_id(state, "hand", 0), inserter.held, screen_context.items)
	result.hand_activated, result.hand_focused = hand.activated, hand.focused
	draw_text_fitted(state, {second.x + UI_SLOT_SIZE + UI_GAP, second.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, text("inserter_hand"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	result.transfer = transfer_button_rows(state, &content, machine)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), inserter_cycle_fraction(inserter, machine, screen_context.tick_rate))
	detail_line(state, &content, inserter_state_text(inserter, screen_context.items), UI_DIM_TEXT_COLOR)
	if inserter_is_electric(machine) {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, inserter.handle)
		detail_line(state, &content, power_line, UI_DIM_TEXT_COLOR)
	}
	return result
}

// A bore drill's depth line, and a level and a flow line per fluid port
// (the revival port).
drill_extra_rows :: proc(machine: Machine) -> int {
	return (drill_is_bore(machine) ? 1 : 0) + FLUID_ROWS_PER_BUFFER * machine.fluid_port_count
}

// The fuel slot and burn bar (or the power line of an electric drill) on
// the first row, a burner's Fill button, the cycle bar (the boring bar
// while a bore drill bores),
// then the vein's lines, a bore drill's depth, the revival port, the rate
// (halved while revived) and the state.
drill_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, drill: Drill, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	machine := screen_context.machines.machines[drill.machine]
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	if drill_is_electric(drill) {
		draw_text_fitted(state, first, power_status_line(&screen_context.world.entities.electric_networks, drill.handle), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	} else {
		slots := drill.slots
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, DRILL_FUEL_SLOT, slots[:], screen_context.items, &result.grid)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, drill_burn_fraction(drill))
	}
	result.transfer = transfer_button_rows(state, &content, machine)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), drill_progress_fraction(drill, machine, screen_context.tick_rate))
	for line in drill_vein_lines(screen_context.world, screen_context.veins, screen_context.items, drill) {
		detail_line(state, &content, line)
	}
	if drill_is_bore(machine) {
		detail_line(state, &content, drill_depth_line(screen_context.world, drill))
	}
	for port, index in fluid_ports_of(machine) {
		fluid_buffer_rows(state, &content, screen_context.fluids, drill.buffers[index], port.filter, port.capacity, drill.closed[index], screen_context.tick_rate)
	}
	units := drill_units_per_minute(machine, screen_context.tick_rate, drill.state == .Revived)
	rate := fmt.tprintf("%s: %s", text("drill_rate"), format_per_minute(units))
	detail_line(state, &content, rate)
	output_rate_label(state, &content, drill.output_rate, screen_context)
	detail_line(state, &content, drill_state_text(drill, screen_context.items), UI_DIM_TEXT_COLOR)
	return result
}

// The input and output priority toggles, the filter slot and the side the
// filter item goes to. The toggles queue their new values for the tick
// (Splitter_Priorities_Command, Splitter_Side_Command).
splitter_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, splitter: ^Splitter, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	content := area
	priorities := Splitter_Priorities_Command{splitter = splitter.handle, input = splitter.input_priority, output = splitter.output_priority}
	if ui_choice(state, cut_row(&content), text("splitter_input_priority"), text(splitter_priority_keys[splitter.input_priority])) {
		priorities.input = next_splitter_priority(splitter.input_priority)
	}
	if ui_choice(state, cut_row(&content), text("splitter_output_priority"), text(splitter_priority_keys[splitter.output_priority])) {
		priorities.output = next_splitter_priority(splitter.output_priority)
	}
	if priorities.input != splitter.input_priority || priorities.output != splitter.output_priority {
		queue_player_command(screen_context.player_commands, screen_context.player_index, priorities)
	}
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	shown := splitter.filter == NO_ITEM ? EMPTY_STACK : Item_Stack{item = splitter.filter, count = 1}
	interaction := ui_item_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, ui_id(state, "filter", 0), shown, screen_context.items)
	result.filter_activated, result.filter_focused, result.filter_shown = interaction.activated, interaction.focused, true
	draw_text_fitted(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, text("inserter_filter"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if ui_choice(state, cut_row(&content), text("splitter_filter_side"), text(splitter_side_keys[splitter.filter_side])) {
		queue_player_command(screen_context.player_commands, screen_context.player_index, Splitter_Side_Command{splitter = splitter.handle, side = other_side(splitter.filter_side)})
	}
	return result
}

// The vein type's name, then what is left of each output, or one line
// saying the vein is infinite. Empty for a drill without a vein.
drill_vein_lines :: proc(world: ^World, veins: Vein_Content, items: Item_Registry, drill: Drill) -> []string {
	lines := make([dynamic]string, context.temp_allocator)
	vein := registered_vein(world, drill.vein)
	if vein == nil || vein.type >= len(veins.types) {
		return lines[:]
	}
	vein_type := veins.types[vein.type]
	append(&lines, text(vein_type.name_key))
	if world.settings.veins_infinite {
		append(&lines, text("drill_infinite"))
		return lines[:]
	}
	for index in 0 ..< vein_type.output_count {
		name := item_name(items, vein_type.outputs[index])
		append(&lines, fmt.tprintf("%s: %d %s", name, vein.remaining[index], text("drill_remaining")))
	}
	return lines[:]
}

// "Depth: 64 blocks", how far below the surface the tapped vein's centre
// lies.
drill_depth_line :: proc(world: ^World, drill: Drill) -> string {
	vein := registered_vein(world, drill.vein)
	depth := vein == nil ? 0 : vein.depth
	return fmt.tprintf("%s: %d %s", text("drill_depth"), depth, text("drill_blocks"))
}

// A with a stack held copies its item into the filter and the stack stays
// held (a ghost); the context action clears it.
inserter_filter_after_input :: proc(filter: Item_Id, held: Item_Stack, activated, clear: bool) -> Item_Id {
	if clear {
		return NO_ITEM
	}
	if activated && !stack_is_empty(held) {
		return held.item
	}
	return filter
}

// A or a drag with nothing on the cursor lifts the inserter's hand onto
// it. The hand takes nothing in: a stack on the cursor stays there.
inserter_hand_after_input :: proc(hand: Item_Stack, held: Held_Stack, activated: bool) -> (Item_Stack, Held_Stack) {
	if !activated || !stack_is_empty(held.stack) || stack_is_empty(hand) {
		return hand, held
	}
	return EMPTY_STACK, Held_Stack{stack = hand, origin_slot = MACHINE_SLOT_ORIGIN}
}

// The machine's name and slots. Results are indices into the machine's slots.
// The machine's description wrapped to the machine side (work item
// 0070), dim under its name. The side scrolls, so it always has room.
machine_description_lines :: proc(state: ^Ui_State, machines: Machine_Registry, machine: Machine_Id, width: f32) -> []string {
	return wrap_text(state, machine_description(machines, machine), UI_BODY_TEXT_SIZE, width)
}

machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, slots: []Item_Stack, screen_context: Screen_Context) -> Machine_Slot_Result {
	content := area
	common := entity_common(&screen_context.world.entities, handle)
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), machine_name(screen_context.machines, common.machine), UI_HEADING_TEXT_SIZE, .Left)
	for line in machine_description_lines(state, screen_context.machines, common.machine, content.width) {
		ui_label(state, cut_top(&content, UI_LINE_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	ui_push_id(state, "machine_slots")
	defer ui_pop_id(state)
	#partial switch handle.kind {
	case .Furnace:
		return furnace_slot_region(state, content, pool_get(&screen_context.world.entities.furnaces, handle)^, screen_context)
	case .Inserter:
		return inserter_slot_region(state, content, pool_get(&screen_context.world.entities.inserters, handle)^, screen_context)
	case .Drill:
		return drill_slot_region(state, content, pool_get(&screen_context.world.entities.drills, handle)^, screen_context)
	case .Splitter:
		return splitter_slot_region(state, content, pool_get(&screen_context.world.entities.splitters, handle), screen_context)
	case .Pipe:
		pipe_panel_region(state, content, pool_get(&screen_context.world.entities.pipes, handle)^, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Fluid_Machine:
		return fluid_machine_slot_region(state, content, pool_get(&screen_context.world.entities.fluid_machines, handle)^, screen_context)
	case .Pole, .Lamp:
		power_panel_region(state, content, handle, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Assembler:
		return assembler_slot_region(state, content, pool_get(&screen_context.world.entities.assemblers, handle)^, screen_context)
	case .Lab:
		return lab_slot_region(state, content, pool_get(&screen_context.world.entities.labs, handle)^, screen_context)
	case .Core_Sample_Drill:
		core_sample_panel_region(state, content, pool_get(&screen_context.world.entities.core_sample_drills, handle)^, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Launch_Pad:
		return {grid = launch_pad_slot_region(state, content, pool_get(&screen_context.world.entities.launch_pads, handle), screen_context)}
	}
	// A chest or the capsule: the slots, then Take all and Store all.
	columns := chest_columns(content.width)
	grid := cut_top(&content, slot_rows_height(len(slots), columns))
	result := Machine_Slot_Result {
		grid = ui_slot_grid(state, {grid.x, grid.y}, "chest", columns, slots, screen_context.items),
	}
	result.transfer = transfer_button_rows(state, &content, screen_context.machines.machines[common.machine])
	return result
}

machine_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	player, items := screen_context.player, screen_context.items
	handle := player.open_machine
	common := entity_common(&screen_context.world.entities, handle)
	if common == nil {
		pop_screen(&state.screens)
		return
	}
	machine := screen_context.machines.machines[common.machine]
	slots := entity_slots(&screen_context.world.entities, handle)
	// Q is also Tab_Previous; while it quick moves it does not turn the
	// launch pad's tabs.
	if state.input.quick_move {
		state.input.tab_previous = false
	}
	ui_backdrop(state)
	// The machine side gets what the player's slots leave of the safe
	// area's width, wraps its slots to it, and scrolls when the panel is
	// clamped to the safe area's height.
	safe := ui_panel_area(state)
	player_width := slot_grid_width(INVENTORY_COLUMNS)
	machine_width := max(min(machine_area_width(machine), safe.width - player_width - 4 * UI_PADDING), UI_SLOT_SIZE)
	description_height := f32(len(machine_description_lines(state, screen_context.machines, common.machine, machine_width))) * UI_LINE_HEIGHT
	machine_height := machine_area_height(machine, len(slots), machine_width) + transfer_rows_height(machine, machine_width) + description_height
	height := max(inventory_panel_height(), machine_height + 2 * UI_PADDING)
	panel := fitted_panel(safe, player_width + machine_width + 4 * UI_PADDING, height)
	ui_panel_begin(state, "machine", panel)
	ui_prefer_focus(state, selected_hotbar_slot_id(state, player))
	content := inset(panel, UI_PADDING)
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Left)
	player_slots := player_slot_region(state, {content.x, content.y, player_width, content.height}, player, items)
	machine_view := Ui_Rectangle{panel.x + UI_PADDING + player_width + 2 * UI_PADDING, panel.y + UI_PADDING, machine_width, panel.height - 2 * UI_PADDING}
	region, machine_area := scroll_region_begin(state, "machine_area", machine_view, machine_height)
	machine_slots := machine_slot_region(state, machine_area, handle, slots, screen_context)
	scroll_region_end(state, region)
	ui_panel_end(state)
	touch := touch_row_shows(state)
	// Laid out for the row with Clear filter on every panel, so Sort and
	// the others keep their places whether it shows or not.
	button := touch ? ui_touch_row(state, machine_touch_buttons(machine_slots.filter_shown), machine_touch_buttons(true)) : .None
	player_slots.activated, machine_slots.activated, machine_slots.hand_activated = apply_quick_move_input(state, screen_context, handle, slots, player_slots, machine_slots)
	state.active_slot = active_slot_after_focus(state.active_slot, player_slots.focused, machine_slots.focused)
	apply_machine_screen_input(state, screen_context, handle, machine.kind, slots, player_slots, machine_slots)
	// Not during the Even Distribution gesture, as the slot input.
	if !state.distribute.active {
		apply_machine_slot_button(screen_context, handle, machine.kind, slots, state.active_slot, button)
	}
	apply_transfer_button(&screen_context.world.entities, statistics_simulation_content(screen_context), handle, player.inventory, machine_slots.transfer)
	if inserter := pool_get(&screen_context.world.entities.inserters, handle); inserter != nil {
		clear_filter := (machine_slots.filter_focused && state.input.context_action) || button == .Clear_Filter
		queue_filter_change(screen_context, handle, inserter.filter, inserter_filter_after_input(inserter.filter, player.held.stack, machine_slots.filter_activated, clear_filter))
		inserter.held, player.held = inserter_hand_after_input(inserter.held, player.held, machine_slots.hand_activated)
	}
	if splitter := pool_get(&screen_context.world.entities.splitters, handle); splitter != nil {
		clear_filter := (machine_slots.filter_focused && state.input.context_action) || button == .Clear_Filter
		queue_filter_change(screen_context, handle, splitter.filter, inserter_filter_after_input(splitter.filter, player.held.stack, machine_slots.filter_activated, clear_filter))
	}
	player.held = finish_slot_drag(state, player.inventory, player.held, items)
	draw_held_stack(state, player.held.stack, items)
	if touch {
		return
	}
	if machine_slots.filter_focused {
		filter_glyph_bar(state)
		return
	}
	focused := focused_stack(player.inventory.slots, player_slots.focused, slots, machine_slots.focused)
	if inserter := pool_get(&screen_context.world.entities.inserters, handle); inserter != nil && machine_slots.hand_focused {
		focused = inserter.held
	}
	machine_glyph_bar(state, player.held.stack, focused)
}

// A filter the panel changed goes to the tick (Machine_Filter_Command).
queue_filter_change :: proc(screen_context: Screen_Context, handle: Entity_Handle, current, wanted: Item_Id) {
	if wanted != current {
		queue_player_command(screen_context.player_commands, screen_context.player_index, Machine_Filter_Command{machine = handle, filter = wanted})
	}
}

// The quick move (quick_transfer.odin): R2 or Q on a slot, or Left
// Control with a click on it (advance_slot_drag focuses the pressed
// slot). Its press takes the slot's activation, since R2 is Confirm too,
// so the stack is not also picked up; returns the activations left for
// the ordinary slot input. On an inserter's hand slot it moves the hand
// into the inventory.
apply_quick_move_input :: proc(state: ^Ui_State, screen_context: Screen_Context, handle: Entity_Handle, slots: []Item_Stack, player_slots: Slot_Grid_Result, machine_slots: Machine_Slot_Result) -> (player_activated, machine_activated: int, hand_activated: bool) {
	input := state.input
	modifier_click := input.quick_move_modifier && state.click
	target, found := quick_move_target(player_slots, machine_slots.grid)
	on_hand := quick_move_targets_hand(machine_slots, found)
	found = found && !on_hand
	stack := EMPTY_STACK
	if found {
		stack = target.side == .Machine ? slots[target.slot] : screen_context.player.inventory.slots[target.slot]
	}
	quick_input := Quick_Move_Input {
		panel   = handle,
		pressed = input.quick_move || modifier_click,
		down    = input.quick_move_down || (input.quick_move_modifier && state.pointer_held),
		seconds = state.frame_seconds,
		found   = found,
		target  = target,
		stack   = stack,
	}
	step: Quick_Move_Step
	state.quick_move, step = advance_quick_move(state.quick_move, quick_input)
	apply_quick_move(&screen_context.world.entities, statistics_simulation_content(screen_context), handle, screen_context.player.inventory, step)
	if quick_input.pressed && on_hand {
		take_inserter_hand(&screen_context.world.entities, screen_context.items, handle, screen_context.player.inventory)
	}
	if quick_input.pressed {
		return -1, -1, false
	}
	return player_slots.activated, machine_slots.activated, machine_slots.hand_activated
}

// The machine panels' touch row (0125, 0137): the slot buttons on the
// active grid and, on a panel with a filter slot, Clear filter, as X on
// the filter slot. It shows on such a panel whatever holds the focus,
// since a tap on the button takes the focus off the filter slot.
machine_touch_buttons :: proc(filter_shown: bool) -> Touch_Buttons {
	buttons := Touch_Buttons{.Sort, .Split, .Transfer_All, .Transfer_All_Of_Type, .Back}
	return filter_shown ? buttons + {.Clear_Filter} : buttons
}

filter_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint{{.Confirm, text("hint_set_filter")}, {.Context_Action, text("hint_clear_filter")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}

apply_machine_screen_input :: proc(state: ^Ui_State, screen_context: Screen_Context, handle: Entity_Handle, kind: Machine_Kind, slots: []Item_Stack, player_slots: Slot_Grid_Result, machine_slots: Machine_Slot_Result) {
	player, items := screen_context.player, screen_context.items
	recipes := screen_context.recipes
	input := state.input
	// X sorts the active grid alone, the main grid from the hotbar
	// (sort_target_grid, 0125); on a filter slot it clears the filter.
	sorts := input.context_action && !machine_slots.filter_focused
	if !state.distribute.active {
		player_input := Inventory_Slot_Input {
			activated      = player_slots.activated,
			focused        = player_slots.focused,
			secondary      = input.secondary,
			context_action = sorts && sort_target_grid(state.active_slot.grid) == .Main,
		}
		player.held = apply_inventory_slot_input(player.inventory, player.held, player_input, items, screen_context.item_sort_ranks)
	}
	machine_input := Machine_Slot_Input {
		activated      = machine_slots.activated,
		focused        = machine_slots.focused,
		confirm_down   = input.confirm_down || state.pointer_held,
		secondary      = input.secondary,
		context_action = sorts && sort_target_grid(state.active_slot.grid) == .Machine,
	}
	filters := open_machine_slot_filters(screen_context, handle, kind, len(slots))
	player.held = apply_machine_slot_input(&state.distribute, slots, filters, player.held, machine_input, items, recipes)
	player.held = apply_machine_slot_secondary(slots, kind, player.held, machine_input, items, screen_context.item_sort_ranks)
}

// The touch row's slot button (0125) on the active grid: Sort and Split as X
// and L2 on the active slot, the transfers into the grid the panel pairs
// it with (transfer_target_grid).
apply_machine_slot_button :: proc(screen_context: Screen_Context, handle: Entity_Handle, kind: Machine_Kind, slots: []Item_Stack, active: Active_Slot, button: Touch_Button) {
	player, items, ranks := screen_context.player, screen_context.items, screen_context.item_sort_ranks
	player.held = apply_player_slot_button(player.inventory, player.held, active, button, items, ranks)
	if active.grid == .Machine && active.index < len(slots) {
		machine_input := Machine_Slot_Input {
			activated      = -1,
			focused        = active.index,
			secondary      = button == .Split,
			context_action = button == .Sort,
		}
		player.held = apply_machine_slot_secondary(slots, kind, player.held, machine_input, items, ranks)
	}
	transfer := slot_button_transfer(.Machine, active, active_slot_stack(player.inventory, slots, active), button)
	apply_grid_transfer(&screen_context.world.entities, statistics_simulation_content(screen_context), handle, player.inventory, transfer)
}

focused_stack :: proc(player_slots: []Item_Stack, player_focused: int, machine_slots: []Item_Stack, machine_focused: int) -> Item_Stack {
	switch {
	case player_focused >= 0:
		return player_slots[player_focused]
	case machine_focused >= 0:
		return machine_slots[machine_focused]
	}
	return EMPTY_STACK
}

machine_glyph_bar :: proc(state: ^Ui_State, held, focused: Item_Stack) {
	if !stack_is_empty(held) {
		hints := [?]Glyph_Hint{{.Confirm, text("hint_place_or_spread")}, {.Back, text("hint_close")}}
		ui_glyph_bar(state, hints[:])
		return
	}
	inventory_glyph_bar(state, held, focused, quick_move = true)
}
