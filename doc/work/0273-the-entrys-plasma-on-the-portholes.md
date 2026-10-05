# 0273: The entry's plasma on the portholes

Status: designed (2026-10-05)

## Goal

The flames on the portholes during the fall are redone from research (`work/research/flames-2026-10-05.md`, untracked): not triangles growing from the rim with a tint drifting red to white (user, 2026-10-05: "kindergarten tier"), but the plasma sheath an astronaut sees, a pink violet haze that brightens with the heat, streaks and sparks streaming aft across the glass, white only in the brightest cores, the sheath hiding the outside at the peak, soot on the glass after it, and the cabin pulsing in the haze's light. The hue family never drifts; the heat drives brightness, reach, speed and sparks (DESIGN.md, Fire). After 0269 (the heat curve) and 0270 (the travel across the glass).

## Controls

No binding changes.

## Change

- `data/shaders/arrival.fs` rewritten as a flow field on the disc: a haze in a fixed pink violet to orange family whose brightness follows `heat`; value noise fBm stretched along the travel axis and scrolled aft at a speed following the heat, soft edged with a glow, white in the cores near the peak (the look is Techtonica's, soft and realistic leaning, never banded); hashed sparks streaking aft, their rate following the heat; the disc's alpha rising to 1 near the peak; soot from the rim inward after the peak, growing to `soot_percent` by the heat's end and staying on the glass for good (`soot` replaces `cooling` in the view); flicker from noise without period, still under reduced motion. No hue changes with the heat or the cooling.
- Each porthole a point light in the haze's colour, its brightness the heat times the flicker, through the pod's lights as the lamps go (`moved_point_light`), none at heat 0.
- The stages of the descent read as a sequence of structures, not of hues: black, a pink haze, sparks in it, bright streaming at the peak, fading, sooty glass.
- Data: the haze's two colours and the soot's kept share in `game.sjson`, or on the planet's `atmosphere` if the gas should set the hue; the design decides.
- Docs: `doc/presentation.md` (The arrival, The windows), `doc/content.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `shader_source_test.odin` on the new shader (the `u` suffixes).
- Tests: the window light's brightness follows the heat and is 0 at heat 0; the flicker has no period; the presentation leaves the hash alone.
- Screenshots through a porthole at the haze, the sparks, the peak and the soot (the 0269 recipe), sent to the user before the landing.
- The couch: the fall from the chair reads as an entry.

## Specification (design, 2026-10-05)

Designed on `main` at `10b7dd5` (0269 and 0270 landed). No save, record or network layout change. The constants below are first values: the main agent tunes them at the screenshots, the structure stays.

### Data (`data/game.sjson`, `Game_Config` in `data_load.odin`)

`arrival_plasma = { haze_color = [240, 118, 200], ablator_color = [255, 142, 56], soot_percent = 35 }` after `atmosphere`, `Arrival_Plasma_Config :: struct { haze_color, ablator_color: [3]int, soot_percent: int }` beside `Atmosphere_Config`, field `arrival_plasma`. In `arrival_problem`'s table: six rows `{"arrival_plasma.haze_color", config.arrival_plasma.haze_color[i], 0, MAXIMUM_COLOR_COMPONENT}` (and `ablator_color`), one `{"arrival_plasma.soot_percent", ..., 0, MAXIMUM_ARRIVAL_SOOT_PERCENT}` (`:: 60`, so a porthole stays a window), after the table a colour whose channels are all 0 fails, `"arrival_plasma.%s is black"` (a missing key reads as black). Comment lines: "The entry's plasma on the portholes (0273): haze_color is the air's glow (pink violet, nitrogen), ablator_color the heat shield's (orange), 0 to 255 per channel, never black, the heat drives their brightness, never their hue. soot_percent (0 to 60) is the soot's opacity at the glass's rim once the heating is over, kept after the landing."

The colours sit in `game.sjson`, not on the planet. For the planet: the gas sets the hue, a CO2 world would glow otherwise. Against: the gas's density and top are `game.sjson`'s `atmosphere` (0269), one air for every planet, and the ablator is the pod's, so a hue on the planet would split one gas across two files. When `atmosphere` moves to the planet record, `arrival_plasma.haze_color` moves with it. The streaks', sparks' and soot's densities, speeds and thresholds are shader constants: they are the Fire rule's structure, not content, and a key per density invites a tuning that bands or stripes.

### The curve (`data_arrival_curve.odin`)

`Arrival_Curve` gains `heat_out_progress: f32`: `i / ARRIVAL_CURVE_INTERVALS` of the first sample after the peak whose heat is 0, 1 when none, set in `build_arrival_curve`.

### The view and the lights (`render_arrival.odin`)

- `Arrival_View`: `cooling` goes (the shader was its only reader), `soot: f32` comes: the soot's growth, 0 to 1. `arrival_soot :: proc(curve: ^Arrival_Curve, curve_progress: f32) -> f32`: 0 at or before `peak_progress`, `smoothstep(peak_progress, heat_out_progress, p)` after. `arrival_view` returns `{}` only without a fall, it sets `view.soot` for every other case from the curve progress reached: `elapsed`, or for a skip `landed_tick - start_tick`, over the descent clamped to 1, through `arrival_curve_progress`, a skip then returns with phase None and its soot. So soot grows from the peak to the heat's end, holds at 1 through the settle and for ever after, and a skip keeps what its fall had reached.
- `ARRIVAL_FLICKER_MEAN :: 0.85`. `arrival_window_flicker :: proc(seconds: f32, index: int, salt: u64, reduced_motion: bool) -> f32`: the mean under reduced motion (stilled, as the torch flames' `flicker_seconds`), else `0.85 + 0.1 * arrival_noise(seconds, 6.1, salt + 20 + 2 * index) + 0.05 * arrival_noise(seconds, 17.9, salt + 21 + 2 * index)`, 0.7 to 1. `arrival_window_flickers :: proc(seconds: f32, count: int, salt: u64, reduced_motion: bool) -> [MAXIMUM_POD_WINDOWS]f32`. One flicker per window drives both its glass and its light.
- `arrival_plasma_color :: proc(color: [3]int) -> [3]f32` (/255). `ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE :: 0.3`, `ARRIVAL_WINDOW_LIGHT_GAIN :: 0.7`, `ARRIVAL_WINDOW_LIGHT_RADIUS_CELLS :: 5.0`, `ARRIVAL_WINDOW_LIGHT_INSET_CELLS :: 0.35`.
- `arrival_window_lights :: proc(view: Arrival_View, body: matrix[4, 4]f32, pitch_millimetres: int, machine: Machine, clip_box: matrix[4, 4]f32, plasma: Arrival_Plasma_Config, flickers: [MAXIMUM_POD_WINDOWS]f32) -> (lights: [MAXIMUM_POD_WINDOWS]Point_Light, count: int)`: none outside Descent or at heat 0, else per window a light at `transform_point(body, centre + normal * INSET)` (into the cabin), colour `mix(haze, ablator, SHARE) * heat * flicker * GAIN`, radius `RADIUS * pitch`, `clip_box` set (the pod's box: the cabin lit, the hull's outside and the terrain not).
- `arrival_travel_on_glass :: proc(normal, travel, fallback: [3]f32) -> [2]f32`: the travel laid on the glass in the quad's (across, along) basis that `arrival_window_corners` builds from the fallback, unit, `{0, 1}` where the travel runs along the normal.
- `draw_arrival_windows(presentation, view, entities, pod, machine, travel, plasma: Arrival_Plasma_Config, flickers: [MAXIMUM_POD_WINDOWS]f32, salt)`: returns when `view.heat <= 0 && view.soot <= 0` (not on the phase). The quad is laid by `arrival_window_corners(centre, normal, fallback, fallback, radius)`, so it never turns between the fall and the rest and the soot holds still, the flow turns by the uniform `travel_on_glass`. Uniforms per window: `heat`, `soot`, `soot_opacity` (`soot_percent / 100`), `seconds`, `flame_seed` (as today), `flicker`, `travel_on_glass`, `haze_color`, `ablator_color`. `set_shader_vector3` beside `set_shader_vector2` (`render_chunks.odin`).

### The field loop (`loop_field_session.odin`)

`draw_field_viewport_world`: `flickers := arrival_window_flickers(view.seconds, machine.window_count, seed, state.settings.reduced_motion)`, with the pod found, `window_lights, window_light_count := arrival_window_lights(view, entity_body_matrix(...), entity_frame_pitch_millimetres(...), machine, machine_light_clip_box(body, machine.footprint, machine_model_top(models, pod_common)), state.config.arrival_plasma, flickers)`. `Field_Scene.window_lights: []Point_Light`, appended in `set_field_scene_point_lights` after `gather_machine_lights` and before the move, so `moved_point_light` takes them with the lamps (2 lamps and 5 windows fit `MAXIMUM_POINT_LIGHTS`). The windows draw whenever the pod is found (not only in Descent), under `push_pod_transform`, which is nil outside the descent.

### The shader (`data/shaders/arrival.fs`, rewritten, `arrival.vs` unchanged)

Every integer literal keeps its `u` (0105, `test_shipped_shaders_have_no_bare_integer_literals` scans every shipped shader, so it covers the new one). `cell_hash` and `value_noise` stay. An fBm helper with the octave count as a `uint` argument. Constants `WHITE_CORE (1.0, 0.97, 0.92)`, `SOOT_COLOR (0.045, 0.038, 0.034)`. The fragment, in order:

1. Mask: `q = (uv - 0.5) * 2.0`, `r = length(q)`, discard above 1.
2. Soot, no time in it: `n_s` = 3 octave fBm of `q * 2.7` plus the seed, `reach = mix(0.12, 0.55, soot)`, `a_s = soot_opacity * soot * smoothstep(1.0 - reach - 0.15, 1.0, r + 0.3 * (n_s - 0.5))`, darkest at the rim, ragged inward, isotropic.
3. `heat <= 0.0`: output `SOOT_COLOR` at `a_s`, discard below 0.002. The branch is on a uniform, so a landed pod's glass costs a few octaves.
4. Flow coordinates: `d = travel_on_glass`, `along = dot(q, d)` (+1 the leading edge), `across = q.x * d.y - q.y * d.x`, `lead = 0.5 + 0.5 * along`, a light warp `across += 0.12 * (value_noise(vec2(across * 2.9, along * 1.7 + seconds * 0.37)) - 0.5)`.
5. Streaks: 4 octave fBm of `vec2(across * 6.3, along * 0.9 + seconds * speed * octave_speed) * octave_scale + seed`, scales 1.0, 2.13, 4.37, 8.71, octave speeds 0.43, 0.61, 0.89, 1.27, the across scale seven times the along one, so the noise is stretched along the travel, adding time to `along` moves the pattern aft. The speed follows the heat without a phase jump: two layers at `speed` 0.55 and 2.35 (ratio 4.27), `n = mix(slow, fast, smoothstep(0.2, 0.9, heat))` (a speed times the seconds would run backwards as the heat falls). `threshold = mix(0.66, 0.40, heat) - 0.08 * lead` (the reach grows with the heat, longest from the leading edge), `streak = smoothstep(threshold, threshold + 0.22, n) * smoothstep(0.1, 0.55, heat)` (soft edged), `glow = 0.5 * smoothstep(threshold - 0.18, threshold + 0.3, n)`, `core = smoothstep(0.78, 0.95, n) * smoothstep(0.65, 1.0, heat)` (white only near the peak).
6. Sparks: two hashed grids in flow space, `vec2(across * 11.0, along * 3.1 + seconds * 2.9)` and `vec2(across * 17.0, along * 4.7 + seconds * 4.3)`, each with its own seed offset, a cell lights when its hash is below `rate * smoothstep(0.22, 0.85, heat)` (rates 0.22 and 0.14), its centre hashed in 0.25 to 0.75 of the cell, the spark `exp(-(dx * dx * 90.0 + dy * dy * 14.0))` in cell units (long along the travel), its colour `mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * hash)`. `spark` is the brighter layer's value.
7. Haze: `n_h` = 2 octave fBm of `vec2(across * 1.9, along * 0.7 + seconds * 0.31)`, `veil = 1.0 - pow(1.0 - heat, 3.0)` (faint at the onset, 0.99 at heat 0.8).
8. Colour: `c = haze_color * mix(0.55, 1.0, n_h)`, `c = mix(c, mix(haze_color, ablator_color, 0.7), streak)`, `c += ablator_color * glow * 0.35 * heat`, `c = mix(c, WHITE_CORE, core)`, `c = mix(c, spark_color, spark)`, `c = min(c * flicker * (0.5 + 0.5 * heat), vec3(1.0))`. The hue comes from the two data colours and the structure alone, never from the heat.
9. Alpha: `a_p = clamp(veil + (1.0 - veil) * (0.6 * streak + spark), 0.0, 1.0)`: 1 near the peak, falling back after it.
10. The soot on the glass is in front of the plasma: `alpha = a_s + a_p * (1.0 - a_s)`, `rgb = (SOOT_COLOR * a_s + c * a_p * (1.0 - a_s)) / max(alpha, 0.0001)`.

The header comment says the stages are structures in one hue family (black, a pink haze, sparks in it, bright streaming at the peak, fading, sooty glass) and names DESIGN.md, Fire.

### Tests

- `render_arrival_test.odin`: `test_the_window_light_follows_the_heat` (a machine with two windows, identity body, flickers 1: heat 0 and Settled give count 0, at heat 0.5 and 1 count 2, each colour `mix(haze, ablator, 0.3) * heat * GAIN` within 1e-5, the heat 1 colour twice the 0.5 one, the position inset along the normal, `clip_box` set), `test_the_window_flicker_has_no_period` (per window 0 to 4, 60 s at 60 Hz: inside 0.7 to 1, a spread above 0.1, for every lag of 1 to 600 samples the largest difference to the shifted series above 0.02, windows 0 and 1 apart, reduced motion gives `ARRIVAL_FLICKER_MEAN` at every sample), `test_the_soot_grows_after_the_peak_and_stays` (shipped config: 0 at every tick to the peak, non-decreasing, 1 from the heat's out and in Settled, at descent + 240 and at tick 100000, a skip at 101 keeps 0, a skip after the heat's out keeps 1, no fall 0), `test_the_travel_lies_on_the_glass` (unit, the fallback's own direction gives `{0, 1}`, a travel along the normal gives `{0, 1}`). `test_the_arrival_view_follows_the_timeline` drops its `cooling` assertions.
- `data_arrival_curve_test.odin`: `test_the_heat_peaks_once_between_the_start_and_the_hit` adds `heat_out_progress > peak_progress`, the heat 0 there and above 0 one interval before.
- `data_load_test.odin`: `test_arrival_values_are_bounded` adds a channel of 256 failing naming "arrival_plasma.haze_color", `{0, 0, 0}` failing naming "is black", `soot_percent` 61 failing and 0 passing.
- `simulation_arrival_test.odin`: `test_the_arrivals_presentation_leaves_the_hash` also calls `arrival_window_flickers`, `arrival_window_lights` and `arrival_travel_on_glass` each tick, reads `view.soot`, and runs to tick 900 (past the test config's landing).

### Docs

- `doc/presentation.md`, The arrival, the windows bullet rewritten: the plasma sheath as a flow on the glass, the haze, streaks, sparks and white cores in the data's hue family, the heat drives brightness, reach, speed, sparks and the alpha (1 near the peak), never the hue, the flow aft along `travel_on_glass` on a quad that never turns, soot from the rim after the peak (`arrival_soot`), kept after the landing, each window a clipped point light in the haze's colour, heat times flicker, moved with the lamps, the flicker stilled under reduced motion, the flow not. Line 51's list of what reduced motion stills gains "the portholes' flicker". `src/settings.odin`'s `reduced_motion` comment the same.
- `doc/content.md`, The arrival: a bullet for `arrival_plasma` with the comment's sentence and the planet argument in one line.
- `doc/code_map.md`: as `tools/code_graph.py --check` asks.
- `doc/log/2026-10-05.md`, at the landing:

  ```
  ## The entry's plasma on the portholes (0273)

  Tags: field, arrival, plasma, fire, shader, light, soot, presentation, 0273, m14

  The first fire under the Fire rule: the hue is two data colours (the air's and the ablator's) and the heat drives only the structure. The flow's speed follows the heat by crossfading a slow and a fast layer, since a speed times the seconds runs the pattern backwards as the heat falls. The quad no longer turns with the travel, the flow turns inside it, so the soot holds still across the hit. The soot grows from the peak to the heat's end and stays for good, worlds landed before 0273 included. The flicker is stilled under reduced motion, the flow is not. The colours live in game.sjson beside the atmosphere and move to the planet with it.
  ```

### Hand-back check lines that apply

- A number parsed from text is range checked: the six channels, the black colour, `soot_percent`.
- A behaviour change old saves meet: a world landed before 0273 shows the soot (no remap), named in the log.
- Tests never touch the state directory: all of the above are pure.

### Screenshots (the main agent)

0270's recipe (isolated XDG directories, Xvfb, `--dev --seed=273 --name=plasma`): `tools/moc pause`, `tick 700`, `query player` (yaw Y), `look Y+32 -2` (the chair's porthole), `screenshot 0273_haze`, `tick 300` (1000), `screenshot 0273_sparks`, `tick 271` (1271), `screenshot 0273_peak`, `tick 4`, `screenshot 0273_peak_flicker`, `look Y -20` (down the cabin), `screenshot 0273_cabin_light`, `look Y+32 -2`, `tick 325` (1600), `screenshot 0273_fade`, `tick 300` (1900, landed), `screenshot 0273_soot`.

### Questions answered

- The colours in `game.sjson`, the densities as shader constants: above.
- Soot grows and stays rather than peaking and thinning to a kept share: soot does not clear off glass, and 0270's horizon shows through the chair's porthole in the descent's last half second, after the heat is out, so the soot is never heavier than what is kept.
- "Still under reduced motion" read as stilled, as the torch flames are: the flicker is a pulsing light. The flow keeps moving, since a frozen sheath reads as a decal, which the Fire rule forbids.
- The light's colour is a fixed mix of the two, not the drawn pixel's: one colour per light, and the haze dominates the glass.

### For the main agent

- Accept soot that stays for good on the five portholes (35 percent at the rim, clear in the middle), worlds landed before 0273 included?
- Accept the flow kept moving under reduced motion while the flicker stills?

### Decisions (main agent, 2026-10-05)

1. Soot that grows from the peak to the heat's end and stays for good, worlds landed before 0273 included: accepted. The Change bullet is corrected above.
2. Under reduced motion the flicker stills and the flow keeps moving: accepted. A frozen sheath is the decal the Fire rule refuses.
3. The colours in `game.sjson` beside the atmosphere, the densities and thresholds as shader constants: accepted. The constants are first values. The main agent judges them at the screenshots against DESIGN.md's Fire and Art direction (soft, Techtonica's manner, no band, no stripe, no repetition) and sends the tuning to the implementer as a fix round.
4. The quad laid from the fallback axis with the flow turned by `travel_on_glass`, and `cooling` removed with `heat_out_progress` added to the curve: accepted.
5. The stream: 0273 touches `render_arrival.odin`, `loop_field_session.odin`, `data_load.odin` and `game.sjson` as 0272 does, so its worktree is made from the 0272 snapshot, after 0271 and 0272 in the arrival stream.
