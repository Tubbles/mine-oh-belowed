# 0300: Bodies joined under water merge

Status: verified (2026-11-06)

Milestone: the water tech demo (0291); found by 0299's design, a follow-up to 0293.

## Goal

Under the `bodies` model two bodies whose shared sill lies under both their levels are one body of water and become one record. Found while designing 0299: two caves joined by a passage end as two bodies at levels 813179 and 813178 over a shared sill at 812935; they stop trading water by tick 2000 but the weir's merge never fires. A pump in one then lowers it alone while the other stays up, which breaks the demo's rule that pumping lowers the lake.

## Controls

None.

## Change

- `world_field_water_body.odin`: find why the merge (a lower body's level reaching the saddle, 0293) does not fire when both levels are over the sill, and merge such bodies, deterministically, the merged body keeping the lower id (the browser demo's rule).
- Docs: `doc/architecture.md` (The water field, Bodies); the log.

## Verify

- The checks and the suite.
- Tests: the two-cave scenario of 0299 ends as one body with the summed volume; a pump in one cave of a joined pair lowers the one body; 0293's merge and split tests unchanged.

## Root cause

Reproduced in scratch copies of item/0298 and of `main` at 286aee5 (0299 landed), with the verifier's scenario and a variant of 0293's trough lakes. Two defects in `world_field_water_body.odin`, each enough to keep joined water two records:

1. **The weir's merge waits for the upper body to drain.** `emit_water_body_weirs` merges only when the receiving body reached the sill *and* `excess - flow <= weir_dead_band`, the browser demo's rule plus a clause it does not have (`bodies-waves.html`, the merge loop of `tick`: `o.L >= b.spill.S && b.V >= b.capSpill`). Once the lower body's level also passes the sill, its own flood finds its spill in the upper one, and the two weirs trade water both ways: in the scenario cave 1 (body 3, level 813179, excess 14658) and cave 2 (body 5, level 813176, excess 16526) each hand the other 48 a tick for good (computed from their heads, 244 and 241). Neither excess ever falls within the band, so the merge never fires.
2. **A flood stops at a saddle under its own water.** `run_water_body_flood` takes every sample whose slab lies wholly under the running sill as the spill, the body's own released samples included. A body that spans a saddle under its level, the union of a merge above all, is cut at that saddle by its next flood, and the part beyond goes to the front as a split. So a merge across a saddle, by the weir or by a seeding flood, is undone at once. In the trough variant (lake A poured to y 13, B to y 4, trough dug), the old weir merge does fire at step 1773, after A has drained, and the survivor's reflood then splits the union. After 3000 ticks that leaves 100 live bodies, 93161 fill of front and seeds and merges every tick. In the scenario, the seed at tick 205 above the floor merges cave 1's lake and stops at the hole's saddle. That is how 0299's 23 seeds of tick 361 begin.

The demo hides the second defect only by accident: `mergeKeep` relabels the absorbed cells but leaves them out of the survivor's cell list, so its next flood never splits them. That is not a rule to port. The demo does have the real rule in its edit path (`flood(b, allowInternal)`, `internalMax`): a body may span internal saddles while its level stands over them, and it floods again (and splits) once its level falls under the highest.

## Specification (design, 2026-11-06)

Designed against `main` at 286aee5 (0298 and 0299 landed). Prototyped there in a scratch copy:
- The 0299 scenario becomes one body at tick 225 (178 ticks after the carve). 0299's test reports its last seed, merge or flood visit 179 ticks after the carve, against about 1049 before.
- The trough variant becomes one body through the new merge pass at step 1044 (pour to y 13), 1028 (y 14) and 1028 (y 16), quiet from the next tick.
- The pump and part tests below hold.
- The 151 tests of the water test files all pass unchanged: `world_field_water_body_test.odin` (0293, 0298 and 0299 included), `world_field_water_test.odin`, `field_water_pump_test.odin`, `field_water_tools_test.odin`, `world_field_water_look_test.odin`, `render_water_test.odin`, `world_field_streaming_test.odin`, `simulation_field_test.odin` and `world_water_test.odin`.

The save fields below were not prototyped.

### The rules

