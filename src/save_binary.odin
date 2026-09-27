package game

import "base:runtime"
import "core:fmt"
import "core:hash"

// The plain value codec of the save files. Values are written field by
// field from their type information: integers, enums, bit sets and floats
// as little endian bytes of their size, booleans as one byte, arrays and
// structs element by element and field by field, slices as a u32 length
// and their elements. Nothing is copied as raw memory, so padding, pointers
// and the host byte order never reach a file. Dynamic arrays, maps,
// strings and pointers are refused: the callers write those explicitly
// (write_list, append_string).
//
// A layout fingerprint over the same type information goes into the file
// header, so a build whose saved structs changed refuses the file instead
// of reading fields into the wrong places.

append_u8 :: proc(bytes: ^[dynamic]byte, value: u8) {
	append(bytes, value)
}

append_u64 :: proc(bytes: ^[dynamic]byte, value: u64) {
	append_u32(bytes, u32(value))
	append_u32(bytes, u32(value >> 32))
}

append_string :: proc(bytes: ^[dynamic]byte, value: string) {
	append_u32(bytes, u32(len(value)))
	append(bytes, ..transmute([]byte)value)
}

read_u8 :: proc(reader: ^Byte_Reader) -> (value: u8, ok: bool) {
	if reader.offset >= len(reader.data) {
		return 0, false
	}
	reader.offset += 1
	return reader.data[reader.offset - 1], true
}

read_u64 :: proc(reader: ^Byte_Reader) -> (value: u64, ok: bool) {
	low := read_u32(reader) or_return
	high := read_u32(reader) or_return
	return u64(low) | u64(high) << 32, true
}

// A view into the reader's data.
read_string :: proc(reader: ^Byte_Reader) -> (value: string, ok: bool) {
	length := int(read_u32(reader) or_return)
	if length > len(reader.data) - reader.offset {
		return "", false
	}
	reader.offset += length
	return string(reader.data[reader.offset - length:reader.offset]), true
}

bytes_left :: proc(reader: Byte_Reader) -> int {
	return len(reader.data) - reader.offset
}

// The value of an integer like field of 1, 2, 4 or 8 bytes.
load_unsigned :: proc(pointer: rawptr, size: int) -> u64 {
	switch size {
	case 1:
		return u64((^u8)(pointer)^)
	case 2:
		return u64((^u16)(pointer)^)
	case 4:
		return u64((^u32)(pointer)^)
	case 8:
		return (^u64)(pointer)^
	}
	panic("save: unsupported integer size")
}

store_unsigned :: proc(pointer: rawptr, size: int, value: u64) {
	switch size {
	case 1:
		(^u8)(pointer)^ = u8(value)
	case 2:
		(^u16)(pointer)^ = u16(value)
	case 4:
		(^u32)(pointer)^ = u32(value)
	case 8:
		(^u64)(pointer)^ = value
	case:
		panic("save: unsupported integer size")
	}
}

append_unsigned :: proc(bytes: ^[dynamic]byte, value: u64, size: int) {
	for index in 0 ..< size {
		append(bytes, byte(value >> (8 * uint(index))))
	}
}

read_unsigned :: proc(reader: ^Byte_Reader, size: int) -> (value: u64, ok: bool) {
	if size > bytes_left(reader^) {
		return 0, false
	}
	for index in 0 ..< size {
		value |= u64(reader.data[reader.offset + index]) << (8 * uint(index))
	}
	reader.offset += size
	return value, true
}

write_value :: proc(bytes: ^[dynamic]byte, pointer: rawptr, info: ^runtime.Type_Info) {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		write_value(bytes, pointer, variant.base)
	case runtime.Type_Info_Integer, runtime.Type_Info_Float, runtime.Type_Info_Enum, runtime.Type_Info_Bit_Set:
		append_unsigned(bytes, load_unsigned(pointer, info.size), info.size)
	case runtime.Type_Info_Boolean:
		append_u8(bytes, (^bool)(pointer)^ ? 1 : 0)
	case runtime.Type_Info_Array:
		write_elements(bytes, pointer, variant.elem, variant.elem_size, variant.count)
	case runtime.Type_Info_Enumerated_Array:
		write_elements(bytes, pointer, variant.elem, variant.elem_size, variant.count)
	case runtime.Type_Info_Struct:
		assert(.raw_union not_in variant.flags, "save: unions cannot be written")
		for field in 0 ..< int(variant.field_count) {
			write_value(bytes, rawptr(uintptr(pointer) + variant.offsets[field]), variant.types[field])
		}
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(pointer)
		append_u32(bytes, u32(raw.len))
		write_elements(bytes, raw.data, variant.elem, variant.elem_size, raw.len)
	case:
		panic(fmt.tprintf("save: values of type %v cannot be written", info.id))
	}
}

write_elements :: proc(bytes: ^[dynamic]byte, pointer: rawptr, elem: ^runtime.Type_Info, elem_size, count: int) {
	for index in 0 ..< count {
		write_value(bytes, rawptr(uintptr(pointer) + uintptr(index * elem_size)), elem)
	}
}

