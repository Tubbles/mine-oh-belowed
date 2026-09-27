package game

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// Font tests read the shipped data/fonts; the few that write use a
// temporary directory they create and remove.

test_data_directory :: proc() -> string {
	return join_save_path(#directory, "..", "data")
}

@(test)
test_shipped_fonts_load_and_name_their_strings :: proc(t: ^testing.T) {
	fonts, problem := load_fonts(test_data_directory())
	defer destroy_arena(fonts.arena)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(fonts.families), 20)
	testing.expect_value(t, font_settings_problem(DEFAULT_SETTINGS, fonts.families, nil), "")
	// The default is the first UI family, so an unknown id falls back to it.
	testing.expect_value(t, font_family_index(fonts.families, "", false), find_font_family(fonts.families, DEFAULT_SETTINGS.font, false))
	strings_table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	for family in fonts.families {
		testing.expectf(t, family.name_key in strings_table.entries, "%s has no string", family.name_key)
	}
}

@(test)
test_font_families_are_validated :: proc(t: ^testing.T) {
	valid := Font_Family{id = "sans", name_key = "font_sans", regular = "Sans.ttf", bold = "Sans-Bold.ttf"}
	mono := Font_Family{id = "mono", name_key = "font_mono", regular = "Mono.ttf", bold = "Mono.ttf", monospace = true}
	good := [?]Font_Family{valid, mono}
	testing.expect_value(t, validate_font_families(good[:]), "")
	no_id, no_name, no_regular, no_bold := valid, valid, valid, valid
	no_id.id, no_name.name_key, no_regular.regular, no_bold.bold = "", "", "", ""
	for broken in ([?]Font_Family{no_id, no_name, no_regular, no_bold}) {
		families := [?]Font_Family{broken, mono}
		testing.expect(t, validate_font_families(families[:]) != "")
	}
	twice := [?]Font_Family{valid, valid, mono}
	testing.expect(t, strings.contains(validate_font_families(twice[:]), "twice"))
	only_ui := [?]Font_Family{valid}
	testing.expect(t, validate_font_families(only_ui[:]) != "")
	only_mono := [?]Font_Family{mono}
	testing.expect(t, validate_font_families(only_mono[:]) != "")
}

@(test)
test_fonts_file_with_a_missing_font_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	path := join_save_path(root, FONTS_DIRECTORY, FONTS_FILE_NAME)
	write_test_file(path, `families = [{id = "sans", name_key = "font_sans", regular = "Sans.ttf", bold = "Sans.ttf"} {id = "mono", name_key = "font_mono", regular = "Mono.ttf", bold = "Mono.ttf", monospace = true}]`)
	write_test_file(join_save_path(root, FONTS_DIRECTORY, "sans", "Sans.ttf"), "not read")
	_, problem := load_fonts(root)
	testing.expect(t, strings.contains(problem, "Mono.ttf is missing"), problem)
	write_test_file(path, `families = [{id = "sans"}]`)
	_, problem = load_fonts(root)
	testing.expect(t, strings.contains(problem, "no name_key"), problem)
}

@(test)
test_font_pixel_sizes_and_cache_keys :: proc(t: ^testing.T) {
	testing.expect_value(t, font_pixel_size(UI_BODY_TEXT_SIZE, ui_pixels_per_unit(1080, 1)), 24)
	testing.expect_value(t, font_pixel_size(UI_BODY_TEXT_SIZE, ui_pixels_per_unit(1080, 1.2)), 29)
	testing.expect_value(t, font_pixel_size(UI_BODY_TEXT_SIZE, ui_pixels_per_unit(800, 1)), 18)
	testing.expect_value(t, font_pixel_size(UI_HEADING_TEXT_SIZE, ui_pixels_per_unit(800, 1.5)), 36)
	testing.expect_value(t, font_pixel_size(0.1, 1), 1)
	entries := [?]Font_Entry{{key = {0, .Regular, 24}}, {key = {0, .Bold, 24}}, {key = {1, .Regular, 24}}}
	testing.expect_value(t, find_font_entry(entries[:], {0, .Bold, 24}), 1)
	testing.expect_value(t, find_font_entry(entries[:], {1, .Regular, 24}), 2)
	testing.expect_value(t, find_font_entry(entries[:], {0, .Regular, 29}), -1)
	testing.expect_value(t, text_weight(UI_BODY_TEXT_SIZE), Font_Weight.Regular)
	testing.expect_value(t, text_weight(UI_BODY_TEXT_SIZE, true), Font_Weight.Bold)
	testing.expect_value(t, text_weight(UI_HEADING_TEXT_SIZE), Font_Weight.Bold)
}

