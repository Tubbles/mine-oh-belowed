package game

import "core:fmt"
import "core:mem/virtual"
import "core:time"
import "model_vox"
import "platform"

// The frame loop's side of hot reload (work item 0054): the data watcher
// (data_watch.odin) polled between frames, presentation files reloaded in
// place, and the content reload (data_reload.odin) the reload command, the
// Developer screen and F8 ask for. Everything here runs on the main thread
// between frames or between ticks, so text() results and content pointers
// taken within a frame stay valid for that frame. A file that fails to
// load leaves the old data in place and says so in a toast and the log.

// Developer mode from --dev or the setting, like the command socket.
developer_mode_on :: proc(state: ^Frame_State) -> bool {
	return state.content.developer_mode || state.settings.developer_mode
}

// At exit, after the session left.
destroy_hot_reload_state :: proc(state: ^Frame_State) {
	destroy_data_watch(&state.reload.data_watch)
	for arena in state.reload.retired_font_arenas {
		destroy_arena(arena)
	}
	delete(state.reload.retired_font_arenas)
	destroy_arena(state.interaction.fonts.arena)
	for entries in state.reload.retired_strings {
		destroy_string_entries(entries)
	}
	delete(state.reload.retired_strings)
	destroy_arena(state.reload.bindings_arena)
	destroy_arena(state.reload.content_arena)
}

report_reload :: proc(state: ^Frame_State, message: string) {
	platform.log_printf("data: %s", message)
	ui_toast(&state.interaction.ui, message)
}

// Loaders log their own error line too; this one says what was kept.
report_reload_problem :: proc(state: ^Frame_State, what, problem: string) {
	platform.log_printf("error: could not reload %s, keeping the old data: %s", what, problem)
	ui_toast(&state.interaction.ui, fmt.tprintf("%s %s: %s", text("reload_failed"), what, problem))
}

// Presentation.

// The old entries stay until exit: names taken from the table outlive a
// frame in places (the recipe names are refreshed here, others may not
// be), and a table is small.
reload_strings :: proc(state: ^Frame_State) -> string {
	data, path, problem := read_strings_file(state.data_directory)
	if problem != "" {
		return problem
	}
	old_entries, error := replace_string_entries(active_string_table(), data)
	if error != nil {
		return fmt.tprintf("cannot parse %s: %v", path, error)
	}
	append(&state.reload.retired_strings, old_entries)
	refresh_content_names(&state.content, virtual.arena_allocator(state.reload.content_arena))
	// New text may need glyphs the fonts were not loaded with.
	replace_font_cache_sources(&state.interaction.font_cache, state.interaction.fonts.families, string(data), state.settings)
	return ""
}

// The cache drops every font; they load again from the new files. An id
// the new file lacks falls back to the first family of its kind.
reload_fonts :: proc(state: ^Frame_State) -> string {
	fonts, problem := load_fonts(state.data_directory)
	if problem != "" {
		return problem
	}
	append(&state.reload.retired_font_arenas, state.interaction.fonts.arena)
	state.interaction.fonts = fonts
	strings_text, _, _ := read_strings_file(state.data_directory)
	replace_font_cache_sources(&state.interaction.font_cache, fonts.families, string(strings_text), state.settings)
	return ""
}

// The configuration's overrides stay as they were read at start.
reload_bindings :: proc(state: ^Frame_State) -> string {
	arena := new_growing_arena()
	if arena == nil {
		return "cannot reserve memory for the bindings"
	}
	bindings, problem := load_bindings(state.data_directory, state.reload.binding_overrides, virtual.arena_allocator(arena))
	if problem != "" {
		destroy_arena(arena)
		return problem
	}
	state.interaction.bindings = bindings
	state.interaction.input_bindings = make_backend_bindings(bindings, state.interaction.input_backend)
	destroy_arena(state.reload.bindings_arena)
	state.reload.bindings_arena = arena
	return ""
}

// Into the content arena, which frees the old kits with the content.
reload_developer_kits :: proc(state: ^Frame_State) -> string {
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	kits, loaded := load_developer_kits(state.data_directory, state.content.items, virtual.arena_allocator(state.reload.content_arena))
	problem := platform.end_log_capture(&capture, fmt.tprintf("%s did not load", DEVELOPER_KITS_FILE_NAME))
	if !loaded {
		return problem
	}
	state.content.developer_kits = kits
	return ""
}

