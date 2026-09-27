package game

// Hand crafting: a short queue on the player, one recipe at a time at
// speed 1. Ingredients leave the inventory when an entry is queued and come
// back when it is cancelled. A finished craft whose outputs do not fit
// waits, with its progress kept, until they do.

HAND_CRAFT_QUEUE_CAPACITY :: 8
HAND_CRAFT_SPEED_PERCENT :: 100

// recipes[0] is the one in progress. waiting is set while a finished
// craft's outputs do not fit.
Craft_Queue :: struct {
	recipes:        [HAND_CRAFT_QUEUE_CAPACITY]int,
	count:          int,
	progress_ticks: u32,
	waiting:        bool,
}

// Why a craft could not be queued.
Craft_Refusal :: enum u8 {
	None,
	Locked,
	Not_Hand_Craftable,
	Missing_Ingredients,
	Queue_Full,
}

@(rodata)
craft_refusal_keys := [Craft_Refusal]string {
	.None                = "",
	.Locked              = "craft_refused_locked",
	.Not_Hand_Craftable  = "craft_refused_not_by_hand",
	.Missing_Ingredients = "craft_refused_missing_ingredients",
	.Queue_Full          = "craft_refused_queue_full",
}

recipe_is_hand_craftable :: proc(recipe: Recipe) -> bool {
	return .Hand in recipe.made_in
}

inventory_holds_inputs :: proc(inventory: Inventory, recipe: Recipe) -> bool {
	for input in recipe.inputs {
		if inventory_count(inventory, input.item) < int(input.count) {
			return false
		}
	}
	return true
}

craft_refusal :: proc(queue: Craft_Queue, inventory: Inventory, recipe: Recipe, available: bool) -> Craft_Refusal {
	switch {
	case !available:
		return .Locked
	case !recipe_is_hand_craftable(recipe):
		return .Not_Hand_Craftable
	case queue.count == HAND_CRAFT_QUEUE_CAPACITY:
		return .Queue_Full
	case !inventory_holds_inputs(inventory, recipe):
		return .Missing_Ingredients
	}
	return .None
}

// Available, by hand and with the inputs at hand; the queue is not asked.
recipe_craftable_now :: proc(inventory: Inventory, recipe: Recipe, available: bool) -> bool {
	return available && recipe_is_hand_craftable(recipe) && inventory_holds_inputs(inventory, recipe)
}

// Takes the ingredients and appends the recipe.
queue_craft :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int) -> Craft_Refusal {
	refusal := craft_refusal(queue^, inventory, recipes.recipes[recipe], recipe_is_available(unlocks, recipe))
	if refusal != .None {
		return refusal
	}
	for input in recipes.recipes[recipe].inputs {
		inventory_remove(inventory, input.item, int(input.count))
	}
	queue.recipes[queue.count] = recipe
	queue.count += 1
	return .None
}

// Queues up to count crafts and returns how many were queued, with the
// refusal that stopped it (None when all were queued).
queue_crafts :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe, count: int) -> (queued: int, refusal: Craft_Refusal) {
	for queued < count {
		if refusal = queue_craft(queue, inventory, recipes, unlocks, recipe); refusal != .None {
			return queued, refusal
		}
		queued += 1
	}
	return queued, .None
}

// Cancels the newest entry and returns its ingredients. Refused (false)
// when they no longer fit, so nothing is lost.
cancel_last_craft :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry) -> bool {
	if queue.count == 0 {
		return false
	}
	recipe := recipes.recipes[queue.recipes[queue.count - 1]]
	if !inventory_fits_all(inventory, items, recipe.inputs) {
		return false
	}
	for input in recipe.inputs {
		inventory_add(inventory, items, input.item, int(input.count))
	}
	queue.count -= 1
	if queue.count == 0 {
		queue.progress_ticks, queue.waiting = 0, false
	}
	return true
}

pop_front_craft :: proc(queue: ^Craft_Queue) {
	copy(queue.recipes[:queue.count - 1], queue.recipes[1:queue.count])
	queue.count -= 1
	queue.progress_ticks, queue.waiting = 0, false
}

// One tick of hand crafting. Returns the recipe whose outputs went into
// the inventory this tick, or NO_RECIPE.
advance_crafting :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry, tick_rate: int) -> (finished: int) {
	if queue.count == 0 {
		return NO_RECIPE
	}
	finished = queue.recipes[0]
	recipe := recipes.recipes[finished]
	required := recipe_ticks(recipe, HAND_CRAFT_SPEED_PERCENT, tick_rate)
	queue.progress_ticks = min(queue.progress_ticks + 1, required)
	if queue.progress_ticks < required {
		return NO_RECIPE
	}
	if !inventory_fits_all(inventory, items, recipe.outputs) {
		queue.waiting = true
		return NO_RECIPE
	}
	for output in recipe.outputs {
		inventory_add(inventory, items, output.item, int(output.count))
	}
	pop_front_craft(queue)
	return finished
}

craft_progress_fraction :: proc(queue: Craft_Queue, recipes: Recipe_Registry, tick_rate: int) -> f32 {
	if queue.count == 0 {
		return 0
	}
	required := recipe_ticks(recipes.recipes[queue.recipes[0]], HAND_CRAFT_SPEED_PERCENT, tick_rate)
	return f32(queue.progress_ticks) / f32(required)
}
