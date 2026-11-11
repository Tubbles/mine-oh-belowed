# 0373: The netlist's charge for a poorer child

Status: designed (2026-11-11)

Found by 0355's review. In the solve's slow path (`src/netlist/solve.odin`, `add_clamped_response`, `region_levels`) the region that feeds a poorer one across a limiting edge is charged the edge's full capacity, while the poorer region at its whole per mille level takes less. The difference is withheld from the feeding region, and when its demand is small that is tens of per mille with its own generation idle: a box with one 13 kW machine and a 12 kW generator on a light cable that passes on to an overloaded box runs its machine at 92.5 percent where full power is reachable. The main agent had accepted the charge as "a few per mille" before the review measured it; that was wrong. Under the poles it cannot occur (every edge unlimited), so 0355 landed with it named.

## Goal

A region is never held under what its own supply and its cables can give it.

## Controls

None.

## Change

- Above a poorer child's level the child is charged what it takes at that level, not the edge's capacity (the review's proposal: `clamp(R_child(poor_level), low, high)`), with the repair pass and the feasibility argument checked again.
- The brute force reference charges the same, and its capacities include the corners the review used (0, 1, 999, 1000, 1001, 1999, 2000, 3000, 4500, unlimited).
- The definition test measures the feeding region's idle reachable supply, and its bound is derived or zero.
- Before 0368.

## Verify

- The checks and the suite, with the review's two hand cases as tests (the middle at 990 and at full power).
- The adapter's paired test unchanged: no behaviour change under the poles.

## Specification (design, 2026-11-11)

Units below: R and every charge are in millijoules (joules times `LEVEL_FULL`), as in `region_levels`; `low = 1000 * lower`, `high = 1000 * upper`; `ru`, `rl`, `pl` are a node's `rich_until`, `rich_level`, `poor_level`.

### The model

- A node's level is a whole per mille; a consumer receives `delivered_at(demand, level)`, rounded down. An edge carries whole joules within its bounds.
- Each edge is open or limiting. Regions are the components of the open edges, one level each. A region's supply: its offers, plus the capacity of each limiting edge from a child region that feeds it, less the take of each child region it feeds.
- A region that feeds its parent region across a limiting edge (up) sends the capacity: its level is `pooled_level(supply - capacity, demand)`, refused when that supply is negative.
- A region fed by its parent region across a limiting edge (down) is at `pooled_level(supply + capacity, demand)`, and the edge carries its take: its deliveries less its supply, at least 0. A region with a surplus under a down edge keeps it. 0355 charged the capacity here; this is the change.
- Direction: across a limiting edge the fed side's level is at most the feeding side's. Power flows towards the shortage.
- Feasible: a flow exists with every offer between 0 and itself, every open edge within its bounds, every limiting edge between 0 and its capacity in its direction, every node balanced.
- Maximised: the levels of the consumers with a demand, sorted ascending, lexicographically. Assignments with equal sorted levels are equal answers. What whole per mille levels and whole joules leave in a region stays undelivered (Leftover below).
- Inside a region the pooled level counts the exact need (`demand * level / 1000` unrounded), today's rule and the fast path's, so nothing changes under the poles. With demands in whole thousands the exact need is whole joules: the brute force uses such demands, and the two hand cases add rounding.

### Why the review's proposal falls short

- `clamp(R_child(pl), low, high)` charges the exact need. Hand case 1: `R_child(713) = -4,995,991`, the middle at 940; hand case 2: `R_child(578) = -4,993,920`, the middle at 954. The 5 J and 34 J missing are the poorer region's deliveries rounded down (7 × 0.713 J, 40 × 0.848 J). The review's reachable values count whole joules, so the charge is the whole joules taken.
- A clamp to `[low, high]` credits a positive `R_child(pl)` (a poorer child with a surplus at its level) as an export, which `bound_flows_by_levels` then closes: the feeder's level counts joules that cannot arrive. The charge is never above 0.
- The 19 edges of 0355's probe were most likely those credits: feeders set too high, a repair unable to meet the target within the bounds, an edge left with the wrong sign or room. The record does not say which metric and capacities gave 123 and 19, so the probe below sets its own baseline.

### Step 0: the probe (scratch, reverted before the change)

On the item's worktree, a scratch `@(test) probe_feeder_idle`, run alone with `./build.sh test quick netlist.probe_feeder_idle`, over `brute_force_netlist` with the corner capacities (Step 2) and `definition_netlist`, demands in thousands. Per equal-level component below full with a demand, its idle supply as `component_idle_supply` (Step 2) defines it. `add_clamped_response` takes the child's `pl` and, in the variants, adds another value above it; a temporary package variable counts the values above 0 added there. For each of three values above `pl` it prints with `log.infof`: the components with `idle * LEVEL_FULL >= demand`, the largest `idle * LEVEL_FULL / demand`, the trees failing `expect_feasible_output`, the trees with a positive charge, and for the first 30 offending components the seed, node, level, idle and demand:
- (a) today's `low`: offenders expected (the defect, now seen from the feeder);
- (b) `clamp(response_at(child, pl), low, high)`: offenders and infeasible trees expected to coincide with positive charges (the 19);
- (c) `min(response_at(child, pl), 0)`: 0 offenders, every tree feasible.

On these demands (c) is the whole change (the walk below returns `R_child(pl)` exactly). If (c) leaves an offender, stop and report it before step 1.

### Step 1: the solve, `src/netlist/solve.odin`

- `add_child_response :: proc(target: ^Response, child: Response, low, high: i64, poor_level: i32, poor_charge: i64, spare_tables: ^[dynamic][]i64)` replaces `add_clamped_response`. The line case is unchanged (a clamp that does not bite means `pl == LEVEL_FULL`). In a table, each level adds `level > poor_level ? poor_charge : clamp(response_at(child, level), low, high)`.
- `make_non_increasing :: proc(table: []i64)`: each entry from level 1 up becomes the least of itself and the one below. The whole-joule charge can lie above the exact one at `pl` by under 1000 per consumer of the poorer region, so a parent's table can rise there; the envelope keeps every response non-increasing, so `largest_level_at_least`'s binary search, `child_level` and the fast path's three levels stand as in 0355. It is progressive filling: a region stops at the first level it cannot afford.
- `whole_joule_net :: proc(phase: Phase, thresholds: []Level_Thresholds, poor_charges: []i64, offsets, children: []i32, region: ^[dynamic]i32, nets: []i64, start: i32, level: u32) -> i64`: what the subtree of `start` gives its parent, in whole joules times 1000, with its region at `level`. The region is `start` and each child `g` of a region node with `ru_g < level <= pl_g`, collected in pre-order on `region` and summed in reverse into `nets`: each region node `LEVEL_FULL * (offer - delivered_at(demand, level))`; each child outside it `high_g` when `level <= ru_g`, `poor_charges[g]` when `level > pl_g`; each child inside it its net clamped to `[low_g, high_g]` (a surplus above the edge stays in the child).
- `region_levels`, unchanged signature: `phase_children` at its start, `poor_charges := make([]i64, count)`. Per non-root position in reverse pre-order: `make_non_increasing` on its table if it has one, the thresholds as today, then `poor_charges[position] = min(whole_joule_net(..., position, u32(pl)), 0)` when `pl < LEVEL_FULL` (else 0), then `add_child_response`. The root's table gets `make_non_increasing` before its level. The comment says the charge, the envelope and that `R` never rises.
- `pooled_level_holds`: a fourth accumulator per position, `whole`, in the same pass: `whole[position] += LEVEL_FULL * (offer - delivered_at(demand, level))`. Each position, before its own check: `responses[position][2] = min(responses[position][1], responses[position][2])` (the envelope at the three levels; levels 0 to L hold no charge above a `pl`, since every descendant has passed `child_keeps_level`). Into the parent: indices 0 and 1 clamped as today; index 2 adds `min(whole[position], 0)` when `response[2] < low` (poor at L + 1, so `pl == L`, and its region at L reaches every descendant but those exporting at capacity, which the clamps count as `high`), else the clamp; `whole[parent] += clamp(whole[position], low, high)`. The slow path's walk at `pl == L` gives the same value, so the fast path still never gives what the slow path would not.
- Unchanged: `child_level`, `bound_flows_by_levels` (a poor charge is at most 0, matching `upper = 0` on a poorer child; a rich one is `high`, matching `lower = 0`), `dispatch_by_order`, `tree_flows`, `repair_dispatch`, phase 2 (its bounds still hold 0, and a store's charge room rounds like a demand).
- The file's header comment: the slow path's charge and the envelope in a sentence; the "Known defect (0373)" comment goes.

Why it stays feasible: with `R̂` a response after `make_non_increasing`, the walk counts every region node in whole joules and every boundary as the solve does, and whole joules never exceed the exact need, so by induction `R̂ <= R <= 1000 * whole-joule net` at every node and level. Every bound a level was certified against in `R̂` (a poorer child's import at `pl` within the capacity, a richer one's export of `high` at `rl`, a root's supply at its level, a joined child within its bounds) therefore holds for the whole-joule deliveries, so an integer flow exists within the bounds `bound_flows_by_levels` leaves, and `repair_dispatch`'s `L <= H` holds at every node as in 0355: no edge over capacity, no node over its demand or offer, joules conserved. Deterministic: integers only, the walk in child order, one stack, no maps.

### Step 2: the reference and the tests, `src/netlist/netlist_test.odin`

- `BRUTE_FORCE_CORNER_CAPACITIES :: [10]i64{0, 1, 999, 1000, 1001, 1999, 2000, 3000, 4500, UNLIMITED_CAPACITY}`. `brute_force_netlist`: each capacity from the corners with probability one half, else 0 to 6000 J; the rest as today. Every test on the set gets the corners.
- `brute_force_region_levels` (signature kept) computes the model: regions and their offers and demands as today, then each node with a limiting edge in reverse pre-order (a region's child regions come first): `Saturated_Up` subtracts the capacity from its region's supply (false when negative), sets the region's level and adds the capacity to the parent region's supply; `Saturated_Down` sets the level at supply plus capacity, its take is the region's `delivered_at` sum less its supply, at least 0 (false above the capacity), subtracted from the parent region's supply; the root region last (false when its supply is negative). Comment: the down edge carries the take, never a share of the solver's response.
- `brute_force_levels`: enumerates only the edges below `UNLIMITED_CAPACITY` (3 to the power of their count); an unlimited edge is open. Comment: a down edge of unlimited capacity puts its region at full, so at its feeder's level, where open is as good; an up one leaves a negative supply. `brute_force_levels_follow_the_flow` and `brute_force_flow_exists` unchanged; their comment loses the shared defect.
- `component_idle_supply :: proc(topology: Topology, inputs: []Node_Input, outputs: []Node_Output, start: u32, seen: []bool) -> (demand, idle: i64)` replaces `equal_level_demand`: from `start` over tree edges whose two levels are equal, marking `seen`: the demand of the component, and its idle reachable supply, the sum of its `offer - supplied` plus, on each tree edge to a neighbour at a higher level, `capacity - inflow`.
- `levels_follow_the_flow :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> (broken: int, largest_idle_per_mille: i64)`: an edge whose levels differ breaks it when its flow runs from the lower level to the higher or the lower side's component has no demand (as today); a component below full with a demand breaks it when `idle * LEVEL_FULL >= demand`. Derived bound: a region's supply less its deliveries is under one level's exact need, `demand / 1000` J, and whole-thousand demands round nothing; regions at one level sum their bounds; a poorer neighbour's take is what it uses. `MAXIMUM_HOLDBACK_PER_MILLE` goes.

Tests:
- `test_solve_matches_brute_force_on_small_netlists`: unchanged body, the corners included, 0 differing. A differing seed goes to the main agent, never fitted.
- `test_levels_differ_only_across_saturated_edges`: the brute force and definition sets through the new `levels_follow_the_flow`: 0 broken, some levels differ.
- `feeder_netlist :: proc(middle_offer, middle_demand: i64, consumer_count: int, consumer_demand: i64) -> Test_Netlist`: node 0 offers 1,000,000 J, node 1 the middle, node 2 a junction, nodes 3 on the consumers; edges (1, 0, 5000), (2, 1, 5000), (k, 2, unlimited).
- `test_a_poorer_branch_charges_its_feeder_what_it_takes`: `feeder_netlist(90, 100, 7, 1001)`. The middle at 990, delivered 99, supplied 90, flow -5000; each consumer at 713, delivered 713; the junction's flow -4991; the root supplied 5000; feasible. `brute_force_levels` equals the solver's sorted levels, its last (the middle) 990: today's 900 fails it.
- `test_a_small_feeder_reaches_full_power_beside_an_overloaded_branch`: `feeder_netlist(200, 216, 40, 216)`, the item's 13 kW machine and 12 kW generator on a light cable. The middle at 1000, delivered 216; each consumer at 578, delivered 124; the junction's flow -4960; the middle supplied 176 and the root 5000, the middle's flow -5000 (traced through the dispatch and the repair); feasible. The reference equal, its last 1000: today's 925 fails it.
- `test_a_poorer_branch_keeps_a_surplus_it_cannot_send`: node 0 offers 9 and asks 10, node 1 offers 2 and asks 4000, edge (1, 0, 1). Node 1 at 0, supplied 0, flow 0; node 0 at 900 (today 800; a clamp to `high` would credit 1 J that the direction rule then blocks); the reference equal.
- Unchanged and passing: `test_solve_output_is_feasible` (odd demands and stores: the walk and the envelope), `test_slow_path_agrees_with_the_fast_path`, `test_solve_is_deterministic`, `test_uniform_netlists_match_the_pooled_balance`, the topology test, 0355's four hand tests (their limiting edges take exactly their capacity: 500 of 500 J, 40 of 40 J), and `test_balance_through_the_netlist_matches_the_pooled_balance` in `power_test.odin`, byte equal under the poles: every edge unlimited, so every `pl` is 1000, no charge, walk or envelope runs, and the fast path holds as before.

### Leftover

Joules stay undelivered only in a region that cannot pass them on: the region at the root, one feeding its parent at the capacity, one under a down edge holding a surplus. In each, under one per mille of its demand plus under 1 J per consumer (each delivery rounded down). A region under a down edge no longer costs its feeder anything it does not take, its own rounding included. The envelope adds one case: where a region's exact need at a poorer region's `pl` crosses its own edge and its whole-joule need one level up would not, the region stops below that `pl`, missing at most the poorer region's rounding (under 1 J per consumer of it). For power the leftover stays: a machine works by its level. For fluids 0356's top-up hands out exactly this (spare offers against shortfalls within the bounds, the direction rule included), so this item builds no second mechanism and the top-up is unchanged.

### Cost

- Fast path: the same passes; `pooled_level_holds` carries a fourth value.
- Slow path per phase, today: `region_levels` four passes, `bound_flows_by_levels` one, the dispatch one per order present, `tree_flows` two, the check one, the repair about six and `tree_flows` again when it runs; 1,001 entries per child added to a table, three binary searches per node with a table.
- After: `phase_children` once more (three light passes), one pass of 1,001 per table (the envelope), and per node with `pl < 1000` a walk over its region at `pl`. A walk reaches a node once for each limiting edge above it whose region reaches it: about one pass over the nodes where limiting edges cut small regions (`cost_netlist`'s chains), n²/2 at worst for a chain of n limiting edges whose poor levels rise towards its end. `test_netlist_solve_cost` measures it in the night window.

### Docs

- `doc/fluids.md`, Power, Balance, last bullet: the defect sentence becomes: a saturated edge splits a netlist into regions with one level each, the region short of power at the level its edge's capacity gives it, the region feeding it charged the whole joules it takes there (0373); power flows towards the shortage; what whole per mille levels and whole joules leave stays undelivered, under one per mille of a region's demand and a joule per consumer.
- `doc/code_map.md`: the netlist tests' line names the corner capacities and the three hand cases; the counts `tools/code_graph.py --check` reports.
- Comments naming 0373: `add_clamped_response`'s known defect, `brute_force_levels_follow_the_flow`'s shared defect, `MAXIMUM_HOLDBACK_PER_MILLE` and `levels_follow_the_flow`'s missed loss, all rewritten as above.

### Hand-back check

- Shared budget: the poorer region's level is computed with its full capacity as before; only its feeder gains, and phase 2 finds more left over.
- Rates: whole joules; the charge is what is delivered, so nothing is lost or made.
- Save layout: none; the solve is a pure function of the tick's inputs, byte equal under the poles.
- Tests use the temp allocator only. The other lines do not apply.

### Decisions in this design

1. The charge above `pl` is `min(whole-joule net at pl, 0)`, not the review's `clamp(R_child(pl), low, high)`: the Verify's 990 and full power are whole-joule values, and a positive credit breaks the direction rule.
2. Every response is made non-increasing (progressive filling) rather than scanned raw. A raw response would place a region by whole-joule leximin even in the envelope's case, but the fast path would then need the root's response at every level above the pooled one, not three. The envelope's case, measured by hand: hand case 1 with a 4976 J edge to the root gives the middle and the 7 consumers 712; whole-joule leximin gives 713 and the middle 750.
3. The reference keeps whole-thousand demands, where the exact need is whole joules. With other demands the solve's thresholds count a joined child's exact need (0355's rule, kept), so an open edge whose exact need crosses its capacity while its whole joules fit makes the child poorer where a whole-joule reference would keep it joined, by up to about `1000 / d` levels for consumers of `d` joules. Odd demands are covered by the hand cases and the feasibility test only.

### Questions to the main agent

1. Decision 2: the envelope, or raw responses with a slow path wherever any edge binds above the pooled level?
2. Decision 3: is the exact need inside a region (the pooled rule, fixed under the poles) the model also between joined nodes of a region, or should 0368's cables, where most consumers are not whole thousands, get a follow-up that counts whole joules there?
3. The corners are folded into `brute_force_netlist` (half its edges), which changes the draws of every seed; 0356's tests on that set still apply. A separate set instead?

### What this changes in 0355's and 0356's specifications

- 0355, decision 3: a region's supply counts what a poorer region behind a saturated cable takes, not the capacity. Part A, `region_levels`: a poorer child above `pl` adds its whole-joule take, and every response is made non-increasing. Tests (A): the reference's down edge carries the take, its capacities include the corners, unlimited edges are open, and the definition test bounds the feeder's idle supply.
- 0356: the top-up is unchanged and spreads the leftover above; decision 11's cost gains the envelope and the walks where a joint saturates; "0355's tests unchanged" reads as 0373's tests.

### Decisions (main agent, 2026-11-11)

1. Not started. The user unqueued everything not explicitly asked to be implemented (2026-11-11); this item waits with 0368 and 0356, which need it.
2. Question 1: the running minimum, as chosen. Its rare case (one level under whole joule leximin) is what 0356's top-up spreads.
3. Question 2 (a child inside a region made poorer than whole joules require, by up to about 1000 / d levels for consumers of d J) is not decided; it is weighed when 0368 is asked for.
4. Question 3: the corners are folded into `brute_force_netlist`.
5. The design found the review's proposed charge does not reach the review's own values (940 and 954, not 990 and full): the charge is the whole joules the poorer region takes.
