package game

import "core:fmt"
import "core:slice"
import "run_length"

// Field chunk delta bytes (work item 0168), all integers little endian:
//   u16 version, i32 chunk x, y, z,
//   then for the densities, the materials and the tints in that order:
//   u32 run count, run count times (u8 value, u32 count).
// A chunk equal to its generation writes nothing and regenerates from the
// seed; a changed chunk is written whole. The version follows the block
// chunk's CHUNK_FORMAT_VERSION (1), so block chunk bytes are refused by
// name.

FIELD_CHUNK_FORMAT_VERSION :: 2
FIELD_RUN_BYTE_SIZE :: 5

field_chunk_equals :: proc(first, second: ^Field_Chunk) -> bool {
	return slice.equal(first.density[:], second.density[:]) && slice.equal(first.material[:], second.material[:]) && slice.equal(first.tint[:], second.tint[:])
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
	bytes := make([dynamic]byte, allocator)
	append_u16(&bytes, FIELD_CHUNK_FORMAT_VERSION)
	for axis in 0 ..< 3 {
		append_i32(&bytes, chunk.coordinate[axis])
	}
	append_field_plane(&bytes, transmute([]u8)chunk.density[:])
	append_field_plane(&bytes, transmute([]u8)chunk.material[:])
	append_field_plane(&bytes, chunk.tint[:])
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

// Fills chunk only when the bytes are whole and of this version; the
// problem names what was refused.
decode_field_chunk_delta :: proc(data: []byte, chunk: ^Field_Chunk) -> (problem: string) {
	reader := Byte_Reader {
		data = data,
	}
	version, has_version := read_u16(&reader)
	if !has_version {
		return "field chunk: no version"
	}
	if version != FIELD_CHUNK_FORMAT_VERSION {
		return fmt.tprintf("field chunk: format version %d is not %d, which this build reads", version, FIELD_CHUNK_FORMAT_VERSION)
	}
	decoded := new(Field_Chunk, context.temp_allocator)
	for axis in 0 ..< 3 {
		value, ok := read_u32(&reader)
		if !ok {
			return "field chunk: the coordinate is cut off"
		}
		decoded.coordinate[axis] = i32(value)
	}
	planes := [3][]u8{transmute([]u8)decoded.density[:], transmute([]u8)decoded.material[:], decoded.tint[:]}
	for plane in planes {
		if !read_field_plane(&reader, plane) {
			return "field chunk: malformed sample runs"
		}
	}
	if reader.offset != len(data) {
		return "field chunk: bytes after the tints"
	}
	for material in decoded.material {
		if material > max(Field_Material) {
			return fmt.tprintf("field chunk: unknown material %d", u8(material))
		}
	}
	chunk^ = decoded^
	chunk.dirty = true
	return ""
}
