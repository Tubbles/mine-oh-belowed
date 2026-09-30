package game

import "core:encoding/json"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:testing"

// Work item 0129: the data edits overlay, the reaction to an overlay
// change, the file tree and the value tree. The overlay test writes only
// under a temporary directory it creates and removes.

@(test)
test_read_data_file_takes_the_overlay_copy_when_present :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-data-edits-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	data_directory := join_save_path(base, "data")
	edits_directory := join_save_path(base, "data_edits")
	testing.expect_value(t, make_directory_path(join_save_path(data_directory, "quests")), nil)
	testing.expect_value(t, make_directory_path(join_save_path(edits_directory, "quests")), nil)
	testing.expect_value(t, os.write_entire_file(join_save_path(data_directory, "blocks.sjson"), "data"), nil)
	testing.expect_value(t, os.write_entire_file(join_save_path(data_directory, "quests", "chapter_01.sjson"), "data chapter"), nil)
	testing.expect_value(t, os.write_entire_file(join_save_path(edits_directory, "quests", "chapter_01.sjson"), "edited chapter"), nil)

	data, path, read_error := read_data_file_with_edits(data_directory, edits_directory, "blocks.sjson", context.temp_allocator)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "data")
	testing.expect_value(t, path, join_save_path(data_directory, "blocks.sjson"))

	data, path, read_error = read_data_file_with_edits(data_directory, edits_directory, "quests/chapter_01.sjson", context.temp_allocator)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "edited chapter")
	testing.expect_value(t, path, join_save_path(edits_directory, "quests/chapter_01.sjson"))

	data, _, read_error = read_data_file_with_edits(data_directory, "", "quests/chapter_01.sjson", context.temp_allocator)
	testing.expect_value(t, read_error, nil)
	testing.expect_value(t, string(data), "data chapter")

	_, _, read_error = read_data_file_with_edits(data_directory, edits_directory, "items.sjson", context.temp_allocator)
	testing.expect(t, read_error != nil)
}

// A content file asks for the content reload; strings reload in place,
// which fails here (no data directory) and says so in a toast.
@(test)
test_a_data_edit_reports_its_category :: proc(t: ^testing.T) {
	defer clear_missing_reports(&global_string_table)
	state := new(Frame_State)
	defer free(state)
	defer destroy_ui_state(&state.ui)
	state.data_directory = "/nonexistent/mine-oh-belowed-data"
	testing.expect_value(t, apply_data_edit_change(state, "blocks.sjson"), Data_File_Category.Content)
	testing.expect(t, state.reload_requested)
	state.reload_requested = false
	testing.expect_value(t, apply_data_edit_change(state, "strings/en.sjson"), Data_File_Category.Strings)
	testing.expect(t, !state.reload_requested)
	testing.expect_value(t, apply_data_edit_change(state, "game.sjson"), Data_File_Category.Restart)
	testing.expect(t, !state.reload_requested)
}

@(test)
test_data_tree_lists_directories_first_and_expands :: proc(t: ^testing.T) {
	entries := [?]Data_File_Entry{{path = "d.sjson", size = 4}, {path = "a/c.png"}, {path = "a/b.sjson", edited = true}}
	rows := data_tree_rows(entries[:], context.temp_allocator)
	paths := [?]string{"a", "a/b.sjson", "a/c.png", "d.sjson"}
	testing.expect_value(t, len(rows), len(paths))
	for path, index in paths {
		testing.expect_value(t, rows[index].path, path)
	}
	testing.expect(t, rows[0].expandable)
	testing.expect_value(t, rows[0].depth, 0)
	testing.expect_value(t, rows[1].name, "b.sjson")
	testing.expect_value(t, rows[1].depth, 1)
	testing.expect(t, rows[1].edited)
	testing.expect_value(t, rows[3].size, 4)

	expanded := make([]bool, len(rows), context.temp_allocator)
	collapsed := visible_row_indices(rows, expanded)
	testing.expect_value(t, len(collapsed), 2)
	testing.expect_value(t, rows[collapsed[0]].path, "a")
	testing.expect_value(t, rows[collapsed[1]].path, "d.sjson")

	expanded[0] = true
	open := visible_row_indices(rows, expanded)
	testing.expect_value(t, len(open), 4)
	testing.expect_value(t, rows[open[1]].path, "a/b.sjson")
	testing.expect_value(t, rows[open[2]].path, "a/c.png")
}

