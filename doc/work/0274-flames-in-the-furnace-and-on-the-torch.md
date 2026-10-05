# 0274: Flames in the furnace and on the torch

Status: implementing (2026-10-05)

## Goal

The stone furnace's firebox burns with live flames instead of the static glowing sheet and tongues of its model (user, 2026-10-05: "chuck the glowing hot mess that tries to be flames"), and the torch's flat flickering quad takes the same flame. One flame shader for both, from the research (`work/research/flames-2026-10-05.md`, untracked) and under DESIGN.md's Fire rule: a flow, soft edged as Techtonica's plume, a fixed ramp for the fuel, flicker without period, a light that flickers with it.

## Controls

No binding changes.

## Change

- A flame shader (`data/shaders/flame.fs`, `flame.vs`): value noise fBm scrolled up with a distortion growing with the height, a teardrop mask, a fixed continuous ramp (a yellow white core, an orange body, dark red tips for coal and wood), soft edged with a glow, flicker from hashed noise with no period, still under reduced motion; the size, the ramp and the direction as uniforms.
- The furnace: three to five fanned quads in the firebox mouth, fixed to the model so they read from the side, drawn only while the furnace works (as its glow motion); the coal bed's emissive pulsing slowly; a firebox point light in the flames' colour flickering with them, through the record's `lights`. The static flame sheet and the three tongues removed from `tools/models/machines/stone_furnace.py`, the OBJ regenerated (the coal bed and the frame stay).
- The torch: the same shader on a quad at `FLAME_SIZE`, the two colour flicker replaced by the ramp and the noise, on the field's torches (`draw_field_torches`, the play build's) as on the block world's (`render_flames.odin`).
- Docs: `doc/presentation.md` (Machine models, the furnace; the torch flames), `DESIGN.md` if the rule needs a word, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, `./build.sh model-check` on the furnace; `shader_source_test.odin` on the new shader.
- Tests: the flames and the light are off while the furnace idles; the flicker has no period; the model's triangle count stays under the budget.
- Screenshots of the working furnace from the front and the side, and of a torch, sent to the user before the landing.
- The couch: a furnace at work reads as a fire.

## Specification (design, 2026-10-05)

Designed on `main` at `1773900`, standalone from 0273 (its own stream). No save, network or simulation change: everything below is presentation, a pure function of the frame's time, the machine's cell and frame (the salt) and its working flag. The shader constants are first values for the main agent to tune at the screenshots, the structure stays.

### The shader (`data/shaders/flame.vs`, `flame.fs`, new)

