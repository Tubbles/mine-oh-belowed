package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:strings"
import "platform"
import "sjson_text"

// The Data files screen's data (work item 0129, ui_data_browser.odin):
// the tree of the data directory, and the open file as a tree of values
// (an SJSON file) or as lines (a shader, a licence). Both trees are rows
// in display order with a depth; the expansion flags pick the visible
// ones (visible_row_indices). The rows are pure data built here; the
// frame loop reads the directory and the files (serve_data_browser in
// loop.odin) when the screen asks.
//
// Editing (work item 0130): an edit changes the parsed json.Value, in the
// file's arena, and builds the value rows again from it; each row knows
// its parent row, which leads from the root to the value it shows. The
// file is unsaved while the tree's SJSON text (sjson_text) differs from
// the text of the tree as it was loaded or last saved.

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
	depth:         int,
	// The object key, or the array element's index.
	label:         string,
	// A leaf's value as SJSON writes it, "" for an object or an array.
	value:         string,
	// An object or an array.
	expandable:    bool,
	array:         bool,
	child_count:   int,
	// The row of the containing object or array, -1 for a member of the
	// root.
	parent:        int,
	// The index in the containing array, -1 for an object member.
	element_index: int,
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
	// An SJSON file's tree, in file_arena; the rows show it.
	value:             json.Value,
	value_rows:        []Data_Value_Row,
	value_expanded:    []bool,
	// The value row last activated, which Duplicate and Remove act on;
	// -1 for none.
	value_selected:    int,
	// The value row the keyboard edits (value_field), -1 for none.
	editing_row:       int,
	value_field:       Text_Field,
	// The tree's SJSON text as loaded or last saved, and whether the tree
	// differs from it.
	loaded_text:       string,
	unsaved:           bool,
	lines:             []string,
	// Shown in place of the rows when the file cannot be read or parsed.
	file_problem:      string,
	// The export directory under the keyboard (0131); Done sets the
	// setting (set_export_directory).
	editing_export_directory: bool,
	export_field:             Text_Field,
	// The edits directory under the keyboard (0228); Done sets the
	// setting (set_edits_directory).
	editing_edits_directory:  bool,
	edits_field:              Text_Field,
	// An export on save failed and toasted; no toast again until one
	// succeeds (sync_data_edit_export).
	export_sync_failed:       bool,
}

make_data_browser :: proc() -> Data_Browser {
	return Data_Browser{selected = -1, value_selected = -1, editing_row = -1}
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
		append_data_value_children(&rows, value, 0, -1, allocator)
	case:
		append(&rows, Data_Value_Row{value = data_leaf_text(value, allocator), parent = -1, element_index = -1})
	}
	return rows[:]
}

append_data_value_children :: proc(rows: ^[dynamic]Data_Value_Row, value: json.Value, depth, parent: int, allocator := context.allocator) {
	#partial switch container in value {
	case json.Object:
		for key in sjson_text.sorted_object_keys(container) {
			row := Data_Value_Row{depth = depth, label = strings.clone(key, allocator), parent = parent, element_index = -1}
			append_data_value_row(rows, row, container[key], allocator)
		}
	case json.Array:
		for element, index in container {
			row := Data_Value_Row{depth = depth, label = fmt.aprintf("%d", index, allocator = allocator), parent = parent, element_index = index}
			append_data_value_row(rows, row, element, allocator)
		}
	}
}

append_data_value_row :: proc(rows: ^[dynamic]Data_Value_Row, row: Data_Value_Row, value: json.Value, allocator := context.allocator) {
	row := row
	#partial switch container in value {
	case json.Object:
		row.expandable, row.child_count = true, len(container)
	case json.Array:
		row.expandable, row.array, row.child_count = true, true, len(container)
	case:
		row.value = data_leaf_text(value, allocator)
	}
	index := len(rows^)
	append(rows, row)
	if row.expandable {
		append_data_value_children(rows, value, row.depth + 1, index, allocator)
	}
}

// A leaf as SJSON writes it (sjson_leaf_text): strings quoted, a float
// with a point.
data_leaf_text :: proc(value: json.Value, allocator := context.allocator) -> string {
	return sjson_text.sjson_leaf_text(value, allocator)
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
		platform.log_printf("error: cannot read %s: %v", directory, error)
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
			edited := edits_directory != "" && os.is_file(platform.join_path(edits_directory, path))
			append(entries, Data_File_Entry{path = path, size = info.size, edited = edited})
		}
	}
}

