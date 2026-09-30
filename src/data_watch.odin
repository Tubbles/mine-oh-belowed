package game

import "core:fmt"
import "core:path/filepath"
import "core:strings"
import "core:time"
import fsw "shared:fsw"
import "model_vox"
import "platform"

// Watching the data directory while the game runs (work items 0054 and
// 0111). The operating system reports the changes (inotify on Linux,
// ReadDirectoryChangesW on Windows) through the vendored odin-fsw
// (shared/fsw); nothing is scanned or stat'ed. Every frame the main thread
// takes the events since the frame before, and a file added, changed,
// renamed or removed marks its category. Presentation files (strings,
// bindings, developer kits, shaders, fonts, models, textures, sounds, the
// UI theme and icons) reload in place at once (hot_reload.odin). Content
// files only mark the data as changed, shown on the Developer screen and
// in the log, until a reload is asked for (the reload command, the
// Developer screen, F8), or, with watch_data all, once a second passes
// without another content event, so a half saved file is not loaded.
// A watcher that cannot be opened logs one line and leaves the watch off
// for the run.
// The simulation never sees the watcher: reloads run between frames.

DATA_WATCH_CONTENT_SETTLE :: 1 * time.Second
CHUNK_SHADER_DIRECTORY :: "shaders"

// The watch_data setting and --watch-data.
Watch_Data_Mode :: enum u8 {
	// Presentation with developer mode on (--dev or the setting), else off.
	Default,
	Off,
	Presentation,
	// Presentation, and content once its files settle.
	All,
}

Data_File_Category :: enum u8 {
	// Read on demand (blueprints) or not game data (editor backups).
	Ignored,
	// game.sjson: the tick rate and starting items apply at the next start.
	Restart,
	Strings,
	Bindings,
	Developer_Kits,
	Shaders,
	// fonts/fonts.sjson and the font files under fonts/ (ui_font.odin).
	Fonts,
	// The .vox files under models/ (model_vox.odin).
	Models,
	// The .png files under textures/blocks/ and textures/items/
	// (render_atlas.odin, render_icons.odin) and
	// textures/procedural.sjson (texture_generate.odin).
	Textures,
	// sounds/sounds.sjson and the .wav files under sounds/ (audio.odin).
	Sounds,
	// ui/theme.sjson and the .png files under ui/icons/ (ui_theme.odin,
	// render_icons.odin).
	Theme,
	Content,
}

Data_File_Categories :: bit_set[Data_File_Category]

PRESENTATION_CATEGORIES :: Data_File_Categories{.Strings, .Bindings, .Developer_Kits, .Shaders, .Fonts, .Models, .Textures, .Sounds, .Theme}

Data_Watch :: struct {
	// Recursive over the data directory while open is set.
	watcher:            fsw.Watcher_Recursive,
	open:               bool,
	// The watcher could not be opened; no more tries this run.
	unavailable:        bool,
	// Content files changed since the content was last loaded.
	content_changed:    bool,
	// Content files changed and the settle has not passed yet.
	content_settling:   bool,
	last_content_event: time.Time,
}

// "" for the setting's value; the command line names only the three modes.
parse_watch_data_mode :: proc(text: string) -> (mode: Watch_Data_Mode, ok: bool) {
	switch text {
	case "":
		return .Default, true
	case "off":
		return .Off, true
	case "presentation":
		return .Presentation, true
	case "all":
		return .All, true
	}
	return .Default, false
}

// The command line wins over the setting; Default follows developer mode.
effective_watch_data_mode :: proc(command_line, setting: Watch_Data_Mode, developer_mode: bool) -> Watch_Data_Mode {
	chosen := command_line != .Default ? command_line : setting
	if chosen != .Default {
		return chosen
	}
	return developer_mode ? .Presentation : .Off
}

