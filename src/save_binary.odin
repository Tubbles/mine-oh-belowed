package game

import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:reflect"

// The value codec of the save files, driven by Odin type information.
// Integers, floats and bit sets over an integer range are little endian
// bytes of their size, booleans one byte, enums the name of their value
// (append_string), bit sets of an enum a u16 count and the names of the
// set values, arrays their elements, enumerated arrays a u16 count and per
// element the index's name, a u32 byte length and the element, arrays and
// slices a u32 count and their elements.
//
// An array's count is not part of its kind: a saved array no longer than
// this build's reads its elements and leaves the rest zero (a raised
// MAXIMUM_ constant keeps saves loading), a longer one refuses the file
// with a problem naming the struct, the field and both counts, since
// dropping its tail would lose data silently.
//
// Structs describe themselves: a schema, a u16 field count and per field
// its name, a shallow kind fingerprint of its type (shallow_kind) and the
// byte size of its encoding when every value of the type has the same (0
// otherwise), then a body, per field its encoding, preceded by a u32 byte
// length when the size is not fixed. An array, slice or list of structs
// writes the schema once and then one body per element, so big arrays of
// small structs (the explored map) cost what their fields cost.
//
// Reading matches fields by name: a field of the same kind is read, a
// field the type no longer has is skipped, a field the file lacks keeps
// what the target held (callers zero targets, or give them defaults on
// purpose), and a field whose kind changed refuses the file with a
// problem naming the struct and the field. An enum name the type no longer
// has reads as zero, and such a name in a bit set is dropped.
//
// Values of the content id types (Item_Id, Block_Id, Fluid_Id, Machine_Id)
// are remapped from the ids the file was written with to this build's
// through the reader's Content_Remap (save_remap.odin).
//
// A field tagged save:"-" is left out (field_is_saved).
//
// Nothing is copied as raw memory, so padding, pointers and the host byte
// order never reach a file. Dynamic arrays, maps, strings and pointers are
// refused: the callers write those explicitly (write_list, append_string).

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

