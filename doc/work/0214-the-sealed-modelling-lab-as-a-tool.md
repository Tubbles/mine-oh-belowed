# 0214: The sealed modelling lab as a tool

Status: todo (2026-10-04, from the 0212 test of a sealed modeller; after 0212)

## Goal

The stone furnace the user accepted (0212, 2026-10-04) was made by a modeller that saw only the reference images, the user's words on the look, the footprint, the renderer's limits and a triangle budget, in a directory built by hand under `tmp/furnace_lab/` with copies of the kit, the record reader, a standalone check and a Blender renderer. The next machines are made the same way, so the lab becomes a tool that builds itself from the repository in one command, and the hand copies stop.

## Change

- `tools/make_model_lab.sh <machine> <reference directory>` (name open to the design stage) builds `tmp/model_lab/<machine>/`: copies of `tools/blender`, `tools/sjson.py`, `tools/make_models.py`, `tools/models/{__init__,kit,palette,records}.py`, a `machines/__init__.py` registering only that machine, a stub script, `data/machines.sjson` with that machine's record only (or the whole file with its `open_cells` and model keys stripped), the reference images, `check.py` (the budget, the material limit, the footprint bounds, the object names) and `render.py` (the workbench's five cameras in Blender, flat shaded, a player capsule for scale), and a `BRIEF.md` written from a template with the machine's name, footprint and the art direction's words.
- The check and the renderer live under `tools/model_lab/` and are tested on the host (a Python test for the check against a small OBJ; the renderer only by use).
- What comes back from a lab (the script and the palette entries) is integrated into the tree by an implementer, as 0212's round two did: the script copied, the palette merged, the OBJ regenerated and compared with the lab's bytes, the record's open cells set to what the model leaves empty, the tests and docs following.
- `doc/build.md`, The workbench, documents the lab and its seal (the modeller reads nothing outside it; the brief carries the look, never `DESIGN.md`'s modelling rules, never a sibling script), and `CLAUDE.md`'s work flow names the lab as the modelling stage of a model item.

## Controls

- None.

## Verify

- `tools/make_model_lab.sh electric_mining_drill <directory>` builds a lab whose stub builds, whose check runs and whose renderer writes five previews of the stub.
- The 0212 lab's `check.py` and `render.py` are the first versions of the tool's.
