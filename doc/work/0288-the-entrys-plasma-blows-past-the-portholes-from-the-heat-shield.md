# 0288: The entry's plasma blows past the portholes from the heat shield

Status: implementing (2026-10-05)

## Goal

The plasma of 0286 flickers like fire but sits still on the glass. The user (2026-10-05): "now it starts to look more like fire -- but a "static" fire like when we're sitting next to a fireplace. But we are blasting through the atmosphere in superterminal velocity, the flames need to "blow past" in a very high speed. Again look up some gif online to get a feel for how fast it should go ... Also the fire is physically not situated correctly, its connected to the window instead of connected from under the pod (and just happen to blow past the window so we can see it). Also right now its burning in between the inner glass and the outer glass, it looks like the fire comes from within the walls". So: the sheath is a layer outside the hull that the heat shield under the pod sheds, streaming past the porthole at the entry's speed, seen through the sleeve's tube; nothing of it belongs to the window.

## Controls

None.

## Change

- The speed, from footage: the design downloads clips of a window during an entry (the Soyuz descent module's window footage, Crew Dragon's and the Shuttle's reentry cameras) and of fast flames, with `curl` and `ffmpeg` or `magick` to cut frames, counts in how many frames a streak crosses the window and how the brightness jumps between frames, and states the game's flow in glass radii a tick at each heat. At the peak a feature crosses the glass in a few frames, not a third of a second.
- The place: the plasma's plane moves out of the sleeve to the hull's outer skin or beyond it, so the fire is seen through the sleeve's depth and its rim crops the view at an angle as a real porthole's does. 0287's "seen whole from the chair" goal is dropped with it, its plate fix kept: the two cabin wall plates that run through the bores of windows 0 and 2 (its design, `tools/models/machines/pod.py`, `upper_walls`) are shortened and `test_nothing_of_the_pod_crosses_a_porthole` guards every later pod script.
- The source: the flow enters each window from the side nearest the pod's base (the heat shield meets the air first, the sheath wraps up the hull from there) and leaves at the far side, never born at the rim; the haze reads as a layer streaming past, brightest where it enters, with the streaks' length and the sparks' life set by the speed, under reduced motion as 0286 left it.
- The window light's inset recomputed from the new plane so it stays where 0273 put it. Docs: `doc/presentation.md` (The arrival, the windows bullet), `doc/content.md` (Models, `windows`), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: the plasma's plane lies outside the hull's skin for every shipped window, the flow's entry side is the base's side, a feature's crossing time at the peak lies within the footage's range, nothing of the pod crosses a bore.
- Clips at the sparks, the peak and the fade (`tools/capture_clip.sh`) sent to the user beside the footage's frame strips.
- The couch.

## Specification (design, 2026-10-05)

### The footage (frame strips in `work/reference/0288/`, untracked)

- Artemis I, Orion's cabin camera looking out of a window through the whole entry: `https://images-assets.nasa.gov/video/art001m1203451716/art001m1203451716~medium.mp4` (NASA image library `art001m1203451716`, 1280x720, 30 fps). Strips at 30 fps: `a30_285.png` and `a30_285_crop.png` (285 s, the pink peak), `a30_297.png` and `a30_297b.png` (297 s, a flake), `a30_316.png` (316 s, the orange phase); `a_1fps.png` (250 to 350 s at 1 fps).
  - The glowing streaks (ablator particles, comet shaped, the bright head downstream) never show in two consecutive frames in 90 frames looked at: each is one frame's motion trail, 5 to 30 % of the window's width long. A crossing therefore takes at most about 2 frames (67 ms), so at least 15 window widths (30 glass radii) a second. The fine structure of the glow decorrelates frame to frame as well.
  - The flow runs from the bright source at the window's top edge (the vehicle's hot side) outward and down across the window, radially, and leaves at the far edges. Nothing is born mid-window.
  - The overall brightness is steady: the grey mean moves 1 to 3 % frame to frame (0.619 to 0.661 over 30 frames at 285 s, 0.547 to 0.588 at 316 s, the largest single step 4.5 %), with flares of the whole scene over 0.5 to 1 s (1 fps sheet, 315 to 319 s).
  - The slowest thing in the clip, a large tumbling flake, crosses the frame in 5 to 6 frames (0.2 s).
  - The window's own geometry: a rounded rectangular pane with a thick dark frame cropping the view at the bottom corners; the glow is beyond the pane, never on the frame.
