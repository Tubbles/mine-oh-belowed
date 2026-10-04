# 0229: Machine lamps stay inside their machine's box

Status: implementing (2026-10-04, the specification approved the same day with the decisions below; the implementer works in `.claude/worktrees/0229` on `item/0229` from `main`, from the user on the phone with the round three preview: "it looks like the point lights lighten up the outside exterior of the pod as well, the light doesnt seem to be blocked by solids?"; 0224's decision 1 accepted that spill and the user does not)

## Goal

The pod's cabin lamps light the cabin and nothing outside it: the hull seen from the crater, the ground round the pod and the machines beside it take no light from a lamp inside, by day or by night. Solids do not cast shadows in this renderer (no shadow maps; a point light is a soft falloff round a point in `field.fs` and `model.fs`), so the lamp is clipped to its machine instead: a lamp's light stops at the faces of its machine's footprint box.

## Controls

No binding changes.

## Change

- Every `Point_Light` may carry a clip box: the machine's footprint box in the world (the body matrix of `machine_point_light`, 0224, times the footprint's extent in cells: x and z centred, y from the bottom), handed to both shaders as a matrix per light that maps a world position into the box's unit coordinates, so the shader adds a light's term only where the mapped position lies inside the unit box (a cheap test, no shadows). The arm's lamp carries no box (the identity or a flag that skips the test), since it lights the ground it works over. A record's lamp may opt out with a key (`clip = false`) for a lamp meant to shine out of a machine, such as a street lamp; the pod's lamps keep the default, clipped.
- Light through the portholes and the open door is lost with the clip (the box stops at the hull); the portholes' and the door's emissive patches are what shows the pod lit from outside, and 0222's closed doors make the loss small. The design stage names what the arrival's open doors look like from outside.
- The uniforms: `point_light_boxes[8u]` as `mat4` in both shaders (GLSL 330 and 300 es take mat4 arrays; every integer literal with the `u` suffix), set with the others in `set_field_point_lights` and `set_model_point_lights` from `point_light_uniform_values`.
- Docs: `doc/presentation.md` (Chunk meshes, the field shader bullet; Machine models, the point lights bullet), `doc/content.md` (the `lights` key: `clip`), the log.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the box matrix maps the footprint's corners to the unit box's corners on the 500 and 1000 mm frames and under every rotation; a point just outside a face maps outside; the arm's lamp has no box; a lamp with `clip = false` has none; the packing puts the matrices in the slots of their lights with the unused slots' matrices at zero; the shaders pass `shader_source_test.odin`.
- A headless screenshot pass (`tmp/pod_shots.sh`) on the round three model: the cabin lit as before, the hull from outside and the ground round the pod unlit by the lamps (the outside shots at dusk if the pass can set the time, else by the terrain's colour under the pod).

## Specification (design, 2026-10-04)

Written from the item, `doc/work/done/0224-point-lights-on-machine-models.md`, `doc/work/done/0225-the-pods-cabin-is-dark-until-its-lamps-light-it.md`, `doc/work/0221-the-pod-remade-from-the-booklet.md`, `doc/presentation.md`, `doc/content.md`, the code named below, raylib's `rcore.c` and `rlgl.h` (`tmp/raylib-src`) and the round three model in the private data copy (`tmp/pod_data/models/pod.obj`, `tmp/pod_data/machines.sjson`). Presentation only: no simulation state, save layout, network message or hash input changes. No binding changes.

### What the round three pod has (measured, so the box's shape is grounded)

From `tmp/pod_data/models/pod.obj` (vertices binned by height, cells of the model's frame): a floor disc at y 0 of radius 5.0 (the first vertex ring, a 24-gon); the hull at radius 5.21 to 5.45 on rows 0 to 4, narrowing as a cone to radius 3.8 at row 5, 1.5 at row 8 and 1.1 at the top, y 9.9; inward facing triangles (the lining) up to y 9.x at radius 1.4 and less, so the cabin's ceiling is the inside of the cone and shows from the chair above the footprint's height of 8 (`pod_inside_lamps.png` of round three). The record's footprint in the copy is 12 by 12 by 8; the lamps are the strip at (-1.85, 5.315, 0) radius 8 and the desk light at (-2.35, 2.507, -2.674) radius 3.5.

Two consequences shape this specification (both in the Questions for the main agent):

1. The box alone cannot keep the hull's outer skin dark. The skin lies inside its own machine's box, and the lamp term gives a face turned away from the light half its value (`point_light_wrap`, 0.5). So the clip comes with a facing rule for clipped lights: a face turned away from a clipped light takes nothing from it. For a convex hull with the lamp inside, every outer face is turned away: for the strip, the cosine on the skin is at most (1.85 - 5.21) / 8 = -0.42; for the desk light (3.56 - 5.21) / 3.5 = -0.47.
2. The box's top is the model's top when the model rises above the footprint (9.9 against 8 here), else the light would stop on a horizontal line across the cabin's ceiling at y 8.

### Representation, decided

- Per light, the three rows of an affine matrix from the world's metres to the box's coordinates, -1 to 1 inside on every axis (centred, not 0 to 1). The fourth row is always (0, 0, 0, 1) and is not sent.
- One uniform per shader: `uniform vec4 point_light_boxes[24u];` (8 lights times 3 rows, light `index`'s rows at `index * 3u`, `+ 1u`, `+ 2u`), set with one `rl.SetShaderValueV(..., .VEC4, 24)`.
- A light with no box (the arm's lamp, a record lamp with `clip = false`, an unused slot) has zero rows. Zero rows map every point to the box's centre, which is inside, so the shader runs the same test for every light with no flag and no branch for the encoding.
- Clipped or not travels in the colour's alpha, which goes up already: 0 for a clipped light (the facing rule applies), 1 for the others (today's term unchanged, so the arm's lamp and every existing look stay as they are). Unused slots keep alpha 1, as today.
- Why not `mat4 point_light_boxes[8u]` as the item names: raylib's `rlSetUniformMatrices` is not bound in `shared/raylib/rlgl/rlgl.odin` (only `SetUniformMatrix`), and in raylib 6.0 it calls `glUniformMatrix4fv` with transpose true on desktop (`GRAPHICS_API_OPENGL_33`) and false on GLES (`GRAPHICS_API_OPENGL_ES2`, which the Android build's ES3 defines too, `rlgl.h` line 191), so the same array would arrive transposed on one platform and not the other. Eight `SetShaderValueMatrix` calls at `location + index` rely on consecutive locations for array elements, which GLSL 330 without explicit locations does not promise, and cost eight program binds and uploads per shader. Four vec4 rows send the constant row for nothing; centre plus half axes needs the same three vec4 and a division in the shader. The vec4 array takes the same path as the positions and colours, in both GLSL 330 and 300 es.
- Cost per frame and viewport: one more `SetShaderValueV` per shader (two in all, 384 bytes each, beside the four that run today); on the CPU one 3 by 3 inverse per working machine with lamps (one per pod). In the fragment shader three `dot`s, an `abs` and two `max` per active light.

### Files and procedures

`src/render_point_lights.odin` (imports `core:math/linalg`):
- Header comment: one sentence: a machine's lamp is clipped to its machine's box (0229, `machine_light_clip_box`), and a clipped light gives nothing to a face turned away from it, so the hull of a machine with a lamp inside stays dark outside; the arm's lamp has no box.
- `POINT_LIGHT_BOX_ROWS :: 3`, comment: the rows of a light's clip box in `point_light_boxes` (field.fs, model.fs), whose size is `MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS`.
- `MACHINE_LIGHT_CLIP_PADDING_CELLS :: 0.05`, comment: the box is this much larger than the footprint on every side, so a model's faces on the footprint's faces count as inside: above `MODEL_FOOTPRINT_TOLERANCE_CELLS` (0.02, how far a model may leave its footprint) plus the f32 error of a world position 16 km from the planet's centre (about 0.006 cells on a 500 mm frame).
- `Point_Light` gains `clip_box: Maybe(matrix[4, 4]f32)`, comment: the world's metres to the light's machine box, -1 to 1 inside (`machine_light_clip_box`); nil for a light that shines everywhere (the arm's lamp, a record lamp with `clip = false`). The struct stays comparable (`slice.contains` in the tests; checked with a probe: a struct with a `Maybe(matrix[4, 4]f32)` compares with `==`).
- `affine_inverse :: proc(transform: matrix[4, 4]f32) -> matrix[4, 4]f32`: pure. `linear := cast(matrix[3, 3]f32)transform` (the upper left 3 by 3), `inverse_linear := linalg.inverse(linear)`, `moved := -(inverse_linear * [3]f32{transform[0, 3], transform[1, 3], transform[2, 3]})`, the result's upper left `inverse_linear`, its last column `moved`, its last row (0, 0, 0, 1). Exact for any invertible affine matrix and steadier than the 4 by 4 cofactor inverse with translations of thousands of metres. Called by `machine_light_clip_box`. (The cast and `linalg.inverse` on `matrix[3, 3]f32` compile with the toolchain, checked with a probe.)
- `machine_light_clip_box :: proc(body: matrix[4, 4]f32, footprint: [3]i32, top_cells: f32) -> matrix[4, 4]f32`: pure. `height := max(f32(footprint.y), top_cells)`; `box_to_model := matrix[4, 4]f32{f32(footprint.x) / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0, 0, 0, 0, height / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0, height / 2, 0, 0, f32(footprint.z) / 2 + MACHINE_LIGHT_CLIP_PADDING_CELLS, 0, 0, 0, 0, 1}` (rows as written: the unit box -1 to 1 onto the unrotated footprint in the model's frame, x and z centred, y from -padding to height plus padding); returns `affine_inverse(body * box_to_model)`. `footprint` is the record's unrotated `Machine.footprint`, since `body` (`entity_body_matrix`: `entity_frame_matrix * model_transform(origin, common.size, rotation)`) already turns the model's frame. Called by `append_machine_lights`.
- `machine_point_light :: proc(light: Machine_Light, body: matrix[4, 4]f32, pitch_millimetres: int, clip_box: matrix[4, 4]f32) -> Point_Light`: as today, plus `clip_box = clip_box` when `light.clip`, nil otherwise. The caller computes the box once per machine. Comment extended.
- `point_light_uniform_values :: proc(lights: [MAXIMUM_POINT_LIGHTS]Point_Light) -> (positions, colors: [MAXIMUM_POINT_LIGHTS][4]f32, boxes: [MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS][4]f32)`: positions as today; colours rgb as today with alpha 0 when `light.clip_box` holds a matrix and 1 otherwise; for a clipped light `boxes[index * POINT_LIGHT_BOX_ROWS + row] = {box[row, 0], box[row, 1], box[row, 2], box[row, 3]}` for rows 0 to 2; every other entry zero. Comment: the packing and the meaning of the alpha.

`src/render_field.odin`:
- `Field_Renderer.point_light_locations: [3]i32`, comment adds the boxes. `use_field_shader` adds `rl.GetShaderLocation(shader, "point_light_boxes")` as the third.
- `set_field_point_lights`: `positions, colors, boxes := point_light_uniform_values(lights)` and a third `rl.SetShaderValueV(shader, renderer.point_light_locations[2], &boxes, .VEC4, MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS)`. Comment: the boxes too.

`src/render_models.odin`:
- `Model_Renderer.point_light_locations: [3]i32`; `use_model_shader` adds `"point_light_boxes"` as the third.
- `set_model_point_lights`: the third upload as in `set_field_point_lights`.

`src/render_entities.odin`:
- `append_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, common: Entity_Common, machine: Machine, working: bool, top_cells: f32)`: after `body` and `pitch`, `clip_box := machine_light_clip_box(body, machine.footprint, top_cells)`, then `machine_point_light(machine.lights[index], body, pitch, clip_box)`. Comment: clipped to the machine's box up to its model's top (0229).
- `gather_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, machines: Machine_Registry, models: Model_Renderer)`: every `append_machine_lights` call passes `machine_model_top(models, <entry>.common)` (the model's top in cells, the footprint's height for a machine drawn as a box or with an empty renderer). Comment: the models give each box its top.

`src/loop_field_session.odin`:
- `set_field_scene_point_lights`: `gather_machine_lights(&lights, &scene.state.world.entities, scene.content.machines, scene.models)`.

`src/render_arm.odin`: no code change; `arm_point_light`'s comment adds "with no clip box: it lights the ground it works over (0229)".

`src/machine.odin`:
- `Machine_Light_Definition` gains `clip: Maybe(bool)` (absent told from false, as `interior_light_share: Maybe(f32)`); its comment: `clip` false lets the lamp shine outside the machine's box (0229), absent is true.
- `Machine_Light` gains `clip: bool`, comment: clipped to the machine's box (0229, `machine_light_clip_box`); a hand built `Machine_Light{}` holds false, a record's lamp is true unless it says `clip = false`.
- `resolve_machine_lights`: `clip = definition.clip.? or_else true`.
- No validation code: `core:encoding/json` refuses a number or a string for a `Maybe(bool)` with `Unsupported_Type_Error` (checked with a probe on `clip = 3` and `clip = "no"`), so a mistyped value fails the record's parse as any mistyped key does.

`src/simulation_arrival_test.odin`, `src/entity_pod_test.odin`: the existing `gather_machine_lights` calls pass `Model_Renderer{}` (the top falls back to the footprint's height).

`tools/models/records.py`: the docstring's sentence on `lights` adds that a lamp's `clip` (0229) is read by the game only. No code change (the whole `lights` key is ignored). `tools/models/records_test.py`, `test_a_record_with_lights_reads`: the lit record's lamp gains `"clip": False`, still equal.

### The shaders (both files, kept identical where marked)

`data/shaders/field.fs` and `data/shaders/model.fs`, after `point_light_colors`:

```glsl
// The lights' clip boxes (work item 0229, render_point_lights.odin): per
// light three rows of the matrix from the world's metres to its machine's
// box, -1 to 1 inside on every axis, light index's rows at index * 3u. A
// light that shines everywhere (an arm's lamp, a record lamp with clip =
// false, an unused slot) has zero rows, which map every point to the
// box's centre, so it passes. A clipped light's colour has alpha 0: it
// gives nothing to a face turned away from it, so a hull's outer skin,
// turned away from a lamp inside, stays dark. No shadows: the box and the
// facing stand in for them.
uniform vec4 point_light_boxes[24u];
```

Beside `point_light_wrap` (in `field.fs` after the uniforms as today, in `model.fs` with its other constants): `const float back_face_fade = 0.25;` with the comment: a clipped light fades out over this much of the cosine past grazing, so a curved fixture shows no hard edge.

Before `point_light_sum` (byte identical in both files, as `point_light_sum` is):

```glsl
bool point_light_inside_box(uint index, vec3 position)
{
    vec4 point = vec4(position, 1.0);
    vec3 local = vec3(dot(point_light_boxes[index * 3u], point), dot(point_light_boxes[index * 3u + 1u], point), dot(point_light_boxes[index * 3u + 2u], point));
    vec3 reach = abs(local);
    return max(max(reach.x, reach.y), reach.z) <= 1.0;
}
```

`point_light_sum` (byte identical in both files):

```glsl
vec3 point_light_sum(vec3 position, vec3 normal)
{
    vec3 sum = vec3(0.0);
    for (uint index = 0u; index < 8u; index++) {
        vec4 light = point_light_positions[index];
        if (light.w <= 0.0) {
            break;
        }
        if (!point_light_inside_box(index, position)) {
            continue;
        }
        vec4 color = point_light_colors[index];
        vec3 offset = light.xyz - position;
        float share = clamp(1.0 - dot(offset, offset) / max(light.w * light.w, smallest_weight_sum), 0.0, 1.0);
        float turned = dot(normal, normalize(offset + vec3(smallest_weight_sum)));
        float facing = mix(point_light_wrap, 1.0, max(turned, 0.0));
        float back_face = clamp(1.0 + turned / back_face_fade, 0.0, 1.0);
        facing *= mix(back_face, 1.0, color.a);
        sum += color.rgb * share * share * facing;
    }
    return sum;
}
```

The padding lives on the CPU (`MACHINE_LIGHT_CLIP_PADDING_CELLS`), not in the shader: in cells it pads every side alike whatever the box's shape (a share of the unit box would pad a 12 cell side six times more than a 2 cell side), and it stays one constant in one place. The shader's bound is exactly 1.0. Every integer literal carries `u`; `point_light_inside_box` and the comments carry none bare. The header comments of both files: one line naming 0229 beside 0175 and 0224.

### The data key

- `data/machines.sjson`, the `lights` header paragraph, after "radius_cells 1 to 64.": "A lamp may add `clip = false` (work item 0229): by default a lamp lights only inside its machine's box (the footprint, up to the model's top when it rises higher) and gives nothing to a face turned away from it, so a lamp inside a hull leaves the hull's outside dark; with `clip = false` it shines out of the machine (a street lamp)." No record changes: the shipped pod has `lights = []`; 0221 adds the two lamps without `clip`, so they are clipped.
- Bounds: a bool; anything else fails the parse.

### Tests

`src/render_point_lights_test.odin`:
- `test_the_clip_box_maps_the_footprint_to_the_unit_box`: frames with pitch 500 and 1000, each with the identity axes (as the 0224 test) and with a quarter turn about up (`axes = {{0, 0, UNIT_VECTOR_ONE}, {0, UNIT_VECTOR_ONE, 0}, {-UNIT_VECTOR_ONE, 0, 0}}`), all at `origin = {8000 * POSITION_UNITS_PER_METRE, 0, 0}` (a planet's radius away, so the f32 magnitudes are the game's); footprint `{4, 3, 2}`, entity origin `{5, 1, -3}`, rotations 0 to 3 with `size = rotated_footprint_size({4, 3, 2}, rotation)`; `body := frame_render_matrix(frame) * model_transform(origin, size, rotation)`; `box := machine_light_clip_box(body, {4, 3, 2}, 3)`. Asserted, through `transform_point(box, transform_point(body, p))`: the eight padded corners (x ±2.05, y -0.05 and 3.05, z ±1.05) map to the unit box's matching corners (each coordinate ±1 within 0.01); the footprint's centre (0, 1.5, 0) maps to 0 within 0.01; the centre of each of the six faces (x ±2, y 0 and 3, z ±1) maps inside (largest absolute coordinate at most 1); a point 0.1 cells beyond each face's centre maps outside (largest absolute coordinate above 1). With `top_cells` 4.5 the point (0, 4.4, 0) maps inside and (0, 4.6, 0) outside.
- `test_the_arms_lamp_and_an_unclipped_lamp_have_no_box`: `arm_point_light(Arm_Placement{transform = 1, dimensions = arm_dimensions_on_frame(4, 500), working = true})` is found with `clip_box` nil; `machine_point_light` of a `Machine_Light{clip = false, ...}` with a box gives nil, of one with `clip = true` gives that box.
- `test_point_light_uniform_values_pack_the_clip_boxes`: slot 0 clipped with a box whose entry `[row, column]` is `row * 4 + column + 1`, slot 1 unclipped, slots 2 to 7 unused: `boxes[0..2]` are `{1, 2, 3, 4}`, `{5, 6, 7, 8}`, `{9, 10, 11, 12}`, `boxes[3..23]` zero; `colors[0].a` 0, `colors[1].a` 1, unused alpha 1.
- `test_point_light_uniform_values_pack_radius_and_colour` and `test_a_machine_light_turns_with_its_machine_and_scales_with_the_pitch`: take the third result and pass `1` as the box; the latter also asserts `clip_box` nil (its `Machine_Light` literal holds `clip` false).

`src/machine_test.odin`:
- `test_a_machine_lights_clip_is_true_unless_it_says_false`: `resolve_machine_lights` of two `Machine_Light_Definition`s, one without `clip` and one with `clip = false`: `clip` true and false.

`src/entity_pod_test.odin`:
- `test_machine_lights_shine_while_their_model_works`: `expected` becomes `machine_point_light(pod.lights[0], body, 500, machine_light_clip_box(body, pod.footprint, f32(pod.footprint.y)))` with `body := entity_body_matrix(&entities, pod_common)`; the pod's lights in the test set `clip = true`.
- `test_a_pods_lamp_lights_only_inside_its_box` (at the end): `make_test_machines`, the pod given one lamp `{position = {0, 5.8, 0}, color = {1, 0.6, 0.15}, radius_cells = 6, clip = true}`, `place_test_pod`; `gather_machine_lights(..., Model_Renderer{})` gives one light with a box; its own position maps inside the box; the world point of the pod's frame cell centre two cells beyond the footprint's +x face on row 1 (`frame_cell_centre` of `pod_origin(pod) + {size.x + 2, 1, size.z / 2}` in metres) maps outside; the cell centre at `pod_origin(pod) + {size.x / 2, 1, size.z / 2}` maps inside.

`src/shader_source_test.odin`:
- `test_the_point_light_shaders_share_the_clip_and_the_sum`: reads `field.fs` and `model.fs` (`platform.join_path(test_data_directory(), CHUNK_SHADER_DIRECTORY)` as the other tests): both contain `fmt.tprintf("uniform vec4 point_light_boxes[%du];", MAXIMUM_POINT_LIGHTS * POINT_LIGHT_BOX_ROWS)` and `uniform vec4 point_light_positions[8u];` with 8 from `MAXIMUM_POINT_LIGHTS` the same way; the text from `bool point_light_inside_box(` to the first `\n}\n` after `vec3 point_light_sum(` is equal in the two files. The two existing shader tests cover the suffix rule and the GLSL ES rewrite of both files.

### Commands (implementer, in the worktree)

`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/models/records_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the heavy ones prefixed with `taskset -c 8-15 nice -n 10`. No benchmark, no game run. The screenshot pass of the Verify section is the main agent's.

### Docs (same commit)

- `doc/presentation.md`, Chunk meshes, the field shader bullet: after "half of it regardless of the facing, so the light is soft.": "A machine's lamp is clipped to its machine's box (0229): the renderer sends each light's matrix from the world to its box (`point_light_boxes`, three rows a light, zero rows for a light with no box, which pass), the shader adds a light only where the fragment lies inside, and a clipped light (colour alpha 0) gives nothing to a face turned away from it, fading out over a quarter of the cosine past grazing. The arm's lamp has no box."
- `doc/presentation.md`, Machine models, the point lights bullet: "The lights have no shadows, so a cabin lamp also lights the ground round the pod within its radius." becomes: "The lights have no shadows; a lamp lights only inside its machine's box, the footprint padded by `MACHINE_LIGHT_CLIP_PADDING_CELLS` up to the model's top when it rises higher (`machine_light_clip_box`, `machine_model_top`), and a face turned away from it takes nothing, so a pod's hull seen from outside, the ground round it and the machines beside it take no light from the cabin, while the cabin seen through a porthole or the open doors is lit. A record lamp with `clip = false` shines out of its machine (0229)."
- `doc/presentation.md`, The arm, Light: after "the arm's own lit layer included (Machine models)": "; it has no clip box (0229)".
- `doc/content.md`, Models, the `lights` bullet: after "radius 1 to 64 cells (...)": "A lamp may add `clip = false` (0229): by default it lights only inside its machine's box, the footprint up to the model's top, and not the faces turned away from it, so a lamp inside a hull leaves the outside dark; `clip = false` lets it shine out of the machine. A value other than a bool fails the parse."
- `doc/code_map.md`: the `render_point_lights.odin` line adds "the clip boxes (0229)". No new file, no new dependency (`render_entities.odin` already calls `machine_model_top`).
- `doc/log/2026-10-04.md`: a section "Machine lamps clipped to their machine's box (0229)", tags `models, light, shaders, pod, presentation, m15`: the box and why a box (no shadows in this renderer); the facing rule for clipped lights and why the box alone fails (the skin lies inside its own box, the wrap gives back faces half); the box's top from the model (the round three cone to 9.9 over a height of 8); three vec4 rows in one array over a mat4 array (the unbound, platform dependent transpose of `rlSetUniformMatrices`, element locations); zero rows for no box; the padding in cells on the CPU; the arm's lamp unclipped; 0224's decision 1 (spill accepted) reversed by the user's note.
- `DESIGN.md`: no change.

### Hand-back check lines that apply

- "A number parsed from text is range checked": `clip` is a bool; a number or a string fails the parse (probe above). Nothing else is parsed.
- "A new participant in a shared budget": the slots are unchanged; a clipped lamp still takes one of the eight slots by its distance to the camera even when the camera is outside its box (two of the eight for the pod while a player stands at its door). Named here and in the log; no change, since the arms' lamps outside find the six other slots (0224's reasoning).
- "Anything that frees or replaces memory a frame may still draw from": none; the boxes are values packed per frame.
- "A changed save layout loads an old save": no layout change (record and presentation only).
- Tests use no state directory; the others do not apply.

### Questions the item left open, answered

1. Representation: three vec4 rows per light in `point_light_boxes[24u]`, one upload per shader; reasons above.
2. A light without a box: zero rows (pass), colour alpha 1 (today's term). No flag in the shader.
3. The matrix: `affine_inverse(entity_body_matrix(entities, common) * box_to_model)`, `box_to_model` as written under `machine_light_clip_box`; the footprint unrotated, since the body turns it.
4. Where computed: `machine_light_clip_box` (pure, beside `machine_point_light`), once per machine in `append_machine_lights`; `machine_point_light` takes the box and keeps it when the lamp clips.
5. The padding: 0.05 cells on every side on the CPU; reasons above.
6. The box's top: the model's top when higher than the footprint (`machine_model_top`), which makes `gather_machine_lights` take the `Model_Renderer`.
7. The arrival's open doors from outside: the bore's mouth is dark (the strip, 8 cells, reaches the bore's floor near the inner door at about a sixth of its strength and under a hundredth of it at the outer door, 7.7 cells or more away; the desk light does not reach it), the open shutters' emissive strips glow (a hatch works while open), and through the bore and the portholes the lit cabin shows, since those fragments lie inside the box. The ground before the outer door and the hull's skin round the door take nothing. The floor of the cabin is the model's floor disc, so nothing of the terrain shows through the bore.
8. The terrain under the pod: the floor disc (radius 5.0 at y 0) covers it inside the hull, so whether it takes the light changes nothing visible there. The terrain inside the box that does show is the band between the hull and the box's edges: about 0.55 cells wide at the sides, widening to the corners (0221 opens those cells, the ground being their floor). There the clip keeps the light in, the facing rule does not (the ground faces up to the lamp): the ground just outside the hull on the strip's side takes up to share squared 0.13 of the strip's colour, 0.085 at the box's edge, under 0.02 in the corners; the desk light adds about 0.04. Question 1 below.
9. Players and fixtures: inside the box they take the lamps as before (the fixtures' models and the players' bodies draw with the model shader). A player standing in a box corner outside the hull takes the lamps on the side turned to the pod.
10. The `clip` key: `Maybe(bool)`, absent true, no range; the pod's lamps carry none.

### Questions for the main agent

1. The ground band inside the box outside the hull (answer 8): accept the faint glow (at most 0.13 of the strip's colour, on a strip of ground 0.3 m wide at the pod's -x side), or let the field shader skip clipped lights entirely (in `field.fs` only: `if (color.a < 0.5) { continue; }` in place of the box test, a one line difference that then breaks the byte identity, so the shader test would compare the two files up to that line)? Skipping is right for every machine whose model covers its footprint's ground, which is every machine today; a future machine with an open floor (a shelter with a lamp over bare ground) would then light none of its ground. My recommendation: skip in `field.fs`, since the Goal names the ground round the pod and the floor disc covers the rest.
2. The facing rule for clipped lights (consequence 1 above) goes beyond the item's Change: without it the box keeps the light off the ground and the neighbours but the hull's outer skin keeps half the lamp term, which is what the user reported. It also darkens the backs of cabin fixtures turned away from a lamp (the chair's back from the strip), a step towards the depth the user asked about after the first lit cabin shots ("does it cast shadows?", 0221 decision 8). Confirm, or drop it and accept the lit skin.
3. The item names `point_light_boxes[8u]` as `mat4`; this specification sends `vec4[24u]` (reasons under Representation). Confirm.

### Decisions at the approval (main agent, 2026-10-04)

1. The terrain skips clipped lights entirely (`field.fs` adds nothing for a light whose colour alpha is 0): the pod's floor plate covers the ground inside the hull, and the band of ground inside the box but outside the round hull is exactly what the user does not want lit. The arm's lamp stays unclipped and lights the ground as before.
2. The facing rule for clipped lights is confirmed: a face turned away from the lamp takes nothing, fading out just past grazing, so the hull's outer skin inside its own box goes dark. The backs of cabin fixtures turned away from a lamp are dark too, which the cabin's base light (0225) still shows.
3. Three vec4 rows per light in one `vec4 point_light_boxes[24u]` uniform, one upload per shader per frame, in place of the item's `mat4` array: `rlSetUniformMatrices` is not bound and transposes differently per platform, and consecutive element locations are not promised. The box's top is the model's top (`machine_model_top`), since the cone rises past the footprint's height and the cabin's ceiling is its inside.
