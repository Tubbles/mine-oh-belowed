package game

import "core:fmt"
import "core:strings"
import "platform"

// The quest runtime, ticked in the simulation. One quest is active at a
// time, chapter after chapter in data order. Every tick the active
// quest's objectives are compared with the statistics counters, the
// recipe unlocks and the reward target (the capsule, or the pod's locker
// on a field world); hints fire once when their counter has grown by the
// threshold since the quest became active. Completion logs Mission
// Control's line, queues the rewards for the reward target, unlocks
// quest channel recipes and technologies and activates the next quest in
// the same tick.
//
// obtain, craft, place, walk and ship count everything since the game
// began, so work done ahead of the journal counts ("quests guide, never
// block"), except a craft objective with produced_since_active. That one,
// counter and produce_fluid objectives count from activation. deliver
// counts what players put into the reward target since the quest became
// active and is still in it. sustain counts consecutive ticks at the rate, and
// with hands_off also without a world action. research is done once the
// technology is marked researched; for an infinite technology that
// happens when its first level finishes (apply_finished_research), even
// though technology_status never calls an infinite technology researched.

CAPSULE_LANDED_KEY :: "capsule_landed"
// The toast when rewards land in the pod's locker (work item 0210).
LOCKER_STOCKED_KEY :: "locker_stocked"
// The reward target's phrase in a quest text (work item 0210).
REWARD_TARGET_CAPSULE_KEY :: "reward_target_capsule"
REWARD_TARGET_LOCKER_KEY :: "reward_target_locker"
RESEARCH_COMPLETE_KEY :: "research_complete"
// Mission Control's line for a vein whose outcrop was mined away with
// units left (work item 0096).
OUTCROP_SPENT_KEY :: "mc_outcrop_spent"
// Where a message's argument text goes in its text, its value, and the
// cargo of its shipment.
MESSAGE_ARGUMENT_MARK :: "{name}"
MESSAGE_VALUE_MARK :: "{value}"
MESSAGE_CARGO_MARK :: "{cargo}"
MESSAGE_TARGET_MARK :: "{target}"

Quest_Status :: enum u8 {
	Locked,
	Active,
	Done,
}

Quest_Hint_Set :: bit_set[0 ..< MAXIMUM_QUEST_HINTS]

// Per quest; the arrays are indexed like the quest's hints and objectives.
Quest_Progress :: struct {
	status:               Quest_Status,
	activated_tick:       u64,
	hints_fired:          Quest_Hint_Set,
	hint_baselines:       [MAXIMUM_QUEST_HINTS]u64,
	delivered_baselines:  [MAXIMUM_QUEST_OBJECTIVES]u64,
	// The produced or counter value at activation, for objectives that
	// count from activation.
	activation_baselines: [MAXIMUM_QUEST_OBJECTIVES]u64,
	sustained_ticks:      [MAXIMUM_QUEST_OBJECTIVES]u64,
	// world_actions when the current sustain streak started.
	sustain_actions:      [MAXIMUM_QUEST_OBJECTIVES]u64,
}

// argument_key, when set, is the text that replaces MESSAGE_ARGUMENT_MARK.
// value replaces MESSAGE_VALUE_MARK. shipment, when not 0, is one more
// than the index into Game_Records.shipments whose cargo replaces
// MESSAGE_CARGO_MARK (work item 0041). item is the discovered item of an
// item_discovered message, for the HUD's discovery card (work item 0069);
// it is not saved, so a loaded message has none.
Quest_Message :: struct {
	tick:         u64,
	text_key:     string,
	argument_key: string,
	value:        u64,
	shipment:     u32,
	item:         Maybe(Item_Id),
}