1. **A flood passes a saddle into its own water** (the demo's internal saddles). A sample beyond a saddle (`bottom + span.height <= flood.sill`) is still the spill, except when it is one of the flood body's own released samples (`WATER_OWNER_RELEASED`) and the sill is at or under the flood's join level (`flood.sill <= flood.join_level`). Then it is claimed like any other sample, and the flood records the saddle (`flood.joined_sill = max(flood.joined_sill, flood.sill)`). No wet test is needed: the slab lies wholly under the sill, so it lies under the level.
   - The join level is the body's level at a fresh start. It is 0 for a seeding flood, which has no water and no released samples. `merge_into_water_flood` raises it to the absorbed body's level, whose released samples are water up to that level.
   - Another body's sample beyond a saddle stays the spill. Rule 3 merges it in the next tick.
2. **A body that joined water floods again from its lowest sample.** A flood that descends through joins pops samples out of bottom order, so its running sill, and the spill it reports, can be too high. In the scenario, a seed on the floor that merges the caves would report the floor's 813438 where the passage's 812935 is the real pour point.
   - So at the finish, when `flood.joined_sill > 0` and the body's lowest loaded sample (`lowest_owned_water_sample` over `body.chunks`) has a lower bottom than the seed, the seed moves there and the body is dirty. The next flood starts at the bottom and finds the true spill.
   - It converges: the seed only ever moves down, and a flood from the region's lowest sample finds no lower one.
   - The body also keeps the highest saddle it spans (`Water_Body.joined_sill`, 0 for none). When its level falls under that saddle, at the finish or at any relevel (a pump, a weir, an absorption), it is marked dirty. The next flood's join level is then under the saddle, so it stops there and splits the far side to the front, as today's flood does.
3. **Bodies joined under water merge.** A new pass, `merge_water_bodies_joined_under_water`, runs each tick between the refloods and the weirs, in id order. It replaces the weir's merge clause.
   - A body merges with the body that owns its spill sample when the body is alive, not the sea, not dirty and not pending, has a spill that is not the sea's, and holds `volume >= spill_volume`, and the spill sample is loaded and not ground. The other body must be alive, not the sea, not the pending flood's (a released owner is skipped) and have `level >= spill_level`.
   - `merge_water_bodies(world, min(id, other), max(id, other))` does the merge. The lower id survives, as the demo does and as 0293 already did.
   - The survivor takes the lower seed of the two and floods again (dirty) in the next tick, and by rule 1 that flood keeps the union whole. The union's level is at or over the sill: each volume is at least its curve's volume at the sill, and the curves add, so the join passes.
   - The weir then waits that tick, since the survivor is dirty. The weir's own merge clause goes. A body that drains to its sill while the other rose to it is the same condition, one tick later.

Conservation: a merge adds volumes and curves (`merge_water_bodies`, unchanged). A join claims the body's own released samples, whose water is already in its volume. A split hands the unreached samples' bytes from the volume to the front (`finish_water_body_flood`, unchanged). The conserved sum was exact every tick in every prototype run.

Determinism: integers only. The pass runs in id order. The new flood and body fields are saved and hashed with the table. The relocation and the dirty marks follow from the saved state.

Cost: the relocation scans the body's loaded chunks once, and only at the finish of a flood that joined. That is the same order as the finish's sweep of the old chunks.

Interaction with 0299: `free_empty_water_body` and the sweep are untouched. A merged body has cells, and a body freed empty has no joins. `absorb_seed_candidate` still runs at a seeding finish before the relocation; the relocation only sets the seed and `dirty`.

### `world_field_water_body.odin`

- `Water_Body`: add `joined_sill: i64` after `base`, with the comment: the highest saddle its last flood passed under its water (rule 1), 0 for none, since levels are never negative; the body floods again when its level falls under it.
- `Water_Flood`: add `join_level, joined_sill: i64` after `sill, rise_limit`, with the comment: the level under which the flood's released samples are water (the body's level at a fresh start, 0 for a seeding flood, raised by a merge), and the highest saddle passed into them.
- `relevel_water_body`: after `write_water_body_fills`, `if body.level < body.joined_sill { mark_water_body_dirty(world, id) }`.
- `start_water_body_flood`: in the `fresh` branch, after `flood.rise_samples = ...`, add `flood.join_level = flood.seeding ? 0 : body.level`. A restart keeps it, since the bodies merged so far are dead and their samples are still released. In both branches, beside `flood.active, flood.body = true, id`, add `flood.joined_sill = 0`.
- `end_water_body_flood`: add `flood.join_level, flood.joined_sill = 0, 0` after `flood.has_candidate = false`.
- `merge_into_water_flood`: after `body.volume += absorbed.volume`, add `world.water_flood.join_level = max(world.water_flood.join_level, absorbed.level)`.
- `run_water_body_flood`: the saddle test becomes `if bottom + span.height <= flood.sill { if owner != WATER_OWNER_RELEASED || flood.sill > flood.join_level { <the spill as today>; return true }; flood.joined_sill = max(flood.joined_sill, flood.sill) }`. It falls through to the claim, and the other-body block is skipped because the owner is released. Comment: rule 1.
- `finish_water_body_flood`: replace `body.dirty = flood.redirty` with `body.joined_sill = flood.joined_sill` and `body.dirty = flood.redirty || body.level < body.joined_sill`. Then add rule 2's relocation: `if flood.joined_sill > 0 { owner := water_owner_of(id); if lowest, found := lowest_owned_water_sample(world, body.chunks[:], owner, owner); found && field_water_bottom(field_water_span(lowest)) < field_water_bottom(field_water_span(body.seed)) { body.seed = lowest; body.dirty = true } }`. It sits before `end_water_body_flood` (it reads `flood`). Update the doc comment.
- `water_body_joined_under_water :: proc(world: ^Field_World, id: Water_Body_Id) -> (other: Water_Body_Id, joined: bool)` (new, before `merge_water_bodies`): rule 3's test for one body, as listed above.
- `merge_water_bodies_joined_under_water :: proc(world: ^Field_World)` (new): `for index in 1 ..< len(world.water_bodies)`, `if other, joined := water_body_joined_under_water(world, id); joined { merge_water_bodies(world, min(id, other), max(id, other)) }`. A body killed earlier in the loop fails the `alive` test.
- `merge_water_bodies`: after `kept.volume += gone.volume`, add `kept.joined_sill = max(kept.joined_sill, gone.joined_sill)` and `if water_flood_entry_before({field_water_bottom(field_water_span(gone.seed)), gone.seed}, {field_water_bottom(field_water_span(kept.seed)), kept.seed}) { kept.seed = gone.seed }`. Update the doc comment: the survivor floods from the lower seed.
- `emit_water_body_weirs`: in the branch for another body's water, delete the `if !water_body_is_pending(world, other) && target.level >= ... { merge_water_bodies(...) }` clause and the now unused `target` pointer (write `world.water_bodies[other].volume += flow`). Update the doc comment: the merge is rule 3's pass.
- The file's header comment, the flood paragraph: one sentence on rule 1.

