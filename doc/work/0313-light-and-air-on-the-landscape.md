# 0313: Light and air on the landscape

Status: verified (2026-11-07)

Milestone: the world generation series 0306 to 0313. The user (2026-11-06): "just generally better visuals".

## Goal

The landscape has depth and time of day: a warm sun and a cool sky light from above with a ground bounce from below in place of one grey ambient, distance haze tinted by the sky and the sun's side (aerial perspective) so ranges stand behind each other, and the sun's shadow of the terrain and the trees where the budget allows.

## Controls

None.

## Change

- The field, model and tree shaders' light terms and the fog, the colours from `data/lighting.sjson` and the day clock.
- Shadows as their own decision in the design: a cascade on the couch behind a setting, none on the phone.
- Docs: `doc/presentation.md`; the log.

## Verify

- The checks, the suite, `shader_source_test.odin`.
- Captures at dawn, noon and dusk from the ground and from 120 m up; the frame cost on the couch and the Deck's setting; sent to the user.

## Specification (design, 2026-11-07)

Prototype: the shaders below compile and link through Mesa as GLSL 3.30 and as ES 3.00 (`tmp/0320/mesa_shader_check.py`, both pairs), with no bare integer literal and no reserved word; the full prototype files are `/var/home/Tubbles/dev/mine-oh-belowed/tmp/0313/shaders/field.fs`, `field.vs` and `model.fs`, and `tmp/0313/sheet_v1.png`, `sheet_v2.png` compare today's light and fog with this one on a synthetic terrain (`tmp/0313/render_prototype.py`).

### Decisions

