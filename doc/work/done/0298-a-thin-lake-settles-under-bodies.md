# 0298: A thin lake settles under bodies

Status: landed (2026-11-06, 5ad39f5)

Milestone: the water tech demo (0291); found while implementing 0295, a follow-up to 0293.

## Goal

Under the `bodies` model a shallow pour on a flat floor settles into one still body, as it does under `teleport`. Found by 0295's implementer: 20 full samples poured on the 8×8 basin floor of the tools' test fixture end in a checkerboard of 254 and 0, about 50 samples stay awake for good, and a body of volume 5 forms. The bucket pours exactly this in play, so the demo's first pour on flat ground never comes to rest.

## Controls

None.

## Change

- Find the cause in 0293's front (`world_field_water.odin`: the two-pass flux, `settle_field_water_front`, the seeding after `still_ticks`, the absorption rules) and fix it there. The checkerboard suggests the flux moves whole samples between neighbours on alternating ticks, or that seeding needs a stillness the flux never reaches.
- A test that pours the fixture's 20 samples and asserts one body, no awake sample after a bound of ticks, and the volume conserved; and the same pour under teleport for comparison.
- Docs: `doc/architecture.md` (The water field, Bodies) if a rule changes; the log.

## Verify

- The checks and the suite.
- The test above; 0293's trough, breach and seeding tests unchanged.

## Root cause

