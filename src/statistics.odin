package game

import "core:math"

// Production statistics, the day one system of doc/architecture.md. Every
// counter is a u64 in the simulation, bumped where its event happens:
// crafting completion, furnace output, mining, placement. The quest
// runtime, the journal and later the statistics screen read them.
//
// Two counters are measured as differences across a tick instead of at a
// call site, because the UI moves stacks between ticks: obtained (what
// players hold grew) and delivered (what the capsule holds grew).
//
// Arrays are sized by make_statistics. A World made without it (tests)
// has empty arrays, and recording into them does nothing.

// The rolling rate per item is a ring of per second buckets.
RATE_BUCKET_COUNT :: 60
MILLIMETRES_PER_BLOCK :: 1000

// Out_Of_Fuel and Output_Full are furnace stalls.
Machine_Stall :: enum u8 {
	Out_Of_Fuel,
	Output_Full,
	Inserter_Out_Of_Fuel,
	Inserter_Waiting_For_Room,
	Drill_Out_Of_Fuel,
	Drill_Waiting_For_Room,
}

Statistics :: struct {
	// Indexed by Item_Id. produced counts crafted and smelted outputs,
	// obtained counts growth of what players hold (mined, taken from a
	// machine or the capsule, crafted), delivered counts growth of what
	// the capsule holds that did not land there as a reward.
	produced:                    []u64,
	obtained:                    []u64,
	delivered:                   []u64,
	// Indexed by Machine_Id: how often a player placed one.
	placed:                      []u64,
	// Indexed by Block_Id: ticks spent holding Mine on a block of the type.
	mining_ticks:                []u64,
	stalls:                      [Machine_Stall]u64,
	fuel_burned:                 u64,
	blocks_mined:                u64,
	distance_walked_millimetres: u64,
	// Ticks during which some player's inventory had no empty slot.
	inventory_full_ticks:        u64,
	// Summed over inserters: ticks one stood at its pickup cell with
	// nothing it could pick.
	inserter_idle_ticks:         u64,
	// Finite veins drills drained to the last unit.
	veins_exhausted:             u64,
	// Mining, placing, picking up and opening a machine. hands_off
	// sustain objectives break when this changes.
	world_actions:               u64,
	// Items produced per second, RATE_BUCKET_COUNT buckets per item, the
	// bucket of a second at second % RATE_BUCKET_COUNT.
	produced_per_second:         []u32,
	current_second:              u64,
	// What players held and the capsule held after the previous tick.
	held_totals:                 []u32,
	capsule_totals:              []u32,
}

make_statistics :: proc(item_count, machine_count, block_count: int, allocator := context.allocator) -> Statistics {
	return Statistics {
		produced = make([]u64, item_count, allocator),
		obtained = make([]u64, item_count, allocator),
		delivered = make([]u64, item_count, allocator),
		placed = make([]u64, machine_count, allocator),
		mining_ticks = make([]u64, block_count, allocator),
		produced_per_second = make([]u32, item_count * RATE_BUCKET_COUNT, allocator),
		held_totals = make([]u32, item_count, allocator),
		capsule_totals = make([]u32, item_count, allocator),
	}
}

destroy_statistics :: proc(statistics: Statistics, allocator := context.allocator) {
	delete(statistics.produced, allocator)
	delete(statistics.obtained, allocator)
	delete(statistics.delivered, allocator)
	delete(statistics.placed, allocator)
	delete(statistics.mining_ticks, allocator)
	delete(statistics.produced_per_second, allocator)
	delete(statistics.held_totals, allocator)
	delete(statistics.capsule_totals, allocator)
}

item_counter :: proc(counters: []u64, item: Item_Id) -> u64 {
	return int(item) < len(counters) ? counters[item] : 0
}

