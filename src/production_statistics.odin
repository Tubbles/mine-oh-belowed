package game

import "core:slice"
import "core:unicode"

// The pure part of the production statistics screen and the bottleneck
// overlay (work item 0028): the rows of the item list, the machines that
// make and use an item, and the marker colour of each machine state.

// One item of the statistics list: what was produced and consumed over
// the chosen window.
Item_Rate_Row :: struct {
	item:     Item_Id,
	produced: u64,
	consumed: u64,
}

// Every item ever produced or consumed, so the list keeps its items when
// a line stops, sorted by produced over the window (most first), then
// consumed, then item order. In the given allocator.
statistics_rows :: proc(statistics: Statistics, window: Rate_Window, allocator := context.allocator) -> []Item_Rate_Row {
	rows := make([dynamic]Item_Rate_Row, allocator)
	for index in 0 ..< len(statistics.produced) {
		item := Item_Id(index)
		if item_counter(statistics.produced, item) == 0 && item_counter(statistics.consumed, item) == 0 {
			continue
		}
		append(&rows, item_rate_row(statistics, item, window))
	}
	slice.sort_by(rows[:], item_rate_row_before)
	return rows[:]
}

item_rate_row :: proc(statistics: Statistics, item: Item_Id, window: Rate_Window) -> Item_Rate_Row {
	second := statistics.current_second
	return Item_Rate_Row {
		item = item,
		produced = window_total(statistics.produced_rates, item, window, second),
		consumed = window_total(statistics.consumed_rates, item, window, second),
	}
}

item_rate_row_before :: proc(first, second: Item_Rate_Row) -> bool {
	if first.produced != second.produced {
		return first.produced > second.produced
	}
	if first.consumed != second.consumed {
		return first.consumed > second.consumed
	}
	return first.item < second.item
}

// The first row whose item name starts with the letter, or -1. The list
// is sorted by rate, not by name, so only an exact first letter jumps.
row_position_for_letter :: proc(names: []string, rows: []Item_Rate_Row, letter: rune) -> int {
	wanted := unicode.to_lower(letter)
	for row, position in rows {
		if int(row.item) < len(names) && first_letter(names[row.item]) == wanted {
			return position
		}
	}
	return -1
}

// How many machines make and use an item right now: furnaces and crafting
// machines by their current recipe (the recycler by the recipe it
// reverses), drills by the outputs of the vein they tap, labs by the
// packs of the queued technology, and every fuel burner by the fuel in its
// slot. A machine counts once on each side.
Item_Machine_Counts :: struct {
	producers: int,
	consumers: int,
}

count_item_machines :: proc(world: ^World, content: Simulation_Content, item: Item_Id) -> Item_Machine_Counts {
	counts: Item_Machine_Counts
	entities := &world.entities
	for furnace in entities.furnaces.entries {
		if furnace.alive {
			slots := furnace.slots
			add_recipe_machine(&counts, content.recipes, furnace.recipe, slots[FURNACE_FUEL_SLOT], item)
		}
	}
	for assembler in entities.assemblers.entries {
		if assembler.alive {
			fuel := assembler.fuel_count > 0 ? assembler.slots[0] : EMPTY_STACK
			add_crafting_machine(&counts, content, assembler, fuel, item)
		}
	}
	for drill in entities.drills.entries {
		if drill.alive {
			add_drill(&counts, world, content.veins, drill, item)
		}
	}
	for lab in entities.labs.entries {
		if lab.alive && lab_uses_pack(world.research, content.technologies, item) {
			counts.consumers += 1
		}
	}
	for fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive && fluid_machine.slot_count > 0 && stack_holds(fluid_machine.slots[0], item) {
			counts.consumers += 1
		}
	}
	return counts
}

stack_holds :: proc(stack: Item_Stack, item: Item_Id) -> bool {
	return !stack_is_empty(stack) && stack.item == item
}

add_machine_sides :: proc(counts: ^Item_Machine_Counts, produces, consumes: bool) {
	counts.producers += produces ? 1 : 0
	counts.consumers += consumes ? 1 : 0
}

add_recipe_machine :: proc(counts: ^Item_Machine_Counts, recipes: Recipe_Registry, recipe: int, fuel: Item_Stack, item: Item_Id) {
	produces, consumes := false, stack_holds(fuel, item)
	if recipe >= 0 && recipe < len(recipes.recipes) {
		produces = stacks_contain_item(recipes.recipes[recipe].outputs, item)
		consumes ||= stacks_contain_item(recipes.recipes[recipe].inputs, item)
	}
	add_machine_sides(counts, produces, consumes)
}

