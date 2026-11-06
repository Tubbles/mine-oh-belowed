# 0305: The wake's colours from KSP

Status: verified (2026-11-06)

Milestone: the entry's look, after 0304. The user (2026-11-06), on 0304's captures: "For the color, let's take it from KSP" (`work/reference/0303/ksp_reentry_outside.jpg`). Those captures showed the shield and the wake's root burned to plain white, hiding the pod's lower half, and the wake above its orange band turning a grey lilac that reads as smoke, the porthole paler than 0288's.

## Goal

The wake and the shield's glow take the reference's colours: orange to red along the whole length, fading to clear rather than to grey or lilac, the shield yellow white inside an orange rim, nothing burned to plain white. Through the porthole the same wake reads in those colours. The opacity stays the user's 60.

## Controls

None.

## Change

- Measure the reference: the trail's colour by distance from the rim along it, the shield's centre and rim, how the trail's light and its saturation fall together.
- Set the wake's colour ramp (`arrival_wake.fs`) and the data colours (`arrival_plasma` in `data/game.sjson`) from it, and bound the intensity's mapping so the root and the shield keep their hue; the flakes' gold edge and dark plate still read against the new colours.
- Docs: `doc/presentation.md` (The wake), `doc/content.md` (`arrival_plasma`); the log.

## Verify

- The checks and the suite.
- Captures at the peak (tick 1271, seed 290) from the side, from below and from the chair's porthole, beside the reference; sent to the user.

## Specification (design, 2026-11-06)

