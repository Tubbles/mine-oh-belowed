# 0220: The third person camera pulled in by the field

Status: todo (2026-10-04, found by the 0218 design: the field's third person camera sits behind the eye at the settings' distance and is never pulled in by the terrain, so in a tunnel it looks from inside the rock; the block world's camera is pulled in by the blocks (`third_person_position`); after 0218)

## Goal

The third person camera on the field never sits inside the ground, a frame or a tree: it is pulled in along its line from the eye to the first surface it would cross, with a margin for the near plane, as the block world's camera is pulled in by the blocks ([doc/architecture.md](../architecture.md), The player on the field: "the third person camera sits behind the eye and is not yet pulled in by the field").

## Change

- `field_third_person_camera` (or the procedure `render_field_camera.odin` names for it) casts from the eye back along the camera's offset with `raycast_field` and the frames' cast, and stops the camera `THIRD_PERSON_WALL_MARGIN` short of the first hit; a hit nearer than the margin puts the camera at the eye (first person for that frame).
- Presentation only: the cast reads the field and the frames, never writes, and runs per viewport per frame.
- A crouched player (0218) is cast from the crouched eye.

## Verify

- Tests: a camera behind a player standing with a wall at 2 m behind them sits 2 m minus the margin away; in a 1 m tunnel (the 0218 tunnel terrain) the camera stays inside the tunnel; on open ground it sits at the settings' distance.
- The couch: third person in the dug tunnel, the camera never shows the inside of the rock.
