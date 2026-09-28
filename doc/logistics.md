# Logistics

How items move without hands: belts, inserters, splitters and the burner mining drill, the M3 content. Ratios and rates are in [content.md](content.md); this document is the model.

## Belts

- A belt is a 1 by 1 by 1 entity with a direction and a shape: flat, ramp up, ramp down, or lift (vertical). Belts are not solid: the player walks over them and is carried at belt speed, which is part of the feel.
- Transport lines (Factorio's model): consecutive belts that feed into each other form one line per lane, two lanes per belt (left and right of the direction). Items are positions along the line in fixed point (1/256 block), never entities. Per tick each line moves every item by the belt speed and stops an item behind the one ahead at the minimum spacing of a quarter block, so four items per lane per block. A yellow belt moves 1.875 blocks per second, which with two lanes gives 900 items per minute.
- A line ends where its last belt faces something that is not a belt continuing it; items compress against the end, or fall off it when the end hangs over a drop (Loose items below). A belt facing into the side of another belt side loads onto the near lane. A belt fed from the side at its start becomes a curve; in the alpha both lanes of a curve keep length one (Factorio shortens the inner lane, we do not, documented for the ratio math).
- Ramps rise or fall one block per block of run and count as one block of line length even though they are longer, so items look a little faster on slopes. Lifts stack: a column of lift blocks is that many blocks of line, entered from a flat belt facing into the bottom (or the top, for a down lift) and left onto a flat belt facing away at the other end.
- Placement: rotation sets the direction, and holding Place while moving the reticle drags a run of belts along the path with automatic turns and ramps where the ground steps by one, so long runs do not cost one button press per block on a gamepad. A belt placed into an existing run re orients to continue it.
- Rendering: one mesh per belt shape with a scrolling texture for the surface, items drawn as small instanced cubes at their line positions, at most eight per belt block.

### As implemented in 0014

- Belt direction on placement is relative to the player's facing turned by the rotation (rotation 0 points away from the player). Lifts have eight rotations, four to seven placing a down lift; an up lift exits forward and one block up. Ramps and lifts accept items straight on only. Only the flat belt drags; automatic ramps consume a ramp item from the inventory and without one the run breaks at the step. A placed belt rotates with Rotate while no machine item is selected. Loop lanes are advanced as a whole so a full loop keeps moving. Lifts do not carry the player and ramps are not walkable slopes yet. All lines are rebuilt on any belt change, from per cell item records that double as the save form. Items are drawn one cube each, not instanced.

## Inserters

- A 1 by 1 by 1 entity with a direction. It picks up from the cell behind it and drops into the cell in front of it, with the arrow showing the drop side. One item at a time in the alpha.
- Sources: belts (either lane, the item nearest the pickup point), chests, machine output slots, the capsule. Sinks: belts (the far lane, as in Factorio), chests, machine input slots that accept the item (fuel into the fuel slot, smeltable ore into the input), never output slots. A filter inserter moves one item type only.
- A fixed cycle of ticks derived from the rate: pick, swing, drop, swing back. The burner inserter has a fuel slot and stalls without fuel; the electric inserter idles until it has power (M4) and until then is a slower placeholder that never moves.

### As implemented in 0015

- Two read only calls joined the transfer interface: a peek at what a source offers and whether a target would ever take an item kind, so an inserter only picks what its target can take and never holds something undroppable. A full target does not stop the pick: the arm carries the item and waits at the drop. A belt running straight towards or away from the inserter has no far side and takes items on its right lane. Check order at pickup: no filter, then nothing to pick (idle), then no fuel. Inserter stalls have their own counters so furnace hints do not fire on inserters. Placement direction is relative to the player's facing like belts; rotating a placed inserter and burner inserters feeding themselves from carried fuel come with 0016.

### As implemented in 0079

- The inserter panel shows the arm's hand in an "In hand" slot under the fuel or filter row, empty when the hand is. A or a click with an empty cursor lifts the item onto the cursor, a quick move puts it into the inventory (what does not fit stays in the hand), and the slot takes nothing in. An arm whose hand the player emptied drops nothing and swings back to pick again. This is the way out of the gravel stall: an inserter that picked an item its target stopped taking waits at the drop, reads "Waiting for room: Gravel" in its panel and in the HUD, and the player takes the item from its hand. Sorting the gravel off the line (a chest at the belt's end) remains the lasting answer.

