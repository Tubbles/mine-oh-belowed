package game

import "generation_seed"

// How many chunks below the camera the debug edit searches for a solid block.
DEBUG_EDIT_SEARCH_DEPTH :: 8

// Topmost solid block of one column of a chunk, so that the removed block
// is visible from above.
topmost_solid_in_column :: proc(chunk: ^Chunk, registry: Block_Registry, x, z: i32) -> (local: Local_Coordinate, found: bool) {
	for y := i32(CHUNK_SIZE - 1); y >= 0; y -= 1 {
		candidate := Local_Coordinate{x, y, z}
		if block_is_solid(registry, chunk_get_block(chunk, candidate)) {
			return candidate, true
		}
	}
	return {}, false
}

// Debug action for work item 0005: in the chunk column under the camera,
// picks a column from the hash of the counter and turns its topmost solid
// block into air, searching downwards through loaded chunks. Returns the
// removed position.
debug_remove_block :: proc(world: ^World, registry: Block_Registry, camera_position: [3]f32, counter: u64) -> (removed: World_Coordinate, ok: bool) {
	camera_chunk := world_to_chunk_coordinate(camera_world_coordinate(camera_position))
	random := generation_seed.hash_u64(counter)
	x := i32(random % CHUNK_SIZE)
	z := i32(random / CHUNK_SIZE % CHUNK_SIZE)
	for depth in i32(0) ..< DEBUG_EDIT_SEARCH_DEPTH {
		coordinate := camera_chunk - {0, depth, 0}
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			continue
		}
		local, found := topmost_solid_in_column(chunk, registry, x, z)
		if found {
			removed = local_to_world_coordinate(coordinate, local)
			world_set_block(world, removed, AIR_BLOCK)
			return removed, true
		}
	}
	return {}, false
}
