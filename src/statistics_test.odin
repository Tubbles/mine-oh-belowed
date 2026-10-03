package game

import "core:testing"

make_test_statistics :: proc(item_count: int = 4) -> Statistics {
	return make_statistics(item_count, 2, 2, context.temp_allocator)
}

@(test)
test_rate_ring_rolls_over_one_minute :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	item := Item_Id(1)
	// Tick rate 1: every tick is a second. One item every 6 seconds is 10 a minute.
	for tick in u64(1) ..= 120 {
		advance_statistics_clock(&statistics, tick, 1)
		if tick % 6 == 0 {
			record_produced(&statistics, item, 1)
		}
		if tick == 30 {
			testing.expect_value(t, production_rate_per_minute(statistics, item), 5)
		}
	}
	testing.expect_value(t, production_rate_per_minute(statistics, item), 10)
	testing.expect_value(t, statistics.produced[item], 20)
	testing.expect_value(t, production_rate_per_minute(statistics, Item_Id(2)), 0)
	advance_statistics_clock(&statistics, 150, 1)
	testing.expect_value(t, production_rate_per_minute(statistics, item), 5)
	// A gap longer than the ring clears it all.
	advance_statistics_clock(&statistics, 1000, 1)
	testing.expect_value(t, production_rate_per_minute(statistics, item), 0)
	testing.expect_value(t, statistics.produced[item], 20)
}

@(test)
test_statistics_ignore_unsized_tables :: proc(t: ^testing.T) {
	statistics: Statistics
	record_produced(&statistics, Item_Id(3), 5)
	record_placed(&statistics, Machine_Id(1))
	record_mining_tick(&statistics, Block_Id(2))
	testing.expect_value(t, production_rate_per_minute(statistics, Item_Id(3)), 0)
	testing.expect_value(t, statistics.world_actions, 1)
}

@(test)
test_furnace_tick_counts_output_fuel_and_stalls :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	before := make_furnace({})
	before.slots[FURNACE_FUEL_SLOT] = {Item_Id(0), 3}
	before.state = .Burning
	after := before
	after.slots[FURNACE_FUEL_SLOT] = {Item_Id(0), 2}
	after.slots[FURNACE_OUTPUT_SLOT] = {Item_Id(2), 1}
	record_furnace_tick(&statistics, before, after, {})
	testing.expect_value(t, statistics.produced[2], 1)
	testing.expect_value(t, statistics.fuel_burned, 1)
	testing.expect_value(t, statistics.stalls[.Out_Of_Fuel], 0)
	stalled := after
	stalled.state = .No_Fuel
	record_furnace_tick(&statistics, after, stalled, {})
	record_furnace_tick(&statistics, stalled, stalled, {})
	testing.expect_value(t, statistics.stalls[.Out_Of_Fuel], 1)
	full := after
	full.state = .Output_Full
	record_furnace_tick(&statistics, after, full, {})
	testing.expect_value(t, statistics.stalls[.Output_Full], 1)
	testing.expect_value(t, statistics.produced[2], 1)
}

@(test)
test_obtained_counts_growth_of_holdings :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	player := make_test_player({}, {})
	players := []Player{player}
	player.inventory.slots[0] = {Item_Id(1), 5}
	observe_player_holdings(&statistics, players, false)
	testing.expect_value(t, statistics.obtained[1], 0)
	player.inventory.slots[0] = {Item_Id(1), 3}
	observe_player_holdings(&statistics, players, true)
	player.inventory.slots[1] = {Item_Id(1), 4}
	players[0].held.stack = {Item_Id(2), 2}
	observe_player_holdings(&statistics, players, true)
	testing.expect_value(t, statistics.obtained[1], 4)
	testing.expect_value(t, statistics.obtained[2], 2)
}

@(test)
test_capsule_growth_counts_as_delivered_but_landing_does_not :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	slots: [CAPSULE_SLOT_COUNT]Item_Stack
	slots[0] = {Item_Id(1), 10}
	snapshot_capsule(&statistics, slots[:])
	observe_capsule(&statistics, slots[:])
	testing.expect_value(t, statistics.delivered[1], 0)
	slots[1] = {Item_Id(1), 3}
	observe_capsule(&statistics, slots[:])
	testing.expect_value(t, statistics.delivered[1], 3)
	slots[0] = EMPTY_STACK
	observe_capsule(&statistics, slots[:])
	slots[0] = {Item_Id(1), 2}
	observe_capsule(&statistics, slots[:])
	testing.expect_value(t, statistics.delivered[1], 5)
}

