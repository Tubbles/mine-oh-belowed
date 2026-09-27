package game

import "core:fmt"

// The assembler (doc/fluids.md, Assembler, lab and research): an electric
// machine making one chosen recipe with assembler in made_in. Its slots
// follow the recipe: one input slot per ingredient in ingredient order,
// then one output slot per product. A craft takes its ingredients when it
// starts, and starts only when every product would fit, so a finished
// craft always has room. It works one tick per power credit step
// (power_machine.odin), with the recipe time of recipe_ticks at the
// machine's speed.

MAXIMUM_ASSEMBLER_SLOTS :: 8

Assembler_State :: enum u8 {
	No_Recipe,
	No_Power,
	Missing_Ingredients,
	Output_Full,
	Working,
}

@(rodata)
assembler_state_keys := [Assembler_State]string {
	.No_Recipe           = "machine_state_no_recipe",
	.No_Power            = "machine_state_unpowered",
	.Missing_Ingredients = "machine_state_missing_ingredients",
	.Output_Full         = "machine_state_output_full",
	.Working             = "machine_state_working",
}

// recipe is NO_RECIPE or a recipe index; slots[:input_count] are its
// inputs and the next output_count slots its products. working is set
// from the start of a craft (ingredients taken) to its end.
Assembler :: struct {
	using common:   Entity_Common,
	recipe:         int,
	input_count:    int,
	output_count:   int,
	slots:          [MAXIMUM_ASSEMBLER_SLOTS]Item_Stack,
	working:        bool,
	progress_ticks: u32,
	state:          Assembler_State,
	power:          Power_State,
}

make_assembler :: proc(common: Entity_Common) -> Assembler {
	assembler := Assembler {
		common = common,
		recipe = NO_RECIPE,
	}
	for &slot in assembler.slots {
		slot = EMPTY_STACK
	}
	return assembler
}

// A recipe an assembler can hold: made in an assembler, and its
// ingredients and products fit the slots.
recipe_fits_assembler :: proc(recipe: Recipe) -> bool {
	return .Assembler in recipe.made_in && len(recipe.inputs) + len(recipe.outputs) <= MAXIMUM_ASSEMBLER_SLOTS
}

validate_assembler_recipes :: proc(recipes: []Recipe) -> string {
	for recipe in recipes {
		if .Assembler in recipe.made_in && !recipe_fits_assembler(recipe) {
			return fmt.tprintf("assembler recipe %q has more than %d ingredients and products", recipe.id, MAXIMUM_ASSEMBLER_SLOTS)
		}
	}
	return ""
}

assembler_slot_count :: proc(assembler: Assembler) -> int {
	return assembler.input_count + assembler.output_count
}

assembler_input_slots :: proc(assembler: ^Assembler) -> []Item_Stack {
	return assembler.slots[:assembler.input_count]
}

assembler_output_slots :: proc(assembler: ^Assembler) -> []Item_Stack {
	return assembler.slots[assembler.input_count:assembler_slot_count(assembler^)]
}

// The input slot for an item, or -1: slots are in ingredient order.
assembler_input_slot_of :: proc(assembler: Assembler, recipes: Recipe_Registry, item: Item_Id) -> int {
	if assembler.recipe == NO_RECIPE {
		return -1
	}
	for input, index in recipes.recipes[assembler.recipe].inputs {
		if input.item == item {
			return index
		}
	}
	return -1
}

// Everything the assembler holds, including the ingredients of a craft in
// progress, in the temp allocator.
assembler_contents :: proc(assembler: ^Assembler, recipes: Recipe_Registry) -> []Item_Stack {
	contents := make([dynamic]Item_Stack, context.temp_allocator)
	append(&contents, ..assembler.slots[:assembler_slot_count(assembler^)])
	append(&contents, ..assembler_held_stacks(assembler^, recipes))
	return contents[:]
}

// The ingredients of the craft in progress, which come back on pick up
// and on a recipe change. In the temp allocator.
assembler_held_stacks :: proc(assembler: Assembler, recipes: Recipe_Registry) -> []Item_Stack {
	if !assembler.working || assembler.recipe == NO_RECIPE {
		return nil
	}
	inputs := recipes.recipes[assembler.recipe].inputs
	held := make([]Item_Stack, len(inputs), context.temp_allocator)
	copy(held, inputs)
	return held
}

// Empties the assembler and lays out the slots of the new recipe (or
// none). The caller takes the contents first (assembler_contents).
set_assembler_recipe :: proc(assembler: ^Assembler, recipes: Recipe_Registry, recipe: int) {
	for &slot in assembler.slots {
		slot = EMPTY_STACK
	}
	assembler.recipe = recipe
	assembler.working, assembler.progress_ticks = false, 0
	assembler.input_count, assembler.output_count = 0, 0
	if recipe != NO_RECIPE {
		assembler.input_count = len(recipes.recipes[recipe].inputs)
		assembler.output_count = len(recipes.recipes[recipe].outputs)
	}
	assembler.state = recipe == NO_RECIPE ? .No_Recipe : .Missing_Ingredients
}

Recipe_Change_Refusal :: enum u8 {
	None,
	Not_For_Assembler,
	Contents_Do_Not_Fit,
}

