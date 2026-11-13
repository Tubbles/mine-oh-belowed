# 0369: Cable loads on the panels and the overview

Status: implementing (2026-11-13)

Part C of 0355's specification (`doc/work/done/0355-cables-and-the-power-netlist.md`): a cable's load against its capacity and the bottleneck, on the junction box's panel and the power overview. The specification below is this item's own, brought up to `main` on 2026-11-13 (0368, 0383, 0384, 0385); an implementer never opens 0355.

## Goal

The player reads which cable limits a netlist.

## Controls

None new: the panels open as they do.

## Change

- Each cable's load from the last balance, and whether it limits: full, with a shortage on the side it feeds and spare on the side it comes from.
- The junction box's, cabinet's and switch's panel: a line per power port. The power overview: the network's limiting cables. The field's HUD: an aimed cable's load.
- After 0368 and 0383. Designed against the solve's interface while 0373 rewrites its inside.

## Verify

- The checks and the suite, with the UI audit cases at the smallest size.
- Captures of a saturated cable on the panel and the overview, sent to the user (Specification, Captures).

## Specification (design, 2026-11-13)

### What the player reads

- **Junction box, cabinet and power switch panel**: under the network and power rows (and a switch's toggle), one line per power port in port order: "Port c: free" dim, or "Port b: 300.0 kW of 300.0 kW, Light cable to Junction box": "to" where power leaves the port, "from" where it enters, "to" with nothing flowing. Accent colour while the cable limits, else text colour. A lamp's panel is unchanged.
- **Power overview**: right under the focused network's Power line, "Limiting cables: N", then its limiting cables behind the largest shortfall, at most three, in the accent colour: "Light cable, Junction box to Junction box: 300.0 kW of 300.0 kW", from the end power came from.
- **HUD on the field**: an aimed cable (the one Take up names, no run carried) replaces the name line with "Light cable: 300.0 kW of 300.0 kW", accented while it limits. The block world aims at no cable and shows nothing new.
- **A cable's load**: what it carried in the last balance, its share of its bundle's flow in proportion to its watts, rounded down, against its watts (the table's `watts`: the least of its item's and its two ports'). **It limits** when its bundle carries all it may, a consumer on the side it feeds got less than it asked, and an offer on the side it comes from has some left.
- A cable that closes a loop is the topology's chord and reads 0 until 0377.
- Before the first balance after a rebuild (a load, a test) no load shows: "Port b: Light cable to Junction box", the item's name on the HUD, no cable section on the overview.

### Where it comes from

- The solve's interface, all this item reads: `Topology.parent`, `.capacity` (the bundled watts of the edge to the parent, in `Electric_Networks.topology`), `.order`, `.trees`, `.tree_of`; `Node_Input.demand`, `.offer`; `Node_Output.delivered`, `.supplied`, `.flow` (both phases summed, positive towards the parent, within the per tick capacity: `test_solve_output_is_feasible`). 0373 changes none of them (its Step 1 keeps `tree_flows` and phase 2). 0377 must add the chords' flows.
- Kept: the balance already keeps `outputs` and `capacity_per_tick` per node between ticks; it adds two per node sums and a flag. `Electric_Networks` is derived (rebuilt at load, never written by `write_simulation_state`), so nothing enters the save or the state hash.
- Cost: one more pass over the nodes a tick, two additions a node (some microseconds at 0355's late factory of 3,400 nodes). A cable's load is two map lookups. The overview reads every cable each frame while it is open (2,700 in that factory), a panel its ports, the HUD one cable, sharing the Take up hint's scan.

### Files and procedures

`src/power_network.odin`:
- `Electric_Networks` gains `short_below, spare_below: [dynamic]i64` (per node, what its subtree's consumers asked and did not get, and what its subtree's offers had left, joules a tick) and `balance_current: bool` (the outputs, `capacity_per_tick` and the sums are the current topology's). `set_electric_allocators` and `destroy_electric_networks` take the two arrays; `clear_electric_networks` sets `balance_current = false`.
- `sum_subtree_slack :: proc(topology: netlist.Topology, inputs: []netlist.Node_Input, outputs: []netlist.Node_Output, short_below, spare_below: []i64)`: each node's `demand - delivered` and `offer - supplied`, then in reverse pre-order added into its parent's. Pure.
- `balance_electric_energy`: resizes the two arrays to the node count, calls `sum_subtree_slack` with `networks.topology` after `netlist.solve`, sets `balance_current = true` last.
- `Cable_Load :: struct {joules_per_tick: u64, watts: i64, at_capacity, limits: bool, shortfall: i64, source_end, network: int}`: the share, the cable's watts, its bundle at its per tick capacity, the rule above, what the fed side's consumers did not get, the end power came from (0 with no flow), its tree's network.
- `cable_tree_child :: proc(topology: netlist.Topology, first, second: int) -> (child, child_end: int)`: the node of the two whose parent is the other and which end (0 or 1) it is; child -1 for a chord.
- `cable_load :: proc(networks: ^Electric_Networks, table: ^Cable_Table, index: int) -> (load: Cable_Load, found: bool)`: not found without `balance_current`, for an index outside the table or an end without a node (`power_port_node`). `watts` from `table.watts`, `network` from `network_of_tree[tree_of[first]]`; a chord returns found with the rest 0. Else, with `flow = outputs[child].flow`:
  - share `|flow| * watts / topology.capacity[child]` in i128, 0 when that capacity is 0;
  - `at_capacity = capacity_per_tick[child] > 0 && |flow| >= capacity_per_tick[child]`;
  - the child's side is `short_below[child]`, `spare_below[child]`, the parent's side the tree root's sums less those. A positive flow feeds the parent's side from the child's (source end `child_end`), a negative one the child's side (source end `1 - child_end`);
  - `limits = at_capacity && fed short > 0 && feeding spare > 0`, `shortfall` the fed side's short.

`src/ui_power.odin`:
- `POWER_PORT_AREA_WIDTH :: 640`, `POWER_CABLE_ROWS :: 3`; `POWER_DETAIL_ROWS` adds `1 + POWER_CABLE_ROWS` (21), its comment naming the cables' heading and rows.
- `power_port_line_count :: proc(machine: Machine) -> int`: the power ports of a `.Junction_Box` or `.Power_Switch` record, else 0.
- `power_area_size`: width `POWER_PORT_AREA_WIDTH` with port lines, else `POWER_AREA_WIDTH`; height plus `power_port_line_count × UI_LINE_HEIGHT`.
- `power_panel_region`: a box draws its two rows then `power_port_lines`, a switch its three rows then `power_port_lines`.
- `power_port_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, handle: Entity_Handle)`: per power port a `detail_line` at `UI_LINE_HEIGHT`, dim when free, accent when it limits, else text colour.
- `power_port_text :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, end: Port_End, tick_rate: int) -> (line: string, cabled, limits: bool)`: the port keys below; `{port}` the port's id, `{cable}` the item's name, `{peer}` the machine at the other end.
- `with_cable_load :: proc(template: string, load: Cable_Load, tick_rate: int) -> string`: `{load}` as `format_joules_per_tick(load.joules_per_tick, tick_rate)`, `{capacity}` as `format_power(f32(load.watts) / 1000)`.
- `Network_Cable :: struct {index: int, load: Cable_Load}`. `cable_ranks_before :: proc(first, second: Network_Cable) -> bool`: the larger shortfall, then the lower index. `insert_ranked_cable :: proc(top: ^[dynamic]Network_Cable, candidate: Network_Cable, limit: int)`: kept in rank order, at most `limit` long.
- `network_limiting_cables :: proc(networks: ^Electric_Networks, table: ^Cable_Table, network, limit: int) -> (top: []Network_Cable, count: int, found: bool)`: every cable whose load is found, in the network and limiting, counted and ranked; not found without `balance_current`; temp allocator.
- `power_cable_text :: proc(entities: ^Entities, machines: Machine_Registry, items: Item_Registry, cable: Network_Cable, tick_rate: int) -> string`: `power_cable_line`, `{from}` the source end's machine, `{to}` the other's.
- `cable_status_text :: proc(entities: ^Entities, items: Item_Registry, index: int, tick_rate: int) -> (line: string, limits: bool)`: `power_cable_load`, or the item's name without a load.
- `power_cable_lines :: proc(state: ^Ui_State, content: ^Ui_Rectangle, screen_context: Screen_Context, network: int)`: nothing when not found; else `"%s: %d"` of `power_limiting_cables` dim, then each row in the accent colour, all at `UI_LINE_HEIGHT`. `power_network_detail` calls it right after the Power line.

`src/hud.odin`:
- `Hud_Context.aimed_cable: Maybe(int)`: the HUD field player's aimed cable, -1 for none; nil until `draw_hud` sets it, and `field_take_up_hint_shown` then looks it up itself (the tests).
- `hud_aimed_cable :: proc(screen_context: Screen_Context, hud: Hud_Context) -> int`: today's lookup of `field_take_up_hint_shown` (a field session with a world, no run carried, `field_aimed_cable` of `hud_field_player`), else -1. `field_take_up_hint_shown` returns the cache's or its value `>= 0`.
- `draw_hud`: `hud := hud` first; after the screens' early return `hud.aimed_cable = hud_aimed_cable(screen_context, hud)`, so the line and the glyph hints share one scan; after `name_color` is set, an aimed cable's `cable_status_text` replaces `name_status`, `name_color` accent while it limits, else `UI_TEXT_COLOR`.

### Layout

UI units are 1080 per screen height over the UI scale; widths at the audit's advance of 0.37 of the text size.
- 1920 by 1080, scale 1: the machine side is 640 (the panel 1488 of the safe 1728). A port line holds about 72 characters at text 1 and 45 at 1.6: the load always shows, a long peer ("Electric mining drill") ends in an ellipsis at 1.6. Box 4 lines (134 units), cabinet 8 (269), switch 2 (67), all inside the inventory's height, no scroll. The overview's 21 lines take 706 of the 816 its content has (panel 802 of 912), the detail column 789 wide (about 88 characters at text 1, 55 at 1.6, where a row's load is cut and its colour still marks it).
- 1280 by 800, scale 1.5, text 1.6, the smallest (1152 by 720 units, panel area 1037 by 588): the machine side keeps the 189 units the inventory leaves; a port line shows its port and part of the load and ends in an ellipsis, and the side scrolls as every machine's does. The overview's detail holds 14 lines: the name, supply, demand, Power, the cables' heading and three rows, the generators' heading and three, the batteries' heading. The rest gives way, cut by `detail_line` as the largest consumers already are today.
- The HUD line is fitted to the screen's width (1120 units at the smallest); "Light cable: 300.0 kW of 300.0 kW" is 33 characters.
- Bounded: port lines by the record's power ports (at most `MAXIMUM_MACHINE_PORTS`, 8, by validation), overview rows by `POWER_CABLE_ROWS`.

### Strings, `data/strings/en.sjson`, after `power_no_cable`

- `power_limiting_cables` "Limiting cables"
- `power_cable_line` "{cable}, {from} to {to}: {load} of {capacity}"
- `power_cable_load` "{cable}: {load} of {capacity}"
- `power_port_free` "Port {port}: free"
- `power_port_cable` "Port {port}: {cable} to {peer}"
- `power_port_out` "Port {port}: {load} of {capacity}, {cable} to {peer}"
- `power_port_in` "Port {port}: {load} of {capacity}, {cable} from {peer}"

### Tests, `src/cable_test.odin`

- `lay_hand_run_factory` gains `bundled := false`: a heavy cable from the first box's port `c` to the second box's `b`, laid right after the light cable.
- `test_cable_loads_follow_the_tree_flow`:
  - the hand run factory before a tick: the light cable's load not found;
  - after `tick_with_hand_run_offer` at 15,000 J: the light cable 5000 J of 300,000 W, at capacity, limits, shortfall 1250, source end 0, network 0; the second box's `short_below` 1250 and the tree's spare 9917; the heavy cable 5083 J of 900,000 W (the engine's port), neither; the lamp's cable 83 J of 5000 W, at capacity, not limiting, source end 1;
  - the bundled factory after the same tick: the assemblers at 1000, the light cable 568 J and the heavy 5681 J of the bundle's 6250 J (3.3 MW), neither at capacity;
  - the loop of `test_a_power_switch_splits_its_netlist` laid on the plain factory and a tick: the cable whose nodes are `topology.chords[0]`'s reads found, 0 J, not at capacity.
- `test_limiting_cables_rank_by_shortfall`: `insert_ranked_cable` of shortfalls 400, 1250, 1250, 90, 1250, 7 at indices 0 to 5 with limit 3 keeps 1, 2, 4, and the same inserted in reverse order. `network_limiting_cables` on the hand run factory: not found before a tick, after it count 1 and the light cable.
- `test_cable_load_texts` (`use_shipped_strings`), the hand run factory: after the tick the first box's ports read "Port a: 305.0 kW of 900.0 kW, Heavy cable from Steam engine", "Port b: 300.0 kW of 300.0 kW, Light cable to Junction box" (limits), "Port c: free", "Port d: 5.0 kW of 5.0 kW, Light cable to Lamp" (not limiting); before the tick port b reads "Port b: Light cable to Junction box". The light cable's overview row "Light cable, Junction box to Junction box: 300.0 kW of 300.0 kW"; its HUD line "Light cable: 300.0 kW of 300.0 kW" (limits), before the tick "Light cable".
- `test_the_glyph_bar_during_a_run_and_on_a_switch_behind_a_cable` gains: aimed at the switch, `hud_aimed_cable` is 0; `field_take_up_hint_shown` is false with `hud.aimed_cable` set to -1 and true with it nil; during the run `hud_aimed_cable` is -1.

### UI audit, `src/ui_audit_test.odin`

- The machine walk already draws the box, the cabinet (eight free ports, `place_missing_machines`) and the switch with their port lines, without loads, since `place_missing_machines` rebuilds after the site's ticks.
- `set_test_cable_limits :: proc(entities: ^Entities, tick_rate: int, limiting: ..int)`, a test helper: `inputs`, `outputs`, `capacity_per_tick` and the sums sized to the node count and zeroed, every node's `capacity_per_tick` from the topology; per limiting cable its child's flow `-capacity_per_tick` (into the child), the child asking 1000 J more than it got and its tree's root offering 1000 J more than it gave; `sum_subtree_slack`; `balance_current = true`.
- `audit_cable_loads(audit)`, after `audit_broken_furnace`: `build_power_plant`'s third box at {6, 1, 9} with the cables on its ports `a`, `b` and `d` limiting: "junction box with limiting cables" (Machine on the box) and "power with limiting cables" (Power), both walking the focus, at every size and text scale; then `balance_current = false`.
- No case for the HUD line: one line fitted to the screen's width.

### Docs

- `doc/fluids.md`, Power: line 63's "a junction box's panel shows its network" becomes a bullet on what the panels, the overview and the HUD read: the load, the limit rule, to and from, a chord until 0377, read from the last balance and kept nowhere. Balance, the overview bullet: its limiting cables, the three behind the largest shortfall, after satisfaction.
- `doc/ui.md`, Other screens, Power: the focused network's limiting cables before its generators.
- `doc/input.md` line 126: a junction box's panel "shows its network, its power and each port's cable ([fluids.md](fluids.md), Power)".
- `doc/code_map.md`: `power_network.odin`'s line names `cable_load`, `hud.odin`'s the aimed cable's load; the counts `tools/code_graph.py --check` reports.

### Hand-back check

- Memory a frame draws from: the sums, `outputs` and `capacity_per_tick` change only in the tick's balance, and a rebuild clears `balance_current`, so a frame drawn before the next balance reads no load. The audit cases run the frame and read the draw list.
- Unbounded lists: bounded as Layout says, checked at the smallest size and the largest text.
- Obsolete audit cases: none; the panel cases gain their lines.
- Save layout: none. Tests: no machine state. The other lines do not apply.

### Captures (main agent)

On the field with `--dev`: a combustion generator with coal, a heavy cable to a junction box with a lamp on a light cable, and a light cable to a second box whose cables feed five assemblers making gears from plates (375 kW behind 300 kW). At 1920 by 1080 and at 1280 by 800 scale 1.5 with text 1.6: the first box's panel (port b accented, the lamp's port full and plain), the overview with "Limiting cables: 1" and its row, the HUD aimed at the light cable.

### Decisions

1. The accent marks a cable that limits, not one at capacity: every machine's port is its rating (0368), so each machine's own cable is full whenever the machine runs at full, and "at capacity" would count every working machine. The rule reads only the interface, so 0373's inside does not move it. A vessel's 5 kW docking connector or 2 kW battery port behind a larger cable limits by the same rule.
2. The overview lists only limiting cables, by the shortage behind them: the heading counts them, so 0355's "and N more" goes. Three rows: the window holds 24 lines at 1080p and 17 are taken.
3. The cables come right after Power, so the bottleneck survives the smallest size; the largest consumers give way first.
4. To and from follow the flow's sign: the stored ends are the run's order, which tells the reader nothing.
5. The capacity shown is the cable's watts, the least of its item's and its ports': that is what limits it. A lamp's light cable reads "of 5.0 kW".
6. The sums are taken in the tick, one pass, beside `participants`, which the balance already keeps for the overview, so every reader is constant time.
7. `balance_current` rather than zeroing at a rebuild: a frame after a load shows no number instead of a wrong one, as `entity_participant` checks its handle.
8. The HUD shows an aimed cable's load: a cable between two machines has no panel, and the overview names ends, not places, so the reticle is how the player finds the one it names. `field_aimed_cable` runs `find_frame`, a linear scan, for each cable's ends, so the line shares the Take up hint's scan through `Hud_Context.aimed_cable` instead of adding a second.
9. A switch's panel gets its two port lines; a lamp's keeps its draw line, which is its cable's load.

### Provisional answers (main agent)

1. Colour alone marks a limiting cable on the panel and the HUD; the overview's rows are only limiting cables, so it reads without colour. A word for colour blind players would cost a template per line.
2. Ends are named by their machine only: no position, no marker in the world. A tint on a limiting cable in the world's draw would be a presentation item of its own.
3. A battery's unfilled charge room is no shortage: a cable that only slows a battery's charging never limits.

### Decisions (main agent, 2026-11-13)

1. Approved. "Limits" in place of part C's "at capacity", for the design's reason.
2. A limiting cable is marked by a word as well as by the accent colour, on the panel's line and on the HUD's (a string key of its own, "limiting", after the load): colour alone tells a colour blind player nothing, and the template is one more key.
3. Cable ends are named by machine, no position and no marker in the world. A tint on limiting cables in the world's draw is not part of this item.
4. A battery's unfilled charge room is not a shortage.
