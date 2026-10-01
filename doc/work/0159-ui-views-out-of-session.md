# 0159: Take the UI views out of Session

Status: implemented

## Goal

Refactor 8 of the loop audit (`doc/audit/loop.md`, section 5). `Session` (`session.odin`) holds four UI views beside the simulation, the generator, the streaming and the save setup: `recipe_browser`, `technology_browser`, `statistics_view` and `map_view`. They belong to the ui cluster: one screen reads each, `make_screen_context` hands out pointers to them, `reset_session_views` (`data_reload.odin`) resets them on a data reload, and `end_session` destroys two of them. For the engine cut, `Session` is engine plus simulation only, and the per world UI state lives beside it, owned by the loop. The UI audit's split of `Screen_Context` (refactor 7 there) waits for this and for the request table.

## Change

- One struct for the per session UI state (a full-word name, for example `Session_Views`) holding the four views, with a make, a destroy and a reset procedure beside it in a ui file (the reset takes what the map view's reset reads today: the world and the explored records, so the signature names the simulation state, not the session). `Session` loses the four fields.
- The loop owns one instance beside the session: made when a session starts, destroyed when it ends, reset where `reset_session_views` is called today (the data reload). `make_screen_context` points at the loop's instance. The UI audit (`destroy_ui_audit`, `ui_audit_test.odin`) owns its own instance the same way.
- `reset_session_views` goes away or becomes the struct's reset; `end_session` no longer destroys views. Every caller that reached `session.recipe_browser` and the other three (grep) reads the new struct.
- `doc/architecture.md` (Sessions): one sentence saying the per session UI state is beside the session, not in it. `doc/code_map.md`: the session -> ui references fall; records lowered where the tool lets, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `test_session_views_reset_for_a_reloaded_world` (`ui_session_views_test.odin`, the views reset on reload), `ui_recipe_browser_test.odin`, `ui_technology_browser_test.odin`, the UI audit; `grep -n "recipe_browser\|technology_browser\|statistics_view\|map_view" src/session.odin` prints nothing.

## Notes

- `Session_Views` (`ui_session_views.odin`) with `make_session_views`, `destroy_session_views` (the map view and the recipe browser with its plans cache; the technology browser and the statistics view own no memory) and `reset_session_views(views, simulation: ^Simulation_State)`, which reads the world and `records.explored` for the map's surfaces.
- The instance is `Frame_Interaction.session_views`, not a top level `Frame_State` field: the groups hold the other clusters' fields and the top level the loop's own, and the views are ui cluster state next to `ui` and `ui_images`. `enter_session` makes it, `leave_session` destroys it after `end_session` (also on exit through its defer), `reload_content` (`hot_reload.odin`) resets it after `reload_session` succeeds, the same point in the same between frames step where `reload_session` reset the views before. `reload_session` no longer reaches the views, so `hot_reload.odin` changed too.
- The UI audit holds `views: Session_Views` in place of its four fields; `ui_pointer_test.odin` reads them through it.
- Moved: 14 `session.<view>` references (4 in `make_screen_context`, 2 makes in `start_session`, 2 destroys in `end_session`, 6 in the old `reset_session_views`).
- Records (`doc/code_map.md`, content cluster): world 93 to 92, ui 42 to 40 (the queued entry for the session's views made by `data_reload.odin` is gone), loop 19 to 18. No edge rose. `Frame_Interaction` 22 to 23 fields.
- `test_session_views_reset_for_a_reloaded_world` pins what `reset_session_views` clears. The call site in `reload_content` has no test, as for the other reloads (`doc/code_map.md`).
