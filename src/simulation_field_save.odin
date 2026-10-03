package game

import "core:container/queue"
import "core:slice"

// The field session's save (work item 0179, doc/architecture.md, Save
// format). Two parts:
//
// - The field tables at the end of entities.bin (write_field_tables,
//   after the frame and run tables, which a field world always writes so
//   the reader finds the field after them): the spacing, the simulated
//   chunk set (its radius, margin, chunks and centres), the torches, the
//   light's emitters and its pending queues, and the water a place dropped.
//   The queues are deterministic state and are saved as they stand, never
//   drained early: draining them on the host at save time would leave the
//   peers that did not drain them behind. Being in entities.bin, they are
//   in the state hash (simulation_state_hash).
// - field.bin (encode_field_file): chunks whole, as the field codec writes
//   them (encode_field_chunk): every chunk of the set a tick changed, and
//   the ones that left it with terrain or water unlike their generation
//   (Field_Simulation.saved_chunks, unload_left_field_chunks).
//
// Loading restores the set at the start of the first tick (0185,
// restore_arrived_field_set): the load leaves the world empty and the set
// restoring (Field_Chunk_Set.restoring), the field streaming generates
// the set's chunks on its workers while the frames run, and once every one
// has arrived they enter in coordinate order with their saved bytes laid
// over them and without the arrival's side effects (the water's wake and
// the light's seeding ran on the machine that saved, and their results are
// in the bytes and the queues), so a loaded world and a joining machine
// hold exactly the chunks and the state of the machine that saved.

FIELD_FILE_MAGIC :: "MOBF"

// An emitter of the light (Field_Lighting.sources).
Field_Light_Source_Record :: struct {
	sample: Sample_Coordinate,
	level:  u8,
}

sorted_field_chunk_coordinates :: proc(chunks: map[Field_Chunk_Coordinate]$T) -> []Field_Chunk_Coordinate {
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(chunks), context.temp_allocator)
	for coordinate in chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	return coordinates[:]
}

field_sample_before :: proc(first, second: Sample_Coordinate) -> bool {
	return field_chunk_coordinate_before(Field_Chunk_Coordinate(first), Field_Chunk_Coordinate(second))
}

sorted_field_light_sources :: proc(sources: map[Sample_Coordinate]u8) -> []Field_Light_Source_Record {
	records := make([dynamic]Field_Light_Source_Record, 0, len(sources), context.temp_allocator)
	for sample, level in sources {
		append(&records, Field_Light_Source_Record{sample = sample, level = level})
	}
	slice.sort_by(records[:], proc(first, second: Field_Light_Source_Record) -> bool {
		return field_sample_before(first.sample, second.sample)
	})
	return records[:]
}

field_queue_elements :: proc(source: queue.Queue($T)) -> []T {
	copy := source
	elements := make([]T, queue.len(copy), context.temp_allocator)
	for &element, index in elements {
		element = queue.get(&copy, index)
	}
	return elements
}

write_field_tables :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation) {
	append_u32(bytes, u32(field.spacing_millimetres))
	append_u32(bytes, u32(field.chunk_set.radius))
	append_u32(bytes, u32(field.chunk_set.margin))
	write_list(bytes, sorted_field_chunk_coordinates(field.chunk_set.chunks))
	write_list(bytes, field.chunk_set.centres[:])
	write_list(bytes, field.torches[:])
	lighting := &field.world.light
	write_list(bytes, sorted_field_light_sources(lighting.sources))
	for channel in Field_Light_Channel {
		write_list(bytes, field_queue_elements(lighting.removals[channel]))
		write_list(bytes, field_queue_elements(lighting.additions[channel]))
	}
	write_list(bytes, sorted_field_chunk_coordinates(lighting.arrived_chunks))
	append_u64(bytes, u64(field.world.water_dropped))
}

