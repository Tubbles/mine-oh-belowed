# 0299: Empty bodies die and a residue above a lake rests

Status: verified (2026-11-06)

Milestone: the water tech demo (0291); found by 0298's verifier, a follow-up to 0293.

## Goal

Under the `bodies` model no body outlives its last cell, and front water resting above a lake comes to rest instead of seeding a body every tick. Found by 0298's verifier in one scenario: front water 4 deep on an 8×8 floor drains through a hole into a cave and settles, then a second cave is carved and joined to the first by a passage.

- Empty bodies: after about 361 ticks, 7 bodies stay alive for good with volume 0, no loaded bands, no frozen parts, no owned samples and `dirty` false. They count against `MAXIMUM_WATER_BODIES` and are saved. The only check that kills a body with no cells left is in `finish_water_body_flood`, which runs for the flooding body only; another body's flood can take all of a body's samples.
- Churning residue: front samples of 2 to 10 fill (above `minimum_fill`, so not films), unowned and still, above the cave lake's level, seed a body every tick that merges at once into the lake below while the sample stays front: 21 seeds and 21 merges a tick, 525 flood visits a tick, forever.

The verifier's scratch tests that reproduce both (they need the helpers in the first file) are kept in the untracked `tmp/0299-repro/`.

## Controls

None.

## Change

- `world_field_water_body.odin`: a body whose last cell another body's flood takes dies (its id freed, the same way `finish_water_body_flood` kills its own empty body), deterministically and in the same tick.
- The seeding rule (0293, `settle_field_water_front`): a still front sample whose seeded body would merge at once into a body below takes the path absorption takes, or stops seeding; the design picks the rule that conserves water and ends the churn.
- Docs: `doc/architecture.md` (The water field, Bodies); the log.

## Verify

- The checks and the suite.
- Tests: the verifier's scenario ends with no body of volume 0 alive and no seeding or merging after a stated tick bound, volume conserved; 0293's and 0298's tests unchanged.

## Root cause: empty bodies

Reproduced in a scratch copy of item/0298 (the verifier's `test_v98c_zero_bodies`, traced). The 7 bodies are seeds of tick 361, the tick the passage opens: 23 still front samples in the second cave seed in one tick, and 7 of the floods (ids 1, 7, 8, 13, 14, 19, 20) finish with volume 0. `start_water_body_flood` settles the seed away from the still sample (`settle_water_body_seed`), the flood spills at the first saddle before it reaches the sample, so `absorb_seeded_front` finds no front the body owns: the body owns a few dry samples and no water. On ticks 362 and 363 front water resting in those dry samples has a nearer neighbour that is the lake's still water, so `absorb_front_water` (`settle_field_water_front`) gives it to the lake and removes the cell from the dry body, which is left with no cell. Nothing kills it: the only check is in `finish_water_body_flood`, for the flood's own body.

The paths by which a body loses its last cell without dying, in `world_field_water_body.odin` and `world_field_water.odin`:

- `claim_water_flood_sample`: another body's flood takes a dry sample (relevels only).
- `absorb_front_water`: front water in a body's dry air joins another body or the sea (the verifier's 7).
- `claim_sea`: the sea takes the cell (marks the body dirty; its reflood kills it, but only once the flood budget reaches it).
- `follow_field_terrain_with_bodies`: the cell turns ground (the same, through the reflood's lost seed).

Not paths: `merge_into_water_flood` and `merge_water_bodies` kill the absorbed body; a pending body's own release and the split at the finish end in `finish_water_body_flood`'s kill; a freeze moves cells to a frozen part.

## Root cause: churning residue

`settle_field_water_front` seeds every still front sample no one owns (fill > 0, still for `still_ticks`) through `seed_water_body`, and the seed's flood starts from the settled seed, not from the sample. On the basin floor the thin lake of 0298 (body 4: 559 fill, level 813438, at its sill, spilling into the hole) owns the floor samples popped before the hole. The residue (21 samples of fill 2 to 10, held still by the front's dead band in `field_water_share_from`) lies in the floor's outer samples, whose bottoms are higher (farther from the axis), beyond the lake's flood. A residue sample's walk ends beside the lake ([5,3,8] or [6,3,8]); the seeding flood merges the lake (`run_water_body_flood`: a seeding flood takes another body's wet sample when its sill is at or under that body's level, 813438 at 813438), claims the lake's samples, and stops at the hole's saddle (`bottom + span.height <= flood.sill`) before it reaches the residue sample. `absorb_seeded_front` takes only front the body owns, so the sample stays front, no one's and still, and seeds again the next tick; nothing records that its seed missed it. `merge_into_water_flood` keeps the flood's id, so the lake's id alternates between slots 2 and 4: 21 seeds, 21 merges and 25 visits each, every tick. The volume 0 bodies above have the same root: a seed whose flood misses its sample.