add_crafting_machine :: proc(counts: ^Item_Machine_Counts, content: Simulation_Content, assembler: Assembler, fuel: Item_Stack, item: Item_Id) {
	produces, consumes := false, stack_holds(fuel, item)
	if assembler.recipe >= 0 && assembler.recipe < len(content.recipes.recipes) {
		craft := machine_craft(content.machines.machines[assembler.machine], content.recipes, assembler.recipe)
		produces = stacks_contain_item(craft.outputs, item)
		consumes ||= stacks_contain_item(craft.inputs, item)
	}
	add_machine_sides(counts, produces, consumes)
}

add_drill :: proc(counts: ^Item_Machine_Counts, world: ^World, veins: Vein_Content, drill: Drill, item: Item_Id) {
	fuel := drill.slot_count > 0 ? drill.slots[DRILL_FUEL_SLOT] : EMPTY_STACK
	add_machine_sides(counts, drill_can_yield(world, veins, drill, item), stack_holds(fuel, item))
}

// Whether the vein the drill taps yields the item, as ore or its low grade.
drill_can_yield :: proc(world: ^World, veins: Vein_Content, drill: Drill, item: Item_Id) -> bool {
	vein := registered_vein(world, drill.vein)
	if vein == nil || vein.type >= len(veins.types) {
		return false
	}
	vein_type := veins.types[vein.type]
	for index in 0 ..< vein_type.output_count {
		if vein_type.outputs[index] == item || vein_type.low_grades[index] == item {
			return true
		}
	}
	return false
}

lab_uses_pack :: proc(research: Research_State, technologies: Technology_Registry, item: Item_Id) -> bool {
	if !research.queued || research.technology >= len(technologies.technologies) {
		return false
	}
	return slice.contains(technologies.technologies[research.technology].science_packs, item)
}

// Bottleneck overlay markers: green working, yellow waiting for room for
// its output, red missing input, fuel, power or a recipe, grey idle or an
// electric machine outside every network (nothing to fix on the machine).
Marker_Colour :: enum u8 {
	Green,
	Yellow,
	Red,
	Grey,
}

// An electric machine without power is red on a network that cannot
// supply it and grey with no network at all.
unpowered_marker :: proc(connected: bool) -> Marker_Colour {
	return connected ? .Red : .Grey
}

// An idle furnace with fuel is set up and starved of ore, one without
// fuel is merely unused.
furnace_marker_colour :: proc(state: Furnace_State, has_fuel: bool) -> Marker_Colour {
	switch state {
	case .Burning:
		return .Green
	case .Output_Full:
		return .Yellow
	case .No_Fuel:
		return .Red
	case .Idle:
		return has_fuel ? .Red : .Grey
	}
	return .Grey
}

crafting_machine_marker_colour :: proc(state: Assembler_State, connected: bool) -> Marker_Colour {
	switch state {
	case .Working:
		return .Green
	case .Output_Full:
		return .Yellow
	case .No_Recipe, .Missing_Ingredients, .No_Fuel, .No_Fluid:
		return .Red
	case .No_Power:
		return unpowered_marker(connected)
	}
	return .Grey
}

drill_marker_colour :: proc(state: Drill_State, connected: bool) -> Marker_Colour {
	switch state {
	case .Mining:
		return .Green
	case .Waiting_For_Room:
		return .Yellow
	case .No_Fuel, .Vein_Exhausted:
		return .Red
	case .Unpowered:
		return unpowered_marker(connected)
	}
	return .Grey
}

lab_marker_colour :: proc(state: Lab_State, connected: bool) -> Marker_Colour {
	switch state {
	case .Researching:
		return .Green
	case .No_Packs:
		return .Red
	case .No_Research:
		return .Grey
	case .No_Power:
		return unpowered_marker(connected)
	}
	return .Grey
}

fluid_machine_marker_colour :: proc(state: Fluid_Machine_State, connected: bool) -> Marker_Colour {
	switch state {
	case .Producing, .Pumping:
		return .Green
	case .Output_Full:
		return .Yellow
	case .No_Water, .No_Fuel, .No_Steam:
		return .Red
	case .Unpowered:
		return unpowered_marker(connected)
	case .Idle:
		return .Grey
	}
	return .Grey
}

machine_marker_colour :: proc {
	furnace_marker_colour,
	crafting_machine_marker_colour,
	drill_marker_colour,
	lab_marker_colour,
	fluid_machine_marker_colour,
}

// Storage tanks hold fluid and do no work, so they get no marker.
fluid_machine_has_marker :: proc(kind: Machine_Kind) -> bool {
	#partial switch kind {
	case .Offshore_Pump, .Boiler, .Steam_Engine, .Pump:
		return true
	}
	return false
}