// Nested directories come once each, and a rebuilt tree keeps what was
// expanded.
@(test)
test_data_tree_nests_directories_and_keeps_the_expansion :: proc(t: ^testing.T) {
	entries := [?]Data_File_Entry{{path = "z.sjson"}, {path = "fonts/play/OFL.txt"}, {path = "fonts/fonts.sjson"}, {path = "fonts/inter/OFL.txt"}}
	rows := data_tree_rows(entries[:], context.temp_allocator)
	paths := [?]string{"fonts", "fonts/inter", "fonts/inter/OFL.txt", "fonts/play", "fonts/play/OFL.txt", "fonts/fonts.sjson", "z.sjson"}
	testing.expect_value(t, len(rows), len(paths))
	for path, index in paths {
		testing.expect_value(t, rows[index].path, path)
	}
	expanded := make([]bool, len(rows), context.temp_allocator)
	expanded[0], expanded[3] = true, true
	visible := visible_row_indices(rows, expanded)
	testing.expect_value(t, len(visible), 6)
	testing.expect_value(t, rows[visible[2]].path, "fonts/play")
	testing.expect_value(t, rows[visible[3]].path, "fonts/play/OFL.txt")

	fewer := [?]Data_File_Entry{{path = "fonts/play/OFL.txt"}, {path = "z.sjson"}}
	rebuilt := data_tree_rows(fewer[:], context.temp_allocator)
	carried := carried_expansion(rows, expanded, rebuilt, context.temp_allocator)
	testing.expect_value(t, len(carried), 4)
	testing.expect(t, carried[0] && carried[1])
	testing.expect(t, !carried[2] && !carried[3])
}

@(test)
test_data_value_rows_show_keys_values_and_indices :: proc(t: ^testing.T) {
	value, error := json.parse_string("x = 1, y = [1, 2]", .SJSON, true, context.temp_allocator)
	testing.expect_value(t, error, json.Error.None)
	rows := data_value_rows(value, context.temp_allocator)
	texts := [?]string{"x = 1", "y", "0 = 1", "1 = 2"}
	testing.expect_value(t, len(rows), len(texts))
	for wanted, index in texts {
		testing.expect_value(t, data_value_row_text(rows[index]), wanted)
	}
	testing.expect(t, rows[1].expandable)
	testing.expect_value(t, data_value_row_count_text(rows[1]), "[2]")
	testing.expect_value(t, rows[2].depth, 1)

	expanded := make([]bool, len(rows), context.temp_allocator)
	testing.expect_value(t, len(visible_row_indices(rows, expanded)), 2)
	expanded[1] = true
	testing.expect_value(t, len(visible_row_indices(rows, expanded)), 4)
}

@(test)
test_data_leaves_and_files_read_as_written :: proc(t: ^testing.T) {
	value, error := json.parse_string(`name = "stone", solid = true, hardness = 1.5, missing = null`, .SJSON, true, context.temp_allocator)
	testing.expect_value(t, error, json.Error.None)
	rows := data_value_rows(value, context.temp_allocator)
	texts := [?]string{"hardness = 1.5", "missing = null", `name = "stone"`, "solid = true"}
	testing.expect_value(t, len(rows), len(texts))
	for wanted, index in texts {
		testing.expect_value(t, data_value_row_text(rows[index]), wanted)
	}
	testing.expect_value(t, data_file_kind("chunk.vs"), Data_File_Kind.Text)
	testing.expect_value(t, data_file_kind("OFL.txt"), Data_File_Kind.Text)
	testing.expect_value(t, data_file_kind("blocks.sjson"), Data_File_Kind.Sjson)
	testing.expect_value(t, data_file_kind("grass_top.png"), Data_File_Kind.Binary)
	lines := data_text_lines("a\r\n\tb\n", context.temp_allocator)
	testing.expect_value(t, len(lines), 2)
	testing.expect_value(t, lines[1], "    b")
	testing.expect_value(t, len(data_text_lines("", context.temp_allocator)), 0)
	testing.expect_value(t, data_file_size_text(512), "512 B")
	testing.expect_value(t, data_file_size_text(2048), "2.0 KB")
}

