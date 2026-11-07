# 0328: Sun shadows

Status: verified (2026-11-07)

0313 lights the landscape by the sun, the sky and the ground's bounce without shadows; its design left the sun's shadow of the terrain and the trees to an item of its own, after 0310's forests. Its estimate (from published hardware figures, not measured): one 2048 square cascade over 256 m adds about 300 draw calls a viewport (50 terrain chunks, 256 trees), 0.3 to 0.5 ms of GPU and 1 to 2 ms of CPU on the couch, 2 to 3.5 ms on the Steam Deck at a 1024 square map, 4 to 8 ms on the phone.

## Goal

The terrain, the trees, the landmarks and the buildings cast the sun's shadow near the player on the couch and the Deck, behind a setting; none on the phone.

## Controls

A setting on the options panel (on, off), its default per platform from data. No binding.

## Change

- A shadow cascade from the sun over the near field, the terrain's nodes and the instanced trees drawn into it with the fewest draw calls, read by the field, model and tree shaders with 0313's light.
- The setting, its default per platform, and the frame cost measured on the couch with a forest in view and estimated for the Deck.
- The shader rules of CLAUDE.md, checked through Mesa.
- Docs: `doc/presentation.md` (Light on the field).

## Verify

- The checks, the suite, `shader_source_test.odin`.
- Captures at morning and noon from the ground, under trees and beside a landmark, with and without; the frame cost on the couch and the Deck's setting; sent to the user.

## Specification (design, 2026-11-07)

Designed against 0310's worktree and 0311's specification (neither on `main` yet); the implementation starts on 0311's tip. The shader text below compiled and linked through Mesa (desktop GLSL 3.30 and `--es`) for `field`, `model`, `tree`, 0311's `cover` and the new `sun_shadow` pairs, and passes the literal and reserved word rules.

### Decisions

