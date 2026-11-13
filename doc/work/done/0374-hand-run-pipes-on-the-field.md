# 0374: Hand run pipes on the field

Status: landed (2026-11-13, 1bfd604b)

Part B of 0356's specification (`doc/work/0356-the-pipes-netlist.md`): on the field every pipe is run by hand from port to port as a cable is (the user, 2026-11-11: "by hand yes"), a fluid junction, fluid ports in 0361's `ports` key, `machine_port_is_linked` for fluid ports, and the pipe run tool between belt poles removed.

## Goal

A fluid connection on a planet or a vessel is a pipe the player runs by hand.

## Controls

0355's control design with a pipe item held, unchanged.

## Change

- As the specification below. After 0356, 0368, 0362 and 0361.
- Not started before the user has seen the proposal.

## Verify

- The checks and the suite.
- Captures of a boiler line run by hand, sent to the user.

## Specification (design, 2026-11-13)

Self-contained: the implementer needs neither 0356 nor 0368's item. Every name below that is not new exists on `main`.

### 1. The seam: one table for cables and pipes

- A pipe is a record in `Entities.cables` (`Cable_Table`, cable.odin), a pipe because its item is a pipe item. 0368's run, aim, take up, pick up return, draw, drain, save and hash paths serve both. The names stay (`Cable`, `Cable_Table`, `cable_*`, `Field_Placement.Cable` and `.Cable_Removal`, `Field_Player.cable_run`, `cable_start`, `cable_slot`, `cable_take_up`, `cable_take_up_ticks`).
- Rejected: a `Pipe_Table` beside it. It is another saved table with its own block world mark and read order (the dance 0368 needed for one), and a copy of the aim, take up, drain, pick up and draw code for what is the same mode with another item held. One run is carried at a time either way.
- `Cable_Table.watts` becomes `capacity: [dynamic]i64` (watts for a cable, litres a second for a pipe) and gains `kinds: [dynamic]Machine_Port_Kind`. Both are derived, kept in step by `add_cable`, `remove_cable_record` and `settle_cables`, never written. The save layout is unchanged: `write_cable_table` writes `cables` only.

### 2. Pipe items (item.odin, data/items.sjson)

