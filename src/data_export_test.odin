package game

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import "platform"

// Work item 0131: the export of the data files and the data edits, and
// the export on save. Every test writes only under a temporary directory
// it creates and removes.

// A data directory with a file in a directory and a binary file, and an
// overlay copy of the first, under base.
make_data_export_test_files :: proc(t: ^testing.T, base: string) -> (data_directory, edits_directory: string) {
	data_directory = platform.join_path(base, "data_source")
	edits_directory = platform.join_path(base, "edits")
	testing.expect_value(t, platform.make_directory_path(platform.join_path(data_directory, "quests")), nil)
	testing.expect_value(t, platform.make_directory_path(platform.join_path(edits_directory, "quests")), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(data_directory, "quests", "chapter_01.sjson"), "data chapter"), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(data_directory, "icon.png"), "png"), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(edits_directory, "quests", "chapter_01.sjson"), "edited chapter"), nil)
	return data_directory, edits_directory
}

expect_file_text :: proc(t: ^testing.T, path, expected: string, location := #caller_location) {
	data, error := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, error, nil, location)
	testing.expect_value(t, string(data), expected, location)
}

@(test)
test_data_export_copies_pair_every_file :: proc(t: ^testing.T) {
	data_files := [?]Data_File_Entry{{path = "blocks.sjson"}, {path = "quests/chapter_01.sjson", edited = true}}
	edit_files := [?]Data_File_Entry{{path = "quests/chapter_01.sjson"}}
	copies := data_export_copies(data_files[:], edit_files[:], "/game/data", "/state/data_edits", "/sync/mine")
	expected := [?]Data_Export_Copy {
		{source = "/game/data/blocks.sjson", destination = "/sync/mine/data/blocks.sjson"},
		{source = "/game/data/quests/chapter_01.sjson", destination = "/sync/mine/data/quests/chapter_01.sjson"},
		{source = "/state/data_edits/quests/chapter_01.sjson", destination = "/sync/mine/data_edits/quests/chapter_01.sjson", edit = true},
	}
	testing.expect_value(t, len(copies), len(expected))
	for copy_expected, index in expected {
		testing.expect_value(t, copies[index], copy_expected)
	}
}

// data/ and data_edits/ with the files, overwritten where the export held
// an older copy, a file of the export's own left alone, and export.txt
// with the build stamp, the time and the counts.
@(test)
test_an_export_writes_the_data_the_edits_and_the_stamp :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-export-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	data_directory, edits_directory := make_data_export_test_files(t, base)
	export_directory := platform.join_path(base, "sync", "mine")
	testing.expect_value(t, platform.make_directory_path(platform.join_path(export_directory, "data")), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(export_directory, "data", "icon.png"), "old png"), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(export_directory, "notes.txt"), "mine"), nil)

	now := time.unix(1_790_000_000, 0)
	result := export_data_files(data_directory, edits_directory, export_directory, now)
	testing.expect_value(t, result, Data_Export_Result{data_count = 2, edit_count = 1})
	expect_file_text(t, platform.join_path(export_directory, "data", "quests", "chapter_01.sjson"), "data chapter")
	expect_file_text(t, platform.join_path(export_directory, "data", "icon.png"), "png")
	expect_file_text(t, platform.join_path(export_directory, "data_edits", "quests", "chapter_01.sjson"), "edited chapter")
	expect_file_text(t, platform.join_path(export_directory, "notes.txt"), "mine")
	expect_file_text(t, platform.join_path(export_directory, "export.txt"), data_export_stamp_text(BUILD_STAMP, now, result))
	stamp := data_export_stamp_text(BUILD_STAMP, now, result)
	testing.expect(t, strings.contains(stamp, BUILD_STAMP), stamp)
	testing.expect(t, strings.contains(stamp, "exported 2026-09-21 "), stamp)
	testing.expect(t, strings.contains(stamp, "2 data files, 1 data edits"), stamp)

	// Without an overlay directory only the data goes.
	result = export_data_files(data_directory, platform.join_path(base, "no_edits"), export_directory, now)
	testing.expect_value(t, result, Data_Export_Result{data_count = 2})
}