### `world_field_water.odin`

- `step_field_water_bodies`: add `merge_water_bodies_joined_under_water(world)` between `reflood_dirty_water_bodies` and `emit_water_body_weirs`. Update its doc comment.

### `simulation_field_save.odin`

- `Water_Body_Record`: add `joined_sill: i64` after `flood_visits, base`. `WATER_BODY_RECORD_BYTES :: 2 + 4 + 8 * 8 + 2 * 12`. `write_water_body_table` writes it, and `read_water_body_table` restores it into `Water_Body`.
- `Water_Flood_Record`: add `join_level, joined_sill: i64` after `sill, rise_limit`. `WATER_FLOOD_RECORD_BYTES :: 4 + 2 + 4 + 4 * 8 + 12`. Write both, and restore both with the active flood beside `sill` and `rise_limit`.
- Validation: refuse a body whose `joined_sill` fails `in_range`, and an active flood whose `join_level` or `joined_sill` fails `in_range`. Extend the reader's doc comment.
- An older record reads both as zero through the schema codec, as 0299's fields do. Zero means no joined saddle and a flood that joins nothing, which is today's behaviour, so a pre-0300 save loads unchanged and its bodies join at their next flood. No remap. The comment above `Water_Flood_Record` names the 0300 fields too. As with 0299, there is no log line at load: nothing in the file tells an older record apart, and the landing log names it.

### Tests (`world_field_water_body_test.odin`, appended under a `// Work item 0300` comment)

Helpers:
- `water_bodies_equal` also compares `body.joined_sill`, `a.join_level` and `a.joined_sill`.
- `joined_two_cave_world :: proc(t: ^testing.T, tick: ^u64) -> Field_World` builds 0299's scenario: the basin, cave 1 `{4,0,4}..{11,1,11}`, the pour `{4,3,4}..{11,6,11}`, the hole `{7,2,7}`, settled under 400, then cave 2 `{13,0,4}..{20,1,11}` and the passage `{12,1,7}`, `{13,1,7}`. 0299's test itself stays unchanged.
- `TWO_CAVE_NEAR :: [3]i32{4, 0, 4}`, `TWO_CAVE_FAR :: [3]i32{20, 0, 11}` and `TWO_CAVE_PASSAGE :: [3]i32{12, 1, 7}`. The passage's bottom is the shared sill, 812934 in the prototype, and the body's `joined_sill` was 812935.

