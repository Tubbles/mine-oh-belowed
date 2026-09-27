# 0055 Model pipeline: voxel models for machines

Status: todo
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
