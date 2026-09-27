# 0055 Model pipeline: voxel models for machines

Status: implemented
Milestone: M11

## Goal

Machines are coloured boxes. A model format and loader let every machine, block shape and item get a real shape without code changes, made in a free tool.

## Deliverables

- MagicaVoxel `.vox` files under `data/models/<id>.vox`, a loader in Odin (the format is small: size chunk, voxel list, palette), meshes built at load with greedy merging of same coloured faces and the world's per vertex light, hot reloadable (0054).
- `data/machines.sjson` names a model per machine; a machine without one keeps its box. A model is scaled to the footprint and oriented by the rotation; sub voxel resolution (8 or 16 per block) is allowed.
- Three placeholder models the assistant generates from a script (`tools/make_placeholder_models.py`): burner drill, stone furnace, wooden chest, so the pipeline is proven end to end and every later model is a data drop.
- Tests: loader on a generated file, mesh vertex counts, footprint scaling, a machine without a model keeps the box.

## Verify

- Builds and tests pass.
- User: Look at the three machines on the couch; take screenshots for review.

## Notes

Implemented by a subagent (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (661 tests, new ones in `src/model_vox_test.odin` and `src/model_mesh_test.odin`, plus cases in `src/data_watch_test.odin`), `./build.sh`, `./build.sh release`, and `python3 tools/make_placeholder_models.py` writes the same bytes on every run.

Files: new `src/model_vox.odin` (the .vox reader), `src/model_mesh.odin` (greedy meshing, footprint scaling, the entity transform), `src/render_models.odin` (upload and draw), `tools/make_placeholder_models.py`, `data/models/{burner_mining_drill,stone_furnace,wooden_chest}.vox`; changes to `src/machine.odin` (`model` key and its validation), `src/render_entities.odin` and `src/render_fluids.odin` (`draw_entity_cells` draws the model when there is one), `src/loop.odin`, `src/hot_reload.odin`, `src/data_watch.odin`, `src/data_reload_test.odin` (the reload tests copy the shipped models), `data/machines.sjson`, `data/strings/en.sjson` (`reload_models_done`).

### Model

- Format subset: `VOX ` header (version not checked), `MAIN` with `SIZE`, `XYZI` and optional `RGBA` children (RGBA entry i is palette index i + 1; without it the MagicaVoxel default palette). Several models per file: the first `SIZE` and `XYZI` pair only, without its `nTRN` transform; `nTRN`, `nGRP`, `nSHP`, `MATL`, `LAYR` and every other chunk are skipped. Refused, with a message naming the file and the chunk: no `VOX ` magic, chunk sizes running past their parent, a first chunk other than `MAIN`, a side outside 1 to 256, `XYZI` before `SIZE`, a voxel outside the size, palette index 0, an `RGBA` shorter than 1024 bytes, `SIZE` or `XYZI` missing, a model without voxels, a mesh over 65536 vertices.
- Axes: both right handed, MagicaVoxel z up and the game y up, so vox (x, y, z) is game (x, z, depth - 1 - y) with depth the model's vox y size: a turn about x, nothing mirrored. The model's minimum corner is the footprint's minimum corner. The script writes the inverse. The model's +x side is the machine's front (the side the rotation points at, the drill's output side).
- `model = "<id>"` per machine in `data/machines.sjson` (lowercase letters, digits, underscores) names `data/models/<id>.vox`. Strict: a named file that is missing or does not load and mesh stops the content load, at start and on a content reload.
- One mesh per machine with a model (scale depends on the footprint), built once, drawn per entity with `rl.DrawMesh` and the translation and quarter turns of `model_transform`. Same coloured faces merge per slice.
- Lighting: entity boxes are unlit (raylib's default shader), so models are too. Each face is its palette colour times a fixed shade per direction (top 1, bottom 0.55, sides 0.72 to 0.92), so the shape reads. No world light yet.
- Hot reload: `.vox` files under `models/` are a presentation category; any change rebuilds every machine's mesh, and a file that does not load keeps the old meshes. A content reload rebuilds them for the new machine table.

### Deviations

- Models are not lit by the world: boxes take no light value today, so there was none to reuse. Taking the light at the entity's cell and the day factor needs the frame's daylight blend passed to the entity drawing.
- A machine with a model loses its state colours (the burning furnace's top, the assembler's working top) and the edge frame; the drill's turning bar, the arrows, fluid ports and bottleneck markers stay.
- Inserters, poles, lamps, pipes and launch pads keep their own shapes; only the machines drawn through `draw_entity_cells` can take a model.

### Not verified

The look: the three placeholders, their orientation against the output side (a quarter turn is checked in the tests against the arrow's direction), the face shades, models next to lit terrain at night, model reload while the game runs.
