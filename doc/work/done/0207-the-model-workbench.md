# 0207: The model workbench: the game checks and shows a model

Status: landed (2026-10-03, ea0462b; todo user, 2026-10-03, on the pipeline, relaying a comment they got: "Design a framework that can do all the physics modeling, mechanics, clearances, animations and simulations so that Claude just writes the model scripts and doesn't have to direct a ton of work every time you want to see how something works or is put together"; after 0204, before 0205)

## Goal

An agent authors a machine by writing one script that composes the kit's parts, and the rest is done for it: the script reads the machine's record, so nothing is typed twice; the game checks the result in its own mesher and motion code (the fit, the budget, the moving part's sweep clear of the body, the arm's reach, the openings over the open cells); and the game renders the model from fixed cameras, at rest and in motion, to PNG files the agent reads. No run of the game is directed by hand to see how a model moves or fits.

## Change

- The kit reads the records: `tools/models/records.py` (plain Python, imported inside Blender's Python) reads `data/machines.sjson` with the SJSON reading the other generators already do (shared into one module) and gives a script its machine's footprint, motion (kind, axis, pivot, amplitude), ports with their faces, open cells and light. A script places an intake at a port's face by name, an opening over an open cell box and the part about the record's pivot, so the record and the model cannot disagree; the generator refuses a part whose pivot is not the record's.
- The checks, in the game (`--model-check=<machine|all>`, no window, exits 1 on a problem, one line per problem with the machine, the check and the numbers): the fit of 0204; the budget of `DESIGN.md` (triangles per body and part, materials); the moving part swept over its motion at 16 phases through `model_motion.odin` in the working state never intersects the body (every part triangle against the body's triangles, boxes first, exact after) and stays inside the footprint plus the tolerance, so a spinning head never pokes into the neighbour's cell; the arm's parts at 16 cycle fractions on the 500 mm frame clear its base; a machine with open cells has no triangle inside an open cell, so a door is open where the record says. `./build.sh model-check` wraps it, and the test suite runs the same checks over the shipped models, so a check is one piece of code run two ways.
- The views, in the game (`--model-preview=<machine>[,<machine>] --model-preview-directory=<path>`): a window as `--planet-preview-screenshot` opens (`tools/model_preview.sh <machine>` wraps the virtual display for an agent's headless session), the machine alone on a 500 mm frame's pad under the field's sky light, the player's capsule beside it for scale, from four cameras (front three quarter, back three quarter, top, a close front at 2 m), at rest and at phases 0.25, 0.5 and 0.75 of its motion (the arm at its grab, lift and drop fractions), one PNG per camera and phase named `<machine>_<camera>_<phase>.png`, then exit. The renderer's real shading and light, so what the agent reads is what the couch sees.
- `tools/make_models.py` (run in Blender through `tools/blender`, 0204) rebuilds every model, and the wrapper `tools/make_models.sh` runs it and then the game's check (building the debug binary first), exiting as the check does, so a committed model always passes; the agent runs the preview after and reads the PNGs before it hands back.
- Docs: `doc/build.md` (the flags and the wrapper, beside `--planet-preview-screenshot`), `doc/presentation.md` Machine models (the workbench), `doc/content.md` (the authoring rule: a model is written by a script, checked and previewed), the log.

## Verify

- The build and check commands of 0168.
- Tests, no GPU: the checks against hand built meshes (a part that cuts the body at phase 0.5 is reported with the phase; a part leaving the footprint; a body over the budget; a triangle inside an open cell; a clean machine passes); the suite's run over the shipped models passes; `records.py` reads the furnace's ports and the pod's open cells as the Odin loader does (a few golden values).
- Headless: `tools/model_preview.sh burner_mining_drill` writes the 16 files; the front three quarter view at phase 0.5 is sent to the user.

## Specification (design, 2026-10-03)

Designed against `main` at dd64126 and against the approved `## Specification` of 0204, which is not on `main` yet: its worktree `.claude/worktrees/0204` was still at dd64126 with no changes when this was written, so every 0204 name below (`model_obj.load_obj_model_file`, `model_obj.model_file_path`, `Obj_Model`, `Obj_Triangle`, `append_model_triangle`, `model_footprint_problem`, `MODEL_FOOTPRINT_TOLERANCE_CELLS`, `tools/blender`, `tools/models/kit.py` with `join` and `export`, `tools/make_models.py`, `MACHINES`) is the specification's. Where 0204's implementation names it differently, follow the implementation and say so in the report. Models are presentation, so floats are fine throughout; nothing here touches the simulation, a save, a record or the network. No binding, no string key.

### Answers to what the item left open

1. **Which models the checks take.** The OBJ machines (a machine whose `model_obj.model_file_path(data, model)` is a file) and the arm (motion `arm`, still six .vox files until 0206), as the item names both. A voxel machine other than the arm is skipped under `all` and counted in the summary, since the voxel models predate the art direction and 0205 and 0206 replace them; running the sweep on them would fail on parts that were never authored against it. Naming a voxel machine explicitly is one `load` problem line ("a voxel model; the checks take OBJ models and the arm"), exit 1.
2. **The fit of 0204** is the loader's refusal: `load_machine_model_mesh` already refuses a model past the footprint, so its problem text is the `load` line and no second fit check exists. The moving part's fit during motion is new (check `footprint`), through 0204's `model_footprint_problem` on the posed part's bounds: x and z within the footprint plus the tolerance and the bottom at most the tolerance below 0, no upper bound (a chimney or a raised head may rise, as 0204 allows).
3. **Crossing, not contact.** Two triangles intersect when an edge of one passes through the interior of the other, strictly: touching faces, a shared edge and coplanar overlap are not crossings, so a part resting flush on the body passes. A part wholly enclosed in a closed body without any surface crossing is not found; the budget and the preview are what catch that, and no shipped motion produces it.
4. **The shipped drill fails the sweep as 0204 specifies it.** At full stroke (phase 0.5, -0.25 cells) 0204's bit cone reaches z 0.0 to 0.20 and its shaft passes z 0.24, through the bore collar (z 0.14 to 0.24, radius 0.22) and the cross plate (z 0.06 to 0.12) at the same axis. The fix is in the script: `tools/models/machines/burner_mining_drill.py` cuts a bore, `kit.cut` with a 10-sided cylinder of radius 0.13 at Blender (-0.55, 0), z -0.05 to 0.30, from the collar and from the cross plate, so the bit sinks through a hole. Regenerate with `tools/make_models.sh burner_mining_drill`. If 0204 lands its drill differently, the check output names the triangles; fix the script the same way and report the numbers (question 3 below).
5. **The stone furnace has no ports** (`data/machines.sjson` gives it none). The golden test of `records.py` takes the boiler's two ports and the steam engine's two `input_steam` ports instead, plus the pod's open cells as the item asks.
6. **"The SJSON reading the other generators already do"** is regular expressions over one-line entries (`make_placeholder_textures.py`, `read_blocks`, `read_items`, `read_procedural_blocks`); `make_placeholder_sounds.py` reads no SJSON. `machines.sjson` has multi-line records (ports, open cells), so a regular expression does not do. The shared module is a small SJSON parser, `tools/sjson.py`, and the texture generator's three readers move onto it; its output must stay byte identical.
7. **Port names.** The records have no port names, so a port is named `<direction>_<fluid>` (`input_water`), `<direction>` when its fluid is "", and a repeat of a name takes `_2`, `_3` in file order (`input_steam`, `input_steam_2`).
8. **Phases.** 16 at `index / 16` for index 0 to 15, through `motion_transform` (the real motion code, phase 0 the rest). The arm takes the same 16 cycle fractions through `arm_pose_at`. The preview's arm shots map 0.25, 0.5 and 0.75 to `ARM_GRAB_END` (grab), `ARM_SWING_MIDDLE` (lifted mid swing) and `ARM_DROP_FRACTION` (over the drop cell), and its files keep the phase tokens so every machine writes the same 16 names.
9. **The arm's parts against the base:** the upper arm, the forearm, the gripper and both fingers, each against the base. The turret is left out: it turns in place on the base's axis, so no fraction moves it against the base, and its voxel bottom sits on the base's top.
10. **The pitch** is the game config's `foundation_pitch_millimetres` (500 in `data/game.sjson`), passed from `main`, not a second constant. It matters only to the arm (its reach in cells and its stretch) and the preview's metres; OBJ models are in cells.
11. **The open cells** are checked against the body and the part at rest, each box shrunk by `MODEL_FOOTPRINT_TOLERANCE_CELLS` on every side, so a wall flush with the opening's side is not inside it.
12. **The budget** is DESIGN.md's, enforced on OBJ models only: body 200 to 800 triangles, a part under 200 (when it has one), at most 8 materials. Materials are counted as distinct (Kd colour, emissive) pairs of the loaded `Obj_Model`, since the reader keeps no material names; two materials of one colour count once.
13. **The preview's files** go through `platform.write_file_replacing` (raylib's `ExportImageToMemory`, then the temporary file and the rename), not `ExportImage` in place as the planet preview does (hand-back check). A machine id must be `[a-z0-9_]+` to be previewed, so a file name built from it stays in the directory.
14. **The capsule** stands on the machine's -z side (the right side seen from the front, Blender +y), so the arm's swing over +z never passes through it and the front three quarter camera, placed front right, shows it beside the machine.

### Command line (`src/main.odin`)

Three fields in `Command_Line`, after the planet preview's, under the comment `// Work item 0207: the model workbench.`:
- `model_check: string` with usage `"<machine|all>: check the machine's model (all: every OBJ model and the arm) in the game's mesher and motion, one line per problem, exit 1 on any; no window"`.
- `model_preview: string` with usage `"<machine>[,<machine>]: render each machine's model from four cameras at rest and at three phases into --model-preview-directory, then exit"`.
- `model_preview_directory: string` with usage `"<path>: where --model-preview writes <machine>_<camera>_<phase>.png"`.

`workbench_conflict :: proc(command_line: Command_Line) -> string`, new, called first in `command_line_conflict` (before the benchmark branch):
- `--model-check and --model-preview cannot be combined` when both are set;
- `--model-preview needs --model-preview-directory` and `--model-preview-directory needs --model-preview`;
- `<flag> runs no world, so it cannot be combined with --benchmark, --planet-preview, --server, --join or a world's flags` (flag `--model-check` or `--model-preview`) when either is set together with `benchmark > 0`, any `planet_preview*` flag that differs from its default, `server`, `join_address != ""` or `command_line_starts_world`.

In `main`, after `command_line_data_problem` and before the benchmark:
```odin
if command_line.model_check != "" {
	os.exit(run_model_check(command_line.model_check, content.machines, config.foundation_pitch_millimetres, data_directory))
}
if command_line.model_preview != "" {
	os.exit(run_model_preview(command_line.model_preview, command_line.model_preview_directory, content.machines, config.foundation_pitch_millimetres, data_directory))
}
```
Exit codes follow the file's rule: 2 for a bad selection (an unknown machine, a machine without a model, an id that is not `[a-z0-9_]+`), 1 for a failed check or a failed preview, 0 otherwise.

### The checks: new file `src/model_check.odin` (presentation)

Imports `core:fmt`, `core:math/linalg`, `core:os`, `core:strings` and `model_obj`. Header comment: the workbench's checks (0207), pure procedures over the meshes the game draws, in the mesher's frame (cells, x and z centred, y from the bottom; the arm in metres), floats only, run by `--model-check` and by `test_the_shipped_models_pass_the_checks`.

Constants, each with its reason in a comment:
- `MODEL_CHECK_PHASE_COUNT :: 16`.
- `MODEL_BODY_TRIANGLES_MINIMUM :: 200`, `MODEL_BODY_TRIANGLES_MAXIMUM :: 800`, `MODEL_PART_TRIANGLES_LIMIT :: 200` (a part has fewer), `MODEL_MATERIAL_LIMIT :: 8` (DESIGN.md, Art direction).
- `MODEL_CROSSING_EPSILON :: 1e-4`: the share of an edge and of a triangle's barycentric range a crossing must clear, so contact is not a crossing.
- `MODEL_PARALLEL_EPSILON :: 1e-6`: an edge counts as parallel to a triangle when `|det| <= MODEL_PARALLEL_EPSILON * |direction| * |edge1| * |edge2|` (relative, so cells and metres alike).
- `MODEL_CHECK_FRAME :: Frame_Id(1)`: any frame but the block frame, for `inserter_reach_on_frame`.

Types:
```odin
Model_Check :: enum u8 { Load, Budget, Sweep, Footprint, Arm, Open_Cells }
@(rodata) model_check_names := [Model_Check]string{.Load = "load", .Budget = "budget", .Sweep = "sweep", .Footprint = "footprint", .Arm = "arm", .Open_Cells = "open_cells"}
Model_Check_Problem :: struct { check: Model_Check, detail: string } // detail in the temp allocator
Model_Check_Subject :: enum u8 { None, Obj, Arm, Voxel }
Check_Triangle :: struct { corners: [3][3]f32, minimum, maximum: [3]f32 }
Triangle_Crossings :: struct { count: int, first_moving, first_still: int, near: [3]f32 } // count: moving triangles crossing any still one; near: the first moving triangle's centroid
```

Geometry (each 5 to 20 lines, pure):
- `check_triangle :: proc(corners: [3][3]f32) -> Check_Triangle`: the corners and their box.
- `model_layers_check_triangles :: proc(layers: Model_Layers, transform: matrix[4, 4]f32, allocator := context.temp_allocator) -> [dynamic]Check_Triangle`: every indexed triangle of `.Lit` then `.Emissive`, corners through `transform_point`.
- `model_layers_triangle_count :: proc(layers: Model_Layers) -> int`: indices of both layers over 3.
- `check_triangles_bounds :: proc(triangles: []Check_Triangle) -> (minimum, maximum: [3]f32)`: zero for none.
- `boxes_overlap :: proc(a_minimum, a_maximum, b_minimum, b_maximum: [3]f32) -> bool`: closed intervals on all three axes.
- `segment_crosses_triangle :: proc(start, end: [3]f32, corners: [3][3]f32) -> bool`: Möller and Trumbore with `direction = end - start`; false when parallel (relative test above); true when `t`, `u`, `v` and `1 - u - v` all exceed `MODEL_CROSSING_EPSILON` and `t < 1 - MODEL_CROSSING_EPSILON`.
- `triangles_cross :: proc(a, b: Check_Triangle) -> bool`: boxes first, then any of a's three edges crosses b or any of b's crosses a. Two non-coplanar triangles intersect in a segment whose ends lie on edges, so this is exact up to the epsilon.
- `count_triangle_crossings :: proc(moving, still: []Check_Triangle) -> Triangle_Crossings`: the still triangles are first filtered by the moving set's bounds (temp), then each moving triangle against the filtered ones, counting a moving triangle once.
- `point_in_box :: proc(point, minimum, maximum: [3]f32) -> bool`: strictly inside.
- `segment_enters_box :: proc(start, end, minimum, maximum: [3]f32) -> bool`: the slab test; true when the clipped parameter interval is non-empty with positive length; an axis-parallel segment whose coordinate is not strictly inside that axis's interval is false.
- `triangle_enters_box :: proc(triangle: Check_Triangle, minimum, maximum: [3]f32) -> bool`: boxes overlap, then a corner inside, or a triangle edge enters the box, or one of the box's 12 edges crosses the triangle (`segment_crosses_triangle`). That covers a large wall slicing through the box with no corner in it.
- `open_cell_box_in_model :: proc(box: Cell_Box, footprint: [3]i32) -> (minimum, maximum: [3]f32)`: `from` and `to + 1` through `footprint_point_to_model` (`model_motion.odin`), shrunk by `MODEL_FOOTPRINT_TOLERANCE_CELLS` on every side.
- `model_check_phase :: proc(index: int) -> f32`: `f32(index) / MODEL_CHECK_PHASE_COUNT`.
- `obj_model_material_count :: proc(model: model_obj.Obj_Model) -> int`: distinct (colour, emissive) pairs (answer 12).
- `model_check_arm_reach :: proc(machine: Machine, pitch_millimetres: int) -> i32`: `inserter_reach_on_frame(machine, Frame{id = MODEL_CHECK_FRAME, pitch_millimetres = pitch_millimetres})`. Also used by the preview.

The checks (pure, problems in the temp allocator by default; at most one line per check and phase, so a report stays bounded):
- `model_budget_problems :: proc(body, part: Model_Layers, material_count: int, allocator := context.temp_allocator) -> []Model_Check_Problem`. Lines: `body has %d triangles, the budget is 200 to 800`; `part has %d triangles, the budget is under 200` (only for a non-empty part); `%d materials, the budget is 8`.
- `model_sweep_problems :: proc(motion: Machine_Motion, footprint: [3]i32, body, part: Model_Layers, allocator := context.temp_allocator) -> []Model_Check_Problem`. Nothing for a motion without a part (`motion_has_part`) or an empty part. The body's triangles once at the identity; per phase the part's through `motion_transform(motion, footprint, phase)`. A crossing: `.Sweep`, `phase %.4f: %d part triangles cut the body, the first (part %d, body %d) near (%.3f, %.3f, %.3f)`. A posed part off the footprint: `.Footprint`, `phase %.4f: the part %s` with 0204's `model_footprint_problem` text of the posed part's bounds.
- `model_open_cell_problems :: proc(boxes: []Cell_Box, footprint: [3]i32, body, part: Model_Layers, allocator := context.temp_allocator) -> []Model_Check_Problem`. Body and part at rest; per box with triangles inside: `.Open_Cells`, `box %d (cells %v to %v): %d triangles inside, the first (%s %d) near (%.3f, %.3f, %.3f)` where `%s` is `body` or `part`.
- `arm_clearance_problems :: proc(machine: Machine, arm: [Arm_Part]Model_Layers, pitch_millimetres: int, allocator := context.temp_allocator) -> []Model_Check_Problem`. `dimensions := arm_dimensions_on_frame(model_check_arm_reach(machine, pitch_millimetres), pitch_millimetres)`; per fraction `angles := arm_pose_at(dimensions, model_check_phase(index))`, `parts := arm_part_transforms(dimensions, angles)`; the base's triangles through `parts[.Base] * arm_voxel_scale()`; the moving sets `.Upper_Arm`, `.Forearm`, `.Gripper` through `parts[part] * arm_voxel_scale()` and each finger through `arm_finger_transforms(parts[.Gripper], angles.grip)[i] * arm_voxel_scale()`, as `draw_arm_colored` places them. A crossing: `.Arm`, `fraction %.4f: %d %s triangles cut the base, the first (%s %d, base %d) near (%.3f, %.3f, %.3f) m` with the part named `upper_arm`, `forearm`, `gripper` or `finger`.

The machine level (reads files; called by `run_model_check` and the suite test):
- `model_check_subject :: proc(data_directory: string, machine: Machine) -> Model_Check_Subject`: `.None` for `model == ""`, `.Arm` for motion `.Arm`, `.Obj` when `os.is_file(model_obj.model_file_path(data_directory, machine.model))`, else `.Voxel`.
- `check_machine_model :: proc(data_directory: string, machine: Machine, pitch_millimetres: int, allocator := context.temp_allocator) -> []Model_Check_Problem`. `.Obj`: `load_machine_model_mesh` (temp); a problem is one `.Load` line and the end. Then `model_obj.load_obj_model_file` (temp) for `obj_model_material_count`, `model_budget_problems`, and only when the budget passes (so the sweep's cost stays bounded) `model_sweep_problems` and `model_open_cell_problems(machine.open_cells[:machine.open_cell_box_count], ...)`. `.Arm`: load, then `arm_clearance_problems`. `.Voxel`: the one `.Load` line of answer 1. `.None`: nothing. Destroys what it loaded.
- `model_check_report_line :: proc(machine_id: string, problem: Model_Check_Problem) -> string`: `<machine>: <check>: <detail>` (temp), for example `burner_mining_drill: sweep: phase 0.5000: 6 part triangles cut the body, the first (part 41, body 112) near (-0.550, 0.180, 0.000)`.

Cost bound (in the header comment): a body of at most 800 and a part of under 200 triangles give at most 16 × 199 × 800 ≈ 2.5 million box tests per machine, exact tests only where boxes overlap, and the bounds filter cuts the body first; over the budget nothing runs. The open cells are at most 4 boxes × 1000 triangles × 18 tests. The arm's voxel parts are a few hundred triangles each: 16 × 5 sets × parts × base, well under a second unoptimised.

### The command: new file `src/loop_model_check.odin` (loop)

- `model_workbench_selection :: proc(machines: Machine_Registry, list: string, allow_all: bool) -> (selected: []Machine_Id, problem: string)` (temp): `all` (when allowed) is every machine whose `model != ""`, in registry order; otherwise the comma separated ids, each found by `find_machine_id`. Problems: `unknown machine %q`, `machine %q has no model`, `machine id %q is not [a-z0-9_]+`, an empty list. Shared with the preview.
- `run_model_check :: proc(selection: string, machines: Machine_Registry, pitch_millimetres: int, data_directory: string) -> int`: the selection (a problem is logged with `platform.log_printf("error: --model-check=%s: %s", ...)`, return 2); per selected machine its subject: under `all` a `.Voxel` machine is counted and skipped, otherwise `check_machine_model` and each problem printed with `fmt.println(model_check_report_line(...))` on stdout; `free_all(context.temp_allocator)` after each machine; then the summary `model check: %d checked (%d obj, %d arm), %d voxel models skipped, %d problems`. Returns 1 when any problem, else 0. No window, no raylib call.

### The preview: new file `src/loop_model_preview.odin` (loop)

Header comment: `--model-preview` (0207), the precedent `--planet-preview-screenshot`: a window, a fixed scene, frames run, the screen exported, exit. The scene is metres with the frame's cells scaled by the pitch about the origin, up +y; no world, no session, no field.

Constants: `MODEL_PREVIEW_WINDOW_WIDTH :: 1280`, `MODEL_PREVIEW_WINDOW_HEIGHT :: 720` (the Xvfb screen), `MODEL_PREVIEW_FIELD_OF_VIEW :: 40` (vertical degrees, less distortion than the planet preview's 70), `MODEL_PREVIEW_FRAMING :: 1.1` (margin round the bounding sphere), `MODEL_PREVIEW_CLOSE_METRES :: 2` (the item's close front), `MODEL_PREVIEW_THREE_QUARTER_RISE :: 0.55` (the cameras' height share), `MODEL_PREVIEW_PAD_RING_CELLS :: 2` (pad cells round the footprint; an arm's ring is its reach plus 1, so the pickup and drop cells lie on the pad), `MODEL_PREVIEW_WARM_UP_FRAMES :: 3` (frames drawn before the first export, as a first swap under Xvfb can read back empty), `MODEL_PREVIEW_ARM_SLACK_METRES :: 0.3` (the gripper past the reach, for the framing).

Types:
```odin
Model_Preview_View :: enum u8 { Front, Back, Top, Close }
@(rodata) model_preview_view_names := [Model_Preview_View]string{.Front = "front", .Back = "back", .Top = "top", .Close = "close"}
Model_Preview_Phase :: enum u8 { Rest, Quarter, Half, Three_Quarters }
@(rodata) model_preview_phase_names := [Model_Preview_Phase]string{.Rest = "rest", .Quarter = "0.25", .Half = "0.5", .Three_Quarters = "0.75"}
Model_Preview_Pose :: struct { phase: f32, working: bool } // a cycle fraction for the arm
Model_Preview_Camera :: struct { position, target, up: [3]f32 }
Model_Preview_Bounds :: struct { model_minimum, model_maximum, scene_minimum, scene_maximum: [3]f32 } // metres
```

Pure procedures (tested):
- `model_preview_pose :: proc(machine: Machine, phase: Model_Preview_Phase) -> Model_Preview_Pose`: rest `{0, false}`; otherwise working with 0.25, 0.5, 0.75, or for motion `.Arm` `ARM_GRAB_END`, `ARM_SWING_MIDDLE`, `ARM_DROP_FRACTION`.
- `model_preview_file_name :: proc(machine_id: string, view: Model_Preview_View, phase: Model_Preview_Phase) -> string`: `%s_%s_%s.png` (temp), for example `burner_mining_drill_front_0.5.png`.
- `model_preview_capsule_feet :: proc(footprint: [3]i32, pitch_metres: f32) -> [3]f32`: cells `(footprint.x - 0.5, 0, -1)` times the pitch: beside the -z side near the front corner (answer 14), 0.2 m clear of the footprint at 500 mm.
- `model_preview_bounds :: proc(machine: Machine, top_cells: f32, pitch_millimetres: int) -> Model_Preview_Bounds`: the model box is the footprint in metres (x 0 to width, z 0 to depth, y 0 to `top_cells`, all times the pitch); an arm's is the post's centre ± (reach in metres + `MODEL_PREVIEW_ARM_SLACK_METRES`) across and 0 to `ARM_SHOULDER_HEIGHT_METRES + dimensions.upper_arm` high. The scene box is that joined with the capsule's (feet ± 0.3 across, 0 to 1.8 up).
- `model_preview_camera :: proc(view: Model_Preview_View, bounds: Model_Preview_Bounds) -> Model_Preview_Camera`: `centre` and `radius` of the scene box (half its diagonal), `distance := MODEL_PREVIEW_FRAMING * radius / sin(fov / 2)`. Front: `centre + normalize({1, MODEL_PREVIEW_THREE_QUARTER_RISE, -1}) * distance` (front right, the capsule's side), up +y. Back: `normalize({-1, MODEL_PREVIEW_THREE_QUARTER_RISE, 1})`. Top: `centre + {0, distance, 0}`, up `{1, 0, 0}` (the front at the image's top). Close: target the model box's front face centre `{model_maximum.x, model_maximum.y / 2, (model_minimum.z + model_maximum.z) / 2}`, position the target plus `{MODEL_PREVIEW_CLOSE_METRES, 0, 0}`, up +y.

Drawing and the loop (untested, as the draw procedures are):
- `draw_model_preview_pad :: proc(footprint: [3]i32, ring: i32, pitch_metres: f32)`: under `rlgl.PushMatrix` and `rlgl.MultMatrixf` of `uniform_scale_matrix(pitch_metres)` flattened as `draw_frames` does, `draw_frame_cell({x, -1, z}, FRAME_FOUNDATION_COLOR)` for x from `-ring` to `footprint.x - 1 + ring` and z likewise.
- `draw_model_preview_scene :: proc(renderer: Model_Renderer, machine: Machine, machine_id: Machine_Id, pose: Model_Preview_Pose, pitch_millimetres: int)`: the light is the field's open sky at full day, `model_light_tint(with_light_level(0, .Sky, MAXIMUM_LIGHT), 1, {1, 1, 1})`, the glow `emissive_brightness(machine.motion.kind, pose.phase, pose.working, light)`. A machine: `body := uniform_scale_matrix(pitch_metres) * model_transform({}, machine.footprint, 0)`, `draw_model_layers` of the body, then of the part at `body * motion_transform(machine.motion, machine.footprint, pose.phase)` (the `draw_posed_model` sequence without the world). An arm: `draw_arm(renderer, arm, uniform_scale_matrix(pitch_metres) * arm_entity_transform(Entity_Common{size = {1, 1, 1}}, pitch_millimetres), dimensions, arm_pose_at(dimensions, pose.phase), light, glow)` with the glow of `.Arm`. Then the pad and `draw_field_player_capsule(model_preview_capsule_feet(...), {0, 1, 0})`.
- `save_model_preview_image :: proc(path: string) -> string`: `LoadImageFromScreen`, `ExportImageToMemory(image, ".png", &size)`, `platform.write_file_replacing(path, bytes)`, `rl.MemFree`, `UnloadImage`; returns the write's problem ("" on success, `cannot encode` when the export returns nil). Called before `EndDrawing`, as `save_planet_preview_screenshot` is.
- `draw_model_preview_frame :: proc(renderer: Model_Renderer, machine: Machine, machine_id: Machine_Id, view: Model_Preview_View, pose: Model_Preview_Pose, top_cells: f32, pitch_millimetres: int, path: string) -> string`: `BeginDrawing`, `ClearBackground(FIELD_FOG_COLOR)`, `BeginMode3D` with the camera (`fovy = MODEL_PREVIEW_FIELD_OF_VIEW`, perspective), the scene, `EndMode3D`, the save when `path != ""`, `EndDrawing`.
- `run_model_preview :: proc(list, directory: string, machines: Machine_Registry, pitch_millimetres: int, data_directory: string) -> int`: `model_workbench_selection(machines, list, false)` (problem logged, return 2); `install_raylib_trace_log`, `SetTraceLogLevel(.WARNING)`, `SetConfigFlags({.MSAA_4X_HINT})`, `InitWindow(MODEL_PREVIEW_WINDOW_WIDTH, MODEL_PREVIEW_WINDOW_HEIGHT, "Mine oh Belowed model preview")`, the `IsWindowReady` check with the planet preview's log line (return 1), `init_model_renderer(machines, data_directory)`; every selected machine must then have `machine_model` or `machine_arm_model` found, else `error: machine %q: its model did not load (the log names the problem)` and return 1. `MODEL_PREVIEW_WARM_UP_FRAMES` frames of the first shot's scene without a save, then per machine, per phase, per view one frame with the save to `platform.join_path(directory, model_preview_file_name(...))`, `platform.log_printf("model preview: wrote %s", path)` each; a save problem logs `error: could not write %s: %s` and returns 1 after the renderer is destroyed and the window closed. 16 files per machine; return 0. `top_cells` is the uploaded model's `top` (0 for an arm, which `model_preview_bounds` ignores).

`src/loop_field_session.odin`: extract `draw_field_player_capsule :: proc(feet, up: [3]f32)` (`rl.DrawCapsule(feet + up * 0.3, feet + up * 1.5, 0.3, 8, 4, FIELD_PLAYER_CAPSULE_COLOR)`) out of `draw_field_player_body`, which calls it; the preview draws the same capsule.

### Scripts

`build.sh`: a `model_check` function (`build -debug`, then `cd "$repository_root"` and `"$output" --model-check="$1"`), the case `model-check) model_check "${2:-all}" ;;`, and the usage line gains `model-check`. The data directory is found from the repository root as for any run.

`tools/make_models.sh` (bash, executable, `set -euo pipefail`): `cd` to the repository root, `tools/blender tools/make_models.py "$@"` (the named models or all), then `exec ./build.sh model-check`. Usage comment: `tools/make_models.sh [model ...]`; it exits as the check does, so a committed model passes.

`tools/model_preview.sh` (bash, executable, `set -euo pipefail`): usage `tools/model_preview.sh <machine>[,<machine>] [directory]`, the directory defaulting to `tmp/model_preview` under the repository root; `cd` to the root, `./build.sh debug`, then `exec xvfb-run -a -s "-screen 0 1280x720x24" build/mine-oh-belowed --model-preview="$1" --model-preview-directory="$directory"`. Always under Xvfb (Mesa's llvmpipe, the screenshot recipe), also when a display is set, so no window opens on the couch. It prints nothing more; the game logs each file.

### The records reader: `tools/sjson.py` and `tools/models/records.py`

`tools/sjson.py` (standard library only; importable from Blender's Python 3.13 and from `python3` on the host):
- `class SjsonError(ValueError)`: the message names the line and column, `line 12, column 5: expected a value`.
- `loads(text: str) -> dict`: Bitsquid SJSON as the game's `core:encoding/json` with `.SJSON` reads the data: an implicit root object (a text starting with `{` is that object), keys as bare identifiers (`[A-Za-z_][A-Za-z0-9_]*`) or quoted strings, `=` or `:` between key and value, commas optional between members and between array elements, `//` line and `/* */` block comments, values object, array, string (JSON escapes `\" \\ \/ \b \f \n \r \t \uXXXX`), number (JSON's grammar; `int` without a fraction or exponent, else `float`), `true`, `false`, `null`. A duplicate key is an error. Recursive descent over a position, 5 to 15 lines per procedure.
- `load(path) -> dict`: `loads(pathlib.Path(path).read_text())`, an error prefixed with the path.

`tools/make_placeholder_textures.py`: `read_blocks`, `read_items` and `read_procedural_blocks` read through `sjson.load` (`import sjson`; the script's directory is on `sys.path`) instead of the four patterns, which are deleted with the docstring paragraph on regular expressions (it says the data is read with `tools/sjson.py`). `read_blocks` keeps its order, its `SystemExit` for a block without `texture`, and its tuples; `read_items` gives `{"id", and "category" and "places_block" when present}` per entry; `read_procedural_blocks` the set of `textures[].block`. Verify: run the script and `git status --short data/` shows nothing (byte identical output).

`tools/models/records.py` (plain Python, `import sjson` from `tools/`, which `make_models.py` already puts on `sys.path`). Frozen dataclasses mirroring the record as written (the Odin `Machine_Definition` names, defaults equal to the Odin zero values):
```python
Footprint(width: int, depth: int, height: int)
Motion(kind: str = "", axis: str = "", amplitude: float = 0.0, period_seconds: float = 0.0, pivot: tuple = (0.0, 0.0, 0.0))
Port(name: str, cell: tuple, face: str, every_face: bool, direction: str, fluid: str)
CellBox(first: tuple, last: tuple)  # the record's from and to, inclusive ("from" is a keyword)
Machine(id: str, model: str, kind: str, footprint: Footprint, motion: Motion, ports: tuple, open_cells: tuple, light_level: int, light_color: tuple)
```
Functions:
- `load_machines(path) -> dict` (id to `Machine`, file order): the `machines` array of the file; port names per answer 7; `every_face` for face `all`.
- `machine_for_model(machines, model) -> Machine`: the first record naming the model; `SystemExit` naming the model when none does. The model scripts are keyed by model, and records sharing a model (the arm) share its geometry.
- `to_blender(machine, point) -> tuple`: a point of the footprint's frame (from its minimum corner, x width, y up, z depth) to the kit's Blender frame: `(x - width / 2, -(z - depth / 2), y)`.
- `footprint_box(machine) -> (minimum, maximum)`: Blender, `(-w/2, -d/2, 0)` to `(w/2, d/2, h)`.
- `pivot(machine) -> tuple`: `to_blender(machine, machine.motion.pivot)`.
- `port(machine, name) -> Port`: `SystemExit` listing the machine's port names when unknown.
- `port_face(machine, port) -> (centre, normal)`: Blender; the cell's centre plus half a cell along the face, the normal mapped `positive_x (1,0,0)`, `negative_x (-1,0,0)`, `positive_y (0,0,1)`, `negative_y (0,0,-1)`, `positive_z (0,-1,0)`, `negative_z (0,1,0)`; `SystemExit` for an `every_face` port.
- `open_cell_box(machine, index) -> (minimum, maximum)`: Blender; the record's `from` to `to + 1` through `to_blender`, sorted per axis (the y flip).

`tools/models/kit.py` gains `join_part(objects, machine, pivot=None)`: refuses (`SystemExit`, naming the model, the given pivot and `records.pivot(machine)`) a machine whose motion moves no part (`kind` not `pump`, `bob`, `spin` or `swing`), a `spin` or `swing` with `pivot` None, and a pivot further than 1e-6 from the record's on any axis; then `join(objects, "part")`. A `pump` or `bob` part may omit the pivot. `tools/make_models.py` loads `records.load_machines(REPOSITORY_ROOT / "data" / "machines.sjson")` once and calls each `build(machine)` with `records.machine_for_model(machines, name)`; both machine scripts take `machine`, the drill's part goes through `kit.join_part(objects, machine)`, and the drill cuts its bore (answer 4).

### Tests

`src/model_check_test.odin` (game package; meshes built by hand with 0204's `append_model_triangle`; a test helper `box_layers :: proc(minimum, maximum: [3]f32) -> Model_Layers`, twelve outward triangles in `.Lit`, and `machine_with_motion`, as needed):
- `test_a_segment_crosses_only_the_interior`: a segment through a triangle's middle crosses; one ending on its plane, one in its plane, one through its edge and one past it do not.
- `test_touching_boxes_do_not_cross`: two unit boxes sharing a face give `count == 0`; overlapping by 0.1 they give `count > 0` with `near` inside the overlap.
- `test_a_part_cutting_the_body_is_reported_with_the_phase`: footprint {2, 2, 2}, body a slab x and z ±0.9, y 0 to 0.2; part a box x and z ±0.1, y 0.5 to 0.9; pump along y by -0.45. The `.Sweep` lines are exactly the phases 0.3125 to 0.6875 (seven), one of them starts `phase 0.5000:`, phase 0 is not among them, and no `.Footprint` line.
- `test_a_part_leaving_the_footprint_is_reported`: body a box inside {2, 2, 2}; part x 0.5 to 0.9 pumped along x by 0.3. A `.Footprint` line starts `phase 0.5000:` and names x 1.2; phase 0 has none.
- `test_a_clean_spinning_part_passes`: body the slab above, part a bar x ±0.8, z ±0.1, y 0.5 to 0.6, spin about y through the footprint's centre (`pivot = {1, 0, 1}`): no problems.
- `test_a_model_over_the_budget_is_reported`: a body of 801 triangles and one of 199 each give a `.Budget` line naming the count; a part of 200 gives one; 9 materials give one; a body of 200 and of 800, a part of 199 and 8 materials give none.
- `test_a_triangle_inside_an_open_cell_is_reported`: footprint {2, 2, 2}, the box cells (1, 0, 0) to (1, 1, 1); a body filling the other half (x -1 to 0) passes; a small triangle at (0.5, 1, 0) is reported as box 0 and `body`; a large quad in the plane x 0.5 reaching past the box on every side (no corner inside) is reported; a face in the plane x 0 (flush with the box's side) is not.
- `test_the_arm_check_finds_a_part_in_the_base`: a `Machine` with motion `.Arm` and `reach_millimetres = 2000` at pitch 500; arm meshes in voxel units with only `.Base` and `.Gripper` filled, the gripper the main box of `arm_gripper()` in the mesher's centred voxel units (x and z -4 to 4, y 112 to 121; folded at rest it hangs from about 0.60 to 0.83 m, 0.06 to 0.26 m off the axis). A base plate x and z ±12, y 0 to 16 (the shipped base's height) gives no problems; a plate y 28 to 30 (0.70 to 0.75 m, through the folded gripper) gives an `.Arm` line starting `fraction 0.0000:` and naming `gripper`.
- `test_the_model_check_report_line`: `model_check_report_line("burner_mining_drill", {.Sweep, "phase 0.5000: x"})` is `burner_mining_drill: sweep: phase 0.5000: x`.
- `test_the_shipped_models_pass_the_checks`: for every machine of `shipped_machines()` whose `model_check_subject(test_data_directory(), machine)` is `.Obj` or `.Arm`, `check_machine_model(..., 500)` (the shipped `foundation_pitch_millimetres`) is empty; each problem is printed with `model_check_report_line` on failure. At least 2 `.Obj` and 5 `.Arm` subjects, so the test is never vacuous.

`src/loop_model_check_test.odin`:
- `test_the_workbench_selection`: over a registry of three machines (one without a model): `all` gives the two with models when allowed and is an unknown machine when not; `a,b` gives both in order; an unknown id, the machine without a model, `a/b` and "" are refused with their texts.

`src/loop_model_preview_test.odin`:
- `test_the_preview_writes_sixteen_names`: for `burner_mining_drill` the 16 names are distinct and include `burner_mining_drill_front_0.5.png` and `burner_mining_drill_top_rest.png`.
- `test_the_preview_poses`: a pump machine gives `{0, false}`, `{0.25, true}`, `{0.5, true}`, `{0.75, true}`; an arm gives `{0, false}`, `{ARM_GRAB_END, true}`, `{ARM_SWING_MIDDLE, true}`, `{ARM_DROP_FRACTION, true}`.
- `test_the_preview_cameras_frame_the_scene`: a {2, 2, 2} machine with top 2.35 cells at pitch 500: the front camera stands at x above the model's maximum and z below the scene's centre (the capsule's side), the back camera at x below the minimum and z above the centre, both at least `radius / sin(20°)` from the centre; the top camera straight above the centre with up {1, 0, 0}; the close camera exactly 2 m in front of the front face's centre. The capsule's box lies inside the scene box.

`src/main_test.odin`:
- `test_command_line_model_workbench_flags`: `--model-check=all` parses with no conflict; `--model-preview=a` alone and `--model-preview-directory=d` alone conflict; check plus preview conflicts; `--model-check=all` with `--benchmark=1`, `--seed=7`, `--server` and `--planet-preview` each conflicts.
- `test_command_line_usage_lists_every_flag` adds `--model-check`, `--model-preview` and `--model-preview-directory`.

`tools/models/records_test.py` (stdlib `unittest`, runnable as `python3 tools/models/records_test.py`, which puts `tools/` on `sys.path`), golden values read by hand off `data/machines.sjson` as `resolve_machine` resolves them:
- the boiler's ports are `input_water` at cell (1, 0, 0) face `negative_z` and `output_steam` at (1, 0, 1) face `positive_z`; `port_face` of the first is centre (0.0, 1.0, 0.5), normal (0, 1, 0).
- the steam engine's ports are named `input_steam` and `input_steam_2`.
- the pod's three open cell boxes are (3, 0, 1) to (4, 6, 4), (1, 1, 1) to (2, 6, 4) and (5, 0, 2) to (5, 3, 3); `open_cell_box(pod, 0)` is (0, -2, 0) to (2, 2, 7).
- the burner mining drill's motion is `pump`, `y`, -0.25, 0.8; the bore drill's `pivot` is (0, 0, 0) in Blender; the stone furnace's footprint is 2, 2, 2 and its ports are none.
- `sjson.loads` on a small text with every form (bare and quoted keys, `=` and `:`, no commas, both comments, nested arrays and objects, escapes, an integer and a float) gives the expected dict, and a duplicate key and an unclosed array raise `SjsonError` naming the line.

Verify commands: `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `python3 tools/models/records_test.py`, `python3 tools/make_placeholder_textures.py` then `git status --short data/` empty, `tools/make_models.sh` (regenerates the drill with its bore, exits 0), and `tools/model_preview.sh burner_mining_drill` writing 16 files (question 1).

### Docs

- `doc/build.md`: the `build.sh` block gains `./build.sh model-check [machine]  # the debug build, then --model-check (all by default)`; the Command line table gains `--model-check=<machine|all>`, `--model-preview=<machine>[,<machine>]` and `--model-preview-directory=<path>`, each "(below)"; under 0204's `## Models`, a subsection `### The workbench` (0207): what `--model-check` checks and through which code (the loader, the budget, the sweep at 16 phases through `motion_transform`, the arm at 16 fractions on the foundation pitch, the open cells), the report line and the summary, the exit codes; `--model-preview`'s scene (the pad, the capsule, the light, the four cameras, the phases and the arm's fractions, the 16 file names, the warm up frames, the write through `write_file_replacing`); `tools/make_models.sh`, `tools/model_preview.sh` (Xvfb always); the agent's loop (write the script, `tools/make_models.sh <model>`, `tools/model_preview.sh <machine>`, read the PNGs before handing back); `tools/sjson.py`, `tools/models/records.py` and `python3 tools/models/records_test.py`.
- `doc/presentation.md`, Machine models: one bullet: a model is checked by the game's own mesher and motion (`model_check.odin`, `--model-check`) and previewed by its own renderer (`--model-preview`), [build.md](build.md), The workbench.
- `doc/content.md`, Models: the authoring rule, one bullet: an OBJ machine is a script that takes its record from `tools/models/records.py` (footprint, motion and pivot, ports by name, open cells, light), so no number is typed twice; it is committed only when `tools/make_models.sh` passes, after its preview was read.
- `doc/code_map.md`: the presentation list adds `model_check.odin` ("the workbench's checks: budget, sweep, arm clearance, open cells"), the loop list adds `loop_model_check.odin` (`run_model_check`, `model_workbench_selection`) and `loop_model_preview.odin` (`run_model_preview`); the tests line adds `model_check_test.odin`; counts from `tools/code_graph.py`.
- `doc/log/2026-10-03.md`: a new entry "The model workbench (0207)", tags `models, tools, workbench, checks, preview, m14`, with answers 1, 3, 4, 6, 9 and 12 (the scope, crossing against contact, the drill's bore, the SJSON parser, the turret, the material count).

### Hand-back lines that apply

- A file is written to `<path>.tmp` and renamed: the preview's PNGs through `write_file_replacing` (answer 13). A path built from a listing stays under its directory: ids must be `[a-z0-9_]+` (`model_workbench_selection`).
- A list that grows without bound is capped: the report is at most one line per check and phase (16) per machine, and per open cell box (at most 4).
- Tests never touch the machine's state: the tests read `data/` through `test_data_directory()` and write nothing; the preview tests call pure procedures only.
- Not applicable: memory a frame draws from (the preview's renderer lives for the run and is destroyed after its last frame), a start-up load (the workbench is not the game's start; a model that fails to load is a reported problem), parsed numbers (none from text in Odin; Python's `int` does not wrap), save layouts, shared budgets, UI audit cases.

### Questions to the main agent

1. The stage rules say no agent runs the game binary. This item's Verify needs `./build.sh model-check` (no window, seconds) and `tools/model_preview.sh burner_mining_drill` (Xvfb, 16 frames), and answer 4 needs Blender to regenerate the drill. Are the implementer and the verifier allowed these, or does the main agent run them?
2. The drill's bore (answer 4) changes a 0204 file. Fold it into 0204 now, while 0204 is being implemented, or keep it here?
3. Confirm the scope (answer 1): voxel models skipped until 0205 and 0206 convert them, so the open cell check has no shipped subject until the pod is an OBJ.
4. DESIGN.md's floor of 200 triangles per body will bind small machines (a lamp, a pole, a pipe) when 0206 converts them. Keep it as written, or a floor only for machines larger than one cell?

### Approval (main agent, 2026-10-03)

Approved as specified, with the answers: 1, yes: the implementer and the verifier of this item and of every model item after it may run `./build.sh model-check`, `tools/make_models.sh` and `tools/model_preview.sh` (the game in its check and preview modes, the preview under Xvfb); a session, `--planet-preview`, the benchmark and the play build stay forbidden to agents. The rule goes into CLAUDE.md when this item lands. 2, folded into 0204 now: the drill's collar and cross plate get a bore along the shaft, so the bit moves in a hole. 3, confirmed: the checks cover OBJ models and the arm, voxel models are skipped and named as skipped in the summary line; the open cell check gets its first shipped model with the pod. 4, changed in DESIGN.md: the check enforces the maxima only (800 per body, 200 per part, 8 materials); 200 per body is a guide, not a bound.
