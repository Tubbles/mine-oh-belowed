package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

// The export of the data files and the data edits (work item 0131), for
// reading them outside the phone (a Syncthing folder): the Data files
// screen's Export copies every file under the data directory to
// <export_directory>/data/ and every copy in the data edits overlay to
// <export_directory>/data_edits/, overwriting and deleting nothing, then
// writes export.txt with the build stamp and the time. With
// export_on_save, a save or a discard of a data edit writes or deletes its
// one copy under data_edits/ as well (one way: nothing is read back). The
// frame loop runs both between frames (serve_data_browser). On Android the
// export needs All files access (export_access_android.odin).

DATA_EXPORT_DATA_DIRECTORY :: "data"
DATA_EXPORT_EDITS_DIRECTORY :: "data_edits"
DATA_EXPORT_STAMP_FILE :: "export.txt"

// One file to copy.
Data_Export_Copy :: struct {
	source:      string,
	destination: string,
	// An overlay copy, counted apart from the data files.
	edit:        bool,
}

Data_Export_Result :: struct {
	data_count: int,
	edit_count: int,
	// The first problem, the path in it; "" when everything was written.
	problem:    string,
}

// The copies of an export: every data file to data/, every overlay copy
// to data_edits/, each at its relative path. In the temp allocator.
data_export_copies :: proc(data_files, edit_files: []Data_File_Entry, data_directory, edits_directory, export_directory: string) -> []Data_Export_Copy {
	copies := make([dynamic]Data_Export_Copy, 0, len(data_files) + len(edit_files), context.temp_allocator)
	for entry in data_files {
		append(&copies, data_export_copy(data_directory, export_directory, DATA_EXPORT_DATA_DIRECTORY, entry.path, false))
	}
	for entry in edit_files {
		append(&copies, data_export_copy(edits_directory, export_directory, DATA_EXPORT_EDITS_DIRECTORY, entry.path, true))
	}
	return copies[:]
}

data_export_copy :: proc(source_directory, export_directory, subdirectory, relative_path: string, edit: bool) -> Data_Export_Copy {
	return Data_Export_Copy {
		source = join_save_path(source_directory, relative_path),
		destination = join_save_path(export_directory, subdirectory, relative_path),
		edit = edit,
	}
}

// export.txt: what wrote the export and when, in UTC.
data_export_stamp_text :: proc(build_stamp: string, now: time.Time, result: Data_Export_Result) -> string {
	date_time, _ := time.time_to_datetime(now)
	return fmt.tprintf(
		"Mine oh Belowed %s\nexported %04d-%02d-%02d %02d:%02d:%02d UTC\n%d data files, %d data edits\n",
		build_stamp,
		date_time.year,
		date_time.month,
		date_time.day,
		date_time.hour,
		date_time.minute,
		date_time.second,
		result.data_count,
		result.edit_count,
	)
}

// The overlay's files, none without an overlay directory (no edit saved
// yet).
list_data_edit_files :: proc(edits_directory: string) -> []Data_File_Entry {
	if edits_directory == "" || !os.is_dir(edits_directory) {
		return nil
	}
	return list_data_files(edits_directory, "")
}

// A leading ~/ against the home directory, as the configuration's path
// values; the path as it is otherwise, and without a home. In the temp
// allocator.
expand_home_path :: proc(path, home: string) -> string {
	if home == "" || !strings.has_prefix(path, "~/") {
		return path
	}
	return join_save_path(home, path[2:])
}

// The path made absolute against the working directory and cleaned (no
// ., .. or doubled separators); symbolic links stay as they are. In the
// temp allocator.
absolute_clean_path :: proc(path, working_directory: string) -> string {
	absolute := os.is_absolute_path(path) ? path : join_save_path(working_directory, path)
	cleaned, _ := os.clean_path(absolute, context.temp_allocator)
	return cleaned
}

// Whether the cleaned absolute inner path is the outer one or lies inside
// it.
path_is_within :: proc(inner, outer: string) -> bool {
	if !strings.has_prefix(inner, outer) {
		return false
	}
	rest := inner[len(outer):]
	return rest == "" || os.is_path_separator(rest[0]) || os.is_path_separator(outer[len(outer) - 1])
}

