# 0369: Cable loads on the panels and the overview

Status: verified (2026-11-13)

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

### Deviations (implementation, 2026-11-13)

1. ~~At capacity (`cable_bundle_is_full`) is the flow at `capacity_per_tick` or the solve's levels differing across the edge.~~ Replaced by the revised rule's `room < cost` (below).
2. Decision 2's word: `power_cable_limiting` = "limiting", put in by a `{limiting}` mark (", limiting" while the cable limits, else empty) after `{capacity}` in `power_cable_load`, filled by `with_cable_load`. The overview's `power_cable_line` has no mark, since its rows are only limiting cables. The HUD line reads "Light cable: 300.0 kW of 300.0 kW, limiting". ~~The mark in `power_port_out` and `power_port_in`.~~ Replaced by the revised rule's `_limiting` port keys.
3. A port's line says "to" when its load reads 0 J, also for a flow that rounds to 0 J: `Cable_Load` keeps no flow, and nothing shown flows.
4. Fix round: `set_test_cable_limits` zeroes every node's `edge_limits` before marking the limiting cables, so a record left by an earlier balance of the audit's world cannot limit a cable the audit did not name. A small helper `expect_limiting_edges` (and its `Limit_Case`) runs each hand case of `test_edge_limits_on_hand_netlists`.
5. Second fix round, the widened meaning (raising a cable together with the other cables at capacity on the power's path). Unclipped spare alone leaves the upstream cable of a series unmarked: it feeds an empty box at level 1000, whose region is short of nothing, and at 4995 of 5000 J it is not even at capacity against that box's cost of 1. So what a cable feeds also reaches on through cables at capacity carrying the power away (`Fed_Reach`, `fed_below` and `fed_above`, two passes before the spare's). The cost, the at capacity test and the short are measured on that reach, and the level test also passes when the reach holds consumers beyond. The short is less the spare that already reaches the fed end through rooms alone (`room_spare_below` and `room_spare_above`): without it, a full generator cable beside a free generator is marked, and with that spare passing full cables whole, two full feeders of one region each defer to the other. Four passes in all. `test_a_generator_cable_filled_by_the_dispatch_does_not_limit` becomes `..._limits_in_series`: its first engine has 117 J left, so the second engine's full cable is in series with the boxes' cable. The hand case "a full generator cable beside a free one" keeps the not limiting case.
6. ~~Second fix round, the test's reference. A mark counts as right when raising its cable together with the cables at capacity in series with it (each on the other's feeding side, `edges_in_series`) gains its fed side more than 2 J. With every mark of the tree raised at once, a poorer region elsewhere takes the power: 23 chain marks lose even though raising their cable alone gains (chain seed 304: 380 J). That count is printed beside the measured one but not asserted. A miss is a starved tree without a mark outside the accepted pattern (`tree_holds_accepted_miss`), asserted at 1 % of the starved trees.~~ Replaced by 8.
7. Second fix round: the limiting port lines read "Port {port}, limiting: …", and the UI audit checks at every size and text scale that each limiting line starts with its port's prefix in the accent colour (`audit_limiting_port_letters`, problem `Port_Letter_Cut`).
8. Third fix round, the test's reference. A mark is right when raising its power path with the mark gains its fed side more than 2 J beyond the same path without it (`path_gain_of_edge`). The path is every edge carrying power in series with the mark, full or not: with only the full ones, a consumer's cable below its demand (game seed 364: 4419 of 5000 J for 6666) fills first and caps the gain, so 5 game and 116 chain marks read wrong. Asserted: wrong at most 1 % of the game marks and 2.5 % of the chain marks, no starved tree silent, and none whose marks are all wrong. The all at once count and the accepted miss pattern go. The accepted false mark beside a later generator (the review's H12) is a hand case that asserts only the cable that does limit.

### The limits rule, revised (design, 2026-11-13)

Against `main`'s solve (0373). It replaces, for the limits only, the Specification's `short_below`, `spare_below` and `sum_subtree_slack` lines, `cable_load`'s `at_capacity` and `limits` bullets, Deviation 1 and the port strings of Deviation 2. The panels, the overview, the HUD, the stale guard and the caps stand.

**Meaning.** A cable limits when raising it alone would deliver more to some consumer on the side it feeds. The total may stay the same: between two short regions, raising the cable moves power from the richer region to the poorer one, and the cable limits.

**The rule**, per tree edge (node `c`, parent `p`), from `Topology`, `Node_Input` and `Node_Output` only, with the capacity per tick:
- No flow: not at capacity, no limit, shortfall 0. Otherwise the fed end is the end the flow enters (`c` when `flow < 0`) and the feeding end is the other. `room` is the capacity left in the flow's direction, `capacity - |flow|`.
- The fed region is the fed end's equal level component (neighbours joined while their levels are equal). It has demand `D`, consumers `n` (nodes with demand) and short `S` (demand less delivered). A level of it costs `cost = max(1, ceil(D / 1000)) + n`.
- **At capacity**: `room < cost`, with no levels test. The margin comes from 0373, which leaves each spare joule under the next level of every region it reaches plus under 1 J per consumer. Up to `cost - 1` joules of room can therefore stay unused under a cable that bounds its region (4995 of 5000 J), while a room of `cost` or more always gets a level bought through it when spare reaches it.
- **Limits**: three conditions: the cable is at capacity, the fed end's level is below the feeding end's, and `min(S, A + T) >= cost`. In that test:
  - `A` is the spare that reaches the cable from the feeding side. Each node's spare is `offer - supplied + charged`: a charging battery's intake counts, because the solve serves demand first. Spare passes towards the cable through each cable's room in that direction (`min(room, spare beyond)`), so a full cable passes only its rounding room.
  - `T` is what the feeding region would give up at a common level, computed in i128: `min(P, D * D_F * (L_F - L_D) / (1000 * (D + D_F)))`. Here `D_F` is the feeding end's region demand and `L_F`, `L_D` are the two levels. `P` is the delivery of the nodes at `L_F` that reaches the cable through rooms towards it (only equal level neighbours join). `T` is 0 when `D_F` is 0.
- **Shortfall**: `S`, the short of the region the cable feeds directly. The overview ranks by it, larger first and then the lower index (`cable_ranks_before` as it is).
- **Steady**: rounding leftovers stay under `cost`, so neither a spare made of leftovers nor a short within a level's rounding reaches the test. A mark changes only when the spare, `T` or the short moves by a level's cost. The two short regions case (3000, 3001 and 2999 J offered) marks in all three ticks. The generation shortage (an engine filling its light cable, 4996 of 5000 J carried) marks in none.

How the review cases come out on the model below:
- The second engine's light cable, filled by the dispatch, does not limit: the first box's region is short of nothing.
- A generator's cable carrying 100 J past a thin cable plus 900 J of charge does not limit, since its fed region is at 1000. The thin cable limits, because `A` holds the 900 J.
- A generator's own cable in a generation shortage does not limit: `A` is only its rounding, and `T` is 0 because a generator's region has no demand.
- Four recyclers behind a light cable at 4996 of 5000 J limit, and still do with a lamp more at 4997.
- In the no demand box between, the two 1000 J cables limit and the 3000 J cable does not.
- In the rated cables in a brownout, nothing limits.

**Cost**: two passes over `Topology.order` a tick, after the solve. The reverse pre-order pass sums the regions and the reach below. The pre-order pass copies the region totals down, adds the reach above and writes each edge's record. Seven i64 a node, integers only.

**Where it errs**, measured on a Python model. The model runs the rule on 0373's prototype (`tmp/0373_pool_model/pool.py`) plus `main`'s phase 2 (`set_charge_phase`), over 4,500 netlists from the reviewer's `probe_game_netlist` distribution (50,145 cables with capacity). The ground truth re-solves with the cable unlimited and sums the gain over the fed side.
- The rule marks 1,857 cables; the snapshot's rule marks 2,524.
- 2 marks are wrong (the fed side gains at most 2 J). Both are edges whose levels differ by one per mille (600 under 601), where `T` (4 J) plus a little spare just reaches `cost`. The snapshot's rule has 670.
- 1 limit is missed at the reviewer's threshold (the fed side gains at least `max(10, capacity / 100)`): donors behind a feeding end that has no demand of its own and sits at the rich level 1000 (a 550 J gain). `T` counts only the feeding end's own equal level part, and the region that would give way sits at another level beyond it.
- Five more cables gain 10 to 35 J unmarked: their region is within a level of full (999, 992), or a battery's 33 J faces a 35 J level. They fall under the margin by design.
- By total delivery (the reviewer's `probe_gain`), 151 marks gain nothing. These follow the two short regions pattern, where the fed side's gain is paid by the feeding side, and are right by the meaning above.
- A cable with no flow and a 0 J cable (which joins nothing) are never marked.

The model's solve is a prototype; the Odin test below measures the real one.

**Code.** The rule needs nothing from the game, and its ground truth needs the package's `solve` and test netlists, so it goes in a new file of package `netlist`, `src/netlist/limits.odin`:

```odin
// Per node, the edge to its parent after a solve (0369).
Edge_Limit :: struct {
	at_capacity, limits: bool,
	shortfall:           i64,
}

// Per node, measure_edge_limits' sums.
Limit_Reach :: struct {
	region_demand, region_consumers, region_short:        i64,
	spare_below, spare_above, donors_below, donors_above: i64,
}
```
- `measure_edge_limits :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, reach: []Limit_Reach, limits: []Edge_Limit)`: zeroes both arrays and calls `sum_limit_reach_below`. Then, in pre-order, it calls `spread_limit_reach_above` for each non root node and sets `limits[node] = edge_limit(...)`. A root's record stays zero.
- `sum_limit_reach_below :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, reach: []Limit_Reach)`: in reverse pre-order, each node first adds its own values: demand, 1 when demand > 0, `demand - delivered`, `offer - supplied + charged`, delivered. It then adds into its parent: the three region sums when the two levels are equal, `min(room_towards_parent, spare_below)` always, and `min(room_towards_parent, donors_below)` when the levels are equal.
- `spread_limit_reach_above :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32)`: copies the three region sums from the parent when the levels are equal. `spare_above = parent.spare_below - min(room_towards_parent(node), node.spare_below)`, plus `min(room_towards_child(parent), parent.spare_above)` when the parent is not a root. `donors_above` follows the same pattern, with the node's term only when node and parent are at equal levels, and the parent's term only when the parent and its own parent are.
- `edge_limit :: proc(topology: Topology, outputs: []Node_Output, reach: []Limit_Reach, node: u32) -> Edge_Limit` applies the rule above. With `flow < 0`: fed end `node`, feeding end `parent`, room `room_towards_child(node)`, `A = node.spare_above`, `P = node.donors_above`. Otherwise: fed end `parent`, feeding end `node`, room `room_towards_parent(node)`, `A = node.spare_below`, `P = node.donors_below`.
- `room_towards_parent :: proc(topology: Topology, outputs: []Node_Output, node: u32) -> i64` returns `capacity - flow`, and `room_towards_child` returns `capacity + flow`. `region_level_cost :: proc(demand, consumers: i64) -> i64`. `ceded_joules :: proc(fed_demand, feeding_demand: i64, fed_level, feeding_level: u32, donors: i64) -> i64` returns 0 unless the feeding level is above the fed level and both demands are above 0.

`src/power_network.odin`:
- `Electric_Networks`: `limit_reach: [dynamic]netlist.Limit_Reach` and `edge_limits: [dynamic]netlist.Edge_Limit` replace `short_below` and `spare_below`, with the allocators, the deletes and the resizes the two had.
- `balance_electric_energy`: `netlist.measure_edge_limits(topology, networks.inputs[:], networks.outputs[:], networks.limit_reach[:], networks.edge_limits[:])` replaces `sum_subtree_slack`. It takes the local per tick `topology`, and `balance_current = true` still comes after it.
- `cable_load`: `at_capacity`, `limits` and `shortfall` come from `networks.edge_limits[child]`, and the early return for no flow stays. `sum_subtree_slack`, `cable_bundle_is_full` and `cable_flow_sides` go. In `Cable_Load`'s comment: `at_capacity` means its bundle has no room for another level of the region it feeds; `limits` means raising it alone would give a consumer there more (`netlist.measure_edge_limits`); `shortfall` is that region's demand less delivered.
- `set_test_cable_limits` (`src/ui_audit_test.odin`): resizes `edge_limits` instead of the sums. For each limiting cable it sets the child's flow to `-capacity_per_tick` and `edge_limits[child] = {at_capacity = true, limits = true, shortfall = 1000}`. It sets no inputs and does not call `measure_edge_limits`.

`src/ui_power.odin`: `power_port_text` takes `power_port_out_limiting` or `power_port_in_limiting` while `found && load.limits`, otherwise the same keys as now.

**Strings** (`data/strings/en.sjson`). At the smallest size about 13 characters of a port line show, so the word leads. "Limiting port…" survives; the port letter is cut, but the line's place in port order and its colour still say which port it is.
- `power_port_out` "Port {port}: {load} of {capacity}, {cable} to {peer}" and `power_port_in` "Port {port}: {load} of {capacity}, {cable} from {peer}", without the `{limiting}` mark.
- New: `power_port_out_limiting` "Limiting port {port}: {load} of {capacity}, {cable} to {peer}" and `power_port_in_limiting` "Limiting port {port}: {load} of {capacity}, {cable} from {peer}".
- `power_cable_load` keeps "{cable}: {load} of {capacity}{limiting}": the HUD line is fitted to the screen's width and shows it whole. The comment above the block says that `{limiting}` (in `power_cable_load` only) is ", " plus `power_cable_limiting` while the cable limits, and that the port lines have limiting forms of their own.

**Tests**

`src/netlist/limits_test.odin` (new):
- `edge_limit_between :: proc(topology: Topology, limits: []Edge_Limit, first, second: u32) -> Edge_Limit`: the record of the tree edge's child.
- `test_edge_limits_on_hand_netlists`: each case runs through `hand_netlist` and `measure_edge_limits`, and the listed edges limit while no others do.
  - Two short regions: box 0, generator 1 offering 3000, then 3001, then 2999, consumers 2 and 3 asking 3000 each, edges 0-1 and 0-2 unlimited, 0-3 of 1000. 0-3 limits in all three, with shortfall equal to node 3's demand less delivered.
  - Generation shortage: box 0, generator 1 offering 5000 on 0-1 of 5000, four consumers of 1666 on cables of 1666. Nothing limits.
  - Dispatch filled: box 0, generators 1 and 2 offering 15000 at order 0 on cables of 15000 and 5000, box 3 by 0-3 of 5000, four consumers of 2500 on box 3 by cables of 2500. Only 0-3 limits.
  - Charging battery and charging battery alone: the inputs of `tmp/0369/verify/tree0373/src/netlist/probe_0369_test.odin` in the main checkout, lines 339 to 341. 0-3 limits; with 0-3 unlimited, nothing limits.
  - Four recyclers: box 0, generator 1 offering 15000 unlimited, box 2 by 0-2 of 5000, four consumers of 1666 on box 2 by cables of 1666; then again with a fifth consumer of 83 by a cable of 83. Only 0-2 limits, with `at_capacity`.
  - No demand box between, as in the same file: 2-3 and 2-4 limit.
  - Rated cables in a brownout and a thicker cable in a brownout, as in the same file: nothing limits. The battery's 50 J cable carries 9 J and is at capacity, since its 41 J room is under the 99999 J region's level cost of 101.
- `game_shaped_netlist :: proc(seed: int) -> Test_Netlist`: the reviewer's `probe_game_netlist` (same file, lines 172 to 215), unchanged.
- `fed_side_gain :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, child: u32) -> i64`: re-solves with `capacity[child] = UNLIMITED_CAPACITY` and sums the change in delivered over the fed side. That is the child's subtree when `outputs[child].flow < 0`, otherwise the child's tree less that subtree. Temp allocator.
- `LIMIT_NETLISTS :: 2000`. `test_edge_limits_match_raising_the_cable` runs seeds 0 ..< `LIMIT_NETLISTS` over every tree edge with capacity and flow. It counts the edges, the marks, the wrong marks (marked, gain ≤ 2) and the missed limits (not marked, gain ≥ `max(10, capacity / 100)`).
  - It asserts `wrong * 100 <= marks`, `missed * 100 <= marks` and `marks * 100 >= edges`.
  - It prints the four counts and the first five wrong and missed edges: seed, child, flow, capacity, the record and the gain.
  - The model expects about 830 marks, 1 wrong and under 1 missed, so the 1% bound leaves the Odin solve ten times the model's rate.
  - If it fails, the implementer reports the counts and the examples and does not loosen the bound without the main agent. The test is marked `// slow` if `build/test_times.tsv` shows it at 1 s or more.

`src/cable_test.odin`:
- `test_cable_loads_follow_the_tree_flow`: the `short_below` and `spare_below` lines become `networks.edge_limits[second].shortfall == 1250`. Every other expectation stays: the lamp's 83 J cable at capacity and not limiting, and the 4995 J case at capacity, limiting, with shortfall 1338.
- `test_a_generator_cable_filled_by_the_dispatch_does_not_limit` and `test_a_generation_shortage_blames_no_cable`: the reviewer's two probes (`tmp/0369/verify/tree0373/src/probe_0369_game_test.odin`, lines 59 to 121) without their prints. The first also expects the boxes' light cable to limit; the second expects `network_limiting_cables` to count 0.
- `test_cable_load_texts`: port b reads "Limiting port b: 300.0 kW of 300.0 kW, Light cable to Junction box"; the HUD line stays as it is.

**Docs**
- `doc/fluids.md`, Power, the cable load bullet (line 64): the clause from "It limits when its bundle carries all it may" to "has some left" becomes the meaning, at capacity and limits in this section's words: the fed region, a level's cost and why, the spare reaching through rooms including a charging battery's intake, the share given up at a common level, and the fed end below the feeding end. The bracket on levels differing goes. The panel line is led by "Limiting" while the cable limits, and the HUD's line ends in ", limiting". "(two sums per subtree beside the solve's flows) and kept nowhere" becomes "(the solve's flows and the per node record of `netlist.measure_edge_limits`, two passes after the solve)".
- `doc/fluids.md`, line 77: "the largest shortfall of the side they feed" becomes "the largest shortfall of the region they feed".
- `doc/code_map.md`: the netlist row's record (`code_graph.py --check`) and the package's file list (line 340) gain `limits.odin` (`Edge_Limit`, `measure_edge_limits`: each edge's limit from a solve's outputs, 0369) and `limits_test.odin`.

**Hand-back check**: the record is resized and written only in the balance, as the sums were, and `balance_current` still guards a frame drawn after a rebuild.

**Provisional answers**
1. The meaning is "some consumer gets more", not total delivery: that is the item's meaning, and it lets the two short regions case mark steadily. For total delivery instead, drop `T` and require the feeding region's own short to be 0. Then 151 of the model's 1,857 marks go, and the two short regions case marks nothing.
2. The port line reads "Limiting port b: …", which loses the letter at the smallest size. The alternative, "Port b: limiting, …", keeps the letter but shows only "Port b: limi…".
3. The spare counts a charging battery's intake. Decision 4 concerns the short and still holds. Without the intake, the reviewer's charging battery case misses its thin cable.
4. The missed limit behind a feeding end with no demand is accepted (1 in 4,500 netlists): catching it needs a level threshold per edge in the reach, which is no longer a fixed pair of passes.

### Decisions on the revised rule (main agent, 2026-11-13)

1. Approved. "Some consumer on the fed side gets more", not the total delivered: a cable between two short regions is why the far one is poorer, and it marks steadily.
2. The port line reads "Port b, limiting: ...": the port letter first, then the word, so both show at the smallest size (second fix round).
3. A charging battery's intake counts as spare on the feeding side.
4. The one miss (the power given up sits behind a feeding end with no demand at level 1000) is accepted and named in `doc/fluids.md`.
5. The designer's Python model of the rule is at `tmp/0369_limits_model.py` in the main checkout (untracked): a reference to read, never run from the tests.
