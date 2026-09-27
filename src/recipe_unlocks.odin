package game

// Which recipes are available, as simulation state. Start recipes always
// are; a discovery recipe once every input item has been obtained by any
// player; a research recipe once its technology is researched; a quest
// recipe once its main quest is done (work item 0013, so never yet).
// Unlocking everything (the --unlock-all flag or the world setting) marks
// every item obtained and every technology researched.
//
// An item counts as obtained once it has been in a player's inventory or
// on a player's cursor. That covers mining, crafting and taking from a
// machine alike, and the scan is cheap. Availability is recomputed only
// when that set grows or a technology is researched.

Recipe_Unlocks :: struct {
	// Indexed by Item_Id.
	obtained:   []bool,
	// Indexed by technology.
	researched: []bool,
	// Indexed by recipe.
	available:  []bool,
	unlock_all: bool,
}

make_recipe_unlocks :: proc(item_count: int, recipes: Recipe_Registry, technologies: Technology_Registry, unlock_all: bool, allocator := context.allocator) -> Recipe_Unlocks {
	unlocks := Recipe_Unlocks {
		obtained   = make([]bool, item_count, allocator),
		researched = make([]bool, len(technologies.technologies), allocator),
		available  = make([]bool, len(recipes.recipes), allocator),
		unlock_all = unlock_all,
	}
	if unlock_all {
		fill_bools(unlocks.obtained, true)
		fill_bools(unlocks.researched, true)
	}
	refresh_available_recipes(&unlocks, recipes)
	return unlocks
}

destroy_recipe_unlocks :: proc(unlocks: Recipe_Unlocks, allocator := context.allocator) {
	delete(unlocks.obtained, allocator)
	delete(unlocks.researched, allocator)
	delete(unlocks.available, allocator)
}

fill_bools :: proc(values: []bool, value: bool) {
	for &entry in values {
		entry = value
	}
}

all_inputs_obtained :: proc(recipe: Recipe, obtained: []bool) -> bool {
	for input in recipe.inputs {
		if !obtained[input.item] {
			return false
		}
	}
	return true
}

recipe_is_unlocked :: proc(unlocks: Recipe_Unlocks, recipe: Recipe) -> bool {
	if unlocks.unlock_all {
		return true
	}
	switch recipe.channel {
	case .Start:
		return true
	case .Discovery:
		return all_inputs_obtained(recipe, unlocks.obtained)
	case .Research:
		return recipe.technology != NO_TECHNOLOGY && unlocks.researched[recipe.technology]
	case .Quest:
		return false
	}
	return false
}

refresh_available_recipes :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry) {
	for recipe, index in recipes.recipes {
		unlocks.available[index] = recipe_is_unlocked(unlocks^, recipe)
	}
}

// Returns whether the item is newly obtained.
record_obtained_item :: proc(unlocks: ^Recipe_Unlocks, item: Item_Id) -> bool {
	if int(item) >= len(unlocks.obtained) || unlocks.obtained[item] {
		return false
	}
	unlocks.obtained[item] = true
	return true
}

record_obtained_slots :: proc(unlocks: ^Recipe_Unlocks, slots: []Item_Stack) -> bool {
	changed := false
	for slot in slots {
		if !stack_is_empty(slot) && record_obtained_item(unlocks, slot.item) {
			changed = true
		}
	}
	return changed
}

// Scans every player's inventory and cursor, and recomputes availability
// when something new turned up.
update_recipe_unlocks :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry, players: []Player) {
	changed := false
	for player in players {
		held := [1]Item_Stack{player.held.stack}
		changed = record_obtained_slots(unlocks, player.inventory.slots) || changed
		changed = record_obtained_slots(unlocks, held[:]) || changed
	}
	if changed {
		refresh_available_recipes(unlocks, recipes)
	}
}

// For the labs of M4.
mark_technology_researched :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry, technology: int) {
	unlocks.researched[technology] = true
	refresh_available_recipes(unlocks, recipes)
}

available_recipe_count :: proc(unlocks: Recipe_Unlocks) -> int {
	return count_true(unlocks.available)
}

obtained_item_count :: proc(unlocks: Recipe_Unlocks) -> int {
	return count_true(unlocks.obtained)
}

count_true :: proc(values: []bool) -> int {
	count := 0
	for value in values {
		count += value ? 1 : 0
	}
	return count
}

recipe_is_available :: proc(unlocks: Recipe_Unlocks, recipe: int) -> bool {
	return recipe >= 0 && recipe < len(unlocks.available) && unlocks.available[recipe]
}
