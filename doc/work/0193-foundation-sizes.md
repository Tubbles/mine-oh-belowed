# 0193: Foundations placed in sizes

Status: todo (user, 2026-10-03, after placing on a foundation worked: "i would like to be able to cycle through a couple of X*Y sizes, say 1x1, 2x2, 5x5, 10x10, as well as some Z heights, say 1, 2, and 5")

## Goal

A held foundation places a block of cells at once: a square of X by X cells and Z cells high, the size and the height chosen by cycling through lists the content defines. Today a foundation places one cell (`field_player_placement`, `entity_frames.odin`: free on the ground through `place_free_foundation`, or on a frame's adjacent cell through `place_on_frame`), so a pad is built one cell at a time.

## Change

- `data/game.sjson` lists the sizes and the heights (`foundation_sizes = [1, 2, 5, 10]`, `foundation_heights = [1, 2, 5]` next to `foundation_pitch_millimetres`); the first of each is the default. Never a literal in Odin.
- The player keeps a size index and a height index (`Field_Player`, saved with the player as the placement rotation is). With a foundation held, Rotate_Building cycles the size (rotation means nothing to a foundation, `field_player_placement` forces 0) and Rotate_Building with Sneak held cycles the height, so no new binding is needed and the touch overlay has both already; the tool line names the current size ("Foundation 5x5, 2 high").
- The placement covers the block: free on the ground, the frame starts at the hit with the square centred on the aim and the block rising from the ground; on a frame, the block grows from the adjacent cell away from the face hit (the square spans the face, the height along the frame's up when the face is a top, else along the face's normal; say in the report which rule reads best in play). Every cell must be free, else the whole block is refused with the frame refusal of the first blocked cell; the inventory must hold the cell count, else the refusal names it ("Needs 25 foundations, 16 held", a new `Field_Edit_Refusal`); the cost is one foundation per cell.
- The ghost draws the whole block (red when refused) so the user sees the pad before the press. The cells enter the entity table as single foundation entities as today, in a fixed order, so the hash agrees on every machine.
- `doc/content.md` (Foundations: the lists), `doc/hud.md` (the tool line), `doc/architecture.md` (the field placement) updated.

## Verify

- The build and check commands of 0168.
- Tests: a 2x2 by 2 block placed free makes a frame with eight foundation cells in the expected cells and costs eight items; a 5x5 refused for 16 held places nothing and raises the refusal once; a block on a frame's top face rises from the adjacent cell; the cycle wraps and Sneak selects the height; a save round trips the indices; the hash is the same on two sessions that place the same block.
- The couch: the user cycles sizes and heights with the foundation held and builds a pad.
