package game

import "core:testing"

// Work item 0129: Back (B, and the touch row's Back) closes an open file
// first and the screen second. The file closes between frames: the Back
// frame's draw list still points into the file's memory, and every text
// in it must read as execute_draw_list reads it (a close during the UI
// pass crashed the game there).
@(test)
test_data_files_back_closes_the_file_then_the_screen :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	browser.selected = find_data_tree_row(browser.rows, "shaders/chunk.fs")
	testing.expect(t, browser.selected >= 0)
	open_data_browser_file(browser, test_data_directory())
	testing.expect(t, browser.open)
	testing.expect(t, len(browser.lines) > 0)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Pause)
	push_screen(&state.screens, .Developer)
	push_screen(&state.screens, .Data_Files)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], "shaders/chunk.fs"))
	screen_test_frame(audit, &state, {back = true})
	testing.expect(t, browser.open)
	testing.expect(t, browser.close_requested)
	testing.expect_value(t, top_screen(state.screens), Screen.Data_Files)
	testing.expect(t, draw_list_has_text(state.draw_list[:], browser.lines[0]))
	checksum: u32
	for command in state.draw_list {
		for byte_value in transmute([]byte)command.text {
			checksum += u32(byte_value)
		}
	}
	testing.expect(t, checksum > 0)
	apply_data_browser_close_request(browser)
	testing.expect(t, !browser.open)
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Developer)
}

// A long file declares every visible row for the focus but draws only
// those in the scroll region (the strings file has about 1,600 keys).
@(test)
test_data_files_draw_only_the_rows_in_view :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	browser.selected = find_data_tree_row(browser.rows, "strings/en.sjson")
	open_data_browser_file(browser, test_data_directory())
	defer close_data_browser_file(browser)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	screen_test_frame(audit, &state, {})
	texts := 0
	for command in state.draw_list {
		if command.kind == .Text {
			texts += 1
		}
	}
	testing.expect(t, len(state.widgets) > len(browser.value_rows))
	testing.expect(t, texts < 100)
}

// The problem line puts the error before the path and wraps, and the
// title of a file read from the overlay carries the edited tag.
@(test)
test_data_files_problem_wraps_and_the_title_shows_the_overlay :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	browser.selected = find_data_tree_row(browser.rows, "game.sjson")
	open_data_browser_file(browser, test_data_directory())
	defer close_data_browser_file(browser)
	browser.file_problem = "Cannot parse Unexpected_Token: /storage/emulated/0/Android/data/io.github.tubbles.mineohbelowed/files/state/mine-oh-belowed/data_edits/quests/chapter_01.sjson"
	browser.shows_overlay = true
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], "Cannot parse Unexpected_Token:"))
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("data_files_edited")))
}

@(test)
test_data_files_confirm_expands_a_directory_and_opens_a_file :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	quests := find_data_tree_row(browser.rows, "quests")
	chapter := find_data_tree_row(browser.rows, "quests/chapter_01.sjson")
	screen_test_frame(audit, &state, {})
	state.focus = data_row_id(quests)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, browser.expanded[quests])
	state.focus = data_row_id(chapter)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, browser.open_requested)
	testing.expect_value(t, browser.selected, chapter)
}

// The id the tree gives a row inside the screen's panel.
data_row_id :: proc(row: int) -> Ui_Id {
	return ui_hash(ui_hash(0, "data_files", -1), "data_row", row)
}