// Work item 0130: editing the value tree and saving it to the overlay.

// Two trees are equal, integers and floats told apart.
json_values_equal :: proc(first, second: json.Value) -> bool {
	#partial switch value in first {
	case json.Object:
		other, is_object := second.(json.Object)
		if !is_object || len(other) != len(value) {
			return false
		}
		for key, member in value {
			other_member, found := other[key]
			if !found || !json_values_equal(member, other_member) {
				return false
			}
		}
		return true
	case json.Array:
		other, is_array := second.(json.Array)
		if !is_array || len(other) != len(value) {
			return false
		}
		for element, index in value {
			if !json_values_equal(element, other[index]) {
				return false
			}
		}
		return true
	case json.Integer:
		other, is_integer := second.(json.Integer)
		return is_integer && other == value
	case json.Float:
		other, is_float := second.(json.Float)
		return is_float && other == value
	case json.Boolean:
		other, is_boolean := second.(json.Boolean)
		return is_boolean && other == value
	case json.String:
		other, is_string := second.(json.String)
		return is_string && other == value
	case json.Null:
		_, is_null := second.(json.Null)
		return is_null
	}
	return false
}

// The text written for a tree parses back to an equal tree, in the data
// files' style; every shipped SJSON file round trips too.
@(test)
test_sjson_text_parses_back_to_an_equal_tree :: proc(t: ^testing.T) {
	source := `
name = "Mine \"oh\" Belowed"
tick_rate = 60
speed = 16.0
share = 0.5
tiny = 0.00001
large = 2500000.0
below = -3
cold = -0.25
path = "C:\\data\ttab\nline"
"true" = 1
on = false
nothing = null
"odd key" = "{count} × {name}"
starting_items = [
	{item = "torch", count = 64}
]
made_in = ["hand", "assembler"]
nested = {deep = [[1, 2], []], empty = {}}
`
	value, error := json.parse_string(source, .SJSON, true, context.temp_allocator)
	testing.expect_value(t, error, json.Error.None)
	written := sjson_text(value, context.temp_allocator)
	parsed, parse_error := json.parse_string(written, .SJSON, true, context.temp_allocator)
	testing.expect_value(t, parse_error, json.Error.None)
	testing.expect(t, json_values_equal(value, parsed), written)
	for wanted in ([]string{"tick_rate = 60\n", "speed = 16.0\n", "share = 0.5\n", "starting_items = [\n\t{count = 64, item = \"torch\"}\n]\n", `made_in = ["hand", "assembler"]`, `"odd key" = "{count} × {name}"`, `name = "Mine \"oh\" Belowed"`, "\tempty = {}\n", "\t\t[1, 2]\n", "tiny = 1e-05\n", "large = 2.5e+06\n", "below = -3\n", "cold = -0.25\n", `path = "C:\\data\ttab\nline"`, `"true" = 1`}) {
		testing.expectf(t, strings.contains(written, wanted), "%q not in %s", wanted, written)
	}

	for entry in list_data_files(test_data_directory(), "") {
		if data_file_kind(entry.path) != .Sjson {
			continue
		}
		data, _, read_error := read_data_file_with_edits(test_data_directory(), "", entry.path, context.temp_allocator)
		testing.expect_value(t, read_error, nil)
		shipped, shipped_error := json.parse(data, .SJSON, true, context.temp_allocator)
		testing.expect_value(t, shipped_error, json.Error.None)
		again, again_error := json.parse_string(sjson_text(shipped, context.temp_allocator), .SJSON, true, context.temp_allocator)
		testing.expect_value(t, again_error, json.Error.None)
		testing.expectf(t, json_values_equal(shipped, again), "%s does not round trip", entry.path)
	}
}

// A browser with the tree of source open, as the frame loop opens a file.
open_test_data_value :: proc(t: ^testing.T, source: string) -> Data_Browser {
	browser := make_data_browser()
	browser.file_arena = new_growing_arena()
	allocator := virtual.arena_allocator(browser.file_arena)
	value, error := json.parse_string(source, .SJSON, true, allocator)
	testing.expect_value(t, error, json.Error.None)
	browser.open, browser.file_kind = true, .Sjson
	show_data_browser_value(&browser, value, allocator)
	return browser
}

