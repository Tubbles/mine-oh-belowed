# 0287: The porthole's glass seen whole from the chair

Status: cancelled (2026-10-05, folded into 0288)

## Goal

From the chair the plasma of 0273 fills only the upper part of each porthole, with a straight edge across the glass's middle, in every phase of the entry. The main agent's capture with the depth test off (2026-10-05, `tmp/shot0274/state/mine-oh-belowed/screenshots/diag_nodepth_1272.png` beside `clip_00.png`) showed the disc whole, so something of the pod lies in front of the glass; the design's ray casts on `data/models/pod.obj` found it: a mounting plate of the cabin wall runs up through the chair's porthole's bore in front of the glass (and a second one through window 0's), and the sleeve's own rim hides a crescent at the edge from every eye in the cabin. The glass must sit where nothing of the sleeve lies between any eye in the cabin and it, and nothing of the pod may cross a porthole's bore.

## Controls

None.

## Change

- The glass placed at the sleeve's cabin end (the record's window positions or an offset in `draw_arrival_windows`, the design decides), the depth test kept, so the plasma and the soot cover the whole hole from the chair and from the cabin floor and never show through the wall.
- Docs: `doc/presentation.md` (The arrival, the windows bullet), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the glass's centre lies at the sleeve's cabin end for every shipped window.
- Headless screenshots from the chair and from the cabin floor at the peak: the whole disc covered, nothing of the plasma outside the hole.
- The couch.

## Specification (design, 2026-10-05)

### Geometry (measured on `data/models/pod.obj` by ray casts, model frame, cells)

- Each porthole is `wall(theta, z)` of `tools/models/machines/pod.py` (`PORTHOLES`): w is the record's normal, w 0 the lining's facet, where the record's centres sit today (no 0.2 offset exists in the record or the code; the 0223 log moved the glass back to w 0). Along w: the outer skin at -0.346, the black sleeve (`porthole_frames`, radius 0.4, 12 sided, flats at 0.386) from -0.22 to +0.125, the rim's lip at r 0.42 w 0.12 rising to its step at r 0.48 to 0.55 w 0.15, the octagonal backing plate r 0.8 at w -0.06 to 0.03, the hull's hole r 0.42 from w +0.3 to -1.0.
- The straight edge is not the sleeve. On the chair's porthole (window 2, theta 120) it is the black mounting plate of `upper_walls` (`(120, 2.45, 1.3)`), which runs up the facet to v 1.3, its face at w 0.035 to 0.04 and its top edge 0.13 to 0.15 below the glass's centre, through the bore. It covers the hole's lower part in front of the glass (and blocks the view out after the landing). A second plate, `(15, 2.45, 2.2)` with u to 0.85, runs past its facet's edge through the bore of window 0 (theta 30) at w -0.14 to +0.19 (OBJ face line 36271), from 0.156 off the axis.
- The sleeve hides a crescent at the rim: with the glass at w 0, 4 to 13 of 65 disc points (rings to r 0.37) are behind the sleeve's lip or the rim from the seated eye and from standing eyes at the floor cells, for every window. With the glass at w 0.125 none are, from any of those eyes.
- From the seated eye (-2.0, 2.7, 1.0) the chair's porthole lies 33 degrees off its normal, 4.4 cells away. Windows 0 and 4 are wholly behind the airlock housing and the chair, window 1 mostly behind the oxygen generator's pipes: cabin furniture, not this item.
- The glass at w 0.125 sits in front of both plates' remains, but the plasma's alpha is under 1 below heat 0.8 (`veil` in `arrival.fs`), so a plate behind it still shows its edge through the glass at the onset and the fade. Both plates are shortened in the model.

### Changes

- `data/machines.sjson`, the pod's `windows`: each centre moved 0.125 cells along its normal to the sleeve's cabin end (recomputed from `wall()`, not from the rounded record). Normals and radius 0.41 unchanged (the disc's edge lies between the sleeve, 0.4, and the rim's lip, 0.42).
  - theta 30: [3.322, 3.700, -1.918] to [3.227, 3.639, -1.863]
  - theta 75: [0.986, 3.750, -3.678] to [0.957, 3.689, -3.573]
  - theta 120: [-1.918, 3.700, -3.322] to [-1.863, 3.639, -3.227]
  - theta 195: [-3.705, 3.700, 0.993] to [-3.600, 3.639, 0.965]
  - theta 240: [-1.904, 3.750, 3.298] to [-1.849, 3.689, 3.203]
  - The comment above them: the glass at each sleeve's cabin end, 0.125 cells along the normal from the lining (`porthole_frames`), so nothing of the sleeve lies between the cabin and it; the hole's radius less a hundredth.
