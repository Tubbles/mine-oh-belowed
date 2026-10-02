package game

import "core:strings"
import "core:testing"

TEST_FIELD_MATERIAL_PARAMETERS :: "seed = 1, share = 0.3, blob_width = 0.8, crystal_size = 1, stone_grain = 8, stone_mottle = 16, ore_grain = 8, rim_strength = 0.1"

test_field_material_entry :: proc(material: string) -> string {
	return strings.concatenate({"{material = \"", material, "\", ground = [120, 100, 80], fleck = [90, 80, 70], ", TEST_FIELD_MATERIAL_PARAMETERS, "}\n"}, context.temp_allocator)
}

@(test)
test_the_shipped_field_material_textures_load :: proc(t: ^testing.T) {
	tiles, problem := parse_field_material_textures(#load("../data/textures/field_materials.sjson"), "field_materials.sjson")
	testing.expect_value(t, problem, "")
	for slot in 1 ..< FIELD_TEXTURED_MATERIAL_COUNT {
		testing.expectf(t, tiles[slot] != tiles[0], "material slot %d has the first slot's tile", slot)
	}
}

@(test)
test_field_material_textures_need_every_material_once :: proc(t: ^testing.T) {
	complete := strings.concatenate({test_field_material_entry("topsoil"), test_field_material_entry("stone"), test_field_material_entry("deep_stone"), test_field_material_entry("bedrock")}, context.temp_allocator)
	_, problem := parse_field_material_textures(transmute([]byte)strings.concatenate({"materials = [\n", complete, "]"}, context.temp_allocator), "test")
	testing.expect_value(t, problem, "")
	cases := [?]struct {
		entries:  string,
		expected: string,
	} {
		{strings.concatenate({test_field_material_entry("topsoil"), test_field_material_entry("stone"), test_field_material_entry("deep_stone")}, context.temp_allocator), "no entry for bedrock"},
		{strings.concatenate({complete, test_field_material_entry("stone")}, context.temp_allocator), "repeats stone"},
		{test_field_material_entry("air"), "unknown material air"},
		{"{material = \"stone\", ground = [1, 2], fleck = [1, 2, 3], " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "ground must be an array"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 300], " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "fleck[2] must be"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3], grain = 3, " + TEST_FIELD_MATERIAL_PARAMETERS + "}", "unknown key grain"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3]}", "has no seed"},
		{"{material = \"stone\", ground = [1, 2, 3], fleck = [1, 2, 3], seed = 1, share = 0.3, blob_width = 0.8, crystal_size = 2, stone_grain = 8, stone_mottle = 16, ore_grain = 8, rim_strength = 0.1}", "crystal_size is 2, not 1"},
	}
	for entry in cases {
		_, case_problem := parse_field_material_textures(transmute([]byte)strings.concatenate({"materials = [\n", entry.entries, "]"}, context.temp_allocator), "test")
		testing.expectf(t, strings.contains(case_problem, entry.expected), "%q does not say %q", case_problem, entry.expected)
	}
}
