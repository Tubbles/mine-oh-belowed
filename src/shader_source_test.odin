package game

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
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

// The words GLSL ES 3.00 (section 3.8) and GLSL 3.30 (section 3.6)
// reserve for future use, the ES list first and then the ones only 3.30
// adds; using one is an error. The ES list holds the 3.30 keywords ES
// lacks (attribute, varying, noperspective, the 1D and rectangle
// samplers). Mesa refuses packed as a parameter name where
// glslangValidator takes it (0307).
GLSL_RESERVED_WORDS :: [?]string {
	"attribute", "varying", "coherent", "volatile", "restrict", "readonly", "writeonly", "resource", "atomic_uint",
	"noperspective", "patch", "sample", "subroutine", "common", "partition", "active", "asm",
	"class", "union", "enum", "typedef", "template", "this", "goto",
	"inline", "noinline", "public", "static", "extern", "external", "interface",
	"long", "short", "double", "half", "fixed", "unsigned", "superp", "input", "output",
	"hvec2", "hvec3", "hvec4", "dvec2", "dvec3", "dvec4", "fvec2", "fvec3", "fvec4",
	"sampler3DRect", "filter",
	"image1D", "image2D", "image3D", "imageCube", "iimage1D", "iimage2D", "iimage3D", "iimageCube",
	"uimage1D", "uimage2D", "uimage3D", "uimageCube", "image1DArray", "image2DArray",
	"iimage1DArray", "iimage2DArray", "uimage1DArray", "uimage2DArray", "imageBuffer", "iimageBuffer", "uimageBuffer",
	"sampler1D", "sampler1DShadow", "sampler1DArray", "sampler1DArrayShadow", "isampler1D", "isampler1DArray", "usampler1D", "usampler1DArray",
	"sampler2DRect", "sampler2DRectShadow", "isampler2DRect", "usampler2DRect", "samplerBuffer", "isamplerBuffer", "usamplerBuffer",
	"sampler2DMS", "isampler2DMS", "usampler2DMS", "sampler2DMSArray", "isampler2DMSArray", "usampler2DMSArray",
	"sizeof", "cast", "namespace", "using",
	"packed", "image1DShadow", "image2DShadow", "image1DArrayShadow", "image2DArrayShadow", "row_major",
}

// The first token of a line of code that is a reserved word or holds two
// consecutive underscores (both specifications reserve those too), empty
// when it has none.
first_reserved_glsl_word :: proc(code: string) -> string {
	index := 0
	for index < len(code) {
		if !is_identifier_character(code[index]) {
			index += 1
			continue
		}
		start := index
		for index < len(code) && is_identifier_character(code[index]) {
			index += 1
		}
		token := code[start:index]
		for word in GLSL_RESERVED_WORDS {
			if token == word {
				return token
			}
		}
		if strings.contains(token, "__") {
			return token
		}
	}
	return ""
}

@(test)
test_reserved_glsl_words_are_found_as_whole_tokens :: proc(t: ^testing.T) {
	testing.expect_value(t, first_reserved_glsl_word("vec3 unpack_bytes(float packed)"), "packed")
	testing.expect_value(t, first_reserved_glsl_word("float sample = 1.0;"), "sample")
	testing.expect_value(t, first_reserved_glsl_word("float sample_count = input_scale;"), "")
	testing.expect_value(t, first_reserved_glsl_word("float a__b;"), "a__b")
	testing.expect_value(t, first_reserved_glsl_word(shader_code_of_line("x = 1.0; // three bytes packed")), "")
}

