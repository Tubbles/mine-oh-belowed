# 0290: Burning flakes shed by the heat shield

Status: designed (2026-10-05)

## Goal

The Artemis I window footage of 0288 shows pieces of the ablator breaking off the heat shield and tumbling past like small meteors. The user (2026-10-05): "we can clearly see pieces of burning material breaking off from the ablation shield and looking like miniature asteroids falling through the sky. This is not something we have today but i think could add to the chaotic feel, like some particle effect of particles starting at the pod ablation shield, nudging off to the side and mostly sharing the same velocity but bleeding of the velocity over the span of a second, with a streak of bright plasma straight up in the anti-velocity direction". So: flakes born at the pod's base during the heating, each with the pod's velocity plus a sideways nudge, slowing against the air over about a second so it drifts aft past the portholes, a bright head with a plasma streak trailing against the travel, seen through the portholes among the sheath of 0288.

## Controls

None.

## Change

- Presentation only, in the pod frame under the pod transform like the sheath (0288), outside the hull: a flake is a pure function of its index, the seed and the arrival's seconds (born at a hashed time and a hashed point on the base's rim while the heat is above a threshold, its nudge and its drag hashed), so a joiner or a load inside the descent sees the same flakes, as the debris of 0272 does. The rate follows the heat (more flakes near the peak), never periodic.
- Each flake a bright head (the ablator's colour towards white) with a streak along the anti-velocity direction whose length follows its speed against the air, drawn in one batch, its motion computed on the CPU and its fire flicker of 0286 per quad, depth-tested so the sleeve crops it; in the footage a flake crosses the window in about five frames at 30 fps, slower than the sheath's streaks, which sets the drift.
- Nothing during the fall's black sky before the heating and nothing after the landing; a cap on the live flakes; reduced motion as the sheath.
- Docs: `doc/presentation.md` (The arrival), `doc/content.md` if a data key sets the rate or the cap, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: a flake's path is deterministic in the seed and the seconds, starts at the base's rim with the pod's velocity, slows over about a second, its streak points against its velocity, none before the heating or after the landing, the live count never exceeds the cap.
- Clips at the sparks, the peak and the fade beside the footage's frames, scored with the motion filter of 0289.
- The couch.

## Specification (design, 2026-10-05)

Designed against 0288's specification (on `main`) and its worktree as it stood: the sheath quad outside the hull in `draw_arrival_windows` (two passes, `layer`, `sheath_scale`, `arrival_sheath_centre`), the record keys `sheath_depth` and `sheath_radius`, `FAST_FLOW` 36 glass radii a second (14.4 cells a second on a 0.40 pane), and 0288's decision 4 (the shipped heat is 0 through the last `arrival_real_seconds`). Rebase onto 0288 before the implement stage starts.

### The footage (`work/reference/0288/`, Artemis I, 30 fps, frames 400 px wide)

- Two kinds of debris. The comet shaped glowing particles (white head of 2 to 4 px, under 1 % of the width, an orange pink tail of 5 to 30 % of the width upstream of the head, dozens in view at the pink peak, `a30_285_crop.png`) live one frame each: they are 0288's sparks. The pieces of ablator (`a30_297.png` f_28 to f_30, `a30_297b.png`, `a30_316.png` f_05, the 1 fps sheet s_049 to s_069) are dark tumbling plates with gold lit edges, 5 to 15 % of the frame's width, and show no streak of their own.
- Count: 0 to 2 pieces in view at once, mostly 0, in bursts (2 in the 42 frames of 297 s, several in 315 to 320 s of the 1 fps sheet). One far from the camera (297b f_09 to f_12) drifts out of the source at about 3 % of the width a frame and grows; the near ones cross in 4 frames (297 f_28 to 297b f_04, about 19 % of the width a frame) or 2 (316 f_05 to f_06).
- So a piece crosses the window in 4 to 6 frames (0.13 to 0.2 s, 5 to 7.5 widths a second) where the streaks cross in at most 2 (at least 15 widths a second): a piece moves at a third of the gas's speed or less, as the user's "mostly sharing the same velocity" says.
- The user's flake (bright head, plasma streak straight aft) is neither kind exactly: it is the piece's size and speed with the burning particle's light. The design follows the user's words; the dark plate is a question below.

### The model

A flake leaves the heat shield's rim with the pod's velocity plus a sideways nudge and loses its speed against the air exponentially, so relative to the pod it accelerates aft towards the air's speed. All of it in cells of the pod's model frame (x and z centred on the footprint, y up from the base), where the air streams along +y: the drawn pod's up is turned exactly against the travel while `rest_share` is 0 (0270, `arrival_tangent_rotation`), and every flake is dead before `rest_share` leaves 0 (born only while the heat is above 0, at most 2 s old, and 0288's decision 4 holds the heat at 0 for the last 6 s).

