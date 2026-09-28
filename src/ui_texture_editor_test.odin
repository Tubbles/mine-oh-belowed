package game

import "core:os"
import "core:strings"
import "core:testing"

// The texture editor (work item 0100): the seed step and the reroll, the
// preview field against the chunk shader's orientation, the overrides
// file through the parser, a slider step through the screen, and the
// textures query.

shipped_texture_editor :: proc(t: ^testing.T) -> (editor: Texture_Editor, registry: Block_Registry) {
	registry = shipped_block_registry(t)
	load_texture_editor(&editor, test_data_directory(), "", registry)
	testing.expect_value(t, len(editor.entries), len(SHIPPED_ORE_BLOCKS))
	return editor, registry
}

@(test)
test_texture_seed_step_and_reroll_are_pure :: proc(t: ^testing.T) {
	largest := int(ore_texture_parameter_ranges[.Seed].maximum)
	testing.expect_value(t, step_texture_seed(1101, .Right), 1102)
	testing.expect_value(t, step_texture_seed(1101, .Left), 1100)
	testing.expect_value(t, step_texture_seed(1101, .Up), 1101)
	testing.expect_value(t, step_texture_seed(0, .Left), largest)
	testing.expect_value(t, step_texture_seed(largest, .Right), 0)
	seen: map[int]bool
	defer delete(seen)
	for tick in u64(0) ..< 64 {
		seed := reroll_texture_seed(tick, 1101)
		testing.expect_value(t, reroll_texture_seed(tick, 1101), seed)
		testing.expect(t, seed >= 0 && seed <= largest)
		testing.expect(t, seed != 1101)
		seen[seed] = true
	}
	testing.expect_value(t, len(seen), 64)
	testing.expect(t, reroll_texture_seed(7, 1101) != reroll_texture_seed(7, 1102), "the old seed counts")
}

// The texel a turned, mirrored and slid cell shows at (u, v), in whole
// texels: the discrete form of orient_tile_texcoord and
// shift_tile_texcoord.
expected_field_texel :: proc(u, v, turns: int, mirrored: bool, offset: [2]int) -> [2]int {
	last := ATLAS_TILE_SIZE - 1
	x := mirrored ? last - u : u
	oriented := [2]int{x, v}
	switch turns {
	case 1:
		oriented = {last - v, x}
	case 2:
		oriented = {last - x, last - v}
	case 3:
		oriented = {v, last - x}
	}
	return {wrap_texel(oriented.x + offset.x), wrap_texel(oriented.y + offset.y)}
}

@(test)
test_texture_preview_field_follows_face_tile_orientation :: proc(t: ^testing.T) {
	tile: Tile_Pixels
	for &texel, index in tile {
		texel = {u8(index % ATLAS_TILE_SIZE * 16), u8(index / ATLAS_TILE_SIZE * 16), 100, 255}
	}
	for y in 0 ..< TEXTURE_EDITOR_FIELD_TEXELS {
		for x in 0 ..< TEXTURE_EDITOR_FIELD_TEXELS {
			hash := texture_variation_hash({i32(x / ATLAS_TILE_SIZE), 0, i32(y / ATLAS_TILE_SIZE)})
			turns, mirrored := face_tile_orientation(hash, .Full)
			expected := expected_field_texel(x % ATLAS_TILE_SIZE, y % ATLAS_TILE_SIZE, turns, mirrored, face_tile_offset(hash, .Full))
			source, source_hash := texture_field_source(x, y)
			testing.expectf(t, source == expected, "field (%d, %d): texel %v, expected %v", x, y, source, expected)
			testing.expect_value(t, source_hash, hash)
			shaded := Ui_Color(shaded_texel(tile[texel_index(expected.x, expected.y)].rgb, 0, texture_variation_brightness(hash)))
			testing.expect_value(t, texture_field_pixel(tile, x, y), shaded)
		}
	}
	// The enlarged tile on the left is the tile upright.
	testing.expect_value(t, texture_preview_pixel(tile, 5 * TEXTURE_EDITOR_PREVIEW_CELLS, 2 * TEXTURE_EDITOR_PREVIEW_CELLS), Ui_Color(tile[texel_index(5, 2)]))
	testing.expect_value(t, texture_preview_pixel(tile, TEXTURE_EDITOR_FIELD_TEXELS, 0), Ui_Color{})
}

