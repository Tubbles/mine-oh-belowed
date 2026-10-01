# 0152: Embed Simulation_Content in Game_Content

Status: implemented

## Goal

Queue entry 3 of the architecture audits, the smallest hub change (`doc/audit/loop.md`, refactor 2). `Game_Content` repeats the ten registries of `Simulation_Content` and adds the presentation tables; three procedures copy one into the other (`game_simulation_content`, `session_simulation_content`, `frame_simulation_content`) and `with_schematics_found` is applied in three places because the recipe view depends on the simulation's unlocks. For the engine cut, the content handed to the game side must be one type.

## Change

- `Game_Content` embeds `Simulation_Content` (`using`) instead of repeating its fields; `game_simulation_content` becomes a field read, `session_simulation_content` a one field override, `frame_simulation_content` rebuilt once per frame instead of seven times (loop audit, section 4).
- `with_schematics_found` is applied in one place that the three callers share.
- The literal constructors in tests follow the new shape.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`data_reload_test.odin`, `save_test.odin`, `developer_test.odin` guard it), `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.

## Implementation notes

- `Game_Content` (`loop.odin`) is `using simulation_content: Simulation_Content` plus the presentation tables and the two flags; the ten repeated fields are gone. `content.items` and the other registry reads and writes (`load_game_data`, `reload_developer_kits`, `rebuild_atlases`) work unchanged through `using`. Its embedded `generator` stays nil; only a session's copy sets it. No `Game_Content` literal existed, in tests or elsewhere, so no constructor changed shape.
- The three conversions. Before: `game_simulation_content` copied the ten fields into a new `Simulation_Content`; `session_simulation_content` called it and overrode `technologies`; `frame_simulation_content` called that and set `generator`. After: `game_simulation_content` is gone, its five callers (`benchmark_factory.odin`, `hot_reload.odin` twice, `loop.odin`'s command context, `data_reload_test.odin`) read `content.simulation_content`; `session_simulation_content` copies the embedded value and overrides `technologies`; `frame_simulation_content` is unchanged.
- The seven calls of `frame_simulation_content` became three builds: one in `update_frame` (passed to `apply_debug_actions`, `update_session` and `run_command_ticks`, which covered the debug drop, the tick loop and the command ticks), one in `render_frame` (passed to `draw_session_world`, which used it for the particles and the player overlay, and `session_sound_frame`), and the existing one per queued command in `frame_command_context`. One value for the whole frame does not fit: a `reload` command inside `serve_command_socket` replaces the content arena and the session's technologies (`reload_content`), and a texture edit saved or discarded through the data browser (`serve_data_browser`, between `update_frame` and `render_frame`) rebuilds the item atlas and frees the old `icon_loaded` the copy points to. Each copy now lives within one phase in which nothing replaces content memory; the builder's comment says so. `draw_session_world` now takes that content instead of reading `state.content`; it read only blocks, items, machines and fluids, which the two share.
- `with_schematics_found` is applied in one place, `content_with_found_schematics` (`simulation_world.odin`), which `simulation_tick`, `serve_command_request` (replacing `command_content`, which went) and `make_screen_context` (`.recipes` of it) call. The command path still applies it itself because the benchmark and the command tests build a `Command_Context` from plain content.
- `doc/audit/loop.md` named `game_simulation_content` in three places; they read "game_simulation_content (the field `simulation_content` since 0152)" so `check_docs.py` passes. `doc/code_map.md`: tools -> loop 19 to 18.
