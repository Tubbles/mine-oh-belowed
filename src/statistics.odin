package game

import "core:math"

// Production statistics, the day one system of doc/architecture.md. Every
// counter is a u64 in the simulation, bumped where its event happens:
// crafting completion, furnace output, mining, placement. The quest
// runtime, the journal and later the statistics screen read them.
//
// Rates (work item 0028): per item rings of produced and consumed
// counts at three resolutions, RATE_BUCKET_COUNT buckets each. The fine
// ring holds per second buckets (one minute), the ten second ring is fed
// from the fine ring whenever a ten second span ends (ten minutes), and the
// minute ring from the ten second ring whenever a minute ends (sixty
// minutes). All integers, advanced only by the simulation clock, and saved
// with the rest of the statistics.
//
// Two counters are measured as differences across a tick instead of at a
// call site, because the UI moves stacks between ticks: obtained (what
// players hold grew) and delivered (what the capsule holds grew).
//
// Arrays are sized by make_statistics, the fluid part by
// make_fluid_statistics. A World made without them (tests) has empty
// arrays, and recording into them does nothing.

// Buckets per item in every rate ring.
RATE_BUCKET_COUNT :: 60
RATE_LEVEL_COUNT :: 3
INSERTER_IDLE_MINUTE_SECONDS :: 60
MILLIMETRES_PER_BLOCK :: 1000

// Out_Of_Fuel and Output_Full are furnace stalls. Crafting_Missing_Input
// counts missing ingredients and missing fluid.
Machine_Stall :: enum u8 {
	Out_Of_Fuel,
	Output_Full,
	Inserter_Out_Of_Fuel,
	Inserter_Waiting_For_Room,
	Drill_Out_Of_Fuel,
	Drill_Waiting_For_Room,
	Crafting_Output_Full,
	Crafting_Missing_Input,
	Crafting_No_Power,
	Crafting_No_Fuel,
}

// The rate windows of the statistics screen, one per ring level.
Rate_Window :: enum u8 {
	One_Minute,
	Ten_Minutes,
	Sixty_Minutes,
}

// Seconds per bucket of each ring level.
@(rodata)
rate_level_seconds := [RATE_LEVEL_COUNT]u64{1, 10, 60}

@(rodata)
rate_window_minutes := [Rate_Window]u64 {
	.One_Minute    = 1,
	.Ten_Minutes   = 10,
	.Sixty_Minutes = 60,
}

// Indexed by item, RATE_BUCKET_COUNT buckets per item in each ring; the
// bucket of unit u (seconds, ten second spans or minutes since the
// start) at u % RATE_BUCKET_COUNT.
Item_Rate_Rings :: struct {
	per_second:      []u32,
	per_ten_seconds: []u32,
	per_minute:      []u32,
}

Statistics :: struct {
	// Indexed by Item_Id. produced counts crafted and smelted outputs,
	// obtained counts growth of what players hold (mined, taken from a
	// machine or the capsule, crafted), delivered counts growth of what
	// the capsule holds that did not land there as a reward.
	produced:                    []u64,
	obtained:                    []u64,
	delivered:                   []u64,
	// Byproducts a lenient world voided because they had no room.
	voided:                      []u64,
	// Items used up: ingredients of crafts (hand, machines, the
	// recycler), science packs and fuel items burned.
	consumed:                    []u64,
	// Indexed by Machine_Id: how often a player placed one.
	placed:                      []u64,
	// Indexed by Item_Id: blocks a player placed with the item (concrete,
	// slag heaps).
	blocks_placed:               []u64,
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
	// Times an inserter reached INSERTER_IDLE_MINUTE_SECONDS of
	// uninterrupted idling. Summed idle ticks grow on healthy lines too,
	// since an inserter outpaces a burner drill or a furnace.
	inserters_idle_a_minute:     u64,
	// Summed over lines: ticks a line's front item was held at a dead end
	// that no inserter picks from.
	belt_dead_end_ticks:         u64,
	// Fuel items lit by drills, a part of fuel_burned.
	drill_fuel_burned:           u64,
	// Items recyclers took, counted when a recycling craft finishes.
	recycled:                    u64,
	// Finite veins drills drained to the last unit.
	veins_exhausted:             u64,
	// Electric energy all networks delivered, in joules; produced and
	// consumed are equal, generators give only what consumers receive.
	energy_produced_joules:      u64,
	energy_consumed_joules:      u64,
	// Ticks in which some network was below full satisfaction while
	// something asked for power.
	brownout_ticks:              u64,
	// Electric machines outside every network in the last tick, and that
	// count summed over ticks for the quest hints.
	unpowered_machines:          u64,
	unpowered_machine_ticks:     u64,
	// Mining, placing, picking up and opening a machine. hands_off
	// sustain objectives break when this changes.
	world_actions:               u64,
	produced_rates:              Item_Rate_Rings,
	consumed_rates:              Item_Rate_Rings,
	current_second:              u64,
	// What players held and the capsule held after the previous tick.
	held_totals:                 []u32,
	capsule_totals:              []u32,
	fluids:                      Fluid_Statistics,
}

