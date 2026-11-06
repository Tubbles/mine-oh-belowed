package game

import "core:os"
import "core:strings"
import "core:testing"
import "platform"

TEST_FIELD_MATERIAL_PARAMETERS :: "seed = 1, share = 0.3, blob_width = 0.8, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 8, rim_strength = 0.1"

test_field_material_entry :: proc(material: string) -> string {
	return strings.concatenate({"{material = \"", material, "\", ground = [120, 100, 80], fleck = [90, 80, 70], ", TEST_FIELD_MATERIAL_PARAMETERS, "}\n"}, context.temp_allocator)
}

test_field_look_entry :: proc(look: string) -> string {
	return strings.concatenate({"{look = \"", look, "\", ground = [130, 130, 130], fleck = [100, 100, 100], ", TEST_FIELD_MATERIAL_PARAMETERS, "}\n"}, context.temp_allocator)
}

TEST_FIELD_MATERIAL_NAMES :: [?]string{"topsoil", "stone", "deep_stone", "bedrock", "hematite_ore", "chalcopyrite_ore", "coal_ore"}

// The file's text from its entries.
test_field_textures_text :: proc(materials, looks: string) -> []byte {
	return transmute([]byte)strings.concatenate({"materials = [\n", materials, "]\nlooks = [\n", looks, "]"}, context.temp_allocator)
}

test_every_field_material_entry :: proc() -> string {
	entries: [len(TEST_FIELD_MATERIAL_NAMES)]string
	for name, index in TEST_FIELD_MATERIAL_NAMES {
		entries[index] = test_field_material_entry(name)
	}
	return strings.concatenate(entries[:], context.temp_allocator)
}

test_every_field_look_entry :: proc() -> string {
	return strings.concatenate({test_field_look_entry("grass"), test_field_look_entry("sand"), test_field_look_entry("snow")}, context.temp_allocator)
}

