package game

import "core:encoding/json"
import "core:os"
import "core:testing"
import "platform"

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

// The id the value tree gives a row, and a button's, inside the panel.
value_row_id :: proc(row: int) -> Ui_Id {
	return ui_hash(ui_hash(0, "data_files", -1), "value_row", row)
}

data_files_button_id :: proc(key: string) -> Ui_Id {
	return ui_hash(ui_hash(0, "data_files", -1), text(key), -1)
}

state_has_toast :: proc(state: Ui_State, key: string) -> bool {
	for toast in state.toasts {
		if toast.text == text(key) {
			return true
		}
	}
	return false
}

// Work item 0130: Confirm flips a boolean in the frame, but Save only
// asks: the frame loop saves between frames (the save reloads what the
// file feeds, the strings among them, which the frame's draw list may
// point into). Every text of the Save frame reads as the draw reads it;
// then serve_data_browser saves into the test's edits directory and the
// next frame's texts read too.
@(test)
test_data_files_save_waits_for_the_frame_loop :: proc(t: ^testing.T) {
	edits_directory, error := os.make_directory_temp("", "mine-oh-belowed-save-frame-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(edits_directory)
	data_edits_reading.directory = edits_directory
	defer reset_data_edits_reading()
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	browser.selected = find_data_tree_row(browser.rows, "game.sjson")
	open_data_browser_file(browser, test_data_directory())
	defer close_data_browser_file(browser)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	flag := find_data_value_row(browser.value_rows, "all_recipes_unlocked")
	testing.expect(t, flag >= 0)
	screen_test_frame(audit, &state, {})
	state.focus = value_row_id(flag)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, json_values_equal(data_value_at_row(browser.value, browser.value_rows, flag), json.Boolean(true)))
	testing.expect(t, browser.unsaved)
	testing.expect_value(t, browser.value_selected, flag)
	loaded_text := browser.loaded_text
	state.focus = data_files_button_id("data_files_save")
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, browser.save_requested)
	testing.expect(t, browser.open)
	testing.expect(t, browser.unsaved)
	testing.expect_value(t, browser.loaded_text, loaded_text)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("data_files_unsaved")))
	testing.expect(t, draw_list_text_checksum(state) > 0)

	// The frame loop's turn, on the audit's browser.
	frame_ui: Ui_State
	defer destroy_ui_state(&frame_ui)
	settings: Settings
	changed := serve_data_browser({browser = browser, ui = &frame_ui, settings = &settings, data_directory = test_data_directory()})
	testing.expect_value(t, changed, Data_File_Categories{data_file_category("game.sjson")})
	testing.expect(t, !browser.save_requested)
	testing.expect(t, !browser.unsaved)
	testing.expect(t, browser.open)
	testing.expect(t, os.is_file(platform.join_path(edits_directory, "game.sjson")))
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_text_checksum(state) > 0)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("data_files_edited")))
	testing.expect(t, !draw_list_has_text(state.draw_list[:], text("data_files_unsaved")))
}

// Confirm on a number opens the keyboard with its value; Done sets it,
// the focus returns to the row; a value that does not parse keeps the old
// one and toasts; Back with unsaved changes drops them and says so.
@(test)
test_data_files_keyboard_sets_a_value :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	browser.selected = find_data_tree_row(browser.rows, "game.sjson")
	open_data_browser_file(browser, test_data_directory())
	defer close_data_browser_file(browser)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	tick_rate := find_data_value_row(browser.value_rows, "tick_rate")
	testing.expect(t, tick_rate >= 0)
	screen_test_frame(audit, &state, {})
	state.focus = value_row_id(tick_rate)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, state.keyboard.field, value_row_id(tick_rate))
	testing.expect_value(t, browser.editing_row, tick_rate)
	testing.expect_value(t, text_field_text(&browser.value_field), "60")
	testing.expect_value(t, browser.value_field.characters, Text_Field_Characters.Number)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], "tick_rate"))
	text_field_set(&browser.value_field, "30")
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, state.keyboard.field, Ui_Id(0))
	testing.expect_value(t, browser.editing_row, -1)
	testing.expect(t, json_values_equal(data_value_at_row(browser.value, browser.value_rows, tick_rate), json.Integer(30)))
	testing.expect(t, browser.unsaved)
	testing.expect_value(t, top_screen(state.screens), Screen.Data_Files)
	testing.expect(t, !browser.close_requested, "Done ends the entry, not the file")
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, value_row_id(tick_rate))

	screen_test_frame(audit, &state, {confirm = true})
	text_field_set(&browser.value_field, "-")
	screen_test_frame(audit, &state, {back = true})
	testing.expect(t, state_has_toast(state, "data_files_bad_number"))
	testing.expect(t, json_values_equal(data_value_at_row(browser.value, browser.value_rows, tick_rate), json.Integer(30)))

	screen_test_frame(audit, &state, {back = true})
	testing.expect(t, browser.close_requested)
	testing.expect(t, state_has_toast(state, "data_files_changes_dropped"))
}

// Work item 0131: the export directory field opens the keyboard and Done
// sets the setting, the focus back on the field; the toggle flips Export
// on save; Export only asks, the frame loop exports between frames.
@(test)
test_data_files_export_directory_toggle_and_button :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	browser := &audit.data_browser
	defer delete(audit.settings.export_directory)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	push_screen(&state.screens, .Data_Files)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("data_files_export_directory_none")))
	field := data_files_button_id("data_files_export_directory")
	state.focus = field
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect_value(t, state.keyboard.field, field)
	testing.expect(t, browser.editing_export_directory)
	screen_test_frame(audit, &state, {})
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("data_files_export_directory")))
	text_field_set(&browser.export_field, "/sync/mine")
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, state.keyboard.field, Ui_Id(0))
	testing.expect(t, !browser.editing_export_directory)
	testing.expect_value(t, audit.settings.export_directory, "/sync/mine")
	testing.expect_value(t, top_screen(state.screens), Screen.Data_Files)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.focus, field)
	testing.expect(t, draw_list_has_text(state.draw_list[:], "/sync/mine"))

	state.focus = data_files_button_id("data_files_export_on_save")
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, audit.settings.export_on_save)
	state.focus = data_files_button_id("data_files_export")
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, browser.export_requested)
	browser.export_requested = false
}
