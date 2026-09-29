package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import rl "shared:raylib"

// TrueType fonts at exact pixel sizes (work item 0077). The families come
// from data/fonts/fonts.sjson. Text drawn at text_size UI units is
// rasterised at text_size * pixels_per_unit rounded to a whole pixel size,
// drawn at that size and at whole pixel positions, so every stem covers
// the same number of pixels. Measuring uses the same font at the same
// size, so layout matches what is drawn. Fonts load lazily into a cache
// keyed by family, weight and pixel size; a new UI scale, window height
// or family drops the cache. settings.font picks the UI family and
// settings.monospace_font the diagnostics overlay's. Only this file and
// ui_draw.odin call raylib for text.

FONTS_DIRECTORY :: "fonts"
FONTS_FILE_NAME :: "fonts.sjson"
// raylib's default glyph set: the printable ASCII characters.
FIRST_ASCII_CODE_POINT :: 32
LAST_ASCII_CODE_POINT :: 126

Font_Family :: struct {
	id:        string,
	name_key:  string,
	// File names in the directory named by the id.
	regular:   string,
	bold:      string,
	// Offered for the diagnostics overlay (settings.monospace_font), not
	// as a UI font.
	monospace: bool,
}

Fonts_File :: struct {
	families: []Font_Family,
}

// The families and the arena they live in. A fonts reload keeps the old
// arena until exit, since settings.font may point at an old id.
Loaded_Fonts :: struct {
	families: []Font_Family,
	arena:    ^virtual.Arena,
}

Font_Key :: struct {
	family:     int,
	weight:     Font_Weight,
	pixel_size: i32,
}

Font_Entry :: struct {
	key:  Font_Key,
	font: rl.Font,
}

Font_Cache :: struct {
	// Borrowed from the frame's Loaded_Fonts.
	families:        []Font_Family,
	// Owned.
	fonts_directory: string,
	// The printable ASCII characters and every other code point of
	// strings/en.sjson, sorted. Owned.
	code_points:     []rune,
	// The UI and diagnostics families, and the pixels per unit the entries
	// were made for.
	family:           int,
	monospace_family: int,
	pixels_per_unit:  f32,
	entries:         [dynamic]Font_Entry,
}

// Loading and validation.

// Every key but monospace is required, ids are unique, and there is at
// least one UI family and one monospace family.
validate_font_families :: proc(families: []Font_Family) -> string {
	ui_count, monospace_count := 0, 0
	for family, index in families {
		switch {
		case family.id == "":
			return fmt.tprintf("family %d has no id", index)
		case family.name_key == "":
			return fmt.tprintf("family %s has no name_key", family.id)
		case family.regular == "":
			return fmt.tprintf("family %s has no regular file", family.id)
		case family.bold == "":
			return fmt.tprintf("family %s has no bold file", family.id)
		}
		for other in families[:index] {
			if other.id == family.id {
				return fmt.tprintf("family %s is listed twice", family.id)
			}
		}
		if family.monospace {
			monospace_count += 1
		} else {
			ui_count += 1
		}
	}
	if ui_count == 0 || monospace_count == 0 {
		return "needs at least one family and one family with monospace = true"
	}
	return ""
}

// In the temp allocator.
font_file_path :: proc(fonts_directory: string, family: Font_Family, weight: Font_Weight) -> string {
	file := weight == .Bold ? family.bold : family.regular
	return join_save_path(fonts_directory, family.id, file)
}

missing_font_file :: proc(fonts_directory: string, families: []Font_Family) -> string {
	for family in families {
		for weight in Font_Weight {
			if path := font_file_path(fonts_directory, family, weight); !os.is_file(path) {
				return fmt.tprintf("%s is missing", path)
			}
		}
	}
	return ""
}

// The problem names the file.
load_fonts :: proc(data_directory: string) -> (fonts: Loaded_Fonts, problem: string) {
	fonts_directory := join_save_path(data_directory, FONTS_DIRECTORY)
	path := join_save_path(fonts_directory, FONTS_FILE_NAME)
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, read_error)
	}
	fonts.arena = new_growing_arena()
	if fonts.arena == nil {
		return {}, "cannot reserve memory for the fonts"
	}
	file: Fonts_File
	if error := json.unmarshal(data, &file, .SJSON, virtual.arena_allocator(fonts.arena)); error != nil {
		problem = fmt.tprintf("cannot parse %s: %v", path, error)
	} else if invalid := validate_font_families(file.families); invalid != "" {
		problem = fmt.tprintf("invalid %s: %s", path, invalid)
	} else {
		problem = missing_font_file(fonts_directory, file.families)
	}
	if problem != "" {
		destroy_arena(fonts.arena)
		return {}, problem
	}
	fonts.families = file.families
	return fonts, ""
}

