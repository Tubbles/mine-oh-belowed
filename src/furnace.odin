package game

import "core:fmt"

// The fuel burning furnace, ticked in the simulation with integer
// arithmetic. It burns only while it has work: a recipe for the input and
// room in the output. Fuel energy is kept in joules, because 90 kW at 60
// ticks per second is 1.5 kJ per tick.

FURNACE_FUEL_SLOT :: 0
FURNACE_INPUT_SLOT :: 1
FURNACE_OUTPUT_SLOT :: 2
FURNACE_SLOT_COUNT :: 3
NO_RECIPE :: -1

Furnace_State :: enum u8 {
	Idle,
	Burning,
	No_Fuel,
	Output_Full,
}

// fuel_joules is what is left of the burning fuel item, fuel_item_joules
// that item's full value (for the burn bar). recipe is an index into the
// smelting table or NO_RECIPE; progress starts over when it changes.
Furnace :: struct {
	using common:     Entity_Common,
	slots:            [FURNACE_SLOT_COUNT]Item_Stack,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	recipe:           int,
	progress_ticks:   u32,
	state:            Furnace_State,
}

Smelting_Recipe :: struct {
	input:                 Item_Id,
	input_count:           u16,
	output:                Item_Id,
	output_count:          u16,
	duration_milliseconds: u32,
}

Smelting_Recipe_Definition :: struct {
	input:                 string,
	input_count:           u16,
	output:                string,
	output_count:          u16,
	duration_milliseconds: u32,
}

// TODO(0012): hardcoded until work item 0012 loads recipes from data, and
// 0012 removes this table together with resolve_smelting_table. Times are
// at speed 1, from doc/content.md.
@(rodata)
HARDCODED_SMELTING_TABLE := [?]Smelting_Recipe_Definition {
	{"hematite", 1, "iron_plate", 1, 3200},
	{"chalcopyrite", 1, "copper_plate", 1, 3200},
	{"cassiterite", 1, "tin_plate", 1, 3200},
	{"stone", 2, "stone_brick", 1, 3200},
	{"sand", 2, "glass", 1, 3200},
	{"log", 2, "charcoal", 1, 3200},
}

resolve_smelting_table :: proc(items: Item_Registry, allocator := context.allocator) -> (recipes: []Smelting_Recipe, problem: string) {
	recipes = make([]Smelting_Recipe, len(HARDCODED_SMELTING_TABLE), allocator)
	for definition, index in HARDCODED_SMELTING_TABLE {
		input, input_found := find_item_id(items, definition.input)
		output, output_found := find_item_id(items, definition.output)
		if !input_found || !output_found {
			delete(recipes, allocator)
			return nil, fmt.tprintf("smelting %q to %q names an unknown item", definition.input, definition.output)
		}
		recipes[index] = Smelting_Recipe{input, definition.input_count, output, definition.output_count, definition.duration_milliseconds}
	}
	return recipes, ""
}

make_furnace :: proc(common: Entity_Common) -> Furnace {
	return Furnace{common = common, slots = {EMPTY_STACK, EMPTY_STACK, EMPTY_STACK}, recipe = NO_RECIPE}
}

smelting_recipe_for :: proc(recipes: []Smelting_Recipe, item: Item_Id) -> int {
	for recipe, index in recipes {
		if recipe.input == item {
			return index
		}
	}
	return NO_RECIPE
}

item_is_smeltable :: proc(recipes: []Smelting_Recipe, item: Item_Id) -> bool {
	return smelting_recipe_for(recipes, item) != NO_RECIPE
}

item_is_fuel :: proc(items: Item_Registry, item: Item_Id) -> bool {
	return int(item) < len(items.items) && items.items[item].fuel_kilojoules > 0
}

// The recipe the input stack can start, or NO_RECIPE when there is none
// or too little input.
furnace_recipe :: proc(recipes: []Smelting_Recipe, input: Item_Stack) -> int {
	if stack_is_empty(input) {
		return NO_RECIPE
	}
	recipe := smelting_recipe_for(recipes, input.item)
	if recipe == NO_RECIPE || input.count < recipes[recipe].input_count {
		return NO_RECIPE
	}
	return recipe
}

output_has_room :: proc(output: Item_Stack, recipe: Smelting_Recipe, items: Item_Registry) -> bool {
	if stack_is_empty(output) {
		return true
	}
	return output.item == recipe.output && int(output.count) + int(recipe.output_count) <= int(item_stack_size(items, recipe.output))
}

// At least one tick, whatever the speed.
recipe_ticks :: proc(recipe: Smelting_Recipe, speed_percent: u32, tick_rate: int) -> u32 {
	ticks := u64(recipe.duration_milliseconds) * u64(tick_rate) * 100 / (1000 * u64(max(speed_percent, 1)))
	return max(u32(ticks), 1)
}

fuel_joules_per_tick :: proc(machine: Machine, tick_rate: int) -> u32 {
	return max(machine.fuel_power_watts / u32(tick_rate), 1)
}

// Burns one more fuel item when the buffer cannot pay for this tick.
// Returns false when there is nothing to burn.
refuel_furnace :: proc(furnace: ^Furnace, items: Item_Registry, needed: u32) -> bool {
	if furnace.fuel_joules >= needed {
		return true
	}
	fuel := &furnace.slots[FURNACE_FUEL_SLOT]
	if stack_is_empty(fuel^) || !item_is_fuel(items, fuel.item) {
		return false
	}
	joules := items.items[fuel.item].fuel_kilojoules * 1000
	take_from_slot(fuel, 1)
	furnace.fuel_joules += joules
	furnace.fuel_item_joules = joules
	return true
}

finish_smelting :: proc(furnace: ^Furnace, recipe: Smelting_Recipe) {
	take_from_slot(&furnace.slots[FURNACE_INPUT_SLOT], int(recipe.input_count))
	output := &furnace.slots[FURNACE_OUTPUT_SLOT]
	output.item = recipe.output
	output.count += recipe.output_count
	furnace.progress_ticks = 0
}

// One tick of the furnace.
advance_furnace :: proc(furnace: Furnace, machine: Machine, items: Item_Registry, recipes: []Smelting_Recipe, tick_rate: int) -> Furnace {
	result := furnace
	recipe_index := furnace_recipe(recipes, result.slots[FURNACE_INPUT_SLOT])
	if recipe_index != result.recipe {
		result.recipe, result.progress_ticks = recipe_index, 0
	}
	if recipe_index == NO_RECIPE {
		result.state = .Idle
		return result
	}
	recipe := recipes[recipe_index]
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

furnace_progress_fraction :: proc(furnace: Furnace, machine: Machine, recipes: []Smelting_Recipe, tick_rate: int) -> f32 {
	if furnace.recipe == NO_RECIPE {
		return 0
	}
	return f32(furnace.progress_ticks) / f32(recipe_ticks(recipes[furnace.recipe], machine.speed_percent, tick_rate))
}

@(rodata)
furnace_state_keys := [Furnace_State]string {
	.Idle        = "machine_state_idle",
	.Burning     = "machine_state_burning",
	.No_Fuel     = "machine_state_no_fuel",
	.Output_Full = "machine_state_output_full",
}
