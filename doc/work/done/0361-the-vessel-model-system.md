# 0361: The vessel model system

Status: landed (2026-11-11, c64634f)

The user (2026-11-11): "I want to have some \"Theseus model system for vessels\" that includes the crawler among other vessels, space ship, rocket etc.", "Think generic slots and keep the cables for power and fluids, so we need to hook it all up as we place it down. E.g. liquid rocket stage: place fuselage, place tanks for fuel and oxygen, place engine, hook up fluid pipes, place batteries, hook up power lines", and before it "I don't like prebaked slots on the vessel though, I want to capture the sandbox feel from TLC". The draft the user was sent is `work/vessel_model_system.md`; the user then asked for the design. Its six questions are not answered, so the design takes the draft's proposals and marks each as the main agent's, for the user to overturn.

## Goal

One system builds every vessel: structure that snaps freely and brings generic slots, equipment placed into slots, every cable and pipe run by hand, what the vessel can do computed from its parts, and any part swapped for a better one in place.

## Controls

No new binding and no new mode. Placing stays Place with the part held, and what is aimed at decides where it goes, as the inventory binding opens the aimed machine:

- A structure piece held: the ghost snaps to the aimed free face of a vessel's structure, or to the ground to begin a vessel. Rotate turns it as it turns a machine's ghost.
- Equipment held: the ghost snaps into the aimed free slot of its size. Rotate turns it through the orientations the slot allows. Aimed at no slot, there is no ghost and Place does nothing, with the reason shown as the other refusals are.
- A part held and aimed at a part of the same size or shape and a lower tier: the ghost shows the replacement and Place swaps it in place.
- Taking a part off is the existing removal, refused while something is attached that would be left without a slot.
- Cables and pipes are 0355's and 0356's controls, unchanged on a vessel.
- The vessel's panel opens with the inventory binding aimed at the control unit.
- The placement editor (0215) is not used for vessel parts: a slot fixes the position.

## Change

- The part table in data: structure and equipment, sizes, the slots a structure piece brings (a size and a side each), ports, mass, storage, what a part delivers when fed, tiers.
- A vessel as a frame holding its parts, its slots' contents and its connections, in the simulation state, hashed and saved.
- Placement into slots and onto structure faces, removal, and the swap in place that keeps the connections whose ports remain.
- The computed figures (mass, power, drive) in integers, recomputed when a part or a connection changes, and the panel that shows them with what is not hooked up.
- The connector that joins a vessel's netlists to the ground's, and the rule that a connected vessel does not move.
- This item ends with a vessel that is built, hooked up and upgraded while standing still. The crawler's motion is 0357, rewritten on this; the rocket stage and the decoupler are an item after 0356.
- Docs: a new `doc/vessels.md`, `DESIGN.md` (Building), `doc/content.md`, `doc/input.md`.

## Verify

- The checks and the suite, with a vessel built, hooked up, saved, loaded and one part of each role swapped, the state hash equal on two machines.
- Captures of a small vessel being built and of its panel with one connection missing, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `ee21546`. No unlanded item is built on. 0347 (designed, not landed) rewrites the model draw's leaf; whichever lands second follows the other's pool loop in `draw_entities`. The work is marked **A** (parts, building, removal, save) and **B** (swap, figures, panel); see question 1 for the split.

### Decisions

