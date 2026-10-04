# 0259: The step rule's remaining edges

Status: todo (2026-10-04, from the 0232 design's questions 1 to 3, worked by hand from the code and not yet seen on the couch; after 0232)

## Goal

A player walking beside a wall, over a low lip at a fine spacing, or resting on the pod's heat shield rim stands and steps as the walk intends, at every sample spacing.

## Findings (0232 design, hand worked)

- Beside a vertical wall that touches the bottom sphere every step is refused at every spacing: `drop_field_capsule` (`player_field.odin`) takes the nearest surface's gap, the wall's is within the tolerance before the drop moves, so the landing hangs a step height over the ground under the centre and `!ground.on` refuses the step before the steep contact rule runs. Older than 0230. It may keep a player walking along the pod's hull or a corridor of cells from stepping a lip there.
- A walking player meets lips between about 220 and 310 mm at 500 mm spacing (200 to 260 mm at 333 mm) whose step landing hangs beyond the leave tolerance, so the ledge takes them with its 0.8 m (0.63 m) stride, a lurch that overshoots a short tread. After 0232 a crouched player steps a 250 mm lip at 500 mm smoothly while a walking one still lurches.
- After 0232's resting rule (`capsule_rests_on_walkable_frame_contact`), the 0232 verifier measured: a crouched player who walks off a low lip and stops just past its edge stays perched on the corner, 20 mm over the floor at 333 mm spacing (83 mm lip), 26 to 29 mm at 500 mm (125 and 175 mm lips), 20 mm out on the 175 mm lip at 1000 mm, where before the settle took them to the floor; and a player standing still on a flat cell or volume top rests 0 to 8 mm over it depending on the landing's drop (within `FIELD_GROUND_TOLERANCE`, deterministic, no bob) where before the settle closed the gap. The rest on a walkable corner is the same rest that keeps the climb, so a change here names what it does to 0232's tests.
- On the pod's rim (175 mm high, 225 mm wide, narrower than the capsule's radius) at 333 and 500 mm spacing the player rests on the ring's edge about 165 mm over the floor, beyond the leave tolerance, so `on_ground` is false there: no jump, the fall speed held at zero by the edge. At 1000 mm the rest is on ground (0232's test 3).

## Controls

No binding changes.

## Change

- The couch first: crouch and walk onto the pod's rim and along the hull at 333 and 500 mm spacing, and try to jump from the rim. What the user feels decides the order of the three.
- The design stage then chooses: the drop reading the surface under the sphere (or the downward gap) rather than the nearest surface when a wall touches, so a step beside a wall is decided by the ground; the step landing's leave tolerance or the ledge's stride at fine spacings, so a 250 mm lip is a step for the walking player too; and the rest on a ring narrower than the capsule counting as ground when the edge holds the fall. Each choice names what it does to 0230's cone (test 8 stays refused) and to 0232's tests.
- Docs: `doc/architecture.md` (The player on the field), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests in `player_field_volume_test.odin`: a step onto a lip while a wall touches the bottom sphere, at the three spacings; a walking step onto a 250 mm lip at 500 mm without a ledge stride; the rim rest at 333 and 500 mm with `on_ground` true; 0230's test 8 and 0232's three tests unchanged.
- The couch: the pod's rim and hull at 500 mm.
