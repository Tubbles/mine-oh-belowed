package game

import "core:testing"

// No test here touches raylib audio: the table, the gap rule and the
// volume approach are pure.

shipped_sound_table :: proc(t: ^testing.T) -> Sound_Table {
	table, problem := load_sound_table(test_data_directory(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	return table
}

shipped_block_registry :: proc(t: ^testing.T) -> Block_Registry {
	file, error := parse_blocks_file(#load("../data/blocks.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	return Block_Registry{definitions = file.blocks}
}

// Only the definitions: enough for the ambience.
shipped_biome_definitions :: proc(t: ^testing.T) -> []Biome {
	file, error := parse_biomes_file(#load("../data/biomes.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	biomes := make([]Biome, len(file.biomes), context.temp_allocator)
	for definition, index in file.biomes {
		biomes[index].definition = definition
	}
	return biomes
}

@(test)
test_shipped_sound_table_loads_with_every_file :: proc(t: ^testing.T) {
	table := shipped_sound_table(t)
	testing.expect_value(t, len(table.entries), 32)
	testing.expect_value(t, missing_sound_file(table, test_data_directory()), "")
	index, found := find_sound(table, "rain")
	testing.expect(t, found)
	testing.expect_value(t, table.entries[index].kind, Sound_Kind.Loop)
	index, found = find_sound(table, "block_break")
	testing.expect(t, found)
	testing.expect_value(t, table.entries[index].kind, Sound_Kind.Effect)
	for id in hum_sound_ids {
		testing.expectf(t, sound_listed(table, id), "%s is listed", id)
	}
	for id in ui_sound_ids {
		testing.expectf(t, sound_listed(table, id), "%s is listed", id)
	}
	fixed := [?]string{BLOCK_BREAK_SOUND, BLOCK_PLACE_SOUND, RAIN_SOUND, ROCKET_LAUNCH_SOUND, CAPSULE_LANDING_SOUND, DISCOVERY_SOUND, footstep_sound_id(DEFAULT_SOUND_MATERIAL)}
	for id in fixed {
		testing.expectf(t, sound_listed(table, id), "%s is listed", id)
	}
}

@(test)
test_shipped_blocks_and_biomes_name_listed_sounds :: proc(t: ^testing.T) {
	table := shipped_sound_table(t)
	blocks := shipped_block_registry(t)
	testing.expect_value(t, validate_sound_references(table, blocks, shipped_biome_definitions(t)), "")
	materials := [?]string{"stone", "dirt", "sand", "wood", "leaves", "snow", "metal", "water"}
	for material in materials {
		testing.expectf(t, sound_listed(table, footstep_sound_id(material)), "footstep for %s", material)
	}
}

@(test)
test_sound_references_catch_a_missing_footstep_or_ambience :: proc(t: ^testing.T) {
	entries := [?]Sound_Entry{{id = "footstep_stone", file = "a.wav", volume = 1}, {id = "ambience_wind", file = "b.wav", volume = 1, kind = .Loop}}
	table := Sound_Table{entries = entries[:]}
	definitions := [?]Block_Definition{{id = "air"}, {id = "glass", sound_material = "glass"}}
	testing.expect_value(t, validate_sound_references(table, Block_Registry{definitions = definitions[:1]}, nil), "")
	testing.expect(t, validate_sound_references(table, Block_Registry{definitions = definitions[:]}, nil) != "")
	biomes := [?]Biome{{definition = {id = "a", ambience = "wind"}}, {definition = {id = "b"}}, {definition = {id = "c", ambience = "birds"}}}
	testing.expect_value(t, validate_sound_references(table, {}, biomes[:2]), "")
	testing.expect(t, validate_sound_references(table, {}, biomes[:]) != "")
	// Clustered calls stand in for a loop; a loop named _1 does not.
	clustered := [?]Sound_Entry{{id = "ambience_birds_1", file = "c.wav", volume = 1}}
	testing.expect_value(t, validate_sound_references(Sound_Table{entries = clustered[:]}, {}, biomes[2:]), "")
	clustered[0].kind = .Loop
	testing.expect(t, validate_sound_references(Sound_Table{entries = clustered[:]}, {}, biomes[2:]) != "")
}

@(test)
test_sound_table_rejects_bad_entries :: proc(t: ^testing.T) {
	valid := Sound_Definition{id = "a", file = "a.wav", volume = 0.5, kind = "effect"}
	cases := [?]struct {
		sounds: [2]Sound_Definition,
	} {
		{{valid, valid}},
		{{valid, {id = "b", file = "b.wav", volume = 0.5, kind = "music"}}},
		{{valid, {id = "b", file = "b.wav", volume = 1.5, kind = "loop"}}},
		{{valid, {id = "b", file = "b.wav", volume = 0, kind = "loop"}}},
		{{valid, {id = "b", volume = 1, kind = "loop"}}},
		{{valid, {file = "b.wav", volume = 1, kind = "loop"}}},
	}
	for &entry in cases {
		_, problem := resolve_sound_table(Sounds_File{sounds = entry.sounds[:]}, context.temp_allocator)
		testing.expectf(t, problem != "", "%v is refused", entry.sounds[1])
	}
	good := [?]Sound_Definition{valid, {id = "b", file = "b.wav", volume = 1, kind = "loop"}, {id = "c", file = "c.wav", volume = 1, kind = "effect", day_only = true}}
	table, problem := resolve_sound_table(Sounds_File{sounds = good[:]}, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, table.entries[1].kind, Sound_Kind.Loop)
	testing.expect(t, !table.entries[0].day_only && table.entries[2].day_only, "day_only carries over")
	testing.expect(t, missing_sound_file(table, test_data_directory()) != "")
}

@(test)
test_effect_gap_rule :: proc(t: ^testing.T) {
	state := make_mixer_state(2, context.temp_allocator)
	testing.expect(t, mixer_request_effect(&state, 0))
	testing.expect(t, !mixer_request_effect(&state, 0))
	// Another id is not held back.
	testing.expect(t, mixer_request_effect(&state, 1))
	advance_mixer_state(&state, 0.03)
	testing.expect(t, !mixer_request_effect(&state, 0))
	advance_mixer_state(&state, 0.03)
	testing.expect(t, mixer_request_effect(&state, 0))
	testing.expect(t, effect_gap_allows(NEVER_PLAYED_SECONDS, 0))
	testing.expect(t, effect_gap_allows(1, 1 + EFFECT_MINIMUM_GAP_SECONDS))
	testing.expect(t, !effect_gap_allows(1, 1.01))
}

@(test)
test_loop_volume_approaches_its_target_over_half_a_second :: proc(t: ^testing.T) {
	expect_near_value(t, approach_loop_volume(0, 1, 0.25), 0.5)
	expect_near_value(t, approach_loop_volume(0, 1, 0.5), 1)
	expect_near_value(t, approach_loop_volume(0, 1, 2), 1)
	expect_near_value(t, approach_loop_volume(1, 0.2, 0.1), 0.8)
	expect_near_value(t, approach_loop_volume(0.3, 0.2, 0.1), 0.2)
	state := make_mixer_state(1, context.temp_allocator)
	mixer_set_loop_target(&state, 0, 0.4)
	mixer_set_loop_target(&state, 0, 1)
	mixer_set_loop_target(&state, 0, 0.2)
	advance_mixer_state(&state, 0.25)
	expect_near_value(t, state.loop_volumes[0], 0.5)
	testing.expect_value(t, state.loop_targets[0], 0)
	// Nobody asks any more: it fades out.
	advance_mixer_state(&state, 0.125)
	expect_near_value(t, state.loop_volumes[0], 0.25)
	advance_mixer_state(&state, 0.5)
	expect_near_value(t, state.loop_volumes[0], 0)
}

@(test)
test_output_volume_by_channel :: proc(t: ^testing.T) {
	volumes := audio_volumes(DEFAULT_SETTINGS)
	testing.expect_value(t, volumes, Audio_Volumes{master = 0.8, effects = 1, ambience = 0.7})
	effect := Sound_Entry{volume = 0.5, kind = .Effect}
	loop := Sound_Entry{volume = 0.5, kind = .Loop}
	expect_near_value(t, sound_output_volume(effect, 1, volumes), 0.4)
	expect_near_value(t, sound_output_volume(loop, 0.5, volumes), 0.14)
	// A clustered ambience call is an effect on the ambience channel.
	call := Sound_Entry{id = "ambience_birds_1", volume = 0.5, kind = .Effect}
	expect_near_value(t, sound_output_volume(call, 1, volumes), 0.28)
	silent := DEFAULT_SETTINGS
	silent.master_volume = 0
	expect_near_value(t, sound_output_volume(effect, 1, audio_volumes(silent)), 0)
	loud := DEFAULT_SETTINGS
	loud.effects_volume = 3
	testing.expect_value(t, audio_volumes(loud).effects, 1)
}
