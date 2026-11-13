# 0389: The solve's repair in dispatch order

Status: landed (2026-11-13, 5b43d915)

Found by 0383's review. When a generator is held back by its own cable, the solve's slow path moves the shortfall onto the other nodes with `repair_dispatch` and `spread_over_rooms` (`src/netlist/solve.odin`), in proportion to each node's room and without regard to the dispatch order. So a battery gives while a second generator in the same tree has spare offer, and having given it gets no charge room that tick: beside a 900 kW engine on a 300 kW cable a docked vessel's battery drains instead of charging. The rule is older than the batteries (two generators of different orders are misordered the same way) and 0373 keeps it. After 0373, in the same files.

## Goal

The repair raises the nodes' gifts in dispatch order: every generator of an earlier order is at its offer or at its cable's limit before a later one gives more, and a store gives only what no generator can.

## Controls

None.

## Change

- `repair_dispatch` and `spread_over_rooms`: the shortfall goes to the rooms of the lowest dispatch order first, in proportion within one order.
- `doc/fluids.md`, Batteries: the qualification 0383 wrote goes.

## Verify

- 0383's reviewer's case as a test: a junction with a generator behind a 10 J cable (offer 100), a second generator (offer 200), a store (offer 50, room 50) and a consumer of 120. The second generator gives 110, the store gives 0 and takes its charge.
- Two generators of different orders with one held back by its cable.
- The definition test and the hand cases of 0373 unchanged.

## Specification (design, 2026-11-13)

