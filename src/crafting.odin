package game

import "core:slice"

// Hand crafting: a queue of runs on the player, one recipe at a time at
// speed 1 (work item 0138). A run is a recipe and a number of crafts.
// Queuing takes nothing: it plans the crafts against a virtual inventory
// (the inventory plus what the queued runs will make minus what they will
// use) and queues the missing hand craftable intermediates ahead of the
// recipe. A craft takes its ingredients when it starts, at the front of
// the queue; a front craft whose ingredients are gone waits for them,
// until the next queue action puts the makers of what it lacks ahead of it
// (plan_front_repair). A
// finished craft whose outputs do not fit waits, with its progress kept,
// until they do.

HAND_CRAFT_QUEUE_RUNS :: 64
HAND_CRAFT_SPEED_PERCENT :: 100
// Intermediates resolve at most this deep, against recipe cycles.
HAND_CRAFT_PLAN_DEPTH :: 16

Craft_Run :: struct {
	recipe: int,
	count:  int,
}

// runs[0] is the front run. started is set while its first craft holds
// its ingredients and makes progress. waiting is set while that craft is
// finished and its outputs do not fit. waiting_for is the ingredient the
// front craft could not take when it tried to start, NO_ITEM otherwise.
// count is the number of runs; the field keeps the name it had when it
// counted single crafts, so remap_craft_queue can tell an older save.
Craft_Queue :: struct {
	runs:           [HAND_CRAFT_QUEUE_RUNS]Craft_Run,
	count:          int,
	progress_ticks: u32,
	started:        bool,
	waiting:        bool,
	waiting_for:    Item_Id,
}

// Why a craft could not be queued.
Craft_Refusal :: enum u8 {
	None,
	Locked,
	Not_Hand_Craftable,
	Missing_Ingredients,
	Recipe_Cycle,
	Plan_Too_Deep,
	Queue_Full,
}

@(rodata)
craft_refusal_keys := [Craft_Refusal]string {
	.None                = "",
	.Locked              = "craft_refused_locked",
	.Not_Hand_Craftable  = "craft_refused_not_by_hand",
	.Missing_Ingredients = "craft_refused_missing_ingredients",
	.Recipe_Cycle        = "craft_refused_cycle",
	.Plan_Too_Deep       = "craft_refused_too_deep",
	.Queue_Full          = "craft_refused_queue_full",
}

// The item a refused plan lacks and how many, or the item made from
// itself.
Craft_Shortage :: struct {
	item:  Item_Id,
	count: int,
}

make_craft_queue :: proc() -> Craft_Queue {
	return Craft_Queue{waiting_for = NO_ITEM}
}

recipe_is_hand_craftable :: proc(recipe: Recipe) -> bool {
	return .Hand in recipe.made_in
}

inventory_holds_inputs :: proc(inventory: Inventory, recipe: Recipe) -> bool {
	return first_missing_input(inventory, recipe) == NO_ITEM
}

// The first ingredient the inventory holds too few of, NO_ITEM when it
// holds them all.
first_missing_input :: proc(inventory: Inventory, recipe: Recipe) -> Item_Id {
	for input in recipe.inputs {
		if inventory_count(inventory, input.item) < int(input.count) {
			return input.item
		}
	}
	return NO_ITEM
}

// Whether the recipe itself may be crafted by hand; the plan checks the
// ingredients.
craft_refusal :: proc(recipe: Recipe, available: bool) -> Craft_Refusal {
	switch {
	case !available:
		return .Locked
	case !recipe_is_hand_craftable(recipe):
		return .Not_Hand_Craftable
	}
	return .None
}

// Available, by hand and with the inputs at hand; the queue is not asked.
recipe_craftable_now :: proc(inventory: Inventory, recipe: Recipe, available: bool) -> bool {
	return available && recipe_is_hand_craftable(recipe) && inventory_holds_inputs(inventory, recipe)
}

