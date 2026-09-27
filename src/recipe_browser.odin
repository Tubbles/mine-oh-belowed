package game

import "core:unicode"
import "core:unicode/utf8"

// The pure part of the recipe browser: filtering, the letter jump and what
// the detail panel may show. ui_recipes.odin draws it.

// The recipe list shows the recipes of one category that carry every
// selected tag, and with craftable_only only those craftable now.
Recipe_Filter :: struct {
	category:       Recipe_Category,
	tags:           Recipe_Tag_Set,
	craftable_only: bool,
}

recipe_matches_filter :: proc(recipe: Recipe, filter: Recipe_Filter, craftable: bool) -> bool {
	if recipe.category != filter.category || filter.tags & recipe.tags != filter.tags {
		return false
	}
	return craftable || !filter.craftable_only
}

// The recipes of the filter in the given order (by name).
filter_recipes :: proc(recipes: Recipe_Registry, order: []int, filter: Recipe_Filter, craftable: []bool, allocator := context.allocator) -> []int {
	visible := make([dynamic]int, 0, len(order), allocator)
	for recipe in order {
		if recipe_matches_filter(recipes.recipes[recipe], filter, craftable[recipe]) {
			append(&visible, recipe)
		}
	}
	return visible[:]
}

// Craftable now, per recipe.
craftable_recipes :: proc(recipes: Recipe_Registry, unlocks: Recipe_Unlocks, inventory: Inventory, allocator := context.allocator) -> []bool {
	craftable := make([]bool, len(recipes.recipes), allocator)
	for recipe, index in recipes.recipes {
		craftable[index] = recipe_craftable_now(inventory, recipe, recipe_is_available(unlocks, index))
	}
	return craftable
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

first_letter :: proc(name: string) -> rune {
	if len(name) == 0 {
		return 0
	}
	letter, _ := utf8.decode_rune_in_string(name)
	return unicode.to_lower(letter)
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
// consuming it.
recipe_detail :: proc(recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int, allocator := context.allocator) -> Recipe_Detail {
	if !recipe_is_available(unlocks, recipe) {
		return {}
	}
	definition := recipes.recipes[recipe]
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
// and the tag and craftable filters dropped when they would hide it.
filter_showing_recipe :: proc(filter: Recipe_Filter, recipe: Recipe, craftable: bool) -> Recipe_Filter {
	result := filter
	result.category = recipe.category
	if result.tags & recipe.tags != result.tags {
		result.tags = {}
	}
	if result.craftable_only && !craftable {
		result.craftable_only = false
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