Quest_State :: struct {
	// Indexed like Quest_Registry.quests.
	progress:        []Quest_Progress,
	// The active quest, or NO_QUEST once every quest is done.
	active:          int,
	capsule:         Entity_Handle,
	// Where rewards land and deliveries count (0210): the capsule, or the
	// pod's locker on a field world. Derived (settle_quest_reward_target),
	// never saved.
	reward_target:   Entity_Handle,
	// Reward items waiting for room in the reward target, never dropped.
	pending_rewards: [dynamic]Item_Stack,
	// Mission Control's lines, oldest first, for the journal.
	messages:        [dynamic]Quest_Message,
	// Toasts, emptied by the UI each frame.
	notices:         [dynamic]Quest_Message,
	hints_fired:     int,
}

// What objectives are measured against.
Quest_View :: struct {
	statistics:    Statistics,
	unlocks:       Recipe_Unlocks,
	capsule_slots: []Item_Stack,
	tick_rate:     int,
}

Objective_Progress :: struct {
	current:  u64,
	required: u64,
}

make_quest_state :: proc(registry: Quest_Registry, capsule: Entity_Handle, allocator := context.allocator) -> Quest_State {
	return Quest_State{progress = make([]Quest_Progress, len(registry.quests), allocator), active = NO_QUEST, capsule = capsule, reward_target = capsule}
}

// Pure: the pod's locker on a field world that has one, otherwise the
// capsule.
quest_reward_target :: proc(entities: ^Entities, machines: Machine_Registry, capsule: Entity_Handle, field_enabled: bool) -> Entity_Handle {
	if !field_enabled {
		return capsule
	}
	if locker, found := pod_locker(entities, machines); found {
		return locker
	}
	return capsule
}

// Derives the reward target at a new world and at load. When it changes,
// the delivery baseline is taken from the new target, so its contents do
// not count as delivered. A field world without a locker logs one line.
settle_quest_reward_target :: proc(quests: ^Quest_State, statistics: ^Statistics, entities: ^Entities, machines: Machine_Registry, field_enabled: bool) {
	target := quest_reward_target(entities, machines, quests.capsule, field_enabled)
	if field_enabled && target.kind != .Chest {
		platform.log_printf("quests: the pod has no locker; quest rewards go to the drop capsule")
	}
	if target != quests.reward_target {
		quests.reward_target = target
		snapshot_capsule(statistics, entity_slots(entities, target))
	}
}

// The string key of the reward target's phrase; NO_ENTITY reads as the
// capsule.
reward_target_name_key :: proc(target: Entity_Handle) -> string {
	return target.kind == .Chest ? REWARD_TARGET_LOCKER_KEY : REWARD_TARGET_CAPSULE_KEY
}

// The string key of the toast when rewards land in the target.
reward_landed_key :: proc(target: Entity_Handle) -> string {
	return target.kind == .Chest ? LOCKER_STOCKED_KEY : CAPSULE_LANDED_KEY
}

// The template with the reward target's phrase at MESSAGE_TARGET_MARK, in
// the temp allocator.
reward_target_text :: proc(template: string, target: Entity_Handle) -> string {
	return replace_message_mark(template, MESSAGE_TARGET_MARK, text(reward_target_name_key(target)))
}

destroy_quest_state :: proc(state: Quest_State, allocator := context.allocator) {
	delete(state.progress, allocator)
	delete(state.pending_rewards)
	delete(state.messages)
	delete(state.notices)
}

