package game

// Chunk byte format, all integers little endian:
//   u16 version, u16 palette length,
//   palette length times u16 block id (in order of first appearance),
//   u32 run count, run count times (u16 palette index, u32 count).
// The runs come from the run length codec over palette indices. Light and
// the chunk coordinate are not stored: light is recomputed (work item 0008)
// and the coordinate is the key of the container the bytes are stored in.

CHUNK_FORMAT_VERSION :: 1
RUN_BYTE_SIZE :: 6

Byte_Reader :: struct {
	data:   []byte,
	offset: int,
}

append_u16 :: proc(bytes: ^[dynamic]byte, value: u16) {
	append(bytes, byte(value), byte(value >> 8))
}

append_u32 :: proc(bytes: ^[dynamic]byte, value: u32) {
	append(bytes, byte(value), byte(value >> 8), byte(value >> 16), byte(value >> 24))
}

read_u16 :: proc(reader: ^Byte_Reader) -> (value: u16, ok: bool) {
	if reader.offset + 2 > len(reader.data) {
		return 0, false
	}
	bytes := reader.data[reader.offset:]
	reader.offset += 2
	return u16(bytes[0]) | u16(bytes[1]) << 8, true
}

read_u32 :: proc(reader: ^Byte_Reader) -> (value: u32, ok: bool) {
	low := read_u16(reader) or_return
	high := read_u16(reader) or_return
	return u32(low) | u32(high) << 16, true
}

// Palette of distinct block ids in first appearance order, and each
// block's index into it.
build_palette :: proc(chunk: ^Chunk, allocator := context.allocator) -> (palette: [dynamic]Block_Id, indices: []u16) {
	palette = make([dynamic]Block_Id, allocator)
	indices = make([]u16, CHUNK_BLOCK_COUNT, allocator)
	lookup := make(map[Block_Id]u16, context.temp_allocator)
	for block, index in chunk.blocks {
		palette_index, found := lookup[block]
		if !found {
			palette_index = u16(len(palette))
			lookup[block] = palette_index
			append(&palette, block)
		}
		indices[index] = palette_index
	}
	return palette, indices
}

serialize_chunk :: proc(chunk: ^Chunk, allocator := context.allocator) -> []byte {
	palette, indices := build_palette(chunk, context.temp_allocator)
	runs := run_length_encode(indices, context.temp_allocator)
	bytes := make([dynamic]byte, 0, 8 + 2 * len(palette) + RUN_BYTE_SIZE * len(runs), allocator)
	append_u16(&bytes, CHUNK_FORMAT_VERSION)
	append_u16(&bytes, u16(len(palette)))
	for block in palette {
		append_u16(&bytes, u16(block))
	}
	append_u32(&bytes, u32(len(runs)))
	for run in runs {
		append_u16(&bytes, run.value)
		append_u32(&bytes, run.count)
	}
	return bytes[:]
}

read_palette :: proc(reader: ^Byte_Reader, allocator := context.allocator) -> (palette: []Block_Id, ok: bool) {
	version := read_u16(reader) or_return
	length := read_u16(reader) or_return
	if version != CHUNK_FORMAT_VERSION || length == 0 || reader.offset + 2 * int(length) > len(reader.data) {
		return nil, false
	}
	palette = make([]Block_Id, length, allocator)
	for &block in palette {
		block = Block_Id(read_u16(reader) or_return)
	}
	return palette, true
}

// Validates the run count against the remaining bytes before allocating.
read_runs :: proc(reader: ^Byte_Reader, palette_length: int, allocator := context.allocator) -> (runs: []Run, ok: bool) {
	count := read_u32(reader) or_return
	if int(count) * RUN_BYTE_SIZE != len(reader.data) - reader.offset {
		return nil, false
	}
	runs = make([]Run, count, allocator)
	for &run in runs {
		run.value = read_u16(reader) or_return
		run.count = read_u32(reader) or_return
		if int(run.value) >= palette_length {
			return nil, false
		}
	}
	return runs, true
}

deserialize_chunk :: proc(data: []byte) -> (chunk: Chunk, ok: bool) {
	reader := Byte_Reader {
		data = data,
	}
	palette := read_palette(&reader, context.temp_allocator) or_return
	runs := read_runs(&reader, len(palette), context.temp_allocator) or_return
	if run_length_decoded_length(runs) != CHUNK_BLOCK_COUNT {
		return {}, false
	}
	indices := run_length_decode(runs, context.temp_allocator)
	for palette_index, index in indices {
		chunk.blocks[index] = palette[palette_index]
	}
	return chunk, true
}
