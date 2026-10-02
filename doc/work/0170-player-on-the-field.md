# 0170: The player on the field: radial up, collision and the slope walk

Status: todo (after 0169; 0177 may start after this item)

## Goal

Walking on a sphere: every entity carries an up along the radial, the player collides with the field as a signed distance, slopes slow and slide past the walkable angle, ledges of a sample are stepped over, a jump of a metre with a mantle to one and a half, a tool reach of a few metres, a camera oriented to the player's up (0167, Collision, raycasts and movement; DESIGN.md, The player).

## Change

- The player's position and velocity in the planet's fixed point frame, the up as the normalised position (fixed point), the forward kept tangent by re-projecting it each tick. The controller is integer like the rest of the tick; the f32 motion of `player.odin` that 0177's prediction factored out goes with it, since floats differ between the phone's arm64 and the desktop's x86 and lockstep needs every machine to agree.
- Collision: the capsule samples the density around it; the surface normal is the gradient; the slope is the angle between the normal and the up. Values in data: the walkable angle (about 40 degrees), the slide speed past it, the step height (one sample), the jump height (about a metre), the mantle height (about one and a half), the tool reach.
- Raycasts march the field (the voxel walk of `world_raycast.odin` has a field counterpart).
- The camera: the first and third person cameras take the player's up as their up, so the horizon tilts as the player walks round the planet; gyro aim unchanged.
- Fly mode (the developer tool) flies in the planet frame with the same up.
- `doc/architecture.md` (the player) and `doc/input.md` (fly mode) updated.

## Verify

- The build and check commands of 0168.
- Tests: a player on a flat part of the sphere stands at the surface with up along the radial; walking a full circle round a small test planet returns to the start within a sample; a slope at 30 degrees is walked and one at 50 degrees slides back; a one sample ledge is stepped over and a two sample ledge needs a jump; the mantle lifts the player onto a ledge of one and a half metres and not two; a raycast from the player hits the ground at the expected distance.
- The main agent reads a screenshot from the developer command: the horizon level with the player standing, tilted after walking a quarter round a 200 m test planet.
