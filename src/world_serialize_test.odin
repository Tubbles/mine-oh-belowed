package game

import "core:slice"
import "core:testing"

expect_round_trip :: proc(t: ^testing.T, chunk: ^Chunk) -> []byte {
	bytes := serialize_chunk(chunk, context.temp_allocator)
	restored := new(Chunk, context.temp_allocator)
	ok := deserialize_chunk_blocks(bytes, &restored.blocks)
	testing.expect(t, ok)
	testing.expect(t, slice.equal(restored.blocks[:], chunk.blocks[:]))
	return bytes
}

@(test)
test_serialize_all_air_chunk :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	bytes := expect_round_trip(t, chunk)
	// Header, a one entry palette, a run count and a single run.
	testing.expect_value(t, len(bytes), 4 + 2 + 4 + RUN_BYTE_SIZE)
}

@(test)
test_serialize_every_block_different :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	for &block, index in chunk.blocks {
		block = Block_Id(index)
	}
	bytes := expect_round_trip(t, chunk)
	testing.expect_value(t, len(bytes), 4 + 2 * CHUNK_BLOCK_COUNT + 4 + RUN_BYTE_SIZE * CHUNK_BLOCK_COUNT)
}

@(test)
test_serialize_debug_terrain_chunk :: proc(t: ^testing.T) {
	blocks := Debug_Terrain_Blocks{Block_Id(1), Block_Id(2), Block_Id(3), Block_Id(4), Block_Id(5)}
	chunk := new(Chunk, context.temp_allocator)
	chunk.coordinate = {-1, 1, 2}
	fill_debug_terrain_chunk(chunk, blocks)
	bytes := expect_round_trip(t, chunk)
	testing.expect(t, len(bytes) < CHUNK_BLOCK_COUNT)
}

@(test)
test_deserialize_rejects_malformed_input :: proc(t: ^testing.T) {
	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {1, 2, 3}, Block_Id(7))
	bytes := serialize_chunk(chunk, context.temp_allocator)

	restored := new(Chunk, context.temp_allocator)
	ok := deserialize_chunk_blocks(nil, &restored.blocks)
	testing.expect(t, !ok)
	ok = deserialize_chunk_blocks(bytes[:len(bytes) - 1], &restored.blocks)
	testing.expect(t, !ok, "truncated")

	wrong_version := slice.clone(bytes, context.temp_allocator)
	wrong_version[0] = 99
	ok = deserialize_chunk_blocks(wrong_version, &restored.blocks)
	testing.expect(t, !ok, "unknown version")

	// The first run's palette index sits right after the two entry palette
	// and the run count.
	bad_index := slice.clone(bytes, context.temp_allocator)
	bad_index[4 + 2 * 2 + 4] = 2
	ok = deserialize_chunk_blocks(bad_index, &restored.blocks)
	testing.expect(t, !ok, "palette index out of range")

	// Shortening the first run leaves the runs one block short of a chunk.
	short_runs := slice.clone(bytes, context.temp_allocator)
	short_runs[4 + 2 * 2 + 4 + 2] -= 1
	ok = deserialize_chunk_blocks(short_runs, &restored.blocks)
	testing.expect(t, !ok, "runs do not cover the chunk")
}
