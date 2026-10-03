# 0186: The pod can be entered

Status: implemented (playtest 1 of the slice, 2026-10-03)

## Goal

The player walks into the pod through its door. Today the pod occupies its whole 6 by 6 by 8 cell footprint and every occupied cell is a solid box to the field player (`frame_cell_is_solid`, `world_frame_collision.odin`), so the door of the model (`pod.vox`, 1 m wide) is a picture on a solid block: the user could not enter it (playtest 1).

## Change

- A machine record may name the cells of its footprint that are open (`open_cells`, or a hollow flag with the hull one cell thick and the door cells open): the occupant index marks them without `Solid`, so the player passes and stands on the floor cell, and `frame_cell_is_solid`, the raycast and the water read the flag as they do today. The pod's record opens its interior and its door; the bed stays a solid block.
- Placement still refuses a machine over any of the pod's cells (open cells are occupied).
- `doc/content.md` (the machine record), `doc/architecture.md` (the occupant index's open cells) updated.

## Verify

- The build and check commands of 0168.
- Tests: a field player walked at the pod's door enters and stands inside on the floor; the walls stop the player; a machine placed on an open cell is refused; the save round trips the open cells.
- The couch: the user walks in and out of the pod.
