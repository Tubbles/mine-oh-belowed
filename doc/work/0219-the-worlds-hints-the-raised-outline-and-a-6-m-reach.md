# 0219: The world's hints, the raised footprint outline and a 6 m reach

Status: todo (2026-10-04, the user's playtest notes after 0215: "I don't see some bindings when playing with mouse and keyboard, eg. Q is missing. Also make the 'footprint ghost' extend a little upwards into the air, since now it clips into the terrain and is tricky to see. could we also extend the build distance by 50%"; folds 0217)

## Goal

Three playtest fixes in the HUD and the field placement. The glyph bar tells a keyboard player what Q, R and the mouse buttons do with an item held: today the world's bar shows Inventory and Pause plus at most one context hint (`hud.odin`, the cases after `tools_radial`), never the tools radial, Rotate or Place, so a keyboard player never learns Q. The footprint outline (0215) rises off the ground so a slope cannot hide it. The reach grows by half, from 4 m to 6 m.

## Change

- **The world's glyph bar.** The hints, in this order, each shown only when its action does something now: the aimed thing's action as today (Interact's Turn, Open or Close; Mine's Pick up or Fell; the schematic's hints); then the held item's actions: Place (the `Use_Item` glyph, "Place") with a placeable tool held (`Field_Held_Tool` Material, Foundation, Belt_Run, Pipe_Run, Machine, Torch), Tools (a new `Glyph_Button.Tools` on the `Pipette` action, "Tools": Q on the keyboard, D-pad Up on the pad) with any item held, Turn (the Rotate glyph) with a tool `Rotate_Building` turns on the field (the design stage reads which); then Sprint as today, Inventory and Pause.
- **The fit (0217 folded).** The bar is laid out in the room between the hotbar's right edge and the safe area's right edge, never over a hotbar slot: hints that do not fit wrap into a second row above the first, both right aligned, and beyond two rows the bar drops from the end. The world's bar therefore sheds Pause and then Inventory first (constant, learnt in the first minute), the opposite of the menus' rule that keeps Back (`ui.md`, The glyph bar), and the placement editor's four stay whole on two rows at the smallest audit size. The UI audit gets a case per bar at every size and the test asserts no glyph box intersects a hotbar slot.
- **The raised outline.** The outline's four edges become low walls, `PLACEMENT_OUTLINE_HEIGHT_CELLS` one cell tall (0.5 m at the shipped pitch), see through below an opaque top rim, and the front arrow is drawn at the walls' top; the design stage checks the height against the bare ground flatness limit over the largest footprint (250 mm over 5 m) and the editor's own ghost, and says the margin. The foundation ghost per cell (0215) is unchanged.
- **The reach.** `tool_reach_millimetres` in `data/game.sjson` goes from 4000 to 6000; its bound (1 to `MAXIMUM_FIELD_PLAYER_LENGTH_MILLIMETRES`) holds. The aim's raycast steps a quarter sample, so the longer ray costs a few more steps a tick; the bury rule and the centre rule are unchanged. Tests and docs that state the 4 m reach follow (the design stage greps `tool_reach` and "4 m").

## Controls

No binding changes. The glyph bar shows existing bindings only: the first binding of each action on the active device, as `glyph` reads it (0151). This is the keybinding pass: nothing gains or changes a meaning.

## Verify

- Tests (names chosen by the design stage): the world's hints with a machine held list Place, Tools and Turn with the keyboard labels (Right mouse, Q, R) and the gamepad icons (L2, D-pad Up, Y); with nothing held only Inventory and Pause; the fit against the hotbar at every audit size and the wrap at the smallest; the outline's wall height in the drawn boxes; a placement at 5.5 m succeeds and one at 6.5 m finds no target.
- The couch: with the furnace held the keyboard bar reads Q Tools, R Turn, Right mouse Place; the outline reads on the slope by the pod; a machine placed from 6 m.
