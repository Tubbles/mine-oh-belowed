# 0356: The pipes' netlist

Status: landed (2026-11-13, 63befd45)

The user (2026-11-11): "we need to have a netlist based simulation, same for the fluids as well, no gravity". Today pipes carry liquids and gases in one network model in which liquids run downhill for free and need pumps to climb (`doc/fluids.md`). The world's water (lakes, the sea, streams, the water bodies) is the terrain's and is not this item.

## Goal

The pipes are simulated as a netlist, as power is in 0355, with no gravity in a pipe.

## Controls

None.

## Change

- The pipe network as nodes and the pipes between them with their capacities, in integers and deterministic; what moves a fluid when height no longer does (pumps, pressure from a source, a tank's level), decided in the design against 0355's netlist so the two share what they can. It runs at all times over the whole world, as 0355's does.
- A save's pipe networks load into it, with one log line where a network that ran by gravity no longer flows.
- The quests and kits that teach water running downhill in a pipe follow.
- Docs: `doc/fluids.md`, `doc/content.md`.

## Verify

- The checks and the suite, with the dev kits' fluid lines running at their rates.

## Specification (design, 2026-11-11)

Designed against 0355 A as it stands in `.claude/worktrees/0355` (snapshot `b5657e1`, with `bound_flows_by_levels`) and its specification. This item is part A of three (question 1): the netlist under today's connections. Hand run pipes (B) and vessel tanks (C) are new items.

### Decisions

1. **What moves a fluid.** Each tick, per netlist, ports offer and ask and `netlist.solve` decides, as for power. Height plays no part.
   - Producer: an output port (a pump's outlet, a boiler's steam, a crafting machine's product): offer its litres at order `FLUID_PRODUCER_ORDER` (0).
   - Consumer: an input port: demand its room.
   - Store: a storage tank's `both` port: offer its litres at `FLUID_STORE_ORDER` (1), charge room its room. It gives only what the producers cannot and fills only from what they leave after the consumers, never from another tank.
   - Relief: the flare stack's port is a store offering 0, so it takes only what every consumer and tank left: a relief valve. It still burns only above `FLARE_RELIEF_PERCENT`.
   - Every offer, demand and charge room is capped at the port's connection (the litres its joints carry a tick), so a lone port never saturates its own joint and the fast path holds wherever there is no real bottleneck.
   - Litres live only in port buffers; the solve moves them buffer to buffer. The machines' ticks are unchanged.
2. **A pump is a one way link with a rate between two netlists**: its inlet a consumer on one, its outlet a producer on the other, its tick moving its rate times its power as today. It empties a tank into another, meters a line and keeps a fluid from flowing back. `head_metres` leaves the data, the code and the panel. Rejected: no pump (chapter 6's quest and the tank lose their partner); a pump as an edge capacity (an edge has no power or direction).
3. **Pipes hold nothing.** In the block world, pipes that touch are one junction node, unlimited inside. A joint is a face where a port meets a pipe or another port; each carries the pipe's `flow_litres_per_second` (20 L a tick), and joints between one pair bundle (a tank on a pipe by three faces carries 60). Rejected: a node per pipe piece, whose loops (any pipe two wide) the tree solve cuts at chords that carry nothing. The rare loop left (two tanks touching each other and one pipe) is cut at a chord as 0355 cuts a malformed save's.
4. **One fluid per netlist, decided each tick from saved state**: the fluid of the first port in node order that is open (its `closed` flag from the last tick) and holds litres; else of the first output or tank port holding litres; else none. A port holding another fluid, or whose filter or phase filter refuses it, is closed (today's rule), moves nothing and counts a mixing refusal when it closes. A netlist keeps its fluid while an open port holds it; two netlists joined take the first such port's fluid and close the others, losing nothing (today the other fluid's pipes emptied). The saved list of network fluids is written empty.
5. **A gas moves as a liquid does.** The phase stays a port filter (the flare's gas, the combustion generator's burnable gas, the chemical plant's gas inlet); a tank holds either.
6. **The rounding top-up, the one addition to `src/netlist/`.** Levels are per mille and litres a tick are few: 21 empty boilers on one 20 L joint each get `20 × 47 / 1000 = 0`, and the line stalls for good. With `top_up = true`, after each phase's levels and dispatch, the litres the rounding left go out in one pass per dispatch order, lowest first: bottom-up each subtree matches its own spare with its own shortfall and passes the rest across its edge within the phase's bounds; top-down each node serves its own shortfall, then its children in node order, drawing on its own spare, then its children's. On a tree that is the most that can move, so no line stalls; the leftover goes to the first consumers in node order (today's gotcha was the first in coordinate order). Levels do not change. Power never sets it, so 0355's tests run unchanged.
7. **Reuse.** As is: `Edge`, `Topology`, `build_topology` (bundling, chords, pre-order), `destroy_topology`, `Node_Input`, `Node_Output`, `solve` with its fast path, regions, direction rule, dispatch, repair and the stores' second phase. Added: the top-up. The fluid side keeps the nodes, joints and junctions, the scaling of joints to litres, the fluid and the closing, the caps, the buffers and the pipes' view.
8. **Connections stay today's: frame 0's.** Joints are looked up on the block frame only, so fluid machines on a field frame stay netlists of their own ports, as today, and the aliasing in which a frame's port met a frame 0 entity at the same coordinates (the benchmark world holds both) ends. How the field joins ports is B's.
9. **The world's water meets a pipe only in a machine's tick.** The offshore pump adds litres to its port from the water in front of it, the tar pit pump from its pit; the netlist sees their ports. No pipe pours into the world's water (0295's water pump has no port), and the hydro turbine reads the world's flowing water. Unchanged; the field's gap is question 4.
10. **Always on.** `tick_fluid_networks` takes the entities, the fluids and the limit, no world, and runs every tick over every port. Its state is the buffers and closed flags in the pools, hashed and saved; the topology is derived at each placement, removal and load.
11. **Cost.** Nodes are the ports (up to 4 a machine) and junctions, edges the joints: 1,000 fluid machines and 300 pipe groups make about 2,800 nodes and 3,000 joints. A rebuild is `O(pipes + ports + joints log joints)`. A tick is about 30 passes over the nodes (inputs, fluid, closing, the fast path with one dispatch pass per order, four top-up passes per order and phase, the buffers and the pipes): some 85,000 steps. A joint saturating in a real bottleneck adds a 1,001 entry table at its parent, as in 0355.

### What stops working as today (for the log)

- Liquid no longer runs downhill by itself or stops below a height; no pump is needed to climb.
- Pipes hold no fluid, and the limit is per joint, not per pipe piece along a run.
- The head, the head line and "Above the pump's head" are gone.
- Two tanks on one netlist no longer even out (a pump between their netlists does it), and a tank never drains into a flare.
- Old saves: a block save's litres in pipes are dropped with one line, its ports and tanks run on (a tank above its consumers still feeds them). A field save changes nothing: no fluid port was joined there.
- Chapter 6's first quest keeps its id, objectives and keys; its text teaches the pump and the tank.

### Files and procedures

`src/netlist/solve.odin`:
- `solve :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, top_up := false)`, `solve_tree :: proc(topology: Topology, tree: int, inputs: []Node_Input, outputs: []Node_Output, fast_path := true, top_up := false) -> (took_fast_path: bool)`, `solve_phase :: proc(phase: ^Phase, by_node: []i32, fast_path, top_up: bool) -> (took_fast_path: bool)`: with `top_up`, `top_up_phase` then `tree_flows` before each of its two returns. The header comment names the top-up.
- `top_up_phase :: proc(phase: ^Phase)`: `top_up_order` for each order among the positions with an offer, ascending.
- `top_up_order :: proc(phase: ^Phase, order: u8)`:
  - `spare[p] = offer[p] - supplied[p]` where `order[p] == order`, else 0; `short[p] = demand[p] - delivered[p]`; nothing when either sums to 0.
  - Bottom-up: `net[p] = spare[p] - short[p] + Σ sent[c]` over p's children; for `p > 0`, `sent[p] = clamp(net[p], lower[p] - flow[p], upper[p] - flow[p])`, the phase's bounds as they stand (0355's direction rule included).
  - Top-down (`phase_children`, `cross[0] = 0`), at p: `give = spare[p] + Σ max(sent[c], 0) + max(-cross[p], 0)`, `take = short[p] + Σ max(-sent[c], 0) + max(cross[p], 0)`. When `give >= take` every taker is served in full and `take - max(-cross[p], 0)` is drawn from p's spare first, then from the exporting children in order, each up to `sent[c]`; otherwise every giver gives in full and `give - max(cross[p], 0)` goes to p's shortfall first, then to the importing children in order, each up to `-sent[c]`. `cross[c]` is what was drawn from c (positive) or given to it (negative); p's own part adds to `supplied[p]` and `delivered[p]`.

`src/fluid_network.odin`, rewritten; header comment: decisions 1, 3, 4, 6 and 8.
- `FLUID_PRODUCER_ORDER :: 0`, `FLUID_STORE_ORDER :: 1`.
- `Fluid_Node :: struct {owner: Entity_Handle, port: i32, direction: Fluid_Port_Direction, filter: Fluid_Id, phase_filter: Fluid_Phase_Filter, capacity: i32, relief: bool}`: `port` -1 for a junction (`owner` its first pipe), `relief` a flare stack's port.
- `Fluid_Networks :: struct {nodes: [dynamic]Fluid_Node, first_port_node: map[Entity_Handle]u32, junction_of_pipe: map[Entity_Handle]u32, topology: netlist.Topology, capacity: [dynamic]i64, connection: [dynamic]i64, scaled_limit: i64, netlist_fluids: [dynamic]Fluid_Id, inputs: [dynamic]netlist.Node_Input, outputs: [dynamic]netlist.Node_Output, allocator: runtime.Allocator}`. The topology's capacities count joints; `capacity` is litres a tick on each node's edge to its parent and `connection` on all its tree edges, both at `scaled_limit`; `netlist_fluids` per tree. Derived, never saved.
- `destroy_fluid_networks`, `clear_fluid_networks`: kept, also freeing the maps and the topology.
- `collect_fluid_nodes :: proc(entities: ^Entities, machines: Machine_Registry)`: every port of every live fluid machine, assembler, drill and launch pad, in today's pool and port order; `first_port_node`.
- `collect_pipe_junctions :: proc(entities: ^Entities) -> map[World_Coordinate]Entity_Handle`: the frame 0 pipes joined face to face (`union_find_root`), one junction node per group after the ports, in the order of each group's first pipe; fills `junction_of_pipe`; returns the pipe cells (temp allocator).
- `fluid_node_at_face :: proc(entities: ^Entities, machines: Machine_Registry, networks: ^Fluid_Networks, pipe_cells: map[World_Coordinate]Entity_Handle, cell: World_Coordinate, face: Direction) -> int`: on frame 0, a pipe's junction there, else a port facing back (`port_at_face`), else -1.
- `fluid_joint_edges :: proc(entities: ^Entities, machines: Machine_Registry, networks: ^Fluid_Networks, pipe_cells: map[World_Coordinate]Entity_Handle) -> []netlist.Edge`: each frame 0 port's positive faces (`placed_port_faces`) and each pipe's six, an edge of capacity 1 to another node met there (temp allocator).
- `rebuild_fluid_networks` (signature kept; 0351's `wake_all_entities` stays first): clear, nodes, junctions, joints, `netlist.build_topology`, the arrays sized, `scaled_limit = -1`.
- `scale_fluid_capacities :: proc(networks: ^Fluid_Networks, limit: i64)`: when `limit != scaled_limit`, `capacity[v] = topology.capacity[v] * limit` and `connection[v]` its own plus its children's.
- `fluid_node_buffer :: proc(entities: ^Entities, node: Fluid_Node) -> (buffer: ^Fluid_Buffer, closed: ^bool)`: through `entity_port_buffers`, nil for a junction.
- `fluid_port_is_closed :: proc(node: Fluid_Node, buffer: Fluid_Buffer, fluid: Fluid_Id, fluids: Fluid_Registry) -> bool`: today's `segment_is_closed` for a port.
- `decide_netlist_fluids :: proc(entities: ^Entities, networks: ^Fluid_Networks)`: decision 4, one pass in node order.
- `close_mixing_ports :: proc(entities: ^Entities, networks: ^Fluid_Networks, fluids: Fluid_Registry) -> (refusals: u64)`: each port's `closed`, the newly closed counted.
- `fluid_node_input :: proc(node: Fluid_Node, buffer: Fluid_Buffer, closed: bool, connection: i64) -> netlist.Node_Input`: decision 1, zero for a junction or a closed port. Pure.
- `apply_fluid_outputs :: proc(entities: ^Entities, networks: ^Fluid_Networks)`: `level += delivered + charged - supplied`, the netlist's fluid set on a port that received, `flow_in = delivered + charged`, `flow_out = supplied`.
- `show_pipe_flows :: proc(entities: ^Entities, networks: ^Fluid_Networks)`: each frame 0 pipe's buffer becomes `{fluid = its netlist's, level = 0, flow_in = flow_out = throughput}`, the throughput being the litres entering its junction (`max(flow, 0)` of each child, `max(-flow, 0)` of its own edge).
- `tick_fluid_networks` (signature kept): `reset_fluid_flows`, scale, decide, close (into `statistics.mixing_refusals`), inputs, `netlist.solve` on the topology with `capacity` and `top_up = true`, apply, pipes.
- `fluid_node_of :: proc(networks: ^Fluid_Networks, owner: Entity_Handle, port: int) -> int`, `fluid_netlist_of` (same parameters, the node's tree, -1 for none), `fluid_netlist_count :: proc(networks: ^Fluid_Networks) -> int`.
- `drop_pipe_litres :: proc(entities: ^Entities) -> (litres: i64)` and `pipe_litres_line :: proc(litres: i64) -> string` ("save: dropped %d litres held in pipes, which hold no fluid since 0356"): called in `read_simulation_state` before `rebuild_loaded_world`, the line logged when litres are above 0.
- Removed: everything from `Fluid_Segment` to `segment_is_above_head_line` except `union_find_root` (power uses it), `is_positive_direction`, `entity_port_buffers` and `reset_fluid_flows`.

Elsewhere:
- `src/machine_fluid_ports.odin`: `MAXIMUM_HEAD_METRES`, `validate_pump_head`, `machine_kind_is_pump` and `placed_port_height` go; a pipe needs only `flow_litres_per_second`. `src/machine.odin`: `head_metres` and the machine level `buffer_litres` leave `Machine_Definition`, `Machine` and the resolve.
- `src/save_state.odin`: `fluid_network_fluids` and `restore_network_fluids` go; `write_world_state` writes an empty `Fluid_Id` list in their place; `Loaded_Derived_State.network_fluids` becomes `dropped_network_fluids`, read and ignored.
- `src/ui_fluid.odin`: `fluid_machine_head_rows`, `pump_head_line` and `fluid_second_line` go; `fluid_buffer_rows` loses `above_head_line`; `pipe_panel_region` shows its netlist's fluid (`fluid_name`) and `fluid_flow_line`; `fluid_status_text` a pipe's name and fluid.
- `src/render_fluids.odin`: `draw_pipe` draws its band the core's full height in the fluid's colour while `flow_in > 0`.

### Data and strings

- `data/machines.sjson`: `head_metres` off the offshore pump, the pump and the tar pit pump, `buffer_litres` off the pipe; the header's paragraphs on pipes, the offshore pump, the pump, the storage tank and the flare stack say decisions 1 to 3.
- `data/fluids.sjson` header: the phase is what a port admits; in a pipe both move alike. `data/quests/chapter_06.sjson` header: "uphill" no longer claims a lift.
- `data/strings/en.sjson`, removed: `fluid_above_pump_head`, `fluid_pump_head`. Changed:
  - `quest_uphill_title` = "Pump and tank";
  - `quest_uphill_text` = "Research fluid handling. Place a pump and a storage tank. A tank keeps what a network has spare and gives it back when the network runs short. A pump moves fluid one way, from one network into the next.";
  - `mc_uphill` = "A pipe hands over what is offered to whoever asks. What nobody asks for, the venture would like kept.";
  - `describe_item_pump` = "Moves 1200 litres a second from its input's network into its output's, one way, on 30 kW. How one tank is emptied into another.";
  - `describe_machine_pump` = "Pushes 1200 litres a second from input to output, one way. Unpowered, nothing passes.";
  - `describe_item_offshore_pump` = "Set at the water's edge, it draws 1200 litres a second on 60 kW. Rivers and lakes never run dry for it.";
  - `describe_item_pipe` = "One iron plate rolled into a pipe. Pipes that touch are one network, and each joint with a machine passes 1200 litres a second.";
  - `describe_machine_pipe` = "Holds nothing itself. Each joint with a machine passes up to 1200 litres a second. One fluid per network.";
  - `describe_machine_storage_tank` = "One port on every face. One fluid at a time, liquid or gas. It fills from what its network has spare and empties when the network runs short.";
  - `describe_machine_flare_stack` = "Takes only the gas nothing else on its network asks for, and burns it above 90 percent full. What it burns is counted as voided.";
  - `describe_technology_fluid_handling` = "The pump and the 25,000 litre storage tank: fluid kept in reserve, and moved one way from network to network.".
- The dev kits carry items only and keep their counts.

### Tests

`src/netlist/netlist_test.odin` (0355's tests unchanged; `test_solve_is_deterministic` also solves its sets with the top-up):
- `reference_residual_flow :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output) -> i64`: augmenting paths from a super source over each `offer - supplied` to a super sink over each `demand - delivered`, along each edge's room (`capacity - flow` up, `capacity + flow` down, none up from a child at a lower level than its parent, none down into a child at a higher one). For netlists without stores.
- `test_top_up_reaches_the_maximum_flow`: 3,000 seeded trees of 2 to 7 nodes, no stores, demands 0 to 9, half the nodes offering 0 to 9 at orders 0 to 2, capacities 0 to 9. Without and with the top-up: equal levels; `delivered` and `supplied` never lower with it; the totals differ by `reference_residual_flow` of the run without; `expect_feasible_output`. A differing seed is reported, never fitted.
- `test_top_up_changes_nothing_when_nothing_is_left` (the paired run): on the brute force and definition sets, where the run without leaves a residual flow of 0, the run with is equal byte for byte.
- `test_top_up_output_is_feasible`: the feasibility set with stores and the top-up passes `expect_feasible_output`, with the levels of the run without.
- `test_top_up_feeds_more_consumers_than_litres`: node 0 offering 20, an edge of 20 to node 1, nodes 2 to 41 asking 20 each on edges of 20: nothing moves without; with it node 2 gets 20 and node 0 supplies 20. Three consumers of 20 on 20 offered: 8, 6, 6.
- `test_top_up_fills_a_large_store`: an offer of 20 and a store with charge room 25,000 behind an edge of 60: charged 0 without, 20 with. A store offering 0 beside a consumer asking 15, 20 offered: the consumer 15, the store 5.
- `test_fluid_shaped_solve_cost` (report, `NETLIST_FLUID_COST`): 250 junctions, each with a producer offering 20 and eight consumers asking 20 on edges of 20, chained through 50 stores; microseconds a solve with the top-up.

`src/fluid_test.odin`:
- `place_test_tank :: proc(world: ^World, content: Simulation_Content, origin: World_Coordinate, fluid: string, litres: i32) -> Entity_Handle`. A test in any file that seeded a pipe with litres seeds a tank meeting that pipe (or further along a new pipe), keeping its expected outcome.
- Gone: `test_pump_head_is_validated`, `test_two_pipes_balance_to_equal_levels`, `test_flow_is_limited_per_connection_and_tick`, `test_gravity_holds_water_but_not_steam`, `test_pump_moves_water_uphill_only_with_power`, the head tests from `test_offshore_pump_lifts_water_to_its_head` to `test_a_pump_with_an_empty_input_lifts_nothing`, `test_machine_fed_liquid_never_climbs`.
- `test_fluid_data_loads`: no head, the pipe's 20 L a tick, no pipe buffer.
- `test_touching_pipes_are_one_junction`: an L of four pipes between a tank and a boiler's inlet is one netlist of three nodes, the outlet another: `fluid_netlist_count` 2.
- `test_a_joint_carries_twenty_litres_a_tick`: a full water tank piped to a boiler's inlet: 20 L a tick until it holds 200, the tank losing exactly that, each pipe showing water, 20 in and 20 out.
- `test_height_moves_nothing_by_itself`: a column from a tank at y 1 to a boiler at y 9 fills it as on the floor; a full tank at y 9 and an empty one at y 1 on one column keep their litres.
- `test_a_tank_fills_from_what_is_left_and_empties_last`: a powered offshore pump, a tank and a boiler's inlet on one junction: the inlet fills first, the tank takes the rest; the pump unpowered and the inlet half drained, the tank refills it.
- `test_a_pump_moves_one_tank_into_another`: two tanks on one network keep their litres for 100 ticks; a powered pump between two networks moves 20 L a tick from the first tank to the second; unpowered, nothing.
- `test_gas_and_liquid_move_alike`: steam to an engine's inlet and water to a boiler's at the same litres a tick.
- `test_a_port_refuses_to_mix_fluids`: a water tank placed before a boiler, piped to its steam outlet: the outlet closes, one refusal over five ticks, the tank keeps its water; the tank emptied by hand, the netlist takes steam and the tank fills with it.
- `test_a_netlist_keeps_its_fluid_while_an_open_port_holds_it`: a water line (tank, boiler inlet) joined by a new pipe to a later boiler's steam outlet stays water and closes the outlet; with the tank emptied it stays water while the inlet holds some; a save and load midway gives an equal hash after 300 ticks.
- `test_a_flare_takes_only_what_is_left`: a refinery's gas outlet holding 200 L, a combustion generator's inlet and an unpowered flare on one network: the flare gets nothing until the generator's inlet is full.
- `test_rounding_never_stalls_a_water_line`: a powered offshore pump and 24 boilers' inlets on one line: 20 L move every tick until every inlet holds 200, after 240 ticks.
- `test_a_boiler_line_runs_at_its_rate` (chapter 4's line): a powered offshore pump, a boiler with 20 coal, its steam piped into a tank: after 120 ticks, over the next 600 the boiler is Producing every tick and the tank gains 600 L.
- `test_an_oil_line_runs_at_its_pumps_rate` (chapter 6's line): two powered tar pit pumps piped to a powered refinery, its three outlets piped to three tanks, `tick_assemblers` then `tick_fluids` each tick: after 600 ticks, over 6,000 the pumps are never Output_Full, 2,000 L of crude are produced, the refinery makes 20 crafts (19 or 21 where the window cuts one), and each fraction's tank and outlet hold 45, 30 and 25 L per craft finished. Marked slow if it takes 1 s.
- `test_fluid_networks_rebuild_after_removing_a_middle_pipe`: one netlist, then two.
- `test_touching_tanks_close_a_loop_that_carries_nothing`: two tanks touching each other and one pipe to a boiler's inlet: one chord, the litres conserved over 100 ticks.
- Kept, with tanks for pipes where needed: the machine tests, `test_offshore_pump_fills_a_tank_to_its_capacity`, `test_fluid_simulation_is_deterministic`, `test_fluid_throughput_does_not_depend_on_direction`.

Elsewhere:
- `oil_test.odin`, `chemistry_test.odin`, `combustion_test.odin`, `deep_mining_test.odin`, `ore_processing_test.odin`, `save_test.odin`: pipe litres become tanks, `networks.networks` becomes `fluid_netlist_count`, `test_fluid_network_of` calls `fluid_netlist_of`; expected outcomes stay.
- `test_an_old_save_drops_its_pipe_litres` (`save_test.odin`): a block world whose pipes hold litres saved and loaded: the pipes hold none, `drop_pipe_litres` counted them and `pipe_litres_line` names the count, the ports keep theirs; saved and loaded again to an equal hash.
- `test_factory_benchmark` passes unchanged: its power and oil modules stand on frame 0.

### Docs

- `doc/fluids.md`: the intro's fluid bullet; "Fluid networks" becomes "Fluid netlists" (decisions 1, 3 to 6, 8, 10, joints, the top-up); "Height and pump head" goes; Fluid machines: the pump (decision 2), the tank as a store, the flare as a relief, the offshore pump, the rendering line.
- `doc/README.md`: fluids.md's line names the netlists. `doc/quests.md`, chapter 6: "A pump and a tank".
- `doc/architecture.md`, Frames: the fluid netlists join on frame 0 only (0356), in place of "pipes connect by cell across frames".
- `doc/code_map.md`: `fluid_network.odin` as the fluid netlists, the netlist cluster naming 0356, the counts the checks report.
- `DESIGN.md`, Logistics: "what moves it is the netlist's" names the producers, the tanks and the pump.
- `doc/content.md`: nothing there states a height; unchanged.

### Hand-back check

- Memory a frame draws from: the topology and arrays change only in rebuilds and ticks; panels and the draw read the pools' buffers.
- Writes: none. Start-up loads: two machine keys leave; an overlay naming them is ignored as any unknown machine key is.
- Rates: litres move whole; the top-up hands out what the per mille rounding leaves, so nothing is lost or made and no line stalls. The pump's truncated rate is question 5.
- Save layout: unchanged but the empty fluids list; old pipe litres dropped with one line.
- Shared budget: tanks and the flare charge only from what the producers leave after the consumers; the pump's inlet is an ordinary consumer.
- Audit: the pump panels lose the head row; every machine panel case stays.
- Tests use temporary worlds only.

### Questions to the main agent

1. The split. A: this item, after 0355 A, independent of 0361, 0362 and 0368. B (new, after 0368, 0362 and 0361 A): hand run pipes on the field, a fluid junction, fluid ports in 0361's `ports` key on the factory's machines (0368 refuses them until then), `machine_port_is_linked` for fluid ports, the pipe run tool between belt poles removed. C (new, after B and 0365): a vessel tank's contents against `stores_litres` as a store, pipes across a docking connector, `frame_is_tied` by a pipe, wet mass in `Vessel_Figures`; then the rocket stage.
2. **Proposal, the user may overturn: on the field every pipe is run by hand port to port as a cable is, on the ground and on vessels alike; placed pipe pieces stay only in the block world, which M14 removes.** Hand run: one model for power, fluids and vessels, as in "everything is hand run" and "keep the cables for power and fluids"; 0368's table (two port ends, an item, metres), run, take up, span, sag and draw serve a pipe item; a fluid junction branches; loops are refused as for cables. Placed pieces on frames: per frame joints are cheap (A's lookup by the frame), but pipes between frames need the belt poles' runs to carry fluid (a look only today), vessels still need hand runs, and there are two models to teach and keep. The netlist takes either: B adds the edges of its table to A's joints. B needs the cable's control design with a pipe item held: does it apply unchanged?
3. The top-up's leftover goes to the first consumers in node order, so in a lasting shortage of fewer litres a tick than consumers, the last ones of a line starve while the first run. Chosen over a rotation, which needs per port state saved.
4. On the field the offshore and tar pit pumps are placed with no source check and make fluid from nothing, where DESIGN has a pump empty a pond. The boundary is a machine's tick (decision 9); an intake on the field's water bodies is its own item.
5. The electric pump's `rate × satisfaction / POWER_FULL` truncates (the hand-back rate line), losing up to a litre a tick. Unchanged here; a follow-up crediting it as the offshore pump does?
6. "The dev kits' fluid lines" are read as chapter 4's boiler line and chapter 6's oil line built in tests (the kits carry items only), with the benchmark's modules through `test_factory_benchmark`.

### Decisions (main agent, 2026-11-11)

1. The split is accepted. This item is part A (the block world's and frame 0's pipes on the netlist, the pump as a link, the top-up). Part B (hand run pipes on the field, fluid ports in 0361's `ports`, the pipe run tool removed) is 0374; part C (vessel tanks, pipes across docking, wet mass) is 0375. Both are implemented from this specification.
2. Order: after 0355 and after 0373. A joint's 20 L a tick makes limiting edges the common case in pipes, which is where 0373's defect bites; this item is not started on the solver as it stands.
3. Question 1: the proposal (every field pipe run by hand, port to port, as a cable) stands as the main agent's, the user may overturn it, and 0355's control design applies unchanged with a pipe held. It is put to the user before 0374 starts.
4. Question 2: accepted, named in the log at the landing: the top-up's leftover litres go to the first consumers in node order.
5. Question 3: the field's pumps that draw from nothing are 0376.
6. Question 4: the electric pump's rate accumulates credits in this item, since the pump is rewritten here.
7. Question 5: agreed.
8. `DESIGN.md`'s pipes on poles and `doc/architecture.md` line 145 are corrected in this item's docs.

### Decisions (main agent, 2026-11-13, at the start)

1. Started on `main` of 2026-11-13, two days after the design: `src/netlist/solve.odin` is 0373's pool now (0355's `bound_flows_by_levels` plan and `add_clamped_response` are gone), stores exist in play (0383's batteries), and power runs on cables (0368). Decision 7's reuse holds for the interface (`Edge`, `Topology`, `build_topology`, `Node_Input`, `Node_Output`, `solve`); where this specification names something inside the solve that no longer exists, the implementer follows `main` and names it as a deviation.
2. The top-up (decision 6) is added beside the solve's phases and changes nothing inside 0373's pool or the repair, which 0390 and 0389 are about to change in the same file.

### Deviations (implementation, 2026-11-13)

1. The top-up reads the `Phase` 0373 left as the specification assumes (`lower` and `upper` as they stand, the direction rule's after `bound_flows_by_levels` on the slow path, `phase_children`, `tree_flows`), so nothing in it is renamed. It lives in a file of its own, `src/netlist/top_up.odin`, with its tests in `src/netlist/top_up_test.odin`; `solve.odin` gains only the `top_up` parameter of `solve`, `solve_tree` and `solve_phase`, its two calls and the header's line, and `netlist_test.odin` is untouched, so 0389 and 0390 meet nothing of this item in those files. The determinism check of the top-up is `test_top_up_is_deterministic` there, in place of a second solve in `test_solve_is_deterministic`.
2. 0351 is not on `main`: there is no `wake_all_entities` to keep first in `rebuild_fluid_networks`.
3. The game package's `union_find_root` is the fluid code's alone (power's union find is the netlist package's own since 0355); it is kept for the junctions.
4. Joints are found through every node's positive faces only, as today's connections are: "each frame 0 port's positive faces and each pipe's six" would meet a port and a pipe twice (the port's positive face and the pipe's face back) and carry 40 L where the item says 20.
5. The flare's port, a store offering 0, would charge in the solve's second phase beside the tanks, each by its share of the room (the stores' phase since 0383), not after them. Decided by the main agent (2026-11-13): the flare stays a relief valve, on the fluid side with no change in `src/netlist/`: a flare's port gets charge room only while no open storage tank port on its netlist has room, read from the buffers before the solve (`netlists_with_tank_room`, `relief_room`); when the tanks' last room is smaller than the leftover, the rest backs up for a tick and the flare opens on the next. It does not open while a tank with room has its joint saturated by the litres passing through it: the producers stay backed up for as long as that lasts (accepted at the review, docs only). No saved field. Test: `test_a_flare_opens_only_when_the_tanks_are_full`.
6. `fluid_netlist_count` counts every tree, a port with no joint included, as `test_touching_pipes_are_one_junction` reads (the boiler's outlet alone is the second netlist).
7. A test whose seeded pipe fed a tank (`test_storage_tank_holds_gas`) gets a producer's port in its place, not a second tank, since two tanks never exchange. `test_flare_stack_relieves_only_a_full_network` relied on a tank draining into a flare and now holds the new rule. Expected values that counted litres in pipes follow: the throughput test's 1258 ticks become 1238 (24,750 L at 20 L a tick from the first tick), and the tank test's last pipe holds 0.
8. `test_oil_simulation_is_deterministic` expects 135 L of gas, not 90: the tar pit pump's first 100 L of crude reach the refinery instead of filling its three pipes, so it makes a third craft in the 1200 ticks. Its other expectations hold.
9. `test_combustion_generator_port_refuses_steam` gets a tank of steam for its pipe of steam, as the specification's Elsewhere says, with its outcomes kept; `power_test.odin`'s pipe reset in `test_fuel_generator_only_covers_what_the_engines_cannot` stays as it was, harmless on a pipe that holds nothing, so no power test changes.
10. `DESIGN.md`'s pipes on poles (decision 8) now read as the user's answer in the log of 2026-11-11: every pipe on a planet is run by hand ("by hand yes", 0374). `SUGGESTIONS.md` loses the pump heads and the electric pump's truncation, both gone with this item.
11. `test_factory_benchmark` found the power module's second boiler and its offshore pump idle: both boilers' outlets are producers of order 0 on one steam netlist whose engines ask a litre or less a tick, and the solve's dispatch splits an order in proportion to the offers with the leftover in node order, so the first boiler serves it all and the second's outlet stays full (Output_Full), its pump's too. The old model's evening of fill fractions drained both. Decided by the main agent (2026-11-13): such a producer stands by, as a generator does. `benchmark_factory.odin`'s idle rule counts a boiler, offshore or tar pit pump in Output_Full and an electric pump idle with its output full as standing by (`fluid_producer_is_standing_by`); the blueprint, the dispatch and the orders stay.

### Fix round (main agent's decisions at the review, 2026-11-13)

1. Decision 4's order changes: of the ports holding litres, the first in node order among the open output and tank ports, else among the closed ones, else among the open input ports (`fluid_claim_rank`), so a feeding port holding litres outranks every inlet. Under the old order an unpowered pump's inlet holding 5 L of water, piped onto a gas line, closed the gas tank and the generator for good; ranking open inlets above closed feeders (the first fix round) still did on a line with no tank, where on most ticks no feeder holds litres. Tests: `test_an_inlet_holding_another_fluid_does_not_decide_its_netlist`, `test_a_held_inlet_never_stops_a_tankless_line`. `test_a_netlist_keeps_its_fluid_while_an_open_port_holds_it` follows: with its water tank emptied, the closed steam outlet takes the line from the boiler inlet still holding water.
2. The pipe's band draws while its netlist carries a fluid (`pipe_shows_band`), not while `flow_in > 0`, which blinked at 10 Hz on a tar pit line. Its panel shows the litres of the last full second (`pipe_litres_last_second`), summed per pipe slot in `Fluid_Networks.pipe_seconds`, kept across rebuilds and never saved or hashed; `tick_fluid_networks` and `show_pipe_flows` take the tick rate for the second's length. Test: `test_a_slow_line_shows_a_steady_pipe`.
3. Decision 6's leftover goes out in the walk's pre-order from the netlist's lowest node, children in node order, not to the first consumers in node order.
