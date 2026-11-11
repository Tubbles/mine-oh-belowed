# 0355: Cables and the power netlist

Status: implementing (2026-11-11)

The user (2026-11-11), after The Last Caretaker: "Power: everything is hand run", then "No power rails", "Cable has capacity (we need to have a netlist based simulation, same for the fluids as well, no gravity)" and "saves with power poles just delete the poles". Today power poles join machines into pooled networks. 0353's study describes the reference's cables (`doc/inspiration.md`, The Last Caretaker) and its proposal is in `SUGGESTIONS.md`.

## Goal

Every power connection is a cable the player runs by hand from one thing to the next, each with a capacity, simulated as a netlist under the lockstep, and the power poles are gone.

## Controls

No new binding. The cable is a hotbar item, and running one is a mode the player enters and leaves with Place and Mine (control design, main agent, 2026-11-11):

- With the cable held and nothing carried, Place aimed at a thing with a free power port (a machine, a generator, a battery, a junction box) takes the cable's first end onto that port and begins the run. Aimed at anything else Place does nothing, with the reason shown as the other refusals are. The aimed thing is the target, not the port: a thing with several ports gives the free one nearest the aim.
- While a run is carried, the cable is drawn from its port to the player's hand and the tool line shows the length left of the span. Every movement control is unchanged. Place aimed at a second thing with a free port ends the run there and takes the cable's length from the stack. Aimed at nothing, at the first thing, or past the span, Place is refused with its reason (too short, no free port); the player is never held back by the cable.
- Mine while a run is carried takes the run back and ends the mode, as does selecting another hotbar slot. Mine digs and fells nothing during a run.
- With no run carried, Mine held on a cable takes it up into the inventory, the hold that picks up an aimed machine.
- The refusals have reasons of their own (added at the design's approval): past the span, not enough cable in the stack, the two things already joined (a cable never closes a loop), a vessel part that is not a connector, and the first end gone.
- Rotate_Building, Interact and Open_Inventory keep their meanings with the cable held and during a run. A machine's panel shows its port's draw, and a cable's load against its capacity is read on the junction box's panel and the power overview.
- A cable's capacity is its item (a light and a heavy cable are two items), never a setting cycled on a control. The junction box is placed as any machine.
- Touch reaches all of it through Place's and Mine's gamepad bindings.

## Change

- The cable as an item with a span, a port on every electric machine, generator and battery, a junction box that joins and branches. No rails: every machine takes its own cable.
- The power simulation as a netlist: nodes, the cables between them with their capacities, what a cable over its capacity does, in integers and deterministic, with the brownout and the power overview following it. It runs at all times over the whole world, also where the terrain and the models are unloaded (user, 2026-11-11), so its state stands apart from the loaded chunks.
- The small pole, the big pole and the substation leave the content. A save that holds them loads with them deleted and one log line; the quests, kits, technologies, recipes and blueprints that name them follow.
- The cable drawn between its two ends.
- Docs: `doc/fluids.md` (Power), `doc/content.md`, `doc/input.md`.

## Verify

- The checks and the suite, with a save holding poles that loads without them.
- Captures of a hand run factory of a handful of machines, sent to the user.

## Specification (design, 2026-11-11)

Three parts, each landing something that runs (question 1): **(A)** the netlist core under today's poles, with no behaviour change; **(B)** cables, ports and the junction box replace the poles, with the field controls, the save and the draw; **(C)** cable loads and the bottleneck on the junction box's panel and the overview. Order: A; B after A, 0361 A and 0362 (the field draws no power machine before 0362); C after B. 0365 and B land in either order.

### Decisions

1. **A netlist is a tree.** A cable that would join two things already joined through other cables is refused (`Already_Joined`), every power switch counted as on, so turning a switch never closes a loop. A cable beside a direct cable between the same two things is allowed, and the two bundle: their capacities add. On a tree the injections fix every cable's flow, so the solve is exact in integers and linear in the nodes. Rejected: loops with a per tick max flow or a Kirchhoff solve, neither exact in integers at this cost (question 2). A loop in a malformed save is a chord that carries nothing.
2. **A node is a thing's terminal.** One node per entity with a power port, its ports joined inside it, each port's capacity limiting the cable on it. A power switch that is off is two nodes, one per port. Nodes are numbered in pool order (`poles`, then the participants' pools in participant order, then `vessel_parts`), so leftover joules go in today's order.
3. **The solve: max-min fair levels in per mille, regions behind saturated cables.**
   - Fast path: every consumer gets today's pooled level `power_satisfaction(supply, demand)` and the generators share by dispatch order as today; then the flows are computed and each compared with its cable's capacity. All within: done.
   - Otherwise a saturated cable splits its netlist into regions. A region's level is `power_satisfaction` of its own offers plus what its saturated cables bring in, minus what they carry out, each at capacity. The side short of power gets the lower level and the side with spare power keeps its higher one, so a thin cable browns out only what is behind it. When no cable saturates this equals the fast path, which the tests hold.
   - Generators dispatch by order as today; where a cable blocks that, a repair pass moves the generation inside the limit.
   - Batteries (0361's, the only stores) discharge last, as dispatch order `STORE_DISPATCH_ORDER` (10). They charge from what the generators have left, through what the first phase left of each cable, fairly among batteries. A battery that discharged this tick does not charge.
   - Integers only: joules a tick in `i64`, levels in per mille, products in `i128`, every loop in node order. Demands stay today's `electric_joules_per_tick`. A capacity is floored to joules a tick: a limit, so no energy is lost.
   - The player sees a consumer's level as its satisfaction and the HUD's brownout warning when any netlist has a consumer below full. The machine's panel shows its draw against its demand, and (C) names the cables at capacity.
4. **Cost.** A rebuild (a cable or a power entity added or removed, a switch turned) sorts the edges and walks the forest, O(E log E + N): about 50,000 steps for a late factory of 2,000 machines, 700 junction boxes and 2,700 cables. A tick's fast path is four passes over the nodes. Saturated cables add two passes, and each node with a saturated cable below it gets a table of the 1,001 levels: a few hundred thousand steps for a few saturated cables in that factory, about three million when every cable of a chain saturates (`test_netlist_solve_cost`, question 3). No incremental solve: in a working factory the inputs change every tick (an inserter's swing), and the solve is a pure function of them.
5. **Cables are a table, not fields on the entities.** `Entities.cables` holds one record per cable: two ends of (entity handle, port index) as 0361 asks, the item and the metres. A map from port end to cable serves lookups only. No pool's struct changes for power, a record is symmetric by construction, the save and the draw iterate it, and 0356 can hold its pipes the same way. Rejected: a link on each port in each pool's struct (ten structs, two copies of each cable kept in agreement, or 48 bytes on every belt in `Entity_Common`).
6. **The netlist never sees a position.** The topology comes from the cable table and the switches alone, so a vessel's netlist moves with its frame and splits or joins by a cable's removal or addition. A cable's span is computed from its ends' frame poses (`power_port_point`) each time it is measured, aimed at or drawn; only its length in whole metres is stored.
7. **Removing an end returns the cable** (seam 4): the metres of every cable on a picked up entity join its stacks (`entity_pickup_stacks`). The field refuses the pick up `Inventory_Full` when they do not fit, as for a machine's contents, and the block world spills them as it spills contents. A swap to a part without the port returns the cable through the swap's own inventory check (0365). Chosen over refusing the removal: taking every cable up first is busywork, and the cable is never lost silently. A developer `remove` drops them.
8. **The poles leave through a data key.** `data/machines.sjson` gains `deleted_ids`. A saved machine id listed there remaps to none as a gone id does, without counting as gone, and a placed entity of it is deleted at load instead of refusing the file, with one log line. Rejected: a remap case naming the poles in code (the content rule).
9. **0351's seam is kept.** Every participant's offer is read each tick and every consumer's satisfaction goes through `deliver_power_satisfaction`. In B a sleeper's frozen `network` (0351) becomes its frozen node; the network is `topology.tree_of[node]`.
10. **Ports are 0361's.** The `ports` key and `Machine_Port` serve the factory's machines unchanged. B lifts the vessel kinds only rule; a factory machine gets one power port, listed first.
11. **Under the lockstep** nothing new travels: the run's begin, its take back and its end by a slot change are player state set in the player's tick from its input frame; the end and the take up are `Field_Placement`s drained in player order and checked again there.

### (A) The netlist core

Package `src/netlist/` (a leaf, importing nothing of `game`); `power_network.odin` imports it.

`src/netlist/netlist.odin`:
- `LEVEL_FULL :: 1000` (the game's `POWER_FULL`), `RESPONSE_LEVELS :: LEVEL_FULL + 1`, `NO_NODE :: max(u32)`, `UNLIMITED_CAPACITY :: i64(1) << 40` (joules a tick; times 1000 stays inside `i64`).
- `Edge :: struct {first, second: u32, capacity: i64}`, `Tree :: struct {first, count: u32}`.
- `Topology :: struct {parent: []u32, capacity: []i64, order: []u32, tree_of: []u32, trees: []Tree, chords: []Edge}`: per node its parent (`NO_NODE` for a root) and the bundled capacity to it (0 for a root); `order` holds every node in pre-order, each tree contiguous, the trees by root ascending; `trees[k]` is tree k's range of `order`.
- `build_topology :: proc(node_count: int, edges: []Edge, allocator := context.allocator) -> Topology`: edges turned to `first < second`, self edges dropped, sorted by `(first, second)`, equal pairs merged with their capacities added (capped at `UNLIMITED_CAPACITY`). A union find in that order makes each a tree edge or a chord. Each node without a parent starts a tree in ascending index, walked depth first with neighbours ascending (an explicit stack). Called by the game's rebuild.
- `destroy_topology :: proc(topology: ^Topology, allocator := context.allocator)`.
- `pooled_level :: proc(supply, demand: i64) -> u32`: today's `power_satisfaction` (demand 0: `LEVEL_FULL` when supply is above 0, else 0; otherwise `min(supply, demand) * LEVEL_FULL / demand`). The game's `power_satisfaction` returns it.

`src/netlist/solve.odin`:
- `Node_Input :: struct {demand, offer, charge_room: i64, order: u8, store: bool}`: joules this tick a consumer asks, an offer gives at its dispatch order, a store can take. A store's offer is its discharge.
- `Node_Output :: struct {level: u32, delivered, supplied, charged, flow: i64}`: the consumer's level; joules delivered to it, taken from the offer, put into the store; the flow on the edge to the parent, positive towards it.
- `solve :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output)`: `solve_tree` on every tree. Called once a tick by the game.
- `solve_tree :: proc(topology: Topology, tree: int, inputs: []Node_Input, outputs: []Node_Output, fast_path := true)`: phase 1, then phase 2 when the tree holds a store with charge room and an offer with joules left. Scratch in `context.temp_allocator`. `fast_path = false` skips the fast path (tests).
- A phase takes per node a demand and an offer with its order, and per non-root node the bounds `lower <= flow <= upper`. Phase 1: the demands, the offers, `[-capacity, capacity]`. Phase 2: the `charge_room` of each store that supplied nothing in phase 1, `offer - supplied` of each node that is no store, `[-capacity - flow, capacity - flow]` with phase 1's flow. A phase's deliveries go to `delivered` (phase 1) or `charged` (phase 2); `supplied` and `flow` add up over both.
- `uniform_levels`: the fast path's level `pooled_level(Σ offer, Σ demand)` for every node; delivered `demand * level / LEVEL_FULL`.
- `dispatch_by_order`: the tree's total delivered shared over the offers by order ascending, each order up to its offers, in proportion, rounded down, the rest a joule at a time in node order (today's `share_generator_energy` on one tree).
- `tree_flows`: in reverse pre-order, `flow = supplied - delivered + Σ children's flows`; `flows_within_bounds` checks every non-root node.
- `region_levels`, the slow path:
  - Bottom-up (reverse pre-order), each node's response for λ in 0 to 1000: `R(λ) = 1000 * offer - demand * λ + Σ children's clamp(R(λ), 1000 * lower, 1000 * upper)`. It is held as a line `a - b * λ` while every child is a line whose clamp does not bite on 0 to 1000 (`R(0) <= 1000 * upper` and `R(1000) >= 1000 * lower`), else as a table of `RESPONSE_LEVELS` values. `R` never rises with λ, and `R(0) >= 0`.
  - Per non-root node three thresholds, each the largest λ in 0 to 1000 meeting it, -1 for none (division on a line, binary search on a table): `rich_until` with `R(λ) > 1000 * upper`, `rich_level` with `R(λ) >= 1000 * upper`, `poor_level` with `R(λ) >= 1000 * lower`.
  - Top-down (pre-order): the root's level is the largest λ with `R(λ) >= 0`, and 0 when `R(0) == 0`. A child's level, with its parent's `p`: `rich_level` when `p <= rich_until`, `poor_level` when `p > poor_level`, else `p`. Delivered `demand * level / LEVEL_FULL`.
- `repair_dispatch`, when `dispatch_by_order` on the slow path's deliveries breaks a bound:
  - bottom-up per node, with `X` its subtree's delivered: `L = max(X + lower, Σ children's L, 0)`, `H = min(X + upper, offer + Σ children's H)`, the root without the bound terms;
  - top-down from the root's target `X`: each child's target starts at `clamp(its subtree's dispatched sum, L, H)` and the node's own `supplied` at its dispatched value. The difference to the node's target is spread over the rooms in proportion, rounded down, the rest a joule at a time in node order (own first), each within its room. Raising, the rooms are `offer - supplied` and each child's `H - target`; lowering, `supplied` and `target - L`. `L <= target <= H` at every node, so the rooms always suffice;
  - then `tree_flows` again.

Game side, `src/power_network.odin`:
- `balance_electric_energy` keeps its signature and runs through the core: the participants in order are nodes, then one hub node per network; each participant with a network has an `UNLIMITED_CAPACITY` edge to its hub; `build_topology` and `solve` in the temp allocator. A consumer's `delivered` is its node's, a generator's its node's `supplied`; the networks' figures as today. A participant without a network is a node alone. The adapter lives until B.
- `Electric_Participant` gains `node: int`.
- `deliver_power_satisfaction :: proc(entities: ^Entities, handle: Entity_Handle, satisfaction: u32)`: writes `participant_power(...).satisfaction`; `apply_electric_balance` calls it. If 0351 has landed, its version stays.
- `power_satisfaction` returns `netlist.pooled_level`.
- `doc/code_map.md` and `tools/code_graph.py`: the package `netlist` as its own cluster and the reaches the check reports. `doc/fluids.md`, Power: one line that the balance runs through `src/netlist/`.

Tests (A), `src/netlist/netlist_test.odin`:
- `test_build_topology_is_order_independent`: 200 seeded edge lists of up to 40 nodes, each shuffled ten times, give equal topologies. A parallel pair's capacities add, the later edge of a loop in sorted order is the chord, a node without edges is a tree of its own, and every root is its tree's lowest node.
- `test_uniform_netlists_match_the_pooled_balance`: 500 seeded trees of up to 60 nodes with `UNLIMITED_CAPACITY` edges: every level is `pooled_level` of the tree's sums, and every `supplied` equals a reference dispatch written in the test (orders ascending, proportional, the rest in node order).
- `test_solve_matches_brute_force_on_small_netlists`: 3,000 seeded trees of 2 to 6 nodes, no stores. Demands come from {0, 1000, 2000, 3000, 4000} J, so a level's delivery is exact. Half the nodes offer 0 to 6000 J at orders 0 to 2; capacities are 0 to 6000 J.
  - The reference enumerates every edge as open, saturated up or saturated down. Regions are the components of the open edges. A region's level is `pooled_level` of its offers plus inflows minus outflows at capacity; an assignment with a negative supply is dropped. An assignment is feasible when every region's open edges carry its flows: the `L`, `H` intervals of the repair pass with the saturated flows as fixed injections, the region's delivered total inside its root's interval.
  - The solver's levels of the consumers with a demand, sorted ascending, equal the lexicographically largest of the feasible assignments', and its output passes the next test's checks. A case where they differ is reported with its seed, never fitted.
- `test_solve_output_is_feasible`: 500 seeded trees of up to 300 nodes with stores, orders 0 to 10 and capacities from 0 to above the totals.
  - Per node: `0 <= delivered <= demand`, `0 <= supplied <= offer`, `0 <= charged <= charge_room`, and a store charges only when it supplied nothing.
  - Per non-root node, `|flow| <= capacity` and `flow` equals its subtree's supplied minus delivered minus charged.
  - Per tree, `Σ supplied == Σ delivered + Σ charged`.
- `test_slow_path_agrees_with_the_fast_path`: every case whose fast path holds gives the same outputs with `fast_path = false`.
- `test_a_saturated_cable_browns_out_only_its_side`: a 1000 J offer at the root, a 200 J consumer beside it, a 500 J edge to a junction with two 400 J consumers: the junction's consumers at 625, the root's at 1000, the junction's flow -500, supplied 700.
- `test_a_rich_branch_exports_at_capacity`: a 2000 J offer behind a 300 J edge with a 500 J consumer, 1000 J of consumers at the root: the branch at 1000, the root at 300, the edge's flow 300.
- `test_dispatch_follows_the_order_where_cables_allow`: a 900 J offer at order 0 behind a 300 J edge, a 900 J offer at order 1 at the root, 1000 J demanded at the root: 300 and 700 supplied.
- `test_stores_discharge_last_and_charge_from_what_is_left`: a generator, a consumer and a store. With demand below the generator's offer, the store charges what is left up to its room and supplies 0. With demand above it, the store supplies the shortfall and charges 0. A 100 J edge to the store already carrying the consumer's flow limits the charge to what is left of it.
- `test_solve_is_deterministic`: the brute force and feasibility sets solved twice give outputs equal byte for byte.
- `test_netlist_solve_cost` (report test): 2,000 consumers on 700 junction nodes in chains of 30, first with one saturated edge, then with every edge saturated; prints microseconds per `solve`.

The game's power tests pass unchanged: A's proof of no behaviour change.

### (B) Cables replace the poles

#### Data

`data/items.sjson`: `Item_Definition` and `Item` gain `cable_kilowatts` (1 to 1,000,000), `cable_span_metres` (1 to 100, at most the stack size), `cable_thickness_millimetres` (5 to 100) and `cable_color` (three of 0 to 255), all four or none. One item is one metre.

| item | kW | span m | mm | color | stack | price | recipe | channel |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `light_cable` | 300 | 20 | 12 | [52, 52, 56] | 200 | 1 | copper_wire 1 → 2 | `start` |
| `heavy_cable` | 3,000 | 30 | 24 | [176, 120, 36] | 200 | 3 | copper_wire 4, iron_plate 1 → 2 | technology `electric_mining` |
| `trunk_cable` | 24,000 | 50 | 40 | [140, 44, 36] | 200 | 8 | copper_wire 8, steel 1 → 2 | technology `electric_grid` |
| `junction_box` | | | | | 50 | 6 | iron_plate 2, copper_wire 4 → 1 | `start` |

All category `machine`. Recipes 0.5 s, `made_in = ["hand", "assembler"]`, `category = "power"`, tags `["electric"]`. The kW are whole joules a tick at 60 Hz (5,000, 50,000, 400,000). The three pole items and recipes go.

`data/machines.sjson`:
- Top level `deleted_ids = ["small_pole", "big_pole", "substation"]` (`Machines_File` and `Machine_Registry` gain it); each must be neither a current id nor a former id.
- The three pole records go; `supply_volume` and `wire_reach` leave the struct, the power switch and the header comment.
- Kind `pole` becomes `junction_box` (`Machine_Kind.Pole` to `.Junction_Box`).
- Every record with `electric_power_kilowatts` or `electric_output_kilowatts` (27 today) gets `ports = [{id = "power", kind = "power", cell = {x = 0, y = 0, z = depth / 2 rounded down}, face = "negative_x", capacity_watts = rating × 1000}]`; where its `fluid_ports` use that cell and face, the face is `positive_x`.
- `junction_box`: keys `machine_junction_box`, `describe_machine_junction_box`, item `junction_box`, kind `junction_box`, `stands_on_ground = true`, footprint 1×1×1, `color = [96, 98, 92]`, no model; ports `a` negative_x, `b` positive_x, `c` negative_z, `d` positive_z at cell (0, 0, 0), each 24,000,000 W.
- `power_switch`: ports `a` negative_x and `b` positive_x, 24,000,000 W.
- `validate_machine_ports` (0361) gains: a record with an electric rating has its only power port at index 0 with a capacity of at least its rating; a junction box has 2 to 4 power ports, a power switch exactly 2; no other kind except the vessel kinds has a power port; a fluid port outside the vessel kinds stays refused until 0356.

`data/vessel_parts.sjson`: the control unit draws 60 W (question 6).

`data/technologies.sjson`: `electric_mining` also unlocks `heavy_cable`, `electric_grid` unlocks `["trunk_cable"]`, header comment updated.

Quests, keeping their ids and keys (saved progress names them):
- `chapter_04.sjson`, `first_pole`: `{type = "counter", counter = "cables_run", label_key = "objective_cables_run", count = 2}`, then the glass; header comment updated.
- `chapter_07.sjson`, `grid`: research `electric_grid`, then `{type = "craft", item = "trunk_cable", count = 20}`.

`data/dev_kits.sjson`: each `small_pole` count N becomes `light_cable` 10 × N and `junction_box` max(N / 2, 4); `big_pole` becomes `heavy_cable` 200; `substation` becomes `trunk_cable` 200 and `junction_box` 10.

`data/blueprints/benchmark/{oil, assembly, smelting, power}.sjson`:
- Each `place small_pole` and `place substation` becomes `place junction_box` at its cell (rotation 0), with more boxes beside where one fed more than three machines.
- `cable` lines (Files and procedures) run from every electric machine and generator the old supply volume covered to a box, and chain the boxes to the generators along the old wire links. Heavy cable from each steam engine and wherever more than 300 kW passes.
- Header comments updated.

Models: `data/models/small_pole.*`, `big_pole.*` and `substation.vox` go, with their entries in `tools/make_placeholder_models.py` and `tools/models/machines/__init__.py`.

#### State, save and hash

- `src/cable.odin`: `Port_End :: struct {entity: Entity_Handle, port: u8}`, `Cable :: struct {ends: [2]Port_End, item: Item_Id, metres: u16}`, `Cable_Table :: struct {cables: [dynamic]Cable, port_cable: map[Port_End]int}` in `Entities.cables`. The map is derived (rebuilt after a load and kept on each change) and never iterated.
- `Vessel_Part` gains `power: Power_State` and `stored_joules: u64` (the battery's charge, as 0361 asks).
- `Statistics.cables_run: u64`; `Hint_Counter.Cables_Run` (`cables_run`), read in `quest_runtime.odin` beside `.Unpowered_Machine_Ticks`.
- `Field_Player` gains `cable_run: bool`, `cable_start: Port_End`, `cable_slot: u8`, `cable_take_up: Port_End`, `cable_take_up_ticks: u32`.
- The pole pool keeps its names (`Pole`, `poles`, `Entity_Kind.Pole`), since the save matches pools by position and a handle's kind by name. A comment says it holds junction boxes and power switches.
- `write_cable_table :: proc(bytes: ^[dynamic]byte, entities: ^Entities)`: `write_list` of the cables, last in `write_simulation_state` (after the field world's tables, 0361's vessel tables included) and only when the world has a cable. `write_later_tables` gets `field_follows || len(cables) > 0`, so a block world writes its frame tables before it. A world without a cable keeps its bytes and its hash.
- `read_cable_table :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool`: read when bytes are left, else empty; then `settle_cables`.
- `settle_cables :: proc(entities: ^Entities, machines: Machine_Registry) -> (dropped: int, ok: bool)`: drops and counts a cable whose item reads as none or whose port index is no longer a power port of its entity's machine; refuses the file for a dead end or two cables on one port end ("the save has a cable whose end is gone"). When some were dropped, one line: `save: dropped %d cables whose item or port this build no longer has`.
- The tests that cut a save's tail (0361's list) add `write_cable_table` after `write_vessel_tables`.

`src/save_remap.odin`:
- `Content_Former_Id` gains `deleted: bool`; `content_former_ids` adds `{former = id, deleted = true}` for each machine `deleted_ids` entry.
- `Content_Remap` gains `deleted: [Content_Table][]bool` (indexed like `saved`), `deleted_entity_count: int` and `deleted_handles: [dynamic]Entity_Handle` (temp allocator). `make_content_remap` maps a deleted id to `CONTENT_GONE` and marks it.
- `read_content_id`: a deleted id reads as none and skips `note_gone_id`.
- `settle_gone_machines`: an alive entry whose machine is none is deleted when `first_gone[.Machines] == ""` (every gone machine id met so far was deleted): `alive = false`, machine 0, its index onto `pool.free`, its handle onto `deleted_handles`, counted. Otherwise it refuses as today.
- `read_frame_tables` and `read_machine_wear_table` skip a record whose handle is in `deleted_handles` instead of refusing.
- `deleted_machines_line :: proc(remap: ^Content_Remap) -> string`: `save: removed %d placed machines of deleted kinds (%s)`, naming the deleted ids the saved table held; logged once beside the renamed ids line. The machines the poles fed load with no cable.

#### Files and procedures

`src/cable.odin` (simulation; `tools/code_graph.py` gains the prefix `cable` in `PREFIX_CLUSTERS["simulation"]`):
- `frame_face_centre :: proc(frame: Frame, cell: World_Coordinate, face: Direction) -> World_Position` (in `world_frame.odin`): `frame_cell_centre` moved half a pitch along the face.
- `power_port_point :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> (point: World_Position, found: bool)`: the port's cell (`rotate_footprint_cell` by the entity's rotation, plus its origin) and face (`rotate_direction`) through `frame_face_centre` of the entity's frame (`find_frame`). Not found for a dead entity or a missing port. Every measure, aim and draw calls it.
- `cable_span_metres :: proc(entities: ^Entities, machines: Machine_Registry, first, second: Port_End) -> i64`: the chord in whole metres rounded up, at least 1.
- `cable_capacity :: proc(entities: ^Entities, content: Simulation_Content, cable: Cable, tick_rate: int) -> i64`: joules a tick, the least of the item's and both ports' (`electric_joules_per_tick`).
- `port_end_cable :: proc(table: ^Cable_Table, end: Port_End) -> int`: -1 for none.
- `machine_port_is_linked :: proc(entities: ^Entities, owner: Entity_Handle, port: int) -> bool`: 0361's seam answered for power ports; a fluid port stays false until 0356. Replaces 0365's stub if that landed first.
- `power_port_net :: proc(entities: ^Entities, handle: Entity_Handle, port: int) -> int`: `topology.tree_of` of the port's node, -1 for none.
- `power_ports_share_net :: proc(entities: ^Entities, first: Entity_Handle, first_port: int, second: Entity_Handle, second_port: int) -> bool`. For 0365: a vessel part is hooked up when one of its power ports shares the net of the control unit's.
- `frame_is_tied_by_cable :: proc(entities: ^Entities, frame: Frame_Id) -> bool`: a cable with one end on the frame and one off it, for 0361's `vessel_is_tied`.
- `free_power_port_nearest :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, point: World_Position) -> (port: int, found: bool)`: the free power port whose point is nearest, the lowest index on a tie.
- `entities_are_joined :: proc(entities: ^Entities, machines: Machine_Registry, first, second: Entity_Handle) -> (joined, direct: bool)`: a walk over the cables from `first`, every switch counted as on; direct when a cable joins the two.
- `Cable_Placement :: struct {ends: [2]Port_End, item: Item_Id}`.
- `cable_placement_refusal :: proc(entities: ^Entities, content: Simulation_Content, placement: Cable_Placement, metres_held: i64) -> Field_Edit_Refusal`, in order:
  - the first end dead or taken: `Cable_End_Gone`; the second not a free power port: `No_Free_Port`;
  - one entity at both ends: `Same_Thing`;
  - the span above the item's: `Cable_Too_Short`;
  - `metres_held` below the span: `Not_Enough_Cable` (the developer command passes `max(i64)`);
  - joined but not directly: `Already_Joined`;
  - ends on two frames, one of them a vessel's (`vessel_index >= 0`) and that end's part not a `connector`: `Not_A_Connector`.
- `add_cable :: proc(entities: ^Entities, machines: Machine_Registry, cable: Cable)` and `remove_cable :: proc(entities: ^Entities, machines: Machine_Registry, index: int)` (`unordered_remove`, the map kept): each ends in `rebuild_electric_networks`.
- `entity_cable_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack`: the metres of every cable on the entity, by item, in the temp allocator; `entity_pickup_stacks` appends them.
- `remove_entity_cables :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle)`: called by `remove_entity` before its rebuild.
- `cables_on_lost_ports :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, machine: Machine_Id) -> []Item_Stack` and `remove_cables_on_lost_ports :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle)`: the cables on ports the new machine lacks, for the swap's inventory check and after it (0365's caller).
- `cable_sag_millimetres :: proc(entities: ^Entities, machines: Machine_Registry, cable: Cable, span_millimetres: i64) -> i64`: `span × (20 + hash % 21) / 1000` (2 to 4 percent by a hash of the two ends), capped at half the pitch of the lower end's frame times `(70 + hash % 31) / 100`, so the lowest point stays above the lower port's cell bottom. Integer, so the aim and the draw agree.
- `cable_curve_point :: proc(first, second: World_Position, down: [3]i64, sag: i64, step, steps: int) -> World_Position`: the chord at `t = step / steps` lowered `4 t (1 - t) sag` along `down`, the first end's frame's up axis negated.
- `field_aimed_cable :: proc(entities: ^Entities, content: Simulation_Content, player: Field_Player, tuning: Field_Player_Tuning) -> int`: as `field_aimed_torch`, against the 8 segments between 9 curve points of each cable within `CABLE_AIM_RADIUS_MILLIMETRES :: 250`, nearer than `field_aim_limit` and within the reach; -1 for none.

`src/cable_field.odin` (simulation, the tool):
- `Field_Held_Tool.Cable` appended; `field_tool_for_item` returns it for an item with `cable_kilowatts`, before the machine lookup.
- `update_field_cable_tool :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool)`, called in `tick_field_session_player` after `queue_field_torch`, its `took_dig` stripping Dig the same way:
  - a run ends when the tool is not `.Cable`, the selected slot is not `cable_slot`, or the first end is dead or taken (`Cable_End_Gone`);
  - Place pressed with no run: the aimed entity (`aimed_entity(NO_ENTITY, frame_target)`) and its `free_power_port_nearest` to the hit face's centre begin the run (`cable_run`, `cable_start`, `cable_slot`); none gives `No_Free_Port`;
  - Place pressed during a run: the second end found the same way and checked with `cable_placement_refusal`; a refusal is set and the run stays, else a `Field_Placement{kind = .Cable}` is queued;
  - Dig pressed during a run ends it; Dig pressed or held during a run returns `took_dig`;
  - with no run, `advance_field_cable_take_up`.
- `advance_field_cable_take_up :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, input: Field_Player_Input) -> (placement: Field_Placement, finished, took_dig: bool)`: Dig held on an aimed cable counts `cable_take_up_ticks` up to `mining_required_ticks(PICK_UP_SECONDS, tick_rate)`, keyed by the cable's first end (a new key restarts). When its metres do not fit: `Inventory_Full` and no progress. Finished, it queues `.Cable_Removal`. `took_dig` whenever a cable is aimed.
- `Field_Placement_Kind` gains `Cable` and `Cable_Removal`, `Field_Placement` gains `cable: Cable_Placement`; `drain_field_placements` routes them to:
  - `drain_field_cable :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, placement: Cable_Placement)`: checked again, then `add_cable` with the span's metres, the metres taken from the inventory, `cables_run` counted, the run ended;
  - `drain_field_cable_removal :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, end: Port_End)`: the cable found again; `Inventory_Full` when it does not fit, else removed and its metres added.
- `Field_Edit_Refusal` gains, appended after 0361's: `No_Free_Port, Same_Thing, Cable_Too_Short, Not_Enough_Cable, Already_Joined, Not_A_Connector, Cable_End_Gone`, each in `field_refusal_keys`.

Developer command `cable`, in `command.odin`, `command_field.odin` and `benchmark_factory.odin`:
- block world: `cable <item> <x> <y> <z> <port id> <x> <y> <z> <port id>`; field: `cable <item> <frame> <x> <y> <z> <port id> <frame> <x> <y> <z> <port id>`;
- the entities at the cells, their ports by id, `cable_placement_refusal` with `max(i64)`, then `add_cable` with the measured metres, `cables_run` counted;
- every number range checked as `place`'s are; `benchmark_command_problem` accepts `cable` naming a cable item.

`src/power_network.odin`, rewritten around the cables (the hub adapter of A goes):
- `Electric_Networks` drops `nodes`, `wires` and `memberships`. It gains `node_entities: [dynamic]Entity_Handle` (an off switch's two nodes name it twice), `node_of_entity: map[Entity_Handle]u32` (its first node), `topology: netlist.Topology`, `inputs` and `outputs`. `networks` is per netlist.
- `rebuild_electric_networks`: the nodes of decision 2, one edge per cable (`cable_capacity`), `build_topology`; 0351's `wake_all_entities` stays first.
- `power_port_node :: proc(networks: ^Electric_Networks, entities: ^Entities, handle: Entity_Handle, port: int) -> int`: the entity's node, plus one for port 1 of an off switch; -1 for none. `entity_network` returns the netlist of the entity's first node.
- `collect_electric_participants` also takes the vessel parts:
  - a battery is a store: offer `min(rate, stored)`, room `min(rate, capacity - stored)`, with rate `electric_joules_per_tick(supplies_watts)` and capacity `stores_watt_hours * 3600`;
  - a control unit is a consumer of `draws_watts`;
  - `participant_power` gains `.Vessel_Part`.
- `STORE_DISPATCH_ORDER :: MAXIMUM_DISPATCH_ORDER + 1` in `power_machine.odin`.
- `balance_electric_energy :: proc(networks: ^Electric_Networks)`: the inputs from the participants, `netlist.solve`, each participant's `delivered` back. Per netlist `Electric_Network` gains `store_count`: supply the offers, demand the demands, delivered, satisfaction the lowest level among consumers with a demand (else `pooled_level(supply, 0)`), the counts.
- `apply_electric_balance`: a battery's `stored_joules += charged - supplied`.
- `record_electric_tick`: a consumer is unpowered on a netlist with no generator and no store (question 10).
- `machine_touches_power` is true for a machine with a power port; `toggle_power_switch` is unchanged (it rebuilds).

`src/render_cables.odin` (presentation, new):
- `draw_cables`, after `draw_belt_runs` in `draw_field_scene` and in the block world's pass in place of the pole wires:
  - each cable's 13 curve points through `cable_curve_point` and `world_position_to_metres`, skipped outside the frustum (a sphere round the chord's middle of half the chord plus the sag);
  - within `CABLE_TUBE_METRES :: 32` a 6 sided tube of the item's thickness per segment, beyond it a line, beyond the haze's end nothing;
  - the item's `cable_color` times the daylight tint, its value varied ±6 % by a hash of the ends, so neighbouring cables of one item never match.
- `draw_cable_run`: the carried run from its port to the hand (the eye 300 mm down and 250 mm right) as a tube, tinted as a refused ghost when past the span.
- `render_power.odin`: the pole and substation draws and the wires go; the switch and the lamp stay.

UI:
- `hud.odin`: `field_tool_line` gains `entities: ^Entities`. With a run carried it shows `field_tool_cable_run` or `field_tool_cable_past`, the metres from `cable_span_metres` between the first end and the hand. The take up's progress shows as a pick up's, from `cable_take_up_ticks`.
- `held_glyph_hints`: with a cable held, Place's hint `hint_run_cable`; during a run, Place's `hint_connect` and Mine's `hint_take_back`.
- `ui_power.odin`: `power_status_line` shows `power_draw` with the node's delivered and demand, or `power_no_cable` when the power port has none. `power_network_list` lists only netlists with a cable, named by position. `power_panel_region` serves the junction box as it served a pole.

Strings, `data/strings/en.sjson`:
- Gone: `item_small_pole`, `item_big_pole`, `item_substation`, and their `describe_item_`, `machine_` and `describe_machine_` keys.
- Changed:
  - `describe_item_copper_wire`: "Poles," becomes "Cables,"; `describe_item_log` drops "poles,";
  - `power_no_networks` = "No power networks yet. Run a cable from a generator.";
  - `describe_technology_electric_grid` = "Trunk cable: 24 MW over 50 m.";
  - `quest_steam_text`: "a small pole beside the pump" becomes "run a light cable from it to the pump";
  - `quest_first_pole_title` = "Cables"; `quest_first_pole_text` = "Run 2 cables from the engine: hold a cable, Place on the engine, then on the machine. Then obtain 5 glass: smelt sand dug from a beach or a riverbed. Lamps will need it.";
  - `quest_first_research_text`: "within reach of a pole" becomes "with a cable to it";
  - `mc_first_pole` = "Power that stays in the engine is not billable. Cable carries it to where the invoices are.";
  - `mc_hint_unpowered` = "A machine with no generator at the other end of its cable is furniture.";
  - `quest_grid_text` = "Research the electric grid and make 20 m of trunk cable.";
  - `mc_grid` = "The outpost has outgrown its light cable. Trunk cable carries more, and costs more to match.".
- Added:
  - `item_light_cable` "Light cable", `item_heavy_cable` "Heavy cable", `item_trunk_cable` "Trunk cable", `item_junction_box` and `machine_junction_box` "Junction box", their descriptions (the kW and the span; the box "Four ports. Joins and branches cables.");
  - `objective_cables_run` "Cables run";
  - `field_refused_no_free_port` "No free power port there", `field_refused_same_thing` "The cable needs a second thing", `field_refused_cable_too_short` "The cable is too short", `field_refused_not_enough_cable` "Not enough cable", `field_refused_already_joined` "These are already joined", `field_refused_not_a_connector` "A vessel takes a cable on its connector", `field_refused_cable_end_gone` "The cable's first end is gone";
  - `field_tool_cable_run` "{name}: {metres} m of the span left", `field_tool_cable_past` "{name}: {metres} m past the span";
  - `hint_run_cable` "Run cable", `hint_connect` "Connect", `hint_take_back` "Take back";
  - `power_draw` "Draw: {delivered} of {demand}", `power_no_cable` "No cable".

#### Tests (B)

- `test_shipped_power_ports_resolve`: every record with an electric rating has one power port, first, with a capacity of at least its rating; the junction box has 4, the switch 2, every port on its record's surface; no other kind but the vessel kinds has one.
- `test_malformed_cable_items_and_power_ports_are_refused`, table driven: a cable item missing one key, 0 kW, a span of 0 or 101, a stack below the span; an electric machine without a power port or with a port below its rating, a junction box with 5, a switch with 1, a furnace with a power port; `deleted_ids` naming a current id.
- `test_a_hand_run_factory_is_powered` (block world): a steam engine at a poked 900 kW offer (`tick_with_engine_offer`), heavy cable to a box with a lamp, a light cable from it to a second box with five working assemblers (375 kW on 300 kW). After a tick: the assemblers at 800, the lamp at 1000 and lit, the engine's delivered the sum of the deliveries. The light cable taken up: the five at 0 and counted unpowered.
- `test_a_power_switch_splits_its_netlist`: off, the machines past it unpowered and one more netlist; on, one again; while it is off, a cable that would close a loop through it is refused `Already_Joined`.
- `test_cable_placement_refusals`: each refusal of `cable_placement_refusal` once; a second cable between the same two boxes is accepted and the edge's capacity is the sum.
- `test_field_cable_run_controls`, on `make_field_placement_test`'s world with a fuel generator and a junction box on a frame:
  - Place on the box, aimed at its positive_x face, begins a run on port `b`, and the tool line shows the span left;
  - a refused Place (a chest) keeps the run;
  - Place on the generator queues the cable; the drain takes the span's metres from the stack, counts `cables_run` and links the generator's port;
  - Dig during a run ends it, the terrain and the frame unchanged and no pick up progress;
  - selecting another slot ends a run.
- `test_taking_up_a_cable_returns_its_metres`: Dig held on the cable for `PICK_UP_SECONDS` removes it and adds its metres; with a full inventory `Inventory_Full` and the cable stays; beyond the reach or behind the frame nothing happens.
- `test_picking_up_a_machine_returns_its_cables`: on the field the cable's metres come with the machine, and the pick up is refused `Inventory_Full` when they do not fit; in the block world they spill.
- `test_cable_spans_follow_the_frames`: after `set_frame_pose` the port points move with the frame and `cable_span_metres` is unchanged; a cable across two frames ties each (`frame_is_tied_by_cable`); the sag stays above the lower port's cell bottom; two cables of equal span sag differently.
- `test_port_queries`: `machine_port_is_linked`, `power_port_net` and `power_ports_share_net` across a switch on and off; with 0361's vessel, a battery on the control unit's net and one not.
- `test_vessel_battery_charges_and_discharges`: a charged lead battery cabled to a control unit holds the unit at 1000 while `stored_joules` falls by its demand a tick; a fuel generator on the ground cabled to the vessel's connector charges the battery by what is left, up to its capacity.
- `test_old_saves_lose_their_poles`: `content_with_the_poles` (the shipped content with the three records, items and recipes back and no `deleted_ids`) saves a block world and a field world, each with a small pole, a big pole, a substation (one on a frame and worn), a power switch and an assembler.
  - Loaded with the shipped content: the poles gone, the switch and the assembler present with no cable, the line logged once, no refusal; a junction box placed afterwards reuses a freed slot; saved and loaded again to an equal hash.
  - A save with a gone machine that is not deleted still refuses.
- `test_cables_save_and_load`: cables save and load to an equal hash and equal records; a cable whose item the content lost is dropped with its line; a dead end, and two cables on one port, each refuse the file.
- `test_power_netlist_is_deterministic`: two simulations of the hand run factory, 600 ticks with a switch turned and a cable taken up on set ticks, hash equal every tick.
- `test_benchmark_modules_cable_every_electric_machine`: each benchmark module built: every electric machine and generator has its power port linked, and every consumer's netlist holds a generator.
- Migrated: every test that placed a pole places a junction box at its cell and cables its machines through `cable_test_machines :: proc(world: ^World, content: Simulation_Content, box: Entity_Handle, handles: ..Entity_Handle)` (trunk cable through `add_cable`, more boxes stacked above the first as its ports run out). Expected values stay. A test whose subject was a pole's reach or volume is rewritten to cables and named in the report. `power_test.odin`'s direct `balance_electric_energy` cases build a star netlist through a test helper and keep their numbers. The UI audit's power cases keep their states, now through the kit's cables.

#### Docs (B)

- `doc/fluids.md`, Power, rewritten: the cable, the ports, the junction box and the switch, the netlist (decisions 1 to 3 and 6), batteries, the brownout and what the panels show, the unpowered statistic, the rebuild triggers, old saves (decision 8).
- `doc/content.md`: the cable item keys and table, the factory machines' `ports` beside 0361's, the junction box, `deleted_ids`; the pole sections go.
- `doc/input.md`, Bindings: Place and Mine with a cable held (the run, its take back, the take up as a hold) and the glyph hints; the pole panel line becomes the junction box's.
- `doc/code_map.md`: `cable.odin`, `cable_field.odin` and `render_cables.odin` in their clusters.
- `DESIGN.md`: chapter 4's poles become cables; the signal network's "pole network" becomes the cable network.

### (C) Loads on the panels

- `cable_load :: proc(networks: ^Electric_Networks, entities: ^Entities, content: Simulation_Content, index: int, tick_rate: int) -> (flow, capacity: i64)` (`cable.odin`): the child node's `flow` on the tree edge between the cable's end nodes, a bundle's share in proportion to capacity; 0 when the ends are not parent and child (a chord, an off switch).
- `power_panel_region`, the junction box: one line per port, at most 4: `power_port_free` "{port}: free" or `power_port_line` "{port}: {cable} to {peer}, {load} of {capacity}", in the accent colour at capacity, fitted. A switch keeps its toggle as the one focusable row.
- `power_network_detail`: `power_cables_at_capacity` "Cables at capacity: {count}", then at most `POWER_CABLE_ROWS :: 5` cables by load per mille, ties by cable index: `power_cable_line` "{cable}: {from} to {to}, {load} of {capacity}", then `power_more_cables` "and {count} more".
- Tests:
  - `test_cable_load_reads_the_tree_flow`: two bundled cables share the flow by capacity; a saturated light cable reads 300 of 300 kW;
  - `test_power_detail_caps_the_cables`: seven busy cables give five lines and "and 2 more";
  - the audit cases `junction box panel` (four ports, one at capacity) and `power` with a saturated cable, at every size.
- Docs: `doc/fluids.md`, Power, the panels.

### Hand-back check

- Memory a frame draws from: the topology, the inputs and outputs and the cable table change only in ticks, commands and loads, never in the UI pass. The panels and the draw read them between ticks; (C)'s audit cases run the frame and read the draw list.
- Writes: no file is written.
- Start-up loads: malformed cable keys and ports are refused by the data load like any malformed record, with its fallback. An old save's poles are deleted instead of refusing the file.
- Parsed numbers: the `cable` command's coordinates and frame ids are range checked as `place`'s are; ports are looked up by id.
- Rates per tick: the solve moves whole joules. Capacities and battery rates are floored limits that lose no energy. The control unit goes to 60 W, so it draws 1 J a tick instead of 0.
- Save layout: the cable table (absent reads empty), `Vessel_Part.power` and `.stored_joules`, `Statistics.cables_run` and the `Field_Player` fields (absent read zero), the deleted poles with one line. The machines the poles fed load unconnected, named in the log line and `doc/fluids.md`; the dev kits carry cables.
- Shared budget: batteries join the dispatch after every generator and charge only from what is left, so no consumer's share shrinks for them. The control unit is a consumer like any other.
- Unbounded lists: the overview's netlists stay in its scroll list; (C) caps the cable lines at five and the panel at four ports, fitted at the smallest size. The tool line is fitted.
- Obsolete audit cases: the power cases keep their states with cables, and the junction box panel replaces the pole panel.
- Tests use the existing temporary directories and touch no machine state.

### Questions to the main agent

1. The split: A stays 0355; B and C become new items.
2. Loops are refused. A reversal needs a flow solve per tick with fairness on a graph, much heavier and not exact in integers; the alternative of accepting a loop whose extra cable carries nothing would confuse the player.
3. A netlist whose every cable saturates costs up to about three million steps a tick at 2,700 nodes; the report test measures it. If that is too slow, a follow-up keeps the last tick's regions and checks them in linear time first.
4. A junction box has four ports (0361's `MAXIMUM_MACHINE_PORTS`), so a 2,000 machine factory needs about 700 boxes. An eight port cabinet (1×1×2) needs the constant at 8.
5. The cable tiers and values are shipped as tuning: 300 kW over 20 m, 3 MW over 30 m, 24 MW over 50 m.
6. The control unit's 50 W (0361) becomes 60 W, since 50 W floors to 0 J a tick.
7. No ground battery exists: the item's "battery" is 0361's vessel battery alone, and DESIGN's pod batteries are a later item.
8. Take up is a hold of `PICK_UP_SECONDS`, as Mine picks up a machine. The Controls' "too short" is the span; `Not_Enough_Cable`, `Already_Joined`, `Not_A_Connector` and `Cable_End_Gone` are reasons the Controls do not name.
9. `deleted_ids` is a machine key only; gone items and recipes vanish as before.
10. The unpowered statistic changes meaning: a consumer on a netlist with no generator and no store (today, a machine outside every pole's volume).

### Decisions (main agent, 2026-11-11)

1. The split is accepted. This item is part A: the `src/netlist/` package with its tests and the brute force reference, wired under today's poles through the hub adapter with no behaviour change. Part B (cables, ports, the junction box, the poles' removal, the controls, the save, the draw, the content) is 0368, after 0361 and 0362. Part C (cable loads and the bottleneck on the panels and the overview) is 0369, after 0368. Both are implemented from this specification.
2. Question 1: loops are refused, and the user is told, since it is a rule of play: a netlist is a tree, and a second path between two things is not laid.
3. Question 2: accepted, the report test measures the case where every cable saturates.
4. Question 3: `MAXIMUM_MACHINE_PORTS` is 8. The junction box ships with 4 ports and a cabinet with 8 at a later technology, both in 0368.
5. Questions 4, 7, 8, 9: accepted as designed. The unpowered statistic's new meaning is named in the log at 0368's landing.
6. Question 5: the control unit draws 60 W; 0361's specification is read with that value.
7. Question 6: no ground battery in these items.
8. 0351's frozen `network` becomes the frozen node when 0368 lands, in whichever of the two lands second.
