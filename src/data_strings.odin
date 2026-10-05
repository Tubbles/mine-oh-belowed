package game

import "base:runtime"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "platform"

// Player facing text by key, from data/strings/en.sjson. A missing key
// shows as the key itself, so the gap is visible in the UI, and is reported
// once on stderr.

STRINGS_DIRECTORY :: "strings"
STRINGS_FILE_NAME :: "en.sjson"

// reported_missing and its keys live on the heap allocator whatever the
// caller's allocator is: text() is called from tests on several threads,
// each with its own allocator, and the records outlive any one caller.
String_Table :: struct {
	entries:          map[string]string,
	reported_missing: map[string]bool,
	// text() may be called from tests on several threads.
	mutex:            sync.Mutex,
}

// Filled at start up by main and replaced by a strings reload
// (replace_string_entries); text() reads it.
global_string_table: String_Table

// A test that needs the shipped strings (the UI audit) points this at its
// own table: other tests read the global table from other threads.
@(thread_local)
thread_string_table: ^String_Table

parse_string_table :: proc(data: []byte, allocator := context.allocator) -> (table: String_Table, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &table.entries, .SJSON, allocator)
	return
}

destroy_string_table :: proc(table: ^String_Table) {
	destroy_string_entries(table.entries)
	clear_missing_reports(table)
}

destroy_string_entries :: proc(entries: map[string]string) {
	for key, value in entries {
		delete(key)
		delete(value)
	}
	delete(entries)
}

// A strings reload (work item 0054): data parsed into new entries that
// replace the table's, between frames. A file that does not parse leaves
// the table as it was. The old entries come back to the caller, who
// frees them once no text() result can point into them any more; the
// missing key reports start over, since the file may have added them.
replace_string_entries :: proc(table: ^String_Table, data: []byte) -> (old_entries: map[string]string, error: json.Unmarshal_Error) {
	parsed: String_Table
	if parsed, error = parse_string_table(data); error != nil {
		destroy_string_entries(parsed.entries)
		return nil, error
	}
	sync.mutex_lock(&table.mutex)
	old_entries, table.entries = table.entries, parsed.entries
	sync.mutex_unlock(&table.mutex)
	clear_missing_reports(table)
	return old_entries, nil
}

// The file's bytes and the path read (the data edits overlay's copy when
// it has one), or the problem naming the file.
read_strings_file :: proc(data_directory: string) -> (data: []byte, path: string, problem: string) {
	read_error: os.Error
	data, path, read_error = read_data_file(data_directory, STRINGS_DIRECTORY + "/" + STRINGS_FILE_NAME, context.temp_allocator)
	if read_error != nil {
		return nil, path, fmt.tprintf("cannot read %s: %v", path, read_error)
	}
	return data, path, ""
}

// Frees the recorded missing keys. For tests that call text() without a
// loaded table, so the once per key records do not show up as leaks.
clear_missing_reports :: proc(table: ^String_Table) {
	sync.mutex_lock(&table.mutex)
	defer sync.mutex_unlock(&table.mutex)
	for key in table.reported_missing {
		delete(key, runtime.heap_allocator())
	}
	delete(table.reported_missing)
	table.reported_missing = {}
}

load_string_table :: proc(data_directory: string, allocator := context.allocator) -> (table: String_Table, ok: bool) {
	data, path := read_logged_data_file(data_directory, STRINGS_DIRECTORY + "/" + STRINGS_FILE_NAME) or_return
	parse_error: json.Unmarshal_Error
	table, parse_error = parse_string_table(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
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
		if table.reported_missing == nil {
			table.reported_missing = make(map[string]bool, runtime.heap_allocator())
		}
		table.reported_missing[strings.clone(key, runtime.heap_allocator())] = true
		platform.log_printf("strings: missing key %q in %s", key, STRINGS_FILE_NAME)
	}
	return key
}

// The thread's table when a test set one, else the global table.
active_string_table :: proc() -> ^String_Table {
	return thread_string_table != nil ? thread_string_table : &global_string_table
}

text :: proc(key: string) -> string {
	return lookup_text(active_string_table(), key)
}

FIELD_VARIANT_SUFFIX :: "_field"

// The field world's text of a key (0263), for the note titles and texts,
// the quest texts and the message texts: the key with FIELD_VARIANT_SUFFIX
// when field is set and the table has it, else the key itself. Reports
// nothing missing. It goes when the block world goes (0237).
field_variant_key :: proc(key: string, field: bool) -> string {
	if !field {
		return key
	}
	variant := strings.concatenate({key, FIELD_VARIANT_SUFFIX}, context.temp_allocator)
	if variant in active_string_table().entries {
		return variant
	}
	return key
}
