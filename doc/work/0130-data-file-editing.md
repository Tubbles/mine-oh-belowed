# 0130: Editing values in the data file tree

Status: todo

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
