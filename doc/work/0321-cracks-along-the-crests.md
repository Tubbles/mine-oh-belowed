# 0321: Cracks along the crests

Status: verified (2026-11-07)

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

## Specification (design, 2026-11-07, revised 2026-11-07 after the review)

### Cause

Not the slope and not the vertices: the coarser side of a level seam hangs no skirt. `field_node_skirt_faces` (`src/world_field_lod.odin:412`, the test at line 418) gives a face a skirt only when a coarser node or nothing lies beyond it; since 0173's fix round the coarser node hangs none towards finer ones. Where the coarser mesh ends short of the finer one (the strip of up to half a coarse cell, `append_field_skirts`' comment, lines 554 to 557), the finer node's flap closes the strip from above only: its first leg sinks one cell over two (atan(1/2), 27 degrees, under the ground's plane) and its second leg faces out of the finer node, away from an eye on that side. A ray from the finer side that meets the ground in the strip at a shallow angle (every one under 27 degrees, some steeper ones near the coarser edge) passes over both legs and under the coarser surface, whose back faces `draw_field` culls, and meets no front face: the sky, or the globe 83 m under the radius on lower ground. 0306's relief made such views common (back slopes and crests seen from 120 m); the skirt is sized in cells along the surface and its gradient, so no relief bound enters it.

Evidence (a probe meshing the selected nodes from the generation and casting the capture's rays: eye at the capture's teleport plus 120 m and the 1.6 m eye, yaw 210, pitch -25, fovy 70, 1280 by 720):

- In the window 840 to 879 by 200 to 239 of `home_air120.png`, the rays that meet no front face are the capture's sky pixels, within one: (842 to 843, 217), (846 to 847, 218), (853 to 863, 219), (872 to 873, 220), (877 to 879, 221). They meet the ground 640 to 645 m out at x -1283 to -1285, inside the strip by the face x = -1280 between the level 2 nodes [-10, 61, 5] and [-10, 62, 5] (4 m cells, skirt on `Negative_X`, the eye's side) and the level 3 node [-6, 30, 2] (8 m cells, no skirt towards them), at 10 to 14 degrees to slopes of 7 to 15 degrees.
- The crest from the peak (pixels 760 to 852, 170 to 222): 10 rays pass under a drawn surface. `away_air120.png`'s dark line (pixels 1196 to 1204, 328 to 352): 11 rays meet no face and stay under the ground, so the globe shows, in the ground's colour.
- With skirts on both sides of every level seam, none of these rays is open, and no ray of the 10,300 cast over both views meets a skirt standing more than 0.5 m over the generated ground.
- Planes (the fine and the half resolution node of the flat seam test): on flat ground with the coarser node on the finer one's negative side, rays from the finer side at 2, 10 and 20 degrees are open, none from the coarser side; at 55 degrees from the finer side on either side of the seam; with both sides' skirts none at 0, 20, 40, 55 or 65 degrees, on x and y faces.
- The steepest ground: 58.5 degrees within 1.2 km of the home (a crest 96 m over the radius; across a level 3 cell of 8 m it drops 13 m), 58.3 round the first spring, 35.4 round the away view (latitude 60, longitude 40); 319 of 361,000 points over 50 degrees round the home.

### Revision (2026-11-07, after the review)

The review measured the first round's flap on the coarser side standing over the finer node's ground: a dug pit 1 to 3 m, a placed wall's shelf up to 7.25 m, a cliff top up to 8.5 samples; 0323's gorges, mesas and spires make cliffs at seams common. The Change, Tests and Docs below replace the first round's; the implementer changes the snapshot 4704ffc to them.

The choice, cut and curtain: on a face towards finer nodes the coarser node keeps its mesh inside its own box. Its cells outside a negative face slide along the surface onto the face, which also removes the lid main always had there (the coarser surface's cells -1 over the finer node, up to 3.4 m over a finer pit's floor); and a curtain one cell long hangs from its border into its ground, in the face's plane. The finer node keeps main's flap, which closes the strip from above; a shallow ray from the finer side that passes over that flap meets the curtain, whose front faces the finer side.

