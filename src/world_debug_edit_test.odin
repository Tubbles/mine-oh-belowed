package game

import "core:testing"

@(test)
test_debug_remove_block_digs_topmost_solid_below_camera :: proc(t: ^testing.T) {
	world := make_test_world({{-1, 0, -1}})
	chunk := world.chunks[{-1, 0, -1}]
	fill_chunk(chunk, TEST_STONE)
	registry := Block_Registry {
		definitions = test_block_definitions[:],
	}
	// The camera is two chunks above; the chunk between is not loaded.
	removed, ok := debug_remove_block(&world, registry, {-10.5, 70, -3.2}, 1)
	testing.expect(t, ok)
	testing.expect_value(t, removed.y, 31)
	testing.expect_value(t, world_to_chunk_coordinate(removed), Chunk_Coordinate{-1, 0, -1})
	testing.expect_value(t, world_get_block(&world, removed), AIR_BLOCK)
	testing.expect(t, chunk.dirty)
}

@(test)
test_debug_remove_block_outside_the_world :: proc(t: ^testing.T) {
	world := make_test_world({{0, 0, 0}})
	registry := Block_Registry {
		definitions = test_block_definitions[:],
	}
	_, ok := debug_remove_block(&world, registry, {100, 10, 0}, 1)
	testing.expect(t, !ok)
}
