# 0304: The entry's flames outside the pod

Status: landed (2026-11-06, b2584ae)

Milestone: the entry's look (0273, 0286, 0288, 0290), 0303 folded in. The user (2026-11-06), on a Kerbal Space Program reentry seen from outside (`work/reference/0303/ksp_reentry_outside.jpg`): the flames are straight and long, and they do not lick the cone's slanted walls but run straight aft from the heat shield's widest rim; doing the real flames on the outside might straighten out the visuals, and is interesting for multiplayer. Today the plasma (0288) and the flakes (0290) are drawn only on the portholes, so the pod falls without a flame from any other view, and the flakes do not read from the chair (0303).

## Goal

During the fall the plasma is drawn on the pod in the world: the glowing shield and a wake streaming straight aft from its rim at the base's width, long, fading with distance, clear of the cone. Every viewer sees the same flames, from the chair through the portholes as from the third person camera or another pod, and the flakes shed from the rim into the wake read from the chair and from outside.

## Controls

None.

## Change

- The wake as geometry on the pod in its model frame: its shape from the rim, its length, the flow and the fire flicker of 0286 and 0288 carried over, the shield's glow; how the porthole sees it (beside the cone at the rim's offset, through the glass and the soot) and how it reads against the sky and the ground.
- The window sheath of 0288 goes where the wake covers it; the soot on the outer pane stays.
- The flakes of 0290 drawn outside, sized, counted and lit to read from the chair and from outside, their streaks long and straight. 0303's measurements of the footage against our captures size them (the log of this item).
- Docs: `doc/presentation.md` (The arrival); the log.

## Verify

- The checks and the suite.
- Captures at the peak from the chair's porthole and from the third person camera beside the pod, the flakes counted by the capture difference of 0290; sent to the user beside the reference picture and the footage.

## Specification (design, 2026-11-06)

