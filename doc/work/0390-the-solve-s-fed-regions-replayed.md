# 0390: The solve's fed regions replayed

Status: verified (2026-11-13)

Found by 0373's review. The solve's pool reruns every inner fed region's capped greedy in each walk above it, so its work is quartic in the depth of nested fed regions that each have a cheap feeder: a chain of 321 nodes nested that way costs 28 million node visits a tick, one of 641 costs 445 million. Ordinary netlists do not nest so (2,701 nodes with every chain edge saturated and generators behind thin cables: 1.3 million), but a long line of generator and consumer pairs joined by thin cables does, and the solve runs every tick on every machine of a session. After 0373, in the same file, before or with 0389.

## Goal

The solve's work on a netlist is bounded near its size times the levels it moves, also for nested fed regions.

## Controls

None.

## Change

- Each fed region's greedy steps are recorded once, uncapped, and replayed up to a cap by every walk above it (a capped run is the uncapped run's prefix, 0373's rule 6), in `src/netlist/solve.odin`.
- The levels and flows do not change: the reference, the definition test and the hand cases stay as they are.

## Verify

- `test_netlist_solve_cost`'s nested chain case (0373) in the night window, before and after.
- A count test, no timing: node visits on nested chains of 81, 161, 321 and 641 nodes grow no faster than the bound the design states.
- The brute force and definition tests unchanged.

## Specification (design, 2026-11-13)

Evidence: a Python port of `region_levels` and everything it calls, as on `main` after 0373 (the design's scratch, not in the repository), reproduces the review's `reachable` counts exactly (123,450, 1,837,700 and 28,342,600 at 81, 161 and 321 nodes). On it the design gives today's levels on about 15,500 trees (shapes of the brute force, feasibility, light cable and twin sets, the same with phase 2's uneven bounds, two nested generators, `nested_chain_netlist` at depths 1 to 40, chains built for long draws, the three `cost_netlist` cases), and on about 15,200 of them, after every replay, the pools were compared with what today's capped greedy leaves from the same pools: equal every time, about 15,000 of those replays cut inside their record.

### Where the work goes

The item's guess holds, and there is a second term. At 161 nodes, of today's 1,837,700 `reachable` visits, 1,663,740 are inner fed regions' capped greedies rerun in the bottom-up walks above them and 85,321 the same reruns in the top-down walk: every walk holding a fed region reruns its run, and each pass walks every deeper candidate's path up to the region. 85,399 are the fed regions' own uncapped runs in `fed_fill`: each runs once, but every pass walks every candidate's path, cubic on the chain (5,512,959 visits at 641 nodes with the replay alone). 3,240 are the domain roots' runs.

### The change

1. Record: `fed_fill`'s uncapped greedy appends each step (the candidate, the level it then sits at, its need) to one list in `Pools`; the fed region's range of it is kept by position.
2. Replay: `settle_domain` replays a fed region's range while each step's candidate is under the cap, in place of its capped greedy.
3. Memo: within one pass of a greedy, `reachable` computes each position on the candidates' paths once.

### Code, `src/netlist/solve.odin`

