# 0275: Reference models set the look, the budgets become caps

Status: todo (2026-10-05, from the user)

## Goal

No exact triangle limit per model (user, 2026-10-05, DESIGN.md, Art direction): the reference models, the stone furnace (0212) and the pod (0221, 0231) first and a couple more as they are made, set the tone, the look and the poly count, and a new model is made against them in the Blender workflow. The lab's brief and the workbench still state and enforce the budgets of 0207 (3200 triangles a body, 200 a moving part, 8 materials) as a design rule; they become sanity caps that catch a runaway mesh, and the brief points the modeller at the reference models instead.

## Controls

No binding changes.

## Change

- `tools/model_lab/brief_template.md` and `tools/model_lab/model_lab.py build`: the brief names the reference models with their triangle and material counts and their renders as the yardstick, and states the cap as a cap (a mesh over it is a mistake to look at, not a budget to fill); the lab's standalone check reads the cap.
- The workbench (`./build.sh model-check`, `tools/make_models.sh`): the per body and per part maxima become one cap well above the references (the design decides the multiple), named as a sanity cap in its message.
- Docs: `CLAUDE.md` (Model items, the sealed lab), `doc/presentation.md` (Machine models), `doc/build.md` (The workbench), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh test`, `./build.sh model-check` on every model, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the cap refuses a mesh over it and passes every shipped model.
