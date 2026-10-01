# 0159: Take the UI views out of Session

Status: todo (after 0158)

## Goal

Refactor 8 of the loop audit (`doc/audit/loop.md`, section 5). `Session` (`session.odin`) holds four UI views beside the simulation, the generator, the streaming and the save setup: `recipe_browser`, `technology_browser`, `statistics_view` and `map_view`. They belong to the ui cluster: one screen reads each, `make_screen_context` hands out pointers to them, `reset_session_views` (`data_reload.odin`) resets them on a data reload, and `end_session` destroys two of them. For the engine cut, `Session` is engine plus simulation only, and the per world UI state lives beside it, owned by the loop. The UI audit's split of `Screen_Context` (refactor 7 there) waits for this and for the request table.

## Change

- One struct for the per session UI state (a full-word name, for example `Session_Views`) holding the four views, with a make, a destroy and a reset procedure beside it in a ui file (the reset takes what the map view's reset reads today: the world and the explored records, so the signature names the simulation state, not the session). `Session` loses the four fields.
- The loop owns one instance beside the session: made when a session starts, destroyed when it ends, reset where `reset_session_views` is called today (the data reload). `make_screen_context` points at the loop's instance. The UI audit (`destroy_ui_audit`, `ui_audit_test.odin`) owns its own instance the same way.
- `reset_session_views` goes away or becomes the struct's reset; `end_session` no longer destroys views. Every caller that reached `session.recipe_browser` and the other three (grep) reads the new struct.
- `doc/architecture.md` (Sessions): one sentence saying the per session UI state is beside the session, not in it. `doc/code_map.md`: the session -> ui references fall; records lowered where the tool lets, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `data_reload_test.odin` (the views reset on reload), `ui_recipe_browser_test.odin`, `ui_technology_browser_test.odin`, the UI audit; `grep -n "recipe_browser\|technology_browser\|statistics_view\|map_view" src/session.odin` prints nothing.