`flame.vs` is `arrival.vs` with its header naming 0274 (the texture coordinate passed on). `flame.fs` takes `seconds`, `flame_seed`, `flicker`, `aspect` (the quad's height over its width) and `core_color`, `body_color`, `tip_color` (vec3). It copies `cell_hash` and `value_noise` from `arrival.fs` verbatim (one shader family) and adds `fbm(vec2 point, uint octaves)`: octave scales 1.0, 2.07, 4.31, 8.83, speeds 1.13, 1.71, 2.47, 3.61 (no small integer ratio), weights halving, each octave sampled at `point * scale + vec2(0.0, -seconds * speed)` so the pattern rises, normalised to 0 to 1. Every integer literal carries `u` (`4u`, `0u`, the array sizes). The fragment, in order, `uv` 0 to 1 across and up the tongue:

1. Reach: `h = uv.y / (0.8 + 0.2 * flicker)`, discard at `h >= 1.0` (the flicker moves the reach and the brightness, never the hue).
2. Flow coordinates: `q = vec2(uv.x - 0.5, uv.y * aspect)` (the noise unstretched on any quad), `s = vec2(flame_seed * 97.0, flame_seed * 53.0)`.
3. Distortion growing with the height: `w = fbm(q * vec2(2.3, 1.6) + vec2(0.0, -seconds * 0.93) + s, 2u)`, `x = (uv.x - 0.5) * 2.0 + 0.55 * h * sqrt(h) * (w - 0.5)`, `q.x += 0.25 * h * (w - 0.5)`.
4. Teardrop mask: `width = 2.6 * sqrt(h) * (1.0 - h)` (1 at a third of the height), `m = (1.0 - smoothstep(0.45 * width, width + 0.02, abs(x))) * smoothstep(0.0, 0.06, h)`.
5. Noise: `n = fbm(q * 2.3 + s, 4u)`.
6. Density, eaten from the top: `d = clamp(m * (1.35 * n + 0.62 - 1.15 * h), 0.0, 1.0)`.
7. Ramp, continuous: `heat = clamp(d * (1.2 - 0.6 * h), 0.0, 1.0)`, `c = mix(tip_color, body_color, smoothstep(0.08, 0.5, heat))`, `c = mix(c, core_color, smoothstep(0.55, 0.95, heat))`.
8. Glow: `halo = 0.22 * (1.0 - smoothstep(0.0, width * 1.7 + 0.12, abs(x))) * (1.0 - h) * smoothstep(0.0, 0.12, h)`.
9. Premultiplied out: `rgb = (c * d + body_color * halo) * flicker`, discard when its largest channel is below 0.003, `final_color = vec4(rgb, 0.6 * d)`.

Drawn with `BlendMode.ALPHA_PREMULTIPLY` (one, one minus source alpha): the flame adds its light and the body hides 60 percent of what is behind, so overlapping fanned quads need no sorting and the halo is pure glow. Depth tested, no depth writes, no culling.

### Data (`data/machines.sjson`, `machine.odin`)

- `flames` (optional, at most `MAXIMUM_MACHINE_FLAMES :: 8`, furnaces only): `{position = [x, y, z], width, height, yaw_degrees}` in cells of the model's frame, the position the tongue's base centre. `Machine_Flame_Definition` as written, `Machine_Flame :: struct {position, across: [3]f32, width, height: f32}` resolved with `across = {sin(yaw), 0, cos(yaw)}` (yaw 0 spans z and faces the front). `validate_machine_flames(definition, kind) -> string`, called after `validate_machine_lights`: refuses on another kind ("machine %q has flames, which only a furnace may"), too many, a base outside the footprint (`machine_light_inside_footprint`), `width` or `height` outside 0.1 to `MAXIMUM_FOOTPRINT_SIZE`, the top `y + height` above the footprint's height plus the tolerance, `yaw_degrees` outside -180 to 180, each naming the index; every comparison fails on NaN. `Machine` gains `flames: [MAXIMUM_MACHINE_FLAMES]Machine_Flame, flame_count: int`.
- A lamp may say `flicker = true` (`Machine_Light_Definition.flicker: Maybe(bool)`, `Machine_Light.flicker: bool`, absent false): its colour follows the machine's fire flicker. `validate_machine_lights` refuses it on a record without `flames` ("machine %q light %d flickers, but the machine has no flames").
- The stone furnace: `motion` goes (the flames' ember pulse replaces the glow's fixed cosine, a period the Fire rule refuses), and it gains `flames = [{position = [2.3, 2.84, 0.0], width = 2.7, height = 2.4, yaw_degrees = 0}, {position = [2.85, 2.84, 0.6], width = 1.4, height = 2.1, yaw_degrees = 35}, {position = [2.95, 2.84, -0.55], width = 1.4, height = 2.3, yaw_degrees = -35}, {position = [3.3, 2.84, 0.05], width = 1.2, height = 1.6, yaw_degrees = 80}]` (a broad sheet before the back wall, two fanned tongues and a near side on one, so the fan reads from the front and the three quarter views; all inside the mouth's opening (|z| under 1.5, x from the back at 1.9) and under its arch at 5.25 to 5.8, on the coal bed's top at 2.86) and `lights = [{position = [4.5, 3.4, 0.0], color = [255, 140, 52], radius_cells = 8.0, clip = false, flicker = true}]`: in front of the mouth, unclipped since the Fire rule wants the ground and the player lit, radius 4 m at 500 mm. The light goes through the record's lamps rather than a renderer light: it is gathered, moved with the pod and clipped like every lamp, and only its flicker is new. The steel furnace keeps its glow (a voxel model, no flames).
- The comment block above the records gains the `flames` paragraph and the lamp's `flicker` sentence. `tools/models/records.py` ignores both keys, the lab does not strip `flames` (a rework's modeller should see where the flames stand).