## Splitters

- A 2 by 1 by 1 entity across two adjacent belts, with a direction. Two inputs feed two outputs round robin per item, so an uneven pair of inputs still fills both outputs. Input priority and output priority flags, and one output filter, are data fields on the same entity and appear in its panel; the alpha implements them because they are the difference between spaghetti and a bus.

### As implemented in 0017

- Each splitter half is its own one block line, so a splitter is two line ends and two line starts; the tick order walks splitters after their output lines and before their input lines. The targeted cell becomes the left half and the right half extends to the right of the flow. Both cells must be free, so belts are picked up before a splitter goes down; a splitter does not carry the player and Rotate turns it half way round since a quarter turn would move a cell. With a filter set there is no round robin: the filter item goes only to its side and everything else only to the other, each stalling when its side is full. Input priority takes every tick it has items, the other input fills gaps. Items routed to the other half jump sideways at the entry edge without animation. Inserters and drills neither take from nor give to splitters.

### As implemented in 0037

- Belt speed comes from the machine entry everywhere: fast belts, ramps and lifts (3.75 blocks per second, 1800 items per minute) exist, drag placement picks the same speed's ramp or lift, lines split where the speed changes and the hand off keeps exact positions with an item entering a slower line waiting for room; faster belts are tinted red in the placeholder art. There is no fast splitter, a splitter keeps yellow speed inside it. Inserters have a data driven reach; the long inserter picks and drops two cells away and the fast inserter moves about 138 per minute.

## Burner mining drill

- A 2 by 2 by 2 entity with a fuel slot and an output arrow. It is valid on a vein outcrop: at least one footprint cell stands on an outcrop block of a vein. It taps that vein's reservoir, not the blocks: every cycle it takes one unit from the vein, chosen by the vein type's output mix with a random generator seeded by tick and vein id (deterministic), and produces the ore or spoil item into the cell in front of the arrow, onto a belt or into a chest or machine that accepts it. It stalls when the output is blocked or fuel is out, and both stalls are counted for hints.
- A drill is valid when at least one footprint cell stands over a surface vein's footprint disc, whatever block is left there (0048): mining the outcrop by hand does not stop drilling, and the HUD names the vein under any block in a footprint. Footprints are discs, not whole chunks, so one chunk can hold parts of several veins, each drillable on its own disc. Several drills share one vein and drain it together. When a finite vein is exhausted the drill reports it, and the outcrop blocks turn to spent rock through the ordinary block change path so light and remeshing follow.
- Ore grades (high and low) are phase 5 content; in M3 a drill produces plain ore items.

### As implemented in 0016

- The drill draws one unit per cycle. The cycle is tuned so an 80 percent ore vein yields 15 ore per minute (18.75 units per minute), so other vein types yield their own mix at the same unit rate. The draw is seeded by world seed, vein id and the vein's draw counter, independent of tick timing and of which drill draws. The drop cell is at ground level in front of the arrow side, on the arrow's left where a two wide side has no middle; a belt there receives on the lane facing the drill. Anything in the drop cell is a target, including another machine's fuel slot; an empty drop cell leaves the drill in the "No output" state, a target that never takes the held item's kind in "Output refused: <item>" (a coal drill feeding another drill's fuel slot stops at the vein's first gravel unit; the belt and inserter loop of the coal loop quest survives it because an inserter picks only what its target takes), and a full target in "Waiting for room" (couch test 1 found the three indistinguishable), and the placement ghost outlines the drop cell. An inserter's ghost outlines its pickup cell (dim) and drop cell (bright) at the machine's reach, so a long inserter shows cells two away, with a chevron from pickup to drop over the post. Two drills facing each other feed each other's fuel slot, since each drop cell lies inside the other's footprint, and the gravel stall is kept as an early game mechanic (user decision 2026-09-27): sorting is the answer, not spilling. The same gravel clogs a coal belt that dead ends at an inserter: the inserter picks only what its target takes, so gravel piles up at the end and coal stops reaching the pickup cell (a test pins it); the belt has to run on into a chest, which the coal loop quest now says. Exhaustion turns the vein's recorded outcrop cells to spent rock one tick after they are loaded, so chunks loaded later follow. Burner inserters feed themselves from the fuel they are about to pick or already hold, and Rotate turns a placed inserter or drill.

