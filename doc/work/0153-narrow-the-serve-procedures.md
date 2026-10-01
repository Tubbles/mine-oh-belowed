# 0153: Narrow the serve procedures

Status: todo

## Goal

Queue entry 3 of the architecture audits (`doc/audit/loop.md`, refactor 3). `serve_data_browser`, `discard_data_edit`, `save_data_edit`, `export_data_browser_files`, `sync_data_edit_export`, `serve_touch_layouts` and `serve_texture_editor` take `^Frame_State` where they need two to six fields, so `data_export.odin` and `touch_overlay.odin` depend on the loop and three tests allocate a 69 field struct to read one. The serve procedures are the engine's request pattern; narrowing them is what lets `Frame_State` split into groups (next item) and the requests become one table later.

## Change

- Each serve procedure takes the fields it uses (the browser, the data directory, the settings, the UI, the touch layouts, the texture editor) instead of `^Frame_State`; `save_data_edit` and `discard_data_edit` return the changed path's category and the loop applies `apply_data_edit_change`.
- The three tests (`data_browser_test.odin`, `data_export_test.odin`, `ui_data_browser_test.odin`) build only what the procedure takes.
- `doc/code_map.md` records lowered (tools -> loop, ui -> loop); `doc/developer_tools.md` or `doc/architecture.md` where it names a serve procedure's shape.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`test_a_data_edit_reports_its_category`, the data browser and export tests, the touch layout editor test), `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md` (lowered records, 0 new or grown).
- The hand-back check's first line still holds: every serve runs between frames and a test reads the draw list after the serve.