@(test)
test_shipped_shaders_use_no_reserved_glsl_word :: proc(t: ^testing.T) {
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
			word := first_reserved_glsl_word(shader_code_of_line(line))
			testing.expectf(t, word == "", "data/shaders/%s:%d: %s is reserved in GLSL 3.30 or GLSL ES 3.00, and Mesa refuses it", entry.name, line_number, word)
		}
		checked += 1
	}
	testing.expect(t, checked >= 12, "found fewer than the twelve shipped shaders")
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
	// The trees' shader (0310) takes the model's lights line for line.
	tree := read_tree_shader(t, "tree.fs")
	testing.expect(t, strings.contains(tree, positions), "tree.fs declares the positions")
	testing.expect(t, strings.contains(tree, boxes), "tree.fs declares the boxes")
	testing.expect(t, shader_point_light_sum(tree) == model_sum, "point_light_sum differs between tree.fs and model.fs")
	testing.expect(t, shader_function_text(tree, "bool point_light_inside_box(") == shader_function_text(model, "bool point_light_inside_box("), "point_light_inside_box differs between tree.fs and model.fs")
	testing.expect(t, shader_spot_light(tree) == shader_spot_light(model), "spot_light differs between tree.fs and model.fs")
	// The cover's shader (0311) takes the terrain's lights line for line.
	cover := read_tree_shader(t, "cover.fs")
	testing.expect(t, strings.contains(cover, positions), "cover.fs declares the positions")
	testing.expect(t, shader_point_light_sum(cover) == field_sum, "point_light_sum differs between cover.fs and field.fs")
}

// A shader of the trees (0310), its text.
read_tree_shader :: proc(t: ^testing.T, name: string) -> string {
	data, error := os.read_entire_file(platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY, name), context.temp_allocator)
	testing.expect_value(t, error, nil)
	return string(data)
}

// Work item 0310: tree.vs reads the instance's transform where the near
// models' buffer (draw_mesh_instances) and the card tiles put it, sizes
// the species' arrays by MAXIMUM_TREE_SPECIES and holds the atlas's
// layout.
@(test)
test_the_tree_shader_reads_the_instance :: proc(t: ^testing.T) {
	vertex := read_tree_shader(t, "tree.vs")
	testing.expect(t, strings.contains(vertex, "\nin mat4 instanceTransform;\n"), "tree.vs reads instanceTransform")
	testing.expect_value(t, INSTANCE_TRANSFORM_LOCATION, 9)
	for line in ([?]string {
			fmt.tprintf("uniform vec3 species_tint[%du];", MAXIMUM_TREE_SPECIES),
			fmt.tprintf("uniform vec4 species_card[%du];", MAXIMUM_TREE_SPECIES),
			fmt.tprintf("min(uint(instanceTransform[0u][3u] + 0.5), %du)", MAXIMUM_TREE_SPECIES - 1),
			fmt.tprintf("const float card_cell_texels = %d.0;", TREE_CARD_CELL_TEXELS),
			fmt.tprintf("const float card_margin_texels = %d.0;", TREE_CARD_MARGIN_TEXELS),
			fmt.tprintf("const float card_atlas_texels = %d.0;", TREE_CARD_ATLAS_WIDTH),
		}) {
		testing.expectf(t, strings.contains(vertex, line), "tree.vs does not hold %s", line)
	}
	fragment := read_tree_shader(t, "tree.fs")
	// The mips keep the share at or above TREE_CARD_ALPHA_KEPT, which
	// tree.fs keeps as 0.5.
	testing.expect_value(t, TREE_CARD_ALPHA_KEPT, 128)
	testing.expect(t, strings.contains(fragment, "texel.a < 0.5"), "tree.fs keeps the texels from alpha 0.5")
}

