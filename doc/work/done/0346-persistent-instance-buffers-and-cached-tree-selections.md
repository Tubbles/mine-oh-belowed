# 0346: Persistent instance buffers and cached tree selections

Status: landed (2026-11-12, 4f61eb2)

The near trees and the shadow trees are selected by a scan every frame (up to about 35 thousand instances in a dense forest, 0328) and drawn through `DrawMeshInstanced`, which makes and frees a buffer per call (`work/performance_research_0340.md`, 2.2).

## Goal

The trees' CPU cost per frame falls to what changed since the last frame.

## Controls

None.

## Change

- One instance buffer per tree kind, updated in place.
- The near and the shadow selections kept across frames while the eye has moved less than a set share of the near distance, with the same trees drawn.

## Verify

- The checks and the suite, with a test that the cached selection equals a fresh one along a walk.
- 0342's table: the forest views' tree sections on the CPU, before and after.
- Captures of a forest before and after, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `4145ed0` and the specifications of 0342 (the frame profiler) and 0343 (the view distance), which change the same files (`loop_field_session.odin`, `render_field_trees.odin`); where they meet is said in decision 12.

### The probe (counts, no timings)

The shipped 8 km home, desktop rows, an extent of about 16.5 m (the pine's 15 cell top at 220 % and 500 mm), 70 degree camera at 16:9; a 600 frame walk north at 5 m/s with the sun at day fraction 0.1 moving with the 1200 s day; a turn in place at 90 degrees a second. The probe is `tmp/0346/tree/src/probe_0346_test.odin` (untracked).

| | forest (80.6, 132; 0342's forest view) | home (83.171, 130.477) |
|---|---|---|
| Today's near scan | 6 tiles, 16,618 instances, 5,327 within 96 m (5,327 felled lookups) | 9 tiles, 9,547 instances, 681 within 96 m |
| Near selection | 1,024 (the cap binds: 2,166 to 2,351 in the frustum within 96 m), near distance 57.2 to 59.2 m | 137 to 471, near distance 96 m |
| Today's shadow scan (sun height 0.94 / 0.55 / 0.18) | 16,618 / 25,596 / 25,596 instances, each with a felled lookup | 9,547 / 14,405 / 11,247 |
| Shadow selection | box 5,730 / 8,931 / 9,748, capped to 2,048 (cut at 59.6 m), sorted every frame | box 912 / 1,881 / 1,571, uncapped |
| Changes per frame, walk | near 3.5 (at most 14; 515 of 599 frames change), shadow 3.9 (at most 10; 571 of 599) | near 0.44 (212 frames), shadow 3.1 (546 frames) |
| Changes per frame, turn | near 19 (at most 48) | near 5.7 (at most 20) |
| Under decision 2's rule (margin 12 m) | near: 5 gathers in 600 frames, 6,821 candidates; shadow: 6 gathers, 11,426 candidates | near 5 gathers, 920 candidates; shadow 6 gathers, 2,304 candidates |

### Decisions

1. **"Matters" is "identical always".** What is held across frames is the candidates (the scan: the tile walk, the felled lookups, a margin's superset); the cut (the distance, the frustum or the casters' box, the cap) runs exactly each frame over them. The drawn set then equals a fresh selection's at every frame: per tree model the same instances (bit equal matrices, as a set) and the same `near_distance` bits. Instance order inside a draw may differ from a fresh one's, which changes a pixel only where two trees meet at exactly equal depth (raylib's `GL_LEQUAL`); today's order is a hash map's and an unstable sort's anyway. The shadow map is depth only and so order free. Ties at a cap now break by the tree key (today's sort left them to chance), so a fresh selection is a function.
   - Rejected, a held drawn set: the probe shows the exact set changes in 86 % (near) and 95 % (shadow) of walking frames, so a held set differs from a fresh one most frames. Hiding that needs a frustum free superset drawn by the GPU and cut by the dither: 6,666 model trees within 108 m in the forest against 1,024 drawn today, six and a half times the near models' vertices in the view 0342 judges, and the shadow pass has no dither (`sun_shadow.vs` presses every caster nearer the sun onto the near plane, so an extra caster shadows).
   - Rejected, a held set bound to the frustum: every turn invalidates it (19 changes a frame at 90 degrees a second).
   - The per frame cost left is a linear pass over the candidates without hashing, allocation or a full sort, a selection, and an upload only when the set changed (decision 7); between gathers nothing walks the tiles. With the probe's forest: near 6,821 distance tests (frustum tests for about 5,300) and a selection over about 2,300, against 16,618 instance visits, 5,327 hash lookups and a 2,300 element sort; shadow 11,426 box tests and a selection over about 9,700, against 25,596 visits with as many hash lookups and a 9,700 element sort. A gather costs about today's scan without its sort, every 12 m of walking.
2. **Near reuse rule.** The margin is `near_metres / TREE_CANDIDATE_MARGIN_DIVISOR` (8: 12 m at 96). Candidates are the standing trees with `|base − eye₀|² ≤ (near + margin + TREE_CANDIDATE_SLACK_METRES)²`, slack 0.25 m against f32 rounding (offsets near 8 km carry about 1 mm). They hold while: `|camera − eye₀|² ≤ margin²`; `near_metres` and the species count are the gather's; no cache change since the gather reaches the sphere (decision 4). Proof: a tree a fresh cut can select has `|base − camera| ≤ near`, so `|base − eye₀| ≤ near + margin`, so it is a candidate; the cut is the fresh predicate and cap over a superset of the fresh candidates, hence equal.
3. **Shadow reuse rule.** Candidates pass `sun_shadow_box_casts` in the cascade with `half_size` grown by `margin + slack` (every face moves out, the sun side too). They hold while: `half_size`, `reach_metres`, the extent, the margin and the species count are the gather's; no cache change reaches the grown box; and `|centre − centre₀| + span × chord ≤ margin`, where `chord` is the largest of `|right − right₀|`, `|up − up₀|`, `|toward_sun − toward_sun₀|` and `span = sqrt(2(h + e√3)² + (h + r + e√3)²) + e√3 + margin` (h the half size, r the reach, e the extent; 270.6 m on the desktop row). Proof: each of the box test's terms is `(p − c)·a` or a spread `e(|aₓ| + |a_y| + |a_z|)`; from (c₀, a₀) to (c, a) it moves by at most `|c − c₀| + (|p − c₀| + e√3)·chord`, and `|p − c₀|` of any tree that passes the current box is below `span − e√3`, so the grown test keeps every tree the current one passes. The sun turns 0.3 degrees a second (1200 s day), so with a still eye the candidates hold about 8 s; the up's turn while walking is in the chord.
4. **Change counters.** `Field_Tree_Cache.revision` counts changes to the cached tiles' instances; each change keeps the tile's bases box in a ring of `FIELD_TREE_CHANGE_RING` (64), `changes[revision % 64]`:
   - a felled tree: `drop_field_tree_key` (via `apply_felled_field_trees`);
   - a tile arriving: `insert_field_tree_tile` (from `take_finished_field_tree_tiles`);
   - a tile leaving: `evict_field_tree_tile` (the eviction loop);
   - every tile at once: `clear_field_tree_tiles` (a shorter felled table, a changed tile size) sets `cleared_at = revision` after its increment.
   A view checks only the changes since its gather against its own reach (decision 2, 3), so tiles streaming at the far distance and 0343's setting (which moves only `far_metres`: its evictions lie past the far distance plus 2 tiles, its arrivals past the old far distance, at least 256 m out, beyond the near reach of 108 m and the casters' box of about 200 m) gather nothing. More than 64 changes since, or a clear since, gathers again. The view distance, the rows (content reload), the species count, the extent (model reload) and the sun are inputs of the rules above. A tile's GPU upload (`upload_field_tree_tile`) is not a change. A tile made without trees (its box inverted) records nothing.
5. **Hysteresis.** The margin is it: the candidates are gathered again only after the eye has moved the margin (or the sun turned), never on a frame where a tree crosses a boundary. The drawn set is exact, so a boundary tree flickers only where a fresh selection would, and a fresh one is a function of the eye: the near boundary lies inside the model to card dither, the shadow cap's ring moves with the eye as today.
6. **The cut each frame.** A linear pass collects the passing candidates as `Tree_Ranked` (distance squared, key, index); past the cap, a quickselect (`select_nearest_ranked`) puts the limit nearest by (distance squared, key) first and the first one cut at `[limit]`, whose distance is `near_distance` (the same order statistic today's full sort reads). The kept indices are sorted ascending. When the cut's inputs (the camera, the frustum or the cascade, the extent, the row's distance and limit, the gather count) are bit equal to the last cut's, the cut is skipped: a still camera costs nothing (the shadow's sun moves every tick while unpaused).
7. **Buffers.** One instance buffer per view and pass (near, shadow), not per model: the selection is packed grouped by species (decision 9), and each group draws from its range by pointing the instance attributes at its byte offset (GL 3.3 and GLES 3.0 have no base instance, the offset does it). One capacity and one upload per pass; the item's "per tree kind" is met by the ranges. The packed instances go up only when the kept indices differ from the last packed or a gather happened; otherwise nothing is uploaded. Capacity in instances: at least `INSTANCE_BUFFER_LEAST_CAPACITY` (256), the next power of two at or above the count, grown only (unload, `rlgl.LoadVertexBuffer(nil, capacity × 64, true)`), at most the row's limit rounded up (8192 near, 16384 shadow by the data's bounds: 0.5 and 1 MB). The update is `rlgl.UpdateVertexBuffer` (`glBufferSubData`, core in GL 3.3 and GLES 2.0); present in `shared/raylib`'s Linux and Android archives and the Windows `raylib.lib` (checked with `nm` and `strings`). Rejected: a slot per tree updated sparsely (a leaving tree's hole needs a degenerate instance), and a ring of buffers (no evidence yet of a stall; see question 2).
8. **The draw.** `draw_mesh_instances` binds the model mesh's own vertex array (`mesh.vaoId`, made by `UploadMesh`, its element buffer included), points locations 9 to 12 (`INSTANCE_TRANSFORM_LOCATION`) at the pass's buffer with divisor 1, and draws `rlgl.DrawVertexArrayElementsInstanced(0, triangleCount × 3, nil, count)` when `mesh.indices != nil`, else `rlgl.DrawVertexArrayInstanced(0, vertexCount, count)`: what `DrawMeshInstanced` does (`rmodels.c` 1704 to 1940 of raylib 6.2) without its `RL_CALLOC`, `MatrixToFloatV` loop and buffer made and deleted per call. The bytes are the same: the Odin matrix's column major storage is what `MatrixToFloatV` produced from the cast (`test_tree_instance_packs_species_and_shade`). The material part (shader, `colDiffuse`, `colSpecular`, view, projection and normal matrices when the shader has them, every map with a texture bound at its unit and its sampler set, mvp = `instanced_mvp()`, then unbound) is ported as `begin_instanced_material` and `end_instanced_material`, so the tree shader gets the atlas on unit 0 and the sun's map on unit 2 and the depth material its default texture as today. No batch flush, as `DrawMeshInstanced`. Re-pointing the mesh's array per draw keeps nothing to rebuild when models reload. The mesh's array keeps pointing at the last buffer afterwards, as it kept pointing at the deleted one after `DrawMeshInstanced`, so anything else drawing a tree mesh meets the state it meets today.
9. **Groups by species index, not machine.** A candidate's group is `tree_instance_species(instance) % species_count` (0 for every tree without species), so a reload that changes a species' machine needs no gather; the draw takes `species_list[group].machine`'s model and skips a group without one, while the cut counts every tree as today. While every species stands in with the pine, a pass draws the pine up to five times instead of once; after 0329 to 0333 each species is its own model anyway.
10. **The felled check moves to the gather**, after the geometric tests (today the shadow scan hashes every instance first). `update_field_tree_cache` drops a felled key from its tile before any viewport draws, and that drop is a change (decision 4).
11. **Split screen.** No tree selection is shared today: each viewport selects with its own camera (the terrain's selection is the shared one). Each viewport keeps its own view (`Field_Tree_Cache.views[FIELD_TREE_VIEWS]`, 4, indexed by the viewport's index; the preview uses 0), so no buffer is written twice in a frame and no viewport invalidates another's. The rules hold whichever viewport last used a slot, since they read only their inputs; after a removal shifts the viewports, a slot's next look gathers again or keeps candidates that are still exact for the new camera. 0342's views with two players on one spot gather twice, as they cut twice today.
12. **0342 and 0343.** The work lands in 0342's sections Shadow_Trees (the update and draw of the shadow pass) and Trees (`draw_field_trees`); the GPU sections stay within noise (same instances, same shaders). 0342's counters Near_Trees and Shadow_Trees become `len(view.near.selected)` and `len(view.shadow.selected)` and must read the same before and after for a view: a free identity check in the table. 0342's `count_draw_call` at the `DrawMeshInstanced` line goes into `draw_mesh_instances`, once per group draw; whichever item lands second moves it. 0343 changes `prepare_field_frame`'s row (`field_trees_view_row`) and adds evictions; neither touches what this item reads (decision 4).
13. **Left as is:** `select_far_tiles` (a pass over every cached tile per viewport, about 550 at 1024 m) and the cover. Question 3.

### Files and procedures

`src/render_instancing.odin` (header comment: the trees' near and cast models draw from a persistent buffer through the mesh's array)
- `INSTANCE_BUFFER_LEAST_CAPACITY :: 256`.
- `instance_buffer_capacity :: proc(capacity, count: int) -> (new_capacity: int, grow: bool)`: pure; `count <= capacity` keeps it (also 0, 0); else the larger of 256 and the next power of two at or above `count`.
- `upload_instances_in_place :: proc(buffer: ^u32, capacity: ^int, instances: []matrix[4, 4]f32)`: grows through `instance_buffer_capacity` (unloads the old buffer), then `rlgl.UpdateVertexBuffer(buffer^, raw_data(instances), i32(len(instances) * 64), 0)` and `rlgl.DisableVertexBuffer()`; nothing for no instances.
- `begin_instanced_material :: proc(material: rl.Material)` and `end_instanced_material :: proc(material: rl.Material)`: decision 8's port (`rl.MAX_MATERIAL_MAPS`; cubemap for `IRRADIANCE`, `PREFILTER`, `CUBEMAP`; uniforms through `rlgl.SetUniform` and `rlgl.SetUniformMatrix` only where the location is not -1, as raylib); end disables the textures, the array, the buffers and the shader.
- `draw_mesh_instances :: proc(mesh: rl.Mesh, instance_buffer: u32, first, count: int)`: between begin and end; decision 8, attribute offset `first * size_of(matrix[4, 4]f32) + column * size_of([4]f32)`, stride 64; `rlgl.DisableVertexArray()` after.

`src/render_field_trees.odin`
- Header comment: the views, the held candidates, the exact cut, the buffers.
- Constants: `FIELD_TREE_VIEWS :: 4` (the loop's `MAXIMUM_VIEWPORTS`, asserted there), `FIELD_TREE_CHANGE_RING :: 64`, `TREE_CANDIDATE_MARGIN_DIVISOR :: 8`, `TREE_CANDIDATE_SLACK_METRES :: 0.25`.
- Types:
  - `Field_Tree_Change :: struct {minimum, maximum: [3]f32}`;
  - `Field_Tree_Cache` gains `revision, cleared_at: u64`, `changes: [FIELD_TREE_CHANGE_RING]Field_Tree_Change`, `views: [FIELD_TREE_VIEWS]Tree_View`;
  - `Tree_Candidate :: struct {instance: matrix[4, 4]f32, key: Tree_Key}`;
  - `Tree_Ranked :: struct {distance_squared: f32, key: Tree_Key, index: u32}`;
  - `Tree_Group :: struct {first, count, drawn_first, drawn_count: int}` (in candidates, in packed);
  - `Tree_Pass :: struct {candidates: [dynamic]Tree_Candidate, groups: [MAXIMUM_TREE_SPECIES]Tree_Group, group_count, gathers: int, ranked: [dynamic]Tree_Ranked, next, selected: [dynamic]u32, packed_gathers: int, packed: [dynamic]matrix[4, 4]f32, buffer: u32, capacity: int, uploaded: bool}`;
  - `Near_Tree_Gather :: struct {built: bool, eye: [3]f32, near_metres: int, margin_metres, radius_metres: f32, species_count: int, revision: u64}`;
  - `Near_Tree_Cut :: struct {camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, near_metres, near_limit, gathers: int}`;
  - `Tree_View :: struct {near: Tree_Pass, near_gather: Near_Tree_Gather, near_cut: Near_Tree_Cut, near_distance: f32, shadow: Tree_Pass, shadow_gather: Shadow_Tree_Gather, shadow_cut: Shadow_Tree_Cut}`.
- Removed: `Near_Tree`, `select_near_trees`, `draw_tree_instances` (the first two move into the tests, below).
- The cache's changes:
  - `note_field_tree_change :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile_Draw)`: nothing when `tile.minimum.x > tile.maximum.x`; else `revision += 1`, `changes[revision % RING] = {tile.minimum, tile.maximum}`.
  - `insert_field_tree_tile :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile, draw: Field_Tree_Tile_Draw)`: stores it and notes it; `take_finished_field_tree_tiles` uses it.
  - `evict_field_tree_tile :: proc(cache: ^Field_Tree_Cache, tile: Field_Tree_Tile)`: notes, releases, deletes the key; the eviction loop of `update_field_tree_cache` uses it.
  - `drop_field_tree_key`: notes the tile after a drop.
  - `clear_field_tree_tiles`: then `revision += 1; cleared_at = revision`.
  - `destroy_field_tree_cache`: `release_tree_view` on every view first.
  - `field_tree_changes_since :: proc(cache: ^Field_Tree_Cache, since: u64) -> (changes: []Field_Tree_Change, complete: bool)`: temp allocator, oldest first; not complete when `since < cleared_at` or `revision - since > FIELD_TREE_CHANGE_RING`.
- Pure helpers:
  - `tree_candidate_margin_metres :: proc(config: Field_Trees_Row) -> f32`;
  - `squared_distance_metres :: proc(first, second: [3]f32) -> f32`: `offset.x * offset.x + offset.y * offset.y + offset.z * offset.z`, the one expression every distance test and rank uses;
  - `tree_species_group :: proc(instance: matrix[4, 4]f32, species_count: int) -> int`;
  - `group_tree_candidates :: proc(pass: ^Tree_Pass, groups: ^[MAXIMUM_TREE_SPECIES][dynamic]Tree_Candidate, species_count: int)`: concatenates the per group lists (temp) into `pass.candidates`, sets `groups` and `group_count = clamp(species_count, 1, MAXIMUM_TREE_SPECIES)`, `gathers += 1`;
  - `tree_ranked_before :: proc(first, second: Tree_Ranked) -> bool`: distance squared, then `tree_key_before`;
  - `select_nearest_ranked :: proc(ranked: []Tree_Ranked, count: int)`: needs `count < len(ranked)`; afterwards `ranked[:count]` are the `count` first by `tree_ranked_before` and `ranked[count]` the next. Hoare partition round the median of the first, middle and last; after `2 × bits.len(uint(len(ranked)))` rounds it sorts what is left with `slice.sort_by`, so the worst case stays n log n;
  - `finish_tree_cut :: proc(pass: ^Tree_Pass, limit: int) -> (cut_distance_squared: f32, cut: bool)`: from `pass.ranked` fills `pass.next` ascending: all when `len <= limit`, else the `limit` nearest after `select_nearest_ranked`, with the first cut's distance;
  - `commit_tree_selection :: proc(pass: ^Tree_Pass)`: when `packed_gathers == gathers` and `next` equals `selected` (`slice.equal`), nothing; else swaps them, packs (`pack_tree_selection`), `packed_gathers = gathers`, `uploaded = false`;
  - `pack_tree_selection :: proc(pass: ^Tree_Pass)`: `packed` = the selected candidates' instances in order, each group's `drawn_first` and `drawn_count`;
  - `release_tree_pass :: proc(pass: ^Tree_Pass)` (the arrays; `unload_instanced_buffer(0, pass.buffer)`) and `release_tree_view :: proc(view: ^Tree_View)`.
- The near pass:
  - `gather_near_tree_candidates :: proc(pass: ^Tree_Pass, cache: ^Field_Tree_Cache, eye: [3]f32, radius_metres: f32, felled: map[Tree_Key]struct{}, species_count: int)`: tiles whose bases box lies within the radius (`box_distance_metres`), then each instance within it (squared), then not felled.
  - `near_tree_candidates_stale :: proc(cache: ^Field_Tree_Cache, gather: Near_Tree_Gather, camera: [3]f32, near_metres, species_count: int) -> bool`: decision 2; a change reaches when `box_distance_metres(change box, gather.eye) <= gather.radius_metres`.
  - `cut_near_trees :: proc(pass: ^Tree_Pass, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, config: Field_Trees_Row) -> (near_distance: f32)`: ranks the candidates within `near_metres` (squared, compared before the frustum, as today) whose base ± extent box is in the frustum, `finish_tree_cut` at `near_limit`; `near_distance` is `sqrt` of the cut's distance squared, else `near_metres`.
  - `update_near_trees :: proc(cache: ^Field_Tree_Cache, view: ^Tree_View, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, felled: map[Tree_Key]struct{}, species_count: int) -> (near_distance: f32)`: stale gathers again at `near + margin + slack` (`near_gather` with `revision = cache.revision`), else `near_gather.revision = cache.revision`; the cut when its inputs differ from `near_cut` (then `commit_tree_selection`); returns `view.near_distance`. Uses `cache.config`.
- `draw_tree_pass :: proc(models: Model_Renderer, species_list: []Field_Tree_Species, pass: ^Tree_Pass, material: rl.Material)`: `upload_instances_in_place` unless `uploaded` (then `uploaded = true`); nothing more without instances or species; `begin_instanced_material`, per group below `len(species_list)` with a drawn count and a model (`machine_model`, `body[.Lit].vertexCount > 0`) `draw_mesh_instances(model.body[.Lit], pass.buffer, drawn_first, drawn_count)`, `end_instanced_material`.
- `draw_field_trees`: `view := &cache.views[scene.tree_view]`; `near_distance := update_near_trees(cache, view, camera.position, frustum, extent, scene.state.field.felled_trees, len(species))`; the uniforms as today; `draw_near_trees(scene.models, species, &view.near, brightness_color(sky))`; the cards unchanged.
- `draw_near_trees :: proc(models: Model_Renderer, species_list: []Field_Tree_Species, pass: ^Tree_Pass, daylight: rl.Color)`: as today, ending in `draw_tree_pass`.

`src/render_sun_shadows.odin`
- Types: `Shadow_Tree_Gather :: struct {built: bool, grown: Sun_Shadow_Cascade, half_size, reach_metres, extent_metres, margin_metres, span_metres: f32, species_count: int, revision: u64}`; `Shadow_Tree_Cut :: struct {cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, limit, gathers: int}`.
- `grown_sun_shadow_cascade :: proc(cascade: Sun_Shadow_Cascade, growth_metres: f32) -> Sun_Shadow_Cascade`: `half_size` plus the growth, the rest as is (only the box test reads it).
- `shadow_gather_span_metres :: proc(cascade: Sun_Shadow_Cascade, extent_metres, margin_metres: f32) -> f32` and `shadow_gather_covers :: proc(gather: Shadow_Tree_Gather, cascade: Sun_Shadow_Cascade) -> bool`: decision 3.
- `gather_shadow_tree_candidates :: proc(pass: ^Tree_Pass, cache: ^Field_Tree_Cache, grown: Sun_Shadow_Cascade, extent_metres: f32, felled: map[Tree_Key]struct{}, species_count: int)`: tiles whose bases box ± extent casts in `grown`, then each base ± extent, then not felled.
- `shadow_tree_candidates_stale :: proc(cache: ^Field_Tree_Cache, gather: Shadow_Tree_Gather, cascade: Sun_Shadow_Cascade, extent_metres, margin_metres: f32, species_count: int) -> bool`: decision 3; a change reaches when its box ± the gather's extent casts in `gather.grown`.
- `cut_shadow_trees :: proc(pass: ^Tree_Pass, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, limit: int)`: ranks the candidates whose base ± extent casts in `cascade` by `squared_distance_metres(base, eye)`, `finish_tree_cut` at `limit`; none at limit 0.
- `update_shadow_trees :: proc(cache: ^Field_Tree_Cache, view: ^Tree_View, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, felled: map[Tree_Key]struct{}, limit, species_count: int)`: as `update_near_trees`, margin from `cache.config`.
- Removed: `select_shadow_trees` (into the tests).
- Comments: the map slot and `use_sun_shadow_sampler` name `begin_instanced_material` beside `DrawMesh`; `set_sun_shadow_instanced` names `draw_tree_pass`.

`src/loop_field_session.odin`
- `Field_Scene.tree_view: int`: the viewport's index in the frame's viewports, the tree cache's view it draws with (0343's and 0342's fields beside it); 0 in the planet preview.
- `#assert(FIELD_TREE_VIEWS >= MAXIMUM_VIEWPORTS)` near `Field_Scene`.
- `draw_field_viewport_world`: `tree_view = viewport_index(state, viewport)` in the scene literal.
- `draw_field_sun_shadows`: inside the trees' `if`, `view := &scene.renderer.trees.views[scene.tree_view]`, `update_shadow_trees(&scene.renderer.trees, view, cascade, camera.position, field_tree_model_extent(scene), scene.state.field.felled_trees, inputs.row.tree_limit, len(scene.content.field.tree_species))`, then `set_sun_shadow_instanced(true)`, `draw_tree_pass(scene.models, scene.content.field.tree_species, &view.shadow, shadows.material)`, `set_sun_shadow_instanced(false)`.

`src/viewport.odin`
- `viewport_index :: proc(state: ^Frame_State, viewport: ^Viewport) -> int`: its index among `active_viewports`, 0 when not found.

`data/shaders/tree.vs` and `data/shaders/sun_shadow.vs`: the header comments say the near and cast models' transforms come from a view's instance buffer (`draw_tree_pass`), not `DrawMeshInstanced`. Comments only.

### Memory and its lifetime

Per view and pass: the candidates (76 bytes each: about 0.5 MB near and 0.9 MB shadow in the forest), `ranked` (20 bytes each), `next` and `selected` (4 bytes each, at most the limit), `packed` (64 bytes each, at most the limit) and one GL buffer (64 bytes × capacity); four views at most. A pass replaces its own arrays and buffer only inside its own update and draw, before its draw, and no other draw reads them; a grown buffer is deleted after no draw of this frame used it. Everything is freed with the cache (`destroy_field_tree_cache`: `stop_field_presentation` and the preview's teardown, both between frames). The per group lists of a gather are in the frame's temp memory.

### Tests

`src/render_field_trees_test.odin`
- Helpers:
  - `fresh_near_trees :: proc(cache: ^Field_Tree_Cache, camera: [3]f32, frustum: render_frustum.Frustum, extent_metres: f32, felled: map[Tree_Key]struct{}, config: Field_Trees_Row, species_count: int) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32, near_distance: f32)`: a temporary `Tree_Pass`, `gather_near_tree_candidates` at radius `near_metres`, `cut_near_trees`, the selection's keys sorted (`tree_key_before`) with their instances; temp allocator, the pass released.
  - `tree_selection_test_forest :: proc(cache: ^Field_Tree_Cache, camera: [3]f32, skip: Field_Tree_Tile)`: tiles (x, 0, z) for x and z in -2 to 1, each 64 m from `camera.x + 64x`, `camera.z + 64z`, a tree every 2 m (1024 a tile) on the plane 1.6 m below the camera, each moved by up to 0.8 m in x and z by a hash of its index, species `index % 3`, shade 1, keys `{64x + i, 0, 64z + j}`; `skip` left out. `tree_selection_test_tile` makes one tile (also for an insert).
  - `tree_test_frustum :: proc(eye: [3]f32, yaw_degrees: f32) -> render_frustum.Frustum`: `linalg.matrix4_look_at_f32` along the yaw in the x, z plane with up +y, `matrix4_perspective_f32` at 70 degrees, 16:9, 0.1 to 32000.
- `test_the_near_selection_caps_and_pulls_in` and the shadow test below: through the fresh helpers, every assertion as today.
- `test_the_cached_near_trees_equal_a_fresh_cut_along_a_walk`: the forest round {0, 8000, 0} without tile (1, 0, 0); config near 48, limit 300, fade 12 (margin 6 m); 240 steps of 0.25 m along +x, the yaw turning 3 degrees a step; extent 4, species count 3. Each step `update_near_trees(&cache, &cache.views[0], ...)` against `fresh_near_trees`: the selected keys equal, `near_distance` equal (`==`). The cap binds at some step (`near_distance < 48`). Step 80: tile (1, 0, 0) inserted (`insert_field_tree_tile`), `view.near.gathers` grows at that step. Step 120: the key of the first selected candidate felled (`felled`, `apply_felled_field_trees`): absent from the next selection, still equal to fresh. After the walk, `gathers` is below 16 (reuse happened; 60 m at a 6 m margin plus the insert and the felling). `destroy_field_tree_cache` frees the views.
- `test_the_near_cut_keeps_the_nearest_by_distance_then_key`: one tile of 30 trees: 10 at 3 m, 10 at 5 m (keys in shuffled order), 10 at 7 m, all in the zero frustum. Limit 15: the 10 at 3 m and the 5 lowest keys at 5 m, `near_distance` 5. Limit 1: one at 3 m (the lowest key), 3. Limit 30 and near 48: all, 48.
- `test_selecting_the_nearest_matches_a_full_sort`: arrays from a fixed linear congruential sequence, sizes 2, 3, 17, 1000 and 5000, distances from 16 values (ties), unique keys; counts 0, 1, half and size − 1: the sorted keys of `ranked[:count]` equal those of a `slice.sort_by(tree_ranked_before)` copy's prefix, and `ranked[count]` equals its `[count]`. An ascending and a descending 5000 finish with the same result.
- `test_a_tree_pass_packs_by_species_and_goes_up_only_on_change`: one tile of 30 trees at 1 to 30 m on +x, species cycling 0, 1, 2; near 48, limit 100, species count 3. After `update_near_trees`: each group holds 10 candidates contiguously, `packed[drawn_first:][:drawn_count]` of group g are all species g, `uploaded` false. Then `uploaded = true` (as an upload leaves it): the same inputs again keep it true and the gathers at 1; the camera 0.1 m along -x runs the cut and keeps it true (the same 30 trees); limit 10 sets it false with 10 packed. `instance_buffer_capacity`: (0, 0) keeps 0; (0, 1) gives 256 and grows; (256, 256) keeps; (256, 257) gives 512; (512, 3000) gives 4096; (4096, 10) keeps.
- `test_tree_changes_name_what_reaches_a_view`: the forest; a near gather at {0, 8000, 0}, radius 54.25. A tile inserted 40 m away: one change, complete, stale. Gathered again: not stale. The corner tile (−2, 0, −2) evicted, 90 m away: one change, not stale. 65 inserts of tiles 200 m out: not complete, stale. `clear_field_tree_tiles` after a fresh gather: stale.

`src/render_sun_shadows_test.odin`
- `fresh_shadow_trees :: proc(cache: ^Field_Tree_Cache, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, felled: map[Tree_Key]struct{}, limit, species_count: int) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32)`: gather in the cascade itself (growth 0), cut, sorted keys.
- `test_shadow_trees_are_the_nearest_inside_the_casters_box`: through `fresh_shadow_trees`, assertions as today.
- `test_the_cached_shadow_trees_equal_a_fresh_cut_along_a_walk_under_a_turning_sun`: the forest round {0, 8000, 0}; `sun_shadows_test_row()` with `tree_limit` 400; trees config near 48 (margin 6); up +y; 240 steps of 0.25 m along +x, the day fraction from 0.1 rising 0.0004 a step; each step the cascade from `sun_shadow_cascade`, `update_shadow_trees` against `fresh_shadow_trees`: the keys equal. The cap binds (400 kept). Step 120: a selected key felled as above. `view.shadow.gathers` above 1 and below 40.

Mark `// slow` what `build/test_times.tsv` shows at 1 s or more.

### Docs

- `doc/presentation.md`, The field session, the trees bullet: per viewport a view of the cache (`Tree_View`, four); the near candidates held while the camera stays within an eighth of `near_metres` and no change in reach (the ring), cut exactly each frame (`cut_near_trees`, ties by key); one instance buffer per view and pass, written only when the selection changed and drawn per species through the model's own vertex array (`draw_tree_pass`). The sun's shadow bullet: the casting trees likewise (`update_shadow_trees`, the grown box and the sun's turn of decision 3) in place of `select_shadow_trees`.
- `doc/code_map.md`: the `render_field_trees.odin` line (`update_near_trees`, `Tree_View`, the change ring; no `select_near_trees`), the `render_sun_shadows.odin` line (`update_shadow_trees`, no `select_shadow_trees`), the `render_field_cover.odin`, `render_instancing.odin` line (`upload_instances_in_place`, `draw_mesh_instances`), the `viewport.odin` line (`viewport_index`). No new cluster edge: presentation names no loop symbol (`FIELD_TREE_VIEWS` is its own; the loop asserts).

### Hand-back check

- Memory a frame draws from: each pass replaces only its own arrays and buffer before its own draw; the views go with the cache, between frames. A test runs the update and then reads what the draw would read (`packed`, the groups).
- A list that grows: the candidates are bounded by the reach (the probe's forest: 6,821 and 11,426), `packed` and the buffer by the row's limit (data bounded), the ring is fixed; nothing reaches the HUD.
- Tests touch no state: everything is in memory, no GL (the upload and the draw are untested, as today's).
- Not applicable: file writes, parsed numbers, the save layout, shared budgets, UI audit cases.

### Questions to the main agent

1. Decision 1 reads the goal as "identical always, the scan out of the frame" and leaves a linear pass over the candidates each frame (6,821 and 11,426 in the forest) with an upload in most walking frames. The literal "falls to what changed" (a held drawn set) costs either the GPU (a frustum free superset) or visible differences. Confirm the reading.
2. `glBufferSubData` into a buffer the previous frame's draw may still read: desktop drivers order or copy it; the phone and Winlator are unmeasured, and 0342 has no GPU timer on Android. Accept, or ask for a ring of buffers now?
3. `select_far_tiles` walks every cached tile per viewport each frame (about 550 at 1024 m); the same held candidate treatment would fit. A new item?

### Decisions (main agent, 2026-11-11)

1. The reading of the goal is accepted: the scan's candidates are cached and each frame makes one exact pass over them, so the drawn set is always a fresh selection's. The rebuilds fall from every frame to 5 or 6 in 600.
2. The buffer is updated in place. If the phone or Winlator stalls on it, a ring of buffers is a fix round of its own item, found by 0342's table on the phone, not built ahead.
3. The far tiles' pass (`select_far_tiles`) is not in this item: a note for `SUGGESTIONS.md` at the landing, weighed against 0342's table.
4. Implemented after 0342 has landed, so the before run is `main` without it.

### Deviations (implementation, 2026-11-12)

- `select_nearest_ranked` moves the median of three to the front and partitions round it in the classic Hoare form (`partition_ranked`), which keeps the split below the last entry, so every round shrinks the range.
- `test_tree_changes_name_what_reaches_a_view`: every forest tile lies 0 m or about 63 m and more from the gather, so the tile "40 m away" and the 65 tiles "200 m out" are one tree tiles (`tree_draw_test_tile`) at new tile keys.
- `shader_source_test.odin`: two comments named `DrawMeshInstanced` and now name `draw_mesh_instances` (comments only).
