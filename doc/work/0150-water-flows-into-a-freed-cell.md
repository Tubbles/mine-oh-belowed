# 0150: Water flows into the cell a machine leaves

Status: todo

## Goal

`schedule_water_around` runs only for block changes (`apply_block_changes`); `pick_up_entity` (`entity_placement.odin`) and `remove_for_developer` (`developer.odin`) schedule nothing, so a pool stays dry where a machine stood until a neighbouring change wakes it (world audit, refactor 2; `SUGGESTIONS.md`). The fix is also the first entity cell change hook.

## Change

- A world procedure, a sibling of `schedule_water_around` taking the freed cells and the tick, schedules water updates around every cell an entity leaves; `pick_up_entity` and `remove_for_developer` call it with the entity's cells. Placement already clears cover through `world_set_block`.
- `doc/fluids.md` or `doc/architecture.md` (whichever owns water today) states that water re checks a cell when a machine leaves it.

## Verify

- A test: a pool of water next to a cell, a machine placed in the cell (so the cell is dry), the machine picked up, ticks run, the cell holds water.
- `./build.sh check`, `./build.sh test`, `python3 tools/check_docs.py`; the determinism test of water (`test_water_updates_are_deterministic_and_bounded`) still passes.