// An empty directory exports nothing and says so; a directory that cannot
// be made stops the export with the path.
@(test)
test_an_empty_export_directory_exports_nothing_and_says_so :: proc(t: ^testing.T) {
	ui: Ui_State
	defer destroy_ui_state(&ui)
	settings: Settings
	browser: Data_Browser
	export_data_browser_files({browser = &browser, ui = &ui, settings = &settings, data_directory = test_data_directory()}, "")
	testing.expect_value(t, len(ui.toasts), 1)
	testing.expect_value(t, ui.toasts[0].text, text("data_files_export_no_directory"))
	testing.expect(t, export_data_files(test_data_directory(), "", "", {}).problem != "")

	base, error := os.make_directory_temp("", "mine-oh-belowed-export-blocked-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	blocked := platform.join_path(base, "file")
	testing.expect_value(t, os.write_entire_file(blocked, "not a directory"), nil)
	result := export_data_files(test_data_directory(), "", blocked, {})
	testing.expect(t, strings.contains(result.problem, blocked), result.problem)
	testing.expect_value(t, result.data_count, 0)
}

// With export on save, a save writes the one edit to the export's
// data_edits/ and a discard deletes it there; with the toggle off the
// export is left alone.
@(test)
test_a_synced_save_writes_the_edit_and_a_synced_discard_removes_it :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-export-sync-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	edits_directory := platform.join_path(base, "edits")
	export_directory := platform.join_path(base, "sync")
	data_edits_reading.directory = edits_directory
	defer reset_data_edits_reading()
	defer clear_missing_reports(&global_string_table)
	ui: Ui_State
	defer destroy_ui_state(&ui)
	settings: Settings
	data_browser := open_test_data_value(t, `blocks = [{id = "stone", hardness = 1.5}]`)
	defer destroy_data_browser(&data_browser)
	browser := &data_browser
	requests: Frame_Requests
	data := Data_Browser_Context{browser = browser, ui = &ui, settings = &settings, data_directory = "/nonexistent/mine-oh-belowed-data", requests = &requests}
	entries := [?]Data_File_Entry{{path = "quests/chapter_09.sjson"}}
	browser.rows = data_tree_rows(entries[:], context.temp_allocator)
	defer browser.rows = nil
	browser.selected = find_data_tree_row(browser.rows, "quests/chapter_09.sjson")
	exported := platform.join_path(export_directory, "data_edits", "quests", "chapter_09.sjson")

	testing.expect(t, set_data_browser_value(browser, find_data_value_row(browser.value_rows, "blocks.0.hardness"), "3"))
	settings.export_directory = export_directory
	save_data_edit(data, edits_directory)
	testing.expect(t, !os.exists(exported), "export on save is off")

	settings.export_on_save = true
	testing.expect(t, set_data_browser_value(browser, find_data_value_row(browser.value_rows, "blocks.0.hardness"), "4"))
	save_data_edit(data, edits_directory)
	overlay, read_error := os.read_entire_file(platform.join_path(edits_directory, "quests", "chapter_09.sjson"), context.temp_allocator)
	testing.expect_value(t, read_error, nil)
	expect_file_text(t, exported, string(overlay))
	testing.expect(t, !browser.export_sync_failed)

	browser.rows[browser.selected].edited = true
	testing.expect_value(t, discard_data_edit(data), Data_File_Categories{data_file_category("quests/chapter_09.sjson")})
	testing.expect(t, !os.exists(platform.join_path(edits_directory, "quests", "chapter_09.sjson")))
	testing.expect(t, !os.exists(exported), "the discard deleted the exported copy")
	testing.expect(t, !browser.export_sync_failed)
	testing.expect_value(t, discard_data_edit(data), Data_File_Categories{})
}