// Writes the text to the relative path under the edits directory, making
// the directories it needs. The problem, or "".
write_data_edit :: proc(edits_directory, relative_path, file_text: string) -> string {
	if edits_directory == "" {
		return "no state directory"
	}
	path := platform.join_path(edits_directory, relative_path)
	// Beside it first, then renamed over it, so a crash or a full disk
	// never leaves a cut off copy the next start would fail on.
	if problem := platform.write_file_replacing(path, transmute([]byte)file_text); problem != "" {
		return problem
	}
	platform.log_printf("data: saved the data edit %s", path)
	return ""
}

// The tree built again from the files, keeping the expansion and the
// selection by path; an open file whose row is gone closes.
rebuild_data_tree :: proc(browser: ^Data_Browser, entries: []Data_File_Entry) {
	arena := new_growing_arena()
	if arena == nil {
		platform.log_printf("error: cannot reserve memory for the data file tree")
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
apply_data_browser_close_request :: proc(browser: ^Data_Browser, requests: ^Frame_Requests) {
	if .Close_Data_File in requests^ {
		requests^ -= {.Close_Data_File}
		close_data_browser_file(browser)
	}
}

// Back to the tree; the file's memory goes, so never during a frame's UI
// pass (Close_Data_File).
close_data_browser_file :: proc(browser: ^Data_Browser) {
	destroy_arena(browser.file_arena)
	browser.file_arena = nil
	browser.open, browser.shows_overlay, browser.value_rows, browser.value_expanded, browser.lines, browser.file_problem = false, false, nil, nil, nil, ""
	browser.value, browser.value_selected, browser.editing_row, browser.loaded_text, browser.unsaved = nil, -1, -1, "", false
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
		platform.log_printf("error: cannot reserve memory for %s", row.path)
		return
	}
	allocator := virtual.arena_allocator(browser.file_arena)
	browser.open, browser.file_kind = true, data_file_kind(row.name)
	data, path, read_error := read_data_file(data_directory, row.path, allocator)
	if read_error != nil {
		browser.file_problem = fmt.aprintf("%s %v: %s", text("data_files_read_failed"), read_error, path, allocator = allocator)
		return
	}
	browser.shows_overlay = path != platform.join_path(data_directory, row.path)
	switch browser.file_kind {
	case .Sjson:
		value, parse_error := json.parse(data, .SJSON, true, allocator)
		if parse_error != .None {
			browser.file_problem = fmt.aprintf("%s %v: %s", text("data_files_parse_failed"), parse_error, path, allocator = allocator)
			return
		}
		show_data_browser_value(browser, value, allocator)
	case .Text:
		browser.lines = data_text_lines(string(data), allocator)
	case .Binary:
	}
	if len(browser.value_rows) == 0 && len(browser.lines) == 0 {
		browser.file_problem = text("data_files_empty_file")
	}
}

// The parsed tree shown, as loaded: nothing selected, all collapsed,
// nothing unsaved. allocator is the file's arena.
show_data_browser_value :: proc(browser: ^Data_Browser, value: json.Value, allocator := context.allocator) {
	browser.value = value
	browser.value_rows = data_value_rows(value, allocator)
	browser.value_expanded = make([]bool, len(browser.value_rows), allocator)
	browser.loaded_text = sjson_text.sjson_text(value, allocator)
	browser.value_selected, browser.editing_row, browser.unsaved = -1, -1, false
}

// Editing the tree (work item 0130). Every edit allocates in the file's
// arena and frees nothing, so the rows a frame drew stay readable until
// the file closes.

Data_Value_Edit :: enum u8 {
	Duplicate,
	Remove,
}

// The rows from the outermost ancestor down to the row itself, none for
// -1 (the root). In the temp allocator.
data_value_row_chain :: proc(rows: []Data_Value_Row, index: int) -> []int {
	chain := make([dynamic]int, context.temp_allocator)
	for row := index; row >= 0; row = rows[row].parent {
		inject_at(&chain, 0, row)
	}
	return chain[:]
}

// The value's place in the file, its labels from the root joined by dots
// (recipes.3.seconds). In the temp allocator.
data_value_row_path_text :: proc(rows: []Data_Value_Row, index: int) -> string {
	chain := data_value_row_chain(rows, index)
	labels := make([]string, len(chain), context.temp_allocator)
	for row, position in chain {
		labels[position] = rows[row].label
	}
	return strings.join(labels, ".", context.temp_allocator)
}

// The member a row names in its container.
data_value_member :: proc(container: json.Value, row: Data_Value_Row) -> json.Value {
	#partial switch members in container {
	case json.Object:
		return members[row.label]
	case json.Array:
		if row.element_index >= 0 && row.element_index < len(members) {
			return members[row.element_index]
		}
	}
	return nil
}

