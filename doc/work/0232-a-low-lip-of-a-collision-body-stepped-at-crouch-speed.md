# 0232: A low lip of a collision body stepped onto at crouch speed

Status: todo (2026-10-04, from the 0230 verifier's re-check of the fix round: the steep contact step rule (`field_landing_held_by_steep_contact`, `player_field.odin`) is reached only for a lip lower than a quarter of the terrain's sample spacing, such as the pod's 0.175 m heat shield rim or a stair, and at crouch speed the edge contact there gets steeper than walkable, so the rule may refuse a step the walk should take; no test covers that case, the fix round's lip test used a lip of the full step height, which the ledge path climbs before the rule runs; after 0230)

## Goal

A player crouching onto a low lip of a machine's collision body (a rim, a stair tread, a threshold under a quarter of the sample spacing) steps onto it as a walking player does, and the steep contact rule of 0230 refuses only what it was made for: a landing on a slope steeper than walkable, such as the pod's hull cone.

## Controls

No binding changes.

## Change

- A test in `player_field_volume_test.odin`: a box of a quarter of the step height (under spacing/4 at 333, 500 and 1000 mm) walked onto at crouch speed and at walking speed, the feet landing on its top within `FIELD_GROUND_TOLERANCE` and the walk continuing; and the same box at the pod's rim height (0.175 m) at 1000 mm.
- If the rule refuses the crouched step: the contact read at the bottom sphere's centre is the nearest volume, which on an edge is the lip's top face only once the sphere is far enough over it; the design stage chooses between reading the contact a little ahead of the centre along the walk, or accepting a contact steeper than walkable when the ray under the centre finds the landing within the land tolerance (the lip's own top), and says what each does to the hull cone, which must stay refused (test 8 of 0230).
- The verifier's other note goes with it: the probe returns the nearest volume, which may be a wall beside the capsule rather than the surface under it, so a step beside a wall may be refused that was hanging anyway; the design stage says whether the contact should be the nearest volume below the centre instead.
- Docs: `doc/architecture.md` (The player on the field, the step rule's paragraph from 0230), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`.
- Tests: the low lip at crouch speed and walking speed at the three spacings; 0230's test 8 (the cone refused, the feet within tolerance every tick) still passes.
- The couch: crouch onto the pod's heat shield rim from the ground.