// The row at a dotted path (data_value_row_path_text), -1 for none.
find_data_value_row :: proc(rows: []Data_Value_Row, path: string) -> int {
	for _, index in rows {
		if data_value_row_path_text(rows, index) == path {
			return index
		}
	}
	return -1
}

data_value_at_path :: proc(browser: Data_Browser, path: string) -> json.Value {
	return data_value_at_row(browser.value, browser.value_rows, find_data_value_row(browser.value_rows, path))
}

@(test)
test_data_value_edits_change_the_tree :: proc(t: ^testing.T) {
	browser := open_test_data_value(t, `flag = true, count = 3, speed = 1.5, name = "stone", recipe = {seconds = 16}`)
	defer destroy_data_browser(&browser)
	testing.expect(t, !browser.unsaved)

	flip_data_browser_value(&browser, find_data_value_row(browser.value_rows, "flag"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "flag"), json.Boolean(false)), "flag")
	testing.expect(t, browser.unsaved)
	flip_data_browser_value(&browser, find_data_value_row(browser.value_rows, "flag"))
	testing.expect(t, !browser.unsaved, "the tree is as loaded again")

	count := find_data_value_row(browser.value_rows, "count")
	testing.expect(t, set_data_browser_value(&browser, count, "-7"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "count"), json.Integer(-7)), "count")
	testing.expect(t, set_data_browser_value(&browser, count, "2.5"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "count"), json.Float(2.5)), "count")
	testing.expect(t, set_data_browser_value(&browser, find_data_value_row(browser.value_rows, "speed"), "2"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "speed"), json.Float(2)), "speed")
	testing.expect(t, set_data_browser_value(&browser, find_data_value_row(browser.value_rows, "name"), "iron ore"))
	testing.expect_value(t, data_value_at_path(browser, "name").(json.String), "iron ore")
	testing.expect(t, browser.unsaved)

	recipe_seconds := find_data_value_row(browser.value_rows, "recipe.seconds")
	testing.expect(t, set_data_browser_value(&browser, recipe_seconds, "9223372036854775807"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "recipe.seconds"), json.Integer(max(i64))))
	testing.expect(t, set_data_browser_value(&browser, recipe_seconds, "-9223372036854775808"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "recipe.seconds"), json.Integer(min(i64))))
	for out_of_range in ([]string{"9223372036854775808", "99999999999999999999", "-9223372036854775809"}) {
		testing.expect(t, !set_data_browser_value(&browser, recipe_seconds, out_of_range), out_of_range)
	}
	testing.expect(t, set_data_browser_value(&browser, recipe_seconds, "1e3"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "recipe.seconds"), json.Float(1000)), "an exponent makes a float")
	testing.expect_value(t, browser.value_rows[recipe_seconds].value, "1000.0")
	testing.expect(t, set_data_browser_value(&browser, recipe_seconds, "20"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "recipe.seconds"), json.Float(20)), "a float stays a float")

	for bad in ([]string{"", "-", "1.2.3", "4-2", "1e999"}) {
		testing.expect(t, !set_data_browser_value(&browser, find_data_value_row(browser.value_rows, "speed"), bad), bad)
		testing.expect(t, json_values_equal(data_value_at_path(browser, "speed"), json.Float(2)), "speed")
	}

	text, characters, editable := data_value_field_text(json.Float(0.5))
	testing.expect_value(t, text, "0.5")
	testing.expect_value(t, characters, Text_Field_Characters.Number)
	testing.expect(t, editable)
	text, _, editable = data_value_field_text(json.Float(0.00001))
	testing.expect_value(t, text, "1e-05")
	testing.expect(t, editable, "an exponent's form fits the number field")
	_, _, editable = data_value_field_text(json.String("{count} × {name}"))
	testing.expect(t, !editable, "the keyboard cannot type ×, so the string is not offered")
	_, _, editable = data_value_field_text(json.Boolean(true))
	testing.expect(t, !editable)
}