hint_counter_value :: proc(statistics: Statistics, hint: Hint) -> u64 {
	switch hint.counter {
	case .Blocks_Mined:
		return statistics.blocks_mined
	case .Mining_Ticks:
		return int(hint.block) < len(statistics.mining_ticks) ? statistics.mining_ticks[hint.block] : 0
	case .Distance_Walked:
		return statistics.distance_walked_millimetres / MILLIMETRES_PER_BLOCK
	case .Furnace_Out_Of_Fuel:
		return statistics.stalls[.Out_Of_Fuel]
	case .Furnace_Output_Full:
		return statistics.stalls[.Output_Full]
	case .Fuel_Burned:
		return statistics.fuel_burned
	case .Inventory_Full_Ticks:
		return statistics.inventory_full_ticks
	case .Inserter_Out_Of_Fuel:
		return statistics.stalls[.Inserter_Out_Of_Fuel]
	case .Inserter_Waiting_For_Room:
		return statistics.stalls[.Inserter_Waiting_For_Room]
	case .Inserter_Idle_Ticks:
		return statistics.inserter_idle_ticks
	case .Drill_Out_Of_Fuel:
		return statistics.stalls[.Drill_Out_Of_Fuel]
	case .Drill_Waiting_For_Room:
		return statistics.stalls[.Drill_Waiting_For_Room]
	case .Vein_Exhausted:
		return statistics.veins_exhausted
	case .Belt_Dead_End_Ticks:
		return statistics.belt_dead_end_ticks
	case .Inserter_Idle_A_Minute:
		return statistics.inserters_idle_a_minute
	case .Drill_Fuel_Burned:
		return statistics.drill_fuel_burned
	case .Brownout_Ticks:
		return statistics.brownout_ticks
	case .Unpowered_Machine_Ticks:
		return statistics.unpowered_machine_ticks
	case .Recycled:
		return statistics.recycled
	case .Mixing_Refusals:
		return statistics.mixing_refusals
	case .Flared_Litres:
		return statistics.flared_litres
	case .Generator_Gas_Litres:
		return statistics.generator_gas_litres
	case .Schematics_Found:
		return statistics.schematics_found
	case .Veins_Assayed:
		return statistics.veins_assayed
	case .Core_Samples_Taken:
		return statistics.core_samples_taken
	case .Seismic_Shots:
		return statistics.seismic_shots
	case .Veins_Resolved:
		return statistics.veins_resolved
	case .Bore_Drill_Units:
		return statistics.bore_drill_units
	case .Bore_Drill_No_Vein_Attempts:
		return statistics.bore_drill_no_vein_attempts
	case .Drill_No_Vein_Attempts:
		return statistics.drill_no_vein_attempts
	case .Turbine_Kilojoules:
		return statistics.turbine_joules / 1000
	case .Turbine_Still_Water_Ticks:
		return statistics.turbine_still_water_ticks
	case .Rockets_Launched:
		return statistics.rockets_launched
	case .Contracts_Completed:
		return statistics.contracts_completed
	case .Contracts_Late:
		return statistics.contracts_late
	case .Credit_Earned:
		return statistics.credit_earned
	case .Surveys_Bought:
		return statistics.surveys_bought
	case .Items_Shipped:
		return statistics.items_shipped
	case .Launch_Parts_Missing:
		return statistics.launch_parts_missing
	case .Launch_Cargo_Empty:
		return statistics.launch_cargo_empty
	}
	return 0
}

slots_item_count :: proc(slots: []Item_Stack, item: Item_Id) -> u64 {
	total: u64
	for slot in slots {
		if !stack_is_empty(slot) && slot.item == item {
			total += u64(slot.count)
		}
	}
	return total
}

sustain_required_ticks :: proc(objective: Objective, tick_rate: int) -> u64 {
	return (objective.minutes * 60 + objective.seconds) * u64(tick_rate)
}

bool_progress :: proc(done: bool) -> Objective_Progress {
	return {current = done ? 1 : 0, required = 1}
}

in_range :: proc(values: []bool, index: int) -> bool {
	return index >= 0 && index < len(values) && values[index]
}

delivered_progress :: proc(objective: Objective, baseline: u64, view: Quest_View) -> Objective_Progress {
	delivered := item_counter(view.statistics.delivered, objective.item) - baseline
	return {current = min(delivered, slots_item_count(view.capsule_slots, objective.item)), required = objective.count}
}

