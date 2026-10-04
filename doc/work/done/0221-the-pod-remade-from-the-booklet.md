# 0221: The pod remade from the booklet

Status: landed (2026-10-04, commit 211f0ef "Remake the pod from the booklet's interior (0221)", the play build installed; the implementer works in `.claude/worktrees/0221` on `item/0221` from `main`, the round three model of the lab accepted for integration (the user on the phone: "otherwise the latest apk works"); the specification approved the same day with the decisions below, the implementer starts when the user accepts the lab's model; from the pod's interior rounds in the art booklet, accepted by the user the same day; the user the same day: skip the exterior rounds, model the pod now in a sealed lab as the furnace was, with the body budget raised to 25600 triangles for this model; the lab is `tools/model_lab/make_pod_lab.sh`, built by hand like the furnace's since 0214 is not done; the design stage and the modeller run at once)

## Goal

The pod the player wakes in looks like the kept interior of [doc/art/booklet.md](../art/booklet.md), The pod: a cone of riveted panels barely larger than a human, a bolted impact chair with straps at the centre, a bed strapped flat against the wall, computers, screens, buttons, panels and cabinet doors over every other surface, portholes dotted round the walls, and a 1 by 1 m airlock cylinder with camera shutter doors on its flat ends that sticks into the cabin low beside the floor, the outer door flush with the hull. The user's words on each of these are the list at the end of the booklet's page.

## Change

- The model is made in a sealed lab (`tools/model_lab/make_pod_lab.sh`, its brief `tools/model_lab/pod/BRIEF.md`) from the booklet's kept interior, the user's two pictures and the user's words, with no exterior picture (the hull follows from the words), never from the current `tools/models/machines/pod.py` ([doc/content.md](../content.md), The pod, Machine models): the cone, the chair, the bed on the wall, the airlock drum, the fixtures' places; the hatches become the drum's two shutter doors (`pod_hatch.py`, whose record has a `slide` motion or none, gains an iris or the hatch kind gains a motion for it: the design stage decides).
- The budget: the pod's body may have 25600 triangles (user, 2026-10-04, doubled again the same day after round two: "lets say doubling it again to 25600, and remodel the whole thing to be higher fidelity"; the first raise: "since this is such an important model we can increase the budget all the way to 12800"), every other body stays at 3200 (`MODEL_BODY_TRIANGLES_MAXIMUM`): a per record budget or a kind's exception, the design stage decides; the door's part stays at 200 and the materials at 8 per model.
- The lab's bound is a footprint of 12 by 12 by 8 cells (6 by 6 by 4 m), the hull inside it, the cabin floor at the bottom row, the airlock on +x; the door's footprint 1 by 2 by 2 cells (0.5 m along the drum, 1 m across, 1 m high) with the motion the modeller chooses (a slide, a spin or a swing of one rigid shutter; the engine has no iris). The modeller reports the cells it leaves empty (the floor before the chair, a lane 2 cells wide to the airlock, the drum's 2 by 2 bore) and the three fixture pockets (1 cell deep, 2 wide, 4, 2 and 3 high) in the lab's frame; the record is written from that.
- The record follows the model: the footprint and the cabin's open cells (the bed leaves the floor, the chair takes the centre, nothing to stand on beside the airlock's mouth), the airlock's two cells between the doors (1 m, already the record's), the spawn on the chair, the fixtures' cells (the locker, the bench and the oxygen generator on the wall). An old save's pod is replaced at load as `upgrade_resized_pods` does today, with one log line.
- The behaviour the user asked for, as a brief for the design stage: the airlock's doors open and close automatically (today Interact toggles a hatch), tight enough that both are closed round the player standing in the middle; the crouch (0218) fits a 2 m roof and the 1 m drum.
- The arrival (0200) shows the cabin from the chair during the fall, the window's view through a porthole.

## Verify

- `tools/make_models.sh` passes and the lab's OBJ and the repository's are byte for byte the same (the 0212 rule); the workbench previews from the five cameras read as the kept interior and the exterior sheet.
- Tests: the record's open cells and fixtures validate; a new player spawns standing on the free floor in front of the chair, facing the airlock; an old save's pod is replaced with its fixtures and the locker's stacks moved, with the log line; the player crawls through the airlock crouched, stands up in the cabin, and both doors close round a crouched player in the bore.
- The couch: wake in the chair, look round the cabin, climb out through the shutter airlock, come back in.

## Specification (design, 2026-10-04)

Written from the item, `tools/model_lab/pod/BRIEF.md`, `tools/model_lab/make_pod_lab.sh` (for the lab's record only), the docs and the code named below. The model is not described here (CLAUDE.md, Model items): the implementer integrates the accepted lab output and the modeller's report, and writes the record, the code, the tests and the docs this section names. No binding changes: Interact still toggles a hatch (the automatic doors are question 2 below).

### What the implementer receives and reads

- The lab's accepted files in the main checkout (untracked, so by absolute path): `/var/home/Tubbles/dev/mine-oh-belowed/tmp/pod_lab/tools/models/machines/pod.py`, `pod_hatch.py`, `tools/models/palette.py`, `tools/models/kit.py`, `data/machines.sjson` (the lab's `pod_hatch` motion), `data/models/pod.obj`, `pod.mtl`, `pod_hatch.obj`, `pod_hatch.mtl`, and the modeller's report (relayed in the prompt). Never the lab's previews, `BRIEF.md`, the references or the old `tools/models/machines/pod.py` and `pod_hatch.py` of the repository beyond replacing them.
- The report's boxes are in the lab's Blender frame (kit.py): x the front, y the game's -z, z up, one unit per cell, cell corners on integers, the footprint x and y from -6 to 6 and z from 0 to 8. A box is (x0, y0, z0) to (x1, y1, z1) with x0 < x1 and so on, the cells it covers being the unit cubes between the corners.
- The report must name, as such boxes: the free floor before the chair (A), the lane to the inner door (B), the airlock's bore between the doors (C), any further empty cells, the inner and the outer door's 1 by 2 by 2 boxes, the three pockets (locker 4 high, bench 2 high, oxygen generator 3 high), the body's bounds (check.py), and the door's motion. Question 1 asks the main agent to get the door boxes stated explicitly before the implementer starts.