`plan_field_water_front` (`world_field_water.odin`) compares the two levels from the fills the tick began with on both sides (`field_water_share_from(span, start, …, receiver_start, …)`, 0293's specification, step 3). The sender's `left` caps what it sends but never lowers its level, so a sample with several lower neighbours hands each one the full pairwise share, and a receiver takes a share from each higher neighbour. Each share is capped only by `fill_rate_per_tick` (64, a quarter of a sample).

Smallest case: one full sample at the middle of the 8×8 floor. On the fixture (x, z > 0, far up +y), the "nearer" pass is −z and −x (ground below is skipped), then +x and +z. Tick 1: the share is min(127, 64, left) each time from a level of 254, so −z, −x and +x get 64 and +z gets the 62 that is left. The sample ends at 0, below all four receivers. Tick 2: each 64 sends 32 to each lower neighbour from its tick-start level until it is empty, and the centre is back at 63. The water sits on the x+z-even cells one tick and on the odd cells the next, so it swaps sublattices every tick. With more water the pattern locks into an exact two-tick cycle. An interior full sample with four empty neighbours sends 64 + 64 + 64 + 62 = 254, everything it holds. An interior empty sample receives 62 (its −z neighbour, planned first, sends +z last), then 64, 64 and 64, which is 254, exactly its room as the promises count. A checkerboard of 254 and 0 therefore maps onto its complement every tick.

Stillness never comes. `apply_field_water_front` resets `water_still` whenever `delta != 0` or `outflow != 0`, and every sample in the cycle has both on every tick. So `settle_field_water_front` never makes them candidates. At the walls the pattern breaks, and a small fill there (1 to 5) goes still for 20 ticks and seeds a body. Its flood claims the whole sealed box as dry air. `absorb_seeded_front` then takes only the samples with `water_still > 0` and those under the new level, which is the floor's bottom plus a few fill units, so the volume is 5. The rest stays front water in the body's dry air. That water joins the body only when still (rule "own") or under the level, and neither ever happens. Reproduced on the 0295 tree: 20 full samples ({4,3,4} to {7,3,8}) end after 3000 ticks with 50 samples awake, one body of volume 5, and the floor 254/0 in a checkerboard. Teleport settles the same pour in 54 ticks (floor 60 to 99).

The browser demo (`bodies-waves.html`, `tickFront`) computes the sender's level from its running remainder (`diff=(li0+fi*hi)-lj`), which damps the sender. 0293 dropped that. Teleport (`field_water_share`) reads the live bytes on both sides while sending only what the sample held when the tick began, which is a sequential, Gauss–Seidel kind of order, and that order cannot form this cycle.

## Specification (design, 2026-11-06)

Builds on 0295 (not on `main` yet): the same stream, since 0294 and 0295 both change `world_field_water.odin`. Designed against `item/0295`'s tree. The worktree is made from `item/0295`.

**The rule.** In the front's plan, a move compares the two samples' projected fills: the fill the tick began with, plus the moves planned into and out of the sample so far this tick (its `pass.delta`). What a sample sends stays capped by `left`, its tick-start fill less what it already planned out, so it never overspends and water arriving in a tick moves on in the next. The receiver's room is `FIELD_WATER_FULL` less its projected fill, as today. This is teleport's comparison (live bytes on both sides, `left` from the tick-start fill) with the two-pass application kept. From the checkerboard, the first tick leaves exactly teleport's bytes (prototype: identical floor bytes for 19 ticks).

Water is conserved: every amount is still debited from the sender's `delta` (or `outflow`) and credited to the receiver's `delta` or to a body's `inflow`, and the caps keep every byte in 0 to `FIELD_WATER_FULL`, since the receiver's projected fill + amount ≤ full and the sender's start − out ≥ 0. Determinism: integers only, and the plan order (chunks in coordinate order, samples in sample order, neighbours in `FIELD_WATER_NEIGHBOUR_OFFSETS` order, nearer first) is already fixed by the data. The result now depends on that order, as teleport's does, and is the same on every machine.

**Code** (`src/world_field_water.odin` only; no new procedure, no data key, no save or hash layout change):
- `plan_field_water_front(world, front, pass, index, tuning, tick)`, signature unchanged. In the neighbour loop, compute per neighbour (after the earlier moves of this loop) `sender_fill := start + i32(pass.delta[index])` and `receiver_fill := receiver_start + promised`. Call `field_water_share_from(span, sender_fill, neighbour.span, receiver_fill, FIELD_WATER_FULL - receiver_fill, tuning, left)`. The film test, `if start == 0` and `left := start` stay on `start`. Rewrite its doc comment: "each the share of the two projected fills (the tick-start fill plus what this tick's plan brought and took so far), at most what it has left of its tick-start fill and the receiver's projected room".
- `field_water_share_from`: comment only, "(the bodies' front gives the projected fills, 0298)".
- The file's header paragraph "The bodies model (0293 …)": replace "every front sample plans its moves from the fills the tick began with, its own falling with every move so it never overspends and each receiver's promised fill counted against its room" with "every front sample plans its moves in the step's order, comparing the two projected fills (the tick-start fill plus the moves planned into and out of the sample so far), at most its tick-start fill less what it planned out and the receiver's projected room (0298: tick-start fills on both sides let a thin layer swap a checkerboard every tick)".

**Tests** (`src/world_field_water_body_test.odin`, on `main`'s fixture: `carve_water_test_box(BASIN_LOW, BASIN_HIGH)`, the same 8×8 floor at local y 3 as the tools' fixture, with `water_body_test_tuning()` for both models):
- `thin_pour_test_world(model: Water_Model) -> Field_World`: `make_body_test_world()` or `make_water_test_world()`, with the basin carved. `THIN_POUR_TICK_BOUND :: 120`; measured 46 ticks for the pour below, 22 for the checkerboard, and at most 53 over 144 scattered pours of 3 to 64 samples.
- `test_a_thin_pour_on_a_flat_floor_settles_into_one_body`: for each `Water_Model`, `pour_test_water({4,3,4}, {7,3,8}, FIELD_WATER_FULL)` (20 samples, 5080), then settle (`settle_body_test_water` or `settle_test_water`, limit `THIN_POUR_TICK_BOUND`). Asserts the ticks are < the bound and `any_water_awake` is false. The total is 20 × 254: `conserved_water` under bodies, `total_test_water` under teleport. Under bodies, also asserts `only_water_body` has volume 5080, level == `body_level_of_volume(body, body.volume)`, and every floor sample owned by it (`water_body_at`). Under teleport, every floor sample holds more than `minimum_fill` (measured 60 to 99). Before the fix: 3000 ticks, still awake, volume 5.
- `test_a_checkerboard_front_does_not_swap`: on both worlds, pour 254 into the 32 floor samples with x + z even. Step one tick (`step_field_water`, tick 1) on each and assert every floor byte under bodies equals teleport's. Then settle the bodies world within the bound: one body of volume 32 × 254, nothing awake. Before the fix: the even half held 996 of 8128 against teleport's 2127, and the front never settled.
- 0293's tests stay unchanged and pass: trough, breach, seeding, merge, spring, saves and hashes. With the prototype the whole suite passed (2123 tests), 0294's look tests included.
- `src/field_water_pump_test.odin` (0295): drop the parenthesis after `WATER_TOOL_TEST_LAKE`'s comment ("A thinner one … awake for good."), which is no longer true.

**Docs:**
- `doc/architecture.md`, The water field, Bodies, "The front:" bullet. Replace "every front sample plans its moves from the fills the tick began with on both sides, its own remainder falling with each move so it never overspends, a receiver's room counting what others promised it, so no receiver overfills; then every move applies at once" with "every front sample plans its moves in the step's order, comparing the two projected fills (the fill the tick began with plus the moves planned into and out of it so far), at most its tick-start fill less what it already planned out, so it never overspends and water arriving in a tick moves on in the next, and at most the receiver's projected room, so no receiver overfills; then every move applies at once. Comparing the tick-start fills on both sides (0293) let a sample hand each of four lower neighbours its share and end below them, so a thin layer swapped a checkerboard of full and empty samples every tick and never came still (0298)."
- The log: the main agent's, at landing. The weighing for it: the alternatives the prototype measured. The demo's sender-only remainder settled the pour in 164 ticks (worst 184). A divisor of shares by neighbour count (Metropolis weights) settled in 114 ticks but slowed the streams and broke 0294's `test_a_moving_stream_has_mesh_within_a_sample_of_every_wet_sample`. The projected fills settled in 46 ticks (worst 53) and passed everything.
- No `doc/code_map.md` change.

**Hand-back lines that apply:** the save layout is unchanged, and an old save loads; a front it holds runs under the new rule, which the log names. No shared budget gains a participant. The tests use no files.

**Question for the main agent:** a pour of one or two samples on this floor spreads into films (fill ≤ `minimum_fill`). Under both models these stay awake until they dry (`dry_ticks_per_step`, 1 per 60 ticks shipped, never in the tests). Under bodies, a body seeded from the thickest part leaves the films awake in its dry air, since a film never counts still. I propose no change here: films drying is 0292's rule under both models. A rule that absorbs a film resting in a body's dry air into that body would be a new item. Confirm?

### Main agent's decisions (approval, 2026-11-06)

- The projected-fill rule as specified. The alternatives the prototype measured go to the log at landing.
- The films question: no change. Films dry under 0292's rule in both models; an awake film costs a little time per tick and draws at its true share (0294). Absorbing a resting film into a body's dry air is not wanted until the playtest shows it.
- The worktree is made from `item/0295` (the stream's tip). This item lands after 0295.
