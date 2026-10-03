# 0189: Terrain sculpting: ledges, basins and where the sea lies

Status: implemented (2026-10-03, doc/log/2026-10-03.md, Terrain sculpting; from playtest 1 of the slice; the user approved the proposal below on 2026-10-03, "so i can try out the slope movement")

## Goal

The planet reads as a landscape: ledges to mantle, hollows that hold water, slopes that are slopes. Today the surface is three octaves of value noise (24 m at 512 m, 8 m at 128 m, 2 m at 32 m, `relief_octaves` in `data/planets.sjson`) and the sea is every air sample below 14 m under the radius, so the ground is featureless rolling and the water lies as flat lakes wherever the noise dips, not in anything that reads as a basin (playtest 1: "featureless, there isn't really any ledges", "it looks misplaced, I would have assumed it would sit in actual lower basins").

## Change

- The relief gains shape, in data where it can: a ridged octave (the absolute value of the noise, sharpened) for ledges a metre or two high at a short wavelength, a terrace function on the long octave so slopes break into steps the mantle height can take, and a basin term (the low parts of the long octave deepened, the rest flattened) so water gathers in a few hollows; the amplitudes still add up to `MAXIMUM_RELIEF_METRES` or that bound rises with the level of detail checked.
- The sea level moves to where only the basins fill (a value in `data/planets.sjson`, the spring's basin kept by moving the spring or the home with it), and `field_home_player`'s dry spawn (0180) keeps the pod out of them.
- The planet preview and the walk screenshot show a ledge, a basin and the spring's pool from the home (0184).
- `doc/architecture.md` (World generation, the relief terms), `doc/content.md` (the planet record's keys) updated; a decision in the log naming what the user chose.

## Verify

- The build and check commands of 0168; the generation tests at every preset radius; the determinism test of two generations from one seed.
- Tests: a ridged octave makes a slope above the walkable angle within a chunk; the basin term leaves at least one hollow below the sea level within 200 m of the home and the home above it; the relief stays within the bound.
- The couch: the user judges the walk, the mantle and the water at the three radii.