// Overwrites the u32 at offset with the number of bytes written after it,
// for a length written before the value it measures.
patch_length :: proc(bytes: ^[dynamic]byte, offset: int) {
	length := u32(len(bytes) - offset - size_of(u32))
	for index in 0 ..< size_of(u32) {
		bytes[offset + index] = byte(length >> (8 * uint(index)))
	}
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

// Type information helpers.

// A struct type with the name it was declared with ("" when anonymous).
Struct_Type :: struct {
	variant: runtime.Type_Info_Struct,
	name:    string,
	id:      typeid,
}

struct_type_of :: proc(info: ^runtime.Type_Info) -> (type: Struct_Type, is_struct: bool) {
	name := ""
	if named, is_named := info.variant.(runtime.Type_Info_Named); is_named {
		name = named.name
	}
	variant := runtime.type_info_base(info).variant.(runtime.Type_Info_Struct) or_return
	assert(.raw_union not_in variant.flags, "save: unions cannot be written")
	return Struct_Type{variant = variant, name = name, id = info.id}, true
}

// The enum behind a bit set's or an enumerated array's elements, with the
// enum type's name.
enum_type_of :: proc(info: ^runtime.Type_Info) -> (variant: runtime.Type_Info_Enum, name: string, is_enum: bool) {
	if named, is_named := info.variant.(runtime.Type_Info_Named); is_named {
		name = named.name
	}
	variant = runtime.type_info_base(info).variant.(runtime.Type_Info_Enum) or_return
	return variant, name, true
}

enum_value_mask :: proc(size: int) -> u64 {
	return size == 8 ? max(u64) : (u64(1) << (8 * uint(size))) - 1
}

// The name of a stored enum value, "" when the value has none. Compares
// the low size bytes, so a negative value of a signed backing type
// matches its stored bit pattern.
enum_value_name :: proc(variant: runtime.Type_Info_Enum, value: u64, size: int) -> string {
	for named, index in variant.values {
		if u64(named) & enum_value_mask(size) == value {
			return variant.names[index]
		}
	}
	return ""
}

enum_value_of_name :: proc(variant: runtime.Type_Info_Enum, name: string) -> (value: i64, found: bool) {
	for candidate, index in variant.names {
		if candidate == name {
			return i64(variant.values[index]), true
		}
	}
	return 0, false
}

// A field tagged save:"-" stays out of the files: the save writes it
// elsewhere when it matters (Entity_Common.frame, save_state.odin), so a
// state without it keeps its bytes.
field_is_saved :: proc(variant: runtime.Type_Info_Struct, field: int) -> bool {
	return reflect.struct_tag_get(reflect.Struct_Tag(variant.tags[field]), "save") != "-"
}

saved_field_count :: proc(variant: runtime.Type_Info_Struct) -> int {
	count := 0
	for field in 0 ..< int(variant.field_count) {
		if field_is_saved(variant, field) {
			count += 1
		}
	}
	return count
}

struct_field_index :: proc(variant: runtime.Type_Info_Struct, name: string) -> int {
	for field in 0 ..< int(variant.field_count) {
		if variant.names[field] == name && field_is_saved(variant, field) {
			return field
		}
	}
	return -1
}

field_pointer :: proc(pointer: rawptr, variant: runtime.Type_Info_Struct, field: int) -> rawptr {
	return rawptr(uintptr(pointer) + variant.offsets[field])
}

element_pointer :: proc(pointer: rawptr, elem_size, index: int) -> rawptr {
	return rawptr(uintptr(pointer) + uintptr(index * elem_size))
}

// Kinds.

Kind_Tag :: enum u8 {
	Named,
	Integer,
	Float,
	Enum,
	Bit_Set,
	Boolean,
	Array,
	Enumerated_Array,
	Struct,
	Slice,
}

kind_start :: proc(tag: Kind_Tag) -> u64 {
	return fingerprint_u64(FINGERPRINT_START, u64(tag))
}

// What a field's type is, without looking into structs, which describe
// their own fields, or at enum values, which are written by name. A
// retyped field changes its kind; a struct or an enum gaining, losing or
// reordering members does not. Named types other than structs and enums
// (distinct ids, coordinates) count by their name and their base.
shallow_kind :: proc(info: ^runtime.Type_Info) -> u64 {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		#partial switch _ in variant.base.variant {
		case runtime.Type_Info_Struct:
			return fingerprint_string(kind_start(.Struct), variant.name)
		case runtime.Type_Info_Enum:
			return fingerprint_string(kind_start(.Enum), variant.name)
		}
		return fingerprint_string(fingerprint_u64(kind_start(.Named), shallow_kind(variant.base)), variant.name)
	case runtime.Type_Info_Integer:
		return fingerprint_u64(fingerprint_u64(kind_start(.Integer), u64(info.size)), u64(variant.signed))
	case runtime.Type_Info_Float:
		return fingerprint_u64(kind_start(.Float), u64(info.size))
	case runtime.Type_Info_Boolean:
		return fingerprint_u64(kind_start(.Boolean), u64(info.size))
	case runtime.Type_Info_Enum:
		return kind_start(.Enum)
	case runtime.Type_Info_Bit_Set:
		if _, name, is_enum := enum_type_of(variant.elem); is_enum {
			return fingerprint_u64(fingerprint_string(kind_start(.Bit_Set), name), u64(info.size))
		}
		range := fingerprint_u64(fingerprint_u64(kind_start(.Bit_Set), u64(variant.lower)), u64(variant.upper))
		return fingerprint_u64(range, u64(info.size))
	case runtime.Type_Info_Array:
		return fingerprint_u64(kind_start(.Array), shallow_kind(variant.elem))
	case runtime.Type_Info_Enumerated_Array:
		_, name, _ := enum_type_of(variant.index)
		return fingerprint_u64(fingerprint_string(kind_start(.Enumerated_Array), name), shallow_kind(variant.elem))
	case runtime.Type_Info_Slice:
		return fingerprint_u64(kind_start(.Slice), shallow_kind(variant.elem))
	case runtime.Type_Info_Struct:
		return kind_start(.Struct)
	}
	panic(fmt.tprintf("save: values of type %v cannot be written", info.id))
}

