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

@(test)
test_oriented_shapes_expand_into_variants :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	ids := [?]string{"air", "stone", "slab", "slab_upper", "stairs", "stairs_r1", "stairs_r2", "stairs_r3", "torch", "tuft"}
	testing.expect_value(t, len(registry.definitions), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.definitions[index].id, id)
	}
	testing.expect_value(t, block_orientation(registry, SHAPE_TEST_UPPER_SLAB), Block_Orientation{upper = true})
	testing.expect_value(t, block_shape(registry, SHAPE_TEST_UPPER_SLAB), Block_Shape.Slab)
	testing.expect_value(t, registry.definitions[SHAPE_TEST_UPPER_SLAB].name_key, "block_stone")
	for rotation in u8(0) ..< 4 {
		stairs := SHAPE_TEST_STAIRS + Block_Id(rotation)
		testing.expect_value(t, block_orientation(registry, stairs), Block_Orientation{rotation = rotation})
		testing.expect_value(t, block_shape_base(registry, stairs), SHAPE_TEST_STAIRS)
		testing.expect_value(t, oriented_block(registry, SHAPE_TEST_STAIRS + 2, Block_Orientation{rotation = rotation}), stairs)
	}
	testing.expect_value(t, oriented_block(registry, SHAPE_TEST_SLAB, Block_Orientation{upper = true}), SHAPE_TEST_UPPER_SLAB)
	testing.expect_value(t, oriented_block(registry, SHAPE_TEST_UPPER_SLAB, {}), SHAPE_TEST_SLAB)
	testing.expect_value(t, oriented_block(registry, SHAPE_TEST_STONE, Block_Orientation{upper = true, rotation = 2}), SHAPE_TEST_STONE)
	testing.expect_value(t, block_shape(registry, SHAPE_TEST_TORCH), Block_Shape.Post)
	testing.expect_value(t, block_shape(registry, SHAPE_TEST_STONE), Block_Shape.Cube)
}

@(test)
test_only_solid_cubes_are_opaque :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	testing.expect(t, block_is_opaque(registry, SHAPE_TEST_STONE))
	testing.expect(t, block_is_solid(registry, SHAPE_TEST_SLAB))
	testing.expect(t, !block_is_opaque(registry, SHAPE_TEST_SLAB))
	testing.expect(t, !block_is_opaque(registry, SHAPE_TEST_STAIRS + 3))
	testing.expect(t, !block_is_opaque(registry, SHAPE_TEST_TORCH))
	testing.expect(t, !block_is_opaque(registry, SHAPE_TEST_TUFT))
}

@(test)
test_block_validation_rejects_bad_shapes :: proc(t: ^testing.T) {
	unknown := [?]Block_Definition{{id = "air"}, {id = "wedge", solid = true, shape = "wedge"}}
	testing.expect_value(t, validate_block_definitions(unknown[:]), `block "wedge" has unknown shape "wedge"`)
	soft_slab := [?]Block_Definition{{id = "air"}, {id = "slab", shape = "slab"}}
	testing.expect(t, validate_block_definitions(soft_slab[:]) != "")
	solid_post := [?]Block_Definition{{id = "air"}, {id = "pole", solid = true, shape = "post"}}
	testing.expect(t, validate_block_definitions(solid_post[:]) != "")
	// A block named like a variant collides with the expansion.
	file, error := parse_blocks_file(transmute([]byte)string(`blocks = [{id = "air"}, {id = "slab", solid = true, shape = "slab"}, {id = "slab_upper", solid = true}]`), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, validate_block_definitions(file.blocks), `block id "slab_upper" is defined twice`)
}

// Variants of the shipped slabs and stairs drop their listed block's item
// and read with its name.
@(test)
test_shipped_shape_variants_drop_the_base_item :: proc(t: ^testing.T) {
	registry := make_test_registry()
	items := make_test_items()
	testing.expect_value(t, block_shape(registry, test_block(registry, "torch")), Block_Shape.Post)
	for base in ([?]string{"stone_slab", "concrete_slab", "plank_slab", "stone_stairs", "concrete_stairs", "plank_stairs"}) {
		block := test_block(registry, base)
		item := test_item(items, base)
		testing.expect_value(t, item_places_block(items, item), block)
		for variant in 0 ..< shape_variant_count(block_shape(registry, block)) {
			testing.expect_value(t, block_drop(items, block + Block_Id(variant)), item)
			testing.expect_value(t, registry.definitions[block + Block_Id(variant)].name_key, registry.definitions[block].name_key)
			testing.expect_value(t, block_shape_base(registry, block + Block_Id(variant)), block)
		}
	}
	testing.expect_value(t, test_block(registry, "stone_stairs_r3"), test_block(registry, "stone_stairs") + 3)
}
