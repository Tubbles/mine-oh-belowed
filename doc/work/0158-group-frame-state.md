# 0158: Group Frame_State into sub-structs

Status: implemented

## Goal

Refactor 5 of the loop audit (`doc/audit/loop.md`, sections 2 and 5). `Frame_State` (`loop.odin`) has 74 top level fields (69 at the audit); about twelve belong to the loop, the rest are input and UI, presentation, developer tools and hot reload state parked there because the loop lives for the whole run. The presentation group is the engine's renderer state, so the grouping is a prerequisite of the engine cut.

## Change

- Four sub-structs along the audit's table in section 2, re-derived from the current struct by the implementer (the table predates `input_backend` and other fields): an input and UI group, a presentation group, a developer tools group, a hot reload group. The loop's own fields (config, content, base generator, session, frame timing, quit request, directories, environment, settings) stay top level. Names are full words (`input`, `presentation`, `developer`, `reload` or better); no `using`, since the point is that a reader sees which group a field belongs to.
- Procedures outside `loop.odin` that take `^Frame_State` or `Frame_State` take their group instead where one group covers what they read and write (`touch_overlay.odin` reads the input group plus the session, the settings, the render camera and the tick count: either a small struct the loop builds or the group plus parameters, the implementer chooses and says why). The hot reload procedures rebuild fields of every group and keep `^Frame_State`; the item's notes say so. The notes record how many procedures outside `loop.odin` took the whole state before and after (`grep -n "Frame_State" src/*.odin | grep -v loop.odin`).
- `Screen_Context` pointers into the moved fields (`settings`, `quit_requested`, `screenshot_requested`, `reload_requested`, `title`, `diagnostics_page`, `show_world_overlay`, `texture_editor`, `data_browser`, `touch_layouts`, `touch_layout_editor`, `biome_banner`) point at the fields in their groups; `make_screen_context` is the one place that changes.
- The destroy order in `run_game` is unchanged: every `defer` keeps its position, only the field paths change. The implementer reads the defers at HEAD and after and says in the report that the order is the same.
- `doc/architecture.md` (Frame and tick, or wherever `Frame_State` is described) names the groups in one sentence; `doc/code_map.md` records lowered where references leave an edge, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `Frame_State` has at most about 16 top level fields; a playtest (the user) of the pause menu, the settings, a data reload and a quit to title then exit, since the loop has no window under test.

## Notes

`Frame_State` had 69 top level fields at b2757f9 (the 74 above was a miscount; `doc/code_map.md` said 69). It now has 16: the loop's 12 and the four groups. The table follows the audit's section 2 with every field's readers and writers grepped (`state.<field>` in `loop.odin`, `hot_reload.odin`, `touch_overlay.odin` and the tests; the loop names the state `state` everywhere).

| Group | Type, field | Fields | Count |
|---|---|---|---|
| loop | top level | config, content, base_generator, session, frame_seconds, frame_times, frame_tick_count, quit_requested, data_directory, environment, settings, stored_settings | 12 |
| input and UI | `Frame_Interaction`, `interaction` | biome_banner, title, input_backend, sdl3_input, input, previous_input, touch_overlay, touch_overlay_forced, haptic, vibrator, system_keyboard_available, system_keyboard_shown, world_action_guard, bindings, input_bindings, ui, ui_images, fonts, font_cache, cursor_enabled, touch_layouts, touch_layout_editor | 22 |
| presentation | `Frame_Presentation`, `presentation` | sprint_kick, render_camera, window_settings, monitor_size, window_scale, platform, renderer, item_atlas, ui_icon_atlas, belt_renderer, model_renderer, particles, particle_memory, particle_renderer, player_model, player_animation, audio, sound_memory | 18 |
| developer tools | `Frame_Developer_Tools`, `developer` | diagnostics_page, show_world_overlay, command_server, command_control, command_socket_path, screenshot_directory, screenshot_requested, texture_editor, data_browser | 9 |
| hot reload | `Frame_Reload`, `reload` | content_arena, data_watch, watch_data_flag, binding_overrides, bindings_arena, retired_strings, retired_font_arenas, reload_requested | 8 |

Choices:

- The input group is `interaction`, not `input`: `input` is already the frame's `Input_Frame` inside it (`state.interaction.input`).
- Field names inside the groups are unchanged (`state.reload.reload_requested`, not `state.reload.requested`), so a grep for the old name still finds every use and `Screen_Context` keeps its field names.
- Hot reload writes into every group (fonts, bindings, the renderers, the atlases, the touch overlay's latches, the theme on the UI). `Frame_Reload` holds only the reload's own bookkeeping; a field the reload rebuilds stays with the group that reads it every frame: fonts and bindings in `interaction`, the renderers, atlases and audio in `presentation`.
- `ui_icon_atlas` is read by the UI pass (`run_ui_frame`'s icon atlas) and written by the theme reload; it is a texture like `item_atlas`, so `presentation`.
- `render_camera` is written by the world draw and read by the touch overlay and the mining ring: `presentation`, its writer.
- `diagnostics_page` is written by F3 (`apply_debug_actions`), the Developer screen and `leave_session`, and read by the world draw (the Render page's water count) and `apply_cursor_mode`: `developer`.
- `monitor_size` and `platform` are read by the settings screen through `Screen_Context` and written by the display code: `presentation`.
- `command_socket_path` and `screenshot_directory` are owned paths of the command socket, built and freed by `start_command_frame_state` and `destroy_command_frame_state`: `developer`, not with the loop's `data_directory`.
- `retired_font_arenas` moved from beside the fonts to `reload`, its only writer and freer (`reload_fonts`, `destroy_hot_reload_state`).

The touch overlay takes `Touch_Overlay_Context` (`touch_overlay.odin`), which `touch_overlay_context` in `loop.odin` builds at each use: a pointer to the input group (the overlay writes `touch_overlay` in `read_touch_overlay_frame`), the session, pointers to the content and the settings, and copies of the render camera, the frame time and the tick count. A struct rather than the group plus parameters, because its eight procedures call each other (`touch_interaction_frame` calls `frame_hud_touch_buttons`, which calls `frame_hud_touch_buttons_shown`, which calls `touch_overlay_on`) and each would carry the same five extra parameters. It is built at each call, not once per frame, so each reads the fields as they are at that point (the tick count and camera are the last frame's while the input is read, as before).

Procedures outside `loop.odin` that take the whole state (`grep -n "Frame_State" src/*.odin | grep -v loop.odin`, tests and comments left out): 30 before (22 in `hot_reload.odin`, 8 in `touch_overlay.odin`), 22 after (the hot reload procedures, which rebuild fields of every group and keep `^Frame_State`). `data_export.odin` and `diagnostics.odin` named it no more since 0157 and the narrowed serve procedures. The tests that build a `Frame_State` (`data_browser_test.odin`, `developer_test.odin`) keep it, since `apply_data_edit_change` keeps it.

`make_screen_context` is the one place the `Screen_Context` pointers changed; the pointer types are the same. The `defer` lines of `run_game` keep their order, only their field paths changed.

Records (`doc/code_map.md`): ui -> loop fell from 14 to 9. The 8 `Frame_State` references of `touch_overlay.odin` left; `Touch_Overlay_Context` adds 3 (`Frame_Interaction` and `Game_Content` in `loop.odin`, `Session` in `session.odin`). No edge rose.

