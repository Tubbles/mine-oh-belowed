package game

import "core:strings"
import "generation_seed"
import "platform"

// The Textures screen (work item 0100), the first of the game's editors
// (DESIGN.md, Editors), opened from the Developer screen. Left, the
// procedural textures (texture_generate.odin) by block name; right, a
// preview of the selected one (its tile enlarged beside a field of it,
// each cell varied as the chunk shader varies it), its seed with a
// reroll, one slider per parameter, then Reset, Save and Back.
//
// The screen changes the editor's entries and regenerates their tiles on
// the CPU; it never calls raylib. The frame loop (serve_texture_editor in
// loop.odin) copies every entry's tile into the block atlas each frame
// while the screen is open, so the world behind the panel shows a change
// at once, reads the files again when asked, and writes the overrides
// file on Save.

TEXTURE_EDITOR_PANEL_WIDTH :: 1180
TEXTURE_EDITOR_LIST_WIDTH :: 300
// The preview image: the tile enlarged to a field's size, a transparent
// gap, then the field of PREVIEW_CELLS by PREVIEW_CELLS tiles, one image
// pixel per texel.
TEXTURE_EDITOR_PREVIEW_CELLS :: 6
TEXTURE_EDITOR_FIELD_TEXELS :: TEXTURE_EDITOR_PREVIEW_CELLS * ATLAS_TILE_SIZE
TEXTURE_EDITOR_PREVIEW_GAP :: 8
TEXTURE_EDITOR_PREVIEW_WIDTH :: 2 * TEXTURE_EDITOR_FIELD_TEXELS + TEXTURE_EDITOR_PREVIEW_GAP
TEXTURE_EDITOR_PREVIEW_HEIGHT :: TEXTURE_EDITOR_FIELD_TEXELS
// Screen pixels per field texel the preview asks for, and the share of
// the right column's height it may take for them.
TEXTURE_EDITOR_PIXELS_PER_TEXEL :: 3
TEXTURE_EDITOR_PREVIEW_HEIGHT_SHARE :: 0.45
// The seed row, then one slider per parameter besides the seed.
TEXTURE_EDITOR_CONTROL_ROWS :: len(Ore_Texture_Parameter)
TEXTURE_EDITOR_SELECTED_MARKER_WIDTH :: 6
// Reset, Save and Back, stacked under the list.
TEXTURE_EDITOR_BUTTON_COUNT :: 3
// Mixed into the reroll's hash, so it differs from the generator's.
TEXTURE_REROLL_KEY :: 0x7265_726f_6c6c

@(rodata)
ore_texture_parameter_label_keys := [Ore_Texture_Parameter]string {
	.Seed         = "texture_editor_seed",
	.Share        = "texture_editor_share",
	.Blob_Width   = "texture_editor_blob_width",
	.Crystal_Size = "texture_editor_crystal_size",
	.Stone_Grain  = "texture_editor_stone_grain",
	.Stone_Mottle = "texture_editor_stone_mottle",
	.Ore_Grain    = "texture_editor_ore_grain",
	.Rim_Strength = "texture_editor_rim_strength",
}

Texture_Editor_Entry :: struct {
	// The block's id in blocks.sjson, owned: a content reload renumbers
	// the blocks, the name finds the entry again.
	block_name: string,
	block:      Block_Id,
	kind:       Procedural_Texture_Kind,
	parameters: Ore_Texture_Parameters,
	// The data file's entry, what Reset returns to.
	defaults:   Ore_Texture_Parameters,
	// Changed in this run since the files were read or saved: a reload
	// of the files keeps these parameters.
	edited:     bool,
	tile:       Tile_Pixels,
}

