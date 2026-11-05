package game

import "core:container/queue"
import "core:slice"
import "platform"

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
// - The water bodies' table (0293, write_water_body_table), after the
//   arrival table: the bodies by id with their curves, and the pending
//   flood with its heap and its pushed samples as they stand, so a loaded
//   machine finishes it on the same tick as the one that saved.
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

// The water bodies (0293).

Water_Body_Record :: struct {
	id:                             u16,
	alive, sea, dirty, spill_to_sea: bool,
	volume, level, written_level:   i64,
	spill_level, spill_volume:      i64,
	flood_visits, base:             i64,
	seed, spill:                    Sample_Coordinate,
}

// A nonzero band of a body's curve: its loaded bands, or a frozen part's
// (the chunk and the owner its samples carry there).
Water_Body_Band_Record :: struct {
	body:          u16,
	frozen:        bool,
	chunk:         Field_Chunk_Coordinate,
	owner:         u16,
	band:          i32,
	opens, closes: i64,
}

Water_Flood_Record :: struct {
	active, seeding, redirty: bool,
	body:                     u16,
	rise_samples:             i32,
	sill, rise_limit:         i64,
}

Water_Flood_Pushed_Record :: struct {
	chunk: Field_Chunk_Coordinate,
	bits:  Field_Sample_Bits,
}

// The least bytes a record's body takes in a list (each field at its size;
// a nested struct takes more, with its length and schema).
WATER_BODY_RECORD_BYTES :: 2 + 4 + 7 * 8 + 2 * 12
WATER_BODY_BAND_RECORD_BYTES :: 2 + 1 + 12 + 2 + 4 + 2 * 8
WATER_FLOOD_RECORD_BYTES :: 3 + 2 + 4 + 2 * 8
WATER_FLOOD_ENTRY_BYTES :: 8 + 12
WATER_FLOOD_PUSHED_RECORD_BYTES :: 12 + FIELD_SAMPLE_BIT_BYTES

// The list's count, read without moving the reader, fits the bytes left
// at element_bytes a record, so a count cannot make read_list allocate
// more than the file could hold.
list_count_fits :: proc(reader: ^Byte_Reader, element_bytes: int) -> bool {
	saved := reader.offset
	count, ok := read_u32(reader)
	reader.offset = saved
	return ok && int(count) <= bytes_left(reader^) / element_bytes
}

append_water_body_bands :: proc(records: ^[dynamic]Water_Body_Band_Record, id: int, frozen: bool, chunk: Field_Chunk_Coordinate, owner: Water_Owner, bands: []Water_Body_Band) {
	for band, index in bands {
		if band != {} {
			append(records, Water_Body_Band_Record{body = u16(id), frozen = frozen, chunk = chunk, owner = owner, band = i32(index), opens = band.opens, closes = band.closes})
		}
	}
}

// In a field world, after the arrival table (write_simulation_state): the
// sea's discarded inflow, the bodies in id order (dead slots too, so the
// ids keep their meaning), every nonzero band (bodies in id order, the
// loaded bands then the frozen parts in order, bands rising), then the
// pending flood, its heap as it stands and its pushed samples by chunk.
// The chunk lists are derived (rebuild_water_body_chunks).
write_water_body_table :: proc(bytes: ^[dynamic]byte, world: ^Field_World) {
	append_u64(bytes, u64(world.water_to_sea))
	bodies := make([dynamic]Water_Body_Record, 0, len(world.water_bodies), context.temp_allocator)
	bands := make([dynamic]Water_Body_Band_Record, context.temp_allocator)
	for &body, id in world.water_bodies {
		append(&bodies, Water_Body_Record{id = u16(id), alive = body.alive, sea = body.sea, dirty = body.dirty, spill_to_sea = body.spill_to_sea, volume = body.volume, level = body.level, written_level = body.written_level, spill_level = body.spill_level, spill_volume = body.spill_volume, flood_visits = body.flood_visits, base = body.base, seed = body.seed, spill = body.spill})
		append_water_body_bands(&bands, id, false, {}, 0, body.loaded[:])
		for part in body.frozen {
			append_water_body_bands(&bands, id, true, part.chunk, part.owner, part.bands[:])
		}
	}
	write_list(bytes, bodies[:])
	write_list(bytes, bands[:])
	flood := &world.water_flood
	record := Water_Flood_Record{active = flood.active, seeding = flood.seeding, redirty = flood.redirty, body = u16(flood.body), rise_samples = flood.rise_samples, sill = flood.sill, rise_limit = flood.rise_limit}
	write_list(bytes, []Water_Flood_Record{record})
	write_list(bytes, flood.heap[:])
	pushed := make([dynamic]Water_Flood_Pushed_Record, 0, len(flood.pushed), context.temp_allocator)
	for coordinate in sorted_field_chunk_coordinates(flood.pushed) {
		append(&pushed, Water_Flood_Pushed_Record{chunk = coordinate, bits = flood.pushed[coordinate]^})
	}
	write_list(bytes, pushed[:])
}

