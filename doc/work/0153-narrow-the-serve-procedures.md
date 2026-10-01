# 0153: Narrow the serve procedures

Status: implemented

## Goal

Queue entry 3 of the architecture audits (`doc/audit/loop.md`, refactor 3). `serve_data_browser`, `discard_data_edit`, `save_data_edit`, `export_data_browser_files`, `sync_data_edit_export`, `serve_touch_layouts` and `serve_texture_editor` take `^Frame_State` where they need two to six fields, so `data_export.odin` and `touch_overlay.odin` depend on the loop and three tests allocate a 69 field struct to read one. The serve procedures are the engine's request pattern; narrowing them is what lets `Frame_State` split into groups (next item) and the requests become one table later.

## Change

- Each serve procedure takes the fields it uses (the browser, the data directory, the settings, the UI, the touch layouts, the texture editor) instead of `^Frame_State`; `save_data_edit` and `discard_data_edit` return the changed path's category and the loop applies `apply_data_edit_change`.
- The three tests (`data_browser_test.odin`, `data_export_test.odin`, `ui_data_browser_test.odin`) build only what the procedure takes.
- `doc/code_map.md` records lowered (tools -> loop, ui -> loop); `doc/developer_tools.md` or `doc/architecture.md` where it names a serve procedure's shape.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`test_a_data_edit_reports_its_category`, the data browser and export tests, the touch layout editor test), `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md` (lowered records, 0 new or grown).
- The hand-back check's first line still holds: every serve runs between frames and a test reads the draw list after the serve.

## Implementation notes

- Parameter lists, before (all `state: ^Frame_State`) and after:
  - `serve_texture_editor(state)` to `(editor: ^Texture_Editor, ui: ^Ui_State, renderer: Chunk_Renderer, data_directory: string, blocks: Block_Registry)`.
  - `save_texture_edits(state)` to `(editor: ^Texture_Editor, ui: ^Ui_State)`.
  - `serve_data_browser(state)` to `(data: Data_Browser_Context) -> (changed: Data_File_Categories)`.
  - `discard_data_edit(state)` to `(data: Data_Browser_Context) -> Data_File_Categories`.
  - `save_data_edit(state, edits_directory)` to `(data: Data_Browser_Context, edits_directory: string) -> Data_File_Categories`.
  - `export_data_browser_files(state, edits_directory)` to `(data: Data_Browser_Context, edits_directory: string)`.
  - `sync_data_edit_export(state, edits_directory, relative_path)` to `(data: Data_Browser_Context, edits_directory, relative_path: string)`.
  - `serve_touch_layouts(state)` to `(layouts: ^Touch_Layouts, editor: ^Touch_Layout_Editor, ui: ^Ui_State, default_layout: Touch_Overlay_Layout, environment: Configuration_Environment) -> (changed: bool)`: it returns whether the active layout changed, and `run_game` releases the overlay's latches (`release_touch_latches`) when it did, before `render_frame` as before. The release now follows the file write instead of preceding it; the write does not read the overlay.
  - `apply_data_edit_change(state, relative_path) -> Data_File_Category` to `(state, changed: Data_File_Categories)`.
- `Data_Browser_Context` (`data_export.odin`): pointers to the browser, the UI and the settings, and the data directory; no new state. The settings are read only (the export directory and `export_on_save`).
- Save and discard return a category set (empty when nothing was written or deleted) rather than one category, so `serve_data_browser` returns the union and `run_game` passes it to `apply_data_edit_change` right after the serve, still between `update_frame` and `render_frame`. `apply_data_edit_change` takes the set because the category alone is what the loop holds after the serve; it no longer computes or returns the category.
- References cut: tools -> loop 18 to 16 (`Frame_State` in `data_export.odin`). ui -> loop stays 14: its `Frame_State` references are `touch_overlay.odin`'s frame readers (`touch_overlay_aims`, `frame_touch_layout` and others), which this item does not touch, and the ui tests are not counted by the graph.
- Tests: `data_export_test.odin` and `ui_data_browser_test.odin` build a `Ui_State`, a `Settings` and a `Data_Browser` (the UI test serves the audit's browser through a pointer, so the copy back went). Review additions: the UI test pins the serve's return after saving `game.sjson` (`{data_file_category("game.sjson")}`), and the export sync test pins the discard's return (`{category}` after the delete, `{}` after a second discard whose delete fails). In `data_browser_test.odin` the save test builds the same; its reload assertions read the returned set (empty after the failed save, `.Content` for `blocks.sjson` only). `test_a_data_edit_reports_its_category` and `test_a_saved_strings_edit_shows_at_once` keep their `Frame_State`, since `apply_data_edit_change` and the strings reload need one; the first checks the category through `data_file_category` and then applies it.
- Small differences in order: a reload's toast now follows the save's or discard's own toasts instead of sitting between them, and a discard and a save of the same category in one serve (both requests set before one serve) reload once instead of twice.
