package game

import "core:os"
import "core:strings"
import "core:testing"
import "platform"

// Shader source tests read the shipped data/shaders (work item 0105).
// Winlator's Gladio rewrites the GLSL line by line before compiling it
// on the phone: on a line with a float variable it appends .0 to every
// bare integer literal, so `hash >> 8` becomes `hash >> 8.0`, which does
// not compile. Integer literals therefore carry the u suffix.

is_identifier_character :: proc(character: u8) -> bool {
	return character == '_' || (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9')
}

is_number_literal_character :: proc(character: u8) -> bool {
	return (character >= '0' && character <= '9') || (character >= 'a' && character <= 'f') || (character >= 'A' && character <= 'F') || character == 'x' || character == 'X' || character == '.'
}

// The line without its // comment, empty for a preprocessor line.
shader_code_of_line :: proc(line: string) -> string {
	code := line
	if comment := strings.index(code, "//"); comment >= 0 {
		code = code[:comment]
	}
	if strings.has_prefix(strings.trim_left_space(code), "#") {
		return ""
	}
	return code
}

// A number literal that Gladio takes for an integer: starts with a digit,
// has no '.' and no u suffix.
is_bare_integer_literal :: proc(literal: string, next_character: u8) -> bool {
	starts_with_digit := literal[0] >= '0' && literal[0] <= '9'
	has_suffix := next_character == 'u' || next_character == 'U'
	return starts_with_digit && !strings.contains_rune(literal, '.') && !has_suffix
}

// The first bare integer literal of a line of code, empty when it has
// none. Identifiers are skipped whole, so atlas_uv2 and vec2 hold none.
first_bare_integer_literal :: proc(code: string) -> string {
	index := 0
	for index < len(code) {
		start := index
		if is_identifier_character(code[index]) && !(code[index] >= '0' && code[index] <= '9') {
			for index < len(code) && is_identifier_character(code[index]) {
				index += 1
			}
			continue
		}
		if !is_number_literal_character(code[index]) {
			index += 1
			continue
		}
		for index < len(code) && is_number_literal_character(code[index]) {
			index += 1
		}
		next_character: u8 = index < len(code) ? code[index] : 0
		if is_bare_integer_literal(code[start:index], next_character) {
			return code[start:index]
		}
	}
	return ""
}

@(test)
test_bare_integer_literals_are_found_outside_identifiers :: proc(t: ^testing.T) {
	testing.expect_value(t, first_bare_integer_literal("x >> 8;"), "8")
	testing.expect_value(t, first_bare_integer_literal("(hash >> 3) & 15u"), "3")
	testing.expect_value(t, first_bare_integer_literal("x >> 8u;"), "")
	testing.expect_value(t, first_bare_integer_literal("float y = 1.0;"), "")
	testing.expect_value(t, first_bare_integer_literal("hash *= 0x7feb352du;"), "")
	testing.expect_value(t, first_bare_integer_literal("vec2 v = vec2(1.5);"), "")
	testing.expect_value(t, first_bare_integer_literal("vec2 atlas_uv2 = position.xz;"), "")
	testing.expect_value(t, first_bare_integer_literal("float z = .5;"), "")
	testing.expect_value(t, shader_code_of_line("#version 330"), "")
	testing.expect_value(t, shader_code_of_line("x = 1.0; // 8 bits"), "x = 1.0; ")
}

@(test)
test_shipped_shaders_have_no_bare_integer_literals :: proc(t: ^testing.T) {
	directory := platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY)
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	testing.expect_value(t, error, nil)
	checked := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".vs") && !strings.has_suffix(entry.name, ".fs") {
			continue
		}
		data, read_error := os.read_entire_file(entry.fullpath, context.temp_allocator)
		testing.expect_value(t, read_error, nil)
		text := string(data)
		line_number := 0
		for line in strings.split_lines_iterator(&text) {
			line_number += 1
			literal := first_bare_integer_literal(shader_code_of_line(line))
			testing.expectf(t, literal == "", "data/shaders/%s:%d: integer literal %s needs the u suffix: Winlator's Gladio appends .0 to a bare integer on a line with a float variable", entry.name, line_number, literal)
		}
		checked += 1
	}
	testing.expect(t, checked >= 6, "found fewer than the six shipped shaders (chunk, water, field and arrival)")
}

// The GLSL ES rewrite for Android (work item 0114).
@(test)
test_shader_source_for_gles_rewrites_the_version_line :: proc(t: ^testing.T) {
	testing.expect_value(t, shader_source_for_gles("#version 330\nout vec4 finalColor;"), "#version 300 es\nprecision highp float;\nprecision highp int;\nout vec4 finalColor;")
	testing.expect_value(t, shader_source_for_gles("#version 330 core\nvoid main() {}\n"), "#version 300 es\nprecision highp float;\nprecision highp int;\nvoid main() {}\n")
}

@(test)
test_shader_source_for_gles_keeps_the_remainder :: proc(t: ^testing.T) {
	remainder := "\n// #version 330 in a comment\nflat in uint cell;\nuint hash = cell * 0x7feb352du;\n"
	rewritten := shader_source_for_gles(strings.concatenate({"#version 330", remainder}, context.temp_allocator))
	testing.expect(t, strings.has_suffix(rewritten, remainder))
	testing.expect_value(t, strings.count(rewritten, "#version"), 2)
}

@(test)
test_shader_source_for_gles_leaves_a_source_without_version :: proc(t: ^testing.T) {
	source := "void main() {}\n"
	testing.expect_value(t, shader_source_for_gles(source), source)
	testing.expect_value(t, shader_source_for_gles(""), "")
	testing.expect_value(t, shader_source_for_gles("#version 100\nvoid main() {}"), "#version 100\nvoid main() {}")
}

@(test)
test_shipped_shaders_begin_with_a_version_line :: proc(t: ^testing.T) {
	directory := platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY)
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	testing.expect_value(t, error, nil)
	checked := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".vs") && !strings.has_suffix(entry.name, ".fs") {
			continue
		}
		data, read_error := os.read_entire_file(entry.fullpath, context.temp_allocator)
		testing.expect_value(t, read_error, nil)
		testing.expectf(t, strings.has_prefix(string(data), "#version 330"), "data/shaders/%s does not begin with #version 330, so the Android build would not rewrite it for GLSL ES", entry.name)
		testing.expectf(t, strings.has_prefix(shader_source_for_gles(string(data)), "#version 300 es\n"), "data/shaders/%s", entry.name)
		checked += 1
	}
	testing.expect(t, checked >= 6, "found fewer than the six shipped shaders (chunk, water, field and arrival)")
}
