# 0347: The factory's draws culled and instanced

Status: verified (2026-11-12)

Every machine (up to 4 draw calls each), every foundation cell (twice a frame) and every belt item is drawn every frame wherever it is, with no culling (`work/performance_research_0340.md`, 2.2; `doc/audit/presentation.md`). Small with a handful of machines, the largest CPU item of the frame once factories grow. Builds on 0163 (`doc/work/0163-per-frame-machine-view.md`).

## Goal

A factory's draw cost follows what is in view, in a few instanced calls per model.

## Controls

None.

## Change

- One list of machines per frame, culled by the frustum and a distance, grouped by model and drawn instanced, the light tint and the glow per instance.
- Foundations as instances or one mesh per frame table revision; belt items instanced per kind.
- The pod and the ghosts keep their own path. The looks do not change.

## Verify

- The checks and the suite; the UI and model audits unchanged.
- 0342's table: the early factory view and a factory of 1000 machines by blueprint, draw calls and the CPU's entity section, before and after.
- Captures of a factory before and after, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `b9a6c82` and the specifications of 0346 (`upload_instances_in_place`, `begin_instanced_material`, `end_instanced_material`, `draw_mesh_instances`, `Field_Scene.tree_view`, `FIELD_TREE_VIEWS`) and 0342 (the sections, `count_draw_call`, the views file and its script), both on `main` before this item starts. 0344 shares no file with it.

### Decisions

1. **The seam is the model draw's leaf, not a machine view.** `draw_entities` keeps its pool loops. Each model draw poses its pieces (`pose_machine_model`, `pose_arm`), tests the posed box against the pass's cull, then appends one `Model_Instance` a piece to the pass's list or draws as today (`emit_posed_model`). After `draw_entities` the list is grouped by mesh and layer and drawn instanced from one persistent buffer a viewport and pass (the sun's and the scene's). 0163's `Machine_View` (markers, hum, ports: the block world's readers) is not needed for the draw cost (question 2). Rejected: a list kept across frames, since every working part's phase and every arm move each frame.
2. **The cull is exact, after posing.** The box is the union of each drawn piece's mesh bounds (`Model_Bounds`, kept per mesh at upload) under its posed transform, plus the held item's cube. Posing is a few matrix products; the draws are what is removed. Rejected: the footprint box widened by a margin before posing, as `model_frame_draws_entity` does for the casters. A hatch slides up to 12 cells and a frame's arm reaches up to 16 (8000 mm over 500), so a fixed margin pops at the screen's edge and a margin per motion kind is a special case per kind. The cast pass keeps that loop-top test and takes the exact one as well, which leaves out only what the map would clip.
3. **The scene pass culls by the frustum and the haze's end** (`Field_Frame_Lights.haze.fog_end`, the last level's distance, so 0343's setting). Past it `apply_haze` paints a lit layer the end colour, so a culled lit layer showed only that. What disappears: the unhazed emissive layers, slabs, runs, poles and belt items past the view distance, which stand beyond the drawn terrain, over the globe (question 1). A distance of 0 or less tests the frustum alone.
4. **An instance carries its colour in its matrix's bottom row**, as a tree's does: rows 0 to 2 the transform, row 3 the layer's `rl.Color` over 255 (what raylib makes of `colDiffuse` today) and 1. A piece's lit and emissive layers are two groups with the same transforms. The model shader gains three uniforms:
   - `instanced_on`: the vertex goes through `instanceTransform` (row 3 rebuilt to 0, 0, 0, 1, as `tree.vs` and `sun_shadow.vs` do), then `matModel`, which the instanced draw sets to the rlgl stack's transform (the pod's during the descent);
   - `instance_tint_on`: that row's colour multiplies `colDiffuse`;
   - `flat_on`: the colour is `fragment_color * colDiffuse * tint` and nothing else, raylib's default shader on its white texture.
   So the emissive layer, the slabs and the belt items draw instanced through the model shader in flat mode, and the sun's pass through `sun_shadow.vs`'s `instanced_on`, as the trees do. A direct draw meets all three at 0.