// Both pairs, the chunk shader and the water shader (work item 0065): a
// pair that does not compile keeps its old shader, the other still
// reloads.
reload_shaders :: proc(state: ^Frame_State) -> string {
	capture: platform.Log_Capture
	platform.begin_log_capture(&capture)
	chunk_reloaded := reload_chunk_shader(&state.presentation.renderer, state.data_directory)
	water_reloaded := reload_water_shader(&state.presentation.renderer.water, state.presentation.renderer.atlas_layout, state.data_directory)
	problem := platform.end_log_capture(&capture, "a shader did not load")
	return chunk_reloaded && water_reloaded ? "" : problem
}

// Every machine's mesh and the player's limbs (work item 0066) are made
// again from the files. A machine model that does not load keeps every
// old machine mesh, a limb that does not load keeps the old player; the
// other still reloads.
reload_models :: proc(state: ^Frame_State) -> string {
	machine_problem := replace_machine_models(&state.presentation.model_renderer, state.content.machines, state.data_directory)
	player_problem := replace_player_model(&state.presentation.player_model, state.data_directory)
	return machine_problem != "" ? machine_problem : player_problem
}

// Both atlases are made again from the files, the block atlas with the
// procedural tiles generated again (texture_generate.odin). The layout
// depends on the block count alone, so the chunk meshes keep their tile
// coordinates. A file that does not load takes its fallback and is
// logged; the rest still load.
reload_textures :: proc(state: ^Frame_State) -> string {
	rebuild_atlases(state)
	return ""
}

// The theme file and the icon atlas (work item 0071). A theme that does
// not load keeps the old theme; the icons load again either way.
reload_theme :: proc(state: ^Frame_State) -> string {
	destroy_item_atlas(&state.presentation.ui_icon_atlas)
	state.presentation.ui_icon_atlas = upload_ui_icon_atlas(state.data_directory)
	theme, problem := load_ui_theme(state.data_directory)
	if problem != "" {
		return problem
	}
	apply_ui_theme(&state.interaction.ui, theme)
	return ""
}

// The table and every file load again; a table that does not load, or
// names a missing file, keeps the old sounds.
reload_sounds :: proc(state: ^Frame_State) -> string {
	return load_mixer_sounds(&state.presentation.audio, state.data_directory, state.content.blocks, state.base_generator.biomes)
}

rebuild_atlases :: proc(state: ^Frame_State) {
	replace_chunk_atlas(&state.presentation.renderer, state.content.blocks, state.data_directory)
	replace_item_atlas(&state.presentation.item_atlas, &state.content.items, state.data_directory)
}

@(rodata)
presentation_reload_keys := [Data_File_Category]string {
	.Ignored        = "",
	.Restart        = "",
	.Strings        = "reload_strings_done",
	.Bindings       = "reload_bindings_done",
	.Developer_Kits = "reload_developer_kits_done",
	.Shaders        = "reload_shaders_done",
	.Fonts          = "reload_fonts_done",
	.Models         = "reload_models_done",
	.Textures       = "reload_textures_done",
	.Sounds         = "reload_sounds_done",
	.Theme          = "reload_theme_done",
	.Content        = "",
}

// What a failed reload's toast names.
@(rodata)
presentation_file_names := [Data_File_Category]string {
	.Ignored        = "",
	.Restart        = "",
	.Strings        = STRINGS_DIRECTORY + "/" + STRINGS_FILE_NAME,
	.Bindings       = BINDINGS_FILE_NAME,
	.Developer_Kits = DEVELOPER_KITS_FILE_NAME,
	.Shaders        = CHUNK_SHADER_DIRECTORY,
	.Fonts          = FONTS_DIRECTORY,
	.Models         = model_vox.MODELS_DIRECTORY,
	.Textures       = "textures",
	.Sounds         = SOUNDS_DIRECTORY,
	.Theme          = UI_THEME_DIRECTORY,
	.Content        = "",
}

reload_presentation :: proc(state: ^Frame_State, category: Data_File_Category) -> string {
	#partial switch category {
	case .Strings:
		return reload_strings(state)
	case .Bindings:
		return reload_bindings(state)
	case .Developer_Kits:
		return reload_developer_kits(state)
	case .Shaders:
		return reload_shaders(state)
	case .Fonts:
		return reload_fonts(state)
	case .Models:
		return reload_models(state)
	case .Textures:
		return reload_textures(state)
	case .Sounds:
		return reload_sounds(state)
	case .Theme:
		return reload_theme(state)
	}
	return ""
}