@(test)
test_texture_edits_file_round_trips_through_the_parser :: proc(t: ^testing.T) {
	editor, registry := shipped_texture_editor(t)
	defer destroy_texture_editor(&editor)
	// Values off the step grid snap onto it, as the sliders set them.
	for &entry, index in editor.entries {
		entry.parameters.seed = reroll_texture_seed(u64(index), entry.parameters.seed)
		for parameter in Ore_Texture_Parameter {
			range := ore_texture_parameter_ranges[parameter]
			if parameter != .Seed {
				odd := range.minimum + (range.maximum - range.minimum) * (0.137 + 0.1 * f64(index))
				set_ore_texture_parameter(&entry.parameters, parameter, snapped_texture_parameter(range, odd))
			}
		}
	}
	text := format_texture_edits_file(texture_editor_lines(editor.entries[:]))
	parsed, problem := parse_procedural_textures(transmute([]byte)text, "texture_edits.sjson", registry, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(parsed), len(editor.entries))
	for entry in editor.entries {
		found_entry, found := find_procedural_texture(parsed, entry.block)
		testing.expectf(t, found && found_entry.parameters == entry.parameters, "%s: %v read back as %v", entry.block_name, entry.parameters, found_entry.parameters)
	}
	// Written to the state directory, the loader takes it over the data file.
	directory := make_configuration_test_directory()
	defer os.remove_all(directory)
	path := join_save_path(directory, "state", TEXTURE_EDITS_FILE_NAME)
	testing.expect_value(t, write_texture_edits_file(path, text), "")
	loaded := load_procedural_textures(test_data_directory(), path, registry)
	for entry in editor.entries {
		found_entry, _ := find_procedural_texture(loaded, entry.block)
		testing.expect_value(t, found_entry.parameters, entry.parameters)
	}
	// An edited entry survives a reload of the files; Reset's defaults stay
	// the data file's.
	editor.entries[0].edited = true
	edited := editor.entries[0].parameters
	load_texture_editor(&editor, test_data_directory(), "", registry)
	testing.expect_value(t, editor.entries[0].parameters, edited)
	testing.expect(t, editor.entries[1].parameters == editor.entries[1].defaults)
}

@(test)
test_texture_parameter_values_print_like_the_data_file :: proc(t: ^testing.T) {
	testing.expect_value(t, format_texture_parameter_value(ore_texture_parameter_ranges[.Share], 0.2), "0.2")
	testing.expect_value(t, format_texture_parameter_value(ore_texture_parameter_ranges[.Blob_Width], 0.65), "0.65")
	testing.expect_value(t, format_texture_parameter_value(ore_texture_parameter_ranges[.Blob_Width], 3), "3")
	testing.expect_value(t, format_texture_parameter_value(ore_texture_parameter_ranges[.Seed], 1101), "1101")
	testing.expect_value(t, snapped_texture_parameter(ore_texture_parameter_ranges[.Rim_Strength], 0.93), 0.8)
	testing.expect_value(t, snapped_texture_parameter(ore_texture_parameter_ranges[.Blob_Width], 0.674), 0.65)
	testing.expect_value(t, format_procedural_texture_entry("hematite_ore", .Ore, test_ore_parameters()), "{block = \"hematite_ore\", kind = \"ore\", seed = 7, share = 0.2, blob_width = 0.7, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 14, rim_strength = 0.2}")
}

// A d-pad step right on the focused Blob share slider changes the
// selected entry, its tile and the preview's revision.
@(test)
test_texture_editor_slider_step_regenerates_the_tile :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	editor := &audit.texture_editor
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Developer)
	push_screen(&state.screens, .Textures)
	screen_test_frame(audit, &state, {})
	entry := editor.entries[editor.selected]
	revision := editor.revision
	state.focus = ui_hash(ui_hash(0, "texture_editor", -1), text("texture_editor_share"), -1)
	screen_test_frame(audit, &state, {navigation = .Right})
	changed := editor.entries[editor.selected]
	testing.expect_value(t, changed.parameters.share, f32(snapped_texture_parameter(ore_texture_parameter_ranges[.Share], f64(entry.parameters.share) + 0.01)))
	testing.expect(t, changed.edited)
	testing.expect(t, changed.tile != entry.tile, "the tile follows the share")
	testing.expect(t, editor.revision > revision)
	testing.expect_value(t, top_screen(state.screens), Screen.Textures)
	// The d-pad between the list and the controls: right from the first
	// row to Reroll, left from Reroll to a row.
	panel := ui_hash(0, "texture_editor", -1)
	reroll := ui_hash(panel, text("texture_editor_reroll"), -1)
	state.focus = ui_hash(panel, "texture", 0)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Right})
	testing.expect_value(t, state.focus, reroll)
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {navigation = .Left})
	row_focused := false
	for index in 0 ..< len(editor.entries) {
		row_focused ||= state.focus == ui_hash(panel, "texture", index)
	}
	testing.expect(t, row_focused, "left from Reroll lands on a list row")
}

@(test)
test_query_textures_answers_without_a_world :: proc(t: ^testing.T) {
	editor, _ := shipped_texture_editor(t)
	defer destroy_texture_editor(&editor)
	response, _ := execute_command_line(Command_Context{textures = editor.entries[:]}, "query textures")
	testing.expect(t, response.ok, response.text)
	testing.expect(t, strings.has_prefix(response.text, "textures 7\n{block = \"hematite_ore\", kind = \"ore\", seed = 1101, share = 0.2,"), response.text)
	testing.expect_value(t, strings.count(response.text, "\n"), len(editor.entries))
	response, _ = execute_command_line(Command_Context{}, "query textures extra")
	testing.expect(t, !response.ok)
}