### The record (`data/machines.sjson`)

#### The footprint: shrunk to the model, the height kept

The record does not stay at the lab's 12 by 12 bound: every footprint cell the model leaves outside its hull is a solid pod cell (`machine_held_cells`), an invisible wall round the hull and, if the outer door is not on the footprint's +x edge, a wall in front of the door. So:

- `x_out` = the outer door box's x1 (its outer face, an integer, on the hull's surface).
- `half_x` = max(-minimum x, maximum x) of the body's bounds, `half_y` the same on y (check.py's bounds of `pod.obj`).
- `W` (record `width`, the Blender x) = 2 * max(`x_out`, ceil(`half_x` - 0.02)), at most 12.
- `D` (record `depth`, the Blender y) = 2 * ceil(`half_y` - 0.02), at most 12.
- `H` (record `height`) = 8, kept: cells above the cone are only placement room no one uses, and the antenna may rise above the height (the loader allows it).
- Both are even, so the model's centred frame does not move and the OBJ needs no shift. The lab's script calls `kit.expect_footprint(machine, 12, 12, 8)`: it becomes `(machine, W, D, 8)` in the repository's copy, the only line of the lab's scripts the implementer edits (besides the docstring, below). If the regenerated OBJ then differs from the lab's (the script reads the footprint for geometry), stop and report; the main agent has the modeller rebuild in the lab with the shrunk record (question 1).
- The corners of the footprint outside a round hull stay solid (up to about 1 m out from the hull at the diagonals). Accepted for this item; question 4.

#### The open cells

Blender box (x0, y0, z0) to (x1, y1, z1) to the record's inclusive cell box (record x along the width from the minimum corner, y up, z along the depth):

- `from.x = x0 + W/2`, `to.x = x1 + W/2 - 1`
- `from.z = D/2 - y1`, `to.z = D/2 - y0 - 1`
- `from.y = z0`, `to.y = z1 - 1`

(The inverse of `records.to_blender`: x_b = x - W/2, y_b = D/2 - z, z_b = y.)

`open_cells` in this order, every reported empty cell in exactly one box, no two boxes overlapping:

0. A, the free floor before the chair: it must start on row 0 and span at least 2 cells on x and on z (`validate_pod_cabin`); the spawn stands at the centre of its floor. It must be 4 rows high (2 m, the standing capsule of 1.8 m; the arrival's eye at 1.6 m stays 0.4 m under its top).
1. B, the lane from A to the inner door: at least 2 wide and 4 rows high, its cells face adjacent to the inner door's -x face over the door's z span on rows 0 and 1.
2. C, the bore: `from.x = inner.x + 1`, `to.x = outer.x - 1`, the doors' z span, rows 0 to 1 (`y` 0 to 1). The report's bore may or may not include the door columns; the door boxes decide, the bore is the cells strictly between them.
3. The cells in front of the outer door, only when `x_out < W/2`: x from `outer.x + 1` to `W - 1`, the door's z span, y 0 to 7, which must be geometry free (the heat shield's rim must not stand there; question 1).
4. onwards: any further empty cells of the report as maximal boxes, in report order.

`MAXIMUM_OPEN_CELL_BOXES` is 4. If the list above needs more than 4 boxes, raise it to 8 (`src/machine.odin`), and its readers follow: `Machine.open_cells` (the array grows, nothing else), `validate_open_cells` and `resolve_open_cells` (unchanged code), `test_machine_open_cells_are_boxes_inside_the_footprint` (uses the constant), the header comment of `data/machines.sjson` ("at most 4" becomes 8), `doc/content.md` The pod ("up to `MAXIMUM_OPEN_CELL_BOXES` (4) boxes"), and the cost comment at the top of `src/model_check.odin` ("at most 4 boxes"). If 4 suffice, the constant stays.

`model_open_cell_problems` refuses any triangle inside a box shrunk by 0.02 cells, so the boxes must be exactly the empty cells: the floor plate under them must lie within z -0.02 to 0.02 (question 1). The pod's other cells, the chair's among them, stay solid.

#### The fixtures

