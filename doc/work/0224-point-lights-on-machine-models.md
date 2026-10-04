# 0224: Point lights on machine models and the pod's lamps

Status: verified (2026-10-04, the specification approved the same day with the decisions below; the implementer works in `.claude/worktrees/0224` on `item/0224` from `main`, from the user's round one notes on the pod's lab model, "We need more orange and blacks, maybe some point lights to give a moody feeling", and the answer to "Can't we add point lights?": "Yes add point light, and then add it to the pod interior so we can see the result"; lands before 0221 so the lit cabin can be shown on the lab's model through the private data copy, 0221 is rebased onto it)

## Goal

A machine record can name lamps, and the lamps light the machine models round them as the arms' work lamps light the terrain since 0175: the pod's amber ceiling lamps and white strips light its own cabin walls, chair and fixtures, so the interior reads as the sheet (warm pools of light on dark lining, not one flat shade). Presentation only: nothing of the simulation or the state hash changes.

## Controls

No binding changes.

## Change

- The machine models take the field's point lights. Today `render_models.odin` draws every model with raylib's default material (the vertex colours, pre-shaded per face on the CPU by `model_mesh.odin` and `model_triangle_mesh.odin`, times the material's diffuse colour carrying the light tint or the glow), and the meshes carry no normals. The item gives the models a shader pair of their own, `data/shaders/model.vs` and `model.fs` (GLSL 330, every integer literal with the `u` suffix, `#version 330` first so `shader_source_for_gles` rewrites it, loaded through `load_shader_pair`): the vertex colour times the diffuse colour as now, plus the vertex colour's rgb times the same `point_light_sum` as `field.fs`, from the same `point_light_positions` and `point_light_colors` uniforms set with the same nearest eight the field pass gets (`set_field_point_lights` sets both shaders). The lit layer takes the point lights; the emissive layer never does (it glows itself). The world position comes from raylib's `matModel`, as `field.vs` does it. Both meshers upload a normal per vertex (the triangle's for an OBJ, the face direction's for a voxel model). A shader that fails to load leaves the default material and logs, so the game still draws.
- A record key `lights` on a machine: a list of lamps, each a `position` in cells of the unrotated footprint in the model's frame (x and z centred, y from the bottom, +x the front, so the same numbers as the OBJ's), a `color` as three 0 to 255 integers and a `radius_cells`; bounds checked at load (the position inside the footprint plus the model tolerance, the radius 1 to 64 cells), the list capped. `tools/models/records.py` reads the key too (the lab's record reader copies it), ignoring it. The lamp's world position is the body matrix (`entity_frame_matrix` times `model_transform`, as `draw_posed_model` builds it) applied to the position, and the radius scales with the frame's pitch, so a lamp turns with its machine and sits right on every pitch.
- When the lamps shine: while the machine's model counts as working, the same flag as its emissive layer (0175: point lights come on top for working parts). The pod never works (`emissive_brightness` gives it the light tint): a machine of kind `pod` counts as working for its model, its emissive materials and its lamps, so the cabin is lit from the arrival on. 0221's specification planned this as `foundation_model_working` in its lights paragraph; 0224 lands it first and 0221's implementer finds it on `main`.
- `set_field_scene_point_lights` (`loop_field_session.odin`) gathers the lamps of every entity whose machine has `lights` and whose model works, with the arms' lamps, and keeps the nearest eight to the camera as today; the block world's renderer keeps taking no point lights (its slots stay at radius 0, so the model shader's loop costs nothing there).
- The pod's lamps go into its record in `data/machines.sjson` once the lab's model is integrated (0221); until then the private data copy of the lab's model carries them for the user's screenshots. The positions come from the modeller's list of the lab model's emissive patches (the ceiling lamp heads and tubes, the bore's white strip, the oxygen niche's white strip, the door's hazard lamps), at most six lamps for the cabin, so the arms' lamps outside still find slots.
- Docs: `doc/presentation.md` (Shaders: the new pair; Machine models: the normals, the shader, the `lights` key and when the lamps shine; The arm, Light: the models now take the point lights too), `doc/content.md` (the `lights` key under the machine record), `doc/code_map.md` if a new file moves a dependency, `DESIGN.md` only if the art direction's light paragraph needs the models named.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the model shader passes `shader_source_test.odin` (the suffix rule and the GLSL ES rewrite, which read every file of `data/shaders`); a machine's lamps rotate with the machine and their radius scales with the pitch (a lamp at the front of a machine turned twice lies at its back, on the 500 and 1000 mm frames); a lamp shines only while the model works and the pod's shine always; a record with a lamp outside the footprint or a radius out of range is refused with its line; the triangle mesher gives every vertex of a triangle its normal and the voxel mesher the face direction's; `nearest_point_lights` with the pod's lamps and arms' lamps together keeps the nearest eight (an existing test extended or one added).
- A headless screenshot of the cabin on the lab's model with the lamps in the private data copy (the main agent, `tmp/pod_shots.sh`), sent to the user: the walls and the chair show pools of amber and white, the far side darker.
- The state hash of a session with a lit pod equals the hash before the item (presentation only): the hash test or the dev kit the field items use.

## Specification (design, 2026-10-04)

Written from the item, `doc/presentation.md`, `doc/content.md`, `doc/code_map.md`, the code named below and raylib 6.0's `rmodels.c` (`DrawMesh`, `UploadMesh`, `UnloadMesh`, read in `tmp/raylib-src`). Presentation only: no simulation state, save layout, network message or hash input changes. No binding changes.

### What raylib does for us (read, so nothing here is guessed)

- `DrawMesh` binds `material.shader` on every call (`rlEnableShader`), uploads `colDiffuse` from `maps[ALBEDO].color` when the shader has the location, and `matModel` as `transform` times the rlgl transform stack (identity for our model draws, which pass the matrix and never push), so `matModel * vertexPosition` is the vertex in the same metres the field's point lights use, as `field.vs` does it. `LoadShaderFromMemory` finds `vertexPosition`, `vertexNormal`, `vertexColor`, `mvp`, `matModel` and `colDiffuse` by these default names; the attribute locations are bound to raylib's defaults (normal at 2), so a mesh's VAO feeds `vertexNormal` once the mesh has normals.
- `UploadMesh` uploads `mesh.normals` into its own VBO when the pointer is set (else a default attribute (0, 0, 1)); `UnloadMesh` frees `mesh.normals` with `RL_FREE`. So the normals come from `clone_for_raylib` like the other arrays, and `unload_model_layers` needs no change: nothing leaks.
- Since `DrawMesh` binds the material's program every call anyway, drawing the emissive layer with a second material (raylib's default shader) costs no extra state change, while a per layer uniform (`SetShaderValue` before each `DrawMesh`) adds a program bind and a uniform upload per layer draw. Chosen: two materials (answer 1 below).

### Files and procedures

`data/shaders/model.vs` (new):
- `#version 330` as the first line, then a comment block (work item 0224, `render_models.odin`, the attribute names are raylib's defaults; the lit layer only; every integer literal with the `u` suffix, 0105).
- `in vec3 vertexPosition; in vec3 vertexNormal; in vec4 vertexColor;`
- `uniform mat4 mvp; uniform mat4 matModel;`
- `out vec3 fragment_world_position; out vec3 fragment_normal; out vec4 fragment_color;`
- `main`: `fragment_world_position = (matModel * vec4(vertexPosition, 1.0)).xyz; fragment_normal = mat3(matModel) * vertexNormal; fragment_color = vertexColor; gl_Position = mvp * vec4(vertexPosition, 1.0);`. `mat3(matModel)` as `field.vs` (answer 3).

`data/shaders/model.fs` (new):
- `#version 330` first; a comment: the vertex colour (pre-shaded per face on the CPU) times `colDiffuse` (the light tint, a ghost's colour or the broken tint) as raylib's default shader draws it, plus the vertex colour's rgb times the point lights' sum, copied from `field.fs` (keep the two in step).
- `in vec3 fragment_world_position; in vec3 fragment_normal; in vec4 fragment_color;`
- `uniform vec4 colDiffuse; uniform vec4 point_light_positions[8u]; uniform vec4 point_light_colors[8u];`
- `out vec4 finalColor;`
- `const float point_light_wrap = 0.5; const float smallest_weight_sum = 0.0001;` and `vec3 point_light_sum(vec3 position, vec3 normal)` byte for byte the body of `field.fs`'s (loop `for (uint index = 0u; index < 8u; index++)`, break on `light.w <= 0.0`).
- `main`: `vec3 normal = normalize(fragment_normal); vec4 base = fragment_color * colDiffuse; vec3 lit = base.rgb + fragment_color.rgb * point_light_sum(fragment_world_position, normal); finalColor = vec4(min(lit, vec3(1.0)), base.a);` (alpha kept from `base`, so ghosts stay translucent). No texture sampler: raylib's default texture is white, so dropping `texture0` changes nothing.

`src/render_point_lights.odin`:
- Header comment: the nearest lights go to the field shader and the model shader (`set_field_point_lights`, `set_model_point_lights`), and machine lights (0224) join the arms' lamps. `MAXIMUM_POINT_LIGHTS`' comment: "Matches the array size in data/shaders/field.fs and model.fs."
- `point_light_uniform_values :: proc(lights: [MAXIMUM_POINT_LIGHTS]Point_Light) -> (positions, colors: [MAXIMUM_POINT_LIGHTS][4]f32)`: the packing `set_field_point_lights` does today (xyz and the radius in w; rgb and 1), pure; called by `set_field_point_lights` and `set_model_point_lights`.
- `machine_point_light :: proc(light: Machine_Light, body: matrix[4, 4]f32, pitch_millimetres: int) -> Point_Light`: `position = transform_point(body, light.position)`, `color = light.color`, `radius = light.radius_cells * f32(f64(pitch_millimetres) / MILLIMETRES_PER_METRE)`. Pure; called by `append_machine_lights`. The body matrix already scales cells to metres by the pitch (`frame_render_matrix`) and turns the model by its rotation (`model_transform`), so the position turns with the machine; the radius is a length, so it takes the pitch alone (all frames scale uniformly).

`src/render_field.odin`:
- `set_field_point_lights` keeps its signature and calls `point_light_uniform_values` instead of packing inline.

`src/render_frames.odin`:
- `entity_frame_pitch_millimetres :: proc(entities: ^Entities, frame: Frame_Id) -> int`: the frame's `pitch_millimetres` (`find_frame`), `BLOCK_FRAME_PITCH_MILLIMETRES` when not found, matching `entity_frame_matrix`'s identity for a missing frame. Called by `append_machine_lights`.

`src/render_models.odin`:
- Header comment rewritten: the lit layer draws with the model shader (`data/shaders/model.vs`, `model.fs`), which adds the point lights; the emissive layer with raylib's default material, so it never takes them; a shader that fails to load leaves the lit layer on the default material too.
- Constants `MODEL_VERTEX_SHADER_PATH :: "shaders/model.vs"`, `MODEL_FRAGMENT_SHADER_PATH :: "shaders/model.fs"`.
- `Model_Renderer` gains `emissive_material: rl.Material` (raylib's default), `point_light_locations: [2]i32` and `point_lights_ready: bool`; `material` becomes the lit layer's (comment: the model shader, or raylib's default when it did not load).
- `use_model_shader :: proc(renderer: ^Model_Renderer, data_directory: string)`: `load_shader_pair(data_directory, MODEL_VERTEX_SHADER_PATH, MODEL_FRAGMENT_SHADER_PATH, "model")`; on failure `platform.log_printf("models: the model shader did not load; models draw without point lights")` and return (the default material stays); on success `renderer.material.shader = shader`, the two locations by `rl.GetShaderLocation` of `"point_light_positions"` and `"point_light_colors"`, `point_lights_ready = true`. Called by `init_model_renderer`.
- `init_model_renderer`: `material` and `emissive_material` both `rl.LoadMaterialDefault()`, then `use_model_shader`, then `use_machine_models` as now.
- `destroy_model_renderer`: unloads both materials (`UnloadMaterial` unloads the model shader with the lit material and never raylib's default shader); fix its comment.
- `model_layer_material :: proc(renderer: Model_Renderer, layer: Model_Layer) -> rl.Material`: `emissive_material` for `.Emissive`, `material` for `.Lit`. Pure.
- `draw_model_layers_colored`: per layer `material := model_layer_material(renderer, layer)`, set its `maps[ALBEDO].color`, `rl.DrawMesh(mesh, material, ...)`. Every caller (`draw_model_layers`, the ghosts, the arm, the player's limbs, the trees) follows unchanged.
- `set_model_point_lights :: proc(renderer: Model_Renderer, lights: [MAXIMUM_POINT_LIGHTS]Point_Light)`: returns when `!point_lights_ready`; else `point_light_uniform_values` and two `rl.SetShaderValueV(renderer.material.shader, ..., .VEC4, MAXIMUM_POINT_LIGHTS)` as `set_field_point_lights`. Called by `set_field_scene_point_lights` and `draw_session_world`.
- `upload_model_mesh`: adds `normals = cast([^]f32)clone_for_raylib(mesh.normals[:])`.
- `entity_body_matrix :: proc(entities: ^Entities, common: Entity_Common) -> matrix[4, 4]f32`: `entity_frame_matrix(entities, common.frame) * model_transform(common.origin, common.size, common.rotation)`. `draw_posed_model` uses it for `body` (same value as today); `append_machine_lights` uses it, so a lamp sits where its model is drawn.

`src/model_mesh.odin`:
- `Model_Mesh` gains `normals: [dynamic][3]f32` (one per position, unit); `make_model_mesh` makes it, `destroy_model_mesh` deletes it.
- `direction_unit_vector :: proc(direction: Direction) -> [3]f32`: moved here unchanged from `model_triangle_mesh_test.odin` (delete it there; the test keeps calling it).
- `append_model_quad :: proc(mesh: ^Model_Mesh, corners: [4][3]f32, colour: [4]u8, positive: bool, normal: [3]f32)`: appends `normal` with each corner. `mesh_model_slice` passes `direction_unit_vector(direction)`; the model's per axis scale is positive and axis aligned, so the face direction stays the normal after `place_model_corners`.

`src/model_triangle_mesh.odin`:
- `append_model_triangle :: proc(mesh: ^Model_Mesh, corners: [3][3]f32, colour: [4]u8, normal: [3]f32)`: appends `normal` with each corner. `mesh_obj_triangles` passes `obj_triangle_normal(triangle)` (the `vn` normal or the winding's, the one the shade already uses; skipped triangles have none).
- `MODEL_FOOTPRINT_TOLERANCE_CELLS` moves to `machine.odin` with its comment (unchanged value), so the record check reads it without a new simulation to presentation reference (the simulation's record in `doc/code_map.md` stays at 21).
- `src/model_check_test.odin`: `append_test_quad` passes `triangle_winding_normal` of each triangle's corners; the three direct `append_model_triangle` calls (lines 39, 150, 172) pass `triangle_winding_normal` of their corners.

`src/machine.odin`:
- Constants: `MAXIMUM_MACHINE_LIGHTS :: 8` (a machine never needs more lights than the shaders' eight slots; the cabin uses at most six), `MINIMUM_MACHINE_LIGHT_RADIUS_CELLS :: 1`, `MAXIMUM_MACHINE_LIGHT_RADIUS_CELLS :: 64`, and the moved `MODEL_FOOTPRINT_TOLERANCE_CELLS :: 0.02`.
- `Machine_Light_Definition :: struct { position: [3]f32, color: [3]int, radius_cells: f32 }`; `Machine_Definition` gains `lights: []Machine_Light_Definition` (after `fixtures`).
- `Machine_Light :: struct { position: [3]f32, color: [3]f32, radius_cells: f32 }` (position in cells of the model's frame, colour 0 to 1); `Machine` gains `lights: [MAXIMUM_MACHINE_LIGHTS]Machine_Light` and `light_count: int`, commented (0224, presentation only: the simulation never reads them).
- `machine_light_inside_footprint :: proc(position: [3]f32, footprint: Machine_Footprint_Definition) -> bool`: `|x| <= width / 2 + tol`, `|z| <= depth / 2 + tol`, `-tol <= y <= height + tol`, tol `MODEL_FOOTPRINT_TOLERANCE_CELLS`. Pure.
- `validate_machine_lights :: proc(definition: Machine_Definition) -> string`, called by `validate_machine_definition` right after `validate_open_cells`. Messages in the record errors' form (the load logs `error: invalid <path>: <message>`):
  - `machine %q has more than %d lights` (`MAXIMUM_MACHINE_LIGHTS`)
  - `machine %q light %d at [%.3f, %.3f, %.3f] is not inside the footprint`
  - `machine %q light %d has radius_cells %.3f, not %d to %d`
  - `machine %q light %d has a color channel outside 0 to 255`
- `resolve_machine_lights :: proc(definitions: []Machine_Light_Definition) -> (lights: [MAXIMUM_MACHINE_LIGHTS]Machine_Light, count: int)`: validated before; colour divided by 255. `resolve_machine` sets `lights` and `light_count` from it.

`src/render_entities.odin`:
- `foundation_model_working :: proc(entities: ^Entities, foundation: Foundation, machine: Machine) -> bool`: `.Pod` true, `.Hatch` `foundation.hatch_open` (what `hatch_pose` gives), `.Oxygen_Generator` `oxygen_generator_supplies_a_room(entities, foundation.handle)`, else false. The foundations' loop of `draw_entities` keeps `case .Foundation:` and `case .Hatch: draw_hatch(...)`, drops the `.Oxygen_Generator` case and draws every other entry with `draw_entity_cells(..., foundation_model_working(&frame.world.entities, foundation, machine), ...)`. 0221 planned this procedure with `(entities, machine, handle)`; it takes the `Foundation` here so the hatch's flag fits (0221's implementer finds it on `main`).
- One line working procedures, pure, replacing the inline expressions in `draw_entities` and `draw_drill` (same expressions): `furnace_model_working :: proc(furnace: Furnace) -> bool`, `schematic_crate_model_working :: proc(crate: Schematic_Crate) -> bool`, `drill_model_working :: proc(drill: Drill) -> bool`, `assembler_model_working :: proc(assembler: Assembler) -> bool`, `lab_model_working :: proc(lab: Lab) -> bool`. `core_sample_drill_is_working` and `launch_pad_is_working` exist.
- `append_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, common: Entity_Common, machine: Machine, working: bool)`: nothing unless `working` and `machine.light_count > 0`; else `machine_point_light(light, entity_body_matrix(entities, common), entity_frame_pitch_millimetres(entities, common.frame))` for each of the first `light_count`.
- `gather_machine_lights :: proc(lights: ^[dynamic]Point_Light, entities: ^Entities, machines: Machine_Registry)`: over the alive entries of the pools `draw_entities` draws whose model can work: furnaces, schematic crates, drills, assemblers, labs, core sample drills, launch pads and foundations, each with its working procedure above (`machines.machines[entry.machine]` for the record). Chests and capsules never work and are skipped; inserters are skipped (their light is the arm's lamp, `arm_point_light`). Called by `set_field_scene_point_lights`.

`src/loop_field_session.odin`:
- `set_field_scene_point_lights`: after the arms, `if !scene.hide_frames { gather_machine_lights(&lights, &scene.state.world.entities, scene.content.machines) }` (during the fall the machines are not drawn, so their lights do not shine onto the crater); then `nearest_point_lights` as now, `set_field_point_lights(scene.renderer, nearest)` and `set_model_point_lights(scene.models, nearest)`. Comment: the working arms' and machines' lights.

`src/loop.odin`:
- `draw_session_world`: `set_model_point_lights(state.presentation.model_renderer, {})` right before its `draw_entities` call, so the block world's models never keep a field session's lights (the renderer lives for the process). The block world sets no lights otherwise.

### The data key

- `data/machines.sjson`: header paragraph after the `open_cells` one: `lights` (optional, work item 0224, at most 8) lists `{position = [x, y, z], color = [r, g, b], radius_cells}`: a lamp at `position` in cells of the model's frame (x and z centred on the unrotated footprint, y from its bottom, +x the front: the OBJ's numbers), inside the footprint with 0.02 cells of slack, `color` 0 to 255 per channel, `radius_cells` 1 to 64. Each shines a point light in a field session while the machine's model works (the same flag that lights its emissive materials; a pod always works); the block world takes no point lights. Presentation only.
- The pod's record: `lights = []` with the comment "The cabin's lamps (0224), filled from the lab model's emissive patches once it is integrated (0221): `{position = [x, y, z], color = [r, g, b], radius_cells = r}` each, at most six so the arms outside find slots." The shipped pod model is the old one; it gets no lamps. The lamp machine gets none: lamps are drawn only in the block world (`draw_power_entities`), which takes no point lights.
- Shipped values: none in this item.

### `tools/models/records.py`

`read_machine` reads keys with `.get`, so a record with `lights` already reads; no code change. The module docstring names the key as read by the game only. `tools/models/records_test.py` gains `test_a_record_with_lights_reads`: `records.read_machine` of a small record dict with and without a `lights` list gives equal `Machine` values. The lab's copy (`make_pod_lab.sh`) takes the file as is. Note for the main agent filling the pod's lights from the modeller's list: the lab works in the Blender frame (x front, y the game's -z, z up), so a Blender point (bx, by, bz) is the record's (bx, bz, -by).

### Tests

- `test_shipped_shaders_have_no_bare_integer_literals` and `test_shipped_shaders_begin_with_a_version_line` (`shader_source_test.odin`): `checked >= 10`, the message "found fewer than the ten shipped shaders (chunk, water, field, arrival and model)". They read every file of `data/shaders`, so `model.vs` and `model.fs` are checked for the suffix rule, the version line and the GLSL ES rewrite.
- `test_point_light_uniform_values_pack_radius_and_colour` (`render_point_lights_test.odin`): two lights in, slot 0 and 1 carry the position with the radius in w and the colour with alpha 1; slots 2 to 7 are zero.
- `test_a_machine_light_turns_with_its_machine_and_scales_with_the_pitch` (`render_point_lights_test.odin`): for pitches 500 and 1000, a frame with identity axes (`UNIT_VECTOR_ONE`) at the origin, footprint size {4, 3, 2} at origin {0, 0, 0}, a light at {1.5, 2, 0} (the front), `radius_cells` 4. Body `frame_render_matrix(frame) * model_transform({0, 0, 0}, {4, 3, 2}, rotation)`. Rotation 0: position {3.5, 2, 1} times the pitch in metres; rotation 2: {0.5, 2, 1} times it (the back); radius 4 times the pitch in metres, within 1e-4.
- `test_nearest_point_lights_keep_machine_lights_and_arms_together` (`render_point_lights_test.odin`): six machine lights at x 1 to 6 and three arm lights (`ARM_LIGHT_RADIUS_METRES`) at x 1.5, 2.5 and 9 from a camera at the origin: eight kept, nearest first, the arm at 9 dropped.
- `test_the_emissive_layer_draws_with_the_default_material` (`render_point_lights_test.odin`): a `Model_Renderer` with `material.shader.id = 7` and `emissive_material.shader.id = 3`: `model_layer_material` gives 7 for `.Lit` and 3 for `.Emissive`.
- `test_the_voxel_mesher_gives_each_face_its_direction` (`model_mesh_test.odin`): the single voxel of `test_a_single_voxel_has_six_faces`: 24 normals, each of the six directions on four vertices, and every triangle's `triangle_winding_normal` (through the indices) equals its vertices' normal within 1e-5.
- `test_the_triangle_mesher_gives_each_vertex_its_triangles_normal` (`model_triangle_mesh_test.odin`): an `Obj_Model` of two triangles (`test_obj_triangle`), the first with `normal = {0, 1, 0}` set, the second without: `mesh_obj_triangles` gives as many normals as positions, vertices 0 to 2 the file's normal, 3 to 5 the second's winding normal.
- `test_machine_lights_stay_on_the_footprint_with_a_bounded_radius` (`machine_test.odin`): a copy of `test_machine_open_cells_are_boxes_inside_the_footprint`'s room (kind, footprint 3 wide, 4 deep, 2 high, and its open cells kept, since a pod needs its cabin box) with one light at {1.51, 2.01, -2.01}, colour {255, 180, 90}, radius 1: accepted, and the resolved light's colour is {1, 180/255, 90/255}. Refused, each with its message's prefix `machine "room" light 0` (or `has more than 8 lights`): x 1.53, z 2.03, y -0.03, y 2.03, radius 0.5, radius 65, a channel 256, a channel -1, nine lights. Radius 64 accepted. The shipped pod (`make_test_machines`) has `light_count` 0.
- `test_the_pod_counts_as_working_for_its_model` (`entity_pod_test.odin`, replaces 0221's planned `test_the_pod_draws_its_lights_as_working`): after `place_test_pod`, `foundation_model_working` is true for the pod, true for the oxygen generator (room supplied), false for both closed hatches, true for the outer hatch after `toggle_hatch` opens it; with both hatches open the generator's is false and the pod's still true.
- `test_machine_lights_shine_while_their_model_works` (`entity_pod_test.odin`): `make_test_machines`, the pod given two lights and the oxygen generator one (set on the registry's entries, `light_count` too), `place_test_pod`: `gather_machine_lights` gives three lights, each radius its `radius_cells` times 0.5; the pod's first light equals `machine_point_light` of the pod's entry with `entity_body_matrix` and pitch 500; with both hatches open it gives two (the generator stops working, the pod's stay). `entity_frame_pitch_millimetres` gives 500 for the pod's frame and 1000 for `BLOCK_FRAME`.
- `test_the_machine_lights_leave_the_hash` (`simulation_arrival_test.odin`, beside `test_the_arrivals_presentation_leaves_the_hash`, its pattern): `make_field_test_game_content`, the pod's record given two lights before both worlds start (`run_arrival_test_world`, count 0); each of 700 ticks both worlds tick, and on the watched one `gather_machine_lights` into a temp array and `nearest_point_lights` round the first player's eye; at ticks 300, 540 and 700 the gathered count is 2 and `lockstep_state_hash` equals the plain world's.

### Commands (implementer, in the worktree)

`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/models/records_test.py`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`. Prefix heavy commands with `taskset -c 8-15 nice -n 10`. No benchmark, no game run.

### Docs (same commit)

- `doc/presentation.md`, Shaders: the list adds `model.vs` and `model.fs` (0224, the machine models' lit layer).
- `doc/presentation.md`, The field session, the scene bullet: "the point lights of the working parts" becomes the working arms' and machines' lights (none from machines during the fall).
- `doc/presentation.md`, Chunk meshes, the field shader bullet: the gathered eight also go to the model shader (`set_model_point_lights`), and the session gathers the machines' lights (`gather_machine_lights`) with the arms'.
- `doc/presentation.md`, Machine models: one new bullet: both meshers upload a normal per vertex (the face direction, the triangle's); the lit layer draws with the model shader (vertex colour times the diffuse colour plus the vertex colour times the point lights, the `field.fs` term), the emissive layer with raylib's default material and never takes point lights; a failed shader load logs and draws as before; the `lights` key (positions in the model's frame, colour, radius in cells scaled by the pitch, turned with the body matrix, `machine_point_light`), shining while the model works (`foundation_model_working`: a pod always, a hatch while open); the block world clears them (`draw_session_world`).
- `doc/presentation.md`, The arm, Light: the point light lights the models round it too, the arm's own lit layer included; "The block world's renderer takes no point lights" stays, with the models' lights cleared there.
- `doc/content.md`, Models: one bullet on the `lights` key (bounds, cap, frame, the Blender conversion for the lab's lists, the pod's lamps filled with 0221).
- `doc/code_map.md`: `render_point_lights.odin`'s line adds machine lights and the uniform packing; `render_entities.odin`'s line adds the working procedures and `gather_machine_lights`; `render_models.odin`'s adds the model shader. No new file, no new dependency, no record count changes.
- `doc/log/2026-10-04.md`: a section "Point lights on machine models (0224)", tags `models, light, shaders, pod, presentation, m15`: two materials over a per layer uniform and why; `mat3(matModel)` and why; the cap of 8; the pod always working; no machine lights during the fall; the block world clearing them; lights shine through hulls (no shadows).
- `DESIGN.md`: no change (Art direction already says point lights come on top for working parts).

### Hand-back check lines that apply

- "A number parsed from text is range checked": the position, radius and colour are bounded in `validate_machine_lights`, the list capped at `MAXIMUM_MACHINE_LIGHTS`; tested.
- "A start-up load that the game itself can make fail falls back and reports": a failed model shader keeps the default material and logs one line (`use_model_shader`).
- "A new participant in a shared budget": machine lights share the eight slots with the arms' lamps by distance to the camera; in the cabin the pod's lamps win, which is wanted, and at most six cabin lamps leave two slots; `test_nearest_point_lights_keep_machine_lights_and_arms_together`.
- "A list that grows without bound is capped where it draws": the gathered list lives in the temp allocator per viewport and only the nearest eight are uploaded.
- "Anything that frees or replaces memory a frame may still draw from": the second material is made at start and freed at the end only; the meshes' normals are freed by the same `UnloadMesh` that already runs between frames (`replace_machine_models`). No new path.
- The others (file writes, save layout, UI audit cases) do not apply; tests use no state directory.

### Questions the item left open, answered

1. Emissive mechanism: a second material on raylib's default shader for the emissive layer. `DrawMesh` binds the program on every call regardless, so this adds no state change, while a per layer uniform adds a program bind and an upload per layer draw; the default shader also keeps the emissive look exactly as today.
2. The cap: 8, the shaders' slot count; more could never all show.
3. The normal transform: `mat3(matModel)` normalized in the fragment, as `field.vs`. The model matrices scale uniformly (the frame's pitch, a tree's scale) or per axis on axis aligned voxel faces (the voxel scale, the arm's), where the result is still the right direction after normalizing; `matNormal` would cost raylib an inverse per draw for no visible gain under the half wrap term.
4. "Refused with its line": record errors name the machine and the entry's index (`open_cells box %d`, `fixture %d`), since validation runs on the parsed record; the lights follow that (`light %d`).
5. Which entities' lights shine: those of the pools `draw_entities` draws whose model can work. A machine drawn elsewhere (fluid and power machines in the block world, an inserter's arm, a tree) may carry the key, which then does nothing; the header and `doc/content.md` say so instead of a kind check that would have to mirror the gather.
6. The fall: machine lights are not gathered while `hide_frames` is set; the arms' gather is left as it is.
7. Hot reload: the model shader is not reloaded on a shader file change, as the field shader is not (`reload_shaders` covers the chunk and water pairs).
8. The `lights` placeholder for the pod: an empty list with the shape in its comment; the shipped old pod gets no lamps.

### Questions for the main agent

1. The lights shine through hulls (no shadows): a cabin lamp lights the crater floor and anything outside the pod within its radius, and the field terrain under the pod is the cabin's floor. Keep radii to roughly the lamp's distance to the hull (the modeller's list should state them so), or accept a soft glow round the pod at night?
2. 0221's specification names `foundation_model_working(entities, machine, handle)` and the test `test_the_pod_draws_its_lights_as_working`; this item lands `foundation_model_working(entities, foundation, machine)` and `test_the_pod_counts_as_working_for_its_model`. Amend 0221's specification (its lights paragraph and that test become "already on `main`") before its implementer starts.

### Decisions at the approval (main agent, 2026-10-04)

1. Light through the hull: accepted. The lights have no shadows, so a cabin lamp spills a soft glow on the ground round the pod at night; that reads as light leaking from the portholes and is wanted. The modeller's radii (6, 4, 3, 3, 2 and 2.5 cells) are about each lamp's distance to the hull already, and nothing in the item clamps them.
2. 0221's specification is amended in this commit: `foundation_model_working(entities, foundation, machine)` and `test_the_pod_counts_as_working_for_its_model` land here, and 0221's implementer finds them on `main` (its lights paragraph and its test of that name are struck).
3. The pod's lamps: the modeller measured the lab model's emissive patches (`tmp/pod_lab/LAMPS.md`, the area weighted centres of the exported triangles in the OBJ's frame) and suggested six lights, which the main agent puts into the private data copy for the user's screenshots now and 0221's implementer into `data/machines.sjson` with the model: cabin fill (255, 150, 40) at (0, 5.8, 0) radius 6; desk (255, 150, 40) at (-1.7, 4.6, -2.2) radius 4; inner door (255, 150, 40) at (0.7, 2.4, 0) radius 3; bunk and locker (255, 150, 40) at (1.4, 5.0, 1.8) radius 3; bore (196, 228, 255) at (3.0, 2.0, 0) radius 2; oxygen niche (196, 228, 255) at (1.0, 2.6, -2.4) radius 2.5. The positions are the OBJ's own numbers, so no Blender conversion applies to this list.
4. No machine lights during the fall: agreed; 0223, which draws the pod during the descent, revisits it.
5. The working procedures per pool (`furnace_model_working` and the others) are accepted as the one place the draw and the gather agree on; the implementer keeps them one line each and changes no expression.