- `Greedy_Step :: struct {candidate: i32, level: u32, need: i64}` (16 bytes): one step of a fed region's uncapped run, the level the candidate then sits at and the joules it cost.
- `Pools` gains `reach, reach_pass: []i64`, `record_first, record_end: []i32`, `path` beside `domain, candidates` (`[dynamic]i32`), `steps: [dynamic]Greedy_Step`, `pass: i64`. Comment: `steps` every fed region's uncapped run as `fed_fill` recorded it, back to back, position's at `steps[record_first[position]:record_end[position]]`; `reach` a position's value in the current pass of a greedy, valid while `reach_pass` equals `pass`; `path` the scratch of `reachable`. `make_pools` allocates the four slices at `count` and `path` and `steps` with capacity `count`, in the temp allocator.
- Test counters, after `Pools`: `when ODIN_TEST { @(thread_local) pool_visits: int; @(thread_local) pool_partial_replays: int }` (one declaration a line), commented "the positions the pool visited on this thread and the replays a cap cut short, for the tests (0390)". `count_pool_visits :: proc(count: int)`: `when ODIN_TEST { pool_visits += count }`. Thread local as `field_water_span_count` is: tests run in parallel.
- `walk_domain`: at its end `count_pool_visits(len(pools.domain) + len(pools.candidates))`.
- `settle_domain :: proc(phase: Phase, pools: ^Pools)`: `responses` goes (only the greedy read it). After zeroing, `count_pool_visits(len(pools.domain))`. A fed position's `candidates_below` and `greedy` become `replay_steps(phase, pools, position, i32(pools.level[parent]) - 1)`; the rest of the branch is unchanged. Comment: a fed region replays its recorded run up to one level under its parent's.
- `replay_steps :: proc(phase: Phase, pools: ^Pools, position, cap_level: i32)`: over `pools.steps[record_first[position]:record_end[position]]` in order: when `i32(pools.level[step.candidate]) + 1 > cap_level`, `when ODIN_TEST { pool_partial_replays += 1 }` and return; else `count_pool_visits(1)`, `export[step.candidate] -= step.need`, `level[step.candidate] = step.level`, `draw(phase, pools, step.candidate, position, step.need)`. Comment: the capped run is the uncapped run's prefix (0373's rule 6), so this is today's capped greedy without its scans.
- `candidates_below` goes from `solve.odin` (no caller left); the test keeps a copy.
- `downward_room :: proc(phase: Phase, pools: Pools, position: i32) -> i64`: the room `reachable` computes today for a position on the path, moved out unchanged: a non-feeder's `min(net, upper) - lower - passed`, a feeder at its parent's level `export - lower`, else `export`.
- `reachable :: proc(phase: Phase, pools: ^Pools, candidate, bound: i32) -> i64` (by pointer now): `clear(&pools.path)`; from `parent[candidate]` up, while the position is not `bound` and `reach_pass[position] != pass`, append it; `reach` is `source[bound]` when the walk stopped at `bound`, else `reach[position]`; then over `path` from its end: `reach = min(reach, downward_room(position)) + source[position]`, stored in `reach[position]` with `reach_pass[position] = pass`; `count_pool_visits(len(pools.path))`; returns `reach`. Comment: the least over the path of an edge's room plus the sources below it, as a running value down from `bound`, each position once a pass. No recursion.
- `draw`: `count_pool_visits(1)` in its loop; otherwise unchanged.
- `greedy :: proc(phase: Phase, responses: []Response, pools: ^Pools, candidates: []i32, bound: i32, fill: []i64)`: `cap_level` goes, every caller now passes `LEVEL_FULL`; the skip becomes `pools.done[candidate] || pools.level[candidate] >= LEVEL_FULL`, still without marking it done. Each pass starts with `pools.pass += 1` and `count_pool_visits(len(candidates))`. `reachable(phase, pools, candidate, bound)`. After a step, with `fill`, also `append(&pools.steps, Greedy_Step{chosen, pools.level[chosen], chosen_need})`. Comment: "none above cap_level" goes; with fill each step is also recorded.
- `fed_fill`: after `settle_domain`, `record_first[position]` and `record_end[position]` both `i32(len(pools.steps))`, before the return for no candidates; after its greedy, `record_end[position] = i32(len(pools.steps))`. Comment: its run is recorded for the walks above it.
- `settle_levels`: `settle_domain(phase, pools)`, `greedy` without the cap.
- Header comment, after the pool's sentence: each fed region's run is recorded once, uncapped, and replayed up to its parent's level by every walk that meets it (0390).

### Why the output is identical