@(test)
test_the_shipped_field_material_textures_load :: proc(t: ^testing.T) {
	tiles, problem := parse_field_material_textures(#load("../data/textures/field_materials.sjson"), "field_materials.sjson")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(tiles), 10)
	for tile in 1 ..< FIELD_GROUND_TILE_COUNT {
		testing.expectf(t, tiles[tile] != tiles[0], "ground tile %d is the first material's tile", tile)
	}
}

// Work item 0307: every look needs one entry, as every material does.
@(test)
test_field_look_textures_need_every_look_once :: proc(t: ^testing.T) {
	materials := test_every_field_material_entry()
	tiles, problem := parse_field_material_textures(test_field_textures_text(materials, test_every_field_look_entry()), "test")
	testing.expect_value(t, problem, "")
	testing.expect(t, tiles[field_look_tile(.Grass)] != {}, "the grass tile is filled")
	cases := [?]struct {
		looks:    string,
		expected: string,
	} {
		{strings.concatenate({test_field_look_entry("grass"), test_field_look_entry("sand")}, context.temp_allocator), "no entry for look snow"},
		{strings.concatenate({test_field_look_entry("grass"), test_field_look_entry("grass")}, context.temp_allocator), "looks[1] repeats grass"},
		{test_field_look_entry("moss"), "unknown look moss"},
		{"{look = \"sand\", material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3], " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "unknown key material"},
		{"{look = \"sand\", ground = [1, 2, 3], fleck = [1, 2, 3], seed = 1, share = 0.3, blob_width = 0.8, crystal_size = 3, stone_grain = 8, stone_mottle = 16, ore_grain = 8, rim_strength = 0.1}", "crystal_size is 3, not 1"},
	}
	for entry in cases {
		_, case_problem := parse_field_material_textures(test_field_textures_text(materials, entry.looks), "test")
		testing.expectf(t, strings.contains(case_problem, entry.expected), "%q does not say %q", case_problem, entry.expected)
	}
	_, problem = parse_field_material_textures(transmute([]byte)strings.concatenate({"materials = [\n", materials, "]"}, context.temp_allocator), "test")
	testing.expect(t, strings.contains(problem, "expected only materials and looks, arrays"), problem)
}

// Work item 0307: each cell of the ground atlas holds its tile repeated,
// the copy the shader reads starting the margin in, so its mipmaps keep
// to the cell; unused cells are zero.
@(test)
test_the_ground_atlas_cells_repeat_their_tile :: proc(t: ^testing.T) {
	tiles, problem := parse_field_material_textures(#load("../data/textures/field_materials.sjson"), "field_materials.sjson")
	testing.expect_value(t, problem, "")
	pixels := field_ground_atlas_pixels(tiles, context.temp_allocator)
	testing.expect_value(t, len(pixels), FIELD_GROUND_ATLAS_TEXELS * FIELD_GROUND_ATLAS_TEXELS)
	at :: proc(pixels: [][4]u8, cell, x, y: int) -> [4]u8 {
		column, row := cell % FIELD_GROUND_ATLAS_COLUMNS, cell / FIELD_GROUND_ATLAS_COLUMNS
		return pixels[(row * FIELD_GROUND_ATLAS_CELL_TEXELS + y) * FIELD_GROUND_ATLAS_TEXELS + column * FIELD_GROUND_ATLAS_CELL_TEXELS + x]
	}
	margin := FIELD_GROUND_ATLAS_MARGIN_TEXELS
	for tile, index in tiles {
		mismatches := 0
		for j in 0 ..< ATLAS_TILE_SIZE {
			for i in 0 ..< ATLAS_TILE_SIZE {
				texel := tile[j * ATLAS_TILE_SIZE + i]
				mismatches += at(pixels, index, margin + i, margin + j) != texel ? 1 : 0
				mismatches += at(pixels, index, margin + i + ATLAS_TILE_SIZE, margin + j) != texel ? 1 : 0
				mismatches += at(pixels, index, margin + i - ATLAS_TILE_SIZE, margin + j - ATLAS_TILE_SIZE) != texel ? 1 : 0
			}
		}
		testing.expectf(t, mismatches == 0, "cell %d differs from its tile at %d texels", index, mismatches)
	}
	for cell in FIELD_GROUND_TILE_COUNT ..< FIELD_GROUND_ATLAS_COLUMNS * FIELD_GROUND_ATLAS_COLUMNS {
		for y in 0 ..< FIELD_GROUND_ATLAS_CELL_TEXELS {
			for x in 0 ..< FIELD_GROUND_ATLAS_CELL_TEXELS {
				testing.expect_value(t, at(pixels, cell, x, y), [4]u8{})
			}
		}
	}
}

@(test)
test_field_material_textures_need_every_material_once :: proc(t: ^testing.T) {
	complete := test_every_field_material_entry()
	_, problem := parse_field_material_textures(test_field_textures_text(complete, test_every_field_look_entry()), "test")
	testing.expect_value(t, problem, "")
	cases := [?]struct {
		entries:  string,
		expected: string,
	} {
		{strings.concatenate({test_field_material_entry("topsoil"), test_field_material_entry("stone"), test_field_material_entry("deep_stone"), test_field_material_entry("hematite_ore"), test_field_material_entry("chalcopyrite_ore"), test_field_material_entry("coal_ore")}, context.temp_allocator), "no entry for bedrock"},
		{strings.concatenate({complete, test_field_material_entry("stone")}, context.temp_allocator), "repeats stone"},
		{test_field_material_entry("air"), "unknown material air"},
		{"{material = \"stone\", ground = [1, 2], fleck = [1, 2, 3], " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "ground must be an array"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 300], " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "fleck[2] must be"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3], grain = 3, " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "unknown key grain"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3]}", "has no seed"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3], seed = 1, share = 0.3, blob_width = 0.8, crystal_size = 2, stone_grain = 8, stone_mottle = 16, ore_grain = 8, rim_strength = 0.1}", "crystal_size is 2, not 1"},
	}
	for entry in cases {
		_, case_problem := parse_field_material_textures(test_field_textures_text(entry.entries, test_every_field_look_entry()), "test")
		testing.expectf(t, strings.contains(case_problem, entry.expected), "%q does not say %q", case_problem, entry.expected)
	}
}