The browser demo has the rule the port left out (`bodies-waves.html`, the candidate loop of `tickFront`): when the new body's flood does not own the seed's cell, the drop is absorbed into the new body ("never retry every tick (flicker + a 2k-visit flood per tick)").

## Specification (design, 2026-11-06)

Designed against item/0298 at 34fa3e6. Both rules were prototyped in a scratch copy: the verifier's scenario frees 6 empty bodies (ticks 361 and 362 of the verifier's counter, which includes the 47 settle ticks), its last seed, merge or flood visit is at tick 1096 (1049 ticks after the carve), it ends with no body of volume 0, nothing dropped, and the conserved sum is exact every tick; the 739 tests of every test file that mentions water pass unchanged; the tests below pass.

### The rules

1. **An empty body dies at once.** A body is empty when it is alive, not the sea, not the pending flood's (`water_body_is_pending`: its loaded bands are cleared while its flood runs), and holds no cell: `len(loaded) == 0 && len(frozen) == 0` (a body with only frozen parts is not empty). It dies where its last cell left it, in the same call: its volume goes to the body that took the cell (the flood's body for a claim, the absorbing body or the sea for an absorption, the sea for the sea's claim); with no taker (a sample turned ground, the sweep) it goes as `finish_water_body_flood` sends its own (to `water_to_sea` when `spill_to_sea`, else `water_dropped`). A sweep at the end of each bodies tick frees any empty body left, in id order: a table saved before 0299. Conservation: the volume moves to a counter or a body one to one (it is 0 in practice: a body whose every cell is dry has its level at or under every bottom, so its curve holds nothing; the heir keeps it exact anyway). No sample carries the freed owner (every owned loaded sample is a cell) and no frozen part names it, so the slot is free for reuse. Determinism: frees follow the claims and absorptions, which run in the step's order, and the sweep runs in id order on every machine, a loaded one included.
2. **A seed's sample joins the body its flood made.** `seed_water_body` records its sample on the flood (`Water_Flood.candidate`, saved and hashed with the flood record, so a seeding flood left pending and finished ticks later, or on a loaded or joining machine, applies it alike). When a seeding flood finishes, after `absorb_seeded_front`, a candidate that is still front water no one owns (its chunk loaded, not ground, owner none, awake, not a spring, fill > 0) goes to the new body's volume: its byte 0 (quiet), asleep, owner still none. It conserves (the fill moves to the volume one to one) and ends the churn: the sample is empty and asleep, so it never seeds again. The walk descended from the sample to the seed, so the water belongs to the basin the seed found; a body put over its sill by it hands the excess to its weir as any body does. A candidate the flood claimed is the body's already (`absorb_seeded_front` or the next settle takes it), so the rule leaves it.

### `world_field_water_body.odin`

