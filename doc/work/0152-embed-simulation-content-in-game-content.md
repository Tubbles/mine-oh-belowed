# 0152: Embed Simulation_Content in Game_Content

Status: todo

## Goal

Queue entry 3 of the architecture audits, the smallest hub change (`doc/audit/loop.md`, refactor 2). `Game_Content` repeats the ten registries of `Simulation_Content` and adds the presentation tables; three procedures copy one into the other (`game_simulation_content`, `session_simulation_content`, `frame_simulation_content`) and `with_schematics_found` is applied in three places because the recipe view depends on the simulation's unlocks. For the engine cut, the content handed to the game side must be one type.

## Change

- `Game_Content` embeds `Simulation_Content` (`using`) instead of repeating its fields; `game_simulation_content` becomes a field read, `session_simulation_content` a one field override, `frame_simulation_content` rebuilt once per frame instead of seven times (loop audit, section 4).
- `with_schematics_found` is applied in one place that the three callers share.
- The literal constructors in tests follow the new shape.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`data_reload_test.odin`, `save_test.odin`, `developer_test.odin` guard it), `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