queued_craft_count :: proc(queue: Craft_Queue) -> int {
	queue := queue
	total := 0
	for run in queue.runs[:queue.count] {
		total += run.count
	}
	return total
}

// The front craft could not take its ingredients and waits for waiting_for.
craft_queue_waits_for_input :: proc(queue: Craft_Queue) -> bool {
	return queue.count > 0 && !queue.started && queue.waiting_for != NO_ITEM
}

// The first available hand recipe in registry order whose first product
// is the item, NO_RECIPE when there is none.
hand_recipe_making :: proc(recipes: Recipe_Registry, available: []bool, item: Item_Id) -> int {
	for recipe, index in recipes.recipes {
		if len(recipe.outputs) > 0 && recipe.outputs[0].item == item && recipe_is_hand_craftable(recipe) && index < len(available) && available[index] {
			return index
		}
	}
	return NO_RECIPE
}

// The plan of one queue action. virtual holds what the queued runs and
// the planned ones change against the inventory; resolving the recipes
// being resolved, outermost first.
Craft_Plan :: struct {
	inventory: Inventory,
	recipes:   Recipe_Registry,
	available: []bool,
	virtual:   map[Item_Id]int,
	resolving: [dynamic]int,
	runs:      [dynamic]Craft_Run,
	refusal:   Craft_Refusal,
	shortage:  Craft_Shortage,
}

make_craft_plan :: proc(inventory: Inventory, recipes: Recipe_Registry, available: []bool) -> Craft_Plan {
	return Craft_Plan {
		inventory = inventory,
		recipes = recipes,
		available = available,
		virtual = make(map[Item_Id]int, context.temp_allocator),
		resolving = make([dynamic]int, context.temp_allocator),
		runs = make([dynamic]Craft_Run, context.temp_allocator),
	}
}

// Never below zero: a plan does not count on covering a deficit of runs
// already queued, which only items spent or dropped after queuing make
// (plan_front_repair covers the front's).
virtual_count :: proc(plan: Craft_Plan, item: Item_Id) -> int {
	return max(inventory_count(plan.inventory, item) + plan.virtual[item], 0)
}

change_virtual :: proc(plan: ^Craft_Plan, stacks: []Item_Stack, crafts: int) {
	for stack in stacks {
		plan.virtual[stack.item] += int(stack.count) * crafts
	}
}

// Runs to come: their outputs come in and their inputs go out.
add_planned_runs :: proc(plan: ^Craft_Plan, runs: []Craft_Run) {
	for run in runs {
		recipe := plan.recipes.recipes[run.recipe]
		change_virtual(plan, recipe.outputs, run.count)
		change_virtual(plan, recipe.inputs, -run.count)
	}
}

// The queued runs like add_planned_runs, except the inputs of the craft
// in progress, which it already took.
add_queued_runs :: proc(plan: ^Craft_Plan, queue: Craft_Queue) {
	queue := queue
	for run, position in queue.runs[:queue.count] {
		recipe := plan.recipes.recipes[run.recipe]
		taken := position == 0 && queue.started ? 1 : 0
		change_virtual(plan, recipe.outputs, run.count)
		change_virtual(plan, recipe.inputs, -(run.count - taken))
	}
}

// Appends a run, growing the last one when it has the same recipe.
append_run :: proc(runs: ^[dynamic]Craft_Run, run: Craft_Run) {
	if len(runs) > 0 && runs[len(runs) - 1].recipe == run.recipe {
		runs[len(runs) - 1].count += run.count
		return
	}
	append(runs, run)
}

// Plans each short ingredient of the crafts and takes the ingredients
// off the virtual inventory.
plan_inputs :: proc(plan: ^Craft_Plan, recipe, crafts: int) -> bool {
	for input in plan.recipes.recipes[recipe].inputs {
		need := int(input.count) * crafts
		if short := need - virtual_count(plan^, input.item); short > 0 {
			plan_intermediate(plan, input.item, short) or_return
		}
		change_virtual(plan, []Item_Stack{input}, -crafts)
	}
	return true
}

