package game

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"

// Player facing text by key, from data/strings/en.sjson. A missing key
// shows as the key itself, so the gap is visible in the UI, and is reported
// once on stderr.

STRINGS_DIRECTORY :: "strings"
STRINGS_FILE_NAME :: "en.sjson"

String_Table :: struct {
	entries:          map[string]string,
	reported_missing: map[string]bool,
	// text() may be called from tests on several threads.
	mutex:            sync.Mutex,
}

// Filled once at start up by main; text() reads it.
global_string_table: String_Table

parse_string_table :: proc(data: []byte, allocator := context.allocator) -> (table: String_Table, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &table.entries, .SJSON, allocator)
	return
}

destroy_string_table :: proc(table: ^String_Table) {
	for key, value in table.entries {
		delete(key)
		delete(value)
	}
	delete(table.entries)
	for key in table.reported_missing {
		delete(key)
	}
	delete(table.reported_missing)
}

// Frees the recorded missing keys. For tests that call text() without a
// loaded table, so the once per key records do not show up as leaks.
clear_missing_reports :: proc(table: ^String_Table) {
	sync.mutex_lock(&table.mutex)
	defer sync.mutex_unlock(&table.mutex)
	for key in table.reported_missing {
		delete(key)
	}
	delete(table.reported_missing)
	table.reported_missing = {}
}

load_string_table :: proc(data_directory: string, allocator := context.allocator) -> (table: String_Table, ok: bool) {
	path, join_error := os.join_path({data_directory, STRINGS_DIRECTORY, STRINGS_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	parse_error: json.Unmarshal_Error
	table, parse_error = parse_string_table(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	return table, true
}

lookup_text :: proc(table: ^String_Table, key: string) -> string {
	if value, found := table.entries[key]; found {
		return value
	}
	sync.mutex_lock(&table.mutex)
	defer sync.mutex_unlock(&table.mutex)
	if key not_in table.reported_missing {
		table.reported_missing[strings.clone(key)] = true
		fmt.eprintfln("strings: missing key %q in %s", key, STRINGS_FILE_NAME)
	}
	return key
}

text :: proc(key: string) -> string {
	return lookup_text(&global_string_table, key)
}