1. **A vessel is a frame and a record; its parts are entities.** A vessel is a frame of `Frame_Table` plus a `Vessel` record keyed by that frame (`Entities.vessels`, sorted by frame id). Its parts are entities of a new pool `Entities.vessel_parts` (`Entity_Kind.Vessel_Part`) on that frame, so the occupant index, the raycast, the collision, the bodies, the pick up and the remap work unchanged. A part stores cells only, never a world position, so the pose is the frame's alone (what 0357 moves with `set_frame_pose`). Rejected: parts as arrays inside the vessel record (a second raycast, collision and draw); parts in the foundations' pool (0355 and 0356 put charge and contents on the part, and moving entities between pools later is a save remap).
2. **A slot is a cell box on a structure part's footprint, and nothing records what fills it.** A slot is filled when the vessel part in its box's low cell is equipment whose origin is that cell and whose size is the box's (`part_slot_filler`). The hosting is derived from the occupancy, so a structure swap, a load and the later split need no fix-up, and two parts offering the same box share it. An inside slot's cells are cells its part does not hold (`machine_held_cells` skips them as it skips a pod's fixture boxes), so an empty ring is hollow.
3. **The data splits the way the machine table already does.** Geometry stays on the machine record in `data/machines.sjson`, beside the footprint, the model and `open_cells`: the kinds `vessel_part` and `vessel_control_unit`, `part_slots` and `ports`. The rest lives in `data/vessel_parts.sjson`, keyed by machine id: `slot_sizes`, and per part its role, line, tier, mass and what it does. Ports are on the machine record because 0355 gives every electric machine one; this item defines the key and 0355 extends it. Rejected: everything in one new file, which would make `machine_held_cells` read a second registry.
4. **Sizes are square boxes and an equipment's size is its footprint.** A slot size is width = depth by height in cells. Equipment fits a slot whose box is its footprint. Every quarter turn fits, so "the orientations the slot allows" are all four, and a swap keeps the cells. A slot's size is found by matching its box against the table, so the machine loader stays size agnostic.
5. **Place with a part held** (`field_vessel_placement`, pure; the tick and the ghost call it):
   - With equipment held:
     1. Aimed at a part of the held part's line and a lower tier, the held part swaps it (B).
     2. Otherwise the nearest free slot of the held size along the view ray takes it, if nearer than the terrain, frame or trunk hit. The ray is tested against each slot box (`ray_box_entry`). A box holding the eye is skipped, so a deck's top slot does not catch a player standing in it.
     3. Otherwise there is no placement, and Place toasts `No_Free_Slot`.
   - With structure held:
     1. A swap, as above.
     2. Aimed at a structure part, the face snap (decision 6).
     3. Aimed at anything else on a frame: `Needs_Vessel_Structure`.
     4. Aimed at bare ground: a new vessel, its frame standing on the hit as a free foundation's does (`free_frame_at`, pitch `foundation_pitch_millimetres`), the footprint centred on cell (0, 0, 0) (`field_footprint_origin`). No flatness check: it stands on the hit and cuts in like a foundation.
   - Rotate turns `placement_rotation` as for a machine. A swap keeps the replaced part's rotation.
6. **The face snap** (`structure_face_origin`):
   - Along the face's normal, the new piece starts at the layer of the aimed cell's adjacent cell.
   - Across the face, on each axis:
     - if the held piece is at least as wide as the aimed part, it is centred on the aimed part (the odd cell on the high side);
     - else it is centred on the aimed cell (offset `(size - 1) / 2`) and clamped inside the aimed part's extent.
   - So rings stack aligned on a hollow top, and a small piece follows the aim along a long one.
   - The drain then requires one held cell of the new piece face to face with a held cell of the vessel's structure (`Needs_Vessel_Structure`). A ring whose hollow lands on the aimed cell is refused, not floated.
7. **A vessel takes vessel parts only, and vessel parts stand on vessel frames only.** `frame_placement_refusal` returns `Vessel_Frame` for any other machine on a vessel's frame: foundations, machines, a run's snapped pole. The field reports it as `Vessel_Parts_Only`. The placement editor's command, the developer's `place` and the block world's placement refuse the vessel kinds.
8. **Removal is the existing pick up**, with two refusals for a structure part. `Holds_Equipment` applies when a filled slot of the part is offered by no other structure part. `Holds_The_Vessel_Together` applies when the remaining structure parts are not one face connected set (`vessel_structure_components`; the decoupler's split reuses its labels). Equipment always comes off. The last part releases the frame, and `release_empty_frame` drops the record. The connectivity refusal is added to the Controls' rule, see question 4.
9. **One control unit a vessel** (the user's question 4): the kind `vessel_control_unit`, refused a second time with `One_Control_Unit`. `entity_has_panel` is true for a control unit on a vessel's frame (B).
10. **Swap in place (B).** Same line and a higher tier. The entity keeps its handle, origin, rotation and cells; only `Entity_Common.machine` changes, and its body is registered again. The old part's item goes to the inventory: the swap is checked on a copy, so a held stack of one frees its slot, and with no room it is refused `Inventory_Full`. `Vessel.parts_replaced` counts. A line has one role and one machine kind. A structure line has one footprint and one slot layout, an equipment line one size, so a swap never moves a cell. Ports may differ. Links on port ids the new record lacks are 0355's and 0356's to drop.
11. **Ports and the link seam.** A port is an id, a kind (`power` or `fluid`), a cell, a face out of the footprint and a capacity (W or L/s). The capacity is what a connector's tier improves. `machine_port_is_linked(entities, owner, port)` returns false until 0355 (power) and 0356 (fluid) answer it from their cables and pipes. A part is hooked up for a kind when one of its ports of that kind is linked. The panel lists the parts and kinds that are not (B).
12. **The figures are a pure function**, `vessel_figures`. Nothing is cached, hashed or saved; the panel computes it once a frame for one vessel. 0357 caches it if its profile asks. Wet mass waits for 0356's contents, drive for 0357's tracks.
13. **Save: one table after the water bodies'**, written always in a field world (`write_vessel_tables`): the parts pool, the parts' frames, the vessel records. `entity_frame_records` and `machine_wear_records` skip the kind, since both tables are read before it. Vessel parts never wear in this item: no tick calls `record_operation` on them. A save that ends before the table loads with no vessels and the line `save: written before vessels (0361), no vessels`. A file whose vessel part names a machine of another kind, or whose vessel names no frame, is refused.

### The user's six questions

Each answer is the main agent's proposal, which the user may overturn.

1. **Slots only, no free deck.** Deck plates bring a medium slot on top. *Reversal:* equipment centred on any free top face of structure (a third branch in `field_vessel_placement`, hosting by support), about a day of the placement and removal code.
2. **Three sizes (1, 2, 4 cells) and three sides (inside, outside, underneath).** *Reversal:* sizes are data, sides one enum.
3. **Physics or a terrain set pose** is 0357's question. Nothing here moves, and everything is integer, so either holds.
4. **The control unit is required, one a vessel, and the panel opens there.** *Reversal:* drop `One_Control_Unit`, or give every vessel part the panel in `entity_has_panel`. One line each.
5. **No factory machines on a vessel** (`Vessel_Parts_Only`). *Reversal:* a vessel record naming a factory kind's machine, the validation relaxed, Place routed by the aim (a slot or the ground) for that item, and the frame refusal letting it through. The kind's tick does not read the frame. Moderate.
6. **Order:** 0361 A, 0361 B (or the item that takes it), 0355, 0356, 0357 rewritten on this, then the rocket stage with the decoupler. Hooking up lands with 0355. *Reversal:* 0355 first, which then adopts the `ports` key defined here unchanged.

### What the siblings need and get

- **0355 gets:**
  - the `ports` key and `Machine_Port`, which it extends to every electric machine (lifting the vessel kinds only check);
  - endpoints as (entity handle, port index), the swap's call site for dropping links on lost port ids (the end of `swap_vessel_part`'s caller);
  - `machine_port_is_linked` to answer;
  - the battery's `supplies_watts` and `stores_watt_hours` and the control unit's `draws_watts` as its participants' figures;
  - the connector flag, for its rule that a cable between a vessel's frame and another frame ends on a connector port.
- **0355 must give:**
  - spans derived from the endpoints' frame poses each frame, never stored world positions (0347's decision 9 notes the runs do that);
  - the battery's charge, on `Vessel_Part`;
  - what a dropped link becomes. The field has no loose items, so it goes into the inventory or refuses (the draft said "to the ground").
- **0356:** pipes on `fluid` ports, a tank's contents against `stores_litres` (on `Vessel_Part`), and wet mass in `Vessel_Figures`.
- **0357:**
  - the crawler is a vessel. Its old Change bullets (a deck that is a foundation frame, "no slots", a mounts key) are superseded;
  - track equipment, a `traction` key and the drive figure;
  - the motion through `set_frame_pose`;
  - `vessel_is_tied(entities, frame)` over 0355's and 0356's cross frame links;
  - splitting `Frame_Table.revision` into occupancy and pose (0347's decision 9). This item moves no frame and changes no revision per tick.
- **The decoupler** moves one component of `vessel_structure_components`, with the equipment its slots host, onto a new frame of the same pose and a new record.
- **0358:** nothing. A cradle on a vessel is a both-way part (question 5) or a vessel part of 0357's.

### Data

`data/machines.sjson`: nine records. Kind `vessel_part`, except `control_unit`, which is kind `vessel_control_unit`. Each has an item, a `color` and no model; the placeholder is a box per held cell in its colour. Cells are x along the width, y up, z along the depth of the unrotated footprint.

| id | footprint w×d×h | part_slots (side: from to) | ports (id kind cell face capacity) |
|---|---|---|---|
| `iron_truss` | 1×1×1 | outside (0,1,0) (0,1,0) | |
| `iron_deck_plate` | 2×2×1 | outside (0,1,0) (1,2,1); underneath (0,-2,0) (1,-1,1) | |
| `iron_fuselage_ring` | 4×4×2 | inside (1,0,1) (2,1,2); outside (-1,0,1), (2,0,-1), (4,0,2), (1,0,4), each one cell | |
| `steel_fuselage_ring` | as the iron ring | as the iron ring | |
| `lead_battery` | 1×1×1 | | `power_a` power (0,0,0) positive_z 2000 W; `power_b` power (0,0,0) negative_z 2000 W |
| `nickel_battery` | 1×1×1 | | as lead, 3000 W |
| `iron_tank` | 2×2×2 | | `fluid` fluid (0,0,1) positive_z 10 L/s |
| `control_unit` | 1×1×1 | | `power` power (0,0,0) positive_z 200 W |
| `docking_connector` | 1×1×1 | | `power` power (0,0,0) positive_z 5000 W; `fluid` fluid (0,0,0) positive_x 20 L/s |

The ring's four outside slots map onto each other under a quarter turn, so a turned ring offers the same boxes.

Keys and rules:

- `part_slots = [{side, from = {x, y, z}, to = {x, y, z}}]`: at most `MAXIMUM_PART_SLOTS` (8), on kind `vessel_part` only. Each component lies in -12 to 23, with `from <= to`.
  - An inside box lies in the footprint.
  - An underneath box has `to.y == -1` and overlaps the footprint in x and z.
  - An outside box lies outside the footprint, not wholly below it, and on one axis touches a footprint face (`to == -1` or `from == size`) while overlapping it on the other two.
  - A part's boxes do not overlap.
- `ports = [{id, kind, cell = {x, y, z}, face, capacity_watts, capacity_litres_per_second}]`: at most `MAXIMUM_MACHINE_PORTS` (4), on the two vessel kinds only until 0355.
  - The id is non-empty and unique on the machine. The kind is `power` or `fluid`.
  - The cell and face pass `port_cell_is_on_the_surface`, and no two ports share a cell and face.
  - A power port has `capacity_watts` and a fluid port `capacity_litres_per_second`, each 1 to 1,000,000,000, the other key 0.
- Both vessel kinds need an item and a `color` (`foundation_color_is_valid`).

`data/vessel_parts.sjson`, loaded strictly through `parse_configuration_layer` and `assign_configuration_value`, so unknown keys and wrong types refuse:

- `slot_sizes`: `small` 1×1×1, `medium` 2×2×2, `large` 4×4×4, each `{id, name_key, width, height, depth}`, every key required. At most 4 sizes. Ids unique, each side 1 to 12, width = depth, no two sizes alike.
- `parts`: each `{machine, role, line, tier, mass_kilograms}` required, plus optional `supplies_watts`, `draws_watts`, `stores_watt_hours`, `stores_litres` (each 0 to 1,000,000,000) and `connector` (bool).
  - `machine` names a machine of a vessel kind, which has exactly one record, and every vessel machine has one.
  - `role` is `structure` or `equipment`. `tier` is 1 to 15. `mass_kilograms` is 1 to 1,000,000.
  - Structure has no function keys and no ports, and each of its slot boxes matches a size.
  - Equipment has no `part_slots`, and its footprint matches a size. A control unit is equipment. `connector` needs a port.
  - One line has one role and one machine kind. A structure line has one footprint and equal `part_slots`, an equipment line one footprint.

| machine | role | line | tier | kg | function |
|---|---|---|---|---|---|
| `iron_truss` | structure | `truss` | 1 | 40 | |
| `iron_deck_plate` | structure | `deck_plate` | 1 | 160 | |
| `iron_fuselage_ring` | structure | `fuselage_ring` | 1 | 420 | |
| `steel_fuselage_ring` | structure | `fuselage_ring` | 2 | 300 | |
| `lead_battery` | equipment | `battery` | 1 | 60 | supplies 2000 W, stores 2000 Wh |
| `nickel_battery` | equipment | `battery` | 2 | 45 | supplies 3000 W, stores 3000 Wh |
| `iron_tank` | equipment | `tank` | 1 | 150 | stores 1000 L |
| `control_unit` | equipment | `control_unit` | 1 | 20 | draws 50 W |
| `docking_connector` | equipment | `docking_connector` | 1 | 30 | connector |

`data/items.sjson`: nine items with `category = "machine"`, the stack size 50 for the truss and the deck plate and 20 for the others, and the price the sum of the recipe's input prices:

| item | price |
|---|---|
| `iron_truss` | 6 |
| `iron_deck_plate` | 14 |
| `iron_fuselage_ring` | 48 |
| `steel_fuselage_ring` | 152 |
| `lead_battery` | 20 |
| `nickel_battery` | 34 |
| `iron_tank` | 36 |
| `control_unit` | 34 |
| `docking_connector` | 36 |

`data/recipes.sjson`: one recipe each, with `channel = "discovery"`, `made_in = ["hand", "assembler"]`, `category = "machines"` and `tags = ["vessel", <metal>]`:

| recipe | inputs | seconds |
|---|---|---|
| `iron_truss` | iron_plate 2, iron_rod 2 | 0.5 |
| `iron_deck_plate` | iron_plate 6, iron_rod 2 | 2 |
| `iron_fuselage_ring` | iron_plate 20, iron_rod 8 | 2 |
| `steel_fuselage_ring` | steel 12, iron_rod 8 | 2 |
| `lead_battery` | lead_plate 6, copper_wire 4, iron_plate 2 | 2 |
| `nickel_battery` | nickel_plate 6, copper_wire 4, steel 1 | 2 |
| `iron_tank` | iron_plate 16, pipe 2 | 2 |
| `control_unit` | electronic_circuit 4, copper_wire 6, iron_plate 2 | 2 |
| `docking_connector` | copper_wire 8, pipe 2, steel 2 | 2 |

`data/strings/en.sjson`:

- `machine_`, `describe_machine_`, `item_` and `describe_item_` for each part. A description says the role and, for structure, the slots it brings.
- The size names `vessel_slot_small`, `vessel_slot_medium`, `vessel_slot_large`.
- The refusals:

  | key | text |
  |---|---|
  | `field_refused_no_free_slot` | "No free slot of its size here" |
  | `field_refused_vessel_parts_only` | "Only vessel parts go on a vessel" |
  | `field_refused_needs_vessel_structure` | "Vessel structure joins a vessel's structure face to face, or starts on the ground" |
  | `field_refused_one_control_unit` | "A vessel has one control unit" |
  | `field_refused_holds_equipment` | "Take its equipment off first" |
  | `field_refused_holds_the_vessel_together` | "It holds the vessel together" |
  | `field_refused_not_an_upgrade` (B) | "Not a better part of its line" |

- The panel (B):

  | key | text |
  |---|---|
  | `vessel_panel_mass` | "Mass" |
  | `vessel_panel_supply` | "Supply" |
  | `vessel_panel_draw` | "Draw" |
  | `vessel_panel_storage` | "Storage" |
  | `vessel_panel_free_slots` | "Free slots" |
  | `vessel_panel_parts_replaced` | "Parts replaced" |
  | `vessel_panel_not_hooked_up` | "Not hooked up" |
  | `vessel_panel_hooked_up` | "Everything is hooked up" |
  | `vessel_panel_more` | "and {count} more" |
  | `vessel_port_kind_power` | "power" |
  | `vessel_port_kind_fluid` | "fluid" |

### State, save and hash

- `Vessel_Part :: struct {using common: Entity_Common}`, in its pool.
- `Vessel :: struct {frame: Frame_Id, parts_replaced: u32}`, in `Entities.vessels`.
- Both are in `write_simulation_state`, so the state hash covers them through the save bytes.
- The table is written last in a field world:
  - `write_pool(vessel_parts)`;
  - `write_list` of `Entity_Frame_Record` for the live parts, in pool order;
  - `write_list(vessels)`.
- The reader:
  - clears the pool and the vessels;
  - at the end of the bytes, logs the line and returns true;
  - otherwise reads the pool (`read_pool` with `.Vessel_Part`) and refuses a part whose machine is not of a vessel kind;
  - sets each part's frame from the records, refusing an unknown frame or a dead part;
  - reads the vessels and refuses ids out of order or naming no frame.
- `rebuild_entity_cells` then occupies the parts' held cells.
- The tests that cut a save's tail (`machine_wear_test.odin`, `field_trees_test.odin`, `simulation_arrival_test.odin`, `world_field_water_body_test.odin`) add `write_vessel_tables` to the table they cut, after `write_water_body_table`.

### Files and procedures

New, simulation cluster: `tools/code_graph.py` gains the prefix `vessel` in `PREFIX_CLUSTERS["simulation"]`.

`src/machine_part_slots.odin`:
- `MAXIMUM_PART_SLOTS :: 8`, `Part_Slot_Side :: enum u8 {Inside, Outside, Underneath}` and its names, `Part_Slot_Definition :: struct {side: string, from, to: Machine_Cell_Definition}`, `Part_Slot :: struct {box: Cell_Box, side: Part_Slot_Side}`.
- `validate_part_slots :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string`: the rules above. Called by `validate_machine_definition`.
- `part_slot_box_fits_side :: proc(box: Cell_Box, footprint: [3]i32, side: Part_Slot_Side) -> bool`: the side rule, pure.
- `resolve_part_slots :: proc(definitions: []Part_Slot_Definition) -> (slots: [MAXIMUM_PART_SLOTS]Part_Slot, count: int)`. Called by `resolve_machine_registry`.
- `cell_in_inside_slot :: proc(machine: Machine, cell: [3]i32) -> bool`: for `machine_held_cells`.
- `placed_part_slot_box :: proc(common: Entity_Common, machine: Machine, slot: Part_Slot) -> (low, high: World_Coordinate)`: both corners through `rotate_footprint_cell` (affine, so it holds outside the footprint), min and max, plus the origin.

`src/machine_ports.odin`:
- `MAXIMUM_MACHINE_PORTS :: 4`, `MAXIMUM_PORT_CAPACITY :: 1_000_000_000`, `Machine_Port_Kind :: enum u8 {Power, Fluid}` and its names, `Machine_Port_Definition :: struct {id, kind: string, cell: Machine_Cell_Definition, face: string, capacity_watts, capacity_litres_per_second: int}`, `Machine_Port :: struct {id: string, kind: Machine_Port_Kind, cell: [3]i32, face: Direction, capacity: i64}`.
- `validate_machine_ports :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string` and `resolve_machine_ports :: proc(definitions: []Machine_Port_Definition) -> (ports: [MAXIMUM_MACHINE_PORTS]Machine_Port, count: int)`. Called beside the slot procedures.
- (B) `machine_port_is_linked :: proc(entities: ^Entities, owner: Entity_Handle, port: int) -> bool`: the seam, `false`, with its comment naming 0355 and 0356.

`src/vessel_part_registry.odin`:
- `VESSEL_PARTS_FILE_NAME`, the bounds, `Vessel_Part_Role :: enum u8 {Structure, Equipment}` and its names.
- `Vessel_Slot_Size_Definition`, `Vessel_Part_Definition`, `Vessel_Parts_File :: struct {slot_sizes: []Vessel_Slot_Size_Definition, parts: []Vessel_Part_Definition}`.
- `Vessel_Slot_Size :: struct {id, name_key: string, cells: [3]i32}` (width, height, depth).
- `Vessel_Part_Record :: struct {machine: Machine_Id, role: Vessel_Part_Role, line: int, tier: u8, size: int, mass_kilograms, supplies_watts, draws_watts, stores_watt_hours, stores_litres: i64, connector: bool}`. `size` is -1 for structure.
- `Vessel_Part_Registry :: struct {slot_sizes: []Vessel_Slot_Size, lines: []string, parts: []Vessel_Part_Record, part_of_machine: []i32}`. `part_of_machine` is indexed by `Machine_Id`, -1 for none.
- `parse_vessel_parts_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (file: Vessel_Parts_File, problem: string)`: the strict parse, with `missing_struct_key` for the sizes and the five required part keys.
- `resolve_vessel_part_registry :: proc(file: Vessel_Parts_File, machines: Machine_Registry, allocator := context.allocator) -> (registry: Vessel_Part_Registry, problem: string)`: every rule of the Data section.
- `load_vessel_part_registry :: proc(data_directory: string, machines: Machine_Registry, allocator := context.allocator) -> (registry: Vessel_Part_Registry, ok: bool)`: through `read_logged_data_file`, so the edits overlay and its fallback apply.
- `vessel_slot_size_of :: proc(registry: Vessel_Part_Registry, cells: [3]i32) -> int`: -1 for none.
- `vessel_part_record :: proc(registry: Vessel_Part_Registry, machine: Machine_Id) -> (record: Vessel_Part_Record, found: bool)`.

`src/vessel.odin`:
- The two structs.
- `vessel_index :: proc(entities: ^Entities, frame: Frame_Id) -> int`: binary search, -1 for none.
- `start_vessel :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, hit: World_Position, heading: [3]i64, pitch_millimetres: int, rotation: u8) -> (handle: Entity_Handle, frame: Frame_Id)`: the frame, the record appended (new ids rise, so the order holds), the part added.
- `remove_vessel_record :: proc(entities: ^Entities, frame: Frame_Id)`: from `release_empty_frame` after `remove_frame`.
- `part_slot_box_is_free :: proc(entities: ^Entities, frame: Frame_Id, low, high: World_Coordinate) -> bool`.
- `part_slot_filler :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, low, high: World_Coordinate) -> Entity_Handle`.
- `vessel_slot_offered :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, low, high: World_Coordinate, excluded: Entity_Handle) -> bool`: some other structure part on the frame has a slot with this placed box.
- `vessel_structure_components :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, excluded: Entity_Handle) -> (labels: map[Entity_Handle]int, count: int)`: union find over the structure parts whose held cells touch face to face (the six neighbours through the occupant index), in the temp allocator.
- `vessel_part_removal_refusal :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle) -> Field_Edit_Refusal`: decision 8.
- `vessel_control_unit_count :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> int`.
- `write_vessel_tables :: proc(bytes: ^[dynamic]byte, entities: ^Entities)` and `read_vessel_tables :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool`.
- (B) `Vessel_Figures :: struct {structure_parts, equipment_parts: int, mass_kilograms, supply_watts, draw_watts, storage_watt_hours, storage_litres: i64, free_slots: [MAXIMUM_SLOT_SIZES]int}` and `vessel_figures :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id) -> Vessel_Figures`. The free slots count each placed box once.
- (B) `Vessel_Unhooked_Part :: struct {machine: Machine_Id, kinds: bit_set[Machine_Port_Kind]}` and `vessel_unhooked_parts :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id) -> []Vessel_Unhooked_Part`: pool order, in the temp allocator.

`src/vessel_placement.odin`:
- `Vessel_Placement_Kind :: enum u8 {None, New_Vessel, Structure, Equipment, Swap}`.
- `Vessel_Placement :: struct {kind: Vessel_Placement_Kind, machine: Machine_Id, rotation: u8, frame: Frame_Id, origin: World_Coordinate, replaced: Entity_Handle, hit: World_Position, heading: [3]i64}`.
- `field_vessel_placement :: proc(entities: ^Entities, content: Simulation_Content, player: Field_Player) -> (placement: Vessel_Placement, refusal: Field_Edit_Refusal)`: decision 5, on `player.held_machine`.
- `structure_face_origin :: proc(aimed_origin: World_Coordinate, aimed_size: [3]i32, adjacent: World_Coordinate, normal_axis: int, normal_sign: i32, held_size: [3]i32) -> World_Coordinate`: decision 6, pure.
- `aim_vessel_slot :: proc(entities: ^Entities, content: Simulation_Content, player: Field_Player, size: int) -> (frame: Frame_Id, low: World_Coordinate, found: bool)`:
  - looks at the structure parts on the vessel frames within the reach plus `MAXIMUM_FOOTPRINT_SIZE` pitches (`frame_within_reach`), and their free slots of the size;
  - turns the eye and the look into the frame's axes (`frame_local_position`, `frame_local_direction`) and the box into position units;
  - keeps the nearest `ray_box_entry` below `field_aim_limit`, the first in pool and slot order on a tie.
- `vessel_placement_cells :: proc(entities: ^Entities, content: Simulation_Content, placement: Vessel_Placement) -> (frame: Frame, cells: []World_Coordinate, found: bool)`: the held cells. For a new vessel these are on the frame it would make; for a swap they are the replaced part's.
- `vessel_placement_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Vessel_Placement) -> Field_Edit_Refusal`, which every kind passes through:
  - All kinds: `Nothing_Held`; then, except a new vessel, `Unknown_Frame` when the frame is gone or is no vessel's.
  - A new vessel: `Frame_Cell_Taken` through `new_frame_cells_meet_a_frame`.
  - Structure: `Frame_Cell_Taken`, then `Needs_Vessel_Structure`.
  - Equipment: `No_Free_Slot` unless `vessel_slot_offered` and the box free, then `One_Control_Unit`.
  - A swap (B): `Not_An_Upgrade`, then `Inventory_Full`.
  - Every kind but a swap then checks `Tree_In_The_Way` (`placement_cells_meet_a_trunk`) and `Would_Bury_Player` (`field_placement_buries_a_player` per held cell).
- `queue_vessel_placement :: proc(state: ^Simulation_State, content: Simulation_Content, index: int)`: on Place's press with the `.Vessel_Part` tool. Either the refusal goes to `player.field_refusal`, or a `Field_Placement{kind = .Vessel_Part, vessel = ...}` is queued. Called from `queue_field_player_edit`.
- `drain_vessel_placement :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, placement: Vessel_Placement)`: the refusal, or `apply_vessel_placement` with one item taken and `record_placed`.
- (B) `swap_vessel_part :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, machine: Machine_Id)`: `unregister_frame_body`, set the machine, `occupy_entity_cells`.
- (B) `swap_returns_fit :: proc(inventory: Inventory, items: Item_Registry, held, returned: Item_Id) -> bool`: on a copy.

`src/world_frame_raycast.odin`: `ray_box_entry :: proc(origin, direction, low, high: [3]i64) -> (distance: i64, hit: bool)`:
- A slab test in position units with the direction in `UNIT_VECTOR_ONE`, `(bound - origin) * UNIT_VECTOR_ONE / direction` per axis.
- No hit when it misses, when the box is behind, or when the origin is inside the box.

`src/ui_vessel.odin` (B, ui cluster):
- `VESSEL_PANEL_AREA_WIDTH :: 480`, `VESSEL_PANEL_FIGURE_ROWS :: 5`, `VESSEL_PANEL_UNHOOKED_ROWS :: 5`.
- `vessel_panel_area_size :: proc() -> [2]f32`: the width by (5 + 1 + 5 + 1) × `UI_LINE_HEIGHT`.
- `vessel_figure_lines :: proc(figures: Vessel_Figures, registry: Vessel_Part_Registry, parts_replaced: u32) -> [VESSEL_PANEL_FIGURE_ROWS]string`, one line each:
  - "Mass: 1.2 t";
  - "Supply: 2.0 kW  Draw: 0.1 kW";
  - "Storage: 2.0 kWh  1000 L";
  - "Free slots: 4 small, 1 medium, 0 large";
  - "Parts replaced: 2".
- `vessel_unhooked_lines :: proc(unhooked: []Vessel_Unhooked_Part, machines: Machine_Registry, limit: int) -> []string`:
  - the heading;
  - at most `limit` lines of "<part name>: power, fluid", in pool order;
  - then "and N more".
  - With none, the one line `vessel_panel_hooked_up`.
- `vessel_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, handle: Entity_Handle, screen_context: Screen_Context)`: every line through `draw_text_fitted`. Nothing is focusable, so focus stays on the inventory's slots and Back closes, as on the oxygen generator's panel.

Changed:

- `machine.odin`:
  - the two kinds and their names, with `machine_kind_is_vessel :: proc(kind: Machine_Kind) -> bool`;
  - `Machine_Definition` gains `part_slots` and `ports`, `Machine` gains `part_slots, part_slot_count, ports, port_count`;
  - their cases in `validate_machine_kind_fields` (an item and a valid `color`);
  - the two resolvers in `resolve_machine_registry`.
- `entity.odin`:
  - `Entity_Kind.Vessel_Part` appended, and `Entities.vessel_parts` and `vessels`;
  - `entity_common`, `destroy_entities`, `add_entity` (both kinds into the pool) and `remove_entity`;
  - `machine_held_cells` also skips `cell_in_inside_slot`, its early return guarded by no inside slot;
  - (B) `entity_has_panel` is true for a `vessel_control_unit` on a frame with `vessel_index >= 0`.
- `save_state.odin`:
  - `entity_pool_length` and `entity_common_at`;
  - `write_vessel_tables` after `write_water_body_table`;
  - `read_vessel_tables` after `read_water_body_table`.
- `entity_frames.odin`:
  - `Frame_Placement_Refusal.Vessel_Frame` in `frame_placement_refusal`, mapped to `Vessel_Parts_Only` by `field_placement_refusal` and `foundation_block_refusal`;
  - `entity_frame_records` skips the kind;
  - `Field_Placement_Kind.Vessel_Part` and `Field_Placement.vessel`, routed by `drain_field_placements` to `drain_vessel_placement`;
  - `field_entity_is_held_up` is false for a vessel part, and `advance_field_pick_up` and `drain_field_pick_up` set `vessel_part_removal_refusal`'s refusal.
- `developer.odin`: `place_on_frame_for_developer`'s switch gains `.Vessel_Frame` ("only vessel parts go on a vessel").
- `belt_run.odin`: `release_empty_frame` calls `remove_vessel_record`.
- `machine_wear.odin`: `machine_wear_records` skips the kind.
- `field_mining.odin`:
  - the seven refusals appended, with `Not_An_Upgrade` in B, and their keys in `field_refusal_keys`;
  - `queue_field_player_edit` calls `queue_vessel_placement` on Place's press with the `.Vessel_Part` tool.
- `player_field.odin`: `Field_Held_Tool.Vessel_Part` appended.
- `simulation_field.odin`: `field_tool_for_item` returns `.Vessel_Part` for both kinds, and `update_field_held_tool` turns `placement_rotation` for it as for `.Machine`.
- `hud.odin`: `field_held_tool_turns` is true for `.Vessel_Part`.
- `player_command.odin`: `machine_takes_placement_command` is false for the vessel kinds.
- `entity_placement.odin`: `selected_placed_machine` returns `NO_MACHINE` for the vessel kinds, the block world.
- `simulation_world.odin`: `Simulation_Content.vessel_parts`.
- `data_reload.odin`: loads it after the machines.
- `data_watch.odin`: adds `VESSEL_PARTS_FILE_NAME` to the content files.
- `render_entities.odin`: a loop over `vessel_parts` drawing `draw_machine_model`, else a cube per held cell (`entity_held_cells`) in the record's colour under the frame matrix, after `model_frame_draws_entity`.
- `loop_field_session.odin`: `draw_field_ghosts` draws the vessel placement first when the tool is `.Vessel_Part`. It uses `draw_frame_ghost_model` when the machine has a model, else `draw_frame_ghost` per cell, tinted by `vessel_placement_refusal`. With no placement it draws nothing.
- (B) `ui_machine.odin`: `machine_area_width` and `machine_area_height` with `vessel_panel_area_size` for the control unit and none for the vessel part, and `machine_slot_region` with `case .Vessel_Part`.
- (B) `ui_format.odin`: `format_mass :: proc(kilograms: i64) -> string` (kg below 1000, t with one decimal) and `format_energy :: proc(watt_hours: i64) -> string` (kWh, MWh from 1000 kWh, one decimal).
- Tests:
  - `machine_test.odin`'s `make_test_content` loads `vessel_parts` from the shipped file (`make_test_vessel_parts(machines)`);
  - `ui_audit_test.odin` gains B's case.
- `doc/code_map.md`: the new files under simulation and ui, with the "Reaches into" counts the checks report (content to simulation grows by the load call).

### Tests

A:

- `test_shipped_vessel_parts_resolve`:
  - every vessel machine has one record and the first set's ids resolve;
  - the ring line has tiers 1 and 2;
  - the size names are in the string table.
- `test_malformed_vessel_parts_are_refused`, table driven, each with its message:
  - an unknown key, a wrong type, a missing required key;
  - an unknown or non-vessel machine, a duplicate record;
  - equipment off every size, structure with a function key or a port, a slot box off every size, equipment with slots;
  - a line mixing roles, kinds, footprints or slots;
  - tier 0 or 16, mass 0 or 1,000,001;
  - a non-square or duplicate size, five sizes.
- `test_malformed_part_slots_and_ports_are_refused`, table driven on `validate_machine_definition`:
  - an inside box leaving the footprint, an outside box not touching, an underneath box with `to.y` of 0, overlapping boxes, nine slots;
  - slots on a furnace;
  - a port off the surface, a duplicate id, two ports on one face, an unknown kind, a power port with litres, ports on a furnace.
- `test_a_ring_holds_its_walls_and_its_slots_turn_with_it`:
  - at each rotation the ring holds 24 cells, none in the interior;
  - turned once, the -x outside box lands where the -z one was.
- `test_structure_face_origin_aligns_or_follows_the_aimed_cell`:
  - a ring on a ring's top is aligned;
  - a truss on a ring's side follows the aimed cell, clamped at each edge;
  - a deck plate on a truss is centred, being the wider;
  - a normal of each sign starts at the adjacent layer.
- `test_ray_box_entry`: an entry along a diagonal, a miss, a box behind, the origin inside, an axis parallel ray inside and outside the slab.
- `test_a_structure_piece_aimed_at_the_ground_starts_a_vessel`: through Place on the flat site; one frame, one record, the ring at `field_footprint_origin`, one ring item spent.
- `test_structure_joins_the_aimed_face_and_must_touch_it`: a second ring aimed at the first one's top stacks aligned; refusals for a ring touching through its hollow, a taken cell and an aim at a foundation, as `Needs_Vessel_Structure`, `Frame_Cell_Taken` and `Needs_Vessel_Structure`.
- `test_equipment_goes_into_the_aimed_free_slot`:
  - a battery aimed beside the ring's wall takes the outside slot, and a tank aimed into the hollow the inside slot;
  - a second battery aimed at the filled slot's battery finds no slot (`No_Free_Slot`, nothing placed);
  - a deck plate's top slot is skipped while the player stands in it;
  - aimed at the sky, `No_Free_Slot`.
- `test_a_vessel_takes_vessel_parts_only_and_one_control_unit`:
  - a furnace and a foundation aimed at a ring are refused `Vessel_Parts_Only`;
  - a second control unit is refused `One_Control_Unit`;
  - `frame_placement_refusal` returns `Vessel_Frame` for a belt pole on the vessel's frame.
- `test_removal_keeps_equipment_on_a_slot_and_the_vessel_whole`:
  - a ring hosting a battery refuses `Holds_Equipment`, unless a second part offers the same box;
  - the middle of three trusses in a row refuses `Holds_The_Vessel_Together`, while an end truss comes off;
  - the last part takes the frame and the record with it.
- `test_a_vessel_round_trips_a_save_and_an_older_save_loads_without_vessels`:
  - a vessel of every part saves and loads to an equal hash, its frames and record restored and the ring's hollow free;
  - cut before the table, it loads with no vessels and the log line;
  - mark it `// slow` when `build/test_times.tsv` says so.
- `test_two_sessions_building_a_vessel_hash_the_same`: the same Place inputs give one hash, and changing a part's machine changes it.

B:

- `test_a_better_part_swaps_in_place`:
  - a steel ring over an iron ring keeps its handle, its tank and its batteries;
  - the iron ring comes back, `parts_replaced` is 1, and a nickel battery over a lead one does the same;
  - a lead battery aimed at a nickel one takes a free slot instead.
- `test_a_swap_is_refused_without_room_or_when_not_an_upgrade`: `Inventory_Full` with a full inventory and more than one held; with one held it goes through; `Not_An_Upgrade` when the aimed part changed in the same tick.
- `test_vessel_figures_sum_the_parts_and_list_what_is_unhooked`: the first set's sums, the free slots per size each counted once, and every part with ports listed with its kinds.
- `test_vessel_panel_lines_cap_the_unhooked_list`: seven parts give the heading, five lines and "and 2 more"; none gives the hooked up line.
- The audit case `vessel panel`, at every size: a ring with a tank, a control unit, a connector and enough batteries on a deck to pass the cap, the control unit's panel open.

### Docs

- `doc/vessels.md` (new, the topic's owner):
  - the model;
  - the data keys of both files;
  - slots, sizes and sides;
  - Place's priorities, the face snap and the slot aim;
  - removal;
  - the record and the save;
  - the swap, the figures and the panel (B);
  - what 0355, 0356, 0357 and the decoupler add.
- `doc/README.md`: its index line.
- `DESIGN.md` (Building): the crawler bullet becomes the vessel system. Every vessel is built from structure that brings generic slots, equipment in the slots, every cable and pipe run by hand, figures from the parts, and any part swapped in place. The structure's slots replace "a deck that is a foundation frame" and "no prebaked slots".
- `doc/content.md`: a "Vessel parts" section with the first set's tables, and the machines' `part_slots` and `ports` keys.
- `doc/input.md`: Bindings, Place and Rotate with a vessel part held; the panel on Open_Aimed (B).
- `doc/architecture.md`:
  - Frames: vessel frames take vessel parts only;
  - Simulation: the pool, the records, the placement;
  - Save format: the table and its log line.
- `doc/code_map.md`: as above.

### Hand-back check

- **Parsed numbers:** every data number above has its bounds and a refusing test.
- **Old saves:** a changed layout loads an old save with one log line (`read_vessel_tables`, the round trip test).
- **Bounded lists:** the panel's list is capped at five lines plus "and N more", every line fitted, at every audit size (B).
- **Audit cases:** none is made obsolete; one is added (B).
- **Start-up loads:** the file reads through `read_logged_data_file`, so a broken overlay copy falls back as every table does.
- **Shared budgets:** none is joined. The vessel kinds are not `machine_touches_power`; 0355 makes them participants.
- **Test state:** the tests use the flat site and in-memory saves.

### Questions to the main agent

1. **The split.** This is more than one implementer should carry through review rounds. Proposed: 0361 keeps A, which lands a vessel built, taken apart, saved and drawn as boxes. A new item takes B (swap, figures, panel), which lands upgrades and the panel listing every port as not hooked up. B and 0355 may land in either order. The Verify's "hooked up" waits for 0355, and its panel capture with one connection missing too.
2. **The swap shadows the stack.** Per the Controls, a higher tier piece aimed at a lower one of its line swaps it, so a steel ring cannot be stacked on an iron ring by aiming at it. It can be by aiming at another piece. Accept, or a Controls change?
3. **A vessel started on a foundation pad** (the rocket on its pad) is left out: structure aimed at a non-vessel frame is refused. The rocket item adds a new frame aligned to the hit frame's top face. Include it now?
4. **The connectivity refusal** (`Holds_The_Vessel_Together`) adds to the Controls' removal rule. Accept?
5. **The ready rule before nets.** A part is hooked up when one port of each kind it has is linked. Should 0355 sharpen it to "on the control unit's net"?
6. **"The rule that a connected vessel does not move"** (Change) cannot be built or tested while nothing moves and nothing links. It moves to 0357 as `vessel_is_tied`. Agree?

### Decisions (main agent, 2026-11-11)

1. Question 1: split accepted. This item is part A (data, kinds, slots, ports, the pool, the record, the save, placement, removal, the ghost and the box rendering). Part B (the swap, the figures, the link seam, the panel) is 0365, implemented from this specification.
2. Question 2: accepted. A better piece aimed at a lesser one of its line swaps it; to stack, aim at another piece.
3. Question 3: left out. A vessel begun on a foundation pad is the rocket stage item's to decide.
4. Question 4: accepted, and it joins the control design: a structure piece is not taken off while it holds equipment or holds the vessel together, with the reason shown.
5. Question 5: a part is hooked up when it is on its vessel's control unit's net. 0355's design was told and provides the query.
6. Question 6: agreed, the rule that a tied vessel does not move is 0357's.
7. Vessel parts only on a vessel's frame, as the user leaned. The draft's both-way parts wait for the user.
8. Order: A, then 0365 and 0355 in either order, 0356, 0357, the rocket stage. A starts when a slot frees after 0342's landing, unless the user overturns one of the draft's six proposals first: the specification says what each reversal costs.
9. The control unit draws 60 W, not 50 W (0355's design: 50 W floors to no joule a tick), and `MAXIMUM_MACHINE_PORTS` is 8 (0355, decision 4).
