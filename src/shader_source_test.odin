package game

import "core:fmt"
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
	testing.expect(t, checked >= 12, "found fewer than the twelve shipped shaders (chunk, water, field, arrival, model and flame)")
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
	testing.expect(t, checked >= 12, "found fewer than the twelve shipped shaders (chunk, water, field, arrival, model and flame)")
}

// The point light sum of a shader: from `vec3 point_light_sum(` to its
// closing brace; "" without it.
shader_point_light_sum :: proc(source: string) -> string {
	start := strings.index(source, "vec3 point_light_sum(")
	if start < 0 {
		return ""
	}
	length := strings.index(source[start:], "\n}\n")
	if length < 0 {
		return ""
	}
	return source[start:][:length + 3]
}

// Work item 0229: the field and model shaders take the same lights and
// share point_light_sum but for the clip line (the terrain skips a
// clipped light, the models test its box); only the model shader takes
// the boxes.
@(test)
test_the_point_light_shaders_share_the_clip_and_the_sum :: proc(t: ^testing.T) {
	directory := platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY)
	field_data, field_error := os.read_entire_file(platform.join_path(directory, "field.fs"), context.temp_allocator)
	testing.expect_value(t, field_error, nil)
	model_data, model_error := os.read_entire_file(platform.join_path(directory, "model.fs"), context.temp_allocator)
	testing.expect_value(t, model_error, nil)
	field, model := string(field_data), string(model_data)
	positions := fmt.tprintf("uniform vec4 point_light_positions[%du];", MAXIMUM_POINT_LIGHTS)
	boxes := fmt.tprintf("uniform vec4 point_light_boxes[%du];", MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS)
	testing.expect(t, strings.contains(field, positions), "field.fs declares the positions")
	testing.expect(t, strings.contains(model, positions), "model.fs declares the positions")
	testing.expect(t, strings.contains(model, boxes), "model.fs declares the boxes")
	testing.expect(t, strings.contains(model, "bool point_light_inside_box("), "model.fs tests the box")
	field_clip := "        if (color.a < 0.5) {\n"
	model_clip := "        if (!point_light_inside_box(index, position)) {\n"
	field_sum, model_sum := shader_point_light_sum(field), shader_point_light_sum(model)
	testing.expect(t, strings.contains(field_sum, field_clip), "field.fs skips a clipped light")
	testing.expect(t, strings.contains(model_sum, model_clip), "model.fs tests a light's box")
	field_as_model, _ := strings.replace_all(field_sum, field_clip, model_clip, context.temp_allocator)
	testing.expect(t, field_sum != "" && field_as_model == model_sum, "point_light_sum differs between field.fs and model.fs beyond the clip line")
}

// Work item 0286: the plasma shader's flicker mean is FIRE_FLICKER_MEAN
// (a flare is the flicker above it) and it takes the reduced motion
// uniform.
@(test)
test_the_plasma_shader_knows_the_flicker_mean :: proc(t: ^testing.T) {
	source := #load("../data/shaders/arrival.fs", string)
	testing.expect(t, strings.contains(source, fmt.tprintf("const float FLICKER_MEAN = %.2f;", FIRE_FLICKER_MEAN)), "arrival.fs's FLICKER_MEAN differs from FIRE_FLICKER_MEAN")
	testing.expect(t, strings.contains(source, "\nuniform float calm;\n"), "arrival.fs does not declare calm")
}

// The block light flicker of a shader: from `float torch_light_flicker(`
// to its closing brace; "" without it.
shader_torch_light_flicker :: proc(source: string) -> string {
	start := strings.index(source, "float torch_light_flicker(")
	if start < 0 {
		return ""
	}
	length := strings.index(source[start:], "\n}\n")
	if length < 0 {
		return ""
	}
	return source[start:][:length + 3]
}

// Work item 0284: the chunk and water shaders take the same torch
// flickers, MAXIMUM_BLOCK_TORCH_FLICKERS of them reaching
// BLOCK_TORCH_LIGHT_REACH_BLOCKS, and blend them line for line alike;
// neither keeps the old single flicker.
@(test)
test_the_block_shaders_share_the_torch_flicker :: proc(t: ^testing.T) {
	chunk := #load("../data/shaders/chunk.fs", string)
	water := #load("../data/shaders/water.fs", string)
	declaration := fmt.tprintf("uniform vec4 torch_flickers[%du];", MAXIMUM_BLOCK_TORCH_FLICKERS)
	reach := fmt.tprintf("const float torch_reach_blocks = %.1f;", BLOCK_TORCH_LIGHT_REACH_BLOCKS)
	for source, index in ([2]string{chunk, water}) {
		name := index == 0 ? "chunk.fs" : "water.fs"
		testing.expectf(t, strings.contains(source, declaration), "%s does not declare %s", name, declaration)
		testing.expectf(t, strings.contains(source, reach), "%s does not hold %s", name, reach)
		testing.expectf(t, !strings.contains(source, "uniform float flicker;"), "%s still declares the single flicker", name)
	}
	chunk_flicker := shader_torch_light_flicker(chunk)
	testing.expect(t, chunk_flicker != "" && chunk_flicker == shader_torch_light_flicker(water), "torch_light_flicker differs between chunk.fs and water.fs")
}

// Work item 0284: the flame shaders decode the flicker over
// FIRE_FLICKER_HIGHEST and move the ramp about FIRE_FLICKER_MEAN.
@(test)
test_the_flame_shaders_read_the_fire_flicker_bounds :: proc(t: ^testing.T) {
	vertex := #load("../data/shaders/flame.vs", string)
	fragment := #load("../data/shaders/flame.fs", string)
	highest := fmt.tprintf("const float fire_flicker_highest = %v;", FIRE_FLICKER_HIGHEST)
	mean := fmt.tprintf("const float fire_flicker_mean = %v;", FIRE_FLICKER_MEAN)
	testing.expectf(t, strings.contains(vertex, highest), "flame.vs does not hold %s", highest)
	testing.expectf(t, strings.contains(fragment, mean), "flame.fs does not hold %s", mean)
}