@(test)
test_text_positions_snap_to_whole_pixels :: proc(t: ^testing.T) {
	testing.expect_value(t, snap_to_pixel({10.4, 10.6}), [2]f32{10, 11})
	testing.expect_value(t, snap_to_pixel({-0.4, 99.5}), [2]f32{0, 100})
}

@(test)
test_code_points_cover_ascii_and_the_strings :: proc(t: ^testing.T) {
	code_points := collect_code_points("Größe × Größe", context.temp_allocator)
	ascii_count := LAST_ASCII_CODE_POINT - FIRST_ASCII_CODE_POINT + 1
	testing.expect_value(t, len(code_points), ascii_count + 3)
	testing.expect_value(t, code_points[0], ' ')
	testing.expect(t, slice.equal(code_points[ascii_count:], []rune{'×', 'ß', 'ö'}))
}

@(test)
test_font_choices_cycle_within_their_kind :: proc(t: ^testing.T) {
	families := [?]Font_Family{{id = "a"}, {id = "mono", monospace = true}, {id = "b"}, {id = "mono_two", monospace = true}}
	testing.expect_value(t, next_font_family(families[:], "a", false), "b")
	testing.expect_value(t, next_font_family(families[:], "b", false), "a")
	testing.expect_value(t, next_font_family(families[:], "mono", true), "mono_two")
	testing.expect_value(t, next_font_family(families[:], "mono_two", true), "mono")
	testing.expect_value(t, font_family_index(families[:], "unknown", false), 0)
	testing.expect_value(t, font_family_index(families[:], "unknown", true), 1)
	testing.expect_value(t, font_family_index(families[:], "mono", false), 0)
}

@(test)
test_unknown_font_setting_names_the_ids :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_configuration_test_directory()
	defer os.remove_all(root)
	fonts, fonts_problem := load_fonts(test_data_directory())
	defer destroy_arena(fonts.arena)
	testing.expect_value(t, fonts_problem, "")
	loaded, problem := load_configuration(test_environment(root), {"settings.font=nonsense"})
	testing.expect_value(t, problem, "")
	problem = font_settings_problem(loaded.configuration.settings, fonts.families, loaded.provenance)
	testing.expect(t, strings.has_prefix(problem, "command line: settings.font is \"nonsense\", not one of exo_2, titillium_web,"), problem)
	testing.expect(t, !strings.contains(problem, "jetbrains_mono"), problem)
	// A monospace family is no UI font, and the other way round.
	loaded, _ = load_configuration(test_environment(root), {"settings.font=jetbrains_mono"})
	testing.expect(t, font_settings_problem(loaded.configuration.settings, fonts.families, loaded.provenance) != "")
	loaded, _ = load_configuration(test_environment(root), {"settings.monospace_font=exo_2"})
	problem = font_settings_problem(loaded.configuration.settings, fonts.families, loaded.provenance)
	testing.expect(t, strings.contains(problem, "not one of jetbrains_mono, share_tech_mono"), problem)
}

// Big endian reads from a TrueType file; 0 past the end.
font_u16 :: proc(data: []byte, offset: int) -> int {
	if offset < 0 || offset + 2 > len(data) {
		return 0
	}
	return int(data[offset]) << 8 | int(data[offset + 1])
}