// A failed sync toasts once, not at every save; a sync or an export that
// succeeds clears it.
@(test)
test_a_failed_export_sync_toasts_once :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-export-sync-failure-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	edits_directory := platform.join_path(base, "edits")
	testing.expect_value(t, write_data_edit(edits_directory, "blocks.sjson", "blocks = []"), "")
	blocked := platform.join_path(base, "file")
	testing.expect_value(t, os.write_entire_file(blocked, "not a directory"), nil)
	ui: Ui_State
	defer destroy_ui_state(&ui)
	browser: Data_Browser
	settings := Settings{export_on_save = true, export_directory = blocked}
	data := Data_Browser_Context{browser = &browser, ui = &ui, settings = &settings}
	sync_data_edit_export(data, edits_directory, "blocks.sjson")
	sync_data_edit_export(data, edits_directory, "blocks.sjson")
	testing.expect_value(t, len(ui.toasts), 1)
	testing.expect(t, browser.export_sync_failed)
	// A successful export ends the run of failures too.
	data.data_directory, _ = make_data_export_test_files(t, platform.join_path(base, "export_source"))
	settings.export_directory = platform.join_path(base, "exported")
	export_data_browser_files(data, "")
	testing.expect(t, os.is_file(platform.join_path(base, "exported", "export.txt")))
	testing.expect(t, !browser.export_sync_failed)
	browser.export_sync_failed = true
	settings.export_directory = platform.join_path(base, "sync")
	sync_data_edit_export(data, edits_directory, "blocks.sjson")
	testing.expect(t, !browser.export_sync_failed)
	testing.expect(t, os.is_file(platform.join_path(base, "sync", "data_edits", "blocks.sjson")))
}

// The typed directory, trimmed and with ~/ expanded, becomes the setting,
// a clone the settings own.
@(test)
test_the_typed_export_directory_sets_the_setting :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	set_export_directory(&settings, " /storage/emulated/0/Sync ", "/home/player")
	testing.expect_value(t, settings.export_directory, "/storage/emulated/0/Sync")
	delete(settings.export_directory)
	set_export_directory(&settings, "~/Sync/mine", "/home/player")
	testing.expect_value(t, settings.export_directory, "/home/player/Sync/mine")
	delete(settings.export_directory)
	set_export_directory(&settings, "~/Sync", "")
	testing.expect_value(t, settings.export_directory, "~/Sync")
	delete(settings.export_directory)
}

// Work item 0228: trimmed, ~/ expanded, a relative path refused with the
// setting kept, the same value not a change, "" clears it.
@(test)
test_the_typed_edits_directory_sets_the_setting :: proc(t: ^testing.T) {
	settings := DEFAULT_SETTINGS
	problem, changed := set_edits_directory(&settings, " /storage/emulated/0/Download ", "/home/player")
	testing.expect_value(t, problem, "")
	testing.expect(t, changed)
	testing.expect_value(t, settings.edits_directory, "/storage/emulated/0/Download")
	problem, changed = set_edits_directory(&settings, "/storage/emulated/0/Download", "/home/player")
	testing.expect_value(t, problem, "")
	testing.expect(t, !changed)
	previous := settings.edits_directory
	problem, changed = set_edits_directory(&settings, "~/Download", "/home/player")
	delete(previous)
	testing.expect_value(t, problem, "")
	testing.expect(t, changed)
	testing.expect_value(t, settings.edits_directory, "/home/player/Download")
	problem, changed = set_edits_directory(&settings, "Download", "/home/player")
	testing.expect_value(t, problem, text("data_files_edits_directory_not_absolute"))
	testing.expect(t, !changed)
	testing.expect_value(t, settings.edits_directory, "/home/player/Download")
	problem, changed = set_edits_directory(&settings, "~/Download", "")
	testing.expect_value(t, problem, text("data_files_edits_directory_not_absolute"))
	testing.expect(t, !changed)
	testing.expect_value(t, settings.edits_directory, "/home/player/Download")
	previous = settings.edits_directory
	problem, changed = set_edits_directory(&settings, "", "/home/player")
	delete(previous)
	testing.expect_value(t, problem, "")
	testing.expect(t, changed)
	testing.expect_value(t, settings.edits_directory, "")
	delete(settings.edits_directory)
}

@(test)
test_edits_directory_done_toast_cases :: proc(t: ^testing.T) {
	testing.expect_value(t, edits_directory_done_toast("a problem", true, true, false), "a problem")
	testing.expect_value(t, edits_directory_done_toast("", false, true, false), "")
	testing.expect_value(t, edits_directory_done_toast("", true, true, false), text("data_files_edits_access"))
	testing.expect_value(t, edits_directory_done_toast("", true, true, true), text("data_files_edits_directory_next_start"))
	testing.expect_value(t, edits_directory_done_toast("", true, false, true), text("data_files_edits_directory_next_start"))
}

