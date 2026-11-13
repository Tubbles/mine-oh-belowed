# Vessels

One system builds every vessel, the crawler, the rocket and the ship alike (0361): structure pieces that join face to face and bring generic slots, equipment placed into those slots, and every cable and pipe run by hand. A vessel has no slots of its own; its structure brings them ([DESIGN.md](../DESIGN.md), Building). The shipped parts and their values are in [content.md](content.md), Vessel parts. The swap in place, the vessel's figures and its panel are 0365's (What comes next).

## The model

- A vessel is a frame of the frame table plus a `Vessel` record keyed by it (`Entities.vessels`, sorted by frame id, `vessel_index`). `parts_replaced` counts the swaps in place and stays 0 until 0365.
- Its parts are entities of the pool `Entities.vessel_parts` (`Entity_Kind.Vessel_Part`, for both vessel machine kinds) on that frame, so the occupant index, the frame raycast, the collision, the pick up and the save's remap work on them unchanged. A part stores cells, no position (`Vessel_Part` is its `Entity_Common` with a control unit's `power` and a battery's `stored_joules`, 0383), so the vessel's pose is its frame's alone.
- A frame with a vessel record takes vessel parts only: `frame_placement_refusal` returns `Vessel_Frame` for any other machine (a foundation, a machine, a run's snapped pole), which the field tells as `Vessel_Parts_Only`. A vessel part stands on a vessel's frame only: the placement editor's command, the developer's `place` on either world (so a blueprint's `place` line too) and the block world's placement (`placement_at`, behind the player's Place, its ghost and the block world's `place`) refuse the vessel kinds, since the block world neither saves nor hashes vessel parts.
- The two roles of `data/vessel_parts.sjson`: structure brings slots and holds the vessel together, equipment goes into a slot. The control unit (kind `vessel_control_unit`) is equipment, one to a vessel (`One_Control_Unit`).
- Vessel parts never wear, have no panel yet (the control unit's is 0365's) and join no fluid network yet (0356). A part with a power port is a node of the cables' netlist (0368, [fluids.md](fluids.md), Power), after every other pool, so cables join it to its vessel's other parts and, through its connector, to the ground. A cable between a vessel's frame and another frame ends on a connector at the vessel's side (`Not_A_Connector` otherwise); the docking connector has a second power port for the cable inward, since a port takes one cable.
- Batteries and the control unit (0383, `collect_vessel_participants`): a part with a power port, `supplies_watts` and `stores_watt_hours` is a battery, a store of the netlist ([fluids.md](fluids.md), Power, Batteries) holding up to `stores_watt_hours` × 3600 J in `stored_joules`; one with `draws_watts` is a consumer of it, 1 J a tick for the control unit's 60 W. A battery starts empty and its charge does not go with it into the inventory.
- Drawing: `draw_entities` draws a part through its model when its record names one, else a box per held cell (`entity_held_cells`) in the record's `color` under the frame's matrix (`draw_vessel_part`, `render_entities.odin`). The field session draws them with the other entities.

## Data

The machine record (`data/machines.sjson`):

- `kind = "vessel_part"` or `"vessel_control_unit"`: an item and a `color` (three channels of 0 to 255, not all zero) are required, and item slots, power and `fluid_ports` are refused (`validate_vessel_kind_definition`).
- `part_slots = [{side, from = {x, y, z}, to = {x, y, z}}]`, on kind `vessel_part` only, at most `MAXIMUM_PART_SLOTS` (8) (`validate_part_slots`). A box is inclusive, in cells of the unrotated footprint (x along the width, y up, z along the depth), each component -12 to 23 with `from <= to`. `side` is `inside` (the box lies in the footprint), `underneath` (`to.y` is -1 and the box overlaps the footprint in x and z) or `outside` (clear of the footprint, not wholly below it, touching one face, `to` -1 or `from` the size on that axis, and overlapping the footprint on the other two). A part's boxes do not overlap, and its inside boxes leave at least one cell of the footprint held, so the piece can be aimed at and taken off.
- `ports = [{id, kind, cell = {x, y, z}, face, capacity_watts, capacity_litres_per_second}]`, either kind on the two vessel kinds; on the others power ports, and fluid ports on a record with `fluid_ports` or a fluid junction (0368, 0374, [content.md](content.md), Cables, pipes and ports), at most `MAXIMUM_MACHINE_PORTS` (8) (`validate_machine_ports`). The id is not empty and unique on the machine; `kind` is `power` or `fluid`; the cell and the face lie on the footprint's surface (`port_cell_is_on_the_surface`), no two ports on one cell and face; a power port has `capacity_watts` (1 to 1,000,000,000), a fluid port `capacity_litres_per_second` (60, a litre a tick, to 1,000,000,000, 0374), and the other key 0. Separate from `fluid_ports`, the fluid network's buffers.

`data/vessel_parts.sjson`, read through `read_logged_data_file` after the machines (so the edits overlay and its fallback apply), strictly: an unknown key, a wrong type or a missing required key refuses the file (`parse_vessel_parts_file`), and every rule below refuses it naming the record (`resolve_vessel_part_registry`).

- `slot_sizes`: `{id, name_key, width, height, depth}`, every key required, at most `MAXIMUM_SLOT_SIZES` (4), ids unique, each side 1 to 12, width equal to depth, no two sizes alike. `name_key` names the size in the string table.
- `parts`: `{machine, role, line, tier, mass_kilograms}` required, `supplies_watts`, `draws_watts`, `stores_watt_hours`, `stores_litres` (each 0 to 1,000,000,000) and `connector` optional. `machine` names a machine of a vessel kind, each exactly once, and every vessel machine has a record. `role` is `structure` or `equipment`; `tier` is 1 to 15; `mass_kilograms` 1 to 1,000,000.
  - Structure has no figure, no `connector` and no port, and each of its slot boxes is a size. A control unit is not structure.
  - Equipment has no `part_slots`, and its footprint is a size: that is the size of slot it goes into.
  - `connector` (the part that joins a vessel's lines to the ground's) needs a port.
  - One line has one role and one machine kind; a structure line one footprint and the same `part_slots`, an equipment line one footprint, so a swap along a line (0365) never moves a cell.

## Slots, sizes and sides

- A slot is a box of the piece's footprint cells and turns with the piece: `placed_part_slot_box` turns both corners as the footprint turns (`rotate_footprint_cell` is affine, so a box outside the footprint turns about it too) and adds the origin.
- An inside slot's cells are not held by the piece (`machine_held_cells` skips them as it skips a pod's fixture boxes), so an empty ring is hollow and the equipment in it is the only occupant there.
- A slot's size is the size its box equals (`vessel_slot_size_of`); equipment fits a slot whose box is its footprint. Sizes are square, so every quarter turn fits and Rotate turns equipment freely.
- Nothing records what fills a slot. The filler is the equipment whose origin is the box's low cell and whose box is the slot's (`part_slot_filler`), so a load or a swap needs no fix-up, and two structure pieces offering the same box share it.

## Placing

No binding and no mode ([input.md](input.md), Bindings): Place with a part held puts it where the aim says (`field_vessel_placement`, which the tick and the ghost both call), Rotate turns it as it turns a machine's ghost, and the placement editor is not used, since a face or a slot fixes the place.

- Structure held, aimed at a vessel's structure piece: the face snap (below). Aimed at anything else on a frame: `Needs_Vessel_Structure` ("Vessel structure joins a vessel's structure face to face, or starts on the ground"). Aimed at bare ground: a new vessel, its frame standing on the hit as a free foundation's (`free_frame_at`, the player's heading's yaw step, `foundation_pitch_millimetres`) with the piece centred on cell (0, 0, 0) (`field_footprint_origin`), `start_vessel`. There is no flatness check: it stands on the hit and cuts in as a foundation does. A hit in another vessel's extent, the box round its parts' footprints and slots' boxes in its frame's cells, or in the ground up to 12 cells under it (`vessel_extent`, `point_in_a_vessel`), is refused `Inside_A_Vessel` ("That is inside a vessel: aim at its structure"), so a look down a ring's hollow does not begin a second vessel in it.
- The face snap (`structure_face_origin`): along the face's normal the new piece starts at the aimed cell's adjacent layer and grows away from the face. Across it, on each axis, a piece at least as wide as the aimed part is centred on that part (the odd cell on the high side), a narrower one is centred on the aimed cell (offset `(size - 1) / 2`) and kept inside the aimed part's extent. So rings stack aligned and a truss follows the aim along a ring's side.
- Equipment held: the nearest free slot of its size along the view ray (`aim_vessel_slot`). It looks at the structure pieces on vessel frames within the reach plus 12 pitches, turns the eye and the look into each frame's axes, and tests each free box of the size in position units (`fixed_ray_box_entry`, `world_frame_raycast.odin`). The nearest entry before the terrain, frame or trunk hit wins, the first in pool and slot order on a tie. A box holding the eye is skipped, so a crouched player in a deck plate's top slot does not catch it; standing, the eye is above the box, the slot is aimed and the drain refuses `Would_Bury_Player`. Aimed at no slot there is no ghost, and Place tells `No_Free_Slot` ("No free slot of its size here").
- Place's press queues a `Field_Placement` of kind `Vessel_Part` (`queue_vessel_placement`); the drain checks it again against the world the placements before it left (`vessel_placement_refusal`) and applies it with one item taken, counted as placed for the quests (`drain_vessel_placement`). The checks, in order: `Nothing_Held`; `Unknown_Frame` when the frame is gone or no vessel's (not for a new vessel); a new vessel `Inside_A_Vessel`, then `Frame_Cell_Taken` where a cell's centre lies in another frame's occupied cell (`new_frame_cells_meet_a_frame`); structure `Frame_Cell_Taken`, then `Needs_Vessel_Structure` without a held cell face to face with a held cell of the vessel's structure (`cells_touch_vessel_structure`), so a ring touching only through its hollow is refused, not floated; equipment `No_Free_Slot` unless a structure piece offers the box and it is free (`vessel_slot_offered`, `part_slot_box_is_free`), then `One_Control_Unit`; then `Tree_In_The_Way` and `Would_Bury_Player` for every kind.
- The ghost (`draw_vessel_placement_ghost`, `loop_field_session.odin`) is the placement's held cells, or the model's ghost when the record names one, tinted by `vessel_placement_refusal`; nothing when there is no placement.

## Removal

Removal is the pick up: Mine held on the part for `PICK_UP_SECONDS` takes it into the inventory. Equipment always comes off. A structure piece gets no progress, and tells why, while (`vessel_part_removal_refusal`):

- a filled slot of it is offered by no other structure piece: `Holds_Equipment` ("Take its equipment off first");
- the vessel's other structure pieces would not be one face connected set: `Holds_The_Vessel_Together` ("It holds the vessel together"). `vessel_structure_components` labels the pieces by union find over their held cells' six neighbours, the labels counting up in pool order, so the decoupler's split can reuse them.

The last part releases the frame, and `release_empty_frame` drops the vessel's record with it (`remove_vessel_record`).

## The record and the save

- The parts and the records are in `write_simulation_state`, so the state hash covers them through the save's bytes. Placement, removal and the records change only in the tick's drain, in integers.
- In a field world the vessels' table follows the water bodies' table (`write_vessel_tables`, always written): the parts' pool, the live parts' frames in pool order (`Entity_Frame_Record`; the frame tables and the wear table, read before it, skip the kind) and the vessel records. The occupancy follows from the pools (`rebuild_entity_cells`).
- A field save that ends before the table was written before 0361 and loads with no vessels and the line `save: written before vessels (0361), no vessels`.
- A save written before 0383 has parts without `power` and `stored_joules` (the part's schema lacks the charge, `saved_list_has_field`): they read zero, so every battery starts empty, with the line `save: written before the batteries' charge (0383), every battery starts empty` when the save holds a vessel.
- The reader refuses a live part whose machine is of no vessel kind, a frame record naming a dead part or an unknown frame, vessel records out of order or naming no frame, and a live part on a frame with no vessel record.

## What comes next

- 0365: a better part of a line swaps a lesser one in place (`Vessel.parts_replaced`), the vessel's figures summed from its parts (mass, supply, draw, storage, free slots), the seam that tells whether a port is linked, and the control unit's panel listing the parts not hooked up.
- 0356: pipes end on fluid ports; a tank's contents and the wet mass.
- 0357: the crawler moves the vessel's frame (`set_frame_pose`), and a vessel tied to the ground does not move.
- The rocket stage (after 0356): the decoupler splits a vessel along `vessel_structure_components`' labels; a vessel begun on a foundation pad is that item's to decide.