@(test)
test_walking_counts_horizontal_millimetres :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	record_walked(&statistics, {0, 0, 0}, {3, 5, 4})
	testing.expect_value(t, statistics.distance_walked_millimetres, 5000)
}

// The field's walk (0187): ten one metre steps along the ground count
// ten blocks for the walk objective; a rise along up counts nothing.
@(test)
test_field_walking_counts_the_move_along_the_ground :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	up := [3]i64{0, UNIT_VECTOR_ONE, 0}
	feet := World_Position{0, 1000 * POSITION_UNITS_PER_METRE, 0}
	for _ in 0 ..< 10 {
		step := feet + {POSITION_UNITS_PER_METRE, POSITION_UNITS_PER_METRE / 4, 0}
		record_field_walked(&statistics, feet, step, up)
		feet = step
	}
	testing.expect_value(t, statistics.distance_walked_millimetres / MILLIMETRES_PER_BLOCK, 10)
	record_field_walked(&statistics, feet, feet + {0, 10 * POSITION_UNITS_PER_METRE, 0}, up)
	testing.expect_value(t, statistics.distance_walked_millimetres, 10000)
}

// Work item 0028: the ten second and minute rings are fed from the finer
// ring when their span ends, and the windows add the open span so far.
@(test)
test_rate_rings_coarsen :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	item := Item_Id(1)
	// Tick rate 1: two items a second for 130 seconds.
	for tick in u64(0) ..< 130 {
		advance_statistics_clock(&statistics, tick, 1)
		record_produced(&statistics, item, 2)
	}
	rings := statistics.produced_rates
	start := int(item) * RATE_BUCKET_COUNT
	for span in 0 ..< 12 {
		testing.expect_value(t, rings.per_ten_seconds[start + span], 20)
	}
	// Span 12 (seconds 120 to 129) is still open.
	testing.expect_value(t, rings.per_ten_seconds[start + 12], 0)
	testing.expect_value(t, rings.per_minute[start + 0], 120)
	testing.expect_value(t, rings.per_minute[start + 1], 120)
	testing.expect_value(t, rings.per_minute[start + 2], 0)
	testing.expect_value(t, rings.per_minute[int(Item_Id(2)) * RATE_BUCKET_COUNT], 0)
	// Closing a span sums only the seconds that had a tick.
	advance_statistics_clock(&statistics, 135, 1)
	testing.expect_value(t, rings.per_ten_seconds[start + 12], 20)
}

@(test)
test_window_totals_and_rates :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	item := Item_Id(2)
	// One item a second for 70 minutes, then quiet.
	for tick in u64(0) ..< 4200 {
		advance_statistics_clock(&statistics, tick, 1)
		record_produced(&statistics, item, 1)
		record_consumed(&statistics, item, 3)
	}
	second := statistics.current_second
	produced, consumed := statistics.produced_rates, statistics.consumed_rates
	testing.expect_value(t, window_total(produced, item, .One_Minute, second), 60)
	testing.expect_value(t, window_total(produced, item, .Ten_Minutes, second), 600)
	testing.expect_value(t, window_total(produced, item, .Sixty_Minutes, second), 3600)
	testing.expect_value(t, window_total(consumed, item, .Ten_Minutes, second), 1800)
	testing.expect_value(t, production_rate_per_minute(statistics, item), 60)
	testing.expect_value(t, statistics.consumed[item], 12600)
	for window in Rate_Window {
		testing.expect_value(t, window_rate_tenths_per_minute(window_total(produced, item, window, second), window), 600)
	}
	// Five quiet minutes, now at the start of a span: the one minute
	// window is empty, the others reach back 59 closed spans (590 seconds
	// and 59 minutes) and find 290 and 3240 busy seconds.
	for tick in u64(4200) ..= 4500 {
		advance_statistics_clock(&statistics, tick, 1)
	}
	second = statistics.current_second
	testing.expect_value(t, window_total(produced, item, .One_Minute, second), 0)
	testing.expect_value(t, window_total(produced, item, .Ten_Minutes, second), 290)
	testing.expect_value(t, window_total(produced, item, .Sixty_Minutes, second), 3240)
	testing.expect_value(t, window_rate_tenths_per_minute(300, .Ten_Minutes), 300)
	// A gap longer than every ring clears them all.
	advance_statistics_clock(&statistics, 100_000, 1)
	for window in Rate_Window {
		testing.expect_value(t, window_total(produced, item, window, statistics.current_second), 0)
	}
	testing.expect_value(t, statistics.produced[item], 4200)
}