// The value a row shows.
data_value_at_row :: proc(root: json.Value, rows: []Data_Value_Row, index: int) -> json.Value {
	value := root
	for row in data_value_row_chain(rows, index) {
		value = data_value_member(value, rows[row])
	}
	return value
}

// The container with the value at the end of the chain replaced. The
// containers along the chain are written in place: an object keeps its
// keys and an array its length, so their memory is not moved.
data_value_replaced :: proc(container: json.Value, rows: []Data_Value_Row, chain: []int, replacement: json.Value) -> json.Value {
	if len(chain) == 0 {
		return replacement
	}
	row := rows[chain[0]]
	member := data_value_replaced(data_value_member(container, row), rows, chain[1:], replacement)
	container := container
	#partial switch &members in container {
	case json.Object:
		members[row.label] = member
	case json.Array:
		members[row.element_index] = member
	}
	return container
}

// The root with the row's value replaced.
data_value_set :: proc(root: json.Value, rows: []Data_Value_Row, index: int, replacement: json.Value) -> json.Value {
	return data_value_replaced(root, rows, data_value_row_chain(rows, index), replacement)
}

// Whether Duplicate and Remove act on the row: an array element.
data_value_row_is_element :: proc(rows: []Data_Value_Row, index: int) -> bool {
	return index >= 0 && index < len(rows) && rows[index].element_index >= 0
}

// The root with the array element duplicated (the copy after it) or
// removed. The array is made anew in allocator, the copy cloned into it.
data_value_edit_element :: proc(root: json.Value, rows: []Data_Value_Row, index: int, edit: Data_Value_Edit, allocator := context.allocator) -> json.Value {
	row := rows[index]
	elements, is_array := data_value_at_row(root, rows, row.parent).(json.Array)
	if !is_array {
		return root
	}
	edited := make(json.Array, 0, len(elements) + 1, allocator)
	for element, element_index in elements {
		if element_index != row.element_index || edit == .Duplicate {
			append(&edited, element)
		}
		if element_index == row.element_index && edit == .Duplicate {
			append(&edited, json.clone_value(element, allocator))
		}
	}
	return data_value_replaced(root, rows, data_value_row_chain(rows, row.parent), edited)
}

// The row after the row's members: the end of its subtree.
data_value_subtree_end :: proc(rows: []Data_Value_Row, index: int) -> int {
	end := index + 1
	for end < len(rows) && rows[end].depth > rows[index].depth {
		end += 1
	}
	return end
}

// The expansion after an element's rows were duplicated (the copy's
// rows follow them, expanded alike) or removed. In allocator.
data_value_expansion_after :: proc(expanded: []bool, rows: []Data_Value_Row, index: int, edit: Data_Value_Edit, allocator := context.allocator) -> []bool {
	end := data_value_subtree_end(rows, index)
	result := make([dynamic]bool, 0, len(expanded) + end - index, allocator)
	switch edit {
	case .Duplicate:
		append(&result, ..expanded[:end])
		append(&result, ..expanded[index:end])
	case .Remove:
		append(&result, ..expanded[:index])
	}
	append(&result, ..expanded[end:])
	return result[:]
}

// The most digits an i64 has; a longer run of digits is out of range
// before parse_i128 could wrap it.
INTEGER_MAXIMUM_DIGITS :: 19