Texture_Editor :: struct {
	entries:           [dynamic]Texture_Editor_Entry,
	selected:          int,
	// Bumped whenever the preview's pixels change: its image revision.
	revision:          u64,
	// TEXTURE_EDITOR_PREVIEW_WIDTH by TEXTURE_EDITOR_PREVIEW_HEIGHT, owned.
	preview:           []Ui_Color,
	// Set by the Developer screen's button: the frame loop reads the files
	// again before the next frame's screens.
	refresh_requested: bool,
	// Set by the Save button, served by the frame loop.
	save_requested:    bool,
}

destroy_texture_editor_entries :: proc(entries: ^[dynamic]Texture_Editor_Entry) {
	for entry in entries {
		delete(entry.block_name)
	}
	delete(entries^)
}

destroy_texture_editor :: proc(editor: ^Texture_Editor) {
	destroy_texture_editor_entries(&editor.entries)
	delete(editor.preview)
	editor^ = {}
}

find_texture_editor_entry :: proc(entries: []Texture_Editor_Entry, block_name: string) -> (entry: Texture_Editor_Entry, found: bool) {
	for candidate in entries {
		if candidate.block_name == block_name {
			return candidate, true
		}
	}
	return {}, false
}

// Every entry still names its block under its id: false after a content
// reload renumbered or removed one.
texture_editor_matches_registry :: proc(editor: Texture_Editor, registry: Block_Registry) -> bool {
	for entry in editor.entries {
		if int(entry.block) >= len(registry.definitions) || registry.definitions[entry.block].id != entry.block_name {
			return false
		}
	}
	return true
}

texture_editor_entry_tile :: proc(block: Block_Id, kind: Procedural_Texture_Kind, parameters: Ore_Texture_Parameters, registry: Block_Registry) -> Tile_Pixels {
	entries := [1]Procedural_Texture{{block = block, kind = kind, parameters = parameters}}
	return generate_procedural_tile(entries[:], registry, block).? or_else {}
}

// The edits file's entries, none when path is "" or the file is missing
// or refused (logged).
read_texture_edits :: proc(edits_path: string, registry: Block_Registry) -> []Procedural_Texture {
	if edits_path == "" {
		return nil
	}
	edits, _, problem := read_procedural_textures_file(edits_path, registry)
	if problem != "" {
		platform.log_printf("error: %s, the texture edits are ignored", problem)
		return nil
	}
	return edits
}

// Reads the data file and the edits file again: the data file's entries
// are the defaults, the edits file's over them the parameters, except
// where an entry was edited in this run, which keeps its parameters. The
// selection stays in range.
load_texture_editor :: proc(editor: ^Texture_Editor, data_directory, edits_path: string, registry: Block_Registry) {
	defaults := load_procedural_textures(data_directory, "", registry)
	loaded := merge_procedural_textures(defaults, read_texture_edits(edits_path, registry), context.temp_allocator)
	entries := make([dynamic]Texture_Editor_Entry, 0, len(loaded))
	for texture in loaded {
		name := registry.definitions[texture.block].id
		entry := Texture_Editor_Entry{block_name = strings.clone(name), block = texture.block, kind = texture.kind, parameters = texture.parameters, defaults = texture.parameters}
		if default_texture, found := find_procedural_texture(defaults, texture.block); found {
			entry.defaults = default_texture.parameters
		}
		if kept, found := find_texture_editor_entry(editor.entries[:], name); found && kept.edited {
			entry.parameters, entry.edited = kept.parameters, true
		}
		entry.tile = texture_editor_entry_tile(entry.block, entry.kind, entry.parameters, registry)
		append(&entries, entry)
	}
	destroy_texture_editor_entries(&editor.entries)
	editor.entries = entries
	editor.selected = clamp(editor.selected, 0, max(len(entries) - 1, 0))
	if editor.preview == nil {
		editor.preview = make([]Ui_Color, TEXTURE_EDITOR_PREVIEW_WIDTH * TEXTURE_EDITOR_PREVIEW_HEIGHT)
	}
	paint_texture_editor_preview(editor)
}

