package game

import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"

// The Data files screen's data (work item 0129, ui_data_browser.odin):
// the tree of the data directory, and the open file as a tree of values
// (an SJSON file) or as lines (a shader, a licence). Both trees are rows
// in display order with a depth; the expansion flags pick the visible
// ones (visible_row_indices). The rows are pure data built here; the
// frame loop reads the directory and the files (serve_data_browser in
// loop.odin) when the screen asks.

Data_File_Kind :: enum u8 {
	// Never opened: png, wav, vox, ttf and anything else.
	Binary,
	Sjson,
	// Shown line by line.
	Text,
}

// A file under the data directory.
Data_File_Entry :: struct {
	// Relative to the data directory, / between names.
	path:   string,
	size:   i64,
	// The data edits overlay holds a copy (read_data_file).
	edited: bool,
}

Data_Tree_Row :: struct {
	// Relative to the data directory, / between names; a directory's
	// without a trailing /.
	path:       string,
	// The last name of path.
	name:       string,
	depth:      int,
	// A directory.
	expandable: bool,
	size:       i64,
	edited:     bool,
}

Data_Value_Row :: struct {
	depth:       int,
	// The object key, or the array element's index.
	label:       string,
	// A leaf's value as SJSON writes it, "" for an object or an array.
	value:       string,
	// An object or an array.
	expandable:  bool,
	array:       bool,
	child_count: int,
}

Data_Browser :: struct {
	// The tree, in tree_arena, built when the screen opens and after a
	// discard. expanded is parallel to rows.
	tree_arena:        ^virtual.Arena,
	rows:              []Data_Tree_Row,
	expanded:          []bool,
	// The file row that Discard and the open file refer to, -1 for none.
	selected:          int,
	// The open file, in file_arena; the tree shows while open is false.
	file_arena:        ^virtual.Arena,
	open:              bool,
	file_kind:         Data_File_Kind,
	// The open file was read from the data edits overlay.
	shows_overlay:     bool,
	value_rows:        []Data_Value_Row,
	value_expanded:    []bool,
	lines:             []string,
	// Shown in place of the rows when the file cannot be read or parsed.
	file_problem:      string,
	// Set by the screens, served by the frame loop before the next frame's
	// screens: close the open file, read the tree again, open the selected
	// file, discard the selected file's overlay copy. The file closes
	// between frames because the frame's draw list points into its arena
	// until the frame is drawn.
	close_requested:   bool,
	refresh_requested: bool,
	open_requested:    bool,
	discard_requested: bool,
}

make_data_browser :: proc() -> Data_Browser {
	return Data_Browser{selected = -1}
}

destroy_data_browser :: proc(browser: ^Data_Browser) {
	destroy_arena(browser.tree_arena)
	destroy_arena(browser.file_arena)
	browser^ = make_data_browser()
}

// By the extension; only text files open.
data_file_kind :: proc(name: string) -> Data_File_Kind {
	switch {
	case strings.has_suffix(name, ".sjson"):
		return .Sjson
	case strings.has_suffix(name, ".vs"), strings.has_suffix(name, ".fs"), strings.has_suffix(name, ".txt"):
		return .Text
	}
	return .Binary
}

// Directories before files at every level, each sorted by name.
data_path_sorts_before :: proc(first, second: string) -> bool {
	first_names := strings.split(first, "/", context.temp_allocator)
	second_names := strings.split(second, "/", context.temp_allocator)
	for index in 0 ..< min(len(first_names), len(second_names)) {
		if first_names[index] == second_names[index] {
			continue
		}
		first_is_directory := index < len(first_names) - 1
		second_is_directory := index < len(second_names) - 1
		if first_is_directory != second_is_directory {
			return first_is_directory
		}
		return first_names[index] < second_names[index]
	}
	return len(first_names) < len(second_names)
}

// How many leading directory names two split paths share.
shared_directory_count :: proc(first, second: []string) -> int {
	count := 0
	for count < len(first) - 1 && count < len(second) - 1 && first[count] == second[count] {
		count += 1
	}
	return count
}

// The tree rows of a list of files: every directory once, before its
// contents, directories first, then files, each sorted by name. The
// paths are cloned into allocator.
data_tree_rows :: proc(entries: []Data_File_Entry, allocator := context.allocator) -> []Data_Tree_Row {
	sorted := slice.clone(entries, context.temp_allocator)
	slice.sort_by(sorted, proc(first, second: Data_File_Entry) -> bool {
		return data_path_sorts_before(first.path, second.path)
	})
	rows := make([dynamic]Data_Tree_Row, 0, len(sorted), allocator)
	previous: []string
	for entry in sorted {
		names := strings.split(entry.path, "/", context.temp_allocator)
		for depth in shared_directory_count(previous, names) ..< len(names) - 1 {
			append(&rows, data_tree_row(strings.join(names[:depth + 1], "/", allocator), depth, true))
		}
		row := data_tree_row(strings.clone(entry.path, allocator), len(names) - 1, false)
		row.size, row.edited = entry.size, entry.edited
		append(&rows, row)
		previous = names
	}
	return rows[:]
}

