# 0334: Bodies that share a spill saddle settle

Status: landed (2026-11-11, 6a58a2c)

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

## Specification (design, 2026-11-07)

Designed against `main` at 010f25a (the water code is the same at 5153193) and prototyped in a scratch copy; the probes and the prototype's diff are kept in `tmp/0334/probe/`.

### Cause

A flood claims a sample whose slab straddles its running sill, and only a slab wholly under the sill is beyond a saddle (`run_water_body_flood`, `world_field_water_body.odin:828`). On the diagonal a slab is 1.73 samples tall, so a flood that crosses its spill saddle claims samples on the far side whose lower part lies under its level: the body holds water in the other basin, joined to its own water only over the saddle (the fringe). On lake 0 the main lake owns 34 fringe components and the side pocket 23, of 1 to 10 samples each; not one holds its body's seed or a sample wholly under its level. The other basin's flood meets that fringe low in its own basin and merges it as water joined under water (`:840-847`): the side pocket's seeding flood merges the main lake at sill -0.42, under its level -0.18 (samples from the generated level). The merge's join level is the main lake's level, under the saddle at 0.29, so by 0300's rule 1 the flood stops at the main lake's released water beyond the saddle, and `finish_water_body_flood` (`:885-901`) wakes it as front (3,546 samples, 797,887 fill). That front seeds; its flood merges the pocket through the pocket's fringe in the main basin (sill -0.83, under the pocket's level -0.05) and wakes the pocket. Every 20 ticks, for good. The rule that releases the water: the merge assumes another body's wet sample, reached at a sill under that body's level, joins its water under that level; a fringe sample does not. A fringe forms on the +y test chunks too, with tops 0.01 to 0.04 samples over the sill: in `test_two_joined_caves_pumped_under_their_passage_part` on `main` the second cave's seeding flood merges the first through it and wakes the first cave's water once before the two settle apart.

### The rule

1. A flood merges another body at a wet sample only when that sample joins the body's water under its level: a breadth first search from it through that body's loaded samples under its level reaches the body's seed or a sample wholly under the level. A fringe sample straddles the level (it was claimed straddling a sill at or over the level), so a fringe component holds neither.
2. A wet sample that does not join is taken from its owner as a dry one is, and every sample a flood takes from another body carries the volume that body's curve holds in the cell at its level, so that body's level holds. For a dry cell that is 0, or the band's rounding.

Two bodies that share a spill saddle end as two bodies at rest, each owning the fringe in its own basin. One body is no option: the union spans a saddle above its level, which 0300's rule 2 parts at its next flood.

### Code (`src/world_field_water_body.odin`)

- `water_sample_joins_body_water :: proc(world: ^Field_World, id: Water_Body_Id, start: Sample_Coordinate) -> bool` (new, before `run_water_body_flood`): breadth first from `start` (a sample `id` owns, under its level) over the six neighbours that are loaded, not ground, owned by `id` (`water_owner_of(id)`) and with a bottom under its level; true at the first sample that is the body's seed or whose top (`bottom + span.height`) is at or under the level, false when the queue runs out. The queue and the visited set on `context.temp_allocator`, as `settle_water_body_seed` does. The result is a property of the set, so the visiting order does not matter. Comment: rule 1 and why a fringe holds neither.
- `run_water_body_flood`: in the other body branch, after the sill test, `merge_into_water_flood` runs only when `water_sample_joins_body_water(world, other, entry.sample)`; otherwise the branch falls through to the claim, which takes the sample. The comment above the branch names the fringe and 0334.
- `take_water_body_cell :: proc(world: ^Field_World, from, to: Water_Body_Id, span: Field_Water_Span)` (new, beside `claim_water_flood_sample`): with `body := &world.water_bodies[from]`, `held := volume_of_water_body_level(body, body.level)`, then `remove_water_body_cell(body, &body.loaded, span)`, then the share `held - volume_of_water_body_level(body, body.level)` moved from `body.volume` to `world.water_bodies[to].volume`. `claim_water_flood_sample` calls it in place of its bare `remove_water_body_cell`, before its `relevel_water_body` and `free_empty_water_body`, which stay. Its doc comment: another body's sample leaves that body with the water its curve holds there.

No save, record or network layout change and no new data key: the decision reads saved state only (owners, levels, seeds), so a loaded machine and a lockstep peer decide alike and a pending flood resumes alike. An old save loads unchanged; a body that holds a fringe keeps it until a flood of the other basin takes it.

### Tests

- `world_field_water_body_test.odin`, unit: `test_two_pits_sharing_a_ridge_settle_apart`. Helpers: `RIDGE_TEST_CHUNK :: Field_Chunk_Coordinate{58, 58, 58}` (on the diagonal, slabs about 1.73 samples tall); `ridge_test_part :: proc(local: [3]i32) -> int` with `u := local.x - local.y`, `v := local.x + local.y - 2 * local.z`: 0 when `abs(u) > 10 || abs(v) > 14`, 1 (pit A) when `u < -1`, 2 (pit B) when `u > 1`, else 3 (the ridge); `make_ridge_test_chunk :: proc() -> ^Field_Chunk`: ground everywhere except air where the part is not 0 and the sample's bottom lies at or over the part's floor and at or under the reference plus 8 samples, the reference being the bottom of local {16, 16, 16} and the floors the reference less 6 samples (A), less 5 samples (B), the reference itself (the ridge); `pour_ridge_test_pit :: proc(world: ^Field_World, chunk: ^Field_Chunk, pit: int, level: i64) -> (total: i64)`: `set_field_water` with `field_sea_fill(level, span)` into the pit's air samples no one owns (a sample another body owns keeps its byte), the sum. For each order (A then B, B then A), with `water_body_test_tuning`, the levels A at the reference less 127 and B less 76 (both under the ridge): pour the first pit and settle (under 200 ticks, one body); assert the precondition, that body owns a sample in the other pit under its level for which `water_sample_joins_body_water` is false; pour the second pit and step until settled, at most 200 ticks, summing seeds and merges. Assert settled, two bodies, the lowest air sample of each pit owned by a different body, `!any_water_awake`, `conserved_water` equal to the two pours, no merge and one seed. Measured: the fringe is one sample in either order; settled 20 and 21 ticks after the second pour; on `main` neither order settles, 75 seeds and 75 merges in 1500 ticks (so too at chunks 40 and 80, and for three of four other depths and levels at 58).
- `generation_planet_waters_test.odin`, slow: `test_shipped_lakes_settle_under_bodies_streamed`, beside `test_shipped_lakes_settle_under_bodies`, for the lakes nearest (65.17, 151.40), (72.02, 143.04) and (71.69, 136.82) at 8 km and 1 m with the shipped tuning: the centre chunk inserted and settled (under 600 ticks), its 26 neighbours in (dz, dy, dx) order from -1 to 1, 30 ticks apart, then settled within 600 ticks, with nothing awake and no still water no one owns. On `main` they never settle (2000 ticks: 234, 893 and 1,758 awake); with the change 0, 75 and 0 ticks after the last arrival. It takes about 1.4 times the existing test (73.6 s against 52.8 s unoptimised on a loaded machine), so it is marked slow; the reverse order is the unit test's and the probe's. Factor the lake's centre chunk out of the existing test into `shipped_lake_centre_chunk :: proc(generation: Planet_Generation, lake: Planet_Lake) -> Field_Chunk_Coordinate` and use it in both.
- Every other test unchanged. With the prototype the 172 tests of the water files pass (`world_field_water_body_test.odin`, `world_field_water_test.odin`, `field_water_pump_test.odin`, `field_water_tools_test.odin`, `world_field_water_look_test.odin`, `render_water_test.odin`, `world_field_streaming_test.odin`, `simulation_field_test.odin`, `world_water_test.odin`, `generation_planet_waters_test.odin`), the conservation, hash, save and part tests among them.

### Docs

- `doc/architecture.md`, The water field, Bodies, the flood bullet: the merge also needs the sample to join the other's water under its level (`water_sample_joins_body_water`, rule 1 above in a sentence); a wet sample that does not is the other's fringe and is taken from it as a dry one is; a sample taken from another body carries the volume its curve holds there.
- The same section, the generated lakes bullet: the lake settles into bodies whether its chunks arrive together or one by one (both tests named); drop the sentence on the three lakes and 0334.
- `doc/log/`: the landing's section (the main agent's).