// Work items 0286 and 0304: the plasma's shader, the wake's, has the
// flicker mean FIRE_FLICKER_MEAN (a flare is the flicker above it) and
// takes the reduced motion uniform.
@(test)
test_the_plasma_shader_knows_the_flicker_mean :: proc(t: ^testing.T) {
	source := #load("../data/shaders/arrival_wake.fs", string)
	testing.expect(t, strings.contains(source, fmt.tprintf("const float FLICKER_MEAN = %.2f;", FIRE_FLICKER_MEAN)), "arrival_wake.fs's FLICKER_MEAN differs from FIRE_FLICKER_MEAN")
	testing.expect(t, strings.contains(source, "\nuniform float calm;\n"), "arrival_wake.fs does not declare calm")
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

// Work items 0290, 0304 and 0305: the wake's and the flakes' hottest
// colour is the data's core colour, no fixed white or violet, and the
// flake's vertex shader decodes the brightness over
// ARRIVAL_FLAKE_BRIGHTEST.
@(test)
test_the_flake_shaders_take_the_core_colour_and_the_brightest :: proc(t: ^testing.T) {
	vertex := #load("../data/shaders/arrival_flake.vs", string)
	fragment := #load("../data/shaders/arrival_flake.fs", string)
	plasma := #load("../data/shaders/arrival_wake.fs", string)
	brightest := fmt.tprintf("const float flake_brightest = %.1f;", ARRIVAL_FLAKE_BRIGHTEST)
	testing.expect(t, !strings.contains(plasma, "WHITE_CORE"), "arrival_wake.fs still holds WHITE_CORE")
	testing.expect(t, !strings.contains(fragment, "WHITE_CORE"), "arrival_flake.fs still holds WHITE_CORE")
	testing.expect(t, !strings.contains(plasma, "VIOLET_SHADE"), "arrival_wake.fs still holds VIOLET_SHADE")
	testing.expect(t, strings.contains(fragment, "\nuniform vec3 core_color;\n"), "arrival_flake.fs does not declare uniform vec3 core_color;")
	testing.expectf(t, strings.contains(vertex, brightest), "arrival_flake.vs does not hold %s", brightest)
}

// Work item 0305: the porthole's light is the wake's colour where the
// chair's porthole looks, the ramp's share of the ablator at the
// reference intensity.
@(test)
test_the_window_light_is_the_wake_at_the_porthole :: proc(t: ^testing.T) {
	source := #load("../data/shaders/arrival_wake.fs", string)
	scale, found := shader_float_constant(source, "RAMP_ORANGE_SCALE")
	testing.expect(t, found, "arrival_wake.fs does not hold RAMP_ORANGE_SCALE")
	share := 1 - math.exp(-f32(ARRIVAL_WAKE_REFERENCE_INTENSITY) / scale)
	testing.expectf(t, abs(share - ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE) < 0.01, "the ramp reads %v of the ablator at the reference intensity, the light %v", share, ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE)
}

// A shader's float constant: the text after `const float <name> = ` up
// to the `;`; found false without it or when it does not parse.
shader_float_constant :: proc(source, name: string) -> (value: f32, found: bool) {
	prefix := fmt.tprintf("const float %s = ", name)
	start := strings.index(source, prefix)
	if start < 0 {
		return 0, false
	}
	rest := source[start + len(prefix):]
	end := strings.index_byte(rest, ';')
	if end < 0 {
		return 0, false
	}
	return strconv.parse_f32(rest[:end])
}

// Work item 0304: arrival_wake.fs declares every uniform
// draw_arrival_wake sets, by type.
@(test)
test_the_wake_shader_takes_its_uniforms :: proc(t: ^testing.T) {
	source := #load("../data/shaders/arrival_wake.fs", string)
	floats := [?]string{"heat", "seconds", "flicker", "calm", "flame_seed", "layer", "opacity_scale", "circumference_cells", "half_light_cells", "length_cells"}
	vectors := [?]string{"eye_position", "wake_origin", "wake_axis", "haze_color", "ablator_color", "hot_color", "core_color"}
	for name in floats {
		declaration := fmt.tprintf("\nuniform float %s;\n", name)
		testing.expectf(t, strings.contains(source, declaration), "arrival_wake.fs does not declare %s", strings.trim_space(declaration))
	}
	for name in vectors {
		declaration := fmt.tprintf("\nuniform vec3 %s;\n", name)
		testing.expectf(t, strings.contains(source, declaration), "arrival_wake.fs does not declare %s", strings.trim_space(declaration))
	}
}

// A function of a shader: from its start (`vec3 spot_light(`) to its
// closing brace; "" without it.
shader_function_text :: proc(source, start: string) -> string {
	offset := strings.index(source, start)
	if offset < 0 {
		return ""
	}
	length := strings.index(source[offset:], "\n}\n")
	if length < 0 {
		return ""
	}
	return source[offset:][:length + 3]
}

// The spot light of a shader; "" without it.
shader_spot_light :: proc(source: string) -> string {
	return shader_function_text(source, "vec3 spot_light(")
}

read_lit_shaders :: proc(t: ^testing.T) -> (field, model: string) {
	directory := platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY)
	field_data, field_error := os.read_entire_file(platform.join_path(directory, "field.fs"), context.temp_allocator)
	testing.expect_value(t, field_error, nil)
	model_data, model_error := os.read_entire_file(platform.join_path(directory, "model.fs"), context.temp_allocator)
	testing.expect_value(t, model_error, nil)
	return string(field_data), string(model_data)
}

