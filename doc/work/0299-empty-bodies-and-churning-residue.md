# 0299: Empty bodies die and a residue above a lake rests

Status: designing (2026-11-06)

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