// Plans crafts of the recipe: each short ingredient first, then the run.
plan_recipe :: proc(plan: ^Craft_Plan, recipe, crafts: int) -> bool {
	append(&plan.resolving, recipe)
	plan_inputs(plan, recipe, crafts) or_return
	pop(&plan.resolving)
	change_virtual(plan, plan.recipes.recipes[recipe].outputs, crafts)
	append_run(&plan.runs, {recipe, crafts})
	return true
}

// Enough crafts of the item's hand recipe to cover the shortage.
plan_intermediate :: proc(plan: ^Craft_Plan, item: Item_Id, short: int) -> bool {
	maker := hand_recipe_making(plan.recipes, plan.available, item)
	switch {
	case maker == NO_RECIPE:
		plan.refusal, plan.shortage = .Missing_Ingredients, {item, short}
		return false
	case slice.contains(plan.resolving[:], maker):
		plan.refusal, plan.shortage = .Recipe_Cycle, {item, short}
		return false
	case len(plan.resolving) >= HAND_CRAFT_PLAN_DEPTH:
		plan.refusal, plan.shortage = .Plan_Too_Deep, {item, short}
		return false
	}
	per_craft := max(int(plan.recipes.recipes[maker].outputs[0].count), 1)
	return plan_recipe(plan, maker, (short + per_craft - 1) / per_craft)
}

// The runs that make what a front run waiting for an ingredient lacks for
// all its crafts, planned against the inventory alone, to go in ahead of
// it. Empty when the front does not wait or the plan fails (no maker, a
// raw shortage, a cycle): the front keeps waiting.
plan_front_repair :: proc(queue: Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, available: []bool) -> []Craft_Run {
	if !craft_queue_waits_for_input(queue) {
		return nil
	}
	plan := make_craft_plan(inventory, recipes, available)
	front := queue.runs[0]
	append(&plan.resolving, front.recipe)
	if !plan_inputs(&plan, front.recipe, front.count) {
		return nil
	}
	return plan.runs[:]
}

// A queue action's plan: the runs to insert ahead of a waiting front
// (plan_front_repair), and the runs that queue count crafts of the recipe
// after what the queue holds, intermediates first, or the refusal and the
// item it names. Pure, in the temp allocator.
plan_crafts :: proc(queue: Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, available: []bool, recipe, count: int) -> (ahead, runs: []Craft_Run, refusal: Craft_Refusal, shortage: Craft_Shortage) {
	ahead = plan_front_repair(queue, inventory, recipes, available)
	plan := make_craft_plan(inventory, recipes, available)
	add_planned_runs(&plan, ahead)
	add_queued_runs(&plan, queue)
	if !plan_recipe(&plan, recipe, count) {
		return nil, nil, plan.refusal, plan.shortage
	}
	return ahead, plan.runs[:], .None, {}
}

// The number of runs the queue holds once the runs are appended.
queue_runs_after :: proc(queue: Craft_Queue, runs: []Craft_Run) -> int {
	total := queue.count
	last := queue.count > 0 ? queue.runs[queue.count - 1].recipe : NO_RECIPE
	for run in runs {
		total += run.recipe == last ? 0 : 1
		last = run.recipe
	}
	return total
}

reset_front_craft :: proc(queue: ^Craft_Queue) {
	queue.progress_ticks, queue.started, queue.waiting, queue.waiting_for = 0, false, false, NO_ITEM
}

// Grows the last run when it has the same recipe.
append_craft_run :: proc(queue: ^Craft_Queue, run: Craft_Run) {
	if queue.count > 0 && queue.runs[queue.count - 1].recipe == run.recipe {
		queue.runs[queue.count - 1].count += run.count
		return
	}
	if queue.count == 0 {
		reset_front_craft(queue)
	}
	queue.runs[queue.count] = run
	queue.count += 1
}

