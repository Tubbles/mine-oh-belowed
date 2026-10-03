# 0044 Couch test 1 quick fixes: overlay, sprint, cheat speed, world deletion

Status: implemented
Milestone: M10

## Goal

Four findings from couch test 1 (2026-09-27) that get in the way of testing: a statistics overlay that is always on, a sprint that is not discoverable, no fast way through the early game, and world deletion hidden behind a glyph bar hint.

## Deliverables

- The world statistics overlay (`draw_world_overlay` in `src/diagnostics.odin`, drawn whenever the diagnostics screen is off) is off by default. It is toggled from the Developer screen ("Statistics overlay") and with a keyboard key, and its state is frame state like `show_diagnostics`. The diagnostics screen keeps its own toggle.
- Sprint: the left stick click toggles sprinting (press once while moving to sprint until movement stops or the stick is clicked again) instead of hold; Left Control on the keyboard keeps hold. The world's glyph bar shows the sprint hint while the player walks.
- Cheat speed (developer): a "Cheat speed" toggle on the Developer screen, served as a developer request into a simulation flag that is not saved: walking and sprinting three times as fast, flying as well, and hand mining taking a tenth of the time (`mining_required_ticks` in `src/player_interaction.odin`). The diagnostics show the flag.
- World deletion: the load screen gets a focusable Delete button next to Back that deletes the focused save after the existing confirmation, so the glyph bar is not the only way. A save this build cannot load (format version, layout or content fingerprint, checked from the entities file header when the list is built) is marked in its row and can still be deleted.
- Tests: the overlay flag default, the sprint toggle state machine as a pure procedure, the cheat speed factors applied to speed and mining ticks, the load list marking an incompatible save.

## Verify

- Builds and tests pass.
- User: the world starts without the statistics block; the stick click sprints until you stop; Cheat speed makes mining near instant; the old world can be deleted from the load screen with the controller.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (572 tests), `./build.sh`, `./build.sh release`, `--version`.

### Model and deviations

- Overlay: `Frame_State.show_world_overlay`, false by default, reset with `show_diagnostics` when a session ends. F4 (`Toggle_World_Overlay`, context both like F3) and a "Statistics overlay" toggle on the Developer screen. The diagnostics screen still wins when both are on. The overlay's hint line now reads "F3 diagnostics  F4 statistics  F5 remove block  F6 fly  V camera  O bottlenecks".
- Sprint: the input frame merges all devices into one action set, so keyboard hold is a separate action, `Sprint_Hold` (Left Control), instead of a device check. `Sprint` (the stick click) toggles `Player.sprinting` on its press while moving; a tick with zero movement input clears it, so a press while standing still does nothing. Fly mode uses the same sprint state for its sprint factor. A configuration that overrides `Sprint` with a keyboard key gets a toggle on that key. `Player` gained a field, so the save layout fingerprint changes and older saves are refused (accepted).
- Sprint hint: the default world glyph bar shows Sprint (L3 or Ctrl) while the player is on the ground, not flying, moving and not in toggled sprint. It also shows while Left Control is held, since the hint reads the toggle only.
- Cheat speed: `Developer_Action.Toggle_Cheat_Speed` flips `Simulation_State.cheat_speed` (not saved, so a new session starts without it). Walking, sprinting and flying velocities times `CHEAT_SPEED_FACTOR` (3), block digging `cheat_mining_ticks` (a tenth, at least one). Picking up an entity keeps its time. The Developer screen now has two toggle rows (fly mode and cheat speed, which queue requests; diagnostics, statistics overlay and bottleneck overlay, which act at once), 11 rows in all. Diagnostics player line shows sprinting and "cheat speed".
- Load screen: Delete and Back share the bottom row. Delete acts on the save row that last held the focus (`Title_State.load_selection`), since focusing the button takes the focus off the list; the confirmation names the save. The listing reads only the entities file header (`entities_header_problem`) against `make_save_header` of the loaded data, kept on `Title_State.expected_header`; a mismatched or missing entities file sets `Save_Summary.loadable = false` with `load_problem`, and the row shows "(other build, cannot load)". Loading such a save still ends in the existing failure toast.

### Guessed numbers

`CHEAT_SPEED_FACTOR` 3 and `CHEAT_MINING_TICK_DIVISOR` 10 are from the work item. F4 for the overlay was a free key.

### Not verified

Everything visual: the two Developer toggle rows at 1000 units, the Delete and Back row, the row marker's width in the load list, the Sprint glyph hint.
