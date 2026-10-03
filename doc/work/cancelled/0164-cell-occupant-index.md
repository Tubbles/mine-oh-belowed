# 0164: A cell occupant index owned by the world

Status: closed in 0174 on 2026-10-03 (folded into it on 2026-10-02: the index is per foundation frame cell, `Frame_Table.occupants` in `world_frame.odin`; the raycast and the water read it, the light keeps `World.entity_lights`; `doc/log/2026-10-03.md`)

## Goal

Refactor 5 of the world audit (`doc/audit/world.md`, section 5). `Entities.cells` (`entity.odin`) maps a cell to the entity in it and is the world's only way to know a cell is taken: the raycast, the water update and the light read it through the simulation's type, which is 7 of the storage's references into entities. The engine side of the cut keeps a cell occupant index with flags (the composition decision in `doc/work/0146-engine-and-game-logic-cut.md`): the world stores what it needs of an entity (an opaque handle, blocks water, emits light) and nothing more.

## Change

- The index moves to the world storage (`world_chunk.odin` or a new `world_occupants.odin`): cell to an entry of an opaque handle plus flags (`blocks_water`, `emits_light`) and the light colour, maintained by `add_entity`, `remove_entity` and `rebuild_entity_cells` through two world procedures (occupy, vacate); `entity_at` keeps its signature over the index; the raycast, `update_water_cell` and the light read the index, never `Entities`; `entity_lights` folds into the flag plus colour.
- The handle stays packed as today (`Entity_Handle`: kind, index, generation); the world does not interpret it.
- Save bytes unchanged: the index is rebuilt on load as `rebuild_entity_cells` does today (confirm the codec does not write `cells`; if it does, keep the field name and the bytes).
- `doc/architecture.md` (World storage) states what the world stores of an entity; `doc/code_map.md`: the world -> simulation record falls by the storage's entity references; never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `world_raycast_test.odin`, `world_water_test.odin`, `hydro_grid_test.odin`, `test_saved_torch_lit_cave_is_lit_after_load`, `test_water_stays_out_of_entity_cells` and the 0150 test of water into a freed cell pass unchanged in what they assert; the factory benchmark's two sizes in the suite keep their state hash (the implementer records it, as 0155 did); a playtest (the user) of lamps, a torch-lit cave after load, and water around a placed and a picked up machine.