// A leaf from the text typed for it: a number keeps its kind, except
// that a point or an exponent makes a float (an integer typed without
// them stays an integer); a string takes the text as it is. ok is false
// for a number that does not parse, an integer outside the i64 range, a
// float that is not finite, and for a boolean, a null or a container.
data_value_from_text :: proc(old: json.Value, typed: string, allocator := context.allocator) -> (value: json.Value, ok: bool) {
	#partial switch _ in old {
	case json.Integer, json.Float:
		_, is_integer := old.(json.Integer)
		if is_integer && !strings.contains_any(typed, ".eE") {
			return data_integer_from_text(typed)
		}
		float, parsed := strconv.parse_f64(typed)
		return json.Float(float), parsed && !math.is_inf(float) && !math.is_nan(float)
	case json.String:
		return json.String(strings.clone(typed, allocator)), true
	}
	return nil, false
}

// An integer inside the i64 range; strconv.parse_i64 wraps a longer one
// and says it parsed.
data_integer_from_text :: proc(typed: string) -> (value: json.Value, ok: bool) {
	digits := strings.trim_left(typed, "+-")
	if len(digits) > INTEGER_MAXIMUM_DIGITS {
		return nil, false
	}
	integer, parsed := strconv.parse_i128(typed)
	if !parsed || integer < i128(min(i64)) || integer > i128(max(i64)) {
		return nil, false
	}
	return json.Integer(i64(integer)), true
}

// The characters the keyboard takes for a leaf, and the text it starts
// from. editable is false for a boolean (Confirm flips it), a null, a
// container, and a leaf whose text the field cannot hold unchanged (a
// string with characters past printable ASCII or longer than the field).
data_value_field_text :: proc(value: json.Value) -> (text: string, characters: Text_Field_Characters, editable: bool) {
	#partial switch leaf in value {
	case json.Integer, json.Float:
		text, characters = sjson_text.sjson_leaf_text(value, context.temp_allocator), .Number
	case json.String:
		text, characters = leaf, .Printable
	case:
		return "", .Printable, false
	}
	return text, characters, text_field_holds(characters, text)
}

// The rows built again after the tree changed shape (Duplicate, Remove),
// and whether it now differs from the text last loaded or saved.
refresh_data_browser_value :: proc(browser: ^Data_Browser, value: json.Value, expanded: []bool) {
	allocator := virtual.arena_allocator(browser.file_arena)
	browser.value = value
	browser.value_rows = data_value_rows(value, allocator)
	browser.value_expanded = expanded
	browser.unsaved = sjson_text.sjson_text(value, context.temp_allocator) != browser.loaded_text
}

// A leaf replaced: the tree keeps its shape, so only the row's text is
// written again, not every row (the strings file has about 1,700).
replace_data_browser_leaf :: proc(browser: ^Data_Browser, index: int, leaf: json.Value) {
	browser.value = data_value_set(browser.value, browser.value_rows, index, leaf)
	browser.value_rows[index].value = data_leaf_text(leaf, virtual.arena_allocator(browser.file_arena))
	browser.unsaved = sjson_text.sjson_text(browser.value, context.temp_allocator) != browser.loaded_text
}

// A boolean flipped; any other row is left alone.
flip_data_browser_value :: proc(browser: ^Data_Browser, index: int) {
	flag, is_boolean := data_value_at_row(browser.value, browser.value_rows, index).(json.Boolean)
	if is_boolean {
		replace_data_browser_leaf(browser, index, json.Boolean(!flag))
	}
}

// The typed text set as the row's value; false (and the value kept) when
// it does not parse.
set_data_browser_value :: proc(browser: ^Data_Browser, index: int, typed: string) -> bool {
	old := data_value_at_row(browser.value, browser.value_rows, index)
	value, ok := data_value_from_text(old, typed, virtual.arena_allocator(browser.file_arena))
	if ok {
		replace_data_browser_leaf(browser, index, value)
	}
	return ok
}

// The selected element duplicated (the copy selected) or removed (nothing
// selected); nothing while the selection is no array element.
edit_data_browser_element :: proc(browser: ^Data_Browser, edit: Data_Value_Edit) {
	index := browser.value_selected
	if !data_value_row_is_element(browser.value_rows, index) {
		return
	}
	allocator := virtual.arena_allocator(browser.file_arena)
	expanded := data_value_expansion_after(browser.value_expanded, browser.value_rows, index, edit, allocator)
	end := data_value_subtree_end(browser.value_rows, index)
	value := data_value_edit_element(browser.value, browser.value_rows, index, edit, allocator)
	refresh_data_browser_value(browser, value, expanded)
	browser.value_selected = edit == .Duplicate ? end : -1
}
