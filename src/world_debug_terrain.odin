package game

import "core:container/queue"
import "core:math"
import "generation_seed"
import "platform"

// Fixed terrain built in code, shown with --debug-terrain instead of the
// generated world, for comparing the mesher against a known scene.

DEBUG_TERRAIN_CHUNKS_X :: 8
DEBUG_TERRAIN_CHUNKS_Y :: 2
DEBUG_TERRAIN_CHUNKS_Z :: 8
// Keeps the surface, which varies by about 7 blocks either way, inside the
// upper chunk layer.
DEBUG_TERRAIN_BASE_HEIGHT :: 46
DEBUG_TERRAIN_DIRT_DEPTH :: 3
// About one surface block in this many is ore.
DEBUG_TERRAIN_ORE_RARITY :: 500

Debug_Terrain_Blocks :: struct {
	stone:    Block_Id,
	dirt:     Block_Id,
	grass:    Block_Id,
	sand:     Block_Id,
	hematite: Block_Id,
}

resolve_debug_terrain_blocks :: proc(registry: Block_Registry) -> (blocks: Debug_Terrain_Blocks, ok: bool) {
	names := [5]string{"stone", "dirt", "grass", "sand", "hematite_ore"}
	targets := [5]^Block_Id{&blocks.stone, &blocks.dirt, &blocks.grass, &blocks.sand, &blocks.hematite}
	for name, index in names {
		found: bool
		targets[index]^, found = find_block_id(registry, name)
		if !found {
			platform.log_printf("error: the debug terrain needs block %q in %s", name, BLOCKS_FILE_NAME)
			return {}, false
		}
	}
	return blocks, true
}

debug_terrain_height :: proc(x, z: i32) -> i32 {
	wave := 4 * math.sin(f32(x) / 13) + 3 * math.sin(f32(z) / 17)
	return DEBUG_TERRAIN_BASE_HEIGHT + i32(math.round(wave))
}

debug_terrain_is_sand :: proc(x, z: i32) -> bool {
	return math.sin(f32(x) * 0.11) * math.cos(f32(z) * 0.09) > 0.75
}

debug_terrain_is_ore :: proc(x, z: i32) -> bool {
	key := u64(u32(x)) << 32 | u64(u32(z))
	return generation_seed.hash_u64(key) % DEBUG_TERRAIN_ORE_RARITY == 0
}

debug_terrain_surface_block :: proc(blocks: Debug_Terrain_Blocks, x, z: i32) -> Block_Id {
	switch {
	case debug_terrain_is_ore(x, z):
		return blocks.hematite
	case debug_terrain_is_sand(x, z):
		return blocks.sand
	}
	return blocks.grass
}

debug_terrain_block :: proc(blocks: Debug_Terrain_Blocks, position: World_Coordinate) -> Block_Id {
	height := debug_terrain_height(position.x, position.z)
	switch {
	case position.y > height:
		return AIR_BLOCK
	case position.y == height:
		return debug_terrain_surface_block(blocks, position.x, position.z)
	case position.y > height - DEBUG_TERRAIN_DIRT_DEPTH:
		return debug_terrain_is_sand(position.x, position.z) ? blocks.sand : blocks.dirt
	}
	return blocks.stone
}

fill_debug_terrain_chunk :: proc(chunk: ^Chunk, blocks: Debug_Terrain_Blocks) {
	for index in 0 ..< CHUNK_BLOCK_COUNT {
		position := local_to_world_coordinate(chunk.coordinate, index_to_local(index))
		chunk.blocks[index] = debug_terrain_block(blocks, position)
	}
}

// The terrain has nothing over its surface, so a column is open to the sky
// above a chunk when its surface lies below the chunk's top.
debug_terrain_sky_light :: proc(chunk: ^Chunk, registry: Block_Registry) {
	origin := chunk_origin(chunk.coordinate)
	open: Open_Columns
	for z in i32(0) ..< CHUNK_SIZE {
		for x in i32(0) ..< CHUNK_SIZE {
			open[column_index(x, z)] = debug_terrain_height(origin.x + x, origin.z + z) < origin.y + CHUNK_SIZE
		}
	}
	fill_chunk_sky_light(chunk, registry, &open)
}

// Chunks x and z run from -4 to 3, so negative coordinates are exercised.
// Light across chunk borders follows in the first ticks, like streamed chunks.
build_debug_terrain :: proc(world: ^World, registry: Block_Registry, blocks: Debug_Terrain_Blocks) {
	for y in i32(0) ..< DEBUG_TERRAIN_CHUNKS_Y {
		for z in i32(0) ..< DEBUG_TERRAIN_CHUNKS_Z {
			for x in i32(0) ..< DEBUG_TERRAIN_CHUNKS_X {
				coordinate := Chunk_Coordinate{x - DEBUG_TERRAIN_CHUNKS_X / 2, y, z - DEBUG_TERRAIN_CHUNKS_Z / 2}
				chunk := world_create_chunk(world, coordinate)
				fill_debug_terrain_chunk(chunk, blocks)
				debug_terrain_sky_light(chunk, registry)
				queue.push_back(&world.lighting.arrived_chunks, coordinate)
			}
		}
	}
}