- Memo: unrolled, `down(x) = min(down(parent x), room(x)) + source(x)` from `down(bound) = source(bound)` is today's least over the path of `room + sources below`, since adding a constant passes through a min; exact in integers. A pass only marks candidates done, so nothing `reachable` reads changes inside a pass.
- Same pools: a fed region's domain and everything its settle and run read or write lie in its subtree (no path inside it reaches a feeder: their subtrees are skipped), and depend only on its level, its poor level in every walk that holds it fed and in its own `fed_fill`; inner fed regions the same, by induction. So at its run the pools in its subtree are the same in `fed_fill` and in every walk.
- Prefix: from the same pools the greedy takes the least level first; levels only rise and sources and rooms only fall inside a run, so a candidate done stays done and the levels bought never fall. A run capped at μ makes exactly the uncapped run's steps that buy a level up to μ, in its order. 0373's inward room for a feeder at its parent's level never enters (no feeder on these paths), and what sources a replay leaves is read only later in the walk, as today.
- Replay: each step sets the recorded export and level and makes the same draw from the same pools; it stops on the capped run's own test. So `drawn`, the take, the surplus and every later step are today's.
- Records exist: a walk makes a position fed only when its parent's level is above its poor level, so `poor_level < LEVEL_FULL` and `region_levels` ran its `fed_fill` earlier in reverse pre-order. The brute force must do the same (Tests).

### Work

n positions, d the tree's depth, h the most fed regions nested on one root path (a position is walked at most h + 1 times, 0373), S the steps of the real runs (each fed region's uncapped run and each domain root's run, once each), P their passes (S plus one a run, at most 2n runs), R the replayed steps (a record replayed at most once a walk: R at most (h + 1) times the recorded steps). Visits: at most 2n(h + 1) for walks and settles, 2n a pass (its candidates and each position on their paths once), d + 1 a drawn or replayed step: 2n(h + 1) + 2nP + (S + R)(d + 1), near n(h + S), the size times the levels moved, plus the replays' draws, each the length of the step's own draw. Today adds every fed region's capped rerun in each of its walks, each pass walking every candidate's path: quartic on the nested chain. In these visits the new work is never above today's on any netlist: the walks are the same, a replay is its rerun's draws, and a memoised pass computes at most the positions today's pass walks.