font_i16 :: proc(data: []byte, offset: int) -> int {
	return int(i16(u16(font_u16(data, offset))))
}

font_u32 :: proc(data: []byte, offset: int) -> int {
	return font_u16(data, offset) << 16 | font_u16(data, offset + 2)
}

font_table_offset :: proc(data: []byte, tag: string) -> int {
	for index in 0 ..< font_u16(data, 4) {
		record := 12 + index * 16
		if record + 4 <= len(data) && string(data[record:record + 4]) == tag {
			return font_u32(data, record + 8)
		}
	}
	return -1
}

// The glyph of a code point through the Windows Unicode BMP cmap
// (format 4), 0 when it has none.
font_glyph_index :: proc(data: []byte, code_point: rune) -> int {
	cmap := font_table_offset(data, "cmap")
	for index in 0 ..< font_u16(data, cmap + 2) {
		record := cmap + 4 + index * 8
		subtable := cmap + font_u32(data, record + 4)
		if font_u16(data, record) != 3 || font_u16(data, record + 2) != 1 || font_u16(data, subtable) != 4 {
			continue
		}
		segment_count := font_u16(data, subtable + 6) / 2
		ends := subtable + 14
		starts := ends + segment_count * 2 + 2
		deltas := starts + segment_count * 2
		range_offsets := deltas + segment_count * 2
		for segment in 0 ..< segment_count {
			if int(code_point) > font_u16(data, ends + segment * 2) || int(code_point) < font_u16(data, starts + segment * 2) {
				continue
			}
			range_offset_at := range_offsets + segment * 2
			range_offset := font_u16(data, range_offset_at)
			if range_offset == 0 {
				return (int(code_point) + font_i16(data, deltas + segment * 2)) & 0xffff
			}
			glyph := font_u16(data, range_offset_at + range_offset + (int(code_point) - font_u16(data, starts + segment * 2)) * 2)
			return glyph == 0 ? 0 : (glyph + font_i16(data, deltas + segment * 2)) & 0xffff
		}
	}
	return 0
}

// Width of the text at a pixel height the way stb_truetype (inside
// raylib) scales it: the hhea ascent to descent spans the pixel height.
font_file_text_width :: proc(data: []byte, text: string, pixel_height: f32) -> f32 {
	hhea, hmtx := font_table_offset(data, "hhea"), font_table_offset(data, "hmtx")
	scale := pixel_height / f32(font_i16(data, hhea + 4) - font_i16(data, hhea + 6))
	metric_count := font_u16(data, hhea + 34)
	width: f32
	for code_point in text {
		glyph := min(font_glyph_index(data, code_point), metric_count - 1)
		width += f32(i32(f32(font_u16(data, hmtx + glyph * 4)) * scale))
	}
	return width
}

// The headless audit measures with approximate_text_width; the default
// family's real advances must stay within 15 percent of it. raylib's own
// loader cannot run here: the test build does not link X11 (see
// font_file_text_width for the same metrics).
@(test)
test_approximate_width_follows_the_default_font :: proc(t: ^testing.T) {
	fonts, problem := load_fonts(test_data_directory())
	defer destroy_arena(fonts.arena)
	testing.expect_value(t, problem, "")
	family := fonts.families[find_font_family(fonts.families, DEFAULT_SETTINGS.font, false)]
	sample := "Build the furnace, then smelt iron ore into plates. Inventory Settings 1234"
	size :: 100
	for weight in Font_Weight {
		data, error := os.read_entire_file(font_file_path(join_save_path(test_data_directory(), FONTS_DIRECTORY), family, weight), context.temp_allocator)
		testing.expect_value(t, error, nil)
		width := font_file_text_width(data, sample, size)
		approximation := approximate_text_width(sample, size)
		testing.expectf(t, abs(approximation - width) <= width * 0.15, "%v: approximation %v, measured %v", weight, approximation, width)
		testing.expectf(t, width > approximation * 0.9, "%v: measured %v looks unread", weight, width)
	}
}