// The byte size of this build's encoding when every value of the type has
// the same, otherwise 0. An array's differs from a file's when the counts
// differ, so reading takes the size from the file's schema.
fixed_encoding_size :: proc(info: ^runtime.Type_Info) -> int {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		return fixed_encoding_size(variant.base)
	case runtime.Type_Info_Integer, runtime.Type_Info_Float:
		return info.size
	case runtime.Type_Info_Boolean:
		return 1
	case runtime.Type_Info_Bit_Set:
		_, _, is_enum := enum_type_of(variant.elem)
		return is_enum ? 0 : info.size
	case runtime.Type_Info_Array:
		element_size := fixed_encoding_size(variant.elem)
		return element_size == 0 ? 0 : size_of(u32) + variant.count * element_size
	}
	return 0
}

// Writing.

write_value :: proc(bytes: ^[dynamic]byte, pointer: rawptr, info: ^runtime.Type_Info) {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		write_value(bytes, pointer, variant.base)
	case runtime.Type_Info_Integer, runtime.Type_Info_Float:
		append_unsigned(bytes, load_unsigned(pointer, info.size), info.size)
	case runtime.Type_Info_Boolean:
		append_u8(bytes, (^bool)(pointer)^ ? 1 : 0)
	case runtime.Type_Info_Enum:
		append_string(bytes, enum_value_name(variant, load_unsigned(pointer, info.size), info.size))
	case runtime.Type_Info_Bit_Set:
		write_bit_set(bytes, pointer, info.size, variant)
	case runtime.Type_Info_Array:
		append_u32(bytes, u32(variant.count))
		write_elements(bytes, pointer, variant.elem, variant.elem_size, variant.count)
	case runtime.Type_Info_Enumerated_Array:
		write_enumerated_array(bytes, pointer, variant)
	case runtime.Type_Info_Struct:
		type, _ := struct_type_of(info)
		write_struct_schema(bytes, type.variant)
		write_struct_body(bytes, pointer, type.variant)
	case runtime.Type_Info_Slice:
		raw := (^runtime.Raw_Slice)(pointer)
		append_u32(bytes, u32(raw.len))
		write_elements(bytes, raw.data, variant.elem, variant.elem_size, raw.len)
	case:
		panic(fmt.tprintf("save: values of type %v cannot be written", info.id))
	}
}

// Structs share one schema.
write_elements :: proc(bytes: ^[dynamic]byte, pointer: rawptr, elem: ^runtime.Type_Info, elem_size, count: int) {
	if type, is_struct := struct_type_of(elem); is_struct {
		write_struct_schema(bytes, type.variant)
		for index in 0 ..< count {
			write_struct_body(bytes, element_pointer(pointer, elem_size, index), type.variant)
		}
		return
	}
	for index in 0 ..< count {
		write_value(bytes, element_pointer(pointer, elem_size, index), elem)
	}
}

write_struct_schema :: proc(bytes: ^[dynamic]byte, variant: runtime.Type_Info_Struct) {
	append_u16(bytes, u16(saved_field_count(variant)))
	for field in 0 ..< int(variant.field_count) {
		if !field_is_saved(variant, field) {
			continue
		}
		append_string(bytes, variant.names[field])
		append_u64(bytes, shallow_kind(variant.types[field]))
		append_u32(bytes, u32(fixed_encoding_size(variant.types[field])))
	}
}

write_struct_body :: proc(bytes: ^[dynamic]byte, pointer: rawptr, variant: runtime.Type_Info_Struct) {
	for field in 0 ..< int(variant.field_count) {
		info := variant.types[field]
		if !field_is_saved(variant, field) {
			continue
		}
		if fixed_encoding_size(info) > 0 {
			write_value(bytes, field_pointer(pointer, variant, field), info)
			continue
		}
		length_offset := len(bytes)
		append_u32(bytes, 0)
		write_value(bytes, field_pointer(pointer, variant, field), info)
		patch_length(bytes, length_offset)
	}
}

// Bit sets of an enum by the names of the set values, others as bits.
write_bit_set :: proc(bytes: ^[dynamic]byte, pointer: rawptr, size: int, variant: runtime.Type_Info_Bit_Set) {
	bits := load_unsigned(pointer, size)
	elements, _, is_enum := enum_type_of(variant.elem)
	if !is_enum {
		append_unsigned(bytes, bits, size)
		return
	}
	count := 0
	for value in elements.values {
		count += bits >> uint(i64(value) - variant.lower) & 1 == 1 ? 1 : 0
	}
	append_u16(bytes, u16(count))
	for value, index in elements.values {
		if bits >> uint(i64(value) - variant.lower) & 1 == 1 {
			append_string(bytes, elements.names[index])
		}
	}
}