data_tree_row :: proc(path: string, depth: int, expandable: bool) -> Data_Tree_Row {
	name := path
	if separator := strings.last_index_byte(path, '/'); separator >= 0 {
		name = path[separator + 1:]
	}
	return Data_Tree_Row{path = path, name = name, depth = depth, expandable = expandable}
}

// The indices of the rows whose every ancestor is expanded, in order.
// Row is a Data_Tree_Row or a Data_Value_Row; expanded is parallel to
// rows.
visible_row_indices :: proc(rows: []$Row, expanded: []bool, allocator := context.temp_allocator) -> []int {
	visible := make([dynamic]int, 0, len(rows), allocator)
	// Rows deeper than this are inside a collapsed row.
	collapsed_depth := max(int)
	for row, index in rows {
		if row.depth > collapsed_depth {
			continue
		}
		collapsed_depth = max(int)
		append(&visible, index)
		if row.expandable && !expanded[index] {
			collapsed_depth = row.depth
		}
	}
	return visible[:]
}

// The expansion of the rows a new tree shares by path with the old one.
carried_expansion :: proc(old_rows: []Data_Tree_Row, old_expanded: []bool, new_rows: []Data_Tree_Row, allocator := context.allocator) -> []bool {
	expanded := make([]bool, len(new_rows), allocator)
	was_expanded := make(map[string]bool, context.temp_allocator)
	for row, index in old_rows {
		if index < len(old_expanded) && old_expanded[index] {
			was_expanded[row.path] = true
		}
	}
	for row, index in new_rows {
		expanded[index] = was_expanded[row.path]
	}
	return expanded
}

// The row of a path, -1 for none.
find_data_tree_row :: proc(rows: []Data_Tree_Row, path: string) -> int {
	for row, index in rows {
		if row.path == path {
			return index
		}
	}
	return -1
}

// The members of the value in display order, depth first: an object's by
// key (json.Object is a map, so the file's order is gone), an array's by
// index. A lone leaf is one row without a label. Into allocator.
data_value_rows :: proc(value: json.Value, allocator := context.allocator) -> []Data_Value_Row {
	rows := make([dynamic]Data_Value_Row, allocator)
	#partial switch _ in value {
	case json.Object, json.Array:
		append_data_value_children(&rows, value, 0, allocator)
	case:
		append(&rows, Data_Value_Row{value = data_leaf_text(value, allocator)})
	}
	return rows[:]
}

append_data_value_children :: proc(rows: ^[dynamic]Data_Value_Row, value: json.Value, depth: int, allocator := context.allocator) {
	#partial switch container in value {
	case json.Object:
		for key in sorted_object_keys(container) {
			append_data_value_row(rows, strings.clone(key, allocator), container[key], depth, allocator)
		}
	case json.Array:
		for element, index in container {
			append_data_value_row(rows, fmt.aprintf("%d", index, allocator = allocator), element, depth, allocator)
		}
	}
}

append_data_value_row :: proc(rows: ^[dynamic]Data_Value_Row, label: string, value: json.Value, depth: int, allocator := context.allocator) {
	row := Data_Value_Row{depth = depth, label = label}
	#partial switch container in value {
	case json.Object:
		row.expandable, row.child_count = true, len(container)
	case json.Array:
		row.expandable, row.array, row.child_count = true, true, len(container)
	case:
		row.value = data_leaf_text(value, allocator)
	}
	append(rows, row)
	if row.expandable {
		append_data_value_children(rows, value, depth + 1, allocator)
	}
}

// A leaf as SJSON writes it: strings quoted.
data_leaf_text :: proc(value: json.Value, allocator := context.allocator) -> string {
	#partial switch leaf in value {
	case json.Integer:
		return fmt.aprintf("%d", leaf, allocator = allocator)
	case json.Float:
		return fmt.aprintf("%v", leaf, allocator = allocator)
	case json.Boolean:
		return fmt.aprintf("%v", leaf, allocator = allocator)
	case json.String:
		return fmt.aprintf("%q", leaf, allocator = allocator)
	}
	return "null"
}

// "key = value" for a leaf, the key alone for an object or an array.
data_value_row_text :: proc(row: Data_Value_Row) -> string {
	if row.expandable {
		return row.label
	}
	if row.label == "" {
		return row.value
	}
	return fmt.tprintf("%s = %s", row.label, row.value)
}

// The member count beside an object or an array: {3} or [2].
data_value_row_count_text :: proc(row: Data_Value_Row) -> string {
	return row.array ? fmt.tprintf("[%d]", row.child_count) : fmt.tprintf("{%d}", row.child_count)
}

// A text file's lines, tabs as four spaces; none for an empty file. Into
// allocator.
data_text_lines :: proc(text: string, allocator := context.allocator) -> []string {
	trimmed := strings.trim_right(text, "\r\n")
	if trimmed == "" {
		return nil
	}
	lines := strings.split_lines(trimmed, allocator)
	for &line in lines {
		line, _ = strings.replace_all(strings.trim_right(line, "\r"), "\t", "    ", allocator)
	}
	return lines
}

