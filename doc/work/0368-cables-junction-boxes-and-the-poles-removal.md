# 0368: Cables, junction boxes and the poles' removal

Status: verified (2026-11-13)

Part B of 0355's specification (`doc/work/done/0355-cables-and-the-power-netlist.md`), split off at its approval: the cable table and the ports, the run under the lockstep, the junction box (4 ports) and the cabinet (8), the poles deleted from the content and from old saves, the draw, and the quests, kits, technologies, recipes, blueprints, strings and models that follow. The specification below is this item's own, brought up to `main` on 2026-11-13; an implementer never opens 0355.

## Goal

Every power connection is a cable run by hand, and the poles are gone.

## Controls

No new binding. The cable is a hotbar item, and running one is a mode the player enters and leaves with Place and Mine (0355's control design, main agent, 2026-11-11, with its refusals):

- **Layer: cable held, no run.** Place aimed at a thing with a free power port (a machine, a generator, a junction box or cabinet, a power switch, a vessel part with a power port) takes the cable's first end onto that port and begins the run. The aimed thing is the target, not the port: of its free power ports the one whose point is nearest the aimed face's centre is taken. Aimed at anything else Place does nothing and tells `No_Free_Port`. Mine keeps its meanings (it fells, picks up, takes up a cable).
- **Mode: a run carried.** The cable is drawn from its port to the player's hand, and the tool line shows the metres left of the span, or past it. Every movement control is unchanged and the player is never held back by the cable. Place aimed at a second thing with a free power port ends the run there and takes the cable's metres from the inventory. Refused, the run stays and the reason is told: no free port, the first thing again, past the span, not enough cable, a vessel end that is not its connector. Mine pressed takes the run back and ends the mode; selecting another hotbar slot ends it too, and the first end's port gone or taken ends it with its reason. Mine digs, fells and picks up nothing during a run.
- **Any tool, no run: Mine held on a cable** takes it up into the inventory, the hold that picks up an aimed machine (`PICK_UP_SECONDS`). Refused `Inventory_Full` when its metres do not fit.
- Rotate_Building, Interact and Open_Inventory keep their meanings with a cable held and during a run. A machine's panel shows its draw; a junction box's panel its netlist.
- A cable's capacity is its item (light, heavy and trunk are three items), never a setting cycled on a control. The junction box and the cabinet are placed as any machine.
- Touch reaches all of it through Place's and Mine's gamepad bindings (0115). With a cable held a tap on any target presses Place's control, not the open panel's, so a run begins and ends by tap (decision 10); it is still a gamepad press routed by context (0194).
- Back does nothing to a run (decision 11): its control carries Sneak.
- A cable may close a loop (0377): until 0377 the loop's chord carries nothing.

## Change

- Data: three cable items, a power port on every electric machine, generator and power switch, the junction box and cabinet, `deleted_ids` for the poles.
- The power simulation on the cables: one node per thing with a power port, one edge per cable, the solve of `src/netlist/` (0355 A, 0373) every tick over the whole world.
- The run, the take up and the developer `cable` command under the lockstep; the cable table in the save and the state hash.
- The poles leave the content and old saves with one log line; the quests, kits, technologies, recipes, blueprints, strings and models that name them follow.
- The cable drawn between its two ends and the carried run to the hand.
- After 0355, 0373 (the solve's charge for a poorer child), 0361 and 0362.

## Verify

- The checks and the suite, with a save holding poles that loads without them and one log line.
- Captures of a hand run factory of a handful of machines, sent to the user (Specification, Captures).

## Specification (design, 2026-11-13)

### Steps

Each step lands something playable; steps 2 and 3 touch different clusters and may run in parallel after step 1.

1. **This item.** Everything below except the parts marked step 2 and step 3: the cables are drawn as lines along their sag (the flat batch), the carried run as a line.
2. **Batteries and the control unit on the netlist** (a new item, simulation only): Batteries and the control unit, below.
3. **The cable's look** (a new item, presentation only): The draw, step 3, below, and the profile view.

Until step 2 a vessel part with a power port is a node that only passes power on.

### Decisions

1. **The netlist is the cables' graph.** A node is a thing's terminal: one node per live entity whose machine has a power port, its ports joined inside it, except a power switch that is off, which is two nodes (port 0, port 1). One edge per cable, between the nodes of its two port ends; parallel cables between two nodes bundle (`build_topology`), their capacities adding. Nodes are numbered in pool order: `poles` (junction boxes and switches), then the participants' pools in today's collection order (inserters, drills, fluid machines, lamps, assemblers, labs, core sample drills, launch pads), then `vessel_parts`, so leftover joules go in today's order.
2. **Loops are accepted** (0377: "0368 and 0374: the loop refusal and its string go"). A cable that closes a loop is laid; `build_topology` makes one bundled edge of the loop a chord that carries nothing until 0377. Which edge is the chord follows the sorted node order, so laying a cable can idle an older cable of the loop while every node stays joined. Named in `doc/fluids.md`.
3. **The netlist never sees a position.** The topology comes from the cable table and the switches. A cable's span is measured from its ends' port points each time it is laid, aimed at or drawn; only its whole metres are stored.
4. **Cables are a table** (`Entities.cables`), not fields on the pools: one symmetric record per cable, a derived map from port end to cable for lookups, never iterated.
5. **Capacities are watts in the topology.** `rebuild_electric_networks` has the machines but neither the items nor the tick rate, so each cable's watts (the least of its item's and its two ports') are derived at `add_cable` and at load into the table, the topology's edges carry watts, and each tick converts the per node capacity to whole joules a tick (floored after bundling: a limit, no energy lost).
6. **Removing an end returns the cable.** `entity_pickup_stacks` holds the metres of every cable on the entity, so the field refuses a pick up `Inventory_Full` when they do not fit and the block world spills them. A developer `remove` drops them.
7. **The poles leave through a data key.** `deleted_ids` on `data/machines.sjson`; a placed entity of a deleted id is deleted at load instead of refusing the file, with one log line. Nothing softens it, by the user's "saves with power poles just delete the poles": an old factory's machines load with no cable and stay unpowered until cables are run; small pole, big pole and substation items vanish as any gone item does; no refund. `doc/fluids.md` and the log line say so.
8. **A netlist with a cable is a network.** `Electric_Networks.networks` holds one entry per tree of two or more nodes (each holds a cable), in tree order; the overview, the brownout warning and the statistics read only those. A consumer is unpowered when its tree has no generator and no store (a consumer with no cable is a tree alone): the unpowered statistic's new meaning, named in the log at the landing.
9. **Under the lockstep nothing new travels** but the developer command: the run's begin, end and take back are player state set in the player's tick from its input frame; the cable laid and the cable taken up are `Field_Placement`s drained in player order and checked again there. The developer `cable` command is a `Developer_Request` as `place` is.
10. **The seams 0355 offered 0365 and 0357** (`machine_port_is_linked`, `power_port_net`, `power_ports_share_net`, `frame_is_tied_by_cable`, `cables_on_lost_ports`, `remove_cables_on_lost_ports`) are left to those items: neither is queued and no stub exists on `main`. Each is a few lines over `power_port_node`, `topology.tree_of` and the cable table (question 6).

### Data

`data/items.sjson`: `Item_Definition` and `Item` gain `cable_kilowatts` (1 to 1,000,000), `cable_span_metres` (1 to 100, at most the stack size), `cable_thickness_millimetres` (5 to 100) and `cable_color` (three channels 0 to 255, not all zero); all four or none, else the load refuses the file naming the item. One item is one metre. The pole items go.

| item | kW | span m | mm | color | stack | price | recipe (0.5 s) | unlock |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `light_cable` | 300 | 20 | 12 | [52, 52, 56] | 200 | 1 | copper_wire 1 → 2 | `start` |
| `heavy_cable` | 3,000 | 30 | 24 | [176, 120, 36] | 200 | 3 | copper_wire 4, iron_plate 1 → 2 | `electric_mining` |
| `trunk_cable` | 24,000 | 50 | 40 | [140, 44, 36] | 200 | 8 | copper_wire 8, steel 1 → 2 | `electric_grid` |
| `junction_box` | | | | | 100 | 6 | iron_plate 2, copper_wire 4 → 1 | `start` |
| `junction_cabinet` | | | | | 100 | 30 | steel 2, copper_wire 8, electronic_circuit 1 → 1 | `electric_grid` |

All category `machine`. Recipes `made_in = ["hand", "assembler"]`, `category = "power"`, `tags = ["electric"]`; the researched ones `channel = "research"` with their `technology`. The kW are 5,000, 50,000 and 400,000 J a tick at 60 Hz. The boxes stack 100, the class of machines placed by the dozen (`doc/content.md`, Items; 0355 had 50). The cabinet's recipe and price are tuning.

`data/recipes.sjson`: `small_pole`, `big_pole`, `substation` go; the five above are added in the Power block.

`data/technologies.sjson`: `electric_mining` unlocks `["electric_mining_drill", "power_switch", "heavy_cable"]`; `electric_grid` unlocks `["trunk_cable", "junction_cabinet"]`; the header comment's "the big pole and substation" becomes "the trunk cable and the junction cabinet".

`data/machines.sjson`:
- Top level `deleted_ids = ["small_pole", "big_pole", "substation"]`; `Machines_File` and `Machine_Registry` gain `deleted_ids: []string`. Each must be neither a current machine id nor a former id of one, nor listed twice (`content_former_id_problem` reports it, naming `machines.sjson`).
- The three pole records go. `supply_volume` and `wire_reach` leave `Machine_Definition`, `Machine`, the power switch's record and the header comment. Kind `pole` becomes `junction_box` (`Machine_Kind.Pole` to `.Junction_Box`; the compiler names every site). The entity pool keeps its names (`Pole`, `poles`, `Entity_Kind.Pole`), since the save matches pools by position and a handle's kind by name; a comment on `Pole` says it holds junction boxes, cabinets and power switches.
- Every record with `electric_power_kilowatts` or `electric_output_kilowatts` (27) gets one port, first in its `ports`: `{id = "power", kind = "power", cell = {...}, face = ..., capacity_watts = rating × 1000}`, cell and face from this table (each on the footprint's surface, none on a cell and face an explicit `fluid_ports` entry uses, an inserter's on neither its pickup face −x nor its drop face +x):

| records | cell | face |
| --- | --- | --- |
| inserter, filter_inserter, fast_inserter, long_inserter | (0, 0, 0) | negative_z |
| offshore_pump, pump, tar_pit_pump | (1, 0, 0) | positive_z |
| electric_mining_drill, refinery, cracking_unit, chemical_plant, flare_stack, lamp, core_sample_drill | (0, 0, 0) | negative_x |
| combustion_generator, fuel_generator, hydro_turbine, crusher, recycler, washer, wood_gasifier, assembler_1, lab, electrolyser | (0, 0, 1) | negative_x |
| bore_drill, steam_engine | (0, 0, 2) | negative_x |
| launch_pad | (0, 0, 4) | negative_x |

- `junction_box`: name keys `machine_junction_box`, `describe_machine_junction_box`, item `junction_box`, kind `junction_box`, `stands_on_ground = true`, footprint 1×1×1, `color = [96, 98, 92]`, no model; ports `a` negative_x, `b` positive_x, `c` negative_z, `d` positive_z, all at cell (0, 0, 0), each `capacity_watts = 24000000`.
- `junction_cabinet`: kind `junction_box` as the box, with `machine_junction_cabinet`, `describe_machine_junction_cabinet`, item `junction_cabinet`, footprint 1×1×2, `color = [84, 88, 96]`; ports `a` to `d` as the box's at cell (0, 0, 0) and `e` to `h` the same faces at cell (0, 1, 0).
- `power_switch`: ports `a` negative_x and `b` positive_x at (0, 0, 0), 24,000,000 W each.
- A record's ports are saved by index, so a record's `ports` is appended to and never reordered (said in the header comment and `doc/content.md`).

Validation (`validate_machine_ports`, `validate_power_machine_definition`, the kind now passed in):
- Outside the vessel kinds a port is a power port; a fluid port there stays refused until 0356.
- A record with an electric rating has exactly one power port, at index 0, with `capacity_watts` at least its rating × 1000.
- A `junction_box` has 2 to `MAXIMUM_MACHINE_PORTS` power ports and a valid `color` (`foundation_color_is_valid`); a `power_switch` is 1×1×1 with exactly 2.
- No other kind but the vessel kinds lists a port.
- `machine_touches_power` becomes "the machine has a power port".

### State, save and hash

`src/cable.odin` (new, simulation; `tools/code_graph.py` gains the prefix `cable` in `PREFIX_CLUSTERS["simulation"]`):
- `Port_End :: struct {entity: Entity_Handle, port: u8}`.
- `Cable :: struct {ends: [2]Port_End, item: Item_Id, metres: u16}`: saved.
- `Cable_Table :: struct {cables: [dynamic]Cable, watts: [dynamic]i64, port_cable: map[Port_End]int}` as `Entities.cables`. `watts` (decision 5) and `port_cable` are derived: kept by `add_cable` and `remove_cable`, rebuilt by `settle_cables`; `destroy_entities` frees all three.

`Field_Player` gains `cable_run: bool`, `cable_start: Port_End`, `cable_slot: u8`, `cable_take_up: Port_End`, `cable_take_up_ticks: u32`. `Statistics.cables_run: u64`; `Hint_Counter.Cables_Run` appended last with the name `cables_run`, read in `quest_runtime.odin` beside `.Unpowered_Machine_Ticks`. Absent in an old save, each reads zero.

The save (`save_state.odin`):
- `write_cable_table :: proc(bytes: ^[dynamic]byte, entities: ^Entities)`: `write_list` of `cables`. Written only when the world has a cable, so a world without one keeps its bytes and its state hash.
- `write_simulation_state`: `write_later_tables(..., state.field.enabled || has_cables)`; a field world writes the cable table after `write_vessel_tables`; a block world with a cable appends `BLOCK_WORLD_CABLES_MARK :: u32(0)` and then the table. 0355 placed the table last in both, which a block world's reader would take for the field tables: `read_simulation_state` detects a field world by bytes left after the later tables, and a version step is not possible (`header_problem` refuses any other version).
- `read_simulation_state`: after `read_later_tables`, with bytes left, a copy of the reader reads the next u32: `BLOCK_WORLD_CABLES_MARK` is consumed and `read_cable_table` follows; anything else is the field tables (their first u32 is the spacing, 333 to 1000), then after `read_vessel_tables` the cable table.
- `read_cable_table :: proc(reader: ^Byte_Reader, entities: ^Entities, content: Simulation_Content) -> bool`: clears the table, reads it while bytes are left (else empty), then `settle_cables`.
- `settle_cables :: proc(entities: ^Entities, content: Simulation_Content) -> (dropped: int, ok: bool)`, after the pools: drops a cable whose item reads as none or has no `cable_kilowatts`, or whose port index is not a power port of its entity's machine, counting them; refuses the file (`reader.problem`) for an end on a dead entity ("the save has a cable whose end is gone") or two cables on one port end ("the save has two cables on one port"). Derives `watts` and `port_cable`. With some dropped, one line: `save: dropped %d cables whose item or port this build no longer has`.
- The state hash and the save snapshot encode through `write_simulation_state` (0382, 0345), so the table is hashed, saved and snapshotted with no further change.

The poles' deletion (`save_remap.odin`):
- `Content_Former_Id` gains `deleted: bool`; `content_former_ids` adds `{former = id, deleted = true}` for each machine `deleted_ids` entry. `make_content_remap` maps a saved id that is a deleted entry to `CONTENT_GONE` and marks `Content_Remap.deleted[table][old_index]` (new, indexed like `saved`).
- `read_content_id`: a deleted id reads as none and skips `note_gone_id`.
- `Content_Remap` gains `deleted_entity_count: int`, `deleted_handles: [dynamic]Entity_Handle` and `deleted_frames: [dynamic]Frame_Id` (temp allocator).
- `settle_gone_machines`: an alive entry whose machine reads none is deleted when `first_gone[.Machines] == ""` (no gone machine id that is not deleted was met): `alive = false`, machine 0, its index appended to `pool.free`, its handle to `deleted_handles`, counted. Otherwise it refuses as today. A save that also names a gone machine that is not deleted refuses as it does today.
- `read_frame_tables` and `read_machine_wear_table` skip a record whose handle is in `deleted_handles`; the frame tables append the skipped record's frame to `deleted_frames`. After `rebuild_loaded_world`, `release_empty_frame` runs on each, so a pole that stood on bare ground (a frame of its own) leaves no empty frame.
- `deleted_machines_line :: proc(remap: Content_Remap) -> string`: "" without deletions, else `save: removed %d placed machines of deleted kinds (%s)`, naming the deleted ids the saved table held. Logged once in `decode_entities` after `renamed_content_line`.

### The model, `src/power_network.odin`

Rewritten around the cables; the hub adapter, `Electric_Node`, `Electric_Wire`, the wires, the supply volumes and the memberships go (`supply_volume_origin`, `make_electric_node`, `doubled_footprint_centre`, `nodes_are_within_reach`, `find_electric_wires`, `assign_electric_networks`, `network_covering_cells`, `append_electric_members`, `assign_electric_memberships`).
- `Electric_Networks` keeps `networks`, `participants`, `allocator` and gains `node_entities: [dynamic]Entity_Handle` (an off switch names its entity twice), `node_of_entity: map[Entity_Handle]u32` (its first node), `topology: netlist.Topology` (in the networks' allocator, freed at each rebuild), `network_of_tree: [dynamic]i32` (-1 for a tree without a cable), `capacity_per_tick: [dynamic]i64`, `inputs: [dynamic]netlist.Node_Input`, `outputs: [dynamic]netlist.Node_Output`, `participant_of_node: [dynamic]i32`.
- `Electric_Network` gains `store_count` (0 until step 2).
- `rebuild_electric_networks :: proc(entities: ^Entities, machines: Machine_Registry)`, unchanged signature: the nodes of decision 1; one `netlist.Edge` per cable between `power_port_node` of its ends with `cables.watts[index]`; `netlist.build_topology`; `network_of_tree` numbering the trees with a cable in tree order; `networks` resized to that count.
- `power_port_node :: proc(networks: ^Electric_Networks, entities: ^Entities, end: Port_End) -> int`: the entity's node, plus one for port 1 of an off switch; -1 for none.
- `entity_network :: proc(networks: ^Electric_Networks, handle: Entity_Handle) -> int`: `network_of_tree[tree_of[node]]` of the entity's first node, -1 without one.
- `collect_electric_participants`: as today; each participant's `node` from `node_of_entity`, `network` from `entity_network`; `participant_of_node` filled.
- `balance_electric_energy :: proc(networks: ^Electric_Networks, tick_rate: int)`: `capacity_per_tick[node] = topology.capacity[node] / tick_rate`; the inputs from the participants (`participant_node_input`, unchanged); `netlist.solve` on a copy of the topology whose `capacity` is `capacity_per_tick`; each participant's `delivered` back (`supplied` for a generator, `delivered` for a consumer). Per network: supply the offers, demand the demands, delivered the consumers' deliveries, satisfaction the lowest level among its consumers with a demand (else `power_satisfaction(supply, 0)`), the counts.
- `apply_electric_balance`: a consumer gets its node's `level` through `deliver_power_satisfaction`, not the network's; a generator as today with its network's demand.
- `record_electric_tick`: unpowered counts the consumers whose `network < 0` or whose network has no generator and no store.
- `tick_electric_networks` passes `tick_context.tick_rate`.
- `power_satisfaction`, `deliver_power_satisfaction`, `participant_power`, `network_is_in_brownout`, `any_network_in_brownout` and `toggle_power_switch` (it rebuilds) stay.
- The lamp keeps `lit = power.satisfaction > LAMP_ON_ABOVE`, now its own node's level.

`src/power_machine.odin`: `make_pole` unchanged; `validate_power_machine_definition` as Data says; `machine_touches_power` as Data says.

### Ports and cables, `src/cable.odin`

- `frame_face_centre :: proc(frame: Frame, cell: World_Coordinate, face: Direction) -> World_Position` (in `world_frame.odin`): `frame_cell_centre` moved half a pitch along the frame axis of the face (`direction_offsets`).
- `placed_machine_port_face :: proc(common: Entity_Common, machine: Machine, port: Machine_Port) -> Cell_Face` (in `machine_ports.odin`): as `placed_port_face` for a fluid port.
- `port_point_on_frame :: proc(frame: Frame, common: Entity_Common, machine: Machine, port: int) -> World_Position`: pure; `frame_face_centre` of the placed port face.
- `power_port_point :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> (point: World_Position, found: bool)`: the end's entity alive, the port a power port, its frame found (`find_frame`); then `port_point_on_frame`.
- `chord_metres :: proc(first, second: World_Position) -> i64`: the distance in whole metres rounded up, at least 1 (`vector_length`, `POSITION_UNITS_PER_METRE`).
- `cable_span_metres :: proc(entities: ^Entities, machines: Machine_Registry, first, second: Port_End) -> i64`: `chord_metres` of the two port points.
- `cable_watts :: proc(content: Simulation_Content, cable: Cable) -> i64`: the least of the item's `cable_kilowatts × 1000` and both ports' capacities.
- `port_end_cable :: proc(table: ^Cable_Table, end: Port_End) -> int`: -1 for none. `port_end_is_free :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> bool`: a live entity's power port with no cable.
- `free_power_port_nearest :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, point: World_Position) -> (port: int, found: bool)`: the free power port whose point is nearest by squared distance, the lowest index on a tie.
- `Cable_Placement :: struct {ends: [2]Port_End, item: Item_Id}`.
- `cable_placement_refusal :: proc(entities: ^Entities, content: Simulation_Content, placement: Cable_Placement, metres_held: i64) -> Field_Edit_Refusal`, in order: the first end not free: `Cable_End_Gone`; the second not free: `No_Free_Port`; one entity at both ends: `Same_Thing`; the span above the item's `cable_span_metres`: `Cable_Too_Short`; `metres_held` below the span: `Not_Enough_Cable` (the developer command passes `max(i64)`); the ends on two frames, one of them a vessel's (`vessel_index >= 0`), and that end's part not a `connector` (`vessel_part_of`): `Not_A_Connector`. No loop refusal (decision 2).
- `add_cable :: proc(entities: ^Entities, content: Simulation_Content, cable: Cable)` and `remove_cable :: proc(entities: ^Entities, machines: Machine_Registry, index: int)` (`unordered_remove` on `cables` and `watts`, the map kept): each ends in `rebuild_electric_networks`.
- `entity_cable_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack`: the metres of every cable on the entity, by item, temp allocator; `entity_pickup_stacks` appends them before the machine's own return.
- `remove_entity_cables :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle)`: called by `remove_entity` before the pool removal (its deferred rebuild follows).
- `cable_hash :: proc(cable: Cable) -> u64`: `generation_seed.hash_combine` over the two ends, the lower end (kind, index, port) first, so it is the same both ways.
- `cable_sag_millimetres :: proc(cable: Cable, span_millimetres: i64, lower_pitch_millimetres: int) -> i64`: `span × (20 + hash % 21) / 1000` (2 to 4 percent), capped at `lower_pitch_millimetres / 2 × (70 + (hash >> 8) % 31) / 100`, the pitch of the lower end's frame, so the lowest point stays above the lower port's cell bottom. Integer, so the aim and the draw agree.
- `cable_curve_point :: proc(first, second: World_Position, down: [3]i64, sag_units: i64, step, steps: int) -> World_Position`: the chord at `step / steps` lowered `4 × step × (steps − step) / steps² × sag` along `down` (the first end's frame's up axis negated, `fixed_scale`).
- `cable_curve :: proc(entities: ^Entities, machines: Machine_Registry, cable: Cable) -> (first, second: World_Position, down: [3]i64, sag_units: i64, found: bool)`: the inputs of `cable_curve_point` for a live cable.
- `CABLE_AIM_RADIUS_MILLIMETRES :: 250`, `CABLE_AIM_STEP_MILLIMETRES :: 200`. `field_aimed_cable :: proc(entities: ^Entities, machines: Machine_Registry, player: Field_Player, tuning: Field_Player_Tuning) -> int`: a cable whose chord's middle lies farther from the eye than the reach plus half its chord plus its sag is skipped; otherwise its curve points every `CABLE_AIM_STEP_MILLIMETRES` (`steps = ceil(chord / step)`) are tested as `field_aimed_torch` tests a torch (along the look between 0 and `field_aim_limit`, within the reach, across at most the radius). The cable with the smallest along wins, ties by the smaller across, then the lower index; -1 for none.

### The run, `src/cable_field.odin` (simulation)

- `Field_Held_Tool.Cable` appended; `field_tool_for_item` returns it for an item with `cable_kilowatts`, before the machine lookup. `field_held_tool_places(.Cable)` is true (the Place hint); `update_field_held_tool` is unchanged for it.
- `update_field_cable_tool :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool)`, called in `queue_field_player_edit` right after `move_and_aim_field_player` and the walk record (after the refusal reset, with this tick's aim), on a local copy of the input whose Dig is stripped when it returns true, so felling, the pick up and the brush see none:
  - A run ends silently when the tool is not `.Cable` or the selected slot is not `cable_slot`; it ends with `Cable_End_Gone` when `cable_start` is no longer free (`port_end_is_free`: its entity gone, or another cable laid on the port).
  - Run carried: Dig pressed ends it (taken back) and returns true; Dig held returns true; Place pressed finds the second end (the aimed entity, `aimed_entity(NO_ENTITY, frame_target)`, and `free_power_port_nearest` to `frame_face_centre` of the hit cell and face; none is `No_Free_Port`), checks it with `cable_placement_refusal` and the inventory's count of the item, sets the refusal and keeps the run, or queues `Field_Placement{kind = .Cable, cable = ...}`.
  - No run, tool `.Cable`, Place pressed: the first end found the same way begins the run (`cable_run`, `cable_start`, `cable_slot` from `selected_hotbar_slot`); none is `No_Free_Port`.
  - No run, any tool: `advance_field_cable_take_up`.
- `tick_field_session_player` skips `queue_field_torch` while `cable_run` is set: its Place needs the torch tool and its Dig press is the run's take back.
- `advance_field_cable_take_up :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool)`: with no cable aimed (`field_aimed_cable`) or Dig not held, `cable_take_up_ticks = 0` and false. Otherwise a cable whose first end differs from `cable_take_up` restarts the count; its metres not fitting (`inventory_fits_all_picked_up`) set `Inventory_Full` and zero the count; else the count rises and at `mining_required_ticks(PICK_UP_SECONDS, tick_rate)` a `Field_Placement{kind = .Cable_Removal, cable = {ends = {first end, {}}}}` is queued and the count zeroed. True whenever a cable is aimed and Dig is held.
- `Field_Placement_Kind` gains `Cable` and `Cable_Removal`; `Field_Placement` gains `cable: Cable_Placement`. `drain_field_placements` routes them:
  - `drain_field_cable :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, placement: Cable_Placement)`: checked again with the inventory's count; refused, the refusal is set and the run stays (ended only for `Cable_End_Gone`); else `inventory_remove` of the span's metres, `add_cable`, `cables_run` counted, the run ended.
  - `drain_field_cable_removal :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, end: Port_End)`: the cable found again by its end; gone, nothing; not fitting, `Inventory_Full`; else `remove_cable` and `inventory_add_picked_up` of its metres.
- `Field_Edit_Refusal` gains, after `Inside_A_Vessel`: `No_Free_Port, Same_Thing, Cable_Too_Short, Not_Enough_Cable, Not_A_Connector, Cable_End_Gone`, each in `field_refusal_keys` as `field_refused_<snake case>`.
- The prediction (0182) runs the movement only, so the run and the take up the HUD shows are the confirmed tick's.

Developer command `cable` (`command.odin`, `command_field.odin`, `benchmark_factory.odin`, `developer.odin`):
- Block world `cable <item> <x> <y> <z> <port id> <x> <y> <z> <port id>`; field `cable <item> <frame> <x> <y> <z> <port id> <frame> <x> <y> <z> <port id>`. Numbers range checked as `place`'s are; the item must have `cable_kilowatts`; each cell must hold an entity with a power port of that id. In `command_writes_simulation`'s list.
- `Developer_Action.Place_Cable` appended last; `Developer_Request` gains `second_cell: World_Coordinate`, `second_frame: Frame_Id`, `ports: [2]u8`, `item: Item_Id`. Served in the tick: the entities found again, `cable_placement_refusal` with `max(i64)`, then `add_cable` with the measured metres and `cables_run` counted. Answers `ok cable <item> <metres> m`, or `error <refusal key>`.
- `blueprint_coordinate_index` becomes `blueprint_coordinate_indices :: proc(name: string) -> (first, second: int)`, `(2, 6)` for `cable` and second -1 for the others; `expand_blueprint_command` moves both triples; its error lists `cable`. `benchmark_command_problem` accepts `cable` naming a cable item.

### UI and strings

- `hud.odin`: `held_glyph_hints(tool: Field_Held_Tool, cable_run: bool, tech_demo := false)`: with `.Cable`, Place's hint is `hint_run_cable`, during a run `hint_connect` and Mine's `hint_take_back`. `aimed_glyph_hints`: with no run and `field_aimed_cable` of the HUD's field player at least 0, Mine's `hint_take_up` first (question 2).
- `field_tool_line` gains `entities: ^Entities`: during a run `field_tool_cable_run` or `field_tool_cable_past` with `{name}` the item's name and `{metres}` the item's span less, or more than, `chord_metres` from the first end's point to the hand (`cable_hand_point`); drawn through the existing fitted line.
- `cable_hand_point :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> World_Position` (`cable_field.odin`): the eye 300 mm down along the up and 250 mm along `field_player_right`.
- The take up's progress draws as a pick up's: `draw_hud` passes `player.mining`, or while that is inactive a `Mining_State{active = true, progress_ticks = cable_take_up_ticks, required_ticks = ...}` built by `cable_take_up_mining_state :: proc(player: Field_Player, tick_rate: int) -> Mining_State`.
- `ui_power.odin`: `power_status_line :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, tick_rate: int) -> string`: `power_no_cable` when no power port of the entity has a cable; a consumer's `power_draw` with its participant's delivered and offered (`format_joules_per_tick`); else today's satisfaction of its network. Callers: `ui_crafting_machines.odin` (2), `ui_launch_pad.odin`, `ui_fluid.odin`, `ui_machine.odin` (2). `power_panel_region` and `power_entity_status_text` serve the junction box and the cabinet as they served a pole. `power_network_list` is unchanged (decision 8).
- `render_power.odin`: the pole and substation draws, `draw_wires`, `wire_anchor`, `draw_supply_volume_ghost` (and its call in `render_player.odin`) and their constants go. `draw_pole`'s fallback draws a junction box or cabinet as a box of the record's `color` over its footprint less `JUNCTION_BOX_INSET :: 0.05` of a cell on each side across, with the edge wires; the switch and the lamp stay (0362: the fallback runs inside `begin_entity_cells_draw`).

Strings, `data/strings/en.sjson`:
- Gone: `item_`, `describe_item_`, `machine_` and `describe_machine_` of `small_pole`, `big_pole`, `substation`.
- Changed: `describe_item_copper_wire` "Poles, circuits and lamps." becomes "Cables, circuits and lamps."; `describe_item_log` drops "poles, "; `describe_item_power_switch` = "Joins the cables on its two ports while on and splits them while off. For isolating a brownout before it spreads."; `describe_machine_power_switch` = "On, it joins the cables on its two ports. Off, it splits them."; `power_no_networks` = "No power networks yet. Run a cable from a generator."; `describe_technology_electric_grid` = "Trunk cable, 24 MW over 50 m, and the junction cabinet's eight ports."; `quest_steam_text`: "place a fuel generator and a small pole beside the pump and give the generator coal" becomes "place a fuel generator, give it coal and run a light cable from it to the pump"; `quest_first_pole_title` = "Cables"; `quest_first_pole_text` = "Run 2 cables from the engine: hold a cable, Place on the engine, then on the machine. Then obtain 5 glass: smelt sand dug from a beach or a riverbed. Lamps will need it once optics is researched."; `quest_first_research_text` = "Place a lab, run a cable to it, feed it science packs and research automation."; `mc_first_pole` = "Power that stays in the engine is not billable. Cable carries it to where the invoices are."; `mc_hint_unpowered` = "A machine with no generator at the other end of its cable is furniture."; `quest_grid_text` = "Research the electric grid and make 20 m of trunk cable."; `mc_grid` = "The outpost has outgrown its light cable. Trunk cable carries more, and costs more to match.".
- Added: `item_light_cable` "Light cable", `item_heavy_cable` "Heavy cable", `item_trunk_cable` "Trunk cable", `item_junction_box` and `machine_junction_box` "Junction box", `item_junction_cabinet` and `machine_junction_cabinet` "Junction cabinet"; `describe_item_light_cable` "Two metres from one copper wire. Carries 300 kW, up to 20 m a span.", `describe_item_heavy_cable` "Two metres from four copper wire and an iron plate. Carries 3 MW, up to 30 m a span.", `describe_item_trunk_cable` "Two metres from eight copper wire and a steel. Carries 24 MW, up to 50 m a span.", `describe_item_junction_box` and `describe_machine_junction_box` "Four ports. Joins and branches cables.", `describe_item_junction_cabinet` and `describe_machine_junction_cabinet` "Eight ports. Joins and branches cables where a box runs out."; `objective_cables_run` "Cables run"; `field_refused_no_free_port` "No free power port there", `field_refused_same_thing` "The cable needs a second thing", `field_refused_cable_too_short` "The cable is too short", `field_refused_not_enough_cable` "Not enough cable", `field_refused_not_a_connector` "A vessel takes a cable on its connector", `field_refused_cable_end_gone` "The cable's first end is gone"; `field_tool_cable_run` "{name}: {metres} m of the span left", `field_tool_cable_past` "{name}: {metres} m past the span"; `hint_run_cable` "Run cable", `hint_connect` "Connect", `hint_take_back` "Take back", `hint_take_up` "Take up"; `power_draw` "Draw: {delivered} of {demand}", `power_no_cable` "No cable".

### Quests, kits, blueprints

- `data/quests/chapter_04.sjson`, ids and keys kept (saved progress names them): `first_pole`'s place objective becomes `{type = "counter", counter = "cables_run", label_key = "objective_cables_run", count = 2}`; the header comment's poles become cables.
- `data/quests/chapter_07.sjson`, `grid`: research `electric_grid`, then `{type = "craft", item = "trunk_cable", count = 20}`.
- `data/quests/chapter_01.sjson`'s counter list: `cables_run` added, `unpowered_machine_ticks` described as "electric machines on a netlist with no generator".
- `data/dev_kits.sjson`: chapter 4 `light_cable` 200 and `junction_box` 10 for the small poles; chapters 5 and 6 `light_cable` 300 and `junction_box` 15; chapter 7 `light_cable` 200, `junction_box` 10 and `heavy_cable` 200 for the big poles; chapter 8 `trunk_cable` 200 and `junction_cabinet` 10 for the substations.
- `data/blueprints/benchmark/{power, oil, assembly, smelting}.sjson`: each `place small_pole` and `place substation` becomes `place junction_cabinet` at its cell (rotation 0); `cable` lines run from every electric machine and generator the old supply volumes covered to a cabinet, and chain the cabinets towards the generators along the old wire links; a second cabinet beside one whose eight ports run out. Heavy cable from each steam engine and wherever more than 300 kW passes, trunk where more than 3 MW passes. Header comments updated. `test_benchmark_modules_cable_every_electric_machine` is the acceptance.

### Old saves

A save with poles loads (decision 7): the poles deleted, one `save: removed ...` line, the switches and machines present with no cable, their frames released where empty. No refund. A save with a cable table loads to an equal hash.

### Batteries and the control unit (step 2)

- `Vessel_Part` gains `power: Power_State` and `stored_joules: u64` (absent, zero).
- `STORE_DISPATCH_ORDER :: MAXIMUM_DISPATCH_ORDER + 1` (`power_machine.odin`).
- `collect_electric_participants` appends after the launch pads, in pool order, each live vessel part with a power port and a figure: a battery (`supplies_watts > 0` and `stores_watt_hours > 0`) a store with offer `min(rate, stored)` and room `min(rate, capacity − stored)`, rate `electric_joules_per_tick(supplies_watts)`, capacity `stores_watt_hours × 3600`; a control unit (`draws_watts > 0`) a consumer of `electric_joules_per_tick(draws_watts)`, 1 J a tick at 60 W. `Electric_Participant` gains `store: bool`, `room, charged: u64`; `participant_node_input` sets `charge_room`, `order = STORE_DISPATCH_ORDER` and `store`.
- `apply_electric_balance`: a battery's `stored_joules += charged − supplied`. `participant_power` gains `.Vessel_Part`. `Electric_Network.store_count` counted.
- Test `test_vessel_battery_charges_and_discharges` (below). `doc/vessels.md` and `doc/fluids.md`, Power: batteries.

### The draw

Step 1 (`src/render_cables.odin`, new, presentation):
- `CABLE_CURVE_STEPS :: 12`. `Cable_Draw :: struct {view: ^Model_View, frames: ^Frame_Matrix_Table, models: Model_Renderer, instances: ^Instance_Buffer, daylight_tint: [3]f32}`.
- `cable_draw_points :: proc(entities: ^Entities, machines: Machine_Registry, frames: ^Frame_Matrix_Table, cable: Cable) -> (points: [CABLE_CURVE_STEPS + 1][3]f32, found: bool)`: the 13 points of `cable_curve_point` in metres, the ends' frames from `find_frame_matrix` when `frames` is set (as `draw_belt_poles`), else `find_frame`.
- `cable_draw_color :: proc(item: Item, cable: Cable, tint: [3]f32) -> rl.Color`: `cable_color` with its value varied ±6 % by `cable_hash` (no two neighbouring cables of one item match), times the tint.
- `draw_cables :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, draw: Cable_Draw)`: each live cable whose box round its points widened by its thickness `model_view_shows` (frustum and the haze's end; nil view shows all) is drawn as 12 `rl.DrawLine3D` segments inside `begin_flat_batch`/`end_flat_batch`: unlit, hazed, cast into no shadow map.
- `draw_cable_run :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, body: Field_Player, tuning: Field_Player_Tuning, item: Item_Id, draw: Cable_Draw)`: the run from its port to `cable_hand_point` as the same curve with the item's sag, in `BELT_RUN_REFUSED_COLOR` past the item's span. `draw_field_cable_runs :: proc(scene: Field_Scene, draw: Cable_Draw)` (`loop_field_session.odin`, beside `draw_field_players`): for each player whose `field_player_body_pose` is `.Standing` and whose `cable_run` is set, `draw_cable_run` of `field_scene_player(scene, index).field` (the predicted body for a local player) with the selected stack's item.
- Field: `draw_field_scene` calls `draw_cables` and `draw_field_cable_runs` after `draw_belt_runs`, outside the pod's transform with `run_view` (the runs' reason: the points are world positions), `daylight_tint` the scene's. Block world: `loop.odin`'s `draw_wires(world)` becomes `draw_cables` with a nil view and frames and tint {1, 1, 1}.

Step 3, the cable's look:
- `CABLE_BOX_METRES :: 32`. Within it of the eye (the box round the points), each segment is one instance of `models.unit_cube` scaled to the item's thickness across and the segment's length along, oriented along it (`cable_segment_instance :: proc(first, second: [3]f32, thickness_metres: f32, color: rl.Color) -> matrix[4, 4]f32`, through `instance_matrix_with_color`), collected and drawn in one `begin_flat_instances`/`draw_mesh_instances`/`end_flat_instances` with `Field_Instance_Buffers.cables` (new); beyond it the lines; without `instancing_ready` the lines everywhere. The carried run the same way.
- `tools/frame_profile_views.sjson`, factory: the two small poles become `junction_box` at their cells, and a new `cables = [{item, from = [x, y, z], from_port, to = [x, y, z], to_port}]` list, placed by `tools/frame_profile.py` after the machines as `cable` lines on the pad's frame (with a case in `tools/frame_profile_test.py`): heavy from the steam engine to the box at [22, 1, 14] port `a`, light from its `b` to the lamp, trunk from its `c` to the box at [24, 1, 4] port `a`, light from that box's `b` to the lab and `c` to the assembler. The factory rows before and after step 3 are not comparable; the log says so.

No perceivable repetition: no texture, no animation, no sound; each cable's colour value and sag differ by its hash.

### Models

- The junction box and the cabinet ship without a model, drawn by the fallback above. Two sealed lab items follow (main agent): the junction box model and the junction cabinet model, each with its four or eight sockets on the face centres of the record's ports, footprint and colour as above.
- `data/models/small_pole.obj` and `.mtl`, `big_pole.obj` and `.mtl`, `substation.vox` go, with `tools/models/machines/small_pole.py`, `big_pole.py`, their entries in `tools/models/machines/__init__.py` and `substation()` with its map entry in `tools/make_placeholder_models.py`.

### Tests

New, in `src/cable_test.odin` unless named:
- `test_shipped_power_ports_resolve`: every record with an electric rating has one power port, at index 0, capacity at least its rating, on its footprint's surface, on no cell and face of an explicit `fluid_ports` entry, an inserter's on neither ±x; the junction box 4, the cabinet 8, the switch 2; no other kind but the vessel kinds lists a port.
- `test_malformed_cable_items_and_power_ports_are_refused`, table driven: a cable item missing one of the four keys, 0 kW, a span of 0 or 101, a stack below the span; an electric machine without a power port, with it second, or below its rating; a junction box with 1 or 9; a switch with 1; a furnace with a power port; `deleted_ids` naming a current id, a former id, or one twice.
- `test_a_hand_run_factory_is_powered` (block world): a steam engine whose offer is poked to 900 kW each tick as `tick_with_engine_offer` pokes it, heavy cable to a box with a lamp, a light cable from it to a second box with five working assemblers (375 kW on 300 kW). After a tick: the assemblers at 800, the lamp at 1000 and lit, the engine's delivered the sum of the deliveries. The light cable removed: the five at 0 and counted unpowered.
- `test_a_power_switch_splits_its_netlist`: off, the machines past it unpowered and one more network; on, one again; a cable closing a loop through it is laid and the topology holds one chord.
- `test_cable_placement_refusals`: each refusal of `cable_placement_refusal` once; a second cable between the same two boxes is laid and the bundled edge's watts are the sum.
- `test_field_cable_run_controls`, on `make_field_placement_test`'s world with a fuel generator and a junction box on a frame: Place on the box aimed at its positive_x face begins a run on port `b` and the tool line shows the span left; a refused Place (a chest) keeps the run and tells `No_Free_Port`; Place on the generator queues the cable, the drain takes the span's metres, counts `cables_run` and the generator's port has the cable; Dig during a run ends it, the terrain, the frame and `player.mining` unchanged; another slot ends a run; the box picked up by another player ends a run with `Cable_End_Gone`; a torch aimed during a run is not removed by the take back.
- `test_taking_up_a_cable_returns_its_metres`: Dig held on the cable for `PICK_UP_SECONDS` removes it and adds its metres, with a shovel held as with a cable; with a full inventory `Inventory_Full` and the cable stays; beyond the reach or behind the frame nothing happens.
- `test_picking_up_a_machine_returns_its_cables`: on the field the metres come with the machine and the pick up is refused `Inventory_Full` when they do not fit; in the block world they spill.
- `test_cable_spans_and_sag`: `cable_span_metres` rounds up; the sag stays above the lower port's cell bottom at the pitches 333, 500 and 1000; two cables of equal span sag differently; `field_aimed_cable` finds a cable's middle and not a point 300 mm beside it.
- `test_old_saves_lose_their_poles` (`save_test.odin`): `content_with_the_poles` (the shipped content with the three records, items and recipes back and no `deleted_ids`) saves a block world and a field world, each with a small pole, a big pole, a substation (on the field one on a foundation frame and one on bare ground with a frame of its own), a power switch and an assembler. Loaded with the shipped content: the poles gone, the bare ground pole's frame released, the switch and the assembler present with no cable, the line logged once, no refusal; a junction box placed afterwards reuses a freed slot; saved and loaded again to an equal hash. A save with a gone machine that is not deleted still refuses.
- `test_cables_save_and_load` (`save_test.odin`): a block world and a field world with cables save and load to an equal hash and equal records; a block world without a cable writes neither the mark nor the table; a cable whose item the content lost is dropped with its line; a dead end, and two cables on one port, each refuse the file.
- `test_power_netlist_is_deterministic`: two simulations of the hand run factory, 600 ticks with a switch turned and a cable taken up on set ticks, hash equal every tick.
- `test_the_cable_command_lays_and_refuses` (`command_test.odin`): block and field forms lay a cable and answer its metres; an unknown item, a missing port id, a refused span each answer an error; a blueprint line moves both triples.
- `test_benchmark_modules_cable_every_electric_machine`: each benchmark module built: every electric machine and generator has its power port's cable, and every consumer's network holds a generator.
- Step 2: `test_vessel_battery_charges_and_discharges`: a charged lead battery cabled to a control unit holds the unit at 1000 while `stored_joules` falls by 1 J a tick; a fuel generator on the ground cabled to the vessel's connector charges the battery by at most 33 J a tick up to its capacity; a battery that discharged this tick does not charge.
- Step 3: `test_cable_instances_follow_the_curve`: the instance matrices of a cable's 12 segments join end to end at the curve points and carry the varied colour.

Migrated: `power_test.odin`'s helpers become `add_test_power_plant(world, content, box_cell, engine_origin) -> (box, engine)` (a junction box at the cell, a trunk cable from the engine) and `cable_test_machines :: proc(world: ^World, content: Simulation_Content, box: Entity_Handle, handles: ..Entity_Handle)` (a trunk cable from each handle's power port through `add_cable`; when the box has one free port left, a junction box placed on the cell above and joined by trunk cable, filling on there). Every test that placed a pole places a box at its cell and cables its machines; expected values stay. `build_power_plant` (the save test site and the UI audit) cables its boxes and machines, so the audit's power cases keep their states. Rewritten to cables and named in the report: `test_power_data_loads`, `test_poles_connect_within_reach`, `test_supply_volume_decides_membership`, `test_power_switch_splits_a_network`, `hydro_grid_test.odin`'s three pole tests and its technology table; `machine_wear_test.odin`'s ground test uses `junction_box`; `model_triangle_mesh_test.odin` drops the two poles; `quest_chapter_04_test.odin` and `quest_chapter_07_test.odin` follow the objectives; `render_entities_test.odin`'s list names `junction_box`; `ui_placement_editor_test.odin`'s `big_pole` becomes `junction_cabinet`. `power_test.odin`'s direct `balance_electric_energy` cases build a star of trunk cables round a box and keep their numbers. Each test added that `build/test_times.tsv` shows at 1 s or more is marked `// slow`.

### Docs

- `doc/fluids.md`: line 5's electric network sentence; Power rewritten (the cable, the ports, the junction box and cabinet, the switch, the netlist of decisions 1 to 3 and 5, the run's refusals in one line pointing at `doc/input.md`, the rebuild triggers, old saves of decision 7, the unpowered statistic); Balance: a consumer's level is its region's, a thin cable browns out only what is behind it, and the sentence of question 2 of 0373 (below).
- `doc/content.md`: Items (the cable keys and the stack of 200, the boxes in the dozen class); Recipes' craft times ("poles" becomes "cables, junction boxes"); the phase 4 budget ("10 poles" becomes "5 junction boxes, about 150 m of light cable"); "medium pole (phase 5)" goes; a new section Cables and power ports (the table, the ports of the factory machines, the box, the cabinet, `deleted_ids`, ports appended and never reordered); Belt poles and runs' "The electric poles are kind `pole`" becomes "The electric poles were kind `pole` (gone in 0368)"; Machines on bare ground's `stands_on_ground` list names the junction box and cabinet in place of the poles.
- `doc/input.md`, Bindings: Place and Mine with a cable held (the run, its take back, the take up as a hold) and their hints; line 125's pole panel becomes the junction box's.
- `doc/architecture.md`, Save format: the cable table after the vessels' in a field world, the block world's mark, the deleted ids; Picking up: the cables come with.
- `doc/commands.md`: the `cable` row; the blueprint command list.
- `doc/vessels.md`: line 11 (parts with power ports join the netlist; step 2 makes batteries and the control unit take part) and What comes next.
- `doc/presentation.md`: a Cables paragraph after the runs (lines along the sag, step 3's boxes), line 198 drops the poles.
- `doc/quests.md` line 76: "Two poles" becomes "Two cables".
- `doc/code_map.md`: `cable.odin`, `cable_field.odin` (simulation), `render_cables.odin` (presentation); the power files' line.
- `DESIGN.md`: line 9 "poles" becomes "cables"; line 56 chapter 4's poles become cables; line 89's "pole network" becomes "cable network".

### Hand-back check

- Memory a frame draws from: the cable table, the topology and the inputs change only in ticks, commands and loads; the draw and the panels read them between ticks.
- Writes: no file is written.
- Start-up loads: malformed cable keys and ports are refused by the data load like any malformed record, with its fallback; an old save's poles are deleted instead of refusing the file.
- Parsed numbers: the `cable` command's coordinates and frames are range checked as `place`'s are, ports looked up by id. Rates: capacities and battery rates are floored limits that lose no energy.
- Save layout: the cable table (absent reads empty), the block world's mark, the `Field_Player` fields, `Statistics.cables_run` and (step 2) the `Vessel_Part` fields read zero when absent; the deleted poles with one line. No old save is refused; its factory loads unpowered, named in the log line and `doc/fluids.md`; the dev kits carry cables.
- Shared budget: the pool becomes the netlist; a consumer now gets its region's level, so a thin cable starves only what is behind it. Batteries (step 2) dispatch after every generator and charge only from what is left.
- Unbounded lists: the overview lists cabled networks in its scroll list; the tool line is fitted.
- Obsolete audit cases: the power cases keep their states through `build_power_plant`'s cables.
- Tests use temporary directories and touch no machine state.

### Captures (main agent)

On the field with `--dev`: a fuel generator, a junction box, an offshore pump, an assembler, a lab and a lamp run by hand (or with `cable` lines), at noon and at dusk, from 5 m, 20 m and 60 m; a run carried in first person, within and past its span. Step 1's captures show the lines; step 3's the boxes. An old save with poles loaded, its log line quoted.

### 0373's question 2

Inside a region the solve counts a consumer's exact need (`demand × level / 1000` unrounded). A whole joule rule would sum the floored deliveries. The two differ only on a branch whose need at the shared level lies within `n` joules above its cable's capacity (`n` its consumers), that is, a branch already at its cable's limit, and there the exact rule sits at most `1000 × n / D` levels lower (`D` the branch's demand), `1000 / d` for one kind of consumer of `d` J a tick. Every delivery differs by at most 1 J, and in the cases below by none.

| consumer | J a tick | levels at most |
| --- | --- | --- |
| lamp | 83 | 12 |
| flare stack | 166 | 6 |
| inserter, filter, long | 216 | 4.6 |
| pump | 500 | 2 |
| core sample drill | 666 | 1.5 |
| fast inserter | 766 | 1.3 |
| washer | 833 | 1.2 |
| 60 kW and up (labs, assemblers, drills, the rest) | 1000 to 8333 | 1 to 0.12 |

24 inserters (5,184 J) on a light cable (5,000 J): the exact rule 964, whole joules 967, both delivering 208 J each, so the machines work 3 per mille slower under the exact rule while drawing the same energy. 61 lamps (5,063 J): both 987. The control unit (1 J) cannot saturate its 3 J port. Answer: no follow-up item; the exact rule is the pooled rule's and keeps a machine's work in step with the energy it draws. One sentence in `doc/fluids.md`, Balance.

### Questions to the main agent

Controls first:
1. Back during a run: belt runs forget their start on Back (`update_field_run_tool`); 0355 named Mine and the slot change only, so Back does nothing here. Add Back?
2. The `hint_take_up` glyph on an aimed cable (UI and strings above): 0355 named the hold, not its hint. Keep it?
3. The take up works with any tool held, as the machine pick up it copies does; a shovel's Mine on an aimed cable then takes it up instead of digging behind it. Agreed, or only with a cable held?
4. The free power ports drawn as markers while a cable is held, so the player sees which port Place takes: not in 0355 and not specified. A later item?

Then:
5. The split into this item and two new ones (Steps).
6. The 0365 and 0357 seams left to those items (decision 10), against 0361's decision 5 that 0355's design provides the net query.
7. 0351 (held) adopts the frozen node in place of the frozen network when it lands after this item (0355's decision 8); nothing here waits for it.

### Decisions (main agent, 2026-11-13)

1. Approved as specified, as step 1. Steps 2 and 3 are the items 0383 and 0384, written from this specification and queued behind this one.
2. Controls, question 1: Back ends a run as it ends a belt run, the run taken back as by Mine. One meaning of Back in every run mode. Reversed by decision 11.
3. Controls, question 2: the take up hint on an aimed cable stays, as an aimed machine has its pick up hint.
4. Controls, question 3: agreed. Mine held on an aimed cable takes it up with any tool held, as on an aimed machine: the aim chooses the meaning, the held item does not.
5. Controls, question 4: no free port markers in this item. A note for `SUGGESTIONS.md` at the landing.
6. Questions 6 and 7: the query seams stay with 0365 and 0357, and 0351 takes the frozen node if it lands after this item.
7. 0373's question 2: no follow-up item; the sentence in `doc/fluids.md` as proposed.
8. Implemented beside 0373's redesign, since it reads the netlist's interface and 0373 changes only the solve's inside. Landing order: 0373 first when it is ready, else this item lands on the solve as it is and the log says so.
9. An old save's factory loses its poles and stands unpowered until cables are run. That is the user's decision of 2026-11-11 (all power hand run) and nothing softens it; the one log line and the quest's new counter are what the player meets.
10. Touch (after the review): while a cable item is held, a tap on an entity presses Place's control (`tap_place_control`) instead of the open panel's, so a run begins and ends by tap. With no cable held nothing changes.
11. Back no longer ends a cable run (reverses decision 2): the gamepad's EAST carries Sneak and Back, so a crouch took the run back. A run ends by Mine (Take back), a slot change, connecting, or its first end gone. Belt runs keep Back.

### Deviations (implementation, 2026-11-13)

- `cable_watts` takes `entities`: the ports' capacities come from the ends' machines.
- `cable_span_metres` the procedure is `port_span_metres`: named like the item's field, it counted 9 content to simulation references in `tools/code_graph.py`.
- `settle_cables` takes the remap and returns `(dropped, clamped: int, problem: string)`: the two refusals have their own texts for `reader.problem`; after the review a cable on a machine the load deleted is dropped, and one longer than `MAXIMUM_CABLE_SPAN_METRES` is cut to it with its own line.
- `power_port_node` takes no `entities`: an off switch is the entity named by the next node too.
- `Cable_Draw` has no `instances` until step 3 (0384).
- `field_tool_line` also takes the held item, which the cable run line names.
- `draw_field_cable_runs` reads the seat, not the body pose, which hides the first person viewer's body and would hide its own run.
- A junction box with no network shows "Not connected" on the HUD (`power_entity_status_text`).
- Placeholder icons for the five new items; the three pole icons go.
- `tools/frame_profile_views.sjson`: the factory's two small poles become `junction_box` now, since the view would not load without them; its cables stay step 3's.
- The hand made electric definitions of the combustion and fluid tests gained a power port; `machine_part_slots_test.odin`'s expected message follows the new port rule; the placement editor's `junction_cabinet` case expects false.
- `test_field_cable_run_controls` runs on `make_pick_up_test`'s world (the same content, without the far players and the tilted frame) with a pad at the site; the field save tests use `make_save_test_simulation` with the field tables on.
- The load's log lines are not captured: the tests read `deleted_machines_line(remap)` and the dropped cable's count.
