package game

import "core:fmt"
import "core:slice"

// The recycler (work item 0027), the universal sink of DESIGN.md: a fixed
// choice crafting machine of the recycler category that no recipe is made
// in. It reverses the first recipe (in data order) that makes the loaded
// item: one craft takes that recipe's count of the item and gives back a
// quarter of each input count rounded down, at the recipe's time. Cheap
// items give nothing back, which is the sink. Items flagged
// cannot_recycle (raw materials, ore, spoils, bricks) are refused.
//
// It runs through the shared crafting machine code (assembler.odin) with
// the reversed recipe as its craft (machine_craft), rather than through the
// fixed recipe matcher: the recipe is looked up by the one loaded item,
// and the returns vary per item, so they go into any output slot holding
// their item or an empty one instead of one slot per product.

RECYCLE_RETURN_PERCENT :: 25

// Indexed by Item_Id: the first recipe making each item the recycler
// takes, or NO_RECIPE.
resolve_recycle_recipes :: proc(recipes: []Recipe, items: Item_Registry, allocator := context.allocator) -> []int {
	table := make([]int, len(items.items), allocator)
	slice.fill(table, NO_RECIPE)
	for recipe, index in recipes {
		for output in recipe.outputs {
			if table[output.item] == NO_RECIPE && !items.items[output.item].cannot_recycle {
				table[output.item] = index
			}
		}
	}
	return table
}

recycle_recipe_of :: proc(recipes: Recipe_Registry, item: Item_Id) -> int {
	if int(item) >= len(recipes.recycle_recipes) {
		return NO_RECIPE
	}
	return recipes.recycle_recipes[item]
}

item_is_recyclable :: proc(recipes: Recipe_Registry, item: Item_Id) -> bool {
	return recycle_recipe_of(recipes, item) != NO_RECIPE
}

// What one craft takes: the recipe's count of the first of its outputs
// the recycler reverses it for.
recycled_stack :: proc(recipes: Recipe_Registry, recipe: int) -> Item_Stack {
	for output in recipes.recipes[recipe].outputs {
		if recycle_recipe_of(recipes, output.item) == recipe {
			return output
		}
	}
	return EMPTY_STACK
}

recycled_count :: proc(count: u16) -> u16 {
	return u16(int(count) * RECYCLE_RETURN_PERCENT / 100)
}

// What one craft gives back, inputs that round down to nothing left out.
// In the temp allocator.
recycling_returns :: proc(recipe: Recipe) -> []Item_Stack {
	returns := make([dynamic]Item_Stack, context.temp_allocator)
	for input in recipe.inputs {
		if count := recycled_count(input.count); count > 0 {
			append(&returns, Item_Stack{item = input.item, count = count})
		}
	}
	return returns[:]
}

// The recipe to reverse for the loaded input, or NO_RECIPE.
recycler_recipe_for_inputs :: proc(recipes: Recipe_Registry, loaded: []Item_Stack) -> int {
	for slot in loaded {
		if !stack_is_empty(slot) {
			return recycle_recipe_of(recipes, slot.item)
		}
	}
	return NO_RECIPE
}

// A slot holding the item with room for the whole stack, else an empty
// one, else -1.
return_slot_of :: proc(slots: []Item_Stack, stack: Item_Stack, items: Item_Registry) -> int {
	for slot, index in slots {
		if !stack_is_empty(slot) && slot.item == stack.item && int(slot.count) + int(stack.count) <= int(item_stack_size(items, stack.item)) {
			return index
		}
	}
	for slot, index in slots {
		if stack_is_empty(slot) {
			return index
		}
	}
	return -1
}

// Places every return; false as soon as one finds no slot.
place_returns :: proc(slots: []Item_Stack, returns: []Item_Stack, items: Item_Registry) -> bool {
	for stack in returns {
		index := return_slot_of(slots, stack, items)
		if index < 0 {
			return false
		}
		slots[index].item = stack.item
		slots[index].count += stack.count
	}
	return true
}

returns_fit :: proc(slots: []Item_Stack, returns: []Item_Stack, items: Item_Registry) -> bool {
	probe := make([]Item_Stack, len(slots), context.temp_allocator)
	copy(probe, slots)
	return place_returns(probe, returns, items)
}

// Every recyclable item's returns must fit the empty output slots.
validate_recycler_returns :: proc(machine: Machine, recipes: Recipe_Registry) -> string {
	for recipe in recipes.recycle_recipes {
		if recipe != NO_RECIPE && len(recycling_returns(recipes.recipes[recipe])) > machine.output_slot_count {
			return fmt.tprintf("recycling recipe %q gives back more stacks than machine %q has output slots", recipes.recipes[recipe].id, machine.id)
		}
	}
	return ""
}
