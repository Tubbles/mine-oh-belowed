# 0321: Cracks along the crests

Status: implementing (2026-11-07)

The captures of 0306 and 0307 from 120 m over the home, looking south west (`tmp/shot_terrain_colours/crest_crop.png`, the same place in both builds), show a dashed line of sky along a contour on a far slope and along a crest's silhouette. The seam between two detail levels opens and the skirts do not close it. It came with 0306's relief: the slopes are steeper and taller than the 34 m relief the skirts were sized for.

## Goal

No sky shows through the ground at any distance or height on the shipped planets.

## Controls

None.

## Change

- Find which seam opens: neighbouring levels whose vertices do not meet, or skirts too short for the drop of a steep slope across a coarse cell. Measure it from the relief map mode and a capture.
- Size the skirt from the planet's relief bound or the slope across the cell, or close the seam where the levels meet, whichever the cause needs.
- Docs: `doc/presentation.md` (The field, the skirts).

## Verify

- The checks and the suite, with a test of the seam at the steepest slope the shipped planets make.
- The captures of 0306's views from 40 m and 120 m, with no sky through the ground.

## Specification (design, 2026-11-07)

### Cause

Not the slope and not the vertices: the coarser side of a level seam hangs no skirt. `field_node_skirt_faces` (`src/world_field_lod.odin:412`, the test at line 418) gives a face a skirt only when a coarser node or nothing lies beyond it; since 0173's fix round the coarser node hangs none towards finer ones. Where the coarser mesh ends short of the finer one (the strip of up to half a coarse cell, `append_field_skirts`' comment, lines 554 to 557), the finer node's flap closes the strip from above only: its first leg sinks one cell over two (atan(1/2), 27 degrees, under the ground's plane) and its second leg faces out of the finer node, away from an eye on that side. A ray from the finer side that meets the ground in the strip at a shallow angle (every one under 27 degrees, some steeper ones near the coarser edge) passes over both legs and under the coarser surface, whose back faces `draw_field` culls, and meets no front face: the sky, or the globe 83 m under the radius on lower ground. 0306's relief made such views common (back slopes and crests seen from 120 m); the skirt is sized in cells along the surface and its gradient, so no relief bound enters it.

Evidence (a probe meshing the selected nodes from the generation and casting the capture's rays: eye at the capture's teleport plus 120 m and the 1.6 m eye, yaw 210, pitch -25, fovy 70, 1280 by 720):

- In the window 840 to 879 by 200 to 239 of `home_air120.png`, the rays that meet no front face are the capture's sky pixels, within one: (842 to 843, 217), (846 to 847, 218), (853 to 863, 219), (872 to 873, 220), (877 to 879, 221). They meet the ground 640 to 645 m out at x -1283 to -1285, inside the strip by the face x = -1280 between the level 2 nodes [-10, 61, 5] and [-10, 62, 5] (4 m cells, skirt on `Negative_X`, the eye's side) and the level 3 node [-6, 30, 2] (8 m cells, no skirt towards them), at 10 to 14 degrees to slopes of 7 to 15 degrees.
- The crest from the peak (pixels 760 to 852, 170 to 222): 10 rays pass under a drawn surface. `away_air120.png`'s dark line (pixels 1196 to 1204, 328 to 352): 11 rays meet no face and stay under the ground, so the globe shows, in the ground's colour.
- With skirts on both sides of every level seam, none of these rays is open, and no ray of the 10,300 cast over both views meets a skirt standing more than 0.5 m over the generated ground.
- Planes (the fine and the half resolution node of the flat seam test): on flat ground with the coarser node on the finer one's negative side, rays from the finer side at 2, 10 and 20 degrees are open, none from the coarser side; at 55 degrees from the finer side on either side of the seam; with both sides' skirts none at 0, 20, 40, 55 or 65 degrees, on x and y faces.
- The steepest ground: 58.5 degrees within 1.2 km of the home (a crest 96 m over the radius; across a level 3 cell of 8 m it drops 13 m), 58.3 round the first spring, 35.4 round the away view (latitude 60, longitude 40); 319 of 361,000 points over 50 degrees round the home.

### Change

`src/world_field_lod.odin`:

- `field_node_skirt_faces :: proc(index: Field_Selection_Index, node: Field_Node) -> Field_Faces`: a face hangs a skirt when its neighbour of the same level is not selected (drop `&& neighbour not_in index.holds_finer`): a coarser node, finer nodes or nothing lies there. Each side's flap meets, from above, the rays that pass over the other's. Comment rewritten to say so (the test named in it becomes `test_a_level_seam_is_closed_at_grazing_views`).
- `Field_Selection_Index` keeps `selected` only; `make_field_selection_index` drops the parent walk; `field_node_parent` goes (nothing else calls it). The streaming's signatures stay.
- `append_field_skirts` keeps its geometry. Comments: the file's header (lines 17 to 23: the skirt hangs on both sides of a level seam), `FIELD_SKIRT_REACH` (two of the node's cells out and one down, one cell of the next coarser level for the finer node), `append_field_skirts` (lines 550 to 561: the outward leg covers the strip from above; the flap of the other side meets the shallow rays from this one).
- The streaming is unchanged: `field_skirt_faces_changed` already meshes a node again when its faces change. A coarser node now meshes again when a neighbour splits or merges as well, through the same queue, nearest first: more mesh jobs along a moving level boundary, accepted.

Tests:

