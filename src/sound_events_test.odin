package game

import "core:testing"

@(test)
test_shipped_block_materials :: proc(t: ^testing.T) {
	blocks := shipped_block_registry(t)
	cases := [?]struct {
		block:    string,
		material: string,
	} {
		{"stone", "stone"},
		{"grass", "dirt"},
		{"sand", "sand"},
		{"log", "wood"},
		{"plank_stairs_r2", "wood"},
		{"pine_leaves", "leaves"},
		{"grass_tuft", "leaves"},
		{"snow", "snow"},
		{"landing_pad", "metal"},
		{"water", "water"},
		{"flowing_water_3", "water"},
		{"hematite_ore", "stone"},
	}
	for entry in cases {
		block, found := find_block_id(blocks, entry.block)
		testing.expectf(t, found, "%s exists", entry.block)
		testing.expectf(t, block_sound_material(blocks, block) == entry.material, "%s is %s", entry.block, block_sound_material(blocks, block))
	}
	testing.expect_value(t, block_sound_material(blocks, Block_Id(len(blocks.definitions))), DEFAULT_SOUND_MATERIAL)
}

@(test)
test_footstep_material_wades_in_water :: proc(t: ^testing.T) {
	blocks := shipped_block_registry(t)
	water, _ := find_block_id(blocks, "water")
	grass, _ := find_block_id(blocks, "grass")
	sand, _ := find_block_id(blocks, "sand")
	testing.expect_value(t, footstep_material(blocks, AIR_BLOCK, grass), "dirt")
	testing.expect_value(t, footstep_material(blocks, water, sand), "water")
	testing.expect_value(t, footstep_sound_id("snow"), "footstep_snow")
}

@(test)
test_mining_hit_per_tool_tier :: proc(t: ^testing.T) {
	table := shipped_sound_table(t)
	testing.expect_value(t, mining_hit_sound_id(table, 0), "mine_hit_0")
	testing.expect_value(t, mining_hit_sound_id(table, 2), "mine_hit_2")
	testing.expect_value(t, mining_hit_sound_id(table, 3), "mine_hit_3")
	// Above the highest listed tier, the highest takes over.
	testing.expect_value(t, mining_hit_sound_id(table, 7), "mine_hit_3")
	gaps := [?]Sound_Entry{{id = "mine_hit_0"}, {id = "mine_hit_2"}}
	testing.expect_value(t, mining_hit_sound_id(Sound_Table{entries = gaps[:]}, 1), "mine_hit_0")
	testing.expect_value(t, mining_hit_sound_id({}, 2), "")
}

