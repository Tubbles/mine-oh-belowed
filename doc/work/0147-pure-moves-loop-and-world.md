# 0147: Pure moves, loop and world

Status: todo

## Goal

Queue entry 1 of the architecture audits (`doc/work/0143-architecture-audit.md`, Implementation notes), the loop and world half: definitions that live in the wrong cluster move to the right one. No behaviour change, no signature change beyond the move. The loop audit measured that 172 of the 252 references into the loop cluster are the simulation naming its own types that sit in `loop.odin`; the world audit lists the helpers the world reaches into the simulation for.

## Change

- `Simulation_State`, `Simulation_Event`, `make_simulation`, `destroy_simulation`, `simulation_tick`, `apply_research_result`, `simulation_quest_context` and `simulation_day_ticks` (`loop.odin`, the first 320 lines) move to `simulation_world.odin` or a new `simulation_state.odin`; `tools/code_graph.py` maps the `simulation` prefix to the simulation cluster (loop audit, refactor 1).
- `Box` (`player_collision.odin`) moves to `block_shape.odin`; `coordinate_before`, `rotate_direction` and `camera_world_coordinate` move to `world_chunk.odin`; `tick_world` and `apply_block_changes` move to a world file; `World_Settings` moves to `world_chunk.odin` (world audit, refactor 1).
- `world_settings_from_file` (`ui_world_setup.odin`) moves to the world side next to `World_Settings` (ui audit, refactor 1).
- `place_capsule` (`landing_pad.odin`) moves to the simulation set-up beside `make_simulation`; `landing_pad.odin` keeps the stamp (0144 notes).
- `doc/code_map.md`: the moved names in their new sections, the "Reaches into" records lowered to the new counts (`python3 tools/code_graph.py --check doc/code_map.md` passes with 0 new or grown and the lowered records); `doc/architecture.md` where it names a moved procedure by file.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (1290 tests), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- The item's Implementation notes list the edges cut with the before and after counts.