`fixtures` in this order (the tests' indices `TEST_OUTER_HATCH` 0, `TEST_INNER_HATCH` 1, `TEST_LOCKER` 2, `TEST_BENCH` 3, `TEST_GENERATOR` 4 stay):

- The two hatches: `{machine = "pod_hatch", cell = <door box's from>, rotation = 0}`, the outer first. Rotation 0 faces the door's front (+x) out of the pod for both, as today. `pod_fixture_box(cell, 0, {1, 2, 2})` must equal the converted door box (1 on x, 2 on z, rows 0 to 1).
- The locker, the bench, the oxygen generator at the converted pockets (`cell` the box's `from`), each turned to face the cabin. The facing is the pocket's side that touches the empty cells (A, B or a further box); the record direction of that side gives the rotation (`machine_front_direction`'s order): record +x 0, +z 1, -x 2, -z 3. From the Blender side: +x is record +x (0), -x is record -x (2), -y is record +z (1), +y is record -z (3). A fixture's own footprint is 1 wide and 2 deep, so an odd rotation gives a box 2 on x and 1 on z (a pocket in a wall across z), an even one 1 on x and 2 on z. The rotated box (`pod_fixture_box`) must equal the converted pocket.
- `validate_pod_fixtures`' rules hold: inside the footprint, no overlap, not on the spawn cells (`pod_spawn_cells` of box 0). New rule, below: no fixture box overlaps an open cells box.

#### The record text

- `pod`: `footprint = {width = W, depth = D, height = 8}`, the comment above it "W by D by 8 cells, the hull's bound (work item 0221): <W/2> by <D/2> by 4 m at the 500 mm pitch; the width is the front axis, the outer hatch on +x.", the comment above `open_cells` naming each box in one line (the floor before the chair where players spawn, the lane, the airlock's bore between the hatches, and so on), the comment above `fixtures` naming the five.
- `pod_hatch`: `footprint = {width = 1, depth = 2, height = 2}`; `motion` the lab's, except a `swing` becomes a `spin` with the same `axis`, `pivot`, `amplitude` and `period_seconds` (a swing goes and comes back over its phase, a hatch's phase is its open fraction, so a swing would close at fully open; a spin at fraction 1 stands where the swing peaks). Its comment says the motion in words ("The shutter slides 2.05 cells up into the drum's wall" or "turns a quarter turn about its hinge"). Named as a deviation in the report when the swing was converted.
- The header comment: the hatch sentence "a slide motion or none" becomes "a slide or a spin motion or none"; the `open_cells` paragraph's "at most 4" follows the constant; "The pod opens its cabin and its airlock but the bed" becomes "The pod opens the floor before its chair, the lane to the airlock and the airlock's bore".

### The budget

A kind's exception, not a record key: one model has it, by the user's word for that model, and a key would invite every record to raise its own.

- `src/model_check.odin`: `MODEL_POD_BODY_TRIANGLES_MAXIMUM :: 25600` beside `MODEL_BODY_TRIANGLES_MAXIMUM`, with the comment "The pod's body (0221, the user's of 2026-10-04): the model every player sees first, from inside, at arm's length."
- `model_body_triangles_maximum :: proc(kind: Machine_Kind) -> int`: 25600 for `.Pod`, 3200 otherwise.
- `model_budget_problems :: proc(body, part: Model_Layers, material_count: int, body_maximum: int, allocator := context.temp_allocator) -> []Model_Check_Problem`: compares the body with `body_maximum` and names it in the detail ("body has %d triangles, the budget is at most %d"). The part (200) and the materials (8) are unchanged.
- `check_obj_machine_model` passes `model_body_triangles_maximum(machine.kind)`.
- The cost comment at the top of the file: the sweep is bounded by the part, and a pod has no part; its open cells and fixture boxes cost boxes times 25600 triangles; the fixture part check (below) filters the body to the part's swept bounds first.
- `src/model_triangle_mesh_test.odin`, the shipped models test: `body_triangles <= model_body_triangles_maximum(machine.kind)`; the `{"pod", ...}` and `{"pod_hatch", ...}` glow flags as the report's materials say (true when a material has a non zero `Ke`).
- `DESIGN.md`, Art direction: "at most 3200 triangles per body and 200 per moving part" becomes "at most 3200 triangles per body (the pod's 25600, the user's of 2026-10-04 for the model seen first and from inside, 0221) and 200 per moving part".
- `doc/build.md`, The workbench, the `--model-check` bullet: "(a body and a part at most 3200 and 200 triangles, a pod's body 25600 (0221), at most 8 materials, ...)".
- `doc/presentation.md`, Machine models: the pod bullet names its 25600 budget.
- `tools/model_lab/pod/check.py` already uses 25600 for the pod: no change.

### The hatch's motion (`src/machine.odin`)

`validate_hatch_definition` allows `.None`, `.Slide` and `.Spin`; the message for any other becomes "hatch %q may only have a slide or a spin motion". A spin's amplitude must satisfy 0 < |amplitude| <= 1 ("hatch %q has a spin amplitude outside 0 to 1 turn"). The generic checks of `validate_motion_definition` (an axis, a pivot inside the footprint, a positive period) still apply. `hatch_pose` already passes the open fraction as the phase and `motion_transform`'s spin turns by 2 pi amplitude phase, so no render code changes. `doc/presentation.md`'s hatch bullet and `doc/content.md` Hatches say "a slide or a spin".

The game's sweep (`model_sweep_problems`) bounds the part by the hatch's own footprint in x and z at every phase and lets it rise above its height. A shutter that slides up into the drum's wall passes; one that slides sideways (Blender y) or swings into the bore leaves the 1 by 2 footprint and fails `./build.sh model-check pod_hatch` (question 1 asks the main agent to tell the modeller now). The implementer never changes the model to make it pass: a failing check goes back to the main agent.

### The open hatch and the crawl (no change to `occupy_open_hatch_cells`)

The premise that a 2 row door leaves one row open to the capsule does not hold: the open hatch's top row is written with `occupant.flags - {.Solid}` (neither solid nor open), and the player collides only with solid cells (`frame_solid_probe` is `raycast_frames(..., {.Solid})`, `world_frame_collision.odin` line 105; `field_capsule_overlaps` and `resolve_field_penetration` go through it). So an open 2 row hatch is passable over both rows, row 0 is passed by the aiming ray and row 1 stops it, which keeps the door aimable to close it. The procedure stays; its comment gains "(a 2 row hatch: the player passes both rows, the ray passes row 0)".

- The crawl: the crouched capsule is 850 mm high and 0.6 m across, its spheres' centres from 0.3 to 0.55 m; the bore is 1 m high and 1 m wide, its roof the solid cells of row 2 at 1.0 m: 150 mm over the head and 0.2 m each side. A standing capsule meets row 2 and is stopped at the drum's mouth; `update_field_crouch` keeps a player crouched inside until the standing capsule fits, so they stand up in the lane or outside.
- Aiming from inside the bore: the crouched eye is at 700 mm (`crouch_eye_height_millimetres`), in row 1, so a level ray meets the closed hatch's row 1 or the open hatch's top row: Interact toggles it. From the lane or outside, standing, the eye is at 1.6 m and the door is 0 to 1 m: the player looks down at it (or crouches); level, the ray meets the solid pod cells above the door, which have no Interact. Named in `doc/content.md`, Hatches.
- Closing: `toggle_hatch` refuses while `capsule_meets_frame_cell` finds a capsule within its radius of a hatch cell. A crouched capsule centred in the 1 m bore is 0.5 m from both doors' cells, more than its 0.3 m radius, so both doors close round it (the item's "both doors closed round the player in the middle"); a capsule in a door's cells refuses.

### The fixture part check (`src/model_check.odin`)

No check today sees whether a hatch's moving shutter cuts the pod's body (the lab checks each model alone). New:

- `pod_fixture_model_transform :: proc(pod: Machine, index: int, fixture: Machine) -> matrix[4, 4]f32`: the fixture's model frame into the pod's model frame: `translation_matrix({-f32(pod.footprint.x) / 2, 0, -f32(pod.footprint.z) / 2}) * model_transform(World_Coordinate(pod.fixture_boxes[index].from), rotated_footprint_size(fixture.footprint, pod.fixtures[index].rotation), pod.fixtures[index].rotation)`.
- `fixture_part_crossing_problems :: proc(pod: Machine, index: int, fixture: Machine, pod_body, fixture_part: Model_Layers, allocator := context.temp_allocator) -> []Model_Check_Problem` (pure): for phase index 0 to `MODEL_CHECK_PHASE_COUNT` inclusive (`model_check_phase`, so the fully open pose 1.0 is checked), the part's triangles through `pod_fixture_model_transform * motion_transform(fixture.motion, fixture.footprint, phase)`; the pod's body triangles kept only where their box overlaps the union of the part's bounds over all phases (`check_boxes_overlap`); `count_triangle_crossings(moving, still)`; one `.Sweep` problem per phase with crossings: "fixture %d (%s) at open fraction %.4f: %d part triangles cut the pod's body, the first (part %d, body %d) near (%.3f, %.3f, %.3f)".
- `pod_fixture_part_problems :: proc(data_directory: string, machines: []Machine, pod: Machine, pod_body: Model_Layers, allocator := context.temp_allocator) -> []Model_Check_Problem`: for each fixture whose machine has `motion_has_part(motion.kind)` and an OBJ, loads its mesh (`load_machine_model_mesh`, a load failure is that fixture's `.Load` problem) and appends `fixture_part_crossing_problems`.
- `check_obj_machine_model :: proc(data_directory: string, machines: []Machine, machine: Machine, allocator := ...)` and `check_machine_model :: proc(data_directory: string, machines: []Machine, machine: Machine, pitch_millimetres: int, allocator := ...)` take the registry's machines; for a `.Pod` with fixtures `check_obj_machine_model` appends `pod_fixture_part_problems` after the fixture boxes. Callers: `run_model_check` (`loop_model_check.odin`, `machines.machines`) and `test_the_shipped_models_pass_the_checks` (`machines`).
- `doc/build.md`, the `--model-check` bullet: "`sweep` ... and for a pod each fixture's part over its motion, open fraction 0 to 1 in 17 steps, placed at its fixture box, against the pod's body (0221)". `doc/code_map.md`, the `model_check.odin` line: "budget, sweep, a pod's fixture parts, arm clearance, open cells".

### The spawn (no procedure change)

`field_pod_spawn` stands new players at the centre of box 0's floor facing the frame's forward, the pod's +x, the airlock's side. Box 0 is the free floor before the chair, so players spawn standing in front of the chair, facing the airlock (the item's "on the chair": the chair's cells are solid and a capsule spawned in them is pushed out; there is no seated posture). The inner door is low and need not be on the line of sight. `pod_cabin_floor_centre` is generalised for the tests:

- `pod_box_floor_centre :: proc(frame: Frame, origin: World_Coordinate, pod: Machine, rotation: u8, box: Cell_Box) -> World_Position` (`simulation_field.odin`): today's body of `pod_cabin_floor_centre` for any box of the unrotated footprint; `pod_cabin_floor_centre` returns it with `pod.open_cells[0]`.

### The pod's lights (`src/render_entities.odin`)

A pod never works, so `emissive_brightness` would draw its screens and lights at the light tint, as lit paint. The pod counts as working: its screens and indicator lights are the cabin's own light, always on; it has no motion, so they are full and steady (no glow pulse).

- Already on `main` from 0224 (decision 7 below): `foundation_model_working :: proc(entities: ^Entities, foundation: Foundation, machine: Machine) -> bool` (true for `.Pod`, the open flag for `.Hatch`, `oxygen_generator_supplies_a_room` for `.Oxygen_Generator`, false otherwise), called by the foundations' loop of `draw_entities`. The implementer adds nothing here.
- `doc/presentation.md`, Machine models, the pod bullet: "its emissive materials (screens, lights) are always lit (`foundation_model_working`, 0221)".

### The arrival (no change)

At the hit `arrival_viewport_camera` cuts to the field camera at the viewer's eye: the spawn's standing eye, 1.6 m over the floor of box 0 (4 rows, 2 m), so the eye is inside the cabin with 0.4 m over it and at least the capsule's 0.3 m from the box's sides, where the nearest geometry stands; the shake (at most `ARRIVAL_SHAKE_METRES`, 0.15 m) and the near plane (`FIELD_NEAR_METRES`, 0.1 m) stay inside that. The view looks at the airlock across the cabin. The descent keeps its window overlay and hides the frames as today. The item's "cabin from the chair during the fall, the window's view through a porthole" is question 3.

### The old save (`src/entity_pod.odin`)

`upgrade_resized_pods` replaces a pod whose saved rotated size is not the record's: a 12 by 8 by 8 pod saved at rotation 1 has size (8, 8, 12), the new one (D, 8, W), so it is replaced. But a 0198 pod has fixtures on its frame, which today stay: the old hatches (saved 1 by 2 by 4) would keep their saved size (`entity_keeps_saved_size`) on the old frame, the old frame would never be released, and the old locker, the quests' reward box, would keep the player's items out of reach. So:

- `take_old_pod_fixtures :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> (locker_stacks: []Item_Stack, removed: int)` (temp allocator): `pool_remove` every alive foundations' entry on `frame` whose kind is `.Hatch`, `.Crafting_Bench` or `.Oxygen_Generator`, and every alive chests' entry on `frame` whose kind is `.Locker`, appending that locker's non empty slots (`slots[:slot_count]`) in slot order. None of these kinds has an item, so nothing on the frame of these kinds belongs to anything but the pod.
- `fill_pod_locker :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id, stacks: []Item_Stack) -> int`: the first alive `.Locker` chest on `frame` takes the stacks into its slots in order, at most its `slot_count`; returns how many it took. Both lockers are the same record (16 slots), so all fit.
- `upgrade_resized_pods` calls `take_old_pod_fixtures(entities, machines, entry.frame)` right after `pool_remove(&entities.foundations, entry.handle)` and `fill_pod_locker(entities, machines, new_frame, stacks)` after `place_pod`. `Upgraded_Pod` gains `moved_stacks: int`.
- `finish_pod_upgrades`' line becomes: "save: the pod of an older build (%d by %d by %d cells) is replaced by the pod of %d by %d by %d cells with its hatches and fixtures, on a frame of its own at the old floor; %d players moved into its cabin, %d stacks moved into its locker". The old frame is released as before, now that nothing stands on it.
- No save layout changes. The behaviour: an old pod's cabin is replaced, its hatches' states are lost (the new ones are closed; `land_field_arrival` is not run again, so a loaded old world starts with both doors closed and the player in the cabin presses Interact on them; named in the log entry), the bench and generator are fresh (they hold nothing).
- `doc/content.md`, The pod, the last bullet, and `doc/architecture.md`, the saves bullet (line 272): the fixtures and the locker's stacks, the new log line.

### Validation addition (`src/machine.odin`)

`validate_pod_fixtures` also refuses a fixture whose box overlaps an `open_cells` box: "pod %q fixture %d stands in open_cells box %d". The record is written by hand from a report, and an overlap would let the occupancy write one cell twice.

### Tests

New helpers in `src/entity_pod_test.odin`:

- `TEST_CABIN_BOX :: 0`, `TEST_LANE_BOX :: 1`, `TEST_AIRLOCK_BOX :: 2`.
- `test_pod_record_cell :: proc(pod: Machine, cell: [3]i32) -> World_Coordinate`: `turned := rotate_footprint_cell({cell.x, cell.z}, pod.footprint.x, pod.footprint.z, POD_ROTATION)`, `pod_origin(pod) + {turned.x, cell.y, turned.y}`. (Record x is the frame's z offset from the origin: frame cell z minus `pod_origin(pod).z`.)
- `test_fixture_front_cell :: proc(pod: Machine, index: int) -> [3]i32`: the record cell in front of a fixture's box at its minimum corner's row: rotation 0 `{box.to.x + 1, box.from.y, box.from.z}`, 1 `{box.from.x, box.from.y, box.to.z + 1}`, 2 `{box.from.x - 1, ...}`, 3 `{box.from.x, box.from.y, box.from.z - 1}`.
- `test_pod_inside_cells :: proc(pod: Machine) -> []World_Coordinate`: the placed open cells (`machine_open_cells` per box, as `test_pod_box_cells`) of the boxes touching neither x 0, x W-1, z 0, z D-1 nor the top row: the cells the sealed room holds with both doors closed.
- `test_airlock_player :: proc(frame: Frame, pod: Machine) -> Field_Player`: `make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.open_cells[TEST_AIRLOCK_BOX]), frame.axes[FRAME_FORWARD])` with `crouching = true`.
- In `src/simulation_field_test.odin`: `move_test_players_out_of_the_pod :: proc(state: ^Simulation_State, machines: Machine_Registry)`: `open_closed_hatches`, then every player's body (`move_field_player_body`) to a `make_field_player` at the floor point two cells in front of the outer hatch's outer face, centred on its z span (`pod_box_floor_centre` of the record box x `outer.x + 2`, the hatch's z span, row 0; outside the footprint is fine), facing the frame's forward.

Changed (`src/entity_pod_test.odin`):

- `test_place_pod_stands_the_pod_on_its_frame_with_no_pad`: the literal 768 becomes W * D * 8.
- `test_place_pod_places_its_hatches_and_fixtures`: `pod_origin` `{-(D - 1) / 2, 0, -(W - 1) / 2}` as a literal; the outer hatch's four cells are `test_pod_record_cell` over its box (rows 0 and 1).
- `test_the_pods_interior_is_open_and_its_hull_bed_and_closed_hatches_solid` becomes `test_the_pods_open_cells_are_open_and_the_rest_solid`: the two generic loops stay; the five literal cells give way to the record cell over the bore (`{bore.from.x, 2, bore.from.z}`, the drum) and `{W / 2, 7, D / 2}` (the top row) being solid.
- `test_a_hatch_toggles_its_cells`: `cell.y < 3` becomes `cell.y < hatch.footprint.y - 1` (row 0 only).
- `test_closing_a_hatch_on_a_player_is_refused`: `in_door` the crouched capsule at the outer hatch box's floor centre (`pod_box_floor_centre` with `pod.fixture_boxes[TEST_OUTER_HATCH]`), refused; `in_airlock` `test_airlock_player`'s capsule, closes.
- `test_a_field_player_walks_through_the_pods_door_and_the_walls_stop_it` becomes `test_a_field_player_crawls_through_the_airlock_and_stands_in_the_cabin`, at every `TEST_FIELD_SPACINGS`: start standing two cells in front of the outer door (as `move_test_players_out_of_the_pod`) facing `-frame.axes[FRAME_FORWARD]`, 30 ticks still. (a) Both doors closed, `FIELD_WALK_FORWARD` 120 ticks: the feet stop at the outer face (frame z at least the face plus the radius minus `FIELD_GROUND_TOLERANCE`). (b) Both open, standing walk 120 ticks: still stopped there (the hull over the door). (c) `FIELD_SNEAK_FORWARD` until the feet's record x is at most `inner.x - 1` (at most 600 ticks), then 30 ticks with no input: not crouching, on the ground, the feet's cell an open cell of box `TEST_LANE_BOX` or `TEST_CABIN_BOX`, `field_capsule_overlaps` false. (d) `FIELD_WALK_FORWARD` 120 ticks on: the feet stay in open cells of the cabin's boxes and the capsule overlaps nothing.
- `test_the_aiming_ray_passes_the_pods_open_cells_and_stops_at_its_walls` becomes `test_the_aiming_ray_meets_the_airlocks_hatches_from_the_bore`: a foundation and a wooden chest on the pod's frame on row 0 at record x `W + 1`, the doors' first z (outside the footprint, as today's test does at `front + 2`); from `test_airlock_player`'s crouched eye (`field_player_eye`) along the forward: closed, the hit is the outer hatch's row 1 cell; open, the hit is still the outer hatch (its top row), so it can be closed from inside; from the bore's row 0 centre (the floor centre lifted a quarter pitch) open, the ray reaches the chest; the ray from the crouched eye to the frame's up hits the solid row 2 cell (the drum).
- `test_the_sealed_room_follows_the_hatches`: the expected room is `test_pod_inside_cells`; the airlock is box `TEST_AIRLOCK_BOX`.
- `test_the_fixtures_refuse_pick_up_and_placement_over_them`: the cell in front of the locker is `test_pod_record_cell(pod, test_fixture_front_cell(pod, TEST_LOCKER))`; the comment "along the frame's x 3 wall" goes.

New:

- `test_the_pods_record_follows_the_model` (`entity_pod_test.odin`, the shipped record through `make_test_machines`): box 0 starts on row 0, is at least 2 by 2 and 4 rows high; box `TEST_LANE_BOX` is 4 rows high and touches the inner hatch's -x face over its z span on rows 0 and 1; box `TEST_AIRLOCK_BOX` is exactly from `inner.x + 1` to `outer.x - 1`, the hatches' z span, rows 0 to 1; the outer hatch's +x neighbours are outside the footprint (`outer.x == W - 1`) or in an open box touching x `W - 1`; for the locker, the bench and the generator `test_fixture_front_cell` lies in an open cells box; the generator's box is face adjacent to a cell of `test_pod_inside_cells`.
- `test_both_hatches_close_round_a_crouched_player_in_the_airlock` (`entity_pod_test.odin`): both open, then `toggle_hatch` closes the outer and then the inner with `test_airlock_player`'s capsule in the list: both closed, and `field_capsule_overlaps` false for that player on a flat test field at 1000 mm (the crouched body fits the closed airlock).
- `test_an_old_pod_and_its_fixtures_are_replaced_at_load` (`entity_pod_test.odin`, as `test_an_old_pod_is_replaced_at_load`): an old frame with the pod at `{-3, 0, -5}` rotation 1 and its size set to `{8, 8, 12}`, two `pod_hatch` entities (sizes set to `{1, 4, 2}`), a `pod_locker` with 5 iron ore (any item of the content) in slot 0 and 3 in slot 4, a `crafting_bench` and an `oxygen_generator`, all on the old frame at origins `{10, 0, 0}`, `{12, 0, 0}`, `{14, 0, 0}`, `{16, 0, 0}`, `{18, 0, 0}` (outside the old pod's box; only the frame matters). Saved and loaded: one pod, of the record's size; no alive hatch, locker, bench or generator on the old frame; the old frame gone; the record's five fixtures on the new frame; the new locker's slots 0 and 1 hold the two stacks; `count_entities_keeping_saved_size` 0; one sealed room.
- `test_the_pod_draws_its_lights_as_working`: struck, 0224 landed it as `test_the_pod_counts_as_working_for_its_model` (`entity_pod_test.odin`).
- `test_the_pods_body_budget_is_25600` (`model_check_test.odin`): `model_body_triangles_maximum(.Pod)` 25600 and `(.Furnace)` 3200; `model_budget_problems(triangles_layers(25600), empty, 1, 25600)` none; `triangles_layers(12801)` one problem whose detail contains "12801" and "25600".
- `test_a_hatch_part_cutting_the_pod_is_reported` (`model_check_test.odin`): a pod `Machine` of footprint `{4, 4, 4}` with one fixture (cell `{3, 0, 1}`, rotation 0, its box from it to `{3, 1, 2}`), a hatch `Machine` of footprint `{1, 2, 2}` with `{kind = .Slide, axis = 1, amplitude = 2, period_seconds = 0.8}`, the part `box_layers({-0.05, 0, -0.9}, {0.05, 1.9, 0.9})`; a pod body of `box_layers({1.0, 2.5, -2}, {2, 3, 2})` (a block over the door's path) gives at least one problem naming "fixture 0", and one of `box_layers({-2, 2.5, -2}, {-1, 3, 2})` (clear of the path) none. (Model frame: x of the pod from -2 to 2, the door's x from 1 to 2.)

Changed elsewhere:

- `model_check_test.odin`: `test_a_model_over_the_budget_is_reported` passes `MODEL_BODY_TRIANGLES_MAXIMUM` as `body_maximum` in every call; `test_the_shipped_models_pass_the_checks` calls `check_machine_model(test_data_directory(), machines, machine, 500)`.
- `machine_test.odin`: `test_machine_open_cells_are_boxes_inside_the_footprint`: the shipped pod's `open_cell_box_count` and `open_cells[TEST_AIRLOCK_BOX]` (the converted bore) as literals. `test_the_world_placed_fixture_kinds_are_validated`: `spinning` moves from the refused list to the accepted (amplitude 1 passes); new refused cases `swinging` (`kind = "swing"`, amplitude 0.25, axis y), `overturned` (spin amplitude 1.5) and `pumping` (`kind = "pump"`); the hatch's footprint in the test becomes `{1, 2, 2}`. `test_the_pod_fixtures_are_checked`: a refusal case of a locker at `{4, 0, 2}` rotation 0 expecting "stands in open_cells box 0" (its box x 4, z 2 to 3 lies in the test pod's cabin box `(1, 0, 1)` to `(4, 1, 2)` and off its spawn cells x 2 to 3, z 1 to 2, which are checked first).
- `tools/models/records_test.py`: `test_the_pod_open_cells` the new boxes and `records.open_cell_box(pod, 0)` (computed by `to_blender`: it gives back the report's Blender box A); `test_the_pod_fixture_boxes` the new sizes (`(2, 4, 1)` for an odd locker rotation, `(1, 4, 2)` for an even one) and `fixture_box(pod, 0)` (the report's outer door box) and `fixture_box(pod, 2)` (the locker's pocket).
- `src/simulation_field_test.odin`: `test_toggling_a_hatch_is_lockstep_state` puts the player on the lane two cells before the inner hatch's -x face, centred on its z span (`pod_box_floor_centre` of that record box), facing the forward, and holds Sneak on both ticks (`pressed = {.Sneak}`, then `{.Interact, .Sneak}` with `just_pressed = {.Interact}`), so the crouched eye's ray meets the low door; its expected room (outer closed, inner open) is `test_pod_inside_cells` (the bore among them) plus the inner hatch's cells. The scripted tests (`test_two_field_simulations_hash_alike_and_part_on_one_input`, `test_two_field_simulations_hash_alike_after_a_walk_over_dug_ground`), `test_a_field_walk_counts_and_a_flight_does_not` and `test_a_machine_on_bare_ground_stands_centred_on_its_frame` call `move_test_players_out_of_the_pod` in place of `open_test_pod_hatches` (a standing walk no longer leaves the pod); the script's walk then starts at the door instead of 2.75 m inside it; if an assertion about where the script lands fails (the foundation, the dig, the place back), shorten the walk window (`tick < 240`) by 40 ticks (2.75 m at 4.3 m/s) and say so.
- `src/lockstep_test.odin`, `test_a_field_prediction_into_a_wall_snaps_to_the_confirmed_feet`: its comment about the inner hatch 0.75 m ahead goes; if the pod's cells now stop the backwards walk before the field wall does, it calls `move_test_players_out_of_the_pod` first and says so in the report.
- Any other field session test that fails because the spawn's surroundings changed takes `move_test_players_out_of_the_pod` and is named in the report with its line; a failure not explained so is reported, not rewritten.
- Rerun, expected unchanged: `test_an_old_pod_is_replaced_at_load`, `test_a_saved_pod_loads_with_its_open_cells`, `test_the_feet_tell_the_sealed_room`, `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin`, the arrival tests (`simulation_arrival_test.odin`, `render_arrival_test.odin`), the benchmark test (pad plus 5 foundations' entries), `test_entity_keeps_saved_size_spares_the_pod`, the crouch tests.

### Commands (implementer, in the worktree `.claude/worktrees/0221`)

Prefix the heavy ones with `taskset -c 8-15 nice -n 10`.

1. `cp` the lab's `pod.py` and `pod_hatch.py` (absolute paths above) over `tools/models/machines/pod.py` and `pod_hatch.py`; edit only the `kit.expect_footprint` line of `pod.py` to `(machine, W, D, 8)` and the docstrings' first line to name the work items (0179, 0198, 0221). `tools/models/machines/__init__.py` is unchanged (same module names).
2. `diff` the lab's `palette.py` with the repository's: append the lab's new entries under the comment `# 0221, the pod and its airlock door.`; an existing entry the lab changed is reported, not copied. `diff` the lab's `kit.py`: new functions are appended verbatim, with the item in their docstring; a changed existing function is copied only if step 4 leaves every other model's OBJ byte for byte unchanged (`git status data/models` shows only the pod's four files), else reported. A changed `records.py` or `make_models.py` in the lab is reported, not copied.
3. The record edits, then the code and the tests above.
4. `tools/make_models.sh` (all models: Blender, then `./build.sh model-check`), passing. Then `cmp` each of `data/models/pod.obj`, `pod.mtl`, `pod_hatch.obj`, `pod_hatch.mtl` with the lab's; any difference is reported (the 0212 rule). Report the body's and the part's triangle counts.
5. `MODEL_PREVIEW_DIRECTORY=tmp/model_preview tools/model_preview.sh pod,pod_hatch` and read `pod_front_rest.png`, `pod_front_left_rest.png`, `pod_back_rest.png`, `pod_top_rest.png`, `pod_close_0.25.png` (lit: phases past rest are working) and `pod_hatch_front_0.5.png`, `pod_hatch_close_0.5.png`: no hole in the hull, the outer door flush on the front, the shutter halfway along its motion.
6. `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/models/records_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
7. Set the status to `implemented`. Never commit, never run the game as a session or the benchmark, never install.

### Docs (same commit)

- `doc/content.md`, The pod: the footprint (W by D by 8, the hull's bound, the lab's 12 by 12 by 8 shrunk); the open cells boxes listed with their record cells and what each is (the floor before the chair, the lane, the bore, ...), what stays solid (everything else, the chair and the corners outside the round hull among it); the spawn (standing in front of the chair, facing the airlock); the fixtures' cells and rotations; `MAXIMUM_OPEN_CELL_BOXES` if raised; the new `validate_pod_fixtures` rule; the old pod bullet with the fixtures removed, the locker's stacks moved and the new log line.
- `doc/content.md`, Hatches: 1 by 2 by 2 cells, a slide or a spin, the open hatch's two rows (passable, the ray passing row 0), the crawl crouched, aiming down or crouched at the door, both doors closing round a crouched player in the bore; the old "slides up 3.95 cells" sentence replaced by the record's motion in words.
- `doc/content.md`, Models: the pod bullet rewritten (0221: made in a sealed lab from the booklet's kept interior, its parts in one line from the report, its materials and triangle count; `pod_hatch.py` the drum's shutter door).
- `doc/presentation.md`, Machine models: the pod bullet (the size, the 25600 budget, the lights always lit through `foundation_model_working`), the hatch bullet (slide or spin, the fixture part check).
- `doc/build.md`, The workbench: the `--model-check` bullet (budget, fixture parts); the sealed lab bullet gains "`tools/model_lab/make_pod_lab.sh` builds `tmp/pod_lab/` the same way for the pod (0221), the pod's footprint widened to 12 by 12 by 8 and its open cells and fixtures stripped, the hatch at 1 by 2 by 2".
- `doc/architecture.md`: the saves bullet (old pod upgrade: fixtures, locker, the log line); The player on the field, the crouch bullet: "the pod's airlock is 1 m high, so the player crawls through it crouched (0221)".
- `doc/code_map.md`: the `model_check.odin` line as above; the `entity_pod.odin` line "the old pod's upgrade at load with its fixtures and locker (`upgrade_resized_pods`, `take_old_pod_fixtures`)".
- `DESIGN.md`, Art direction: the budget sentence above.
- `data/machines.sjson` header as above.
- `doc/log/2026-10-04.md`, a new section "The pod remade from the booklet (0221)", tags `models, art, pod, airlock, budget, m15`: the lab and the integration; the budget as a kind's exception and why not a record key; the footprint shrunk to the hull and why (invisible walls), the corners left; the open cells and fixtures from the report and the conversion; the hatch's spin and why a swing is not a hatch's motion; the open hatch's top row already passable (no change), the crawl; the fixture part check; the pod's lights always on; the old pod's fixtures and locker at load; the tests moved out of the pod; what the rounds changed.

### Hand-back check lines that apply

- "A changed save layout loads an old save (a remap and one log line)": no layout change; the old 0198 pod is replaced with one log line naming the moved stacks, covered by `test_an_old_pod_and_its_fixtures_are_replaced_at_load`. The doors' lost state is named in the log entry.
- "Tests never touch the machine's state directory": the save tests use `make_save_test_directory`.
- "A number parsed from text is range checked": the hatch's spin amplitude is bounded in `validate_hatch_definition`; the footprint by `validate_footprint`.
- The others (frame memory, file writes, start-up loads, shared budgets, unbounded lists, UI audit cases) do not apply: say so in one line.

### Questions the item left open, answered

- Budget mechanism: the pod kind's exception (above).
- The record's size: shrunk to the hull's bound on x and y, the height kept (above).
- The hatch's motion: slide or spin; a swing converts to a spin (above).
- The 2 row door and the crouch: no change needed (above).
- The spawn "on the chair": in front of it, standing (above).
- The pod's screens: always lit (above).
- The arrival at the hit: no change (above).

### Questions for the main agent

1. Before the modeller hands back (relay now, while the lab runs): (a) report the inner and outer door boxes explicitly; (b) the game's sweep keeps the open shutter inside the door's 1 by 2 cells in x and z at every phase (rising above its 2 rows into the drum's wall is fine), so a sideways slide or a swing into the bore fails `model-check`; (c) the empty cells must be truly empty: the floor plate under them within z -0.02 to 0.02, nothing of the rim or the drum in them; (d) nothing in front of the outer door (the heat shield's rim cut at the door); (e) at acceptance, set the lab's record to the shrunk W by D by 8 (formula above, from its own bounds and door box) and the stub's `expect_footprint` line, rebuild and check, so the implementer's byte comparison holds.
2. The automatic doors (the item's brief): not specified here, since it changes what Interact does on a hatch (the control design is yours) and meets the arrival opening both doors at once. A proposal for an item of its own: a lockstep step after the players move, per pod: a door opens when a capsule stands within one cell of its outer side or crouches in the bore facing it, and only while the other door is closed (the interlock); it closes once no capsule meets its cells or its approach cells; Interact stays as an override. Fold into this item, or a new item?
3. The arrival "from the chair through a porthole": the descent hides the pod and draws the shader window; showing the real cabin needs the pod drawn moving with the camera along the path, a seated eye (a record key, say `seat = {x, y, z}` in cells, from the report's chair) and the flames moved outside the porthole. It depends on where the portholes ended up. A follow up item once the model is accepted?
4. The footprint's corners outside the round hull stay solid (up to about 1 m from the hull at the diagonals). Acceptable, or open them with more `open_cells` boxes (a staircase per corner, about 8 more boxes, `MAXIMUM_OPEN_CELL_BOXES` to 16)?
5. The item's Verify says "spawns on the chair": accept "standing in front of the chair, facing the airlock" as the spawn, with the arrival's hit view from there?

### Decisions at the approval (main agent, 2026-10-04)

1. Relayed to the modeller while the lab runs: the inner and outer door boxes reported explicitly; the shutter stays inside the door's x and z at every phase, so it slides up into a pocket in the drum's wall above the bore (a sideways slide or a swing into the bore fails the game's sweep); no floor plate under the empty cells (the ground is the floor there), nothing of the rim in front of the outer door; the record shrinks to the hull at acceptance and the lab rebuilds with it.
2. The automatic doors are item 0222 (todo, the design's proposal as its brief, the control design the main agent's). Interact stays the only way to toggle a hatch in 0221.
3. The arrival seen from the chair through a porthole is item 0223 (todo, after this item lands).
4. The corners of the footprint outside the round hull are opened, not left as invisible walls: `MAXIMUM_OPEN_CELL_BOXES` goes to 32 (its readers as the specification lists for 8), and the boxes beyond the hand written A, B, C and the cells before the outer door are computed, not guessed. The implementer writes `tools/models/empty_cells.py` (plain Python, on the host, tested by `tools/models/empty_cells_test.py` against a small OBJ): it reads `data/models/pod.obj` and the record's footprint, marks a cell solid when any body triangle's bounding box meets the cell's box shrunk by 0.02 cells (conservative on the solid side, so the game's exact test never refuses), takes the hand written boxes as given, merges the remaining empty cells into maximal boxes (greedy: runs along x, then merged across z, then across y) and prints them as `open_cells` entries in the record's frame. The pod's cells that the hull's rim touches at row 0 stay solid, which is the collision wanted (a 0.5 m lip is not stepped over). `doc/build.md`, Models, documents the tool in one bullet.
5. The spawn is standing in front of the chair, facing the airlock (the Verify section says so now).
6. The user (2026-10-04): "The pod airlock doors shall need crouching to pass through." The 1 by 2 by 2 door and the 2 row bore are that: the standing capsule (1.8 m) is stopped at the drum's mouth by the solid cells over the door, the crouched one (0.85 m) passes with 150 mm of headroom; `test_a_field_player_crawls_through_the_airlock_and_stands_in_the_cabin` proves both at every spacing. The modeller's brief already asks for a 1 m bore and a 1 by 2 by 2 door; no change to the lab.
7. 0224 (point lights on machine models) lands before this item and brings `foundation_model_working`, its test and the `lights` record key. This item's implementer finds them on `main`, puts the six cabin lamps of 0224's decision 3 into the pod's `lights` list with the model, and the new tests of the lights paragraph above are struck as noted.
8. The user, after the first lit cabin shots (2026-10-04): "Hmm i like the colors but it still looks flat, does it cast shadows? And i dont see any lamp models. Lets decrease to one overhead lamp strip in the ceiling and one desk light. Also i think maybe we should try increasing the budget even more, lets say doubling it again to 25600, and remodel the whole thing to be higher fidelity, its a little too placeholder-y as it is." So: the budget is 25600 everywhere above (the constant, the test name, the docs, the lab's check), the pod's `lights` list holds two lamps (the ceiling strip and the desk light, at the fixtures the round three model places), and the flatness goes to 0225 (the cabin's base light), not to this item. 0225 landed (commit 5125964) with the key `interior_light_share` and no shipped value: this item's implementer writes `interior_light_share = 0.25` above the two lamps in the pod's record and flips the shipped pod's share assertion in `test_the_interior_light_share_is_a_pods_and_bounded` (`machine_test.odin`) from 1 to 0.25.
9. The user (2026-10-04, with the round three preview): "Skip the stepped collider work, do a better collision directly." Decision 4 is struck: no `tools/models/empty_cells.py`, no raise of `MAXIMUM_OPEN_CELL_BOXES` for the corners, the open cells stay the hand written boxes (the cabin, the lane, the airlock) and the pod collides as its footprint box until 0230 (collision volumes authored with the model) lands after this item.