// Into a field made for the world (enabled, the world empty). False for
// malformed bytes.
read_field_tables :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool {
	spacing := int(read_u32(reader) or_return)
	radius := int(read_u32(reader) or_return)
	margin := int(read_u32(reader) or_return)
	if !sample_spacing_is_valid(spacing) || radius < 1 || radius > MAXIMUM_FIELD_CHUNK_RADIUS || margin < 0 || margin > MAXIMUM_FIELD_CHUNK_MARGIN {
		return false
	}
	field.spacing_millimetres = spacing
	field.chunk_set.radius, field.chunk_set.margin = i32(radius), i32(margin)
	chunks := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	read_list(reader, &chunks) or_return
	clear(&field.chunk_set.chunks)
	for coordinate in chunks {
		field.chunk_set.chunks[coordinate] = {}
	}
	read_list(reader, &field.chunk_set.centres) or_return
	read_list(reader, &field.torches) or_return
	lighting := &field.world.light
	sources := make([dynamic]Field_Light_Source_Record, context.temp_allocator)
	read_list(reader, &sources) or_return
	clear(&lighting.sources)
	for source in sources {
		lighting.sources[source.sample] = source.level
	}
	for channel in Field_Light_Channel {
		removals := make([dynamic]Field_Light_Node, context.temp_allocator)
		read_list(reader, &removals) or_return
		queue.clear(&lighting.removals[channel])
		for node in removals {
			queue.push_back(&lighting.removals[channel], node)
		}
		additions := make([dynamic]Sample_Coordinate, context.temp_allocator)
		read_list(reader, &additions) or_return
		queue.clear(&lighting.additions[channel])
		for sample in additions {
			queue.push_back(&lighting.additions[channel], sample)
		}
	}
	arrived := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	read_list(reader, &arrived) or_return
	clear(&lighting.arrived_chunks)
	for coordinate in arrived {
		lighting.arrived_chunks[coordinate] = {}
	}
	field.world.water_dropped = i64(read_u64(reader) or_return)
	return true
}

// field.bin.

