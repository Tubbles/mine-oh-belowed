package game

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "core:strings"

// A json.Value written as SJSON in the style of the data files (work item
// 0130, the Data files screen's Save): the root object without braces,
// keys unquoted and "=", tabs, a container of leaves alone on one line
// ({item = "torch", count = 64}, ["hand", "assembler"]), any other
// container one member per line. Integers stay integers and floats keep
// a point, so the text parses back (json.parse, .SJSON, parse_integers)
// to an equal tree. Not json.marshal: it prints a float 0.5 as
// 0.5000000000000000 and puts every container on its own lines. An
// object's keys come sorted, since json.Object keeps no order.

// The whole file, ending in a newline. In allocator.
sjson_text :: proc(value: json.Value, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	if object, is_object := value.(json.Object); is_object {
		write_sjson_members(&builder, object, 0)
	} else {
		write_sjson_value(&builder, value, 0)
		strings.write_byte(&builder, '\n')
	}
	return strings.to_string(builder)
}

// One "key = value" line per member at the indentation.
write_sjson_members :: proc(builder: ^strings.Builder, object: json.Object, depth: int) {
	for key in sorted_object_keys(object) {
		write_sjson_indentation(builder, depth)
		fmt.sbprintf(builder, "%s = ", sjson_key_text(key))
		write_sjson_value(builder, object[key], depth)
		strings.write_byte(builder, '\n')
	}
}

// A value whose opening bracket is already at the indentation of depth;
// its members, when on lines of their own, go one level deeper.
write_sjson_value :: proc(builder: ^strings.Builder, value: json.Value, depth: int) {
	if sjson_value_is_flat(value) {
		write_sjson_inline(builder, value)
		return
	}
	#partial switch container in value {
	case json.Object:
		strings.write_string(builder, "{\n")
		write_sjson_members(builder, container, depth + 1)
		write_sjson_indentation(builder, depth)
		strings.write_byte(builder, '}')
	case json.Array:
		strings.write_string(builder, "[\n")
		for element in container {
			write_sjson_indentation(builder, depth + 1)
			write_sjson_value(builder, element, depth + 1)
			strings.write_byte(builder, '\n')
		}
		write_sjson_indentation(builder, depth)
		strings.write_byte(builder, ']')
	}
}

// A leaf, or a container whose members are all leaves.
sjson_value_is_flat :: proc(value: json.Value) -> bool {
	#partial switch container in value {
	case json.Object:
		for _, member in container {
			if sjson_value_is_container(member) {
				return false
			}
		}
	case json.Array:
		for element in container {
			if sjson_value_is_container(element) {
				return false
			}
		}
	}
	return true
}

sjson_value_is_container :: proc(value: json.Value) -> bool {
	#partial switch _ in value {
	case json.Object, json.Array:
		return true
	}
	return false
}

// A flat value on one line.
write_sjson_inline :: proc(builder: ^strings.Builder, value: json.Value) {
	#partial switch container in value {
	case json.Object:
		strings.write_byte(builder, '{')
		for key, index in sorted_object_keys(container) {
			if index > 0 {
				strings.write_string(builder, ", ")
			}
			fmt.sbprintf(builder, "%s = ", sjson_key_text(key))
			write_sjson_inline(builder, container[key])
		}
		strings.write_byte(builder, '}')
	case json.Array:
		strings.write_byte(builder, '[')
		for element, index in container {
			if index > 0 {
				strings.write_string(builder, ", ")
			}
			write_sjson_inline(builder, element)
		}
		strings.write_byte(builder, ']')
	case:
		strings.write_string(builder, sjson_leaf_text(value, context.temp_allocator))
	}
}

write_sjson_indentation :: proc(builder: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth {
		strings.write_byte(builder, '\t')
	}
}

// A leaf as the file holds it: a float with a point (16.0, not 16, which
// would read back as an integer), a string quoted with JSON's escapes.
sjson_leaf_text :: proc(value: json.Value, allocator := context.allocator) -> string {
	#partial switch leaf in value {
	case json.Integer:
		return fmt.aprintf("%d", leaf, allocator = allocator)
	case json.Float:
		return sjson_float_text(leaf, allocator)
	case json.Boolean:
		return fmt.aprintf("%v", leaf, allocator = allocator)
	case json.String:
		return sjson_quoted(leaf, allocator)
	}
	return "null"
}

// The shortest text that reads back as the same float, with a point
// unless it has an exponent.
sjson_float_text :: proc(value: f64, allocator := context.allocator) -> string {
	shortest := fmt.tprintf("%v", value)
	if strings.contains_any(shortest, ".eEnN") {
		return strings.clone(shortest, allocator)
	}
	return strings.concatenate({shortest, ".0"}, allocator)
}

// Quoted, with the quote, the backslash and control characters escaped;
// other characters (UTF-8 among them) as they are.
sjson_quoted :: proc(value: string, allocator := context.allocator) -> string {
	builder := strings.builder_make(allocator)
	strings.write_byte(&builder, '"')
	for character in transmute([]u8)value {
		switch character {
		case '"':
			strings.write_string(&builder, `\"`)
		case '\\':
			strings.write_string(&builder, `\\`)
		case '\n':
			strings.write_string(&builder, `\n`)
		case '\t':
			strings.write_string(&builder, `\t`)
		case '\r':
			strings.write_string(&builder, `\r`)
		case 0 ..< ' ':
			fmt.sbprintf(&builder, `\u%04x`, character)
		case:
			strings.write_byte(&builder, character)
		}
	}
	strings.write_byte(&builder, '"')
	return strings.to_string(builder)
}

// Words the parser reads as values, so a key of that name is quoted.
@(rodata)
sjson_value_words := [?]string{"true", "false", "null", "Infinity", "NaN"}

// Bare when it is an identifier (letters, digits and _, not starting with
// a digit) and no value word, else quoted.
sjson_key_text :: proc(key: string) -> string {
	if sjson_key_is_identifier(key) && !slice.contains(sjson_value_words[:], key) {
		return key
	}
	return sjson_quoted(key, context.temp_allocator)
}

sjson_key_is_identifier :: proc(key: string) -> bool {
	if key == "" || (key[0] >= '0' && key[0] <= '9') {
		return false
	}
	for character in transmute([]u8)key {
		letter := (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z')
		if !letter && character != '_' && !(character >= '0' && character <= '9') {
			return false
		}
	}
	return true
}