// Why the export directory cannot take an export, "" when it can: it must
// be absolute and lie outside the data and the edits directories, and
// neither may lie inside it, since a copy onto its own source (os opens
// the destination truncated) would empty the file. The paths are cleaned
// and made absolute against the working directory first (the desktop's
// data directory is the relative "data"). An edits directory of ""
// counts as none.
export_directory_refusal :: proc(export_directory, data_directory, edits_directory, working_directory: string) -> string {
	if !os.is_absolute_path(export_directory) {
		return text("data_files_export_not_absolute")
	}
	export := absolute_clean_path(export_directory, working_directory)
	for directory in ([]string{data_directory, edits_directory}) {
		if directory == "" {
			continue
		}
		source := absolute_clean_path(directory, working_directory)
		if path_is_within(export, source) || path_is_within(source, export) {
			return text("data_files_export_overlaps")
		}
	}
	return ""
}

// export_directory_refusal against the process's working directory.
export_directory_refusal_here :: proc(export_directory, data_directory, edits_directory: string) -> string {
	working_directory, _ := os.get_working_directory(context.temp_allocator)
	return export_directory_refusal(export_directory, data_directory, edits_directory, working_directory)
}

// Writes the data beside the path first, then renames it over the path,
// making the directories it needs, so a failed write never leaves a cut
// off file (for the next start, or for Syncthing to spread). The file gets
// the default permissions, whatever its source had. The problem, or "".
write_file_replacing :: proc(path: string, data: []byte) -> string {
	directory, _ := os.split_path(path)
	if error := make_directory_path(directory); error != nil {
		return fmt.tprintf("%v: %s", error, directory)
	}
	temporary := strings.concatenate({path, ".tmp"}, context.temp_allocator)
	if error := os.write_entire_file(temporary, data); error != nil {
		os.remove(temporary)
		return fmt.tprintf("%v: %s", error, temporary)
	}
	if error := os.rename(temporary, path); error != nil {
		os.remove(temporary)
		return fmt.tprintf("%v: %s", error, path)
	}
	return ""
}

// Copies the file through write_file_replacing; a source that is its own
// destination is refused, never read and written over. The problem, or
// "".
copy_exported_file :: proc(source, destination: string) -> string {
	working_directory, _ := os.get_working_directory(context.temp_allocator)
	if absolute_clean_path(source, working_directory) == absolute_clean_path(destination, working_directory) {
		return fmt.tprintf("%s: %s", text("data_files_export_overlaps"), destination)
	}
	data, error := os.read_entire_file(source, context.temp_allocator)
	if error != nil {
		return fmt.tprintf("%v: %s", error, source)
	}
	return write_file_replacing(destination, data)
}

// Every copy of the export, then export.txt; stops at the first problem.
// An export directory export_directory_refusal refuses writes nothing.
export_data_files :: proc(data_directory, edits_directory, export_directory: string, now: time.Time) -> Data_Export_Result {
	result: Data_Export_Result
	if export_directory == "" {
		result.problem = "no export directory"
		return result
	}
	if result.problem = export_directory_refusal_here(export_directory, data_directory, edits_directory); result.problem != "" {
		return result
	}
	data_files := list_data_files(data_directory, "")
	copies := data_export_copies(data_files, list_data_edit_files(edits_directory), data_directory, edits_directory, export_directory)
	for planned in copies {
		if result.problem = copy_exported_file(planned.source, planned.destination); result.problem != "" {
			return result
		}
		result.edit_count += planned.edit ? 1 : 0
		result.data_count += planned.edit ? 0 : 1
	}
	stamp := join_save_path(export_directory, DATA_EXPORT_STAMP_FILE)
	result.problem = write_file_replacing(stamp, transmute([]byte)data_export_stamp_text(BUILD_STAMP, now, result))
	return result
}