// Pure: how far one objective of a quest is.
objective_progress :: proc(objective: Objective, index: int, progress: Quest_Progress, view: Quest_View) -> Objective_Progress {
	statistics := view.statistics
	switch objective.type {
	case .Obtain:
		return {item_counter(statistics.obtained, objective.item), objective.count}
	case .Craft:
		baseline := objective.produced_since_active ? progress.activation_baselines[index] : 0
		return {item_counter(statistics.produced, objective.item) - baseline, objective.count}
	case .Place:
		return {placed_count(statistics, objective), objective.count}
	case .Walk:
		return {statistics.distance_walked_millimetres / MILLIMETRES_PER_BLOCK, objective.count}
	case .Research:
		return bool_progress(in_range(view.unlocks.researched, objective.technology))
	case .Discover:
		return bool_progress(in_range(view.unlocks.available, objective.recipe))
	case .Deliver:
		return delivered_progress(objective, progress.delivered_baselines[index], view)
	case .Sustain:
		return {progress.sustained_ticks[index], sustain_required_ticks(objective, view.tick_rate)}
	case .Counter:
		return {objective_counter_value(statistics, objective) - progress.activation_baselines[index], objective.count}
	case .Produce_Fluid:
		return {fluid_counter(statistics.fluids.produced, objective.fluid) - progress.activation_baselines[index], objective.count}
	case .Ship:
		return {shipped_count(statistics, objective.item), objective.count}
	}
	return {}
}

// Items of one kind shipped, or with NO_ITEM every item shipped.
shipped_count :: proc(statistics: Statistics, item: Item_Id) -> u64 {
	if item == NO_ITEM {
		return statistics.items_shipped
	}
	return item_counter(statistics.shipped, item)
}

// Machines placed, or blocks placed with the objective's item.
placed_count :: proc(statistics: Statistics, objective: Objective) -> u64 {
	if objective.machine == NO_MACHINE {
		return item_counter(statistics.blocks_placed, objective.item)
	}
	return int(objective.machine) < len(statistics.placed) ? statistics.placed[objective.machine] : 0
}

objective_counter_value :: proc(statistics: Statistics, objective: Objective) -> u64 {
	return hint_counter_value(statistics, Hint{counter = objective.counter})
}

// What an objective that counts from activation subtracts.
objective_activation_value :: proc(statistics: Statistics, objective: Objective) -> u64 {
	#partial switch objective.type {
	case .Craft:
		return item_counter(statistics.produced, objective.item)
	case .Counter:
		return objective_counter_value(statistics, objective)
	case .Produce_Fluid:
		return fluid_counter(statistics.fluids.produced, objective.fluid)
	}
	return 0
}

objective_done :: proc(value: Objective_Progress) -> bool {
	return value.current >= value.required
}

quest_objectives_done :: proc(quest: Quest, progress: Quest_Progress, view: Quest_View) -> bool {
	for objective, index in quest.objectives {
		if !objective_done(objective_progress(objective, index, progress, view)) {
			return false
		}
	}
	return true
}

// One tick of a sustain streak: it grows while the rate holds (and, hands
// off, while no world action happens) and starts over otherwise.
advance_sustain :: proc(progress: ^Quest_Progress, index: int, objective: Objective, statistics: Statistics) {
	rate_holds := production_rate_per_minute(statistics, objective.item) >= objective.rate_per_minute
	untouched := !objective.hands_off || statistics.world_actions == progress.sustain_actions[index]
	if rate_holds && untouched {
		progress.sustained_ticks[index] += 1
		return
	}
	progress.sustained_ticks[index] = 0
	progress.sustain_actions[index] = statistics.world_actions
}

advance_sustains :: proc(progress: ^Quest_Progress, quest: Quest, statistics: Statistics) {
	for objective, index in quest.objectives {
		if objective.type == .Sustain {
			advance_sustain(progress, index, objective, statistics)
		}
	}
}

log_quest_message :: proc(state: ^Quest_State, tick: u64, key: string, argument_key := "") {
	log_message(state, Quest_Message{tick = tick, text_key = key, argument_key = argument_key})
}

// Into the message log and the toasts.
log_message :: proc(state: ^Quest_State, message: Quest_Message) {
	if message.text_key == "" {
		return
	}
	append(&state.messages, message)
	append(&state.notices, message)
}

