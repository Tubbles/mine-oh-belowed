# 0044 Couch test 1 quick fixes: overlay, sprint, cheat speed, world deletion

Status: todo
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
