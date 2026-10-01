package game

import "core:hash"
import "core:slice"
import "core:unicode"

// The pure part of the recipe browser: filtering, the letter jump and what
// the detail panel may show. ui_recipes.odin draws it.

// The recipe list shows the recipes of one category that carry every
// selected tag, with craftable_only only those craftable now, and with
// available_only (the "Unlocked only" toggle, on by default) only the
// unlocked ones. The selection mode (choosing an assembler's recipe) adds
// makers, which the recipe must be made in, and forces available_only.
Recipe_Filter :: struct {
	category:       Recipe_Category,
	tags:           Recipe_Tag_Set,
	craftable_only: bool,
	makers:         Recipe_Makers,
	available_only: bool,
}

recipe_matches_filter :: proc(recipe: Recipe, filter: Recipe_Filter, craftable, available: bool) -> bool {
	if recipe.category != filter.category || filter.tags & recipe.tags != filter.tags {
		return false
	}
	if filter.makers & recipe.made_in != filter.makers || (filter.available_only && !available) {
		return false
	}
	return craftable || !filter.craftable_only
}

// The recipes of the filter in the given order (by name). available is
// per recipe; nil counts every recipe as available.
filter_recipes :: proc(recipes: Recipe_Registry, order: []int, filter: Recipe_Filter, craftable: []bool, available: []bool = nil, allocator := context.allocator) -> []int {
	visible := make([dynamic]int, 0, len(order), allocator)
	for recipe in order {
		is_available := available == nil || available[recipe]
		if recipe_matches_filter(recipes.recipes[recipe], filter, craftable[recipe], is_available) {
			append(&visible, recipe)
		}
	}
	return visible[:]
}

// The browser choosing a recipe for a machine: the recipes the maker makes
// that are available, whether or not they can be hand crafted now.
selection_filter :: proc(filter: Recipe_Filter, maker: Recipe_Maker) -> Recipe_Filter {
	result := filter
	result.craftable_only = false
	result.makers = {maker}
	result.available_only = true
	return result
}

// Per recipe, whether the queue accepts one craft now, intermediates
// included (0156).
craftable_recipes :: proc(recipes: Recipe_Registry, unlocks: Recipe_Unlocks, inventory: Inventory, queue: Craft_Queue, allocator := context.allocator) -> []bool {
	craftable := make([]bool, len(recipes.recipes), allocator)
	for _, index in recipes.recipes {
		craftable[index] = queue_accepts_crafts(queue, inventory, recipes, unlocks, index, 1)
	}
	return craftable
}

// The planner's answers the browser shows, kept across frames: planning
// every recipe each frame costs too much, so they are planned again only
// when what the planner reads changes (recipe_plan_key) and, for the
// detail, when the focused recipe does.
Recipe_Plans :: struct {
	craftable_key: u64,
	craftable:     [dynamic]bool,
	detail_key:    u64,
	detail_recipe: int,
	detail_count:  int,
	detail_inputs: [dynamic]Planned_Input,
}

destroy_recipe_plans :: proc(plans: ^Recipe_Plans) {
	delete(plans.craftable)
	delete(plans.detail_inputs)
	plans^ = {detail_recipe = NO_RECIPE}
}

// Changes when what the planner reads changes: the inventory, the queued
// runs, the front's state and the available recipes; not the front's
// progress, which moves every tick.
recipe_plan_key :: proc(queue: Craft_Queue, inventory: Inventory, available: []bool) -> u64 {
	queue := queue
	front := [2]u64{u64(queue.started), u64(queue.waiting_for)}
	key := hash.fnv64a(slice.to_bytes(inventory.slots))
	key = hash.fnv64a(slice.to_bytes(queue.runs[:queue.count]), key)
	key = hash.fnv64a(slice.to_bytes(available), key)
	return hash.fnv64a(slice.to_bytes(front[:]), key)
}

