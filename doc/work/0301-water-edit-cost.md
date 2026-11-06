# 0301: The water's cost per edit

Status: todo (2026-11-06)

Milestone: the water tech demo (0291); the bench 0293 asked for, run after 0300 landed.

## Goal

An edit at a lake costs under 2 ms in the tick, the target 0293 set, measured in the build the couch runs; idle settled water stays near zero (it does). The bench on main e16d45b (unoptimised test build, 4 cores, a 4000 m tech demo planet, a poured lake of 3438 wet samples owning 7247 across 4 chunks):

| Case | Bodies, worst tick | Teleport, worst tick |
|---|---|---|
| Idle, settled | 0.02 ms | 0.005 ms |
| Idle, the spawn's spring running | 4.6 ms (867 awake) | 15.3 ms (4180 awake) |
| Fill inside the lake | 4.6 ms | 0.25 ms |
| Dig under the lake into a cave | 5.0 ms | 19.8 ms, a mean of 9 ms for 600 ticks |
| Dig through the rim | 14.6 ms | 9.4 ms |
| Dig under the sea into a 2140-sample cave | 2.3 ms (`claim_sea`) | 13.0 ms |

Where the bodies' time goes beyond the flood budget: the 4000 visits themselves take 3.5 to 3.8 ms (about 0.9 µs a visit, where 0293 sized the budget at about 2 ms); `release_water_body_samples` at a flood's start scans every sample of the body's chunks (0.9 to 1.6 ms); `finish_water_body_flood` scans the old chunks and rewrites the fills (1.5 to 6 ms, growing with the chunks the body spans; the look's reach marks are 0.5 to 1 ms of it); a weir's level steps rerun `write_water_body_fills` (0.6 to 2.2 ms a tick); `claim_sea` is outside every budget (2 to 3 ms for the cave). The edit itself is 0.02 to 0.3 ms. Under teleport the cost is the pressure pull after a dig, up to about 12,900 visits a tick for thousands of ticks.

The optimised test build did not compile within 25 minutes here, so these are upper bounds; the release game build (`-o:speed`) compiles in 1.5 minutes. The bench's scratch test, its timer patch and its log are in the untracked `tmp/0301-bench/`.

## Controls

None.

## Change

- First measure in an optimised build: a way to run the water bench optimised that compiles in minutes (a bench mode the release build carries, as the factory benchmark has, or a test build that only compiles what it needs). If the release numbers meet the targets, record them in `doc/architecture.md` and close the rest.
- Otherwise bound the work per tick: the flood budget sized in time measured, not assumed; the release and finish sweeps visiting the body's cells (its bands) instead of every sample of its chunks; the fills rewrite touching only the bands that changed; `claim_sea` under a budget of its own, resumed next tick; the teleport pull's per-tick budget weighed against its settle time.
- Docs: `doc/architecture.md` (The water field), `doc/content.md` for changed budgets; the log.

## Verify

- The checks and the suite.
- The bench's six cases under both models in the optimised build, each edit's worst tick under 2 ms, idle settled near zero; conservation and the hash tests unchanged.