// A finished technology, in the log and as a toast.
log_research_complete :: proc(state: ^Quest_State, tick: u64, technology_name_key: string) {
	log_quest_message(state, tick, RESEARCH_COMPLETE_KEY, technology_name_key)
}

// The shipments and items fill in a shipment's cargo, the reward target
// its phrase.
quest_message_text :: proc(message: Quest_Message, shipments: []Shipment, items: Item_Registry, reward_target: Entity_Handle) -> string {
	result := text(message.text_key)
	if message.argument_key != "" {
		result = format_message_text(result, text(message.argument_key))
	}
	result = replace_message_mark(result, MESSAGE_VALUE_MARK, fmt.tprintf("%d", message.value))
	result = reward_target_text(result, reward_target)
	if message.shipment > 0 && int(message.shipment) <= len(shipments) {
		result = replace_message_mark(result, MESSAGE_CARGO_MARK, shipment_cargo_text(shipments[message.shipment - 1], items))
	}
	return result
}

// In the temp allocator.
replace_message_mark :: proc(template, mark, value: string) -> string {
	result, _ := strings.replace_all(template, mark, value, context.temp_allocator)
	return result
}

// In the temp allocator.
format_message_text :: proc(template, argument: string) -> string {
	result, _ := strings.replace_all(template, MESSAGE_ARGUMENT_MARK, argument, context.temp_allocator)
	return result
}

// Hints fire once, when their counter has grown by the threshold since
// the quest became active.
fire_hints :: proc(state: ^Quest_State, quest: Quest, progress: ^Quest_Progress, statistics: Statistics, tick: u64) {
	for hint, index in quest.hints {
		if index in progress.hints_fired {
			continue
		}
		if hint_counter_value(statistics, hint) - progress.hint_baselines[index] >= hint.threshold {
			progress.hints_fired += {index}
			state.hints_fired += 1
			log_quest_message(state, tick, hint.text_key)
		}
	}
}

activate_quest :: proc(state: ^Quest_State, registry: Quest_Registry, index: int, statistics: Statistics, tick: u64) {
	state.active = index
	if index == NO_QUEST {
		return
	}
	quest := registry.quests[index]
	progress := &state.progress[index]
	progress^ = Quest_Progress{status = .Active, activated_tick = tick}
	for hint, hint_index in quest.hints {
		progress.hint_baselines[hint_index] = hint_counter_value(statistics, hint)
	}
	for objective, objective_index in quest.objectives {
		progress.delivered_baselines[objective_index] = item_counter(statistics.delivered, objective.item)
		progress.sustain_actions[objective_index] = statistics.world_actions
		progress.activation_baselines[objective_index] = objective_activation_value(statistics, objective)
	}
	log_quest_message(state, tick, quest.message_key)
}

// The first quest, at the start of a game.
start_quests :: proc(state: ^Quest_State, registry: Quest_Registry, statistics: Statistics, tick: u64) {
	if len(registry.quests) > 0 {
		activate_quest(state, registry, 0, statistics, tick)
	}
}

// Removes up to count of the item, last slots first.
remove_from_slots :: proc(slots: []Item_Stack, item: Item_Id, count: u64) {
	remaining := int(count)
	#reverse for &slot in slots {
		if remaining > 0 && !stack_is_empty(slot) && slot.item == item {
			remaining -= take_from_slot(&slot, remaining)
		}
	}
}

// Delivered items leave the reward target (the capsule, or the pod's
// locker on a field world) when their quest completes.
consume_deliveries :: proc(quest: Quest, capsule_slots: []Item_Stack) {
	for objective in quest.objectives {
		if objective.type == .Deliver {
			remove_from_slots(capsule_slots, objective.item, objective.count)
		}
	}
}

queue_rewards :: proc(state: ^Quest_State, quest: Quest, unlocks: ^Recipe_Unlocks, recipes: Recipe_Registry) {
	append(&state.pending_rewards, ..quest.reward_items)
	for recipe in quest.reward_recipes {
		unlock_quest_recipe(unlocks, recipes, recipe)
	}
	for technology in quest.reward_technologies {
		mark_technology_researched(unlocks, recipes, technology)
	}
}

