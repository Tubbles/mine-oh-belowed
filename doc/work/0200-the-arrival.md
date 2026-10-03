# 0200: The arrival: the fall, the flames, the crash, the doors open

Status: todo (user, 2026-10-03: "when starting a new world the first 10 seconds is falling down towards the planet from an angle, we can see it approaching through a window, and then getting closer and flames start erupt from atmospheric drag, and then a violent crash down and the doors open"; after 0199)

## Goal

A new world opens with the landing. For ten seconds the player sits in the pod and sees the ground come up through the window at an angle, flames tear past as the air thickens, the pod hits hard, and the hatches open. Today a new world starts standing in front of the pod.

## Change

- The arrival is simulation time: the new world's first `arrival_ticks` (600 at 60 Hz, in `game.sjson`) are the fall; the player is seated in the cabin and cannot move; at the last tick the pod's hatches (0198) open through the same toggle every machine runs, so the hash agrees. A loaded save past the arrival and a joiner never see it (the world's tick is past it). The pause menu's Skip ends it early (a command that sets the tick's remaining fall to zero on every machine, so it is lockstep too).
- The presentation draws the pod's descent: the pod model on a straight path from the start point (the crater's up tilted by `arrival_angle_degrees`, the start `arrival_start_metres` above the floor) to its resting place, eased so the last second is the fastest; the camera sits at the cabin window looking along the path, so the terrain comes up at an angle; the planet's terrain under the path is drawn from the field renderer's levels (the coarsest level reaches `level_distances_metres[3]`, 1024 m today, so the start is at most about that high; a view from orbit needs a far level that is not in scope here, say so if the start looks too low to read as a fall and the user picks the height).
- Flames from drag: in the last four seconds a shader effect over the window, rooted in the window's edges, bright at the leading edge, no fixed period (`DESIGN.md`, no perceivable repetition), plus a low roar that rises; at the hit a hard shake of the camera, a dust cloud outside, a crash sound, then silence and the hatch sound as the doors open. Sounds through the cue system (0181 if it has landed, else the block world's cue path).
- The crater (0199) is already there under the pod: the fall ends in it, no terrain changes at the hit.
- `doc/architecture.md` (the arrival: the ticks, the presentation), `doc/content.md` (the arrival's values in `game.sjson`), `doc/ui.md` (Skip), the log.

## Controls

- During the fall nothing moves the player; Pause works, and the pause menu shows Skip arrival. After the hatches open the world's controls are what they are.

## Verify

- The build and check commands of 0168.
- Tests: a new world's player cannot move for `arrival_ticks` and the hatches are closed until the last tick, open after; a joiner at tick 1000 and a save loaded at tick 1000 start with no fall; Skip ends the fall on two sessions at the same tick; the shake and the flames are presentation only (the hash is the same with and without them).
- Headless: a screenshot at tick 300 (mid fall, the ground through the window) and at tick 560 (flames), sent to the user; then the couch.
