# 0298: A thin lake settles under bodies

Status: designing (2026-11-06)

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