The tests:
- `test_two_caves_joined_under_water_end_as_one_body`: `joined_two_cave_world`, `total := conserved_water`, then 2500 ticks.
  - Every tick: `conserved_water == total`, and `water_dropped` and `water_to_sea` unchanged.
  - The first tick at which `water_body_at` gives the same body for NEAR and FAR is at most 1000 after the carve (prototype: 178), and it stays the same body every tick after.
  - In steps 1501 to 2500, `seeded`, `merged` and `flood_visits` are all 0.
  - At the end there is one live body (as measured). Every sample of both caves and the passage that is not ground is its own. Its level is at or over the passage's bottom. Its `joined_sill > 0` and `<= level`. Its volume equals `total - front_total(&world)`, so the summed water of both caves is in it.
  - Print a `0300:` line with the joining tick.
- `test_a_pump_in_one_of_two_joined_caves_lowers_the_one_body`: the world, then 1000 ticks.
  - `id` is the body at NEAR, the same as at FAR. Take the probe `{16,1,7}` in cave 2, with its byte before.
  - `displace_water_body_volume(world, id, {7,0,7} in cave 1, 6000) == 6000`. After it, the body's `level` and `written_level` are lower (prototype: 813183 to 813134, written 813168 to 813134), the probe's byte equals `field_sea_fill(written_level, span)` and is lower than before (229 to 195), and the body is not dirty.
  - Then 100 ticks: the same body at NEAR and FAR, no seed, merge or flood visit, and `conserved_water == total - 6000`.
- `test_two_joined_caves_pumped_under_their_passage_part`: the world, then 1000 ticks.
  - Displace 36000 at `{7,0,7}`. The body is dirty at once, since its level (812901 in the prototype) is under `joined_sill`.
  - Within 200 ticks (prototype: 39), the bodies at NEAR and FAR differ, and `conserved_water == total - 36000`. Cave 2's body has its level under the passage's bottom (prototype volumes: cave 1 14854, cave 2 14030).
  - Then displace 1000 from cave 1's body and run 100 ticks: cave 2's body's volume is unchanged.
- `test_a_lake_rising_to_the_sill_of_the_lake_pouring_into_it_merges_with_it`: carve both trough lakes as `carve_trough_test_lakes` does, but pour A `{2,3,4}..{9,13,11}` and B `{14,3,4}..{21,4,11}`. Settle under 300, take `total`, `dig_test_trough(world, 0)`, then 3000 ticks.
  - Every tick the sum is conserved.
  - On the tick the bodies at `{5,3,7}` and `{17,3,7}` first become one, `merged == 1` and `seeded == 0`. That is the pass, before which the two traded through the weir. It happens within 2000 ticks (prototype: step 1044).
  - Nothing seeds, merges or floods in the last 1000 ticks, and at the end there is one live body whose level is at or over the trough's bottom at `{10,9,7}`.
  - Print a `0300:` line with the step. Before 0300 this world churned: 100 bodies, see the root cause.
- `test_a_joined_body_saved_and_loaded_parts_alike`: the joined world after 1000 ticks. Round-trip the table and the chunks into a second world, as `test_a_saved_empty_body_loads_and_dies_on_the_first_tick` does. The read succeeds, and the second world's body carries the same `joined_sill`.
  - On both worlds, displace 36000 at `{7,0,7}` and run 100 ticks.
  - `water_bodies_equal` holds, the chunk state hashes are equal, and on each the bodies at NEAR and FAR differ.
