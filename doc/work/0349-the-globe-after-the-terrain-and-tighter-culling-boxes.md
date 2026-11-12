# 0349: The globe after the terrain, and tighter culling boxes

Status: verified (2026-11-13)

The far globe is drawn first, under all the terrain, so its covered pixels are shaded; and a terrain node is culled by its whole cube (256 m at level 3) widened by 4 cells, though its mesh's bounds are known at upload (`work/performance_research_0340.md`, 2.6).

## Goal

Less overdraw from the globe and fewer terrain nodes drawn, with the same picture.

## Controls

None.

## Change

- The globe drawn after the opaque terrain, so the depth test rejects what the terrain covers.
- A node culled by its mesh's own bounds.

## Verify

- The checks and the suite.
- 0342's table: the globe's pass on the GPU, the drawn node and triangle counts and the shadow pass's casters in the spring and ridge views, before and after.
- Captures before and after, sent to the user.

## Specification (design, 2026-11-11)

Brought up to `main` at `85e046f` on 2026-11-12: the casters' test sits in `sun_shadow_node_casts` (0348), which the kept map's fingerprint calls too, so the casters read the terrain mesh's own box and a node keeps two boxes (decision 6); the caves' walls (0327) and the water's waves (0344) are positions the bounds hold; the globe stays outside 0360's flat batches; `Water_Nodes` stays in `draw_field`; the acceptance reads 0348's redraw-only shadow counts under the views' noon sun; the probe is marked as taken before the caves, 0343 and 0354; 0348's test helper takes the boxes.

Designed against `main` at `4145ed0` and 0342's specification; 0342 (`Field_Scene.profile`, the sections Globe, Terrain, Cover and Water, the counters), 0343 and 0348 have landed since. The acceptance is 0342's table before and after.

### Decisions

