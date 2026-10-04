# 0226: Models over 65536 vertices draw unindexed

Status: todo (2026-10-04, found when the round three pod of the lab, 25488 triangles under the budget of 25600 the user set, was refused by the game: `machine "pod": model pod: more than 65536 vertices`; blocks the in game shots of that model and 0221)

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
