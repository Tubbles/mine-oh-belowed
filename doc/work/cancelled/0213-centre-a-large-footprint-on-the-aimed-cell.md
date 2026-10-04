# 0213: Centre a large footprint on the aimed cell

Status: cancelled (2026-10-04, folded into 0215, the placement editor, whose off state places a large machine centred on the aimed cell; written 2026-10-03 from the 0212 design's questions)

## Goal

A machine placed on bare ground stands where the player aims, not beside it: today a free frame's cell (0, 0, 0) stands centred on the hit (`free_frame_at`, `world_frame.odin`), so a machine's whole width and depth extend to the frame's right and forward of the reticle. A 2 by 2 cell machine lands half a metre off and nobody minds; the 10 by 10 cell stone furnace of 0212 stands 5 m to one side of the aimed point, and the ghost shows it only once the player looks for it.

## Change

- The footprint is centred on the hit: an odd footprint's middle cell stands on the hit, an even one's centre corner does, so the ghost and the placed machine sit round the reticle; a 1 by 1 footprint (a belt pole, a torch, a single foundation) stays as it is.
- The design stage checks whether placement on an existing frame anchors the same way (the aimed cell as the origin cell) and whether it should centre too, and what the frame placement's ghost (`frame_ghost_color`) draws while aiming.
- The rotation turns the footprint about the same centre, so rotating a ghost does not walk it across the ground.

## Controls

- None: the bindings stay, only where the footprint lands changes.

## Verify

- A test places a 10 by 10 machine on bare ground and reads the hit inside its middle cells, a 3 by 3 one with its middle cell on the hit, a 1 by 1 one unchanged against the current test; the rotation cases keep the centre.
- The couch: aiming at a spot and placing the furnace puts it there.
