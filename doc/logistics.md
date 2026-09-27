# Logistics

How items move without hands: belts, inserters, splitters and the burner mining drill, the M3 content. Ratios and rates are in [content.md](content.md); this document is the model.

## Belts

- A belt is a 1 by 1 by 1 entity with a direction and a shape: flat, ramp up, ramp down, or lift (vertical). Belts are not solid: the player walks over them and is carried at belt speed, which is part of the feel.
- Transport lines (Factorio's model): consecutive belts that feed into each other form one line per lane, two lanes per belt (left and right of the direction). Items are positions along the line in fixed point (1/256 block), never entities. Per tick each line moves every item by the belt speed and stops an item behind the one ahead at the minimum spacing of a quarter block, so four items per lane per block. A yellow belt moves 1.875 blocks per second, which with two lanes gives 900 items per minute.
- A line ends where its last belt faces something that is not a belt continuing it; items compress against the end. A belt facing into the side of another belt side loads onto the near lane. A belt fed from the side at its start becomes a curve; in the alpha both lanes of a curve keep length one (Factorio shortens the inner lane, we do not, documented for the ratio math).
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

## Splitters

- A 2 by 1 by 1 entity across two adjacent belts, with a direction. Two inputs feed two outputs round robin per item, so an uneven pair of inputs still fills both outputs. Input priority and output priority flags, and one output filter, are data fields on the same entity and appear in its panel; the alpha implements them because they are the difference between spaghetti and a bus.

## Burner mining drill

- A 2 by 2 by 2 entity with a fuel slot and an output arrow. It is valid on a vein outcrop: at least one footprint cell stands on an outcrop block of a vein. It taps that vein's reservoir, not the blocks: every cycle it takes one unit from the vein, chosen by the vein type's output mix with a random generator seeded by tick and vein id (deterministic), and produces the ore or spoil item into the cell in front of the arrow, onto a belt or into a chest or machine that accepts it. It stalls when the output is blocked or fuel is out, and both stalls are counted for hints.
- Several drills share one vein and drain it together. When a finite vein is exhausted the drill reports it, and the outcrop blocks turn to spent rock through the ordinary block change path so light and remeshing follow.
- Ore grades (high and low) are phase 5 content; in M3 a drill produces plain ore items.

### As implemented in 0016

- The drill draws one unit per cycle. The cycle is tuned so an 80 percent ore vein yields 15 ore per minute (18.75 units per minute), so other vein types yield their own mix at the same unit rate. The draw is seeded by world seed, vein id and the vein's draw counter, independent of tick timing and of which drill draws. The drop cell is at ground level in front of the arrow side, on the arrow's left where a two wide side has no middle; a belt there receives on the lane facing the drill. Anything in the drop cell is a target, including another machine's fuel slot. Exhaustion turns the vein's recorded outcrop cells to spent rock one tick after they are loaded, so chunks loaded later follow. Burner inserters feed themselves from the fuel they are about to pick or already hold, and Rotate turns a placed inserter or drill.

## Item transfer

One small interface per entity kind, so inserters and drills never know what they talk to: `entity_accepts(handle, item) -> (slot, ok)`, `entity_insert(handle, stack) -> leftover`, `entity_extract(handle, filter) -> Item_Stack`. Belts implement the same three against a lane position instead of a slot. Chests, furnaces and the capsule implement them over their slots with the slot filters from 0011.

## Determinism and cost

All movement and timing is integer: fixed point positions, tick counts, seeded generators. Per tick cost is proportional to items on belts plus entities, not to belt length, since empty line segments cost nothing. Lines are rebuilt only when a belt is placed, removed or rotated.
