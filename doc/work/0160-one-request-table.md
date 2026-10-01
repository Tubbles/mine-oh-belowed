# 0160: One request table between frames

Status: todo (after 0159)

## Goal

Refactor 7 of the loop audit (`doc/audit/loop.md`, section 5) and the engine's request pattern (`doc/architecture.md`, Frame and tick; the hand-back check's first line). Today the screens leave requests in many places: `Screen_Context` hands out four pointers (`quit_requested`, `save_requested`, `screenshot_requested`, `reload_requested`), the data browser keeps six flags of its own (close, refresh, open, discard, save, export), the texture editor and the touch layouts keep `save_requested` and `write_requested`, and the loop serves them in an order that only `run_game` shows: the texture editor, then the data browser, then the touch layouts before the draw; the session request, the data watch and the reload after it; the screenshot and the save at their own places. The order matters (a data browser close before a discard; the reload after the draw, because it frees memory a frame draws from), and the rule that memory is freed only between frames lives in that order.

## Change

- One request set (a `bit_set` over an enum of frame requests, name it after what it is, for example `Frame_Request` and `Frame_Requests`) on the loop, reached from the screens through one pointer on `Screen_Context` in place of the four request pointers. The data browser's, the texture editor's and the touch layouts' flags become members of the set where a screen sets them and the loop serves them; a flag an editor serves for itself inside its own pass (read `apply_data_browser_close_request` and decide) stays as it is and is named in the notes.
- One serve procedure in `loop.odin` that runs the set's members in a documented order between frames, the same order as today: before the draw the data browser (close, discard, save, export, refresh, open), the texture editor, the touch layouts; after the draw the screenshot, the session request, the reload. The save keeps its place after the ticks (it needs the tick). The order is written once as a comment on the procedure and once in `doc/architecture.md` (Frame and tick), and nowhere else.
- `Screen_Context` loses the four pointers; `make_screen_context` sets the one. The screens that set a request (`ui_screens.odin` pause menu, `ui_developer.odin`, `ui_data_browser.odin`, `ui_texture_editor.odin`, `ui_touch_layout_editor.odin`) set a member. Tests that read a request flag after a frame (`ui_data_browser_test.odin`, `ui_touch_layout_editor_test.odin`, `developer_test.odin`) read the set.
- A test runs a frame that sets a data browser request, serves the set, and reads the draw list afterwards (hand-back check line 1), as the existing data browser tests do; keep or extend them rather than adding a parallel one.
- `doc/code_map.md`: records lowered where the tool lets, never raised silently; the `loop.odin` entry names the serve procedure.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `ui_data_browser_test.odin` (draw list after the serve), `ui_touch_layout_editor_test.odin`, `developer_test.odin`; a playtest (the user) of a data edit save and discard, a texture editor save, a touch layout edit, a screenshot, a reload and a quit.