// Work item 0297: the field and model shaders take the same torchlight,
// the six spot_ uniforms and spot_light line for line.
@(test)
test_the_lit_shaders_share_the_spot_light :: proc(t: ^testing.T) {
	field, model := read_lit_shaders(t)
	uniforms := [?]string{"uniform vec3 spot_position;", "uniform vec3 spot_direction;", "uniform float spot_cos_inner;", "uniform float spot_cos_outer;", "uniform float spot_range;", "uniform vec3 spot_color;"}
	for uniform in uniforms {
		testing.expectf(t, strings.contains(field, uniform), "field.fs declares %s", uniform)
		testing.expectf(t, strings.contains(model, uniform), "model.fs declares %s", uniform)
	}
	field_spot, model_spot := shader_spot_light(field), shader_spot_light(model)
	testing.expect(t, field_spot != "" && field_spot == model_spot, "spot_light differs between field.fs and model.fs")
	// The cover's shader (0311) is field.fs's twin.
	cover := read_tree_shader(t, "cover.fs")
	for uniform in uniforms {
		testing.expectf(t, strings.contains(cover, uniform), "cover.fs declares %s", uniform)
	}
	testing.expect(t, shader_spot_light(cover) == field_spot, "spot_light differs between cover.fs and field.fs")
}

// Work items 0297 and 0313: the field shader lights by the clock's sun,
// the sky and the bounce in colour, the old ambient and daylight shares
// and the fog colour are gone, and the model shader takes the open sky
// with the flat light to divide out.
@(test)
test_the_field_shader_lights_by_the_sun :: proc(t: ^testing.T) {
	field, model := read_lit_shaders(t)
	testing.expect(t, strings.contains(field, "uniform vec3 sun_direction;"), "field.fs declares the sun")
	testing.expect(t, strings.contains(field, "uniform vec3 sun_color;"), "field.fs declares the sun's light")
	testing.expect(t, strings.contains(field, "uniform vec3 sky_color;"), "field.fs declares the sky's light")
	testing.expect(t, strings.contains(field, "uniform vec3 bounce_color;"), "field.fs declares the bounce")
	testing.expect(t, !strings.contains(field, "sky_ambient"), "field.fs keeps the ambient share")
	testing.expect(t, !strings.contains(field, "uniform float daylight;"), "field.fs keeps the daylight share")
	testing.expect(t, !strings.contains(field, "fog_color"), "field.fs keeps the fog colour")
	testing.expect(t, !strings.contains(field, "ambient_share"), "field.fs keeps no ambient_share")
	testing.expect(t, strings.contains(model, "uniform float outdoor_on;"), "model.fs declares the open sky's switch")
	testing.expect(t, strings.contains(model, "uniform vec3 daylight_tint;"), "model.fs declares the flat light")
}

// Work item 0313: the field and model shaders take the same open sky,
// every uniform of OPEN_SKY_UNIFORM_NAMES and outdoor_light and
// apply_haze line for line.
@(test)
test_the_lit_shaders_share_the_open_sky :: proc(t: ^testing.T) {
	field, model := read_lit_shaders(t)
	tree := read_tree_shader(t, "tree.fs")
	cover := read_tree_shader(t, "cover.fs")
	names := OPEN_SKY_UNIFORM_NAMES
	for name in names {
		vector, scalar := fmt.tprintf("\nuniform vec3 %s;\n", name), fmt.tprintf("\nuniform float %s;\n", name)
		testing.expectf(t, strings.contains(field, vector) || strings.contains(field, scalar), "field.fs declares no %s", name)
		testing.expectf(t, strings.contains(model, vector) || strings.contains(model, scalar), "model.fs declares no %s", name)
		testing.expectf(t, strings.contains(tree, vector) || strings.contains(tree, scalar), "tree.fs declares no %s", name)
		testing.expectf(t, strings.contains(cover, vector) || strings.contains(cover, scalar), "cover.fs declares no %s", name)
	}
	for start in ([?]string{"vec3 outdoor_light(", "vec3 apply_haze("}) {
		field_text, model_text := shader_function_text(field, start), shader_function_text(model, start)
		testing.expectf(t, field_text != "" && field_text == model_text, "%s differs between field.fs and model.fs", start)
		testing.expectf(t, shader_function_text(tree, start) == model_text, "%s differs between tree.fs and model.fs", start)
		testing.expectf(t, shader_function_text(cover, start) == field_text, "%s differs between cover.fs and field.fs", start)
	}
}

