# 0145: Pilot package split of the true leaves

Status: todo

## Goal

The fourth step of the architecture cleanup (user, 2026-09-30): learn what a package split costs before deciding on the layering refactor. In Odin a directory is a package and packages cannot import in a cycle, so the split is only possible for files with no edge back into the game package.

## Change

- Move the files the graph shows outside the main component, or with one or two edges into it that a parameter removes, into packages under `src/`: candidates `sjson_text`, `run_length`, `model_vox`, `platform_paths`, `generation_seed`, `render_frustum`, `jni_indices`, the platform pairs (`haptics_*`, `export_access_*`, `system_keyboard_*`, `local_zone_*`, `logging_*`). Each package is a leaf utility with no back reference (the rule in `CLAUDE.md`), a `doc/code_map.md` entry, and its tests beside it.
- Record per package: the edges that had to be cut and how, the call sites that gained a prefix, the build and test time before and after, and anything the `#+build` tags or the Android build made awkward.
- The item's Implementation notes end with a recommendation: whether a full layering split (content, world, simulation, presentation, ui, loop) is worth its cost given what the pilot showed, as input to 0146.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py`; the play build installs and runs (the user playtests the couch and the phone once).
