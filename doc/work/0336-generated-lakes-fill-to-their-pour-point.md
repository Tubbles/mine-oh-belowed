# 0336: Generated lakes fill to their pour point

Status: verified (2026-11-11)

From 0334's design. Under the bodies model, the 8 km planet's lake 27 (79.46 N, 40.95 E, 3 m deep) is generated 0.69 samples over the pour point the bodies' flood finds for it. It drains about 680k fill over its sill, and every flood splits its layer over the sill to the front, which seeds and merges it again, so it settles only after 979 to 2,622 ticks, depending on the order its chunks arrive (`tmp/0334/sweep_fix_arena.log`). 0312's refine sets the level on its 2 m grid sealed on the 1 m lattice; the flood finds the pour point on the samples.

## Goal

Every generated lake at 4, 8 and 16 km stands at or under the pour point the bodies' flood finds, so it is at rest from the tick its chunks arrive.

## Controls

None.

## Change

- The refine's level agrees with the flood's pour point on the samples (the generation fills to the lower of the two, or reads the sill as the flood does). Or, if the design finds the flood's pour point wrong, the flood keeps an over-sill body's top layer as its volume.
- Old worlds keep their lakes through the record (0312's waters), or the change is recorded with one log line.
- Docs: `doc/architecture.md` (World generation, the waters), the log.

## Verify

- The checks and the suite, with lake 27 at 8 km settling under bodies as one body in every arrival order (the design found the lakes under their pour points and the flood's rule at fault, Specification).

## Specification (design, 2026-11-11)

Designed on `main` at a79cda5, against 0326's specification (designed, lands first in this stream): its tiles refine and seal lakes with 0312's `refine_planet_lake` and `seal_planet_lake` unchanged and fill them through `fill_field_chunk_lakes`, so the rule below meets its lakes as it meets 0312's, and nothing here touches its files. The numbers come from a probe in `tmp/0336/tree` (`src/zz_probe_0336_test.odin`, counters in scratch copies of `world_field_water_body.odin` and `generation_planet_waters.odin`): the shipped planet, `DEFAULT_WORLD_SEED`, every lake at 4, 8 and 16 km (14, 31, 15), 1 m unless named.

### Cause: the flood, not the generation

The generation is not over its pour point. A flood on the samples from a lake's lowest sample that passes the lake's own water (the bodies' rule, with the lake as one body) finds lake 27 at 8 km 1.10 samples over its level (the outer saddle's relief 1.11 m over it, 0.24 m on the 1 m lattice), and the main water of every lake at least 0.07 samples under its pour point (4 km lake 6). Two 8 km lakes (4 at 71.23, 141.35 and 5 at 72.02, 143.04) hold pockets apart from their main water standing 0.05 and 0.01 samples (13 and 3 fill) over their own rims, against the weir's dead band of 8 fill: such a pocket's body hands the fill over the band to the front and rests. At 500 mm one lake stands over: 4 km lake 4 (63.08, 80.90) by 0.04 samples (10 fill), a notch between the 1 m lattice's points; at 333 mm none (the least 0.01 samples under, 8 km lake 17, the largest). The seal lowered a level for three lakes only.

What the item's 0.69 read is an inner saddle: a lake's flat water covers ridges inside its basin (lake 27's deepest 2.13 samples under its level; 22 of the 60 lakes hold one). The flood stops at the first sample wholly under its sill (beyond a saddle) and calls it the spill unless it is the body's own released water under the join level (0300, rule 1). Beyond an inner saddle lies the lake's own water, still and no one's, or woken where a chunk woke its pocket's lowest sample: the seeding flood calls the inner saddle its spill, the claimed water (woken as front) reaches the volume only as the front is absorbed, the level stands over that spill, the weir hands the top layer to the front, which seeds and merges, the joined saddle splits it again. Lake 27 on `main`: 1,091 ticks streamed, 2,622 reversed, 979 together, ending as 3, 3 and 1 bodies, with 3.3 and 8.3 million awake sample ticks streamed and reversed.

### The rule

A flood passes a saddle into water no one owns whose column stands at or over its sill, as it passes its own joined water (rule 1): the saddle lies under that water. The pass keeps the saddle in `joined_sill`, so the body floods again from its lowest sample when that lies under its seed (its spill may be too high after a descent, rule 2) and parts there when its level falls under it (a pump, the weir). The claim is unchanged: the water wakes as front (0312's review).

Measured with the rule (all 180 runs: 60 lakes, streamed, reversed and the 27 chunks together; `main`'s numbers from 0334's sweep, `tmp/0334/sweep_fix_arena.log`, which `main` repeats for lake 27 and 4 km lake 2): every run settles with nothing awake and no still water no one owns. Lake 27: 0 ticks streamed (within the 30 after the last arrival), 41 reversed, 152 together, one body each time; 0 and 56 thousand awake sample ticks streamed and reversed. Together is the seeding flood's budget (4000 visits a tick for 132 ticks over 27 chunks of air under the rise cap), not the lake: the longest runs on `main` (480 ticks, 16 km lakes 4 and 11 together) are that budget too and do not change. 8 km lakes 22 and 30 reversed end as one body instead of two. One run is slower: 4 km lake 2 reversed, 158 ticks against 38, one reflood of the whole lake from a lower seed after the last arrival (rule 2), budget bound; its level holds while the flood is pending, so nothing moves on screen. The water balance stays within the rounding `main` already shows (minus 1 to 55 fill a run on both).

### Rejected

- **The generation fills to the flood's pour point.** It already does; filling to the inner saddle would part 22 lakes into ponds 0312 did not find.
- **The flood keeps an over-sill body's top layer.** The spill it found is a saddle under water: keeping the layer over a wrong spill leaves the wrong split for the first pump.
- **Claimed still water joins the body asleep with its volume** (0312's first design, rejected by its review). On top of the rule: lake 27 reversed 13 ticks instead of 41, 4 km lake 2 reversed 157; not worth reopening 0312's finding.
- **The weir waits while still water lies beyond its spill.** Lake 27 streamed stays at 1,091 ticks.
- **The column rule for still water only.** A chunk arriving with others wakes each pocket's lowest sample: counting still water only (measured with the asleep claim on), lake 27 together took 288 to 1,802 ticks, its first spill into a woken sample; counting woken water, 152.
- **A wider `lake_margin_millimetres`.** The outer pour point is not what drains.

### Changes (`src/world_field_water_body.odin`)

- New `field_sample_is_column_water :: proc(chunk: ^Field_Chunk, index: int, own: Water_Owner) -> bool`: water (`chunk.water[index] > 0`), not ground (`density <= 0`), not a spring (`water_source` bit clear), owner `WATER_OWNER_NONE`, `own` or `WATER_OWNER_RELEASED`; awake or asleep alike. Beside `field_sample_is_still_unowned_water`.
- New `field_water_column_reaches :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, own: Water_Owner, level: i64) -> bool`: whether the water standing on the sample reaches `level`. From the sample: a sample not full (`chunk.water[index] < FIELD_WATER_FULL`) answers `field_water_level(span, fill) >= level`; a full one whose top (`field_water_bottom(span) + span.height`) is at or over `level` answers true; else it steps to the sample above, the neighbour along the axis of the sample's largest absolute coordinate (ties to x, then y, then z) away from the centre (the neighbour of greatest `field_water_fine_distance`, so of greatest middle), and answers false when that one is not loaded (`field_world_cell` nil) or not `field_sample_is_column_water`. At most `MAXIMUM_FIELD_WATER_FLOOD_RISE` steps, then false. Reads saved state only (fills, owners, bits), so peers and a loaded save decide alike; it runs only for a pop beyond a saddle holding no one's water, and stops at the sill, so a walk is the far water's depth under the sill in samples. Like 0334's join search it is not charged to the visit budget.
- `run_water_body_flood`, the branch `if bottom + span.height <= flood.sill`: the sample is passed (the existing `flood.joined_sill = max(flood.joined_sill, flood.sill)`, then the claim) when rule 1 holds or when `owner == WATER_OWNER_NONE && field_sample_is_column_water(chunk, index, own) && field_water_column_reaches(world, chunk, index, entry.sample, own, flood.sill)`; else the spill as now. The branch's comment names both rules, the second as 0336: water no one owns standing at or over the sill beyond it (a generated lake over its inner saddles, still or woken).
- `claim_water_flood_sample`, `join_field_chunk_lake_water` and the weir: unchanged.

### Save, record, old worlds

No layout changes: field chunks, the body table, `Water_Flood_Record` and 0312's waters record stay as they are, no remap, no log line in the game. The generation is untouched, so an old world's lakes are the same bytes. The rule reads only what saves hold: a pending flood saved by an older build resumes under it, and a lake still settling in an old save settles under it. A lake an old save holds settled into several bodies at rest (lake 27 streamed or reversed on `main`: 3) stays so until a flood reaches it (a dig, a pour, a body marked dirty); the log names this.

### Tests

- `world_field_water_body_test.odin`, `test_a_water_column_reaches_the_level_its_top_stands_at`: `make_test_lake_chunk(0, BASIN_LOW, BASIN_HIGH, test_lake_level())` inserted into a bodies world, not stepped; from `(6, y, 6)` for y in `BASIN_LOW.y`, 6, 9 and 10 (full to half full) the column reaches `test_lake_level()` and not `test_lake_level() + 1`; with `(6, 8, 6)`'s owner set to `water_owner_of(5)`, from `(6, BASIN_LOW.y, 6)` it reaches the top of `(6, 7, 6)` and not one over it. The probe read exactly these.
- `world_field_water_body_test.odin`, `test_a_generated_lake_over_a_ridge_is_one_body_after_its_first_flood`: `make_split_test_lake_chunk(ridge)` for ridges 2 and 4 inserted into a bodies world and stepped (at most 200 ticks) until a body lives and no flood is pending; then `still_unowned_water_samples` is 0 and the body's `spill_level` is `max(i64)`. On `main` 479 and 399 samples stay no one's, the spill at the ridge; with the rule both hold at tick 20.
- `generation_planet_waters_test.odin`, `@(test) // slow` `test_a_lake_over_its_inner_saddles_settles_as_one_body`: 8 km, 1 m, shipped tuning, the lake near (79.46, 40.95) (lake 27), its 27 chunks round `shipped_lake_centre_chunk` three ways: together (as `test_shipped_lakes_settle_under_bodies`), streamed (the centre settled, then the 26 neighbours 30 ticks apart, as `test_shipped_lakes_settle_under_bodies_streamed`) and the same reversed. Each run, after the last arrival's 30 ticks for the streamed two: `settle_body_test_water` settles within 60 ticks streamed, 120 reversed, 300 together (measured 0, 41, 152; `main` 1,091, 2,622, 979); one body (`alive_water_body_count`); nothing awake; no still water no one owns. A local helper may take the order. The probe ran the three in 23 s at `-o:minimal`.
- The suite passes unchanged with the rule (the probe ran the six water test files, 103 tests, with it on).

### Docs

- `doc/architecture.md`, The water field, the flood bullet: after rule 1's sentence, the second pass (water no one owns whose column reaches the sill, `field_water_column_reaches`, the walk and its bound, why: a generated lake's flat water covers its basin's inner saddles), kept in `joined_sill` like rule 1.
- `doc/architecture.md`, the Generated lakes bullet: the new test beside 0312's and 0334's, a lake over inner saddles settling as one body in any order.
- `doc/architecture.md`, World generation, the waters: one clause, a lake stands under the pour point a flood on the samples finds, or a few fill over it where the samples see a notch the 1 m lattice misses (0336: two lakes' pockets at 1 m, one lake at 500 mm, at most 13 fill), and its water covers the basin's inner saddles (The water field).
- The log, at landing: the cause and the numbers above, the rejected rules, and the old saves' split lakes.

### Hand-back lines that apply

- Old saves: no layout change; the behaviour change (a flood passing into no one's water) is named in the log and stops no save.
- A shared budget: the walk is bounded per pop and not charged to the visit budget, as 0334's search; the rule's refloods (rule 2) spend the budget as any reflood does, measured above.
- Tests use no state directory or settings.

### Answers to the item

- The item's two forms of the change: neither. The generation stands under its pour point; the flood's pour point was wrong for water beyond an inner saddle, so the flood's rule changes and the simulation's other rules stay.
- The Verify line's first test (every lake at or under its flood's pour point) measured the wrong thing: the margins are in the log, and the settle test above checks what the item wanted.

### Questions for the main agent

1. A nightly report test logging every lake's margin to its pour point at the three presets (the probe's static flood, about 2 minutes at `-o:minimal` at 1 m, longer at 333 mm), as a guard for 0326's and 0314's changes to the relief and the finder? Recommendation: no; the settle test and the sweep's numbers in the log cover what drains, and the static flood is about 150 lines of test code to keep.
2. 4 km lake 2 reversed settles in 158 ticks instead of 38 (one reflood after the last arrival, nothing on screen). Accept, or an item to start rule 2's reflood from the lowest sample without releasing the whole body? Recommendation: accept; the reflood is 0300's correctness rule.

### Decisions (main agent, 2026-11-11)

1. No report test of the static margins. The settle test guards what drains, and the margins go to the log.
2. 4 km lake 2 reversed at 158 ticks is accepted: the reflood is 0300's rule, and the level holds while it is pending.
3. A stream of its own, from `main`, ahead of 0326: the change is the flood's branch, its tests and `doc/architecture.md`. 0326 pins `waters_test_planet` to 0312's finder, so the lake 27 test reads the same lake after it, and its change to `generation_planet_waters_test.odin` meets this one at the rebase.
4. The walk answering false at a sample that is not loaded follows 0334's search: the body floods again when the chunk arrives.