The scripts and measurements are in `tmp/0305/` (`sample.py`, `band.py`, `fit.py`, `predict.py`, `check.py`, `clip.py`; previews `side_predicted.png`, `chair_predicted.png`, the new ramp painted on 0304's frame: the speckles in the side's tail are the fit's noise at the faintest opacity, the white at the rim's ends clipped source pixels, the sparks 0304's).

### Measured

The reference (sRGB, 5 by 5 means; the shield's rim ellipse is about 380 px tall, so a diameter D is about 380 px projected). The trail's brightest band by projected distance from the rim:

| distance | colour | hue | saturation | value |
|---|---|---|---|---|
| 0 to 0.37 D | 255 81..93 26..30 | 15 to 17 | 0.88 to 0.90 | 1.0 |
| 0.62 D | 219 63 18 | 14 | 0.92 | 0.86 |
| 0.9 D | 136 36 7 | 14 | 0.95 | 0.54 |
| 1.15 D | 72 13 0 | 11 | 1.0 | 0.28 |
| 1.4 D | 49 8 0 | 9 | 0.99 | 0.19 |
| 1.85 D | 26 2 1 | 3 | 0.98 | 0.10 |
| 2.1 D | 12 1 0 | 2 | 1.0 | 0.05 |

Only the light falls: the saturation stays 0.88 to 1.0 to the end, the hue slides from orange (16) to red (3) as the light fades, nothing is grey, violet or white. Past 0.37 D the light halves about every 0.35 D projected. The silhouette band is about twice the inner face's light at the same distance. Over the ground the trail adds light (150, 48, 19) and the ground stays visible: an emitter of its own hue, not a veil. The shield's face is yellow white, (254, 250, 142) hue 58 saturation 0.44, (254, 243, 137) and (254, 253, 158), a highlight (254, 252, 211) at 0.17; its rim ring orange, (254, 96, 34) hue 17 saturation 0.87, (182, 53, 14) on the dim side; where the trail leaves the rim (253, 134, 82) hue 18. The cone is lit salmon orange, hue 13, saturation 0.52 to 0.78, value 0.69 to 0.83.

Ours (0304 at 1271, opacity 60; per pixel the intensity I and the background recovered from the captures at 20, 40, 60 and 80, `fit.py`): the side's tail (8 to 18 cells) has I 0.04 to 0.46 and the colour (60..102, 33..57, 76..98), a dark violet at value 0.3 to 0.4, which darkens the sky from value 0.94 to 0.70 to 0.86 (the smoke); from I 0.7 the colour is pink (hue 316 to 358); the root (median I 2.5) and the disc are white. The chair's glass: median I 0.95, mean (213, 171, 153), hue 19, saturation 0.28, 62 percent warm and 33 percent violet. The cause: the ramp's dim stop is the haze times `VIOLET_SHADE` and `shell` multiplies the ramp by 0.35 + 0.75 I, so a faint wall is a dark violet veil over the bright day sky; above I 1.05 the ramp mixes to `WHITE_CORE` and the factor reaches 1.15, so the root, the silhouettes and the disc clip to white.

### Decisions

1. The ramp runs by the local intensity as before (KSP's hue follows its light, and the silhouettes brightest), through three colours at full value: from the haze's red towards the ablator's orange by 1 - exp(-I / 0.55) (0.77 of the way at the porthole's reference 0.8), then towards a hot gold, the ablator 0.3 of the way to the core colour, by `smoothstep(2.5, 6.0, I)`, which only the root's silhouettes and its tongues' cores reach. Why: on a dark sky our light is the opacity (1 - exp(-1.145 I) at 60), and these give KSP's hue at each of its values (opacity 0.11 hue 7, 0.29 hue 10, 0.44 hue 12, 0.6 hue 14, 0.82 hue 16, KSP's 3 to 9, 9 to 11, 12 to 14, 12 to 14, 13 to 14); a smoothstep rises too late at the faint end. The gold is KSP's (253, 134, 82) where the trail leaves the rim.
2. Data colours: `haze_color` [255, 28, 6] (hue 5, KSP's faint end), `ablator_color` [255, 92, 30] (hue 16.5, its bright body and the shield's rim), and a new key `core_color` [255, 248, 150] (hue 56, saturation 0.41, the shield's face), each 0 to 255 per channel and never black, as the other two. Why a key: the ramp needs a third hue the other two cannot mix (yellow), and the user tunes these colours as data. The two old keys keep their names (the air's glow and the shield's), so nothing else reads differently.
3. The colour keeps its full value: `shell` drops the 0.35 + 0.75 I factor, so the light falls by the opacity alone, as KSP's trail on its dark sky; on our bright sky the faint wall is then a light warm veil, not a dark one. No stop is white and none exceeds 1, so nothing clips.
4. The opacity law stays 0304's (1 - exp(-k I), `wake_opacity_percent` 60 at I 0.8). A steeper fall below 0.8 (I to the power 1.6) clears the side's tail sooner (its violet share 11 to 5 percent, `predict.py side 1.6`) but lets the sky's blue into the porthole's dim streaks (warm 99 to 87 percent, violet 0 to 7), and the porthole is the only view a player has.
5. The shield's disc: the ramp's colour at its intensity (orange at the peak), turned towards `core_color` inside 0.78 of the radius (full inside 0.78, none outside 0.95) by `smoothstep(0.3, 0.8, heat)`, so the face is yellow white inside an orange ring at the peak and reddens towards the onset. Its alpha stays the shell's. Why: KSP's orange ring is about the outer tenth of the radius.
6. The sparks run from the ablator towards `core_color` (0.35 + 0.5 of the white share, as now), gold to pale yellow, never white.
7. The flakes: their rim's gold and their streak's head take `core_color` where they took `WHITE_CORE`; the plate's char and opacity are unchanged. Against the new orange and coral the dark core reads better than against white, and the rim runs gold (hue 26 at brightness 0.6) to yellow (hue 53 at 1), where it ran to pale white.
8. The cabin's light: the porthole lights are the wake's colour where the chair's porthole looks, the haze mixed with 0.77 of the ablator (`ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE` 0.3 to 0.77, the ramp at the reference intensity, hue 14; at 0.3 the cabin would be lit a deep red the porthole does not show), and a flare turns them towards `core_color` instead of white (`ARRIVAL_WINDOW_WHITE_LIGHT`). Its luminance falls to about 0.7 of 0304's (red orange against pink); the gain stays.
9. A data edits copy of `game.sjson` without `core_color` reads it black and is refused at the start, which falls back to the data files with its log line, as 0304's new key did; the copy's other edits wait until it is saved again.

### Code

`data/game.sjson`, `arrival_plasma`: `haze_color = [255, 28, 6]`, `ablator_color = [255, 92, 30]`, `core_color = [255, 248, 150]` after `ablator_color`. Its comment: the plasma's colours are Kerbal Space Program's reentry (0305); `haze_color` the air's glow (red, the wake where its light is faint), `ablator_color` the heat shield's (orange, its rim and the wake's bright body), `core_color` the hottest (yellow white, the shield's face, the sparks and the flakes' rims), 0 to 255 per channel, never black; the heat drives the wake's opacity and its place between them, never their hue. The soot and opacity sentences stay.

`src/data_load.odin`:
- `Arrival_Plasma_Config`: `haze_color, ablator_color, core_color: [3]int,`; the comment above names 0305 and the hottest colour.
- `arrival_problem`: three bound rows `{"arrival_plasma.core_color", config.arrival_plasma.core_color[0..2], 0, MAXIMUM_COLOR_COMPONENT}` after the ablator's; the black list gains `{"core_color", config.arrival_plasma.core_color}`.

`src/render_arrival_wake.odin`:
- `ARRIVAL_WAKE_HOT_SHARE :: 0.3` (the hot stop's share of the way from the ablator to the core colour: the gold where KSP's trail leaves the rim) and `ARRIVAL_WAKE_RAMP_STOPS :: 4`.
- `arrival_wake_ramp_stops :: proc(plasma: Arrival_Plasma_Config) -> [ARRIVAL_WAKE_RAMP_STOPS][3]f32`: the haze, the ablator, `ablator + (core - ablator) * ARRIVAL_WAKE_HOT_SHARE` (the ramp's three) and the core (the disc and the sparks), each through `arrival_plasma_color`. The single source of what the shader mixes, so the test reads exactly that.
- `draw_arrival_wake`: the two colour lines become `stops := arrival_wake_ramp_stops(plasma)` and `set_shader_vector3` of `haze_color`, `ablator_color`, `hot_color`, `core_color` from `stops[0]` to `stops[3]`.

`src/render_arrival_flakes.odin`, `draw_arrival_flakes`: the parameter `haze, ablator, core: [3]f32`; sets `core_color` after `ablator_color`. `src/render_arrival.odin`, `draw_arrival_entry`: passes `arrival_plasma_color(plasma.core_color)` as well.

`src/render_arrival.odin`:
- `ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE :: 0.77`, its comment: the ablator's share of the light's colour is the wake's ramp at `ARRIVAL_WAKE_REFERENCE_INTENSITY`, the colour the chair's porthole shows (0305).
- `ARRIVAL_WINDOW_WHITE_LIGHT` goes.
- `arrival_window_light_color :: proc(color, core: [3]f32, flicker: f32) -> [3]f32`: towards `core` by the same share; its comment: a flare that drives the wake up its ramp turns the cabin's light towards the core colour.
- `arrival_window_lights`: `core := arrival_plasma_color(plasma.core_color)`, passed to `arrival_window_light_color`; its comment's "whitened by a flare" becomes "turned towards the core colour by a flare".

`data/shaders/arrival_wake.fs`:
- Header: "the colour a fixed ramp of the two data colours read by the local intensity (plasma_ramp)" becomes "the colour a ramp of the data colours read by the local intensity at full value, so the light falls by the opacity alone (plasma_ramp, 0305)".
- `WHITE_CORE` and `VIOLET_SHADE` go. New uniforms after `ablator_color`: `uniform vec3 hot_color;` and `uniform vec3 core_color;`. New constants with a comment (KSP's trail, 0305: the hue by the light as KSP's on its dark sky; the porthole's 0.8 reads 0.77 of the way to orange, `ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE`):

```glsl
const float RAMP_ORANGE_SCALE = 0.55;
const float RAMP_HOT_FROM = 2.5;
const float RAMP_HOT_FULL = 6.0;

// The fire's ramp by the local intensity (0305, KSP's trail): the haze's
// red, the ablator's orange, the hot gold, every stop at full value.
vec3 plasma_ramp(float intensity)
{
    vec3 c = mix(haze_color, ablator_color, 1.0 - exp(-max(intensity, 0.0) / RAMP_ORANGE_SCALE));
    return mix(c, hot_color, smoothstep(RAMP_HOT_FROM, RAMP_HOT_FULL, intensity));
}

// ... not premultiplied. The colour keeps its full value, so the light
// falls by the opacity alone and the wake fades to clear on a bright sky.
vec4 shell(float intensity, float chemistry)
{
    vec3 c = plasma_ramp(intensity + 0.18 * (chemistry - 0.5));
    float alpha = 1.0 - exp(-opacity_scale * intensity);
    return vec4(c, alpha);
}
```

- The disc's branch, after `vec4 shield = shell(...)`:

```glsl
        float core_share = (1.0 - smoothstep(0.78, 0.95, along)) * smoothstep(0.3, 0.8, heat);
        shield.rgb = mix(shield.rgb, core_color, core_share);
```

- The sparks: `spark_layer`'s out parameter `white_share` becomes `core_share` (its comment "its colour's core share"), the locals `first_white`, `second_white`, `white_share` become `first_core`, `second_core`, `spark_core`, and `vec3 spark_color = mix(ablator_color, core_color, 0.35 + 0.5 * spark_core) * (0.8 + 0.3 * flicker);`.
- Everything else (the geometry, the flow, the noise, the flicker, `WAKE_GAIN`, `COS_FLOOR`, the opacity) stays.

`data/shaders/arrival_flake.fs`: `WHITE_CORE` goes, `uniform vec3 core_color;` after `ablator_color`; `vec3 gold = mix(ablator_color, core_color, 0.25 + 0.4 * fragment_whiteness);`, `vec3 streak_color = mix(mix(ablator_color, core_color, 0.6), haze_color, trail);`. Header: "rimmed in the ablator's gold towards white" becomes "rimmed in gold, the ablator's orange towards the core colour", "cooling from white gold to the air's pink" becomes "cooling from gold to the air's red". `fragment_whiteness` and the flake's `whiteness` keep their names.

### Tests

- `src/render_arrival_wake_test.odin`, new `test_the_wake_ramp_stays_warm` (no window): for `arrival_wake_ramp_stops(shipped_arrival_config().arrival_plasma)`, every stop has red 0.95 or more and red >= green >= blue (hue 0 to 60, so never pink, lilac or violet, which need blue over green), and saturation `1 - blue / red` 0.35 or more (never grey or white); `green / red` rises strictly from stop to stop (red, orange, gold, yellow white). Its comment says why the stops suffice: a mix of two neighbours keeps red the largest and green over blue, its saturation near the lesser's. Shipped: saturation 0.98, 0.88, 0.74, 0.41.
- `src/shader_source_test.odin`:
  - `test_the_wake_shader_takes_its_uniforms`: the vectors gain `hot_color` and `core_color`.
  - `test_the_flake_shaders_share_the_white_core_and_the_brightest` becomes `test_the_flake_shaders_take_the_core_colour_and_the_brightest`: neither `arrival_wake.fs` nor `arrival_flake.fs` contains `WHITE_CORE`, `arrival_wake.fs` not `VIOLET_SHADE`, `arrival_flake.fs` declares `\nuniform vec3 core_color;\n`; the vertex shader's brightest as before.
  - New `test_the_window_light_is_the_wake_at_the_porthole`: `RAMP_ORANGE_SCALE` read from `arrival_wake.fs` (`shader_float_constant`, found), `1 - math.exp(-ARRIVAL_WAKE_REFERENCE_INTENSITY / scale)` within 0.01 of `ARRIVAL_WINDOW_LIGHT_ABLATOR_SHARE` (0.766 shipped).
- `src/data_load_test.odin`, `test_arrival_values_are_bounded`: `core_color[2] = 256` names `arrival_plasma.core_color`; `core_color = {0, 0, 0}` names `arrival_plasma.core_color is black`.
- `src/render_arrival_test.odin`, `test_the_window_light_follows_the_heat`: the flare's colour is `(mixed + core) * 0.5` with `core := arrival_plasma_color(plasma.core_color)`; its comment "half way to white" becomes "half way to the core colour".

### Docs

- `doc/presentation.md`, The arrival, the wake bullet: the colour sentence becomes Kerbal Space Program's trail (0305): a ramp of the data colours (`arrival_plasma`, `arrival_wake_ramp_stops`) read by the local intensity, from the haze's red towards the ablator's orange by 1 - exp(-I / 0.55), then towards the hot gold (the ablator 0.3 of the way to the core colour) from 2.5 to 6, KSP's hue at each light on its dark sky, patches richer in the ablator running higher; every stop at full value, so the light falls by the opacity alone, the wake fading to clear rather than darkening the sky, and nothing reaches white. The disc: the core colour's yellow white inside 0.78 of its radius as the heat rises from 0.3 to 0.8, the ramp's orange at its rim. The sparks run from gold to the core colour. The flicker "drives its brightness" becomes "drives its intensity (its opacity and its place on the ramp)".
- The windows bullet: the light is the wake's colour where the chair's porthole looks, the haze mixed with 0.77 of the ablator's (the ramp at the reference intensity, 0305), turned by a flare towards the core colour by up to half (where it says the wake's white).
- The flakes bullet: "rimmed in the ablator's gold whitening the faster it goes" becomes "rimmed in gold, the ablator's orange turning towards the core colour the faster it goes"; "cooling from white gold to the haze's pink" becomes "cooling from gold to the haze's red".
- `doc/content.md`, `arrival_plasma`: 0305 in the list, the shipped `haze_color` [255, 28, 6], `ablator_color` [255, 92, 30], new `core_color` [255, 248, 150]; the colours are KSP's reentry; `haze_color` the air's glow (red, the wake where its light is faint), `ablator_color` the heat shield's (orange, its rim and the wake's bright body), `core_color` the hottest (yellow white: the shield's face, the sparks, the flakes' rims), never black, a missing key refused as the others; "the heat drives their brightness, never their hue" becomes "the heat drives the wake's opacity and its place between them, never their hue".
- `DESIGN.md`, Fire: "an entry's pink violet air plasma with the ablator's orange and white cores" becomes "an entry's red air plasma running into the ablator's orange, yellow white only on the heat shield's face and never plain white (Kerbal Space Program's reentry, user, 2026-11-06)".
- `doc/log/2026-11-06.md` (the main agent's): the measured cause (the dark violet dim stop and the brightness factor; the white above 1.05), the full value decision and the opacity law kept for the porthole (decision 4), the new key and the old copy rule, the cabin light's share.

### Hand-back check

- Start-up load: an old data edits copy without `core_color` is refused and the start falls back to the data files (decision 9); `data_load_test` covers the bound and the black key.
- Numbers parsed from text: the new channels are bounded 0 to 255 as the others.
- No save, record, budget, list, UI audit or file write change. Tests read `data/` only.
- No perceivable repetition: colours only, no new pattern.

### Capture (main agent)

As 0304's (`tmp/shot0304`, seed 290, tick 1271), all at the shipped opacity 60: the side `arrival_camera 0 3 -32`, below `arrival_camera 0 -14 -26`, the chair's porthole (`look 180 -2`, crop 140x150+580+130) and its 120 frame clip. Run `python3 tmp/0305/check.py side|below|chair <capture>` and `python3 tmp/0305/clip.py <dir> <prefix>`; the masks come from 0304's captures of the same frames, valid since nothing moves. Bounds, with 0304's value and the prediction (`predict.py`, the new ramp on the recovered I and background):

| region | bound | 0304 (o60) | predicted |
|---|---|---|---|
| side root 0 to 4 cells | white 5 % or less; mean hue 12 to 25; mean saturation 0.6 or more | 64 %; 34 at 0.04; 0.05 | 0; 17; 0.85 |
| side middle 4 to 10 | warm 90 % or more; violet 5 % or less; mean saturation 0.5 or more | 47 %; 39 %; 0.37 | 100 %; 0; 0.71 |
| side tail 10 to 22 | grey 2 % or less; mean value 0.84 or more; mean hue 330 to 360 or 0 to 40; violet 15 % or less | 0; 0.82; 222; 11 % | 0; 0.86; 341; 11 % |
| chair glass | warm 90 % or more; violet 5 % or less; mean saturation 0.45 or more; mean value 0.8 or more | 62 %; 33 %; 0.35; 0.85 | 99 %; 0; 0.50; 0.87 |
| chair clip, 120 frames | warm mean 85 % or more; violet mean 10 % or less | 75 %; 22 % (opacity 80) | none (one opacity) |
| below disc inside 0.7 | white 5 % or less; mean hue 45 to 62; mean saturation 0.25 to 0.55 | 100 % white (opacity 80) | about hue 55, 0.36 |
| below disc rim 0.85 to 1.0 | mean hue 12 to 35; mean saturation 0.45 or more | 87 % white (80) | about hue 21, 0.68 |
| below tube near the rim, middle | white 5 % or less; warm 85 % or more; violet 5 % or less | 93 % white; 52 % warm, 44 % violet (80) | none |

The porthole's mean lightness falls from L* 73 to about 64 while its saturation nearly doubles: it reads as a red orange fire, coral where the sky shows through 40 percent of it. Beside the reference: orange at the root, red orange in the body, a pale rose fading to the sky in the tail (KSP's red fading to black), the shield yellow white in an orange ring, the flakes dark plates with a gold rim.

### For the main agent

1. The tail over the day sky: any red veil at low coverage over the light blue is a pale rose (hue 340 to 355, saturation 0.1 to 0.2), and where it is faintest a mauve (11 percent of the tail's pixels by the violet test, as 0304's 11), but lighter than 0304's (value 0.86 against 0.82) and with no dark violet. If the user still reads it as lilac, a steeper opacity below 0.8 (decision 4) is one constant, at the porthole's cost.
2. Through the porthole the composite reads coral (hue 10) where KSP's emitter at that light is hue 16: the 40 percent of sky behind it pulls it towards red. A more orange read there needs an emitter hue near 22, off KSP's; kept on KSP's.
3. KSP's trail keeps its full light for about 0.37 D and then halves about every 0.35 D (projected), where ours halves every 0.25 D from the rim (0303's measurement, 0304's geometry): our orange body is shorter. Out of this item's scope.
4. The cabin's light falls to about 0.7 of 0304's luminance with the red orange colour (decision 8); `ARRIVAL_WINDOW_LIGHT_GAIN` stays 0.7 unless the couch finds the cabin too dark.

### Decisions (main agent, 2026-11-06)

1. The faint tail's rose over the day sky is accepted as the red over blue it is; the capture shows it to the user, and the steeper fade stays a one constant answer for later.
2. The porthole keeps KSP's colours and reads coral, as the user asked for KSP's colour.
3. The light's fall along the wake stays 0304's (half every quarter diameter); KSP's longer bright body is offered to the user beside the capture, not done here.
4. The cabin light at gain 0.7, red orange and about 30 percent dimmer, as specified; the capture from the chair shows it.