write_enumerated_array :: proc(bytes: ^[dynamic]byte, pointer: rawptr, variant: runtime.Type_Info_Enumerated_Array) {
	index_enum, _, _ := enum_type_of(variant.index)
	append_u16(bytes, u16(variant.count))
	for position in 0 ..< variant.count {
		value := u64(i64(variant.min_value) + i64(position))
		append_string(bytes, enum_value_name(index_enum, value, size_of(u64)))
		length_offset := len(bytes)
		append_u32(bytes, 0)
		write_value(bytes, element_pointer(pointer, variant.elem_size, position), variant.elem)
		patch_length(bytes, length_offset)
	}
}

// Reading.

// A field of the file's schema: the target field it reads into (-1 when
// this build's type has no field of that name) and its fixed encoding
// size (0 when a u32 length precedes each value).
Schema_Field :: struct {
	field:      int,
	fixed_size: int,
}

read_value :: proc(reader: ^Byte_Reader, pointer: rawptr, info: ^runtime.Type_Info) -> bool {
	#partial switch variant in info.variant {
	case runtime.Type_Info_Named:
		if table, is_id := content_id_table(info.id); is_id {
			return read_content_id(reader, pointer, info.size, table)
		}
		if type, is_struct := struct_type_of(info); is_struct {
			schema := read_struct_schema(reader, type) or_return
			return read_struct_body(reader, pointer, type, schema)
		}
		return read_value(reader, pointer, variant.base)
	case runtime.Type_Info_Integer, runtime.Type_Info_Float:
		store_unsigned(pointer, info.size, read_unsigned(reader, info.size) or_return)
		return true
	case runtime.Type_Info_Enum:
		name := read_string(reader) or_return
		value, _ := enum_value_of_name(variant, name)
		store_unsigned(pointer, info.size, u64(value))
		return true
	case runtime.Type_Info_Bit_Set:
		return read_bit_set(reader, pointer, info.size, variant)
	case runtime.Type_Info_Boolean:
		value := read_u8(reader) or_return
		if value > 1 {
			return false
		}
		(^bool)(pointer)^ = value == 1
		return true
	case runtime.Type_Info_Array:
		return read_array(reader, pointer, variant)
	case runtime.Type_Info_Enumerated_Array:
		return read_enumerated_array(reader, pointer, variant)
	case runtime.Type_Info_Struct:
		type, _ := struct_type_of(info)
		schema := read_struct_schema(reader, type) or_return
		return read_struct_body(reader, pointer, type, schema)
	case runtime.Type_Info_Slice:
		// Read into the slice already there, whose length must match: the
		// slices indexed by content ids are read into copies sized by the
		// file's tables (save_remap.odin), the others have fixed lengths.
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
	if type, is_struct := struct_type_of(elem); is_struct {
		schema := read_struct_schema(reader, type) or_return
		for index in 0 ..< count {
			read_struct_body(reader, element_pointer(pointer, elem_size, index), type, schema) or_return
		}
		return true
	}
	for index in 0 ..< count {
		read_value(reader, element_pointer(pointer, elem_size, index), elem) or_return
	}
	return true
}

// Matches the file's fields to the type's by name. A field whose kind
// changed sets reader.problem.
read_struct_schema :: proc(reader: ^Byte_Reader, type: Struct_Type) -> (schema: []Schema_Field, ok: bool) {
	count := int(read_u16(reader) or_return)
	if count > bytes_left(reader^) {
		return nil, false
	}
	schema = make([]Schema_Field, count, context.temp_allocator)
	for &entry in schema {
		name := read_string(reader) or_return
		kind := read_u64(reader) or_return
		entry.fixed_size = int(read_u32(reader) or_return)
		entry.field = struct_field_index(type.variant, name)
		if entry.field < 0 {
			continue
		}
		info := type.variant.types[entry.field]
		if kind != shallow_kind(info) {
			reader.problem = fmt.tprintf("the field %s of %s changed its type", name, type.name)
			return nil, false
		}
		if (entry.fixed_size == 0) != (fixed_encoding_size(info) == 0) {
			return nil, false
		}
	}
	return schema, true
}