// Puts the runs in front of the queue; the front craft starts afresh.
insert_runs_ahead :: proc(queue: ^Craft_Queue, runs: []Craft_Run) {
	if len(runs) == 0 {
		return
	}
	copy(queue.runs[len(runs):queue.count + len(runs)], queue.runs[:queue.count])
	copy(queue.runs[:len(runs)], runs)
	queue.count += len(runs)
	reset_front_craft(queue)
}

// Queues count crafts of the recipe with the intermediates they need, all
// or nothing, and repairs a waiting front (plan_front_repair). Takes no
// ingredients. A count below one queues nothing.
queue_crafts :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe, count: int) -> (refusal: Craft_Refusal, shortage: Craft_Shortage) {
	if count < 1 {
		return .None, {}
	}
	if refusal = craft_refusal(recipes.recipes[recipe], recipe_is_available(unlocks, recipe)); refusal != .None {
		return refusal, {}
	}
	ahead, runs: []Craft_Run
	if ahead, runs, refusal, shortage = plan_crafts(queue^, inventory, recipes, unlocks.available, recipe, count); refusal != .None {
		return refusal, shortage
	}
	if queue_runs_after(queue^, runs) + len(ahead) > HAND_CRAFT_QUEUE_RUNS {
		return .Queue_Full, {}
	}
	insert_runs_ahead(queue, ahead)
	for run in runs {
		append_craft_run(queue, run)
	}
	return .None, {}
}

// The newest craft is the one in progress, holding its ingredients.
newest_craft_is_in_progress :: proc(queue: Craft_Queue) -> bool {
	return queue.count == 1 && queue.runs[0].count == 1 && queue.started
}

// Takes one craft off the newest run. Only the craft in progress holds
// ingredients, and gives them back; cancelling it is refused (false) when
// they no longer fit, so nothing is lost.
cancel_last_craft :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry) -> bool {
	if queue.count == 0 {
		return false
	}
	if newest_craft_is_in_progress(queue^) {
		recipe := recipes.recipes[queue.runs[0].recipe]
		if !inventory_fits_all(inventory, items, recipe.inputs) {
			return false
		}
		for input in recipe.inputs {
			inventory_add(inventory, items, input.item, int(input.count))
		}
	}
	queue.runs[queue.count - 1].count -= 1
	if queue.runs[queue.count - 1].count == 0 {
		queue.count -= 1
	}
	if queue.count == 0 {
		reset_front_craft(queue)
	}
	return true
}

// The front craft takes its ingredients, or names the first missing one.
start_front_craft :: proc(queue: ^Craft_Queue, inventory: Inventory, recipe: Recipe) -> bool {
	queue.waiting_for = first_missing_input(inventory, recipe)
	if queue.waiting_for != NO_ITEM {
		return false
	}
	for input in recipe.inputs {
		inventory_remove(inventory, input.item, int(input.count))
	}
	queue.started = true
	return true
}

finish_front_craft :: proc(queue: ^Craft_Queue) {
	queue.runs[0].count -= 1
	if queue.runs[0].count <= 0 {
		copy(queue.runs[:queue.count - 1], queue.runs[1:queue.count])
		queue.count -= 1
	}
	reset_front_craft(queue)
}

// One tick of hand crafting. Returns the recipe whose outputs went into
// the inventory this tick, or NO_RECIPE.
advance_crafting :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry, tick_rate: int) -> (finished: int) {
	if queue.count == 0 {
		return NO_RECIPE
	}
	finished = queue.runs[0].recipe
	recipe := recipes.recipes[finished]
	if !queue.started && !start_front_craft(queue, inventory, recipe) {
		return NO_RECIPE
	}
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
	finish_front_craft(queue)
	return finished
}

craft_progress_fraction :: proc(queue: Craft_Queue, recipes: Recipe_Registry, tick_rate: int) -> f32 {
	if queue.count == 0 {
		return 0
	}
	required := recipe_ticks(recipes.recipes[queue.runs[0].recipe], HAND_CRAFT_SPEED_PERCENT, tick_rate)
	return f32(queue.progress_ticks) / f32(required)
}
