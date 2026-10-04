# 0226: Models over 65536 vertices draw unindexed

Status: implementing (2026-10-04, the specification approved the same day with the decisions below; the implementer works in `.claude/worktrees/0226` on `item/0226` from `main`, found when the round three pod of the lab, 25488 triangles under the budget of 25600 the user set, was refused by the game: `machine "pod": model pod: more than 65536 vertices`; blocks the in game shots of that model and 0221)

## Goal

A machine model may use the whole body budget 0221 sets (25600 triangles for the pod): the game loads and draws it, and the lab's check refuses what the game would refuse.

## Why it fails

`model_triangle_mesh.odin` gives every triangle three vertices of its own (flat shading) and writes an index per vertex into `Model_Mesh.indices`, which is `u16` because raylib's `Mesh.indices` is `[^]u16` (`shared/raylib/raylib.odin`, `Mesh`); `mesh_obj_triangles` refuses a mesh past `MESH_PART_VERTEX_LIMIT` (65536, `world_mesh.odin`), which 21846 triangles reach. The index buffer of a triangle mesh is the identity (vertex 0, 1, 2, 3, ...), so it carries nothing: raylib draws a mesh whose `indices` is nil with `glDrawArrays` over `vertexCount` vertices (`rlgl`, `DrawMesh`: indexed only when `mesh.indices` is set), and `vertexCount` is a C int. The voxel mesher (`model_mesh.odin`) shares vertices per quad and keeps its indices; it is far under the limit and stays as it is.

## Controls

No binding changes.

## Change

- The triangle mesher writes no indices: `append_model_triangle` appends the three vertices only, and `upload_model_mesh` (`render_models.odin`) uploads a mesh without indices as unindexed (`indices = nil`, `triangleCount = vertexCount / 3`) and one with indices as today. The vertex limit of the triangle mesher goes; the triangle budget bounds it (`model_body_triangles_maximum` of 0221, `MODEL_BODY_TRIANGLES_MAXIMUM` until then, both in `model_check.odin`), and a model over 65536 vertices loads and draws.
- Every reader of a model mesh's triangles that walks `indices` (the model check's sweep and open cell tests in `model_check.odin`, the workbench's preview and `--model-check`, `model_check_test.odin`'s helpers, the normals test of 0224 that reads winding normals through the indices, anything else `grep indices src/model*.odin src/render_models.odin` finds) reads triangles through one helper that serves both shapes: three consecutive positions when the mesh has no indices, the indexed corners otherwise.
- The lab's `check.py` (`tools/model_lab/pod/check.py`, and the copy in `tmp/pod_lab`) gains no vertex rule: the triangle budget is the rule, as in the game.
- Docs: `doc/presentation.md` (Machine models: flat shaded triangles go up unindexed; the voxel meshes indexed), `doc/build.md` if the workbench bullet names the limit.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: a triangle mesh of 22000 triangles (66000 vertices) meshes without an error and its upload shape is unindexed (the pure part: the mesh has no indices, as many positions as normals and colours, a multiple of three); a voxel mesh keeps its indices; the triangle reader gives the same corners for an indexed and an unindexed mesh of the same triangles; the model check's sweep and open cell tests pass on an unindexed mesh (the existing tests through the helper).
- `./build.sh model-check pod` on the round three model in the private data copy (`tmp/pod_data`) passes its budget and open cells, and the headless screenshot pass (`tmp/pod_shots.sh`, main agent) shows it in the cabin.

## Specification (design, 2026-10-04)

Built against `main` at `c395308`. 0221 (designed, not implemented) changes `model_budget_problems` to take a body maximum; this item touches the same procedure's callee (`model_layers_triangle_count`) only, so the two rebase cleanly in either order.

### Facts of "Why it fails", checked