// Plans the craftable marks again when the key or the registry changed.
refresh_craftable_recipes :: proc(plans: ^Recipe_Plans, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, inventory: Inventory, queue: Craft_Queue) {
	key := recipe_plan_key(queue, inventory, unlocks.available)
	if key == plans.craftable_key && len(plans.craftable) == len(recipes.recipes) {
		return
	}
	clear(&plans.craftable)
	append(&plans.craftable, ..craftable_recipes(recipes, unlocks, inventory, queue, context.temp_allocator))
	plans.craftable_key = key
}

// Plans the focused recipe's count and ingredients again when the key or
// the recipe changed.
refresh_recipe_detail_plan :: proc(plans: ^Recipe_Plans, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, inventory: Inventory, queue: Craft_Queue, recipe: int) {
	key := recipe_plan_key(queue, inventory, unlocks.available)
	if key == plans.detail_key && recipe == plans.detail_recipe {
		return
	}
	planned := planned_crafts(queue, inventory, recipes, unlocks, recipe, context.temp_allocator)
	clear(&plans.detail_inputs)
	append(&plans.detail_inputs, ..planned.inputs)
	plans.detail_key, plans.detail_recipe, plans.detail_count = key, recipe, planned.count
}

// The tags any recipe of the category carries, for the tag filter list.
category_tags :: proc(recipes: Recipe_Registry, category: Recipe_Category) -> Recipe_Tag_Set {
	tags: Recipe_Tag_Set
	for recipe in recipes.recipes {
		if recipe.category == category {
			tags += recipe.tags
		}
	}
	return tags
}

// Position in the visible list of the first recipe whose name starts with
// the letter, or failing that of the first one starting with a later
// letter, so a letter without recipes lands close by. -1 when there is
// none. The list is sorted by name.
recipe_position_for_letter :: proc(names: []string, visible: []int, letter: rune) -> int {
	wanted := unicode.to_lower(letter)
	for recipe, position in visible {
		if first_letter(names[recipe]) >= wanted {
			return position
		}
	}
	return -1
}

// A recipe the player has not unlocked is a silhouette: its name and
// category show, its ingredients and graph neighbours do not.
Recipe_Detail :: struct {
	revealed: bool,
	inputs:   []Item_Stack,
	outputs:  []Item_Stack,
	made_by:  []int,
	used_in:  []int,
}

// made_by lists the recipes producing the first output, used_in those
// consuming it; a recipe with fluid outputs only has neither.
recipe_detail :: proc(recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int, allocator := context.allocator) -> Recipe_Detail {
	if !recipe_is_available(unlocks, recipe) {
		return {}
	}
	definition := recipes.recipes[recipe]
	if len(definition.outputs) == 0 {
		return Recipe_Detail{revealed = true, inputs = definition.inputs}
	}
	product := definition.outputs[0].item
	return Recipe_Detail {
		revealed = true,
		inputs = definition.inputs,
		outputs = definition.outputs,
		made_by = recipes_making(recipes, product, allocator),
		used_in = recipes_using(recipes, product, allocator),
	}
}

// The filter that shows a recipe reached through the graph: its category,
// and the tag, craftable and unlocked filters dropped when they would hide
// it.
filter_showing_recipe :: proc(filter: Recipe_Filter, recipe: Recipe, craftable, available: bool) -> Recipe_Filter {
	result := filter
	result.category = recipe.category
	if result.tags & recipe.tags != result.tags {
		result.tags = {}
	}
	if result.craftable_only && !craftable {
		result.craftable_only = false
	}
	if result.available_only && !available {
		result.available_only = false
	}
	return result
}

// Letters bound to menu actions on the keyboard (WASD navigate, Q and E
// switch tabs, R is info, F the context action, C closes the browser), so
// they cannot also jump.
KEYBOARD_MENU_LETTERS :: "acdefqrsw"

letter_jumps_on_keyboard :: proc(letter: rune) -> bool {
	lower := unicode.to_lower(letter)
	for reserved in KEYBOARD_MENU_LETTERS {
		if reserved == lower {
			return false
		}
	}
	return lower >= 'a' && lower <= 'z'
}

LETTER_WHEEL_COUNT :: 26

letter_for_wheel_slot :: proc(slot: int) -> rune {
	return rune('a' + slot)
}