// Litres per fluid (work item 0030), indexed by Fluid_Id, with rings like
// the items' (the ring procedures take the fluid id as an index). produced
// counts what pumps, boilers and crafting machines put into their ports,
// consumed what machines drew from theirs (boilers, crafting machines,
// steam engines, flare stacks), voided what flare stacks burned and what
// a lenient world dropped of fluid byproducts that had no room.
Fluid_Statistics :: struct {
	produced:       []u64,
	consumed:       []u64,
	voided:         []u64,
	produced_rates: Item_Rate_Rings,
	consumed_rates: Item_Rate_Rings,
	voided_rates:   Item_Rate_Rings,
}

make_fluid_statistics :: proc(fluid_count: int, allocator := context.allocator) -> Fluid_Statistics {
	return Fluid_Statistics {
		produced = make([]u64, fluid_count, allocator),
		consumed = make([]u64, fluid_count, allocator),
		voided = make([]u64, fluid_count, allocator),
		produced_rates = make_item_rate_rings(fluid_count, allocator),
		consumed_rates = make_item_rate_rings(fluid_count, allocator),
		voided_rates = make_item_rate_rings(fluid_count, allocator),
	}
}

destroy_fluid_statistics :: proc(statistics: Fluid_Statistics, allocator := context.allocator) {
	delete(statistics.produced, allocator)
	delete(statistics.consumed, allocator)
	delete(statistics.voided, allocator)
	destroy_item_rate_rings(statistics.produced_rates, allocator)
	destroy_item_rate_rings(statistics.consumed_rates, allocator)
	destroy_item_rate_rings(statistics.voided_rates, allocator)
}

make_statistics :: proc(item_count, machine_count, block_count: int, allocator := context.allocator) -> Statistics {
	return Statistics {
		produced = make([]u64, item_count, allocator),
		obtained = make([]u64, item_count, allocator),
		delivered = make([]u64, item_count, allocator),
		voided = make([]u64, item_count, allocator),
		consumed = make([]u64, item_count, allocator),
		placed = make([]u64, machine_count, allocator),
		blocks_placed = make([]u64, item_count, allocator),
		mining_ticks = make([]u64, block_count, allocator),
		produced_rates = make_item_rate_rings(item_count, allocator),
		consumed_rates = make_item_rate_rings(item_count, allocator),
		held_totals = make([]u32, item_count, allocator),
		capsule_totals = make([]u32, item_count, allocator),
	}
}

destroy_statistics :: proc(statistics: Statistics, allocator := context.allocator) {
	delete(statistics.produced, allocator)
	delete(statistics.obtained, allocator)
	delete(statistics.delivered, allocator)
	delete(statistics.voided, allocator)
	delete(statistics.consumed, allocator)
	delete(statistics.placed, allocator)
	delete(statistics.blocks_placed, allocator)
	delete(statistics.mining_ticks, allocator)
	destroy_item_rate_rings(statistics.produced_rates, allocator)
	destroy_item_rate_rings(statistics.consumed_rates, allocator)
	delete(statistics.held_totals, allocator)
	delete(statistics.capsule_totals, allocator)
	destroy_fluid_statistics(statistics.fluids, allocator)
}