- Keys in `data/game.sjson`, not `data/lighting.sjson`: `lighting.sjson` is the simulation's light fill (`Simulation_Content.lighting`, [content.md](../content.md), Lighting), while this light is presentation and its existing keys are `sun_and_torchlight`'s (0297). One place: `sun_and_torchlight` takes the sun's and the sky's keys, a new table `haze` the haze's.
- The colours per time of day come from the clock: the sky's light and the haze's colour from the clock's `Sky_Colors` (the dome's zenith and horizon, `render_day.odin`'s constants), so the light always matches the sky the player sees, and the sun's light from two data colours (high and low) mixed by the sun's height. At night the sky's light is the night dome's, about 5 percent and blue; no moon term, the field stays dark and the torchlight needed (0297).
- Models keep their CPU face shade and their CPU light path. On the field the frame's flat light (the open sky's light on an upward face, clamped to 1) becomes `Model_Frame.sky_tint` with `day_factor` 1, so what the CPU lights from the frame (an idle model's emissive layer, a box fallback) follows the new light; the model shader divides that flat light out (`daylight_tint`) and multiplies the open sky's light by the face's normal. The face shade stays (shared with the block world and its tests); a side face therefore reads about 0.8 of the terrain under the same light.
- The haze: an exponential aerial haze from the eye whose air thins with height by `atmosphere.scale_height_metres` (the same air as the sky's), times the fragment's sky light (no sky colour in a cave), plus today's end fade (smoothstep over 0.6 to 1.0 of the last distance) to the full sky colour, scaled by `atmosphere_sky_share` at the eye so above the atmosphere's top the planet does not fade into the black sky. The colour is the altitude sky's horizon (what the dome and the clear show behind the terrain), plus a warm lobe towards a low sun; the field's dome takes the same lobe and reaches below the horizon, so the hazed far terrain, the globe and the sky meet without a band.
- The globe draws through the model shader's lit material, so it is lit and hazed as the terrain is.
- Shadows: not in this item (section Shadows, a question below).

### Shaders

`data/shaders/field.fs`: drop `sky_ambient`, `sun_strength`, `daylight`, `fog_color` and `in float fragment_distance`; before the point lights' block add (identical text in `model.fs`):

```glsl
uniform vec3 sun_direction;
uniform vec3 sun_color;
uniform vec3 sky_color;
uniform vec3 bounce_color;

vec3 outdoor_light(vec3 normal, vec3 up)
{
    float upward = 0.5 + 0.5 * dot(normal, up);
    return mix(bounce_color, sky_color, upward) + sun_color * max(dot(normal, sun_direction), 0.0);
}

uniform vec3 haze_color;
uniform vec3 haze_sun_color;
uniform float haze_density;
uniform float haze_scale_height;
uniform float haze_end_share;
uniform float planet_radius;
uniform float eye_height;
uniform float fog_start;
uniform float fog_end;

const float haze_sun_exponent = 6.0;
const float haze_level_rise = 0.01;

vec3 apply_haze(vec3 color, vec3 position, vec3 eye, float sky_share)
{
    vec3 offset = position - eye;
    float reach = length(offset);
    float height = length(position) - planet_radius;
    float rise = (height - eye_height) / haze_scale_height;
    float mean_density = abs(rise) < haze_level_rise ? exp(-0.5 * (height + eye_height) / haze_scale_height) : (exp(-eye_height / haze_scale_height) - exp(-height / haze_scale_height)) / rise;
    float aerial = 1.0 - exp(-reach * haze_density * mean_density);
    float end = haze_end_share * smoothstep(fog_start, fog_end, reach);
    float amount = sky_share * (1.0 - (1.0 - aerial) * (1.0 - end));
    float toward_sun = max(dot(offset, sun_direction) / max(reach, smallest_weight_sum), 0.0);
    vec3 sky = min(haze_color + haze_sun_color * pow(toward_sun, haze_sun_exponent), vec3(1.0));
    return mix(color, sky, amount);
}
```

The mean density is the exact mean of `exp(-h / H)` along a ray whose height runs linearly from the eye's to the fragment's (stable from the cave floor to orbit: neither exponential overflows within the far plane). `field.fs` main, from the light on (`up` is `normalize(fragment_world_position)`, shared with the steepness line):

```glsl
    vec3 outdoor = fragment_color.a * outdoor_light(normal, up);
    vec3 light = max(vec3(fragment_block_light), outdoor);
    vec3 lit = albedo * light;
    lit += albedo * point_light_sum(fragment_world_position, normal);
    lit += albedo * spot_light(fragment_world_position, normal);
    vec3 to_camera = normalize(camera_position - fragment_world_position);
    float glint = water * fragment_color.a * pow(max(dot(normal, normalize(sun_direction + to_camera + vec3(smallest_weight_sum))), 0.0), water_glint_power) * water_glint_strength;
    lit += sun_color * glint;
    finalColor = vec4(apply_haze(min(lit, vec3(1.0)), fragment_world_position, camera_position, fragment_color.a), mix(1.0, water_color.a, water));
```

`field.vs`: drop `camera_position`, `fragment_distance` and its line. `model.fs`: add `uniform float outdoor_on;`, `uniform vec3 daylight_tint;`, `uniform vec3 camera_position;` and the block above; main:

```glsl
    vec3 outdoor = outdoor_light(normal, normalize(fragment_world_position)) / max(daylight_tint, vec3(smallest_weight_sum));
    vec3 lit = base.rgb * mix(vec3(1.0), outdoor, outdoor_on) + fragment_color.rgb * (point_light_sum(fragment_world_position, normal) + spot_light(fragment_world_position, normal));
    vec3 clamped = min(lit, vec3(1.0));
    finalColor = vec4(mix(clamped, apply_haze(clamped, fragment_world_position, camera_position, 1.0), outdoor_on), base.a);
```

Both headers' comments follow (no "no directional sun", no fog colour). Cost: about 50 ALU operations a fragment against field.fs's up to 24 texture reads.

### Data

`sun_and_torchlight` (`Sun_And_Torchlight_Config`, `sun_and_torchlight_problem`): `sun_strength_percent` 100 (kept, 0 to 400); new `sun_high_color` [255, 243, 222] and `sun_low_color` [255, 150, 72] (`[3]int`, each 0 to `MAXIMUM_COLOR_COMPONENT`, neither black, refused by name as `arrival_plasma`'s are); `sky_ambient_percent` renamed `sky_light_percent` 60 (0 to `MAXIMUM_SUN_SHARE_PERCENT`), percent of the sky's light; new `ground_bounce_percent` 60 (0 to 100); the torchlight's keys unchanged. New table `haze` (`Haze_Config{metres, sun_glow_percent: int}`, `haze_problem`, called from `validate_game_config` after `sun_and_torchlight_problem`): `metres` 1500 (`MINIMUM_HAZE_METRES` 100 to `MAXIMUM_HAZE_METRES` 1_000_000; the distance over which air at the radius takes 63 percent of the sky's colour; a missing table reads 0 and fails), `sun_glow_percent` 50 (0 to 100). Comments in `game.sjson` as 0297's.

The shipped light (sun height `y` is `sun_direction(fraction).y`; flat is the upward face's light, clamped):

| time | y | sun | sky | flat | haze colour | glow |
|---|---|---|---|---|---|---|
| noon (0.25) | 0.94 | 1.0, 0.95, 0.87 | 0.39, 0.47, 0.55 | 1, 1, 1 | 0.78, 0.87, 0.94 | 0 |
| fraction 0.04 | 0.23 | 1.0, 0.75, 0.55 | as noon | 0.63, 0.65, 0.68 | as noon | 0 |
| dawn, dusk (0, 0.5) | 0 | 0.5, 0.29, 0.14 | 0.30, 0.25, 0.24 | 0.30, 0.25, 0.24 | 0.94, 0.55, 0.27 | 0.5, 0.29, 0.14 |
| midnight (0.75) | -0.94 | 0 | 0.04, 0.05, 0.10 | 0.04, 0.05, 0.10 | 0.11, 0.13, 0.23 | 0 |

Flat ground at noon takes about 1.35 of its albedo, today's 1.29.

### Odin

`render_day.odin` (pure):
- `SUN_LIGHT_SET_HEIGHT :: -0.05`, `SUN_LIGHT_RISEN_HEIGHT :: 0.05`, `SUN_HIGH_HEIGHT :: 0.5`, `SKY_LIGHT_ZENITH_SHARE :: 2.0 / 3.0`.
- `sun_light_color :: proc(fraction: f64, light: Sun_And_Torchlight_Config) -> [3]f32`: `mix(high, low, 1 - smoothstep(0, SUN_HIGH_HEIGHT, y)) / 255 * smoothstep(SUN_LIGHT_SET_HEIGHT, SUN_LIGHT_RISEN_HEIGHT, y) * sun_strength_percent / 100`.
- `sky_light_color :: proc(colors: Sky_Colors, light: Sun_And_Torchlight_Config) -> [3]f32`: `mix(horizon, zenith, SKY_LIGHT_ZENITH_SHARE) / 255 * sky_light_percent / 100` (the cosine weighted mean of a dome linear in the sine of the elevation, as `sky_color_towards` is).
- `ground_bounce_color :: proc(ground, sun, sky: [3]f32, sun_height: f32, light: Sun_And_Torchlight_Config) -> [3]f32`: `ground * (sun * max(sun_height, 0) + sky) * ground_bounce_percent / 100`.
- `haze_sun_glow_color :: proc(fraction: f64, light: Sun_And_Torchlight_Config, haze: Haze_Config) -> [3]f32`: `sun_low_color / 255 * twilight_share(sun_height(fraction)) * sun_glow_percent / 100`.

`render_sky.odin`:
- `HAZE_SUN_EXPONENT :: 6.0` (the shaders' `haze_sun_exponent`); `SKY_DOME_SEGMENTS` 24 to 48 (a 7.5 degree step keeps the lobe smooth under Gouraud); `SKY_DOME_RINGS_BELOW :: 2`: rings from `-SKY_DOME_RINGS_BELOW` to `SKY_DOME_RINGS - 1` at `ring / SKY_DOME_RINGS * 90` degrees, vertex `(ring + SKY_DOME_RINGS_BELOW) * SKY_DOME_SEGMENTS + segment`, the apex last; `SKY_DOME_VERTEX_COUNT` 481, `SKY_DOME_TRIANGLE_COUNT` `(SKY_DOME_RINGS + SKY_DOME_RINGS_BELOW - 1) * SKY_DOME_SEGMENTS * 2 + SKY_DOME_SEGMENTS`. The lower rings take the horizon colour (`sky_color_towards` clamps), the clear colour, so the block world looks the same.
- `Sky_Glow :: struct {direction, color: [3]f32}` (the sun in the sky's frame, the lobe's colour 0 to 1); `sky_glow_towards :: proc(glow: Sky_Glow, direction: [3]f32) -> [3]f32`: `color * pow(max(dot(direction, glow.direction), 0), HAZE_SUN_EXPONENT)`; `fill_sky_dome_colors(colors, vertex_colors, glow := Sky_Glow{})` adds it to each vertex, each channel clamped at 255; `draw_sky_dome` and `draw_sky(..., glow := Sky_Glow{})` pass it on. The block world passes none.

`render_point_lights.odin`:
- `Field_Haze :: struct {color, sun_color: [3]f32, density, scale_height, end_share, planet_radius, eye_height, fog_start, fog_end: f32}`.
- `Field_Frame_Lights`: `sun_direction`, `sun_color`, `sky_color`, `bounce_color`, `flat_light` (all `[3]f32`), `haze: Field_Haze`, `spot`; `sky_ambient` and `sun_strength` go.
- `Field_Light_Inputs :: struct {sky: Day_Sky, daylight: f32, ground_color: [3]f32, planet_radius_metres, last_distance_metres: f32, light: Sun_And_Torchlight_Config, haze: Haze_Config, atmosphere: Atmosphere_Config}` (`sky` the clock's at the ground, `daylight` 1 in a session and the planet preview's share).
- `field_frame_lights :: proc(inputs: Field_Light_Inputs, camera: rl.Camera3D, torchlight: bool) -> Field_Frame_Lights`: the sun's world direction as today; `sun_color` and `sky_color` from the procedures above times `daylight`; `bounce_color` from them with `y`; `flat_light` `clamp(sky + sun * max(y, 0), 0, 1)`; altitude `length(camera.position) - planet_radius_metres`, `share := atmosphere_sky_share(altitude, atmosphere)`; `haze.color` `altitude_day_sky(sky, share).colors.horizon / 255`, `haze.sun_color` `haze_sun_glow_color(...) * share`, `density` `1 / haze.metres`, `scale_height` from the atmosphere, `end_share` `share`, `eye_height` the altitude, `fog_start` `last_distance_metres * FOG_START_SHARE`, `fog_end` `last_distance_metres`; `spot` as today.

`render_field.odin`:
- `Open_Sky_Uniform` enum (`Sun_Direction, Sun_Color, Sky_Color, Bounce_Color, Haze_Color, Haze_Sun_Color, Haze_Density, Haze_Scale_Height, Haze_End_Share, Planet_Radius, Eye_Height, Fog_Start, Fog_End`) with the uniform names; `open_sky_locations :: proc(shader: rl.Shader) -> [Open_Sky_Uniform]i32`; `set_open_sky_uniforms :: proc(shader: rl.Shader, locations: [Open_Sky_Uniform]i32, lights: Field_Frame_Lights)`, both shaders, every frame.
- `Field_Renderer`: drop `daylight`, `daylight_location`, `sun_direction_location`, `sky_ambient_location`, `sun_strength_location`, `globe_material`; add `open_sky_locations`, `globe_color: [3]f32` (`field_globe_color / 255`, the globe's and the bounce's colour), `last_distance_metres: f32` (the `fog_end` parameter of `init_field_renderer`, kept). `use_field_shader` sets no fog.
- `set_field_frame_lights` uploads `set_open_sky_uniforms` and the spot; `draw_field` draws no globe and sets no daylight.
- `draw_field_globe :: proc(renderer: ^Field_Renderer, models: Model_Renderer, daylight_tint: [3]f32)`: the globe through `model_layer_material(models, .Lit)` with its albedo `brightness_color(renderer.globe_color * daylight_tint)`, as an open sky model is lit (GenMeshSphere has normals; the missing colours default to white, as on today's default material).
- `FIELD_FOG_COLOR` goes; the model workbench keeps the value as `MODEL_PREVIEW_BACKGROUND_COLOR` atop `loop_model_preview.odin`.

`render_models.odin`: `Model_Renderer` gains `open_sky_locations` and the locations of `outdoor_on`, `daylight_tint`, `camera_position` (in `use_model_shader`); `model_frame_daylight_tint :: proc(frame: Model_Frame) -> [3]f32` (`day_factor * sky_tint`, what `model_light_tint` gives a full sky light); `set_model_open_sky :: proc(renderer: Model_Renderer, lights: Field_Frame_Lights, daylight_tint, eye: [3]f32)` (the uniforms and `outdoor_on` 1) and `clear_model_open_sky :: proc(renderer: Model_Renderer)` (`outdoor_on` 0), both nothing without the model shader (`point_lights_ready`).

`loop_field_session.odin`:
- `field_light_inputs :: proc(renderer: ^Field_Renderer, sky: Day_Sky, daylight: f32, planet_radius_metres: int, config: Game_Config) -> Field_Light_Inputs`.
- `draw_field_viewport_world`: the lights (`field_frame_lights(field_light_inputs(..., sky, 1, ...), camera, torchlight)`) before the sky; `draw_field_sky(..., Sky_Glow{direction = sun_direction(sky.fraction), color = lights.haze.sun_color})`; `Model_Frame{day_factor = 1, sky_tint = lights.flat_light, ...}`; `scene.lights = lights`.
- `draw_field_scene`: after `set_model_spot_light`, `set_model_open_sky(scene.models, scene.lights, model_frame_daylight_tint(scene.frame), camera.position)`, `draw_field_globe`, `draw_field`, then as today to the players; `clear_model_open_sky` before `draw_field_flames`, so the ghosts keep their full colour.
- `prepare_field_frame` sets no daylight.

`loop_planet_preview.odin`: `Planet_Preview.sun_and_torchlight` becomes `field_light: Field_Light_Inputs` built at start (`day_sky_at(NOON_FRACTION, 0)`, the flag's share as `daylight`); the renderer's daylight line goes; `planet_preview_scene` takes `field_frame_lights(preview.field_light, camera, false)` and `Model_Frame{day_factor = 1, sky_tint = lights.flat_light}`; `draw_planet_preview` clears with `preview.field_light.sky.colors.horizon`.

`loop.odin` (`draw_session_world`): `clear_model_open_sky` beside the cleared spot.

Not in this item: the foundations' slabs, runs, torch boxes, flames and debris keep their colours unhazed (the haze at the trees' 128 m is about 8 percent at the radius's height); a model in a cave takes the open sky's light as it takes the full sky light today; an emissive layer is not hazed; models keep `MINIMUM_MODEL_BRIGHTNESS` (0.06), so on a night field they stand a little brighter than the ground. Above the atmosphere's top (the arrival's first seconds) the end fade is off, so the drawn terrain's edge shows against the lit globe where today it shows a blue fog ring. No repetition: every term is smooth in position and direction, nothing tiles; the dome's 48 segments keep the glow free of facets.

### Tests

- `data_load_test.odin`: `test_sun_and_torchlight_is_range_checked` takes the shipped table with the new keys and refuses `sky_light_percent` 401, `ground_bounce_percent` 101, a `sun_low_color` component of 256 and a black `sun_high_color`, each by name; new `test_haze_is_range_checked`: the shipped {1500, 50} passes, `metres` 99 and 1_000_001 and `sun_glow_percent` 101 are refused by name, `haze_problem({})` fails, `validate_game_config` names it.
- `render_day_test.odin`: `test_the_sun_light_warms_low_and_sets` (noon equals `sun_high_color / 255` within 1e-6; fraction 0 equals half of `sun_low_color / 255`; 0.75 is zero; 200 percent doubles noon); `test_the_sky_light_takes_the_zenith_two_thirds` (noon equals `(horizon + 2 zenith) / 3 / 255 * 0.6` within 1e-5; midnight every channel above 0 and under 0.1, blue the largest); `test_the_bounce_is_the_ground_lit_from_above` (ground 0.5, sun 1, sky 0.2, 60 percent: 0.21 at height 0.5, 0.06 at -0.3); `test_the_haze_glows_towards_a_low_sun_only` (half of `sun_low_color / 255` at 0 and 0.5, zero at 0.25 and 0.75).
- `render_sky_test.odin`: `test_the_sky_dome_is_a_closed_hemisphere` becomes `test_the_sky_dome_closes_down_to_its_lowest_ring` (481 vertices, none lower than `sin(22.5°)` of the radius below the horizon, the open edges the lowest ring's); `test_the_dome_blends_horizon_to_zenith` also checks the horizon ring (vertex `SKY_DOME_RINGS_BELOW * SKY_DOME_SEGMENTS`); new `test_the_dome_glows_towards_a_low_sun` (noon's colours with `Sky_Glow{sun_direction(0.5), {0.1, 0.05, 0.02}}`: the horizon vertex towards the sun, at azimuth 180 degrees, is the horizon plus the glow within 1 per channel, the opposite one the horizon; with no glow every vertex equals the fill without one).
- `render_point_lights_test.odin`: `test_field_frame_lights_follow_the_clock` with inputs (radius 8000, camera at {0, 8002, 0}, up +y, last distance 1024, ground {0.3, 0.5, 0.2}): noon's sun and sky colours are the procedures', its flat light 1; midnight's sun colour zero and flat light its sky colour; a daylight of 0.5 halves the sun, sky and bounce colours; the spot as before. New `test_field_haze_follows_the_altitude`: at 2 m the end share 1, the colour the horizon over 255, density 1/1500, fog 614.4 to 1024, at dusk the glow `haze_sun_glow_color`; at 800 m (above the top) end share 0, no glow, the colour `SPACE_SKY_COLOR` over 255.
- `shader_source_test.odin`: new `test_the_lit_shaders_share_the_open_sky` (both declare the thirteen uniforms, `outdoor_light` and `apply_haze` equal line for line through a helper `shader_function_text(source, start)`); `test_the_field_shader_lights_by_the_sun` updated (field.fs declares `sun_color`, `sky_color`, `bounce_color` and holds no `sky_ambient`, `uniform float daylight;` or `fog_color`; model.fs declares `outdoor_on` and `daylight_tint`); new `test_the_haze_glow_is_the_domes` (both hold `const float haze_sun_exponent = 6.0;` formatted from `HAZE_SUN_EXPONENT`). The bare integer and reserved word tests cover the new text.

### Docs

`doc/presentation.md`: The field session (`prepare_field_frame`; the scene's globe first, the open sky on and off), Light on the field (rewritten: the open sky's light, the models' division, the haze, the dome's glow, the keys), Field meshes (the globe bullet; the field shader bullet's light and fog), Sky and day (the dome below the horizon, the field's glow), Machine models (0224's bullet: no longer "no directional sun"). `doc/content.md`, World: the `sun_and_torchlight` bullet and a `haze` bullet. `doc/build.md`: `--planet-preview-daylight` scales the open sky's light (the table row and line 156). `doc/code_map.md`: the `render_day.odin`/`render_sky.odin` and `render_point_lights.odin` lines name the new procedures and types.

### Hand-back check

- Numbers from text: every new key is bounded and tested by name.
- Start-up loads: a `game.sjson` copy in the edits directory older than this item reads the new keys as zero and fails by name (black sun, `haze.metres` 0), as 0297's keys did; no fallback is added here.
- Tests touch no state: the new tests are pure.

### Captures (the main agent's)

With `time dawn|noon|dusk`, from the ground and 120 m up, one toward and one away from the sun at dawn and dusk:
- Noon: flat ground as bright as today; slopes away from the sun bluer and darker, not black; trees with a lit and a shade side; ridges paler and bluer with distance, valleys hazier than crests, and from 120 m the farthest terrain in the sky's horizon colour with no blue fog band and no flat globe ring between it and the sky.
- Dawn and dusk toward the sun: a warm glow round the sun in the sky and the haze alike, continuous across the horizon line; terrain and trees backlit and dark; no blue band against the orange horizon (today's fog).
- Dawn and dusk away from the sun: slopes facing the sun catch warm grazing light, the rest lit by the warm grey sky; the far terrain fades into the orange horizon.
- Midnight (one shot): the ground near black, the landscape's outline faintly apart from the night horizon; the torchlight still needed.
- The couch's frame time on the F3 page at the same spot and time before and after.

### Shadows

Recommended: no shadows in this item; a separate item, on the couch and the Deck behind a setting, none on the phone, after 0310 (the forest's draw count is the main cost) and starting with a measurement in the benchmark window. The figures are estimates from published hardware figures and the field's draw limits, not measured (a GPU timing is a benchmark).
- One sun cascade of 2048² round the eye, 256 m across to cover the trees' 128 m: about 50 nodes of the first two levels (about 125 thousand triangles at 1 m spacing), up to 256 trees (`FIELD_TREE_DRAW_LIMIT`, the pine 100 faces) and the machines, so about 300 more `DrawMesh` calls a viewport.
- Couch (RX 5700, 7.9 TFLOPS, 448 GB/s, 1920 by 1080 at 60 Hz per the game log and the settings): GPU about 0.3 to 0.5 ms (the comparison taps in `field.fs` and `model.fs` the larger part), CPU about 1 to 2 ms on the 2700X for the draws through raylib (3 to 6 µs each), the dominant part, again per split screen viewport. About a tenth of the 16.7 ms frame.
- Deck (8 RDNA2 compute units, 1.6 TFLOPS, 88 GB/s, 1280 by 800, the preset's 40 fps cap, 25 ms): a 1024² cascade, GPU about 1 to 1.5 ms, CPU about 1 to 2 ms; affordable if today's frame leaves 3 ms, which no measurement shows yet.
- Phone (Mali or Adreno class, GLES 3.0, tiled): the extra target forces a tile store and a read back, the binning of about 200 thousand triangles, the comparison taps over about 2.5 million pixels and the draws on an ARM core: about 4 to 8 ms. Off.
- Ridge shadows across valleys at dusk need a second, far cascade over the whole kilometre: about 150 coarse nodes more, about 0.3 ms GPU and 0.5 to 1 ms CPU, refreshable every few frames since the sun moves slowly.
- The item would need: a depth target through rlgl (`rlLoadFramebuffer`, `rlLoadTextureDepth`), a depth only pass, a texel snapped cascade fit, `sampler2DShadow` in `field.fs` and `model.fs` (GLES 3.0 core, but 0105, 0106 and 0307 each found a driver that differs from the desktop's), a setting with its row and the Deck preset's entry; instancing the trees would cut the CPU part.

### Questions for the main agent

- Shadows as their own item after 0310, as above? If so, the Verify line's "the Deck's setting" moves there.
- `game.sjson` in place of `lighting.sjson` for the keys (Decisions)?
- The night stays dark (the night dome's light, no moon term)?

### Decisions (main agent, 2026-11-07)

1. Shadows are 0328, after 0310; the Verify's frame cost line here covers 0313's own shaders, the Deck's setting moves to 0328.
2. The keys in `game.sjson`, beside the sky's: accepted, since `lighting.sjson` holds the simulation's light fill.
3. Night stays as designed; the midnight capture goes to the user, who may ask for more.
4. Above the atmosphere's top the end fade goes to the globe's colour lit by the same open sky light (as `draw_field_globe` lights it) instead of being off, so the drawn terrain blends into the globe during the arrival's first seconds and shows no edge. The implementer adds it to `field.fs` and the model shader's haze and says how in the report; a capture from the arrival's start shows it.
