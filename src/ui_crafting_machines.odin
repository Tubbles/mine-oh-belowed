package game

import "core:fmt"

// The crafting machine and lab panels inside the machine panel
// (ui_machine.odin). Crafting machine: the recipe, with a button that
// opens the recipe browser in its selection mode when the player chooses
// it, the fuel slot and burn bar of a fuel burner, the input slots, the
// progress bar, the output slots, the transfer buttons (Take all, and
// Fill for a fuel burner), a level and a flow line per fluid port, the
// output rate over the last minute, the state and the power line of an
// electric one. Lab: the pack slots, the Fill button, the unit's
// progress bar, the queued technology with its progress, a button to the
// technology screen, the state and the power line.

CRAFTING_MACHINE_SLOT_COLUMNS :: 6
CRAFTING_MACHINE_AREA_WIDTH :: CRAFTING_MACHINE_SLOT_COLUMNS * (UI_SLOT_SIZE + UI_GAP)

crafting_machine_area_width :: proc(machine: Machine) -> f32 {
	if machine.kind == .Crafting_Machine && machine.fluid_port_count > 0 {
		return max(CRAFTING_MACHINE_AREA_WIDTH, FLUID_AREA_WIDTH)
	}
	return CRAFTING_MACHINE_AREA_WIDTH
}

// The height at a width, whose slot rows wrap (slot_rows_height). A
// machine that chooses its recipe is sized for a full row of inputs and
// one of outputs.
crafting_machine_area_height :: proc(machine: Machine, slot_count: int, width: f32) -> f32 {
	columns := slot_columns(width)
	if machine.kind == .Crafting_Machine {
		// Name, recipe row, fuel, inputs, bar, outputs, fluid rows, output
		// rate, state, power.
		fuel_rows := f32(min(machine.slot_count, 1)) * (UI_SLOT_SIZE + UI_GAP)
		fixed := machine.recipe_choice == .Fixed
		inputs := slot_rows_height(fixed ? machine.input_slot_count : CRAFTING_MACHINE_SLOT_COLUMNS, columns)
		outputs := slot_rows_height(fixed ? machine.output_slot_count : CRAFTING_MACHINE_SLOT_COLUMNS, columns)
		text_rows := f32(3 + FLUID_ROWS_PER_BUFFER * machine.fluid_port_count)
		if crafting_machine_is_electric(machine) {
			text_rows += 1
		}
		return 2 * (UI_ROW_HEIGHT + UI_GAP) + fuel_rows + inputs + outputs + text_rows * UI_ROW_HEIGHT
	}
	// Name, slots, bar, technology, progress, button, state, power.
	return UI_ROW_HEIGHT + slot_rows_height(slot_count, columns) + 4 * UI_ROW_HEIGHT + (UI_ROW_HEIGHT + UI_GAP) + UI_ROW_HEIGHT
}

// The machine slots from first to first + count, in rows taken off the
// top of the content, as many per row as its width holds.
machine_slot_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, first, count: int, slots: []Item_Stack, items: Item_Registry, result: ^Slot_Grid_Result) {
	columns := slot_columns(content.width)
	area := cut_top(content, slot_rows_height(count, columns))
	for index in 0 ..< count {
		machine_slot(state, slot_grid_rectangle({area.x, area.y}, columns, index), first + index, slots, items, result)
	}
}

assembler_recipe_text :: proc(assembler: Assembler, screen_context: Screen_Context) -> string {
	if assembler.recipe == NO_RECIPE && screen_context.machines.machines[assembler.machine].recipe_choice == .Fixed {
		return text("assembler_recipe_from_inputs")
	}
	if assembler.recipe == NO_RECIPE {
		return text("assembler_recipe_none")
	}
	return screen_context.recipe_names[assembler.recipe]
}

