# 0150: Water flows into the cell a machine leaves

Status: implemented

## Goal

`schedule_water_around` runs only for block changes (`apply_block_changes`); `pick_up_entity` (`entity_placement.odin`) and `remove_for_developer` (`developer.odin`) schedule nothing, so a pool stays dry where a machine stood until a neighbouring change wakes it (world audit, refactor 2; `SUGGESTIONS.md`). The fix is also the first entity cell change hook.

## Change

- A world procedure, a sibling of `schedule_water_around` taking the freed cells and the tick, schedules water updates around every cell an entity leaves; `pick_up_entity` and `remove_for_developer` call it with the entity's cells. Placement already clears cover through `world_set_block`.
- `doc/fluids.md` or `doc/architecture.md` (whichever owns water today) states that water re checks a cell when a machine leaves it.

## Verify

- A test: a pool of water next to a cell, a machine placed in the cell (so the cell is dry), the machine picked up, ticks run, the cell holds water.
- `./build.sh check`, `./build.sh test`, `python3 tools/check_docs.py`; the determinism test of water (`test_water_updates_are_deterministic_and_bounded`) still passes.

## Implementation notes

- `schedule_water_around_freed_cells` (`world_water.odin`) calls `schedule_water_around` per freed cell. That already schedules the cell itself beside its six neighbours, and the cell itself is the one that matters: `update_water_cell` returned early for it while the entity stood there.
- The cells are taken with `common_cells` before `remove_entity` and scheduled after it, so `update_water_cell` sees no occupant.
- The tick: `remove_for_developer` gets `state.tick` from `serve_developer_request`. `pick_up_entity` had none on its path, so `tick: u64` is threaded from `simulation_tick` (`state.tick`) through `tick_player`, `mine_with_player` and `mine_entity`; the tests that call these pass 0.
- Due ticks stay in order: player and developer actions run earlier in the same tick as `apply_block_changes`, with the same tick, so `run_water_updates` keeps its due order. The water queue is already saved, so the save layout is unchanged.
- Test: `test_water_flows_into_the_cell_a_machine_leaves` (`world_water_test.odin`), which fails with the call removed. The turbine side is covered by `test_water_flows_through_a_hydro_turbine`.