- `Item_Definition` gains `pipe_litres_per_second`, `pipe_span_metres`, `pipe_thickness_millimetres` (int) and `pipe_color` ([3]int); `Item` gains them as u32, u16, u16 and [3]u8, filled where the cable keys are (item.odin:363).
- `validate_pipe_item :: proc(definition: Item_Definition) -> string`, called right after `validate_cable_item`: all four keys or none ("pipe %q needs all of pipe_litres_per_second, pipe_span_metres, pipe_thickness_millimetres and pipe_color"); `pipe_litres_per_second` from `MINIMUM_PIPE_LITRES_PER_SECOND :: 60` (a litre a tick at 60 Hz) to `MAXIMUM_PIPE_LITRES_PER_SECOND :: 1_000_000`; `pipe_span_metres` 1 to `MAXIMUM_CABLE_SPAN_METRES` and at most `stack_size`; `pipe_thickness_millimetres` from `MINIMUM_PIPE_THICKNESS_MILLIMETRES :: 20` to `MAXIMUM_PIPE_THICKNESS_MILLIMETRES :: 400`; `pipe_color` passes `foundation_color_is_valid`; an item with cable keys and pipe keys is refused ("item %q cannot be both a cable and a pipe"). Messages follow `validate_cable_item`'s.
- `item_is_pipe :: proc(registry: Item_Registry, item: Item_Id) -> bool` (`pipe_litres_per_second > 0`, bounds checked as `item_is_cable`); `item_is_line` (either).
- `Line_Figures :: struct {kind: Machine_Port_Kind, capacity: i64, span_metres: i64, thickness_millimetres: int, color: [3]u8}` and `item_line_figures :: proc(registry: Item_Registry, item: Item_Id) -> (figures: Line_Figures, found: bool)`: a cable's (`.Power`, kilowatts × 1000) or a pipe's (`.Fluid`, litres a second). Every reader of the cable keys outside item.odin goes through it.
- Shipped: the `pipe` item keeps its id, category, stack 100, price 2 and recipe (1 iron plate makes 1) and gains `pipe_litres_per_second = 1200, pipe_span_metres = 20, pipe_thickness_millimetres = 150, pipe_color = [110, 112, 118]` (the block pipe's flow and `PIPE_COLOR`). One item is one metre. In the block world it still places the pipe block.

### 3. Fluid ports in `ports` (machine_ports.odin, power_machine.odin, machine.odin, data/machines.sjson)

- `Machine_Port` gains `fluid_buffer: i8`, derived: for a fluid port the index into the machine's `fluid_ports` of the buffer it meets (one of the same cell and face, else the first `every_face` one); -1 for a power port, a vessel part's fluid port and a fluid junction's port.
- `link_fluid_ports_to_buffers :: proc(machine: ^Machine, id: string) -> string`, called in `resolve_machine_registry` right after `resolve_fluid_ports` (machine.odin:1568) when that returned no problem: sets `fluid_buffer`; outside the vessel kinds and the fluid junction, a fluid port that meets no buffer is refused ("machine %q fluid port %q meets none of its fluid_ports"). A buffer without a port stays allowed (the block world joins it by face); the shipped data test below requires every field fluid machine's buffers covered.
- `validate_power_ports_of_kind` becomes `validate_ports_of_kind`, its comment rewritten. Outside the vessel kinds a fluid port is allowed on a record with `fluid_ports` or on a fluid junction, else "machine %q port %q is a fluid port, which only a machine with fluid_ports, a fluid junction or a vessel part may list". The existing rules count power ports only: an electric machine or generator one power port, at index 0, of at least the rating (message kept); a junction box 2 to 8 power ports and no fluid port; a power switch exactly 2 power ports and no fluid port; any other kind no power port (the `count > 0` message kept). A fluid junction 2 to `MAXIMUM_MACHINE_PORTS` fluid ports and no power port ("fluid junction %q needs 2 to %d fluid ports and no power port").
- `machine_port_takes_line :: proc(machine: Machine, port: int) -> bool` (power_machine.odin beside `machine_port_is_power`): a power port, a fluid port with `fluid_buffer >= 0`, or any port of a fluid junction.
- Shipped ports, appended after each record's existing power port so the indices of saved cables stay, every one `kind = "fluid"`, `capacity_litres_per_second = 1200`, on the cell and face of the buffer it meets. The boiler and the storage tank gain a `ports` key.

| Record | Ports (id, cell, face) |
|---|---|
| electric_mining_drill, bore_drill | `revival` (0,0,1) negative_x |
| offshore_pump | `out` (0,0,0) negative_x |
| boiler | `in` (1,0,0) negative_z; `out` (1,0,1) positive_z |
| steam_engine | `in_a` (1,0,0) negative_z; `in_b` (1,0,4) positive_z |
| storage_tank (every face buffer) | `a` (1,0,0) negative_z; `b` (2,0,1) positive_x; `c` (1,0,2) positive_z; `d` (0,0,1) negative_x |
| pump | `in` (0,0,0) negative_x; `out` (1,0,0) positive_x |
| tar_pit_pump | `out` (0,0,0) negative_x |
| flare_stack (every face buffer) | `in` (0,0,0) positive_x |
| combustion_generator, washer | `in` (1,0,0) negative_z |
| refinery | `crude_in` (2,0,0) negative_z; `gas_out` (0,0,2) negative_x; `light_out` (2,0,4) positive_z; `heavy_out` (4,0,2) positive_x |
| cracking_unit | `oil_in` (1,0,0) negative_z; `water_in` (0,0,1) negative_x; `out` (1,0,2) positive_z |
| chemical_plant | `gas_in` (1,0,0) negative_z; `in` (0,0,1) negative_x; `out` (1,0,2) positive_z |
| wood_gasifier | `gas_out` (0,0,1) positive_z |
| launch_pad | `fuel_in` (4,0,0) negative_z |

The four tank ports meet one buffer, so they are one node: two pipes from one tank to one junction bundle.

### 4. The fluid junction

- `Machine_Kind.Fluid_Junction`, name `fluid_junction`, appended to the enum and its name table; its entities live in the `poles` pool (add_entity's case beside `.Junction_Box, .Power_Switch`, entity.odin:697). No power port, so no power node. Every complete switch on `Machine_Kind` the compiler names gains the case beside the junction box's.
- Record `fluid_junction`: footprint 1 by 1 by 1, `stands_on_ground = true`, `color = [70, 104, 140]`, ports `a` negative_x, `b` positive_x, `c` negative_z, `d` positive_z, all fluid at (0,0,0), `capacity_litres_per_second = 24000`; no `fluid_ports`, no model: `draw_pole`'s fallback box in its colour draws it. `validate_fluid_machine_definition` requires the colour for the kind as `validate_power_machine_definition` does for the junction box. Its model is a sealed lab item the main agent writes, as 0387 for the junction box.
- Item `fluid_junction` (category machine, stack 100, price 6, `item_fluid_junction`, `describe_item_fluid_junction`); recipe 2 iron plates and 2 pipes make 1, 0.5 s, hand and assembler, category logistics, tags fluid, channel start.
- `machine_touches_fluids :: proc(machine: Machine) -> bool`: kind pipe, fluid ports, or fluid junction. add_entity's rebuild (entity.odin:727) uses it; remove_entity's `.Pole` case rebuilds the fluid netlist after `pool_remove` when it is true. remove_entity's existing fluid rebuilds then cover every pipe `remove_entity_cables` drops, since every pipe end has fluid ports or is a fluid junction.

### 5. Running a pipe (cable.odin, cable_field.odin, simulation_field.odin, player_field.odin)

- `Field_Held_Tool`: `Pipe_Run` deleted, `Pipe` appended. `field_tool_for_item` returns `.Pipe` for `item_is_pipe` right after its cable check and before the machine lookup; the branch turning the pipe machine into `.Pipe_Run` goes. `field_tool_line_kind :: proc(tool: Field_Held_Tool) -> (kind: Machine_Port_Kind, runs: bool)`: `.Cable` power, `.Pipe` fluid. Every `.Cable` tool check (cable_field.odin:44 and 61, hud.odin:913, 915 and 1269, the `field_held_tool_*` switches) reads it; complete switches get `.Pipe` beside `.Cable`.
- Generalised in cable.odin, old name to new:
  - `power_port_point` → `port_end_point(entities, machines, end) -> (point: World_Position, found: bool)`: any port of a live entity's machine. `port_span_metres` and `cable_run_line` call it.
  - New `port_end_kind(entities, machines, end) -> (kind: Machine_Port_Kind, found: bool)`.
  - `port_end_is_free`: a live entity's port that `machine_port_takes_line` and holds no record.
  - `free_power_port_nearest` → `free_port_nearest(entities, machines, handle, point, kind: Machine_Port_Kind) -> (port: int, found: bool)`: free ports of that kind only.
  - `field_aimed_free_port(entities, machines, body, kind)`; `update_field_cable_tool` and `queue_field_cable` pass the held tool's kind.
  - `cable_placement_refusal`: an item `item_line_figures` does not find refuses as `Cable_Too_Short` before the ends (only a malformed request reaches it); then, in the existing order, the first end not free or not of the item's kind is `Cable_End_Gone`, the second likewise `No_Free_Port`, then `Same_Thing`, the span against `figures.span_metres` (`Cable_Too_Short`), `Not_Enough_Cable`, the vessel connector rule unchanged.
  - `cable_watts` → `cable_capacity(content, entities, cable) -> i64`: the least of the figures' capacity and both ports' capacity.
  - `cable_ports_are_power` → `cable_ports_take_item(entities, content, cable) -> bool`: both ports take lines and are of the item's kind.
  - `add_cable` and `remove_cable` rebuild the netlist of the record's kind (read before the record leaves): `rebuild_electric_networks` or `rebuild_fluid_networks`.
  - `settle_cables`: `item_is_line` and `cable_ports_take_item` decide the drop; derives `capacity` and `kinds`. Its log lines in `read_cable_table` name "cables and pipes".
  - `drain_field_cable` counts `statistics.cables_run` for a cable only.
- Power side: `cable_edges` skips a record whose kind is not power; `cable_load` returns not found for one. `network_limiting_cables` and the power panels then never meet a pipe.
- Lockstep: unchanged in kind. The run's begin, end and take back stay player state set from the input frame; the laid pipe and the taken up pipe are `Field_Placement.Cable` and `.Cable_Removal`, drained and checked again in player order. No new command, no new saved field; the state hash covers the table as before. `Developer_Request.Place_Cable` validation (player_command.odin:608) and the blueprint check (benchmark_factory.odin:210) use `item_is_line`. Touch: `cable_held` (touch_overlay.odin:1850) uses `item_is_line`, so a tap presses Place with a pipe held as with a cable.

### 6. The netlist (fluid_network.odin, fluid_machine.odin)

- Topology capacities become litres a second. A block world joint's edge carries `block_joint_litres_per_second :: proc(machines: Machine_Registry) -> i64` (the pipe machine's `flow_litres_per_second`, 0 without one), replacing `pipe_flow_per_tick`; a pipe record's edge carries its `capacity`. Parallel edges bundle as now. `scale_fluid_capacities(networks, tick_rate: int)`: `capacity[node] = topology.capacity[node] / tick_rate`, floored after bundling, `connection` as now; `scaled_limit` becomes `scaled_tick_rate`. `tick_fluid_networks` drops its `limit` parameter (fluid_machine.odin:326). Block world flows stay 20 L a joint a tick at 60 Hz.
- Nodes: the ports in pool and port order as now, the block junctions, then one node per live fluid junction in pole pool order (`collect_fluid_junctions`), `port = -1`, owner the junction. `junction_of_pipe` becomes `junction_of`, holding block pipes and fluid junctions; `fluid_node_of(networks, owner, -1)` serves both. A fluid junction holds nothing (`fluid_node_buffer` is nil for `port < 0`).
- `pipe_end_node :: proc(networks: ^Fluid_Networks, entities: ^Entities, machines: Machine_Registry, end: Port_End) -> int`: a fluid junction's node, else `fluid_node_of(networks, end.entity, port.fluid_buffer)`, -1 otherwise.
- `pipe_edges :: proc(networks: ^Fluid_Networks, entities: ^Entities, machines: Machine_Registry) -> []netlist.Edge` (temp allocator): one edge per fluid record whose two ends have nodes, appended after `fluid_joint_edges` in `rebuild_fluid_networks`. A pipe holds nothing. A loop of pipes is laid and its chord carries nothing until 0377.
- `pipe_record_litres(networks, table: ^Cable_Table, entities, machines, index: int) -> i64`: the pipe's share of its bundle's flow this tick, as `cable_load` takes it (`cable_tree_child`, `abs(outputs[child].flow) × capacity[index] / topology.capacity[child]`), 0 for a chord or an end without a node.
- `Pipe_Line_Second :: struct {end: Port_End, running, last: i64}` and `Fluid_Networks.pipe_line_seconds: [dynamic]Pipe_Line_Second`, indexed by table index; an entry whose `end` is not the record's `ends[0]` starts afresh (a removal moves the last record into the gap). `show_pipe_flows` counts every fluid record's litres; `roll_pipe_seconds` rolls them with the block pipes'. `pipe_line_litres_last_second(networks, table, index) -> i64`. Presentation only, never saved or hashed, kept across rebuilds as `pipe_seconds` is.
- `pipe_record_fluid(networks, table, entities, machines, index) -> Fluid_Id`: its tree's netlist fluid, `NO_FLUID` without a node.
- Block world pipes, their joints by face on frame 0 and their bands are unchanged.

### 7. The pipe run between belt poles removed (belt_run.odin, belt_run_placement.odin, render_belt_runs.odin)

- Deleted: `Belt_Run_Kind`, `Belt_Run.kind`, `Field_Run_Placement.kind`, the `kind` parameters of `belt_run_endpoint_taken`, `belt_pole_fixed_facing`, `belt_pole_refusal`, `belt_run_endpoint_refusal`, `belt_run_refusal`, `add_belt_run`, `belt_pole_endpoint`, `belt_run_options`, `field_run_candidate`, `belt_run_candidate_endpoint`, `plan_belt_run`; `Field_Content.run_pipe`; `draw_pipe_run`, `PIPE_RUN_RADIUS_SHARE`, `PIPE_RUN_SIDES` and the switch on the run's kind in render_belt_runs.odin. `field_run_tool` returns `(machine: Machine_Id, found: bool)`. `belt_run_in_lines` is `run.alive`. `add_belt_run`, `remove_belt_run` and `drain_field_run_placement` rebuild lines and record the placement unconditionally. loop_planet_preview.odin and loop_planet_preview_runs.odin follow.
- Old saves: `Belt_Run.kind` in the file is a field the type no longer has, skipped by the codec. `drop_pipe_runs :: proc(entities: ^Entities, machines: Machine_Registry) -> int` (belt_run.odin) removes every live run whose machine is not of kind belt with `pool_remove` and returns the count; `read_simulation_state` calls it after `drop_pipe_litres`, before `rebuild_loaded_world`, and logs `pipe_runs_line(count)`: "save: removed %d pipe runs between belt poles, which carried no fluid; pipes are run by hand from port to port since 0374". The poles stay. A pipe run ended only on poles (belt ends were offered to belt runs alone), so no frame is left empty. A run took no item, only its new poles, so nothing is owed. A saved `Field_Player.tool` of `Pipe_Run` reads as `Material` and is derived again on the first tick.

### 8. Drawing (render_cables.odin)

- `cable_draw_points` uses `port_end_point`; `cable_look` and `cable_run_look` use `item_is_line` and `item_line_figures` (span, thickness, colour); `cable_draw_color` takes the base colour instead of the item; `cable_thickness_metres` takes the figures.
- `cable_down_and_sag` gains `kind: Machine_Port_Kind`: a fluid record sags 0, so a pipe runs straight from port to port (`cable_side_axis` already serves a straight curve). The carried run's look past the span keeps `BELT_RUN_REFUSED_COLOR`.

### 9. HUD, panel and strings

- HUD, aimed record (hud.odin:792): a fluid record's line is `pipe_status_text(entities, machines, items, fluids, index, tick_rate) -> string` (ui_fluid.odin), `fluid_pipe_load`, in the text colour; a cable's is unchanged. Held: `held_glyph_hints` shows `hint_run_pipe` with a pipe held and no run, `hint_connect` and `hint_take_back` during a run as for a cable; `field_tool_line` serves `.Pipe` as `.Cable` (`cable_run_line` with `item_is_line` and the figures' span). Aimed fluid junction: `entity_status_text`'s `.Pole` case gives `fluid_junction_status_text(world, machines, fluids, handle, name) -> string`, "{name}  {fluid}" with its netlist's fluid.
- Panel: `fluid_junction_area_size() -> [2]f32` and `fluid_junction_panel_region(state, area, handle, screen_context)` (ui_fluid.odin), routed from `machine_area_width`, `machine_area_height` and `machine_slot_region` (ui_machine.odin:435) by the machine's kind before the `.Pole` power branch: the netlist's fluid, then one line per port (at most 8), `fluid_port_free` dim or `fluid_port_out` and `fluid_port_in` by the last second's flow. Other machines' panels are unchanged (their buffer lines already show the flow).
- Strings, data/strings/en.sjson. New: `item_fluid_junction` and `machine_fluid_junction` "Fluid junction"; `describe_item_fluid_junction` and `describe_machine_fluid_junction` "Four ports. Joins and branches pipes."; `hint_run_pipe` "Run pipe"; `fluid_pipe_load` "{pipe}: {fluid}, {flow} of {capacity}" (both rates through `format_second_litres_per_minute`); `fluid_port_free` "Port {port}: free"; `fluid_port_out` "Port {port}: {flow}, {pipe} to {peer}" and `fluid_port_in` with "from". Changed: `describe_item_pipe` "One iron plate rolled into a metre of pipe. Run it by hand from one fluid port to another, up to 20 m a span; it carries 1200 litres a second."; `describe_item_belt_pole` "A post a belt hangs from. Place it, aim at the next and place again: the run between them curves by itself."; `describe_machine_belt_pole` "Belts run between poles, inclining or turning but never both at once."; `field_refused_no_free_port` "No free port for it there"; `field_refused_same_thing` "Run it to a second thing"; `field_refused_cable_too_short` "Too long for one span"; `field_refused_not_enough_cable` "Not enough held for the span"; `field_refused_cable_end_gone` "The run's first end is gone"; `quest_steam_text`'s "a boiler fed by it and a steam engine fed by the boiler" becomes "a boiler piped from it and a steam engine piped from the boiler". The planet preview's refusal texts (loop_planet_preview.odin:529 to 540) follow the same wording; `field_held_name` gives `.Pipe` "pipe, run carried" or "pipe".

### 10. Developer command (command.odin, command_field.odin, developer.odin)

- `cable` takes a pipe item: `command_cable_request` refuses with `"%q is not a cable or pipe item"` for an item that is no line; `command_cable_port` looks the port id up among the ports of the item's kind, `"the %s at %d %d %d has no %s port %q"` with `power` or `fluid`. The answer stays `ok cable <item> <metres> m`. `place_cable_for_developer` counts `cables_run` for a cable only. No `pipe` alias.
- `machine_port_is_linked` is not added: 0368 left it to 0365 and 0357 and no stub exists on `main`. Whoever adds it answers both kinds with `port_end_cable(&entities.cables, end) >= 0`.

### 11. Dev kits (data/dev_kits.sjson)

`pipe` 60, 100, 200 and 200 in the chapter 4 to 7 kits (from 20, 50, 100, 100), and `fluid_junction` 4, 6, 10 and 10 in the same kits, so the chapters' fluid lines can be run by hand at 20 m spans.

### 12. Tests

New:
- `test_shipped_fluid_ports_resolve` (cable_test.odin): every non-vessel record with `fluid_ports` has a fluid port in `ports` meeting each buffer; the table of section 3 resolves (spot check boiler `out` at index 1 with `fluid_buffer` 1, a tank's four ports all `fluid_buffer` 0); the fluid junction has 4 fluid ports and no power port.
- `test_malformed_pipe_items_and_fluid_ports_are_refused`: a pipe item missing a key, litres 59 and 1,000,001, span 0 and above the stack, thickness 19 and 401, an all zero colour, cable and pipe keys together; a fluid port meeting no buffer; a fluid port on a lamp; a fluid junction with one port and with a power port; a junction box with a fluid port. Each refused with its message.
- `test_a_hand_run_boiler_line_runs_at_its_rate` (fluid_test.odin): on a field test pad, a powered offshore pump (satisfaction set as `place_powered_offshore_pump` does), a boiler with 20 coal, a storage tank, pipes pump `out` to boiler `in` and boiler `out` to tank `a`; after 120 ticks, over 600 ticks the boiler produces on all 600 and the tank gains 600 L.
- `test_a_pipe_carries_its_capacity_a_tick`: a full water tank, a fluid junction and three boilers without fuel on a field pad; one pipe tank to junction and one junction to each boiler: the boilers gain 20 L together in a tick; a second pipe tank to junction: 40 L the next tick, and the junction's edge reads 2400 L/s in the topology.
- `test_a_fluid_junction_branches_a_line`: pump to junction to three boiler inlets; after 30 ticks every inlet holds 200 L.
- `test_field_pipe_run_controls` (cable_test.odin, as `test_field_cable_run_controls`): with a pipe held, Place on a boiler begins a run on its free fluid port nearest the aimed face, Place on a tank lays it and takes the span's metres, Mine takes a run back, a slot change ends it, Place on a lamp refuses `No_Free_Port`, a power port never starts a pipe run and a fluid port never a cable run.
- `test_taking_up_a_pipe_returns_its_metres`: Mine held for `PICK_UP_SECONDS` on an aimed pipe returns its metres; picking up a fluid junction returns the junction and its pipes' metres and rebuilds the fluid netlist.
- `test_a_pipe_is_straight_and_a_cable_sags`: `cable_down_and_sag` gives 0 for a fluid record and the cable's sag for a power one between the same two points.
- `test_cables_and_pipes_share_the_table_but_not_the_netlists`: a pump with a cable on its power port and a pipe on its `out`: the table holds both with kinds power and fluid; `cable_edges` has one edge, `pipe_edges` one; `cable_load` of the pipe is not found.
- `test_pipes_save_and_load` (save_test.odin): a field world with two pipes and a junction saves and loads to the same table, capacities, kinds and state hash.
- `test_old_saves_lose_their_pipe_runs` (save_test.odin): `lay_save_test_runs` plus a run of the pipe machine between the second and third pole added with `pool_add` (as an old save holds it): after the round trip one run is left, the three poles stand, the belt run's plates stand on it, and `drop_pipe_runs` on the saved world returns 1.
- `test_the_cable_command_lays_a_pipe` (command_test.odin): `cable pipe <frame> ... in ... a` answers `ok cable pipe <metres> m`; a power port id with a pipe answers the fluid port error; a cable item onto a fluid port id answers the power port error.
- `test_a_pipe_netlist_is_deterministic`: the same pipes laid in two orders give the same flows tick for tick and the same state hash.
- `test_fluid_junction_panel_lines`: the junction's panel lines with two ports piped and two free, the pipe's HUD line with its fluid, flow and capacity.

Updated: `test_shipped_power_ports_resolve` counts power ports (`machine_power_port_count`) where it counted `port_count`; `test_fluid_data_loads` asserts `block_joint_litres_per_second` 1200 in place of `pipe_flow_per_tick` 20; `lay_save_test_runs` lays the belt run only and `belt_runs_loaded` expects one run and drops the kind compare; belt_run_test.odin drops `kind`; world_chunk_test.odin:123 and save_test.odin:1180 read `capacity` (and `kinds`).

### 13. UI audit (ui_audit_test.odin)

The fluid junction gets its `machine fluid_junction` case from `place_missing_machines`. New: `fluid junction with pipes` (two ports piped with flow, two free) and `hud field pipe held` (a run carried, as the cable's held case). The reworded refusal toasts come through `hud field refusals`. No case becomes obsolete: the pipe run tool had none.

### 14. Docs

- doc/fluids.md: the intro and Fluid netlists (nodes with fluid junctions, hand run pipe edges in litres a second, capacities per tick after bundling, block world unchanged), the pipe's drawing and panel lines, the Power section's note that the cable table holds pipes too.
- doc/logistics.md, Runs: the pipe run line goes; the tools line and the header name belt runs only.
- doc/input.md (Bindings, 130 to 131) and doc/touch_overlay.md (59): a pipe held runs as a cable does.
- doc/content.md: Items (the pipe keys), Cables and power ports becomes Cables, pipes and ports (fluid ports in `ports`, `fluid_buffer`, the fluid junction), Belt poles and runs (226) belts only, `stands_on_ground` (237) names the fluid junction.
- doc/architecture.md (44, 149, 151, 183, 306), doc/commands.md (63: the `cable` row takes pipes and fluid ports; 87: the `tool` list reads `belt_run, pipe, cable`, dropping `pipe_run`), doc/presentation.md (228 to 230 and Cables: pipes straight), doc/code_map.md (203, 257 and the cable files), the data headers (data/machines.sjson ports paragraph, the fluid junction, the belt pole; data/items.sjson the pipe keys; data/game.sjson the `belt_runs` comment "Free belt runs").
- doc/log at landing (main agent): the seam, the old save rule.

### 15. Hand-back check

- Memory a frame draws from: no new freeing in the UI pass; `pipe_line_seconds` survives rebuilds; the HUD's aimed index comes from the same frame's table.
- Numbers parsed from text: the four pipe keys and the port capacities are range checked (section 2, the existing port check).
- Changed save layout: none for the table; `Belt_Run.kind` removed with `drop_pipe_runs` and one log line; the dev kits carry the pipes the chapters now need.
- Shared budget: hand run pipes and junctions join the fluid netlist; block world flows checked unchanged by the existing fluid tests; a junction holds nothing, so it never keeps a line busy.
- Lists capped: at most 8 port lines on the junction panel; the HUD line is one line, fitted.
- UI audit: no case obsolete (section 13).
- Tests use temporary directories only.

### 16. Captures (Verify)

A `--dev` field pad at noon and at dusk, standing at a shore (0376: an offshore pump is placed only with water in front of its intake): an offshore pump at the pad's edge, its intake over the water, a fuel generator with coal cabled to it, a fluid junction, two boilers with coal, two steam engines, a junction box and a lamp cabled to the engines; pipes pump to junction, junction to each boiler, each boiler to an engine. Shots at 5, 20 and 60 m; a pipe run carried within and past 20 m; the HUD on an aimed pipe; the junction's panel.

### 17. Questions decided here

1. One table, not two (section 1).
2. Pipes are straight: a pipe under tension sagging like a cable reads wrong, and straight keeps the draw cheap.
3. A hand run pipe draws no fluid band: the HUD and the panel name its fluid and flow. The block world's bands stay.
4. The existing `pipe` item is the hand run pipe, one per metre, 1200 L/s, 20 m: the chapters' recipes already ask for pipes, so no new item is needed.
5. A buffer without a port in `ports` stays allowed in the loader; the shipped data test holds the coverage, so modded data for the block world needs no `ports`.
6. Fluid machines' panels gain no port lines; only the fluid junction lists its ports.
7. The neutral refusal wording serves cables and pipes with one string each.

### 18. Questions to the main agent (provisional answers)

1. Keep the `Cable` names for the shared table and run? Yes: a rename touches every 0368 file for no behaviour.
2. No band on a hand run pipe? Yes, as above.
3. Pipes straight? Yes.
4. The `pipe` item at 1 m a plate, 1200 L/s, 20 m span? Yes.
5. The dev kits raised as section 11? Yes.
6. The neutral rewording of the cable refusals? Yes.
7. `cable` command takes pipes, no `pipe` alias? Yes.

### 19. 0375, 0376, 0377

- 0375 (vessel tanks and pipes across docking): prepared, not designed. A vessel part's fluid port has `fluid_buffer` -1, so it takes no pipe until 0375 gives it a node in `pipe_end_node` and `machine_port_takes_line`; the connector rule in `cable_placement_refusal` already serves any kind.
- 0376 (the field's pumps draw from nothing): untouched. Since 0376 the offshore pump on a field frame needs water in front of its intake; the tar pit pump still makes crude oil from nothing until 0391. Pipes now carry what they make.
- 0377 (netlists that carry loops): untouched. A pipe loop lays a chord that carries nothing, as a cable loop does.

### Decisions (main agent, 2026-11-13)

1. Approved: pipes as records of the cable table, told by their item, the names `Cable` and `cable_*` kept. A second table would be a second copy of the run, the aim, the take up and the save.
2. The seven questions: yes to each as the designer answered (no band on a hand run pipe, straight pipes, the existing `pipe` item, the dev kits' counts, the neutral refusal wording, the `cable` developer command for both).
3. The fluid junction ships as the fallback box, as the junction box did; its model is item 0392, which waits for the user's reference sheet as 0387 and 0388 do.
4. The line "Not started before the user has seen the proposal" under Change: the main agent reads the user's queueing of this item on 2026-11-12 as the go ahead and says so in its report to the user, since it cannot show from the record that the proposal itself was read.

### Deviations (implementation, 2026-11-13)

1. `tick_fluid_networks` takes `machines` where it dropped `limit`: `pipe_end_node` reads each port's `fluid_buffer` from the registry.
2. `fluid_junction_area_size` takes the machine and sizes to its port count (at most 8), not a fixed 8 lines.
3. A run also ends silently when the held line's kind is not its first port's (a slot's stack swapped between a cable and a pipe), where the drain would otherwise toast "The run's first end is gone".
4. `test_a_pipe_carries_its_capacity_a_tick` feeds two boilers, not three: the junction has four ports, and three boilers with two pipes from the tank need five.
5. `test_a_pipe_netlist_is_deterministic` compares the flows tick for tick between the two orders, and the state hash between two worlds laid in the same order: the hash is the save's bytes and the table is written in its order, so two orders cannot hash alike.
6. Outside the named files: `render_belt_runs_test.odin` drops the tube check (its test renamed `test_a_belt_run_box_holds_its_surface_and_items`), `model_mesh_test.odin` lists the fluid junction among the machines without a model, `data/textures/items/fluid_junction.png` is generated by `tools/make_placeholder_textures.py` (every item needs an icon), and the shipped count tests (170 items, 72 machines, 147 recipes) follow.
7. Fix round: a fluid port's `capacity_litres_per_second` starts at 60 (`MINIMUM_PIPE_LITRES_PER_SECOND`) on every record, the vessel parts' too, so the iron tank's 10 and the docking connector's 20 L/s became 60; neither port takes a pipe before 0375.
8. Fix round: the junction's port lines are `fluid_port_out` and `fluid_port_in`, chosen by the last second's litres, which `pipe_record_litres` now counts signed from the record's first end.
9. Fix round: the box distance (`cable_box_metres`) is computed once per line each frame from its thickness and kept in its `Cable_Look`, not stored per item.