@(test)
test_export_paths_resolve_and_nest :: proc(t: ^testing.T) {
	testing.expect_value(t, absolute_clean_path("data", "/home/player/game"), "/home/player/game/data")
	testing.expect_value(t, absolute_clean_path("/sync/./mine/../mine/", "/elsewhere"), "/sync/mine")
	testing.expect(t, path_is_within("/game/data", "/game"))
	testing.expect(t, path_is_within("/game", "/game"))
	testing.expect(t, path_is_within("/game", "/"))
	testing.expect(t, !path_is_within("/game/database", "/game/data"))
	testing.expect(t, !path_is_within("/game", "/game/data"))
	working := "/home/player/game"
	edits := "/home/player/.local/state/mine-oh-belowed/data_edits"
	testing.expect_value(t, export_directory_refusal("/sync/mine", "data", edits, working), "")
	testing.expect_value(t, export_directory_refusal("sync", "data", edits, working), text("data_files_export_not_absolute"))
	testing.expect_value(t, export_directory_refusal("~/Sync", "data", edits, working), text("data_files_export_not_absolute"))
	overlaps := text("data_files_export_overlaps")
	testing.expect_value(t, export_directory_refusal("/home/player/game", "data", edits, working), overlaps)
	testing.expect_value(t, export_directory_refusal("/home/player/game/data/", "data", edits, working), overlaps)
	testing.expect_value(t, export_directory_refusal("/home/player/game/data/export", "data", edits, working), overlaps)
	testing.expect_value(t, export_directory_refusal("/home/player/.local/state/mine-oh-belowed", "data", edits, working), overlaps)
	testing.expect_value(t, export_directory_refusal("/home/player/.local/state/mine-oh-belowed", "data", "", working), "")
}

// A copy onto its own source would empty it (os opens the destination
// truncated before reading, 0131). An export into the parent of the data
// directory is refused and the data keeps its bytes, as is a copy whose
// source is its destination, and a sync into the overlay's parent.
@(test)
test_an_export_onto_its_sources_is_refused :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-export-overlap-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	data_directory, edits_directory := make_data_export_test_files(t, base)
	source := platform.join_path(data_directory, "quests", "chapter_01.sjson")

	result := export_data_files(data_directory, edits_directory, base, {})
	testing.expect_value(t, result, Data_Export_Result{problem = text("data_files_export_overlaps")})
	expect_file_text(t, source, "data chapter")
	testing.expect(t, !os.exists(platform.join_path(base, "export.txt")))

	testing.expect(t, strings.contains(copy_exported_file(source, source), text("data_files_export_overlaps")))
	expect_file_text(t, source, "data chapter")

	parent, _ := os.split_path(edits_directory)
	problem := sync_exported_data_edit(data_directory, edits_directory, parent, "quests/chapter_01.sjson")
	testing.expect_value(t, problem, text("data_files_export_overlaps"))
	expect_file_text(t, platform.join_path(edits_directory, "quests", "chapter_01.sjson"), "edited chapter")
}

// The copy goes through a temporary file renamed over the destination,
// with the default permissions: a read only source exports twice, and no
// temporary file stays.
@(test)
test_an_exported_copy_replaces_the_destination_whole :: proc(t: ^testing.T) {
	base, error := os.make_directory_temp("", "mine-oh-belowed-export-copy-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(base)
	source := platform.join_path(base, "source.sjson")
	destination := platform.join_path(base, "export", "data", "source.sjson")
	testing.expect_value(t, os.write_entire_file(source, "read only", os.Permissions_Read_All), nil)
	testing.expect_value(t, copy_exported_file(source, destination), "")
	testing.expect_value(t, copy_exported_file(source, destination), "")
	expect_file_text(t, destination, "read only")
	testing.expect(t, !os.exists(strings.concatenate({destination, ".tmp"}, context.temp_allocator)))
}