@(test)
test_data_value_elements_duplicate_and_remove :: proc(t: ^testing.T) {
	browser := open_test_data_value(t, `list = [{a = 1, tags = ["x"]}, {a = 2}], other = 5`)
	defer destroy_data_browser(&browser)
	list := find_data_value_row(browser.value_rows, "list")
	first := find_data_value_row(browser.value_rows, "list.0")
	browser.value_expanded[list] = true
	browser.value_expanded[first] = true
	testing.expect(t, !data_value_row_is_element(browser.value_rows, list))
	testing.expect(t, data_value_row_is_element(browser.value_rows, first))

	browser.value_selected = list
	edit_data_browser_element(&browser, .Duplicate)
	testing.expect_value(t, len(browser.value_rows), 8)

	browser.value_selected = first
	edit_data_browser_element(&browser, .Duplicate)
	testing.expect_value(t, len(data_value_at_path(browser, "list").(json.Array)), 3)
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.1.a"), json.Integer(1)), "list.1.a")
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.2.a"), json.Integer(2)), "list.2.a")
	testing.expect_value(t, browser.value_selected, find_data_value_row(browser.value_rows, "list.1"))
	testing.expect_value(t, len(browser.value_expanded), len(browser.value_rows))
	testing.expect(t, browser.value_expanded[find_data_value_row(browser.value_rows, "list.1")], "the copy expands as its original")
	testing.expect(t, browser.unsaved)
	testing.expect(t, set_data_browser_value(&browser, find_data_value_row(browser.value_rows, "list.1.a"), "9"))
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.0.a"), json.Integer(1)), "list.0.a")
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.1.a"), json.Integer(9)), "list.1.a")

	browser.value_selected = find_data_value_row(browser.value_rows, "list.0")
	edit_data_browser_element(&browser, .Remove)
	elements := data_value_at_path(browser, "list").(json.Array)
	testing.expect_value(t, len(elements), 2)
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.0.a"), json.Integer(9)), "list.0.a")
	testing.expect(t, json_values_equal(data_value_at_path(browser, "list.1.a"), json.Integer(2)), "list.1.a")
	testing.expect_value(t, browser.value_selected, -1)
	testing.expect_value(t, len(browser.value_expanded), len(browser.value_rows))
	testing.expect(t, browser.value_expanded[find_data_value_row(browser.value_rows, "list.0")])
	testing.expect(t, !browser.value_expanded[find_data_value_row(browser.value_rows, "list.1")])
	testing.expect(t, json_values_equal(data_value_at_path(browser, "other"), json.Integer(5)), "other")

	root := open_test_data_value(t, `[1, 2]`)
	defer destroy_data_browser(&root)
	root.value_selected = 1
	edit_data_browser_element(&root, .Remove)
	testing.expect_value(t, len(root.value.(json.Array)), 1)
}

