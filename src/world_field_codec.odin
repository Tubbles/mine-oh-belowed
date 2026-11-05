package game

import "core:fmt"
import "core:slice"
import "run_length"

// Field chunk delta bytes (work item 0168), all integers little endian:
//   u16 version, i32 chunk x, y, z,
//   then for each plane in this order: the densities, the materials, the
//   tints, the water fills, the water's still ticks (0172), the awake bits
//   and the source bits (each as FIELD_SAMPLE_BIT_BYTES bytes, the words
//   little endian), the water owners' low bytes and high bytes (0293,
//   Field_Chunk.water_owner), the pressure pull's failed bits (0292, as
//   the other bits), the block light and the sky light (0173):
//   u32 run count, run count times (u8 value, u32 count).
// A chunk equal to its generation writes nothing and regenerates from the
// seed; a changed chunk is written whole. The water's flow is measured
// again each tick and not written. Version 4 (before 0293) had no owner
// and no failed planes and is still read: both read zero, and the caller
// learns it (decode_field_chunk), since under the bodies model such a
// chunk's water settles into bodies again (insert_field_chunk_arrival).
// The version follows the block chunk's CHUNK_FORMAT_VERSION (1), so block
// chunk bytes are refused by name; version 2 had no water and 3 no light,
// and both are refused too, since the field was not saved then.
//
// The light is saved, not rebuilt on load as the block light is: the sky
// of an edited chunk depends on edits in the chunks above it along the
// radial, which need not be loaded when it loads (the march reads the
// generation beyond the loaded chunks), so it cannot be derived from the
// chunk and its neighbours; and a lockstep joiner then holds the host's
// bytes without relighting over ticks the host has already run. An
// emitter in a neighbour chunk still lights the chunk again when that
// neighbour arrives (seed_field_chunk_light).

FIELD_CHUNK_FORMAT_VERSION :: 5
// The version before the owner and failed planes (0293), still read.
FIELD_CHUNK_FORMAT_VERSION_WITHOUT_OWNERS :: 4
FIELD_RUN_BYTE_SIZE :: 5
FIELD_SAMPLE_BIT_BYTES :: FIELD_CHUNK_SAMPLE_COUNT / 8
FIELD_CHUNK_PLANE_COUNT :: 12
FIELD_CHUNK_PLANE_COUNT_WITHOUT_OWNERS :: 9

// The terrain and the water alike: what a tick changes and generation
// makes. The light is left out, since an arrival seeds it and the
// generation leaves it dark (0179, unload_left_field_chunks).
field_chunk_terrain_and_water_equal :: proc(first, second: ^Field_Chunk) -> bool {
	return(
		slice.equal(first.density[:], second.density[:]) &&
		slice.equal(first.material[:], second.material[:]) &&
		slice.equal(first.tint[:], second.tint[:]) &&
		slice.equal(first.water[:], second.water[:]) &&
		slice.equal(first.water_still[:], second.water_still[:]) &&
		first.water_awake == second.water_awake &&
		first.water_source == second.water_source &&
		slice.equal(first.water_owner[:], second.water_owner[:]) &&
		first.water_pressure_failed == second.water_pressure_failed \
	)
}

field_chunk_equals :: proc(first, second: ^Field_Chunk) -> bool {
	return(
		field_chunk_terrain_and_water_equal(first, second) &&
		slice.equal(first.block_light[:], second.block_light[:]) &&
		slice.equal(first.sky_light[:], second.sky_light[:]) \
	)
}

field_sample_bits_to_bytes :: proc(bits: Field_Sample_Bits) -> []u8 {
	bytes := make([]u8, FIELD_SAMPLE_BIT_BYTES, context.temp_allocator)
	for word, word_index in bits {
		for byte_index in 0 ..< 8 {
			bytes[word_index * 8 + byte_index] = u8(word >> uint(8 * byte_index))
		}
	}
	return bytes
}

field_sample_bits_from_bytes :: proc(bytes: []u8) -> Field_Sample_Bits {
	bits: Field_Sample_Bits
	for value, index in bytes {
		bits[index / 8] |= u64(value) << uint(8 * (index % 8))
	}
	return bits
}

append_i32 :: proc(bytes: ^[dynamic]byte, value: i32) {
	append_u32(bytes, u32(value))
}

append_field_plane :: proc(bytes: ^[dynamic]byte, plane: []u8) {
	values := make([]u16, len(plane), context.temp_allocator)
	for value, index in plane {
		values[index] = u16(value)
	}
	runs := run_length.run_length_encode(values, context.temp_allocator)
	append_u32(bytes, u32(len(runs)))
	for run in runs {
		append(bytes, byte(run.value))
		append_u32(bytes, run.count)
	}
}

// Nil when the chunk equals generated, the same chunk freshly generated.
encode_field_chunk_delta :: proc(chunk, generated: ^Field_Chunk, allocator := context.allocator) -> []byte {
	if field_chunk_equals(chunk, generated) {
		return nil
	}
	return encode_field_chunk(chunk, allocator)
}

// The chunk whole. The session's save (0179) writes every chunk a tick
// changed (Field_Chunk.modified) this way, without generating the chunk
// again to compare.
encode_field_chunk :: proc(chunk: ^Field_Chunk, allocator := context.allocator) -> []byte {
	bytes := make([dynamic]byte, allocator)
	append_u16(&bytes, FIELD_CHUNK_FORMAT_VERSION)
	for axis in 0 ..< 3 {
		append_i32(&bytes, chunk.coordinate[axis])
	}
	planes := [FIELD_CHUNK_PLANE_COUNT][]u8 {
		transmute([]u8)chunk.density[:],
		transmute([]u8)chunk.material[:],
		chunk.tint[:],
		chunk.water[:],
		chunk.water_still[:],
		field_sample_bits_to_bytes(chunk.water_awake),
		field_sample_bits_to_bytes(chunk.water_source),
		water_owner_plane_bytes(chunk, 0),
		water_owner_plane_bytes(chunk, 1),
		field_sample_bits_to_bytes(chunk.water_pressure_failed),
		chunk.block_light[:],
		chunk.sky_light[:],
	}
	for plane in planes {
		append_field_plane(&bytes, plane)
	}
	return bytes[:]
}