// Work item 0354: the sky share scales only the aerial haze, so the end
// fade takes a shaded face to the end colour as it takes a lit one; the
// other three shaders follow through the comparison above.
@(test)
test_the_end_fade_is_full_on_shaded_ground :: proc(t: ^testing.T) {
	field, _ := read_lit_shaders(t)
	haze := shader_function_text(field, "vec3 apply_haze(")
	testing.expect(t, strings.contains(haze, "    vec3 hazed = mix(color, sky, aerial * sky_share);\n"), "field.fs's apply_haze does not scale only the aerial haze by the sky share")
	testing.expect(t, strings.contains(haze, "    return mix(hazed, end_color, smoothstep(fog_start, max(fog_end, fog_start + 1.0), reach));\n"), "field.fs's apply_haze does not end in the full end fade")
	testing.expect(t, !strings.contains(haze, "mix(color, hazed, sky_share)"), "field.fs's apply_haze still scales the end fade by the sky share")
}

// Work item 0360: the model shader's flat mode samples texture0 at the
// vertex's texture coordinate and takes the haze on the open sky, and a
// batch vertex (flat without instancing) is its own world position.
@(test)
test_the_flat_mode_takes_the_haze :: proc(t: ^testing.T) {
	vertex := read_tree_shader(t, "model.vs")
	vertex_lines := [?]string {
		"\nin vec2 vertexTexCoord;\n",
		"\nuniform float flat_on;\n",
		"\nout vec2 fragment_texcoord;\n",
		"    fragment_texcoord = vertexTexCoord;\n",
		"    bool batch_vertex = flat_on > 0.5 && instanced_on < 0.5;\n",
		"    fragment_world_position = batch_vertex ? local.xyz : (matModel * local).xyz;\n",
	}
	for line in vertex_lines {
		testing.expectf(t, strings.contains(vertex, line), "model.vs does not hold %s", strings.trim_space(line))
	}
	_, fragment := read_lit_shaders(t)
	for line in ([?]string{"\nin vec2 fragment_texcoord;\n", "\nuniform sampler2D texture0;\n"}) {
		testing.expectf(t, strings.contains(fragment, line), "model.fs does not hold %s", strings.trim_space(line))
	}
	main_text := shader_function_text(fragment, "void main(")
	unlit := "        vec4 unlit = base * texture(texture0, fragment_texcoord);\n"
	hazed := "        finalColor = vec4(outdoor ? apply_haze(unlit.rgb, fragment_world_position, camera_position, 1.0) : unlit.rgb, unlit.a);\n"
	testing.expect(t, strings.contains(main_text, unlit), "model.fs's flat mode does not sample texture0")
	testing.expect(t, strings.contains(main_text, hazed), "model.fs's flat mode does not take the haze")
	outdoor := strings.index(main_text, "    bool outdoor = outdoor_on > 0.5;\n")
	flat := strings.index(main_text, "    if (flat_on > 0.5) {\n")
	testing.expect(t, outdoor >= 0 && flat >= 0 && outdoor < flat, "model.fs does not select outdoor before the flat branch")
	testing.expect(t, !strings.contains(main_text, "finalColor = base;"), "model.fs's flat mode still returns the bare colour")
}