// One line per entry in the data file's form, in the temp allocator.
texture_editor_lines :: proc(entries: []Texture_Editor_Entry) -> []string {
	lines := make([]string, len(entries), context.temp_allocator)
	for entry, index in entries {
		lines[index] = format_procedural_texture_entry(entry.block_name, entry.kind, entry.parameters)
	}
	return lines
}

// The seed one step left (down) or right (up), wrapping inside its range.
step_texture_seed :: proc(seed: int, direction: Ui_Direction) -> int {
	count := int(ore_texture_parameter_ranges[.Seed].maximum) + 1
	#partial switch direction {
	case .Left:
		return ((seed - 1) % count + count) % count
	case .Right:
		return (seed + 1) % count
	}
	return seed
}

// A new seed from the tick and the old seed: pure, so the same press on
// the same tick gives the same seed.
reroll_texture_seed :: proc(tick: u64, seed: int) -> int {
	count := u64(ore_texture_parameter_ranges[.Seed].maximum) + 1
	return int(generation_seed.hash_u64(tick ~ (u64(seed) << 32) ~ TEXTURE_REROLL_KEY) % count)
}

// Where a field pixel reads the tile: its cell's hash and the texel the
// chunk shader samples for a top face at (cell x, 0, cell y), turned,
// mirrored and slid through varied_tile_texcoord.
texture_field_source :: proc(x, y: int) -> (texel: [2]int, hash: u32) {
	cell := [2]int{x, y} / ATLAS_TILE_SIZE
	hash = texture_variation_hash({i32(cell.x), 0, i32(cell.y)})
	inside := [2]f32{f32(x % ATLAS_TILE_SIZE), f32(y % ATLAS_TILE_SIZE)}
	varied := varied_tile_texcoord((inside + 0.5) / ATLAS_TILE_SIZE, hash, .Full)
	return {int(varied.x * ATLAS_TILE_SIZE), int(varied.y * ATLAS_TILE_SIZE)}, hash
}

// A field pixel with its cell's brightness jitter.
texture_field_pixel :: proc(tile: Tile_Pixels, x, y: int) -> Ui_Color {
	texel, hash := texture_field_source(x, y)
	return Ui_Color(shaded_texel(tile[texel_index(texel.x, texel.y)].rgb, 0, texture_variation_brightness(hash)))
}

// The preview's pixel: the tile enlarged on the left, the gap, the field
// on the right.
texture_preview_pixel :: proc(tile: Tile_Pixels, x, y: int) -> Ui_Color {
	field_x := x - TEXTURE_EDITOR_FIELD_TEXELS - TEXTURE_EDITOR_PREVIEW_GAP
	switch {
	case x < TEXTURE_EDITOR_FIELD_TEXELS:
		return Ui_Color(tile[texel_index(x / TEXTURE_EDITOR_PREVIEW_CELLS, y / TEXTURE_EDITOR_PREVIEW_CELLS)])
	case field_x >= 0:
		return texture_field_pixel(tile, field_x, y)
	}
	return {}
}

paint_texture_editor_preview :: proc(editor: ^Texture_Editor) {
	editor.revision += 1
	if len(editor.entries) == 0 || len(editor.preview) == 0 {
		return
	}
	tile := editor.entries[editor.selected].tile
	for &pixel, index in editor.preview {
		pixel = texture_preview_pixel(tile, index % TEXTURE_EDITOR_PREVIEW_WIDTH, index / TEXTURE_EDITOR_PREVIEW_WIDTH)
	}
}

// After the selected entry's parameters changed.
apply_texture_editor_change :: proc(editor: ^Texture_Editor, registry: Block_Registry) {
	entry := &editor.entries[editor.selected]
	entry.edited = true
	entry.tile = texture_editor_entry_tile(entry.block, entry.kind, entry.parameters, registry)
	paint_texture_editor_preview(editor)
}

