# 0007 Player, digging and placing

Status: implemented
Milestone: M1

## Goal

The player as a body in the world instead of a fly camera: first person by default with a third person toggle, collision with blocks, walking, jumping, sneaking and sprinting, hand mining with a progress timer, block placement with a preview, selection assist, and the fly mode kept as the developer and creative tool. After this item the M1 verify walk (500 blocks, dig to the deep stone, find three outcrops) can be done on foot.

## Deliverables

- Player state in the simulation, ticked at 60 Hz, not per frame: position, velocity, yaw and pitch, on ground flag, selected hotbar slot, mining progress. The `Simulation_State` owns an array of players with one entry; the camera reads player 0. Rendering interpolates the camera between the previous and current tick using the accumulator alpha.
- Movement per `DESIGN.md`: the player is one block wide and two blocks tall (an axis aligned box 0.6 by 1.8 blocks, eye height 1.6), reaches five blocks, jumps one block, sneaks (slower, cannot walk off edges) and sprints. Gravity and terminal velocity constants in one place. Axis separated swept collision against solid blocks of loaded chunks, so the player never tunnels at 60 Hz and can stand on block edges. Unloaded chunks count as air but the player does not fall while the chunk under them is not yet loaded (freeze vertical movement until it is).
- Look: `look` (rate) and `look_delta` (pixels) from the action layer turn yaw and pitch, pitch clamped, with sensitivity constants in one place (configuration later).
- Camera modes: first person at eye height, third person behind and above the player with a placeholder capsule drawn for the body, toggled by a new action (keyboard V, and the Steam Controller View button is taken by the map, so leave the gamepad binding for later). Fly mode toggled by a developer action (keyboard F6): no gravity, no collision, the existing fly camera speeds.
- Targeting: a voxel raycast from the eye along the look direction up to five blocks, returning the hit block, the face normal and the adjacent empty cell. The targeted block gets a wireframe outline. Selection assist from `doc/input.md` is limited to the block level here (the outline snaps to the block, entities come later).
- Hand mining: holding `Mine` on a targeted solid block accumulates progress; the block breaks after its hardness time (from `data/blocks.sjson`, one to three seconds by hand, deep stone longer) and the broken block becomes an item count in a simple inventory (a per block id counter, the real inventory is M2). Progress resets when the target changes or the button is released. A crack overlay or a shrinking outline shows the progress. Water is not minable.
- Placing: `Place` on a targeted block puts the currently selected block type (cycled with the hotbar actions, d-pad left and right or L1 and R1, and the mouse wheel) into the adjacent empty cell if the player owns at least one and the cell does not intersect the player's box. A translucent preview shows the cell. Placing marks the chunk dirty through the existing `world_set_block` path so the streaming remesh picks it up.
- Spawn: the player starts on the spawn block from 0006, standing on the surface. The old fly camera start goes away except in fly mode.
- Diagnostics and overlay: player position, on ground, targeted block and face, selected block, owned block counts.
- Tests (headless): swept collision cases (walk into a wall stops flush, fall onto a floor lands exactly on top, jump height reaches one block and not two, sneaking stops at an edge), voxel raycast cases (hits the expected block and face for axis aligned and diagonal rays, misses on air, respects the five block reach), mining progress arithmetic, placement rejection when the cell intersects the player, and a determinism test that ticks two players with the same input sequence and compares positions bit for bit.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh`, `./build.sh release` pass.
- User: walk from the spawn across a biome border, jump onto a boulder, dig down to the deep stone and climb back out by placing blocks, in both camera modes, with the controller. The M1 verify walk follows once 0008 lands.

## Notes

Implemented 2026-09-27. Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (94 tests), `./build.sh`, `./build.sh release`, `--version`. Without a display the game prints the spawn and stops at the "could not open a window" error as before.

### Layout

- `player.odin`: `Player`, the movement constants, `tick_player` (toggles, look, walk or fly, targeting, mining, placing, selection, in that order). `player_collision.odin`: box sweep per axis, ground and overlap tests. `player_interaction.odin`: mining progress, placement rules, selection cycling. `world_raycast.odin`: the voxel raycast. `render_player.odin`: interpolated camera, third person pull in, outlines, preview, capsule, crosshair.
- `Simulation_State` now owns the `World` and `players: [dynamic]Player`, plus `tick_rate` from `data/game.sjson`. `simulation_tick(state, registry, inputs)` ticks `players[index]` with `inputs[index]`. Streaming follows player 0.
- Input between frames and ticks: `Tick_Input_Accumulator` sums `look_delta` and unions `just_pressed` over every frame since the last tick. The first tick of a frame takes the sums and empties the accumulator, later ticks of the same frame get zero look delta and no edges. `move`, `look` and `pressed` are levels and every tick reads the latest frame.

### Constants

- Box 0.6 by 1.8, eye 1.6, reach 5. Walk 4.3, sprint 5.6, sneak 1.3 blocks per second, as the brief asked. Horizontal velocity follows the input directly, no acceleration or friction.
- Gravity 28 blocks per s², jump speed 8.4 blocks per s: the apex is 1.26 blocks in continuous time and about 1.19 with the 60 Hz step (the jump test reads it between 1 and 1.5). Terminal speed 50 blocks per s; the sweep visits every layer crossed, so any speed is safe from tunnelling.
- Third person: 4 blocks behind along the reverse look direction plus 0.75 up, pulled in to 0.2 before the first solid block on the ray from the eye.
- Hardness in `data/blocks.sjson`: as asked; spent rock (not listed) got 1.5 like stone. 0 means not minable (air, water); negative values are rejected at load. Required ticks are `round(hardness * tick_rate)`, at least 1, so stone takes 90 ticks.

### Deviations

- Player physics is plain `f32`, the stated exception to the fixed point rule until the world scale is settled (comment in `player.odin`). Mining progress is an integer tick count.
- Yaw and pitch reuse `turn_fly_camera` and the fly mode reuses `fly_camera_velocity`, so the look sensitivities and fly speeds stay in `render_fly_camera.odin`. The per frame `update_fly_camera` is gone, its tests now target the two procedures.
- A body that overlaps solid blocks rises one block per tick until free. Not in the brief: without it a spawn on a column with a boulder or tree, or leaving fly mode underground, would leave the player stuck.
- While the chunk under the feet is missing, vertical velocity is held at 0 and gravity does not apply. Horizontal moves into missing chunks are allowed (they read as air).
- Sneak edge rule: a horizontal step on one axis is rejected if the box would have no solid block in the layer under its footprint, which for a 0.6 box is the "under any corner" test. Per axis, so the player can slide along an edge.
- The selection skips to the next owned block when the selected one runs out, and the first mined block gets selected. Number keys are not bound (there are no slots yet); brackets and the wheel are. The wheel feeds `just_pressed` directly because a notch is an event.
- Water is not solid, so the raycast passes through it and targets what lies behind. Placing into a water cell replaces the water.
- In third person the targeting ray still starts at the eye, not at the camera, so the crosshair and the outline can disagree a little at short range.
- The F5 debug edit now uses the player's eye position. The debug terrain starts the player in fly mode at the old fly camera start.
- Mining progress shows as a second outline inside the target outline that shrinks to nothing as progress reaches 100 %. A crosshair was added, since first person aiming needs one.

### Not verified

Everything visual and the feel: camera smoothness at 60 and 144 Hz, outline and preview visibility (the preview is drawn translucent after the chunks with raylib's default alpha blending), the capsule, third person framing and pull in, the crosshair, movement and jump feel with the controller, mouse wheel direction, d-pad and bumper bindings on both backends, the couch walk from the Verify section.

### Open questions

- The 0.2 margin can still let the near plane clip into a wall at steep angles in third person; a sphere cast would fix it if it shows.
- Should fly mode also mine instantly (DESIGN.md mentions a flying and instant mining toggle)? Not done.
- `doc/input.md` and `doc/architecture.md` do not yet mention the new bindings (V, F6, brackets, wheel, d-pad left and right, L1 and R1), the tick input accumulation or the world moving into the simulation; outside this item's allowed files.
- The raylib gamepad table still has no Sneak on B (only Back), unlike the SDL3 table; pre-existing, left alone.