Evidence: `tmp/0389_model/` in the main checkout (untracked): a Python port of `solve_tree` as on `main` (fast path, `pooled_level_holds`, dispatch, flows, phase 2) around the 0390 model's `region_levels`, with today's `repair_dispatch` and the one below. `hand.py`: on the 19 hand cases of `netlist_test.odin` both repairs give every asserted value and equal outputs to the joule. `verify.py`: on 7,149 phases of 2 to 5 positions with random bounds of both signs, against every feasible integer supply vector, the new repair reaches the best supply of every order prefix each time, and the rule's check (Tests) is empty exactly on the best vectors. `random_sets.py`, on sets shaped like the test file's (Python's generator: the shapes, not the seeds):

| Set | Netlists | Misordered today | Outputs differ | Misordered after |
|---|---|---|---|---|
| `brute_force_netlist` shape | 3,000 | 153 | 197 | 0 |
| `light_cable_netlist`, chains | 3,000 | 527 | 689 | 0 |
| `light_cable_netlist`, twins | 3,000 | 70 | 155 | 0 |
| `feasibility_netlist` shape (stores) | 500 | 485 (1,274 phases) | 485 | 0 |
| generators of orders 0 to 3 behind cables, stores (stress, no test set) | 2,000 | 1,494 | 1,564 | 0 |

Every netlist whose outputs differ has a repaired phase with two or more orders offering. Every other netlist is equal byte for byte. No output is infeasible. `definition.py` (the test's `levels_follow_the_flow` ported) finds nothing on either repair's outputs over the brute force, chain, twin and definition shapes.

### The rule

The levels fix what every consumer receives, the repair only who gives it. A dispatch is in order when, for every order k, the joules the orders up to k give are the most any dispatch within the phase's bounds gives: each edge's capacity and, across an edge whose levels differ, power only towards the poorer side (`bound_flows_by_levels`, unchanged). Seen from the results alone: no position of a later order gives while a position of an earlier order has offer left and the tree path from it to the giver has room in that direction. The two agree because a tree's feasible dispatches are a base polyhedron (laminar bounds on subtree sums over a box), and `verify.py` confirms it vector by vector. A store so gives only what no generator can bring through the cables, its forced part where a thin cable leaves the consumers behind it short. Within one order the split is today's: from the dispatch, the difference in proportion to the rooms.

### Today's repair against the rule

The model's outputs, supplied (s) and charged (c) summed over both phases, orders in brackets, U an unlimited edge.

| Case | Today | After |
|---|---|---|
| Verify 1: junction 0; node 1 offers 100 [0] behind 10 J; node 2 200 [0]; node 3 a store, 50 and room 50 [10]; node 4 asks 120 | 2: 102, 3: s8 | 2: 160 (110 and the 50 J charge), 3: s0 c50 |
| The same, the 10 J cable as two of 5 J (bundled) | as above | as above |
| Verify 2: node 1 100 [0] behind 10 J, node 2 200 [1], node 3 200 [2], node 4 asks 120 | 2: 63, 3: 47 | 2: 110, 3: 0 |
| Limited further up: node 0 asks 120; junction 1 behind 40 J holds node 2, 100 [0] behind 30 J, and node 3, 100 [1]; node 4 200 [2] and node 5 a store, 50 and room 50, at the root | 2: 24, 3: 16, 4: 64, 5: s16 | 2: 30, 3: 10, 4: 130, 5: s0 c50 |
| Inside a subtree: node 0 asks 100; junction 1 (U) holds node 2, 100 [0] behind 10 J, and node 3, 100 [2]; node 4 100 [1] at the root | 3: 90, 4: 0 | 3: 0, 4: 90 |
| Store behind a thin cable: node 0 asks 100, offers 1000 [0]; junction 1 behind 10 J holds node 2 a store, 50 and room 50, node 3 20 [1], node 4 asking 40 | 2: 22, 3: 8 | 2: 10 (forced), 3: 20 |
| The same without node 3 | 2: 30 | 2: 30 (forced, unchanged) |
| Phase 2: node 1 100 [0] behind 70 J, node 2 200 [1], node 3 200 [2], node 4 a store with room 100, node 5 asks 50 | 2: 63, 3: 17 | 2: 80, 3: 0 (c100 both) |
| Two trees: Verify 1's and Verify 2's in one netlist | both misordered | both in order |
| The item's: engine 15,000 [1] on a light cable (5000 J), fuel generator 1000 [3], lead battery 33 and room 33, 5500 asked | fuel 485, battery s15 | fuel 533, battery s0 c33 |

The case inside a subtree is why a room per child sorted by order (the item's Change, read literally) cannot do: the root's difference there is 0, junction 1 keeps its dispatched 100, and the misorder is in its subtree's composition, which no scalar room shows. Each subtree needs its range per order.

### The change, `src/netlist/solve.odin`

The repair becomes the tree's min cost flow with the order as the cost, the dispatch kept wherever the order leaves a choice. A class is an order some position of the phase offers at, the classes ascending from 0.

- `Class_Ranges :: struct {class_of: [256]i32, class_count: int, dispatched, forced, length: []i64}`, after `Phase`'s helpers. Comment: per position and class, flat at `position * class_count + class`: what the dispatch gave of the class in the position's subtree, the least of it the subtree gives with its edge at its floor (`forced`, the floor met by the cheapest classes), and what more of it the subtree can give under its edge's ceiling (`length`, the ceiling cut from the dearest); `class_of` an order's class, -1 for an order nobody offers at (0389).
- `order_classes :: proc(phase: Phase) -> (class_of: [256]i32, class_count: int)`: a `[256]bool` of the orders of positions offering above 0, then orders 0 to 255 ascending each get the next class or -1. Called by `class_ranges`.
- `cut_from_cheapest :: proc(forced, length: []i64, amount: i64)`: from class 0 up, `taken := clamp(remaining, 0, length[class])` moves from `length` to `forced`. Comment: the floor met by the earliest orders.
- `cut_from_dearest :: proc(length: []i64, amount: i64)`: from the last class down, `taken := clamp(remaining, 0, length[class])` leaves `length`. Comment: what the ceiling leaves out is the latest orders.
- `class_ranges :: proc(phase: Phase) -> (ranges: Class_Ranges)`, in reverse pre-order with `subtree_delivered` as today, rows `slice[position * classes:][:classes]`, all in the temp allocator: the position's offer adds to its class's `length` and its supplied to `dispatched`; floor and ceiling are `subtree_delivered` plus `lower` and `upper` (plus 0 at the root, where the tree balances); `cut_from_cheapest(forced, length, floor - sum(forced))`, then `cut_from_dearest(length, sum(forced) + sum(length) - ceiling)`; below the root the three rows and `subtree_delivered` add into the parent's.
- `split_class_target :: proc(phase: ^Phase, ranges: Class_Ranges, target: []i64, own_children: []i32, position: i32, class: int, rooms, given: []i64)`: today's top-down body for one class. `owns` when the position offers and its class is `class`, `own` its supplied then, else 0. Each child's target starts at its `dispatched` clamped to `[forced, forced + length]`; `difference` is the position's target less `own` and those; at 0 it returns; rooms own first (`owns ? (raising ? offer - own : own) : 0`), then each child's `forced + length - target` raising or `target - forced` lowering; `spread_over_rooms`; `supplied[position]` written only when it owns the class; each child's target moves by its share.
- `repair_dispatch :: proc(phase: ^Phase)`, signature and call in `solve_phase` kept: `class_ranges`, `phase_children`, `target` of count times classes with the root's row copied from its `forced` row (its `length` is 0 after the root's cuts), `rooms` and `given` of count as today, then in pre-order for each class `split_class_target`. Comment: moves the dispatch inside the edges' bounds in dispatch order (0389), each subtree's range per class from the bottom, then top-down each class's target split over the position and its children from the dispatch, the difference over the room left, own first; with one class it is the repair before 0389, joule for joule.
- `spread_over_rooms` and `phase_children` unchanged, `spread_over_rooms` now running once a class.
- Header comment: "where an edge blocks the dispatch the generation moves inside the limit (repair_dispatch)" becomes "...moves inside the limit, every order at its offers or its edges' limits before a later one gives (repair_dispatch, 0389)".

### Why it is in order, and today's with one class

- `class_ranges` is the dynamic program of a min cost flow on a tree with the classes as costs: a subtree's cost against what it sends up is convex and piecewise linear with one slope a class, so it is its least point (`forced`) and a length a class in class order. Children add their lengths; an edge's bounds cut the domain at both ends, the floor from the cheapest slopes, the ceiling from the dearest.
- Top-down a position's use of its merged lengths is a prefix in class order: the root's is its floor cut, and a child gets full lengths below its parent's partial class, a share of that one and nothing above. So at each position every class but one is full or at its least, and the spread meets those exactly (an amount equal to the total room gives every room in full). Only the partial class is a free split, and there the dispatch's own split stands as today.
- Feasible: any class targets within each child's `[forced, forced + length]` are a point of its domain, so every edge stays in bounds and every offer in `[0, offer]`, given `floor <= ceiling` at each position, which 0373's argument provides (done 0373, Step 1, Feasible). No guard, as today.
- One class: `forced` is today's `low` and `forced + length` its `high` at every position, and the start values, rooms and spreads are today's, so the output is today's to the joule (the model: no single class netlist differs on any set).

### What changes in the outputs

- Phase 1: levels and `delivered` do not change, since the repair writes only `supplied` and `tree_flows` then the flows. Both change only on trees whose phase 1 repair runs with two or more classes.
- Phase 2: its offers are what phase 1 left of each generator and its bounds what phase 1's flows left, so the charge follows phase 1's order: a store that gave only through the misorder now gives nothing and charges (the goal). On the stress set the total charge fell on 12 of 2,000 netlists, the generators giving what the stores stopped giving and leaving less, while the stores' net (charge less discharge) rose or stayed within a joule of per mille rounding on every one. 15 of 7,170 stores there start giving where today they did not (a forced share split within one order over the stores' rooms); 2,055 stop.
- The fast path never repairs and its dispatch, each order the least of its offers and what is left, is the best for every prefix when it fits: unchanged.

### 0373, 0390, 0356, 0369

- 0373's pool and 0390's recorded runs set the levels before the repair, which reads only `delivered`, the offers, the orders and the bounds: untouched. `repair_dispatch` and `spread_over_rooms` are as 0355 wrote them (`git log -L` shows 737df950 alone), so 0390's statement holds. The `plain_*` copies are of the pool, not the repair. `test_replayed_pool_matches_the_plain_pool` compares levels of both forms on one phase built from the solve's outputs, so it holds.
- 0356 (in flight): `top_up_phase` runs after the repair and reads `supplied`, `delivered`, `flow` and the bounds, which the repair leaves as `bound_flows_by_levels` set them; it meets ordered supplies, which its pass per order lowest first expects. A tank as a store gives only what no producer can push through the pipes, the same rule. The two meet in text only in the header comment and in the test's `solve_phase` call (`phase_misorders`): whichever lands second passes `top_up = false` there.
- 0369 (in flight): `limits.odin` reads `Node_Output.delivered`, `.supplied` and `.flow`, unchanged in meaning; their values move only as above. Its tests run one engine, one class.

### Work

n positions, c classes offered in the tree (the game's orders 0 to 3 and 10, so c is at most 5): bottom-up about 6nc (three rows into the parent, two cuts), top-down about 2nc (each class over the children), four rows of c i64 a position in the tree's temp guard (443 KB at 2,771 nodes and c 5). Today's is c 1. Every case of `test_netlist_solve_cost` offers one order, so no night run. Integers, loops in position and class order, an array for the classes: deterministic.

### Tests, `src/netlist/netlist_test.odin`

Written first and run on today's repair: the three hand tests fail on the Today column, and the property test counts misorders on each set, reported; then the change. `store50` below is `{offer = 50, charge_room = 50, order = 10, store = true}` and U is `UNLIMITED_CAPACITY`. Every netlist also passes `expect_feasible_output`.

- `test_a_held_back_generator_leaves_the_store_its_charge`: Verify 1, inputs `{{}, {offer = 100}, {offer = 200}, store50, {demand = 120}}`, edges `(1, 0, 10)` and nodes 2 to 4 on node 0 unlimited: node 4 delivered 120, node 1 supplied 10 flow 10, node 2 supplied 160 (110 and the store's 50 J charge) flow 160, node 3 supplied 0 charged 50 flow -50. The same with `(1, 0, 5), (0, 1, 5)` for the 10 J edge: outputs equal byte for byte. The item's: `{{}, {offer = 15000, order = 1}, {offer = 1000, order = 3}, {offer = 33, charge_room = 33, order = 10, store = true}, {demand = 5500}}`, edges `(1, 0, 5000)` and the rest unlimited: node 1 supplied 5000, node 2 533, node 3 supplied 0 charged 33.
- `test_the_repair_serves_an_earlier_order_first`: Verify 2, `{{}, {offer = 100}, {offer = 200, order = 1}, {offer = 200, order = 2}, {demand = 120}}`, `(1, 0, 10)`, the rest unlimited on node 0: nodes 1 to 3 supplied 10, 110 and 0. Limited further up, `{{demand = 120}, {}, {offer = 100}, {offer = 100, order = 1}, {offer = 200, order = 2}, store50}`, edges `(1, 0, 40), (2, 1, 30), (3, 1, U), (4, 0, U), (5, 0, U)`: node 2 30, node 3 10, node 1 flow 40, node 4 130, node 5 supplied 0 charged 50. Inside a subtree, `{{demand = 100}, {}, {offer = 100}, {offer = 100, order = 2}, {offer = 100, order = 1}}`, edges `(1, 0, U), (2, 1, 10), (3, 1, U), (4, 0, U)`: node 2 10, node 3 0, node 4 90, node 1 flow 10. Two trees, Verify 1's netlist as nodes 0 to 4 and Verify 2's as 5 to 9: node 2 160, node 3 charged 50, node 7 110, node 8 0.
- `test_a_store_gives_only_what_no_generator_can`: `{{demand = 100, offer = 1000}, {}, store50, {offer = 20, order = 1}, {demand = 40}}`, edges `(1, 0, 10)` and nodes 2 to 4 on node 1 unlimited: node 3 20, node 2 supplied 10 charged 0, node 0 110, node 1 flow -10. Without the generator, `{{demand = 100, offer = 1000}, {}, store50, {demand = 40}}`, edges `(1, 0, 10), (2, 1, U), (3, 1, U)`: node 2 supplied 30, its forced part. Phase 2, `{{}, {offer = 100}, {offer = 200, order = 1}, {offer = 200, order = 2}, {charge_room = 100, order = 10, store = true}, {demand = 50}}`, edges `(1, 0, 70)` and the rest unlimited on node 0: node 4 charged 100, node 1 70, node 2 80, node 3 0.
- `count_misordered :: proc(phase: Phase, lower, upper: []i64) -> (misordered, guarded: int)`: on copies of the bounds the direction rule from `phase.level` (as `bound_flows_by_levels`, written out); for each order of a position that gives (a `[256]bool`), a walk with a stack and `phase_children` from every position of an earlier order with `offer > supplied`, to the parent while `upper - flow > 0` of the position walked from, to a child while its `flow - lower > 0`; each reached giving position of that order counts as misordered. `guarded` counts the giving positions of an order above the least order with offer left (where the rule has something to say). Comment: the rule from a phase's results (0389).
- `phase_misorders :: proc(phase: ^Phase, by_node: []i32) -> (misordered, guarded: int)`: the bounds cloned, `solve_phase(phase, by_node, true)`, `count_misordered`.
- `dispatch_misorders :: proc(netlist: Test_Netlist) -> (misordered, guarded: int)`: per tree as `solve_tree` runs it (`make_phase`, `positions_by_node`, `set_supply_phase`, `phase_misorders`, phase 1's `supplied` and `flow` into an outputs slice, `set_charge_phase`, `phase_misorders` again when it returns true).
- `test_the_repair_follows_the_dispatch_order`: `dispatch_misorders` over `brute_force_netlist` (`BRUTE_FORCE_NETLISTS`), `light_cable_netlist` both forms (`LIGHT_CABLE_NETLISTS`) and `feasibility_netlist` (`FEASIBILITY_NETLISTS`), `free_all` after each; expects 0 misordered (the first failing seed and set named), `guarded > 0`, and logs the totals. `// slow` if `build/test_times.tsv` says so.
- Unchanged and passing: every other test, the 0373 hand cases, the brute force, the definition test, `test_solve_output_is_feasible`, the fast path against the slow, `test_replayed_pool_matches_the_plain_pool`, `test_solve_is_deterministic`. A game test whose numbers move is named in the report with before and after; none is expected (the battery tests run one generator).

### Docs

- `doc/fluids.md`, Balance, the dispatch bullet, after "each next order only what is left.": "Where a cable holds a generator back, what it cannot give goes to the generators that can still reach the consumers, the earliest order first: no order gives more while an earlier one has offer left and cables with room to where it is needed (0389)."
- `doc/fluids.md`, Batteries, first bullet: "..., after every generator, so it gives only what the generators cannot bring through the cables." The sentences from "as long as no generator" to "item 0389 changes it." go.
- `doc/code_map.md`: the netlist row's line count (`wc -l` of the two sources); in the netlist bullet "the dispatch by order and its repair" becomes "the dispatch by order and its repair in that order (`repair_dispatch`, `class_ranges`, 0389)", and the tests gain "the repair's dispatch order on every phase (`count_misordered`) and its hand cases".

### Hand-back check

- A shared budget: no participant is added, but phase 2's budget moves: its offers are what an ordered phase 1 leaves, so stores that stop giving charge, earlier orders burn more and later ones less, and the statistics' produced counts the charge (fluids.md, Balance). The model's figures are under What changes.
- Tests in the temp allocator, no state directory. The rest does not apply: no save, file, parsed number, drawn list or audit case.

### Decisions in this design

1. The rule is lexicographic by order within the bounds the repair has today, the direction rule included: a poorer region's leftover, under a level's worth, never flows into a richer region to spare a later order there.
2. Ranges per class, not a sorted room per child: the case inside a subtree.
3. Within one class the split starts from the dispatch as today, so one class stays today's to the joule: the hand cases, every single order netlist and the game's single generator tests. A split by length alone would move them.
4. The property test checks each phase as `solve_tree` runs it, not `Node_Output`: the output sums both phases and carries no level of phase 2, which the direction rule needs.
5. No guard for `floor > ceiling`: 0373 shows it cannot happen, and today's repair has none.

### Questions to the main agent, with provisional answers

1. The property test reads each phase's results through a test copy of `solve_tree`'s sequence instead of the solve's output alone (decision 4). Provisional: accept. On netlists without charge room phase 1 is the output, and phase 2 has no other way to be checked.
2. Within one order a forced share splits over the stores' rooms from the dispatch, so a store can start giving where today it did not (15 of 7,170 on the stress set). Draining one store first would be a rule beyond the item's "in proportion within one order". Provisional: accept.

### Decisions (main agent, 2026-11-13)

1. Approved: the repair as the tree's min cost flow by order, ranges per class, one class staying today's to the joule.
2. Question 1: accepted. The property test follows `solve_tree`'s sequence per phase.
3. Question 2: accepted. Stores of one order share a forced part in proportion; no store is drained first.
4. The item is implemented on `main`'s tip while 0356 and 0369 are in flight in the same package. Whichever of 0356 and this lands second passes `top_up = false` in `phase_misorders`' `solve_phase` call; the main agent resolves that at the rebase.
5. The designer's model is at `tmp/0389_model` in the main checkout (untracked): a reference to compare counts against, never ported line by line and never run from the tests.
