# 0297: Sun and torchlight

Status: landed (2026-11-05, 20f490b)

Milestone: the water tech demo (0291); the presentation stream.

## Goal

The field is lit by the sun where it stands in the sky: a directional term from the day clock's sun direction, strong at noon, gone at night, with the sky light as the ambient, so slopes facing the sun are bright and the water's sheet and waves catch it; and the player carries a torchlight, a spotlight from the eye along the view, strong enough to light a cave or a night-time dig, toggled on the D-pad.

## Controls

- Torchlight: D-pad up toggles the torchlight in the tech demo and under `--dev` (D-pad up is Pipette in the world, which has no use without an inventory game; in the tech demo the binding's world meaning is the torchlight, a mode choice, documented in `doc/input.md`). A HUD glyph shows it on.
- Time of day: D-pad down in the tech demo steps the clock through noon, evening, midnight, morning (Drop_Stack's binding, unused in the demo), so the sun can be judged; the clock otherwise runs at the world's day length.

## Change

- `data/shaders/field.fs` and `model.fs` (and the water pass if separate): `sun_direction` set per frame from `sun_direction(day_fraction)` turned into the chunk's frame (the field is drawn in world space, so the planet-space direction is used directly) and weighted by `daylight`; the lighting becomes ambient (sky light times a `sky_ambient` of 0.35 at noon) plus the directional term (max(0, dot(normal, sun)) times daylight) plus block light plus point lights; a spotlight: uniforms `spot_position`, `spot_direction`, `spot_cos_inner`, `spot_cos_outer`, `spot_range`, `spot_color`, set in `draw_field` from the camera when the torchlight is on, zero otherwise, with inverse-square falloff and a smooth cone edge. Every integer literal carries `u`.
- `render_field.odin` `use_field_shader` / `draw_field`: the new uniforms, set each frame beside `daylight`; `Field_View.torchlight` toggled by the new action `Toggle_Torchlight` (D-pad up, world layer, tech demo and dev) and `Step_Time_Of_Day` (D-pad down, tech demo) in `data/bindings.sjson`, served in the field session's frame.
- Keys in `data/game.sjson` presentation: `sky_ambient`, `sun_strength`, `torchlight_strength`, `torchlight_cone_degrees` (28 inner, 36 outer), `torchlight_range_metres` (40).
- Docs: `doc/presentation.md` (Light on the field), `doc/input.md`, the log.

## Verify

- The checks and the suite; `shader_source_test.odin` passes on the changed shaders.
- Tests: the sun direction uniform follows the clock (noon up, midnight down) in a draw list test; the torchlight toggle sets and clears the uniforms; the time step cycles the four times.
- The couch: at noon a slope facing the sun is visibly brighter than its back; at night the torchlight lights the dig; the water sheet and the waves catch the sun (the user).

## Specification (design, 2026-11-05)

Designed against 0291's and 0296's item text, neither specified yet: the tech demo is `Simulation_Content.field.tech_demo` (0291, `Field_Content` in `field_mining.odin`), read on the frame side through `frame_simulation_content(state).field.tech_demo`; nothing here reads 0296.

### The sun's frame (corrects the Change section)

`field.vs` writes `fragment_world_position = matModel * vertexPosition` and `fragment_normal = mat3(matModel) * vertexNormal`: planet-centred world metres. The sky is not drawn in that frame: `draw_field_sky` draws through `field_sky_camera`, which turns the scene by `up_to_sky_rotation(camera.up)` (the viewer's up onto +y), and `draw_sky` puts the sun disc at `sun_direction(sky.fraction)` in that turned frame. So the sun the field must light by is `sun_direction(fraction)` turned back by the inverse of that rotation, per viewport (each viewer's up differs, noon is overhead for every longitude at once, as `doc/presentation.md`, The field session says of `daylight`). Nothing is "used directly".

- `render_day.odin`: `field_sun_world_direction :: proc(fraction: f64, up: [3]f32) -> [3]f32`: `linalg.quaternion128_mul_vector3(linalg.quaternion_inverse(up_to_sky_rotation(up)), sun_direction(fraction))`. Unit. Pure. (`up_to_sky_rotation` stays in `loop_field_session.odin`; `render_day.odin` may call it, both are the render cluster's neighbours in `doc/code_map.md`; if the map's check objects, move `up_to_sky_rotation` to `render_day.odin` and leave a call in place.)
- `FIELD_SUN_DIRECTION` and the `sun_direction` upload in `use_field_shader` are removed; the uniform keeps its name and is set per draw (below).

### The field shader (`data/shaders/field.fs`)

Before (the terrain and the water pass alike, `water` = 1 in the water pass):

```
sun   = max(dot(n, normalize(sun_direction)), 0)        // the constant FIELD_SUN_DIRECTION
light = max(block_light, sky_light * daylight)
lit   = albedo * light * mix(0.45, 1, sun) + albedo * point_light_sum(position, n)
```

After:

```
sun_facing = max(dot(n, sun_direction), 0.0)                              // sun_direction unit, world frame
sun_light  = sky_light * daylight * (sky_ambient + sun_strength * sun_facing)
light      = max(fragment_block_light, sun_light)                          // block light stays the brighter, never added
lit        = albedo * light
lit       += albedo * point_light_sum(position, n)                          // unchanged
lit       += albedo * spot_light(position, n)                               // the torchlight
glint      = water * sky_light * daylight * pow(max(dot(n, normalize(sun_direction + to_camera)), 0.0), water_glint_power) * water_glint_strength
lit       += vec3(glint)                                                    // the sun on the water, white, the sheet and the waves catch it
```

`to_camera = normalize(camera_position - position)` (`camera_position` is already a uniform). `const float water_glint_power = 48.0; const float water_glint_strength = 0.6;` (shader constants, not data: the look items 0294 tune the water). The `ambient_share` constant goes. Sky light gates the direct sun: a cave's samples have sky light 0 and take no sun, the cheap shadow. At noon a slope facing the sun reads `0.35 + 0.94` before the final `min(lit, 1)`, its back `0.35`; at night (`daylight` 0) nothing but block light, the torchlight and the point lights.

New uniforms, all set in `draw_field` each frame (so the water pass takes them too): `uniform vec3 sun_direction;` (kept), `uniform float sky_ambient;`, `uniform float sun_strength;`, `uniform vec3 spot_position;`, `uniform vec3 spot_direction;`, `uniform float spot_cos_inner;`, `uniform float spot_cos_outer;`, `uniform float spot_range;`, `uniform vec3 spot_color;`. `daylight`, `camera_position`, `water_color`, the fog and the point lights stay as they are.

The spot, in `field.fs` and `model.fs` line for line (the point light sum's rule; `point_light_wrap` and `smallest_weight_sum` exist in both):

```
// The torchlight (0297): a cone from spot_position along spot_direction,
// full inside spot_cos_inner, gone past spot_cos_outer, inverse square
// from torchlight_reference_metres, ended smoothly at spot_range; a range
// of 0 is off and costs one compare. Half the facing is wrapped as the
// point lights do.
const float torchlight_reference_metres = 4.0;

vec3 spot_light(vec3 position, vec3 normal)
{
    if (spot_range <= 0.0) {
        return vec3(0.0);
    }
    vec3 offset = position - spot_position;
    float distance_squared = dot(offset, offset);
    vec3 to_fragment = offset * inversesqrt(max(distance_squared, smallest_weight_sum));
    float cone = smoothstep(spot_cos_outer, spot_cos_inner, dot(to_fragment, spot_direction));
    float reach = clamp(1.0 - distance_squared / (spot_range * spot_range), 0.0, 1.0);
    float reference = torchlight_reference_metres * torchlight_reference_metres;
    float falloff = reference / (reference + distance_squared) * reach * reach;
    float facing = mix(point_light_wrap, 1.0, max(dot(normal, -to_fragment), 0.0));
    return spot_color * cone * falloff * facing;
}
```

Cost per fragment: the dot for the cone, the smoothstep, one division; the glint one normalize and one pow, only paid as a multiply by `water` (no branch: the mipmapped samples' rule in the shader's comment). Every integer literal carries `u` (none is added; `0.0` and `1.0` are floats). Android: `shader_source_for_gles` rewrites to `#version 300 es` with `precision highp`; `smoothstep`, `inversesqrt` and `pow` are GLSL ES 3.00; no `uint` is added. Update the header comment of each shader (the sun, the torchlight, the glint; "a gentle sun term shades the slopes" goes).

### The model shader (`data/shaders/model.fs`, `model.vs` unchanged)

Before: `lit = base.rgb + fragment_color.rgb * point_light_sum(position, n)`. After: `lit = base.rgb + fragment_color.rgb * (point_light_sum(position, n) + spot_light(position, n))`. The same six spot uniforms, the same `spot_light` text. No directional sun on models (Decisions). `model.fs`'s header: the torchlight added, "keep the two in step" now names both `point_light_sum` and `spot_light`.

### Data (`data/game.sjson`, `src/data_load.odin`)

A table after `field_simulation`, integers as every key (`salvage_percent`, `soot_percent`):

```
// The sun and the torchlight on the field (0297, doc/presentation.md,
// Light on the field): the sky light's share without the sun and the
// sun's, both in percent; the torchlight's brightness in percent of
// TORCHLIGHT_COLOR, its cone's full and outer half angles in degrees
// (outer above inner) and its reach in metres.
sun_and_torchlight = {
	sky_ambient_percent = 35
	sun_strength_percent = 100
	torchlight_strength_percent = 100
	torchlight_inner_cone_degrees = 28
	torchlight_outer_cone_degrees = 36
	torchlight_range_metres = 40
}
```

- `Sun_And_Torchlight_Config :: struct { sky_ambient_percent, sun_strength_percent, torchlight_strength_percent, torchlight_inner_cone_degrees, torchlight_outer_cone_degrees, torchlight_range_metres: int }`, `Game_Config.sun_and_torchlight` (named so, since `Field_Light_Tuning` is the flood fill's).
- `sun_and_torchlight_problem :: proc(config: Sun_And_Torchlight_Config) -> string`, called from `validate_game_config` after `pod_airlock_problem`: a `Config_Bound` table, `sky_ambient_percent` 0 to 100, `sun_strength_percent` 0 to 400, `torchlight_strength_percent` 0 to 400, `torchlight_inner_cone_degrees` 1 to 89, `torchlight_outer_cone_degrees` 2 to 90, `torchlight_range_metres` 1 to 200 (`MAXIMUM_TORCHLIGHT_RANGE_METRES`); then `outer <= inner` fails with `torchlight_outer_cone_degrees %d is not above torchlight_inner_cone_degrees %d`. A missing table reads as zeros and fails on the inner cone, as the other tables do.
- game.sjson is not hot reloaded (`data_watch.odin`: a restart); nothing to add.

### Renderer (`src/render_field.odin`, `src/render_models.odin`, `src/render_point_lights.odin`)

- `render_point_lights.odin` (pure, tested): `TORCHLIGHT_COLOR :: [3]f32{1.0, 0.93, 0.8}`; `Spot_Light :: struct { position, direction: [3]f32, cos_inner, cos_outer, range: f32, color: [3]f32 }` (range 0 is off, every field zero then); `Field_Frame_Lights :: struct { sun_direction: [3]f32, sky_ambient, sun_strength: f32, spot: Spot_Light }`; `torchlight_spot :: proc(camera: rl.Camera3D, config: Sun_And_Torchlight_Config, on: bool) -> Spot_Light` (off: `{}`; on: position `camera.position`, direction `normalize(camera.target - camera.position)`, cos of the two angles, range as f32, color `TORCHLIGHT_COLOR * strength / 100`); `field_frame_lights :: proc(fraction: f64, camera: rl.Camera3D, torchlight: bool, config: Sun_And_Torchlight_Config) -> Field_Frame_Lights` (sun `field_sun_world_direction(fraction, camera.up)`, the two shares over 100, the spot).
- `Field_Renderer` gains `sun_direction_location, sky_ambient_location, sun_strength_location: i32` and `spot_locations: [6]i32` (position, direction, cos_inner, cos_outer, range, color), looked up in `use_field_shader` where `daylight_location` is. `set_field_frame_lights :: proc(renderer: ^Field_Renderer, lights: Field_Frame_Lights)` uploads the nine values (`rl.SetShaderValue`, `.VEC3` and `.FLOAT`). `draw_field :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, selection: []Field_Node, lights: Field_Frame_Lights)` calls it beside the `daylight` upload, before the terrain, so the water pass shares them.
- `Model_Renderer` gains `spot_locations: [6]i32`, looked up in `use_model_shader` beside the point light locations, and `set_model_spot_light :: proc(renderer: Model_Renderer, spot: Spot_Light)` (nothing unless `point_lights_ready`).

### The field session (`src/loop_field_session.odin`, `src/loop_planet_preview.odin`, `src/viewport.odin`)

- `Field_Scene.lights: Field_Frame_Lights`, filled by the callers. `draw_field_scene` passes `scene.lights` to `draw_field` and calls `set_model_spot_light(scene.models, scene.lights.spot)` next to `set_field_scene_point_lights`.
- `draw_field_viewport_world`: `lights = field_frame_lights(sky.fraction, camera, viewport.presentation.torchlight, state.config.sun_and_torchlight)` with the camera it draws with (after `arrival_viewport_camera`; `sky` is the parameter it already has).
- `planet_preview_scene` (`loop_planet_preview.odin`): `field_frame_lights(NOON_FRACTION, camera, false, config.sun_and_torchlight)`: the preview's sun stands at noon over the camera, `--planet-preview-daylight` scales it as before through `renderer.daylight`.
- `Viewport_Presentation.torchlight: bool` (render state, reset with the session like the rest).
- `prepare_field_frame` is unchanged.

### Actions and bindings (`src/input_actions.odin`, `data/bindings.sjson`, `src/loop.odin`, `src/hud.odin`, `src/ui_input.odin`)

- `Action` gains, after `Reload_Data` and before the nudges: `// The torchlight (0297): D-pad up in the tech demo and in developer mode, where it rides on Pipette's control.` `Toggle_Torchlight,` `// Steps the clock noon, dusk, midnight, dawn (0297): D-pad down in the tech demo, on Drop_Stack's control.` `Step_Time_Of_Day,`. Both in `WORLD_ACTIONS` (a screen blocks them).
- `data/bindings.sjson`, after the `Drop_Stack` gamepad line, with a comment: `// The tech demo's D-pad (0297): the torchlight on Pipette's up, the clock on Drop_Stack's down; outside the demo the torchlight needs developer mode and the clock does nothing.` then `{action = "Toggle_Torchlight" device = "gamepad" control = "DPAD_UP" context = "world"}` and `{action = "Step_Time_Of_Day" device = "gamepad" control = "DPAD_DOWN" context = "world"}`. No keyboard line (the Controls section names none).
- `input_actions.odin`: `tech_demo_world_frame :: proc(frame: Input_Frame, tech_demo: bool) -> Input_Frame`: with `tech_demo` false the frame unchanged; true, `without_actions(frame, {.Pipette, .Drop_Stack})`, since in the demo the D-pad's world meanings are the torchlight and the clock (the Controls section) and the kit must not be dropped. `viewport_world_input` (`loop.odin`) applies it after `tools_radial_world_frame` and before the placement editor's frame, with `frame_simulation_content(state).field.tech_demo`.
- `loop.odin`: `apply_field_light_actions :: proc(state: ^Frame_State, viewport: ^Viewport, world: Input_Frame)`, called in `update_session` right after `worlds[index] = viewport_world_input(state, viewport)` with that frame (so an open screen, the tools radial and the editor have had their say): `tech_demo := frame_simulation_content(state).field.tech_demo`; if `.Toggle_Torchlight in world.just_pressed && (tech_demo || developer_mode_on(state))` flip `viewport.presentation.torchlight`; if `.Step_Time_Of_Day in world.just_pressed && tech_demo && viewport_player_ready(session, viewport^)`, `queue_player_command(&session.simulation.player_commands, viewport.player, Developer_Request{action = .Set_Time_Of_Day, time_of_day = next_time_of_day(simulation_day_ticks(session.simulation), session.simulation.day_length_ticks)})`, the path `Debug_Remove_Block` takes (`apply_debug_actions`): through the lockstep records into `apply_developer_command`, so the existing `Set_Time_Of_Day` case (`day_offset_for(tick, time_of_day_day_ticks(...))`) serves it on every machine alike. The frame side only chooses the target.
- `developer.odin`, beside `time_of_day_day_ticks`: `next_time_of_day :: proc(day_ticks, day_length_ticks: u64) -> Time_Of_Day`: `start_ticks := u64(math.round(DAY_START_FRACTION * f64(day_length_ticks)))`, `since_sunrise := (day_ticks % day_length_ticks + start_ticks) % day_length_ticks`, `quarter := since_sunrise * 4 / day_length_ticks`, return `Time_Of_Day((quarter + 1) % 4)`; `.Noon` with a day length of 0. Integers only, one rounded constant as `time_of_day_day_ticks` already has. From the demo's start (fraction 0.05) the presses give Noon, Dusk, Midnight, Dawn, Noon: the Controls section's order (evening is `Dusk`, morning `Dawn`).
- The tools radial in the tech demo: `tools_radial :: proc(state: ^Ui_State, editor: ^Placement_Editor, shown: bool)`, `touching` also needs `shown`; `draw_hud` passes `!screen_context.content.field.tech_demo` (the pipette and the placement editor are the inventory game's). Outside the demo nothing changes: under `--dev` a D-pad up press toggles the torchlight on its edge and the hold still shows the radial, the tap still pipettes (Decisions).

### HUD (`src/hud.odin`, `src/ui_widgets.odin`, `src/loop.odin`, `data/strings/en.sjson`)

- `Glyph_Button.Torchlight` (`// The torchlight's toggle (0297): D-pad up.`), `glyph_button_actions[.Torchlight] = .Toggle_Torchlight`.
- `Hud_Context.torchlight: bool`, set in `make_hud_context` from `viewport.presentation.torchlight`.
- `world_glyph_hints`: after the Sprint hint, `if hud.torchlight { append(&list, Glyph_Hint{.Torchlight, text("hint_torchlight_on")}) }`, outside `kept` (it may move above the hotbar with Sprint and Pause). `hint_torchlight_on = "Torch on"` under the field hints in `en.sjson`. The glyph shows D-pad up on the gamepad; on the keyboard nothing is bound, so `glyph` draws the action's fallback as for an unbound action today.

### Tests

- `render_day_test.odin` `test_the_field_sun_turns_with_the_viewers_up`: `field_sun_world_direction(f, {0, 1, 0})` equals `sun_direction(f)` for f in 0, 0.25, 0.5, 0.75 (`expect_near_point`); with up `{1, 0, 0}` at noon the dot with the up is `cos(tilt)` within `MOTION_TEST_TOLERANCE` and the vector is `{cos tilt, 0, sin tilt}`; at midnight the dot is `-cos(tilt)`; every result has length 1.
- `render_point_lights_test.odin` `test_the_torchlight_spot_follows_the_camera`: camera at `{10, 20, 30}` targeting `{14, 20, 30}`, shipped config, on: position `{10, 20, 30}`, direction `{1, 0, 0}`, `cos_inner` and `cos_outer` the cosines of 28 and 36 degrees within 1e-5, range 40, color `TORCHLIGHT_COLOR`; off: `Spot_Light{}`; strength 50 halves the colour. `test_field_frame_lights_follow_the_clock`: up `{0, 1, 0}`, fraction 0.25 gives `sun_direction.y > 0.9`, 0.75 gives `y < -0.9`, `sky_ambient` 0.35 and `sun_strength` 1 from the shipped values.
- `developer_test.odin` `test_the_time_step_cycles_noon_dusk_midnight_dawn`: day length `1200 * TEST_TICK_RATE`; `next_time_of_day(0, length)` is `.Noon`; then for each of `.Noon, .Dusk, .Midnight, .Dawn` the day ticks `time_of_day_day_ticks(it, length)` (and that plus 1) give the next in that order, `.Dawn` giving `.Noon`; length 0 gives `.Noon`.
- `shader_source_test.odin` `test_the_lit_shaders_share_the_spot_light`: a `shader_spot_light` extractor (from `vec3 spot_light(` to `\n}\n`, as `shader_point_light_sum`); both `field.fs` and `model.fs` declare the six `spot_` uniforms (exact declaration lines) and their `spot_light` texts are equal and non-empty. `test_the_field_shader_lights_by_the_sun`: `field.fs` declares `uniform vec3 sun_direction;`, `uniform float sky_ambient;`, `uniform float sun_strength;` and holds no `ambient_share`; `model.fs` holds no `sun_direction`.
- `data_load_test.odin` `test_sun_and_torchlight_is_range_checked`: the shipped table passes; outer 28 with inner 28 fails naming `torchlight_outer_cone_degrees`; range 0 fails; `sky_ambient_percent` 101 fails.
- `input_actions_test.odin` `test_the_tech_demo_takes_the_d_pads_world_meanings`: a frame with `Pipette`, `Drop_Stack`, `Toggle_Torchlight`, `Step_Time_Of_Day`, `Jump` pressed and just pressed; `tech_demo_world_frame(frame, true)` keeps the last three and drops the first two in both sets; `tech_demo_world_frame(frame, false)` is the frame.
- `bindings_test.odin` `test_the_shipped_bindings_put_the_torchlight_and_the_clock_on_the_d_pad`: the default bindings hold a gamepad `DPAD_UP` world line for `Toggle_Torchlight` and a `DPAD_DOWN` world line for `Step_Time_Of_Day`, and `Pipette` and `Drop_Stack` keep theirs.
- `hud_test.odin` `test_the_torchlight_hint_shows_while_it_is_on`: `world_glyph_hints` with `hud.torchlight` true holds a `.Torchlight` hint after the Sprint position and before Pause, false holds none; `kept` unchanged by it.
- `data_strings_test` `test_shipped_strings_cover_the_ui` covers the new key through `text(...)` as it does every key; nothing to add unless it lists keys.
- No test uploads a uniform: raylib's `SetShaderValue` has no capture under `odin test` (the repository's pattern is the pure packing procedure tested and a thin upload, `point_light_uniform_values`), so the item's "draw list test" is the pure tests above; the draw list is the UI's.

### Docs

- `doc/presentation.md`: a new `### Light on the field` under The field session, after the scene bullet: the equation above in words (sky light times daylight times ambient plus sun, gated by the sky light; block light the brighter; the point lights and the torchlight added; the glint on the water), the sun's frame (`field_sun_world_direction`, the sky camera's inverse, per viewport), the torchlight (the cone, the reference distance, the range, `TORCHLIGHT_COLOR`, `torchlight_spot`, set per draw in `draw_field` and on the models' lit layer), the keys by name with the shipped values, and that the planet preview's sun stands at noon. The Shaders bullet on `field.fs`'s "gentle sun term" and the Machine models bullet on the model shader (the torchlight added, no sun) updated.
- `doc/input.md`: the Gamepad table's D-pad row gains "In the water tech demo (0291) up toggles the torchlight and down steps the clock noon, evening, midnight, morning; under `--dev` outside it up toggles the torchlight beside Pipette." A bullet under Bindings for `tech_demo_world_frame` and `apply_field_light_actions`, and the glyph `Torch on`.
- `doc/content.md`, World: a bullet for `sun_and_torchlight` with each key, its bounds and shipped value, pointing at presentation.md, Light on the field.
- `doc/code_map.md`: `render_point_lights.odin`'s line names the torchlight's `Spot_Light`; `render_day.odin`'s `field_sun_world_direction`; the loop's `apply_field_light_actions`.
- The log entry is the main agent's at landing.

### Hand-back check

- "A number parsed from text is range checked": the six keys through `sun_and_torchlight_problem`, the cones ordered.
- "A UI audit case a change makes obsolete is replaced": none made obsolete; the glyph bar's audit sizes still fit one more hint (it moves above the hotbar as Sprint does).
- Determinism: the clock step enters the simulation only as a `Developer_Request` through the lockstep records; the torchlight never reaches the simulation. No float enters simulation state.
- Shaders: no bare integer literal added; `shader_source_test` passes; `./build.sh check-android` (the same `.fs` files ship).
- The other lines (memory a frame draws from, files, start-up loads, save layouts, shared budgets, unbounded lists, test directories) do not apply: nothing is saved, no list grows, no file is written.

### Decisions on the open questions

- `FIELD_SUN_DIRECTION` becomes nothing: the constant and its one-time upload go; `sun_direction` is set per `draw_field` from the clock and the viewer's up. Its `mix(0.45, 1, sun)` factor becomes `sky_ambient + sun_strength * sun_facing` inside the sky light's term, so the sun no longer darkens block-lit caves (before, a torch-lit wall facing away from the constant sun lost 55 percent of its block light).
- The model shader's machines take the torchlight: yes, the same `spot_light`, since a dug-out machine at night must show in the beam. They take no directional sun: their faces are pre-shaded per face on the CPU (`model_mesh.odin`, `MODEL_SHADE_BASE`) and tinted by `model_light_tint` from the day factor, so a second directional term would double-shade them; moving the face shade into the shader to follow the sun is a follow-up item.
- The water pass has no shader of its own on the field (`water.fs` is the block world's; the field's water is `field.fs` with `water_color.a` above 0), so the sun and the torchlight reach it through the same uniforms, plus the glint; the glint's power and strength are shader constants for 0294 to revisit.
- Cost: per fragment one dot, one smoothstep and a division for the cone, one normalize and a pow for the glint (the terrain pays it multiplied by 0); the off state costs one compare.
- The torchlight's falloff: inverse square from a 4 m reference (half at 4 m, a seventh at 10 m, a hundredth at 40 m) ended by the range, so a 40 m beam lights a dig without blowing out the hand's reach.
- Under `--dev` outside the demo a D-pad up press is both the torchlight's edge and Pipette's control (held: the tools radial, tapped: Pipette); the Controls section accepts that, and in the demo the radial and Pipette are off. Not decided here, for the main agent: whether the torchlight should instead be demo-only, which would drop `developer_mode_on` from the gate and the overlap.
- `Field_View.torchlight` of the Change section is not used: `Field_View` (`world_field_lod.odin`) is the node selection's value made once a frame; the toggle lives in `Viewport_Presentation`, per viewer, as the item's per-camera uniform wants.

### Main agent's decisions (approval, 2026-11-05)

- The torchlight stays available under `--dev` beside Pipette, as designed; demo-only would lose it for development.
- Models take the torchlight and no directional sun, as designed; the face shade following the sun is a later item.
- The stream: 0297 follows 0296 (both touch `viewport_world_input`, the actions and the bindings) and reads 0291's `Field_Content.tech_demo`; its worktree is made from 0296's snapshot, which carries the flag's stub.
- Approved.
