# 0057 Terrain with shape: ranges, plateaus, valleys, beaches

Status: todo
Milestone: M11

## Goal

The terrain is a gently noisy plain. Continents and ranges, plateaus and cliffs, valleys with gentle banks and beaches make a landscape worth crossing while the flat landing site rule still finds a home.

## Deliverables

- A layered height function: low frequency continents and ranges, domain warping for ridges and valleys, plateaus with cliffs, river valleys with gradual banks and sand beaches, still one pure function of seed and column.
- The spawn search keeps finding flat sites for every seed (extend the generation tests), and cave and vein placement follow the new heights.
- A `generator_version` in `world.sjson`: a loaded world whose version is older is marked in the load list ("terrain changed since this world was made") and loads anyway, since unmodified chunks regenerate with the new terrain.
- Tests: height ranges and slopes per biome, spawn found for the seven test seeds, determinism.

## Verify

- Builds and tests pass.
- User: Fly around a new world; screenshots from the pad.