// Work item 0380: field.fs greys the bounce by the vertex's sky light,
// wholly at the sky light a metre into the shade and not at all at the
// open sky's full light, so the open ground is lit as before, and
// outdoor_light takes the bounce from its caller.
@(test)
test_the_field_shader_greys_the_bounce_under_a_roof :: proc(t: ^testing.T) {
	field, _ := read_lit_shaders(t)
	lines := [?]string {
		"\n    float roofed = 1.0 - smoothstep(roof_sky_light_shut, roof_sky_light_open, fragment_color.a * 255.0);\n",
		"\n    vec3 roof_bounce = mix(bounce_color, vec3(dot(bounce_color, luminance_weights)), roofed);\n",
		"\n    vec3 outdoor = fragment_color.a * outdoor_light(normal, normalize(fragment_world_position), sunlit, roof_bounce);\n",
	}
	for line in lines {
		testing.expectf(t, strings.contains(field, line), "field.fs does not hold %s", strings.trim_space(line))
	}
	light := shader_function_text(field, "vec3 outdoor_light(")
	testing.expect(t, strings.has_prefix(light, "vec3 outdoor_light(vec3 normal, vec3 up, float sunlit, vec3 bounce)\n"), "field.fs's outdoor_light does not take the bounce")
	testing.expect(t, strings.contains(light, "mix(bounce, sky_color, upward)"), "field.fs's outdoor_light does not mix the bounce it is given")
	testing.expect(t, !strings.contains(light, "bounce_color"), "field.fs's outdoor_light still reads the planet's bounce")
	shut, shut_found := shader_float_constant(field, "roof_sky_light_shut")
	open, open_found := shader_float_constant(field, "roof_sky_light_open")
	testing.expect(t, shut_found && open_found, "field.fs does not hold the roof's sky light bounds")
	shade := make_field_light_tuning(test_lighting_file(), 1000).spread[FIELD_LIGHT_FULL]
	testing.expectf(t, shut == f32(shade), "the bounce is wholly grey at %v, a metre into the shade is %v", shut, shade)
	testing.expectf(t, open > f32(FIELD_LIGHT_FULL - 1) && open <= f32(FIELD_LIGHT_FULL) - 0.5, "the bounce is wholly the planet's from %v", open)
	testing.expect_value(t, 1 - math.smoothstep(shut, open, f32(FIELD_LIGHT_FULL)), 0)
	testing.expect_value(t, 1 - math.smoothstep(shut, open, shut), 1)
}

// Work item 0328: the four lit shaders take the same sun's shadow, its
// uniforms and sun_shadow_light and sun_shadow_tap_weight line for line,
// with the offset and the bias render_sun_shadows.odin names.
@(test)
test_the_lit_shaders_share_the_sun_shadow :: proc(t: ^testing.T) {
	field, model := read_lit_shaders(t)
	sources := [4]string{field, model, read_tree_shader(t, "tree.fs"), read_tree_shader(t, "cover.fs")}
	names := [4]string{"field.fs", "model.fs", "tree.fs", "cover.fs"}
	uniforms := [?]string{"\nuniform highp sampler2D sun_shadow_map;\n", "\nuniform mat4 sun_shadow_matrix;\n", "\nuniform float sun_shadow_strength;\n", "\nuniform vec4 sun_shadow_shape;\n"}
	for source, index in sources {
		for uniform in uniforms {
			testing.expectf(t, strings.contains(source, uniform), "%s does not declare %s", names[index], strings.trim_space(uniform))
		}
		for start in ([?]string{"float sun_shadow_light(", "float sun_shadow_tap_weight("}) {
			text := shader_function_text(source, start)
			testing.expectf(t, text != "" && text == shader_function_text(model, start), "%s differs between %s and model.fs", start, names[index])
		}
		offset, offset_found := shader_float_constant(source, "sun_shadow_normal_offset_texels")
		testing.expectf(t, offset_found && offset == SUN_SHADOW_NORMAL_OFFSET_TEXELS, "%s's normal offset %v differs from SUN_SHADOW_NORMAL_OFFSET_TEXELS", names[index], offset)
		bias, bias_found := shader_float_constant(source, "sun_shadow_depth_bias_texels")
		testing.expectf(t, bias_found && bias == SUN_SHADOW_DEPTH_BIAS_TEXELS, "%s's depth bias %v differs from SUN_SHADOW_DEPTH_BIAS_TEXELS", names[index], bias)
	}
	names_by_uniform := SUN_SHADOW_UNIFORM_NAMES
	for name in names_by_uniform {
		testing.expectf(t, strings.contains(field, fmt.tprintf(" %s;\n", name)), "field.fs declares no %s", name)
	}
	testing.expect(t, strings.contains(field, fmt.tprintf("\nuniform float %s;\n", FIELD_SUN_SHADOW_UNIFORM)), "field.fs declares the uniform its load checks")
}

