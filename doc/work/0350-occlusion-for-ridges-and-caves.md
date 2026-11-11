# 0350: Occlusion for ridges and caves

Status: designed (2026-11-11)

The frustum keeps far terrain nodes and tree tiles that a ridge hides, and after 0327 the finest nodes mesh cave walls under the ground the eye stands on (`work/performance_research_0340.md`, 2.4). After 0327 and 0339.

## Goal

What a ridge or the ground hides is not drawn, and nothing pops into view at a corner.

## Controls

None.

## Change

- Ridges: last frame's visibility for nodes and far tree tiles (occlusion queries on their boxes, or a depth pyramid), what was visible drawn first.
- Caves: per chunk, which faces connect through open space, computed on the workers with the mesh, and a walk from the eye's chunk through the connected faces, as Minecraft's cave culling does.
- The phone's GLES path and the Windows build keep working where a query is missing.

## Verify

- The checks and the suite, with a test of the connectivity on hand-made chunks.
- 0342's table: the GPU's time and the drawn counts in the ridge, forest and cave views, before and after.
- A capture series round a corner and out of a cave mouth with no pop, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `701be70` (0341, 0343), the 0339 worktree at `ac3861a` (0327's caves, 0337, 0339) and the specifications of 0342 (`Field_Scene.profile`, `count_frame`, `Frame_Counter`, `count_draw_call`, `GL_QUERY_RESULT`, `GL_QUERY_RESULT_AVAILABLE`), 0344 (`run_field_job`'s look step), 0346 and 0347 (`Field_Scene.view_slot`, `FIELD_VIEW_SLOTS`, `viewport_index`), 0348 (`apply_field_mesh`'s hash), 0349 (the draw box `Field_Node_Render.minimum, maximum`, `draw_field` for the terrain only, `draw_field_passes`) and 0354 (`balance_field_selection` inside `select_field_nodes`). It is implemented after all of them have landed. Presentation only: the openness is mesh job output; the walk and the queries read the frame's selection, the meshes and the camera. Nothing reaches the tick, the hash or the save, and nothing reads the frame time.

### Decisions

1. **Two culls in series, both conservative.** First, the cave walk on the CPU, on every platform: it keeps the frustum's nodes that a straight ray from the eye can reach through open cells. Then, where conditional rendering exists, GPU occlusion queries test the rest against the depth already drawn in this frame. A node is hidden only when one of the two proves that no ray reaches it, and every failure mode falls back to drawing.
2. **The queries decide within the frame; last frame's answers only set the order.**
   - Each viewport first draws the nodes and far tiles that its last answered queries saw, each inside an occlusion query on its own draw.
   - It then tests the boxes of the rest (`GL_ANY_SAMPLES_PASSED`, colour and depth writes off, culling off) and draws each of them inside `glBeginConditionalRender(id, GL_QUERY_WAIT)`, so the GPU skips a draw only when its box passed no sample.
   - The results are read without waiting, one to three frames later, and only move a node between the two lists.
   - Rejected: skipping draws by last frame's results, since a node round a corner pops in a frame late, which is the defect the item names. Reading the results inside the frame makes the CPU wait for the GPU every frame. A Hi-Z pyramid needs a mip chain pass and a read back, is a frame late without reprojection, and has the same gap on GLES.
3. **The box.**
   - For a node, 0349's draw box (terrain, water and cover). For a far tile, the box `select_far_tiles` tests: the bases' box widened by the model extent.
   - Widened by 0.1 m plus 0.004 m per metre of distance. That is 6 steps of a 24 bit depth at 1024 m with the near plane at 0.1 m (0349's decision 3), so after quantisation the box's front lies in front of every fragment inside it. The test uses `GL_LEQUAL`, rlgl's default.
   - A box within 1 m of the eye is never tested, since the near plane (0.1 m) would clip its front; it draws unconditionally. At the widest view (110 degrees plus the 15 degree sprint kick) in a 32:9 split, the near rectangle lies within 0.72 m of the eye.
4. **Platforms.**
   - Conditional rendering is core since GL 3.0, so it is in raylib's 3.3 context on Linux, Windows and the Steam Deck. The entry points come through `rl.glfwGetProcAddress`, as `log_gl_info` gets `glGetString`.
   - GLES 3.0 has occlusion queries but no conditional rendering. On the phone the GPU part is therefore off without trying, and the walk alone culls.
   - A desktop GL that lacks one of the eight entry points (a translation layer) turns the GPU part off with one log line. So do 32 query sets dropped in a row.
5. **Openness on the workers.** A mesh job computes, from the grid it meshes, which faces of its node an open path joins (`Field_Node_Links`, 6 bytes). For a finest node it also keeps the ground bit of each of the node's 33³ samples, for the eye's test (decision 8).
   - A cell (8 samples, 0 to 31 on each axis inside the node) is solid when its 8 corners are ground (`field_sample_is_ground` of the terrain density). Water is open.
   - The open cells are flood filled, 6-connected. Each component notes which faces' outer layers of cells it touches, and the faces it touches all link to each other, so a face links to itself when its layer holds an open cell.
   - Why this holds: the surface nets mesh lies only in cells with corners on both sides (a vertex sits inside its cell, a quad inside the four cells round its edge). So a ray that stays in air never crosses a solid cell's interior, and between linked faces the walk lets it through.
   - A uniform grid skips the fill: air links every face, ground links none.
   - Cost: 32,768 cells and one fill per job, against a finest job's 1.8 ms mesh. The nightly meshing report measures it.
6. **The walk** (`walk_field_visibility`, per viewport, from the camera's position).
   - It starts in the finest node holding the eye, which it may leave through any face.
   - From a node entered through faces E, it leaves through any face G that `links[F]` holds for some F in E. It enters the selected nodes that share G's area, at any level, when two things hold: the neighbour's entering face links to itself (its layer has an open cell), and the neighbour's cube meets the frustum or lies within 1 m of the eye.
   - Straight rays only. A node remembers the directions moved to reach it (one face per direction), and a move opposite to one of them is refused, since a straight line's coordinates change monotonically.
   - A node reached again merges: its entries by union, its directions by intersection. Its state then allows every move that any path to it allows, and each node is expanded at most 13 times.
   - A node without openness yet (not meshed) links every face: it draws nothing, so rays pass through it.
   - Rejected: Minecraft's breadth first search that visits each chunk once (Checchi, part 2). Its result depends on which path arrives first, and it can refuse a move that another path allows.
7. **Geometry reaching into a neighbour.** A node's mesh leaves its cube by up to 4.6 of its cells: its cells at −1, the flaps into coarser nodes, the curtains on its face plane, a coarser node's lid over a finer one. A candidate the walk did not reach is still drawn when its draw box reaches into the cube of a reached node, since a point of its geometry inside a reached cube is reachable by the rays the walk followed into that cube. The nodes checked are those met by up to three hops across the sides where the draw box reaches its face plane or past it: the face neighbours, then their neighbours across the other such sides, so the edge and corner neighbours are covered.
8. **Where the walk stands down.** There is no walk, and every frustum node is drawn, when any of these holds:
   - the eye's finest node is not selected;
   - that node has no ground bits yet;
   - the eye's cell (the 8 samples round the eye in that node's drawn grid) is not all air. An eye under the ground sees through the back faces: flying through the terrain, a camera clipped into a wall, a dig not yet meshed.

   Outside the shell (the arrival's fall), no finest node holds the eye.
9. **Past the view.** A face can open onto ground that the selection leaves out (in the shell, so past the view's last distance): the graph's `beyond`. A ray leaving through such a face stays past the last distance. Once the walk leaves through one, every candidate whose draw box reaches within 1 m of the last distance is drawn. After 0354 those parts show only the end colour, but they still hide the sky's dome behind them.
10. **The premise.** The walk is exact for terrain whose meshes close (the skirts and curtains of 0321, the balance of 0354). A ray that slips through a seam into the ground sees through back faces, and what it shows there may change once the walk hides the node behind; both pictures are a seam defect. The same holds for 0327's tunnel end at the level 2 seam, if it shows as a hole (question 3).
11. **Cost.**
    - The walk graph (each node's face neighbours, beyond flags and cube) is rebuilt in `prepare_field_frame` only when the selection, the shell or the last distance changed. That is map lookups, about 9,000 at 600 nodes, on the frames the eye crosses a node's distance.
    - The walk itself is array work over the reached nodes, per viewport.
    - The GPU part adds three calls per drawn node, and one box draw into a shared vertex buffer per tested node or tile.
12. **No data key.** The near distance, the margins and the hop depth follow from the geometry and the depth buffer, not from taste.
13. **Counters (0342), appended to `Frame_Counter`.**
    - `Walk_Culled_Nodes`: the frustum's nodes with a render that the walk dropped, counted in `draw_field`.
    - `Occluded_Nodes` and `Occluded_Tiles`: box queries answered 0, so the GPU skipped the draw. They are counted in the frame that reads them, one to three frames late.
14. **Acceptance by 0342's table**, one viewport at 512 m and 1024 m, before (`main` without this item) and after:
    - In the cave view, `count walk_culled_nodes` is above 0, and `count terrain_nodes` and `gpu terrain` fall.
    - In the ridge and forest views, `count occluded_nodes` and `count occluded_tiles` are above 0, and `gpu terrain` and `gpu trees` fall.
    - `cpu terrain` rises by no more than the walk's share, which the report gives.

### Files and procedures

`src/world_field_openness.odin` (new, world cluster). Header: the openness of a node for the cave walk (0350, doc/presentation.md, Field meshes, Occlusion).
- `FIELD_GROUND_BIT_SIDE :: FIELD_GRID_CELLS + 1`, `FIELD_GROUND_BIT_WORDS :: (FIELD_GROUND_BIT_SIDE * FIELD_GROUND_BIT_SIDE * FIELD_GROUND_BIT_SIDE + 63) / 64`, and `EVERY_FIELD_FACE`, moved here from `world_field_lod_test.odin` (its comment: every face; the tests keep using it).
- `Field_Node_Links :: [Field_Face]Field_Faces`: per face, the faces an open path from its layer reaches (itself when its layer holds an open cell).
- `Field_Node_Openness :: struct {links: Field_Node_Links, ground: [dynamic]u64}`: `ground` holds the samples 0 to `FIELD_GRID_CELLS` of a finest node (`FIELD_GROUND_BIT_WORDS` words, x fastest), and is empty above level 0.
- `field_unknown_links :: proc() -> Field_Node_Links`: every face to every face.
- `field_opposite_face :: proc(face: Field_Face) -> Field_Face`: `Field_Face(u8(face) ~ 1)`.
- `field_ground_bit_index :: proc(local: [3]i32) -> int` (each axis 0 to `FIELD_GRID_CELLS`) and `field_ground_bit :: proc(ground: []u64, local: [3]i32) -> bool`.
- `field_grid_ground_bits :: proc(grid: ^Field_Grid, allocator := context.allocator) -> [dynamic]u64`: `field_sample_is_ground(grid.density[field_grid_index(local)])` for each local sample 0 to `FIELD_GRID_CELLS`.
- `field_cell_is_solid :: proc(ground: []u64, cell: [3]i32) -> bool`: its 8 corners are ground.
- `field_cell_layers :: proc(cell: [3]i32) -> Field_Faces`: the faces whose outer layer of cells holds the cell (cell 0 on an axis gives the negative face, `FIELD_GRID_CELLS - 1` the positive one).
- `field_node_links :: proc(ground: []u64) -> Field_Node_Links`.
  - Shortcut: every bit 0 gives `field_unknown_links()`, and every sample bit 1 gives all empty.
  - Otherwise: a visited `[]bool` of the 32³ cells and a queue `[dynamic]i32`, both in the temp allocator. Each open, unvisited cell starts a fill over its 6 face neighbours inside the node, and `touched` gathers `field_cell_layers` of every cell of the component. At the end of each fill, `links[face] += touched` for every face in `touched`.
- `field_node_openness :: proc(grid: ^Field_Grid, level: i32, allocator := context.allocator) -> Field_Node_Openness`: the bits (kept at level 0, otherwise taken in the temp allocator) and `field_node_links` of them.
- `destroy_field_node_openness :: proc(openness: Field_Node_Openness)`: `delete(openness.ground)`.

`src/world_field_streaming.odin`
- `Field_Job_Result.openness: Field_Node_Openness`. The comment: a Mesh result carries its grid's openness (0350).
- `run_field_job`, `.Mesh`: once the grid is complete (after `generate_field_grid` and 0344's look), `result.openness = field_node_openness(grid, job.node.level)`.
- `free_field_job_result`: `destroy_field_node_openness(result.openness)`.

`src/render_field_walk.odin` (new, presentation cluster). Header: the cave walk (0350), decisions 6 to 9 in a few lines.
- Constants:
  - `FIELD_WALK_NEAR_METRES :: 1.0`: nodes this near the eye pass the frustum, and boxes this near are not tested (decision 3).
  - `FIELD_WALK_SLACK_METRES :: 0.01`: box contacts.
  - `FIELD_WALK_DISTANCE_SLACK_METRES :: 1.0`: decision 9.
- `Field_Walk_Face :: struct {first, count: i32, beyond: bool}`: the face's neighbours in `neighbours[first:][:count]`, and `beyond` when part of it opens onto uncovered ground in the shell.
- `Field_Walk_Graph :: struct`, kept in the renderer across frames:
  - `selection: [dynamic]Field_Node`, `shell_inner, shell_outer, last_distance: i64`, `spacing_millimetres: int` (what it was built for);
  - `index: map[Field_Node]i32` (position in the selection), `holds_finer: map[Field_Node]struct{}` (every ancestor up to `FIELD_COARSEST_LEVEL` of a selected node);
  - `faces: [dynamic][Field_Face]Field_Walk_Face`, `neighbours: [dynamic]i32`, `cubes: [dynamic][2][3]f32` (each node's `field_node_box` in metres through `world_position_to_metres`).
- `Field_Walk :: struct {walked, beyond: bool, reached: []bool, eye_metres: [3]f32, last_distance_metres: f32}`.
- `update_field_walk_graph :: proc(graph: ^Field_Walk_Graph, selection: []Field_Node, view: Field_View)`:
  - Nothing when `slice.equal(graph.selection[:], selection)` and the shell, `view.level_distances[FIELD_COARSEST_LEVEL]` and the spacing are the built ones.
  - Otherwise every container is cleared and refilled: the index, holds_finer, the cubes, then for each node and face `field_walk_face_neighbours`.
  - Called from `prepare_field_frame`.
- `field_walk_face_neighbours :: proc(graph: ^Field_Walk_Graph, node: Field_Node, face: Field_Face, out: ^[dynamic]i32) -> (beyond: bool)`: the region across the face at the node's level, resolved in this order:
  - selected: it is the neighbour;
  - in `holds_finer`: `field_walk_finer_neighbours`;
  - else its ancestors up to `FIELD_COARSEST_LEVEL`, and the first selected one is the neighbour;
  - else uncovered, and `beyond` is `field_box_in_shell` of its box.
- `field_walk_finer_neighbours :: proc(graph: ^Field_Walk_Graph, region: Field_Node, face: Field_Face, out: ^[dynamic]i32) -> (beyond: bool)`: the region's 4 children on the side facing the node, in `field_corner_offset` order; each is resolved as selected, holds finer (recursing), or uncovered (in shell: beyond).
- `destroy_field_walk_graph :: proc(graph: ^Field_Walk_Graph)`.
- `field_eye_in_open_air :: proc(openness: map[Field_Node]Field_Node_Openness, eye: World_Position, spacing_millimetres: int) -> (node: Field_Node, open: bool)`:
  - the sample at or below the eye (`world_position_to_sample`), its finest node (`floor_divide` by `FIELD_CHUNK_SIZE`), the local cell;
  - open when the node's openness has ground bits and the cell's 8 corners are not ground.
- `walk_field_visibility :: proc(graph: ^Field_Walk_Graph, openness: map[Field_Node]Field_Node_Openness, eye: World_Position, frustum: Maybe(render_frustum.Frustum), allocator := context.temp_allocator) -> Field_Walk`:
  - Not walked when `field_eye_in_open_air` fails or the node is not in `graph.index`.
  - Per position: links (the openness's, else `field_unknown_links()`), entries, moved (`Field_Faces` as directions), reached and queued, and a work list.
  - The start: reached, entries `EVERY_FIELD_FACE`, moved `{}`, links unknown.
  - Popping i: for each G in the union of `links[i][F]` over F in entries, skip it when `field_opposite_face(G)` is in moved. Set `beyond` when the face's `beyond` holds. For each neighbour m: with `entry := field_opposite_face(G)`, skip it when `entry not_in links[m][entry]` or when `field_walk_in_view` fails; otherwise relax m with `entry` and `moved[i] + {G}`.
  - Relaxing a node not yet reached sets its state. Otherwise its entries take the union and its moved the intersection, and the node is pushed again when either changed.
- `field_walk_in_view :: proc(cube: [2][3]f32, eye_metres: [3]f32, frustum: Maybe(render_frustum.Frustum)) -> bool`: true without a frustum; otherwise `frustum_contains_box`, or `box_distance_metres` at most `FIELD_WALK_NEAR_METRES`.
- `box_farthest_metres :: proc(minimum, maximum, point: [3]f32) -> f32` and `field_boxes_meet :: proc(first, second: [2][3]f32, slack: f32) -> bool` (closed boxes widened by the slack).
- `field_walk_draws :: proc(graph: ^Field_Walk_Graph, walk: Field_Walk, position: int, draw_minimum, draw_maximum: [3]f32) -> bool`. True in any of these cases:
  - the walk did not walk;
  - the position was reached;
  - `walk.beyond` holds and `box_farthest_metres` of the draw box is at least `last_distance_metres - FIELD_WALK_DISTANCE_SLACK_METRES`;
  - `field_walk_reaches_into`.
- `field_walk_reaches_into :: proc(graph: ^Field_Walk_Graph, walk: Field_Walk, position: int, draw_minimum, draw_maximum: [3]f32) -> bool`:
  - the sides: per axis, the negative face when `draw_minimum` is at most the cube's minimum plus the slack, and the positive face when `draw_maximum` is at least its maximum less the slack;
  - from the position, every hop sequence of 1 to 3 of those sides on distinct axes, in every order, through `graph.faces`;
  - true at the first reached node whose cube meets the draw box (`field_boxes_meet`, `FIELD_WALK_SLACK_METRES`).

`src/render_field_occlusion.odin` (new, presentation cluster). Header: the GPU half (0350), decisions 2 to 4.
- Constants:
  - `GL_ANY_SAMPLES_PASSED :: 0x8C2F`, `GL_QUERY_WAIT :: 0x8E13`; 0342's result constants are reused;
  - `FIELD_OCCLUSION_FRAMES :: 4` (sets in flight per view slot);
  - `FIELD_OCCLUSION_QUERY_BATCH :: 256`, `FIELD_OCCLUSION_MAXIMUM_QUERIES :: 16384`;
  - `FIELD_OCCLUSION_MAXIMUM_BOXES :: 8192` (per frame, over every viewport and pass);
  - `FIELD_OCCLUSION_DROP_LIMIT :: 32`, `FIELD_OCCLUSION_HISTORY_LIMIT :: 8192`;
  - `FIELD_OCCLUSION_BOX_MARGIN_METRES :: 0.1`, `FIELD_OCCLUSION_BOX_MARGIN_PER_METRE :: 0.004`;
  - `FIELD_BOX_VERTEX_COUNT :: 36`.
- Types:
  - `Field_Occlusion_State :: enum u8 {Off, Ready, Unavailable}`;
  - `Field_Occlusion_Class :: enum u8 {Plain, First, Box}`;
  - `Field_Occlusion_Kind :: enum u8 {Node_Drawn, Node_Box, Tile_Drawn, Tile_Box}`;
  - `Field_Occlusion_Entry :: struct {id: u32, kind: Field_Occlusion_Kind, node: Field_Node, tile: Field_Tree_Tile}`;
  - `Field_Occlusion_Set :: struct {entries: [dynamic]Field_Occlusion_Entry, pending: bool}`;
  - `Field_Occlusion_View :: struct {sets: [FIELD_OCCLUSION_FRAMES]Field_Occlusion_Set, frame, current: int, seen_nodes: map[Field_Node]struct{}, seen_tiles: map[Field_Tree_Tile]struct{}}`;
  - `Field_Occlusion_Procedures`: eight `proc "c"` fields:
    - `generate_queries(count: i32, ids: [^]u32)`;
    - `delete_queries(count: i32, ids: [^]u32)`;
    - `begin_query(target, id: u32)`;
    - `end_query(target: u32)`;
    - `get_query_object(id, name: u32, value: ^u32)`;
    - `begin_conditional(id, mode: u32)`;
    - `end_conditional()`;
    - `color_mask(red, green, blue, alpha: u8)`;
  - `Field_Occlusion :: struct {state: Field_Occlusion_State, procedures: Field_Occlusion_Procedures, free_ids: [dynamic]u32, made, drops_in_a_row, box_count: int, box_array, box_buffer: u32, views: [FIELD_VIEW_SLOTS]Field_Occlusion_View}`.
- Pure procedures:
  - `field_occlusion_class :: proc(seen_last, has_mesh: bool, box_distance_metres: f32) -> Field_Occlusion_Class`: First when it has a mesh and was seen last or lies within `FIELD_WALK_NEAR_METRES`; Plain when near without a mesh; Box otherwise.
  - `field_occlusion_box :: proc(minimum, maximum, eye: [3]f32) -> (low, high: [3]f32)`: decision 3's margin.
  - `field_box_vertices :: proc(minimum, maximum: [3]f32, vertices: [][3]f32)`: 36 vertices, two triangles per face.
  - `field_occlusion_turn :: proc(view: ^Field_Occlusion_View) -> (dropped: bool)`: `frame += 1`, `current = frame % FIELD_OCCLUSION_FRAMES`; dropped when that set is still pending.
  - `apply_field_occlusion_results :: proc(view: ^Field_Occlusion_View, entries: []Field_Occlusion_Entry, results: []u32) -> (hidden_nodes, hidden_tiles: int)`: a result above 0 puts the key in its seen map, and 0 removes it. A box entry answered 0 counts as hidden.
- GL procedures (the GL calls never run in tests):
  - `load_field_occlusion :: proc(occlusion: ^Field_Occlusion)`:
    - On Android, Unavailable with `occlusion: GLES 3 has no conditional rendering, the cave walk culls alone`.
    - On the desktop, the eight procedures through `rl.glfwGetProcAddress` under `when ODIN_PLATFORM_SUBTARGET != .Android`: `glGenQueries`, `glDeleteQueries`, `glBeginQuery`, `glEndQuery`, `glGetQueryObjectuiv`, `glBeginConditionalRender`, `glEndConditionalRender`, `glColorMask`.
    - A nil procedure: Unavailable with `occlusion: no <name>, drawn without GPU occlusion queries`.
    - Otherwise: the box vertex array (`rlgl.LoadVertexArray`), a dynamic buffer of `FIELD_OCCLUSION_MAXIMUM_BOXES * FIELD_BOX_VERTEX_COUNT` `[3]f32`, attribute 0 three floats (`render_instancing.odin`'s pattern), Ready, and `occlusion: GPU occlusion queries on`.
  - `release_field_occlusion :: proc(occlusion: ^Field_Occlusion)`: deletes every id (free and in sets), the array and buffer, and the maps.
  - `take_field_occlusion_id :: proc(occlusion: ^Field_Occlusion) -> u32`: from `free_ids`, which grows by `FIELD_OCCLUSION_QUERY_BATCH` while `made` stays within `FIELD_OCCLUSION_MAXIMUM_QUERIES`; 0 for none.
  - `collect_field_occlusion :: proc(occlusion: ^Field_Occlusion, profile: ^Frame_Profile)`:
    - Called once a frame in `prepare_field_frame`; sets `box_count = 0` while Ready.
    - Per view, the pending sets oldest first: a set is read only when every id answers `GL_QUERY_RESULT_AVAILABLE`, otherwise this view stops.
    - A read set gives its results to `apply_field_occlusion_results`, counts `Occluded_Nodes` and `Occluded_Tiles`, returns its ids, is no longer pending, and zeroes `drops_in_a_row`.
  - `begin_field_occlusion_pass :: proc(occlusion: ^Field_Occlusion, slot: int) -> ^Field_Occlusion_Set`:
    - `field_occlusion_turn` first. A dropped set returns its ids unread and adds to `drops_in_a_row`; at the limit, `release_field_occlusion`, Unavailable, and `occlusion: GPU occlusion results never became readable, drawn without the queries`.
    - Clears the set; clears a seen map over `FIELD_OCCLUSION_HISTORY_LIMIT`.
  - `query_field_occlusion_boxes :: proc(occlusion: ^Field_Occlusion, set: ^Field_Occlusion_Set, boxes: [][2][3]f32, ids: []u32, kind: Field_Occlusion_Kind, nodes: []Field_Node, tiles: []Field_Tree_Tile)`:
    - An id past the frame's box capacity goes back and is zeroed.
    - The vertices go in at `box_count` (`rlgl.UpdateVertexBuffer`) after `rlgl.DrawRenderBatchActive()`.
    - The state: the default shader (`rlgl.GetShaderIdDefault`, its MVP location set to `instanced_mvp()`), `color_mask(0, 0, 0, 0)`, `rlgl.DisableDepthMask`, `rlgl.DisableBackfaceCulling`, the box array.
    - Each box is drawn by `rlgl.DrawVertexArray` inside `begin_query`/`end_query` and appended as an entry; `count_draw_call()` each.
    - Then everything is restored (colour mask on, depth mask, culling, no array, no shader), and the set is pending when it holds entries.
  - `begin_field_condition`/`end_field_condition :: proc(occlusion: ^Field_Occlusion, id: u32)` and `begin_field_drawn_query`/`end_field_drawn_query` (same signature): nothing for id 0.

`src/render_field.odin`
- `Field_Cull_View :: struct {eye: World_Position, slot: int, on: bool}`: what `draw_field` culls a viewport by; zero draws by the frustum only.
- `Field_Renderer` gains:
  - `openness: map[Field_Node]Field_Node_Openness`;
  - `walk_graph: Field_Walk_Graph`;
  - `occlusion: Field_Occlusion`.
- `store_field_openness :: proc(openness: ^map[Field_Node]Field_Node_Openness, node: Field_Node, value: Field_Node_Openness)` (destroys the old value first) and `forget_field_openness :: proc(openness: ^map[Field_Node]Field_Node_Openness, node: Field_Node)`.
- `unload_field_node` calls `forget_field_openness`.
- `upload_streamed_field_meshes`: after `apply_field_mesh`, `store_field_openness(&renderer.openness, result.node, result.openness)`. The openness moves into the map and is not destroyed with the mesh data.
- `destroy_field_renderer`: every openness, `destroy_field_walk_graph` and `release_field_occlusion`.
- `draw_field :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, selection: []Field_Node, lights: Field_Frame_Lights, cull: Field_Cull_View = {}, profile: ^Frame_Profile = nil) -> (visible: []Field_Node_Render, conditions: []u32)`:
  - The uniforms as 0349 leaves them.
  - With `cull.on`: `walk := walk_field_visibility(&renderer.walk_graph, renderer.openness, cull.eye, frustum)`. A frustum node with a render that `field_walk_draws` refuses counts `Walk_Culled_Nodes`; the rest are the visible list, in selection order.
  - With `cull.on`, an Off occlusion is loaded first.
  - Without Ready: every visible terrain is drawn as today, and the conditions are all 0.
  - With Ready, `begin_field_occlusion_pass(cull.slot)`, a batch flush, then the classes (`field_occlusion_class` of `node in seen_nodes`, `has_mesh`, the draw box's `box_distance_metres` from the camera):
    - First: drawn inside a drawn query (`Node_Drawn`); without an id, plain.
    - Plain: drawn.
    - Box: their `field_occlusion_box` boxes tested in one `query_field_occlusion_boxes` (`Node_Box`), then each with a mesh drawn inside its condition. `conditions[k]` is the id, 0 when it got none, which draws plainly.

  The counts of 0342 and 0349 stay.
- `draw_field_water :: proc(renderer: ^Field_Renderer, visible: []Field_Node_Render, conditions: []u32)`: each draw inside `begin_field_condition`/`end_field_condition` of its condition (0 when `conditions` is shorter).

`src/render_field_cover.odin`: `draw_field_cover :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, visible: []Field_Node_Render, conditions: []u32, shadow_texture: u32)`: each node's instanced draw of a kind inside its condition.

`src/render_field_trees.odin`
- `Far_Tile` gains `key: Field_Tree_Tile` and `minimum, maximum: [3]f32` (the widened box `select_far_tiles` already computes), filled there.
- `draw_far_tree_cards :: proc(trees: Tree_Draw, far: []Far_Tile, daylight: rl.Color, shadow_texture: u32, occlusion: ^Field_Occlusion = nil, slot := 0, camera_metres: [3]f32 = {})`:
  - With a Ready occlusion, the classes first. The Box tiles' boxes are tested (`Tile_Box`) before the tree shader is bound, into the slot's current set (`views[slot].sets[views[slot].current]`).
  - Then the cards as today: a First tile inside a drawn query (`Tile_Drawn`), a Box tile inside its condition.
  - Nil draws as today.
- `draw_field_trees` passes `&scene.renderer.occlusion` when `scene.occlusion`, with `scene.view_slot` and `camera.position`.

`src/loop_field_session.odin`
- `Field_Scene.occlusion: bool`: the walk and the queries. True in `draw_field_viewport_world`; false (zero) in the planet preview, which draws as today.
- `draw_field_passes`: Terrain takes `visible, conditions := draw_field(scene.renderer, camera, selection, scene.lights, Field_Cull_View{eye = metres_to_world_position(camera.position), slot = scene.view_slot, on = scene.occlusion}, scene.profile)`. Cover and Water pass `conditions`.
- `prepare_field_frame`, after `upload_streamed_field_meshes`:
  - `update_field_walk_graph(&renderer.walk_graph, frame_field_selection(state), make_field_view({}, session.planet, session.simulation.field.spacing_millimetres, state.presentation.field_level_distances))`;
  - `collect_field_occlusion(&renderer.occlusion, &state.developer.frame_profile)`.

0342's files
- `render_frame_profile.odin`: `Frame_Counter` gains `Walk_Culled_Nodes`, `Occluded_Nodes`, `Occluded_Tiles` last.
- `diagnostics.odin`: the Render page's counters take four rows of four (28 lines).
- `command_profile_test.odin`: `test_the_profile_report_names_every_section` expects 124 lines and a `count` line for each of 15 counters.
- `diagnostics_test.odin`: `test_the_render_page_fits_with_the_profile` keeps its bound of 28 lines and 94 characters.

### Tests

`src/world_field_openness_test.odin`, hand-made grids through `fill_test_field_grid` (densities ±50, never 0):
- `test_an_open_grid_links_every_face_and_a_solid_one_none`: all air gives `field_unknown_links()`, all ground gives every set empty, both through the shortcut. A grid of air with one ground sample in the middle gives `field_unknown_links()` through the fill.
- `test_a_tunnel_links_the_faces_it_opens`:
  - Ground with a straight tunnel along x (samples within 3 of y = z = 16): `links[.Negative_X]` and `links[.Positive_X]` are both `{.Negative_X, .Positive_X}`, and the other four are empty.
  - An L from the −x face to the +y face: −x and +y link each other and themselves, and nothing else.
- `test_two_pockets_link_only_their_own_faces`: a pocket in the (−x, −z) edge and one in the (+x, +y) edge. `links[.Negative_X] == {.Negative_X, .Negative_Z}` and `links[.Positive_Y] == {.Positive_X, .Positive_Y}`.
- `test_a_wall_two_samples_thick_parts_the_faces_and_one_does_not`: air with a wall at x = 16 links −x and +x (the cells either side hold the surface). With walls at x = 16 and 17, it does not, and −x still links ±y and ±z.
- `test_the_ground_bits_hold_the_samples_of_the_node`: `field_ground_bit` equals `field_sample_is_ground` of the grid at every local sample 0 to 32 of a sloped grid (`fill_test_plane_grid`), and `field_node_openness` keeps bits at level 0 and none at level 1.
- `test_a_mesh_result_carries_its_openness`:
  - `start_field_streaming(TEST_PLANET_SEED, make_test_planet(), 1000, 0)`.
  - Jobs at levels 0 and 1, each given a heap grid copied from the tunnel grid.
  - `result.openness.links` equals `field_node_links` of that grid. The ground holds `FIELD_GROUND_BIT_WORDS` words at level 0 and 0 at level 1.
  - `free_field_job_result` frees both.

`src/render_field_walk_test.odin`, with a `Field_View` built by hand: `shell_inner` 0, `shell_outer` `1 << 40`, 1000 mm, last distance 1000 m.
- `test_the_walk_graph_finds_the_neighbours_of_every_level`: A = `{1, {0,0,0}}`; the four level 0 nodes `{0, {2, y, z}}`, y and z in {0, 1}; `{2, {−1,0,0}}`; `{1, {0,−1,0}}`. Expected:
  - A's +x face holds the four level 0 nodes, and its −x face the level 2 node.
  - A's −y face holds `{1,{0,−1,0}}`. Its +y, −z and +z faces hold none and are beyond.
  - `{0,{2,0,0}}`'s −x face holds A, and its +x face is beyond.
  - The level 2 node's +x face holds A and is beyond.
  - With `shell_outer` set under every box, the beyond flags are false.
  - A second update with the same selection leaves the containers untouched (same backing pointer).
- `test_the_walk_passes_only_linked_faces_and_never_turns_back`: level 0 nodes N0 to N3 along x at y = 0, N4 above N2, N5 above N1. Openness by hand, N0 all air with ground bits:
  - N1 links −x with +x.
  - N2 links −x with +x and +y.
  - N4 links −y with −x.
  - N5 links every face.
  - N3's −x layer is closed.

  The eye in N0, no frustum. Reached: N0, N1, N2 and N4. Not reached: N5 (it would need −x after +x) and N3 (closed layer).

  Teeth: with N5 placed at +x of N4 instead (N4 linking −y with +x), N5 is reached.

  A frustum looking −x from N0's centre leaves N1 unreached. With the eye 0.5 m from N0's +x face and the same frustum, N1 is reached (its cube lies within 1 m).
- `test_a_node_whose_mesh_reaches_into_a_reached_one_is_drawn`, `Field_Walk` filled by hand, level 0 nodes N (0,0,0), P (1,0,0), Q (0,1,0), D (1,1,0):
  - A draw box 2 m into P with P reached: drawn. The same box with P not reached: not drawn.
  - A box inside N's cube by 1 m: not drawn.
  - A box ending exactly on N's +x face (a curtain) with P reached: drawn.
  - A box poking 2 m on +x and +y with only D reached: drawn. With nothing reached: not drawn.
- `test_a_path_past_the_view_draws_what_reaches_the_view`: last distance 100 m, `beyond` set. Draw boxes whose farthest point lies at 99.5 m and at 101 m are drawn, one at 98 m is not. Without `beyond`, none is drawn.
- `test_the_walk_stands_down_where_the_eye_is_not_in_open_air`: not walked in each of these cases (otherwise walked):
  - the eye's node has no openness;
  - it has openness without bits (level 1);
  - one corner of the eye's cell is ground;
  - the eye's node is not selected.
- `test_the_walk_never_hides_a_visible_node` (`// slow`): the brute force reference over meshes.
  - The world: `occlusion_test_world_density` (a `Test_Field_Density`, f64 inside, ±`MAXIMUM_DENSITY`, 0 read as −1), round the pole of the test planet (radius 8000 samples at 1000 mm), in samples relative to (0, 8000, 0):
    - Ground under the sphere of radius 8000 + 5.5 + a ridge `max(0, 30 − 0.75·|z − 70|)`.
    - Air in four capsules: tunnel A, (−90, −10, −20) to (90, −10, −20), radius 3; its shaft, (40, −10, −20) to (40, 12, −20), radius 2.5, which opens it to the surface; chamber B, (−40, −18, 40), radius 6, closed; tunnel C, (−20, −14, 70) to (20, −14, 70), radius 3, closed, under the ridge.
  - The view: `make_field_view(eye, make_test_planet(), 1000, {48, 96, 144, 192})`, its shell set to the radius ± 48 m. `select_field_nodes` balances it.
  - Each selected node: `fill_test_field_grid` at its origin and step, `field_node_openness`, `mesh_field_grid` with `field_node_skirt_faces` of the selection, and its draw box from the positions' extremes. A test map keyed by node and faces reuses a node's mesh across eyes.
  - Then `update_field_walk_graph` and `walk_field_visibility` with no frustum, which is every direction.
  - The eyes (metres from the pole, each + (0.37, 0.29, 0.41)):
    - 1.6 m over the ground at (0,0), (30,−20), (−50,10), (60,40), (10,70) on the ridge, (−30,−60), (45,−20) beside the shaft and (80,80);
    - 40 m over (0,0) and 25 m over (20,−50);
    - on tunnel A's axis at x −80, −30, 10, 39 and 70;
    - in the shaft at y 0 and 4;
    - in chamber B at its centre and at (−37, −16, 42);
    - on tunnel C's axis at x 0 and 15;
    - 120 m over (−40, 0), outside the shell.
  - The reference:
    - Every mesh's triangles go in world metres relative to the pole, into a uniform grid of 4 m cells.
    - A triangle faces the eye when `dot(cross(b − a, c − a), eye − a) > 0` (counter clockwise fronts, the mesh wound outward).
    - Possible failures: for every node `field_walk_draws` refuses, any triangle of it facing the eye whose centroid the segment from the eye reaches is a failure. A blocked segment meets another triangle facing the eye at a parameter in (1e-4, 1 − 1e-4); grid cells are visited along the segment, and the walk stops at the first hit. A failure names the eye, the node and the triangle.
  - Asserted:
    - every eye walks except the one outside the shell, which does not;
    - no failure;
    - from each walking eye the reference finds at least one triangle of a drawn node reachable (the reference can see);
    - from chamber B's eyes at least half the meshed nodes are culled;
    - summed over the eyes on the ground, chamber B's and tunnel C's nodes are culled at least once.
  - A failure whose segment passes a level seam's strip is a seam leak (decision 10): the implementer reports it with the ray and does not loosen the walk for it.

`src/render_field_occlusion_test.odin`
- `test_a_box_query_draws_the_six_faces`: `field_box_vertices` gives 36 vertices, each a corner, and each face's plane holds two triangles of nonzero area covering it.
- `test_the_seen_ones_go_first_and_the_near_ones_always`: `field_occlusion_class` over the eight cases of seen, mesh and near (0.5 m and 5 m).
- `test_query_results_update_the_history_and_count_the_hidden`: four entries (a drawn node seen 0, a box node 0, a box tile 3, a drawn tile 1). Afterwards the node keys are out of `seen_nodes`, both tiles are in `seen_tiles`, and hidden is (1, 0).
- `test_a_set_still_waiting_at_its_turn_is_dropped`: `field_occlusion_turn` cycles 0 to 3. It reports dropped on the fifth turn when set 1's pending is still set, and not when it was cleared.
- `test_the_box_margin_grows_with_the_distance`: a unit box 1000 m away widens by 4.1 m per side, one at the eye by 0.1 m.

`src/render_field_test.odin`: `test_a_new_openness_replaces_the_old`: `store_field_openness` twice for a node leaves one entry holding the second value. `forget_field_openness` empties the map. Bits allocated with a tracking allocator are all freed.

### Docs

- `doc/presentation.md`:
  - Field meshes, a bullet "Occlusion (0350)" after 0349's culling bullet: decisions 1 to 3 and 5 to 9 in a few lines each, naming `walk_field_visibility`, `field_walk_draws`, `Field_Node_Openness` and the queries' two lists.
  - The field session, the trees bullet: the far tiles take the same queries.
- `doc/architecture.md`:
  - Threads and chunk streaming, the field bullet: a mesh result carries its grid's openness (`Field_Job_Result.openness`).
  - Platforms: GPU occlusion needs conditional rendering (GL 3.0), so the GLES build culls by the walk alone.
- `doc/android.md`, Display and shaders: the same line.
- `doc/developer_tools.md`, the Render row: the three new counters.
- `doc/commands.md`, Frame profile: 15 `count` lines.
- `doc/code_map.md`: `world_field_openness.odin` in the world cluster; `render_field_walk.odin` and `render_field_occlusion.odin` in the presentation cluster; the counts.

### Hand-back check

- Memory a frame draws from: the openness is stored and freed in `upload_streamed_field_meshes` and `unload_field_node`, and the graph is rebuilt in `prepare_field_frame`, all before the viewports draw. The query sets reuse their arrays, and nothing is freed inside a draw. `test_a_new_openness_replaces_the_old` covers the replacement.
- A list that grows: the query ids (16384), the boxes (8192 a frame) and the seen maps (8192, cleared past it) are capped, past which things draw plainly. The graph is sized by the selection. The Render page's four counter rows fit 0342's 28 line test.
- A start-up load that can fail: missing entry points and unreadable results turn the GPU part off with one log line, and the frame draws as today.
- A shared budget: the workers' mesh job grows by one fill. The nightly meshing report gives the job time before and after (the main agent's night run; the implementer does not run report tests).
- Tests touch no machine state: everything is in memory.
- File writes, parsed numbers, save layout and audit cases do not apply.

### Questions to the main agent

1. The phone keeps only the walk: GLES 3.0 has no conditional rendering, and using its queries a frame late would pop. Accept, or an item for `GL_NV_conditional_render` where the phone's driver offers it?
2. Far tree tiles are culled only by the queries, so in a closed cave on the phone (40,000 cards) they all draw. A tile could also be dropped when its box meets no reached node's cube and no path left the view. That would be a follow-up item; it is not in the item's change list.
3. 0327's decision 6 asks whether a tunnel ends in a hole at the level 2 seam. If it does, the walk treats the coarse node as solid there and may hide what the hole shows through the coarse node's back faces. That is decision 10's case: the hole's own item fixes it, not the walk.
4. No setting turns the occlusion off. The Windows build under Winlator's Gladio is unverified: a layer that has the entry points but answers conditional rendering wrongly would show missing ground. A developer screen toggle would be a small addition; I left it out.

### Decisions (main agent, 2026-11-11)

1. Question 1: accepted. The phone keeps the walk alone; it is secondary, and the Steam Deck runs desktop GL.
2. Question 2: no item now. Whether a closed cave's far tree tiles cost the phone anything is measured first (`SUGGESTIONS.md` at this item's landing).
3. Question 3: agreed, a hole at a tunnel's level 2 seam is a seam defect and the walk is not loosened for it. The main agent checks 0327's decision 6 for it at that item's landing and writes the item if the hole is real.
4. Question 4: a switch is part of this item, as a socket command `occlusion on|off` (developer mode, presentation only, not saved) with its row in `doc/commands.md` and the F3 Render page showing the state. 0342's script then measures both in one build, and Gladio under Winlator can be told apart from a defect.
5. Order: last of the performance items, after 0327, 0339, 0349, 0354, 0346 and 0347 have landed, and started only when 0342's ridge and cave views show what the hidden nodes cost.