Measured (probes in a tree of main; the verifier's scenes on both sides of the seam: pits of radius 2.5 centred up to 6 samples from the plane, a placed wall in each sample column from x -1 to 3, cliffs of 9.5 samples with the top edge up to 5 samples from the plane, as a step or a ramp, high on either side):

| | main | first round | cut and curtain |
|---|---|---|---|
| planar seams at 0 to 85 degrees, rays at 1 to 45 degrees open | 98 flat, 34 at 60 degrees | 0 | 0 |
| the coarser mesh past the plane by over a quarter sample, in the open: pits, walls, cliffs | 415 points up to 3.4 m, 436 up to 1.9, 728 up to 0.75 | 1,529 up to 3.4, 7,978 up to 7.25, 28,340 up to 8.5 | 0, 0, 0 |
| rays at the scenes, to visible ground near the seam, that meet no front face and pass under the drawn surface: flat, pits, walls, cliffs (of 7,332, 31,440, 21,188, 91,636) | 66, 237, 111, 380 | 0 | 0 |
| the eight views of the captures (the four starts at 40 and 120 m, on main be455b7 with 0323's and 0324's relief): rays through the ground | 481 | 4 | the same 4 |
| the views: rays whose first face is a skirt over 0.5 m above the generated ground, the most | 5, 2.02 m | 34, 6.89 m | 11, 3.30 m |

A curtain of half a cell measured the same everywhere; one cell reaches a deeper step at the plane for the same vertices.

Rejected: a curtain without the cut closes the rays but keeps main's lid over finer pits (up to 3 m); a coarser flap clamped to the finer ground needs the finer samples, which the coarser job does not hold; a finer flap reaching under the coarser surface leaves rays open (54 on flat ground, 14 at 60 degrees); transition cells need both levels' samples in one mesh job, so the grid, the jobs and the mesher's borders change, a rewrite for what the cut and curtain already close.

Not closed:

- The curtain hangs from the coarser edge, which stands over the generated ground where the coarser grid misses a dip: of the 11 rays above, 6 meet a curtain, at most 3.30 m over the ground (away 40, a level 3 node's curtain inside its own box, where the first round's flap stood 3.35 m) and 1.43 m at the plane (spring 40). The other 5 meet main's finer flap (2.02 m, newspring 120). At a dug pit the coarser edge at the plane stands up to 3.5 m over the finer floor, as on main: the coarser grid does not see a pit narrower than its cells. No sky shows under either.
- 4 rays of the views meet no face in any mode, main included, each entering the ground within 0.1 m of the relief: three pass through a crest and out again where a level 3 node's crest lies lower (newspring 120 and 40, spring 40), one runs under a level 2 node's top edge below finer nodes (away 120, 337 m). No skirt reaches them.
- The cells the cut leaves keep main's lid where they lie over the finer node (a corner column, or the last row beside a node of the same level: one coarse cell each way), and the finer flap over a pit on the coarser side stays (up to 2.5 m, since 0173).

### Change (revised)

`src/world_field_lod.odin`:

- `Field_Seam_Faces :: struct {flaps, curtains: Field_Faces}`: the faces that hang main's flap (a coarser node or none beyond) and those that cut and hang a curtain (finer nodes beyond).
- `field_node_skirt_faces :: proc(index: Field_Selection_Index, node: Field_Node) -> Field_Seam_Faces`: flaps where the neighbour of the same level is neither in `index.selected` nor in `index.holds_finer` (main's test), curtains where it is in `holds_finer`. `Field_Selection_Index.holds_finer`, the parent walk of `make_field_selection_index` and `field_node_parent` come back as on main.
- `FIELD_CURTAIN_DROP :: FIELD_MESH_POSITION_UNITS`, one of the node's cells.
- `FIELD_MESH_VERTEX_BOUND`: three more per border cell (two for the flap, one for the curtain): 35,937 + 3 times 6,146 = 54,375, under 65,536.
- `cut_field_surface :: proc(surface: ^Field_Surface, faces: Field_Seam_Faces)`: for each axis whose negative face is in `faces.curtains`, each cell at -1 on that axis that no other node meshes and that holds a vertex (`surface.cell_vertices`, `field_vertex_cell_index`): the other two coordinates from 0 to 31, and not 31 on an axis whose positive face borders a node of this level (in neither set), since that neighbour's quads use the cell as its cell -1. When the cell at 0 with the same other two coordinates holds a vertex, the vertex moves along the line to it until its coordinate on the axis is 0 (in i64: `position += (inner - position) * -position[axis] / (inner[axis] - position[axis])`, then `position[axis] = 0`), else its coordinate on the axis becomes 0. Both lie on the surface, so the cut follows it; the gradient stays. Positive faces need no cut: the surface stops in cell 31. Nil `cell_vertices` (a uniform grid) cuts nothing. The cells left out are shared with a node of this level, or a diagonal one that can be; cutting them opened 3 rays at node corners in the views (away 120, spring 40, newspring 40), where the copies of one vertex in two meshes parted.
- `field_curtain_drop :: proc(vertex: Field_Surface_Vertex, faces: Field_Faces) -> [3]i32`: the gradient without its components on the axes where `field_skirt_outward(vertex.position, faces)` is not 0, scaled to `FIELD_CURTAIN_DROP` (`field_scaled_vector`): down the ground within the face's plane, zero when the gradient lies across the face.
- `append_field_skirts :: proc(surface: ^Field_Surface, faces: Field_Seam_Faces)`, in this order: the surface's border edges (`field_border_edges`, before any skirt) sorted into those on `faces.flaps` and those on `faces.curtains` (`field_edge_on_faces`; an edge along a node's edge can be on both); the vertex check with 2 per flap border vertex plus 1 per curtain border vertex (over the limit: the log line, and neither cut nor skirts); each curtain border vertex's drop, before the cut moves it; `cut_field_surface(surface, faces)`; the flaps as now; then per curtain border vertex one lower vertex (a copy of the cut vertex, its position plus the drop) and per curtain edge the band `to, from, from_lower, to, from_lower, to_lower`, which continues the surface's winding so its front faces out of the node. Comment: the strip between levels, the finer flap from above, the curtain against the shallow rays from the finer side, nothing of the coarser node over the finer ground.
- Comments back to main's where the first round changed them (`FIELD_SKIRT_REACH`, `field_skirt_vertices`), the file's header saying both: flaps towards coarser nodes or none, the cut and the curtain towards finer ones.

`src/world_field_mesh.odin`: `Field_Surface` gains `cell_vertices: []i32` (each cell's vertex, -1 for none, `field_vertex_cell_index`), which `mesh_field_surface` allocates with its allocator instead of the temporary one and keeps (nil for a uniform grid). `mesh_field_grid` takes `skirt_faces: Field_Seam_Faces` and calls `append_field_skirts` with it after the look, as now; the cut vertices keep the look of where they were, under a cell away along the same surface.

`src/world_field_streaming.odin`: `Field_Job.skirt_faces`, `Field_Streaming.skirt_faces`, `submit_field_mesh_job`, `field_skirt_faces_changed` (`!=` on the struct) and `schedule_finest_field_mesh` carry `Field_Seam_Faces`; the comments name both sets. A coarser node still meshes again when a neighbour splits or merges, since its curtains change.

Tests (`src/world_field_lod_test.odin` unless named):

- The callers of `append_field_skirts` with one face set (`test_the_skirt_lies_inside_the_surface`, `test_pit_skirt_depth`, `append_strip_triangles`, `append_seam_triangles` and the others) pass `Field_Seam_Faces`; the old ones `{flaps = faces}`.
- `test_the_skirt_faces_follow_the_neighbours_levels`: the fine node `{flaps = {.Negative_X, .Negative_Y, .Positive_Y, .Negative_Z}}`, the coarse node `{flaps = EVERY_FIELD_FACE - {.Positive_X}, curtains = {.Positive_X}}`.
- `test_a_level_seam_on_flat_ground_is_closed_from_above`: the fine node `{flaps = {towards_coarse}}`, the coarse one `{curtains = {towards_fine}}`; the bare check stays.
- `test_a_level_seam_is_closed_at_grazing_views` stays, each node's faces `field_node_skirt_faces` with both sets masked to the x faces; the power check is main's rule (the fine node `{flaps = {.Negative_X}}`, the coarse one `{}`).
- New `test_a_coarser_node_stays_out_of_the_finer_node`, with test densities beside it for the verifier's scenes in samples of the finest level: a pit of radius 2.5 centred at y 19, z 16.3 and 1.5 samples into the finer node, its coarse density `coarse_field_density(fine, generated, 2)` against the flat generation `(41 - 2y) * DENSITY_STEPS_PER_SAMPLE / 2` (divided by 2 for the coarse); a placed wall filling the finer node's first sample column (x 0 to 1 beside a coarse node on the negative side) from y 20 to 26 and z 10 to 22, the same way; a cliff stepping from y 30 on the coarser side to 20.5 with its top edge 1.5 samples into the finer node, densities the depth over the grid's step. For each, the coarse node at {-64, 0, 0} with `{curtains = {.Positive_X}}` and at {0, 0, 0} with `{curtains = {.Negative_X}}` (the scene mirrored in x): every vertex of its mesh after `append_field_skirts` (surface, cut and curtain, `test_grid_vertex_samples`) outside the cells the cut leaves (y and z positions from 0 to under 31 cells; the test's node borders nothing else, so its other faces count as of its level) has x at most 0, or at least 0, within 1e-9, and the mesh holds curtain triangles. On main the lid fails it (the coarse node on +x), on the snapshot the flap (both sides).
- New `test_the_cut_follows_the_coarser_surface`: on the planes of the grazing test (rises 0 and `STEEPEST_SHIPPED_RISE`, the coarse node at {0, 0, 0}, `{curtains = {.Negative_X}}`), the surface vertices at x 0 lie no farther from y = (2600 + rise x) / 128 than the farthest of the others (the clamped densities put the uncut surface 0.10 samples off at the steep rise, the cut vertices 0.055; a cut that only set x would put them over a sample off), and none has x below 0.
- New `test_the_cut_keeps_the_cells_a_neighbour_meshes`: the node {1, {0, 0, 0}} with `{curtains = {.Negative_Z}}` beside {1, {1, 0, 0}} with `{}` (the views' corner: a node of its level on +x), both on `fill_test_plane_grid` with the slope {64, 222}: for every y where the first's cell (31, y, -1) and the second's cell (-1, y, -1) both hold a vertex, they sit at the same place in samples (`test_grid_vertex_samples`), and at least one such y exists. A cut of every cell at -1 fails it (measured: the one shared vertex parts).
- `src/world_field_streaming_test.odin`, `test_a_node_whose_neighbour_splits_meshes_again`: `.Positive_X` not in, then in, `streaming.skirt_faces[node].curtains`.

### Docs (revised)

`doc/presentation.md`, Field meshes, the Seams bullet, in place of the first round's text: main's flap (two cells out along the slope, one below, then two along the gradient) on the faces towards a coarser node or none, never between nodes of one level (0173). Towards finer nodes (0321) the coarser node keeps its mesh in its box: its cells outside a negative face slide along the surface onto the face, and a curtain of one cell hangs from its border into its ground in the face's plane. A ray from the finer side meeting the ground in the strip at a shallow angle passes over the finer flap and under the coarser surface, whose back faces are culled, and showed the sky or the globe; the curtain meets it. A flap there instead stood over the finer ground (a dug pit 3 m, a placed wall 7 m, a cliff top 8.5 samples), and the coarser node's cells beyond a negative face had lain over the finer node as a lid. The coarser surface's edge still steps over a finer pit narrower than its cells. The vertex bound counts three more per border cell. The streaming keeps both face sets with the revision and meshes a node again when either changes.

### Hand-back check (revised)

As the first round: no line applies. The vertex bound rises to 54,375 with its `#assert`.

### The captures afterwards (revised)

As the first round, and along every level seam no flap or shelf standing over the finer side's ground; a step where a dug pit meets a seam is the coarser level's edge, with no sky under it.

### Question for the main agent

The user's decision of 2026-10-02 (`doc/log/2026-10-02.md`) took skirts at the level seams with "transition cells only if seams show". Seams showed, but the cause is the one sided skirt rule of 0173, and skirts on both sides close every probed ray, so this keeps skirts; transition cells would be a rewrite of the mesher's borders. Your call whether the clause asks the user first.

### Decisions (main agent, 2026-11-07)

1. Skirts on both sides of a level seam, as designed. The user's 2026-10-02 clause ("transition cells only if seams show") gates the costlier fix, it does not require it; the seams come from 0173's one sided rule, and skirts close every probed ray. No skirt between nodes of one level, so 0173's pit rim stays fixed.
2. The revision (cut and curtain) is approved as designed. The 4 rays of the views that no mode closes graze the ground within 0.1 m of the relief and stand on main too; no item for them unless the captures after the landing show sky through a crest.
3. The second review found the cut opening rays where the ground meets the cut face at a shallow angle (below about 27 degrees between the ground and the face plane: up to 560 of 48,000 rays at 5 degrees, main none), since the finer flap's first leg then falls short of the plane and the curtain shows its back to the coarser side. The cut applies only where the coarser surface stands steeper than 35.26 degrees to the face plane (the cotangent squared 2, `field_surface_steep_to_face`); shallower cells keep main's lid, as on main. 30 degrees was decided first; the round measured the cut of every cell losing rays up to 31.5 degrees, so the threshold sits above it.
