package game

import "core:testing"

// The detector's cues for a frame of the counters, the memory advanced.
step_cues :: proc(memory: ^Cue_Memory, counters: Cue_Counters) -> Frame_Cues {
	cues: Frame_Cues
	cues, memory^ = detect_cues(memory^, counters)
	return cues
}

expect_cues :: proc(t: ^testing.T, memory: ^Cue_Memory, counters: Cue_Counters, fired: bit_set[Cue], loc := #caller_location) -> Frame_Cues {
	cues := step_cues(memory, counters)
	testing.expect_value(t, cues.fired, fired, loc = loc)
	return cues
}

// A scripted session: each cue fires once on the frame its counter
// changes and not again while the counters stay; the first frame only
// learns what a loaded world already has.
@(test)
test_detector_fires_each_cue_once_over_a_scripted_session :: proc(t: ^testing.T) {
	messages := [?]Quest_Message{{text_key = ITEM_DISCOVERED_KEY}, {text_key = "mc_welcome"}, {text_key = ITEM_DISCOVERED_KEY}, {text_key = ORBITAL_SURVEY_KEY}}
	stone := Block_Id(3)
	dig :: proc(progress: u32) -> Mining_State {
		return Mining_State{active = true, block = {4, 5, 6}, block_id = 3, progress_ticks = progress, required_ticks = 20}
	}
	memory: Cue_Memory
	counters := Cue_Counters{tick = 1, distance_millimetres = 1000, placed_total = 5, blocks_mined = 2, shipment_count = 2, messages = messages[:2]}
	first := expect_cues(t, &memory, counters, {})
	testing.expect_value(t, first.cadence_millimetres, 1000)
	// Walk: a footstep at the half cycle (2400), with the blocks at the feet.
	counters.tick, counters.distance_millimetres, counters.feet_block, counters.under_block = 2, 2500, 7, stone
	walked := expect_cues(t, &memory, counters, {.Footstep})
	testing.expect(t, walked.moving)
	testing.expect_value(t, walked.feet_block, Block_Id(7))
	testing.expect_value(t, walked.under_block, stone)
	expect_cues(t, &memory, counters, {})
	counters.tick = 3
	stood := expect_cues(t, &memory, counters, {})
	testing.expect(t, !stood.moving)
	// Place.
	counters.tick, counters.placed_total = 4, 6
	expect_cues(t, &memory, counters, {.Place})
	counters.tick = 5
	expect_cues(t, &memory, counters, {})
	// Dig: quarters 1 and 2, then the block is gone and the statistic grows.
	counters.dig, counters.block_at_last_dig = dig(4), stone
	expect_cues(t, &memory, counters, {})
	counters.dig = dig(5)
	expect_cues(t, &memory, counters, {.Dig_Quarter})
	expect_cues(t, &memory, counters, {})
	counters.dig = dig(12)
	expect_cues(t, &memory, counters, {.Dig_Quarter})
	counters.dig, counters.block_at_last_dig, counters.blocks_mined = {}, AIR_BLOCK, 3
	broken := expect_cues(t, &memory, counters, {.Dig_Break, .Block_Break})
	testing.expect_value(t, broken.broken_cell, World_Coordinate{4, 5, 6})
	testing.expect_value(t, broken.broken_block, stone)
	expect_cues(t, &memory, counters, {})
	// Launch, shipment, discovery, survey.
	counters.launching_count = 1
	expect_cues(t, &memory, counters, {.Launch})
	expect_cues(t, &memory, counters, {})
	counters.launching_count = 0
	expect_cues(t, &memory, counters, {})
	counters.shipment_count = 3
	expect_cues(t, &memory, counters, {.Shipment})
	expect_cues(t, &memory, counters, {})
	counters.messages = messages[:3]
	expect_cues(t, &memory, counters, {.Discovery})
	expect_cues(t, &memory, counters, {})
	counters.messages = messages[:4]
	expect_cues(t, &memory, counters, {.Survey})
	expect_cues(t, &memory, counters, {})
}

// The dig detectors: a quarter of the same dig, the break of a block dig
// past half way.
@(test)
test_dig_detectors :: proc(t: ^testing.T) {
	block := Mining_State{active = true, block = {1, 0, 0}, block_id = 3, progress_ticks = 6, required_ticks = 10}
	testing.expect(t, dig_broke_block(block, AIR_BLOCK))
	testing.expect(t, !dig_broke_block(block, 3), "still there")
	pick_up := block
	pick_up.entity = Entity_Handle{index = 1}
	testing.expect(t, !dig_broke_block(pick_up, AIR_BLOCK), "an entity pick up")
	testing.expect(t, !dig_broke_block({}, AIR_BLOCK), "no dig")
	next := block
	next.progress_ticks = 8
	testing.expect(t, dig_quarter_crossed(block, next))
	other := next
	other.block = {2, 0, 0}
	testing.expect(t, !dig_quarter_crossed(block, other), "a new dig")
}

// Work item 0296: the field's cheat movement divides the walk cadence
// like the block world's cheat speed, by the larger factor that is on,
// so the footsteps keep their cadence per metre.
@(test)
test_the_cadence_divides_by_the_cheat_that_is_on :: proc(t: ^testing.T) {
	testing.expect_value(t, cue_cheat_factor(false, false, 4), 1)
	testing.expect_value(t, cue_cheat_factor(true, false, 4), CHEAT_SPEED_FACTOR)
	testing.expect_value(t, cue_cheat_factor(false, true, 4), 4)
	testing.expect_value(t, cue_cheat_factor(true, true, 4), 4)
	testing.expect_value(t, cue_cheat_factor(true, true, 2), CHEAT_SPEED_FACTOR)
	testing.expect_value(t, advance_cadence_millimetres(100, 500, 900, true, 4), 200)
	testing.expect_value(t, advance_cadence_millimetres(100, 500, 900, false, 4), 500)
	memory: Cue_Memory
	counters := Cue_Counters{tick = 1, cheat_speed = true, cheat_factor = 4}
	expect_cues(t, &memory, counters, {})
	// Four metres under the field's cheat count as one: no footstep short
	// of the half cycle, one past it.
	counters.tick, counters.distance_millimetres = 2, 4 * u64(WALK_CYCLE_MILLIMETRES / 2) - 400
	walked := expect_cues(t, &memory, counters, {})
	testing.expect(t, walked.moving)
	counters.tick, counters.distance_millimetres = 3, counters.distance_millimetres + 800
	expect_cues(t, &memory, counters, {.Footstep})
}
