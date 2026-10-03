# 0130: Editing values in the data file tree

Status: implemented

## Goal

The editing half of the data file browser (0129, asked 2026-09-30): change a value in an SJSON file from the couch or the phone, save it to the overlay (never the data file), and see it in the game at once.

## Change

- In the value tree of an open SJSON file: Confirm on a boolean flips it; on a number or a string it opens the on screen keyboard (`ui_text_field`, 0121's Save as is the precedent) prefilled with the value; Done sets it. A number field accepts digits, `-` and `.` (a character class on `Text_Field` beside `digits_only`); an integer stays an integer and a float a float (a value typed without a point into an integer leaf stays integer); a value that does not parse keeps the old one and toasts. Strings take what the keyboard has (letters, digits, space, `-_.`); the doc names that limit. Array elements: Duplicate (a copy of the selected element after it) and Remove; objects get no new keys, since a loader takes fixed keys anyway.
- Save writes the tree as SJSON through `json.marshal` (`spec = .SJSON`, keys unquoted, `=`, tabs, one element per line, the style of `data/game.sjson`) to the overlay path (`data_edits_directory`, `make_directory_path`, `os.write_entire_file`), then calls `apply_data_edit_change`, so a presentation file shows at once and a content file marks the data changed for the Reload button (or reloads with watch_data all). The comments of the data file are not in the overlay copy: reconciling an overlay into the checked in file is done outside the game, by hand or by an agent, against the data file, which is the point of the overlay (DESIGN.md, Editors).
- The file view shows an "unsaved" marker while the tree differs from what was loaded; Back drops unsaved changes (a toast says so), Save keeps them. Discard edit (0129) stays.
- The save is served by the frame loop between frames like the touch layout editor's requests (0121, `apply_touch_layout_request`), never inside the screen's draw, since the reload frees arenas the draw list may point into.
- Docs: `doc/ui.md` (the editing controls, the keyboard's limits, unsaved changes), `doc/architecture.md` (the overlay loses comments, reconciliation outside).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: the SJSON text written for a tree parses back to an equal tree, integers stay integers; a boolean flip, a number set, a string set, a duplicate and a remove change the tree as expected; a bad number keeps the value; a save writes under a temporary edits directory and asks for the category's reload; the audit covers the file view with the keyboard open.
- The user: set a recipe's `seconds` on the phone, Save, Reload data, craft it; edit `strings/en.sjson`, Save, see the text change at once; Discard edit, see it return.

## Implementation notes

- The SJSON is written by `sjson_text` (`src/sjson_text.odin`), not `json.marshal`: marshal prints a float 0.5 as `0.5000000000000000` and every container on lines of its own, far from the style of `data/game.sjson`. The writer gives the root without braces, bare keys with `=`, tabs, a container of leaves on one line and any other container one member per line, integers as integers and floats with a point. Keys come in name order (the parsed object is a map). A test round trips every shipped SJSON file.
- An edit changes the parsed `json.Value`; a flip or a set replaces only its row's text, Duplicate and Remove build the rows again. Each row knows its parent row and its array index. "Unsaved" compares the tree's written text with the text as loaded or last saved, so undoing an edit by hand clears it.
- `Text_Field.digits_only` became `characters: Text_Field_Characters` (`Printable`, `Digits`, `Number`). `TEXT_FIELD_CAPACITY` went from 64 to 512 for the strings file's long lines. A string with a character past printable ASCII (the strings file's `×`) or longer than 512 is not offered for editing and toasts "This value cannot be edited here", since the field would drop those characters.
- A number typed with a point or an exponent into an integer leaf becomes a float (the spec only fixed the case without a point). The number field takes `+`, `e` and `E` besides the digits, `-` and `.`, so a float written as `1e-05` edits. An integer outside the i64 range and a float that is not finite are refused with the bad number toast.
- Duplicate and Remove act on the value row last activated (Confirm or a tap), the selection rule of 0129's file rows; the copy becomes the selection after Duplicate, nothing after Remove.
- The keyboard entry shows the value's place (`recipes.3.seconds`) and the typed text in one field two rows tall (the end of a longer string); a third row pushed the keys off the Deck's screen at interface scale 1.5.
- The edits apply in the frame (they free nothing); only Save is served between frames, with the test `test_data_files_save_waits_for_the_frame_loop`.
- A content file's Save asks for the content reload at once (`apply_data_edit_change` from 0129, as Discard does), not only the Reload button's mark the spec named; with `watch_data = all` that is the same, otherwise the edit shows sooner.
- Beyond the spec (review): a broken overlay copy no longer stops the game at start. `load_start_data` (`main.odin`) loads the fonts, bindings, game config, strings and game data; when it fails with the overlay read, `turn_data_edits_off` turns the overlay off for the run and the load runs again (the chunk shaders and the UI theme fall back alike). A toast at start and a notice on the Data files screen ("Data edits are off after a failed load: <problem>. Discard the file and restart") say so. The overlay state is thread local (`data_edits_reading`), which lets a test give its thread a temporary edits directory.
- The copy is written to `<path>.tmp` and renamed over the path. The writer quotes the keys `true`, `false`, `null`, `Infinity` and `NaN`. Discard edit toasts dropped unsaved changes as Back does. `reload_strings` replaces the active string table (`active_string_table`), the global one in the game.
- Tests: `test_sjson_text_parses_back_to_an_equal_tree`, `test_data_value_edits_change_the_tree`, `test_data_value_elements_duplicate_and_remove`, `test_a_data_edit_save_writes_the_overlay_and_asks_for_the_reload`, `test_a_saved_strings_edit_shows_at_once`, `test_a_broken_data_edit_turns_the_overlay_off_at_start`, `test_data_files_save_waits_for_the_frame_loop` (one frame through `serve_data_browser`, then the draw list read), `test_data_files_keyboard_sets_a_value`; the audit's "data files, a chapter edited", "data files, data edits off" (and its touch row) and "data files, a value under the keyboard" (the game's keys and the system keyboard).
