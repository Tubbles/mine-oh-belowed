# 0354: The view's edge fades everything

Status: implementing (2026-11-11)

0343's view distance setting brings the end of the drawn world as near as 256 m, where two things that 1024 m hid show. Its review found by probe that the packed level distances leave selected nodes two levels apart meeting along edges and corners at 256 m and 512 m (130 edge and 49 corner contacts over 48 eyes at 512 m, 230 to 360 m out, against 4 corner contacts at 1024 m): the skirts and curtains cover faces only (`field_node_skirt_faces`), and `field_level_gap_metres` assumes a level's node was chosen for its own distance, where the child of a split node can lie up to its parent's diagonal past it. And `field.fs` scales the haze by the sky's share, so shaded terrain at the view's edge never fades and ends on a hard edge. The landing's capture at 256 m shows a far hilltop standing unfaded in the sky.

## Goal

At every view distance the world ends in haze with no hard edge and no pinhole between levels.

## Controls

None.

## Change

- The haze at the view's end fades shaded ground as it fades lit ground.
- The level distances the setting packs keep nodes two levels apart from meeting at an edge or a corner, or the seam is covered there.
- What the unfaded hilltop of the 256 m capture is (a node past the view, the globe, a tree tile) is found first, since it decides which of the two it belongs to.

## Verify

- The checks and the suite, with a test that no selection at the four view distances holds nodes two levels apart in contact, over many eyes.
- Captures at 256 m and 512 m of the view that showed the hilltop, a grotto mouth at the view's edge, and a ridge 230 to 360 m out, sent to the user.

## Specification (design, 2026-11-11)

Designed against `main` at `b9a6c82`. Presentation only: the haze is shader colour, and the selection only drives meshing and drawing (0343, decision 2), so nothing reaches the tick, the hash or the save. No dither or noise is added; the fade is a colour mix.

### The hilltop (settled from the code and the captures)

What reaches the view's edge today, and what each does there:

- Terrain nodes (`field.fs`, terrain pass): a node is selected when its nearest point lies inside the view, so its far side reaches up to its diagonal past it (a level 2 node 222 m past 256 m, a level 3 node 443 m past 512 m). The end fade is complete at the view, then scaled by the vertex's sky light (`apply_haze`'s `sky_share`), so a vertex with sky light under 1 keeps its own colour at any distance.
- Water (`field.fs`, water pass): the same nodes, the terrain's light, the same scaling.
- Ground cover (`cover.fs`): ends 8 m inside level 0, never at the edge.
- Trees (`tree.fs`, `sky_share` 1.0): cards hidden past `min(far_metres, view)` and dithered out over its last quarter; near models within 96 m.
- Globe and machines (`model.fs`, `sky_share` 1.0): fully the end colour past the view. The globe is a smooth sphere 8 m under the lowest relief and cannot stand above the drawn ground.
- Unhazed at every distance: foundation slabs (`draw_frames`), belt runs and poles, torch boxes (question 1); the flames end at 64 m, the debris lies at the crater.

The 256 m capture (`tmp/shot_terrain_0343/state/mine-oh-belowed/screenshots/view_256.png`, about pixel 557, 410) shows a dark outline with sky inside it. At the same pixel the 512 m capture shows a grey rock fin standing out of the forest. The trees round it are gone at 256 m (cards end at 256) and opaque at 512 m (they fade from 384 m), so it lies about 250 to 384 m out, past the view, in a level 2 node whose nearest point is inside it. A sky lit surface there is exactly the end colour. The loaded chunks end about 100 m from the eye (`chunk_radius` 2 and `chunk_margin` 1), and a coarse node's generated samples lack sky light only in carved air under a roof (`generate_field_grid`, `column_shades`: arch, grotto, mushroom, 0324). So it is the unlit underside of a carved landmark, a terrain node: the haze defect, not the seam defect, not the globe and not a tree tile. No capture is needed to tell them apart; capture A below must show it gone.

### Decisions