- Seam: the record, not a constant in `draw_arrival_windows`. The glass's depth in the sleeve is this model's geometry (another pod has another sleeve), and the record is where the model's points live, as the lamps' "just under their lenses". `draw_arrival_windows` and `arrival_window_corners` are unchanged; the depth test stays.
- `src/render_arrival.odin`: `ARRIVAL_WINDOW_LIGHT_INSET_CELLS` 0.35 to 0.225, so each window's light stays where 0273 put it (0.35 from the lining), inside the cabin and the clip box. The soot draws on the same disc and moves with it; nothing to change.
- `tools/models/machines/pod.py`, `upper_walls`, the mounting plates: `(120, 2.45, 1.3)` to `(120, 2.45, 1.0)` (its top 0.431 from window 2's axis, behind the rim, so the cabin's look is unchanged outside the hole); the `{15: (-0.1, 0.85), ...}` range to `(-0.1, 0.55)` (0.448 from window 0's axis; the part cut lies behind the hull's next facet, unseen). One comment line on the loop: no plate reaches into a porthole's bore (0287). Then `tools/make_models.sh pod`: `git status data/models` shows `pod.obj` alone, the body still 25488 triangles (the slabs keep their triangles; `doc/presentation.md`, Machine models, the pod, names the count), `./build.sh model-check` passes.
- No save change: the windows are content read at load, in no save or record layout. The old save rule does not apply.

### Tests (`src/render_arrival_test.odin`, the shipped pod: `make_test_machines`, `load_machine_model_mesh(test_data_directory(), pod)`, `model_layers_check_triangles(mesh.body, 1)`)

Helpers in the test file: `porthole_axes :: proc(window: Pod_Window) -> (up, across: [3]f32)` (`arrival_glass_axis(window.normal, {0, 1, 0}, {0, 0, 1})` and its cross with the normal); `porthole_frame_triangles :: proc(triangles: []Check_Triangle, window: Pod_Window, allocator := context.temp_allocator) -> [dynamic]Check_Triangle` (every corner less than 0.9 from the axis and from -0.575 to +0.075 along the normal from the centre: the sleeve, the rim, the backing plate, the rivets; it leaves out long runs such as the pipes); `segment_crosses_any_triangle :: proc(start, end: [3]f32, triangles: []Check_Triangle) -> bool` (box rejection, then `segment_crosses_triangle`).