read_struct_body :: proc(reader: ^Byte_Reader, pointer: rawptr, type: Struct_Type, schema: []Schema_Field) -> bool {
	gone_before := content_gone_count(reader.remap)
	for entry in schema {
		length := entry.fixed_size
		if length == 0 {
			length = int(read_u32(reader) or_return)
		}
		if length > bytes_left(reader^) {
			return false
		}
		end := reader.offset + length
		if entry.field < 0 {
			reader.offset = end
			continue
		}
		info := type.variant.types[entry.field]
		if problem := array_count_problem(reader^, info); problem != "" {
			reader.problem = fmt.tprintf("the field %s of %s %s", type.variant.names[entry.field], type.name, problem)
			return false
		}
		read_value(reader, field_pointer(pointer, type.variant, entry.field), info) or_return
		if reader.offset != end {
			return false
		}
	}
	if content_gone_count(reader.remap) != gone_before {
		empty_value_of_gone_content(pointer, type.id)
	}
	return true
}

// Why the array at the reader cannot be read into a value of the type:
// it holds more elements than the type has. Empty for other types.
array_count_problem :: proc(reader: Byte_Reader, info: ^runtime.Type_Info) -> string {
	variant, is_array := runtime.type_info_base(info).variant.(runtime.Type_Info_Array)
	peek := reader
	saved_count, ok := read_u32(&peek)
	if !is_array || !ok || int(saved_count) <= variant.count {
		return ""
	}
	return fmt.tprintf("holds %d saved elements, this build's array has %d", saved_count, variant.count)
}

// The saved elements, the rest zeroed.
read_array :: proc(reader: ^Byte_Reader, pointer: rawptr, variant: runtime.Type_Info_Array) -> bool {
	count := int(read_u32(reader) or_return)
	if count > variant.count {
		reader.problem = fmt.tprintf("an array holds %d saved elements, this build's has %d", count, variant.count)
		return false
	}
	read_elements(reader, pointer, variant.elem, variant.elem_size, count) or_return
	rest := element_pointer(pointer, variant.elem_size, count)
	runtime.mem_zero(rest, (variant.count - count) * variant.elem_size)
	return true
}

read_bit_set :: proc(reader: ^Byte_Reader, pointer: rawptr, size: int, variant: runtime.Type_Info_Bit_Set) -> bool {
	elements, _, is_enum := enum_type_of(variant.elem)
	if !is_enum {
		store_unsigned(pointer, size, read_unsigned(reader, size) or_return)
		return true
	}
	count := int(read_u16(reader) or_return)
	bits: u64
	for _ in 0 ..< count {
		name := read_string(reader) or_return
		if value, found := enum_value_of_name(elements, name); found {
			bits |= u64(1) << uint(value - variant.lower)
		}
	}
	store_unsigned(pointer, size, bits)
	return true
}

// Elements whose index name this build's enum lacks are skipped.
read_enumerated_array :: proc(reader: ^Byte_Reader, pointer: rawptr, variant: runtime.Type_Info_Enumerated_Array) -> bool {
	index_enum, _, _ := enum_type_of(variant.index)
	count := int(read_u16(reader) or_return)
	for _ in 0 ..< count {
		name := read_string(reader) or_return
		length := int(read_u32(reader) or_return)
		if length > bytes_left(reader^) {
			return false
		}
		end := reader.offset + length
		value, found := enum_value_of_name(index_enum, name)
		position := int(value - i64(variant.min_value))
		if !found || position < 0 || position >= variant.count {
			reader.offset = end
			continue
		}
		read_value(reader, element_pointer(pointer, variant.elem_size, position), variant.elem) or_return
		if reader.offset != end {
			return false
		}
	}
	return true
}

// A list of plain values: a u32 count and the values.
write_list :: proc(bytes: ^[dynamic]byte, values: []$T) {
	append_u32(bytes, u32(len(values)))
	write_elements(bytes, raw_data(values), type_info_of(T), size_of(T), len(values))
}

// Every value takes at least one byte, which bounds the count by the
// bytes left before anything is allocated. Elements start zeroed, so
// fields the file lacks read as zero.
read_list :: proc(reader: ^Byte_Reader, values: ^[dynamic]$T) -> bool {
	count := int(read_u32(reader) or_return)
	if count > bytes_left(reader^) {
		return false
	}
	resize(values, count)
	for &value in values {
		value = {}
	}
	return read_elements(reader, raw_data(values^), type_info_of(T), size_of(T), count)
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
