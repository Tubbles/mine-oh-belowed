# 0168: The terrain field: storage, planet frame and generation

Status: implemented (2026-10-02; the field is reachable through its procedures and tests until 0179 wires the save and the session)

## Goal

The smooth world's storage: a density field with a material and a tint per sample on a 3D grid aligned with the planet's axes, in chunks, generated lazily from the seed as a sphere with strata and bedrock, saved as deltas. Pure data and generation, no mesh, no player; the world cluster gains its field files beside the block files (0167, Sequencing on `main`).

## Change

- New files in the world cluster with the `world_field` and `generation_planet` prefixes (a prefix line in `tools/code_graph.py` if the script needs one): the field chunk (32 by 32 by 32 samples; per sample a signed byte of density, a material byte, a tint byte), the field world holding chunks in a map keyed by chunk coordinate, get and set of a sample, dirty marking, and the planet frame (centre at the origin, the sample spacing from the world settings, world positions in 64 bit fixed point with a 1/4096 m unit).
- The planet record in data (`data/planets.sjson` or a block of `data/game.sjson`, say which and why): radius (default 8 km), gravity, bedrock depth (256 m), sea level, rotation, palette; read through the content cluster like the other tables, never a constant in code.
- Generation as a pure function of seed and chunk coordinate on the streaming workers' pattern: the surface at the radius plus three dimensional noise read on the sphere (no latitude and longitude), strata by depth below the local surface (topsoil, stone, deep stone), bedrock at the planet's depth, the sea level recorded for 0172. Every noise is integer or fixed point through the `generation_seed` package, so two machines generate the same bytes.
- The save codec: a chunk whose samples differ from generation is saved as a delta (the run length package for the bytes), a chunk equal to generation is not; the save layout is new (decision 28 of `doc/log/2026-10-02.md`, saves break), and the loader reports the version it refuses.
- `doc/architecture.md` (World storage, World generation) gains the field beside the blocks; `doc/code_map.md` lists the new files; `doc/content.md` the planet record.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: generating the same chunk twice from the same seed gives identical bytes; a chunk at the planet's surface has air outside the radius band and stone inside; a sample at the bedrock depth is bedrock; a delta round trips through the codec; an edited sample survives encode and decode while an unedited chunk writes nothing (at the codec level; the session's save takes the field in 0179); a planet record with a missing field is refused with a message naming it.