// Into the world's (empty) table. A save from before 0293 ends before the
// table and loads with no bodies and one log line; under bodies the sea is
// added and the water settles into bodies over the first ticks. False for
// malformed records: a list count beyond the bytes left, ids out of order
// or past the owner plane's reach, a sea that is not body 0 or not alone,
// a base off the bands or a base or level outside the far limit, a band
// naming a dead or unknown body or past MAXIMUM_WATER_BODY_BAND, a frozen
// band whose owner names no listed body, more band entries in all than
// MAXIMUM_WATER_BODY_BAND_ENTRIES, a flood naming a body that is not alive
// and dirty.
read_water_body_table :: proc(reader: ^Byte_Reader, world: ^Field_World) -> bool {
	if bytes_left(reader^) == 0 {
		platform.log_printf("save: written before the water bodies (0293), the water settles into bodies over the first ticks")
		return true
	}
	world.water_to_sea = i64(read_u64(reader) or_return)
	// Each count is checked against the bytes left at its record's encoded
	// size before read_list allocates the records.
	bodies := make([dynamic]Water_Body_Record, context.temp_allocator)
	list_count_fits(reader, WATER_BODY_RECORD_BYTES) or_return
	read_list(reader, &bodies) or_return
	bands := make([dynamic]Water_Body_Band_Record, context.temp_allocator)
	list_count_fits(reader, WATER_BODY_BAND_RECORD_BYTES) or_return
	read_list(reader, &bands) or_return
	floods := make([dynamic]Water_Flood_Record, context.temp_allocator)
	list_count_fits(reader, WATER_FLOOD_RECORD_BYTES) or_return
	read_list(reader, &floods) or_return
	heap := make([dynamic]Water_Flood_Entry, context.temp_allocator)
	list_count_fits(reader, WATER_FLOOD_ENTRY_BYTES) or_return
	read_list(reader, &heap) or_return
	pushed := make([dynamic]Water_Flood_Pushed_Record, context.temp_allocator)
	list_count_fits(reader, WATER_FLOOD_PUSHED_RECORD_BYTES) or_return
	read_list(reader, &pushed) or_return
	if len(bodies) > MAXIMUM_WATER_BODIES || len(floods) != 1 {
		return false
	}
	in_range :: proc(value: i64) -> bool {
		return value >= 0 && value <= MAXIMUM_WATER_BODY_LEVEL
	}
	for record, id in bodies {
		if int(record.id) != id || record.sea != (id == 0) || (id == 0 && !record.alive) {
			return false
		}
		if record.base %% WATER_BODY_BAND != 0 || !in_range(record.base) || !in_range(record.level) || !in_range(record.written_level) {
			return false
		}
	}
	// The arrays the band records make: their lengths in all are bounded
	// before anything is allocated.
	Band_Array :: struct {
		body:   u16,
		frozen: bool,
		chunk:  Field_Chunk_Coordinate,
		owner:  u16,
	}
	lengths := make(map[Band_Array]int, context.temp_allocator)
	for band in bands {
		if int(band.body) >= len(bodies) || !bodies[band.body].alive || band.band < 0 || band.band >= MAXIMUM_WATER_BODY_BAND {
			return false
		}
		if band.frozen && (band.owner < u16(WATER_OWNER_SEA) + 1 || Water_Owner(band.owner) == WATER_OWNER_RELEASED || int(band.owner) - 1 >= len(bodies)) {
			return false
		}
		key := Band_Array{band.body, band.frozen, band.frozen ? band.chunk : {}, band.frozen ? band.owner : 0}
		lengths[key] = max(lengths[key] or_else 0, int(band.band) + 1)
	}
	entries := 0
	for _, length in lengths {
		entries += length
	}
	if entries > MAXIMUM_WATER_BODY_BAND_ENTRIES {
		return false
	}
	flood := floods[0]
	if flood.active && (int(flood.body) >= len(bodies) || flood.body == 0 || !bodies[flood.body].alive || !bodies[flood.body].dirty || len(heap) == 0) {
		return false
	}
	destroy_water_bodies(world)
	world.water_bodies = {}
	world.water_flood = {}
	world.water_sea_seeds = {}
	for record in bodies {
		append(&world.water_bodies, Water_Body{alive = record.alive, sea = record.sea, dirty = record.dirty, spill_to_sea = record.spill_to_sea, volume = record.volume, level = record.level, written_level = record.written_level, spill_level = record.spill_level, spill_volume = record.spill_volume, flood_visits = record.flood_visits, base = record.base, seed = record.seed, spill = record.spill})
	}
	for band in bands {
		body := &world.water_bodies[band.body]
		target := &body.loaded
		if band.frozen {
			part_index := -1
			for part, index in body.frozen {
				if part.chunk == band.chunk && part.owner == Water_Owner(band.owner) {
					part_index = index
				}
			}
			if part_index < 0 {
				append(&body.frozen, Water_Body_Frozen{chunk = band.chunk, owner = Water_Owner(band.owner)})
				part_index = len(body.frozen) - 1
			}
			target = &body.frozen[part_index].bands
		}
		if len(target) <= int(band.band) {
			resize(target, int(band.band) + 1)
		}
		target[band.band] = {opens = band.opens, closes = band.closes}
	}
	for &body in world.water_bodies {
		sort_water_body_frozen(&body)
	}
	if flood.active {
		target := &world.water_flood
		target.active, target.seeding, target.redirty = true, flood.seeding, flood.redirty
		target.body, target.rise_samples, target.sill, target.rise_limit = Water_Body_Id(flood.body), flood.rise_samples, flood.sill, flood.rise_limit
		append(&target.heap, ..heap[:])
		for record in pushed {
			bits := new(Field_Sample_Bits)
			bits^ = record.bits
			target.pushed[record.chunk] = bits
		}
	}
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
		old_owner_plane := apply_saved_field_chunk(field, chunk)
		restore_field_chunk(&field.world, chunk)
		if old_owner_plane && field.world.water_model == .Bodies {
			// Saved before the water bodies (0293): its sea is claimed and
			// its water settles into bodies over the first ticks.
			seed_water_sea_facing(&field.world, chunk)
			wake_old_field_chunk_water(&field.world, chunk)
		}
	}
	// The bodies' chunk lists are derived from the restored planes (0293).
	rebuild_water_body_chunks(&field.world)
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
// ticks, the awake and the source bits, the water owners (0293) and the
// pressure pull's failed bits (0292, hashed since 0293); not the tint,
// the light or the flow. Kept on the chunk until a write of the tick
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
	result = fingerprint_bytes(result, slice.to_bytes(chunk.water_owner[:]))
	result = fingerprint_bytes(result, slice.to_bytes(chunk.water_pressure_failed[:]))
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