make_item_rate_rings :: proc(item_count: int, allocator := context.allocator) -> Item_Rate_Rings {
	return Item_Rate_Rings {
		per_second = make([]u32, item_count * RATE_BUCKET_COUNT, allocator),
		per_ten_seconds = make([]u32, item_count * RATE_BUCKET_COUNT, allocator),
		per_minute = make([]u32, item_count * RATE_BUCKET_COUNT, allocator),
	}
}

destroy_item_rate_rings :: proc(rings: Item_Rate_Rings, allocator := context.allocator) {
	delete(rings.per_second, allocator)
	delete(rings.per_ten_seconds, allocator)
	delete(rings.per_minute, allocator)
}

rate_ring_levels :: proc(rings: Item_Rate_Rings) -> [RATE_LEVEL_COUNT][]u32 {
	return {rings.per_second, rings.per_ten_seconds, rings.per_minute}
}

item_counter :: proc(counters: []u64, item: Item_Id) -> u64 {
	return int(item) < len(counters) ? counters[item] : 0
}

// The rate rings. When the clock enters a new second, every coarser
// bucket whose span ended is closed from the finer ring, buckets of spans
// skipped without a tick are cleared, and the fine buckets of the seconds
// entered are cleared.
advance_statistics_clock :: proc(statistics: ^Statistics, tick: u64, tick_rate: int) {
	second := tick / u64(max(tick_rate, 1))
	if second == statistics.current_second {
		return
	}
	advance_rate_rings(statistics.produced_rates, statistics.current_second, second)
	advance_rate_rings(statistics.consumed_rates, statistics.current_second, second)
	advance_rate_rings(statistics.fluids.produced_rates, statistics.current_second, second)
	advance_rate_rings(statistics.fluids.consumed_rates, statistics.current_second, second)
	advance_rate_rings(statistics.fluids.voided_rates, statistics.current_second, second)
	statistics.current_second = second
}

// from is the second the clock was in, to the one it enters. A clock
// that went back clears everything, like a gap longer than the rings.
advance_rate_rings :: proc(rings: Item_Rate_Rings, from, to: u64) {
	levels := rate_ring_levels(rings)
	for level in 1 ..< RATE_LEVEL_COUNT {
		close_rate_level(levels[level - 1], levels[level], level, from, to)
	}
	cleared := to > from ? min(to - from, RATE_BUCKET_COUNT) : RATE_BUCKET_COUNT
	for offset in 0 ..< cleared {
		clear_rate_bucket(rings.per_second, int((to - offset) % RATE_BUCKET_COUNT))
	}
}

// When second `to` lies in a later span of the level than second `from`,
// the span `from` was in is closed: its bucket gets the finer units it
// spans up to `from` (later ones had no tick), and the spans skipped in
// between are cleared. The span `to` is in stays open and is not read
// from this level until it closes.
close_rate_level :: proc(finer, coarser: []u32, level: int, from, to: u64) {
	span_seconds, finer_seconds := rate_level_seconds[level], rate_level_seconds[level - 1]
	from_span, to_span := from / span_seconds, to / span_seconds
	if from_span == to_span {
		return
	}
	first_finer, last_finer := from_span * span_seconds / finer_seconds, from / finer_seconds
	skipped := to_span > from_span ? min(to_span - from_span - 1, RATE_BUCKET_COUNT) : RATE_BUCKET_COUNT
	for item_start := 0; item_start < len(coarser); item_start += RATE_BUCKET_COUNT {
		item := item_start / RATE_BUCKET_COUNT
		coarser[item_start + int(from_span % RATE_BUCKET_COUNT)] = u32(sum_ring_units(finer, item, first_finer, last_finer))
		for offset in 1 ..= skipped {
			coarser[item_start + int((from_span + offset) % RATE_BUCKET_COUNT)] = 0
		}
	}
}

