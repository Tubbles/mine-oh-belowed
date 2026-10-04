# 0216: The pipette

Status: todo (2026-10-04, found by the 0215 design: the Pipette action exists with its bindings (D-pad Up, R5, Q, the middle mouse button, the touch pipette) and its reference tests, and does nothing; after 0215)

## Goal

The pipette picks what the player aims at into the hotbar: aimed at a placed machine, a foundation, a belt or a pole, a tap selects the hotbar slot holding that item, or moves one stack of it from the inventory into the selected slot when no slot holds it, so a player extending a line never opens the inventory to find the belt again. Since 0215 the control's hold opens the tools radial; the tap stays the pipette.

## Change

- `Pipette` pressed in the world with an entity aimed in reach (the HUD's target, as `Open_Aimed` reads it) becomes a player command carrying the aimed item (or the hotbar selection is local presentation when the slot already holds it; the design stage decides which parts are simulation and which are presentation, since the hotbar selection is simulation state today).
- Aimed at nothing placeable (terrain, a tree, a player): nothing, no toast.
- The item under the reticle is read from the entity's record (`item`), a foundation from the frame's cell record, a belt or a pole from the run.
- `doc/input.md` (Bindings) and the HUD's glyph hint when a pipette target is aimed.

## Controls

- None new: the `Pipette` action and its bindings exist; the tap (a release before the tools radial of 0215 shows) is the pipette.

## Verify

- Tests: aiming at a placed furnace selects the slot holding stone furnaces, moves a stack from the inventory when no slot holds one, does nothing with an empty inventory and with nothing aimed; the command round trips.
- The couch: aim at a belt, tap, the belt is in hand.