### Hand-back check

- A new participant in a shared budget: the search runs outside `flood_visit_budget`, once per wet sample of another body a flood meets under that body's level. Over every lake at 4, 8 and 16 km in three arrival orders the largest search is 513 samples (`tmp/0334/sweep_fix_arena.log`); it stops at the first sample wholly under the level, so only a fringe, which is small, or water thinner than a slab is searched through.
- A changed save layout: none (above).
- Tests use no state directory: the new tests build their worlds in memory.

### Decisions

- Take, not wall: walling the fringe partitions the basin it lies in. In 0300's caves the walls cut cave 2 into separate bodies, and `test_two_joined_caves_pumped_under_their_passage_part` and `test_a_joined_body_saved_and_loaded_parts_alike` failed.
- The share moves with the cell: taking the cell alone raised its owner's level (same volume, fewer cells) until its own cells read as wholly under it and the merge fired anyway, a new flip in the same two tests.
- The share for every take, dry ones included, not only for the new path: one rule; a dry take today raises its owner's level by up to a band's rounding. The prototype ran it so.
- Wholly under the level as well as the seed: the seed alone would search through a deep lake's whole water at every merge; the seed covers water thinner than a slab, which holds no sample wholly under its level.

### Measured with the prototype

Every lake at 4, 8 and 16 km (14, 31 and 15 lakes) streamed in the order above, in the reverse order and all at once settles with nothing awake and no still water no one owns: 179 of the 180 runs within 2000 ticks, the nine runs `main` leaves unsettled for this item's fault within 75 ticks of the last arrival, and the reversed 8 km lake 27 after 2,622 (`tmp/0334/sweep_fix_arena.log`, `sweep_main_arena.log`). The water balance (final, to the sea and dropped against the inserted water, under the shipped tuning) is at most 55 fill units short with the change, as on `main` (up to 249). On `main` 10 runs are not settled at 2000 ticks: streamed 4 km lakes 6 and 7 and 8 km lakes 0, 5 and 6; reversed 4 km lake 7, 8 km lakes 6 and 27 and 16 km lake 12; all at once 4 km lake 7. The reversed lake 27 stands at 2000 ticks exactly as with the change (4,290 awake, a flood pending): it (79.46, 40.95, 3 m deep) stands 0.69 samples over the pour point the bodies' flood finds, so it drains about 680k fill over its sill while each flood splits its top layer to the front, which seeds and merges it again. That is not this item's fault; see the question below.