- `test_a_merged_bodys_frozen_part_thaws_into_the_survivor_after_its_id_is_reused` (the coordinator's question; a guard, no code change):
  - Use the world of `test_a_lake_straddling_a_chunk_the_set_drops_keeps_its_volume`: the lake settled, chunk `{1, WATER_TEST_CHUNK_Y, 0}` encoded and removed, so the lake (id 1) has a frozen part tagged with owner 2.
  - `survivor := make_dry_water_body(world, {22,15,7}, 0)` (id 2). Then `merge_water_bodies(world, survivor, lake)`. The survivor holds one frozen part whose owner is still 2.
  - `reused := make_dry_water_body(world, {23,15,7}, 0)` takes id 1.
  - Decode the chunk and insert it again. Sample `{FIELD_CHUNK_SIZE + 5, 3, 7}` is the survivor's, the survivor has no frozen part, the reused body's chunks do not name the returned chunk, and `conserved_water` is unchanged.
  - After 50 ticks the sample is still the survivor's and the sum is conserved. In the prototype the reused body was freed empty by 0299 once the survivor's flood took its cell.

### The frozen owner tags (the coordinator's question)

No defect, as far as the code and the prototype show; no change proposed.
- Both merges forward the absorbed body's frozen parts to the survivor with their owner tags as they stand (`merge_into_water_flood` and `merge_water_bodies` append them and clear the absorbed list). They are never retagged, because the samples carrying the tag are in a chunk outside the set.
- A reused id cannot meet a stale tag: a new body only claims samples in loaded chunks, and the tagged samples sit in the missing chunk until its thaw. `thaw_water_body_chunk` hands every sample carrying a part's tag to the body that holds the part, before its owner sweep and before anything else reads the chunk.
- Two parts with the same chunk and tag cannot exist in two bodies: the absorbed body's parts all move, and the reused id can only freeze a chunk it held while loaded, which the thaw had retagged already.
- The guard test above pins this. Rule 3 keeps the lower id through the existing `merge_water_bodies` and changes nothing here. The flood's merge keeps the flood's id, as before; 0300 does not change that either (see the question below).

### Docs

- `doc/architecture.md`, The water field, Bodies:
  - The flood bullet: after "Another body's dry sample is taken from it.", add that a sample beyond a saddle is the spill unless it is the body's own released water and the saddle is at or under the flood's join level (the body's level, raised by a merge to the absorbed body's). Then the flood passes the saddle and the body keeps the highest such saddle (`joined_sill`). A body that joined water floods again from its lowest sample, so its spill is the true pour point, and floods again whenever its level falls under its joined saddle, which splits the far side to the front (0300, the demo's internal saddles).
  - The weir bullet: drop the merge parenthesis. A new sentence, or a bullet after it: each tick, between the refloods and the weirs, a body at or over its sill whose spill sample is another body's water standing at or over the sill merges with it (`merge_water_bodies_joined_under_water`), the lower id surviving with the lower seed and flooding again. Two lakes over a shared sill are one water, which a pump in either lowers (0300).
- The same file, Save format, the water bodies' table: the body record carries its joined saddle and the pending flood its join level and joined saddle (0300). An older record reads them as none. The reader refuses them outside the far limit.
- The log section is the main agent's: the two defects, the trough variant's before and after, the demo's accident, and the measured ticks above.

### Hand-back lines that apply

- **A changed save layout:** three i64 fields, read as zero from an older record, which is the old behaviour. No remap and no load log line, with the reason above, as in 0299.
- **A new participant in a shared budget:** rule 2 costs a second flood after a join, and the merge pass costs one flood of the union. Both spend the flood budget in id order like any reflood, and a merged lake's flood is never stuck behind a queue. The weir no longer trades between joined bodies, so it only sees fewer participants.
- **A number parsed from text:** none. The new save fields are range checked.
- **Tests:** temporary worlds only.

### Questions for the main agent

- `merge_into_water_flood` (a flood meeting another body's water) keeps the flood's id, not the lower id. A seed that merges a lake therefore renames it, as 0299 noted. The demo's `absorb` keeps the lower id. Changing it means retagging the flood body's claimed and released samples mid-flood, or swapping the records and the pending flood's body. That is a wider change to a saved, in-flight structure, so it is left as is. Make it a new item?
- Rule 1 joins only the body's own released water. Another body's water beyond a saddle under both levels stays the spill for that flood, and rule 3 merges it in the next tick. That is one tick of weir trade, accepted for a smaller flood change.

### Main agent's decisions (approval, 2026-11-06)

- The fix as specified: the flood's join through its own released water under `join_level`, `joined_sill` with the dirty mark when the level falls under it, the reflood from the lowest loaded sample after a join, and the merge pass of the demo's rule replacing the weir's merge clause.
- A seed's flood that merges a lake keeps the flood's id: body ids are internal and nothing keeps one across ticks but the frozen parts' tags, which follow the merge. No item.
- The one tick of weir trade before the pass merges another body beyond a saddle under both levels is accepted.
- The save's three new fields read as zero from an older record, by name, with no remap; the landing log names it.
- The frozen-tag question from 0299's review: no defect; the guard test stays.
- The worktree is made from `main` (0299 landed).