Measured on `data/models/pod.obj` (cells, the record's frame: x and z centred, y up from the base) with `tmp/0304/geometry.py` (untracked). The body reaches 5.45 from the y axis only in the rim (y 0 to 0.5), at most 5.314 elsewhere (y up to 4.5), under 4.9 above y 4.5, nothing below y 0. During the descent the drawn pod's +y is exactly against the travel until the rest easing (0270), so +y is aft.

### What no viewer can do today

No one sees the pod from outside during the fall: a strapped player is first person (`field_view_camera_mode`, `STRAPPED_FIELD_ACTIONS`, `arrival_input` drops every press), a joiner is strapped too (`make_field_session_player`), `seat stand` is refused while falling, and a third person camera would be pulled into the cabin by the hull's volumes (`field_camera_obstacle`). The captures need a camera beside the pod, so this item adds a developer command, render only (Code, The arrival camera). No binding changes.

### The wake

- Shape (`Arrival_Wake_Shape`, model cells, from `heat_shield`): a tube of `ARRIVAL_WAKE_SIDES` 32 quads about the y axis from y 0 to `ARRIVAL_WAKE_LENGTH_DIAMETERS` 2 shield diameters (21.8 cells, the reference's 1 to 2 diameters, the far part faded out), its flats `ARRIVAL_WAKE_RIM_CLEARANCE_CELLS` 0.05 outside the rim (5.5; vertex radius 5.5 / cos(pi / 32) = 5.526). Straight and parallel to the axis: it leaves the rim at the base's width and stands 0.05 cells off the rim, 0.19 off the door's fairing (5.31), 0.5 off the skirt (5.0) and 3.1 off the cone's top (2.41 at y 6.8), so no flame touches the cone (the user's KSP note). Plus the shield's glow: a fan of 32 triangles of the rim's radius (5.45) `ARRIVAL_WAKE_SHIELD_DROP_CELLS` 0.03 under the base; from above the rim hides it. 96 triangles in all.
- Axis: the model's +y, so the wake turns with the pod through the rest easing (heat 0.85 at its start, tick 1440) as the flakes do (0290's deviation 2). Laid along the travel instead, the tube would cut into the cone's windward side once the pod leans more than about 11 degrees off the travel.
- Light along the flow: halving every `half_light_cells` = `ARRIVAL_WAKE_HALF_LIGHT_DIAMETERS` 0.25 diameters times (0.5 + 0.5 heat), 2.725 cells at the peak (the KSP measurement of 0303), so the wake is short and dim at the onset and longest at the peak; and gone over its last quarter (`1 - smoothstep(0.75 L, L, s)`), so no end shows.
- The look: 0288's sheath carried onto the tube in cells (shader below): the tongues (slow and fast layers crossfaded by the heat), the haze, the chemistry, the sparks, `plasma_ramp` by intensity, `fire_flicker` (one flicker for the wake, `arrival_wake_flicker`). The heat terms are 0288's (`smoothstep`s on the heat, `0.55 + 0.6 heat`); 0288's `lead` (1 where the flow entered the glass) becomes the light's fall along the flow (1 at the rim).
- An emitting and absorbing shell: the intensity on the view's path is the face intensity over max(|cos|, `COS_FLOOR` 0.35) between the view and the tube's normal, so the silhouettes run up to 2.9 times brighter, straight from the rim's ends, and the face (over the cone, through a porthole) is the thinnest. Opacity `1 - exp(-opacity_scale * intensity)`, premultiplied. `opacity_scale` comes from the data key `arrival_plasma.wake_opacity_percent` (below).
- Speeds and sizes from the chair's porthole (window 2) by ray casts through its bore from the seated eye: it sees the tube at s 3.86 to 4.64 (mean 4.21) cells aft of the rim, azimuth -115 to -108 degrees, 6.1 to 6.5 cells away, the patch 0.78 cells along the flow and 0.65 across, the view at cos 0.904 to the tube's normal (nearly face on), the flow running straight up the glass's view; the glass is 49 by 58 px at 720p, one cell there 82 px. 0288's glass was two radii, so one glass radius becomes 0.385 cells, and every 0288 speed and spatial scale converts by it. `WAKE_GAIN` 2.64 = cos 0.904 / 2^(-4.21 / 2.725) makes the porthole read 0288's intensity at the peak.
- Across the tube the noise wraps every whole number of noise cells round it (`wrapped_noise`), so the seam never shows; the finer octaves and the sparks fade where a noise cell would cover under 3 px (`detail`, by `fwidth`), so the tube seen from afar does not shimmer. Streaks: noise cells 8 a cell round the tube and 0.4 along at the first octave (scales 1, 2.13, 4.37), so the first octave's streaks are 2.5 cells long (straight and long from outside) and the third's 0.57 (the motion through the 0.78 cell porthole).
- Reduced motion: the flow at `CALM_FLOW` (0286's calm pace converted), morph, warp and sparks at 0.4, the flicker at its mean.
- Presentation only: a pure function of the arrival view (heat, seconds), the seed and the record, nothing saved or hashed, so a joiner or a load sees the same.

### What the portholes show

- 0288's window sheath goes: its quads stood outside the hull and would read as glowing squares on the cone from outside, and the wake now fills every porthole. From every cabin eye the rays through every bore meet the tube's wall between s 3 and 6, never its ends or the disc (test below). The soot stays on the outer pane; the window lights (0273) stay with their per window flickers.
- Goes with it: the keys `sheath_depth` and `sheath_radius` (`Pod_Window_Definition`, `Pod_Window`, `MAXIMUM_POD_SHEATH_DEPTH_CELLS`, `MAXIMUM_POD_SHEATH_RADIUS_CELLS`, their two checks in `validate_pod_windows`, the copies in `resolve_pod_windows`, the five windows' values in `data/machines.sjson`), `arrival_sheath_centre`, `arrival_travel_on_glass`, the sheath half of `arrival.fs` (layer 1, `sheath_scale`, `travel_on_glass`, the flow constants, the tongues, sparks and ramp), and the tests named under Tests. Record rule: windows are content read at load, never saved; Odin's `json.unmarshal` skips unknown keys (`core/encoding/json/unmarshal.odin`, "allows skipping unused struct fields"), so a data edits copy of `machines.sjson` still holding the keys loads. No log line.
- Draw order: the soot is on the pane inside the tube. An eye inside the tube (the chair, the cabin) draws the wake, the flakes, then the soot over them; an eye outside draws the soot first, then the wake and the flakes over it (`arrival_eye_inside_wake`).

### The flakes

- Kept from 0290: the closed form path in the model frame, the slot and candidate births thinned by the rate times the heat squared, the per index hash, the lives, the record key `heat_shield`, the fixed array cap, none under reduced motion, the porthole crossing test. `ARRIVAL_FLAKE_AIR_CELLS_PER_SECOND` stays 7: by the porthole a flake moves at 0.5 to 0.75 of it relative to the pod (3.5 to 5.3 cells a second), a third of the wake's `FAST_FLOW` 14, the footage's "a third of the gas's speed or less".
- Drawn in the world pass after the wake for every eye, depth tested against the hull, premultiplied, so a plate's core reads dark against the glow (0303: a core at 0.45 to 0.55 of the glow behind it). A flake beyond the far wall therefore also draws over it; with the pod hiding most of those, the read from the chair wins.
- Every flake is a plate: a charred core to 0.6 of its radius and a gold rim, opaque (0.92) and faded in and out; `ARRIVAL_FLAKE_DARK_CORE_CELLS` goes, `dark_core` is the fade for every flake.
- Size: half size `ARRIVAL_FLAKE_SMALLEST_CELLS` 0.055 to `ARRIVAL_FLAKE_LARGEST_CELLS` 0.11 (share squared): the port of 0303's model (`tmp/0303/flake_model.py`, 8 salts) gives plates of 8 to 15 px at 720p from the chair, median 10.7, cores about 6 px (0303: core 6 px or more, plate 9 to 10).
- Streak: `ARRIVAL_FLAKE_STREAK_SECONDS` 0.65 of the speed against the air, as wide as the plate at its root, narrowing to a quarter, its light halving every quarter of its length, white gold cooling to the haze: 75 to 98 px at the porthole (the glass is 58 tall), 4.6 cells at birth.
- Rate: `ARRIVAL_FLAKE_CANDIDATES_PER_SLOT` 5 to 8, so `MAXIMUM_ARRIVAL_FLAKES` 328 per pod and `MAXIMUM_ARRIVAL_FLAKES_PER_SECOND` 160 under the existing `#assert`; `arrival_flakes_per_second` shipped 50 to 90. The model at 90: 1.8 crossings a second at the chair's porthole within 1 s of the peak, a flake in view 23 percent of the time, 155 alive at the peak. 0303's target: 1.5 to 2.
- The head's share of the quad's length is now as small as 0.02, so it travels as its square root in the green byte (2 percent error instead of 10).

### Code

`src/render_arrival_wake.odin` (new, presentation cluster). Header: 0304, the wake and the shield's glow in the pod's model frame, drawn for every viewer, pure in the view, the seed and the record.

- Constants, each with a comment line: `ARRIVAL_WAKE_VERTEX_SHADER_PATH :: "shaders/arrival_wake.vs"`, `ARRIVAL_WAKE_FRAGMENT_SHADER_PATH :: "shaders/arrival_wake.fs"`, `ARRIVAL_WAKE_SIDES :: 32`, `ARRIVAL_WAKE_RIM_CLEARANCE_CELLS :: 0.05`, `ARRIVAL_WAKE_LENGTH_DIAMETERS :: 2.0`, `ARRIVAL_WAKE_HALF_LIGHT_DIAMETERS :: 0.25`, `ARRIVAL_WAKE_SHIELD_DROP_CELLS :: 0.03`, `ARRIVAL_WAKE_REFERENCE_INTENSITY :: 0.8` (0288's mean intensity on the chair's glass at the peak, so the opacity key is the mean opacity there).
- `Arrival_Wake_Shape :: struct {radius, length, shield_radius: f32}` (the tube's vertex radius, its length, the disc's radius; cells).
- `arrival_wake_shape :: proc(heat_shield: Pod_Heat_Shield_Definition) -> Arrival_Wake_Shape`: `{}` when `heat_shield.radius <= 0`, else the numbers above.
- `arrival_wake_quad :: proc(shape: Arrival_Wake_Shape, index: int) -> (corners: [4][3]f32, coordinates: [4][2]f32)`: azimuths `index / N * TAU` and `((index + 1) % N) / N * TAU` (so the seam's corners are bit equal), `point(a, y) = {r cos a, y, r sin a}`; corners at (a0, 0), (a1, 0), (a1, length), (a0, length); coordinates x `index / N`, `(index + 1) / N` (the last quad ends at 1, never running back), y 0 and `length` (cells along the flow).
- `arrival_wake_quad_normal :: proc(index: int) -> [3]f32`: `{cos, 0, sin}` at `(index + 0.5) / N * TAU`.
- `arrival_wake_shield_triangle :: proc(shape: Arrival_Wake_Shape, index: int) -> (corners: [3][3]f32, coordinates: [3][2]f32)`: `{0, -drop, 0}` and the rim points at the same two azimuths at `shield_radius`, y `-drop`; coordinates `{(index + 0.5) / N, 0}`, `{index / N, 1}`, `{(index + 1) / N, 1}` (x the share of the turn, y the share of the radius).
- `arrival_wake_half_light_cells :: proc(shape: Arrival_Wake_Shape, heat: f32) -> f32`: `ARRIVAL_WAKE_HALF_LIGHT_DIAMETERS * 2 * shape.shield_radius * (0.5 + 0.5 * heat)`.
- `arrival_eye_inside_wake :: proc(shape: Arrival_Wake_Shape, eye_cells: [3]f32) -> bool`: `shape.radius > 0`, `length(eye.xz) < radius * cos(pi / N)` and y within 0 to `length`.
- `arrival_wake_quad_order :: proc(shape: Arrival_Wake_Shape, eye_cells: [3]f32) -> (order: [ARRIVAL_WAKE_SIDES]int, far_count: int)`: the quads facing away from the eye (`dot(normal, eye - corners[0]) <= 0`) first in index order, then the facing ones; exact for planar quads of a convex tube, so the far walls composite under the near ones.
- `arrival_wake_flicker :: proc(seconds: f32, salt: u64, reduced_motion: bool) -> f32`: `fire_flicker(f64(seconds), salt + 60, reduced_motion)`.
- `arrival_wake_opacity_scale :: proc(percent: int) -> f32`: `-ln(1 - percent / 100) / ARRIVAL_WAKE_REFERENCE_INTENSITY` (2.01 at 80).
- `arrival_wake_frame :: proc(body, transform: matrix[4, 4]f32, eye: [3]f32) -> (eye_position, origin, axis: [3]f32)`: in the moved space, `transform_point(transform, eye)`, `transform_point(transform, transform_point(body, {}))`, `normalize(linear(transform * body) * {0, 1, 0})`. Gotcha in its comment: rlgl 6.0 transforms each immediate mode vertex by the pushed matrix on the CPU (`rlVertex3f`, `transformRequired`), so `vertexPosition` reaches the shader moved and `mvp` holds only the camera; the shader's uniforms are therefore in the moved space.
- `draw_arrival_wake :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, body, transform: matrix[4, 4]f32, shape: Arrival_Wake_Shape, eye_cells: [3]f32, eye: [3]f32, plasma: Arrival_Plasma_Config, flicker: f32, salt: u64, reduced_motion: bool)`: nothing unless Descent, `view.heat > 0`, `wake_ready`, `shape.radius > 0`. `DrawRenderBatchActive`, `DisableDepthMask`, `DisableBackfaceCulling`, `BeginBlendMode(.ALPHA_PREMULTIPLY)`, the shader, the default texture. Uniforms: `heat`, `seconds`, `flicker`, `calm`, `flame_seed` (`f32(salt % 1000) / 1000`), `opacity_scale`, `circumference_cells` (`TAU * shape.radius`), `half_light_cells`, `length_cells`, `eye_position`, `wake_origin`, `wake_axis` (`arrival_wake_frame`), `haze_color`, `ablator_color`, `layer`. Then `layer` 0 and the far quads (`order[:far_count]`, `rlgl.QUADS`, `Color4ub(255, 255, 255, 255)`, each corner's coordinates then `transform_point(body, corner)`, as `draw_arrival_quad`), flush; `layer` 1 and the 32 fan triangles (`rlgl.TRIANGLES`), flush; `layer` 0 and the near quads, flush (a uniform applies at the flush, so each change follows one). Restore the blend, the shader, culling and the depth mask. No `discard` in the shader, so early depth rejects the walls behind the cabin from the chair.

`src/render_arrival.odin`:

- `Arrival_Presentation` gains `wake_shader: rl.Shader, wake_ready: bool`; `init_arrival_presentation` loads the pair after the flake shader, logging `arrival: the wake shader did not load; the fall draws without its flames`; `destroy_arrival_presentation` unloads it.
- `draw_arrival_windows :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, entities: ^Entities, pod: Entity_Common, machine: Machine, plasma: Arrival_Plasma_Config, salt: u64)`: the soot alone (nothing at `soot <= 0`), one quad per window as today with `soot`, `soot_opacity`, `flame_seed` (per window, as today); depth mask and culling off and back, the default alpha blend. The travel, flickers, flakes and eye parameters go.
- New `draw_arrival_entry :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, entities: ^Entities, pod: Entity_Common, machine: Machine, plasma: Arrival_Plasma_Config, salt: u64, reduced_motion: bool, flakes: []Arrival_Flake, eye: [3]f32, transform: matrix[4, 4]f32)`, under the pod's transform after the scene: `body`, `pitch_metres`, `shape := arrival_wake_shape(machine.heat_shield)`, `eye_cells := transform_point(linalg.inverse(body), eye)`, `inside := arrival_eye_inside_wake(shape, eye_cells)`; soot when outside, `draw_arrival_wake` (flicker `arrival_wake_flicker(view.seconds, salt, reduced_motion)`), `draw_arrival_flakes`, soot when inside. Its comment states the order and why.
- New `arrival_watch_camera :: proc(body, transform: matrix[4, 4]f32, point, target: [3]f32, camera: rl.Camera3D) -> rl.Camera3D`: position `transform_point(transform, transform_point(body, point))`, target likewise from `target`, up and fovy kept; the camera unchanged when the two lie within 1e-3 m.
- `arrival_sheath_centre` and `arrival_travel_on_glass` go. The file's header and `ARRIVAL_WINDOW_LIGHT_*` comments drop the sheath (the light sits where 0273 put it, unchanged).

`src/render_arrival_flakes.odin`: the constants above (`CANDIDATES_PER_SLOT` 8, sizes 0.055 and 0.11, streak 0.65, `DARK_CORE_CELLS` gone, `dark_core = fade`). `arrival_flake_vertex_color`: green `arrival_flake_byte(math.sqrt(head_share))`. `draw_arrival_flakes` (signature unchanged) sets and restores the depth mask and culling itself, since it is no longer inside the windows' pass; its comment says it draws after the wake. Header and `Arrival_Flake` comments: every flake a plate, drawn after the wake.

`src/loop_field_session.odin`, `draw_field_viewport_world`:

- `arrival_viewport_camera` returns `(moved, pod_transform)` only (the rotation and the travel fed only the sheath); its no pod branch drops the travel line; its comment drops "with the rotation and the travel for the windows".
- After it: when `session.arrival_camera` holds a point, the pod is found and `pod_transform` is present, `camera = arrival_watch_camera(entity_body_matrix(...), transform, point, {0, f32(machine.footprint.y) / 2, 0}, camera)`.
- The pod block: `transform := pod_transform.? or_else linalg.MATRIX4F32_IDENTITY`, `eye := transform_point(linalg.inverse(transform), camera.position)`, then under the push `draw_arrival_entry(..., flakes[:flake_count], eye, transform)`.

The arrival camera (developer, render only, like `weather`):

- `src/session.odin`: `arrival_camera: Maybe([3]f32)` after `weather_override` (the command's point in cells of the pod's model frame, nil for the seat's camera; render only, not saved).
- `src/command.odin`: `Command_Context.arrival_camera: ^Maybe([3]f32)`, set in `session_command_context` (`lockstep.odin`) and `frame_command_context` (`loop.odin`) as `weather_override` is; `ARRIVAL_CAMERA_REACH_CELLS :: 200`; the usage `{"arrival_camera <x> <y> <z> | arrival_camera off", "during the fall, the camera at the point in cells of the pod's model frame looking at its middle, moved with the pod; off returns to the seat"}`; `case "arrival_camera"` beside `weather` calling `command_arrival_camera`: nil pointer `no world is loaded`; `off` sets nil (`ok arrival_camera off`); three words each `strconv.parse_f32` with `abs(value) <= ARRIVAL_CAMERA_REACH_CELLS` (NaN fails) set the point (`ok arrival_camera <x> <y> <z>`); else `usage_error`. Not in `command_writes_simulation`.

`src/machine.odin`: the sheath keys, constants, checks and copies go; the comments of `Pod_Window_Definition` and `validate_pod_windows` follow. `Pod_Heat_Shield_Definition`'s comment adds the wake.

`src/data_load.odin`: `Arrival_Plasma_Config.wake_opacity_percent: int` (comment: the wake's opacity face on where the chair's porthole looks at the peak, 0304); `MINIMUM_ARRIVAL_WAKE_OPACITY_PERCENT :: 5`, `MAXIMUM_ARRIVAL_WAKE_OPACITY_PERCENT :: 95` (a missing key reads 0 and is refused, so a stale data edits copy falls back to the data files at start); its bounds row; `MAXIMUM_ARRIVAL_FLAKES_PER_SECOND :: 160`. The struct's comment names the wake.

Data:

- `data/game.sjson`: `arrival_flakes_per_second = 90`, its comment "(0 to 160) ... and drift aft through the wake"; `arrival_plasma.wake_opacity_percent = 80`, the block's comment "The entry's plasma on the pod (0273, 0304)" plus: wake_opacity_percent (5 to 95) is the wake's opacity face on where the chair's porthole looks at the peak; lower shows the pod through its flames from outside and the sky through the porthole.
- `data/machines.sjson`: the five windows lose `sheath_depth` and `sheath_radius`; the key comment block and the pod's windows comment drop the sheath; the `heat_shield` comment: where the flakes break off and the wake leaves (0304).

`data/shaders/arrival.fs`: the soot alone. Keeps `fragment_texture_coordinate`, `soot`, `soot_opacity`, `flame_seed`, `SOOT_COLOR`, `cell_hash`, the 2D `value_noise`, `soot_fbm`, and today's layer 0 block as `main` (`q`, `seed`, the disc's discard, the soot formula and its discard). Everything else goes. Header: the portholes' soot (0273, 0288), the plasma moved to `arrival_wake.fs` (0304).

`data/shaders/arrival_wake.vs`: arrival.vs's form plus `out vec3 fragment_position;` set to `vertexPosition` (the moved space, header says why). Header: 0304, the u suffix rule.

`data/shaders/arrival_wake.fs` (header: 0304, the shell, the two layers and their texture coordinates, premultiplied, the u suffix rule, `seconds` under 32 s):

- Uniforms: `float heat, seconds, flicker, calm, flame_seed, layer, opacity_scale, circumference_cells, half_light_cells, length_cells; vec3 eye_position, wake_origin, wake_axis, haze_color, ablator_color`. Ins `fragment_texture_coordinate`, `fragment_position`.
- Constants: `FLICKER_MEAN = 0.85`, `WHITE_CORE = vec3(1.0, 0.97, 0.92)`, `VIOLET_SHADE = vec3(0.42, 0.30, 0.66)`, `CALM_FLOW = 0.22`, `SLOW_FLOW = 4.7`, `FAST_FLOW = 14.0`, `SPARK_FLOW = 12.5`, `SPARK_FAST_FLOW = 17.0`, `SPARK_CALM_FLOW = 2.9`, `SPARK_CALM_FAST_FLOW = 4.0`, `SPARK_LIFE = 15.0`, `SPARK_FAST_LIFE = 20.0`, `SPARK_TAIL = 8.0`, `HAZE_LEAD = 0.26`, `STREAK_ACROSS = 8.0`, `STREAK_ALONG = 0.4`, `WAKE_GAIN = 2.64`, `COS_FLOOR = 0.35`, each with 0288's comment converted (cells a second, the 0.385 cells a glass radius).
- Copied from arrival.fs: `cell_hash`, `plasma_ramp`.
- New helpers:

```glsl
uint wake_period(float frequency)
{
    return uint(max(floor(circumference_cells * frequency + 0.5), 1.0));
}

float round_tube(float share, float frequency)
{
    return share * float(wake_period(frequency)) + 4.0;
}

float detail(float footprint, float frequency)
{
    return 1.0 - smoothstep(0.35, 0.7, footprint * frequency);
}

float wrapped_noise(vec3 point, uint period)
{
    vec3 base = floor(point);
    vec3 fraction = point - base;
    vec3 blend = fraction * fraction * (3.0 - 2.0 * fraction);
    uint x0 = uint(base.x) % period;
    uint x1 = (x0 + 1u) % period;
    uint y0 = uint(int(base.y));
    uint z0 = uint(int(base.z));
    uint y1 = y0 + 1u;
    uint z1 = z0 + 1u;
    float near_bottom = mix(cell_hash(uvec3(x0, y0, z0)), cell_hash(uvec3(x1, y0, z0)), blend.x);
    float near_top = mix(cell_hash(uvec3(x0, y1, z0)), cell_hash(uvec3(x1, y1, z0)), blend.x);
    float far_bottom = mix(cell_hash(uvec3(x0, y0, z1)), cell_hash(uvec3(x1, y0, z1)), blend.x);
    float far_top = mix(cell_hash(uvec3(x0, y1, z1)), cell_hash(uvec3(x1, y1, z1)), blend.x);
    return mix(mix(near_bottom, near_top, blend.y), mix(far_bottom, far_top, blend.y), blend.z);
}

float streak_noise(float share, float along, float speed, vec3 seed, float pace, float footprint)
{
    float scales[3u] = float[3u](1.0, 2.13, 4.37);
    float morphs[3u] = float[3u](2.3, 3.9, 6.7);
    float total = 0.0;
    float weight = 0.5;
    float weights = 0.0;
    for (uint octave = 0u; octave < 3u; octave++)
    {
        float frequency = STREAK_ACROSS * scales[octave];
        vec3 point = vec3(round_tube(share, frequency), (along - seconds * speed) * STREAK_ALONG * scales[octave], seconds * morphs[octave] * pace + float(octave) * 7.1);
        float value = wrapped_noise(point + seed + vec3(float(octave) * 17.3, float(octave) * 29.1, 0.0), wake_period(frequency));
        total += weight * mix(0.5, value, detail(footprint, frequency));
        weights += weight;
        weight *= 0.5;
    }
    return total / weights;
}
```

- `spark_layer(vec2 point, uint period, float rate, float life_rate, vec2 seed, float pace, out float white_share)`: 0288's with `shifted = point + seed + vec2(4.0, 0.0)`, `base = floor(shifted)`, `cell = uvec2(uint(base.x) % period, uint(int(base.y)))`, `inside = shifted - base`, the head downstream at +y here (the flow runs to +y): `centre = vec2(0.25, 0.68) + vec2(0.5, 0.2) * hashes`, `trail = offset.y > 0.0 ? exp(-offset.y * offset.y * 400.0) : exp(offset.y * SPARK_TAIL)`; the rest unchanged.
- `vec4 shell(float intensity, float chemistry)`: `c = plasma_ramp(intensity + 0.18 * (chemistry - 0.5)) * clamp(0.35 + 0.75 * intensity, 0.0, 1.15)`, `alpha = 1.0 - exp(-opacity_scale * intensity)`, returns `vec4(c, alpha)`.
- `main`:

```glsl
    float share = fragment_texture_coordinate.x;
    float along = fragment_texture_coordinate.y;
    vec3 offset = fragment_position - wake_origin;
    vec3 view = normalize(eye_position - fragment_position);
    float footprint = fwidth(share * circumference_cells);
    float pace = calm > 0.5 ? 0.4 : 1.0;
    float slow_speed = calm > 0.5 ? CALM_FLOW : SLOW_FLOW;
    vec3 seed3 = vec3(flame_seed * 97.0, flame_seed * 53.0, flame_seed * 71.0);
    float heat_light = flicker * (0.55 + 0.6 * heat);
    if (layer > 0.5)
    {
        float glow = wrapped_noise(vec3(round_tube(share, 1.0), along * 3.0, seconds * 2.3 * pace) + seed3, wake_period(1.0));
        float face = (1.25 - 0.35 * along * along + 0.2 * (glow - 0.5)) * smoothstep(0.0, 0.35, heat) * heat_light;
        vec4 shield = shell(face / max(abs(dot(view, wake_axis)), COS_FLOOR), glow);
        final_color = vec4(shield.rgb * shield.a, shield.a);
        return;
    }
    vec3 radial = offset - wake_axis * dot(offset, wake_axis);
    float path = 1.0 / max(abs(dot(view, normalize(radial))), COS_FLOOR);
    float fast_share = calm > 0.5 ? 0.0 : smoothstep(0.2, 0.9, heat);
    float lead = exp2(-along / half_light_cells);
    float end = 1.0 - smoothstep(0.75 * length_cells, length_cells, along);
    float warp = 0.06 * (1.0 - 0.7 * fast_share) * (wrapped_noise(vec3(round_tube(share, 3.0), (along - seconds * slow_speed) * 0.6, seconds * 3.1 * pace) + seed3 + vec3(31.7, 3.9, 0.0), wake_period(3.0)) - 0.5);
    float warped = share + warp / circumference_cells;
    float n = streak_noise(warped, along, slow_speed, seed3, pace, footprint);
    if (fast_share > 0.0)
    {
        float fast = streak_noise(warped, along, FAST_FLOW, seed3 + vec3(13.7, 41.9, 5.3), pace, footprint);
        n = mix(n, fast, fast_share);
        n = clamp(0.5 + (n - 0.5) * inversesqrt(fast_share * fast_share + (1.0 - fast_share) * (1.0 - fast_share)), 0.0, 1.0);
    }
    float flare = flicker - FLICKER_MEAN;
    float threshold = mix(0.68, 0.38, heat) - 0.14 * lead - 0.22 * flare;
    float streak = smoothstep(threshold, threshold + 0.18, n) * smoothstep(0.1, 0.55, heat);
    float core = smoothstep(0.62, 0.8, n + 0.1 * lead + 0.15 * flare) * smoothstep(0.55, 1.0, heat);
    float haze_along = along - seconds * slow_speed;
    float haze_noise = 0.65 * wrapped_noise(vec3(round_tube(warped, 2.0), haze_along * 0.15, seconds * 0.8 * pace) + seed3, wake_period(2.0)) + 0.35 * wrapped_noise(vec3(round_tube(warped, 4.3), haze_along * 0.33, seconds * 1.7 * pace) + seed3 + vec3(17.3, 29.1, 0.0), wake_period(4.3));
    float haze_level = mix(0.18, 0.42, haze_noise) * smoothstep(0.0, 0.35, heat) + HAZE_LEAD * heat * lead;
    float chemistry = wrapped_noise(vec3(round_tube(warped, 1.5), haze_along * 0.3, seconds * 1.3 * pace) + seed3 + vec3(5.1, 9.7, 0.0), wake_period(1.5));
    float face = (haze_level + 0.55 * streak + 0.45 * core) * heat_light * lead * WAKE_GAIN * end;
    vec4 wake = shell(face * path, chemistry);
    float spark_rate = smoothstep(0.22, 0.85, heat) * (0.5 + 0.6 * flicker) * min(lead * WAKE_GAIN, 2.0) * end;
    float spark_speed = calm > 0.5 ? SPARK_CALM_FLOW : SPARK_FLOW;
    float spark_fast_speed = calm > 0.5 ? SPARK_CALM_FAST_FLOW : SPARK_FAST_FLOW;
    float spark_life = calm > 0.5 ? 4.5 : SPARK_LIFE;
    float spark_fast_life = calm > 0.5 ? 6.5 : SPARK_FAST_LIFE;
    uint first_period = wake_period(28.6);
    uint second_period = wake_period(44.2);
    float first_white;
    float second_white;
    float first = spark_layer(vec2(share * float(first_period), (along - seconds * spark_speed * pace) * 2.6), first_period, 0.22 * spark_rate, spark_life, seed3.xy + vec2(3.3, 8.9), pace, first_white) * detail(footprint, 28.6);
    float second = spark_layer(vec2(share * float(second_period), (along - seconds * spark_fast_speed * pace) * 3.25), second_period, 0.14 * spark_rate, spark_fast_life, seed3.xy + vec2(21.1, 5.7), pace, second_white) * detail(footprint, 44.2);
    float spark = max(first, second);
    float white_share = first >= second ? first_white : second_white;
    vec3 spark_color = mix(ablator_color, WHITE_CORE, 0.35 + 0.5 * white_share) * (0.8 + 0.3 * flicker);
    vec3 c = min(mix(wake.rgb, spark_color, spark), vec3(1.0));
    float alpha = max(wake.a, spark);
    final_color = vec4(c * alpha, alpha);
```

`data/shaders/arrival_flake.vs`: `fragment_head_share = (bytes.g / 255.0) * (bytes.g / 255.0);` and its header says the green byte is the square root. `arrival_flake.fs` (header: a charred plate with a gold rim and a streak aft, premultiplied, 0290 and 0304):

```glsl
const vec3 CHAR_COLOR = vec3(0.11, 0.065, 0.04);
...
    float across = fragment_texture_coordinate.x * 2.0 - 1.0;
    float along = fragment_texture_coordinate.y;
    float head_centre = 0.5 * fragment_head_share;
    float head_along = (along - head_centre) / max(head_centre, 0.001);
    float radius = sqrt(across * across + head_along * head_along);
    float plate = fragment_dark_core * (1.0 - smoothstep(0.85, 1.0, radius));
    float rim = smoothstep(0.5, 0.75, radius);
    vec3 gold = mix(ablator_color, WHITE_CORE, 0.25 + 0.4 * fragment_whiteness);
    vec3 plate_color = mix(CHAR_COLOR, gold * 1.6 * fragment_brightness, rim);
    float trail = clamp((along - head_centre) / max(1.0 - head_centre, 0.001), 0.0, 1.0);
    float width = mix(0.8, 0.25, trail);
    float streak = along > head_centre ? exp(-across * across / (width * width)) * exp2(-4.0 * trail) * (1.0 - smoothstep(0.85, 1.0, trail)) : 0.0;
    vec3 streak_color = mix(mix(ablator_color, WHITE_CORE, 0.6), haze_color, trail);
    float alpha = 0.92 * plate;
    vec3 c = plate_color * alpha + streak_color * streak * fragment_brightness * (1.0 - alpha);
    if (max(c.r, max(c.g, c.b)) < 0.003 && alpha < 0.003) discard;
    final_color = vec4(c, alpha);
```

### Tests

`src/render_arrival_wake_test.odin` (new; the shipped pod through `shipped_pod_body`, `cabin_eyes`, `segment_crosses_any_triangle`; a helper `wake_test_tube_exit(origin, direction: [3]f32, radius: f32) -> f32`, the larger root of `|(origin + t direction).xz| = radius`):

- `test_the_wake_clears_the_pod`: the shipped shape's flats (`radius * cos(pi / N)`) lie 0.04 to 0.06 outside `heat_shield.radius`; every corner of every body triangle lies at least 0.04 inside the flats from the y axis and at y 0 or above; `length` is 21.8 (1e-4); `shield_radius` is 5.45.
- `test_the_wake_tube_closes_without_a_seam`: every quad's corners at `shape.radius` from the axis (1e-4), y 0 at the first two and `length` at the last two; quad k's corners 1 and 2 equal quad k + 1's corners 0 and 3 exactly, the last quad's equal quad 0's; coordinates x `k / N` and `(k + 1) / N` (the last reaching 1), y 0 and `length`. `arrival_wake_quad_normal(k)` is unit and square to the quad's bottom edge.
- `test_the_shield_disc_lies_under_the_base`: every fan triangle's centre is `{0, -0.03, 0}`, its rim points at 5.45 from the axis at y -0.03, triangle k's last rim point is triangle k + 1's first.
- `test_the_far_walls_draw_first`: from `{0, 3, -32}` the order is a permutation of 0 to 31, its first `far_count` quads face away and the rest face the eye, `far_count` within 16 to 20 (18 by hand); from the chair's eye `far_count` is 32; from `{0, -12, 0}` too.
- `test_the_eye_inside_the_wake`: the chair's eye and every cabin eye inside; `{0, 3, -32}`, `{0, 30, 0}`, `{0, -1, 0}` outside; nothing inside `arrival_wake_shape({})`.
- `test_the_wake_light_and_opacity`: half light 2.725 at heat 1 and 1.3625 at heat 0 (1e-4); `arrival_wake_opacity_scale(80)` is `-ln(0.2) / 0.8` (1e-4) and the scale rises with the percent from 5 to 95.
- `test_the_wake_frame_is_in_the_moved_space`: identity transform: the eye kept, the origin `transform_point(body, {})`, the axis the body's up; a rotation and translation: each turned and moved alike, the axis unit.
- `test_the_wake_crosses_the_chairs_porthole_as_the_sheath_did`: rays from `cabin_eyes(pod)[0]` over a 33 by 33 grid of 0.5 degree steps about the direction to window 2's centre (right `normalize(cross(direction, {0, 1, 0}))`, up `cross(right, direction)`), each to the tube's flats radius (`wake_test_tube_exit`), kept when the segment crosses no body triangle. Measured: about 105 kept, s 3.86 to 4.64, mean 4.21, mean cosine 0.904. Asserts: at least 60 kept; mean s within 3.9 to 4.5; extent along the flow within 0.6 to 0.95; from `arrival_wake.fs` (`shader_float_constant`, `#load`) `FAST_FLOW`, `SPARK_FLOW` and `SPARK_FAST_FLOW` cross the extent in 2 to 4 ticks at 60 Hz; `SLOW_FLOW` within 2.3 and `FAST_FLOW`; `CALM_FLOW` within 10 percent of 0.56 times extent / 2; `WAKE_GAIN * exp2(-mean_s / 2.725) / mean_cosine` within 0.9 to 1.1.
- `test_the_wake_fills_every_porthole_from_the_cabin`: for every cabin eye and window, the rays from the eye through the pane's centre and through 8 points at r 0.2 on it, extended to the tube's flats, that cross no body triangle, meet the tube at s within 3 to 6 (never its root, its end or the disc); at least one such ray for the seated eye and window 2.
- `test_the_watch_camera_follows_the_pod`: identity body and transform: position the point, target the target; a turned and moved transform: both moved alike, up and fovy kept; a point at the target returns the camera unchanged.

Changed and removed:

- `src/render_arrival_test.odin`: remove `test_the_sheath_lies_outside_the_hull`, `test_the_sheaths_edge_is_never_seen_from_the_cabin`, `test_the_flow_enters_from_the_heat_shield`, `test_the_travel_lies_on_the_glass`, and the last two lines (the flow) of `test_a_porthole_facing_up_lays_along_the_forward`. The soot, light and bore tests stay.
- `src/render_arrival_flakes_test.odin`: `test_the_live_flakes_stay_under_the_cap` expects 328 and a largest count within 100 to 250; `test_the_flake_vertex_color_carries_its_values` expects green 180; `test_only_the_larger_flakes_show_a_dark_core` becomes `test_every_flake_is_a_dark_plate` (every flake alive at age 0.5 over the 200 slots round the peak has `dark_core` 1 and a size within 0.055 to 0.11; at birth 0). `flake_test_porthole_runs` records `Flake_Test_Run :: struct {start: u64, length: int}`; the median test reads the lengths; new `test_the_flakes_cross_the_chairs_porthole_most_seconds`: the runs starting within 60 ticks of the peak tick, pooled over the 8 salts, give 1.4 to 2.6 a second per world.
- `src/shader_source_test.odin`: `test_the_plasma_crosses_the_glass_as_fast_as_the_footage` goes (its check moves to the wake test); `test_the_plasma_shader_knows_the_flicker_mean` and the flake test's white core read `arrival_wake.fs`; new `test_the_wake_shader_takes_its_uniforms`: `arrival_wake.fs` declares each uniform `draw_arrival_wake` sets (`uniform float heat;` and the rest, by type).
- `src/machine_test.odin`: the `deep` and `narrow` rows and their windows go.
- `src/data_load_test.odin`: the refusal table gains `arrival_plasma.wake_opacity_percent` at 4 and at 96.
- `src/simulation_arrival_test.odin`, `test_the_arrivals_presentation_leaves_the_hash`: the sheath corners, `arrival_travel_on_glass` and the `travel` line go; it calls `arrival_wake_shape`, every `arrival_wake_quad` and `arrival_wake_shield_triangle`, `arrival_wake_quad_order(shape, {0, 3, -32})`, `arrival_eye_inside_wake`, `arrival_wake_half_light_cells(shape, view.heat)` and `arrival_wake_flicker` each tick; its comment names 0304.
- `src/command_test.odin`, `test_the_arrival_camera_command_sets_and_clears`: on `make_command_test` with the context's `arrival_camera` pointing at a local: `arrival_camera 0 3 -32` sets `{0, 3, -32}`; `arrival_camera off` clears; `arrival_camera 0 3`, `arrival_camera 0 3 201` and `arrival_camera nan 0 0` fail with the usage and leave it; a nil pointer answers `no world is loaded`; `command_writes_simulation("arrival_camera")` is false.

### Docs

- `doc/presentation.md`, The field session, The arrival: a bullet "The wake (0304, `render_arrival_wake.odin`, `arrival_wake.vs`, `arrival_wake.fs`)" before the windows: the tube and the disc from `heat_shield` in the model frame, straight aft along the pod's axis (turning with it in the easing), clear of the cone, the light halving every quarter diameter at the peak, the shell (silhouettes brighter, `wake_opacity_percent`), 0288's flow in cells (speeds from the chair's porthole), the wrapped noise and the detail fade, drawn after the scene for every viewer, the order with the soot and the flakes, reduced motion. The windows bullet keeps the soot and the lights and drops the sheath (its flow, speeds, sparks and colour move to the wake bullet). The flakes bullet: drawn after the wake for every viewer, every flake a plate, sizes, streak 0.65 s, 8 candidates a slot, cap 328, 90 a second shipped with the crossing figures.
- `doc/content.md`: `windows` without the sheath keys (the shipped five's sentence on the sheath goes); `heat_shield` also sets the wake; `arrival_flakes_per_second` (90, 0 to 160); `arrival_plasma` gains `wake_opacity_percent` (80, 5 to 95).
- `doc/commands.md`: an `arrival_camera` row after `weather`.
- `doc/architecture.md`, Sessions: "the forced weather" becomes "the forced weather and the arrival camera".
- `doc/code_map.md`: `render_arrival.odin`'s line drops the sheath and names `draw_arrival_entry` and the soot; `render_arrival_wake.odin` after it; `render_arrival_flakes.odin` "drawn after the wake". Run `python3 tools/code_graph.py --check doc/code_map.md` and record a new edge as its rules say.
- `DESIGN.md`, Fire: "a fire sits where it burns, so the entry's plasma streams straight aft from the heat shield's rim outside the pod, the same for every viewer, and a porthole only frames it (user, 2026-10-05 and 2026-11-06)".
- `doc/log/2026-11-06.md` (the main agent's).

### Hand-back check

- Start-up load that can fail: a data edits copy of `game.sjson` without `wake_opacity_percent` reads 0, is refused by the bound, and the start falls back to the data files (`load_start_data`, `turn_data_edits_off`); a copy of `machines.sjson` still holding the sheath keys loads (unknown keys are skipped). A wake shader that does not load logs and the fall plays without its flames.
- Numbers parsed from text: the `arrival_camera` coordinates (`ARRIVAL_CAMERA_REACH_CELLS`, NaN refused), the new key's bound, the flakes' raised bound.
- Lists capped where they draw: the flakes by construction (328, a fixed array, tested); the wake is a fixed 32 quads and 32 triangles.
- Old saves: no layout change; the removed keys are content.
- Tests: `data/` only; the command test points at a local, no state directory.
- The rest (memory under a frame, file writes, budgets, UI audit) do not apply.

### Cost

- From the chair (the phone's only view in the fall): 96 triangles whose fragments behind the cabin are rejected by early depth (no `discard`, depth writes off), so the shader runs on the visible glass alone, about 3000 px at 720p, each 10 wrapped noises (80 hashes) and two spark cells. On the CPU, 328 flake candidates a frame and viewport (up to 160 alive, each a closed form and a `fire_flicker`), 1 `fire_flicker` for the wake.
- From outside (the developer camera; no player has that view yet): the tube covers up to about 40 percent of a 720p frame in two layers, about 0.75 M fragments at about 90 hashes, fine on the desktop, heavy on a phone; an outside view in play would want the octaves cut by distance first.

### Capture (main agent)

- Session as `tmp/shot0290_start.sh` (copied to `shot0304_*`, the item's worktree, seed 290), paused at 1271.
- The chair's porthole: `look 180 -2`, a 120 frame clip from 1271 (`tools/capture_clip.sh`, the default crop), then the same ticks with `arrival_flakes_per_second` 0 (a data edits copy or the data file in the worktree) for the difference. Checked against: the glass (49 by 58 px) filled with the wake streaming up it, `tools/motion_stats.py` streak orientation within 20 degrees of 0288's peak clip and coherence 0.5 or more, the glass's mean luminance within 25 percent of `tmp/0303/sheath_r0.png`'s; flakes in view in most seconds (0303's 1.5 to 2 crossings a second, the model 1.8 over 8 worlds, one world may draw lower), each a dark core of 6 px or more (about 28 darker px) with a gold rim, the plate 9 to 10 px, its streak crossing the glass or 58 px long.
- From outside: `arrival_camera 0 3 -32` (beside the pod, 32 cells off its axis) and `arrival_camera 0 -14 -26` (below it, the shield), a still and a 60 frame clip each at 1271, and the side still at 1000 (onset) and 1600 (fade). Checked against: two silhouettes running straight from the rim's ends, parallel to the pod's axis on screen within 3 degrees, standing about 8 px off the skirt and 50 px off the cone's top at 720p; the light above the sky along a silhouette at 0.4, 1.0 and 1.25 diameters from the rim falling as KSP's 1 : 0.28 : 0.11 within a factor of 1.6; no seam or facet edge, no end; the shield glowing from below; the flake cloud trailing; the pod clear at the onset and the fade. Beside `work/reference/0303/ksp_reentry_outside.jpg`.
- Reduced motion on at 1271: no flakes, the calm wake. After the landing (1862) from the chair: the soot on the panes, no wake.

### For the main agent

1. The face on opacity (`wake_opacity_percent` 80) is one number for two views: matching 0288's veil through the porthole (the sky at 285 m is the day's behind it at the peak) makes the near wall hide the cone from outside at the peak (opacity about 0.96 at the skirt, 0.78 mid cone, 0.53 at its top, less in the streaks' gaps); the pod is clear at the onset and the fade. KSP's pod reads through its flames, which needs about 40 and lets the sky through the porthole. The capture decides.
2. The capture camera: the spec adds the developer command `arrival_camera`, render only. The alternative is letting the camera toggle reach the strapped seat with a chase camera outside the pod during the fall, a control change for your control design (and what a joiner might want, the user's multiplayer note).
3. The flake rate ships at 90 (porthole model); from outside about 155 are alive at the peak with streaks of 4.6 cells at birth, which may read as a shower. The rate and `ARRIVAL_FLAKE_STREAK_SECONDS` (a cap on the streak's length would be one more constant) are the capture's call.
4. The flakes' cores draw over the wake for every eye, so one behind the far wall shows over it; the pod hides most of those, and the chair's read needs the order.
5. The window lights keep 0286's flicker per window while the glass shows the wake's one flicker; independent light per porthole reads as each seeing its own patch. One flicker for all is a two line change if the couch prefers.
6. `COS_FLOOR` 0.35 keeps the silhouettes white for about 0.6 diameters before orange; KSP's run orange from the rim. A shader constant for the capture.

### Decisions (main agent, 2026-11-06)

1. `wake_opacity_percent` ships at 80 as specified. The capture takes the chair and the side camera at 80 and at 40 and the user picks; the value is data, so the pick needs no code. The user picked 60 on a capture of 20, 40, 60 and 80.
2. The developer command `arrival_camera` as specified. A player's outside view during the fall (the camera toggle reaching the strapped seat with a chase camera) is a control change and its own item, written after this one with the user.
3. The rate ships at 90 and the streak at 0.65 s as specified; the capture settles both, as data and one constant.
4. Accepted: the chair's read needs the order.
5. The window lights keep their per window flickers (no change in this item).
6. `COS_FLOOR` 0.35 as specified; the capture beside the reference decides whether the silhouettes start orange.
