package game

import "core:encoding/json"
import "core:os"
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