// The header, a u32 count and per chunk its coordinate and its codec
// bytes (as a length and the bytes, append_string), in coordinate order. In the temp allocator.
encode_field_file :: proc(field: ^Field_Simulation, header: Save_Header) -> []byte {
	chunks := make(map[Field_Chunk_Coordinate][]byte, context.temp_allocator)
	for coordinate, saved in field.saved_chunks {
		chunks[coordinate] = saved.bytes
	}
	for coordinate, chunk in field.world.chunks {
		if chunk.modified {
			chunks[coordinate] = encode_field_chunk(chunk, context.temp_allocator)
		}
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	append_save_header(&bytes, FIELD_FILE_MAGIC, header)
	coordinates := sorted_field_chunk_coordinates(chunks)
	append_u32(&bytes, u32(len(coordinates)))
	for coordinate in coordinates {
		for axis in 0 ..< 3 {
			append_u32(&bytes, u32(coordinate[axis]))
		}
		append_string(&bytes, string(chunks[coordinate]))
	}
	return bytes[:]
}

// Into Field_Simulation.saved_chunks, each chunk's bytes copied; the
// chunks are decoded when they enter the world. The problem names what
// was refused.
decode_field_file :: proc(field: ^Field_Simulation, data: []byte, expected: Save_Header) -> string {
	reader := Byte_Reader {
		data = data,
	}
	header, ok := read_save_header(&reader, FIELD_FILE_MAGIC)
	if !ok {
		return "field.bin is not a field file"
	}
	if problem := header_problem(header, expected, "field.bin"); problem != "" {
		return problem
	}
	count, counted := read_u32(&reader)
	if !counted || int(count) > bytes_left(reader) {
		return "field.bin is malformed or truncated"
	}
	for _ in 0 ..< count {
		coordinate: Field_Chunk_Coordinate
		for axis in 0 ..< 3 {
			value, read := read_u32(&reader)
			if !read {
				return "field.bin is malformed or truncated"
			}
			coordinate[axis] = i32(value)
		}
		text, read := read_string(&reader)
		if !read {
			return "field.bin is malformed or truncated"
		}
		saved, problem := decode_saved_field_chunk(transmute([]byte)text, coordinate)
		if problem != "" {
			return problem
		}
		if previous, found := field.saved_chunks[coordinate]; found {
			delete(previous.bytes)
		}
		field.saved_chunks[coordinate] = saved
	}
	if bytes_left(reader) != 0 {
		return "field.bin has bytes after its chunks"
	}
	return ""
}

// A chunk of field.bin: its bytes copied and its hash computed once from
// the decoded chunk, the hash the machine that kept it computed. The
// problem names a chunk that does not decode.
decode_saved_field_chunk :: proc(bytes: []byte, coordinate: Field_Chunk_Coordinate) -> (saved: Field_Saved_Chunk, problem: string) {
	chunk := new(Field_Chunk)
	defer free(chunk)
	if problem = decode_field_chunk_delta(bytes, chunk); problem != "" {
		return {}, problem
	}
	if chunk.coordinate != coordinate {
		return {}, "field.bin: a chunk's bytes name another chunk"
	}
	return Field_Saved_Chunk{bytes = slice.clone(bytes), state_hash = field_chunk_state_hash(chunk)}, ""
}

// The first tick's start in a loaded world: once every chunk of the
// saved set has arrived (or is in the world), each enters in coordinate
// order with its saved bytes (apply_saved_field_chunk) and as it was
// saved (restore_field_chunk), and the set stops restoring. False while
// a chunk is missing, and nothing changes.
restore_arrived_field_set :: proc(field: ^Field_Simulation) -> bool {
	coordinates := sorted_field_chunk_coordinates(field.chunk_set.chunks)
	for coordinate in coordinates {
		if coordinate not_in field.world.chunks && coordinate not_in field.arrived_chunks {
			return false
		}
	}
	for coordinate in coordinates {
		chunk, arrived := field.arrived_chunks[coordinate]
		if !arrived {
			continue
		}
		delete_key(&field.arrived_chunks, coordinate)
		apply_saved_field_chunk(field, chunk)
		restore_field_chunk(&field.world, chunk)
	}
	field.chunk_set.restoring = false
	return true
}

// Into the world as it was saved: no wake and no light seeding, which the
// arrival's insert (field_world_insert_chunk) does; the restored light
// queues (read_field_tables) already hold the saving machine's seeding.
restore_field_chunk :: proc(world: ^Field_World, chunk: ^Field_Chunk) {
	chunk.dirty = true
	world.chunks[chunk.coordinate] = chunk
	if field_sample_bits_any(&chunk.water_awake) {
		world.water_awake_chunks[chunk.coordinate] = {}
	}
}

// The state hash.

// The terrain and the water of a chunk: density, material, fill, still
// ticks, the awake and the source bits; not the tint, the light or the
// flow. Kept on the chunk until a write of the tick
// (note_field_chunk_change) makes it stale.
field_chunk_state_hash :: proc(chunk: ^Field_Chunk) -> u64 {
	if chunk.hash_current {
		return chunk.state_hash
	}
	result := fingerprint_u64(FINGERPRINT_START, u64(u32(chunk.coordinate.x)) | u64(u32(chunk.coordinate.z)) << 32)
	result = fingerprint_u64(result, u64(u32(chunk.coordinate.y)))
	result = fingerprint_bytes(result, transmute([]byte)chunk.density[:])
	result = fingerprint_bytes(result, transmute([]byte)chunk.material[:])
	result = fingerprint_bytes(result, chunk.water[:])
	result = fingerprint_bytes(result, chunk.water_still[:])
	result = fingerprint_bytes(result, slice.to_bytes(chunk.water_awake[:]))
	result = fingerprint_bytes(result, slice.to_bytes(chunk.water_source[:]))
	chunk.state_hash, chunk.hash_current = result, true
	return result
}

// The loaded field chunks in coordinate order (the set), and the hashes
// the kept chunks outside it took when they were kept.
field_state_hash :: proc(field: ^Field_Simulation, start: u64) -> u64 {
	result := start
	for coordinate in sorted_field_chunk_coordinates(field.world.chunks) {
		result = fingerprint_u64(result, field_chunk_state_hash(field.world.chunks[coordinate]))
	}
	for coordinate in sorted_field_chunk_coordinates(field.saved_chunks) {
		if coordinate not_in field.world.chunks {
			result = fingerprint_u64(result, field.saved_chunks[coordinate].state_hash)
		}
	}
	return result
}
