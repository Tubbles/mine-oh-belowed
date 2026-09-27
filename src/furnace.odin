package game

// The fuel burning furnace, ticked in the simulation with integer
// arithmetic. It burns only while it has work: a recipe for the input and
// room in the output. Fuel energy is kept in joules, because 90 kW at 60
// ticks per second is 1.5 kJ per tick.

FURNACE_FUEL_SLOT :: 0
FURNACE_INPUT_SLOT :: 1
FURNACE_OUTPUT_SLOT :: 2
FURNACE_SLOT_COUNT :: 3

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
}

make_furnace :: proc(common: Entity_Common) -> Furnace {
	return Furnace{common = common, slots = {EMPTY_STACK, EMPTY_STACK, EMPTY_STACK}, recipe = NO_RECIPE}
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

output_has_room :: proc(output: Item_Stack, recipe: Recipe, items: Item_Registry) -> bool {
	if stack_is_empty(output) {
		return true
	}
	product := recipe.outputs[0]
	return output.item == product.item && int(output.count) + int(product.count) <= int(item_stack_size(items, product.item))
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

finish_smelting :: proc(furnace: ^Furnace, recipe: Recipe) {
	take_from_slot(&furnace.slots[FURNACE_INPUT_SLOT], int(recipe.inputs[0].count))
	output := &furnace.slots[FURNACE_OUTPUT_SLOT]
	output.item = recipe.outputs[0].item
	output.count += recipe.outputs[0].count
	furnace.progress_ticks = 0
}

// One tick of the furnace. It smelts every furnace recipe whether or not
// the recipe is unlocked: today every one of them is a start recipe or is
// discovered by obtaining its only input.
advance_furnace :: proc(furnace: Furnace, machine: Machine, items: Item_Registry, recipes: Recipe_Registry, tick_rate: int) -> Furnace {
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
	if !output_has_room(result.slots[FURNACE_OUTPUT_SLOT], recipe, items) {
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
		finish_smelting(&result, recipe)
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