// The item's buckets for units first through last of one ring.
sum_ring_units :: proc(ring: []u32, item: int, first, last: u64) -> u64 {
	total: u64
	for unit := first; unit <= last; unit += 1 {
		total += u64(ring[item * RATE_BUCKET_COUNT + int(unit % RATE_BUCKET_COUNT)])
	}
	return total
}

clear_rate_bucket :: proc(ring: []u32, bucket: int) {
	for item_start := 0; item_start < len(ring); item_start += RATE_BUCKET_COUNT {
		ring[item_start + bucket] = 0
	}
}

// Items counted in the window ending at `second`: the open bucket of the
// window's level so far (taken from the finer rings) and the
// RATE_BUCKET_COUNT - 1 closed ones before it.
window_total :: proc(rings: Item_Rate_Rings, item: Item_Id, window: Rate_Window, second: u64) -> u64 {
	levels := rate_ring_levels(rings)
	level := int(window)
	if (int(item) + 1) * RATE_BUCKET_COUNT > len(levels[level]) {
		return 0
	}
	span := second / rate_level_seconds[level]
	total := open_span_total(levels, int(item), level, second)
	if span > 0 {
		first := span >= RATE_BUCKET_COUNT - 1 ? span - (RATE_BUCKET_COUNT - 1) : 0
		total += sum_ring_units(levels[level], int(item), first, span - 1)
	}
	return total
}

// What the level's span holding `second` has counted so far: its closed
// finer units plus the open finer unit, down to the current second.
open_span_total :: proc(levels: [RATE_LEVEL_COUNT][]u32, item, level: int, second: u64) -> u64 {
	if level == 0 {
		return u64(levels[0][item * RATE_BUCKET_COUNT + int(second % RATE_BUCKET_COUNT)])
	}
	finer_seconds := rate_level_seconds[level - 1]
	first_finer := second / rate_level_seconds[level] * rate_level_seconds[level] / finer_seconds
	current_finer := second / finer_seconds
	total := open_span_total(levels, item, level - 1, second)
	if current_finer > first_finer {
		total += sum_ring_units(levels[level - 1], item, first_finer, current_finer - 1)
	}
	return total
}

// A window's total as items per minute in tenths, rounded down.
window_rate_tenths_per_minute :: proc(total: u64, window: Rate_Window) -> u64 {
	return total * 10 / rate_window_minutes[window]
}

add_to_rate_ring :: proc(ring: []u32, item: Item_Id, second: u64, count: int) {
	bucket := int(item) * RATE_BUCKET_COUNT + int(second % RATE_BUCKET_COUNT)
	if bucket < len(ring) {
		ring[bucket] += u32(count)
	}
}

record_produced :: proc(statistics: ^Statistics, item: Item_Id, count: int) {
	if int(item) >= len(statistics.produced) || count <= 0 {
		return
	}
	statistics.produced[item] += u64(count)
	add_to_rate_ring(statistics.produced_rates.per_second, item, statistics.current_second, count)
}

record_consumed :: proc(statistics: ^Statistics, item: Item_Id, count: int) {
	if int(item) >= len(statistics.consumed) || count <= 0 {
		return
	}
	statistics.consumed[item] += u64(count)
	add_to_rate_ring(statistics.consumed_rates.per_second, item, statistics.current_second, count)
}

record_consumed_stacks :: proc(statistics: ^Statistics, stacks: []Item_Stack) {
	for stack in stacks {
		record_consumed(statistics, stack.item, int(stack.count))
	}
}

// How much of before's item the slot lost.
stack_shrink :: proc(before, after: Item_Stack) -> int {
	if stack_is_empty(before) {
		return 0
	}
	if stack_is_empty(after) || before.item != after.item {
		return int(before.count)
	}
	return max(int(before.count) - int(after.count), 0)
}

// Slots that only shrink inside a machine tick (fuel, inputs, lab packs):
// what they lost was consumed.
record_slot_consumption :: proc(statistics: ^Statistics, before, after: []Item_Stack) {
	for slot, index in before {
		record_consumed(statistics, slot.item, stack_shrink(slot, after[index]))
	}
}

record_produced_stacks :: proc(statistics: ^Statistics, stacks: []Item_Stack) {
	for stack in stacks {
		record_produced(statistics, stack.item, int(stack.count))
	}
}