- `src/world_field_lod_test.odin`, new `test_a_level_seam_is_closed_at_grazing_views`, with test helpers beside it:
  - `STEEPEST_SHIPPED_RISE :: 222`: tan(60 degrees) times `DENSITY_STEPS_PER_SAMPLE`, the measured 58.5 degrees rounded up, its comment naming the measurement.
  - `append_seam_triangles :: proc(triangles: ^[dynamic][3][3]f64, grid: ^Field_Grid, faces: Field_Faces)`: `mesh_field_surface`, `append_field_skirts` with faces, then each triangle with a corner within 10 samples of x = 0, in samples from the world's origin (`test_grid_vertex_samples`).
  - `ray_meets_front_face :: proc(triangles: [][3][3]f64, origin, direction: [3]f64) -> bool`: Möller and Trumbore, a front face being counter clockwise seen from the origin as `draw_field` keeps them (`determinant := dot(corner1 - corner0, cross(direction, corner2 - corner0))` above 1e-12), the barycentric bounds widened by 1e-9 so a ray along an edge two triangles share meets one.
  - `open_grazing_rays :: proc(triangles: [][3][3]f64, rise: i64) -> int`: rays aimed at the plane of `fill_test_plane_grid` with the slope {rise, 0} (y = (2600 + rise x) / 128) at x from -4 to 4 by 0.1 on the lines z = 8.25 and 16.75, from either side along x (the plane's tangent normalize({1, rise / 128, 0}) times plus or minus one, turned by the angle towards minus the normal normalize({-rise / 128, 1, 0})), at 2, 10 and 20 degrees to the plane, each starting 40 samples back; counts those meeting no front face.
  - The test: the two sides of the flat seam test as nodes (fine {0, {0, 0, 0}} with coarse {1, {-1, 0, 0}}, fine {0, {-1, 0, 0}} with coarse {1, {0, 0, 0}}), at the rises 0 and `STEEPEST_SHIPPED_RISE`: each node's grid from `fill_test_plane_grid(field_node_origin(node), field_node_step(node), {rise, 0})`, its faces `field_node_skirt_faces(make_field_selection_index(the two nodes), node) & {.Negative_X, .Positive_X}` (the other faces border nothing in this selection), and `open_grazing_rays` is 0 for all four. Then the old rule's power: the fine node {0, 0, 0} with `{.Negative_X}` only and the coarse one at {-64, 0, 0} with none, flat, leaves rays open (more than 0).
  - On main it fails: 24 rays open on flat ground beside the coarse node at [-1, 0, 0], 6 on each side at 60 degrees; with the change all four are 0 and the power check sees 24. 0.31 s in the test build, unit tier.
- `test_the_skirt_faces_follow_the_neighbours_levels`: the coarse node's faces are `EVERY_FIELD_FACE` (its +x face borders the finer nodes); the fine node's stay; the comment says the faces towards a node of another level or none hang skirts.
- `test_a_level_seam_on_flat_ground_is_closed_from_above`: the coarse node takes the skirt on its face towards the fine one too (`Positive_X` for the first side, `Negative_X` for the second), as `field_node_skirt_faces` now gives them; the bare check stays.
- `src/world_field_streaming_test.odin`, new `test_a_node_whose_neighbour_splits_meshes_again`, after `test_a_node_whose_neighbour_changes_level_meshes_again`: node {2, {0, 62, 0}} settled beside {2, {1, 62, 0}} has no `Positive_X` skirt; settled beside {1, {2, 124, 0}} instead (one child of that neighbour), its revision rises and `Positive_X` is in `streaming.skirt_faces[node]`. Fails on main (no remesh, no face).

### Docs

- `doc/presentation.md`, Field meshes, the Seams bullet: the flap hangs on every face that borders a node of another level or none, never between nodes of one level (0173's pit rim stays); its legs in the node's own cells (two out along the slope and one below, then two further along the gradient); both sides of a level seam hang one (0321): the finer node's flap closes the strip from above, but a ray from the finer side meeting the ground in the strip at a shallow angle passes over it and under the coarser surface, whose back faces are culled, showing the sky or the globe; the coarser node's flap, reaching under the strip from the other side, meets it from above. Drop "The outward leg covers the strip whichever side the coarser node is on" as the whole story; a coarser node now also meshes again when a neighbour splits or merges.
- The code comments above. `doc/code_map.md` needs no change (`append_field_skirts` on the faces `field_node_skirt_faces` gives).

### Hand-back check

No line applies: no memory a frame draws from, no file, no parsed number, no save or record layout (meshes are not saved), no list on the HUD, no UI audit case, no state directory. The shared budget line: the extra mesh jobs of coarser nodes join the field's job queue nearest first like every other; nothing waits behind them for good.

### The captures afterwards

The terrain views of `tmp/shot_terrain_views.sh` from the four starts: in `home_air120.png` no sky at (842 to 880, 217 to 221) nor along the crest down from the peak; in `away_air120.png` no dark line from (1137, 300) to (1280, 390); in every air view no sky or globe coloured line along a level seam, and no flap standing over the ground there (a sliver of other shading along the seams); the ground views as before.

### Question for the main agent

The user's decision of 2026-10-02 (`doc/log/2026-10-02.md`) took skirts at the level seams with "transition cells only if seams show". Seams showed, but the cause is the one sided skirt rule of 0173, and skirts on both sides close every probed ray, so this keeps skirts; transition cells would be a rewrite of the mesher's borders. Your call whether the clause asks the user first.

### Decisions (main agent, 2026-11-07)

1. Skirts on both sides of a level seam, as designed. The user's 2026-10-02 clause ("transition cells only if seams show") gates the costlier fix, it does not require it; the seams come from 0173's one sided rule, and skirts close every probed ray. No skirt between nodes of one level, so 0173's pit rim stays fixed.