// The one data edit's copy in the export: written from the overlay when
// the overlay holds it (a save), deleted when not (a discard). An export
// directory export_directory_refusal refuses is left alone. The problem,
// or "".
sync_exported_data_edit :: proc(data_directory, edits_directory, export_directory, relative_path: string) -> string {
	if refusal := export_directory_refusal_here(export_directory, data_directory, edits_directory); refusal != "" {
		return refusal
	}
	overlay := join_save_path(edits_directory, relative_path)
	exported := join_save_path(export_directory, DATA_EXPORT_EDITS_DIRECTORY, relative_path)
	if os.is_file(overlay) {
		return copy_exported_file(overlay, exported)
	}
	if error := os.remove(exported); error != nil && error != .Not_Exist {
		return fmt.tprintf("%v: %s", error, exported)
	}
	return ""
}

// The toast after an export: where to and the counts, or the problem.
data_export_toast_text :: proc(export_directory: string, result: Data_Export_Result) -> string {
	if result.problem != "" {
		return fmt.tprintf("%s %s", text("data_files_export_failed"), result.problem)
	}
	return fmt.tprintf(
		"%s %s: %d %s, %d %s",
		text("data_files_exported"),
		export_directory,
		result.data_count,
		text("data_files_exported_data"),
		result.edit_count,
		text("data_files_exported_edits"),
	)
}

// The frame loop's side (serve_data_browser).

// All files access on Android: asked for, and the settings page opened
// with a toast when it is missing. Always granted elsewhere.
export_access_granted :: proc(ui: ^Ui_State) -> bool {
	if all_files_access_granted() {
		return true
	}
	open_all_files_access_settings()
	ui_toast(ui, text("data_files_export_access"))
	return false
}

// The export directory setting with a leading ~/ expanded against the
// home directory. In the temp allocator.
export_directory_setting :: proc(settings: Settings) -> string {
	return expand_home_path(settings.export_directory, platform_directories(context.temp_allocator).home)
}

// The Export button's request: the export into the settings' directory,
// logged and toasted; an empty directory exports nothing and says so. A
// success ends a run of failed syncs (export_sync_failed), so the next
// failure toasts again. The export runs in one frame: the game stands
// still while it copies.
export_data_browser_files :: proc(state: ^Frame_State, edits_directory: string) {
	export_directory := export_directory_setting(state.settings)
	if export_directory == "" {
		ui_toast(&state.ui, text("data_files_export_no_directory"))
		return
	}
	if !export_access_granted(&state.ui) {
		return
	}
	result := export_data_files(state.data_directory, edits_directory, export_directory, time.now())
	if result.problem != "" {
		log_printf("error: the data export to %s stopped: %s", export_directory, result.problem)
	} else {
		log_printf("data: exported %d data files and %d data edits to %s", result.data_count, result.edit_count, export_directory)
		state.data_browser.export_sync_failed = false
	}
	ui_toast(&state.ui, data_export_toast_text(export_directory, result))
}

// After a save or a discard: with export_on_save and a directory, the
// data edit's copy in the export follows. A failure is logged every time
// and toasted once, until a sync succeeds again, so a missing volume does
// not toast at every save; the settings page for All files access opens
// with that toast only.
sync_data_edit_export :: proc(state: ^Frame_State, edits_directory, relative_path: string) {
	export_directory := export_directory_setting(state.settings)
	if !state.settings.export_on_save || export_directory == "" {
		return
	}
	browser := &state.data_browser
	problem: string
	if !all_files_access_granted() {
		problem = text("data_files_export_access")
		if !browser.export_sync_failed {
			open_all_files_access_settings()
		}
	} else {
		problem = sync_exported_data_edit(state.data_directory, edits_directory, export_directory, relative_path)
	}
	if problem == "" {
		browser.export_sync_failed = false
		return
	}
	log_printf("error: cannot export the data edit %s: %s", relative_path, problem)
	if !browser.export_sync_failed {
		ui_toast(&state.ui, fmt.tprintf("%s %s", text("data_files_export_sync_failed"), problem))
		browser.export_sync_failed = true
	}
}

// The directory typed on the Data files screen, trimmed and with a
// leading ~/ expanded, into the settings, which the frame loop writes to
// the settings file. The settings own the text for the run and never
// free it (a few bytes per entry, as the loader's strings): the settings
// the frame loop last wrote (stored_settings) may still point at the one
// before.
set_export_directory :: proc(settings: ^Settings, typed, home: string) {
	settings.export_directory = strings.clone(expand_home_path(strings.trim_space(typed), home))
}
