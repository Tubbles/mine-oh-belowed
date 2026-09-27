package game

import "core:testing"

@(test)
test_shipped_blocks_parse_and_validate :: proc(t: ^testing.T) {
	file, error := parse_blocks_file(#load("../data/blocks.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, validate_block_definitions(file.blocks), "")
	registry := Block_Registry {
		definitions = file.blocks,
	}
	air, air_found := find_block_id(registry, "air")
	testing.expect(t, air_found)
	testing.expect_value(t, air, AIR_BLOCK)
	_, terrain_ok := resolve_debug_terrain_blocks(registry)
	testing.expect(t, terrain_ok)
	grass, _ := find_block_id(registry, "grass")
	testing.expect(t, block_is_solid(registry, grass))
	testing.expect_value(t, registry.definitions[grass].texture.top, [3]u8{106, 170, 64})
}

@(test)
test_block_validation_rejects_bad_tables :: proc(t: ^testing.T) {
	no_air := [?]Block_Definition{{id = "stone", solid = true}}
	testing.expect(t, validate_block_definitions(no_air[:]) != "")
	solid_air := [?]Block_Definition{{id = "air", solid = true}}
	testing.expect(t, validate_block_definitions(solid_air[:]) != "")
	duplicate := [?]Block_Definition{{id = "air"}, {id = "stone"}, {id = "stone"}}
	testing.expect(t, validate_block_definitions(duplicate[:]) != "")
	unnamed := [?]Block_Definition{{id = "air"}, {id = ""}}
	testing.expect(t, validate_block_definitions(unnamed[:]) != "")
	below_hands := [?]Block_Definition{{id = "air"}, {id = "stone", hardness_seconds = 1, tool_tier = -1}}
	testing.expect_value(t, validate_block_definitions(below_hands[:]), `block "stone" has a negative tool_tier`)
}