// The rate ring. The bucket of the current second is cleared when the
// second begins; seconds skipped without a tick are cleared too.
advance_statistics_clock :: proc(statistics: ^Statistics, tick: u64, tick_rate: int) {
	second := tick / u64(max(tick_rate, 1))
	if second == statistics.current_second {
		return
	}
	cleared := min(second - statistics.current_second, RATE_BUCKET_COUNT)
	for offset in 0 ..< cleared {
		clear_rate_bucket(statistics, int((second - offset) % RATE_BUCKET_COUNT))
	}
	statistics.current_second = second
}

clear_rate_bucket :: proc(statistics: ^Statistics, bucket: int) {
	for item_start := 0; item_start < len(statistics.produced_per_second); item_start += RATE_BUCKET_COUNT {
		statistics.produced_per_second[item_start + bucket] = 0
	}
}

record_produced :: proc(statistics: ^Statistics, item: Item_Id, count: int) {
	if int(item) >= len(statistics.produced) || count <= 0 {
		return
	}
	statistics.produced[item] += u64(count)
	bucket := int(item) * RATE_BUCKET_COUNT + int(statistics.current_second % RATE_BUCKET_COUNT)
	statistics.produced_per_second[bucket] += u32(count)
}

record_produced_stacks :: proc(statistics: ^Statistics, stacks: []Item_Stack) {
	for stack in stacks {
		record_produced(statistics, stack.item, int(stack.count))
	}
}

// Items produced over the last minute: the current second so far plus
// the 59 before it.
production_rate_per_minute :: proc(statistics: Statistics, item: Item_Id) -> u64 {
	start := int(item) * RATE_BUCKET_COUNT
	if start + RATE_BUCKET_COUNT > len(statistics.produced_per_second) {
		return 0
	}
	total: u64
	for count in statistics.produced_per_second[start:start + RATE_BUCKET_COUNT] {
		total += u64(count)
	}
	return total
}

record_placed :: proc(statistics: ^Statistics, machine: Machine_Id) {
	if int(machine) < len(statistics.placed) {
		statistics.placed[machine] += 1
	}
	statistics.world_actions += 1
}

record_mining_tick :: proc(statistics: ^Statistics, block: Block_Id) {
	if int(block) < len(statistics.mining_ticks) {
		statistics.mining_ticks[block] += 1
	}
}

record_block_mined :: proc(statistics: ^Statistics) {
	statistics.blocks_mined += 1
	statistics.world_actions += 1
}

record_world_action :: proc(statistics: ^Statistics) {
	statistics.world_actions += 1
}

// Horizontal distance only, so jumping in place walks nowhere.
record_walked :: proc(statistics: ^Statistics, from, to: [3]f32) {
	distance := math.sqrt((to.x - from.x) * (to.x - from.x) + (to.z - from.z) * (to.z - from.z))
	statistics.distance_walked_millimetres += u64(math.round(distance * MILLIMETRES_PER_BLOCK))
}

// Output slots only grow and fuel slots only shrink inside a furnace
// tick, so the differences are what it smelted and burned. A stall counts
// when the furnace enters the state, not for every tick it stays there.
record_furnace_tick :: proc(statistics: ^Statistics, before, after: Furnace) {
	output_before, output_after := before.slots[FURNACE_OUTPUT_SLOT], after.slots[FURNACE_OUTPUT_SLOT]
	if !stack_is_empty(output_after) && output_after.count > output_before.count {
		grown := int(output_after.count) - (output_before.item == output_after.item ? int(output_before.count) : 0)
		record_produced(statistics, output_after.item, grown)
	}
	fuel_before, fuel_after := before.slots[FURNACE_FUEL_SLOT], after.slots[FURNACE_FUEL_SLOT]
	if fuel_after.count < fuel_before.count {
		statistics.fuel_burned += u64(fuel_before.count - fuel_after.count)
	}
	if after.state == before.state {
		return
	}
	#partial switch after.state {
	case .No_Fuel:
		statistics.stalls[.Out_Of_Fuel] += 1
	case .Output_Full:
		statistics.stalls[.Output_Full] += 1
	}
}