The model, visits as the test counts them (walk and settle positions, positions `reachable` computes, draw positions, each pass's candidates, replayed steps):

| Netlist | Nodes | Today | Replay alone | After |
|---|---|---|---|---|
| `nested_chain_netlist(40)` | 81 | 152,390 | 18,280 | 7,620 |
| `nested_chain_netlist(80)` | 161 | 2,037,980 | 114,960 | 29,640 |
| `nested_chain_netlist(160)` | 321 | 29,824,760 | 799,520 | 116,880 |
| `nested_chain_netlist(320)` | 641 | (the review's `reachable` alone: 445,146,000) | 5,925,440 | 464,160 |
| `cost_netlist(false, false)` | 2,701 | 5,530 | 5,530 | 5,530 |
| `cost_netlist(true, false)` | 2,701 | 88,502 | 88,502 | 88,502 |
| `cost_netlist(true, true)` | 2,771 | 2,078,428 | 2,035,267 | 1,545,432 |

After, on the nested chain: about 1.13 n² (641 nodes: walks 103,681, settles 52,001, `reachable` 51,679, draws 51,359, pass candidates 154,399, replayed steps 51,041). `reachable` alone, the review's metric: 859, 3,319, 13,039 and 51,679. On the generators case the fed regions' uncapped runs are the work (45,610 steps, each a draw of about 12 positions), not repetition.

Memory, per tree in the temp allocator: 16 bytes a recorded step (the `fed_fill` runs' steps, which today's code also runs: 639 on the 641 node chain, 45,610 on the generators case, 730 KB) and 28 bytes a position.

### Tests, `src/netlist/netlist_test.odin`

- `plain_region_levels`, `plain_fed_fill`, `plain_settle_levels`, `plain_settle_domain`, `plain_greedy`, `plain_reachable` and `plain_candidates_below`: verbatim copies of `region_levels`, `fed_fill`, `settle_levels`, `settle_domain`, `greedy`, `reachable` and `candidates_below` as they stand at the item's base, renamed and calling each other, nothing else changed. One comment above them: the pool as before 0390, each fed region's capped greedy rerun in every walk and every path walked, the reference of the replay and the memo.
- `NESTED_FED_NETLISTS :: 500` and `nested_fed_netlist :: proc(seed: int) -> Test_Netlist`, in the temp allocator, `pick` and `rand.int_max` on the seed's generator as in `brute_force_netlist`: depth `pick(2, 25)`; node 0 offers 1,000,000,000 J when `rand.int_max(2) == 0`, else `pick(0, 50_000)`; per chain node in order: a new node asking `1000 * pick(1, 100)` J behind an edge to the previous chain node (node 0 first) of `max(demand * pick(1, 999) / 1000 + pick(-30, 60), 0)` J, then `pick(0, 3)` feeders on it, each asking `1000 * pick(1, 9)` J and offering `demand * pick(100, 1500) / 1000 + pick(0, 50)` J behind an edge of `pick(0, offer + 10)` J. Comment: fed regions nested deep with feeders of several joules a level and rooms of many, so the recorded runs are long and the caps cut them. (The model's form of it: about 3 replays cut inside their record a netlist.)
- `pools_differ :: proc(t: ^testing.T, netlist: Test_Netlist, seed: int) -> (differing: int)`: `solve_test_netlist`, then per tree a phase (`make_phase`, `set_supply_phase`), `region_levels`, its levels cloned, `plain_region_levels` on the same phase, the two compared; again with `set_charge_phase` from the solve's outputs when it returns true (phase 2's uneven bounds). Each difference counted and named with seed, tree and phase.
- `test_replayed_pool_matches_the_plain_pool`: `pool_partial_replays = 0`; `pools_differ` over `brute_force_netlist` and `light_cable_netlist` (both forms) for their seed counts, `feasibility_netlist` for `FEASIBILITY_NETLISTS`, `nested_fed_netlist` for `NESTED_FED_NETLISTS`, `nested_chain_netlist` at depths 1 to 40 and the three `cost_netlist` cases, `free_all` after each. Expects 0 differing and `pool_partial_replays > 0`. Marked slow if `build/test_times.tsv` says so.
- `test_nested_fed_regions_stay_within_the_visit_bound`: for depths 40, 80, 160 and 320, `pool_visits = 0`, `solve` of `nested_chain_netlist(depth)` (phase 1 takes the slow path, phase 2 has no store), `log.infof` the visits and n, expect `4 * pool_visits <= 5 * n * n`. Comment: the design's bound for this shape and the model's counts (7,620, 29,640, 116,880, 464,160; today 152,390, 2,037,980 and 29,824,760, and 445,146,000 `reachable` visits alone at 641). The implementer reports its four counts: they equal the model's when the counting sites are as above, and a difference is named in the report.
- `brute_force_responses`: at its start `clear(&pools.steps)` and zero `record_first` and `record_end` (fresh, as `make_pools` leaves them for each assignment). In the capacity 0 branch, after `thresholds[position] = {alone, alone}`, when `alone < LEVEL_FULL`: `fed_fill` of the position, its fill returned to `spare_tables`, its net unused: such a child is fed whenever its parent sits above `alone`, and today's code ran its capped greedy there, which the replay needs recorded. No level of the reference changes. `brute_force_levels`' comment: it shares the replay as well.
- Unchanged and passing: every other test, the brute force on 3,000 netlists, the definition test on all its sets, the hand cases, `test_solve_is_deterministic`.

### Night window

`test_netlist_solve_cost` (not run by agents outside 03:00 to 06:00 Europe/Stockholm), unchanged: its five cases on `main` before the landing and on the item's branch after. The model predicts the nested cases' pool work falling from 2,037,980 to 29,640 visits and from 29,824,760 to 116,880, the generators case from 2,078,428 to 1,545,432, the first two the same. The tables of every child with one (1,001 entries each) are untouched, so the time falls less than the visits.

### Docs

- `doc/fluids.md`: unchanged, it states no cost.
- `doc/code_map.md`: the netlist row's line count (`tools/code_graph.py --check` reports it); in the netlist bullet, `solve.odin`'s parenthesis adds "each fed region's run recorded once and replayed (`replay_steps`)", the tests add "the replayed pool against its plain form (`plain_region_levels`), the visit bound on fed regions nested 40 to 320 deep".
- The comments named under Code.

### Hand-back check