- `test_the_porthole_glass_sits_at_the_sleeves_cabin_end`: for every shipped window, in 12 directions on the glass's plane (angles 0.1 + k·tau/12 from `up`): the segment from centre - normal·0.01 out to 0.45 crosses a frame triangle (the sleeve is behind the glass), and the one from centre + normal·0.01 out to 0.40 crosses none (nothing of the sleeve in front). Measured: 12 and 0 for all five.
- `test_the_porthole_glass_is_seen_whole_from_the_cabin`: eyes are the seat's (`pod.seat.eye` over `COLLISION_UNITS_PER_CELL`) and a standing eye over the centre of each floor cell of `open_cells` boxes 0 and 1 (12 cells, `footprint_point_to_model`, y the box's floor plus `PLAYER_EYE_HEIGHT` / 0.5 cells, so 3.2). For every window and eye, the segment from the eye to the centre and to the points at r 0.1, 0.2, 0.3 and 0.37 in 16 directions, each lifted 0.003 along the normal, crosses no frame triangle. Measured: 0 hidden at the new centres; at the old ones 4 to 13 of 65 per eye and window, so it fails before the change. It leaves out r 0.40: pipe 68's clamp reaches into window 1's bore there (below).
- `test_nothing_of_the_pod_crosses_a_porthole`: for every window, the segments along the normal from centre - normal·0.425 (inside the outer skin, short of the outer rim's washer at -0.47) to centre + normal·0.025 (the rim's step), at the centre and at r 0.1, 0.2, 0.3 and 0.35 in 16 directions, cross no triangle of the whole body. Today it fails on windows 0 and 2 (the plates: 14 and 17 of 65 at r up to 0.38); with the plates shortened all pass (the same scan with the plates' triangles removed: 0 for all five).

### Docs

- `doc/presentation.md`, The field session, The arrival, the windows bullet: "on its glass at the sleeve's cabin mouth, its rim the hole's edge seen from the cabin" becomes the glass at the sleeve's cabin end, nothing of the sleeve between the cabin and it; the light "inset into the cabin" stays.
- `doc/content.md`, Models, `windows`: "The shipped five lie at each sleeve's cabin mouth, where the porthole's hole ... meets the lining" becomes: at each sleeve's cabin end, 0.125 cells along the normal from the lining (`porthole_frames` in `tools/models/machines/pod.py`), radius 0.41 between the sleeve's 0.4 and the hole's 0.42.
- `doc/log/2026-10-05.md` (the main agent's): the cut was the mounting plate, not the sleeve; the sleeve's own share was a crescent at the rim.

### Hand-back check

None of the lines apply (no memory freed, no file written, no parse, no save, no budget, no list, no UI). The tests read only `data/`.

### Capture (main agent)

- The chair at the peak: `tmp/shot0286_start.sh 1271` adapted to the 0287 worktree (`checkout`, `base` and the runtime directory renamed), the seated look as it starts (it faces the chair's porthole, as `clip_1271_30.png`), then `MOC=... tools/capture_clip.sh clip_0287_1271 30`. Repeat at 1000 and 1600, where the heat is lower and the alpha under 1: no straight edge and no dark band in the lower part.
- After the landing (`tmp/shot0287_start.sh 1862`): `tools/moc seat stand`, then from the cabin's spawn `tools/moc look` towards the chair's porthole and `screenshot`; then teleport to the far corner of the free floor (the floor cell centre x -2.5, z -1.5 of the model's frame, put in the world with the pod frame's axes from `tools/moc query frames` and its centre from `query world`) and screenshot each visible porthole: the soot covers the whole disc, the view out is open below the centre, nothing draws outside the hole. The players stay strapped through the fall, so a standing eye sees only the soot and the hole.

### For the main agent

- The model change. `CLAUDE.md` routes machine models through the sealed lab; this is two numbers of an accepted model's mounting plates, not a remodel, and nothing of the cabin's look changes outside the holes. I put it in this item's implementer's hands with `tools/make_models.sh pod`. If the lab rule covers this too, the item lands the record, the constant and the first two tests, and the plates become an item of their own with `test_nothing_of_the_pod_crosses_a_porthole`.
- Plate 15's bolt row moves with its range (the last bolt from u 0.77 to 0.47, near the facet's edge at the top). That is a look change of a few centimetres on the airlock side. The alternative is shortening the plate's height, which takes it from behind the keypad at `lean(15, 3.6)`.
- Pipe 68's saddle clamp (orange run, `PIPE_RUNS`, `pipe_clamps`) reaches into window 1's bore at r 0.36 to 0.39, up to 0.075 in front of the new glass, and the pipe's side grazes the glass's edge. It shows as a clamp over the edge of the glass, behind the oxygen generator from the chair. Not fixed here.
- The item's goal names the cause as the sleeve and the 0.2 cell offset as 0273's; the record never had the offset (0223's log). The log section should name the plate.
- The booklet's pod renders (a reference model, 0275) may show the plate in the hole of the chair's porthole; re-rendering them is yours.

### Decisions (main agent, 2026-10-05)

1. Approved as designed: the record's centres at the sleeve's cabin end, the light's inset shortened, the two plates shortened in `pod.py` by this item's implementer. Two numbers of an accepted model's plates are engineering, not a remodel, and `test_nothing_of_the_pod_crosses_a_porthole` guards the shipped OBJ from here on, so 0264's integration of the lab's pod script must carry both numbers or fail that test.
2. Plate 15 shortened along its facet as designed, the bolt row moving with it. The booklet's pod renders are re-rendered when 0264 lands, which changes the hatch anyway.
3. The clamp of pipe 68 over window 1's edge stays, named in the log; the visibility test samples short of it.