// A button for a chosen recipe, a plain line for a fixed one.
assembler_recipe_row :: proc(state: ^Ui_State, content: ^Ui_Rectangle, assembler: Assembler, machine: Machine, screen_context: Screen_Context) {
	recipe_row := choice_row(content)
	if machine.recipe_choice == .Fixed {
		draw_text_fitted(state, recipe_row, fmt.tprintf("%s: %s", text("assembler_recipe"), assembler_recipe_text(assembler, screen_context)), UI_BODY_TEXT_SIZE, .Left)
		return
	}
	if ui_button(state, recipe_row, fmt.tprintf("%s: %s", text("assembler_choose_recipe"), assembler_recipe_text(assembler, screen_context))) {
		open_recipe_selection(state, screen_context.browser, assembler.handle)
	}
}

assembler_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, assembler: Assembler, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	machine := screen_context.machines.machines[assembler.machine]
	slots := assembler.slots
	content := area
	assembler_recipe_row(state, &content, assembler, machine, screen_context)
	if assembler.fuel_count > 0 {
		first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, 0, slots[:], screen_context.items, &result.grid)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, assembler_burn_fraction(assembler))
	}
	first_input, first_output := assembler_first_input(assembler), assembler_first_output(assembler)
	machine_slot_rows(state, &content, first_input, assembler.input_count, slots[:], screen_context.items, &result.grid)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), assembler_progress_fraction(assembler, machine, screen_context.recipes, screen_context.tick_rate))
	machine_slot_rows(state, &content, first_output, assembler.output_count, slots[:], screen_context.items, &result.grid)
	result.transfer = transfer_button_rows(state, &content, machine)
	for port, index in fluid_ports_of(machine) {
		fluid_buffer_rows(state, &content, screen_context.fluids, assembler.buffers[index], port.filter, port.capacity, assembler.closed[index], screen_context.tick_rate)
	}
	output_rate_label(state, &content, assembler.output_rate, screen_context)
	detail_line(state, &content, text(assembler_state_keys[assembler.state]), UI_DIM_TEXT_COLOR)
	if crafting_machine_is_electric(machine) {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, assembler.handle)
		detail_line(state, &content, power_line, UI_DIM_TEXT_COLOR)
	}
	return result
}

lab_research_text :: proc(research: Research_State, technologies: Technology_Registry) -> string {
	if !research.queued {
		return text("lab_research_none")
	}
	return fmt.tprintf("%s  %s", technology_name(technologies, research.technology), research_progress_text(research, technologies))
}

lab_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, lab: Lab, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	machine := screen_context.machines.machines[lab.machine]
	research := screen_context.world.research
	slots := lab.slots
	content := area
	machine_slot_rows(state, &content, 0, lab.slot_count, slots[:], screen_context.items, &result.grid)
	result.transfer = transfer_button_rows(state, &content, machine)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), lab_progress_fraction(lab, machine, research, screen_context.technologies, screen_context.tick_rate))
	detail_line(state, &content, lab_research_text(research, screen_context.technologies))
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), research_progress_fraction(research, screen_context.technologies))
	if ui_button(state, choice_row(&content), text("lab_open_technologies")) {
		push_screen(&state.screens, .Technologies)
	}
	detail_line(state, &content, text(lab_state_keys[lab.state]), UI_DIM_TEXT_COLOR)
	power_line := power_status_line(&screen_context.world.entities.electric_networks, lab.handle)
	detail_line(state, &content, power_line, UI_DIM_TEXT_COLOR)
	return result
}

// The slot rules of the open machine for the player's drops.
open_machine_slot_filters :: proc(screen_context: Screen_Context, handle: Entity_Handle, kind: Machine_Kind, slot_count: int) -> []Slot_Filter {
	#partial switch handle.kind {
	case .Assembler:
		assembler := pool_get(&screen_context.world.entities.assemblers, handle)
		return assembler_slot_filters(assembler^, screen_context.machines.machines[assembler.machine], screen_context.recipes)
	case .Lab:
		return lab_slot_filters(screen_context.machines.lab_packs, slot_count)
	case .Launch_Pad:
		pad := pool_get(&screen_context.world.entities.launch_pads, handle)
		return launch_pad_slot_filters(pad^, screen_context.machines.machines[pad.machine])
	}
	return machine_slot_filters(kind, slot_count)
}
