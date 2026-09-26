# 0007 Player, digging and placing

Status: todo
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