- Orion EFT-1, the top hatch camera looking along the wake: `https://images-assets.nasa.gov/video/JSC-Orion-12-5-2014-GA_EFT-1_reentry/JSC-Orion-12-5-2014-GA_EFT-1_reentry~small.mp4` (480x480, 30 fps). Strips `e30_66.png`, `e30_90.png`, `e_1fps.png` (15 to 115 s). The filaments decorrelate every frame while the glowing envelope holds its place. The grey mean moves under 4 % a frame (0.166 to 0.186 at 66 s).
- Not obtained: no Soyuz, Crew Dragon or Shuttle window clip and no fast flame GIF downloadable as a direct file (Wikimedia Commons' search returned none, the NASA library holds none; giphy and tenor need an API key).
- Physics: a real sheath streams past at hundreds of metres to kilometres a second, so it crosses a 0.4 m pane in under a millisecond. No frame rate resolves it; the footage is limited by the camera. The game can't show that speed without motion blur, so it takes the footage's lower bound and keeps the per tick step short enough for the eye to read the direction (below).

### The place

Measured by ray casts on `data/models/pod.obj` along each porthole's normal, w as 0287's (0 at the lining, + into the cabin): the sleeve from +0.125 to -0.22 (radius 0.4, 12 sides, flats 0.386), the hull's skin at -0.25 (one surface), the outer rim washer of `exterior` from -0.345 to -0.415 with a hexagonal bore (6 sides, flats 0.338, corners 0.39), nothing outside it within 1.0 of the axis out to -1.02 for windows 1 to 4. 0287's "outer skin at -0.346" was the washer's back face.

- The record's `windows` centre becomes the outer pane: 0.38 cells out along the normal from the lining, inside the washer's bore, radius 0.40 (just over the bore's corners, so its disc fills the hexagon and the washer hides the rest). The soot lives there: soot deposits on the outside of the outer pane, and the user reads the plasma at the cabin mouth as fire inside the walls. After the landing it is the dirty pane at the end of the tube, from the cabin and from outside the pod.
- Two new keys per window place the sheath. `sheath_depth` (cells along the outward normal from the centre to the sheath's plane, 0 to 2) is 0.37: the plane lies at w -0.75, half a cell (0.25 m) outside the hull's skin, 0.335 beyond the washer's outer face. `sheath_radius` (the sheath quad's half side in cells, from the window's radius to 4) is 1.2. Ray casts from the 13 cabin eyes (below) to 32 points on the quad's border: none sees the border at 1.1 or 1.2; at 1.0 one does (the floor eye at (-2.5, 3.2, -1.5) on window 2). The steepest view through the sleeve and the washer reaches 0.88 on the plane; the extra comes from the gaps between the sleeve's end, the skin and the washer.
- Seam: the record, not constants. The depth is this model's geometry, and the centre must stay inside the footprint (`validate_pod_windows`), which the pane and the sheath plane both do (at most 4.34 from the axis, footprint ±6).
- The depth test stays and nothing writes depth. The lining, the sleeve (its faces point into the bore), the hull and the washer are drawn first, so the sheath is seen only through the bore and the tube crops it at an angle like a real porthole. The sheath quad is square, has no disc mask, and its border is never seen. On window 0 the sheath plane passes the outer door's fairing (metal on the window's -across side, w -0.43 to -0.96): it shows in front of the flow, and from the chair window 0 is behind the airlock housing anyway (0287).
- Centres, from `wall()` (lining origin minus the into-cabin normal times 0.38, record frame (x, z, -y)); normals unchanged:
  - theta 30: [3.322, 3.700, -1.918] to [3.609, 3.886, -2.083]
  - theta 75: [0.986, 3.750, -3.678] to [1.071, 3.936, -3.998]
  - theta 120: [-1.918, 3.700, -3.322] to [-2.083, 3.886, -3.609]
  - theta 195: [-3.705, 3.700, 0.993] to [-4.025, 3.886, 1.078]
  - theta 240: [-1.904, 3.750, 3.298] to [-2.069, 3.936, 3.584]
  - Each `radius = 0.40, sheath_depth = 0.37, sheath_radius = 1.2`.
- The light: `ARRIVAL_WINDOW_LIGHT_INSET_CELLS` 0.35 to 0.73 (0.35 + 0.38), so each light sits where 0273 put it, 0.35 into the cabin from the lining.
- 0287's plate fix stays: `tools/models/machines/pod.py`, `upper_walls`, `(120, 2.45, 1.3)` to `(120, 2.45, 1.0)` and `{15: (-0.1, 0.85), ...}` to `{15: (-0.1, 0.55), ...}`, one comment line (no plate reaches into a porthole's bore, 0288). Then `tools/make_models.sh pod`: `git status data/models` shows `pod.obj` alone, 25488 triangles, `./build.sh model-check` passes. The rays confirm the blockers: window 0's 14 hits at r 0.2 to 0.35 and window 2's 2 hits at r 0.35 (up share -0.38, w +0.023) are both `pod_black` plates.
- No save change: windows are content read at load.

### The flow

- Direction: `arrival_travel_on_glass` is already right. At rest_share 0 the rotation turns the pod's up against the travel, so `transpose(pod_rotation) * travel` in the unmoved frame is the pod's -up. Laid on the glass (fallback = the pod's up laid on it) it gives d = (0, -1). In `arrival.fs` the leading edge (`along` +1, `lead` 1) is then the base side, and the scroll (`along + seconds * speed`) carries features toward decreasing `along`: from the base side to the nose side, the sheath wrapping up the cone. No change.
- The shader works in glass radii over the larger quad: `vec2 p = q * sheath_scale` with the new uniform `sheath_scale` = `sheath_radius / radius` (3.0 shipped). `p` replaces `q` in the flow, and `lead = clamp(0.5 + 0.5 * along, 0.0, 1.0)`.
- Constants in `arrival.fs` (glass radii a second; at 60 frames a second):
  - `CALM_FLOW = 0.56`: 0286's slow layer at its calm pace (1.4 x 0.4), the speed under reduced motion.
  - `SLOW_FLOW = 12.0` (0.2 radii a tick, a crossing in 10 ticks, 0.17 s): the layer at the onset and the fade.
  - `FAST_FLOW = 36.0` (0.6 radii a tick, a crossing in 3.3 ticks, 0.056 s, 18 window widths a second): the peak. That is just over the footage's lower bound, and the step stays under the long octave's length so the direction reads without motion blur.
  - `STREAK_ALONG_SCALE = 0.45` (was 0.9 inline): the tongues 2.2 radii long per octave 1 cell, so they span the window as streaks.
  - `SPARK_FLOW = 30.0`, `SPARK_FAST_FLOW = 42.0` (crossings in 4 and 2.9 ticks), `SPARK_LIFE = 15.0`, `SPARK_FAST_LIFE = 20.0` (lives of 4 and 3 ticks, about the footage's one frame trails).
  - `SPARK_TAIL = 8.0`: the spark's trail e-folds over an eighth of its cell.
  - `HAZE_LEAD = 0.26` (was 0.18 inline).
- Formulas, in this order in `main()`:
  - `float pace = calm > 0.5 ? 0.4 : 1.0;` and `float slow_speed = calm > 0.5 ? CALM_FLOW : SLOW_FLOW;`.
  - `fast_share` is computed before the warp (unchanged formula).
  - The warp: `across += 0.16 * (1.0 - 0.7 * fast_share) * (value_noise(vec3(across * 2.9, (along + seconds * slow_speed) * 1.7, seconds * 3.1 * pace) + seed3 + vec3(31.7, 3.9, 0.0)) - 0.5);`. The fast sheath streams straighter, as in the footage.
  - The tongues: `streak_noise(across, along, slow_speed, seed3, pace)`, the fast layer `streak_noise(..., FAST_FLOW, ...)`, crossfaded as today. Inside `streak_noise` the along term is `(along + seconds * speed) * STREAK_ALONG_SCALE * scale`. The morphs (2.3, 3.9, 6.7) stay, so a tongue changes shape by a third of a cell or less over its crossing and is born upstream of the visible patch and dies downstream.
  - The haze: `haze_along = along + seconds * slow_speed`, its along scales 0.7 and 1.5 become 0.25 and 0.55 (bands longer than the window, streaming), and `haze_level = mix(0.18, 0.42, haze_noise) * smoothstep(0.0, 0.35, heat) + HAZE_LEAD * heat * lead`: a layer brightest where it enters, no rim term.
  - The chemistry: its scroll `seconds * 3.0 * pace` becomes `seconds * slow_speed`.
  - The sparks: `spark_speed = calm > 0.5 ? 7.5 : SPARK_FLOW`, `spark_fast_speed = calm > 0.5 ? 10.5 : SPARK_FAST_FLOW`, `spark_life = calm > 0.5 ? 4.5 : SPARK_LIFE`, `spark_fast_life = calm > 0.5 ? 6.5 : SPARK_FAST_LIFE`. Then `first = spark_layer(vec2(across * 11.0, (along + seconds * spark_speed * pace) * 1.0), 0.22 * spark_rate, spark_life, ...)` and `second = spark_layer(vec2(across * 17.0, (along + seconds * spark_fast_speed * pace) * 1.25), 0.14 * spark_rate, spark_fast_life, ...)`. Under calm that is 0286's sparks exactly.
  - In `spark_layer` the shape becomes a trail with its head downstream: `centre = vec2(0.25, 0.12) + vec2(0.5, 0.2) * hashes`, `float trail = offset.y < 0.0 ? exp(-offset.y * offset.y * 400.0) : exp(-offset.y * SPARK_TAIL);` and the value `exp(-offset.x * offset.x * 90.0) * trail * edge_fade * envelope`. The tail runs toward the entry (+y in the cell) and ends inside the 0.85 fade.
  - Unchanged: `FLICKER_MEAN`, `plasma_ramp`, `threshold`, `streak`, `core`, `intensity`, the colour, `spark_rate`, the veil.
- Two layers through one shader, the new uniform `layer`: 0 is the soot on the pane (the disc inscribed in the quad, `r > 1.0` discarded, today's soot formula and its `soot_alpha < 0.002` discard, `final_color = vec4(SOOT_COLOR, soot_alpha)`); 1 is the sheath (`heat <= 0.0` discards, no disc and no soot, `final_color = vec4(c, plasma_alpha)`). The header comment says so and names 0288.
- Under reduced motion (`calm` 1) the tongues, the warp, the haze and the chemistry run at `CALM_FLOW` with `fast_share` 0 and the sparks at 0286's calm values. The streaks' shapes are longer, and nothing moves faster than 0286's calm.

### The parallax

The sheath is a world space quad 0.875 cells beyond the sleeve's cabin mouth, drawn under `push_pod_transform` as today, since the pod travels and turns through the descent. The parallax against the sleeve and the washer comes free: from the chair (33 degrees off window 2's normal, 4.4 cells away) the visible patch sits about 0.57 cells off the bore's axis on the plane, and a head turn, the buffet (up to 0.1 cells at heat 1) or a lean slides it against the rim. The soot on the pane is at the washer, so it moves with the rim, and the fire moves behind it.

### Code

- `src/machine.odin`: `Pod_Window_Definition` and `Pod_Window` gain `sheath_depth, sheath_radius: f32` (comment: the sheath's plane that far out along the normal, its quad that half side, 0288). `MAXIMUM_POD_SHEATH_DEPTH_CELLS :: 2` and `MAXIMUM_POD_SHEATH_RADIUS_CELLS :: 4` beside the window constants. `validate_pod_windows` adds `!(window.sheath_depth >= 0 && window.sheath_depth <= MAXIMUM_POD_SHEATH_DEPTH_CELLS)` giving `pod %q window %d has sheath_depth %.3f, not 0 to 2`, and `!(window.sheath_radius >= window.radius && window.sheath_radius <= MAXIMUM_POD_SHEATH_RADIUS_CELLS)` giving `pod %q window %d has sheath_radius %.3f, not its radius to 4`; its comment names both. `resolve_pod_windows` copies both.
- `src/render_arrival.odin`:
  - `arrival_sheath_centre :: proc(window: Pod_Window) -> [3]f32`: `window.centre - window.normal * window.sheath_depth`, the sheath quad's centre in the model's frame. It is called by `draw_arrival_windows` and the tests.
  - `draw_arrival_quad :: proc(corners: [4][3]f32, texture: u32)`: today's `rlgl.SetTexture` to `DrawRenderBatchActive` block, taken out of the loop.
  - `draw_arrival_windows`: set the shared uniforms per window as today, plus `layer`, `sheath_scale`. Pass 1, only while `view.heat > 0`: each window's sheath quad, `arrival_window_corners(transform_point(body, arrival_sheath_centre(window)), normal, fallback, fallback, window.sheath_radius * pitch_metres)`, `layer` 1, `sheath_scale` `window.sheath_radius / window.radius`. Pass 2, only while `view.soot > 0`: each window's pane disc at `transform_point(body, window.centre)` with `window.radius * pitch_metres`, `layer` 0. The sheath first, since the soot lies in front of it and nothing writes depth. Its comment and the file's header say the sheath is outside the hull and the soot on the outer pane.
  - `ARRIVAL_WINDOW_LIGHT_INSET_CELLS :: 0.73`, its comment "how far into the cabin it sits from the outer pane".
- `src/simulation_arrival_test.odin`, `test_the_arrivals_presentation_leaves_the_hash`: the window loop also calls `arrival_sheath_centre(window)`.
- `data/machines.sjson`: the key comment (lines 128 to 133) names `sheath_depth` and `sheath_radius` with their bounds, and the centre is the outer pane where the soot sits. The pod's comment and `windows` follow The place.
- `data/shaders/arrival.fs`: as The flow.

### Tests

In `src/render_arrival_test.odin`, the shipped pod: `make_test_machines`, `load_machine_model_mesh(test_data_directory(), pod)`, `model_layers_check_triangles(mesh.body, 1)`. Helpers: `porthole_axes :: proc(window: Pod_Window) -> (up, across: [3]f32)` (`arrival_glass_axis(window.normal, {0, 1, 0}, {0, 0, 1})` and `linalg.cross(window.normal, up)`); `segment_crosses_any_triangle :: proc(start, end: [3]f32, triangles: []Check_Triangle) -> bool` (box rejection on `minimum`/`maximum`, then `segment_crosses_triangle`); `cabin_eyes :: proc(pod: Machine, allocator := context.temp_allocator) -> [dynamic][3]f32` (the seat's `eye` over `COLLISION_UNITS_PER_CELL`, then the centre of every floor cell of `open_cells` boxes 0 and 1 through `footprint_point_to_model`, y the box's floor plus `PLAYER_EYE_HEIGHT / 0.5`, 13 eyes).

- `test_the_sheath_lies_outside_the_hull`: for every shipped window, `arrival_sheath_centre` lies `sheath_depth` along -normal from the centre, and `sheath_depth > 0`. Every segment from the sheath's plane at r 0.7 (16 directions) along +normal to the lining (`centre + normal * 0.38`) crosses the body (the hull lies between). Every segment at r 0, 0.1, 0.2 and 0.3 (16 directions) from `centre + normal * 0.405` to the sheath's plane plus 0.01 along +normal crosses nothing (the view through the bore is open).
- `test_the_sheaths_edge_is_never_seen_from_the_cabin`: for every shipped window and cabin eye, the segment from the eye to each of 32 points on the sheath quad's border (8 per side, the quad of `arrival_window_corners(arrival_sheath_centre(window), normal, up, up, sheath_radius)`) crosses the body. Measured with 1.2: 0 of 2080 seen. With 1.0: 1 seen.
- `test_the_flow_enters_from_the_heat_shield`: `place_test_pod` and the shipped curve as `test_the_drawn_attitude_follows_the_tangent_then_rests`. At the views of ticks 0 and of the heat's peak tick (`arrival_view(...).heat` largest over the descent), take `arrival_pod_transform`'s rotation and travel and `local := linalg.transpose(rotation) * travel`. Then, as `draw_arrival_windows` does with `body := entity_body_matrix`: for every window, `fallback := arrival_glass_axis(normal_world, up_world, forward_world)`, `d := arrival_travel_on_glass(normal_world, local, fallback)`, entry `centre + (linalg.cross(normal_world, fallback) * d.x + fallback * d.y) * radius`, exit the opposite point. `dot(entry - exit, up_world) < -0.5 * radius` (the entry lies on the base's side).
- `test_the_window_light_stays_where_0273_put_it`: today's centres as literals (the five old ones above) plus 0.35 times the normalised normals lie within 0.003 cells of `window.centre + window.normal * ARRIVAL_WINDOW_LIGHT_INSET_CELLS` of the shipped pod, and of `arrival_window_lights`' positions at heat 1 with an identity body.
- `test_the_soot_lies_on_the_outer_pane`: for every shipped window the segment at r 0, 0.2 and 0.3 (16 directions) from `centre + normal * 0.02` to `centre - normal * 0.02` crosses nothing, and the one at r 0.36 at the bore's flat directions crosses the washer (`porthole_axes`; directions `k * tau / 6` plus the hexagon's phase, which the implementer reads off the OBJ by trying the 24 directions of 15 degrees and keeping those that cross; measured: 18 of 24 cross at r 0.36). So the pane sits inside the washer's bore. Also `radius` 0.40 is at least the bore's corner radius 0.39.
- `test_nothing_of_the_pod_crosses_a_porthole`: for every window, segments along the normal from `centre + normal * 0.405` (the lining plus 0.025) to `centre + normal * 0.05` (the lining minus 0.33, short of the washer at -0.345), at r 0, 0.1, 0.2, 0.3 and 0.35 in 16 directions, cross no triangle of the body. It fails today on window 0 (14 of 65) and window 2 (2 of 65), the two plates, and passes with them shortened.
- `src/machine_test.odin`, the window refusals: `deep` (`sheath_depth = 3`, `"window 0 has sheath_depth 3.000"`) and `narrow` (`sheath_radius = 0.2`, `"window 0 has sheath_radius 0.200"`).
- `src/shader_source_test.odin`: the helper `shader_float_constant :: proc(source, name: string) -> (value: f32, found: bool)` (the text after `const float <name> = ` up to `;`, `strconv.parse_f32`). `test_the_plasma_crosses_the_glass_as_fast_as_the_footage`: for `FAST_FLOW`, `SPARK_FLOW` and `SPARK_FAST_FLOW`, the crossing `2 * 60 / value` lies within 2 to 4 ticks (at least the footage's 15 widths a second, at most one radius a tick); `SLOW_FLOW` lies within 6 and `FAST_FLOW`; `CALM_FLOW` is 0.56; the source declares `uniform float layer;` and `uniform float sheath_scale;`.

### Docs

- `doc/presentation.md`, The field session, The arrival, the windows bullet: each window draws two layers. The sheath is a square quad of the shader outside the hull (`sheath_depth`, `sheath_radius`, `arrival_sheath_centre`), seen only through the porthole's bore, which crops it, and streaming from the base's side at the footage's speed (12 and 36 glass radii a second crossfaded by the heat, the sparks' trails at 30 and 42, the 0.56 of 0286 under reduced motion). The soot is a disc on the outer pane at the record's centre. The light's inset is from the pane. The "1.4 and 5.5 glass radii" sentence and "on its glass at the sleeve's cabin mouth" go.
- `doc/content.md`, Models, `windows`: `{centre, normal, radius, sheath_depth, sheath_radius}` with the bounds. The shipped five: the centre on the outer pane 0.38 along the normal from the lining, inside the outer rim's hexagonal bore, radius 0.40; the sheath 0.37 further out, half a cell outside the skin, half side 1.2 so no cabin eye sees its edge.
- `DESIGN.md`, Fire: one clause after "masked to the fire's extent": a fire sits where it burns, so the entry's sheath streams outside the hull from the heat shield and the porthole only frames it (user, 2026-10-05).
- `doc/log/2026-10-05.md` (the main agent's): the footage and what it measured, the sheath as content keys, 0287's -0.346 being the washer, the plates.

### Hand-back check

None of the lines apply: no memory freed, no file written, no number parsed at run time (the test's `parse_f32` reads a shipped constant), no save layout, no budget, no list, no UI. The tests read only `data/`.

### Capture (main agent)

- `tmp/shot0286_start.sh` copied to `tmp/shot0288_start.sh` with `checkout`, `base` and the runtime directory renamed to 0288, then at 1000 (onset), 1271 (peak) and 1600 (fade): the seated look as it starts faces the chair's porthole; `MOC=... tools/capture_clip.sh clip_0288_<tick> 30` with the default crop (the chair's porthole, as 0286's `clip_1271_30.png`). The strips go to the user beside `work/reference/0288/a30_285.png` and `a30_316.png`.
- After the landing (1862): `tools/moc seat stand`, `tools/moc look` at the chair's porthole and `screenshot`, then from the far floor corner (model (-2.5, 3.2, -1.5), put in the world through `tools/moc query frames` and `query world`) a screenshot of each porthole: the soot on the pane at the tube's end, the view out through it, no quad edge anywhere.

### For the main agent

- Seam choice: two new record keys and the centre moved to the pane, instead of a constant offset in the code. If you prefer the centre at the lining (soot on the inner glass), it takes a third key for the pane and the soot stays at the cabin mouth, which is where the user saw "fire within the walls".
- The flicker against the footage: the whole scene's brightness moves only 1 to 3 % a frame in both clips, with flares over half a second to a second. 0286's `fire_flicker` (0.4 to 1.5 on the glass's brightness and the light) is much stronger than that. The item keeps it, and the user liked it ("starts to look more like fire"). Whether to calm it toward the footage is the couch's call.
- The model: the outer rim washer stands 0.095 cells off the hull's skin (`exterior`, `outer_point` assumes a 0.4 deep wall where the skin is 0.25 out), and its bore is hexagonal (6 sides) inside a 12 sided sleeve. From outside the gap may show; from the cabin a grazing view could see slivers between the sleeve's end (-0.22) and the skin (-0.25), past back faces the ray casts count but the renderer culls. Not fixed here; the edge test is geometric and ignores culling.
- 0287's numbers that did not hold: its outer skin (-0.346) is the washer's back face, and its `test_nothing_of_the_pod_crosses_a_porthole` range to -0.425 at r 0.35 would cross the washer in 18 of 24 directions. The range above stops at -0.33.
- The rest's easing: in the last `arrival_real_seconds` the drawn rotation slerps to the rest pose, so the laid travel turns off the pod's -up. I did not check that the heat is out by then.
- The downloads are 657 MB under `work/reference/0288/` (the two MP4s); the sheets are the small PNGs beside them.

### Decisions (main agent, 2026-10-05)

1. Approved as designed: the two record keys, the centre on the outer pane with the soot there, the sheath quad half a cell outside the skin, the speeds of the footage, the plate fix and the bore test of 0287 with the corrected range.
2. The flicker stays 0286's. The footage's steadier brightness (1 to 3 percent a frame, flares over half a second to a second) goes into the log, and the couch decides whether to calm it once the speed and the place are right.
3. The model's gaps are closed in the same `pod.py` pass where each is one number: the outer washer's standoff (`outer_point` assuming a 0.4 deep wall where the skin is 0.25 out) and the sleeve's outer end short of the skin. A gap that takes more than a number stays and is named in the report.
4. The rest's easing: a test asserts the shipped heat is 0 through the last `arrival_real_seconds`, so the laid travel's turn at the rest never shows with the sheath. If it is not, nothing changes, since a sheath that turns with the pod is right.