// Stands in for load_field_presentation, whose shaders need GL: the tiles
// load for real, and a shader fails as an older copy does, a field.vs
// without the look's outputs as GLSL ES fails to link it (desktop Mesa
// links it) and a field.fs without the ground atlas by
// init_field_renderer's check. The renderer carries the tiles' mean
// colours.
test_load_field_presentation :: proc(data_directory: string, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, problem: string) {
	tiles: Field_Ground_Tiles
	if tiles, problem = load_field_material_tiles(data_directory); problem != "" {
		return {}, problem
	}
	markers := [2][2]string{{FIELD_VERTEX_SHADER_PATH, "out vec3 fragment_look;"}, {FIELD_FRAGMENT_SHADER_PATH, "uniform sampler2D " + FIELD_GROUND_ATLAS_SAMPLER + ";"}}
	for marker in markers {
		source, source_path, error := read_data_file(data_directory, marker[0], context.temp_allocator)
		if error != nil || !strings.contains(string(source), marker[1]) {
			return {}, strings.concatenate({"cannot load the field shader from ", source_path}, context.temp_allocator)
		}
	}
	for slot in 0 ..< FIELD_MATERIAL_TILE_COUNT {
		renderer.material_colors[slot] = tile_mean_color(tiles[slot])
	}
	return renderer, ""
}

// Work item 0307: an overlay copy of the materials file or of a field
// shader written before the looks fails the field's start, which loads
// again from the data files with the overlay off; a failure without the
// overlay stands. The decision is tested through a stand-in, since
// loading a shader needs a GL context the tests do not have.
@(test)
test_a_stale_overlay_copy_of_the_field_falls_back :: proc(t: ^testing.T) {
	defer reset_data_edits_reading()
	shipped, shipped_problem := test_load_field_presentation(test_data_directory(), {}, 1000, 0)
	testing.expect_value(t, shipped_problem, "")
	materials_only := strings.concatenate({"materials = [\n", test_every_field_material_entry(), "]"}, context.temp_allocator)
	stale_copies := [3][2]string {
		{FIELD_MATERIALS_TEXTURE_FILE, materials_only},
		{FIELD_VERTEX_SHADER_PATH, "#version 330\nout vec3 fragment_normal;\n"},
		{FIELD_FRAGMENT_SHADER_PATH, "#version 330\nuniform sampler2D material_texture_topsoil;\n"},
	}
	for stale in stale_copies {
		reset_data_edits_reading()
		edits_directory, error := os.make_directory_temp("", "mine-oh-belowed-field-presentation-test-*", context.temp_allocator)
		testing.expect_value(t, error, nil)
		defer os.remove_all(edits_directory)
		data_edits_reading.directory = edits_directory
		stale_path := platform.join_path(edits_directory, stale[0])
		testing.expect_value(t, os.make_directory_all(platform.join_path(edits_directory, stale[0][:strings.last_index_byte(stale[0], '/')])), nil)
		testing.expect_value(t, os.write_entire_file(stale_path, transmute([]byte)stale[1]), nil)
		_, problem := test_load_field_presentation(test_data_directory(), {}, 1000, 0)
		testing.expectf(t, strings.contains(problem, edits_directory), "the stale %s fails from the overlay: %s", stale[0], problem)
		renderer, fallback_problem := load_field_presentation_or_without_edits(test_load_field_presentation, test_data_directory(), {}, 1000, 0)
		testing.expect_value(t, fallback_problem, "")
		testing.expectf(t, data_edits_reading.off, "the stale %s turns the overlay off for the run", stale[0])
		testing.expect(t, renderer.material_colors == shipped.material_colors, "the shipped tiles load")
	}
	failing_load :: proc(data_directory: string, planet: Planet, spacing_millimetres: int, fog_end: f32) -> (renderer: Field_Renderer, problem: string) {
		return {}, "the field shaders did not load"
	}
	_, problem := load_field_presentation_or_without_edits(failing_load, test_data_directory(), {}, 1000, 0)
	testing.expect_value(t, problem, "the field shaders did not load")
}