@(test)
test_rate_windows_early_in_a_game :: proc(t: ^testing.T) {
	statistics := make_test_statistics()
	item := Item_Id(0)
	for tick in u64(0) ..< 25 {
		advance_statistics_clock(&statistics, tick, 1)
		record_produced(&statistics, item, 4)
	}
	for window in Rate_Window {
		testing.expect_value(t, window_total(statistics.produced_rates, item, window, statistics.current_second), 100)
	}
	testing.expect_value(t, window_total(statistics.produced_rates, Item_Id(9), .Ten_Minutes, 24), 0)
}

@(test)
test_machine_output_rate_rolls_over_one_minute :: proc(t: ^testing.T) {
	rate: Machine_Output_Rate
	for second in u64(0) ..< 90 {
		if second % 3 == 0 {
			record_machine_output(&rate, second, 2)
		}
	}
	// Seconds 30 to 89: 20 records of 2.
	testing.expect_value(t, machine_output_per_minute(rate, 89), 40)
	// Read later without records: seconds up to 89 that are still inside.
	testing.expect_value(t, machine_output_per_minute(rate, 119), 20)
	testing.expect_value(t, machine_output_per_minute(rate, 149), 0)
	record_machine_output(&rate, 400, 1)
	testing.expect_value(t, machine_output_per_minute(rate, 400), 1)
	record_machine_output(&rate, 400, 0)
	testing.expect_value(t, machine_output_per_minute(rate, 401), 1)
}

// Fuel and inputs that left a furnace, a crafting machine or an inserter
// in its tick count as consumed.
@(test)
test_consumption_from_machine_ticks :: proc(t: ^testing.T) {
	statistics := make_test_statistics(8)
	before := make_furnace({})
	before.slots[FURNACE_FUEL_SLOT] = {Item_Id(0), 3}
	before.slots[FURNACE_INPUT_SLOT] = {Item_Id(1), 1}
	after := before
	after.slots[FURNACE_FUEL_SLOT] = {Item_Id(0), 2}
	after.slots[FURNACE_INPUT_SLOT] = EMPTY_STACK
	after.slots[FURNACE_OUTPUT_SLOT] = {Item_Id(2), 1}
	record_furnace_tick(&statistics, before, after, {})
	testing.expect_value(t, statistics.consumed[0], 1)
	testing.expect_value(t, statistics.consumed[1], 1)
	testing.expect_value(t, statistics.consumed[2], 0)

	assembler := make_assembler({})
	assembler.input_count, assembler.output_count = 2, 1
	assembler.slots[0] = {Item_Id(3), 5}
	assembler.slots[1] = {Item_Id(4), 2}
	started := assembler
	started.slots[0] = {Item_Id(3), 3}
	started.slots[1] = EMPTY_STACK
	started.slots[2] = {Item_Id(5), 7}
	record_crafting_machine_tick(&statistics, assembler, started)
	testing.expect_value(t, statistics.consumed[3], 2)
	testing.expect_value(t, statistics.consumed[4], 2)
	testing.expect_value(t, statistics.consumed[5], 0)

	// An inserter burning the fuel item in its hand.
	inserter: Inserter
	inserter.slot_count = 1
	inserter.slots[INSERTER_FUEL_SLOT] = EMPTY_STACK
	inserter.held = {Item_Id(6), 1}
	burning := inserter
	burning.held = EMPTY_STACK
	burning.fuel_joules = 1000
	record_inserter_tick(&statistics, inserter, burning, 1)
	testing.expect_value(t, statistics.consumed[6], 1)
	testing.expect_value(t, statistics.fuel_burned, 2)
}

@(test)
test_craft_main_output_skips_byproducts :: proc(t: ^testing.T) {
	outputs := [?]Item_Stack{{Item_Id(1), 3}, {Item_Id(2), 1}}
	testing.expect_value(t, craft_main_output_count(Craft{outputs = outputs[:]}), 3)
	testing.expect_value(t, craft_main_output_count(Craft{outputs = outputs[:], byproducts = {0}}), 1)
	testing.expect_value(t, craft_main_output_count(Craft{outputs = outputs[:], returns = true}), 4)
}