- Confirmed: `Model_Mesh.indices` is `[dynamic]u16` (`src/model_mesh.odin:51`), raylib's `Mesh.indices` is `[^]u16` and `vertexCount` a `c.int` (`shared/raylib/raylib.odin:314`, `:324`); `append_model_triangle` writes the identity (`src/model_triangle_mesh.odin:56-61`); `mesh_obj_triangles` refuses at `src/model_triangle_mesh.odin:77-78` against `MESH_PART_VERTEX_LIMIT` (`src/world_mesh.odin:16`).
- Narrowed: the limit is per layer (lit or emissive) of the body or the part, not per model: a layer is refused at its 21846th triangle (21845 make 65535 vertices). The refusal runs in content validation (`validate_machine_models`, `src/machine.odin:767`), so the whole data load fails (`./build.sh model-check pod` on `tmp/pod_data` prints `error: invalid .../machines.sjson: machine "pod": model pod: more than 65536 vertices`), not only the renderer.
- Corrected: `DrawMesh` is in raylib's `rmodels.c`, not rlgl. Read in `tmp/raylib-src` (the source `tools/build_raylib.sh` builds, `RAYLIB_VERSION "6.0"`): `rmodels.c:1655-1656` (the GL 3.3 and ES path) and `:1463-1464` (GL 1.1) call `rlDrawVertexArray(0, mesh.vertexCount)` when `mesh.indices` is NULL, which is `glDrawArrays(GL_TRIANGLES, offset, count)` (`rlgl.h:4079-4081`). `UploadMesh` creates the element buffer only when `indices != NULL` (`rmodels.c:1417-1420`) and leaves `vboId[INDICES]` 0; `UnloadMesh` (`rmodels.c:1929-1944`) calls `rlUnloadVertexBuffer` on every slot (0 is ignored by GL, as the model meshes' texcoords slot already is today) and `RL_FREE(NULL)`. So both work with nil indices unchanged.
- Corrected: the workbench's preview (`src/loop_model_preview.odin`) reads no indices: it draws through `init_model_renderer`, `upload_model_mesh` and `draw_model_layers`, so it needs no change of its own. Nothing outside `model_check.odin`, `render_models.odin` and three test files reads a `Model_Mesh`'s indices (`grep -n "\.indices" src/*.odin`); the player limbs (`render_player_model.odin`) and the arm's parts (`model_arm.odin`, `load_arm_part_meshes`) are voxel meshes and stay indexed.
- Side fact: `clone_for_raylib` of an empty slice already returns nil (Odin's `mem_alloc_bytes` returns nil for size 0, `~/opt/odin/base/runtime/internal.odin:119`), so the upload sets `indices = nil` explicitly anyway, for the reader.

### Files and procedures

`src/model_mesh.odin`:
- The comment above `Model_Mesh` (line 44) becomes: "Two shapes (0226): the voxel mesher shares a quad's four corners and writes indices, u16, so at most MESH_PART_VERTEX_LIMIT vertices a layer; the triangle mesher writes three vertices per triangle in order and no indices, drawn unindexed, bounded by the triangle budget (model_check.odin) only. Read a mesh's triangles through model_mesh_triangle, which serves both." Keep the normals sentence. `indices` stays `[dynamic]u16` (the voxel mesher and raylib need it; an empty array is the unindexed shape).
- Add, after `append_model_quad`:
  - `model_mesh_triangle_count :: proc(mesh: Model_Mesh) -> int`: `len(mesh.indices) / 3` when `len(mesh.indices) > 0`, else `len(mesh.positions) / 3`. Called by `model_layers_triangle_count`, `model_mesh_upload_counts`, the tests below.
  - `model_mesh_triangle_vertices :: proc(mesh: Model_Mesh, triangle: int) -> [3]int`: the vertex indices of the triangle's corners, `{int(mesh.indices[3 * triangle]), ...}` when indexed, `{3 * triangle, 3 * triangle + 1, 3 * triangle + 2}` otherwise. Called by `model_mesh_triangle` and by `test_the_voxel_mesher_gives_each_face_its_direction` (which reads normals per corner).
  - `model_mesh_triangle :: proc(mesh: Model_Mesh, triangle: int) -> [3][3]f32`: the three positions at `model_mesh_triangle_vertices`. Called by `model_layers_check_triangles`, `expect_outward_winding`, and the tests below.
  - No bounds check beyond Odin's own: callers loop `0 ..< model_mesh_triangle_count(mesh)`.
- `make_model_mesh`, `append_model_quad`, `destroy_model_mesh` and the check at line 192 are unchanged.

`src/model_triangle_mesh.odin`:
- `append_model_triangle :: proc(mesh: ^Model_Mesh, corners: [3][3]f32, colour: [4]u8, normal: [3]f32)` keeps its signature; drop `base` and the `append(&mesh.indices, ...)`; the loop becomes `for corner in corners`.
- `mesh_obj_triangles`: delete the check at lines 77-79. The signature and the `problem` result stay (callers and the arm path read it; it is always "" now). Update its comment: "The meshes have no indices (0226): any number of triangles, the budget is the model check's."
- The header comment (lines 11-13): after "Every triangle gets three vertices of its own (flat shading)" add "and no indices: the layers go up unindexed (render_models.odin, 0226)".
- `fmt` stays imported (`model_footprint_problem`).

`src/render_models.odin`:
- Add `model_mesh_upload_counts :: proc(mesh: Model_Mesh) -> (vertex_count, triangle_count: i32, indexed: bool)`: `i32(len(mesh.positions))`, `i32(model_mesh_triangle_count(mesh))`, `len(mesh.indices) > 0`. Pure, so the test reads the upload's shape without a window. Called by `upload_model_mesh` only.
- `upload_model_mesh :: proc(mesh: Model_Mesh) -> rl.Mesh` keeps its signature and its early return on no positions. Fields: `vertexCount = vertex_count`, `triangleCount = triangle_count`, `vertices`, `normals`, `colors` as today, and `indices = clone_for_raylib(mesh.indices[:])` when `indexed`, else `nil` (set after the literal: `if indexed { uploaded.indices = clone_for_raylib(mesh.indices[:]) }`). Then `rl.UploadMesh(&uploaded, false)` as today. Indexed: triangleCount `len(indices) / 3` as before, unchanged behaviour. Unindexed: triangleCount `vertexCount / 3`, raylib draws `vertexCount` vertices with `glDrawArrays`.
- The comment above it: "A voxel layer goes up indexed, a triangle layer (no indices, 0226) unindexed: raylib's DrawMesh draws vertexCount vertices in order when indices is nil."
- `unload_model_layers` unchanged (`rl.UnloadMesh` handles a nil index pointer, above).

`src/model_check.odin`:
- `model_layers_check_triangles`: the inner loop becomes `for triangle in 0 ..< model_mesh_triangle_count(mesh)`, `corners := model_mesh_triangle(mesh, triangle)`, each corner through `transform_point(transform, ...)`, then `append(&triangles, check_triangle(corners))`. Its comment: "Every triangle of the lit layer, then the emissive one (either shape, model_mesh_triangle), its corners through transform." The order (lit then emissive, triangle order) is unchanged, so the report's `part N, body N` indices keep their meaning.
- `model_layers_triangle_count :: proc(layers: Model_Layers) -> int`: `model_mesh_triangle_count(layers[.Lit]) + model_mesh_triangle_count(layers[.Emissive])`. This one matters most: left on `indices`, every OBJ model would count 0 triangles and pass the budget silently.
- No budget constant changes: `MODEL_BODY_TRIANGLES_MAXIMUM`, `MODEL_PART_TRIANGLES_MAXIMUM` stay (0221 adds the pod's). The cost comment at the top stays (0221 rewrites it).

`src/world_mesh.odin`: `MESH_PART_VERTEX_LIMIT` and its comment stay (chunks, field nodes, the voxel model mesher).

### Tests

`src/model_triangle_mesh_test.odin`:
- Replace `test_an_obj_layer_past_the_vertex_limit_is_refused` with `test_a_triangle_layer_past_65536_vertices_meshes_unindexed`: 22000 copies of `test_obj_triangle({{0, 0, 0}, {0, 1, 0}, {0, 0, 1}})` through `mesh_obj_triangles(model, false)`; assert problem "", `len(lit.indices) == 0`, `len(lit.positions) == 66000`, `len(lit.normals) == len(lit.colors) == len(lit.positions)`, `len(lit.positions) % 3 == 0`, `model_mesh_triangle_count(lit) == 22000`, `model_layers_triangle_count(meshes) == 22000`, and `model_mesh_upload_counts(lit)` is `(66000, 22000, false)`. Destroy the layers.
- `expect_outward_winding`: `testing.expectf(t, model_mesh_triangle_count(mesh) > 0, ...)`, loop `for triangle in 0 ..< model_mesh_triangle_count(mesh)` with `corners := model_mesh_triangle(mesh, triangle)`, the message's index `triangle`. It runs on the voxel cube (indexed) and the OBJ box (unindexed) in `test_obj_and_voxel_meshes_wind_alike`, so both shapes are read by the helper.
- `test_an_obj_model_wins_over_a_voxel_model`: line 257 `len(lit.indices)` expects 0 (was 36) and add `model_mesh_triangle_count(lit) == 12`; the voxel half (line 265) stays: the voxel mesh still has `len(indices) != len(positions)`.

`src/model_mesh_test.odin`:
- `test_a_single_voxel_has_six_faces`: add `model_mesh_triangle_count(mesh) == 12` and `model_mesh_upload_counts(mesh)` is `(24, 12, true)` (the voxel mesh keeps its indices; the existing `len(mesh.indices) == 36` stays).
- `test_the_voxel_mesher_gives_each_face_its_direction`: the loop becomes `for triangle in 0 ..< model_mesh_triangle_count(mesh)`, `vertices := model_mesh_triangle_vertices(mesh, triangle)`, `winding := triangle_winding_normal(model_mesh_triangle(mesh, triangle))`, the normal `mesh.normals[vertices[corner]]`; the message's index `triangle`.
- New `test_the_triangle_reader_serves_both_shapes`: mesh one voxel (`make_test_voxel_model({1, 1, 1}, ...)`, `mesh_voxel_model`) as the indexed mesh; build an unindexed one with `make_model_mesh(context.temp_allocator)` and `append_model_triangle(&unindexed, model_mesh_triangle(indexed, triangle), {255, 255, 255, 255}, triangle_winding_normal(...))` per triangle. Assert both counts 12, `model_mesh_triangle(unindexed, triangle) == model_mesh_triangle(indexed, triangle)` for every triangle, `model_mesh_triangle_vertices(unindexed, 5) == {15, 16, 17}`, and `model_mesh_triangle_vertices(indexed, 5)` equals `{int(indexed.indices[15]), int(indexed.indices[16]), int(indexed.indices[17])}`.

`src/model_check_test.odin`: no edits. `box_layers`, `triangles_layers` and the hand built meshes go through `append_model_triangle`, so after the change every sweep, footprint, open cell, fixture box, budget and arm test runs on unindexed meshes; `test_the_shipped_models_pass_the_checks` runs the OBJ models (unindexed) and the arm's voxel parts (indexed). `test_a_model_over_the_budget_is_reported` (3201 triangles, one problem naming 3201) is the guard that the budget counts unindexed triangles.

### The lab

No change to `tools/model_lab/pod/check.py`, `tools/model_lab/check.py` or the copy in `tmp/pod_lab/check.py`: read, none has a vertex rule; each counts body and part triangles against its budget, which is the game's only rule after this item. `tools/make_models.py` has no budget check of its own (`tools/make_models.sh` ends in `./build.sh model-check`).

### Docs

- `doc/presentation.md`, Machine models, the bullet on a machine's `model` key: after "Both go up through `render_models.odin` as the same layers." insert "The triangle mesher writes no indices, so its layers go up unindexed (`indices` nil, raylib draws every vertex in order) with no vertex limit, only the model check's triangle budget; the voxel mesher shares a quad's corners and goes up indexed, at most `MESH_PART_VERTEX_LIMIT` vertices a layer (u16 indices). Readers of a layer's triangles go through `model_mesh_triangle` (`model_mesh.odin`), which serves both (0226)."
- `doc/code_map.md` line 215 becomes: "`model_mesh.odin`, `model_motion.odin`: the voxel mesher over the `model_vox` package's parser (Packages), the choice of an .obj over a .vox and `model_mesh_triangle`, the reader of a layer's triangles in either shape (0226); `Machine_Motion` and part transforms."
- `doc/build.md`: no change; the workbench bullet names the budget and the loader's refusal, not the vertex limit.
- `doc/log/2026-10-04.md`: a section "Machine model layers go up unindexed (0226)", `Tags: models, presentation, raylib, m15`: the identity index buffer carried nothing and capped a layer at 21845 triangles; the triangle budget is now the only bound; no save, record or network change.

### Hand-back check

- Memory a frame may draw from: the upload and unload run where they ran (`replace_machine_models`, `unload_model_meshes`); nothing new frees mid frame. Nothing to do.
- Save layout, records, network: none (presentation only, the simulation never reads a model).
- A list that grows without bound: the triangle layer no longer has a cap at load; the bound is the budget in `--model-check` and `test_the_shipped_models_pass_the_checks` (see question 2). `i32(len(...))` cannot overflow below about 715 million triangles.
- Tests touch no state directory: all meshes are built in memory; `test_an_obj_model_wins_over_a_voxel_model` keeps its temporary directory.
- The other lines (file writes, parsed numbers, shared budgets, UI audit) do not apply.

### Questions the item left open, answered

- The helper: three small pure procedures in `model_mesh.odin` (count, vertex indices, positions) rather than an iterator: Odin has no cheap closure iterator, the callers already loop by index, and the normals test needs the vertex indices, not only the positions.
- `Model_Mesh.indices` stays `[dynamic]u16`; empty means unindexed. No flag field: the shape is read off the data, so a mesh cannot claim one shape and hold the other.
- The 22000 triangle test meshes through `mesh_obj_triangles` (the procedure that held the limit), not `append_model_triangle` directly, so it fails if the check comes back.
- The upload's shape is tested through the pure `model_mesh_upload_counts`; `rl.UploadMesh` needs a GL context the suite does not have.
- No budget constant or doc names the vertex limit for models except the `Model_Mesh` comment and `presentation.md`, both updated above; `doc/work/done/0204` keeps its historical text.

### For the main agent

1. Verify's `./build.sh model-check pod` on `tmp/pod_data`: on `main` (budget 3200) after this item it loads and then prints one `budget` line (`body has 25488 triangles, the budget is at most 3200`), and the open cell checks do not run, because `check_obj_machine_model` stops at the budget. It passes budget and open cells only on a tree with 0221's `model_body_triangles_maximum`. Land 0226 first and run that Verify line in 0221's worktree, or accept the budget line as this item's pass?
2. The game's loader takes a triangle layer of any size; only the workbench and the suite enforce the budget. The item's decision reads that way and I kept it. If you want the loader to refuse a model past its budget (so a model dropped into `data/` without the check cannot load), that is a change to `mesh_obj_machine_model` and would need 0221's per kind maximum: a separate item.

### Decisions at the approval (main agent, 2026-10-04)

1. 0226 lands first. On `main` the body budget is still 3200 for every kind, so `./build.sh model-check pod` on the private data copy loads the round three pod and stops at its budget line (25488 over 3200): that line is this item's pass of the Verify section's model-check bullet, and the open cell checks run in 0221's worktree with its per kind maximum.
2. The loader keeps accepting a triangle layer of any size; the budget stays enforced by `--model-check` and the suite, as before this item.
3. The corrections to "Why it fails" stand as written in the specification (the limit is per layer, the refusal is in content validation, `DrawMesh` is in rmodels.c).
