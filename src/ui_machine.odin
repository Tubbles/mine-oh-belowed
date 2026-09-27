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
// or a splitter, which is not one of the slots.
Machine_Slot_Result :: struct {
	using grid:       Slot_Grid_Result,
	filter_activated: bool,
	filter_focused:   bool,
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

chest_rows :: proc(slot_count: int) -> int {
	return (slot_count + MACHINE_CHEST_COLUMNS - 1) / MACHINE_CHEST_COLUMNS
}

machine_area_size :: proc(machine: Machine, slot_count: int) -> [2]f32 {
	switch machine.kind {
	case .Chest, .Capsule:
		return {slot_grid_width(MACHINE_CHEST_COLUMNS), UI_ROW_HEIGHT + slot_grid_height(chest_rows(slot_count))}
	case .Furnace:
		return {FURNACE_AREA_WIDTH, UI_ROW_HEIGHT + 2 * (UI_SLOT_SIZE + UI_GAP) + 2 * UI_ROW_HEIGHT}
	case .Inserter:
		return {FURNACE_AREA_WIDTH, UI_ROW_HEIGHT + (UI_SLOT_SIZE + UI_GAP) + 3 * UI_ROW_HEIGHT}
	case .Drill:
		rows := 1 + DRILL_TEXT_ROWS + drill_extra_rows(machine)
		return {DRILL_AREA_WIDTH, UI_ROW_HEIGHT + (UI_SLOT_SIZE + UI_GAP) + f32(rows) * UI_ROW_HEIGHT}
	case .Splitter:
		return {SPLITTER_AREA_WIDTH, UI_ROW_HEIGHT + SPLITTER_CHOICE_ROWS * (UI_ROW_HEIGHT + UI_GAP) + (UI_SLOT_SIZE + UI_GAP)}
	case .Pipe, .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump, .Tar_Pit_Pump, .Flare_Stack, .Combustion_Generator, .Hydro_Turbine:
		return fluid_area_size(machine)
	case .Pole, .Power_Switch, .Lamp:
		return power_area_size(machine)
	case .Crafting_Machine, .Lab:
		return crafting_machine_area_size(machine)
	case .Core_Sample_Drill:
		return core_sample_area_size()
	case .Launch_Pad:
		return launch_pad_area_size(machine)
	case .Belt, .Schematic_Crate:
	}
	return {}
}

// A bar with its label to the right, vertically centred on the row.
machine_bar :: proc(state: ^Ui_State, row: Ui_Rectangle, fraction: f32) {
	bar := Ui_Rectangle{row.x, row.y + (row.height - MACHINE_BAR_HEIGHT) / 2, MACHINE_BAR_WIDTH, MACHINE_BAR_HEIGHT}
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
// byproduct slot under the output on the second; the state below.
furnace_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, furnace: Furnace, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	slots, items := furnace.slots, screen_context.items
	machine := screen_context.machines.machines[furnace.machine]
	recipes := screen_context.recipes
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_INPUT_SLOT, slots[:], items, &result)
	progress_row := Ui_Rectangle{first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}
	machine_bar(state, progress_row, furnace_progress_fraction(furnace, machine, recipes, screen_context.tick_rate))
	output := Ui_Rectangle{progress_row.x + MACHINE_BAR_WIDTH + UI_GAP, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}
	machine_slot(state, output, FURNACE_OUTPUT_SLOT, slots[:], items, &result)
	second := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	machine_slot(state, {second.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_FUEL_SLOT, slots[:], items, &result)
	machine_bar(state, {second.x + UI_SLOT_SIZE + UI_GAP, second.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, furnace_burn_fraction(furnace))
	machine_slot(state, {output.x, second.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, FURNACE_BYPRODUCT_SLOT, slots[:], items, &result)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(furnace_state_keys[furnace.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	output_rate_label(state, &content, furnace.output_rate, screen_context)
	return result
}

// The rate readout of a machine panel: its main output over the last
// minute, from the machine's own ring (statistics.odin).
output_rate_line :: proc(rate: Machine_Output_Rate, second: u64) -> string {
	return fmt.tprintf("%s: %s", text("machine_output_rate"), format_per_minute(f32(machine_output_per_minute(rate, second))))
}

output_rate_label :: proc(state: ^Ui_State, content: ^Ui_Rectangle, rate: Machine_Output_Rate, screen_context: Screen_Context) {
	ui_label(state, cut_top(content, UI_ROW_HEIGHT), output_rate_line(rate, screen_context.world.statistics.current_second), UI_BODY_TEXT_SIZE, .Left)
}

// The fuel slot and burn bar of a burner, or the filter slot of a filter
// inserter, on the first row; the cycle bar and the state below.
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
		result.filter_activated, result.filter_focused = interaction.activated, interaction.focused
		ui_label(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, text("inserter_filter"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), inserter_cycle_fraction(inserter, machine, screen_context.tick_rate))
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(inserter_state_keys[inserter.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if inserter_is_electric(machine) {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, inserter.handle)
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), power_line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	return result
}

// A bore drill's depth line, and a level and a flow line per fluid port
// (the revival port).
drill_extra_rows :: proc(machine: Machine) -> int {
	return (drill_is_bore(machine) ? 1 : 0) + FLUID_ROWS_PER_BUFFER * machine.fluid_port_count
}

// The fuel slot and burn bar (or the power line of an electric drill) on
// the first row, the cycle bar (the boring bar while a bore drill bores),
// then the vein's lines, a bore drill's depth, the revival port, the rate
// (halved while revived) and the state.
drill_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, drill: Drill, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	machine := screen_context.machines.machines[drill.machine]
	content := area
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	if drill_is_electric(drill) {
		ui_label(state, first, power_status_line(&screen_context.world.entities.electric_networks, drill.handle), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	} else {
		slots := drill.slots
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, DRILL_FUEL_SLOT, slots[:], screen_context.items, &result)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, drill_burn_fraction(drill))
	}
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), drill_progress_fraction(drill, machine, screen_context.tick_rate))
	for line in drill_vein_lines(screen_context.world, screen_context.veins, screen_context.items, drill) {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), line, UI_BODY_TEXT_SIZE, .Left)
	}
	if drill_is_bore(machine) {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), drill_depth_line(screen_context.world, drill), UI_BODY_TEXT_SIZE, .Left)
	}
	for port, index in fluid_ports_of(machine) {
		fluid_buffer_rows(state, &content, screen_context.fluids, drill.buffers[index], port.filter, port.capacity, drill.closed[index], screen_context.tick_rate)
	}
	units := drill_units_per_minute(machine, screen_context.tick_rate, drill.state == .Revived)
	rate := fmt.tprintf("%s: %s", text("drill_rate"), format_per_minute(units))
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), rate, UI_BODY_TEXT_SIZE, .Left)
	output_rate_label(state, &content, drill.output_rate, screen_context)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(drill_state_keys[drill.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	return result
}

choice_row :: proc(content: ^Ui_Rectangle) -> Ui_Rectangle {
	row := cut_top(content, UI_ROW_HEIGHT)
	cut_top(content, UI_GAP)
	return row
}

// The input and output priority toggles, the filter slot and the side the
// filter item goes to. The toggles change the splitter directly.
splitter_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, splitter: ^Splitter, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	content := area
	if ui_choice(state, choice_row(&content), text("splitter_input_priority"), text(splitter_priority_keys[splitter.input_priority])) {
		splitter.input_priority = next_splitter_priority(splitter.input_priority)
	}
	if ui_choice(state, choice_row(&content), text("splitter_output_priority"), text(splitter_priority_keys[splitter.output_priority])) {
		splitter.output_priority = next_splitter_priority(splitter.output_priority)
	}
	first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
	shown := splitter.filter == NO_ITEM ? EMPTY_STACK : Item_Stack{item = splitter.filter, count = 1}
	interaction := ui_item_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, ui_id(state, "filter", 0), shown, screen_context.items)
	result.filter_activated, result.filter_focused = interaction.activated, interaction.focused
	ui_label(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, text("inserter_filter"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if ui_choice(state, choice_row(&content), text("splitter_filter_side"), text(splitter_side_keys[splitter.filter_side])) {
		splitter.filter_side = other_side(splitter.filter_side)
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

// The vein's name and what is left of it in total, for the HUD.
vein_size_class_name :: proc(veins: Vein_Content, size_class: int) -> string {
	if size_class < 0 || size_class >= len(veins.size_class_ids) {
		return ""
	}
	return text(fmt.tprintf("vein_size_%s", veins.size_class_ids[size_class]))
}

vein_status_text :: proc(world: ^World, veins: Vein_Content, id: Vein_Id) -> string {
	vein := registered_vein(world, id)
	if vein == nil || vein.type >= len(veins.types) {
		return ""
	}
	name := text(veins.types[vein.type].name_key)
	if vein_is_assayed(world, id) {
		name = fmt.tprintf("%s  %s  %s", name, vein_size_class_name(veins, vein.size_class), text("vein_assayed"))
	}
	if world.settings.veins_infinite {
		return fmt.tprintf("%s  %s", name, text("drill_infinite"))
	}
	return fmt.tprintf("%s  %d %s", name, vein_remaining_total(vein^), text("drill_remaining"))
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

// The machine's name and slots. Results are indices into the machine's slots.
machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, slots: []Item_Stack, screen_context: Screen_Context) -> Machine_Slot_Result {
	content := area
	common := entity_common(&screen_context.world.entities, handle)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), machine_name(screen_context.machines, common.machine), UI_HEADING_TEXT_SIZE, .Left)
	ui_push_id(state, "machine_slots")
	defer ui_pop_id(state)
	#partial switch handle.kind {
	case .Furnace:
		return {grid = furnace_slot_region(state, content, pool_get(&screen_context.world.entities.furnaces, handle)^, screen_context)}
	case .Inserter:
		return inserter_slot_region(state, content, pool_get(&screen_context.world.entities.inserters, handle)^, screen_context)
	case .Drill:
		return {grid = drill_slot_region(state, content, pool_get(&screen_context.world.entities.drills, handle)^, screen_context)}
	case .Splitter:
		return splitter_slot_region(state, content, pool_get(&screen_context.world.entities.splitters, handle), screen_context)
	case .Pipe:
		pipe_panel_region(state, content, pool_get(&screen_context.world.entities.pipes, handle)^, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Fluid_Machine:
		return {grid = fluid_machine_slot_region(state, content, pool_get(&screen_context.world.entities.fluid_machines, handle)^, screen_context)}
	case .Pole, .Lamp:
		power_panel_region(state, content, handle, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Assembler:
		return {grid = assembler_slot_region(state, content, pool_get(&screen_context.world.entities.assemblers, handle)^, screen_context)}
	case .Lab:
		return {grid = lab_slot_region(state, content, pool_get(&screen_context.world.entities.labs, handle)^, screen_context)}
	case .Core_Sample_Drill:
		core_sample_panel_region(state, content, pool_get(&screen_context.world.entities.core_sample_drills, handle)^, screen_context)
		return {grid = {activated = -1, focused = -1}}
	case .Launch_Pad:
		return {grid = launch_pad_slot_region(state, content, pool_get(&screen_context.world.entities.launch_pads, handle), screen_context)}
	}
	return {grid = ui_slot_grid(state, {content.x, content.y}, "chest", MACHINE_CHEST_COLUMNS, slots, screen_context.items)}
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
	ui_backdrop(state)
	machine_size := machine_area_size(machine, len(slots))
	player_width := slot_grid_width(INVENTORY_COLUMNS)
	height := max(inventory_panel_height(), machine_size.y + 2 * UI_PADDING)
	panel := centred_rectangle(ui_safe_area(state), player_width + machine_size.x + 4 * UI_PADDING, height)
	ui_panel_begin(state, "machine", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("inventory_title"), UI_HEADING_TEXT_SIZE, .Left)
	player_slots := player_slot_region(state, {content.x, content.y, player_width, content.height}, player, items)
	machine_area := Ui_Rectangle{panel.x + UI_PADDING + player_width + 2 * UI_PADDING, panel.y + UI_PADDING, machine_size.x, machine_size.y}
	machine_slots := machine_slot_region(state, machine_area, handle, slots, screen_context)
	ui_panel_end(state)
	apply_machine_screen_input(state, screen_context, handle, machine.kind, slots, player_slots, machine_slots)
	if inserter := pool_get(&screen_context.world.entities.inserters, handle); inserter != nil {
		clear_filter := machine_slots.filter_focused && state.input.context_action
		inserter.filter = inserter_filter_after_input(inserter.filter, player.held.stack, machine_slots.filter_activated, clear_filter)
	}
	if splitter := pool_get(&screen_context.world.entities.splitters, handle); splitter != nil {
		clear_filter := machine_slots.filter_focused && state.input.context_action
		splitter.filter = inserter_filter_after_input(splitter.filter, player.held.stack, machine_slots.filter_activated, clear_filter)
	}
	draw_held_stack(state, player.held.stack, items)
	if machine_slots.filter_focused {
		filter_glyph_bar(state)
		return
	}
	machine_glyph_bar(state, player.held.stack, focused_stack(player.inventory.slots, player_slots.focused, slots, machine_slots.focused))
}

filter_glyph_bar :: proc(state: ^Ui_State) {
	hints := [?]Glyph_Hint{{.Confirm, text("hint_set_filter")}, {.Context_Action, text("hint_clear_filter")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}

apply_machine_screen_input :: proc(state: ^Ui_State, screen_context: Screen_Context, handle: Entity_Handle, kind: Machine_Kind, slots: []Item_Stack, player_slots: Slot_Grid_Result, machine_slots: Machine_Slot_Result) {
	player, items := screen_context.player, screen_context.items
	recipes := screen_context.recipes
	input := state.input
	if !state.distribute.active {
		player_input := Inventory_Slot_Input {
			activated      = player_slots.activated,
			focused        = player_slots.focused,
			secondary      = input.secondary,
			context_action = input.context_action && machine_slots.focused < 0 && !machine_slots.filter_focused,
		}
		player.held = apply_inventory_slot_input(player.inventory, player.held, player_input, items, screen_context.item_sort_ranks)
	}
	machine_input := Machine_Slot_Input {
		activated      = machine_slots.activated,
		focused        = machine_slots.focused,
		confirm_down   = input.confirm_down || state.pointer_held,
		secondary      = input.secondary,
		context_action = input.context_action,
	}
	filters := open_machine_slot_filters(screen_context, handle, kind, len(slots))
	player.held = apply_machine_slot_input(&state.distribute, slots, filters, player.held, machine_input, items, recipes)
	player.held = apply_machine_slot_secondary(slots, kind, player.held, machine_input, items, screen_context.item_sort_ranks)
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
	inventory_glyph_bar(state, held, focused)
}

// The name and state of an entity for the HUD, "" when it has none.
entity_status_text :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry, handle: Entity_Handle) -> string {
	common := entity_common(&world.entities, handle)
	if common == nil {
		return ""
	}
	name := machine_name(machines, common.machine)
	#partial switch handle.kind {
	case .Furnace:
		furnace := pool_get(&world.entities.furnaces, handle)
		return fmt.tprintf("%s  %s", name, text(furnace_state_keys[furnace.state]))
	case .Inserter:
		inserter := pool_get(&world.entities.inserters, handle)
		return fmt.tprintf("%s  %s", name, text(inserter_state_keys[inserter.state]))
	case .Drill:
		drill := pool_get(&world.entities.drills, handle)
		return fmt.tprintf("%s  %s", name, text(drill_state_keys[drill.state]))
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
		return fmt.tprintf("%s  %s", name, core_sample_state_text(world, pool_get(&world.entities.core_sample_drills, handle)^))
	case .Launch_Pad:
		return fmt.tprintf("%s  %s", name, launch_pad_state_text(pool_get(&world.entities.launch_pads, handle)))
	}
	return name
}

// While a bore drill is being placed, the HUD's vein line names the deep
// vein its ghost would tap, since nothing on the surface marks deep veins.
bore_drill_ghost_line :: proc(world: ^World, machines: Machine_Registry, veins: Vein_Content, player: Player) -> (line: string, shown: bool) {
	vein, found, selected := bore_drill_ghost_vein(world, machines, player)
	if !selected {
		return "", false
	}
	if !found {
		return text("bore_drill_no_deep_vein"), true
	}
	return vein_status_text(world, veins, vein), true
}

// What the HUD shows under the crosshair: the targeted entity's name and
// state, and for a drill or an outcrop block the vein and what is left.
target_status_lines :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry, veins: Vein_Content, target: Raycast_Hit) -> (entity_line, vein_line: string) {
	if drill := pool_get(&world.entities.drills, target.entity); drill != nil {
		return entity_status_text(world, machines, fluids, target.entity), vein_status_text(world, veins, drill.vein)
	}
	if target.entity != NO_ENTITY {
		return entity_status_text(world, machines, fluids, target.entity), ""
	}
	if !target.hit {
		return "", ""
	}
	if vein, found := outcrop_vein_at(world, veins, target.block); found {
		return "", vein_status_text(world, veins, vein)
	}
	return "", ""
}
