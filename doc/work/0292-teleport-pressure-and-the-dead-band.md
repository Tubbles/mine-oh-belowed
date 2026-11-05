# 0292: Teleport pressure and the dead band

Status: todo (2026-11-05)

Milestone: the water tech demo (0291). The first of the water stream: 0292, then 0293, 0294, 0295, all on `world_field_water.odin` and `world_field_mesh.odin`.

## Goal

The field's water rule gains communicating vessels and static friction, so a shaft dug beside a lake and joined to its bed fills to the lake's level, a U-tube rises, and a settled lake is still: no transfer for a level difference under a minimum head, no film at a sill topped up every drying step. This is water model `teleport` of the tech demo, the browser demo `teleport-waves` (its notes: `/home/user/water-demos/notes/teleport-pressure.md`, `teleport-waves.md` revisions 3 to 6) carried into the field.

## Controls

None.

## Change

- `world_field_water.odin`: after `spread_field_water`, a not-full sample resting on full water (its nearer-centre neighbour full) that moved nothing runs a bounded depth-first search through full samples (nearer and farther neighbours alike, visited at most `pressure_visit_budget` per search and `pressure_visit_budget_per_tick` per tick, in sample order) for the surface sample with the highest level; when that level exceeds the sample's own by more than one cell height plus the dead band, the equalising fill (rate capped) moves from there to here in one step. A failed search sets a `water_pressure_failed` bit that a change next door clears. The dead band: `field_water_share` moves nothing for a level difference at or under `minimum_head` (fill units, shipped 4 of 254, about 1/64 cell); falling into room below is never banded. Films: `field_water_is_film` drying wakes only the film sample; a film that cannot be refilled above the band sleeps.
- Tuning keys in `field_water` of `data/game.sjson`: `pressure` (true), `pressure_visit_budget` (128), `pressure_visit_budget_per_tick` (20000), `minimum_head` (4). `Field_Water_Tuning` gains them; the planet preview's and the tech demo's debug line shows teleports, visits and failures per tick.
- The chunk codec: the failed bit is derived (cleared on load, rebuilt by the first tick), so `FIELD_CHUNK_FORMAT_VERSION` stays; the state hash is unchanged in its inputs. Lockstep: the search runs in sample order with the fixed budget, so every machine teleports alike.
- Docs: `doc/architecture.md` (The water field: pressure, the dead band), `doc/content.md` (the keys), the log.

## Verify

- `./build.sh check`, `check-android`, `test`, the doc checks.
- Tests in `world_field_water_test.odin`: U-tube (a lake, a sealed tunnel from its bed to a shaft open to air): the shaft reaches the lake level within the band in under 1500 ticks with pressure on, stays at the tunnel with it off; shaft beside a lake; a settled 20-sample lake stays asleep for 3000 ticks (no awake samples, volume constant); the sill film: a lake at a sill's height does not pulse (no wake every `dry_ticks`); the existing levelling and breach tests still pass; determinism: two worlds stepped alike hash alike.
- The bench: the water's ms per tick at the existing scenarios within 10 percent of before.