// Work item 0328: the depth shader reads the trees' instances where
// draw_mesh_instances puts them and presses a caster nearer the sun than
// the map's near plane onto it.
@(test)
test_the_sun_shadow_shader_presses_casters_onto_the_near_plane :: proc(t: ^testing.T) {
	vertex := read_tree_shader(t, "sun_shadow.vs")
	for line in ([?]string{"\nin mat4 instanceTransform;\n", "\nuniform float instanced_on;\n", "\n    gl_Position.z = max(gl_Position.z, -gl_Position.w);\n"}) {
		testing.expectf(t, strings.contains(vertex, line), "sun_shadow.vs does not hold %s", strings.trim_space(line))
	}
	fragment := read_tree_shader(t, "sun_shadow.fs")
	testing.expect(t, strings.contains(fragment, "\nout vec4 finalColor;\n"), "sun_shadow.fs writes finalColor")
}

// Work item 0311: cover.vs reads the instance's transform where the
// node's buffer puts it and the rank's bits for the parts' lean.
@(test)
test_the_cover_shader_reads_the_instance :: proc(t: ^testing.T) {
	vertex := read_tree_shader(t, "cover.vs")
	testing.expect(t, strings.contains(vertex, "\nin mat4 instanceTransform;\n"), "cover.vs reads instanceTransform")
	testing.expect(t, strings.contains(vertex, "floatBitsToUint(rank)"), "cover.vs hashes the rank's bits")
	testing.expect(t, strings.contains(vertex, "float rank = instanceTransform[0u][3u];"), "cover.vs reads the rank from the bottom row")
	testing.expect_value(t, INSTANCE_TRANSFORM_LOCATION, 9)
	layout := COVER_SHAPE_LAYOUT
	testing.expect_value(t, layout[0].location, 0)
	testing.expect_value(t, layout[1].location, 2)
	testing.expect_value(t, layout[2].location, 3)
}

// Work item 0313: the shaders' haze glow is as narrow as the dome's.
@(test)
test_the_haze_glow_is_the_domes :: proc(t: ^testing.T) {
	field, model := read_lit_shaders(t)
	line := fmt.tprintf("\nconst float haze_sun_exponent = %.1f;\n", HAZE_SUN_EXPONENT)
	testing.expectf(t, strings.contains(field, line), "field.fs does not hold %s", strings.trim_space(line))
	testing.expectf(t, strings.contains(model, line), "model.fs does not hold %s", strings.trim_space(line))
}

// Work item 0307: the field shader reads every tile from the one ground
// atlas by level (textureLod), never by texture() with its derivatives,
// takes the look's uniforms, and field.vs unpacks the packed bytes.
@(test)
test_the_field_shader_reads_the_ground_atlas_by_level :: proc(t: ^testing.T) {
	fragment := #load("../data/shaders/field.fs", string)
	vertex := #load("../data/shaders/field.vs", string)
	testing.expect(t, strings.contains(fragment, "\nuniform sampler2D ground_atlas;\n"), "field.fs does not declare the ground atlas")
	// The one ground atlas, and the sun's shadow map (0328).
	testing.expect_value(t, strings.count(fragment, "sampler2D"), 2)
	testing.expect(t, strings.contains(fragment, "\nuniform highp sampler2D sun_shadow_map;\n"), "field.fs's second sampler is the sun's shadow map")
	testing.expect(t, !strings.contains(fragment, "texture("), "field.fs reads a texture with derivatives")
	testing.expect(t, strings.contains(fragment, "textureLod(ground_atlas,"), "field.fs reads the atlas by level")
	for declaration in ([?]string{"\nuniform float ground_look_on;\n", "\nuniform vec3 sand_color;\n", "\nuniform vec3 snow_color;\n"}) {
		testing.expectf(t, strings.contains(fragment, declaration), "field.fs does not declare %s", strings.trim_space(declaration))
	}
	testing.expect(t, strings.contains(vertex, "\nvec3 unpack_bytes(float packed_bytes)\n"), "field.vs does not declare unpack_bytes")
}