5. **The pod, the ghosts and the workbench keep `DrawMesh`.** The pod (`.Pod`) is posed and culled like the rest, then drawn directly (`model_frame_takes_instances`). The ghosts and the model preview never reach `draw_posed_model`. A model shader that did not load, or lacks the three uniforms (an overlay copy from before), leaves `Model_Renderer.instancing_ready` false: every model draws directly, as today, with one log line.
6. **Foundations: instances in their frame's cells, in bricks, one buffer.** A foundation cell is a unit cube scaled by `FRAME_CELL_FILL` at the cell's centre, in its frame's cells, its slab colour in row 3. The cells are grouped per frame into bricks of `FOUNDATION_BRICK_CELLS` (32) a side, each brick a range of one buffer with its box in cells. A pass tests each brick's box under its frame's matrix and draws a visible brick in one instanced draw under that matrix (the rlgl stack). The buffer is rebuilt in `prepare_field_frame`, never in a pass. Rejected: one mesh per frame. raylib's indices are u16, so a mesh holds 2,730 cells; a mesh costs 456 bytes a cell against 64; in world positions it would be rebuilt on every pose change. Rejected too: instances rebuilt every frame, a pass over every cell, the cost being removed.
7. **The slabs' edges as instanced lines.** A mesh of the cube's 12 edges in `FRAME_EDGE_COLOR` is drawn as `GL_LINES` over the same instances with the tint off: the lines `DrawCubeWiresV` draws. rlgl draws vertex arrays only as triangles, so `glDrawArraysInstanced` is reached as `log_gl_info` reaches `glGetString`: `rl.glfwGetProcAddress` off Android, `libGLESv3` on it. Without it a visible brick's edges go through rlgl's batch per cell, as today. The sun's pass draws no edges: they lie on the slabs' own outlines. Rejected: edges drawn from screen derivatives in the shader (another look); polygon line mode (none on GLES).
8. **What rebuilds the foundations**: `Frame_Table.revision` (occupancy and pose) or `Model_Renderer.generation` (new: +1 whenever the models or the machine table are replaced, so a tier's new colour reaches the slabs) moved. The bricks are built again and uploaded only when their bytes differ. No world field is added.
9. **Moving frames (0357).** Nothing keeps a world position across frames: each pass builds the frames' matrices from the frame table (`frame_matrix_table`), the foundations are in cells, the machines' and runs' boxes come from that pass's transforms. A frame that moves every tick is drawn and culled where its record stands that frame. Left to 0357:
   - `revision` moving every tick makes `refresh_field_foundations` walk every occupant every tick (it uploads nothing), and the cover's streaming snapshots the frames on the same counter; an occupancy count apart from the pose fixes both;
   - poses are drawn as stored, not interpolated between ticks; `frame_matrix_table` is the one place an interpolated matrix would reach every draw of this item;
   - runs are polylines in world positions.
10. **Belt items: one instanced draw** of the unit cube in flat mode, each item's colour per instance (the five category colours, all opaque), which is "instanced per kind" at once. Runs, sides, pipes and poles stay in rlgl's batch, each culled by its box. Items are made only on shown runs, and a run's frame facts are read once a pass instead of once an item.
11. **Frame lookups.** `find_frame` scans the frames, and every machine placed on bare ground starts a frame (0201), so a lookup per entity costs entities times frames. A pass builds `Frame_Matrix_Table` once (sorted by id, binary searched) for the cull, the posing, the arms, the foundations and the runs. `find_frame` is world code the simulation reads, and stays.
12. **Buffers per viewport and pass**, `Field_Renderer.instance_buffers[FIELD_VIEW_SLOTS]`: the sun's machines, the scene's machines and the belt items, each written once a frame through `upload_instances_in_place` (0346's decision 2: in place). 0346's `Field_Scene.tree_view` and `FIELD_TREE_VIEWS` become `view_slot` and `FIELD_VIEW_SLOTS` (moved to `render_field.odin`), since the machines and the items index by them too.
13. **Order.** The instanced machines draw after the pool loops instead of inside them. All are opaque under the depth test, so only coincident faces (z-fighting today) may resolve otherwise. A group keeps pool order (stable sort).
14. **0342.** Instanced draws count in `draw_mesh_instances` and `draw_mesh_line_instances`. The foundations stay in Foundations, the machines' instanced draws in Machines, the items in Runs, the sun's in Shadow_Models; a rebuild of the foundations lands in Prepare. No counter is added.
15. **The 1000 machine view (part A).** `blueprint` answers `error no block world` on a field world (`doc/commands.md`), so the Verify's "by blueprint" cannot be. 0342's script builds it with `place` lines, as it builds `factory` (question 3).

### Files and procedures

`src/render_model_instances.odin` (new, presentation; header: decisions 1 to 5 in a few lines)
- `MAXIMUM_POSED_PIECES :: 1 + MAXIMUM_IRIS_BLADES`.
- Types:
  - `Model_Mesh_Slot :: enum u8 {Body, Part, Arm_Base, Arm_Turret, Arm_Upper_Arm, Arm_Forearm, Arm_Gripper, Arm_Finger}` (the arm's in `Arm_Part`'s order);
  - `Model_Piece :: struct {machine: Machine_Id, slot: Model_Mesh_Slot}`;
  - `Model_Bounds :: struct {minimum, maximum: [3]f32}`, inverted (minimum above maximum) when empty;
  - `Model_Piece_Pose :: struct {slot: Model_Mesh_Slot, transform: matrix[4, 4]f32}`;
  - `Posed_Model :: struct {pieces: [MAXIMUM_POSED_PIECES]Model_Piece_Pose, count: int, minimum, maximum: [3]f32}`, the box inverted while empty;
  - `Model_Instance :: struct {piece: Model_Piece, transform: matrix[4, 4]f32, colors: [Model_Layer]rl.Color}`;
  - `Model_Instance_Group :: struct {mesh: rl.Mesh, first, count: int}`;
  - `Model_View :: struct {frustum: render_frustum.Frustum, eye: [3]f32, distance_metres: f32, transform: matrix[4, 4]f32}`;
  - `Frame_Matrix_Entry :: struct {frame: Frame, matrix: matrix[4, 4]f32}`, `Frame_Matrix_Table :: struct {entries: []Frame_Matrix_Entry}`;
  - `Instance_Buffer :: struct {buffer: u32, capacity: int}`, `Field_Instance_Buffers :: struct {cast_models, models, items: Instance_Buffer}`.
- Pure:
  - `frame_matrix_table :: proc(frames: ^Frame_Table, allocator := context.temp_allocator) -> Frame_Matrix_Table`: every record with `frame_render_matrix`, sorted by id.
  - `find_frame_matrix :: proc(table: Frame_Matrix_Table, id: Frame_Id) -> (entry: Frame_Matrix_Entry, found: bool)`: binary search. `BLOCK_FRAME` gives `block_frame()` and the identity, found; a missing id the zero frame and the identity, not found, as `entity_frame_matrix` and `inserter_arm_placement` read one today.
  - `model_frame_entity_matrix :: proc(frame: Model_Frame, entities: ^Entities, id: Frame_Id) -> matrix[4, 4]f32`: `find_frame_matrix`'s when `frame.frames != nil`, else `entity_frame_matrix(entities, id)`.
  - `transformed_box :: proc(transform: matrix[4, 4]f32, minimum, maximum: [3]f32) -> (box_minimum, box_maximum: [3]f32)`: the centre transformed, the half extent through the absolute matrix (`sun_shadow_entity_box`'s arithmetic).
  - `model_view_shows :: proc(view: ^Model_View, minimum, maximum: [3]f32) -> bool`: true for nil; else the box under `view.transform` within `distance_metres` of the eye (`box_distance_metres`, skipped at 0 or less) and in the frustum (`render_frustum.frustum_contains_box`).
  - `model_frame_shows_box :: proc(frame: Model_Frame, minimum, maximum: [3]f32) -> bool`: with `casters`, `sun_shadow_box_casts` of the box under `casters.transform`; then `model_view_shows(frame.view, ...)`.
  - `model_frame_takes_instances :: proc(frame: Model_Frame, kind: Machine_Kind) -> bool`: `frame.instances != nil && kind != .Pod`.
  - `model_layers_bounds :: proc(layers: Model_Layers) -> Model_Bounds`: both layers' positions.
  - `model_piece_layers :: proc(renderer: Model_Renderer, piece: Model_Piece) -> Uploaded_Layers` and `model_piece_bounds :: proc(renderer: Model_Renderer, piece: Model_Piece) -> Model_Bounds`: zero layers and an inverted box for a machine past `renderer.models`.
  - `add_posed_piece :: proc(posed: ^Posed_Model, renderer: Model_Renderer, machine: Machine_Id, slot: Model_Mesh_Slot, transform: matrix[4, 4]f32)`: nothing when the slot's layers have no vertices (`layers_have_vertices`); else appends and grows the box by `transformed_box` of the slot's bounds.
  - `grow_posed_box :: proc(posed: ^Posed_Model, minimum, maximum: [3]f32)`.
  - `pose_machine_model :: proc(renderer: Model_Renderer, machine_id: Machine_Id, body: matrix[4, 4]f32, machine: Machine, phase: f32) -> Posed_Model`: the body, then the part at each pose of `motion_part_transforms` (`body * pose`), the order `draw_posed_model` draws in today.
  - `pose_arm :: proc(renderer: Model_Renderer, machine_id: Machine_Id, placement: Arm_Placement) -> (posed: Posed_Model, angles: Arm_Joint_Angles)`: `draw_arm_colored`'s parts, then its two fingers, each `placement.transform * part * arm_voxel_scale()`; the angles from `arm_pose_at`.
  - `held_item_box :: proc(hand: [3]f32) -> (minimum, maximum: [3]f32)`: `draw_held_item`'s cube.
  - `instance_matrix_with_color :: proc(transform: matrix[4, 4]f32, color: rl.Color) -> matrix[4, 4]f32`: decision 4's row 3.
  - `pack_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, packed: ^[dynamic]matrix[4, 4]f32, groups: ^[Model_Layer][dynamic]Model_Instance_Group)`: `slice.stable_sort_by` on (machine, slot); per layer, per run of one piece whose layer has vertices, a group at `len(packed)` and the run's matrices with that layer's colour.
  - `unit_cube_mesh :: proc(allocator := context.temp_allocator) -> Model_Mesh`: 24 corners at ±0.5, outward normals, white, 36 indices counter clockwise seen from outside.
  - `cube_edge_mesh :: proc(color: rl.Color, allocator := context.temp_allocator) -> Model_Mesh`: that cube's 12 edges as 24 points, normals +y, the colour, no indices.
- Impure:
  - `emit_posed_model :: proc(renderer: Model_Renderer, frame: Model_Frame, machine_id: Machine_Id, kind: Machine_Kind, posed: Posed_Model, colors: [Model_Layer]rl.Color)`: with `model_frame_takes_instances` one `Model_Instance` a piece, else `draw_model_layers_colored(renderer, model_piece_layers(...), transform, colors)` a piece, in order.
  - `camera_frustum :: proc(camera: rl.Camera3D) -> render_frustum.Frustum`: `draw_field`'s two lines, inside `BeginMode3D`.
  - `set_model_instancing :: proc(renderer: Model_Renderer, instanced, tint, flat: bool)`: the three uniforms; nothing unless `instancing_ready`.
  - `begin_flat_instances :: proc(renderer: Model_Renderer, tint: bool)` and `end_flat_instances :: proc(renderer: Model_Renderer)`: `set_model_instancing(true, tint, true)`, the lit material with `colDiffuse` white, `begin_instanced_material`; then `end_instanced_material` and the three off. The slabs, their edges and the belt items draw between them.
  - `draw_scene_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, buffer: ^Instance_Buffer)`: nothing for none. Packs in temp memory, then `upload_instances_in_place`. The lit groups: `set_model_instancing(true, true, false)`, the lit material with `colDiffuse` white, `begin_instanced_material`, `matModel` (its location, when not -1) set to `rlgl.GetMatrixTransform()`, `draw_mesh_instances` a group, `end_instanced_material`. The emissive groups likewise with flat on. The three off at the end.
  - `draw_cast_model_instances :: proc(renderer: Model_Renderer, instances: []Model_Instance, buffer: ^Instance_Buffer, shadows: Sun_Shadow_Renderer)`: packs and uploads; `set_sun_shadow_instanced(true)`, `begin_instanced_material(shadows.material)`, every group of both layers, end, `set_sun_shadow_instanced(false)`.
  - `release_instance_buffer :: proc(buffer: ^Instance_Buffer)` (`unload_instanced_buffer(0, buffer.buffer)`, zeroed) and `release_field_instance_buffers :: proc(buffers: []Field_Instance_Buffers)`.

`src/render_instancing.odin` (0346's procedures)
- `bind_mesh_instances :: proc(mesh: rl.Mesh, instance_buffer: u32, first: int)`: 0346's binding (the mesh's array, locations 9 to 12 at the buffer from `first`, divisor 1), split out of `draw_mesh_instances`.
- `detach_mesh_instances :: proc()`: with the array still bound, `rlgl.DisableVertexAttribute` on 9 to 12, then `rlgl.DisableVertexArray()`.
- `draw_mesh_instances`: bind, 0346's draw, `count_draw_call()`, detach. 0346 leaves the instance attributes on the mesh's array, as raylib did; a machine's mesh is also drawn by `DrawMesh` (its ghost, the pod, the workbench), so it is detached.
- `GL_LINES :: 0x0001`; `Gl_Draw_Arrays_Instanced :: #type proc "c" (mode: u32, first, count, instance_count: i32)`.
- `load_draw_arrays_instanced :: proc() -> Gl_Draw_Arrays_Instanced`: `platform.glDrawArraysInstanced` on Android, else `cast(Gl_Draw_Arrays_Instanced)rl.glfwGetProcAddress("glDrawArraysInstanced")`, under `log_gl_info`'s `when`.
- `draw_mesh_line_instances :: proc(mesh: rl.Mesh, instance_buffer: u32, first, count: int, draw: Gl_Draw_Arrays_Instanced)`: bind, `draw(GL_LINES, 0, mesh.vertexCount, count)`, `count_draw_call()`, detach.

`src/platform/platform_android.odin`: `glDrawArraysInstanced :: proc(mode: u32, first, count, instance_count: i32) ---` in `foreign gles`.

`src/render_models.odin`
- `Uploaded_Machine_Model.bounds: [Model_Mesh_Slot]Model_Bounds`, set in `replace_machine_models` from the CPU meshes (`model_layers_bounds`).
- `Model_Renderer` gains:
  - `instanced_location, instance_tint_location, flat_location: i32` and `instancing_ready: bool`, set in `use_model_shader`: ready when the point lights are and the three are found, else the log line `models: the model shader has no instancing uniforms, machines draw one by one`;
  - `unit_cube, cube_edges: rl.Mesh`, uploaded in `init_model_renderer` (`upload_model_mesh` of `unit_cube_mesh()` and `cube_edge_mesh(FRAME_EDGE_COLOR)`), unloaded in `destroy_model_renderer`;
  - `draw_lines_instanced: Gl_Draw_Arrays_Instanced` from `load_draw_arrays_instanced` in `init_model_renderer`; nil logs `models: no glDrawArraysInstanced, the foundations' edges draw one by one`;
  - `generation: u64`, +1 in `replace_machine_models` after the swap and in `unload_model_meshes`.
- `Model_Frame` gains `view: ^Model_View`, `instances: ^[dynamic]Model_Instance` and `frames: ^Frame_Matrix_Table`, each nil for today's draw, a comment line each.
- `draw_posed_model :: proc(renderer: Model_Renderer, common: Entity_Common, machine: Machine, frame: Model_Frame, pose: Model_Pose) -> (shown: bool)`, the `model` parameter gone:
  1. the body is `model_frame_entity_matrix(frame, &frame.world.entities, common.frame) * model_transform(...)`;
  2. `pose_machine_model`, and false when `!model_frame_shows_box`;
  3. then `posed_model_light` and `emit_posed_model` with `brightness_color` of both.
  `draw_machine_model` and `draw_hatch` follow the signature.

`src/render_arm.odin`
- `arm_placement_on_frame :: proc(frame: Frame, frame_matrix: matrix[4, 4]f32, inserter: Inserter, machine: Machine, tick_rate: int) -> Arm_Placement`: today's body of `inserter_arm_placement`, which calls it with `find_frame` and `entity_frame_matrix`.
- `model_frame_arm_placement`: from `find_frame_matrix` when `frame.frames != nil` (the lights' gather reads it too).
- `draw_placed_arm` goes; its caller becomes `draw_inserter_model`. `draw_arm` and `draw_arm_colored` stay for the workbench and the ghosts.

`src/render_entities.odin`
- `draw_inserter_model`:
  1. `model_frame_arm_placement`, `pose_arm`;
  2. while the hand holds an item (`arm_shows_held_item`), its `held_item_box` grows the box;
  3. a culled arm returns true (the model exists);
  4. else today's tint and glow, `emit_posed_model`, and `draw_held_item` at the hand.
- Fallbacks and decorations, culled by `model_frame_shows_box` with the box of where they are drawn:
  - `draw_entity_cells` without a model: `[origin, origin + size]` under `model_frame_entity_matrix`, also the matrix it pushes;
  - `draw_inserter` without a model: x and z widened by `reach` each way, one cell high, under that matrix;
  - `draw_drill`'s bar and arrow, which today's code draws in raw cells without the frame's matrix: `[origin − 0.1, origin + size + {0.1, 0.2, 0.1}]`, raw;
  - `draw_launch_pad`'s fallback platform, tower and rocket, raw likewise: the footprint up to `LAUNCH_PAD_PLATFORM_HEIGHT + ROCKET_HEIGHT + ROCKET_ASCENT_HEIGHT` above its bottom.

`src/render_sun_shadows.odin`: `model_frame_draws_entity` reads `model_frame_entity_matrix(frame, entities, common.frame)`; `set_sun_shadow_instanced`'s comment names the machines and the slabs.

`src/render_frames.odin` (header: decisions 6 to 8)
- `FOUNDATION_BRICK_CELLS :: 32`.
- Types:
  - `Foundation_Cell :: struct {frame: Frame_Id, cell: World_Coordinate, color: rl.Color}`;
  - `Foundation_Brick :: struct {frame: Frame_Id, brick: [3]i32, minimum, maximum: [3]f32, first, count: int}`, the box in cells from the lowest cell to the highest plus 1;
  - `Field_Foundations :: struct {built, uploaded: bool, revision, models_generation: u64, cells: [dynamic]Foundation_Cell, bricks: [dynamic]Foundation_Brick, instances: [dynamic]matrix[4, 4]f32, buffer: Instance_Buffer}`.
- Pure:
  - `foundation_cell_instance :: proc(cell: World_Coordinate, color: rl.Color) -> matrix[4, 4]f32`: to the cell's centre, scaled by `FRAME_CELL_FILL`, row 3 the colour.
  - `foundation_brick_of :: proc(cell: World_Coordinate) -> [3]i32`: `floor_divide` on each axis.
  - `foundation_cell_before :: proc(first, second: Foundation_Cell) -> bool`: frame, brick (z, y, x), cell (z, y, x).
  - `build_foundation_bricks :: proc(entities: ^Entities, machines: Machine_Registry, allocator := context.temp_allocator) -> (cells: []Foundation_Cell, bricks: []Foundation_Brick, instances: []matrix[4, 4]f32)`: `draw_frames`' occupant filter (a `.Foundation` handle whose machine is a `.Foundation`, on a known frame), `foundation_slab_color`, sorted, a brick per run.
  - `refresh_field_foundations :: proc(foundations: ^Field_Foundations, entities: ^Entities, machines: Machine_Registry, models_generation: u64) -> (changed: bool)`: false when built and both stamps are equal. Else it builds again; when the cells, bricks or instances differ bytewise from the stored ones it replaces them, clears `uploaded` and returns true; the stamps and `built` are set either way.
- Impure:
  - `update_field_foundations :: proc(foundations: ^Field_Foundations, entities: ^Entities, machines: Machine_Registry, models_generation: u64)`: refresh, then `upload_instances_in_place` while not `uploaded`. Called by `prepare_field_frame` and `stream_planet_preview`, before any pass of the frame.
  - `draw_field_foundations :: proc(foundations: ^Field_Foundations, models: Model_Renderer, frame: Model_Frame, entities: ^Entities, cast: ^Sun_Shadow_Renderer)`: a brick shows when `model_frame_shows_box` passes its box under `model_frame_entity_matrix` of its frame. Per frame with shown bricks, inside `rlgl.PushMatrix` and `MultMatrixf` of its matrix:
    - instanced, the sun's pass (`cast` set, `cast.instanced_location != -1`): `set_sun_shadow_instanced(true)`, `begin_instanced_material(cast.material)`, `draw_mesh_instances(models.unit_cube, ...)` a brick, end, false;
    - instanced, the scene (`models.instancing_ready`): `begin_flat_instances(models, true)`, the slabs a brick, end; then, with `models.draw_lines_instanced`, `begin_flat_instances(models, false)` and `draw_mesh_line_instances(models.cube_edges, ...)` a brick, else the brick's cells' `DrawCubeWiresV` as today;
    - otherwise, or before the first upload, the brick's cells through `draw_frame_cell`, as today.
  - `release_field_foundations :: proc(foundations: ^Field_Foundations)`.
- `draw_frames` goes; `draw_frame_cell` stays.

`src/render_belt_runs.odin`
- `Belt_Run_View :: struct {shown, found: bool, ups: [2][3]i64, pitch_metres: f32}`; `Belt_Run_Draw :: struct {view: ^Model_View, frames: ^Frame_Matrix_Table, models: Model_Renderer, items: ^Instance_Buffer}`, zero for today's draw.
- Pure:
  - `belt_run_box :: proc(curve: Belt_Run_Curve, pitch_metres: f32) -> (minimum, maximum: [3]f32)`: the polyline's points in metres, widened by a pitch. Everything drawn lies within 0.71 of a pitch of its section's point: half a pitch across, the tube's top half a pitch up, an item 0.35 across and 0.23 up.
  - `belt_pole_box :: proc(bottom, top: [3]f32) -> (minimum, maximum: [3]f32)`: widened by `BELT_RUN_POLE_RADIUS_METRES`.
  - `belt_run_facts :: proc(table: ^Frame_Matrix_Table, entities: ^Entities, run: Belt_Run) -> (ups: [2][3]i64, pitch_metres: f32, found: bool)`: `belt_run_frame_facts` through the table when set.
  - `belt_run_views :: proc(entities: ^Entities, draw: Belt_Run_Draw, allocator := context.temp_allocator) -> []Belt_Run_View`: by the runs pool's index, each alive run's facts and `model_view_shows(draw.view, belt_run_box(...))`.
  - `belt_run_item_cube :: proc(entities: ^Entities, items: Item_Registry, views: []Belt_Run_View, line: Belt_Line, lane: Belt_Lane, entry: Lane_Item) -> (centre: [3]f32, size: f32, color: rl.Color, found: bool)`: `draw_belt_run_item`'s arithmetic; not found on a run not shown.
  - `belt_item_instance :: proc(centre: [3]f32, size: f32, color: rl.Color) -> matrix[4, 4]f32`: translated, scaled by `size`, row 3 the colour.
- `draw_belt_runs(renderer, entities, machines, items, tick, tick_rate, draw: Belt_Run_Draw)`:
  - the views first; a run is drawn only when shown, a pole only when its box shows (`draw_belt_poles(entities, machines, draw)`);
  - `draw_belt_run_items(entities, items, views, draw)` collects `belt_item_instance`s in temp memory and draws them in one instanced draw when `draw.models.instancing_ready && draw.items != nil` (`upload_instances_in_place` into `draw.items`, `begin_flat_instances(models, true)`, `draw_mesh_instances(models.unit_cube, ...)`, end); else `rl.DrawCube` an item, as today.

`src/render_field.odin`: `FIELD_VIEW_SLOTS :: 4` (0346's `FIELD_TREE_VIEWS`, renamed and moved). `Field_Renderer` gains `foundations: Field_Foundations` and `instance_buffers: [FIELD_VIEW_SLOTS]Field_Instance_Buffers`, both released in `destroy_field_renderer`.

`src/loop_field_session.odin`
- `Field_Scene.view_slot` (0346's `tree_view`); the assert reads `FIELD_VIEW_SLOTS`.
- `draw_field_scene`:
  - first, `frames := frame_matrix_table(&scene.state.world.entities.frames)` and `scene.frame.frames = &frames`, before the lights' gather;
  - `view := Model_View{frustum = camera_frustum(camera), eye = camera.position, distance_metres = scene.lights.haze.fog_end, transform = scene.pod_transform.? or_else linalg.MATRIX4F32_IDENTITY}`;
  - a copy `machines_frame := scene.frame` with `view = &view` and, when `scene.models.instancing_ready`, `instances` a temp list;
  - inside the pod's push: `draw_field_foundations(&scene.renderer.foundations, scene.models, machines_frame, &world.entities, nil)`, `draw_entities(..., machines_frame)`, `draw_scene_model_instances(scene.models, instances[:], &buffers.models)`;
  - `draw_belt_runs(..., Belt_Run_Draw{view = &run_view, frames = &frames, models = scene.models, items = &buffers.items})`, `run_view` being `view` with the identity transform, since runs draw outside the pod's push.
- `draw_field_sun_shadows`: `casters.frame.frames` its own table; `casters.frame.instances` a temp list when `shadows.instanced_location != -1`; `draw_field_foundations(..., casters.frame, &world.entities, shadows)` in place of `draw_frames`; after `draw_entities`, `draw_cast_model_instances(scene.models, ..., &buffers.cast_models, shadows^)`.
- `prepare_field_frame`: `update_field_foundations(&renderer.foundations, &session.simulation.world.entities, frame_simulation_content(state).machines, state.presentation.model_renderer.generation)` after the mesh uploads.

`src/loop_planet_preview.odin`: `stream_planet_preview` calls `update_field_foundations` with `planet_preview_content(preview).machines` and `preview.models.generation`.

Shaders
- `data/shaders/model.vs`: `in mat4 instanceTransform;`, `uniform float instanced_on;`, `uniform float instance_tint_on;`, `out vec4 fragment_tint;`. The model matrix is `mat4(1.0)` and the tint `vec4(1.0)` unless instanced. Instanced, the model is `instanceTransform` with row 3 (`[0u][3u]` to `[3u][3u]`) rebuilt, and the row's first three are the tint when `instance_tint_on`. Then `local = model * vertex`, the world position `matModel * local`, the normal `mat3(matModel) * (mat3(model) * vertexNormal)` and `gl_Position = mvp * local`. Header comment.
- `data/shaders/model.fs`: `in vec4 fragment_tint;`, `uniform float flat_on;`; `base = fragment_color * colDiffuse * fragment_tint`; with `flat_on` the colour is `base` and the shader returns. Header comment.
- `data/shaders/sun_shadow.vs`: comment only (the machines' and the slabs' instances come the same way).

Part A, the 1000 machine view
- `tools/frame_profile_views.sjson`: `factory_large = {copies = [11, 7], back_metres = 45, up_metres = 25}`, with a comment line.
- `tools/frame_profile.py`:
  - after `factory` in one viewport (0342's order, step 5), the copies are built under `pause`, as the factory is. Copy (i, j), for i below 11 and j below 7 except (0, 0), is the factory's pad, machines and inserts moved `i × (pad.x + gap)` cells along the frame's x and `j × (pad.z + gap)` along its z;
  - a copy's refused line is counted and skipped, not failed; the notes column says `placed <m> of 1001 machines, <f> of 36036 foundations`;
  - `copies` outside 1 to 32 on either axis stops the script with exit 2 and the line;
  - the target is the copies' middle cell one row above the pad (from the pod's frame's `query frames` line: origin, axes, pitch); the stand is the target less `back_metres` along the frame's forward plus `up_metres` along its up;
  - `factory_large` runs in one viewport at 512 m and 1024 m.

### Memory and its lifetime

- Per pass: the instance list (80 bytes an instance), the packed matrices and the groups, in temp memory.
- Per viewport and pass: one GL buffer, 64 bytes an instance, grown in 0346's powers of two.
- The foundations: 64 bytes a cell in GL and about 84 on the CPU (cell, brick share, matrix): 2.3 MB and 3 MB for part A's 36,036 cells.
- The foundations' arrays and buffer change only in `update_field_foundations`, before any pass of the frame; a pass writes only its own buffer, before its own draws. All of it goes with the field renderer (`destroy_field_renderer`, from `stop_field_presentation` and the preview's teardown, between frames), the cube meshes with the model renderer.

### Tests

`src/render_model_instances_test.odin`
- `test_a_frame_matrix_table_finds_every_frame`: frames 1, 3 and 4 (2 added and removed).
  - Each found entry's matrix equals `frame_render_matrix` of its record.
  - Ids 2 and 99: not found, the identity.
  - `BLOCK_FRAME`: found, the identity, pitch `BLOCK_FRAME_PITCH_MILLIMETRES`.
  - `model_frame_entity_matrix` gives the same with the table as without.
- `test_the_view_cull_takes_the_frustum_and_the_haze_end`: 0346's `tree_test_frustum({0, 8000, 0}, 0)`, distance 512, a 1 m box:
  - 10 m ahead: shown; 10 m behind: not;
  - 600 m ahead: not, and shown at distance 0;
  - nearest 500 m and farthest 520 m: shown;
  - 10 m behind under a transform moving it 20 m ahead: shown.
- `test_a_posed_model_appends_what_it_would_draw`: a `Model_Renderer` without GL (meshes with vertex counts, bounds set) and a hatch with an iris of 3 blades, on the block frame, `Model_Frame{world = &world, open_sky = true, day_factor = 1, sky_tint = 1, instances = &list}`:
  - `draw_posed_model` returns true and appends 4 instances, the body then 3 blades;
  - their transforms equal `model_transform(...)` and `body * motion_part_transforms(...)`;
  - their colours equal `brightness_color` of `posed_model_light`;
  - with a view looking away it returns false and appends none;
  - `model_frame_takes_instances` is false for `.Pod`.
- `test_a_posed_box_holds_a_slid_part_and_a_reaching_arm`:
  - a 2 by 2 by 2 body whose part slides 12 cells along x, at open fraction 1: every corner of the part's bounds under its transform lies inside the box, which reaches 12 cells past the body's;
  - an arm of reach 4 on a 500 mm frame (`arm_dimensions_on_frame(4, 500)`, `arm_entity_transform`) at fractions 0, `ARM_GRAB_END`, 0.25, `ARM_DROP_FRACTION` and 0.75: 7 pieces; the hand (`arm_hand_point`) and, while it holds, its `held_item_box` lie inside the box; at `ARM_GRAB_END` and `ARM_DROP_FRACTION` the hand lies more than 3 cells outside the footprint, past `sun_shadow_entity_box`'s one cell margin;
  - `model_layers_bounds` of empty layers is inverted.
- `test_model_instances_pack_by_layer_and_piece`: instances of machine 2 body, machine 1 part, machine 2 body, machine 1 body, machine 1 part; machine 1's body has no emissive mesh.
  - Lit groups: 1 body (1), 1 part (2), 2 body (2); emissive: 1 part (2), 2 body (2); 9 matrices.
  - The groups' meshes are the layers' (vertex counts as tags).
  - Rows 0 to 2 equal the transforms; row 3 is the layer's colour over 255, and 1.
  - The two machine 2 instances keep their order.
- `test_the_unit_cube_and_its_edges`:
  - `unit_cube_mesh`: 24 positions at ±0.5, 36 indices, every triangle's winding normal pointing away from the centre, all white;
  - `cube_edge_mesh`: 12 segments, each 1 long along one axis, every edge of the cube once, the colour given.

`src/render_frames_test.odin`
- `test_foundation_bricks_group_the_cells_by_frame_and_brick`: `lay_test_pad(&entities, machines, 0, 0, {-1, 0, 0}, {32, 0, 1})`, a `stone_cutting_table` (the foundations' pool, not a foundation) at (2, 1, 0) and a `wooden_chest` at (5, 1, 0) by `place_on_frame`, a second pad of one cell 50 m away.
  - Bricks: x −1 (2 cells), 0 (64), 1 (2), then the second frame's (1); 69 instances.
  - No instance for the table's or the chest's cells.
  - Each instance is its cell's centre, scaled 0.96, with `foundation_slab_color` of `stone_brick_foundation` over 255 in row 3.
  - The boxes are in cells: brick 0's is (0, 0, 0) to (32, 1, 2).
  - The order is `foundation_cell_before`'s.
- `test_the_foundation_cache_rebuilds_only_on_a_change`, `refresh_field_foundations` on that pad:
  - the first call is a change, a second is not;
  - `set_frame_pose` of the pad's frame moves the revision and is not a change;
  - a cell vacated and another occupied (`remove_entity`, `place_on_frame`) is;
  - the generation moved over the same machines is not;
  - the foundation's `color` changed with the generation moved is.

`src/render_belt_runs_test.odin`
- `test_a_belt_run_box_holds_its_surface_tube_and_items`: the quarter turn run of `test_a_run_with_facings_at_right_angles_is_a_quarter_turn` (its helpers). At every step, from `belt_run_section`: the surface's corners, the sides' bottoms, the tube's top and an item's cube corners on both lanes lie inside `belt_run_box`.
- `test_a_belt_item_instance_is_its_cube`: the translation is the centre, the diagonal the size, row 3 the colour over 255, and 1.

Mark `// slow` what `build/test_times.tsv` shows at 1 s or more. `shader_source_test.odin` covers the shaders' literals and words unchanged.

### Docs

- `doc/presentation.md`:
  - The field session, the scene bullet: the foundations (`draw_field_foundations`, the bricks, the edges as lines), the machines culled and instanced after `draw_entities`, the pod drawn alone, the runs and poles culled, the items in one draw.
  - Light on the field: the haze bullet's unhazed list adds that these are not drawn past the haze's end; the sun's shadow bullet: the foundations' bricks in the casters' box, the machines also by their posed box, instanced.
  - Machine models: a bullet on the instanced path (`Model_Instance`, the model shader's three uniforms, the emissive layer in flat mode, the pod, the ghosts and the workbench by `DrawMesh`, `instancing_ready`); `draw_frames` becomes `draw_field_foundations` where named.
  - Runs: the culling and the items' draw.
- `doc/code_map.md`: the new file under presentation; the lines of `render_frames.odin`, `render_belt_runs.odin`, `render_entities.odin` and `render_models.odin`, `render_field_cover.odin` and `render_instancing.odin`; the counts `tools/code_graph.py --check` reports.
- `doc/android.md`, the `platform_android.odin` bullet: `glDrawArraysInstanced` beside `glGetString`.
- `doc/build.md`, Frame profile (0342): `factory_large`.

### Hand-back check

- Memory a frame draws from: Memory and its lifetime. The tests read what the draws read (bricks, instances, packed matrices, groups).
- A start-up load that can fail: a model shader without the uniforms and a missing `glDrawArraysInstanced` fall back to today's draws, one log line each.
- A list that grows: the lists are bounded by the entities and cells, the buffers grow in powers of two, nothing reaches the HUD.
- A number parsed from text: the views file's `copies`, range checked by the script.
- Tests touch no state: in memory, no GL.
- Not applicable: file writes; the save, record and network layouts (nothing saved, hashed or sent changes: the diff touches no simulation, world or save file); shared budgets; UI audit cases.

### Questions to the main agent

1. Decision 3: past the view distance the emissive glows, slabs, runs, poles and belt items, unhazed today, are no longer drawn. Accept, or the frustum alone?
2. 0163 is not needed: this item's list is per pass and serves the draws only. Keep 0163 its own item and drop "Builds on 0163" above?
3. Part A here, with the before run taken by this branch's script against `main`'s release binary (`--binary`), or a small item landing before 0347?

### Decisions (main agent, 2026-11-11)

1. Question 1: the scene pass culls at the haze's end as designed. Until 0360 hazes the slabs, runs and belt items they end there on a step; 0360 lands after this item and removes it.
2. Question 2: 0163 stays its own item and this item does not build on it.
3. Question 3: part A stays here. The before figures come from this branch's script against `main`'s binary (`--binary`), taken by the main agent in the night window.
4. The field session does not draw the fluid and the power machines at all, and the drill's bar and the launch pad's fallback draw in raw cells: 0362 holds both, not this item. This item's `factory_large` view therefore places only machines the field session draws.
5. Decision 9's three findings for a moving frame are 0357's to solve; 0361's design was given them.
6. Implemented after 0342 and 0346 have landed, in their stream.

### Deviations (implementation, 2026-11-12)

1. No `Model_Renderer.generation`: 0348's `Model_Renderer.revision` (moved in `unload_model_meshes`, which `replace_machine_models` and `use_machine_models` call) is decision 8's counter, and `Field_Foundations.models_revision` its stamp. The bricks are rebuilt on the same two counters the kept shadow map's key reads, so a rebuild always falls on a frame whose kept map recentres.
2. `Field_Instance_Buffers` holds a fourth buffer, `kept_cast_models`, for 0348's still part, drawn only on a kept map's redraw. `cast_models` takes the moving part or the whole pass every frame, so no buffer is written twice in a frame. The foundations draw in the still part and the whole pass, never the moving part.
3. Names: `Frame_Matrix_Entry.transform` (`matrix` is a keyword), `draw_field_foundations`' parameter `shadows` (`cast` is one), `model_slot_bounds` (`model_layers_bounds` exists in `model_triangle_mesh.odin`).
4. `render_instancing.odin` imports `platform` with `@(require)`, since only the Android branch of `load_draw_arrays_instanced` reads it.
5. `draw_vessel_part`'s fallback (0361, landed after the design) is culled as `draw_entity_cells`' is.
6. Part A: the copies hold only the machines the field session draws (decision 4), named by the views entry's `machines`, so the note reads 621 machines (the factory's 13 and 8 a copy) with the 36036 foundations. The gap the specification left open is `FACTORY_COPY_GAP_CELLS` (2). The copies step against the frame's right, since along it the leaning pad's plane falls 0.26 m a metre (the views file's probe) and the copies would sink under the ground. The target is the middle of the copies' span at the centre of the row over the pads.