// The preview's height in UI units: TEXTURE_EDITOR_PIXELS_PER_TEXEL
// screen pixels per field texel where the column allows.
texture_preview_height :: proc(area: Ui_Rectangle, pixels_per_unit: f32) -> f32 {
	wanted := f32(TEXTURE_EDITOR_FIELD_TEXELS * TEXTURE_EDITOR_PIXELS_PER_TEXEL) / max(pixels_per_unit, 0.01)
	fitting_width := area.width * TEXTURE_EDITOR_PREVIEW_HEIGHT / TEXTURE_EDITOR_PREVIEW_WIDTH
	return min(wanted, area.height * TEXTURE_EDITOR_PREVIEW_HEIGHT_SHARE, fitting_width)
}

texture_editor_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	editor := screen_context.texture_editor
	if editor == nil {
		pop_screen(&state.screens)
		return
	}
	// No backdrop, and the panel against the left of the safe area, so the
	// world shows to its right as the edits land.
	area := ui_panel_area(state)
	panel := Ui_Rectangle{area.x, area.y, min(f32(TEXTURE_EDITOR_PANEL_WIDTH), area.width), area.height}
	ui_panel_begin(state, "texture_editor", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("texture_editor_title"), UI_HEADING_TEXT_SIZE, .Left)
	cut_top(&content, UI_GAP)
	left := cut_left(&content, TEXTURE_EDITOR_LIST_WIDTH)
	cut_left(&content, UI_PADDING)
	// The buttons under the list, so the right column's height goes to
	// the preview and the controls.
	buttons := cut_bottom(&left, f32(TEXTURE_EDITOR_BUTTON_COUNT) * (UI_ROW_HEIGHT + UI_GAP))
	editable := len(editor.entries) > 0 && texture_editor_matches_registry(editor^, screen_context.blocks)
	texture_editor_list(state, left, editor, screen_context.blocks)
	if editable {
		texture_editor_controls(state, content, editor, screen_context)
	} else {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("texture_editor_none"))
	}
	texture_editor_buttons(state, buttons, editor, screen_context.blocks, editable)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Confirm, text("hint_select")}, {.Back, text("hint_back")}}
	ui_glyph_bar_or_back_row(state, hints[:])
}

// One row per texture, the selected one marked in the accent; Confirm or
// a click selects. The rows scroll where the column is short.
texture_editor_list :: proc(state: ^Ui_State, area: Ui_Rectangle, editor: ^Texture_Editor, blocks: Block_Registry) {
	region, rows := scroll_region_begin(state, "texture_list", area, f32(len(editor.entries)) * (UI_ROW_HEIGHT + UI_GAP))
	theme := ui_theme(state)
	for entry, index in editor.entries {
		row := cut_top(&rows, UI_ROW_HEIGHT)
		cut_top(&rows, UI_GAP)
		id := ui_id(state, "texture", index)
		interaction := ui_interact(state, id, row)
		if interaction.activated && index != editor.selected {
			editor.selected = index
			paint_texture_editor_preview(editor)
		}
		widget_background(state, row, id, interaction)
		selected := index == editor.selected
		if selected {
			draw_fill(state, cut_left(&row, TEXTURE_EDITOR_SELECTED_MARKER_WIDTH), theme.colors[.Accent])
		}
		name := int(entry.block) < len(blocks.definitions) ? block_display_name(blocks, entry.block) : entry.block_name
		draw_text_fitted(state, inset(row, UI_PADDING), name, UI_BODY_TEXT_SIZE, .Left, selected ? theme.colors[.Accent] : theme.colors[.Text])
	}
	scroll_region_end(state, region)
}