// Litres into a fluid counter and its ring; the rings index fluids like
// items.
add_fluid_litres :: proc(counters: []u64, rings: Item_Rate_Rings, fluid: Fluid_Id, second: u64, litres: int) {
	if int(fluid) >= len(counters) || litres <= 0 {
		return
	}
	counters[fluid] += u64(litres)
	add_to_rate_ring(rings.per_second, Item_Id(fluid), second, litres)
}

record_fluid_produced :: proc(statistics: ^Statistics, fluid: Fluid_Id, litres: int) {
	add_fluid_litres(statistics.fluids.produced, statistics.fluids.produced_rates, fluid, statistics.current_second, litres)
}

record_fluid_consumed :: proc(statistics: ^Statistics, fluid: Fluid_Id, litres: int) {
	add_fluid_litres(statistics.fluids.consumed, statistics.fluids.consumed_rates, fluid, statistics.current_second, litres)
}

record_fluid_voided :: proc(statistics: ^Statistics, fluid: Fluid_Id, litres: int) {
	add_fluid_litres(statistics.fluids.voided, statistics.fluids.voided_rates, fluid, statistics.current_second, litres)
}

// Port buffers across a machine's own step, where the network does not
// move fluid: what a buffer lost was drawn (consumed), what it gained was
// made (produced).
record_buffer_changes :: proc(statistics: ^Statistics, before, after: []Fluid_Buffer) {
	for buffer, index in before {
		change := int(after[index].level) - int(buffer.level)
		if change < 0 {
			record_fluid_consumed(statistics, buffer.fluid, -change)
		} else {
			record_fluid_produced(statistics, after[index].fluid, change)
		}
	}
}

// Litres of a fluid over a window ending at `second`, like window_total.
fluid_window_total :: proc(rings: Item_Rate_Rings, fluid: Fluid_Id, window: Rate_Window, second: u64) -> u64 {
	return window_total(rings, Item_Id(fluid), window, second)
}

fluid_counter :: proc(counters: []u64, fluid: Fluid_Id) -> u64 {
	return int(fluid) < len(counters) ? counters[fluid] : 0
}

record_voided :: proc(statistics: ^Statistics, item: Item_Id, count: int) {
	if int(item) < len(statistics.voided) && count > 0 {
		statistics.voided[item] += u64(count)
	}
}

// How much of after's item the slot gained.
stack_growth :: proc(before, after: Item_Stack) -> int {
	if stack_is_empty(after) {
		return 0
	}
	if stack_is_empty(before) || before.item != after.item {
		return int(after.count)
	}
	return max(int(after.count) - int(before.count), 0)
}

// A machine's own main output over the last minute (work item 0028), for
// the rate readout of its panel: a ring of per second buckets on the
// entity, saved with it. It is kept lazily, a record first clears the
// seconds that passed since the last record, so idle machines cost
// nothing per tick.
Machine_Output_Rate :: struct {
	counts:      [RATE_BUCKET_COUNT]u16,
	last_second: u64,
}

forget_machine_output :: proc(rate: ^Machine_Output_Rate, second: u64) {
	if second == rate.last_second {
		return
	}
	cleared := second > rate.last_second ? min(second - rate.last_second, RATE_BUCKET_COUNT) : RATE_BUCKET_COUNT
	for offset in 0 ..< cleared {
		rate.counts[(second - offset) % RATE_BUCKET_COUNT] = 0
	}
	rate.last_second = second
}

record_machine_output :: proc(rate: ^Machine_Output_Rate, second: u64, count: int) {
	if count <= 0 {
		return
	}
	forget_machine_output(rate, second)
	bucket := &rate.counts[second % RATE_BUCKET_COUNT]
	bucket^ = u16(min(int(bucket^) + count, int(max(u16))))
}

