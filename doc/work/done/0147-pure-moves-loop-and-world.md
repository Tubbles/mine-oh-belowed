# 0147: Pure moves, loop and world

Status: implemented

## Goal

Queue entry 1 of the architecture audits (`doc/work/done/0143-architecture-audit.md`, Implementation notes), the loop and world half: definitions that live in the wrong cluster move to the right one. No behaviour change, no signature change beyond the move. The loop audit measured that 172 of the 252 references into the loop cluster are the simulation naming its own types that sit in `loop.odin`; the world audit lists the helpers the world reaches into the simulation for.

## Change

- `Simulation_State`, `Simulation_Event`, `make_simulation`, `destroy_simulation`, `simulation_tick`, `apply_research_result`, `simulation_quest_context` and `simulation_day_ticks` (`loop.odin`, the first 320 lines) move to `simulation_world.odin` or a new `simulation_state.odin`; `tools/code_graph.py` maps the `simulation` prefix to the simulation cluster (loop audit, refactor 1).
- `Box` (`player_collision.odin`) moves to `block_shape.odin`; `coordinate_before`, `rotate_direction` and `camera_world_coordinate` move to `world_chunk.odin`; `tick_world` and `apply_block_changes` move to a world file; `World_Settings` moves to `world_chunk.odin` (world audit, refactor 1).
- `world_settings_from_file` (`ui_world_setup.odin`) moves to the world side next to `World_Settings` (ui audit, refactor 1).
- `place_capsule` (`landing_pad.odin`) moves to the simulation set-up beside `make_simulation`; `landing_pad.odin` keeps the stamp (0144 notes).
- `doc/code_map.md`: the moved names in their new sections, the "Reaches into" records lowered to the new counts (`python3 tools/code_graph.py --check doc/code_map.md` passes with 0 new or grown and the lowered records); `doc/architecture.md` where it names a moved procedure by file.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (1290 tests), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- The item's Implementation notes list the edges cut with the before and after counts.

## Implementation notes

- New files: `simulation_state.odin` (`Simulation_State`, `Simulation_Event`, `make_simulation`, `destroy_simulation`, `place_capsule`, `simulation_day_ticks`) and `world_tick.odin` (`apply_block_changes`, `tick_world`, with the old header of `simulation_world.odin`). `simulation_world.odin` keeps `Simulation_Content` and takes `simulation_tick`, `apply_research_result` and `simulation_quest_context`, so the content tables and the tick order that reads them sit together; a separate `simulation_tick.odin` would have left `simulation_world.odin` holding one struct.
- `loop.odin` keeps `frame_simulation_content` (it takes `Frame_State`), `Save_Setup`, `Tick_Accumulator` and `INITIAL_FLY_CAMERA`.
- `Box` went to `block_shape.odin`; `World_Settings`, `world_settings_from_file`, `camera_world_coordinate`, `coordinate_before` and `rotate_direction` (with its `quarter_turn_ring`) to `world_chunk.odin`, which now imports `core:math` and `world_debug_edit.odin` no longer does.
- `tools/code_graph.py` maps the `simulation` prefix to the simulation cluster.
- Tests stay where they are: no test file tests a moved procedure alone. `rotate_direction` is asserted inside `test_fluid_ports_turn_with_the_footprint` (`fluid_test.odin`), `world_settings_from_file` inside `test_world_settings_round_trip_through_world_file` (`ui_world_setup_test.odin`), both tests of their own cluster's behaviour.
- The save codec fingerprints type names, not files; no type was renamed, so saves keep their bytes.

`python3 tools/code_graph.py --check doc/code_map.md` before, 19 edges, 973 references:

```
world -> simulation 227, world -> ui 118, content -> world 94, simulation -> loop 93, content -> simulation 87,
ui -> tools 49, tools -> loop 46, simulation -> ui 43, content -> ui 42, content -> loop 28, presentation -> ui 28,
world -> loop 27, ui -> loop 25, simulation -> presentation 18, content -> presentation 16, content -> tools 12,
world -> presentation 12, presentation -> loop 6, presentation -> tools 2
```

After, 18 edges, 805 references, 0 new or grown against the updated records:

```
world -> simulation 220, world -> ui 117, content -> simulation 96, content -> world 94, ui -> tools 49,
simulation -> ui 45, content -> ui 42, presentation -> ui 28, content -> loop 19, tools -> loop 19,
simulation -> presentation 18, content -> presentation 16, ui -> loop 14, content -> tools 12,
world -> presentation 12, presentation -> tools 2, presentation -> loop 1, simulation -> loop 1
```

Edges cut: world -> loop 27 to 0 (gone), simulation -> loop 93 to 1, tools -> loop 46 to 19, content -> loop 28 to 19, ui -> loop 25 to 14, presentation -> loop 6 to 1, world -> simulation 227 to 220 (`Box`, `rotate_direction`, `coordinate_before` 29 and `place_capsule` 8 left, the old record undercounted them by 2; the save codec's 27 references to `Simulation_State` and `Simulation_Content` moved here from world -> loop, and `tick_world` adds 3 into `tree_felling.odin` for the leaf decay), world -> ui 118 to 117.

Two records grew, because the names they reference changed cluster, not because of a new reference: content -> simulation 87 to 96 (`reload_simulation` naming `Simulation_State`, `make_simulation`, `destroy_simulation` and `Simulation_Content`, 9 that were content -> loop) and simulation -> ui 43 to 45 (`simulation_tick` naming `Input_Frame`, 2 that were loop -> ui). Both are recorded as accepted in `doc/code_map.md`.