1. **The order.** `draw_field_scene` after `set_model_open_sky`: the terrain, the cover, the globe, the water (`FIELD_PASS_ORDER`, `draw_field_passes`), then the rest as today: the foundations (0347's instanced bricks), the machines (`draw_entities`, then `draw_scene_model_instances`), the trees (`draw_field_trees`, 0346), the runs and poles and the torches' boxes (0360's flat batches), the players, the open sky off, the flames, the ghosts; the arrival's entry and debris after the scene. The cover goes before the globe: it is opaque (`cover.fs` writes alpha 1, no `discard`), writes depth and stands on the terrain, so a tuft at a crest against the far globe also rejects the globe's pixel behind it. The water stays after the globe: it blends without depth writes over whatever lies behind it, as today.
   - Only the terrain and the cover move ahead of the globe, and neither reads the depth or blends, so every pixel ends as today: where they lie in front of the globe they win in both orders, where they lie behind it (decision 4's pit) the globe now overwrites them where it hid them. Everything from the water on meets the depth and colour it meets today.
   - The globe draws through the model shader by `DrawMesh`, so it must stay outside every `begin_flat_batch` region (0360's rule in `render_model_instances.odin`). Its new place, before the foundations, is outside all of them, and between `set_model_open_sky` and it only the field's and the cover's shaders draw, so the model shader's switches and uniforms are those of its old place.
2. **GL state per pass.** Inside the viewport's `BeginMode3D`: depth test on, `GL_LEQUAL`, alpha blending on, back faces culled (rlgl's defaults). The sky before it runs in its own `BeginMode3D` with the depth test, the depth writes and the culling off (`draw_sky`), unchanged.
   - Terrain: the field shader, `water_color` alpha 0, depth writes on; output alpha 1, so the blend copies.
   - Cover: the cover shader, instanced, depth writes on, culling off for foliage and on for stones, back on at its end; the shadow map bound on unit 2 and unbound (`draw_field_cover`, unchanged).
   - Globe: the model shader's lit material, one `DrawMesh` of the sphere (64 rings by 128 slices), depth writes on, back faces culled, alpha 1. `model.fs` has no `discard` and writes no `gl_FragDepth`, so the early depth test rejects every fragment behind the terrain and the cover before it shades.
   - Water: the field shader with `FIELD_WATER_COLOR`, depth writes off, then on again (`draw_field_water`, unchanged).
3. **Depth.** The globe keeps its depth writes, so everything drawn after it meets the depth it meets today. Under `GL_LEQUAL` a tie now goes to the globe (drawn second), so the gap was checked. The globe lies `FIELD_GLOBE_MARGIN_METRES` (8 m) under the lowest relief; on the shipped home that is 83 m under the radius (radius 8000 m, lowest relief −75 m, from the probe). A ray between two concentric spheres crosses at least their radial gap, so a terrain fragment lies at least 8 m in front of the globe's on its ray, and the sphere's facets sag 2.4 m further in. The 24 bit depth step at distance d with the near plane at `FIELD_NEAR_METRES` (0.1 m) is about d² / (0.1 · 2^24): 0.04 m at 256 m, 0.16 at 512, 0.63 at 1024, 1.3 at 1,470 m (the far corner of a level 3 node selected at 1024 m). The closest pair is thus 6 steps apart at the deepest point of the relief and far more on land: no tie. The caves (0327) lie above the sea level plus `dry_metres`, so above the sea's floor and far over the globe. The step reaches the 8 m margin at about 3.66 km, which at 1 m spacing only a data last distance over about 3.2 km reaches (`MAXIMUM_FIELD_VIEW_DISTANCE_METRES` allows 4096, 1024 ships): there a tie at the deepest relief would now go to the globe. The window's depth is 24 bits (GLFW's default, `EGL_DEPTH_SIZE` 24 on Android), a split screen target's is rlgl's `GL_DEPTH_COMPONENT` (24 on GLES 3). The near and far planes are unchanged; the planet preview sets the same ones. No depth function, offset or range change is needed.
4. **Unchanged by the order.** The haze and its end fade are per fragment (`apply_haze` in `field.fs` and `model.fs`), not a pass, and both shaders compute the same reach, so the far nodes still fade into the globe. The sun's shadow pass draws into its own target before the 3D pass and never draws the globe. The fall and a short view of 0343 show more globe: its visible pixels shade once either way, only its pixels under the terrain stop shading. A pit or a cave dug under the globe's sphere shows the globe as a floor from outside today and still will (question 2); from inside the sphere the globe's back faces are culled.
5. **The bounds.** Each box is computed on the worker with what it bounds (`run_field_job`'s Mesh case: `mesh_field_grid`, `mesh_field_water_grid`, the cover through `mesh_field_grid`), travels in the result's `mesh`, `water_mesh` and `cover`, and is joined on the main thread at upload. No new field in `Field_Job_Result`.
   - Terrain and water: `Field_Mesh_Data.minimum, maximum`, the extremes of `positions` (metres from the node's origin), set by `field_mesh_from_surface`. That runs after `append_field_skirts`, so the flaps, the cut and the curtains are in `positions`; at levels 0 and 1 so are a cave's walls (0327), which belong to the terrain mesh, so a cave node's box reaches down to its cave. The water's look is written into the grid by the worker before it meshes (0344, `write_field_water_look`), so the waves are in the water's positions. Zero without vertices.
   - Cover: `Field_Cover_Data.minimum, maximum`, world metres, the union of each instance's shape box (`cover_instance_box`): the shape's unit box, sideways to `COVER_SHAPE_REACH` (0.75: foliage's 0.5 plus `cover.vs`'s `part_lean` 0.25 at the top; the stones reach 0.6 and do not lean) and 0 to 1 along the up, through the instance's columns. Per world axis: base + [min(0, U), max(0, U)] ± 0.75 (|R| + |F|), with R, U, F the right, up and forward columns. `cover.vs`'s shrink only pulls vertices towards the base. Set at the end of `place_field_cover`, after the sort and the cut.
   - The node's draw box: `Field_Node_Render.minimum, maximum`, world metres (`field_node_draw_box`): the origin plus the terrain's box when it has triangles, the origin plus the water's when it has triangles, the cover's (its data's `minimum, maximum`) when a kind holds an instance.
   - The node's terrain box: `Field_Node_Render.terrain_minimum, terrain_maximum`, world metres: the origin plus the terrain's box, set with the terrain mesh, zero without one.
   - Cost: 48 bytes in a node's render, 24 in each mesh's and each cover's data. On the worker, 6 comparisons a vertex and a few dozen operations an instance, against a level 0 job's 1.8 ms (measured before the caves). On the main thread, three box joins an upload; the two tests read two vectors each where they built the cube.
6. **Two boxes, one for each test.** `draw_field`'s frustum test reads the draw box; the casters' test, `sun_shadow_node_casts` (`render_sun_shadows.odin`), reads the terrain box; `field_node_box_metres` goes. Since 0348, `sun_shadow_node_casts` serves both `draw_sun_shadow_terrain` and `sun_shadow_terrain_fingerprint`, and a casting node's term hashes only its terrain mesh (`field_mesh_depth_hash`: positions, then indices), so the waves' remeshes keep a kept map. The terrain box is the extremes of those same positions, so a node's casting follows only what its term hashes: a wave or a cover remesh moves the draw box but can neither add nor drop a caster and force a redraw, which the joined box could at the casters' box's edge. The approved design kept one box ("not worth a second"); the probe gave the two boxes the same caster counts but one node in one case of twelve.
   - A redraw when needed: a box changes only in `apply_field_mesh`, which moves `mesh_revision`, so the viewport's next step is at least Compare and the fingerprint is taken over the new boxes. A node that starts or stops casting adds or drops its term and the map is drawn again; a node unloaded drops its term as today.
   - No caster lost: the terrain box holds every terrain vertex, and `sun_shadow_box_casts` separates only on the cascade's three axes, so it never refuses a box that meets the casters' box. A node casting before and after with the same hash draws the same depth, so no stale caster stays.
7. **Edits and empty nodes.** The boxes are fields of the node's render, written only by `apply_field_mesh` together with the meshes they bound. A remesh (an edit, a wave, a neighbour's level change, a frame clearing cover) replaces them at once; until then the old mesh draws with its old boxes. A node whose meshes are both empty gets no render (`apply_field_mesh` returns first), so `draw_field` skips it as before: 375 of the home's 586 selected nodes at 1024 m in the probe.
8. **The probe**, taken on `4145ed0`: before 0327 and 0339 carved the caves, 0343 packed the levels inside the view and 0354 balanced them at edges and corners; not taken again (counts only; the shipped home at 8 km, seed `DEFAULT_WORLD_SEED`, 1 m spacing, the crater baked, water tiles on, the desktop cover row; nodes meshed by the worker's path with the skirt faces of their selection; an eye 1.6 m over the uncratered relief; 70 degrees vertical, 16:9, the game's planes). Selected nodes the frustum keeps, the cube widened by 4 cells → the draw box, at 1024 m (512 m in brackets). The ridge is the highest relief within 1500 m of the home stand on a 25 m grid: 76.552 N, 133.534 E, 104 m.

   | View | north | east | south | west | north, 30° down | east, 30° down | 0342's target |
   |---|---|---|---|---|---|---|---|
   | home (83.171, 130.477) | 67 → 60 (43 → 40) | 82 → 78 (48 → 46) | 84 → 75 (57 → 50) | 78 → 74 (55 → 51) | 63 → 59 (41 → 40) | 84 → 75 (50 → 45) | 89 → 84 (64 → 61) |
   | spring (79.159, 150.561) | 100 → 91 (67 → 58) | 94 → 82 (69 → 57) | 91 → 85 (63 → 57) | 82 → 76 (58 → 52) | 101 → 90 (67 → 57) | 99 → 81 (72 → 57) | 88 → 81 (57 → 51) |
   | ridge | 87 → 85 (54 → 52) | 92 → 84 (66 → 58) | 98 → 89 (73 → 66) | 96 → 87 (68 → 60) | 98 → 90 (64 → 57) | 101 → 87 (75 → 61) | |

   That is 2 to 21 % fewer drawn nodes and 2 to 14 % fewer drawn triangles (the spring east at 1024 m: 201 to 185 thousand). The shadow pass's casters (the desktop row, a sun 60 and 15 degrees up in the east): home 52 → 41 and 58 → 49, spring 54 → 41 and 60 → 46, ridge 62 → 43 and 67 → 50, at both distances: 15 to 31 % fewer. Selected and meshed at 1024 m (512 m): home 586, 211 (446, 134); spring 567, 232 (426, 152); ridge 531, 252 (387, 167).

   What the caves change in kind: levels 0 and 1 mesh cave walls down to `shell_metres` (32 m shipped) under the relief, levels 2 and 3 none. A selected node under the ground that meshed empty now meshes where a tunnel or a chamber crosses it, and a surface node's terrain box reaches down to its cave. Over cave ground (the spring; the home's calm circle holds none) more nodes and triangles are drawn and the tighter box spares less at levels 0 and 1, while levels 2 and 3 meet no cave. The bounds hold every wall, being the mesh's own positions.
9. **Acceptance by 0342** (`./build.sh frame-profile` in the night window). One viewport, 512 m and 1024 m, the home, the spring and the ridge views, before and after; the views stand at noon, the sun overhead:
   - `gpu globe` falls: the globe now shades only its visible pixels. `gpu terrain` stays within noise, since the reorder does not change what the terrain shades; fewer nodes trim its vertex work. The four field sections (`gpu terrain`, `cover`, `globe`, `water`) summed fall.
   - `count terrain_nodes` and `count terrain_triangles` fall, `draws terrain` with them; `cpu terrain` does not rise. Decision 8's shares were taken before the caves, 0343 and 0354: a guide, not a threshold.
   - The shadow counts come only from a frame that draws its kept map (0348): `count shadow_nodes` (its worst is a redraw's casters, its mean follows the redraws) does not rise and falls with the casters, `draws shadow_terrain` with it; `cpu shadow_terrain`, which holds the Compare's fingerprint, does not rise. The probe's 15 to 31 % fewer casters were for a sun 60 and 15 degrees up; with the sun overhead the casters' box stands round the eye, a node's horizontal extent decides most and the box tightens that only by the cube's margin, so the table's fall is not the probe's figure.
   - 0342's `Frame_Section` enum keeps its order, so the before and after tables keep their columns.

### Files and procedures

`src/world_field_mesh.odin`
- `Field_Mesh_Data` gains `minimum, maximum: [3]f32` after `indices`, in its comment: the positions' extremes in metres from the grid's origin, the skirts, a cave's walls and the water's waves included, zero without vertices (0349). `make_field_mesh_data` and `destroy_field_mesh_data` are unchanged.
- `field_positions_bounds :: proc(positions: [][3]f32) -> (minimum, maximum: [3]f32)`: the extremes, zero for none.
- `field_mesh_from_surface`: after its loop, `data.minimum, data.maximum = field_positions_bounds(data.positions[:])`.

`src/world_field_cover.odin`
- `COVER_SHAPE_REACH :: 0.75`, commented as decision 5 says, naming `test_the_cover_box_holds_every_leaned_shape_vertex`.
- `Field_Cover_Data` gains `minimum, maximum: [3]f32`: world metres round every instance's shape (`cover_instances_box`), zero without instances.
- `cover_instance_box :: proc(instance: matrix[4, 4]f32) -> (minimum, maximum: [3]f32)`: decision 5's formula from `cover_instance_base` and the columns 0 to 2.
- `cover_instances_box :: proc(kinds: []Field_Cover_Instances) -> (minimum, maximum: [3]f32, found: bool)`: the union; found is false without instances.
- `place_field_cover`: after the finish loop, `data.minimum, data.maximum, _ = cover_instances_box(data.kinds[:table.kind_count])`; its comment adds the box.

`src/render_field.odin`
- Header comment: the globe is drawn after the terrain and the cover (0349).
- `Field_Node_Render` gains, after `terrain_hash`, `minimum, maximum: [3]f32` (the draw box in world metres, `field_node_draw_box`, which the frustum tests) and `terrain_minimum, terrain_maximum: [3]f32` (the terrain mesh's box in world metres, zero without one, which the sun's casters test, decision 6); its comment names both (0349).
- `Field_Pass :: enum u8 {Terrain, Cover, Globe, Water}` and `FIELD_PASS_ORDER :: [len(Field_Pass)]Field_Pass{.Terrain, .Cover, .Globe, .Water}`, commented with decision 1 in two lines.
- `field_node_draw_box :: proc(origin: [3]f32, mesh, water: Field_Mesh_Data, cover: Field_Cover_Data) -> (minimum, maximum: [3]f32, found: bool)`: decision 5; a mesh counts when it has indices (as `apply_field_mesh` uploads it), the cover when a kind holds an instance.
- `apply_field_mesh`: after the early return, `render.minimum, render.maximum, _ = field_node_draw_box(render.origin, data, water, cover)`; inside its `len(data.indices) > 0` branch, `render.terrain_minimum, render.terrain_maximum = render.origin + data.minimum, render.origin + data.maximum`. Its comment adds the boxes.
- `field_node_box_metres`: removed.
- `field_node_in_frustum :: proc(frustum: render_frustum.Frustum, render: Field_Node_Render) -> bool`: `frustum_contains_box` on the render's draw box.
- `draw_field :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, selection: []Field_Node, lights: Field_Frame_Lights, profile: ^Frame_Profile = nil) -> []Field_Node_Render`: the terrain pass only. The frustum, the uniforms and the loop as now, the visible list returned (`visible[:]`, temp allocator). The cover and water calls leave it, with 0342's Cover and Water marks and the Cover_Instances count; Terrain_Nodes, Terrain_Triangles and Water_Nodes stay counted in its loop. Comment: inside `BeginMode3D`, first of `FIELD_PASS_ORDER`; the cover and the water draw over the list it returns.
- `draw_field_globe` comment: after the terrain and the cover with depth writes, so the depth test rejects what they cover. `draw_field_water` comment: after the terrain, the cover and the globe.

`src/render_field_cover.odin`: the header's "between the terrain and the water" and `draw_field_cover`'s "after the terrain and before the water" become "between the terrain and the globe" and "after the terrain and before the globe and the water" (0349). The cover's per node distance (`box_distance_metres` of the cube) is unchanged.

`src/render_sun_shadows.odin`: `sun_shadow_node_casts` tests `sun_shadow_box_casts(cascade, render.terrain_minimum, render.terrain_maximum)`; its comment: the node's terrain box (0349), so its casting follows only what its term hashes. `draw_sun_shadow_terrain` and `sun_shadow_terrain_fingerprint` are unchanged.

`src/render_frame_profile.odin`: `Frame_Section`'s comment "In frame order" gains: but Globe, drawn after Cover since 0349 and kept in its place so the tables before and after keep their columns.

`src/loop_field_session.odin`
- Header comment: "the globe and the field's terrain and water" becomes "the field's terrain and its cover, the globe and the water (0349)".
- `draw_field_scene`: the four lines `profile_mark(scene.profile, .Globe)`, `draw_field_globe(...)`, `profile_mark(scene.profile, .Terrain)`, `draw_field(...)` become `draw_field_passes(scene, camera, selection, daylight_tint)`.
- `FIELD_PASS_SECTIONS :: [Field_Pass]Frame_Section{.Terrain = .Terrain, .Cover = .Cover, .Globe = .Globe, .Water = .Water}`.
- `draw_field_passes :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, daylight_tint: [3]f32)`: for each pass of `FIELD_PASS_ORDER`, `profile_mark(scene.profile, FIELD_PASS_SECTIONS[pass])`, then: Terrain sets `visible = draw_field(scene.renderer, camera, selection, scene.lights, scene.profile)`; Cover calls `draw_field_cover(scene.renderer, camera, visible, scene.lights.sun_shadow.texture)` and `count_frame(scene.profile, .Cover_Instances, scene.renderer.cover.drawn_count)`; Globe calls `draw_field_globe(scene.renderer, scene.models, daylight_tint)`; Water calls `draw_field_water(scene.renderer, visible)`. The planet preview reaches it through `draw_field_scene` with a nil profile, which `profile_mark` and `count_frame` skip.

No shader or data change.

### Tests

`src/world_field_mesh_test.odin`: `test_the_mesh_bounds_hold_every_vertex_with_its_skirts`.
- Grids: `fill_test_plane_grid` (from `world_field_lod_test.odin`) at origin {0, 0, 0}, steps 1 and 8, slope {38, 14} (as `test_a_sloped_plane_meshes_without_terraces_at_every_level`).
- Each is meshed three ways: with `{}`, with `{flaps = EVERY_FIELD_FACE}`, and with `{flaps = {.Negative_X, .Negative_Z}, curtains = {.Positive_X, .Positive_Z}}`.
- `minimum` and `maximum` equal the positions' extremes, and every position lies within them.
- The flapped mesh's box reaches below the unskirted one's `minimum.x` and `minimum.z` and above its `maximum.x` and `maximum.z`.
- A buried cave (0327's walls are terrain positions): `fill_test_field_grid` at origin {0, 0, 0}, step 1, of `test_buried_pocket_density :: proc(sample: [3]i64) -> i8`, `min(test_large_sphere_density(sample), -test_sphere_density(sample, {16, 12, 16}, 4 * DENSITY_STEPS_PER_SAMPLE))` (a pocket of 4 samples round y 12 under ground whose top lies at y 26 to 30 in the grid), meshed without skirts at 1000 mm: the bounds equal the extremes, and `minimum.y` lies at least 10 m under that of `test_large_sphere_density`'s grid meshed the same way.
- A grid of air only meshes to zero bounds.

`src/render_field_test.odin`
- `test_the_draw_box_joins_the_terrain_the_water_and_the_cover`: hand-made data, origin {100, 200, 300}.
  - Terrain: positions {0,0,0} and {4,1,4}, three indices. Water: positions {1,3,1} and {2,5,2}, three indices. Each mesh's `minimum, maximum` set by `field_positions_bounds`, as `field_mesh_from_surface` sets them. Cover: one instance with base (99, 199, 299), right (2, 0, 0), up (0, 2, 0) and forward (0, 0, 2), its data's `minimum, maximum` set by `cover_instances_box`: (97.5, 199, 297.5) to (100.5, 201, 300.5).
  - The result is (97.5, 199, 297.5) to (104, 205, 304), found.
  - A water with positions but no indices is left out.
  - All three empty gives found false.
- `test_a_node_is_culled_by_its_mesh_not_its_cube`:
  - Node {0, {−2, −1, −2}} at 1000 mm, origin (−64, −32, −64) m. A grid from `fill_test_field_grid` at the node's origin, step 1, of a sphere of 3 samples round sample (−62, −30, −34) (a named proc over `test_sphere_density`, since `Test_Field_Density` takes no captures), meshed without skirts.
  - The camera stands at the origin looking −z, 90 degrees, aspect 1, planes 0.1 and 200, the frustum from `linalg.matrix4_perspective_f32` and `matrix4_look_at_f32` as `render_frustum_test.odin` builds it.
  - The old cube widened by 4 cells, written out in the test as (−68, −36, −68) to (−28, 4, −28), passes `frustum_contains_box`. `field_node_in_frustum` on a render whose `minimum, maximum` are `field_node_draw_box`'s fails: the sphere lies left of the left plane.
  - Looking −x from the same point, the render passes.
- `test_the_globe_draws_after_the_opaque_field`: `FIELD_PASS_ORDER` begins with Terrain (the others draw over its visible list), ends with Water, and Globe's index exceeds Terrain's and Cover's.

`src/render_field_cover_test.odin`: `test_the_cover_box_holds_every_leaned_shape_vertex`.
- The five shapes at the parts of `test_cover_shapes_fit_the_unit_box`, three seeds each.
- Instances from `cover_instance`:
  - a foliage kind and a stone kind of width {0.5, 4} and height {0.3, 4} m;
  - the point (5000, 6000, 1000) m with its up;
  - normals along the up and 40 degrees off it;
  - slope tangents 0 and 0.8;
  - 16 hash sets.
- Every shape vertex, leaned for foliage at the four corners (±0.25 · y on x and on z, `cover.vs`) and at size 1, put through the instance's columns and base, lies in `cover_instance_box` within 1e-3 m.
- `#load("../data/shaders/cover.vs")` holds `const float part_lean = 0.25;`, and `COVER_SHAPE_REACH` is 0.5 plus that lean.

`src/world_field_cover_test.odin`: `test_the_placed_cover_carries_its_box`. `cover_test_setup`, the meadow spot's node (`cover_test_surface_node` of `cover_test_direction` of `COVER_TEST_SPOTS[0]`, ahead and aside 0), its cover by `cover_test_node_cover`. The data holds an instance, and its `minimum`, `maximum` equal `cover_instances_box` of its kinds, with every instance's base and top (`cover_instance_base`, `cover_instance_top`) inside.

`src/render_sun_shadows_test.odin`
- `sun_shadow_test_render` sets both boxes to the node's cube, `field_node_origin_metres(node, 1000)` to it plus 32 m, so 0348's tests keep their casting sets (a still holds the eye, b and w lie as before).
- `test_the_casters_read_the_terrain_box`: the renderer, the nodes a and b and the noon cascade of `test_the_terrain_fingerprint_follows_the_casting_nodes`.
  - b with its terrain box its cube and its draw box from a's origin to b's far corner (a water or a cover reaching the eye): `sun_shadow_node_casts` is false, and the fingerprint over {a, b} equals the one with b's draw box its cube.
  - a with its draw box its cube and its terrain box moved 2 km along x: `sun_shadow_node_casts` is false.

Mark `// slow` what `build/test_times.tsv` puts at 1 s or more; the cover's placed box likely.

### Captures (the main agent, before and after, one viewport, clear weather)

- The horizon where the last level meets the globe, at 512 m and 1024 m: the home stand towards 0342's target, and the ridge looking east, at noon.
- The fall: the arrival's start, and the first seconds once nodes appear, at 1024 m and at 256 m.
- A low sun through the haze: the ridge at `time dusk`, looking towards the sun, the glow running across the far nodes into the globe.
- The spring at 1024 m turned north, east, south and west: no node missing at the frame's edges.

### Docs

- `doc/presentation.md`:
  - The field session, the scene bullet: "the globe (`draw_field_globe`), the field (terrain, its ground cover, then water)" becomes the passes of `FIELD_PASS_ORDER` (`draw_field_passes`, 0349): the terrain, its ground cover, the globe (`draw_field_globe`) after the opaque ground so its covered pixels fail the depth test before they shade, then the water.
  - The ground cover bullet: "`draw_field_cover` draws after the terrain and before the water" becomes "after the terrain and before the globe and the water".
  - Light on the field, the sun's shadow: "the selected nodes' terrain whose box meets the casters' box (`sun_shadow_box_casts`)" becomes "whose terrain box (Field meshes, the culling) meets the casters' box (`sun_shadow_node_casts`)".
  - Field meshes:
    - The water pass: "after every node's terrain" becomes "after the terrain, the cover and the globe".
    - The globe bullet: "drawn every frame before the nodes" becomes drawn after the nodes' terrain and cover and before their water, with depth writes; its 8 m margin keeps it at least 6 depth steps behind the farthest terrain at the shipped 1024 m.
    - A new bullet after the water pass, the culling (0349): a node is drawn when its draw box meets the frustum (`field_node_in_frustum`). The box is the bounds of its terrain mesh (flaps, cut, curtains and a cave's walls included) and of its water mesh (the waves included), both made with the mesh on the worker (`Field_Mesh_Data.minimum`, `maximum`), joined with its cover's instances at their lean (`field_node_draw_box`, `cover_instance_box`) and replaced with the meshes. The sun's casters test the terrain mesh's box alone, so a node's casting follows only what the kept map's fingerprint hashes (Light on the field).
- Code comments as listed above. No new file, so `doc/code_map.md` changes only if `tools/code_graph.py --check` asks.

### Hand-back check

- Memory a frame draws from: the boxes are written in `apply_field_mesh`, inside `upload_streamed_field_meshes` in `prepare_field_frame` before any viewport's shadow pass or draw, with the meshes they bound. Nothing new is freed.
- Tests touch no machine state: every test is in memory.
- The other lines do not apply: no file, save layout, parsed number, budget or list.

### Questions to the main agent

1. The Verify line names "the terrain pass on the GPU". The reorder shows in `gpu globe`, not in `gpu terrain` (decision 9). I specified the acceptance on both and their sum; confirm or reword the Verify.
2. Today and after this item, a pit or a cave mouth dug below the globe's sphere (83 m under the radius at the home) shows the globe as its floor from outside, since the globe's depth hides what lies under it. That is outside this item; it could be a separate item (the globe drawn only beyond the nodes, for example) if the user digs that deep.
3. The probe's ridge (76.552 N, 133.534 E) follows 0342's decision 1 rule within 1500 m of the home stand; 0342's implementer may take it.

### Decisions (main agent, 2026-11-11)

1. The Verify line names the globe's pass and the counts, where the change shows (above).
2. A pit dug under the globe showing the globe as its floor is today's behaviour and stays: a note for `SUGGESTIONS.md` at the landing.
3. 0342's ridge view takes the probe's ridge at 76.552 N, 133.534 E, so both items read the same place.
4. Implemented after 0342 has landed, so the before run is `main` without it.

### Decisions (main agent, 2026-11-12)

1. The specification as brought up to `main` is approved, the two boxes included: the casters read the terrain's box, so a wave or a cover remesh never redraws the kept shadow map.
2. The depth margin past a 3.2 km view distance is documented only; no clamp here. A note for `SUGGESTIONS.md` at the landing.
3. The table before and after is taken in the night window, the before from the commit under this item's. The item may land before it.
