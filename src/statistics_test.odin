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