// Items over the minute ending at `second`: the buckets of the seconds up
// to the last record that still lie inside it.
machine_output_per_minute :: proc(rate: Machine_Output_Rate, second: u64) -> u64 {
	if second < rate.last_second || second - rate.last_second >= RATE_BUCKET_COUNT {
		return 0
	}
	first := second >= RATE_BUCKET_COUNT - 1 ? second - (RATE_BUCKET_COUNT - 1) : 0
	total: u64
	for unit := first; unit <= rate.last_second; unit += 1 {
		total += u64(rate.counts[unit % RATE_BUCKET_COUNT])
	}
	return total
}

// A product the craft made: what its slot gained is produced, the rest was
// voided (lenient byproducts). Output slots only grow inside a machine
// tick.
record_product :: proc(statistics: ^Statistics, product: Item_Stack, before, after: Item_Stack) {
	kept := min(stack_growth(before, after), int(product.count))
	record_produced(statistics, product.item, kept)
	record_voided(statistics, product.item, int(product.count) - kept)
}

// A finished crafting machine craft. The recycler's returns always fit.
record_craft_outputs :: proc(statistics: ^Statistics, craft: Craft, before, after: Assembler) {
	if craft.returns {
		record_produced_stacks(statistics, craft.outputs)
		record_recycled(statistics, craft.inputs)
		return
	}
	first := assembler_first_output(after)
	for product, index in craft.outputs {
		record_product(statistics, product, before.slots[first + index], after.slots[first + index])
	}
}

// What of a finished craft's fluid outputs did not reach its port: only
// a lenient byproduct can lack room. The part that did is counted
// produced by record_buffer_changes.
record_voided_fluid_outputs :: proc(statistics: ^Statistics, machine: Machine, craft: Craft, before, after: Assembler) {
	for output, position in craft.fluid_outputs {
		index := output_port_index(machine, position)
		kept := int(after.buffers[index].level) - int(before.buffers[index].level)
		record_fluid_voided(statistics, output.fluid, int(output.litres) - max(kept, 0))
	}
}

record_recycled :: proc(statistics: ^Statistics, taken: []Item_Stack) {
	for stack in taken {
		statistics.recycled += u64(stack.count)
	}
}

// The main output of a finished craft: every return of the recycler,
// otherwise the first product that is not a byproduct (main outputs
// always fit, since a craft waits for their room).
craft_main_output_count :: proc(craft: Craft) -> int {
	if craft.returns {
		total := 0
		for stack in craft.outputs {
			total += int(stack.count)
		}
		return total
	}
	for product, index in craft.outputs {
		if index not_in craft.byproducts {
			return int(product.count)
		}
	}
	return 0
}

// Fuel items lit, fuel and ingredients used up, and a stall when the
// machine enters it. The fuel and input slots only shrink inside the
// machine's tick.
record_crafting_machine_tick :: proc(statistics: ^Statistics, before, after: Assembler) {
	if fuel_item_lit(before.fuel_joules, after.fuel_joules) {
		statistics.fuel_burned += 1
	}
	last := assembler_first_output(before)
	slots_before, slots_after := before.slots, after.slots
	record_slot_consumption(statistics, slots_before[:last], slots_after[:last])
	if after.state == before.state {
		return
	}
	#partial switch after.state {
	case .Output_Full:
		statistics.stalls[.Crafting_Output_Full] += 1
	case .Missing_Ingredients, .No_Fluid:
		statistics.stalls[.Crafting_Missing_Input] += 1
	case .No_Power:
		statistics.stalls[.Crafting_No_Power] += 1
	case .No_Fuel:
		statistics.stalls[.Crafting_No_Fuel] += 1
	}
}

// Items produced over the last minute: the current second so far plus
// the 59 before it.
production_rate_per_minute :: proc(statistics: Statistics, item: Item_Id) -> u64 {
	return window_total(statistics.produced_rates, item, .One_Minute, statistics.current_second)
}

record_placed :: proc(statistics: ^Statistics, machine: Machine_Id) {
	if int(machine) < len(statistics.placed) {
		statistics.placed[machine] += 1
	}
	statistics.world_actions += 1
}