// Bytes up to a kibibyte, then KB and MB to one decimal.
data_file_size_text :: proc(size: i64) -> string {
	switch {
	case size < 1024:
		return fmt.tprintf("%d B", size)
	case size < 1024 * 1024:
		return fmt.tprintf("%.1f KB", f64(size) / 1024)
	}
	return fmt.tprintf("%.1f MB", f64(size) / (1024 * 1024))
}

// Reading the directory and the files, for the frame loop.

// Every file under the data directory, hidden names (a leading dot)
// skipped, each marked when the edits directory holds its copy; "" marks
// none. In the temp allocator. A directory that cannot be read is logged
// and left out.
list_data_files :: proc(data_directory, edits_directory: string) -> []Data_File_Entry {
	entries := make([dynamic]Data_File_Entry, context.temp_allocator)
	append_data_directory_files(&entries, data_directory, "", edits_directory)
	return entries[:]
}

append_data_directory_files :: proc(entries: ^[dynamic]Data_File_Entry, directory, relative, edits_directory: string) {
	infos, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	if error != nil {
		log_printf("error: cannot read %s: %v", directory, error)
		return
	}
	for info in infos {
		if strings.has_prefix(info.name, ".") {
			continue
		}
		path := relative == "" ? info.name : fmt.tprintf("%s/%s", relative, info.name)
		#partial switch info.type {
		case .Directory:
			append_data_directory_files(entries, info.fullpath, path, edits_directory)
		case .Regular:
			edited := edits_directory != "" && os.is_file(join_save_path(edits_directory, path))
			append(entries, Data_File_Entry{path = path, size = info.size, edited = edited})
		}
	}
}

// The tree built again from the files, keeping the expansion and the
// selection by path; an open file whose row is gone closes.
rebuild_data_tree :: proc(browser: ^Data_Browser, entries: []Data_File_Entry) {
	arena := new_growing_arena()
	if arena == nil {
		log_printf("error: cannot reserve memory for the data file tree")
		return
	}
	allocator := virtual.arena_allocator(arena)
	rows := data_tree_rows(entries, allocator)
	expanded := carried_expansion(browser.rows, browser.expanded, rows, allocator)
	selected := -1
	if browser.selected >= 0 && browser.selected < len(browser.rows) {
		selected = find_data_tree_row(rows, browser.rows[browser.selected].path)
	}
	destroy_arena(browser.tree_arena)
	browser.tree_arena, browser.rows, browser.expanded, browser.selected = arena, rows, expanded, selected
	if selected < 0 {
		close_data_browser_file(browser)
	}
}

// Between frames: the close the screen asked for.
apply_data_browser_close_request :: proc(browser: ^Data_Browser) {
	if browser.close_requested {
		browser.close_requested = false
		close_data_browser_file(browser)
	}
}

// Back to the tree; the file's memory goes, so never during a frame's UI
// pass (close_requested).
close_data_browser_file :: proc(browser: ^Data_Browser) {
	destroy_arena(browser.file_arena)
	browser.file_arena = nil
	browser.open, browser.shows_overlay, browser.value_rows, browser.value_expanded, browser.lines, browser.file_problem = false, false, nil, nil, nil, ""
}

// The selected file read through the overlay and shown: an SJSON file as
// values, a text file as lines, a problem in their place.
open_data_browser_file :: proc(browser: ^Data_Browser, data_directory: string) {
	if browser.selected < 0 || browser.selected >= len(browser.rows) {
		return
	}
	row := browser.rows[browser.selected]
	close_data_browser_file(browser)
	browser.file_arena = new_growing_arena()
	if browser.file_arena == nil {
		log_printf("error: cannot reserve memory for %s", row.path)
		return
	}
	allocator := virtual.arena_allocator(browser.file_arena)
	browser.open, browser.file_kind = true, data_file_kind(row.name)
	data, path, read_error := read_data_file(data_directory, row.path, allocator)
	if read_error != nil {
		browser.file_problem = fmt.aprintf("%s %v: %s", text("data_files_read_failed"), read_error, path, allocator = allocator)
		return
	}
	browser.shows_overlay = path != join_save_path(data_directory, row.path)
	switch browser.file_kind {
	case .Sjson:
		value, parse_error := json.parse(data, .SJSON, true, allocator)
		if parse_error != .None {
			browser.file_problem = fmt.aprintf("%s %v: %s", text("data_files_parse_failed"), parse_error, path, allocator = allocator)
			return
		}
		browser.value_rows = data_value_rows(value, allocator)
		browser.value_expanded = make([]bool, len(browser.value_rows), allocator)
	case .Text:
		browser.lines = data_text_lines(string(data), allocator)
	case .Binary:
	}
	if len(browser.value_rows) == 0 && len(browser.lines) == 0 {
		browser.file_problem = text("data_files_empty_file")
	}
}