@(test)
test_step_detector_fires_once_per_half_cycle :: proc(t: ^testing.T) {
	// The first frame only learns the counters.
	memory, cues := advance_sound_memory({}, {tick = 1, distance_millimetres = 2390, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect_value(t, cues, Sound_Cues{})
	memory, cues = advance_sound_memory(memory, {tick = 2, distance_millimetres = 2410, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, cues.footstep)
	testing.expect_value(t, memory.step_count, 1)
	// The same tick again, a frame faster than the tick rate: no step.
	memory, cues = advance_sound_memory(memory, {tick = 2, distance_millimetres = 2410, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, !cues.footstep)
	memory, cues = advance_sound_memory(memory, {tick = 3, distance_millimetres = 4790, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, !cues.footstep)
	memory, cues = advance_sound_memory(memory, {tick = 4, distance_millimetres = 4810, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, cues.footstep)
	testing.expect_value(t, memory.step_count, 2)
}

@(test)
test_quarter_detector_fires_once_per_quarter :: proc(t: ^testing.T) {
	block := World_Coordinate{1, 2, 3}
	dig := proc(block: World_Coordinate, progress: u32) -> Mining_Sound_Memory {
		return mining_sound_memory_of(Mining_State{active = true, block = block, progress_ticks = progress, required_ticks = 20})
	}
	testing.expect_value(t, dig(block, 4).quarter, 0)
	testing.expect_value(t, dig(block, 5).quarter, 1)
	testing.expect_value(t, dig(block, 20).quarter, 4)
	testing.expect(t, !mining_hit_due({}, dig(block, 5)))
	testing.expect(t, mining_hit_due(dig(block, 4), dig(block, 5)))
	testing.expect(t, !mining_hit_due(dig(block, 5), dig(block, 6)))
	testing.expect(t, mining_hit_due(dig(block, 9), dig(block, 15)))
	// The break is not a hit, nor is a new dig.
	testing.expect(t, !mining_hit_due(dig(block, 19), dig(block, 20)))
	testing.expect(t, !mining_hit_due(dig(block, 4), dig({1, 2, 4}, 5)))
	testing.expect_value(t, mining_sound_memory_of({}), Mining_Sound_Memory{})
	// Through the memory, once.
	memory, _ := advance_sound_memory({}, {tick = 1, mining = dig(block, 4)})
	cues: Sound_Cues
	memory, cues = advance_sound_memory(memory, {tick = 2, mining = dig(block, 5)})
	testing.expect(t, cues.mining_hit)
	memory, cues = advance_sound_memory(memory, {tick = 3, mining = dig(block, 6)})
	testing.expect(t, !cues.mining_hit)
}

@(test)
test_counter_cues :: proc(t: ^testing.T) {
	memory, _ := advance_sound_memory({}, {tick = 1, placed_total = 3, blocks_mined = 5, launching_count = 0, descent_active = true, message_count = 1})
	cues: Sound_Cues
	memory, cues = advance_sound_memory(memory, {tick = 2, placed_total = 4, blocks_mined = 6, launching_count = 1, descent_active = false, message_count = 2, discovered = true})
	testing.expect_value(t, cues, Sound_Cues{block_break = true, block_place = true, launch = true, landing = true, discovery = true})
	memory, cues = advance_sound_memory(memory, {tick = 3, placed_total = 4, blocks_mined = 6, launching_count = 1, message_count = 2})
	testing.expect_value(t, cues, Sound_Cues{})
	messages := [?]Quest_Message{{text_key = "mc_welcome"}, {text_key = ITEM_DISCOVERED_KEY}, {text_key = "research_complete"}}
	testing.expect(t, discovery_since(messages[:], 0))
	testing.expect(t, discovery_since(messages[:], 1))
	testing.expect(t, !discovery_since(messages[:], 2))
	testing.expect(t, !discovery_since(messages[:], 5))
}

@(test)
test_nearest_working_machine_and_its_volume :: proc(t: ^testing.T) {
	sources := [?]Hum_Source{{position = {10, 0, 0}, family = .Burner}, {position = {0, 0, 4}, family = .Electric}, {position = {0, 0, -6}, family = .Fluid}}
	nearest, distance, found := nearest_hum_source(sources[:], {0, 0, 0})
	testing.expect(t, found)
	testing.expect_value(t, nearest.family, Hum_Family.Electric)
	expect_near_value(t, distance, 4)
	_, _, found = nearest_hum_source(sources[:], {0, 40, 0})
	testing.expect(t, !found)
	_, _, found = nearest_hum_source(nil, {})
	testing.expect(t, !found)
	expect_near_value(t, hum_volume(0), 1)
	expect_near_value(t, hum_volume(6), 0.5)
	expect_near_value(t, hum_volume(HUM_RANGE_BLOCKS), 0)
	expect_near_value(t, hum_volume(20), 0)
	testing.expect_value(t, machine_hum_family(Machine{electric_power_watts = 90_000}, false), Hum_Family.Electric)
	testing.expect_value(t, machine_hum_family(Machine{fuel_power_watts = 90_000}, false), Hum_Family.Burner)
	testing.expect_value(t, machine_hum_family(Machine{electric_power_watts = 90_000}, true), Hum_Family.Fluid)
}

@(test)
test_biome_ambience_mapping :: proc(t: ^testing.T) {
	biomes := shipped_biome_definitions(t)
	expected := [?]struct {
		biome: string,
		sound: string,
	} {
		{"forest", "ambience_birds"},
		{"lake", "ambience_water"},
		{"mountains", "ambience_wind"},
		{"steppe", "ambience_insects"},
		{"tar_flats", ""},
	}
	seen := 0
	for entry in expected {
		for biome, index in biomes {
			if biome.definition.id == entry.biome {
				testing.expectf(t, biome_ambience_sound_id(biomes, index) == entry.sound, "%s plays %q", entry.biome, biome_ambience_sound_id(biomes, index))
				seen += 1
			}
		}
	}
	testing.expect_value(t, seen, len(expected))
	testing.expect_value(t, biome_ambience_sound_id(biomes, len(biomes)), "")
	testing.expect_value(t, biome_ambience_sound_id(biomes, -1), "")
}

@(test)
test_rain_volume :: proc(t: ^testing.T) {
	expect_near_value(t, rain_volume(.Rain, 0.8, 1), 0.8)
	expect_near_value(t, rain_volume(.Rain, 0.8, 0.5), 0.4)
	expect_near_value(t, rain_volume(.Snow, 0.8, 1), 0)
	expect_near_value(t, rain_volume(.None, 1, 1), 0)
}

@(test)
test_footstep_pitch_varies_within_its_range :: proc(t: ^testing.T) {
	changes := 0
	previous := footstep_pitch(0)
	for step in u64(0) ..< 64 {
		pitch := footstep_pitch(step)
		testing.expect(t, pitch >= FOOTSTEP_PITCH_MINIMUM && pitch <= FOOTSTEP_PITCH_MAXIMUM)
		testing.expect_value(t, pitch, footstep_pitch(step))
		if pitch != previous {
			changes += 1
		}
		previous = pitch
	}
	testing.expect(t, changes > 32)
}

@(test)
test_ui_records_move_confirm_and_back :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	// The first focus is a fallback, not a move.
	test_ui_frame(&state, {})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{})
	test_ui_frame(&state, {navigation = .Down})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{.Move})
	state.sound_events = {}
	test_ui_frame(&state, {confirm = true})
	append(&state.widgets, test_widget(1, 0, 0), test_widget(2, 0, 100))
	ui_resolve(&state)
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{.Confirm})
	state.sound_events = {}
	// Back only on a screen.
	test_ui_frame(&state, {back = true})
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{})
	push_screen(&state.screens, .Pause)
	test_ui_frame(&state, {back = true})
	testing.expect_value(t, state.sound_events, bit_set[Ui_Sound_Event]{.Back})
}

// However fast the dig, at most MINING_HIT_MAXIMUM_PER_SECOND hits: a dig
// crossing a quarter every 4 ticks hits every 20 ticks at most.
@(test)
test_mining_hits_capped_at_three_a_second :: proc(t: ^testing.T) {
	block := World_Coordinate{1, 2, 3}
	memory, _ := advance_sound_memory({}, {tick = 0})
	hits, last_hit := 0, u64(0)
	for tick in u64(1) ..= 600 {
		// A new dig of 16 ticks every 16 ticks: quarters at 4, 8 and 12.
		dig := Mining_State{active = true, block = block, entity = Entity_Handle{index = u32(tick / 16)}, progress_ticks = u32(tick % 16), required_ticks = 16}
		cues: Sound_Cues
		memory, cues = advance_sound_memory(memory, {tick = tick, mining = mining_sound_memory_of(dig)})
		if cues.mining_hit {
			testing.expectf(t, hits == 0 || tick - last_hit >= MINING_HIT_MINIMUM_GAP_TICKS, "hit at %d after %d", tick, last_hit)
			hits, last_hit = hits + 1, tick
		}
	}
	testing.expect(t, hits > 0, "some hits play")
	testing.expect(t, hits <= 10 * MINING_HIT_MAXIMUM_PER_SECOND, "ten seconds hold at most thirty")
	testing.expect(t, mining_hit_allowed(0, 0))
	testing.expect(t, !mining_hit_allowed(20, 19))
	testing.expect(t, mining_hit_allowed(20, 20))
}

// Pauses between clusters lie in 20 to 60 seconds and are not all the
// same; the gaps within one in 1 to 3 seconds.
@(test)
test_ambience_cluster_pauses_lie_in_range_and_differ :: proc(t: ^testing.T) {
	pauses: map[u64]bool
	pauses.allocator = context.temp_allocator
	for count in u64(0) ..< 32 {
		pause := ambience_cluster_pause_ticks(count * 3001 + 17, count)
		testing.expectf(t, pause >= AMBIENCE_CLUSTER_PAUSE_MINIMUM_TICKS && pause <= AMBIENCE_CLUSTER_PAUSE_MAXIMUM_TICKS, "pause %d", pause)
		gap := ambience_call_gap_ticks(count * 3001 + 17, count)
		testing.expectf(t, gap >= AMBIENCE_CALL_GAP_MINIMUM_TICKS && gap <= AMBIENCE_CALL_GAP_MAXIMUM_TICKS, "gap %d", gap)
		pitch := ambience_call_pitch(count * 3001 + 17, count)
		testing.expectf(t, pitch >= 1 - AMBIENCE_CALL_PITCH_SHARE && pitch <= 1 + AMBIENCE_CALL_PITCH_SHARE, "pitch %v", pitch)
		pauses[pause] = true
	}
	testing.expect(t, len(pauses) > 16, "the pauses vary")
}

// Run the scheduler for an hour of ticks: calls come in clusters of two
// or three, a gap apart, with a pause in range between clusters, the
// variant never the same twice in a row.
@(test)
test_ambience_cluster_scheduler_plays_clusters :: proc(t: ^testing.T) {
	memory: Ambience_Cluster_Memory
	calls := make([dynamic]u64, context.temp_allocator)
	last_variant := 0
	for tick in u64(100) ..< 100 + 60 * 60 * 60 {
		call: bool
		memory, call = advance_ambience_cluster(memory, tick, 3)
		if call {
			testing.expect(t, memory.variant >= 1 && memory.variant <= 3)
			testing.expect(t, memory.variant != last_variant, "no variant twice in a row")
			last_variant = memory.variant
			append(&calls, tick)
		}
	}
	testing.expect(t, len(calls) >= 60 * 2, "at least a cluster a minute")
	testing.expect(t, calls[0] - 100 >= AMBIENCE_CLUSTER_PAUSE_MINIMUM_TICKS, "the first cluster waits a pause")
	cluster_size, sizes, distinct_pauses := 1, [4]int{}, map[u64]bool{}
	distinct_pauses.allocator = context.temp_allocator
	for index in 1 ..< len(calls) {
		between := calls[index] - calls[index - 1]
		if between <= AMBIENCE_CALL_GAP_MAXIMUM_TICKS {
			testing.expect(t, between >= AMBIENCE_CALL_GAP_MINIMUM_TICKS)
			cluster_size += 1
			continue
		}
		testing.expectf(t, between >= AMBIENCE_CLUSTER_PAUSE_MINIMUM_TICKS && between <= AMBIENCE_CLUSTER_PAUSE_MAXIMUM_TICKS, "pause %d", between)
		testing.expectf(t, cluster_size == 2 || cluster_size == 3, "cluster of %d", cluster_size)
		sizes[cluster_size] += 1
		distinct_pauses[between] = true
		cluster_size = 1
	}
	testing.expect(t, sizes[2] > 0 && sizes[3] > 0, "two and three calls both happen")
	testing.expect(t, len(distinct_pauses) > 20, "the pauses differ")
}

// The choice cycles through every variant without repeating the last.
@(test)
test_ambience_variant_never_repeats_the_last :: proc(t: ^testing.T) {
	seen: [4]bool
	variant := 0
	for step in u64(0) ..< 64 {
		next := next_ambience_variant(variant, 3, sound_hash(step, step, AMBIENCE_VARIANT_SALT))
		testing.expect(t, next >= 1 && next <= 3)
		testing.expect(t, next != variant)
		seen[next] = true
		variant = next
	}
	testing.expect(t, seen[1] && seen[2] && seen[3], "every variant plays")
	testing.expect_value(t, next_ambience_variant(1, 1, 99), 1)
	testing.expect_value(t, next_ambience_variant(2, 2, 12345), 1)
}

// The shipped birds and insects are clustered calls, the birds by day;
// wind and water stay loops.
@(test)
test_shipped_ambience_clusters :: proc(t: ^testing.T) {
	table := shipped_sound_table(t)
	testing.expect_value(t, ambience_variant_count(table, "ambience_birds"), 3)
	testing.expect_value(t, ambience_variant_count(table, "ambience_insects"), 2)
	testing.expect_value(t, ambience_variant_count(table, "ambience_wind"), 0)
	testing.expect(t, ambience_day_only(table, "ambience_birds"))
	testing.expect(t, !ambience_day_only(table, "ambience_insects"))
	testing.expect(t, !sound_listed(table, "ambience_birds"), "no bird loop")
	loops := [?]string{"ambience_wind", "ambience_water"}
	for id in loops {
		index, found := find_sound(table, id)
		testing.expect(t, found)
		testing.expect_value(t, table.entries[index].kind, Sound_Kind.Loop)
	}
}

// The hum's level stays within 5 percent either way, each drift lasting
// 3 to 7 seconds, and it moves.
@(test)
test_hum_drift_range :: proc(t: ^testing.T) {
	memory: Hum_Drift_Memory
	lowest, highest := f32(2), f32(0)
	for tick in u64(0) ..< 60 * 60 * 10 {
		previous := memory
		memory = advance_hum_drift(memory, tick)
		if memory.drift_count != previous.drift_count {
			length := memory.end_tick - memory.start_tick
			testing.expectf(t, length >= HUM_DRIFT_MINIMUM_TICKS && length <= HUM_DRIFT_MAXIMUM_TICKS, "drift of %d ticks", length)
		}
		factor := hum_drift_factor(memory, tick)
		testing.expectf(t, factor >= 1 - HUM_DRIFT_SHARE - 0.0001 && factor <= 1 + HUM_DRIFT_SHARE + 0.0001, "factor %v", factor)
		lowest, highest = min(lowest, factor), max(highest, factor)
	}
	testing.expect(t, highest - lowest > HUM_DRIFT_SHARE, "the level drifts")
	expect_near_value(t, hum_drift_factor({}, 0), 1)
}
