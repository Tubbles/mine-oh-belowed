package game

// Which recipes are available, as simulation state. Start recipes always
// are; a discovery recipe once every input item has been obtained by any
// player; a research recipe once its technology is researched; a quest
// recipe once a quest reward unlocks it (quest_runtime.odin); a schematic
// recipe once its schematic was read (schematic.odin). Unlocking
// everything (the --unlock-all flag or the world setting) marks every item
// obtained, every technology researched and every schematic found.
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
	// Indexed by recipe: unlocked by a quest reward.
	quest_unlocked: []bool,
	// Indexed by recipe: a schematic channel recipe whose schematic was
	// read. Machines make a schematic alternate only once it is found
	// (recipe_runs_in_machines).
	schematics_found: []bool,
	// Indexed by recipe.
	available:  []bool,
	unlock_all: bool,
}

make_recipe_unlocks :: proc(item_count: int, recipes: Recipe_Registry, technologies: Technology_Registry, unlock_all: bool, allocator := context.allocator) -> Recipe_Unlocks {
	unlocks := Recipe_Unlocks {
		obtained   = make([]bool, item_count, allocator),
		researched = make([]bool, len(technologies.technologies), allocator),
		quest_unlocked = make([]bool, len(recipes.recipes), allocator),
		schematics_found = make([]bool, len(recipes.recipes), allocator),
		available  = make([]bool, len(recipes.recipes), allocator),
		unlock_all = unlock_all,
	}
	if unlock_all {
		fill_bools(unlocks.obtained, true)
		fill_bools(unlocks.researched, true)
		fill_bools(unlocks.schematics_found, true)
	}
	refresh_available_recipes(&unlocks, recipes)
	return unlocks
}

destroy_recipe_unlocks :: proc(unlocks: Recipe_Unlocks, allocator := context.allocator) {
	delete(unlocks.obtained, allocator)
	delete(unlocks.researched, allocator)
	delete(unlocks.quest_unlocked, allocator)
	delete(unlocks.schematics_found, allocator)
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

recipe_is_unlocked :: proc(unlocks: Recipe_Unlocks, recipe: Recipe, index: int) -> bool {
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
		return index < len(unlocks.quest_unlocked) && unlocks.quest_unlocked[index]
	case .Schematic:
		return index < len(unlocks.schematics_found) && unlocks.schematics_found[index]
	}
	return false
}

refresh_available_recipes :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry) {
	for recipe, index in recipes.recipes {
		unlocks.available[index] = recipe_is_unlocked(unlocks^, recipe, index)
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

// The quest channel: a quest reward's unlocks_recipe.
unlock_quest_recipe :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry, recipe: int) {
	unlocks.quest_unlocked[recipe] = true
	refresh_available_recipes(unlocks, recipes)
}

// The schematic channel. Returns whether the schematic is newly found.
record_found_schematic :: proc(unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry, recipe: int) -> bool {
	if unlocks.schematics_found[recipe] {
		return false
	}
	unlocks.schematics_found[recipe] = true
	refresh_available_recipes(unlocks, recipes)
	return true
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