// settings.font picks among the families without monospace,
// settings.monospace_font among those with it.
find_font_family :: proc(families: []Font_Family, id: string, monospace: bool) -> int {
	for family, index in families {
		if family.id == id && family.monospace == monospace {
			return index
		}
	}
	return -1
}

// An unknown id falls back to the first family of the kind.
font_family_index :: proc(families: []Font_Family, id: string, monospace: bool) -> int {
	if index := find_font_family(families, id, monospace); index >= 0 {
		return index
	}
	for family, index in families {
		if family.monospace == monospace {
			return index
		}
	}
	return 0
}

// The id after the current one among the families of the kind, in file
// order, wrapping around.
next_font_family :: proc(families: []Font_Family, id: string, monospace: bool) -> string {
	current := max(find_font_family(families, id, monospace), 0)
	for step in 1 ..= len(families) {
		candidate := families[(current + step) % len(families)]
		if candidate.monospace == monospace {
			return candidate.id
		}
	}
	return id
}

font_family_ids :: proc(families: []Font_Family, monospace: bool) -> string {
	ids := make([dynamic]string, context.temp_allocator)
	for family in families {
		if family.monospace == monospace {
			append(&ids, family.id)
		}
	}
	return strings.join(ids[:], ", ", context.temp_allocator)
}

// The problem names the layer that set the key and the ids it accepts.
font_setting_problem :: proc(key_path, id: string, families: []Font_Family, monospace: bool, provenance: Configuration_Provenance) -> string {
	if find_font_family(families, id, monospace) >= 0 {
		return ""
	}
	return fmt.tprintf("%s: %s is %q, not one of %s", source_of_key_path(provenance, key_path), key_path, id, font_family_ids(families, monospace))
}

font_settings_problem :: proc(settings: Settings, families: []Font_Family, provenance: Configuration_Provenance) -> string {
	if problem := font_setting_problem("settings.font", settings.font, families, false, provenance); problem != "" {
		return problem
	}
	return font_setting_problem("settings.monospace_font", settings.monospace_font, families, true, provenance)
}

// The printable ASCII characters and every other code point in the text,
// sorted and without repeats.
collect_code_points :: proc(text: string, allocator := context.allocator) -> []rune {
	code_points := make([dynamic]rune, allocator)
	for code_point in FIRST_ASCII_CODE_POINT ..= LAST_ASCII_CODE_POINT {
		append(&code_points, rune(code_point))
	}
	for code_point in text {
		if code_point > LAST_ASCII_CODE_POINT && !slice.contains(code_points[:], code_point) {
			append(&code_points, code_point)
		}
	}
	slice.sort(code_points[:])
	return code_points[:]
}

// Sizes and positions.

font_pixel_size :: proc(text_size, pixels_per_unit: f32) -> i32 {
	return max(i32(math.round(text_size * pixels_per_unit)), 1)
}

snap_to_pixel :: proc(position: [2]f32) -> [2]f32 {
	return {math.round(position.x), math.round(position.y)}
}

find_font_entry :: proc(entries: []Font_Entry, key: Font_Key) -> int {
	for entry, index in entries {
		if entry.key == key {
			return index
		}
	}
	return -1
}

// The cache.

// strings_text is the content of strings/en.sjson, scanned for the code
// points to rasterise.
init_font_cache :: proc(cache: ^Font_Cache, data_directory: string, families: []Font_Family, strings_text: string, settings: Settings) {
	cache.fonts_directory = strings.clone(join_save_path(data_directory, FONTS_DIRECTORY))
	cache.families = families
	cache.code_points = collect_code_points(strings_text)
	select_font_families(cache, settings)
}

select_font_families :: proc(cache: ^Font_Cache, settings: Settings) {
	cache.family = font_family_index(cache.families, settings.font, false)
	cache.monospace_family = font_family_index(cache.families, settings.monospace_font, true)
}

drop_font_cache :: proc(cache: ^Font_Cache) {
	for entry in cache.entries {
		rl.UnloadFont(entry.font)
	}
	clear(&cache.entries)
}

destroy_font_cache :: proc(cache: ^Font_Cache) {
	drop_font_cache(cache)
	delete(cache.entries)
	delete(cache.fonts_directory)
	delete(cache.code_points)
	cache^ = {}
}

// New families (a fonts reload) or new code points (a strings reload).
replace_font_cache_sources :: proc(cache: ^Font_Cache, families: []Font_Family, strings_text: string, settings: Settings) {
	drop_font_cache(cache)
	delete(cache.code_points)
	cache.families = families
	cache.code_points = collect_code_points(strings_text)
	select_font_families(cache, settings)
}

