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
	memory, cues := advance_sound_memory({}, {tick = 1, distance_millimetres = 790, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect_value(t, cues, Sound_Cues{})
	memory, cues = advance_sound_memory(memory, {tick = 2, distance_millimetres = 810, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, cues.footstep)
	testing.expect_value(t, memory.step_count, 1)
	// The same tick again, a frame faster than the tick rate: no step.
	memory, cues = advance_sound_memory(memory, {tick = 2, distance_millimetres = 810, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, !cues.footstep)
	memory, cues = advance_sound_memory(memory, {tick = 3, distance_millimetres = 1590, placed_total = 4, blocks_mined = 9, message_count = 2})
	testing.expect(t, !cues.footstep)
	memory, cues = advance_sound_memory(memory, {tick = 4, distance_millimetres = 1610, placed_total = 4, blocks_mined = 9, message_count = 2})
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