// Strings first, so the toasts of the others read the new ones.
apply_presentation_changes :: proc(state: ^Frame_State, changed: Data_File_Categories) {
	for category in Data_File_Category {
		if category not_in changed || category not_in PRESENTATION_CATEGORIES {
			continue
		}
		if problem := reload_presentation(state, category); problem != "" {
			report_reload_problem(state, presentation_file_names[category], problem)
		} else {
			report_reload(state, text(presentation_reload_keys[category]))
		}
	}
}

// The data edits overlay (work item 0129, read_data_file) is not
// watched: a change to it comes through here, from the Data files
// screen's Discard (and 0130's Save), whose categories serve_data_browser
// returns, and does what the watcher does for the same files in the data
// directory. A presentation file reloads in place, a content file asks
// for the content reload, game.sjson says a restart is needed.
apply_data_edit_change :: proc(state: ^Frame_State, changed: Data_File_Categories) {
	apply_presentation_changes(state, changed)
	if .Content in changed {
		state.reload.reload_requested = true
	}
	if .Restart in changed {
		report_reload(state, text("reload_restart_needed"))
	}
}

// The watcher.

// Every frame while watching is on, the events since the frame before.
// Content changes are only announced, except with watch_data all, where a
// second without another content event asks for the reload.
update_data_watch :: proc(state: ^Frame_State) {
	watch := &state.reload.data_watch
	mode := effective_watch_data_mode(state.reload.watch_data_flag, state.settings.watch_data, developer_mode_on(state))
	if mode == .Off {
		if watch.open {
			destroy_data_watch(watch)
		}
		return
	}
	if !watch.open && (watch.unavailable || !open_data_watch(watch, state.data_directory)) {
		return
	}
	now := time.now()
	content_was_changed := watch.content_changed
	changed := poll_data_watch(watch, now)
	apply_presentation_changes(state, changed)
	if .Restart in changed {
		report_reload(state, text("reload_restart_needed"))
	}
	if .Content in changed && !content_was_changed {
		report_reload(state, text("reload_content_changed"))
	}
	if data_watch_content_settled(watch^, now) {
		watch.content_settling = false
		if mode == .All && watch.content_changed {
			state.reload.reload_requested = true
		}
	}
}

// Content.

// The new content replaces the frame's; the old arena goes once nothing
// points into it: the session was rebuilt already, and the renderers
// that were made from the content (block and item atlases, belts, machine
// models) are made again.
replace_frame_content :: proc(state: ^Frame_State, data: Game_Data) {
	old_arena := state.reload.content_arena
	state.content = data.content
	state.interaction.touch_overlay = release_touch_latches(state.interaction.touch_overlay)
	state.base_generator = data.base_generator
	state.reload.content_arena = data.arena
	rebuild_atlases(state)
	destroy_belt_renderer(&state.presentation.belt_renderer)
	state.presentation.belt_renderer = init_belt_renderer(state.content.machines)
	use_machine_models(&state.presentation.model_renderer, state.content.machines, state.data_directory)
	destroy_arena(old_arena)
	state.reload.data_watch.content_changed = false
	state.reload.data_watch.content_settling = false
}

// Loads and validates every content file, then rebuilds the session under
// the new data (reload_session). The answer for the command, or the
// problem; either is also logged and toasted. On a problem everything
// stays as it was.
reload_content :: proc(state: ^Frame_State) -> (summary: string, problem: string) {
	data: Game_Data
	data, problem = load_game_data(state.data_directory, state.config, global_string_table.entries)
	if problem == "" {
		data.content.unlock_all = state.content.unlock_all
		data.content.developer_mode = state.content.developer_mode
		changes := content_table_changes(content_tables(state.content.simulation_content), content_tables(data.content.simulation_content))
		summary = content_changes_text(changes)
		if state.session != nil {
			problem = reload_session(state.session, state.content, data, state.config)
		}
	}
	if problem != "" {
		destroy_game_data(&data)
		report_reload_problem(state, text("reload_content"), problem)
		return "", problem
	}
	replace_frame_content(state, data)
	if state.session != nil {
		summary = fmt.tprintf("%s. %s", summary, text("reload_chunks_note"))
	}
	report_reload(state, fmt.tprintf("%s %s", text("reload_content_done"), summary))
	return summary, ""
}

// F8 in developer mode, the Developer screen's button and watch_data all.
apply_reload_request :: proc(state: ^Frame_State) {
	if !state.reload.reload_requested {
		return
	}
	state.reload.reload_requested = false
	reload_content(state)
}

command_reload :: proc(state: ^Frame_State) -> Command_Response {
	summary, problem := reload_content(state)
	if problem != "" {
		return command_error("%s", problem)
	}
	return command_ok("reloaded: %s", summary)
}
