# 0334: Bodies that share a spill saddle settle

Status: todo (2026-11-07)

From 0312's second review. Under the bodies model (the tech demo's), three of the 31 lakes at 8 km never settle when their chunks arrive one by one, as they do while the player walks: lake 0 (65.166, 151.403), 234 samples awake after 2000 ticks; lake 5 (72.018, 143.041), 893; lake 6 (71.694, 136.821), 1,758. All 31 settle when the 27 chunks arrive together. Water is conserved. The fault lies in 0300's merge rules; 0312's generated lakes are what reach it.

Traced on lake 0 (ticks 853 to 1128): two bodies spill at the same saddle, 0.29 samples over the lake's generated level. Each one's seeding flood merges the other (`run_water_body_flood`) and stops at that saddle; `finish_water_body_flood` wakes the merged body's unreached samples as front, which seeds the other body again. The state flips every 25 to 75 ticks between the main lake as a body with its side pocket as front, and the side pocket as a body with the main lake (798k fill) as front.

The reviewer's probe (the centre chunk settled, the 26 neighbours arriving 30 ticks apart, then 2000 ticks) is in `tmp/0312/verify/tree_r2b/src/zz_verify_0312_r2_probe_test.odin`, its logs `tmp/0312/verify/r2_*.log`.

## Goal

Every generated lake at every preset settles under bodies, with nothing awake and no still water no one owns, in either arrival order; poured and dug water too.

## Controls

None.

## Change

- The merge and the finish so two bodies that share a spill saddle end as one body, or as two at rest, instead of releasing each other in turn.
- A test of the streamed arrival on the three lakes (or a reduced basin that reproduces the flip), beside `test_shipped_lakes_settle_under_bodies`, which inserts all its chunks at once.
- Docs: `doc/architecture.md` (The water field, the generated lakes bullet's scope "when its chunks arrive together"); the log.

## Verify

- The checks and the suite, the water conservation and hash tests unchanged.
- Every lake at 4, 8 and 16 km settles under bodies with its chunks streamed in.
