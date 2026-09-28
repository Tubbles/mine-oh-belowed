package game

import "core:os"
import "core:strings"
import "core:time"

// Watching the data directory while the game runs (work item 0054). Once
// a second the main thread stats every file under the data directory and
// compares modification time and size with the previous scan; a file
// added, changed or removed marks its category. Presentation files
// (strings, bindings, developer kits, shaders, fonts, models, textures,
// sounds) reload in place at
// once (hot_reload.odin). Content files only mark the data as changed,
// shown on the Developer screen and in the log, until a reload is asked
// for (the reload command, the Developer screen, F8), or, with watch_data
// all, once a poll finds them unchanged again, so a half saved file is
// not loaded.
// The simulation never sees the watcher: reloads run between frames.

DATA_WATCH_INTERVAL :: 1 * time.Second
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
	// (render_atlas.odin, render_icons.odin).
	Textures,
	// sounds/sounds.sjson and the .wav files under sounds/ (audio.odin).
	Sounds,
	Content,
}

Data_File_Categories :: bit_set[Data_File_Category]

PRESENTATION_CATEGORIES :: Data_File_Categories{.Strings, .Bindings, .Developer_Kits, .Shaders, .Fonts, .Models, .Textures, .Sounds}

Data_File_Stamp :: struct {
	modification_time: time.Time,
	size:              i64,
}

Data_Watch :: struct {
	started:          bool,
	last_poll:        time.Time,
	// By path relative to the data directory, with / between names. The
	// keys are owned.
	stamps:           map[string]Data_File_Stamp,
	// Content files changed since the content was last loaded.
	content_changed:  bool,
	// Content files changed in the latest poll.
	content_settling: bool,
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
	case MODELS_DIRECTORY:
		return strings.has_suffix(name, MODEL_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Models : .Ignored
	case BLOCK_TEXTURES_DIRECTORY, ITEM_TEXTURES_DIRECTORY:
		return strings.has_suffix(name, TEXTURE_FILE_EXTENSION) && !strings.has_prefix(name, ".") ? .Textures : .Ignored
	case SOUNDS_DIRECTORY:
		return name == SOUNDS_FILE_NAME || (strings.has_suffix(name, SOUND_FILE_EXTENSION) && !strings.has_prefix(name, ".")) ? .Sounds : .Ignored
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
	case BLOCKS_FILE_NAME, ITEMS_FILE_NAME, FLUIDS_FILE_NAME, MACHINES_FILE_NAME, RECIPES_FILE_NAME, TECHNOLOGIES_FILE_NAME, CONTRACTS_FILE_NAME, BIOMES_FILE_NAME, TREES_FILE_NAME, VEINS_FILE_NAME:
		return .Content
	}
	return .Ignored
}

// Every regular file under directory, in the temp allocator. Directories
// that cannot be read are left out.
scan_data_files :: proc(directory: string) -> map[string]Data_File_Stamp {
	files := make(map[string]Data_File_Stamp, context.temp_allocator)
	scan_data_directory(&files, directory, "")
	return files
}

scan_data_directory :: proc(files: ^map[string]Data_File_Stamp, directory, prefix: string) {
	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if error != nil {
		return
	}
	for entry in entries {
		relative := prefix == "" ? entry.name : strings.concatenate({prefix, "/", entry.name}, context.temp_allocator)
		#partial switch entry.type {
		case .Directory:
			scan_data_directory(files, entry.fullpath, relative)
		case .Regular:
			files[relative] = Data_File_Stamp{entry.modification_time, entry.size}
		}
	}
}

// The categories of the files added, changed or removed between the scans.
changed_data_categories :: proc(previous, current: map[string]Data_File_Stamp) -> (changed: Data_File_Categories) {
	for path, stamp in current {
		if previous_stamp, found := previous[path]; !found || previous_stamp != stamp {
			changed += {data_file_category(path)}
		}
	}
	for path in previous {
		if path not_in current {
			changed += {data_file_category(path)}
		}
	}
	return changed - {.Ignored}
}

destroy_data_watch :: proc(watch: ^Data_Watch) {
	for path in watch.stamps {
		delete(path)
	}
	delete(watch.stamps)
	watch^ = {}
}

replace_data_stamps :: proc(watch: ^Data_Watch, scanned: map[string]Data_File_Stamp) {
	for path in watch.stamps {
		delete(path)
	}
	clear(&watch.stamps)
	for path, stamp in scanned {
		watch.stamps[strings.clone(path)] = stamp
	}
}

// The first call records the files; later ones return what changed since
// the call before.
poll_data_watch :: proc(watch: ^Data_Watch, data_directory: string, now: time.Time) -> Data_File_Categories {
	scanned := scan_data_files(data_directory)
	changed := watch.started ? changed_data_categories(watch.stamps, scanned) : {}
	replace_data_stamps(watch, scanned)
	watch.started = true
	watch.last_poll = now
	if .Content in changed {
		watch.content_changed = true
	}
	watch.content_settling = .Content in changed
	return changed
}

data_watch_poll_due :: proc(watch: Data_Watch, now: time.Time) -> bool {
	return !watch.started || time.diff(watch.last_poll, now) >= DATA_WATCH_INTERVAL
}