// A recipe change from the panel: the contents go to the player's
// inventory, and when they do not fit nothing changes.
change_assembler_recipe :: proc(assembler: ^Assembler, inventory: Inventory, items: Item_Registry, recipes: Recipe_Registry, recipe: int) -> Recipe_Change_Refusal {
	if recipe == assembler.recipe {
		return .None
	}
	if recipe != NO_RECIPE && !recipe_fits_assembler(recipes.recipes[recipe]) {
		return .Not_For_Assembler
	}
	contents := assembler_contents(assembler, recipes)
	if !inventory_fits_all(inventory, items, contents) {
		return .Contents_Do_Not_Fit
	}
	for stack in contents {
		if !stack_is_empty(stack) {
			inventory_add(inventory, items, stack.item, int(stack.count))
		}
	}
	set_assembler_recipe(assembler, recipes, recipe)
	return .None
}

assembler_inputs_ready :: proc(assembler: Assembler, recipe: Recipe) -> bool {
	for input, index in recipe.inputs {
		slot := assembler.slots[index]
		if stack_is_empty(slot) || slot.count < input.count {
			return false
		}
	}
	return true
}

assembler_outputs_fit :: proc(assembler: Assembler, recipe: Recipe, items: Item_Registry) -> bool {
	for output, index in recipe.outputs {
		slot := assembler.slots[assembler.input_count + index]
		if !stack_is_empty(slot) && int(slot.count) + int(output.count) > int(item_stack_size(items, output.item)) {
			return false
		}
	}
	return true
}

// Ingredients present and room for the products.
assembler_can_start :: proc(assembler: Assembler, recipes: Recipe_Registry, items: Item_Registry) -> bool {
	if assembler.recipe == NO_RECIPE {
		return false
	}
	recipe := recipes.recipes[assembler.recipe]
	return assembler_inputs_ready(assembler, recipe) && assembler_outputs_fit(assembler, recipe, items)
}

assembler_wants_power :: proc(assembler: Assembler, recipes: Recipe_Registry, items: Item_Registry) -> bool {
	return assembler.working || assembler_can_start(assembler, recipes, items)
}

start_assembler_craft :: proc(assembler: ^Assembler, recipe: Recipe) {
	for input, index in recipe.inputs {
		take_from_slot(&assembler.slots[index], int(input.count))
	}
	assembler.working, assembler.progress_ticks = true, 0
}

finish_assembler_craft :: proc(assembler: ^Assembler, recipe: Recipe) {
	for output, index in recipe.outputs {
		slot := &assembler.slots[assembler.input_count + index]
		slot.item = output.item
		slot.count += output.count
	}
	assembler.working, assembler.progress_ticks = false, 0
}

// The state before any work this tick: why it cannot start, or none.
assembler_start_state :: proc(assembler: Assembler, recipes: Recipe_Registry, items: Item_Registry) -> (state: Assembler_State, blocked: bool) {
	switch {
	case assembler.recipe == NO_RECIPE:
		return .No_Recipe, true
	case !assembler_inputs_ready(assembler, recipes.recipes[assembler.recipe]):
		return .Missing_Ingredients, true
	case !assembler_outputs_fit(assembler, recipes.recipes[assembler.recipe], items):
		return .Output_Full, true
	}
	return .Working, false
}

// One tick. Returns whether a craft finished, for the statistics.
advance_assembler :: proc(assembler: ^Assembler, machine: Machine, items: Item_Registry, recipes: Recipe_Registry, tick_rate: int) -> (crafted: bool) {
	if !assembler.working {
		state, blocked := assembler_start_state(assembler^, recipes, items)
		if blocked {
			assembler.state = state
			return false
		}
	}
	if !power_is_on(assembler.power) {
		assembler.state = .No_Power
		return false
	}
	recipe := recipes.recipes[assembler.recipe]
	if !assembler.working {
		start_assembler_craft(assembler, recipe)
	}
	assembler.state = .Working
	if take_power_step(&assembler.power) {
		assembler.progress_ticks += 1
	}
	if assembler.progress_ticks < recipe_ticks(recipe, machine.speed_percent, tick_rate) {
		return false
	}
	finish_assembler_craft(assembler, recipe)
	return true
}

assembler_progress_fraction :: proc(assembler: Assembler, machine: Machine, recipes: Recipe_Registry, tick_rate: int) -> f32 {
	if !assembler.working || assembler.recipe == NO_RECIPE {
		return 0
	}
	return f32(assembler.progress_ticks) / f32(recipe_ticks(recipes.recipes[assembler.recipe], machine.speed_percent, tick_rate))
}

// Pool order; products count as produced.
tick_assemblers :: proc(world: ^World, content: Simulation_Content, tick_rate: int) {
	for &assembler in world.entities.assemblers.entries {
		if !assembler.alive {
			continue
		}
		machine := content.machines.machines[assembler.machine]
		if advance_assembler(&assembler, machine, content.items, content.recipes, tick_rate) {
			record_produced_stacks(&world.statistics, content.recipes.recipes[assembler.recipe].outputs)
		}
	}
}

// What the player may drop into each slot: an input takes only its
// ingredient, outputs take nothing. In the temp allocator.
assembler_slot_filters :: proc(assembler: Assembler, recipes: Recipe_Registry) -> []Slot_Filter {
	filters := make([]Slot_Filter, assembler_slot_count(assembler), context.temp_allocator)
	for &filter, index in filters {
		filter = {kind = .Output}
		if index < assembler.input_count {
			filter = {kind = .Item, item = recipes.recipes[assembler.recipe].inputs[index].item}
		}
	}
	return filters
}