1. **One cascade round the eye**, not fitted to the frustum: with a 70 degree view the frustum slice's bounding sphere is 1.5 times its depth, wider than a sphere round the eye, and turning the camera then redraws nothing. The receivers are the sphere of `radius_metres` round the camera, the shadow fading out over its last quarter (`SUN_SHADOW_FADE_SHARE`), so no edge shows. The map's half size is the radius plus `SUN_SHADOW_MARGIN_TEXELS` (4) texels, so the normal offset and the taps stay inside it.
2. **Snapping**: the light's axes are the sun and the sun path's axis turned to the world as the sun is (`field_sun_path_world_axis`; the sun is always square to it, so the basis never degenerates and turns only as the sun or the viewer's up turns). The centre is the eye moved in the light's plane to the nearest whole texel along both axes (in `f64`); along the sun it is not snapped. A walk inside one texel draws the same map.
3. **Depth range and far casters**: the ortho box runs from the sun side of the sphere (near plane at the centre plus half a box towards the sun) to its far side, so 24 bits (16 on a GLES fallback) cover only the receivers. Casters up to `caster_reach_metres` beyond the near plane towards the sun are drawn and pressed onto that plane in `sun_shadow.vs` (`gl_Position.z = max(gl_Position.z, -gl_Position.w)`), so a ridge or a tree towards a low sun still shadows the sphere.
4. **Casters**, one depth only pass a viewport, culling off (models may be open shells): the frame's selected terrain nodes whose box meets the casters' box (`sun_shadow_box_casts`), the trees instanced (one `DrawMeshInstanced` a tree machine, the standing trees of the cached tiles in the casters' box, nearest the eye first up to `tree_limit`, whatever their distance band, so a tree drawn as a card still casts its model), the foundations (`draw_frames`), the machines (`draw_entities`) and every player's body including the viewer's in first person (`draw_field_players` with `viewer_body_shown` true), under the pod's transform as the scene draws them. Not drawn: the cards, the water (it does not cast), 0311's cover (receives only: thousands of blades a node for shadows a few centimetres long), the runs and poles, the torches, the flames, the ghosts, the debris, the arrival's wake and flakes, the globe.
5. **Bias and filter**: the receiver moves 2 texels along its shading normal and 0.5 texel towards the sun in depth; the 4 by 4 texels round it are compared and weighted as the mean of the 3 by 3 bilinear lookups (per axis 1 less the fraction, 1, 1, the fraction, over 9), an edge three texels soft. A 2D probe of this kernel (`tmp/0328/bias_probe.py`, `bias_margin.py`): every receiver on a lit plane read at least 0.98 lit at any slope up to 88 degrees from the sun, with the shading normal 15 degrees off the face's either way, and a plate's shadow edge moved at most two texels in the light's plane (towards the lit side, never a gap at the contact). With 1 texel of offset the slopes from 60 degrees read 0.67 to 0.81, the acne of 0072's "steep angle onto the side of trees".
6. **Light**: the shadow scales the sun's term of `outdoor_light` only (a new third parameter `sunlit`), never the sky's or the bounce: the sun stays partly ambient as the user asked in 0097. A full shadow takes `strength_percent` (70) of the sun: flat ground at noon keeps about half its light (0.51, 0.54, 0.58 of it per channel, blue leaning) instead of about a third at 100. The water's glint is scaled by it too. A face turned from the sun reads nothing (its sun term is 0).
7. **Comparisons in the shader** through a `highp sampler2D` on the depth texture as `rlLoadTextureDepth` makes it (nearest, clamped, no compare mode): rlgl offers no `GL_TEXTURE_COMPARE_MODE`, and a plain sampler avoids `sampler2DShadow`, a new driver path for Gladio and the phone. `highp` because GLSL ES gives a sampler lowp by default. 16 reads where a hardware compare would take 9.
8. **Setting**: `settings.sun_shadows`, `default`, `on` or `off`; `default` takes the build target's row (`on` true on desktop, so the Deck too, false on Android). The Display tab's toggle shows the effective value and writes `on` or `off`. No Deck row: the Deck's estimate (below) fits its 25 ms frame and it reads `SteamDeck` only at start; the main agent's Deck measurement decides otherwise.
9. **Off**: no pass, no framebuffer and no texture (freed between frames when the setting turns off); every receiving shader pays one compare. Also no pass while the sun's light is zero (night).
10. **Split screen**: one map, drawn again before each viewport's 3D pass and read by it before the next viewport overwrites it (the GL command order guarantees it). The cost doubles with two viewports.
11. **Where the pass runs**: inside `draw_field_viewport_world`, after the camera and the lights and before `rl.BeginMode3D`; `rl.BeginTextureMode` on the map unbinds the split screen viewport's target, so the viewport's target is bound again after (`resume_viewport_target`). The planet preview runs it before `rl.BeginDrawing` with its row's default, so its screenshots show the shadows.

### Data (`data/game.sjson`, after `field_trees`)

```
// The sun's shadow (work item 0328, doc/presentation.md, Light on the
// field): strength_percent (0 to 100) of the sun's light a full shadow
// takes away; a row for the desktop builds (the Steam Deck's too) and one
// for Android: on, the default of settings.sun_shadows; map_texels (512,
// 1024, 2048 or 4096) a side of the depth map; radius_metres (16 to 256)
// round the eye that receives the shadow, fading out over its last
// quarter; caster_reach_metres (0 to field_view's last distance) beyond
// it towards the sun that still casts; tree_limit (0 to 16384, 0 for
// none) of the trees that cast, nearest the eye first.
sun_shadows = {
	strength_percent = 70
	desktop = {on = true, map_texels = 2048, radius_metres = 64, caster_reach_metres = 96, tree_limit = 2048}
	android = {on = false, map_texels = 1024, radius_metres = 48, caster_reach_metres = 64, tree_limit = 512}
}
```

The radius is the first level of detail's 64 m: the near ground is level 0 and the texel is 6.3 cm (9.4 cm on the phone's row). `tree_limit` 2048 covers about 52 m round the eye in 0310's densest forest (2400 a hectare).

### Files and procedures

`src/data_load.odin` (content):
- `Sun_Shadows_Row :: struct {on: bool, map_texels, radius_metres, caster_reach_metres, tree_limit: int}`, `Sun_Shadows_Config :: struct {strength_percent: int, desktop, android: Sun_Shadows_Row}`, `Game_Config.sun_shadows: Sun_Shadows_Config` after `field_trees`.
- `sun_shadows_row :: proc(config: Sun_Shadows_Config) -> Sun_Shadows_Row`: the build target's row, as `field_trees_row`.
- `sun_shadows_problem :: proc(shadows: Sun_Shadows_Config, field_view: Field_View_Config) -> string`: `strength_percent` 0 to 100, then per row (`sun_shadows.<row>.<key> %d is outside %d to %d`) `map_texels` 512 to 4096 and a power of two (else `... %d is not a power of two from 512 to 4096`), `radius_metres` 16 to 256, `caster_reach_metres` 0 to the last level distance, `tree_limit` 0 to 16384; a missing block reads zeros and fails `map_texels`. Called in `validate_game_config` after `field_trees_problem`.

`src/settings.odin` (content):
- `Sun_Shadows_Mode :: enum u8 {Default, On, Off}`, `Settings.sun_shadows` after `weather` (comment: the build's data row decides `Default`), `DEFAULT_SETTINGS.sun_shadows = .Default`. A settings file without the key reads `.Default`; the strict enum refuses any other word.
- `sun_shadows_enabled :: proc(mode: Sun_Shadows_Mode, platform_default: bool) -> bool`.

`src/render_day.odin`: `field_sun_path_world_axis :: proc(up: [3]f32) -> [3]f32`: `sun_path_axis()` turned by the inverse of `up_to_sky_rotation(up)`, as `field_sun_world_direction` turns the sun.

`src/render_sun_shadows.odin` (new, presentation; header comment from Decisions 1 to 7):
- Constants: `SUN_SHADOW_VERTEX_SHADER_PATH :: "shaders/sun_shadow.vs"`, `SUN_SHADOW_FRAGMENT_SHADER_PATH :: "shaders/sun_shadow.fs"`, `SUN_SHADOW_MARGIN_TEXELS :: 4`, `SUN_SHADOW_FADE_SHARE :: 0.25`, `SUN_SHADOW_NORMAL_OFFSET_TEXELS :: 2.0` and `SUN_SHADOW_DEPTH_BIAS_TEXELS :: 0.5` (the shaders' constants, compared by a test), `SUN_SHADOW_MAP_SLOT :: rl.MaterialMapIndex.NORMAL` (texture unit 2).
- `Sun_Shadow_State :: enum u8 {Unloaded, Ready, Failed}`; `Sun_Shadow_Renderer :: struct {state, framebuffer: u32, depth_texture: u32, texels: int, material: rl.Material, instanced_location: i32}` (the size it holds or failed at).
- `Sun_Shadow_Cascade :: struct {view, projection, view_projection: matrix[4, 4]f32, centre, right, up, toward_sun: [3]f32, half_size, texel_metres, radius_metres, reach_metres: f32}`.
- `Sun_Shadow_Frame :: struct {view_projection: matrix[4, 4]f32, strength: f32, shape: [4]f32, texture: u32}`: what the shaders read; zero is off.
- `Sun_Shadow_Inputs :: struct {on: bool, row: Sun_Shadows_Row, strength_percent: int, data_directory: string}`; `sun_shadow_inputs :: proc(settings: Settings, config: Sun_Shadows_Config, data_directory: string) -> Sun_Shadow_Inputs`.
- `Sun_Shadow_Uniform :: enum {Matrix, Strength, Shape}` and `SUN_SHADOW_UNIFORM_NAMES` (`sun_shadow_matrix`, `sun_shadow_strength`, `sun_shadow_shape`).
- `sun_shadow_cascade :: proc(eye, toward_sun, path_axis: [3]f32, row: Sun_Shadows_Row) -> Sun_Shadow_Cascade`: pure. `texel_metres = 2 * radius / (texels - 2 * SUN_SHADOW_MARGIN_TEXELS)`, `half_size = texels * texel_metres / 2`; `right = normalize(cross(-toward_sun, path_axis))`, `up = cross(right, -toward_sun)` (the axes `linalg.matrix4_look_at_f32` derives); centre `= right * round(dot(eye, right) / texel) * texel + up * round(dot(eye, up) / texel) * texel + toward_sun * dot(eye, toward_sun)`, all in `f64`, then `f32`; `view = matrix4_look_at_f32(centre + toward_sun * half_size, centre, up)`, `projection = matrix_ortho3d_f32(-half, half, -half, half, 0, 2 * half)`, `view_projection = projection * view`.
- `sun_shadow_box_casts :: proc(cascade: Sun_Shadow_Cascade, minimum, maximum: [3]f32) -> bool`: pure; the box's middle less the centre and its half extents projected on each axis (`|a.x| e.x + |a.y| e.y + |a.z| e.z`): within `half_size` across `right` and `up`, and along `toward_sun` overlapping `-half_size` to `half_size + reach_metres`.
- `sun_shadow_frame :: proc(cascade: Sun_Shadow_Cascade, strength_percent, texels: int, texture: u32) -> Sun_Shadow_Frame`: shape `{texels, texel_metres, radius * (1 - SUN_SHADOW_FADE_SHARE), radius}`, strength `/ 100`.
- `select_shadow_trees :: proc(cache: ^Field_Tree_Cache, cascade: Sun_Shadow_Cascade, eye: [3]f32, extent_metres: f32, felled: map[Tree_Key]struct{}, limit: int) -> []Near_Tree`: temp allocator; tiles whose bases' box widened by the extent casts, then each instance whose base plus or minus the extent casts and whose key is not felled, with its squared distance to the eye; past `limit` sorted nearest first and cut (as `select_near_trees`); none at limit 0.
- `sun_shadow_receivers :: proc(field: ^Field_Renderer, models: Model_Renderer) -> [3]rl.Material`: the field's, the lit model layer's and the tree shader's materials (a material whose `maps` is nil, the trees' without their shader, is skipped by the slot setter).
- `set_sun_shadow_map_slot :: proc(materials: []rl.Material, texture: rl.Texture2D)`: writes `maps[SUN_SHADOW_MAP_SLOT].texture` of each material with maps (`{}` clears).
- `load_sun_shadow_map :: proc(shadows: ^Sun_Shadow_Renderer, data_directory: string, texels: int, receivers: []rl.Material) -> bool`: called from the pass when `Unloaded`; `load_shader_pair` of the two files into `rl.LoadMaterialDefault()`, `instanced_location`; `rlgl.LoadFramebuffer`, `rlgl.LoadTextureDepth(texels, texels, false)`, `rlgl.FramebufferAttach(... .DEPTH, .TEXTURE2D, 0)`, `rlgl.FramebufferComplete`; on any failure one line `error: the sun's shadow map did not load (<what>), the field draws without shadows`, everything made so far freed, `state = .Failed`, `texels` kept; on success `Ready` and the depth texture (`rl.Texture2D{id, texels, texels, 1, .UNCOMPRESSED_GRAYSCALE}`, the format unread) into the receivers' slot.
- `release_sun_shadow_map :: proc(shadows: ^Sun_Shadow_Renderer, receivers: []rl.Material)`: the receivers' slot cleared first, then `rlgl.UnloadFramebuffer` (raylib 6.0 deletes the attached depth texture with it; no separate `UnloadTexture`), `rl.UnloadMaterial` of the depth material; `shadows^ = {}`. Nothing to free when `Unloaded` or `Failed` (the failure freed what it made); a `Failed` one only returns to `Unloaded`.
- `sun_shadow_map_stale :: proc(shadows: Sun_Shadow_Renderer, on: bool, texels: int) -> bool`: pure; true when not `Unloaded` and (`!on` or `shadows.texels != texels`). A `Failed` map is not retried while the setting stays on at the same size.
- `serve_sun_shadows :: proc(shadows: ^Sun_Shadow_Renderer, receivers: []rl.Material, on: bool, texels: int)`: between frames; releases when stale.
- `use_sun_shadow_sampler :: proc(shader: rl.Shader) -> [Sun_Shadow_Uniform]i32`: sets `shader.locs[MAP_NORMAL]` to the location of `sun_shadow_map`, so `DrawMesh` and `DrawMeshInstanced` bind the slot's texture to unit 2, and returns the three locations.
- `set_sun_shadow_uniforms :: proc(shader: rl.Shader, locations: [Sun_Shadow_Uniform]i32, frame: Sun_Shadow_Frame)`.
- `bind_sun_shadow_texture :: proc(shader: rl.Shader, texture: u32)` and `unbind_sun_shadow_texture :: proc(texture: u32)`: for the draws that enable their shader by hand (the cards, 0311's cover): nothing at texture 0; else the sampler set to unit 2, `rlgl.ActiveTextureSlot(2)`, `EnableTexture`, back to slot 0; the unbind disables it on unit 2.
- `begin_sun_shadow_map :: proc(shadows: Sun_Shadow_Renderer, cascade: Sun_Shadow_Cascade)` and `end_sun_shadow_map :: proc()`: `rl.BeginTextureMode` on `rl.RenderTexture2D{id = framebuffer, texture = {width, height = texels}, depth = {id = depth_texture}}`, `rlgl.ClearScreenBuffers`, `rlgl.SetMatrixProjection` and `SetMatrixModelview` with the cascade's (`rl.Matrix(...)`), depth test and mask on, back face culling off; the end flushes the batch, culling back on, depth test off, `rl.EndTextureMode`.

`src/render_point_lights.odin`: `Field_Frame_Lights.sun_shadow: Sun_Shadow_Frame` (zero from `field_frame_lights`; the pass fills it).

`src/render_field.odin`:
- `field_node_box_metres :: proc(render: Field_Node_Render, node: Field_Node, spacing_millimetres: int) -> (minimum, maximum: [3]f32)`: the box and margin `field_node_in_frustum` uses today, which now calls it.
- `Field_Renderer.sun_shadows: Sun_Shadow_Renderer`, `.sun_shadow_locations`; `use_field_shader` calls `use_sun_shadow_sampler`; `init_field_renderer` refuses a fragment shader without `sun_shadow_strength` as it refuses one without the haze (`FIELD_SUN_SHADOW_UNIFORM`, "a copy older than the sun's shadow"), so an old overlay copy falls back to the shipped file.
- `set_field_frame_lights` also sets the shadow uniforms on the field shader and on 0311's cover shader; `draw_field` passes `lights.sun_shadow.texture` to `draw_field_cover`, which binds it after enabling its shader and unbinds it after its loop.
- `destroy_field_renderer :: proc(renderer: ^Field_Renderer, models: Model_Renderer)`: releases the map with `sun_shadow_receivers(renderer, models)` before `UnloadMaterial` (which would delete a texture still in a slot). Callers: `stop_field_presentation` (`presentation.model_renderer`), the preview's teardown (`preview.models`, before `destroy_model_renderer`), tests (`{}`).

`src/render_models.odin`: `Model_Renderer.sun_shadow_locations`; `use_model_shader` calls `use_sun_shadow_sampler`; `set_model_open_sky` sets the shadow uniforms from `lights.sun_shadow` on the model shader and, when ready, the tree shader.

`src/render_field_trees.odin`: `Tree_Draw.sun_shadow_locations` (from `use_tree_shader`); `draw_tree_instances :: proc(models: Model_Renderer, species_list: []Field_Tree_Species, trees: []Near_Tree, material: rl.Material)`, the per machine grouping and `DrawMeshInstanced` taken out of `draw_near_trees`, which keeps its uniforms and colour and calls it; `draw_far_tree_cards` takes `shadow_texture: u32` (`scene.lights.sun_shadow.texture` from `draw_field_trees`) and binds it after `rlgl.EnableShader`, unbinding before `DisableShader`.

`src/render_field_cover.odin` (0311): `Field_Cover_Renderer` gets `sun_shadow_locations` from `use_sun_shadow_sampler` at load; `draw_field_cover` takes `shadow_texture: u32` as above.

`src/loop_field_session.odin` (loop):
- `draw_field_sun_shadows :: proc(scene: Field_Scene, camera: rl.Camera3D, selection: []Field_Node, inputs: Sun_Shadow_Inputs) -> Sun_Shadow_Frame`: `{}` when `!inputs.on` or the sun's colour is zero; loads the map when `Unloaded` (`load_sun_shadow_map` with `sun_shadow_receivers(scene.renderer, scene.models)`), `{}` unless `Ready`; the cascade from `camera.position`, `scene.lights.sun_direction`, `field_sun_path_world_axis(camera.up)` and the row; `begin_sun_shadow_map`; the terrain (each selected node with a mesh whose `field_node_box_metres` casts, `DrawMesh` with the depth material and the node's translation); the trees when `tree_limit > 0` and the tree shader is ready (`select_shadow_trees` with `field_tree_model_extent(scene)` and the felled table, `instanced_on` 1, `draw_tree_instances` with the depth material, `instanced_on` 0); a copy of the scene whose `models.material` and `models.emissive_material` are the depth material and whose `viewer_body_shown` is true, and under `push_pod_transform`: `draw_frames`, `draw_entities`, `draw_field_players`; `pop_pod_transform`; `end_sun_shadow_map`; returns `sun_shadow_frame(cascade, inputs.strength_percent, row.map_texels, depth_texture)`.
- `resume_viewport_target :: proc(viewport: ^Viewport)`: `rl.BeginTextureMode(viewport.presentation.target)` when its id is not 0 (split screen); a single viewport is back on the window after `EndTextureMode`. Called unconditionally after the pass (a failed load also unbinds the framebuffer).
- `draw_field_viewport_world`: after `scene` is built, `scene.lights.sun_shadow = draw_field_sun_shadows(scene, camera, frame_field_selection(state), sun_shadow_inputs(state.settings, state.config.sun_shadows, state.data_directory))`, `resume_viewport_target(viewport)`, then `rl.BeginMode3D`.
- `prepare_field_frame`: `serve_sun_shadows` with the receivers, `sun_shadows_enabled(state.settings.sun_shadows, row.on)` and `row.map_texels`, before the uploads.
- `stop_field_presentation`: `destroy_field_renderer(&presentation.field_renderer, presentation.model_renderer)`.

`src/loop_planet_preview.odin`: `Planet_Preview.sun_shadows: Sun_Shadow_Inputs` set beside `field_trees` (`on` the row's default, the run's data directory); `draw_planet_preview` builds the scene before `rl.BeginDrawing`, runs the pass and sets `scene.lights.sun_shadow`, then draws as today.

`src/ui_screens.odin`: `Screen_Context.sun_shadows_default: bool` (`make_screen_context` in `loop.odin`: `sun_shadows_row(state.config.sun_shadows).on`); `display_settings` takes it and after the weather toggle: `shadows := sun_shadows_enabled(settings.sun_shadows, sun_shadows_default)`, `if ui_toggle(state, cut_row(content), text("settings_sun_shadows"), &shadows, text("settings_sun_shadows_tooltip")) { settings.sun_shadows = shadows ? .On : .Off }`; `DISPLAY_SETTINGS_ROW_COUNT` 19. Saved by `write_changed_settings` as every row.

`data/strings/en.sjson` after the weather's: `settings_sun_shadows = "Sun shadows"`, `settings_sun_shadows_tooltip = "The terrain, the trees, the buildings and the players cast the sun's shadow round you. Off saves frame time"`.

### Shaders

`data/shaders/sun_shadow.vs` (new): `in vec3 vertexPosition; in mat4 instanceTransform; uniform mat4 mvp; uniform float instanced_on;`; with `instanced_on > 0.5` the position goes through `instanceTransform` with its bottom row rebuilt to `0, 0, 0, 1` as `tree.vs` does (`model[0u][3u]` ...); `gl_Position = mvp * position; gl_Position.z = max(gl_Position.z, -gl_Position.w);`. `sun_shadow.fs` (new): `out vec4 finalColor;` set to `vec4(1.0)` (the framebuffer has no colour attachment). Header comments as `tree.vs`'s.

`field.fs`, `model.fs`, `tree.fs`, `cover.fs`: `outdoor_light(vec3 normal, vec3 up, float sunlit)` whose sun term is `sun_color * (sunlit * max(dot(normal, sun_direction), 0.0))`; `apply_haze` calls it with `1.0`. Right after `outdoor_light`, the same block in all four:

```
uniform highp sampler2D sun_shadow_map;
uniform mat4 sun_shadow_matrix;
uniform float sun_shadow_strength;
uniform vec4 sun_shadow_shape;

const float sun_shadow_normal_offset_texels = 2.0;
const float sun_shadow_depth_bias_texels = 0.5;

float sun_shadow_tap_weight(uint index, float fraction)
{
    if (index == 0u) {
        return 1.0 - fraction;
    }
    return index == 3u ? fraction : 1.0;
}

float sun_shadow_light(vec3 position, vec3 normal, vec3 eye)
{
    if (sun_shadow_strength <= 0.0 || dot(normal, sun_direction) <= 0.0) {
        return 1.0;
    }
    float fade = 1.0 - smoothstep(sun_shadow_shape.z, sun_shadow_shape.w, length(position - eye));
    if (fade <= 0.0) {
        return 1.0;
    }
    vec3 moved = position + normal * (sun_shadow_shape.y * sun_shadow_normal_offset_texels);
    vec3 coordinate = (sun_shadow_matrix * vec4(moved, 1.0)).xyz * 0.5 + 0.5;
    float depth = coordinate.z - sun_shadow_depth_bias_texels / sun_shadow_shape.x;
    vec2 texel_position = coordinate.xy * sun_shadow_shape.x - 0.5;
    vec2 base = floor(texel_position);
    vec2 fraction = texel_position - base;
    float lit = 0.0;
    for (uint row = 0u; row < 4u; row++) {
        for (uint column = 0u; column < 4u; column++) {
            vec2 texel = base + vec2(float(column), float(row)) - 0.5;
            float stored = textureLod(sun_shadow_map, texel / sun_shadow_shape.x, 0.0).r;
            lit += sun_shadow_tap_weight(column, fraction.x) * sun_shadow_tap_weight(row, fraction.y) * step(depth, stored);
        }
    }
    return 1.0 - sun_shadow_strength * fade * (1.0 - lit / 9.0);
}
```

with a comment above it (what the shape holds, the offset and bias, the kernel, the early returns, why `highp`, that the text is shared). The calls: `field.fs` `float sunlit = sun_shadow_light(fragment_world_position, normal, camera_position);` before `outdoor`, passed to `outdoor_light`, and `lit += sun_color * glint * sunlit;`; `model.fs` inside the `outdoor ?` branch only (the ghosts and the block world never read it); `tree.fs` and `cover.fs` in their `outdoor_light` call. Each header comment gains a line on the shadow.

### Tests

- `render_sun_shadows_test.odin` (new): `test_the_cascade_covers_the_radius` (fractions 0.1, 0.25, 0.4, ups `{0, 1, 0}` and `normalize({1, 2, 3})`, the eye 8000 m out: the eye plus or minus the radius along each axis lands inside clip space by at least the margin; `texel_metres` and `half_size` as defined); `test_the_cascade_snaps_to_whole_texels` (an eye moved a quarter texel along `right` keeps the centre and the matrix within 1e-5, one texel moves the centre one texel, 5 m along the sun moves it 5 m along the sun only; the eye stays within 0.71 texel of the centre in the light's plane); `test_casters_toward_the_sun_cast_within_the_reach` (a 2 m box at `toward_sun` times radius plus 50 casts, at half size plus reach plus 10 not, behind the far side not, beside past the half size not, straddling the side yes); `test_shadow_trees_are_the_nearest_inside_the_casters_box` (a cache of two tiles from `make_field_tree_tile_draw`, one beyond the reach, a felled key: the count, no felled or far tree, the cut keeps the nearest); `test_a_lit_slope_does_not_shadow_itself` and `test_an_occluder_shadows_the_ground_under_it` through a test only mirror `sun_shadow_lit_share(depths: []f32, frame: Sun_Shadow_Frame, position, normal: [3]f32) -> f32` (the shader's offset, bias and taps after the matrix, texel indices clamped) over a 2048 map filled from the cascade's basis (each texel centre's ray along `-toward_sun` met with the plane, depth `(half - t) / (2 half)` clamped to 0 to 1): planes at 0, 45, 75 and 85 degrees from the sun with the shading normal 10 degrees off either way read at least 0.98 everywhere in the radius; a 10 m square plate 10 m over flat ground under a sun 60 degrees high reads at most 0.01 under its shadow's middle and at least 0.99 a metre past its shadow's edge; `test_the_shadow_map_is_released_when_off_or_resized` (`sun_shadow_map_stale` over the states); `test_the_shadow_slot_follows_the_map` (`set_sun_shadow_map_slot` on two materials with local map arrays and one with nil maps: the NORMAL slot set and cleared, the albedo slot kept); `test_the_shadow_frame_carries_the_fade` (`sun_shadow_frame`'s shape and strength).
- `render_day_test.odin`: `test_the_sun_path_axis_is_square_to_the_sun` (fractions every 0.05, three ups: unit length, `|dot|` with `field_sun_world_direction` under 1e-5).
- `settings_test.odin`: `test_sun_shadows_follow_the_platform_default` (the four combinations).
- `configuration_test.odin`: `test_settings_file_round_trip` also sets `.Off`; `test_a_settings_file_without_sun_shadows_reads_the_default` (`.Default` without the key, `"on"` reads `.On`, `"maybe"` is refused naming `settings.sun_shadows`).
- `data_load_test.odin`: `test_the_shipped_sun_shadows` (the block above); `test_sun_shadows_bounds` (each bound's message at minimum less 1 and maximum plus 1 on the desktop row, `map_texels` 1536, the zero block).
- `shader_source_test.odin`: `test_the_lit_shaders_share_the_sun_shadow` (the four uniform lines in `field.fs`, `model.fs`, `tree.fs`, `cover.fs`; `float sun_shadow_light(` and `float sun_shadow_tap_weight(` equal to `model.fs`'s in all; the two constants equal the Odin ones through `shader_float_constant`); `test_the_sun_shadow_shader_presses_casters_onto_the_near_plane` (`sun_shadow.vs` holds `in mat4 instanceTransform;`, `uniform float instanced_on;` and the clamp line). The open sky test already compares the new `outdoor_light`.
- `ui_pointer_test.odin`: `test_the_sun_shadows_toggle_writes_on_or_off` (`Ui_Audit.sun_shadows_default`, copied by `audit_screen_context`: with it true and `.Default`, a tap on `settings_row_id("settings_sun_shadows")` writes `.Off` and a second `.On`; with it false the first tap writes `.On`).
- New tests at 1 s or more get `// slow` (the 2048 fills may).

### Docs

- `doc/presentation.md`: Light on the field, a bullet "The sun's shadow (0328)": the cascade, the snap, the casters and the press, the bias and the kernel, the sun term only and the strength, the fade, the setting and the rows, off and night; the keys line gains `sun_shadows`. The field session: the pass's place before each viewport's 3D pass and the target bound again. Shaders: `sun_shadow.vs`, `sun_shadow.fs`.
- `doc/content.md`, World: `sun_shadows`, its keys and bounds.
- `doc/ui.md`, the Display table: `Sun shadows (sun_shadows)`, default from the build's row, the toggle shows the effective value and writes on or off.
- `doc/code_map.md`: `render_sun_shadows.odin` in presentation; the shaders; `loop_field_session.odin`'s line names the pass.

### Hand-back check

- Memory a frame draws from: the framebuffer and its texture are freed or replaced only by `serve_sun_shadows` in `prepare_field_frame` and by `destroy_field_renderer`, between frames, the receivers' slots cleared before the delete; the pass only creates. `test_the_shadow_map_is_released_when_off_or_resized` covers the decision.
- A start-up load the game can make fail: the depth shader (an overlay copy) or an incomplete framebuffer logs one line and the field draws without shadows; an old overlay `field.fs` falls back to the shipped one.
- A number parsed from text: every `sun_shadows` key bounded; the setting is a strict enum.
- A shared budget: the frame's, per viewport; the trees capped by `tree_limit`, the terrain by the selection; the entities are drawn uncapped as the scene draws them (question 3).
- An unbounded list: the shadow trees capped where they draw.
- A UI audit case: none obsolete; the Display tab's new row is reached by scrolling at the smallest size.
- Tests touch no state directory: all in memory.
- A save layout: none; the settings file gains `sun_shadows`, an old file reads `default`.

### Cost (estimated from published figures and the counts above; not measured)

- Draws a viewport: terrain 20 to 50 (20 to 30 at noon, up to 50 with a low sun's reach), the trees 1 (every shipped species is `pine_tree`), the pod and its fixtures about 10 to 20, a player 12; about 45 to 85 at the home, 2 to 4 more per machine of a factory. Triangles: terrain 50 to 120 thousand (0311's 2380 a level 0 node), trees up to 2048 times 100 (615 thousand vertices, the pine unindexed), models 10 to 30 thousand.
- Couch (RX 5700, 2700X, 1080p): GPU about 0.3 ms on open ground, 0.5 to 0.7 ms in a dense forest (the tree vertices and the receivers' 16 reads over about 2 million fragments the larger parts); CPU 0.4 to 1.2 ms (the draws at 3 to 6 µs, the tree selection over up to 35 thousand cached instances in a dense forest). Twice in split screen.
- Deck (desktop row, 1280 by 800, 25 ms at the preset's cap): GPU about 0.8 ms open, 1.5 to 2 ms in a dense forest; CPU 0.5 to 1.5 ms. On by default; its measurement may move it.
- Phone (Android row if turned on): GPU 3 to 5 ms (the extra target's store and load on a tiler, the reads over about 1.5 million fragments), CPU 1 to 2 ms. Off by default.
- Memory: 16 MB for the 2048 map, 4 MB for 1024. Off: nothing.

### Questions to the main agent

1. `strength_percent` 70 leaves about half the noon light in a full shadow, against 0097's "soft and low contrast"; 100 is physically right and bluish dark. The captures decide; data only.
2. Ridge shadows across valleys at dusk beyond 64 m need a second, far cascade (0313's estimate: about 150 coarse nodes, 0.3 ms GPU, 0.5 to 1 ms CPU, refreshable every few frames). A follow-up item, or not wanted?
3. `draw_entities` has no box test, so the pass draws every machine again: a large factory doubles the machines' draw calls a viewport. Accept now and measure, or a cull seam (a box on `Model_Frame`) in this item?
4. During the descent the hull now shadows the cabin where the sun's term reached it through the interior share. Accept (physically right), or no pass while `pod_transform` is set?
5. `SUGGESTIONS.md`'s 0097 line on sun shadows is answered by this item: drop it at the landing?

### Decisions (main agent, 2026-11-07)

1. The strength ships at 70; the captures go to the user at 70 and 100 for the pick.
2. No far cascade in this item; a suggestion in `SUGGESTIONS.md` for the user (ridge shadows across valleys at dusk against a second pass).
3. The cast pass culls entities against the casters' box (a machine whose bounds lie outside it is not drawn into the map), so a large factory costs only what stands near the eye.
4. The pod's hull shadowing the cabin during the descent is accepted.
5. The 0097 shadows line leaves `SUGGESTIONS.md` at the landing.
6. The implementation starts from 0311's snapshot (stream 0310, 0311, 0328): `cover.fs` is one of the four shaders that share the block.
