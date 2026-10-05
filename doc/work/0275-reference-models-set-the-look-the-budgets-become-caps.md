# 0275: Reference models set the look, the budgets become caps

Status: implementing (2026-10-05)

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

## Specification (design, 2026-10-05)

### The caps

Every cap is three times the budget its reference model was made under, so a reference sits just under a third of its cap and a mesh subdivided once (four times the triangles) over a reference's density fails: a machine's body 9600 (the furnace's 3173 under 3200, 3149 once 0274 lands), a pod's body 76800 (the pod's 25488 under 25600, the class keeps its own cap since the pod is a cabin the player stands in and a single cap above it would pass a furnace at sixteen times its density), a moving part 600 (the pod hatch's iris blade at 172, the steam engine's part at 164, both under 200). The 8 materials stay a limit as they are: `DESIGN.md`'s palette sentence still says at most 8 per machine, both references use exactly 8, and a material count does not run away the way a mesh does. The check keeps its gate (over a cap, the sweep, the open cells and the fixtures do not run), so the worst sweep grows from 16 x 200 x 3200 to 16 x 600 x 9600 box tests (about 92 million) and only for a model at its cap.

The reference models, in this order: `stone_furnace` (0212) and `pod` (0221, 0231). Their machine ids equal their model names.

### Game: `src/model_check.odin`

- Rename `MODEL_BODY_TRIANGLES_MAXIMUM` to `MODEL_BODY_TRIANGLES_CAP :: 9600`, `MODEL_POD_BODY_TRIANGLES_MAXIMUM` to `MODEL_POD_BODY_TRIANGLES_CAP :: 76800`, `MODEL_PART_TRIANGLES_MAXIMUM` to `MODEL_PART_TRIANGLES_CAP :: 600`. `MODEL_MATERIAL_LIMIT` stays 8. Their comment: sanity caps that catch a runaway mesh (DESIGN.md, Art direction, 0275), three times the budget each reference model was made under, the look and the density set by the reference models.
- Add `MODEL_REFERENCE_MACHINES :: [?]string{"stone_furnace", "pod"}` beside them, commented as the reference models (DESIGN.md, Art direction), pinned to `tools/model_lab/model_lab.py`'s `REFERENCE_MODELS` by `model_lab_test.py`.
- The enum member `Model_Check.Budget` becomes `.Cap`, its label `"cap"`, so a problem line reads `<machine>: cap: <detail>`.
- `model_body_triangles_maximum` becomes `model_body_triangles_cap :: proc(kind: Machine_Kind) -> int`, same body with the new constants.
- `model_budget_problems` becomes `model_cap_problems :: proc(body, part: Model_Layers, material_count: int, body_cap: int, allocator := context.temp_allocator) -> []Model_Check_Problem`. Details: `body has %d triangles, over the sanity cap %d`, `part has %d triangles, over the sanity cap %d`, `%d materials, the limit is %d`. Called from `check_obj_machine_model` as before.
- Add `Model_Counts :: struct { body_triangles, part_triangles, materials: int }`.
- Add `obj_model_counts :: proc(data_directory: string, machine: Machine) -> (counts: Model_Counts, problem: string)`: loads the machine's mesh (`load_machine_model_mesh`) and OBJ (`model_obj.load_obj_model_file`) in the temp allocator as `check_obj_machine_model` does, returns `model_layers_triangle_count` of body and part and `obj_model_material_count`, or the loader's problem.
- Add `Model_Reference :: struct { id: string, counts: Model_Counts, found: bool }` and `model_reference_counts :: proc(data_directory: string, machines: Machine_Registry, allocator := context.temp_allocator) -> []Model_Reference`: one entry per `MODEL_REFERENCE_MACHINES` id, `found` false when the registry has no such machine, its model is not an OBJ (`model_check_subject` not `.Obj`) or `obj_model_counts` returns a problem.
- Add `model_references_line :: proc(references: []Model_Reference) -> string` (temp allocator): `model check: reference models stone_furnace (body 3173, part 0, 8 materials), pod (body 25488, part 0, 8 materials)`, an entry not found as `pod (no model)`.
- Add `model_counts_line :: proc(id: string, counts: Model_Counts, body_cap: int) -> string` (temp allocator): `boiler: counts: body 336 triangles (cap 9600), part 0 (cap 600), 7 materials (limit 8)`.
- Update the file's Cost comment to the caps (the numbers above) and the comment of `check_obj_machine_model` ("then the caps, and only within them ...").

### Game: `src/loop_model_check.odin`

`run_model_check` keeps its signature and exit codes. After the selection succeeds and before the loop, it prints `model_references_line(model_reference_counts(data_directory, machines))` and frees the temp allocator. In the loop, for a machine whose subject is `.Obj`, it prints `model_counts_line(machine.id, counts, model_body_triangles_cap(machine.kind))` before that machine's problem lines, from `obj_model_counts` (on a counts problem no counts line: the check's `load` line reports it). The arm and voxel models print no counts line. The summary line is unchanged and counts lines are not problems. Update the file's header comment (the reference line and a counts line per OBJ model).

### Game tests

- `src/model_check_test.odin`: `test_a_model_over_the_budget_is_reported` becomes `test_a_model_over_the_cap_is_reported`: a body of 9601 gives one problem whose detail holds `9601` and `sanity cap 9600`, 9600 none, 199 none, a part of 601 one problem holding `part has 601`, part 600 none, 9 materials one problem, 8 none. `test_the_pods_body_budget_is_25600` becomes `test_the_pods_body_cap_is_76800`: `model_body_triangles_cap(.Pod)` 76800 and `(.Furnace)` 9600, 76800 none, 76801 one problem holding `76801` and `76800`.
- New `test_the_caps_stand_three_times_above_the_reference_models` (same file): `model_reference_counts(test_data_directory(), machines)` over the shipped registry (load as `test_the_shipped_models_pass_the_checks` does) has every entry found, and for each, three times its body is at most `model_body_triangles_cap` of its kind, three times its part at most `MODEL_PART_TRIANGLES_CAP`, its materials at most `MODEL_MATERIAL_LIMIT`. A future reference denser than a third of its cap fails here, which is the point: the cap is raised with it.
- New `test_the_counts_lines` (same file): the two exact strings above from `model_counts_line("boiler", {336, 0, 7}, 9600)` and `model_references_line` over `{"stone_furnace", {3173, 0, 8}, true}` and `{"pod", {}, false}` (expect `model check: reference models stone_furnace (body 3173, part 0, 8 materials), pod (no model)`).
- `src/model_triangle_mesh_test.odin` (lines 345, 348): the renamed procedure and constant.

### Lab: `tools/model_lab/check.py`

- `BODY_TRIANGLES_CAP = 9600`, `POD_BODY_TRIANGLES_CAP = 76800`, `PART_TRIANGLES_CAP = 600` replace the three maxima. `body_triangles_maximum` and `part_triangles_maximum` become `body_triangles_cap(machine)` and `part_triangles_cap(machine)` (part 0 when the motion moves no part, as now). Docstrings say sanity cap, as the game's `model_body_triangles_cap`.
- `check_model`: problems `body has N triangles, over the sanity cap C` and `part has N triangles, over the sanity cap C`, the report line `{model}: body N triangles (cap C), part N (cap P), M materials (limit 8): ...`. The lab holds no reference OBJ, so the lab's check names no reference counts (the brief does).
- The module docstring: the caps instead of the budgets.

### Lab: `tools/model_lab/model_lab.py`

- Add `BOOKLET = REPOSITORY_ROOT / "doc" / "art" / "booklet"`, `REFERENCE_MODELS_DIRECTORY = "reference_models"` and `REFERENCE_MODELS`, a tuple of `(model, ((file, caption), ...))` in the order of the game's list: `stone_furnace` with `furnace_model_front_left.jpg` ("the game's render from the hero angle, lit by the game"), `pod` with `pod_model_round3_exterior.jpg` ("the lab's preview from outside: the riveted cone, the shutter, the antenna"), `pod_model_round3_chair.jpg` ("the lab's preview of the cabin from the chair: the desk, keypads, levers, cabinets, the oxygen manifold") and `pod_model_round3_lamps.jpg` ("the lab's preview looking up: the lamp strip on its brackets, the portholes, the desk lamp"). The pod's are its lab previews, made by the same renderer as the modeller's own, the furnace has only the game's render.
- Add `lab_reference_models(models, machines) -> list`: the `REFERENCE_MODELS` entries whose model is not among the lab's models and whose record (`records.machine_for_model(machines, reference)`) has no fixture whose machine's model is among them (a pod hatch or locker lab does not see the pod, whose renders show the old fixtures), so a lab never shows the modeller the model it remakes.
- Add `reference_counts(model) -> (body, part, materials)`: `check.read_obj` of the repository's `data/models/<model>.obj`, body and part triangles as `check_model` counts them, the distinct materials over both.
- Add `reference_models_text(references) -> str`, the `{{reference_models}}` slot: one bullet per reference, `` `stone_furnace`: the footprint W by D by H cells, B body triangles, P part triangles, M materials`` followed by one sub line per image, `` `reference_models/<file>`: <caption> ``. With no reference: `None: this lab remakes a reference model.` `brief_slots(machines, models, views, collision_models=(), references=())` gains the last parameter, each entry `(model, images, footprint, counts)`, and fills `reference_models` from it.
- `parts_line`: `at most {body} triangles` becomes `under the sanity cap of {body} triangles`, the part's likewise. `brief_slots`' materials line unchanged. `check_command`: `the triangle counts against the budgets` becomes `the triangle counts against the sanity caps`.
- `write_lab`: after the reference images, it creates `reference_models/` and copies each image of `lab_reference_models(models, checkout_machines)` from `BOOKLET` into it (stopping with `no reference model image <path>` when one is missing), and passes the references with their footprints and `reference_counts` to `brief_slots`. The `reference/` images and `unmentioned_images` are unchanged (they apply to the sheet only). A verbatim brief (the furnace's, the pod's) gets the copies but no slot, which is harmless.
- The module docstring names the reference models' renders.

### Lab: `tools/model_lab/brief_template.md`

- A new section after "The reference images", `## The reference models (`reference_models/`)`: the game's accepted models, made in labs like this one, set the tone, the look and the density of everything the game draws. Match them: how much detail they carry for their size, their bevels, their surfaces of raised stones and riveted plates, their way of interleaving the rough and the clean world. They are a yardstick, not the thing to model, and they are not this machine's look (that is the reference images). Then `{{reference_models}}`. Then: there is no triangle budget to fill. A model of about their density for its size is right. The caps below only catch a runaway mesh (a modifier left on, a subdivision): a model near one is a mistake to look at.
- In "Size, frame and limits", the `{{parts}}` lines carry the caps (above). The report paragraph: `what you would add with a larger budget` becomes `where your model is denser or sparser than the reference models and why`. "Look at every one of them" in the references section also covers `reference_models/`: say so in that section's first sentence.
- The committed `tools/model_lab/stone_furnace/BRIEF.md` and `tools/model_lab/pod/BRIEF.md` stay as they are: they are the record of what those modellers saw.

### Lab tests

- `tools/model_lab/check_test.py`: `test_the_budgets` becomes `test_the_caps`: a body polygon of 9603 vertices gives `body has 9601 triangles, over the sanity cap 9600`, the same under `kind = "pod"` none, a part polygon of 603 vertices gives `part has 601 triangles`. The line assertion at line 93 becomes `body 12 triangles (cap 9600)`. `test_the_limits_are_the_games` reads the `_CAP` constants.
- `tools/model_lab/model_lab_test.py`: `test_brief_slots` asserts `under the sanity cap of 9600 triangles`, `600 triangles` and for the pod `76800`, and `brief_slots` without references gives `None: this lab remakes a reference model.` in `reference_models`. New `test_the_reference_models_are_the_games`: the names of `REFERENCE_MODELS` in order equal the strings of `MODEL_REFERENCE_MACHINES` parsed from `src/model_check.odin`, each names a shipped record whose model has that name, and every image exists under `BOOKLET`. New `test_lab_reference_models`: over the shipped records, a lab of `["electric_mining_drill"]` gets both, `["stone_furnace"]` only the pod, `["pod"]` and `["pod_hatch"]` only the furnace. New `test_reference_models_text`: for the drill's lab the text names `reference_models/furnace_model_front_left.jpg`, the furnace's body count as `reference_counts("stone_furnace")` gives it and `8 materials`. `test_the_template_fills` passes references from `lab_reference_models` and still finds no `{{` left.

### Docs

- `doc/build.md`, The workbench, the `--model-check` bullet: the check `budget` becomes `cap` with the caps (9600, a pod's body 76800, a part 600, three times the budgets the reference models were made under, 0275), 8 materials as the limit, and the output gains the reference line before the machines and a counts line per OBJ model before its problems (the two formats). The sealed lab bullet: the lab holds `reference_models/` (the reference models' renders from `doc/art/booklet/`, never a model the lab remakes or one holding it as a fixture), the `{{...}}` slots include the reference models with their counts read from `data/models/`, and `check.py` checks against the caps (9600, 76800 for a pod, 600). Every `model_body_triangles_maximum` becomes `model_body_triangles_cap`.
- `doc/presentation.md`, Machine models: line 152's "only the model check's triangle budget" becomes the cap. Line 156's "the budget" becomes "the caps". Line 169 (the pod): its body is under the pod's cap of 76800 (`MODEL_POD_BODY_TRIANGLES_CAP`), made under the user's budget of 25600 of 2026-10-04, uses 25488, and with the furnace is a reference model (0275).
- `DESIGN.md`, Art direction: the parenthesis `(the workbench's budgets of 0207 become sanity caps that catch a runaway mesh, 0275)` becomes `(the workbench only caps a runaway mesh, 0275)`. Nothing else changes, the 8 materials sentence stays.
- `CLAUDE.md`, Work flow, Model items: `the budget of 3200 triangles and 8 materials` becomes `the reference models' renders and counts, the sanity caps and 8 materials`.
- `doc/log`: the main agent's at landing.

### Hand-back check

- Tests never touch the machine's state directory: the new Odin test reads the shipped `data/` only, the Python tests read the repository read-only and build in temporary directories as now.
- A file is written to `<path>.tmp` and renamed: the reference images are copied into the staging directory that `build` renames into place, so the rule holds as for `reference/`.
- No other line applies: no frame draws from this memory, no save layout, no parsed number, no shared budget, no HUD list.

### Verify

`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `./build.sh model-check` (every model passes, the reference line and a counts line per OBJ model print), `python3 tools/model_lab/check_test.py`, `python3 tools/model_lab/model_lab_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.

### Questions the item left open

- The multiple: three, for the reason under The caps.
- One cap or two for the body: two, a machine's and a pod's, as the kind exception was. The item's "one cap" is read as one cap per kind of mesh replacing each budget.
- The materials: unchanged at 8, for the reason under The caps.
- Which renders: the furnace's hero render and the pod's three lab previews of round three, all already in `doc/art/booklet/`.
- Where model-check shows the references: one line per run, and each model's counts with its cap, instead of a per model ratio, so the line stays readable with more references.

### For the main agent

- 0274 is implementing on the furnace and its spec says "under 3200". The furnace's count after it (about 3149) keeps the three times rule, and the new test reads the live count, so either landing order works. Its spec sentence goes stale after this item lands and needs no edit since 0274 lands first or rebases.
- The pod hatch and locker labs see no pod render (the fixture rule above). If you want them to see the furnace only, as specified, nothing to do. If you would rather show them the pod's exterior only, say so and the rule narrows to the images that show the cabin.
- `CLAUDE.md` is edited by the implementer per the line above. Say so if you keep that file's edits for yourself.

### Decisions (main agent, 2026-10-05)

1. A lab that remakes a pod fixture still gets the pod's exterior render: the exterior carries the tone, and the old fixture in it is a detail the brief names as replaced. Only the render of the model being remade itself is left out.
2. The implementer edits the Model items paragraph of `CLAUDE.md` with the rest; the verifier reads it.
3. The caps at three times the budgets (9600 a machine's body, 76800 the pod's, 600 a moving part), the material limit at 8: approved as reasoned.