record_block_placed :: proc(statistics: ^Statistics, item: Item_Id) {
	if int(item) < len(statistics.blocks_placed) {
		statistics.blocks_placed[item] += 1
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
// tick, so the differences are what it smelted and burned. The main
// output grows exactly when a smelt finishes, and then the byproduct slot
// shows what of the recipe's byproduct was kept. A stall counts when the
// furnace enters the state, not for every tick it stays there.
record_furnace_tick :: proc(statistics: ^Statistics, before, after: Furnace, recipes: Recipe_Registry) {
	grown := stack_growth(before.slots[FURNACE_OUTPUT_SLOT], after.slots[FURNACE_OUTPUT_SLOT])
	if grown > 0 {
		record_produced(statistics, after.slots[FURNACE_OUTPUT_SLOT].item, grown)
		record_furnace_byproduct(statistics, before, after, recipes)
	}
	fuel_before, fuel_after := before.slots[FURNACE_FUEL_SLOT], after.slots[FURNACE_FUEL_SLOT]
	if fuel_after.count < fuel_before.count {
		statistics.fuel_burned += u64(fuel_before.count - fuel_after.count)
	}
	slots_before, slots_after := before.slots, after.slots
	record_slot_consumption(statistics, slots_before[:FURNACE_OUTPUT_SLOT], slots_after[:FURNACE_OUTPUT_SLOT])
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

record_furnace_byproduct :: proc(statistics: ^Statistics, before, after: Furnace, recipes: Recipe_Registry) {
	if after.recipe < 0 || after.recipe >= len(recipes.recipes) || len(recipes.recipes[after.recipe].outputs) < 2 {
		return
	}
	product := recipes.recipes[after.recipe].outputs[1]
	record_product(statistics, product, before.slots[FURNACE_BYPRODUCT_SLOT], after.slots[FURNACE_BYPRODUCT_SLOT])
}

// A fuel item was lit when the buffer grew: lighting adds a whole item's
// joules, far more than one tick burns. Unlike a slot count difference
// this also sees an item an inserter fed itself and burned in one tick.
fuel_item_lit :: proc(joules_before, joules_after: u32) -> bool {
	return joules_after > joules_before
}

// The item an inserter lit: from its fuel slot, or with the slot empty
// the fuel item in its hand (feed_inserter_from_hand burns it in the same
// tick). A fuel item taken from the source waits in the slot until the
// next tick.
inserter_lit_fuel_item :: proc(before: Inserter) -> Item_Id {
	fuel := before.slots[INSERTER_FUEL_SLOT]
	return stack_is_empty(fuel) ? before.held.item : fuel.item
}

// Uninterrupted idle ticks after a tick that ended in `state`.
next_idle_streak :: proc(streak: u32, state: Inserter_State) -> u32 {
	return state == .Idle ? streak + 1 : 0
}

// Like record_furnace_tick: fuel burned, idle ticks, a minute of idling,
// and a stall when the inserter enters it.
record_inserter_tick :: proc(statistics: ^Statistics, before, after: Inserter, tick_rate: int) {
	if fuel_item_lit(before.fuel_joules, after.fuel_joules) {
		statistics.fuel_burned += 1
		record_consumed(statistics, inserter_lit_fuel_item(before), 1)
	}
	if after.state == .Idle {
		statistics.inserter_idle_ticks += 1
	}
	if after.idle_streak == u32(INSERTER_IDLE_MINUTE_SECONDS * tick_rate) {
		statistics.inserters_idle_a_minute += 1
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
		statistics.drill_fuel_burned += 1
		record_consumed(statistics, before.slots[DRILL_FUEL_SLOT].item, 1)
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

// A line whose last block an inserter picks from feeds that inserter, so
// items held at its end are not a dead end.
record_belt_dead_ends :: proc(statistics: ^Statistics, entities: ^Entities) {
	for line in entities.belt_network.lines {
		if line.front_held_at_dead_end && !inserter_picks_from(entities, line.belts[len(line.belts) - 1]) {
			statistics.belt_dead_end_ticks += 1
		}
	}
}

inserter_picks_from :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	for inserter in entities.inserters.entries {
		if inserter.alive && entity_at(entities, inserter_pickup_cell(inserter)) == handle {
			return true
		}
	}
	return false
}
