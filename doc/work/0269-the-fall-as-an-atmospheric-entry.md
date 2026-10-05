# 0269: The fall as an atmospheric entry

Status: implementing (2026-10-05)

## Goal

The fall reads as an entry seen from the chair: black space with stars, the sky brightening as the atmosphere thickens, the portholes glowing pink, then red, then white hot as the drag peaks, the flames dying as the speed drops, the ground rushing up at terminal speed, the bang. The stages follow the path, not timers: the heat is the air's density times the speed cubed, so the flames rise as the pod sinks into the air and die when the drag has taken its speed. The research is in `work/research/arrival-entry-2026-10-05.md` (untracked, 2026-10-05).

## Controls

No binding changes.

## Change

- The arrival's data (`game.sjson`): the start above the atmosphere's top, the entry angle, the speed curve or the drag that makes it, the atmosphere's scale height and the fall's seconds (about 30 by the note, the user tunes them), replacing `arrival_flame_ticks`; the landing tick stays the simulation's.
- The sky's colour by the camera's altitude: black with stars above the atmosphere's top, the day's sky below (`render_sky.odin`, presentation only).
- The window shader's colour and strength from the heat (pink, orange, white hot, dull red, out); the roar from the heat; a buffeting shake at the peak.
- Docs: `doc/content.md` (The arrival), `doc/presentation.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the curve ends at the floor on the landing tick and never runs backwards; the heat is zero at the start and at the hit and peaks once between; the sky is black at the start altitude; the presentation leaves the hash alone.
- The couch and the phone: a new world from black space to the bang, screenshots at the start, the peak and the fade.

## Specification (design, 2026-10-05)

The fall follows a drag curve integrated once at session start in its own seconds and stretched over the descent: the landing tick stays `arrival_ticks` (integer data, the simulation's), floats stay in the presentation and in the load check. No save, record or network layout changes; `Field_Arrival` is untouched, and a save made mid-fall keeps its saved `fall_ticks` (the curve stretches over it).

### Data (`data/game.sjson`, `Game_Config` in `data_load.odin`)

| Key | Shipped | Bound |
|---|---|---|
| `arrival_ticks` | 1860 (30 s of descent and the settle) | 0, or `arrival_settle_ticks + 1` to `MAXIMUM_ARRIVAL_TICKS` (3600) |
| `arrival_settle_ticks` | 60 | 0 to 300, unchanged |
| `arrival_start_metres` | 810 | 20 to 4096, and at least `atmosphere.top_metres + MAXIMUM_RELIEF_METRES` (34), so the start is in black sky wherever the crater lies |
| `arrival_entry_angle_degrees` | 45 | 5 to 85: the start velocity's angle below the horizontal, towards the door (replaces `arrival_angle_degrees`, whose meaning was the straight path's tilt from the up) |
| `arrival_entry_speed_metres_per_second` | 60 | 1 to 1000 |
| `arrival_terminal_speed_metres_per_second` | 20 | 1 to 1000: the terminal speed at density 1 (the planet's radius); the drag per metre is `g / terminal²` |
| `arrival_heat_threshold_percent` | 20 | 0 to 90: the share of the peak heating below which nothing glows |
| `atmosphere = {top_metres, scale_height_metres}` | 650, 145 | top 64 to 4096, scale height 1 to 4096, and `top_metres - 2 * scale_height_metres >= ATMOSPHERE_CLEAR_GROUND_METRES` (64), so the day's sky is untouched on the ground |

`arrival_flame_ticks` and `arrival_angle_degrees` go, with `MAXIMUM_ARRIVAL_FLAME_TICKS` and `MAXIMUM_ARRIVAL_ANGLE_DEGREES`. `Atmosphere_Config :: struct { top_metres, scale_height_metres: int }` beside `Pod_Airlock_Config`, field `atmosphere` on `Game_Config`. Altitudes of the atmosphere are above the planet's `radius_metres`; the curve's altitude is above the resting place (a few metres apart, immaterial). The game.sjson comment block is rewritten to name every key, its bound and that the curve stretches over the descent.

`arrival_problem` (`data_load.odin`), in this order, each a `fmt.tprintf` naming the key: the ticks; the `Config_Bound` table; the clear ground (`"atmosphere.top_metres %d less two scale heights of %d m leaves %d m, below %d"`); the start over the top (`"arrival_start_metres %d is not %d m above atmosphere.top_metres %d"`); then `curve := build_arrival_curve(config)`: `!curve.reached_floor` (`"the arrival's curve does not reach the floor within %d s"`); the start distance `sqrt(range² + start²)` above `ARRIVAL_START_DISTANCE_SHARE * level_distances_metres[FIELD_COARSEST_LEVEL]` (`"arrival_start_metres %d with a range of %d m starts %d m from the crater, beyond %d m"`); `curve.hit_heat_share * 100 >= arrival_heat_threshold_percent` (`"the heat at the hit is %d percent of the peak, not below arrival_heat_threshold_percent %d"`). `FOG_START_SHARE` is no longer read (lower the content cluster's presentation record in `doc/code_map.md` by 1).

### The curve (new `src/data_arrival_curve.odin`, content cluster)

Constants: `ARRIVAL_CURVE_INTERVALS :: 256`, `ARRIVAL_CURVE_STEP_SECONDS :: 1.0 / 240`, `ARRIVAL_CURVE_MAXIMUM_SECONDS :: 600`, `ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED :: 9.81` (Earth's; the stretch absorbs the planet's, which config load does not know), `ARRIVAL_START_DISTANCE_SHARE :: 0.9`, `ATMOSPHERE_CLEAR_GROUND_METRES :: 64`.

- `Arrival_Curve_State :: struct { seconds: f64, position, velocity: [2]f64 }`: x along the pod's forward from the start, y the altitude above the resting place; velocity y negative falling.
- `Arrival_Curve_Sample :: struct { along_metres, altitude_metres: f32, velocity: [2]f32, heat: f32 }`.
- `Arrival_Curve :: struct { samples: [ARRIVAL_CURVE_INTERVALS + 1]Arrival_Curve_Sample, range_metres, natural_seconds, peak_progress, hit_heat_share: f32, reached_floor: bool }`: sample i at progress `i / ARRIVAL_CURVE_INTERVALS` of the natural time. Fixed array, no allocation.
- `arrival_atmosphere_density :: proc(altitude_metres: f64, atmosphere: Atmosphere_Config) -> f64`: 0 at or above `top_metres`, else `exp(-max(altitude, 0) / scale_height_metres)`.
- `arrival_curve_start :: proc(config: Game_Config) -> Arrival_Curve_State`: position `{0, start}`, velocity `speed * {cos(angle), -sin(angle)}`.
- `arrival_curve_step :: proc(state: Arrival_Curve_State, drag_per_metre: f64, atmosphere: Atmosphere_Config) -> Arrival_Curve_State`: semi-implicit Euler over `ARRIVAL_CURVE_STEP_SECONDS`: `acceleration = {0, -g} - drag_per_metre * density(altitude) * |v| * v`; velocity first, then position.
- `arrival_curve_lerp :: proc(before, after: Arrival_Curve_State, share: f64) -> Arrival_Curve_State`.
- `build_arrival_curve :: proc(config: Game_Config) -> Arrival_Curve`: pass 1 steps until the altitude is at or below 0 (or past `ARRIVAL_CURVE_MAXIMUM_SECONDS`: `reached_floor` false, return); the end is the lerp at `before.altitude / (before.altitude - after.altitude)`, exactly altitude 0; `natural_seconds` and `range_metres` from it. Pass 2 repeats the same steps from the start and fills sample i by the lerp of the two states bracketing `i * natural_seconds / ARRIVAL_CURVE_INTERVALS`; the last sample is the end, its `along_metres` the same f32 as `range_metres`. Then `raw_i = density(altitude_i) * |velocity_i|³`, `peak = max raw_i` at index p, `peak_progress = p / ARRIVAL_CURVE_INTERVALS`, `hit_heat_share = raw_last / peak`, and

  `heat_i = clamp((raw_i / peak - threshold) / (1 - threshold), 0, 1)`, threshold `arrival_heat_threshold_percent / 100`.

  The sampled peak is exactly 1; above the top the density is 0, so the space phase has no heat; the threshold makes the heat 0 at the hit (the load check guarantees it).
- `arrival_curve_at :: proc(curve: ^Arrival_Curve, progress: f32) -> Arrival_Curve_Sample`: progress clamped to 0 to 1, every field lerped between the two neighbouring samples.

The shipped values, integrated (Python model of the above, 30 s descent): natural 14.3 s stretched to 30 s; range 350 m, start 882 m from the crater (bound 921 m); the top crossed at 6 s; heat on at 8.3 s (pink), peak at 0.527 (15.8 s), out at 27.1 s; the path from 45 degrees below the horizon to 87 at the hit (the gravity turn); speed as seen 29, 44 (12 s), 24 (20 s), 10.6 m/s at the hit; `hit_heat_share` 0.156.

### The presentation (`render_arrival.odin`)

- `Arrival_Presentation` gains `curve: Arrival_Curve`; `init_arrival_presentation :: proc(data_directory: string, config: Game_Config)` builds it before loading the shader, so it exists without the shader; `start_field_presentation` passes `state.config`.
- `Arrival_View`: `flame_strength` becomes `heat`; add `cooling: f32` (0 up to the peak, 1 after). `arrival_view :: proc(arrival: Field_Arrival, tick: u64, alpha: f32, config: Game_Config, curve: ^Arrival_Curve) -> Arrival_View`: the phases as today; in Descent `progress = elapsed / descent` (linear, the curve carries the shape), `heat = arrival_curve_at(curve, progress).heat`, `cooling = progress > curve.peak_progress ? 1 : 0`. Callers: `draw_field_viewport_world`, `play_field_session_sounds` (`&state.presentation.arrival.curve`), the tests.
- `arrival_eased_share`, `arrival_path_direction`, `arrival_start_offset` go.
- `arrival_descent_offset :: proc(view: Arrival_View, up, forward: [3]f32, curve: ^Arrival_Curve) -> [3]f32`: zero outside Descent; else with `sample := arrival_curve_at(curve, view.progress)`: `up * sample.altitude_metres - forward * (curve.range_metres - sample.along_metres)`, exactly zero at progress 1.
- `arrival_travel_direction :: proc(sample: Arrival_Curve_Sample, up, forward: [3]f32) -> [3]f32`: `normalize(forward * velocity.x + up * velocity.y)`, the curve's tangent. `draw_field_viewport_world` passes it as `draw_arrival_windows`' travel. This is 0270's hook: the pod's attitude turns its base into this direction.
- `arrival_noise` takes `hertz: f64` before the salt (the shake passes `ARRIVAL_SHAKE_HERTZ`). `arrival_buffet_offset :: proc(seconds, heat: f32, salt: u64) -> (position, look: [3]f32)`: amplitude `ARRIVAL_BUFFET_METRES * heat³` (0.05), noise at `ARRIVAL_BUFFET_HERTZ` (7.3) on salts `salt + 8` to `salt + 13`, look half the amplitude, as the shake. `arrival_viewport_camera`'s Descent adds it to the moved camera (position by the first, target by both) unless `reduced_motion`; the stored camera stays the resting one; the cabin is not moved by it.
- `draw_arrival_windows`: returns when `view.heat <= 0`; uniforms `heat`, `cooling`, `seconds`, `flame_seed`.
- `play_arrival_sounds`: the roar's target is `view.heat`.

### The window shader (`data/shaders/arrival.fs`)

Uniforms `heat`, `cooling`, `seconds`, `flame_seed` (`flame_strength` goes). The flames' height and the glow (`0.35 * heat`) follow `heat` as they followed the strength. The tint: `rising = mix(mix(PINK, ORANGE, smoothstep(0.0, 0.45, heat)), WHITE_HOT, smoothstep(0.45, 1.0, heat))`, `falling = mix(mix(DULL_RED, ORANGE, smoothstep(0.0, 0.6, heat)), WHITE_HOT, smoothstep(0.6, 1.0, heat))`, `tint = mix(rising, falling, cooling)` with PINK (1.0, 0.42, 0.62), ORANGE (1.0, 0.5, 0.12), WHITE_HOT (1.0, 0.96, 0.88), DULL_RED (0.5, 0.07, 0.03); both meet at WHITE_HOT at heat 1, so the step of `cooling` at the peak shows nothing. Flame colour `mix(tint * 0.8, mix(tint, vec3(1.0, 0.97, 0.9), 0.5), flame * flame)`, glow colour `tint`. The header comment says so. Every integer literal keeps its `u`.

### The sky (`render_sky.odin`, `loop_field_session.odin`)

- `SPACE_SKY_COLOR :: rl.Color{2, 3, 8, 255}`, `ATMOSPHERE_FULL_SKY_SCALE_HEIGHTS :: 2.0`.
- `atmosphere_sky_share :: proc(altitude_metres: f32, atmosphere: Atmosphere_Config) -> f32`: `depth := (top - altitude) / scale_height`; 0 for `depth <= 0`, else `min((1 - exp(-depth)) / (1 - exp(-ATMOSPHERE_FULL_SKY_SCALE_HEIGHTS)), 1)`: 1 from two scale heights under the top down (360 m shipped).
- `altitude_day_sky :: proc(sky: Day_Sky, share: f32) -> Day_Sky`: zenith and horizon mixed from `SPACE_SKY_COLOR` by the share, `blend` times the share (the stars' `1 - blend` shows them in space by day), `fog` and `sun_tint` kept; the sky unchanged at share 1.
- `draw_field_viewport_world`, after the camera is moved: `altitude := linalg.length(camera.position) - f32(session.planet.radius_metres)`, `field_sky := altitude_day_sky(sky, atmosphere_sky_share(altitude, state.config.atmosphere))`; when the share is below 1, `rl.ClearBackground(field_sky.colors.horizon)` first (the frame cleared to the day's horizon, which shows between the dome's horizontal and the globe), then `draw_field_sky` with `field_sky`. The scene's `day_factor` and `sky_tint` keep `sky`: the sun lights the pod in space. Not special cased for the arrival: any field camera above 360 m (the developer's fly camera) sees it; the block world never calls it. The terrain's fog stays `FIELD_FOG_COLOR`: from the start the crater lies 65 percent into the fog, the ground hazed under the atmosphere and clearing as the pod sinks.

### Tests

- `data_arrival_curve_test.odin`: `test_the_arrival_curve_reaches_the_floor` (shipped config: `reached_floor`; the last sample's altitude 0 and `along_metres == range_metres`; along non-decreasing and altitude non-increasing over every sample; the tangent at the end steeper than at the start, `velocity.y / |velocity|` lower); `test_the_heat_peaks_once_between_the_start_and_the_hit` (first and last sample heat 0, max exactly 1 at `peak_progress`, non-decreasing to it and non-increasing after, 0 at every sample at or above the top).
- `render_arrival_test.odin`: `test_the_arrival_view_follows_the_timeline` rewritten on the shipped ticks by `descent := arrival_ticks - settle` (Descent with heat 0 at tick 0; heat above 0.95 at the tick of the peak and `cooling` 0 one tick before it and 1 one after; heat 0 at `descent - 1`; Settled at `descent`; the landed, skipped and no fall cases as today); `test_the_fall_ends_at_the_floor_and_never_runs_backwards` (replaces `test_the_fall_ends_at_the_eye_and_its_last_second_is_fastest`: for every tick of the descent the offset's height along the up never rises and its part along the forward never falls back; the start's height `arrival_start_metres` within 0.01; at progress 1 the offset `[3]f32{}` exactly; zero outside Descent); `test_the_buffet_follows_the_heat` (zero at heat 0, moving at heat 1 over 120 samples, never above `ARRIVAL_BUFFET_METRES * sqrt(3)`); `test_the_sky_is_black_above_the_atmosphere` (share 0 at `arrival_start_metres` and at the top, 1 at 0 and at `top - 2 * scale_height`, non-increasing with altitude; `altitude_day_sky(sky, 0)` has `SPACE_SKY_COLOR` zenith and horizon and blend 0; `altitude_day_sky(sky, 1) == sky`). `test_the_shake_fades_and_never_repeats` stays.
- `data_load_test.odin`: `test_arrival_values_are_bounded` rewritten: shipped passes; start 2000 fails naming "starts"; start equal to the top fails naming "atmosphere.top_metres"; threshold 0 fails naming "heat at the hit"; scale height 400 fails naming "two scale heights"; `arrival_ticks` 60 fails; no fall passes.
- `simulation_arrival_test.odin`: `arrival_test_config` copies the new keys and `atmosphere` (600 ticks stay: the curve stretches); `test_the_arrivals_presentation_leaves_the_hash` builds the curve once and calls `arrival_view` with it, `arrival_descent_offset`, `arrival_travel_direction` for the windows' corners, `arrival_buffet_offset` and `atmosphere_sky_share` each tick.

### Docs

- `doc/content.md`, The arrival: the bullets rewritten to the table above. New sentences: "`arrival_entry_angle_degrees` (45, 5 to 85), `arrival_entry_speed_metres_per_second` (60) and `arrival_terminal_speed_metres_per_second` (20, at the planet's radius): the pod leaves the start at that speed and angle below the horizontal towards its door; gravity and a drag of the air's density times the speed squared bend the path towards vertical (`build_arrival_curve`), integrated once in its own seconds and stretched over the descent, so the seconds tune the tempo and the keys the shape." "`atmosphere` (`top_metres` 650, `scale_height_metres` 145): the air's density falls as exp(-altitude / scale height) and is 0 above the top; the sky is black above it, the day's from two scale heights under it." "`arrival_heat_threshold_percent` (20): the heating is the density times the speed cubed, normalised to its peak; below this share nothing glows, and the load fails when the hit is not below it." The start distance sentence: "`arrival_start_metres` (810) stays at least the relief bound above the top, and the start lies inside 0.9 of the coarsest level's distance (921 m shipped) from the crater, so the crater shows hazed through the fog at the start."
- `doc/presentation.md`, The arrival: Descent bullet: the path is the curve's (`arrival_descent_offset` from `arrival_curve_at`), the cabin's offset the altitude along the up and the range left along the back; the travel its tangent (`arrival_travel_direction`). Windows bullet: the flames follow the heat (`heat`), pink, then orange, white hot at the peak, after it orange to a dull red (`cooling`), out; gone from the windows at heat 0. New bullet: the buffeting (`arrival_buffet_offset`, heat cubed, off under reduced motion). Sounds bullet: the roar at the heat. Sky and day: "A field camera's sky follows its altitude above the planet's radius (`atmosphere_sky_share`, `altitude_day_sky`): black with the stars above `atmosphere.top_metres`, the day's from two scale heights under it; the frame is cleared to that horizon; the scene stays lit by the day."
- `doc/code_map.md`: content's file list gains `data_arrival_curve.odin` (`Arrival_Curve`, `build_arrival_curve`, `arrival_curve_at`), the cluster table's counts, the content record's presentation count lowered by one (the `FOG_START_SHARE` read goes); the `render_arrival.odin` line names the buffet and the heat.
- `doc/log/2026-10-05.md`, at the landing:

  ```
  ## The fall as an atmospheric entry (0269)

  Tags: field, arrival, entry, sky, atmosphere, heat, shader, presentation, 0269, m14

  The curve is a drag model integrated at load in its own seconds and stretched over the descent, so the landing tick stays integer data and no float reaches the tick; the user tunes the seconds and the keys the shape. At game scale the heating at terminal speed is 16 percent of the peak (a real entry's is near none), so a threshold key models the glow's onset and makes the hit dark. The start bound moved from the fog's start to 0.9 of the coarsest level: within 614 m a 30 s fall hits at 7 m/s; at 882 m the crater starts hazed in the fog, read as the atmosphere seen from above. The sky's altitude rule is general: any field camera above 360 m darkens.
  ```

### Hand-back check lines that apply

- A number parsed from text is range checked: every new key in `arrival_problem`, plus the curve's three checks.
- A start-up load that the game can make fail: none new (shipped data; a bad `game.sjson` fails the load as today).
- A behaviour change that stops old saves: none; a mid-fall save stretches the curve over its saved length.
- Tests use no state directory: the tests above are pure.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `check-android`, `test`; `python3 tools/check_docs.py`; `python3 tools/code_graph.py --check doc/code_map.md`.

Screenshots (the main agent, the 0223 recipe: isolated XDG directories, Xvfb, `--dev --seed=269 --name=entry`): `tools/moc pause`, `tick 120` (2 s, space), `query player` (yaw Y), `look Y 14`, `screenshot 0269_space`, `look Y 60`, `screenshot 0269_stars`, `look Y 14`, `tick 830` (tick 950, the peak), `screenshot 0269_peak`, `tick 370` (tick 1320, the fade, orange to red), `screenshot 0269_fade`, `tick 400` (tick 1720, terminal, the ground near), `screenshot 0269_terminal`, `tick 140` (landed), `screenshot 0269_touchdown`.

### Questions answered

- Drag model over key points: the phases and the gravity turn fall out of one law, and 0270 gets a tangent.
- Stretch over the descent instead of deriving the ticks from the curve: the ticks feed the simulation and must not depend on float integration across machines.
- The roar follows the heat alone, silent in the terminal phase, as the item says; the crash still marks the hit.
- The atmosphere is a `game.sjson` object, not a planet record key: the item says so, and a planet key would go into `world.sjson`.

### For the main agent

- The hit is slow: 10.6 m/s as seen with 30 s (0223 hit at 126 m/s). Shorter seconds raise it in proportion (15 s: 21 m/s); more is only possible with a farther start, which needs the far level of 0200's note. Ship 30 s as asked?
- The start bound moves from 0200's "the crater never starts in fog" to 0.9 of the coarsest level (the crater 65 percent fogged at the start). Accept, or keep 0.6 and a slower hit (about 7 m/s)?

Decided (main agent, 2026-10-05): approved with one change. The stretch is not uniform: a new key `arrival_real_seconds` (shipped 6, bound 1 to 60, checked at load to be below both the natural seconds and the descent's seconds) names the curve's last natural seconds, which play 1:1 at the end of the descent; the natural time before them is stretched over the rest of the descent (the descent's progress maps to natural time piecewise linearly, and `arrival_curve_at` takes the descent's progress through that map), so the hit comes at the natural terminal speed while the space and entry phases, where nothing near the eye moves, carry the stretch. With it `arrival_terminal_speed_metres_per_second` ships at 30 and `arrival_entry_speed_metres_per_second` is raised (about 90) until the hit's heat share sits under the threshold with margin; the implementer re-derives the timeline (the top crossing, the heat on, the peak, the heat out, the hit speed) from the built curve in a test that prints it, and the log takes those numbers in place of the specification's. 30 s stays. The 0.9 start bound is accepted.

Ran: a Python model of the curve, the heat and the sky share (scratchpad, not in the repository) to pick and check the shipped values; read the code and docs named above. No build or test.
