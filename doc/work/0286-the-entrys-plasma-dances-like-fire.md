# 0286: The entry's plasma dances like fire

Status: verified (2026-10-05)

## Goal

The plasma on the portholes during the entry (0273) moves like fire, not like a wave. The user (2026-10-05): "the flames are better, but they've still got far to go ... The flames doesnt flicker at all, they do not behave like flames at all. They have a very weird pinkish color which might be correct, but i think it needs to be mixed up a bit. Its like theyre moving like a wave of 1 Hz, while real flames dance around very skittishly and erratically." The yardstick is footage: a clip of a couple of seconds captured from the headless game, set beside clips of flames in general and of the glow seen through a window during an atmospheric entry, and the shader reworked until the game's clip reads as the footage. The same yardstick applies to the firebox and torch flames of 0274 once the user has seen them.

## Controls

None.

## Change

- The motion of `arrival.fs`: an erratic, fast flicker of the brightness and of the streaks (a flame's dance is a spectrum of fast irregular changes, nothing near a single slow wave), the streaks skittish, the colour a mix the heat and the flicker shift between the haze's pink violet and the ablator's orange and white rather than one hue, all without a period (DESIGN.md, no perceivable repetition), under the reduced motion setting as 0273 left it.
- The capture: a script that takes consecutive frames from a paused headless session and assembles a clip and a frame strip, so the main agent and the user judge the motion, not one still (`tools/` or `tmp/`, the design decides).
- Docs: `doc/presentation.md` (The entry's plasma), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: the flicker has no period over the entry's length, the brightness changes between consecutive ticks by a measured share, the colour spans the mix.
- A one second clip at the sparks, the peak and the fade from the headless game, sent to the user beside the reference clips.
- The couch.

## Specification (design, 2026-10-05)

What was wrong in the 0273 clip (`tmp/shot0274/`, tick 1211), measured on the CPU model: the flicker is 0.85 ± 0.1 at 6.1 Hz plus ± 0.05 at 17.9 Hz, smoothed, so its mean change between ticks is 0.012 and only 0.1 to 0.4 % of ticks change by more than 0.05 (a Python model of `arrival_window_flicker` over the 1860 tick fall); the fast streak layer scrolls 1.1 glass radii a second, so a feature takes 1.8 s to cross the glass, the "1 Hz wave"; the streaks are a 2D texture translated, so no shape changes as it goes; the hue is one mix because every term mixes the same two colours at fixed shares. The black lower part of the glass is not the shader: see For the main agent.

### Sources and the numbers taken from them

- Buoyant diffusion flames flicker at 10 to 20 Hz in the laboratory, scaling with sqrt(g / D) (https://arxiv.org/pdf/1912.03642); a candle in still air at 9.9 Hz (https://cpldcpu.com/2025/08/13/candle-flame-oscillations-as-a-clock/); a pool fire puffs at 1.5 / sqrt(D) Hz (Cetegen and Ahmed 1993, cited in https://www.frontiersin.org/journals/mechanical-engineering/articles/10.3389/fmech.2019.00034/full), 2.4 Hz for a 0.4 m window. In a turbulent luminous flame the radiation fluctuates by up to 100 percent with a broadband spectrum falling as f^-5/3 (https://www.sciencedirect.com/science/article/abs/pii/S0082078406804248). So: four bands at 2.3, 5.9, 11.3 and 23.7 Hz (no small integer ratio), the largest at 11.3 Hz, the fastest linearly interpolated so its corners stay sharp (crackle), plus hashed flares and dips with no period; the depth chosen (deviation about 0.14 on a mean of 0.9) is far below the measured 100 percent because it multiplies the whole glass.
- The entry: Garan's black sky, pink, sparks, bright flames, soot (Forbes, already in `work/research/flames-2026-10-05.md`); the Soyuz plasma "creates the intense color flashes and sparks visible from inside the cabin" (https://www.russianspaceweb.com/soyuz-landing.html, via search summary); flakes of the charring ablator stream past (`work/research/arrival-entry-2026-10-05.md`); the Shuttle's "cherry red to light orange to purple and brilliant white" at once. I could not watch footage frame by frame (Mike Hopkins' 2014 Soyuz window clip is the reference to set beside the game's clip), so the flare rate and lengths are a judgement: about two flares a second, each a jump within 1 to 2 ticks and a decay of 60 to 160 ms.
- Shaders (`work/research/flames-2026-10-05.md`, Febucci, Cyanilux, plus https://blog.fixermark.com/posts/2025/webgl-fire-shader-based-on-fbm/): fBm octaves at rising rates give the crackle; read as fire when brightness and shape change together and colour follows the brightness through a fixed ramp. So the shapes evolve in a third noise axis (time), the flicker also lengthens the tongues and raises the spark rate, and the colour is a fixed ramp of the two data colours indexed by the local intensity, which the heat and the flicker raise: dim violet, pink haze, salmon, the ablator's orange, white.

### The flicker (CPU, shared): `src/render_flames.odin`

Constants, beside the flame constants:

- `FIRE_FLICKER_MEAN :: 0.85` (held under reduced motion), `FIRE_FLICKER_LOWEST :: 0.4`, `FIRE_FLICKER_HIGHEST :: 1.5`.
- `Fire_Flicker_Band :: struct { hertz: f64, amplitude: f32, smooth: bool }` and `FIRE_FLICKER_BANDS :: [4]Fire_Flicker_Band{{2.3, 0.06, true}, {5.9, 0.09, true}, {11.3, 0.13, true}, {23.7, 0.09, false}}`.
- `FIRE_FLARE_SLOT_SECONDS :: 0.2`, `FIRE_FLARE_SLOTS_BACK :: 3`, `FIRE_FLARE_ATTACK_SECONDS :: 0.025`, `FIRE_FLARE_SHARE :: 0.35`, `FIRE_DIP_SHARE :: 0.15`.

Procedures:

- `fire_flicker_band :: proc(seconds: f64, band: Fire_Flicker_Band, salt: u64) -> f32`: `flame_noise(seconds, band.hertz, salt)` when `band.smooth`, else the same steps of `arrival_noise_value` interpolated linearly. -1 to 1.
- `fire_flare :: proc(seconds: f64, salt: u64) -> f32`: the sum over the slots `slot - FIRE_FLARE_SLOTS_BACK ..= slot` (`slot := i64(math.floor(seconds / FIRE_FLARE_SLOT_SECONDS))`) of each slot's event, keyed by `hash := generation_seed.hash_combine(salt, u64(slot_index))` and `key_fraction(k) = f32(generation_seed.hash_to_unit(generation_seed.hash_combine(hash, k)))`: the start `(f64(slot_index) + key_fraction(1)) * FIRE_FLARE_SLOT_SECONDS`; `kind := key_fraction(2)`; below `FIRE_FLARE_SHARE` a flare of amplitude `0.18 + 0.22 * key_fraction(3)` and decay `0.06 + 0.10 * key_fraction(4)` seconds; below `FIRE_FLARE_SHARE + FIRE_DIP_SHARE` a dip of amplitude `-(0.15 + 0.15 * key_fraction(3))` and decay `0.05 + 0.08 * key_fraction(4)`; else nothing. An event at `elapsed := seconds - start >= 0` adds `amplitude * min(elapsed / FIRE_FLARE_ATTACK_SECONDS, 1) * exp(-max(elapsed - FIRE_FLARE_ATTACK_SECONDS, 0) / decay)`; one before its start adds 0. Hashed per slot with a hashed start, so the events form no period.
- `fire_flicker :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32`: `FIRE_FLICKER_MEAN` under reduced motion; else `FIRE_FLICKER_MEAN + Σ band.amplitude * fire_flicker_band(seconds, band, salt + 30 + u64(index)) + fire_flare(seconds, salt + 40)`, clamped to `FIRE_FLICKER_LOWEST ..= FIRE_FLICKER_HIGHEST`. The doc comment names it the shared fire flicker (0286) and says `flame_flicker` keeps 0274's model until its own item.

`flame_flicker`, `flame_noise`, `flame.fs` and every 0274 flame stay unchanged.

The model in Python over 1860 ticks and 8 salts (the design's check of this specification; the test's bounds sit below these): range 0.40 to 1.50, mean 0.89 to 0.91, deviation 0.13 to 0.16, mean change between ticks 0.036 to 0.041 (today 0.012), 22 to 28 % of ticks change by more than 0.05 (today 0.1 to 0.4 %), 5 to 7 % by more than 0.1 (today 0), 1.5 to 2.2 flares a second, the worst lag ratio (below) 0.87 to 0.93 (today 0.84 to 0.90; a 1 Hz sine with noise gives 0.30, a series looped every 3 s gives 0.00), at most 0.3 % of ticks at a bound.

### The portholes: `src/render_arrival.odin`

- Remove `ARRIVAL_FLICKER_MEAN`. `arrival_window_flicker` keeps its signature and returns `fire_flicker(f64(seconds), salt + 20 + 2 * u64(index), reduced_motion)`; its comment: the shared fire flicker per window, 0.4 to 1.5, the mean under reduced motion.
- `draw_arrival_windows` gains a last parameter `reduced_motion: bool` and sets `set_shader_float(shader, "calm", reduced_motion ? 1 : 0)` with the other uniforms. The call in `src/loop_field_session.odin` (`draw_field_viewport_world`) passes `state.settings.reduced_motion`.
- `arrival_window_lights` unchanged: the light is the heat times the same flicker, now 0.4 to 1.5 (gain 0.7, so up to 1.05 at the peak's flares); its hue stays fixed.
- The file's header comment: the plasma flickers through `fire_flicker` (0286).

### The shader: `data/shaders/arrival.fs`

`arrival.vs` unchanged. Rewrite the fragment shader as below (comments to be written in the file's style; the header comment rewritten to say what this section says). Every integer literal with `u`. `seconds` stays the fall's own clock (under 32 s, so float precision holds without the flame's split clock).

Uniforms: the existing nine plus `uniform float calm;` (1 under reduced motion). `const float FLICKER_MEAN = 0.85;` matching `FIRE_FLICKER_MEAN` (a test holds them equal). Constants: `WHITE_CORE = vec3(1.0, 0.97, 0.92)`, `SOOT_COLOR` as today, `VIOLET_SHADE = vec3(0.42, 0.30, 0.66)` (the dim haze: the haze colour times this, darker and bluer, the ionised nitrogen's blue lines), `SLOW_FLOW = 1.4` and `FAST_FLOW = 5.5` (glass radii a second aft; at the peak a feature crosses the glass in 0.36 s, 0.09 radii a tick).

Noise: replace the `sin` hash (its precision falls off with the larger coordinates the faster flow reaches, and on mobile GPUs first) with flame.fs's integer hash in 3D:

```glsl
float cell_hash(uvec3 cell)
{
    uint hash = (cell.x * 73856093u) ^ (cell.y * 19349663u) ^ (cell.z * 83492791u);
    hash ^= hash >> 16u;
    hash *= 0x7feb352du;
    hash ^= hash >> 15u;
    hash *= 0x846ca68bu;
    hash ^= hash >> 16u;
    return float(hash >> 8u) / 16777215.0;
}
```

`value_noise(vec3 point)`: trilinear between the 8 corner hashes of `uvec3(ivec3(floor(point)))` with the smoothstep blend; `value_noise(vec2 point)` overload: the 4 corners at z cell 0u (bilinear). Seeds stay float offsets added to the point: `vec2 seed = vec2(flame_seed * 97.0, flame_seed * 53.0)`, `vec3 seed3 = vec3(seed, flame_seed * 71.0)`.

`float pace = calm > 0.5 ? 0.4 : 1.0;` scales every morph rate and the sparks' speeds and lives under reduced motion.

`float streak_noise(float across, float along, float speed, vec3 seed)`: three octaves, scales 1.0, 2.13, 4.37, weights 0.5, 0.25, 0.125 normalised, morph rates 2.3, 3.9, 6.7 cells a second (a tongue of each octave lives about 0.43, 0.26, 0.15 s); octave `o` samples `value_noise(vec3(across * 6.3 * scale, (along + seconds * speed) * 0.9 * scale, seconds * morph * pace + float(o) * 7.1) + seed + vec3(float(o) * 17.3, float(o) * 29.1, 0.0))`. All octaves scroll at the one speed (the flow carries its eddies), only the morph differs. 0 to 1.

`float spark_layer(vec2 point, float rate, float life_rate, vec2 seed, out float white_share)`: `vec2 shifted = point + seed; uvec2 cell = uvec2(ivec2(floor(shifted))); vec2 inside = fract(shifted);` the spark's life `age = seconds * life_rate * pace + cell_hash(uvec3(cell, 0xffffffffu))`, `uint epoch = uint(int(floor(age)))`, `life = fract(age)`; `lit = cell_hash(uvec3(cell, epoch * 4u))`, `white_share = cell_hash(uvec3(cell, epoch * 4u + 1u))`; 0 when `lit >= rate`; the centre `vec2(0.25, 0.42) + vec2(0.5, 0.16) * vec2(cell_hash(uvec3(cell, epoch * 4u + 2u)), cell_hash(uvec3(cell, epoch * 4u + 3u)))`; returns `exp(-(offset.x * offset.x * 90.0 + offset.y * offset.y * 9.0)) * edge_fade * envelope` with `edge_fade` as today (0.15 at each end along) and `envelope = smoothstep(0.0, 0.2, life) * (1.0 - smoothstep(0.55, 1.0, life))`. A spark appears, streaks about 0.18 radii long (longer than its 0.125 radii a tick travel, so it reads as a streak, not a dotted line) and burns out mid glass.

`vec3 plasma_ramp(float intensity)`: `dim = haze_color * VIOLET_SHADE`, `salmon = mix(haze_color, ablator_color, 0.55)`; `c = mix(dim, haze_color, smoothstep(0.05, 0.4, i))`, `c = mix(c, salmon, smoothstep(0.4, 0.75, i))`, `c = mix(c, ablator_color, smoothstep(0.7, 1.0, i))`, `c = mix(c, WHITE_CORE, smoothstep(1.05, 1.6, i))`.

`main`, in order:

1. The disc, the soot, the `heat <= 0.0` path as today, the soot's noise now `value_noise` fBm of 3 octaves on the integer hash (`q * 2.7 + seed`, no time).
2. `along`, `across`, `lead` as today. The warp: `across += 0.16 * (value_noise(vec3(across * 2.9, (along + seconds * 3.0 * pace) * 1.7, seconds * 3.1 * pace) + seed3 + vec3(31.7, 3.9, 0.0)) - 0.5);` (the tongues lick sideways).
3. The streaks: `fast_share = calm > 0.5 ? 0.0 : smoothstep(0.2, 0.9, heat)`; `slow = streak_noise(across, along, SLOW_FLOW * pace, seed3)`; the fast layer only when `fast_share > 0.0`: `fast = streak_noise(across, along, FAST_FLOW, seed3 + vec3(13.7, 41.9, 5.3))`; `n = mix(slow, fast, fast_share)`, its contrast restored: `n = clamp(0.5 + (n - 0.5) * inversesqrt(fast_share * fast_share + (1.0 - fast_share) * (1.0 - fast_share)), 0.0, 1.0)` (an even mix of two fields would otherwise flatten at the crossfade's middle). Two layers crossfaded, as 0273 decided, so the speed follows the heat without the pattern running backwards.
4. `flare = flicker - FLICKER_MEAN`; `threshold = mix(0.68, 0.38, heat) - 0.14 * lead - 0.22 * flare` (a flare lengthens the tongues, a dip shortens them); `streak = smoothstep(threshold, threshold + 0.18, n) * smoothstep(0.1, 0.55, heat)`; `core = smoothstep(0.62, 0.8, n + 0.1 * lead + 0.15 * flare) * smoothstep(0.55, 1.0, heat)`.
5. The haze over the whole glass, the leading edge brightest: `haze_noise = 0.65 * value_noise(vec3(across * 1.9, (along + seconds * 1.1 * pace) * 0.7, seconds * 0.8 * pace) + seed3) + 0.35 * value_noise(vec3(across * 4.1, (along + seconds * 1.1 * pace) * 1.5, seconds * 1.7 * pace) + seed3 + vec3(17.3, 29.1, 0.0))`; `haze_level = mix(0.18, 0.42, haze_noise) * smoothstep(0.0, 0.35, heat) + 0.18 * heat * lead`.
6. The colour mix: `chemistry = value_noise(vec3(across * 1.7, (along + seconds * 3.0 * pace) * 0.8, seconds * 1.3 * pace) + seed3 + vec3(5.1, 9.7, 0.0))` (patches richer in the ablator's products run up the ramp); `intensity = (haze_level + 0.55 * streak + 0.45 * core) * flicker * (0.55 + 0.6 * heat)`; `c = plasma_ramp(intensity + 0.18 * (chemistry - 0.5)) * clamp(0.35 + 0.75 * intensity, 0.0, 1.15)`.
7. The sparks: `spark_rate = smoothstep(0.22, 0.85, heat) * (0.5 + 0.6 * flicker)` (a flare brings a shower); `first = spark_layer(vec2(across * 11.0, (along + seconds * 7.5 * pace) * 3.1), 0.22 * spark_rate, 4.5, seed + vec2(3.3, 8.9), first_white)`; `second = spark_layer(vec2(across * 17.0, (along + seconds * 10.5 * pace) * 4.7), 0.14 * spark_rate, 6.5, seed + vec2(21.1, 5.7), second_white)`; the brighter kept, its colour `mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * white_share) * (0.8 + 0.3 * flicker)`; `c = min(mix(c, spark_color, spark), vec3(1.0))`.
8. Alpha and the soot over it as today: `veil = 1.0 - pow(1.0 - heat, 3.0)`, `plasma_alpha = clamp(veil + (1.0 - veil) * (0.6 * streak + spark), 0.0, 1.0)`. The 0273 `glow` term is gone (the haze's lead term replaces it).

What this gives, for the capture's judgement: at the onset (heat 0.2) a dim violet veil at alpha 0.49 with slow tongues; at the peak the whole glass opaque, pink violet haze with salmon and orange tongues streaming aft in a third of a second, white where they are thickest and through the flares, sparks streaking and burning out; the glass whitening and darkening several times a second with the flicker.

### Tests

In `src/render_flames_test.odin`, with two pure helpers:

- `Flicker_Statistics :: struct { lowest, highest, mean, deviation, mean_step, step_share_above_5, step_share_above_10, flares_per_second, worst_lag_ratio: f32 }` and `flicker_statistics :: proc(series: []f32) -> Flicker_Statistics` (the series at 60 Hz): `mean_step` the mean of `abs(series[t + 1] - series[t])`; the two shares the share of those above 0.05 and 0.1; `flares_per_second` the onsets of `series[t + 2] - series[t] > 0.15` (a tick that qualifies after one that did not) per `len / 60` seconds; `worst_lag_ratio` the least, over the lags 30 ..= len / 2, of the mean `abs(series[t] - series[t + lag])` over the mean difference of all pairs.
- `mean_pair_difference :: proc(series: []f32) -> f32`: a sorted copy (temp allocator), `2 * Σ x_k * (2k - n + 1) / (n * (n - 1))`.
- `test_the_fire_flicker_dances_without_period`: 8 salts (`DEFAULT_WORLD_SEED + 7919 * u64(index)`), 1860 ticks each (`seconds = f64(tick) / 60`). Every value within `FIRE_FLICKER_LOWEST ..= FIRE_FLICKER_HIGHEST`; per salt: lowest ≤ 0.62, highest ≥ 1.25, deviation ≥ 0.10, mean_step ≥ 0.028, step_share_above_5 ≥ 0.16, step_share_above_10 ≥ 0.03, flares_per_second within 0.8 to 3.5, worst_lag_ratio ≥ 0.7; under reduced motion exactly `FIRE_FLICKER_MEAN` at every tick; at 36000.5 s finite and within the bounds; salts 1 and 2 apart: their mean absolute difference ≥ 0.6 times the first's `mean_pair_difference`. Each failure message names the salt and the statistic.
- `test_the_flicker_statistics_catch_a_wave`: the helpers on a 1 Hz sine of amplitude 0.1 about 0.85 (1860 ticks) give `worst_lag_ratio` below 0.4 and `mean_step` below 0.012, so the guard above would catch the 0273 wave.
- `FIRE_FLICKER_DUMP :: #config(FIRE_FLICKER_DUMP, false)` and `test_print_the_window_flicker_series` (a no-op unless the define is true): prints `tick,window_0,...,window_4` CSV lines of `arrival_window_flicker` for the shipped fall (`shipped_arrival_config().arrival_ticks`, `DEFAULT_WORLD_SEED`), then one `flicker_statistics` line per window. The implementer's judging tool: `./build.sh test -define:FIRE_FLICKER_DUMP=true -define:ODIN_TEST_NAMES=game.test_print_the_window_flicker_series`. Prints only, writes no file.

In `src/render_arrival_test.odin`, `test_the_window_flicker_has_no_period` rewritten (the statistics live in the fire test now): for the 5 windows of the shipped fall, `arrival_window_flicker` equals `fire_flicker(f64(seconds), DEFAULT_WORLD_SEED + 20 + 2 * window, false)` at every 60th tick, `FIRE_FLICKER_MEAN` under reduced motion, every pair of windows apart (mean absolute difference over the fall ≥ 0.6 times the first's `mean_pair_difference`), and `arrival_window_flickers` matches per window as today.

`test_the_plasma_shader_knows_the_flicker_mean` (in `src/shader_source_test.odin`): `#load("../data/shaders/arrival.fs", string)` contains `fmt.tprintf("const float FLICKER_MEAN = %.2f;", FIRE_FLICKER_MEAN)` and the line `uniform float calm;`.

`test_shipped_shaders_have_no_bare_integer_literals` covers the new shader as is.

### build.sh and the capture

- `build.sh`: `test) shift; run_tests "$@" ;;`, so a test run takes defines. `doc/build.md`, build.sh: the `test` line says it passes further arguments to `odin test`.
- `tools/capture_clip.sh <name> [frames=60] [crop=140x150+580+160]` (tracked; the main agent runs it, the implementer writes it and runs `bash -n` on it): against a running developer session paused where wanted, with `MOC` (default `tools/moc`, so a session's wrapper can be named) and `SCREENSHOTS` (default `$XDG_STATE_HOME/mine-oh-belowed/screenshots`) from the environment. Per frame `"$MOC" tick 1`, `"$MOC" screenshot <name>_NN`, then waits (poll 0.05 s, up to 10 s) for the file, since it exists only once the game drew its next frame. Then `magick montage` of every third frame cropped to `crop` (`-tile 10x -geometry +2+2`) into `<name>_strip.png`, and `magick -delay 2 -loop 0` of all frames resized to 640x360 into `<name>.gif` (60 frames at 2 hundredths a second play at 50 fps, near the tick rate), both in `SCREENSHOTS`; prints their paths. `doc/commands.md`, For the assistant: a step 6 naming the script.

### Docs

- `doc/presentation.md`, The arrival, the windows bullet: replace the sentences from "The glass shows the plasma sheath" to "so nothing repeats." and the flicker sentence with: the glass shows the plasma sheath as a flow (DESIGN.md, Fire): a haze over the whole glass, brightest at the leading edge, tongues and sparks streaming aft; the colour a fixed ramp of the two data colours by the local intensity (dim violet, the haze's pink, salmon, the ablator's orange, white), which the heat, the tongues and the flicker raise, and patches richer in the ablator run higher. The tongues are 3D value noise (across, along scrolled aft, time), so they change shape as they go and live a fraction of a second; a slow and a fast layer (1.4 and 5.5 glass radii a second) are crossfaded by the heat. The sparks live a fifth of a second and burn out on the glass. The flicker (`arrival_window_flicker` through `fire_flicker`, 0286: four bands of hashed value noise from 2.3 to 23.7 Hz and hashed flares and dips, 0.4 to 1.5) drives the glass's brightness, the tongues' reach, the sparks' rate and the window's light alike; under reduced motion it holds its mean and the flow runs at its slow layer with its morph, its warp and the sparks at 0.4 of their pace (`calm`).
- `doc/presentation.md`, the sky light bullet: the portholes' flicker (`arrival_window_flicker`, through `fire_flicker`) stands still and their flow runs calm (0286).
- `doc/code_map.md`, the `render_flames.odin` line: "the fire flicker (`fire_flicker`, 0286)".
- `DESIGN.md`, Fire (needs the main agent's approval, see below): "what the heat changes is the brightness, the reach, the speed and the sparks, never the hue of the whole" becomes: the colour is the fire's ramp read by the local intensity, so the heat and the flicker move the brightness, and with it the place on the ramp (hotter whiter), the reach, the speed and the sparks, never a tint that drifts apart from the brightness.

### Hand-back check

Of the lines, only "Tests never touch the machine's state directory" applies: the dump test prints and writes nothing. No save, setting, list or UI audit case changes.

### For the main agent

- The black lower part of the glass is not the shader. In 0273's strip (`tmp/shot0273/crops/0273_porthole_strip.png`) the same straight edge stands at tick 700, where the glass is nearly clear and shows the sky above it, and at tick 1900, after the landing, with only soot above it. At the peak the plasma's alpha is 1 (`veil` at heat ≥ 0.8), and the shader discards only outside the disc, so a fragment there is either depth rejected by something in front of the glass or the quad does not cover it. I could not find the occluder by reading: the sleeve lining (`porthole_frames`, radius 0.4 from w -0.22 to +0.125, the glass at w 0 with radius 0.41) hides only about 0.06 of the radius at the 25 degrees I estimate for the chair's porthole. A one capture diagnostic: `rlgl.DisableDepthTest()` around the windows in `draw_arrival_windows`; if the plasma then fills the disc, something in front occludes it (a model or a mask), else the quad's placement. That fix belongs to a new item, not to this shader.
- DESIGN.md's Fire rule says the heat never changes "the hue of the whole"; the user's note asks for the colour to move with the heat and the flicker. The ramp keeps the fire's colours fixed and moves along them with the intensity (an incandescent body whitens as it brightens), which I read as within the rule's intent but not its letter. Approve the DESIGN.md sentence above or strike it.
- The shared seam: yes, `fire_flicker(seconds: f64, salt: u64, reduced_motion: bool) -> f32` in `render_flames.odin` is the seam, and only the portholes take it here. 0274's flames should not switch in this item: `flame_vertex_color` packs the flicker into a byte clamped to 0 to 1, and `flame.fs` reads it as the reach (`uv.y / (0.8 + 0.2 * flicker)`), so a switch needs the byte to carry flicker / `FIRE_FLICKER_HIGHEST` and the reach formula retuned, and the firebox lamp's 0.7 to 1 assumption in `test_the_furnace_burns_only_while_it_works` (render_flames_test.odin, line 91) widened. 0284's lights and the later furnace pass should call `fire_flicker` and retire `flame_flicker` then. Whether a torch wants the same 0.2 s flare slot and the same depth (a torch is smaller: 1.5 / sqrt(D) gives 5 to 7 Hz puffing for 5 cm) is theirs to decide; a per fire band table passed in would be the change then, not now.
- The window light's hue stays fixed (the flicker scales it); a light that whitens with the flares would mean a share driven by the flicker in `arrival_window_lights`. Left out for simplicity; say if wanted.
- The capture: start a session on the item's worktree paused at ticks 1000 (the sparks), 1271 (the peak) and 1600 (the fade) (0273's crop ticks), the chair's porthole framed as in `tmp/shot0286_clip.sh`, `tools/capture_clip.sh clip_<tick>` for each, then set the GIFs beside the Hopkins Soyuz window clip (2014) and a flame clip. Also one capture with reduced motion on at 1271 to see the calm flow.

### Decisions (main agent, 2026-10-05)

1. Approved as designed, the numbers included. The DESIGN.md sentence is replaced as proposed: the colour is the fire's ramp read by the local intensity, so the heat and the flicker move the brightness and with it the place on the ramp, never a tint apart from the brightness.
2. The window light whitens with the flares: `arrival_window_lights` mixes its colour towards `WHITE_CORE` by `clamp((flicker - FIRE_FLICKER_MEAN) / (FIRE_FLICKER_HIGHEST - FIRE_FLICKER_MEAN), 0, 1) * 0.5`, so a flare that whitens the glass whitens the cabin's light, and the window light test covers a flicker at the mean (the hue as today) and at the highest (half way to white).
3. The shared seam is `fire_flicker` in `render_flames.odin`; the furnace and torch flames keep `flame_flicker` here. 0284 and a later furnace pass move them over and retire it.
4. The black lower part of the glass is a separate item (0287), diagnosed by the main agent with the depth test off in a scratch build; nothing of it in this item.
5. `build.sh test` passing its arguments on and `tools/capture_clip.sh` are in scope; the dump test stays a no-op without its define.
