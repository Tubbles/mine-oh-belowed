# 0300: Bodies joined under water merge

Status: designing (2026-11-06)

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
