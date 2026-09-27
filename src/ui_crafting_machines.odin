package game

import "core:fmt"

// The assembler and lab panels inside the machine panel (ui_machine.odin).
// Assembler: the recipe with a button that opens the recipe browser in
// its selection mode, the input slots, the progress bar, the output
// slots, the state and the power line. Lab: the pack slots, the unit's
// progress bar, the queued technology with its progress, a button to the
// technology screen, the state and the power line.

CRAFTING_MACHINE_AREA_WIDTH :: 6 * (UI_SLOT_SIZE + UI_GAP)

crafting_machine_area_size :: proc(kind: Machine_Kind) -> [2]f32 {
	slot_row := f32(UI_SLOT_SIZE + UI_GAP)
	if kind == .Assembler {
		// Name, recipe row, inputs, bar, outputs, state, power.
		return {CRAFTING_MACHINE_AREA_WIDTH, 2 * (UI_ROW_HEIGHT + UI_GAP) + 2 * slot_row + 3 * UI_ROW_HEIGHT}
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
	if assembler.recipe == NO_RECIPE {
		return text("assembler_recipe_none")
	}
	return screen_context.recipe_names[assembler.recipe]
}

assembler_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, assembler: Assembler, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	machine := screen_context.machines.machines[assembler.machine]
	slots := assembler.slots
	content := area
	recipe_row := choice_row(&content)
	if ui_button(state, recipe_row, fmt.tprintf("%s: %s", text("assembler_choose_recipe"), assembler_recipe_text(assembler, screen_context))) {
		open_recipe_selection(state, screen_context.browser, assembler.handle)
	}
	machine_slot_row(state, cut_top(&content, UI_SLOT_SIZE + UI_GAP), 0, assembler.input_count, slots[:], screen_context.items, &result)
	machine_bar(state, cut_top(&content, UI_ROW_HEIGHT), assembler_progress_fraction(assembler, machine, screen_context.recipes, screen_context.tick_rate))
	machine_slot_row(state, cut_top(&content, UI_SLOT_SIZE + UI_GAP), assembler.input_count, assembler.output_count, slots[:], screen_context.items, &result)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(assembler_state_keys[assembler.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	power_line := power_status_line(&screen_context.world.entities.electric_networks, assembler.handle)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), power_line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
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
		return assembler_slot_filters(pool_get(&screen_context.world.entities.assemblers, handle)^, screen_context.recipes)
	case .Lab:
		return lab_slot_filters(screen_context.machines.lab_packs, slot_count)
	}
	return machine_slot_filters(kind, slot_count)
}