### Question for the main agent

- Lake 27 settles, slowly. A generated lake whose level stands over the pour point the bodies' flood finds drains its excess through the weir while every flood splits its over-sill layer to the front and the front seeds and merges it again. Should that be a new item (the generation fills to the pour point the flood finds, or a flood keeps an over-sill body's top layer as its volume)?

### Decisions (main agent, 2026-11-07)

1. The share moves with every take, dry ones included, as designed.
2. The join search is capped, so a tick's work stays bounded where water thinner than a slab spreads wide (a flooded flat holds no sample wholly under its level, so the search would run to the seed): `water_sample_joins_body_water` takes `limit: int` and answers true (merge, as before 0334) once it has visited `limit` samples; the flood passes `WATER_JOIN_SEARCH_LIMIT :: 4096`, eight times the largest search of the sweep. The answer stays a function of saved state, so peers still decide alike. Test `test_a_join_search_past_its_limit_merges` (unit): on the ridge chunk's fringe after the first pour, the search with `limit` 1 answers true where the uncapped one answers false.
3. Lake 27 (a generated lake standing 0.69 samples over the pour point the bodies' flood finds) is item 0336. The sweep's slow settling of it (2,622 ticks) is not this item's to fix.
4. The not joined answer is remembered: within one call of `run_water_body_flood`, the samples a search that answered not joined visited go into a set on `context.temp_allocator` (`water_sample_joins_body_water` takes it as `not_joined`), and a sample in it answers not joined without a search, so a fringe of n samples costs one search a call instead of about n²/2 visits. A not joined answer stays valid while the flood runs, since taking samples from the other body never joins the rest to its seed or to a sample wholly under its level; a joined answer merges, so it needs no memo. The set lives for one call, whose bounds the budget fixes, so peers still decide alike. Test `test_a_fringe_found_not_joined_is_not_searched_again` (unit).
