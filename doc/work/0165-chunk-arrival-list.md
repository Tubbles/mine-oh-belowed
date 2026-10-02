# 0165: Chunk arrivals as an arrival list

Status: folded into 0177 on 2026-10-02 (a chunk's arrival becomes the chunk ready event of the lockstep driver's queued inputs; `doc/log/2026-10-02.md`)

## Goal

Refactor 4 of the world audit (`doc/audit/world.md`, section 5). `insert_generated_chunk` (`world_streaming.odin`) stores the chunk, queues light, marks neighbours, and then registers the arrival's veins, outcrops, crate sites, explored column and added vein stamps into the game's records straight from the frame, which is a frame write into simulation state and 12 of streaming's references into the records. For the cut, a chunk arrival is tick input at a defined tick: the engine stores the chunk, the game registers what it brings at the start of the next tick.

## Change

- One insertion procedure stores the chunk, queues light and marks neighbours, and appends the arrival (the chunk coordinate and what the generator produced for the game: veins, outcrops, crate sites, the explored column, added vein stamps) to an arrival list on the simulation state; `receive_generated_chunks` and `load_chunk_now` both use it.
- The tick drains the list first (`simulation_tick`, before `tick_entities_on_world`): the registrations run then, in arrival order, so a vein registers one tick after its chunk lands. The item's notes name what a reader between the arrival and the tick sees (a HUD vein read sees nothing for that tick) and the tests that pin the delay.
- The list is not saved: on load every chunk comes through the same path and registers on the next tick, as today's load path registers at insertion; the save test's state hash after a load plus a tick must equal the original's.
- `doc/architecture.md` (Threads and chunk streaming, Simulation) states the arrival list; `doc/code_map.md`: the world -> simulation record falls by streaming's record references; never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; the tests that call `load_chunk_now` (`prospecting_test.odin`, `command_test.odin`, `schematic_test.odin`, `save_test.odin`) adjusted to run the tick that drains the list; `test_streaming_loads_meshes_and_unloads`, `test_vein_lookup_same_from_each_overlapping_chunk`, `test_explored_surface_is_recorded_for_unloaded_chunks`; the factory benchmark's two sizes keep their state hash after the same number of ticks (the implementer records it); a playtest (the user) walking into new chunks with the HUD's vein line showing, and a save and load.
