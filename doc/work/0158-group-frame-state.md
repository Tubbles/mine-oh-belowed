# 0158: Group Frame_State into sub-structs

Status: todo (after 0157)

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
