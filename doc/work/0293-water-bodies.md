# 0293: Water bodies

Status: todo (2026-11-05)

Milestone: the water tech demo (0291); the water stream after 0292.

## Goal

A connected basin of still water is one record with an integer volume and a level, found by a priority flood over water-capable samples with the radial potential; levelling is instant and exact, a tunnel under a lake fills by construction, the sea is a body of infinite volume with a fixed level, and the cellular rule runs only on the wet front: water pouring into a hole, spilling over a sill at a weir rate, leaving an outlet. Front water that comes to rest on a body is absorbed; front water that goes still in a pit seeds a body. This is water model `bodies` of the tech demo, the browser demo `bodies-waves` (`/home/user/water-demos/notes/basin-bodies.md`, `bodies-front-hybrid.md`, `bodies-waves.md` sections 6 to 9, `chunk-boundary.md`) carried into the field, selected by `World_File_Settings.water_model = bodies`; with `teleport` the field runs 0292's rule unchanged.

## Controls

None.

## Change

- `world_field_water_body.odin` (new): `Water_Body` (id, volume in fill units as i64, level in fill units from the centre, spill level and sample, the volume-level histogram as counts per level band, a frozen histogram per unloaded chunk as 0295 will need, dirty), the body table on `Field_World`, `flood_water_body` (the priority flood from a seed, in sample order with fixed tie breaks, stopping at the spill sample, bounded per tick by `flood_visit_budget` and resumed next tick), `body_level_of_volume`, merge when a lower body's level reaches the saddle, split by handing unreached wet samples to the front; body-owned samples carry their fill as bytes rewritten per level band when the level changes, so the chunk format and the hash stay (the plan's finding: `Field_Chunk` already holds the water planes the hash covers), and the body table goes to the field tables of `simulation_field_save.odin`.
- `world_field_water.odin`: the front set (unowned samples with fill), the two-pass face flux for it (fluxes from tick-start fills, outflows scaled so a sample never overspends), absorption into a body when the lower neighbour is the body's water or the body's level rises over the sample, pit seeding after `still_ticks`, the weir emission at a spill (`weir_rate_per_head`, `weir_cap`, `weir_dead_band`), the sea as body 0 (inflow counted and discarded, a dig below sea level fills to it in the same tick), edits re-flooding the touched bodies in the same tick.
- Keys in `field_water`: `model` is per world (`save_world.odin`), the rates and budgets in data. The debug line shows bodies, front samples and flood visits per tick.
- Docs: `doc/architecture.md` (The water field: bodies), `doc/content.md`, the log.

## Verify

- The checks and the suite.
- Tests: hole under a lake lowers the level in the same tick with the volume unchanged; a trough between two lakes runs a front stream until the upper lake sits at its sill (within the band); a pump intake (0295's stub: a direct volume subtraction) lowers the level to the litre; a cave under a lake fills when the floor is dug through; a lake straddling a chunk the set drops keeps its volume; the sea does not rise under a spring over 2000 ticks; the total of body volumes plus front fill is constant over 5000 ticks of the breach scenario; two worlds stepped alike hash alike; a save during a pending flood loads and hashes alike.
- The bench: idle water cost near zero; the flood spike per edit under 2 ms at 4000 m.