// Slices are read into the slice already there, whose length must match:
// their lengths follow from the game data (inventory slots, per item
// counters), which the content fingerprint pins.
read_value :: proc(reader: ^Byte_Reader, pointer: rawptr, info: ^runtime.Type_Info) -> bool {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		return read_value(reader, pointer, variant.base)
	case runtime.Type_Info_Integer, runtime.Type_Info_Float, runtime.Type_Info_Bit_Set:
		store_unsigned(pointer, info.size, read_unsigned(reader, info.size) or_return)
		return true
	case runtime.Type_Info_Enum:
		value := read_unsigned(reader, info.size) or_return
		if !enum_value_is_named(variant, value, info.size) {
			return false
		}
		store_unsigned(pointer, info.size, value)
		return true
	case runtime.Type_Info_Boolean:
		value := read_u8(reader) or_return
		if value > 1 {
			return false
		}
		(^bool)(pointer)^ = value == 1
		return true
	case runtime.Type_Info_Array:
		return read_elements(reader, pointer, variant.elem, variant.elem_size, variant.count)
	case runtime.Type_Info_Enumerated_Array:
		return read_elements(reader, pointer, variant.elem, variant.elem_size, variant.count)
	case runtime.Type_Info_Struct:
		for field in 0 ..< int(variant.field_count) {
			read_value(reader, rawptr(uintptr(pointer) + variant.offsets[field]), variant.types[field]) or_return
		}
		return true
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(pointer)
		length := read_u32(reader) or_return
		if int(length) != raw.len {
			return false
		}
		return read_elements(reader, raw.data, variant.elem, variant.elem_size, raw.len)
	}
	panic(fmt.tprintf("save: values of type %v cannot be read", info.id))
}

read_elements :: proc(reader: ^Byte_Reader, pointer: rawptr, elem: ^runtime.Type_Info, elem_size, count: int) -> bool {
	for index in 0 ..< count {
		read_value(reader, rawptr(uintptr(pointer) + uintptr(index * elem_size)), elem) or_return
	}
	return true
}

// Compares the low size bytes, so a negative value of a signed backing
// type matches its stored bit pattern.
enum_value_is_named :: proc(variant: runtime.Type_Info_Enum, value: u64, size: int) -> bool {
	mask := size == 8 ? max(u64) : (u64(1) << (8 * uint(size))) - 1
	for named in variant.values {
		if u64(named) & mask == value {
			return true
		}
	}
	return false
}

// A list of plain values: a u32 count and the values.
write_list :: proc(bytes: ^[dynamic]byte, values: []$T) {
	append_u32(bytes, u32(len(values)))
	for &value in values {
		write_value(bytes, &value, type_info_of(T))
	}
}

// Every value takes at least one byte, which bounds the count by the
// bytes left before anything is allocated.
read_list :: proc(reader: ^Byte_Reader, values: ^[dynamic]$T) -> bool {
	count := int(read_u32(reader) or_return)
	if count > bytes_left(reader^) {
		return false
	}
	resize(values, count)
	for &value in values {
		read_value(reader, &value, type_info_of(T)) or_return
	}
	return true
}

// Hashing, FNV-1a 64.

FINGERPRINT_START :: u64(0xcbf29ce484222325)

fingerprint_bytes :: proc(state: u64, bytes: []byte) -> u64 {
	return hash.fnv64a(bytes, state)
}

fingerprint_u64 :: proc(state: u64, value: u64) -> u64 {
	value := value
	return fingerprint_bytes(state, ([^]byte)(&value)[:size_of(value)])
}

fingerprint_string :: proc(state: u64, value: string) -> u64 {
	return fingerprint_bytes(fingerprint_u64(state, u64(len(value))), transmute([]byte)value)
}

Layout_Tag :: enum u8 {
	Named,
	Integer,
	Float,
	Enum,
	Bit_Set,
	Boolean,
	Array,
	Struct,
	Slice,
}

// Changes whenever a written type changes its fields, their order, their
// types or sizes, or an enum its names and values.
layout_fingerprint :: proc(state: u64, info: ^runtime.Type_Info) -> u64 {
	result := fingerprint_u64(state, u64(info.size))
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		return layout_fingerprint(fingerprint_string(fingerprint_u64(result, u64(Layout_Tag.Named)), variant.name), variant.base)
	case runtime.Type_Info_Integer:
		return fingerprint_u64(fingerprint_u64(result, u64(Layout_Tag.Integer)), u64(variant.signed))
	case runtime.Type_Info_Float:
		return fingerprint_u64(result, u64(Layout_Tag.Float))
	case runtime.Type_Info_Boolean:
		return fingerprint_u64(result, u64(Layout_Tag.Boolean))
	case runtime.Type_Info_Bit_Set:
		return fingerprint_u64(fingerprint_u64(result, u64(Layout_Tag.Bit_Set)), u64(variant.upper))
	case runtime.Type_Info_Enum:
		result = fingerprint_u64(result, u64(Layout_Tag.Enum))
		for name, index in variant.names {
			result = fingerprint_u64(fingerprint_string(result, name), u64(variant.values[index]))
		}
		return result
	case runtime.Type_Info_Array:
		return layout_fingerprint(fingerprint_u64(fingerprint_u64(result, u64(Layout_Tag.Array)), u64(variant.count)), variant.elem)
	case runtime.Type_Info_Enumerated_Array:
		return layout_fingerprint(fingerprint_u64(fingerprint_u64(result, u64(Layout_Tag.Array)), u64(variant.count)), variant.elem)
	case runtime.Type_Info_Slice:
		return layout_fingerprint(fingerprint_u64(result, u64(Layout_Tag.Slice)), variant.elem)
	case runtime.Type_Info_Struct:
		result = fingerprint_u64(result, u64(Layout_Tag.Struct))
		for field in 0 ..< int(variant.field_count) {
			result = layout_fingerprint(fingerprint_string(result, variant.names[field]), variant.types[field])
		}
		return result
	}
	panic(fmt.tprintf("save: no layout for type %v", info.id))
}
