package game

// The fuel burning furnace (stone and steel furnace), ticked in the
// simulation with integer arithmetic. It burns only while it has work: a
// recipe for the input and room in the output. Fuel energy is kept in
// joules, because 90 kW at 60 ticks per second is 1.5 kJ per tick.
// A recipe's byproduct (slag, work item 0027) goes to its own slot. With
// strict byproducts the furnace waits for room there like for the main
// output; with lenient byproducts it smelts on and voids what does not
// fit.

FURNACE_FUEL_SLOT :: 0
FURNACE_INPUT_SLOT :: 1
FURNACE_OUTPUT_SLOT :: 2
FURNACE_BYPRODUCT_SLOT :: 3
FURNACE_SLOT_COUNT :: 4

Furnace_State :: enum u8 {
	Idle,
	Burning,
	No_Fuel,
	Output_Full,
}

// fuel_joules is what is left of the burning fuel item, fuel_item_joules
// that item's full value (for the burn bar). recipe is a recipe index or
// NO_RECIPE; progress starts over when it changes.
Furnace :: struct {
	using common:     Entity_Common,
	slots:            [FURNACE_SLOT_COUNT]Item_Stack,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	recipe:           int,
	progress_ticks:   u32,
	state:            Furnace_State,
	// Main output over the last minute, for the panel (statistics.odin).
	output_rate:      Machine_Output_Rate,
}

make_furnace :: proc(common: Entity_Common) -> Furnace {
	return Furnace{common = common, slots = {EMPTY_STACK, EMPTY_STACK, EMPTY_STACK, EMPTY_STACK}, recipe = NO_RECIPE}
}

item_is_fuel :: proc(items: Item_Registry, item: Item_Id) -> bool {
	return int(item) < len(items.items) && items.items[item].fuel_kilojoules > 0
}

// The recipe the input stack can start, or NO_RECIPE when there is none
// or too little input.
furnace_recipe :: proc(recipes: Recipe_Registry, input: Item_Stack) -> int {
	if stack_is_empty(input) {
		return NO_RECIPE
	}
	recipe := furnace_recipe_for(recipes, input.item)
	if recipe == NO_RECIPE || input.count < recipes.recipes[recipe].inputs[0].count {
		return NO_RECIPE
	}
	return recipe
}

// Room for the main output, and for the byproduct unless a lenient world
// voids it.
furnace_has_room :: proc(slots: [FURNACE_SLOT_COUNT]Item_Stack, recipe: Recipe, items: Item_Registry, byproducts_lenient: bool) -> bool {
	if !stack_fits_slot(slots[FURNACE_OUTPUT_SLOT], recipe.outputs[0], items) {
		return false
	}
	return len(recipe.outputs) < 2 || byproducts_lenient || stack_fits_slot(slots[FURNACE_BYPRODUCT_SLOT], recipe.outputs[1], items)
}

fuel_joules_per_tick :: proc(machine: Machine, tick_rate: int) -> u32 {
	return max(machine.fuel_power_watts / u32(tick_rate), 1)
}

// Burns one more fuel item when the buffer cannot pay for this tick.
// Returns false when there is nothing to burn.
refuel_furnace :: proc(furnace: ^Furnace, items: Item_Registry, needed: u32) -> bool {
	return refuel_from_slot(&furnace.fuel_joules, &furnace.fuel_item_joules, &furnace.slots[FURNACE_FUEL_SLOT], items, needed)
}

// Shared by every fuel burning entity: the buffer, the full value of the
// item burning (for the burn bar) and the fuel slot.
refuel_from_slot :: proc(fuel_joules, fuel_item_joules: ^u32, fuel: ^Item_Stack, items: Item_Registry, needed: u32) -> bool {
	if fuel_joules^ >= needed {
		return true
	}
	if stack_is_empty(fuel^) || !item_is_fuel(items, fuel.item) {
		return false
	}
	joules := items.items[fuel.item].fuel_kilojoules * 1000
	take_from_slot(fuel, 1)
	fuel_joules^ += joules
	fuel_item_joules^ = joules
	return true
}

// The byproduct goes in as far as there is room; the rest is voided,
// which only a lenient world gets to (strict waited for room).
finish_smelting :: proc(furnace: ^Furnace, recipe: Recipe, items: Item_Registry) {
	take_from_slot(&furnace.slots[FURNACE_INPUT_SLOT], int(recipe.inputs[0].count))
	for product, index in recipe.outputs {
		fill_slot(&furnace.slots[FURNACE_OUTPUT_SLOT + index], product.item, int(product.count), item_stack_size(items, product.item))
	}
	furnace.progress_ticks = 0
}

// One tick of the furnace. It smelts every furnace recipe whether or not
// the recipe is unlocked (every one of them is a start recipe or is
// discovered by obtaining its only input), except a schematic alternate
// not found yet (recipe_runs_in_machines). byproducts_lenient is the world
// setting, read on every tick including the one a smelt completes on.
advance_furnace :: proc(furnace: Furnace, machine: Machine, items: Item_Registry, recipes: Recipe_Registry, tick_rate: int, byproducts_lenient := false) -> Furnace {
	result := furnace
	recipe_index := furnace_recipe(recipes, result.slots[FURNACE_INPUT_SLOT])
	if recipe_index != result.recipe {
		result.recipe, result.progress_ticks = recipe_index, 0
	}
	if recipe_index == NO_RECIPE {
		result.state = .Idle
		return result
	}
	recipe := recipes.recipes[recipe_index]
	if !furnace_has_room(result.slots, recipe, items, byproducts_lenient) {
		result.state = .Output_Full
		return result
	}
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	if !refuel_furnace(&result, items, per_tick) {
		result.state = .No_Fuel
		return result
	}
	result.fuel_joules -= per_tick
	result.progress_ticks += 1
	result.state = .Burning
	if result.progress_ticks >= recipe_ticks(recipe, machine.speed_percent, tick_rate) {
		finish_smelting(&result, recipe, items)
	}
	return result
}

furnace_burn_fraction :: proc(furnace: Furnace) -> f32 {
	if furnace.fuel_item_joules == 0 {
		return 0
	}
	return f32(furnace.fuel_joules) / f32(furnace.fuel_item_joules)
}

furnace_progress_fraction :: proc(furnace: Furnace, machine: Machine, recipes: Recipe_Registry, tick_rate: int) -> f32 {
	if furnace.recipe == NO_RECIPE {
		return 0
	}
	return f32(furnace.progress_ticks) / f32(recipe_ticks(recipes.recipes[furnace.recipe], machine.speed_percent, tick_rate))
}

@(rodata)
furnace_state_keys := [Furnace_State]string {
	.Idle        = "machine_state_idle",
	.Burning     = "machine_state_burning",
	.No_Fuel     = "machine_state_no_fuel",
	.Output_Full = "machine_state_output_full",
}
