# 0367: The water tick at a flowing spring

Status: todo (2026-11-11)

0342's first check run (2026-11-11, the couch's RX 5700 under headless gamescope, 512 m, capped at 30) found what holds the spring start at 3 to 6 frames a second, the figure the user saw: not the GPU (2.0 ms a frame) but the simulation. At the spring view `field_water` costs 14.1 ms of a 14.9 ms tick (worst 24.4 ms), so the frame falls behind, runs about 10 ticks a frame (155 ms) and never catches up; beside it the streaming remeshes 8 nodes every frame (14.8 ms). The view never settles. Every other view of the run ticks in 0.3 to 1.0 ms and draws in under 6 ms. The user's bar is 60 frames a second at 512 m.

## Goal

Standing at a flowing spring, a tick costs what it costs elsewhere, and the frame holds 60.

## Controls

None.

## Change

- Find what the water tick does at the spring every tick (the stream's flow, the bodies it feeds, a body that never comes to rest) and make its steady state cost nothing: water that only repeats itself sleeps, deterministically, as 0301's budgets and the rest rule intend.
- The remeshing every frame: a mesh is rebuilt only when its water changed by what shows.
- 0301 (the water's cost per edit) and 0344 (the water's look on the workers) touch the same code: the design says what each keeps.

## Verify

- The checks and the suite, with the state hash of a session at the spring equal with and without the change where the change is a pure saving, or the behaviour change named in the log.
- 0342's spring view settles and passes at 512 m, in one and two viewports.