- A list that grows without bound: `steps` grows with the work, at most one entry a step the `fed_fill` runs already make, freed with the tree's temp guard; nothing draws it.
- Tests use the temp allocator only; the counters are thread local. The other lines do not apply: no save, no file, no parsed number, no shared budget changes (the output is today's).

### Decisions in this design

1. The memo goes with the replay: the replay alone leaves the uncapped runs cubic on the nested chain (5,925,440 visits at 641 nodes), the memo alone leaves the reruns cubic (2,177,840 at 321). Both: 464,160.
2. A memo per pass, not a heap of candidates by key: on the nested chain a run buys a level or two and then each candidate fails its check once, which a heap would check as well (the model at 641 nodes: 52,319 checks and 104,638 heap operations with one, 52,638 checks and 154,399 pass candidates without, the same levels), and the heap changes more code.
3. The record holds the level after each step, so the replay needs no binary search, and no cut level: the cut is the capped greedy's own test on the replayed pools, so the record stays 16 bytes a step.
4. `greedy` loses `cap_level` and `settle_domain` loses `responses`: both only served the capped rerun.
5. The count lives in test builds only, thread local, through one helper; the visit bound is asserted on the shape it was derived for, 5 n² / 4 over the model's 1.13 to 1.16 n².
6. The old pool stays in the test file as `plain_*`: it is the only check that a replay is the run it stands for.

### Questions to the main agent, with provisional answers

1. The replays still walk their draws in every walk that holds the region (R × d). On the review's chain that is 51,359 of 464,160 visits. On a chain built so that every fed region's cable keeps spare room and one deep generator climbs through all of them, the work stays cubic in both forms (82 nodes: 1,119,510 today, 859,655 after; 162 nodes: 8,569,902 and 6,507,783): there each fed region's own `fill` run raises the generator to full through the chain, which 0373's fill needs and this item cannot remove, and the replays are about a third. A replay of O(1) a step (a skip pointer to the next source above, a difference array for `passed`, made exact once a walk) would take that third, by my estimate about 40 lines. Provisional: accept, no follow-up unless the night measurement or a save shows it.
2. The `plain_*` copies, about 150 lines, stay as the pool's plain form; a later item that changes the pool's rule changes both or removes the test with a log line. Provisional: keep.
3. Test only globals in the leaf package: `when ODIN_TEST` thread locals, no production cost, no signature carrying a counter. Provisional: accept.

### 0389

Not designed here. This change touches `Pools`, the walks, the replay, `reachable`, `draw`, `greedy`, `fed_fill` and `settle_levels`; 0389's `repair_dispatch` and `spread_over_rooms` are untouched, and `test_replayed_pool_matches_the_plain_pool` compares levels only, so 0389's dispatch changes do not reach it.

### Decisions (main agent, 2026-11-13)

1. Approved: the recorded steps replayed, and `reachable` memoised within a pass. Both, since the model shows either alone leaves a cubic term.
2. The remaining cost (replays re-walking their draws, and 0373's fill runs on a chain whose every fed cable keeps spare room: 6.5 million visits at 162 nodes in the model) is accepted here. Constant time replay steps are a follow-up only if the night's figures or a save ask for it; noted in `SUGGESTIONS.md` at the landing.
3. The `plain_*` copies of the old pool stay in the test file as the equality test's reference.
4. The test only thread local counters are accepted, as `field_water_span_count` is.
5. The designer's Python model is at `tmp/0390_replay_model` in the main checkout (untracked): a reference to read and compare counts against, never ported line by line and never run from the tests.

### Deviations (implementation, 2026-11-13)

1. `pool_visits` and `pool_partial_replays` are declared in every build, not inside `when ODIN_TEST`: `./build.sh check` type-checks the test files without `ODIN_TEST`, so the tests' references to them did not resolve. Only their writes stay under `when ODIN_TEST` (`count_pool_visits`, `replay_steps`), as `data_edits_directory` gates its read. A release build carries two thread local ints it never writes.
2. `pools_differ` runs both forms on a phase through a helper, `replayed_levels_differ`, shared by phase 1 and phase 2, and `test_replayed_pool_matches_the_plain_pool` logs the netlists compared, the differing count and the replays cut short.
3. `tools/code_graph.py --check` prints no line counts: the netlist row's 1132 is `wc -l` of `netlist.odin` and `solve.odin`, as its 1056 was.
