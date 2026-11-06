# 0306: Taller, varied relief: plains, hills, ranges and valleys

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313 (the plan in `doc/log/2026-11-06.md`, The world generation series). The user (2026-11-06): "I need better and more varied elevation for testing the water tech demos, and just generally better visuals because right now it is very bland". The research is `work/world_generation_research.md`.

## Goal

The relief reads as landscape from the ground and from the air: plains and rolling lowlands round the home, hills, ridged ranges and deep valleys within walking distance, a few peaks on the horizon, basins and coasts below them. Water from the tech demo's spring runs a long way downhill.

## Controls

None.

## Change

- Relief terms after Minecraft's noise router and domain warping: a low frequency region noise read through a data spline (sea floor, coast, lowland, plain, hill, highland heights), a folded ridge noise for the ranges and the valleys between them, hills and detail octaves, a warp of the large terms' input that hides the value noise lattice, and the skew of real terrain (many lowlands, few peaks). Integer and fixed point, a pure function as today.
- The drama fades in with the distance from the home (Valheim's meadows at the spawn): the crater and the first base on gentle ground, hills within a few hundred metres, ranges in sight.
- The relief bound goes from the global 34 m to a bound per planet derived from its record, about 160 m of total range on the home planet (peaks about 100 m over the sea). Every reader of `MAXIMUM_RELIEF_METRES` takes the planet's bound: the generation's shortcuts, the level of detail shell, the sky march, the globe, the edits, the arrival's start, the bedrock depth rule. The generation's cost per node and the nodes generated per view are measured before and after, with a reject per node from the relief's range over its footprint if the thicker shell costs.
- Old worlds generate as before: the new terms are off in a world record without them (as `relief_shape` in 0189), one log line.
- The default seed's spring moves (data) to a slope above a valley or a basin, so the tech demo's spring start runs a stream at least 100 m downhill. The home keeps its rules (the dry crater floor, the dry home search).
- A relief map mode for tuning without a window (a workbench mode, as `--model-check`): a shaded height PNG of a square round a latitude and longitude with the sea, contour lines, the home and the springs. This item's verify uses it, and so do the later items of the series.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation), `doc/build.md` (the map mode); the log.

## Verify

- The checks and the suite, with tests of the new terms' bounds, their determinism, and the old record's unchanged generation.
- Relief maps of 4 km round the home at the three radius presets, before and after.
- Captures of the tech demo's spring start, the home and a far point from the ground and from 40 m and 120 m up, beside the before set in `tmp/shot_terrain_before/`; sent to the user.
