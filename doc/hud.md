# HUD

What the world view draws over the world (`hud.odin`, through the UI draw list under any open screen). Widget and screen rules are in [ui.md](ui.md); the touch buttons' input is in [touch_overlay.md](touch_overlay.md).

- The hotbar sits bottom centre, the quest objective top right, toasts and Mission Control top left, notices top centre, the glyph bar bottom right. There is no compass strip.
- Under a screen `draw_hud` draws only the crosshair or the mining ring, the hotbar and the craft queue; everything else waits for the world.

## Layout

| Where | What |
| --- | --- |
| Bottom centre | Hotbar of eight slots, the selected one 1.25 times as large (`HUD_SELECTED_SLOT_SCALE`), the held item's name above |
| Right of the hotbar | Touch buttons while the overlay drives the world (0134) |
| Left of the hotbar | Crafting queue boxes (0138) |
| Centre | Crosshair, mining bar, target lines; the magnetometer's dial while it is selected |
| Top right | The active quest objective, at most 0.4 of the safe width (`HUD_OBJECTIVE_WIDTH_FRACTION`); after the last quest the oldest open contract's name, requests and time left, or nothing (0042) |
| Top left | Mission Control's panel, the toasts below it |
| Top centre | Brownout warning, the biome banner below it, the discovery card |
| Bottom right | Glyph bar; it offers Sprint while the player walks on the ground without sprinting (`sprint_hint_shown`), and "Pick up" with the Mine glyph while the field player aims at a frame cell other than the pod's and its pad's (`field_pick_up_hint_shown`, 0195) |

- **Touch buttons** (`hud_touch_button_rectangles`): backpack, map, pause, then rotate, a slot's size each on the hotbar's baseline, so rotate coming and going moves no other; rows going up where the room is narrower (1280 by 800 at UI scale 1.5). Rotate shows while a machine or stairs is selected (turned before placing) or a belt, splitter, inserter or drill is targeted (turned in place).
- **Crafting queue**: one box per run, newest nearest the hotbar, up to 4 rows going up; when the runs outnumber the boxes the front run and the newest show. Each box has the product's icon and the run's crafts as its count; a progress bar over the front run, and above it "Crafting waits: inventory full" while the finished craft's outputs do not fit, or "Waiting for Log" while the front craft lacks an ingredient.

## Targeting

- Target lines under the crosshair (0052), stacked without gaps: the block's name dim, or an entity's name and state; the pickaxe the block needs (0051); the vein line. Nothing when the ray hits nothing.
- On the field the tool line says "Needs a foundation under it" while a machine other than a foundation is held over bare ground (`field_tool_line`, 0187); Place there toasts the same, and the ghost is the machine's footprint at the cell a free foundation would take, red.
- With a foundation held the tool line names the block Place puts down, "Foundation 5x5, 2 high" (`foundation_block_line`, 0193), chosen in the configure pop-up that Context_Action opens on a foundation highlighted in the inventory view ([ui.md](ui.md), Configure pop-up); the ghost draws every cell of the block, red when the drain would refuse it.
- A discoverable ore reads "Unknown ore" until its drop was obtained once; the vein line calls its type "Unknown ore" until one of its discoverable ores is. A vein type with no discoverable output (a quarry, the deep bauxite vein) is always named.
- A bar above the crosshair fills while a block is dug, and on the field while Mine is held on a frame cell to pick its entity up (0195, `PICK_UP_SECONDS`, the confirmed tick's progress, never the prediction's); a foundation something stands on gets no bar and toasts "Something stands on it". In the touch tap scheme (0118), which draws no crosshair, a ring around the mined block fills clockwise instead (`draw_mining_ring`, placed through the camera the world was drawn with; on the field at the mined frame cell's centre on its frame, `mining_ring_point`).
- Placing: no preview cube; the outline shows the target's shape (a slab's half, the half block box a torch aims at, 0061). A slab goes into the upper half against a block's underside or high on a side face, else the lower. Stairs rise away from the player, a quarter turn more per Rotate.
- Ground cover (0082: tufts, flowers, reeds) stops the ray and fills its cell. A block placed at cover replaces it; a machine, belt or pipe aimed at cover stands on the ground under it and clears the cover in its footprint; a belt drag lays over cover. Mining the block under cover drops the cover as a loose item.
- Ghosts (0081): a machine's own model tinted translucent green or red at full brightness, its part at rest, turned by Rotate; a translucent box without a model. A belt ghost is its surface with a white chevron along the flow, following a ramp; an inserter ghost is its arm folded at rest (0175) and outlines its pickup cell dim and its drop cell bright with a chevron over the base; drills, splitters, fluid machines and poles draw their arrows, ports and volumes over the model.

## Notices

- **Mission Control** (0069): notices whose key starts with `mc_` go to a panel at the top left, the toasts moving below it. The panel colour with an accent border on the left, the venture's mark (a stepped chevron of fills) and "MISSION CONTROL", then the line typing at 40 characters a second with a blinking cursor, held 4 seconds, faded over half a second.
- Mission Control's lines queue (at most 8, the oldest waiting gives way); a rising chime plays as each starts (`mission_control_chime`). No button acts on a line, since in the world Confirm is also Jump and Mine; its time runs on under a screen, and the journal keeps it.
- **Discovery card** (0052): `item_discovered` shows a card at the top centre for 3 seconds instead of a toast: the icon, "Discovered" dim and the name, with the discovery chime. A second discovery replaces it; under the touch overlay it sits below the layout's top centre buttons. Finished research, the capsule landing and the contract and trade notes stay toasts.
- **Biome banner** (0058): when the biome under the player has changed and stayed changed for 2 seconds, its name fades in below the brownout warning, shows 3 seconds in all and fades out. A world's first biome is announced too; a short visit announces nothing; it pauses under a screen.
- **Descent and survey** (0067): the map draws a parachute over the landing pad while a capsule descends. After an orbital survey a satellite crosses the map west to east along the pad's row in 6 seconds, over the pad halfway, and a bright quad crosses the sky along the sun's path in the same time. Both are render state kept with the particles, never read by the simulation; a loaded world starts neither.

## The player's hands

In first person the right arm reaches in from the lower right with the selected stack (0066, 0092): a cube shaped block as a 0.35 block cube with its top, side and bottom tiles, shaded per face and lit like the arm; any other item (torch, slab, stairs, ground cover) as its icon, a small cube in its colour without one; nothing for an empty slot. It chops while mining, swings once on a placement, and draws over the world, so a wall never hides it. In third person the whole body walks, sprints, chops and places, and the head follows the look.