1. **The end fade is full on every surface.** `apply_haze` scales only the aerial haze by `sky_share`; the end fade then takes the result to the end colour whatever the sky share. Past the view lies only the end colour (the globe and the dome's horizon), so fading a shaded face to anything else leaves an edge. Inside `FOG_START_SHARE` of the view nothing changes: the new result differs from the old by `(1 - sky_share) * fade * (end_color - color)`. A cave's far walls past 0.6 of the view now go to the end colour; that is the goal ("fades everything").
2. **The selection is balanced 2:1 at faces, edges and corners**, by a pass after the walk that splits any selected node touching one two or more levels finer. The proof of the defect: a level L node's parent was split because its nearest point lay within `D[L]`, so the node reaches up to `D[L]` plus the parent's diagonal, while a node two levels coarser needs only `D[L+1]`; the gap rule asks `D[L+1] - D[L]` for the node's own diagonal, half of that. The walk alone meets two levels apart at 256 m (levels 0 and 2), 512 m (1 and 3, and 0 and 2) and at 768 m and 1024 m (0 and 2, corners only), so the shipped data needs the pass too, not only the packing.
   - Rejected: the parent's diagonal as the gap (111, 222, 444 m). The shipped 64 and 160 fail it, and the packing loses a level at every short view: rough flat ground node counts 60 against 34 at 256 m, 77 against 49 at 512 m, 140 against 74 at 768 m.
   - Rejected: flaps on edges and corners. The Verify asks for no contact, and a flap reaches one coarser cell, where two levels need two.
   - Rejected: merging the finer side. It ripples into new contacts nearer the eye and drops detail inside a level's distance.
   - The pass only splits, so detail only rises, and only where a contact was: a node of level j is checked only when its nearest distance plus its diagonal reaches `D[j+1]`, the least distance of any node two levels coarser (the same bound, so the check is exact). A split child lies past `D[m-1]` like its parent, so `select_field_node` keeps it whole; children outside the shell or wholly past the view are dropped as the walk drops them.
3. **`field_level_gap_metres`, the data check and the packing stay.** No data key changes. The gap now only keeps the contacts, and so the pass's splits, few. Its comment's two claims (no two levels apart, no hole past the last distance) are both wrong for a split node's children and are rewritten. Within the last distance every point of the shell is covered whatever the gaps; past it nothing shows but the end colour.

### Files and procedures

`data/shaders/field.fs`, `model.fs`, `tree.fs`, `cover.fs`: `apply_haze`'s last two lines become (identical text in all four; `test_the_lit_shaders_share_the_open_sky` compares them):

```glsl
    vec3 hazed = mix(color, sky, aerial * sky_share);
    return mix(hazed, end_color, smoothstep(fog_start, max(fog_end, fog_start + 1.0), reach));
```

In each shader's comment above the haze uniforms, the line "sky_share scales it: air the sky does not light (a cave's, by its samples' sky light) scatters no sky colour." becomes "sky_share scales the aerial haze: air the sky does not light (a cave's, by its samples' sky light) scatters no sky colour. The end fade is full whatever the share (0354): past the view lies only the end colour, so a shaded face fades there as a lit one does." No integer literal and no new identifier besides `hazed`.

`src/world_field_lod.odin`:
- `walk_field_nodes :: proc(view: Field_View) -> [dynamic]Field_Node_Distance`: the present body of `select_field_nodes` up to the walk's end (lines 209 to 227), in the temp allocator, unsorted.
- `field_node_diagonal :: proc(level: i32, spacing_millimetres: int) -> i64`: the node's diagonal in position units, rounded up: `(edge * SQUARE_ROOT_OF_THREE_TEN_THOUSANDTHS + 9999) / 10000` with `edge := sample_axis_to_position(field_node_samples(level), spacing_millimetres)`.
- `field_node_may_touch_coarser :: proc(view: Field_View, entry: Field_Node_Distance) -> bool`: `i64(integer_square_root(u64(entry.distance_squared))) + 1 + field_node_diagonal(entry.node.level, view.spacing_millimetres) >= view.level_distances[entry.node.level + 1]` (the `+ 1` covers the square root's floor).
- `field_selected_holder :: proc(held: map[Field_Node]int, region: Field_Node, least_level: i32) -> (holder: Field_Node, found: bool)`: from `region` up through `field_node_parent` to `least_level`, then on up to `FIELD_COARSEST_LEVEL`, the first ancestor in `held`.
- `split_selected_field_node :: proc(view: Field_View, node: Field_Node, selected: ^[dynamic]Field_Node_Distance, held: ^map[Field_Node]int)`: `delete_key(held, node)`; `select_field_node` on each of the 8 children (`node.coordinate * 2 + field_corner_offset(child)`, level `node.level - 1`); every entry appended is put in `held` with its index.
- `balance_field_selection :: proc(view: Field_View, selected: ^[dynamic]Field_Node_Distance)`: `held` maps each node to its index (temp allocator). For `level` from 0 to `FIELD_COARSEST_LEVEL - 2`, over every index of `selected` (its length read each turn, as splits append), an entry of that level still held at that index that `field_node_may_touch_coarser`: for each of the 26 offsets (the 27 of the walk without the centre), `region := Field_Node{level, coordinate + offset}`, and while `field_selected_holder(held, region, level + 2)` finds a holder, `split_selected_field_node` it. Splits append only levels above the one in hand, so one pass from the finest up settles every contact. At the end `selected^` keeps the entries still held at their index, in order.
- `select_field_nodes`: `walk_field_nodes`, `balance_field_selection`, then the sort and the copy as today. Signature unchanged; the field session, the planet preview and the shadow pass get the balance through it.
- Comments: the file header's skirt paragraph adds that the selection is balanced at faces, edges and corners (`balance_field_selection`), so a skirt never meets a node two levels coarser; `balance_field_selection` carries the proof of decision 2 in three lines.

`src/data_load.odin`, `field_level_gap_metres`'s comment: the least gap between the distances of levels L - 1 and L, a level L - 1 node's diagonal at the widest spacing, so few nodes meet one two levels coarser. It does not rule that out: the child of a split node reaches up to its parent's diagonal, twice this, past its level's distance and can meet such a node at an edge or a corner, which the selection's balance splits (`balance_field_selection`, 0354).

`src/data_load_test.odin` line 43: the message becomes `"%v leaves a level less than its gap above the one before"`.

### Tests

`src/world_field_lod_test.odin`:
- Helpers: `contact_test_eyes :: proc(radius_metres: int) -> [48]World_Position`, 48 directions on a golden angle spiral (`z := 1 - 2 * (index + 0.5) / 48`, angle `index * 2.399963`), each at `radius + 2 + (index % 4) * 30` metres; `field_nodes_touch :: proc(first, second: Field_Node, spacing_millimetres: int) -> bool`, the closed boxes (`field_node_box`) meet on every axis; `count_two_level_contacts :: proc(nodes: []Field_Node, spacing_millimetres: int) -> int`, pairs two or more levels apart that touch, by brute force.
- `test_no_selection_holds_nodes_two_levels_apart_in_contact`: `make_test_planet`, `DEFAULT_SAMPLE_SPACING_MILLIMETRES`, the shipped `field_view` (`parse_game_config` of `data/game.sjson`) packed at 256, 512, 768 and 1024 m (`field_view_level_distances`). Per view, the 48 eyes alone, and every fourth eye with `more_cameras` holding the eye moved 150 m along +x:
  - `select_field_nodes` holds no contact two levels apart, no two nodes whose boxes overlap in volume, and no node whose nearest point is at or past the view;
  - every balanced node is a walk node or lies inside one (the pass adds no ground); every child of a walk node missing from the balanced selection that meets the shell (`field_box_in_shell` with the view's shell) and whose nearest point lies inside the view (the nearest eye's) is in it or holds a node of it (the pass drops no ground);
  - teeth: summed over the 48 eyes, `walk_field_nodes` holds at least one contact at 256 m and at 512 m (the review's scan found 22 and 34 of 48 eyes).
  - Mark it `// slow` if `build/test_times.tsv` says so.
- `test_the_selection_refines_towards_the_camera` must still pass unchanged (a split child is visible and no finer than its distance asks).

`src/shader_source_test.odin`: `test_the_end_fade_is_full_on_shaded_ground`: `field.fs`'s `apply_haze` (`shader_function_text`) holds the two lines above and not `mix(color, hazed, sky_share)`; the other three follow from the existing comparison.

Measurement for the report (a throwaway probe, not committed): per view, the mean and largest node count per eye of the walk and of the balanced selection over the 48 eyes, and the mean time of `select_field_nodes` with and without the pass at 512 m and at 1024 m, at 1000 and 333 mm spacing.

### Captures (taken by the main agent)

The implementer's throwaway probe (not committed) builds `make_planet_generation(DEFAULT_WORLD_SEED, default_planet(shipped_test_planets()), DEFAULT_SAMPLE_SPACING_MILLIMETRES)`, the tech demo's world (check against `query world` before trusting the lines), and reports these socket lines with the numbers filled in, in metres:
- Grotto: the nearest `.Grotto` site to the spring start (-1347.1, 7925.5, 746.7 m), found as `test_landmark_sites` finds sites round the home (`landmark_site_candidate`, `place_landmark_site` over the lattice cells within 1500 m of the start). The mouth opens against its axis (`landmark_site_axis(site, generation.radius)`). Eyes 220 m and 300 m from the centre against the axis, each 20 m above `surface_relief` there; the target the centre's direction at the radius plus `surface_relief` at the centre less half `site.height`. Lines: `fly on`, `teleport <eye>`, `look at <target>`.
- Ridge: from the spring start's surface plus 2 m, over 32 directions in the tangent plane, the surface point 230 to 360 m out (sampled every 4 m) that stands highest in elevation angle; lines `fly off`, `teleport 79.0 151.0`, `look at <point>`.

Session: `tmp/shot_terrain_start.sh 0354 <worktree>` (paused, noon). For each of 256 and 512: `view_distance <V>`, the framing lines, 45 times `tick 1` (the frames stream the nodes in), `screenshot <name>_<V>`.
- A, the hilltop: `fly off`, `teleport 79.0 151.0`, `fly on`, `teleport -1357.103 7984.421 752.205`, `look 90 -12`. At 256 m nothing stands in the faded ground near pixel 557, 410; `look 81 -18` puts that place near the crosshair (worked out from the 70 degree field of view).
- B, the grotto mouth from 220 m and from 300 m; C, the ridge.
- The same lines on `main`'s build for the before captures (A's are the 0343 ones).

### Docs

- `doc/presentation.md`, Light on the field, the haze bullet: "The terrain's haze is scaled by its sky light (a cave's air scatters no sky colour), the models' is full." becomes "The terrain's aerial haze is scaled by its sky light (a cave's air scatters no sky colour), the models' is full; the end fade is full on every surface (0354), since past the view lies only the end colour, so a carved landmark's unlit faces fade at the view's end as the lit ground does."
- `doc/presentation.md`, Field meshes, Level of detail, after "nodes outside the shell the relief can reach and beyond the last distance are skipped.": the balance (`balance_field_selection`, 0354): a selected node touching one two or more levels finer at a face, an edge or a corner is split, finest contacts first, until no two nodes in contact are two levels apart; why (a split node's child reaches its parent's diagonal past the level's distance); only nodes whose distance plus diagonal reaches the next level's distance are checked.
- `doc/presentation.md`, Seams: the flaps' reach of one coarser cell holds at edges and corners too, since the selection is balanced there (Level of detail).
- `doc/content.md`, the `field_view.level_distances_metres` line: "The gap keeps a node chosen at one level from bordering one chosen two levels coarser, which the skirts' reach assumes, and keeps the children of a node split at the last but one distance inside the last one, so the far end has no holes." becomes "The child of a split node can still reach its parent's diagonal past a level's distance and meet a node two levels coarser at an edge or a corner; the selection's balance splits that node ([presentation.md](presentation.md), Field meshes, 0354)."
- `doc/code_map.md`, the world entry of `world_field_lod.odin`: `balance_field_selection` after `select_field_nodes`.

### Hand-back check

- Frees between frames: applies unchanged. The selection is still made in `frame_field_selection` and the nodes that leave it unloaded in `prepare_field_frame`; a split node's mesh goes there as any node whose level changes.
- A shared budget: the streaming queue takes the split children as any node of their level, finest first; the pass adds nodes only where a contact was (the measurement above says how many).
- Tests touch no machine state: the tests read shipped data and the test planet only.
- File writes, parsed numbers, start-up loads, save layout, capped lists and audit cases do not apply.

### Questions to the main agent

1. Foundation slabs, belt runs and poles and torch boxes are drawn unhazed at every distance (0313 chose them so). At 256 m a factory 300 m away would show them standing on the faded ground with its machines faded out. Outside this item's change list; I suggest a new item that hazes them (or ends them with the view). Yours to decide.
2. The pass's cost is unmeasured here; the implementer's report gives node counts and times. If they grow more than you accept at 512 m, I know of no cheaper fix that meets the Verify: the parent's diagonal as the gap costs the counts in decision 2 and changes the shipped data.

### Decisions (main agent, 2026-11-11)

1. Question 1: a new item, 0360, hazes the slabs, belts, poles and torch boxes at the view's end. It follows 0347, which rewrites those draws.
2. Question 2: accepted as designed. The report's node counts and times decide nothing here; they go to the log, and 0342's table shows the frame's cost afterwards.
3. Implemented after 0342 has landed, as the other performance items, so its captures and 0342's views run on one tree.