next_quest :: proc(registry: Quest_Registry, index: int) -> int {
	return index + 1 < len(registry.quests) ? index + 1 : NO_QUEST
}

Quest_Tick_Context :: struct {
	registry:   Quest_Registry,
	recipes:    Recipe_Registry,
	items:      Item_Registry,
	statistics: ^Statistics,
	unlocks:    ^Recipe_Unlocks,
	tick:       u64,
	tick_rate:  int,
}

complete_active_quest :: proc(state: ^Quest_State, tick_context: Quest_Tick_Context, capsule_slots: []Item_Stack) {
	index := state.active
	quest := tick_context.registry.quests[index]
	state.progress[index].status = .Done
	consume_deliveries(quest, capsule_slots)
	log_quest_message(state, tick_context.tick, quest.complete_key)
	queue_rewards(state, quest, tick_context.unlocks, tick_context.recipes)
	activate_quest(state, tick_context.registry, next_quest(tick_context.registry, index), tick_context.statistics^, tick_context.tick)
}

quest_view :: proc(tick_context: Quest_Tick_Context, capsule_slots: []Item_Stack) -> Quest_View {
	return Quest_View{statistics = tick_context.statistics^, unlocks = tick_context.unlocks^, capsule_slots = capsule_slots, tick_rate = tick_context.tick_rate}
}

// Advances the active quest and completes it when every objective is
// met; a quest done at activation completes in the same tick, so several
// may complete at once.
advance_active_quests :: proc(state: ^Quest_State, tick_context: Quest_Tick_Context, capsule_slots: []Item_Stack) {
	for _ in 0 ..< len(tick_context.registry.quests) {
		if state.active == NO_QUEST {
			return
		}
		quest := tick_context.registry.quests[state.active]
		progress := &state.progress[state.active]
		advance_sustains(progress, quest, tick_context.statistics^)
		fire_hints(state, quest, progress, tick_context.statistics^, tick_context.tick)
		if !quest_objectives_done(quest, progress^, quest_view(tick_context, capsule_slots)) {
			return
		}
		complete_active_quest(state, tick_context, capsule_slots)
	}
}

// Rewards land in the reward target (the capsule, or the pod's locker on
// a field world) as far as they fit; the rest waits for room.
// Returns whether anything landed.
land_rewards :: proc(pending: ^[dynamic]Item_Stack, capsule_slots: []Item_Stack, items: Item_Registry) -> bool {
	landed := false
	index := 0
	for index < len(pending) {
		stack := &pending[index]
		left := add_to_slots(capsule_slots, stack.item, int(stack.count), item_stack_size(items, stack.item))
		landed ||= left < int(stack.count)
		stack.count = u16(left)
		if left == 0 {
			ordered_remove(pending, index)
		} else {
			index += 1
		}
	}
	return landed
}

// One line per outcrop mined away since the last announcement, whatever
// quest is active. The counts live in the saved statistics, so a line is
// neither lost nor repeated across a save.
announce_spent_outcrops :: proc(state: ^Quest_State, statistics: ^Statistics, tick: u64) {
	for statistics.outcrops_spent_announced < statistics.outcrops_spent {
		statistics.outcrops_spent_announced += 1
		log_quest_message(state, tick, OUTCROP_SPENT_KEY)
	}
}

tick_quests :: proc(state: ^Quest_State, tick_context: Quest_Tick_Context, entities: ^Entities) {
	announce_spent_outcrops(state, tick_context.statistics, tick_context.tick)
	target_slots := entity_slots(entities, state.reward_target)
	observe_capsule(tick_context.statistics, target_slots)
	advance_active_quests(state, tick_context, target_slots)
	if land_rewards(&state.pending_rewards, target_slots, tick_context.items) {
		append(&state.notices, Quest_Message{tick = tick_context.tick, text_key = reward_landed_key(state.reward_target)})
	}
	snapshot_capsule(tick_context.statistics, target_slots)
}