// Save writes the tree under the edits directory (a temporary one here)
// and applies the change: a content file asks for the content reload. A
// file in a directory makes the directory; without an edits directory the
// save fails and the tree stays unsaved.
@(test)
test_a_data_edit_save_writes_the_overlay_and_asks_for_the_reload :: proc(t: ^testing.T) {
	edits_directory, error := os.make_directory_temp("", "mine-oh-belowed-data-save-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(edits_directory)
	defer clear_missing_reports(&global_string_table)
	state := new(Frame_State)
	defer free(state)
	defer destroy_ui_state(&state.ui)
	entries := [?]Data_File_Entry{{path = "blocks.sjson"}, {path = "quests/chapter_09.sjson"}}
	for relative_path in ([]string{"blocks.sjson", "quests/chapter_09.sjson"}) {
		state.data_browser = open_test_data_value(t, `blocks = [{id = "stone", hardness = 1.5}]`)
		browser := &state.data_browser
		browser.rows = data_tree_rows(entries[:], context.temp_allocator)
		browser.selected = find_data_tree_row(browser.rows, relative_path)
		testing.expect(t, set_data_browser_value(browser, find_data_value_row(browser.value_rows, "blocks.0.hardness"), "3"))
		testing.expect(t, browser.unsaved)

		save_data_edit(state, "")
		testing.expect(t, browser.unsaved, "no edits directory, nothing saved")
		testing.expect(t, !state.reload_requested)

		save_data_edit(state, edits_directory)
		testing.expect(t, !browser.unsaved)
		testing.expect(t, browser.shows_overlay)
		testing.expect(t, browser.refresh_requested)
		testing.expect_value(t, state.reload_requested, data_file_category(relative_path) == .Content)
		data, read_error := os.read_entire_file(join_save_path(edits_directory, relative_path), context.temp_allocator)
		testing.expect_value(t, read_error, nil)
		saved, parse_error := json.parse(data, .SJSON, true, context.temp_allocator)
		testing.expect_value(t, parse_error, json.Error.None)
		testing.expect(t, json_values_equal(saved, browser.value))
		testing.expect(t, strings.contains(string(data), "hardness = 3.0"), string(data))
		state.reload_requested = false
		browser.rows = nil
		destroy_data_browser(browser)
	}
}

// Saving strings/en.sjson reloads the strings at once: text() reads the
// edit right after the save. The test thread has its own string table and
// its own edits directory, so the other tests keep theirs.
@(test)
test_a_saved_strings_edit_shows_at_once :: proc(t: ^testing.T) {
	edits_directory, error := os.make_directory_temp("", "mine-oh-belowed-strings-save-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(edits_directory)
	data_edits_reading.directory = edits_directory
	defer reset_data_edits_reading()
	table, loaded := load_string_table(test_data_directory())
	testing.expect(t, loaded)
	thread_string_table = &table
	defer destroy_string_table(&table)
	defer thread_string_table = nil
	state := new(Frame_State)
	defer free(state)
	defer destroy_ui_state(&state.ui)
	defer destroy_hot_reload_state(state)
	defer destroy_font_cache(&state.font_cache)
	state.data_directory = test_data_directory()
	state.content_arena = new_growing_arena()
	source, read_error := os.read_entire_file(join_save_path(test_data_directory(), "strings", "en.sjson"), context.temp_allocator)
	testing.expect_value(t, read_error, nil)
	state.data_browser = open_test_data_value(t, string(source))
	defer destroy_data_browser(&state.data_browser)
	browser := &state.data_browser
	entries := [?]Data_File_Entry{{path = "strings/en.sjson"}}
	browser.rows = data_tree_rows(entries[:], context.temp_allocator)
	defer browser.rows = nil
	browser.selected = find_data_tree_row(browser.rows, "strings/en.sjson")
	testing.expect_value(t, text("data_files_title"), "Data files")
	testing.expect(t, set_data_browser_value(browser, find_data_value_row(browser.value_rows, "data_files_title"), "Edited files"))
	save_data_edit(state, edits_directory)
	testing.expect(t, !browser.unsaved)
	testing.expect_value(t, text("data_files_title"), "Edited files")
	testing.expect(t, !state.reload_requested)
	testing.expect(t, os.is_file(join_save_path(edits_directory, "strings", "en.sjson")))
	testing.expect(t, !os.exists(join_save_path(edits_directory, "strings", "en.sjson.tmp")), "the temporary copy was renamed")
}

// A broken overlay copy of blocks.sjson fails the start load, with the
// overlay copy named; the data edits go off for the run and the second
// load takes the data files. The Data files screen still sees the copy.
@(test)
test_a_broken_data_edit_turns_the_overlay_off_at_start :: proc(t: ^testing.T) {
	edits_directory, error := os.make_directory_temp("", "mine-oh-belowed-broken-edit-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(edits_directory)
	data_edits_reading.directory = edits_directory
	defer reset_data_edits_reading()
	broken := join_save_path(edits_directory, "blocks.sjson")
	testing.expect_value(t, os.write_entire_file(broken, "blocks = ["), nil)
	loaded := Loaded_Configuration{configuration = DEFAULT_CONFIGURATION}

	start, problem := load_start_data(test_data_directory(), loaded, nil)
	testing.expect(t, problem != "")
	testing.expectf(t, strings.contains(problem, broken), "the problem names the overlay copy: %s", problem)
	testing.expect(t, start.arena == nil, "nothing stays loaded")
	testing.expect(t, turn_data_edits_off(problem))
	testing.expect(t, data_edits_reading.off)
	testing.expect_value(t, data_edits_reading.off_problem, problem)
	testing.expect_value(t, reading_data_edits_directory(), "")
	testing.expect_value(t, data_edits_directory(), edits_directory)

	start, problem = load_start_data(test_data_directory(), loaded, nil)
	defer destroy_start_data(&start)
	testing.expect_value(t, problem, "")
	testing.expect(t, start.game_data.arena != nil)
	testing.expect(t, !turn_data_edits_off("again"), "off already: the caller gives up")
}