### Odin (`render_flames.odin` unless named)

- `FLAME_VERTEX_SHADER_PATH`, `FLAME_FRAGMENT_SHADER_PATH`; `Flame_Shader :: struct {shader: rl.Shader, ready: bool}`; `Model_Renderer.flame: Flame_Shader`, loaded by `use_flame_shader(renderer: ^Model_Renderer, data_directory: string)` in `init_model_renderer` (on failure one log line, "models: the flame shader did not load; machines and torches draw without flames"), unloaded in `destroy_model_renderer`. Not hot reloaded, as the model and arrival shaders.
- `FLAME_CORE_COLOR :: [3]f32{1.0, 0.93, 0.72}`, `FLAME_BODY_COLOR :: {1.0, 0.52, 0.12}`, `FLAME_TIP_COLOR :: {0.55, 0.09, 0.02}` (coal and wood, the research's ramp). `FLAME_FLICKER_MEAN :: 0.85`, `FLAME_EMBER_HERTZ :: 0.37`, `FLAME_SECONDS_WRAP :: 600.0`.
- `flame_salt :: proc(cell: World_Coordinate, frame: Frame_Id) -> u64`: `generation_seed.hash_u64` of the old `flame_flicker` key packing with the frame mixed in.
- `flame_noise :: proc(seconds: f64, hertz: f64, salt: u64) -> f32`: `arrival_noise`'s smoothed hashed steps at f64 (through `arrival_noise_value`), -1 to 1, no period, no f32 loss over a long session.
- `flame_flicker :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32`: the mean under reduced motion, else `0.85 + 0.1 * flame_noise(seconds, 6.1, salt) + 0.05 * flame_noise(seconds, 17.9, salt + 1)`, 0.7 to 1 (0273's `arrival_window_flicker` shape, written standalone). Replaces the torch's two sines.
- `flame_ember_glow :: proc(seconds: f64, salt: u64, reduced_motion: bool) -> f32`: the mean under reduced motion, else `0.85 + 0.15 * flame_noise(seconds, FLAME_EMBER_HERTZ, salt + 2)`.
- `flame_shader_seconds :: proc(seconds: f64) -> f32`: `seconds` modulo `FLAME_SECONDS_WRAP`, so the sine hash keeps its precision on the phone (one jump of the pattern every ten minutes).
- `flame_quad_corners :: proc(base, across, up: [3]f32, width, height: f32) -> [4][3]f32`: bottom left, bottom right, top right, top left (`base -+ across * width / 2`, plus `up * height` on top). Texture coordinates (0, 0), (1, 0), (1, 1), (0, 1).
- `Flame_Draw :: struct {corners: [4][3]f32, seed, flicker, aspect: f32}`. `machine_flame_draws :: proc(machine: Machine, body: matrix[4, 4]f32, salt: u64, flicker: f32, draws: ^[dynamic]Flame_Draw)`: per flame the base `transform_point(body, position)`, `across` and `up` through the body's linear part (so a width in cells becomes metres with the frame's pitch), seed `f32(salt % 1000) / 1000 + f32(index) * 0.618`.
- `gather_machine_flames :: proc(entities: ^Entities, machines: Machine_Registry, frame: Model_Frame, allocator := context.temp_allocator) -> []Flame_Draw`: every alive furnace whose `furnace_model_working` holds and whose machine has flames, its body `entity_body_matrix`, its salt `flame_salt(origin, frame id)`, its flicker `flame_flicker(model_frame_seconds(frame), salt, frame.reduced_motion)`.
- `draw_flames :: proc(flame: Flame_Shader, draws: []Flame_Draw, seconds: f64)`: nothing when not ready or empty; flush the batch, depth mask off, culling off, premultiplied blend, the shader, the ramp uniforms once, per draw the four uniforms and one quad as `draw_arrival_windows` draws its windows (`set_shader_float`; a `set_shader_vector3` beside `set_shader_vector2` in `render_chunks.odin` if 0273 has not added it, each stream adds it only when missing at its rebase), then everything restored.
- `draw_machine_flames :: proc(renderer: Model_Renderer, entities: ^Entities, machines: Machine_Registry, frame: Model_Frame)`: `draw_flames(renderer.flame, gather_machine_flames(...), model_frame_seconds(frame))`. Called in `draw_field_scene` inside the second `push_pod_transform` block after `draw_field_players`, before the ghosts, and in `draw_session_world` right after `draw_torch_flames`: after everything opaque.
- `draw_torch_flames :: proc(renderer: ^Chunk_Renderer, flame: Flame_Shader, camera: rl.Camera3D, seconds: f64, reduced_motion: bool)`: per torch cell the base `{x + 0.5, y + POST_HEIGHT - 0.02, z + 0.5}`, `across` the horizontal unit vector square to the camera's horizontal offset (`{1, 0, 0}` when the camera is straight above), up `{0, 1, 0}`, `FLAME_SIZE` (0.2) wide and `FLAME_TORCH_HEIGHT :: 0.32` tall, salt `flame_salt(cell, BLOCK_FRAME)`. The call in `loop.odin` passes `state.presentation.model_renderer.flame`, the raw `seconds` and the setting. `flame_centre`, `flame_size`, `FLAME_FLICKER_HERTZ`, `FLAME_SMALLEST_SHARE`, `FLAME_DIM_COLOR` and `FLAME_BRIGHT_COLOR` go.
- `render_models.odin`: `Model_Frame.reduced_motion: bool` (set from `state.settings.reduced_motion` in `loop.odin` and `loop_field_session.odin`, false in the planet preview); `model_frame_seconds :: proc(frame: Model_Frame) -> f64` (`(tick + alpha) / tick_rate`, so a paused game stills the flames as it stills every motion, and the screenshots reproduce); `posed_model_light`: while working, a machine with flames takes `flame_ember_glow(model_frame_seconds(frame), flame_salt(...), frame.reduced_motion)` as its glow, splatted. The whole emissive layer pulses with it (one multiplier per layer: the console's lights too, mildly at 0.7 to 1).
- `render_entities.odin`: `append_machine_lights` gains `flicker: f32 = 1` (a lamp with `flicker` takes `color * flicker`); `gather_machine_lights` gains `frame: Model_Frame` and passes the furnaces' `flame_flicker` (the same salt and seconds as their quads, so light and flame flicker as one).
- The model preview (`draw_model_preview_scene`): while `pose.working`, `draw_flames(renderer.flame, ...)` of `machine_flame_draws(machine, body, 0, FLAME_FLICKER_MEAN, ...)` at `seconds = phase * 8`, after the capsule.
- The command socket on a field world (`command_field.odin`): `insert <item> <count> <frame> <x> <y> <z>` into the machine at a frame's cell, `Developer_Request.frame` (already carried), `insert_for_developer` taking the frame (`entity_at`'s parameter); five words or frame 0 answer `error no block world` as before. Needed for the Verify's screenshots, since a field furnace cannot be fed from the socket today.

### The model (`tools/models/machines/stone_furnace.py`, an integration edit of the accepted lab model)

In `mouth`: the docstring drops "and the flames"; the comment "# Flames: ..." through the `blade` loop goes and in its place `for _ in range(27): random.random()` under the comment "The flames are the game's flame shader (0274); these 27 draws keep the hood's numbers." (the outline drew three numbers for each of seven tongues, the blades two each of three, and `hood` reads the same `details` stream after). The coal bed box, the coals, the frame, the ledge and the rivets stay. `tools/make_models.sh stone_furnace`, then: the budget print's `mouth` line 24 triangles lower (15 of the sheet, 9 of the blades) and every other line as before the edit; `./build.sh model-check stone_furnace` passes; the body about 3149 triangles, under 3200.

### Tests

- `render_flames_test.odin` (new): `test_the_flame_flicker_has_no_period` (salts 1 and 2, 60 s at 60 Hz: `flame_flicker` inside 0.7 to 1 with a spread above 0.1, for every lag of 1 to 600 samples the largest difference to the shifted series above 0.02, the two salts apart; `flame_ember_glow` inside 0.7 to 1; both the mean at every sample under reduced motion; `flame_flicker` at 36000.5 s inside its range), `test_flame_quad_corners_stand_on_their_base` (base (1, 2, 0), across (0, 0, 1), width 2, height 3 gives (1, 2, -1), (1, 2, 1), (1, 5, 1), (1, 5, -1)), `test_the_furnace_burns_only_while_it_works` (the shipped stone furnace from `make_test_content`, placed as `test_furnaces_tick_in_the_simulation` does: idle, `gather_machine_flames` returns none and `gather_machine_lights` appends none; with hematite and coal ticked to `Burning`, four draws and one light whose colour is the record's times a flicker in 0.7 to 1, the draws' bases inside the furnace's box in metres).
- `machine_test.odin` or beside the lights' tests: `test_machine_flames_are_validated` (each refusal above with its message, a flickering lamp without flames refused, the shipped stone furnace resolving 4 flames and a flickering unclipped lamp and no motion).
- `accessibility_test.odin`: the flame line becomes `flame_flicker(12.5, 7, true) == flame_flicker(99, 7, true) == FLAME_FLICKER_MEAN`.
- `shader_source_test.odin`: both shipped shader counts `>= 12`, the message naming flame; the scan covers `flame.fs` and `flame.vs` without a new test.
- `command_test.odin`: `test_field_insert_into_a_frame_machine` (on the place test's foundation and chest: `insert coal 5 <frame> <x> 0 0` ok and the chest holds 5, an empty cell "no entity there", frame 0 `error no block world`); `test_field_refuses_the_block_world_commands` keeps its five word `insert` line.

### Docs

- `doc/presentation.md`: Frame order, "torch flames" becomes "torch and furnace flames"; The field session's scene list gains "the working machines' flames (`draw_machine_flames`)" after the bodies; Shaders lists `flame.vs` and `flame.fs` (the flames of the furnace and the torch, 0274); Machine models, the stone furnace bullet: "a glowing coal bed with coals, where the flames burn (below)" for "a flame sheet against a dark back", and the count `model-check` prints; a new bullet "Flames (0274)": the record's quads, the shader in order (rising noise, distortion with the height, teardrop, continuous coal ramp, halo), premultiplied and unsorted, only while the model works, the ember pulse on the emissive layer, the flickering lamp, the flicker stilled under reduced motion and the flow not, the tick clock; Chunk meshes' line 51 ends "and the flames' flicker (0274), whose flow keeps moving".
- `doc/content.md`: the `lights` bullet gains `flicker = true`; a `flames` bullet beside it (the keys, bounds, furnaces only, presentation only, `records.py` ignores it); the "Coloured light" line names the stone furnace's flames.
- `doc/commands.md`: the `insert` row gains the frame form, the field refusal line drops `insert` but for its block form.
- `src/settings.odin`, the `reduced_motion` comment: "the flames' flicker (not their flow)" for "the torch flames"; `render_player.odin`'s `flicker_seconds` comment drops the torch flames.
- `doc/code_map.md` as `tools/code_graph.py --check` asks; its `render_flames.odin` entry reads "the flame shader, the torch's and the machines' flames".

### Log at the landing (`doc/log/YYYY-MM-DD.md`)

```
## Flames in the furnace and on the torch (0274)

Tags: fire, flame, furnace, torch, shader, light, presentation, 0274, m14

The second fire under the Fire rule, one shader for every burning fuel: the quads and the firebox lamp are data on the furnace's record, the ramp is the shader's. The quads draw premultiplied so the fanned tongues need no sorting. The furnace lost its glow motion, whose fixed cosine was a period, for an ember pulse of hashed noise on the whole emissive layer. The flames run on the tick clock, so a paused game stills them. The model's flame sheet and tongues are gone with their seeded draws kept, so the rest of the accepted model is unchanged. A field furnace can now be fed from the socket (insert with a frame), which the screenshots needed.
```

### Hand-back check lines that apply

- A number parsed from text is range checked: the flames' position, width, height and yaw, the lamp's `flicker` type, the insert's frame and count.
- A new participant in a shared budget: the firebox lamp takes one of the eight point light slots while it burns, the nearest eight kept as before.
- A list capped where it draws: at most eight flames a machine.
- Tests never touch the state directory: all of the above are pure or on test content.

### Screenshots (the main agent)

- The flames alone: `tools/model_preview.sh stone_furnace`, then `stone_furnace_front_0.25.png`, `stone_furnace_front_left_0.5.png` and `stone_furnace_close_0.75.png` (the rest phase without flames).
- The field, with the light (the memory's isolated session, `--dev --seed=274 --name=flames`): `tools/moc pause`, `tick 800`, `query world` (the pod's frame F), then through `tools/moc -` the 100 lines `place wooden_foundation F <x> -1 <z> 0` for x 9 to 18 and z -4 to 5 (outside the pod's +x side, as `test_field_place_on_a_frame_cell`), `place stone_furnace F 9 0 -4 0`, `insert coal 20 F 9 0 -4`, `insert hematite 50 F 9 0 -4`, `tick 120`, `query entities furnace` (centre C) and `query frames` (F's `right` R, `up` U, `forward` W); front: `teleport` C + 7R - 2.5U, `tick 30`, `look at` C + 2.15R - 0.9U, `screenshot 0274_front`, `tick 7`, `screenshot 0274_front_flicker`; side: `teleport` C + 5R + 5W - 2.5U, `tick 30`, the same `look at`, `screenshot 0274_side`; dusk for the light: `time dusk`, `screenshot 0274_dusk`.
- The torch: block world only (`--debug-terrain --dev`), `block torch` beside the player from `query player`; the block world has no `look`, so the main agent frames it with the mouse as the memory's xdotool recipe does.

### Questions answered

- The light through the record's `lights` with a new `flicker` flag, not a renderer light: the lamp path already gathers, moves and clips, and the record keeps its colour and place as data.
- The quads as record data: `CLAUDE.md` forbids a machine in Odin code, and a rework of the model may move the mouth.
- Under reduced motion the flicker (reach, brightness, light, ember) stills and the flow keeps moving, as 0273 decided: a frozen flame is a decal.
- No direction uniform: each quad is laid along its fire's up, so the flow is always up the texture. Premultiplied rather than plain alpha blending, for the fan without sorting.

### For the main agent

- The field's torches are still the small glowing boxes of `draw_field_torches` (the play build's torch); this item changes only the block world's torch, as its Change names `render_flames.odin`. Under the Fire rule the field torch wants the flame too: in this item (a quad at the sample, the same call as the block torch) or a new item?
- "At 1000 mm" in the brief: read as the furnace on the pod's frame at that frame's pitch (`query frames` answers it). If a 1000 mm frame was meant, the shot needs a private data copy with `foundation_pitch_millimetres = 1000` and a free frame, which `place` cannot start.

### Decisions (main agent, 2026-10-05)

1. The field's torches take the flame in this item: the play build runs on the field, so the block torch alone would change nothing the user sees. `draw_field_torches` keeps its box and draws the same quad above it through `draw_flames`, the salt from the torch's sample, the width `FLAME_SIZE` scaled as the box is (`FIELD_TORCH_SIZE_METRES` over the block torch's size).
2. "At 1000 mm" meant the field's sample spacing, not the frame's pitch. The `--dev` world's own spacing is fine for the shots; the furnace stands on the pod's frame as the recipe says.
3. The hash and the time: `cell_hash` in `flame.fs` is an integer hash of the cell (`uvec2` mixing with multiplications and shifts, every literal with its `u`), not `arrival.fs`'s sine hash, so a large coordinate keeps its precision on every GPU; and `seconds` reaches the shader as a `vec2` of whole seconds and the fraction (`flame_shader_seconds` returns that pair, each octave's scroll `whole * speed + fraction * speed`), so a session of days never wraps and never jumps. `FLAME_SECONDS_WRAP` goes. The fBm's structure and the rest of the shader stay as written.
4. The ember pulse on the whole emissive layer, the console's lights with it: accepted as the limitation of one emissive layer per model, which the glow motion already had, and named in the log. A later item may split the heat emissive from the electric one.
5. The `insert` frame form, premultiplied blending, the quads as record data and the lamp's `flicker` flag: accepted.
6. The stream: its own, a worktree from `main`. If 0273 lands first and adds `set_shader_vector3`, the rebase keeps one.