// Once a frame after ui_begin: a new family, UI scale or window height
// drops the fonts loaded for the old one.
sync_font_cache :: proc(cache: ^Font_Cache, settings: Settings, pixels_per_unit: f32) {
	family := font_family_index(cache.families, settings.font, false)
	monospace_family := font_family_index(cache.families, settings.monospace_font, true)
	if family != cache.family || monospace_family != cache.monospace_family || pixels_per_unit != cache.pixels_per_unit {
		drop_font_cache(cache)
		cache.pixels_per_unit = pixels_per_unit
		select_font_families(cache, settings)
	}
}

// raylib's padding around each glyph in a TrueType atlas
// (FONT_TTF_DEFAULT_CHARS_PADDING in rtext.c).
FONT_GLYPH_PADDING :: 4

// The font LoadFontEx would build, with the atlas uploaded as RGBA
// (load_rgba_texture): raylib's two-channel atlas relies on a texture
// swizzle Gladio drops, so its glyphs render in red boxes on the phone
// (0106). A zero glyphCount means the file could not be read or has no
// glyphs. UnloadFont frees what this allocates through raylib.
load_font_file :: proc(path: string, pixel_size: i32, code_points: []rune) -> rl.Font {
	path_c := strings.clone_to_cstring(path, context.temp_allocator)
	data_size: i32
	data := rl.LoadFileData(path_c, &data_size)
	if data == nil {
		return {}
	}
	defer rl.UnloadFileData(data)
	font := rl.Font{baseSize = pixel_size, glyphPadding = FONT_GLYPH_PADDING}
	font.glyphs = rl.LoadFontData(data, data_size, pixel_size, raw_data(code_points), i32(len(code_points)), .DEFAULT, &font.glyphCount)
	if font.glyphs == nil || font.glyphCount == 0 {
		return {}
	}
	atlas := rl.GenImageFontAtlas(font.glyphs, &font.recs, font.glyphCount, pixel_size, FONT_GLYPH_PADDING, 0)
	font.texture = load_rgba_texture(atlas)
	rl.UnloadImage(atlas)
	return font
}

// A file raylib cannot read gives its default font, which UnloadFont
// leaves alone. That fallback keeps raylib's two-channel atlas.
load_cached_font :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
	path := font_file_path(cache.fonts_directory, cache.families[key.family], key.weight)
	font := load_font_file(path, key.pixel_size, cache.code_points)
	if font.glyphCount == 0 {
		log_printf("error: cannot load the font %s, drawing with raylib's default", path)
		font = rl.GetFontDefault()
	}
	rl.SetTextureFilter(font.texture, .BILINEAR)
	append(&cache.entries, Font_Entry{key = key, font = font})
	return font
}

cached_font :: proc(cache: ^Font_Cache, key: Font_Key) -> rl.Font {
	if index := find_font_entry(cache.entries[:], key); index >= 0 {
		return cache.entries[index].font
	}
	return load_cached_font(cache, key)
}

// Width in pixels of the text in the font at its own size.
font_text_width :: proc(font: rl.Font, text: string, pixel_size: i32) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(font, text_c, f32(pixel_size), 0).x
}

// Width in UI units of text drawn at size units in the UI family.
measure_font_text :: proc(cache: ^Font_Cache, text: string, size: f32, weight: Font_Weight, pixels_per_unit: f32) -> f32 {
	key := Font_Key{cache.family, weight, font_pixel_size(size, pixels_per_unit)}
	return font_text_width(cached_font(cache, key), text, key.pixel_size) / pixels_per_unit
}

// position is the top left corner in pixels.
draw_font_text :: proc(font: rl.Font, text: string, position: [2]f32, pixel_size: i32, color: rl.Color) {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawTextEx(font, text_c, snap_to_pixel(position), f32(pixel_size), 0, color)
}

// A draw command's text in its box: aligned horizontally, centred
// vertically, in pixels.
draw_ui_text :: proc(cache: ^Font_Cache, command: Draw_Command, box: rl.Rectangle, pixels_per_unit: f32) {
	key := Font_Key{cache.family, command.weight, font_pixel_size(command.text_size, pixels_per_unit)}
	font := cached_font(cache, key)
	width := font_text_width(font, command.text, key.pixel_size)
	x := box.x
	switch command.alignment {
	case .Left:
	case .Centre:
		x += (box.width - width) / 2
	case .Right:
		x += box.width - width
	}
	y := box.y + (box.height - f32(key.pixel_size)) / 2
	draw_font_text(font, command.text, {x, y}, key.pixel_size, to_raylib_color(command.color))
}

// The diagnostics overlay's lines, in the monospace family.
draw_monospace_text :: proc(cache: ^Font_Cache, text: string, x, y, pixel_size: i32, color: rl.Color) {
	if cache == nil || len(cache.families) == 0 {
		return
	}
	key := Font_Key{cache.monospace_family, .Regular, max(pixel_size, 1)}
	draw_font_text(cached_font(cache, key), text, {f32(x), f32(y)}, key.pixel_size, color)
}