- Air speed past the pod as the flakes feel it, `U` = `ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND` 9.0 (below the sheath's 14.4, so the flakes read slower than its streaks).
- A flake's drag time `tau` (hashed 0.8 to 1.25 s), its nudge `n` (outward `0.4 + 1.2 h` cells a second, sideways `0.8 (2 h - 1)`), its age `a`, `decay = exp(-a / tau)`. Its velocity against the air is `(n - U y) decay`. Relative to the pod:
  - velocity `U y (1 - decay) + n decay`;
  - position `start + U y (a - tau (1 - decay)) + n tau (1 - decay)`.
- Measured against the shipped geometry: the sheath planes sit at y 4.07 to 4.12, about 4.1 cells above the rim. A flake gets there after 1.0 to 1.25 s at 5.6 to 6.5 cells a second, so it crosses the chair's porthole's view (about 1.04 cells at its distance) in about 0.18 s, 5.4 frames at 30 fps. That is the footage's 4 to 6 frames. Its angular speed is about 0.4 of the sheath's at the peak, matching the footage's third or less.
- Births: time slots of `ARRIVAL_FLAKE_SLOT_SECONDS` 0.05 s, each holding `ARRIVAL_FLAKE_CANDIDATES_PER_SLOT` 5 candidates. Index `slot * 5 + j`. A candidate's birth is `(slot + h) * 0.05`. It exists when `h < flakes_per_second * heat(birth)^2 * 0.05 / 5`. That is thinned Bernoulli births at hashed offsets, Poisson-like with no period, the rate following the heat squared, so most come near the peak.
- Life: hashed 1.6 to 2.0 s (`ARRIVAL_FLAKE_SHORTEST_LIFE_SECONDS`, `ARRIVAL_FLAKE_LONGEST_LIFE_SECONDS`). By then the flake is 6 cells or more above the portholes' height, out of every view. No distance rule: the life alone ends it.
- The cap is structural. A frame scans the slots `last - ARRIVAL_FLAKE_SLOTS_BACK ..= last` (`last = floor(seconds / 0.05)`, `ARRIVAL_FLAKE_SLOTS_BACK` 40 = 2.0 / 0.05), so at most `MAXIMUM_ARRIVAL_FLAKES` = 41 x 5 = 205 are alive or drawn. The rate's bound keeps the chance at or under 1: `#assert(MAXIMUM_ARRIVAL_FLAKES_PER_SECOND * ARRIVAL_FLAKE_SLOT_SECONDS <= ARRIVAL_FLAKE_CANDIDATES_PER_SLOT)`.
- Rate: the data key `arrival_flakes_per_second` (0 to 100, shipped 50) is the births a second at heat 1. It is data because it is the effect's density, the tuning the couch will ask for. The other numbers are constants because they are tied to the shader's constants (the speeds) or to the cap (slots, lives). At 50 a second about 90 are alive at the peak and about 2.8 % of them pass the chair's porthole, so about 1.4 a second cross it and 0.25 are in view on average. That is a little busier than the footage, for the user's "chaotic feel".
- Start: azimuth `h * math.TAU`, `outward = {cos, 0, sin}`, `sideways = {-sin, 0, cos}`, `start = outward * radius + {0, rim_height * h, 0}`: on the rim's outer face. The rim's geometry is the model's, so it is a record key like 0288's sheath (below): `heat_shield = {radius = 5.45, rim_height = 0.2}`, from `tools/models/machines/pod.py`'s `rim` (5.45 out, 0 to 0.2 up). The radius only grows (outward is at least 0.4, and sideways adds), so a flake never enters the hull or the door's fairing (at most 5.3 out).
- Look per flake: head half size `0.025 + 0.045 h^2` cells (most are small; the largest spans 13 % of the porthole from the chair, the footage's 5 to 15 %). Streak length `ARRIVAL_FLAKE_STREAK_SECONDS` 0.1 times the speed against the air in cells: 0.9 at birth, about 0.27 at the porthole, a third of the pane's width, the footage's tail lengths. Streak direction: the anti-velocity against the air, `normalize(U y - n)`, aft and leaning off the nudge, the user's "straight up". Brightness `(0.8 + 0.4 h) (0.35 + 0.65 decay) (0.5 + 0.5 heat(birth)) fade`, where `fade = clamp(min(a, life - a) / ARRIVAL_FLAKE_FADE_SECONDS, 0, 1)` with 0.15 s, so nothing pops. Whiteness `0.3 + 0.5 decay` (faster, hotter, whiter). Its own fire flicker, `fire_flicker(seconds, hash, false)` (0286).
- Reduced motion: no flakes. A flake slowed to the sheath's calm 0.56 radii a second would hover at the rim for half a minute and never reach a porthole, and a fast one breaks the calm promise. The sheath's calm layer stays as 0288 left it.

### Code

`src/render_arrival_flakes.odin` (new, presentation cluster; header comment: the item, the model above in two sentences, pure per index, so a joiner or a load sees the same flakes, no simulation state):

- Constants as above, each with one comment line: `ARRIVAL_FLAKE_SALT :: 0x666c616b`, `ARRIVAL_FLAKE_SLOT_SECONDS :: 0.05`, `ARRIVAL_FLAKE_CANDIDATES_PER_SLOT :: 5`, `ARRIVAL_FLAKE_SHORTEST_LIFE_SECONDS :: 1.6`, `ARRIVAL_FLAKE_LONGEST_LIFE_SECONDS :: 2.0`, `ARRIVAL_FLAKE_SLOTS_BACK :: 40`, `MAXIMUM_ARRIVAL_FLAKES :: (ARRIVAL_FLAKE_SLOTS_BACK + 1) * ARRIVAL_FLAKE_CANDIDATES_PER_SLOT`, `ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND :: 9.0`, `ARRIVAL_FLAKE_SHORTEST_DRAG_SECONDS :: 0.8`, `ARRIVAL_FLAKE_LONGEST_DRAG_SECONDS :: 1.25`, `ARRIVAL_FLAKE_SLOWEST_OUTWARD :: 0.4`, `ARRIVAL_FLAKE_FASTEST_OUTWARD :: 1.6`, `ARRIVAL_FLAKE_SIDEWAYS :: 0.8` (cells a second), `ARRIVAL_FLAKE_SMALLEST_CELLS :: 0.025`, `ARRIVAL_FLAKE_LARGEST_CELLS :: 0.07`, `ARRIVAL_FLAKE_STREAK_SECONDS :: 0.1`, `ARRIVAL_FLAKE_FADE_SECONDS :: 0.15`, `ARRIVAL_FLAKE_BRIGHTEST :: 2.0` (the vertex colour's brightness scale, flake.vs's), `ARRIVAL_FLAKE_VERTEX_SHADER_PATH :: "shaders/arrival_flake.vs"`, `ARRIVAL_FLAKE_FRAGMENT_SHADER_PATH :: "shaders/arrival_flake.fs"`, and the `#assert` above.
- `Arrival_Flake_Key :: enum u64 {Birth, Exists, Life, Azimuth, Height, Drag, Outward, Sideways, Size, Brightness}`.
- `Arrival_Flake_Source :: struct {curve: ^Arrival_Curve, descent_seconds, flakes_per_second, shield_radius, rim_height: f32, salt: u64}`.
- `Arrival_Flake :: struct {position, streak: [3]f32, streak_cells, size_cells, brightness, flicker, whiteness: f32, alive: bool}`: the head's centre in model cells, the streak's unit direction, its length, the head's half size, the values above.
- `arrival_flake_hash :: proc(index: int, salt: u64) -> u64`: `hash_combine(hash_combine(salt, ARRIVAL_FLAKE_SALT), u64(index))`, as `arrival_debris_hash`. `arrival_flake_fraction :: proc(hash: u64, key: Arrival_Flake_Key) -> f32` uses `arrival_puff_fraction`.
- `arrival_flake_birth_seconds :: proc(index: int, salt: u64) -> f32`: `(f32(index / ARRIVAL_FLAKE_CANDIDATES_PER_SLOT) + fraction(.Birth)) * ARRIVAL_FLAKE_SLOT_SECONDS`.
- `arrival_flake :: proc(index: int, seconds: f32, source: Arrival_Flake_Source) -> Arrival_Flake`: the model above, in this order: the birth and life (dead outside them), the heat at the birth (`arrival_heat_at_seconds`, dead at 0), the existence draw, then the path and the look. Dead when `shield_radius <= 0`. Velocity against the air `(n - U y) decay`, speed its length (above 0 because `U > 0`), `streak = -velocity / speed`, `streak_cells = ARRIVAL_FLAKE_STREAK_SECONDS * speed`.
- `arrival_flakes :: proc(view: Arrival_View, source: Arrival_Flake_Source, reduced_motion: bool) -> (flakes: [MAXIMUM_ARRIVAL_FLAKES]Arrival_Flake, count: int)`: nothing unless `view.phase == .Descent`, not reduced motion, `source.flakes_per_second > 0` and `source.shield_radius > 0`. Otherwise the alive flakes of the scanned slots (above) at `view.seconds`, packed. No allocation.
- `arrival_flake_source :: proc(curve: ^Arrival_Curve, view: Arrival_View, config: Game_Config, machine: Machine, salt: u64) -> Arrival_Flake_Source`.
- `arrival_flake_corners :: proc(head, axis, eye: [3]f32, size, length: f32) -> [4][3]f32`: front `head - axis * size`, back `head + axis * max(length, size)`, across `normalize(cross(axis, eye - head))` (`flame_perpendicular(axis)` when that cross is under 1e-4 long), corners front minus and plus across times size, then back plus and minus, for the texture coordinates (0, 0), (1, 0), (1, 1), (0, 1): x across, y from the head's front to the streak's end. The quad turns about its streak to face the eye.
- `arrival_flake_vertex_color :: proc(flake: Arrival_Flake) -> [4]u8`: red `brightness * flicker / ARRIVAL_FLAKE_BRIGHTEST`, green the head's share of the quad's length `2 size / (size + max(streak_cells, size))`, blue the whiteness, alpha 255. Each is clamped to 0 to 1 and rounded to a byte.
- `draw_arrival_flakes :: proc(presentation: ^Arrival_Presentation, flakes: []Arrival_Flake, body: matrix[4, 4]f32, pitch_metres: f32, eye: [3]f32, haze, ablator: [3]f32)`: nothing without flakes or the shader. Otherwise one batch: `DrawRenderBatchActive`, `rl.BeginBlendMode(.ADDITIVE)`, `rl.BeginShaderMode(flake_shader)`, the `haze_color` and `ablator_color` uniforms, the default texture, one `rlgl.QUADS` of every flake (head `transform_point(body, position)`, axis `normalize(linear * streak)`, size and length times `pitch_metres`, its vertex colour), `DrawRenderBatchActive`, then end the shader and the blend. It is called inside `draw_arrival_windows`, so the depth mask is off and culling disabled there.

Blending: additive, because the flakes emit light and nothing writes depth here, so additive needs no sort among the flakes or against the sheath. Over the sheath's bright gas the head saturates towards white, as the footage's burning heads do.

Depth order: the flakes lie 1.3 cells or more outside the pane, beyond the sheath's plane (0.37 out). The opaque hull, lining and sleeve (drawn before, depth written) crop them through the bore as they crop the sheath. The sheath writes no depth (0288), so it never hides a flake. They draw after the sheath and before the soot: the soot pass (alpha blended dark, on the pane) then darkens them as it darkens the sheath. Drawing a flake over the sheath although it is farther reads as light through the translucent glowing gas.

`src/render_arrival.odin`:

- `Arrival_View` gains `descent_seconds: f32` (last field; the descent's length in seconds, set in the Descent phase, 0 otherwise), set in `arrival_view`'s Descent case as `descent / tick_rate`.
- `arrival_heat_at_seconds :: proc(curve: ^Arrival_Curve, seconds, descent_seconds: f32) -> f32`: 0 when `descent_seconds <= 0` or `seconds` is outside `[0, descent_seconds)`. Otherwise `arrival_curve_at(curve, arrival_curve_progress(curve, seconds / descent_seconds, descent_seconds)).heat`, the view's heat at those seconds. `arrival_view` stays as it is.
- `Arrival_Presentation` gains `flake_shader: rl.Shader, flake_ready: bool`. `init_arrival_presentation` loads the pair after the window shader, logging `arrival: the flake shader did not load; the fall draws without its flakes` on failure. `destroy_arrival_presentation` unloads it.
- `draw_arrival_windows` gains the parameters `flakes: []Arrival_Flake, eye: [3]f32` (eye in the frame's unmoved space). The early return also requires `len(flakes) == 0`. In the pass loop, at the start of pass 1: `rl.EndShaderMode()`, `draw_arrival_flakes(presentation, flakes, body, pitch_metres, eye, haze, ablator)`, `rl.BeginShaderMode(shader)`. This runs whether or not pass 0 drew, since flakes outlive the heat by up to 2 s. Its comment names the flakes between the passes (0290).

`src/loop_field_session.odin`, `draw_field_viewport_world`, before the window call:

- `flakes, flake_count := arrival_flakes(view, arrival_flake_source(&state.presentation.arrival.curve, view, state.config, machine, seed), state.settings.reduced_motion)`.
- `eye := camera.position`, mapped through `linalg.inverse` of `pod_transform` when present.
- Pass `flakes[:flake_count], eye` to `draw_arrival_windows`.

`src/machine.odin`:

- `Pod_Heat_Shield_Definition :: struct {radius, rim_height: f32}`. `Machine_Definition.heat_shield: Maybe(Pod_Heat_Shield_Definition)`.
- `Machine` gains `heat_shield: Pod_Heat_Shield_Definition` (zero for none), with the comment "the heat shield's rim in cells of the model's frame, where the entry's flakes break off (0290, presentation only)". `resolve_machine` sets it with `or_else {}`.
- `validate_pod_heat_shield :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string`, called after `validate_pod_windows`, in `validate_interior_light_share`'s style:
  - a non-pod gives `machine %q is not a pod and cannot have heat_shield`;
  - `!(radius > 0 && radius <= f32(min(width, depth)) / 2)` gives `pod %q has heat_shield radius %.3f, not above 0 to half its footprint`;
  - `!(rim_height >= 0 && rim_height <= f32(height))` gives `pod %q has heat_shield rim_height %.3f, not 0 to its height`.

`src/data_load.odin`: `Game_Config.arrival_flakes_per_second: int` after `arrival_debris_angle_degrees` (its comment line names 0290). `MAXIMUM_ARRIVAL_FLAKES_PER_SECOND :: 100`. The bounds row `{"arrival_flakes_per_second", config.arrival_flakes_per_second, 0, MAXIMUM_ARRIVAL_FLAKES_PER_SECOND}`.

`data/game.sjson`: `arrival_flakes_per_second = 50` after `arrival_debris_angle_degrees`. The arrival comment gains: "During the heating arrival_flakes_per_second (0 to 100) flakes break off the heat shield's rim at the peak, fewer by the heat's square below it, and drift aft past the portholes (presentation only)."

`data/machines.sjson`: the key comment block gains `heat_shield` (optional, pods only, 0290): `{radius, rim_height}`, the heat shield's rim in cells of the model's frame, its outer face from y 0 to rim_height at radius (above 0 to half the footprint), where the entry's flakes break off; presentation only. The pod gains `heat_shield = {radius = 5.45, rim_height = 0.2}` with a comment: pod.py's `rim`.

`data/shaders/arrival_flake.vs`: flame.vs's form. It decodes `bytes = floor(vertexColor * 255.0 + 0.5)` into `flat out` brightness (`bytes.r / 255.0 * flake_brightest`, `const float flake_brightest = 2.0;`), head share (`bytes.g / 255.0`) and whiteness (`bytes.b / 255.0`), passes the texture coordinate, `gl_Position = mvp * vec4(vertexPosition, 1.0)`. Header comment: 0290, the values, the u suffix rule.

`data/shaders/arrival_flake.fs`: header comment (0290, additive, no clock: the flicker comes per quad). `uniform vec3 haze_color, ablator_color;`, `const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);`. Then:

```glsl
float across = fragment_texture_coordinate.x * 2.0 - 1.0;
float along = fragment_texture_coordinate.y;
float head_centre = 0.5 * fragment_head_share;
float head_along = (along - head_centre) / max(head_centre, 0.001);
float head = exp(-3.0 * (across * across + head_along * head_along));
float trail = clamp((along - head_centre) / max(1.0 - head_centre, 0.001), 0.0, 1.0);
float width = mix(0.45, 0.08, trail);
float streak = along > head_centre ? exp(-across * across / (width * width)) * (1.0 - trail) * (1.0 - trail) : 0.0;
vec3 head_color = mix(ablator_color, WHITE_CORE, fragment_whiteness);
vec3 streak_color = mix(mix(ablator_color, WHITE_CORE, 0.3), haze_color, trail);
vec3 c = (head_color * head * 1.4 + streak_color * streak * 0.7) * fragment_brightness;
if (max(c.r, max(c.g, c.b)) < 0.003) discard;
final_color = vec4(c, 1.0);
```

A round soft head, a streak narrowing and cooling from the ablator's orange to the air's pink, as the footage's tails.

### Tests

`src/render_arrival_flakes_test.odin`. The shipped config and curve (`shipped_arrival_config`, `build_arrival_curve`); a source of the shipped pod (`shipped_pod_body`), `descent_seconds` of the shipped fall (30 s), salt 1234. `peak_seconds` is the view's seconds at the heat's peak tick (as `test_the_arrival_view_follows_the_timeline` finds it).

- `test_a_flake_is_a_pure_function_of_its_index_and_the_seed`: for every index of the 41 slots before `peak_seconds`, two calls are equal. With salt 1235 at least half of the alive ones differ in position or are dead.
- `test_a_flake_leaves_the_rim_with_the_pods_velocity`: for every index of 200 slots round the peak that is alive 0.001 s after its birth (`arrival_flake_birth_seconds`): `length(position.xz)` is within 0.01 of 5.45 and `position.y` is within 0 to 0.2. The finite difference over the next 0.01 s has a y part under 0.1 cells a second and a length under 1.8 (the nudge alone: the pod's velocity).
- `test_a_flake_bleeds_its_speed_over_about_a_second`: for the same flakes alive 1.0 s after birth, the speed against the air (finite difference less `U y`) over its value at birth lies within 0.25 to 0.5. The aft speed relative to the pod lies within 0.5 U to 0.75 U. `position.y` rises at every 1/60 s step of its life.
- `test_the_streak_trails_against_the_air`: for those flakes at 0.1, 0.5 and 1.0 s of age: `dot(streak, velocity against the air) / speed < -0.99`, `streak.y > 0.9`, and `streak_cells` is within 2 % of `ARRIVAL_FLAKE_STREAK_SECONDS * speed`.
- `test_no_flake_outside_the_heating`: `arrival_flakes` gives count 0 at every tick before the first tick with heat above 0. It gives 0 at every tick from 2 s after the last such tick to the end of the descent, for `{phase = .Settled, seconds = peak_seconds}` and `{}`, under reduced motion at the peak, with `flakes_per_second` 0, and with `shield_radius` 0.
- `test_the_live_flakes_stay_under_the_cap`: at every tick of the shipped descent, count is at most `MAXIMUM_ARRIVAL_FLAKES` (205), and the largest count lies within 40 to 160. `MAXIMUM_ARRIVAL_FLAKES == 205`. This is also the cost: a frame evaluates exactly 205 candidates and draws at most 205 quads.
- `test_a_flake_never_enters_the_hull`: every alive flake at every tick has `length(position.xz) >= 5.45 - 1e-4`.
- `test_the_flakes_end_before_the_pod_turns_to_rest`: every tick with a count above 0 has `view.rest_share == 0`.
- `test_the_heat_at_seconds_is_the_views`: at every 10th tick of the descent, `arrival_heat_at_seconds(curve, view.seconds, view.descent_seconds)` is within 1e-4 of `view.heat`. It gives 0 at `-1` and at `descent_seconds`.
- `test_the_flake_quad_faces_the_eye`: for head `{0, 0, 0}`, axis `{0, 1, 0}`, eye `{3, 1, 0}`, size 0.1, length 0.5: the corners' midpoints of the front and back edges are `-axis * 0.1` and `axis * 0.5`, and the across edge is perpendicular to the axis and to the eye's offset. Eye on the axis: the corners are finite. Length 0.02: the back is `axis * 0.1`.
- `test_the_flake_vertex_color_carries_its_values`: brightness 1.2 and flicker 1.5 give red 230 (1.8 / 2 x 255, rounded). Size 0.05 and streak 0.15 give green 128. Whiteness 0.8 gives blue 204.
- `test_the_flakes_cross_the_chairs_porthole_as_in_the_footage`: the chair's eye (`cabin_eyes(pod)[0]`) and window 2 (the chair's porthole, 0288). At every tick of the shipped descent, an alive flake is in view when the segment from the eye to its head crosses window 2's pane plane within 0.5 cells of its centre (the cheap filter), the head lies beyond it (`dot(head - centre, normal) < 0`), and `segment_crosses_any_triangle(eye, head, triangles)` is false. Track each index's runs of consecutive ticks in view. There are at least 5 runs over the fall, and the median run length lies within 6 to 14 ticks (the footage's 4 to 6 frames at 30 fps are 8 to 12 ticks; grazing passes are shorter). If the median falls outside, tune `ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND`, not the range, and report it.
- `src/machine_test.odin`, `test_the_heat_shield_is_a_pods_and_bounded`, in the style of the `interior_light_share` test. Refusals are named: a non-pod with one; radius 0; radius 6.5 on the 12 by 12 pod; rim_height -0.1; rim_height 9 on its height 8. The shipped pod's is `{5.45, 0.2}`.
- `test_the_heat_shield_matches_the_model` (`render_arrival_flakes_test.odin`): the largest distance from the y axis of any corner of the shipped body's triangles with y at most `rim_height + 0.01` lies within 0.01 of `heat_shield.radius`.
- `src/data_load_test.odin`: the 0272 refusal table gains `arrival_flakes_per_second = MAXIMUM_ARRIVAL_FLAKES_PER_SECOND + 1`.
- `src/simulation_arrival_test.odin`: the config helper copies `arrival_flakes_per_second`. `test_the_arrivals_presentation_leaves_the_hash` calls `arrival_flakes` at every tick of its fall beside 0288's `arrival_sheath_centre` calls.
- `src/shader_source_test.odin`, `test_the_flake_shaders_share_the_white_core_and_the_brightest`: `arrival_flake.fs` contains arrival.fs's `const vec3 WHITE_CORE = vec3(1.0, 0.97, 0.92);`, and `arrival_flake.vs` contains `const float flake_brightest = 2.0;` matching `ARRIVAL_FLAKE_BRIGHTEST` (`fmt.tprintf("%.1f")`). The u suffix and version line tests cover the new files on their own.

### Docs

- `doc/presentation.md`, The field session, The arrival: a bullet "The flakes (0290, `render_arrival_flakes.odin`)" after the windows bullet. It gives the model in three sentences (rim, nudge, exponential loss against the air at `U` 9 cells a second with `tau` 0.8 to 1.25 s, the closed form's name), the births (slots, heat squared, `arrival_flakes_per_second`), the cap of 205, the look (head, streak of 0.1 s of the speed against the air, additive, between the sheath and the soot), none under reduced motion, and the footage's 4 to 6 frames it matches.
- `doc/content.md`, The arrival: `arrival_flakes_per_second` (50, 0 to 100) as its own bullet after the debris'. The pod's `windows` bullet (line 225): `heat_shield` beside it, `{radius, rim_height}`, the bounds, the shipped `{5.45, 0.2}` from pod.py's rim.
- `doc/code_map.md`: `render_arrival_flakes.odin` after `render_arrival_debris.odin` in the presentation cluster, one line. Run `python3 tools/code_graph.py --check doc/code_map.md`; a new edge or a higher count is recorded as the rules there say, never silenced.
- `doc/log/2026-10-05.md` (the main agent's).

### Hand-back check

- "A list that grows without bound is capped where it draws": the flakes are capped by construction (205 candidates a frame, a fixed array), and `test_the_live_flakes_stay_under_the_cap` asserts it.
- "A number parsed from text is range checked": `arrival_flakes_per_second` and `heat_shield` go through the bounds table and the validator.
- None of the other lines apply: no memory freed between frames (a fixed array on the stack), no file written, no save layout (presentation only; the record key is content read at load), no budget, no UI. The tests read only `data/`.

### Capture (main agent)

- `tmp/shot0288_start.sh` copied to `tmp/shot0290_start.sh` (checkout, base and runtime directory renamed). Clips with `MOC=... tools/capture_clip.sh clip_0290_<tick> 30` and the chair's porthole crop at 1000 (onset: no or rare flakes), 1271 (peak) and 1600 (fade). At the peak also a 120 frame clip, since about 1.4 flakes a second cross the chair's porthole. The strips go beside `work/reference/0288/a30_297.png` and `a30_297b.png`.
- If 0289 has landed: its tool on the peak's 120 frames and on `a30_297/` (crop to the window), the motion energy and the crossing speed side by side.
- Reduced motion on: a peak clip shows no flakes and 0288's calm sheath.

### For the main agent

1. The footage's ablator pieces are dark plates with gold lit edges and no streak. The user asked for a bright head with a plasma streak, which is what the footage's tiny burning particles look like. I followed the user. Should a share of the flakes (the larger ones) draw a dark core inside the glowing rim, as the footage's pieces do? That would be one more vertex byte and a darker centre term in the head.
2. Relative to the pod the flake moves aft, but its streak (against the air) also points aft. So the streak runs ahead of the head across the porthole: the head trails its own tail. This is right physically (the wake is at rest in the air, which passes the pod faster than the flake) and follows the user's words. It is the opposite of 0288's sparks, whose heads lead. If the couch reads it as backwards, flipping the streak to the anti-velocity relative to the pod is one sign.
3. Reduced motion draws no flakes, not slowed ones (reason in The model). The item said "reduced motion as the sheath".
4. `heat_shield` is a record key, following 0288's seam choice (the model's geometry in the record), and `test_the_heat_shield_matches_the_model` ties it to the OBJ. The rim has a gap before the outer door (pod.py's `rim_gap`, about 12 degrees either side of +x). Flakes are born across it too. From the chair (window 2, at 240 degrees) it cannot be seen, and a gap key would be more record for no visible change.
5. The rate (50 a second) puts about 0.25 flakes in the chair's porthole at the peak, a little more than the footage's bursts. It is the data key the couch tunes.
6. The item's line "drawn in one batch with the sheath's clock" does not hold: the flakes need no clock in the shader. Their motion is computed on the CPU from `view.seconds`, and the flicker comes per quad.

### Decisions (main agent, 2026-10-05)

1. Approved as designed against 0288's specification; the worktree is made from 0288's snapshot once its implementer reports, and the rebase follows 0288's landing.
2. The larger flakes get a dark core inside the glowing rim, as the footage's plates show, the smaller ones stay a bright head: the user's burning pieces and the footage's dark plates are the same thing at two sizes. One hashed size threshold decides, the shader draws the core.
3. The streak points aft of the head, the way the flake drifts seen from the pod, as designed; the couch says if it reads backwards, and then one sign flips it.
4. No flakes under reduced motion, since a slowed flake never reaches a porthole. The rate key ships at 50 a second for the couch to tune. The rim's door gap is ignored.
