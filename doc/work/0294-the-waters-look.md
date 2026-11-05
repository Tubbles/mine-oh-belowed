# 0294: The water's look: sheet, radial plane, waves

Status: todo (2026-11-05)

Milestone: the water tech demo (0291); the water stream after 0293, needed by both models.

## Goal

Water is drawn where it is and only where it is: a body as its radial plane at every level of detail (no staircase), thin or fast water as a sheet hugging the terrain with a minimum visible thickness while it moves and its true thickness at rest, no water showing through a one-sample wall, no film climbing a drained basin's walls; and a surface wave layer, a presentation-only float height field over the surface samples, excited by water arriving from a fall, a stream mouth into standing water, a dig, a pump intake, never by routine levelling, so a stream entering a lake sends ripples out and a settled lake is bit-identical frame to frame. The browser demos' rules (`/home/user/water-demos/notes/bodies-waves.md` sections 6 to 8, `teleport-waves.md` revisions 3 to 6, `surface-mesher.md`).

## Controls

None.

## Change

- `world_field_water.odin` `field_water_density` and the gather sites (`copy_field_grid_part` in `world_field_mesh.odin`, `coarse_field_water_density` in `world_field_lod.odin`): per corner the maximum of the level plane (a body's level, or the sample's slab level) and the sheet (terrain density plus the sample's thickness: the true fill share at rest, a 0.2-sample floor while moving, the full column while falling), stamped onto the sample and its 26 neighbours through face-connected open space only, with the wall guard (a stamp onto a solid sample is clipped so the crossing stays inside the wall on every edge to an air sample the wet sample does not reach). Moving means fill changed, flux ran or the sample falls within the last 6 ticks (a `water_moved` stamp per sample, derived, not saved).
- Remesh: a body's chunks remesh when its displayed level moves a thirty-second of a sample or ownership changes; a chunk with active wave samples remeshes while they are active; a settled chunk never.
- `render_field_waves.odin` (new, presentation): per surface sample a height offset and a velocity (f32, frame side, never in the simulation state or the hash), the height-field wave equation on the active set (c, damping, clamp 0.15 sample, CFL), excitations from the simulation's events of the tick (a per-tick event list the water step fills: impacts, stream mouths, digs, intakes), the offset added at gather time for the water grid; a `waves` setting in `data/game.sjson` presentation keys.
- Docs: `doc/presentation.md` (The water's look), `doc/architecture.md`, the log.

## Verify

- The checks and the suite.
- Tests: the trough stream of 0293's test has mesh within a sample of every moving wet sample (reading the chunk mesh); a settled lake's water mesh is byte-identical over 4 consecutive meshes; a one-sample wall between a full body and air yields no water vertex beyond the wall; a drained basin (pumped dry) has no water vertex more than 0.1 sample above the ground; the sea's surface residual at latitude 0, 45 and 90 at LOD steps 1, 2, 4 under 0.05 sample; waves change no fill byte and no hash.