- `Water_Flood`: add `has_candidate: bool` and `candidate: Sample_Coordinate` (comment: the still front sample a seeding flood began from, `seed_water_body`; none for a reflood).
- `start_water_body_flood`: in the `fresh` branch, `flood.has_candidate = false` beside `flood.redirty = false`.
- `end_water_body_flood`: also `flood.has_candidate = false`.
- `seed_water_body`: after `start_water_body_flood` returns true and before `run_water_body_flood`, `world.water_flood.has_candidate, world.water_flood.candidate = true, sample`. Doc comment: the sample is kept on the flood for its finish.
- `absorb_seed_candidate :: proc(world: ^Field_World, id: Water_Body_Id)` (new, after `absorb_seeded_front`): rule 2. Nothing when `!flood.has_candidate` or the candidate fails the checks; else `fill := i64(chunk.water[index])`, `world.water_bodies[id].volume += fill`, `world.water_body_counts.absorbed += fill`, `write_field_water_quiet(world, chunk, index, flood.candidate, 0)`, `sleep_field_water_sample(chunk, index)` (which clears the still ticks and the moving stamp). Called from `finish_water_body_flood` inside `if flood.seeding`, right after `absorb_seeded_front(world, id)`, so the level that follows counts it.
- `free_empty_water_body :: proc(world: ^Field_World, id: Water_Body_Id, heir: Maybe(Water_Body_Id) = nil) -> bool` (new, beside `kill_water_body`): rule 1; false and nothing done when the body is not empty; else the volume to `heir` (`WATER_BODY_SEA`: `water_to_sea`; a body: its `volume`, no relevel here, every caller's heir is pending or relevelled by its caller), or with no heir by `spill_to_sea`, then `kill_water_body`; true.
- `free_empty_water_bodies :: proc(world: ^Field_World)` (new): `free_empty_water_body(world, Water_Body_Id(index))` for index in `1 ..< len(world.water_bodies)`.
- `claim_water_flood_sample`: after `relevel_water_body(world, other)`, `free_empty_water_body(world, other, id)` (the heir is the flood's body; its volume applies at the finish like any credit to a pending body).
- `claim_sea`: after `mark_water_body_dirty(world, id)`, `free_empty_water_body(world, id, WATER_BODY_SEA)`.
- `finish_water_body_flood`: its own kill stays as it is; update its comment for the candidate.

### `world_field_water.odin`

- `absorb_front_water`: after `changed[previous] = true`, `free_empty_water_body(world, previous, target)` (the target's relevel follows through `changed`; the sea heir goes to `water_to_sea`; the freed slot's `changed` entry relevels nothing since `relevel_water_body` skips a dead body).
- `follow_field_terrain_with_bodies`: in the ground branch, after `mark_water_body_dirty(world, id)`, `free_empty_water_body(world, id)`.
- `step_field_water_bodies`: `free_empty_water_bodies(world)` after the awake chunks are pruned and before the alive count, so `water_body_counts.bodies` never counts an empty body.
- `settle_field_water_front`'s comment: a seed's sample its flood did not reach joins the new body (rule 2).

### `simulation_field_save.odin`

- `Water_Flood_Record`: add `has_candidate: bool` and `candidate: Sample_Coordinate`; `WATER_FLOOD_RECORD_BYTES :: 4 + 2 + 4 + 2 * 8 + 12`; `write_water_body_table` writes them; `read_water_body_table` restores them with the active flood (`target.has_candidate, target.candidate = flood.has_candidate, flood.candidate`). No new validation: a candidate is only read through `field_world_cell` and its checks. The schema codec reads an older record with both zero: such a pending seeding flood finishes without rule 2 and its sample seeds once more later, under the rule. No log line, since nothing in the file tells such a record (as for the frame tables, `doc/architecture.md`, Save format), and a bodies save is a developer's (the tech demo never saves).

### Tests (`world_field_water_body_test.odin`, appended under a `// Work item 0299` comment)

Helpers: `water_bodies_equal` also compares `has_candidate` and `candidate` (the 0293 and 0298 tests themselves are unchanged). `make_dry_water_body :: proc(world: ^Field_World, sample: Sample_Coordinate, volume: i64) -> Water_Body_Id`: allocates an id, sets `Water_Body{alive = true, volume = volume, level = base, written_level = base, base = base, seed = sample, spill_level = max(i64), spill_volume = max(i64), meshed_level = min(i64)}` with `base := floor_divide_i64(field_water_bottom(field_water_span(sample)), WATER_BODY_BAND) * WATER_BODY_BAND` (the level at the base, so the cell reads dry whatever the volume), removes the sample's cell from the body owning it (`remove_water_body_cell` on its `loaded`, not the sea), sets the owner, `add_water_body_cell` and `insert_sorted_field_chunk`. Volume 37 in the path tests checks the heir.

- `test_a_drained_lake_joined_to_a_second_cave_comes_to_rest` (the verifier's scenario): `make_body_test_world()`, carve `BASIN_LOW..BASIN_HIGH` and the cave `{4,0,4}..{11,1,11}`, pour `{4,3,4}..{11,6,11}` full, `field_world_set_sample({7,2,7}, FIELD_AIR_SAMPLE)`, `settle_body_test_water(..., 400) < 400`; then carve `{13,0,4}..{20,1,11}` and set `{12,1,7}` and `{13,1,7}` to air; `total := conserved_water`. 1500 ticks, each: `conserved_water == total`, `water_dropped` and `water_to_sea` unchanged, and no empty body (alive, not the sea, no loaded band, no frozen part, not pending). Then 1000 ticks, each also: `water_body_counts.seeded`, `.merged` and `.flood_visits` all 0. At the end: at least one live body and none of volume 0. Print one `0299:` line with the last tick that seeded, merged or flooded (1049 after the carve in the prototype).
- `test_a_body_whose_last_cell_a_flood_claims_dies`: `settled_body_test_lake(t, 3, &tick)` (the sealed basin's lake owns its air to the rim); `make_dry_water_body` on `{7,6,7}` with 37; `mark_water_body_dirty` the lake; one step: the dry body is dead, the lake's volume grew by 37, `{7,6,7}` is the lake's, `conserved_water` unchanged.
- `test_a_body_whose_last_cell_absorption_takes_dies`: the same lake; a dry body on `{7,4,7}` with 37; `set_front_water(..., 100)` there; call `absorb_front_water(world, chunk, index, sample, span, lake, changed)` directly (`changed` a temp slice of `len(world.water_bodies)`): the dry body is dead at once, the lake's volume grew by 137, `conserved_water` unchanged.
- `test_a_body_whose_last_cell_the_sea_claims_dies`: the world of `test_a_dig_joining_a_cave_to_the_sea_fills_it_in_the_tick` (sea planet, shaft, sealed cave `{14..16, 5..7, 4..6}`), one step; a dry body on `{16,6,6}` with 37 (not beside the dug wall); dig `{12,6,5}` and `{13,6,5}` to air: the body still lives; one step: it is dead and `water_to_sea` grew by exactly 37.
- `test_a_body_whose_last_cell_turns_ground_dies`: the lake; a dry body on `{7,6,7}` with 37; `field_world_set_sample({7,6,7}, {MAXIMUM_DENSITY, .Stone, 0})`: the body is dead before any step and `water_dropped` grew by 37.
- `test_a_pending_or_frozen_body_without_loaded_cells_lives`: the lake; `start_water_body_flood(lake, tuning, true)`: its `loaded` is empty and `free_empty_water_body` returns false; run and finish the flood: the lake lives. Then a hand-made body with no loaded band and one frozen part (`chunk = {5, WATER_TEST_CHUNK_Y, 0}`, not loaded, its own owner, bands `{opens = 1}, {closes = 1}`, seed in that chunk, volume 254): `free_empty_water_body` returns false, and after one step it lives.
- `test_a_saved_empty_body_loads_and_dies_on_the_first_tick`: the lake plus a hand-made empty body (alive, volume 0, no cell, `base`, `level` and `written_level` the lake's base, `spill_level`/`spill_volume` max); write the table and read it into a second world as `test_a_save_during_a_pending_flood_loads_and_hashes_alike` does (chunks through `encode_field_chunk`/`decode_field_chunk_delta`/`restore_field_chunk`, `rebuild_water_body_chunks`): the read succeeds and the body is alive there; one step on both: dead on both, the lake's volume and level equal, the chunk state hashes equal. (Not `water_bodies_equal` before a flood has run on both: an idle flood's `sill` and `rise_limit` are not saved.)
- `test_a_seed_whose_flood_misses_its_sample_takes_its_fill`: `make_body_test_world()`, carve the basin, `set_front_water` 100 on the far corner `{11,3,11}`; `tuning.flood_rise_samples = 0` (the flood claims only samples no higher than the seed's bottom); `seed_water_body(sample, tuning, &budget)`: no flood pending; the sample's byte 0, asleep, owner none; one body, of volume 100, whose seed is not the sample (the walk moved it to the floor's lowest, `{4,3,4}`); `conserved_water == 100`. Then 100 steps: `seeded == 0` each tick and `conserved_water == 100`.
- `test_a_pending_seed_flood_saved_takes_its_sample_alike`: the same world and tuning, `seed_water_body` with a budget of 1: the flood is pending with `has_candidate` and `candidate == sample`; round-trip the table and chunks into a second world: the second's flood carries the candidate; one step on both: on each the sample's byte is 0, no flood pending, `conserved_water == 100`; `water_bodies_equal(&first, &second)`.

### Docs

- `doc/architecture.md`, The water field, Bodies, the flood bullet: after "and a body with no cells left dies": so does any body left with no cell (no loaded band, no frozen part) and not pending, at once where its last cell left it (another flood's claim, an absorption, the sea's claim, a sample turned ground; `free_empty_water_body`), its volume to the body or the sea that took the cell, else as the finish sends it; a sweep at the end of the tick frees any other, a table saved before 0299 among them (0299).
- The same section, the front bullet, after the seeding sentence: the seed's sample is kept on the flood (`Water_Flood.candidate`, saved with it); when the seeding flood ends without having claimed it (the walk moved the seed, and the flood stopped at a saddle first, typically after merging the lake beside it), its fill goes to the new body's volume and it sleeps empty, no one's: a residue resting above a lake by less than the dead band joins the lake once instead of seeding every tick (0299, the study's rule).
- The same file, Save format, the water bodies' table: the pending flood's record carries the seed's sample (0299); an older record reads with none.
- The log section is the main agent's: the two root causes, the prototype's numbers above, and the observations below.

### Hand-back lines that apply

- A changed save layout: the flood record's two fields, read zero from an older record (above); no log line, with the reason.
- A save holding an empty body loads cleanly: the reader accepts it and the first tick frees it on every machine alike (`test_a_saved_empty_body_loads_and_dies_on_the_first_tick`), so a host and a joiner stay equal. The free is in the tick, never at the load, for that reason.
- A new participant in a shared budget: the candidate's fill raises the new body's volume; a body put over its sill hands the excess on through its weir. The flood budget only sees fewer seeds.
- Tests use temporary worlds only.

### Decisions and questions for the main agent

- Rule 1 frees bodies with no cell, as the item says, not bodies of volume 0 (the demo deletes every body with V <= 0, `bodies-waves.html`, `tick`): a basin pumped dry keeps its body and refills as it. With rule 2 a seeded body always holds its sample's fill, so the scenario ends with no body of volume 0. Free volume 0 bodies too?
- The transient that remains: until tick 1096 the floor's thin lake stays over its sill while it drains through the hole, and front water resting in the floor's far corners, beyond its flood region, seeds about every 25 ticks; each seed merges the lake, its flood reaches a slightly different region (a split hands the rest to the front), and its sample joins the lake. Bounded and conserving; no change proposed.
- Observation for a possible new item: the two caves end as two bodies joined under water by the passage (levels 813179 and 813178 with the shared sill at 812935 under both). They come to rest by tick 2000 and trade nothing after, but the weir's merge never fires (it waits for the excess within the dead band), so one water stays two records.
- `merge_into_water_flood` keeps the flood's id, so a lake's id changes whenever a seed merges it (the demo keeps the lower id). Not needed for this fix.

### Main agent's decisions (approval, 2026-11-06)

- Both fixes as specified. A body dies when its last cell goes, not at volume 0: a basin pumped dry keeps its body and refills as it.
- The save: the flood record's two new fields read as zero from an older record, by name; no remap, and the landing log names it (bodies saves are the tech demo's only).
- A seed about every 25 ticks while the thin lake over the sill drains, each absorbing its sample, is accepted.
- Two bodies joined under both their levels (the two caves, levels 813179 and 813178 over a shared sill at 812935) stay two records: that is item 0300, since a pump in one would lower it alone.
- The worktree is made from `item/0298`; this item lands after 0298.