// A fuel item was lit when the buffer grew: lighting adds a whole item's
// joules, far more than one tick burns. Unlike a slot count difference
// this also sees an item an inserter fed itself and burned in one tick.
fuel_item_lit :: proc(joules_before, joules_after: u32) -> bool {
	return joules_after > joules_before
}

// Like record_furnace_tick: fuel burned, idle ticks, and a stall when the
// inserter enters it.
record_inserter_tick :: proc(statistics: ^Statistics, before, after: Inserter) {
	if fuel_item_lit(before.fuel_joules, after.fuel_joules) {
		statistics.fuel_burned += 1
	}
	if after.state == .Idle {
		statistics.inserter_idle_ticks += 1
	}
	if after.state == before.state {
		return
	}
	#partial switch after.state {
	case .No_Fuel:
		statistics.stalls[.Inserter_Out_Of_Fuel] += 1
	case .Waiting_For_Room:
		statistics.stalls[.Inserter_Waiting_For_Room] += 1
	}
}

// Per item totals of some stacks, into totals (cleared first).
total_stacks :: proc(totals: []u32, stacks: []Item_Stack) {
	for stack in stacks {
		if !stack_is_empty(stack) && int(stack.item) < len(totals) {
			totals[stack.item] += u32(stack.count)
		}
	}
}

// Adds every growth from previous to current into counters and makes
// current the new previous.
count_growth :: proc(counters: []u64, previous: []u32, current: []u32) {
	for total, item in current {
		if total > previous[item] {
			counters[item] += u64(total - previous[item])
		}
		previous[item] = total
	}
}

player_held_totals :: proc(players: []Player, item_count: int) -> []u32 {
	totals := make([]u32, item_count, context.temp_allocator)
	for player in players {
		held := [1]Item_Stack{player.held.stack}
		total_stacks(totals, player.inventory.slots)
		total_stacks(totals, held[:])
	}
	return totals
}

// What players hold that they did not hold after the last tick counts as
// obtained. Setting the baseline without counting (count false) keeps
// starting items out.
observe_player_holdings :: proc(statistics: ^Statistics, players: []Player, count: bool) {
	current := player_held_totals(players, len(statistics.held_totals))
	if count {
		count_growth(statistics.obtained, statistics.held_totals, current)
	} else {
		copy(statistics.held_totals, current)
	}
}

inventory_has_empty_slot :: proc(inventory: Inventory) -> bool {
	for slot in inventory.slots {
		if stack_is_empty(slot) {
			return true
		}
	}
	return false
}

observe_full_inventories :: proc(statistics: ^Statistics, players: []Player) {
	for player in players {
		if !inventory_has_empty_slot(player.inventory) {
			statistics.inventory_full_ticks += 1
			return
		}
	}
}

// Growth of the capsule's contents since the last tick is what players
// put in; rewards land after this and are taken into the baseline by
// snapshot_capsule.
observe_capsule :: proc(statistics: ^Statistics, slots: []Item_Stack) {
	current := make([]u32, len(statistics.capsule_totals), context.temp_allocator)
	total_stacks(current, slots)
	count_growth(statistics.delivered, statistics.capsule_totals, current)
}

snapshot_capsule :: proc(statistics: ^Statistics, slots: []Item_Stack) {
	for &total in statistics.capsule_totals {
		total = 0
	}
	total_stacks(statistics.capsule_totals, slots)
}

// Fuel burned, and a stall when the drill enters it. What the drill
// produces is recorded where it leaves the drill (output_drill_item).
record_drill_tick :: proc(statistics: ^Statistics, before, after: Drill) {
	if fuel_item_lit(before.fuel_joules, after.fuel_joules) {
		statistics.fuel_burned += 1
	}
	if after.state == before.state {
		return
	}
	#partial switch after.state {
	case .No_Fuel:
		statistics.stalls[.Drill_Out_Of_Fuel] += 1
	case .Waiting_For_Room:
		statistics.stalls[.Drill_Waiting_For_Room] += 1
	}
}
