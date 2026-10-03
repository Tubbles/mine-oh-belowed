# 0207: The model workbench: the game checks and shows a model

Status: todo (user, 2026-10-03, on the pipeline, relaying a comment they got: "Design a framework that can do all the physics modeling, mechanics, clearances, animations and simulations so that Claude just writes the model scripts and doesn't have to direct a ton of work every time you want to see how something works or is put together"; after 0204, before 0205)

## Goal

An agent authors a machine by writing one script that composes the kit's parts, and the rest is done for it: the script reads the machine's record, so nothing is typed twice; the game checks the result in its own mesher and motion code (the fit, the budget, the moving part's sweep clear of the body, the arm's reach, the openings over the open cells); and the game renders the model from fixed cameras, at rest and in motion, to PNG files the agent reads. No run of the game is directed by hand to see how a model moves or fits.

## Change

- The kit reads the records: `tools/models/records.py` reads `data/machines.sjson` with the SJSON reading the other generators already do (shared into one module) and gives a script its machine's footprint, motion (kind, axis, pivot, amplitude), ports with their faces, open cells and light. A script places an intake at a port's face by name, an opening over an open cell box and the part about the record's pivot, so the record and the model cannot disagree; the generator refuses a part whose pivot is not the record's.
- The checks, in the game (`--model-check=<machine|all>`, no window, exits 1 on a problem, one line per problem with the machine, the check and the numbers): the fit of 0204; the budget of `DESIGN.md` (triangles per body and part, materials); the moving part swept over its motion at 16 phases through `model_motion.odin` in the working state never intersects the body (every part triangle against the body's triangles, boxes first, exact after) and stays inside the footprint plus the tolerance, so a spinning head never pokes into the neighbour's cell; the arm's parts at 16 cycle fractions on the 500 mm frame clear its base; a machine with open cells has no triangle inside an open cell, so a door is open where the record says. `./build.sh model-check` wraps it, and the test suite runs the same checks over the shipped models, so a check is one piece of code run two ways.
- The views, in the game (`--model-preview=<machine>[,<machine>] --model-preview-directory=<path>`): a window as `--planet-preview-screenshot` opens (`tools/model_preview.sh <machine>` wraps the virtual display for an agent's headless session), the machine alone on a 500 mm frame's pad under the field's sky light, the player's capsule beside it for scale, from four cameras (front three quarter, back three quarter, top, a close front at 2 m), at rest and at phases 0.25, 0.5 and 0.75 of its motion (the arm at its grab, lift and drop fractions), one PNG per camera and phase named `<machine>_<camera>_<phase>.png`, then exit. The renderer's real shading and light, so what the agent reads is what the couch sees.
- `tools/make_models.py` rebuilds every model and then runs the check, exiting as it does, so a committed model always passes; the agent runs the preview after and reads the PNGs before it hands back.
- Docs: `doc/build.md` (the flags and the wrapper, beside `--planet-preview-screenshot`), `doc/presentation.md` Machine models (the workbench), `doc/content.md` (the authoring rule: a model is written by a script, checked and previewed), the log.

## Verify

- The build and check commands of 0168.
- Tests, no GPU: the checks against hand built meshes (a part that cuts the body at phase 0.5 is reported with the phase; a part leaving the footprint; a body over the budget; a triangle inside an open cell; a clean machine passes); the suite's run over the shipped models passes; `records.py` reads the furnace's ports and the pod's open cells as the Odin loader does (a few golden values).
- Headless: `tools/model_preview.sh burner_mining_drill` writes the 16 files; the front three quarter view at phase 0.5 is sent to the user.
