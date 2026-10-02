# 0171: Brushes: dig, place and the item yield

Status: implemented

## Goal

Digging and placing the field by hand: brushes of two sizes and a level mode, applied in fixed point in a fixed sample order, the dug volume credited as items per material with a fractional remainder per player, edits queued to the end of the tick (0167, The terrain field; the design session's decision on edits inside a tick).

## Change

- A brush record in data: shape (sphere, level plane), radius, rate per tick; two sizes for the slice.
- A dig lowers the density of the samples inside the brush by the rate, bounded at air; the volume removed per material sums into cubic metres and credits the player's inventory with that material's item, the remainder kept per player and per material as `take_power_step` keeps credits. A place raises the density from the held material and debits the same way; placing into an occupied frame cell (0174) is refused.
- Edits from the tick (the player's brush, later a drill) go into an edit queue drained at the end of the tick in the order they were queued, so no system reads a half edited field inside a tick; the queue is not saved.
- Tool tiers: the material's tool tier gates the brush as the block's tier gated the pickaxe (0051).
- The HUD's target status reads the material under the reticle and its tint.
- `doc/architecture.md` (Simulation, the edit queue), `doc/content.md` (brushes, the material unit) updated.

## Verify

- The build and check commands of 0168.
- Tests: digging a sphere of stone credits the stone item by the volume removed within one item, with the remainder carried to the next dig; placing a cubic metre of stone debits one item and raises the field by that volume; two edits queued in one tick apply in order and none shows before the tick ends; a brush over a material above the carried tool's tier digs nothing; a save between the queueing and the drain loses nothing that the drain had not applied.
