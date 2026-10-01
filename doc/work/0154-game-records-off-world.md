# 0154: The game's records off World, byte compatible

Status: todo

## Goal

Queue entry 3 of the architecture audits, the hub change the engine cut depends on most (`doc/audit/world.md`, refactor 3; `doc/audit/simulation.md`, section 3). `World` (27 fields) carries 13 simulation or content records (statistics, research, shipments, contracts, venture credit, catalogue orders, the five prospecting lists, crate sites, explored, leaf decay) so the tick reaches them through one pointer; 136 of the 145 `world.` field reads in the simulation are those records. For the cut, `World` is the engine's block store and the records are the game's state.

## Change

- One game records struct holds the records; it lives on `Simulation_State` beside `World` (`simulation_state.odin`). `World` keeps blocks, chunks, light, water, streaming state, settings and, for now, `entities` (the cell occupant index of the world audit's refactor 5 comes later).
- Every reader and writer of a record follows (about 40 files: the tick procedures, the screens through `Screen_Context`, the save codec, the remap, the command socket, the diagnostics). Where a procedure took `^World` only for a record, it takes the records (or the one record) instead; where it needs both, both.
- The save bytes stay the same: `save_state.odin` writes each field separately, so the writer and reader address the records struct for those fields in the same order; `simulation_state_hash` covers the records as before. A save written before the change loads unchanged (the hand-back check's save line), and the run comparison test proves it.
- `doc/architecture.md` (World storage, the simulation) and `doc/code_map.md` (the world and simulation state lines, the records lowered: world -> simulation falls by the record readers) follow.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test` (`test_save_load_run_matches_the_original`, `test_prospecting_records_round_trip`, `save_remap_test.odin`, the statistics, quest and venture tests), `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- A save file written by the previous build (the implementer writes one with a test before the change, keeps it under `tmp/`, and loads it after) loads with the same state hash.
