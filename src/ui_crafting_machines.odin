package game

import "core:fmt"

// The crafting machine and lab panels inside the machine panel
// (ui_machine.odin). Crafting machine: the recipe, with a button that
// opens the recipe browser in its selection mode when the player chooses
// it, the fuel slot and burn bar of a fuel burner, the input slots, the
// progress bar, the output slots, a level and a flow line per fluid port,
// the state and the power line of an electric one. Lab: the pack slots, the unit's
// progress bar, the queued technology with its progress, a button to the
// technology screen, the state and the power line.

CRAFTING_MACHINE_AREA_WIDTH :: 6 * (UI_SLOT_SIZE + UI_GAP)

crafting_machine_area_size :: proc(machine: Machine) -> [2]f32 {
	slot_row := f32(UI_SLOT_SIZE + UI_GAP)
	if machine.kind == .Crafting_Machine {
		// Name, recipe row, fuel, inputs, bar, outputs, fluid rows, state,
		// power.
		fuel_rows := f32(min(machine.slot_count, 1))
		text_rows := f32(2 + FLUID_ROWS_PER_BUFFER * machine.fluid_port_count)
		if crafting_machine_is_electric(machine) {
			text_rows += 1
		}
		width := f32(machine.fluid_port_count > 0 ? max(CRAFTING_MACHINE_AREA_WIDTH, FLUID_AREA_WIDTH) : CRAFTING_MACHINE_AREA_WIDTH)
		return {width, 2 * (UI_ROW_HEIGHT + UI_GAP) + (2 + fuel_rows) * slot_row + text_rows * UI_ROW_HEIGHT}
	}
	// Name, slots, bar, technology, progress, button, state, power.
	return {CRAFTING_MACHINE_AREA_WIDTH, UI_ROW_HEIGHT + slot_row + 4 * UI_ROW_HEIGHT + (UI_ROW_HEIGHT + UI_GAP) + UI_ROW_HEIGHT}
}

// A row of machine slots from first to first + count.
machine_slot_row :: proc(state: ^Ui_State, row: Ui_Rectangle, first, count: int, slots: []Item_Stack, items: Item_Registry, result: ^Slot_Grid_Result) {
	for index in 0 ..< count {
		x := row.x + f32(index) * (UI_SLOT_SIZE + UI_GAP)
		machine_slot(state, {x, row.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, first + index, slots, items, result)
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
		ui_label(state, recipe_row, fmt.tprintf("%s: %s", text("assembler_recipe"), assembler_recipe_text(assembler, screen_context)), UI_BODY_TEXT_SIZE, .Left)
		return
	}
	if ui_button(state, recipe_row, fmt.tprintf("%s: %s", text("assembler_choose_recipe"), assembler_recipe_text(assembler, screen_context))) {
		open_recipe_selection(state, screen_context.browser, assembler.handle)
	}
}

assembler_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, assembler: Assembler, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	machine := screen_context.machines.machines[assembler.machine]
	slots := assembler.slots
	content := area
	assembler_recipe_row(state, &content, assembler, machine, screen_context)
	if assembler.fuel_count > 0 {
		first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, 0, slots[:], screen_context.items, &result)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, assembler_burn_fraction(assembler))
	}
	first_input, first_output := assembler_first_input(assembler), assembler_first_output(assembler)
	machine_slot_row(state, cut_top(&content, UI_SLOT_SIZE + UI_GAP), first_input, assembler.input_count, slots[:], screen_context.items, &result)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), assembler_progress_fraction(assembler, machine, screen_context.recipes, screen_context.tick_rate))
	machine_slot_row(state, cut_top(&content, UI_SLOT_SIZE + UI_GAP), first_output, assembler.output_count, slots[:], screen_context.items, &result)
	for port, index in fluid_ports_of(machine) {
		fluid_buffer_rows(state, &content, screen_context.fluids, assembler.buffers[index], port.filter, port.capacity, assembler.closed[index], screen_context.tick_rate)
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(assembler_state_keys[assembler.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	if crafting_machine_is_electric(machine) {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, assembler.handle)
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), power_line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	return result
}

lab_research_text :: proc(research: Research_State, technologies: Technology_Registry) -> string {
	if !research.queued {
		return text("lab_research_none")
	}
	return fmt.tprintf("%s  %s", technology_name(technologies, research.technology), research_progress_text(research, technologies))
}

lab_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, lab: Lab, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	machine := screen_context.machines.machines[lab.machine]
	research := screen_context.world.research
	slots := lab.slots
	content := area
	machine_slot_row(state, cut_top(&content, UI_SLOT_SIZE + UI_GAP), 0, lab.slot_count, slots[:], screen_context.items, &result)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), lab_progress_fraction(lab, machine, research, screen_context.technologies, screen_context.tick_rate))
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), lab_research_text(research, screen_context.technologies), UI_BODY_TEXT_SIZE, .Left)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), research_progress_fraction(research, screen_context.technologies))
	if ui_button(state, choice_row(&content), text("lab_open_technologies")) {
		push_screen(&state.screens, .Technologies)
	}
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(lab_state_keys[lab.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	power_line := power_status_line(&screen_context.world.entities.electric_networks, lab.handle)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), power_line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
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
	}
	return machine_slot_filters(kind, slot_count)
}