// The preview above, the seed row and the sliders below it, scrolling
// where the column is short.
texture_editor_controls :: proc(state: ^Ui_State, area: Ui_Rectangle, editor: ^Texture_Editor, screen_context: Screen_Context) {
	content := area
	preview_height := texture_preview_height(content, state.pixels_per_unit)
	preview_row := cut_top(&content, preview_height)
	cut_top(&content, UI_GAP)
	preview := Ui_Rectangle{preview_row.x, preview_row.y, preview_height * TEXTURE_EDITOR_PREVIEW_WIDTH / TEXTURE_EDITOR_PREVIEW_HEIGHT, preview_height}
	draw_image(state, preview, editor.preview, {TEXTURE_EDITOR_PREVIEW_WIDTH, TEXTURE_EDITOR_PREVIEW_HEIGHT}, editor.revision)
	region, rows := scroll_region_begin(state, "texture_controls", content, f32(TEXTURE_EDITOR_CONTROL_ROWS) * (UI_ROW_HEIGHT + UI_GAP))
	entry := &editor.entries[editor.selected]
	changed := texture_seed_row(state, cut_row(&rows), &entry.parameters, screen_context.tick)
	for parameter in Ore_Texture_Parameter {
		if parameter != .Seed {
			changed |= texture_parameter_slider(state, cut_row(&rows), &entry.parameters, parameter)
		}
	}
	scroll_region_end(state, region)
	if changed {
		apply_texture_editor_change(editor, screen_context.blocks)
	}
}

// Reroll on the left, where a step left from the list lands, then the
// seed stepper.
texture_seed_row :: proc(state: ^Ui_State, row: Ui_Rectangle, parameters: ^Ore_Texture_Parameters, tick: u64) -> bool {
	seed := parameters.seed
	if ui_button(state, column_rectangle(row, 3, 0, UI_GAP), text("texture_editor_reroll")) {
		seed = reroll_texture_seed(tick, seed)
	}
	stepper := row
	cut_left(&stepper, column_rectangle(row, 3, 0, UI_GAP).width + UI_GAP)
	seed_text := format_texture_parameter_value(ore_texture_parameter_ranges[.Seed], f64(seed))
	seed = step_texture_seed(seed, ui_stepper(state, stepper, text(ore_texture_parameter_label_keys[.Seed]), seed_text))
	changed := seed != parameters.seed
	parameters.seed = seed
	return changed
}

texture_parameter_slider :: proc(state: ^Ui_State, row: Ui_Rectangle, parameters: ^Ore_Texture_Parameters, parameter: Ore_Texture_Parameter) -> bool {
	range := ore_texture_parameter_ranges[parameter]
	value := f32(ore_texture_parameter(parameters^, parameter))
	slider_range := Slider_Range{f32(range.minimum), f32(range.maximum), f32(range.step)}
	value_text := format_texture_parameter_value(range, f64(value))
	if !ui_slider(state, row, text(ore_texture_parameter_label_keys[parameter]), &value, slider_range, value_text) {
		return false
	}
	before := ore_texture_parameter(parameters^, parameter)
	set_ore_texture_parameter(parameters, parameter, snapped_texture_parameter(range, f64(value)))
	return ore_texture_parameter(parameters^, parameter) != before
}

// Reset (the data file's entry for the selected texture), Save (every
// texture to the overrides file) and Back, one above the other, Back at
// the bottom.
texture_editor_buttons :: proc(state: ^Ui_State, area: Ui_Rectangle, editor: ^Texture_Editor, blocks: Block_Registry, editable: bool) {
	rows := area
	cut_top(&rows, UI_GAP)
	reset, save := cut_row(&rows), cut_row(&rows)
	if editable && ui_button(state, reset, text("texture_editor_reset")) {
		editor.entries[editor.selected].parameters = editor.entries[editor.selected].defaults
		apply_texture_editor_change(editor, blocks)
	}
	if editable && ui_button(state, save, text("texture_editor_save")) {
		editor.save_requested = true
	}
	if ui_button(state, cut_top(&rows, UI_ROW_HEIGHT), text("texture_editor_back")) {
		pop_screen(&state.screens)
	}
}
