# Logistics

How items move without hands: belts as transport lines, inserters, splitters, mining drills, loose items, and the one interface they all talk through. All movement and timing is integer (fixed point positions, tick counts, seeded draws). Rates and ratios: [content.md](content.md). The machine keys: the header of `data/machines.sjson`.

- Per tick cost is proportional to the items on belts plus the entities, not to belt length.
- Belt lines are rebuilt only when a belt or splitter is placed, removed, turned or reshaped.

## Belts

`belt.odin`, `belt_movement.odin`. A belt is a 1 by 1 by 1 entity with a direction and a shape: flat, ramp or lift.

- Transport lines (Factorio's model): consecutive belts that feed each other form one line with two lanes, left and right of the direction. Items are positions along a lane in 1/256 block, never entities.
- Per tick each lane moves its items from the front backwards by the belt speed, each stopping `BELT_ITEM_SPACING` (a quarter block) behind the item ahead: four items per lane per block. A speed of 1.875 blocks a second with two lanes carries 900 items a minute.
- Every belt block counts as one block of line length, whatever its shape: ramps look a little faster, and both lanes of a curve keep length one where Factorio shortens the inner lane. The ratio math relies on it (`test_belt_curve_keeps_lanes`, `test_belt_ramps_count_one_block`). A run between poles counts its arc length (Runs, below).
- A line ends where its last belt faces something that does not continue it: items compress at the end, or fall off when it hangs over a drop (Loose items). A belt facing the side of another belt side loads onto the near lane. Head on does not connect.
- A flat belt that nothing continues into and exactly one feeder side loads onto becomes a curve. Where two feeders would continue into one belt, the first wins (splitters, then belts, in pool order).
- A line also ends where the speed changes. The hand off keeps exact positions, and an item entering a slower line waits for room.
- A loop continues into itself and moves as a whole when full.
- Ramps rise or fall one block over one block of run and take items straight on only. A column of lift blocks is one line, entered at one end and left onto a flat belt facing away at the other. An up lift exits forward and one block up.
- The player walks over belts and rides flat belts and ramps at belt speed. Lifts do not carry the player.
- A save holds the belts and the items per belt cell (`Belt_Cell_Item`). Lines are derived.

### Placing belts

`belt_placement.odin`.

- The direction is the player's facing turned by the rotation, so rotation 0 points away from the player. A belt placed where another belt's items come out takes that belt's direction. Lifts have eight rotations: four to seven place a down lift.
- Holding Place with a flat belt drags a run along the reticle's path with automatic turns. A one block step of the ground becomes a ramp of the same speed taken from the inventory. Without one the belt stays flat. Only belts this drag placed are turned or reshaped.
- Ramp and lift items place one at a time. A lift placed on a lift continues the column.
- Rotate with no machine selected turns the targeted belt a quarter turn, a lift together with its column.
- On a foundation frame (0174, [architecture.md](architecture.md), Frames) a belt is a cell of the frame: its output cell, the belt or splitter there and a lift's column are looked up in the belt's own frame (`belt_at` and `splitter_at` with the frame), so the lines, the lanes and the side loading run on a frame as on the block world, which is frame 0. A belt never connects to a cell of another frame; belts between frames are runs between poles (Runs, below). The drag placement above is the block world's, and placing belts on a frame from the field waits for the slice (0179).

### Runs

`belt_run.odin`, `belt_run_placement.odin` (0176): free belts between poles and frames, as Satisfactory's. The record and the save: [architecture.md](architecture.md), Simulation.

- A run joins two endpoints: its start, where items leave onto it, and its end, where they arrive. Each is a belt pole (where the run meets it, `height_millimetres` over its bottom) or a belt end: the middle of the bottom edge of a frame cell's flat belt, the edge items leave by at the start and enter by at the end. Each endpoint has a facing, the frame direction items travel in there: a belt end's is its belt's direction, a pole's its own facing or the reverse, whichever the run's chord is nearer, unless the pole has a run of the kind on the other side: then a leaving run takes the facing the arriving run left the pole with and an arriving run the facing the leaving run starts with, so items never turn round on a pole (`belt_pole_fixed_facing`; a run that would cross the pole against that facing is refused `Reverses_At_Pole`). A free pole faces its frame's forward, which the placement turns to the yaw step nearest the chord.
- The curve is a cubic Hermite from the endpoints' positions and facings, each tangent `BELT_RUN_TANGENT_SHARE` of the span (1.17, at which a quarter turn follows its circle), kept as four Bezier control points. The polyline is the curve at `BELT_RUN_SUBDIVISIONS` (32) plus one fixed parameters, the Bernstein basis exact in 1/65536; the arc length is the sum of the segments' `vector_length`, taken on points kept to 1/256 of a position unit and rounded to whole units. Integers only, so every machine computes the same bytes.
- Constraints (`belt_runs` in `data/game.sjson`, [content.md](content.md), Belt poles and runs), all across the mean of the two endpoint frames' ups so a run and its reverse are judged alike: the chord at most `maximum_span_millimetres`. A run whose ends lie within `level_tolerance_millimetres` of each other along that up is level and may turn: the sharpest of the angles between the facings and between each facing and the chord, across that up, at most `maximum_turn_degrees`. Any other run inclines: that angle at most `aligned_degrees` and the belt's rise at most `maximum_slope_percent` of its run across, both along the chord and in the middle of the curve, where an incline between level ends is steepest (the derivative at its middle runs along the control points' P3 + P2 - P1 - P0), so the limit holds of the belt and not only of the chord. Inclining and turning at once is refused (`Belt_Run_Refusal.Inclines_And_Turns`), as is a span over the maximum, a slope too steep, a turn too far, ends that meet, a pole or belt end that already has a run on that side (one run arrives at and one leaves each), a run crossing a pole against its other run, a belt end already fed from behind (`Belt_Already_Fed`) or a start belt whose output already feeds a belt or a splitter (`Belt_Output_Taken`), so a run never dead ends silently behind a belt's own link, and an endpoint that is gone. A nominal quarter turn between frames tilted apart may fall on either side of the turn limit by rounding.
- In the line a belt run is one segment as long as its arc length in line units at the start frame's pitch: `BELT_UNITS_PER_BLOCK` (256) a cell of that pitch, rounded to the nearest unit and at least one. A line holding a run keeps each segment's start (`Belt_Line.segment_starts`, `belt_line_segment_start`, `belt_line_segment_at`); a line of belts alone keeps none and counts a block a segment as before. Items keep their distance along the line across the run, so the spacing and the speed are the line's; the line is rebuilt when a run is added or removed as for a belt (`link_belt_runs` in `compute_belt_links`): the flat belt a run starts at feeds the run instead of its output cell, a run arriving at a pole continues into the run leaving it, a run ending at a belt end continues into that belt, and the run moves at its belt's speed (`Belt_Run.machine`). A line that ends on a run ends there: its items compress at the pole and never fall off.
- Removing a pole removes the runs on it and the items on them are lost (the player has no removal path for poles and runs yet, 0179). A run outlives the belt it starts or ends at: the belt end's frame keeps its record while a run names it, and the run reconnects when the same belt returns to that cell and facing. A frame left with no occupant and no run endpoint loses its record (`release_empty_frame`), so a free pole leaves no frame behind.
- `belt_run_point_at` maps a distance along a run to the polyline, for the renderer ([presentation.md](presentation.md), Runs). The player walks through runs as through belts; collision with them waits.
- A pipe run (`Belt_Run_Kind.Pipe`) has the same poles, curve and constraints and draws as a pipe, but the fluid networks do not connect through it yet: they still connect pipes by cell on frame 0 (0174).
- Placing on the field: past the foundation the held material cycle holds the belt run tool and the pipe run tool. The first Place picks the start: the pole or belt end the selection assist offers (those within the tool's reach whose point lies within `BELT_RUN_ASSIST_RADIUS_MILLIMETRES` of the reticle's ray, the nearest to the ray first, `nearest_belt_run_option`), else a new pole snapped to the targeted frame cell, else a new free pole on the targeted ground. The ghost draws the curve to the reticle's candidate for the end, red when the shape would be refused; the second Place queues the run, Back forgets the start. A new pole takes one pole item; the run takes no item until the slice's content (0179) prices it.

## Inserters

`inserter.odin`. A 1 by 1 by 1 entity that picks one item from the cell behind it and drops it into the cell in front, its reach in cells each way, fixed when it is placed (`inserter_reach_on_frame`).

- The reach (0175): on a foundation frame the arm's `reach_millimetres` (the inserter record, [content.md](content.md), Foundations) over the frame's pitch, rounded down to whole cells and at least one: 2000 mm at the 500 mm pitch is four cells, so the arm picks four cells behind it and not five. On the block frame (frame 0) the reach stays `inserter_reach` cells (one, two for the long inserter), so the block world's inserters, the dev kits and the benchmark factories run as before; that rule goes with the block world (M14). The pickup and drop cells follow the facing on either frame and the lane rules below are the same.

- The cycle is `items_per_minute`: half a swing to the drop, half back, picking and dropping instantly, so with a ready source and sink an inserter moves exactly its rate.
- It picks only an item its target can ever take (`entity_offered_items`, `entity_takes_item_kind`), so it never holds something undroppable. A full target does not stop the pick: the arm waits at the drop with the item.
- From a belt it takes the item nearest the block's middle from either lane. Onto a belt it drops on the far lane. A belt running straight towards or away from it has no far side and takes the right lane.
- The check order at pickup: a filter inserter without a filter, then nothing to pick (Idle), then no fuel.
- A burner inserter burns fuel only while its arm moves. With an empty buffer and fuel slot it feeds itself from fuel it is about to pick or holds.
- An electric inserter draws power only while its arm moves. In a brownout its arm moves on the ticks its power credit pays for.
- Inserter stalls have their own counters, so furnace hints never fire on them.
- The panel's "In hand" slot shows the held item (0079): the player can lift it onto the cursor or quick move it, and an emptied hand drops nothing and swings back. That is the way out of the gravel stall: the panel and the HUD read "Waiting for room: Gravel". Sorting the gravel off the line is the lasting answer.
- The arm's look and swing follow its cycle ([presentation.md](presentation.md), The arm), so two arms swing in step only when their work does: two arms on one belt that feeds them at different rates fall out of step (`test_two_arms_on_one_belt_fall_out_of_step`).
- Placement turns the player's facing by the rotation, like belts. Rotate turns a placed inserter. Its ghost is in [hud.md](hud.md), Targeting.

## Splitters

`splitter.odin`. One block along the flow and two across it, each half where a belt block would stand.

- A belt facing into a half from behind ends its line there. Each half is a one block output line of its own, run after its output lines and before its input lines.
- Items go to the outputs round robin per item and lane, skipping a half with nothing in front of it or no room, so an uneven pair of inputs still fills both outputs. Inputs take turns.
- The panel sets input priority, output priority and one filter. With a filter the filter item goes only to its side and everything else only to the other, each stalling when its side is full. Input priority takes every tick it has items and the other input fills the gaps.
- The targeted cell becomes the left half. Both cells must be free. Rotate turns a splitter half way round, since a quarter turn would move a cell.
- A splitter runs at yellow speed. There is no fast splitter. It does not carry the player, and inserters and drills neither take from it nor give to it.

## Mining drills

`drill.odin`. A square entity with an output arrow, tapping a vein's reservoir, never its blocks.

- A surface drill is valid when one footprint cell stands over a surface vein's footprint disc, whatever block is left there (0048). The first found in footprint order is its vein. Discs, not chunks, so one chunk can hold parts of several veins. Several drills share one vein and drain it together.
- Every cycle it draws one unit, picked by the vein type's mix, seeded by the world seed, the vein and its draw count, so a draw never depends on which drill or tick takes it.
- `items_per_minute` is the ore rate on a vein of `rate_reference_ore_percent` ore. The spoil comes on top at the same unit rate.
- The unit drops into the cell in front of the footprint's middle on the arrow side at ground level, on the arrow's left where a side two cells wide has no middle. A belt there receives on the lane facing the drill. Anything in the drop cell is a target, another drill's fuel slot included.
- A drill never spills: a unit without room is held. The states tell the cases apart: "No output" (nothing in the drop cell), "Output refused: <item>" (the target never takes that item) and "Waiting for room" (full). The placement ghost outlines the drop cell.
- The gravel stall is a deliberate early game mechanic (user decision 2026-09-27): two drills facing each other feed each other's fuel slot and stop at the first gravel unit, and a coal belt that dead ends at an inserter clogs with gravel (`test_drill_feeding_a_drill_stops_on_gravel_and_names_it`, `test_coal_line_dead_end_clogs_with_gravel`). The belt has to run on into a chest. Sorting is the answer, not spilling.
- A burner drill burns fuel only on the ticks it works. An electric drill works at its network's satisfaction through power credit. Both stalls count for hints.
- When a finite vein is exhausted the drill reports it, and the vein's outcrop cells turn to spent rock through `world_set_block` at the end of the tick. Chunks loaded later come out spent too. A cell the player mined or built over keeps its block.
- Mining productivity levels add their effect to a per mille credit per unit drawn. Each full 1000 is an extra unit that costs the vein nothing.

### Bore drills and revival

- Deep veins are a second placement layer per region with their own seed, a depth below the surface and no outcrop. The vein id carries the layer.
- A bore drill taps the deep vein whose disc holds its footprint's centre column, bores `boring_seconds` of powered work, then draws like a surface drill. Its ghost names the deep vein it would tap.
- A drill with `revival_port` keeps an exhausted finite vein producing at half rate (`REVIVAL_CYCLE_FACTOR`) for `REVIVAL_LITRES_PER_UNIT` litres of mining fluid per unit, by the full mix at the depleted low grade share. It has no effect on infinite veins.

## Loose items

`loose_item.odin` (0062). Item stacks lying in world cells: their own list beside the entity pools, never in the occupant index, so they block no placement, movement or ray.

- Sources: a felled tree's logs and its decaying leaves' drops ([content.md](content.md), World), a mined block whose item does not fit, a machine picked up with contents that do not fit, the inventory's Drop, and a belt dead end over a drop. Drills never spill.
- A mined block breaks even with a full inventory and spills what does not fit, with the "Inventory full" toast once. A machine pick up spills at the machine's origin, the machine item last, so a pickup never refuses.
- Drop puts the cursor's stack, or the focused one, into the cell in front of the player at feet height along the quarter the player faces, never the player's own cell.
- Spilling into a solid cell or a machine's cell uses the first open cell above. A machine placed over stacks lifts them onto its top. A block placed into a stack's cell pushes it up a cell per tick.
- Falling: a stack moves into the cell below every `LOOSE_ITEM_FALL_TICKS` while that cell is loaded, holds no solid block and no machine, and both cells are dry. Water holds a stack at its surface, an unloaded chunk where it is.
- A stack in a belt's cell goes onto the belt one item per tick, on the lane on its side, and waits on top while the belt has no room.
- Merging: a later stack of the same item at the same place (cell and quarter block offset) moves into the earlier one up to the stack size, keeping the younger age. A cell may hold several stacks.
- Belt ends: a dead end whose cell in front of the last belt, at the belt's height, is loaded, open and free of entities, with a stack there able to fall, lets the front item of each lane fall off once it reaches the end, keeping its lane as a quarter block offset. A dead end against a wall, a machine or over level ground holds its items and counts for the dead end statistic.
- Pickup: a stack whose cell centre lies within `LOOSE_ITEM_PICKUP_RANGE` blocks of the player in the horizontal plane, in the feet's cell layer or the one below, goes into the inventory as far as it fits (`loose_item_in_pickup_range`). A pickup triggers discovery like a mined item.
- A dropped stack remembers its dropper (`dropping_player`, saved): that player skips it until a tick out of range clears the field, while other players take it at once. A merge takes the dropper of the stack merged in when it has one. Spilled and fallen stacks have none.
- Routing (`inventory_add_picked_up`) for picked up stacks, mined blocks and a machine pick up's returns: partial stacks of the item on the hotbar first. Then a tool or machine takes empty hotbar slots before the main grid, while any other item fills the main grid and takes empty hotbar slots only once the grid is full. A machine pick up checks the fit the same way (`inventory_fits_all_picked_up`). Crafting, quick moves and every other insertion fill the hotbar first (`inventory_add`).
- Despawn: after `loose_item_despawn_minutes` in `data/game.sjson` (0 for never, at most `MAXIMUM_LOOSE_ITEM_DESPAWN_MINUTES`), generous so a spill can be walked back to.
- Order: after the belts in the entity tick, so a stack that fell off a belt end starts falling at once. Saved in the entities file ([architecture.md](architecture.md)).

## Item transfer

`item_transfer.odin`: the one door into an entity's contents for inserters and drills, so callers never switch on the entity kind. Its header lists what each kind takes and gives.

- `entity_accepts` (the slot or lane an item would go to), `entity_insert` (returns the leftover), `entity_extract` (by filter). Belts implement them against one lane of the block.
- Inserters only feed a crafting machine's ingredient slot or a lab's pack slot below `INSERTION_LIMIT_CRAFTS` crafts, so one machine does not swallow a belt. The player's panel is not limited.
- Splitters, pipes, fluid machines without a fuel slot, electric drills, poles, switches and lamps neither take nor give. Burner inserters and drills, boilers and combustion generators take only fuel.
