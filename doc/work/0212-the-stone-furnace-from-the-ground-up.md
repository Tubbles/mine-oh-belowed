# 0212: The stone furnace, redone from the ground up under supervision

Status: implementing (2026-10-03, worktree `.claude/worktrees/0212` on `item/0212` from `main`, the specification approved the same day with the decisions below; user, 2026-10-03: the 0205 models "are fine for very rough placeholder ideas ... but they are very flat, both geometry and color wise ... they need to be completely scrapped ... i want us to completely scrap a single machine and redo it from the ground up, with my supervision ... Lets do the stone furnace first. I want it to be larger, feeling awe-inspiring, formidable, and intimidating through sheer presence, more akin to satisfactory style machine sizes"; after 0211)

## Goal

The stone furnace is the first machine made in the chosen art direction, from nothing: larger than today's 2 by 2 by 2 cells, formidable through sheer presence as Satisfactory's machines are, modelled against the reference sheet of 0211's second session, with the user judging every round on the couch and in the previews.

## Change

- The footprint grows (the user chooses the size on the reference sheet; a candidate is 4 by 4 by 5 cells, 2 by 2 by 2.5 m, with the record's `footprint`, ports and open cells changed to match; the recipes, the quests and the dev kits that place it are checked for the new size, and an old save's furnace keeps its saved footprint through the remap of 0196's kind).
- The modeller never sees the old model (user, 2026-10-03: "When the subagent works on the new model it shall not have seen the old one"): before its worktree is handed over, the old `tools/models/machines/stone_furnace.py`, `data/models/stone_furnace.obj` and `.mtl` are deleted from it, and its brief names the reference sheet, the record, the kit and the workbench only, never the old script, the old previews or 0204's log entry. The design stage writes the block from the reference sheet.
- Rounds: the implementer hands back previews from the workbench (0207); the main agent sends them; the user says what to change; the same agent iterates until the user accepts. The accepted model lands with its reference sheet in `doc/art/`.
- What is learned about the kit (primitives the look needs, a material or shading rule) goes into `tools/models/kit.py`, `DESIGN.md` and the log, so the next machine starts from it. The other machines follow one at a time, each its own item.

## Controls

- None.

## Verify

- The workbench's check passes, the previews read as the reference sheet, the suite passes with the new footprint, an old save loads.
- The couch: the user stands next to it and it feels formidable.

## Specification (design, 2026-10-03)

Written from the reference sheet (`work/art/2026-10-03-round-4/furnace/banana2_0.png`, the hero view; `work/art/2026-10-03-furnace-sheet/`: `turnaround`, `plan`, `rear_quarter`, `detail_mouth`, `detail_top`, `sheet.png`), the record, the kit and the workbench. The designer did not open the old script, the old OBJ or MTL, or any preview of the old furnace, and this section does not describe them.

### The rule of the clean room (implementer, read first)

- Before anything else, in the worktree `.claude/worktrees/0212`: `git rm tools/models/machines/stone_furnace.py data/models/stone_furnace.obj data/models/stone_furnace.mtl`. Do not open them before, do not read them from git afterwards (`git show`, `git log -p`, `git diff` against `main` on those paths, the main checkout's copies), and do not open `tmp/model_preview/stone_furnace_*` of the main checkout.
- Also never read: `doc/work/done/0204-machine-models-of-arbitrary-geometry.md`, `doc/work/done/0205-the-model-kit-and-the-first-machines.md`, and the sections "The model pipeline (0204)" and "The model kit and the machines before oil (0205)" of `doc/log/2026-10-03.md`. Everything needed from them is in this specification.
- Allowed inputs: this item, the reference images named above, `data/machines.sjson`, `tools/models/kit.py`, `palette.py`, `records.py`, other machines' scripts under `tools/models/machines/` (for the kit's idioms), `doc/build.md` (Models, The workbench), `doc/presentation.md` (Machine models), `DESIGN.md` (Art direction), the source and tests named below.

### Measurements and the footprint

One cell is 500 mm on the field (`foundation_pitch_millimetres`); the model is authored in cells (kit.py: one Blender unit per cell), so metres below are cells / 2.

- Hero view (`banana2_0.png`, 2400 by 1792 shown at 2000 wide): the astronaut stands about 500 px from helmet to boots (1.8 m, so about 278 px per metre at his depth); the nearest corner of the masonry body runs from its foot (about y 1440) to the top band (about y 160), 1280 px, about 4.6 m. The firebox opening is about 270 px high (about 1.0 m) and its hearth shelf about 1.15 m over the ground; the console about 2.0 m high.
- Rear quarter (`rear_quarter/banana_0.png`): astronaut about 485 px; the corner from its foot (about y 1460) to the top band (about y 140) 1320 px; the astronaut stands a little behind the corner, so the body is 4.4 to 4.9 m.
- Turnaround (orthographic, one ground line): base width over the corner feet 375 px, body height to the top of the band 462 px (width over height 0.81), top width of the body 305 px, chimney collar about 240 px wide, chimney top 587 px over the ground, the stack pipe 617 px. Console on the left elevation 185 px wide and 247 px high.
- Plan (`plan/banana_0.png`): the chimney centred on the square body, its collar about 0.69 of the body's top width; the hearth shelf sticks out of the front, the console out of the left face, the stack pipe out of the back near the left corner, a small box out of the right face; each about 0.15 to 0.2 of the body's width.
- Scaled to a 4.5 m body: base 3.75 m square over the feet, 3.0 m at the top band, chimney collar 2.4 m across, chimney top at 6.0 m, stack pipe to 6.3 m. That is the "three player heights and two wide" of `DESIGN.md`, Art direction.

The chosen footprint: **width 10, depth 10, height 12** (5 by 5 by 6 m, within `MAXIMUM_FOOTPRINT_SIZE` 12 on every side). The body stands on an 8 by 8 cell square (4 m over the feet) centred in it; the one cell ring round it holds the hearth shelf (front), the console and the corner pipe (left), the stack pipe's foot zone (back) and the side panel (right). The chimney ends at the footprint's top (12 cells, 6 m); only the stack pipe rises above it, to 12.6 cells (the record allows a model to rise above its height; the smoke and markers follow the model's top).

### Frames, sides and colours

- Blender frame of kit.py: x the front (+X is the firebox mouth), z up, y is the game's -z. Seen from the front, the left face is Blender **-Y** (game +z) and the right face Blender **+Y** (game -z). The footprint box is x and y from -5 to 5, z from 0 to 12 (`records.footprint_box`).
- The sheet's layout, approved by the user: mouth on the front (+X), console on the left face (-Y), pipes at the back (-X) and down the left back corner, a small panel on the right face (+Y).
- `tools/models/palette.py` gains six entries (comment: "0212, the stone furnace: the astro-industrial punk palette's rough and clean worlds"), existing entries unchanged:
  - `fieldstone` (124, 98, 84): the warm grey brown masonry.
  - `fieldstone_dark` (78, 64, 58): the grimy base course, the hearth slab, the chimney's flue, the grime plates.
  - `iron_grimy` (66, 60, 58): straps, feet, the top band, the chimney, the pipes, the mouth frame, the lever base, the console's kick plate.
  - `rust` (128, 74, 52): the chimney collar, the pipe collars, the buttons, the lever handle.
  - `alloy_smudged` (192, 188, 180): the console and the side panel.
  - `signal_green` (96, 224, 120), emissive: the indicator studs.
  - Plus the existing `heat_glow` (the coals and the back of the firebox) and `electric_glow` (the screens and the light bar). Eight materials, exactly `MODEL_MATERIAL_LIMIT`; no other material may appear (not `soot`: `kit.opening` puts the cutter's material on no face, `join` drops it).
- Every emissive material lights only while the furnace works and pulses with the record's glow motion (`emissive_brightness`); idle they are shaded like the rest. The screens pulsing with the fire is accepted for this item.

### Kit additions (`tools/models/kit.py`)

Each is a module level function with a docstring in the file's manner; all three go into the kit list of `doc/build.md` (Models) and the primitives list of `doc/presentation.md` (Machine models).

- `square_frustum(z0, z1, half_bottom, half_top, material_name)`: a capped four sided frustum, axis aligned, centred on x = y = 0, half side `half_bottom` at z0 and `half_top` at z1; `cone((0, 0), z0, z1, half_bottom * sqrt(2), half_top * sqrt(2), 4, material_name, rotation=math.pi / 4)`. 12 triangles. The tapered masonry and the top band.
- `quad_prism(lower, upper, material_name)`: a hexahedron from four lower and four upper corners, each list counter-clockwise seen from +Z: one bmesh with 8 vertices and 6 quad faces, `bmesh.ops.recalc_face_normals`, `mesh_object("quad_prism", mesh, material_name, 0.0)`. 12 triangles. Everything that follows the taper (straps, mouth frame, wall plates).
- `stud(face, centre, radius, height, material_name)`: a four sided pyramid standing on a face (`"+X"`, `"-X"`, `"+Y"`, `"-Y"` or `"+Z"`), its square base of circumradius `radius` at `centre` and its tip `height` out along the face's normal; through `frustum(...)` with 4 sides and rotation pi / 4, on the face's axis; on a positive face start = the surface coordinate, end = surface + height, radius_bottom = radius, radius_top = 0; on a negative face start = surface - height, end = surface, radius_bottom = 0, radius_top = radius (`AXIS_ROTATIONS` maps local +Z onto the positive axis, so the narrow end must be the low one there). 6 triangles. Rivets, LEDs, buttons, coals.

### The script `tools/models/machines/stone_furnace.py`

Module docstring: "The stone furnace (work item 0212): 10 by 10 by 12 cells, from the reference sheet of 0211. A tapering square body of fieldstone on iron clad corner feet, iron corner straps and a top band, a riveted collar under a round iron chimney, the firebox mouth in the front with its hearth shelf and glowing coals, a pale alloy console bolted to the left face, pipes down the back and the left back corner, a small panel on the right face, grime. The body glows (motion glow); no moving part. Blender frame of kit.py: x the front, y = -game z, z up." It keeps the registration in `tools/models/machines/__init__.py` unchanged (the module name is the same).

Module constants and helpers (local to the script):

- `WALL_BOTTOM_Z = 1.0`, `WALL_TOP_Z = 9.0`, `WALL_BOTTOM_HALF = 3.75`, `WALL_TOP_HALF = 3.05`.
- `wall_half(z)`: the masonry's half side at height z, linear between the two (3.75 at 1.0, 3.05 at 9.0; 0.0875 less per cell up). Below z 1.0 it returns 3.75.
- `wall_plate(face, along_low, along_high, z0, z1, inner, outer, material_name)`: a `kit.quad_prism` lying on the tapered face `face` (one of `+X`, `-X`, `+Y`, `-Y`), spanning `along_low..along_high` on the face's horizontal axis (y for ±X, x for ±Y) and z0..z1, its inner surface `inner` and its outer surface `outer` cells out from the wall at each height (negative inner sinks it into the wall). Used for straps, the mouth frame, the console's flange, grime and the side panel's back.

`build(machine)`: `kit.expect_footprint(machine, 10, 10, 12)`, then the volumes below in this order, `kit.join(volumes, "body")`. Triangle counts per part are targets; the body's total must stay at or under `MODEL_BODY_TRIANGLES_MAXIMUM` (800).

| # | Part | Geometry (cells; metres = cells / 2) | Material | Helper | Triangles |
|---|---|---|---|---|---|
| 1 | Base course | `square_frustum(0.0, 1.0, 3.82, 3.75)` | fieldstone_dark | square_frustum | 12 |
| 2 | Masonry body (the primary volume) | `square_frustum(1.0, 9.0, 3.75, 3.05)`; the firebox cut into it (row 9) | fieldstone | square_frustum, opening | 12 + about 20 for the cut |
| 3 | Corner feet, four | boxes at each corner (signs sx, sy of ±1): x from sx·2.4 to sx·4.0, y from sy·2.4 to sy·4.0, z 0 to 1.7 | iron_grimy | box | 48 |
| 4 | Corner straps, four | `quad_prism` per corner from z 1.7 to 8.3: at each end an axis aligned square whose outer corner is at (sx·(wall_half(z) + 0.10), sy·(wall_half(z) + 0.10)) and inner corner at (sx·(wall_half(z) - 0.80), sy·(wall_half(z) - 0.80)), so each face shows a strap 0.9 cells (0.45 m) wide and 0.1 proud | iron_grimy | quad_prism | 48 |
| 5 | Top band | `square_frustum(8.3, 9.1, 3.24, 3.14)` (proud of the wall, its top cap is the body's deck) | iron_grimy | square_frustum | 12 |
| 6 | Chimney collar | `cylinder((0, 0), 9.1, 9.7, 2.4, 10, ...)` | rust | cylinder | 36 |
| 7 | Chimney | `cone((0, 0), 9.7, 12.0, 2.2, 1.85, 10, ...)` | iron_grimy | cone | 36 |
| 8 | Flue | `cylinder((0, 0), 11.98, 12.02, 1.35, 10, ...)` (the dark mouth on top, read by the top camera) | fieldstone_dark | cylinder | 36 |
| 9 | Firebox mouth | cut: `kit.opening(body, (1.9, -1.3, 2.6), (4.2, 1.3, 5.0))`; back glow: box (1.88, -1.28, 2.6) to (2.0, 1.28, 4.95), heat_glow; three coals: `stud("+Z", c, 0.32, 0.26, "heat_glow")` at c = (2.35, -0.6, 2.6), (2.85, 0.3, 2.6), (2.3, 0.8, 2.6); frame: `wall_plate("+X", -1.9, 1.9, 5.0, 5.6, -0.05, 0.15, "iron_grimy")` (lintel) and `wall_plate("+X", ±1.3..±1.9, 2.6, 5.0, -0.05, 0.15, "iron_grimy")` (two jambs); hearth pier: box (3.3, -1.7, 0.0) to (4.6, 1.7, 2.1), fieldstone; hearth slab: box (3.2, -1.95, 2.1) to (4.8, 1.95, 2.6), fieldstone_dark | as listed | opening, box, stud, wall_plate | about 110 |
| 10 | Console (left face) | body: box (-1.4, -4.7, 0.0) to (1.8, -3.45, 3.6), alloy_smudged; sloped top: `wedge((-1.4, -4.7, 3.6), (1.8, -3.45, 4.3), "alloy_smudged", rise="+Y")`; on the `-Y` face at y -4.7: main screen `strip("-Y", (-0.75, -4.7, 3.0), 1.0, 0.6, "electric_glow")`, small screen `strip("-Y", (0.95, -4.7, 3.05), 0.6, 0.4, "electric_glow")`, light bar `strip("-Y", (0.2, -4.7, 3.45), 2.8, 0.12, "electric_glow")`, three LEDs `stud("-Y", (x, -4.7, 2.55), 0.08, 0.06, "signal_green")` at x -1.05, -0.7, -0.3, two buttons `stud("-Y", (x, -4.7, 2.05), 0.11, 0.07, "rust")` at x -0.95, -0.5, lever base `face_box("-Y", (1.0, -4.7, 2.2), 0.35, 0.6, 0.0, 0.1, "iron_grimy")`, lever handle `cylinder((1.0, -4.77), 2.2, 2.95, 0.06, 8, "rust")`, kick plate `face_box("-Y", (0.2, -4.7, 0.4), 2.4, 0.8, -0.02, 0.01, "iron_grimy")` | as listed | box, wedge, strip, stud, face_box, cylinder | about 138 |
| 11 | Console feed pipe | `pipe([(0.2, -3.0, 7.6), (0.2, -3.95, 7.6), (0.2, -3.95, 4.0)], 0.28, "iron_grimy", sides=8)` (out of the left wall under the top band, an elbow, down into the console's sloped top); its wall flange `wall_plate("-Y", -0.35, 0.75, 7.15, 8.05, -0.05, 0.08, "iron_grimy")` | iron_grimy | pipe, wall_plate | 88 |
| 12 | Left back corner pipe | `pipe([(-2.05, -3.0, 7.2), (-2.05, -4.5, 7.2), (-2.05, -4.5, 0.0)], 0.3, "iron_grimy", sides=8)` (out of the left face's back end, an elbow, down to the ground) | iron_grimy | pipe | 76 |
| 13 | Stack pipe (back) | `cylinder((-3.55, -1.8), 4.0, 12.6, 0.32, 8, "iron_grimy")` rising from the back wall past the chimney; collar `cylinder((-3.55, -1.8), 9.6, 9.9, 0.4, 8, "rust")` | iron_grimy, rust | cylinder | 56 |
| 14 | Right panel | `face_box("+Y", (0.4, wall_half(3.2), 3.2), 1.0, 1.3, -0.1, 0.25, "alloy_smudged")`; strip `strip("+Y", (0.4, wall_half(3.2) + 0.25, 3.7), 0.7, 0.1, "electric_glow")`; two LEDs `stud("+Y", (x, wall_half(3.2) + 0.25, 3.3), 0.07, 0.05, "signal_green")` at x 0.2 and 0.55 | as listed | face_box, strip, stud | 36 |
| 15 | Rivets | six `stud` on strap faces and the top band, radius 0.12, height 0.08, iron_grimy, in uneven counts and heights: front right strap on `+X` at z 3.1 and 6.4; front left strap on `+X` at z 5.2; back left strap on `-Y` at z 2.6 and 7.0; back right strap on `+Y` at z 4.4. Each sits on the strap's outer surface (wall_half(z) + 0.10 from the centre on the face's axis) at the strap's middle along the face (wall_half(z) - 0.35 from the centre, signed to the corner) | iron_grimy | stud | 36 |
| 16 | Grime | two plates: under the lintel on the front, `wall_plate("+X", -1.6, 0.9, 5.6, 7.2, -0.01, 0.01, "fieldstone_dark")`; above the console on the left, `wall_plate("-Y", -1.0, 1.4, 4.4, 6.8, -0.01, 0.01, "fieldstone_dark")` | fieldstone_dark | wall_plate | 24 |

The targets add to about 790. If `./build.sh model-check stone_furnace` reports the body over 800, cut in this order and say so in the report: the grime plates (16), then two rivets (15), then the flue's sides from 10 to 8 (8). Never cut the console, the mouth or the chimney. Nothing may leave the footprint's x and y (0.02 of slack): the console's front is at -4.7, the lever at -4.83, the left pipe's outside at -4.8, the hearth slab at 4.8.

Determinism: no seeded draws are needed (every position above is fixed and the counts are uneven by hand); if the implementer adds any jitter it goes through `kit.model_random(machine, "<salt>")`.

The scale cue of `DESIGN.md` is the console (its lever at about 1.1 to 1.5 m) and the firebox mouth (1.2 m high).

### The record (`data/machines.sjson`, `stone_furnace`)

- `footprint = {width = 10, depth = 10, height = 12}`.
- `model = "stone_furnace"` and `motion = {kind = "glow", period_seconds = 2}` stay; no part (no moving part, so no `pivot`).
- `open_cells` (new), four boxes, the ring cells the model leaves empty (cells of the unrotated footprint, x the width with the front at 9, y up, z the depth with the right face at 0 and the console's left face at 9):
  - `{from = {x = 0, y = 0, z = 0}, to = {x = 0, y = 11, z = 9}}` the back row,
  - `{from = {x = 1, y = 0, z = 0}, to = {x = 9, y = 11, z = 0}}` the right row,
  - `{from = {x = 9, y = 0, z = 1}, to = {x = 9, y = 11, z = 2}}` and `{from = {x = 9, y = 0, z = 7}, to = {x = 9, y = 11, z = 8}}` the front row beside the hearth.
  The left row (z 9) stays solid: the console and the corner pipe stand in it. The model check's `open_cells` check proves the model leaves them empty; the player then walks up to the wall on three sides.
- Ports: the stone furnace has no `fluid_ports` and keeps none; an inserter feeds and empties it through any footprint cell it faces (open cells are still the machine's), so no port cell changes. No other key changes (slots, `speed`, `fuel_power_kilowatts`).
- `steel_furnace` is untouched (still 2 by 2 by 2, its own later item).

### What else reads the footprint

- Content data: `data/dev_kits.sjson` and the quests (`chapter_01` to `03`) count items and placements only, no change. `data/recipes.sjson` no change. `data/blueprints/benchmark/*` place steel furnaces only, no change.
- `data/blueprints/tier1_factory.sjson` (block world, 1 m cells, so the furnace is 10 by 10 by 12 m there) is re-laid; the belt, the drills and the overflow chest stay; the header comment's ground size becomes "about 20 by 27 blocks" (x -2 to 17, z -13 to 13):
  - furnace one `place stone_furnace 4 0 2 0` stays (x 4 to 13, z 2 to 11); its input inserter `4 0 1 1` stays; coal: `place burner_inserter 14 0 2 2`, `place wooden_chest 15 0 2 0`; output: `place burner_inserter 5 0 12 1`, `place wooden_chest 5 0 13 0`.
  - furnace two `place stone_furnace 6 0 -11 0` (x 6 to 15, z -11 to -2); input inserter `6 0 -1 3` stays; coal: `place burner_inserter 16 0 -2 2`, `place wooden_chest 17 0 -2 0`; output: `place burner_inserter 7 0 -12 3`, `place wooden_chest 7 0 -13 0`.
  - coal lines: `insert coal 50 15 0 2`, `insert coal 50 17 0 -2`, `insert coal 5 5 0 12`, `insert coal 5 7 0 -12`; the drills', the input inserters' and the overflow inserter's lines stay.
  - `doc/commands.md` (the tier1 paragraph) gets the new ground size.
- Field play: a 5 by 5 m furnace on bare ground meets `bare_ground_is_flat` over its four corners and centre (250 mm shipped), so it stands on slopes up to about 2.8 degrees, and founded it needs 100 foundation cells. No code or data changes for that in this item (see the questions).
- Old saves (the item's "an old save loads"): a saved entity keeps `Entity_Common.size`, but `occupy_entity_cells` and `vacate_entity_cells` (`entity.odin`) take the cells from the record (`machine_held_cells`, `machine_open_cells`), so an old furnace would claim 10 by 10 by 12 cells over its neighbours after a load. The fix, no save layout change:
  - `entity_keeps_saved_size :: proc(common: Entity_Common, machine: Machine) -> bool` (`entity.odin`, pure): `machine.kind != .Pod && common.size != rotated_footprint_size(machine.footprint, common.rotation)`. (A pod is upgraded by `upgrade_resized_pods` instead.)
  - `entity_held_cells :: proc(common: Entity_Common, machine: Machine) -> []World_Coordinate` (`entity.odin`, temp allocator): `machine_held_cells(common.origin, machine, common.rotation)`, or when `entity_keeps_saved_size`, `footprint_cells(common.origin, saved, common.rotation)` with `saved` the unrotated size (`common.size` with x and z swapped on an odd rotation). `occupy_entity_cells` and `vacate_entity_cells` call it in place of `machine_held_cells`, and skip `machine_open_cells` for such an entity.
  - After a load, one log line through the game's logger when any entity keeps its saved size, `"N machines keep the footprint they were saved with; pick them up and place them again for the new size"` (written from `rebuild_loaded_world` or right after it in `save_state.odin`, counted over every pool's alive entries by `entity_keeps_saved_size`).
  - The renderer is not changed: such a furnace draws the new model centred on its old box, overlapping its neighbours, until it is picked up (it returns its item, or its salvage when worn) and placed again at the new size. Named in the log entry.

### Tests

Run `./build.sh test`; the stone furnace grows from 2 by 2 by 2 to 10 by 10 by 12, so tests that put something within 10 cells of it in +x or +z, or that rely on its size, change. Two rules:

- **Generic machine** (the test uses the furnace as "a 2 by 2 by 2 machine with a panel" for frames, aiming, placement, touch or viewports): swap `"stone_furnace"` for `"steel_furnace"` (same kind, same 2 by 2 by 2, same slots), and its item where the test counts the item. These: `entity_frames_test.odin` (`test_a_machine_on_a_frame_occupies_its_footprint_and_a_second_is_refused` and the tests at the lines naming the furnace near 602 and 795), `entity_test.odin` (the furnace at `{4, 1, 4}` with the belt at `{6, 1, 4}`, and the open aimed test), `entity_placement_test.odin` (the three tests naming it), `touch_overlay_test.odin` (both), `simulation_field_test.odin` (the furnace with the power switch at `{3, 0, 0}`), `viewport_test.odin`, `machine_wear_test.odin`'s founded and unfounded test with the chest (the pad of `{0, 0, 0}` to `{1, 0, 1}` and the furnace at `{0, 2, 0}`) and its state hash test (`add_entity` on a frame).
- **Stone furnace specific** (smelting times, slots, the salvage of 4 stone, the breakdown toast, the bare ground slope): keep the stone furnace and move what stands in its new box by +8 on the axis it stood on, or grow the pad:
  - `inserter_test.odin`: `test_inserter_takes_only_from_the_furnace_output` (taking inserter `{12, 1, 0}`, chest `{13, 1, 0}`, the second furnace `{13, 1, 0}`); `lay_smelting_line` (inserter `{12, 1, 0}`, belt row from `{13, 1, 0}`, inserter `{16, 1, 0}`, chest `{17, 1, 0}`).
  - `save_test.odin`: `lay_save_test_smelting` the same +8 shift (inserter `{12, 1, 0}`, belt row `{13, 1, 0}`, inserter `{16, 1, 0}`, chest `{17, 1, 0}`, all plus the offset); in `build_save_test_site` the splitter line moves from offset `{12, 0, 20}` to `{12, 0, 26}` (the furnace now spans z 14 to 23).
  - `production_statistics_test.odin`: second furnace `{10, 1, 20}`, assembler `{22, 1, 10}`.
  - `render_particles_test.odin` (`test_emitters_for_frame_from_the_world`): alloy furnace `{12, 1, 0}`, boiler `{18, 1, 0}`.
  - `command_test.odin` (`test_tier1_factory_blueprint_places_and_smelts`): no change beyond the blueprint above; the counts (2 drills, 2 furnaces, 9 belts, 7 inserters, 5 chests) stay.
  - `machine_wear_test.odin`: `test_a_furnace_stands_on_flat_bare_ground_and_is_refused_on_a_slope` takes the slope cases `{2, .None}` and `{10, .Too_Steep}` (5 m across: 175 mm and 882 mm against 250) with its comment updated; the pads under founded stone furnaces grow to `{0, 0, 0}` to `{9, 0, 9}`; `test_a_new_frame_is_refused_inside_another_frames_entities` places the apart furnace at `6 * POSITION_UNITS_PER_METRE` (half a metre still overlaps).
  - `machine_test.odin`: the shipped furnace's footprint `[3]i32{10, 12, 10}` (x, y, z) and its four open cell boxes.
  - `model_triangle_mesh_test.odin`: `emissive_layer_centroid` becomes `emissive_colour_centroid(mesh, colour) -> (centroid: [3]f32, count: int)`, the centroid of the vertices of that colour only (the furnace now also glows cyan and green); the furnace's case expects `count > 0`, every `heat_glow` vertex at x > 0 and the centroid x > footprint width / 8 (1.25), the glow facing the front (the export axes).
  - `tools/models/records_test.py`: `Footprint(10, 10, 12)`, `footprint_box` `((-5.0, -5.0, 0.0), (5.0, 5.0, 12.0))`, ports `()`, and `open_cell_box(furnace, 0)` `((-5.0, -5.0, 0.0), (-4.0, 5.0, 12.0))`.
- Unchanged by the reading above, but rerun: `drill_test.odin` (both), `deep_mining_test.odin`, `furnace_test.odin`, `quick_transfer_test.odin`, `item_transfer_test.odin`, `byproduct_test.odin`, `schematic_test.odin`, `field_trees_test.odin` (flatness overridden), the quest tests, `ui_audit_test.odin`, `test_the_shipped_models_pass_the_checks`.
- New: `test_a_machine_saved_at_an_older_size_keeps_its_cells` (`entity_test.odin`): a stone furnace added at `{4, 1, 4}` on the block frame, its cells vacated, `common.size` set to `{2, 2, 2}`, occupied again: `entity_keeps_saved_size` is true, the eight cells of the 2 by 2 by 2 box hold it, `{6, 1, 4}` and `{4, 1, 6}` are free, and vacating frees all eight. And `test_entity_keeps_saved_size_spares_the_pod` (pure): a pod entry with a size unlike its record is false, a furnace with its record's size is false.
- A test, if any, whose failure is not explained by the rules above is named in the report with its line, not rewritten silently.

### Commands (implementer, in the worktree)

1. The deletions above, the palette and kit additions, the script, the record, the tests, the blueprint.
2. `tools/make_models.sh stone_furnace` (Blender through `tools/blender`, then `./build.sh model-check`), passing: load, budget (body at most 800, 8 materials), footprint, open_cells. Report the body's triangle count.
3. `MODEL_PREVIEW_DIRECTORY=tmp/model_preview tools/model_preview.sh stone_furnace` and read at least `stone_furnace_front_rest.png`, `_back_rest.png`, `_top_rest.png`, `_close_rest.png` and `_close_0.25.png`. What they must show: front (three quarter from the front right): the mouth with its frame, hearth and coals, the right panel, the capsule (1.8 m) on the right, the body more than twice its height, the chimney on top; back (from the back left): the console with its screens, lever and the feed pipe, the corner pipe, the stack pipe; top: the square body, the round collar and the dark flue centred, the hearth slab, console and panel sticking out of three sides; close: the mouth filling the view, the coals and the back glow, at 0.25 lit. No camera shows a hole, a floating part or the cyan of the console on the front.
4. `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/models/records_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
5. Set the status to `implemented`, never commit, never run the game as a session or the benchmark, never install the play build.

### Rounds with the user

- The implementer's report ends with the five preview paths above and the triangle count. The main agent sends the previews (and the hero image beside them); the user says what to change; the same implementer is resumed with the user's words and iterates the script (and only the script, the palette and the kit, unless the user's change needs the record) until the user accepts. Each round reruns steps 2 to 4 and reports the same five previews.
- What a round teaches about the kit (a helper, a material, a rule) goes into `kit.py` in that round and into `DESIGN.md`, Art direction, and the log at the end.
- When the user accepts, the main agent copies the reference images the user kept into `doc/art/stone_furnace/` (a few hundred kilobytes each, downscaled) and adds a "Stone furnace" page to `doc/art/booklet.md` naming them and the accepted previews; the implementer does not.
- The couch check of Verify (standing next to it) is the user's, after landing.

### Docs (same commit)

- `doc/presentation.md`, Machine models: the stone furnace sentence (0212: 10 by 10 by 12 cells, the parts in one line, the eight materials, the open cells on three sides) and the three new primitives in the kit list.
- `doc/build.md`, Models: `square_frustum`, `quad_prism`, `stud` in the kit's layout list.
- `doc/content.md`: Foundations, the last bullet ("the footprints of `data/machines.sjson` are unchanged until then") gains "except the stone furnace, the first machine at its real size in frame cells (0212, 10 by 10 by 12 cells, 5 by 5 by 6 m)"; Machines on bare ground: a footprint's corners are read, so a 5 m furnace stands on slopes up to about 2.8 degrees at the shipped 250 mm; Models: the old size rule (a machine saved at an older size keeps its cells until picked up, `entity_keeps_saved_size`).
- `doc/commands.md`: the tier1 blueprint's ground size.
- `data/machines.sjson` header: after the `open_cells` paragraph, one line that open cells are used by the stone furnace too (its ring of empty cells).
- `doc/log/2026-10-03.md`, a new section "The stone furnace from the ground up (0212)" with tags `models, art, furnace, footprint, m15`: the measurements and the 10 by 10 by 12 choice; the eight materials and the six palette entries; the triangle budget split and what was cut; the open cells; the saved size rule and its log line, and that an old furnace draws the big model over its old box until placed again; the slope consequence (about 2.8 degrees on bare ground, 100 foundations to found it); the block world's 10 m furnace in the tests and the blueprint; the tests swapped to the steel furnace and why; what the rounds changed.
- `DESIGN.md`, Art direction: only what the rounds teach (one sentence per rule), nothing at the first hand back.

### Hand-back check lines that apply

- "A changed save layout loads an old save (a remap and one log line), and a behaviour change that stops old saves is named in the log": the layout does not change; the saved size rule and its log line keep an old furnace loading on its old cells, and the log names it.
- "A UI audit case a change makes obsolete is replaced": none expected; `ui_audit_test.odin` only reads the furnace's item. Confirm in the report.
- "Tests never touch the machine's state directory": the preview writes to `tmp/model_preview` only.
- "A list that grows without bound is capped where it draws": not applicable. The memory, file write, parse and shared budget lines: not applicable (no new parse, no new file writer, no new budget participant). Say so in one line each.

### Questions for the main agent

1. The triangle budget. 800 per body (`DESIGN.md`, `MODEL_BODY_TRIANGLES_MAXIMUM`) holds the sheet only thinly at this size: the plan above fits about 790 and leaves out the console's cables to the front corner (about 76 each), most rivets, the second light bar and a lip on the chimney. Should the user be asked for a higher cap for machines past some size (for instance 1600 for a footprint over 8 cells a side), which would change `model_check.odin`, `DESIGN.md` and the shipped models test? The specification assumes 800.
2. Field play at the new size. On bare ground the flatness test over 5 m allows about 2.8 degrees (250 mm), and founding it takes 100 foundation cells (the starting kit has 16). The first quest asks to place one. Options: leave it and let the couch tell (the specification's assumption), raise `bare_ground_flatness_millimetres`, give the furnace its own tolerance, or more starting foundations. A decision the user may want to make.
3. Placement anchoring. A machine placed on bare ground stands with its cell (0, 0, 0) at the hit (`free_frame_at`), so a 5 m furnace extends 5 m to one side of the reticle rather than round it. Centring large footprints on the hit is a code change outside this item; worth its own item?
4. The hero view (mouth and console together, from the front left) is none of the workbench's four cameras (front right, back left, top, close). Accept the four for the rounds, or add a front left camera to `loop_model_preview.odin` first (a small change to 0207's workbench)?
5. The generic tests moved to the steel furnace keep testing 2 by 2 by 2 machines; when the steel furnace is redone at its real size they move again. Acceptable, or should those tests get a test only machine record instead?

### Decisions at the approval (main agent, 2026-10-03)

1. The triangle budget stays at 800 for the first hand back, with the cut order above. If a round's ask does not fit, the main agent raises `MODEL_BODY_TRIANGLES_MAXIMUM` to 1600 for every body (one constant, the "at most 800 triangles per body" sentence of `DESIGN.md`, Art direction, and `doc/presentation.md`, Machine models) and tells the user; the implementer never raises it on its own.
2. Field play at 5 by 5 m is left as the specification assumes; the decision (the flatness, a tolerance per record, the starting foundations) is in `SUGGESTIONS.md`, Decisions needed, and the couch tells first.
3. Placement anchoring is its own item, `0213-centre-a-large-footprint-on-the-aimed-cell.md`.
4. The hero view gets its camera in this item (the section below), so every round shows the mouth and the console together.
5. The generic tests move to the steel furnace as written; they get a test only machine record when the steel furnace is redone, not before.

### The front left camera (approval addition, 2026-10-03)

A fifth workbench camera, so the sheet's hero angle (the mouth and the console together, from the front left) is one of the previews:

- `loop_model_preview.odin`: `Model_Preview_View` gains `Front_Left` between `Front` and `Back`, `model_preview_view_names[.Front_Left] = "front_left"`, and `model_preview_camera` gets `case .Front_Left: return {centre + linalg.normalize([3]f32{1, MODEL_PREVIEW_THREE_QUARTER_RISE, 1}) * distance, centre, {0, 1, 0}}` (from the front and the +z side, the left seen from the front, the Blender -Y side; the capsule stands on the -z side, so from here it is behind the machine, which is accepted). The comment above `model_preview_camera` says the three quarter cameras are three.
- `loop_model_preview_test.odin`, `test_the_preview_cameras_frame_the_scene`: `front_left := model_preview_camera(.Front_Left, bounds)` expecting `position.x > bounds.model_maximum.x && position.z > centre.z` and a distance from the centre of at least `least`.
- Five cameras at four phases give 20 files per machine. Docs in the same commit: `doc/build.md`, Models (the `--model-preview` bullet: "Five cameras (`front` from the front right, `front_left` from the front left, `back` ... give 20 files per machine") and the flags table ("five cameras"); `doc/code_map.md`, the `loop_model_preview.odin` line ("five cameras"); the header comment of `tools/model_preview.sh`.
- The previews to report become six: `stone_furnace_front_left_rest.png` must show the hearth and the coals on the right, the console with its screens and lever on the left, the feed pipe above it and the chimney on top, read against the hero image (`work/art/2026-10-03-round-4/furnace/banana2_0.png`).