// relative_path uses / between names.
data_file_category :: proc(relative_path: string) -> Data_File_Category {
	directory, name := "", relative_path
	if separator := strings.last_index_byte(relative_path, '/'); separator >= 0 {
		directory, name = relative_path[:separator], relative_path[separator + 1:]
	}
	switch directory {
	case "":
		return top_level_data_file_category(name)
	case STRINGS_DIRECTORY:
		return name == STRINGS_FILE_NAME ? .Strings : .Ignored
	case QUESTS_DIRECTORY:
		return strings.has_suffix(name, QUEST_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Content : .Ignored
	case CHUNK_SHADER_DIRECTORY:
		return is_shader_file_name(name) ? .Shaders : .Ignored
	case FONTS_DIRECTORY:
		return name == FONTS_FILE_NAME ? .Fonts : .Ignored
	case model_vox.MODELS_DIRECTORY:
		return strings.has_suffix(name, model_vox.MODEL_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Models : .Ignored
	case TEXTURES_DIRECTORY:
		return name == PROCEDURAL_TEXTURES_FILE_NAME ? .Textures : .Ignored
	case BLOCK_TEXTURES_DIRECTORY, ITEM_TEXTURES_DIRECTORY:
		return strings.has_suffix(name, TEXTURE_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Textures : .Ignored
	case SOUNDS_DIRECTORY:
		return name == SOUNDS_FILE_NAME || (strings.has_suffix(name, SOUND_FILE_EXTENSION) && !strings.has_prefix(name, ".")) ? .Sounds : .Ignored
	case UI_THEME_DIRECTORY:
		return name == UI_THEME_FILE_NAME ? .Theme : .Ignored
	case UI_ICONS_DIRECTORY:
		return strings.has_suffix(name, TEXTURE_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Theme : .Ignored
	}
	if strings.has_prefix(directory, FONTS_DIRECTORY + "/") {
		return is_font_file_name(name) ? .Fonts : .Ignored
	}
	return .Ignored
}

// The chunk and the water shader pairs (render_chunks.odin,
// render_water.odin).
is_shader_file_name :: proc(name: string) -> bool {
	switch name {
	case "chunk.vs", "chunk.fs", "water.vs", "water.fs":
		return true
	}
	return false
}

is_font_file_name :: proc(name: string) -> bool {
	return !strings.has_prefix(name, ".") && (strings.has_suffix(name, ".ttf") || strings.has_suffix(name, ".otf"))
}

top_level_data_file_category :: proc(name: string) -> Data_File_Category {
	switch name {
	case BINDINGS_FILE_NAME:
		return .Bindings
	case DEVELOPER_KITS_FILE_NAME:
		return .Developer_Kits
	case GAME_CONFIG_FILE_NAME:
		return .Restart
	case BLOCKS_FILE_NAME, ITEMS_FILE_NAME, FLUIDS_FILE_NAME, MACHINES_FILE_NAME, RECIPES_FILE_NAME, TECHNOLOGIES_FILE_NAME, CONTRACTS_FILE_NAME, NOTES_FILE_NAME, BIOMES_FILE_NAME, TREES_FILE_NAME, VEINS_FILE_NAME, TOUCH_OVERLAY_FILE_NAME:
		return .Content
	}
	return .Ignored
}


// Logs a line and leaves the watch off for the run when the operating
// system refuses the watcher.
open_data_watch :: proc(watch: ^Data_Watch, data_directory: string) -> bool {
	watcher, error := fsw.watch_dir_recursive(data_directory)
	if error != .None {
		watch.unavailable = true
		platform.log_printf("%s", data_watch_open_failed_line(data_directory, error))
		return false
	}
	watch.watcher = watcher
	watch.open = true
	return true
}

data_watch_open_failed_line :: proc(directory: string, error: fsw.Error) -> string {
	return fmt.tprintf("data: cannot watch %s: %v", directory, error)
}

// Closes the watcher; a watch that could not be opened stays off.
destroy_data_watch :: proc(watch: ^Data_Watch) {
	if watch.open {
		fsw.destroy(watch.watcher)
	}
	watch^ = {unavailable = watch.unavailable}
}

// The categories of the files touched since the call before.
poll_data_watch :: proc(watch: ^Data_Watch, now: time.Time) -> Data_File_Categories {
	events := fsw.get_events(&watch.watcher, context.temp_allocator)
	changed := data_event_categories(watch.watcher.path, events)
	if .Content in changed {
		watch.content_changed = true
		watch.content_settling = true
		watch.last_content_event = now
	}
	return changed
}

data_event_categories :: proc(watched_directory: string, events: []fsw.Event) -> (changed: Data_File_Categories) {
	for event in events {
		changed += {data_event_category(watched_directory, event)}
	}
	return changed - {.Ignored}
}

// Every event kind counts: editors save through a rename as often as
// through a write.
data_event_category :: proc(watched_directory: string, event: fsw.Event) -> Data_File_Category {
	if event.is_dir {
		return .Ignored
	}
	relative, inside := data_relative_path(watched_directory, event.path)
	return inside ? data_file_category(relative) : .Ignored
}

// fsw reports absolute paths under the absolute watched directory. The
// result uses / between names.
data_relative_path :: proc(directory, path: string) -> (relative: string, inside: bool) {
	prefix := strings.concatenate({directory, filepath.SEPARATOR_STRING}, context.temp_allocator)
	if !strings.has_prefix(path, prefix) {
		return "", false
	}
	relative, _ = strings.replace_all(path[len(prefix):], filepath.SEPARATOR_STRING, "/", context.temp_allocator)
	return relative, true
}

// A whole DATA_WATCH_CONTENT_SETTLE passed since the last content event.
data_watch_content_settled :: proc(watch: Data_Watch, now: time.Time) -> bool {
	return watch.content_settling && time.diff(watch.last_content_event, now) >= DATA_WATCH_CONTENT_SETTLE
}