// Validates the run count against the remaining bytes before reading and
// the decoded length against the plane before writing.
read_field_plane :: proc(reader: ^Byte_Reader, plane: []u8) -> bool {
	count := read_u32(reader) or_return
	if int(count) > (len(reader.data) - reader.offset) / FIELD_RUN_BYTE_SIZE {
		return false
	}
	offset := 0
	for _ in 0 ..< count {
		value := reader.data[reader.offset]
		reader.offset += 1
		length := int(read_u32(reader) or_return)
		if length > len(plane) - offset {
			return false
		}
		slice.fill(plane[offset:offset + length], value)
		offset += length
	}
	return offset == len(plane)
}

// The owners' low (part 0) or high (part 1) bytes as a plane.
water_owner_plane_bytes :: proc(chunk: ^Field_Chunk, part: uint) -> []u8 {
	bytes := make([]u8, FIELD_CHUNK_SAMPLE_COUNT, context.temp_allocator)
	for owner, index in chunk.water_owner {
		bytes[index] = u8(owner >> (8 * part))
	}
	return bytes
}

// Fills chunk only when the bytes are whole and of this version; the
// problem names what was refused.
decode_field_chunk_delta :: proc(data: []byte, chunk: ^Field_Chunk) -> (problem: string) {
	problem, _ = decode_field_chunk(data, chunk)
	return problem
}

// As decode_field_chunk_delta; old_owner_plane is true for version 4
// bytes, whose owner and failed planes read zero.
decode_field_chunk :: proc(data: []byte, chunk: ^Field_Chunk) -> (problem: string, old_owner_plane: bool) {
	reader := Byte_Reader {
		data = data,
	}
	version, has_version := read_u16(&reader)
	if !has_version {
		return "field chunk: no version", false
	}
	if version != FIELD_CHUNK_FORMAT_VERSION && version != FIELD_CHUNK_FORMAT_VERSION_WITHOUT_OWNERS {
		return fmt.tprintf("field chunk: format version %d is not %d, which this build reads", version, FIELD_CHUNK_FORMAT_VERSION), false
	}
	old_owner_plane = version == FIELD_CHUNK_FORMAT_VERSION_WITHOUT_OWNERS
	decoded := new(Field_Chunk, context.temp_allocator)
	for axis in 0 ..< 3 {
		value, ok := read_u32(&reader)
		if !ok {
			return "field chunk: the coordinate is cut off", false
		}
		decoded.coordinate[axis] = i32(value)
	}
	awake := make([]u8, FIELD_SAMPLE_BIT_BYTES, context.temp_allocator)
	source := make([]u8, FIELD_SAMPLE_BIT_BYTES, context.temp_allocator)
	failed := make([]u8, FIELD_SAMPLE_BIT_BYTES, context.temp_allocator)
	owner_low := make([]u8, FIELD_CHUNK_SAMPLE_COUNT, context.temp_allocator)
	owner_high := make([]u8, FIELD_CHUNK_SAMPLE_COUNT, context.temp_allocator)
	planes := [FIELD_CHUNK_PLANE_COUNT][]u8{transmute([]u8)decoded.density[:], transmute([]u8)decoded.material[:], decoded.tint[:], decoded.water[:], decoded.water_still[:], awake, source, owner_low, owner_high, failed, decoded.block_light[:], decoded.sky_light[:]}
	old_planes := [FIELD_CHUNK_PLANE_COUNT_WITHOUT_OWNERS][]u8{transmute([]u8)decoded.density[:], transmute([]u8)decoded.material[:], decoded.tint[:], decoded.water[:], decoded.water_still[:], awake, source, decoded.block_light[:], decoded.sky_light[:]}
	for plane in (old_owner_plane ? old_planes[:] : planes[:]) {
		if !read_field_plane(&reader, plane) {
			return "field chunk: malformed sample runs", false
		}
	}
	if reader.offset != len(data) {
		return "field chunk: bytes after the sky light", false
	}
	for fill in decoded.water {
		if fill > FIELD_WATER_FULL {
			return fmt.tprintf("field chunk: water fill %d is above %d", fill, FIELD_WATER_FULL), false
		}
	}
	// Ground holds no light; a malformed chunk's light there is dropped,
	// so it cannot spread from inside the ground.
	for density, index in decoded.density {
		if density > 0 {
			decoded.block_light[index], decoded.sky_light[index] = 0, 0
		}
	}
	decoded.water_awake = field_sample_bits_from_bytes(awake)
	decoded.water_source = field_sample_bits_from_bytes(source)
	decoded.water_pressure_failed = field_sample_bits_from_bytes(failed)
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		decoded.water_owner[index] = Water_Owner(owner_low[index]) | Water_Owner(owner_high[index]) << 8
	}
	for material in decoded.material {
		if material > max(Field_Material) {
			return fmt.tprintf("field chunk: unknown material %d", u8(material)), false
		}
	}
	// The crater overlay is the generation's, not the save's (0271).
	decoded.crater_overlay = chunk.crater_overlay
	chunk^ = decoded^
	chunk.dirty = true
	return "", old_owner_plane
}