### As implemented in 0035

- Deep veins are a second placement layer per region with their own seed, a depth below the surface and no outcrop; the vein id carries the layer so the two never collide. The bore drill (4 by 4 by 4, 300 kW) is valid where its centre column lies inside a deep vein's disc, bores for 180 seconds, then draws 60 units per minute. The electric mining drill and the bore drill have a revival port: mining fluid (sulfur and water in the chemical plant) keeps an exhausted vein producing at half rate for 10 litres per unit, drawing the vein mix as if the reservoir were full. Bauxite, alumina and aluminium, gold ore and gold plate, quartz and silicon arrived with the electrolyser. Handed to 0036: the bore drill ghost should name the deep vein it would tap, since nothing marks deep veins before the prospecting tools; the revived draw should use the depleted vein's 60 percent low grade share.

## Loose items

Item stacks lying in world cells (work item 0062, `src/loose_item.odin`). They are not machines: they live in their own list next to the entity pools, never in the entity cell map, so they block no placement, movement or ray.

- Sources: a felled tree (0059) drops the logs above the mined one at their cells and its decaying leaves drop leaves and saplings now and then (`doc/content.md` Trees); a mined block whose items do not fit breaks anyway and spills the rest at its cell (the "Inventory full" toast still shows once for that block); picking up a machine takes what fits and spills the rest at the machine's origin after it is gone (contents, held items, and the machine item itself last), so a pickup never refuses; the inventory's Drop puts the cursor's stack, or the focused one with nothing held, into the cell in front of the player at feet height (along the quarter the player faces, so never the player's own cell); a belt dead end over a drop. Drills never spill: a refused unit stalls the drill on purpose.
- Spilling into a solid cell or a machine's cell puts the stack in the first open cell above. A machine placed over stacks lifts them onto its top; a block placed into a stack's cell pushes it up a cell per tick.
- Falling is integer: a stack moves into the cell below every 6 ticks while the cell below is loaded, holds no solid block and no machine, and both cells are dry. Water holds a stack at its surface, an unloaded chunk where it is. A stack in a belt's cell goes onto the belt, one item per tick on the lane on its side, and waits on top while the belt has no room.
- Merging: a later stack of the same item at the same place in a cell (cell and quarter block offset) moves into the earlier one up to the stack size, keeping the younger age. A cell may hold several stacks.
- Belt ends: a line whose end is a dead end, with the cell in front of its last belt at the belt's height loaded, open and free of entities, and a stack there able to fall, lets the front item of each lane fall off into that cell once it reaches the end, keeping its lane as a quarter block offset, so items falling onto a belt below land on the same lane. A dead end against a wall, a machine or over level ground holds its items as before and counts towards the dead end statistic.
- Pickup: walking over stacks in the player's cell or the cell under the feet puts them into the inventory as far as they fit, hotbar first for items already there; a full inventory leaves them lying. Discovery follows from the inventory scan like mined items.
- Despawn: a stack vanishes after `loose_item_despawn_minutes` from `data/game.sjson` (15, 0 for never), counted in ticks of its age.
- Order: after the belts in the entity tick, so a stack that fell off a belt end starts falling at once. Saved in the entities file (`doc/architecture.md`). Drawn as a 0.3 block cube coloured like belt items, turning slowly and bobbing, its fall interpolated between cells.

## Item transfer

One small interface per entity kind, so inserters and drills never know what they talk to: `entity_accepts(handle, item) -> (slot, ok)`, `entity_insert(handle, stack) -> leftover`, `entity_extract(handle, filter) -> Item_Stack`. Belts implement the same three against a lane position instead of a slot. Chests, furnaces and the capsule implement them over their slots with the slot filters from 0011.

## Determinism and cost

All movement and timing is integer: fixed point positions, tick counts, seeded generators. Per tick cost is proportional to items on belts plus entities, not to belt length, since empty line segments cost nothing. Lines are rebuilt only when a belt is placed, removed or rotated.