// Work item 0381: field.vs draws from the pass's anchor: one matrix for
// the pass and the node's offset in whole samples added to the position,
// the sum kept invariant, the world position from the node's origin and
// the spacing, and no raylib matrix.
@(test)
test_the_field_pass_draws_from_its_anchor :: proc(t: ^testing.T) {
	vertex := #load("../data/shaders/field.vs", string)
	invariant := strings.index(vertex, "\ninvariant gl_Position;\n")
	main_start := strings.index(vertex, "\nvoid main()\n")
	testing.expect(t, invariant >= 0 && main_start > invariant, "field.vs does not declare gl_Position invariant before main")
	lines := [?]string {
		"\nuniform mat4 field_view_projection;\n",
		"\nuniform vec3 node_offset;\n",
		"\nuniform vec3 node_origin;\n",
		"\nuniform float metres_per_sample;\n",
		"\n    gl_Position = field_view_projection * vec4(vertexPosition + node_offset, 1.0);\n",
		"\n    fragment_world_position = node_origin + vertexPosition * metres_per_sample;\n",
		"\n    fragment_normal = vertexNormal;\n",
	}
	for line in lines {
		testing.expectf(t, strings.contains(vertex, line), "field.vs does not hold %s", strings.trim_space(line))
	}
	for line in ([?]string{"uniform mat4 mvp;", "uniform mat4 matModel;"}) {
		testing.expectf(t, !strings.contains(vertex, line), "field.vs still holds %s", line)
	}
	names := FIELD_ANCHOR_UNIFORM_NAMES
	for name in names {
		testing.expectf(t, strings.contains(vertex, fmt.tprintf(" %s;\n", name)), "field.vs declares no %s", name)
	}
}

// Work item 0307: field.fs's atlas constants are the Odin ones.
@(test)
test_the_field_shader_knows_the_atlas_layout :: proc(t: ^testing.T) {
	fragment := #load("../data/shaders/field.fs", string)
	lines := [?]string {
		fmt.tprintf("const uint ground_tile_count = %du;", FIELD_GROUND_TILE_COUNT),
		fmt.tprintf("const uint strata_tile_count = %du;", FIELD_MATERIAL_TILE_COUNT),
		fmt.tprintf("const uint grass_tile = %du;", field_look_tile(.Grass)),
		fmt.tprintf("const uint sand_tile = %du;", field_look_tile(.Sand)),
		fmt.tprintf("const uint snow_tile = %du;", field_look_tile(.Snow)),
		fmt.tprintf("const uint atlas_columns = %du;", FIELD_GROUND_ATLAS_COLUMNS),
		fmt.tprintf("const float atlas_cell_texels = %.1f;", f32(FIELD_GROUND_ATLAS_CELL_TEXELS)),
		fmt.tprintf("const float atlas_texels = %.1f;", f32(FIELD_GROUND_ATLAS_TEXELS)),
		fmt.tprintf("const float tile_texels = %.1f;", f32(ATLAS_TILE_SIZE)),
		fmt.tprintf("const float tile_margin_texels = %.1f;", f32(FIELD_GROUND_ATLAS_MARGIN_TEXELS)),
		fmt.tprintf("const float largest_lod = %.1f;", math.log2(f32(ATLAS_TILE_SIZE))),
	}
	for line in lines {
		testing.expectf(t, strings.contains(fragment, strings.concatenate({"\n", line, "\n"}, context.temp_allocator)), "field.fs does not hold %s", line)
	}
}
