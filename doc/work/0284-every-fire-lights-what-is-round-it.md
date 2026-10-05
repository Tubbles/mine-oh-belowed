# 0284: Every fire lights what is round it

Status: implementing (2026-10-05)

## Goal

The fire rule of `DESIGN.md` holds for the torches as it does for the furnace after 0274: a field torch is a point light of the flame's colour, flickering with its own flame (the same hash and clock), and the block world's torch light flickers with its flame instead of the periodic two sine `light_flicker` of `render_chunks.odin`. The 0274 review found both gaps, which predate it.

## Controls

None.

## Change

- The field torches join the point light gathering (`set_field_scene_point_lights` takes only arm and machine lamps today), nearest first within the eight slots, the flame's flicker scaling the colour as the furnace lamp's does.
- The block world's `light_flicker` goes for the flame's hashed noise, per torch.
- Docs: `doc/presentation.md` (The field, Flames), `DESIGN.md` (Fire, if the wording needs the torches named).

## Verify

- Tests: a field torch within reach adds a light with the flame's colour; its flicker equals the flame's at the same seconds; the block torch's light is aperiodic.
- A headless screenshot of a torch lit cave on the field at night.
- The couch.

## Specification (design, 2026-10-05)

Revised against 0286 (8185733). Every fire's flicker is `fire_flicker` (0.4 to 1.5, mean 0.85). The flames, the lamps and the block light read it. `flame_flicker` and its constants go. The flicker is computed on the CPU and reaches the flame shader as the quad's red byte, and the shader's integer clock moves only the flow. A light therefore flickers with its flame when it calls the same procedure with the same salt, seconds and reduced motion flag. One procedure per torch kind makes that structural. No data keys: the constants sit beside the fire's in Odin, as 0274's and 0286's do.

One band table for every fire, no `Fire_Flicker_Bands` parameter. The puffing rule (1.5 / sqrt(D) Hz) puts a 5 to 10 cm torch at 5 to 7 Hz and the furnace's metre-wide firebox near 1.5 Hz. The shared table (2.3, 5.9, 11.3 and 23.7 Hz, flares every 0.2 s slot) is closer to the torch than to the furnace. A second table would be untested numbers before the couch has seen either fire on `fire_flicker`. The furnace pass that 0286 named decides a large fire's table, and the seam is then a `bands: []Fire_Flicker_Band` parameter with `FIRE_FLICKER_BANDS` as the default.

### The flames move to fire_flicker

`src/render_flames.odin`:
- Remove `flame_flicker`, `FLAME_FLICKER_MEAN`, `FLAME_FLICKER_SLOW_HERTZ` and `FLAME_FLICKER_FAST_HERTZ`. `flame_noise` stays (the bands and the embers read it). `flame_ember_glow` keeps its model with `FIRE_FLICKER_MEAN` in place of `FLAME_FLICKER_MEAN` (the same 0.85). `loop_model_preview.odin`'s `FLAME_FLICKER_MEAN` becomes `FIRE_FLICKER_MEAN`.
- `gather_machine_flames`, `torch_flame_draw` and `field_torch_flame_draw` take `fire_flicker` through the procedures below. A `Flame_Draw.flicker` is then 0.4 to 1.5.
- `flame_vertex_color`: the red byte carries `clamp(flicker / FIRE_FLICKER_HIGHEST, 0, 1) * 255 + 0.5`. `flame.vs` gets `const float fire_flicker_highest = 1.5;` and `fragment_flicker = bytes.r / 255.0 * fire_flicker_highest`.
- `flame.fs` gets `const float fire_flicker_mean = 0.85;`. Three lines change, and the header comment's "0.7 to 1" becomes "0.4 to 1.5, fire_flicker":
  - The reach: `float h = uv.y / (0.82 + 0.12 * flicker);`. The highest flare fills the quad and the mean reaches 0.92 of it (0.97 today). The lowest is 0.87: a dip shortens the flame, it never leaves the quad.
  - The ramp, after the Fire rule as 0286 worded it (the flicker moves the place on the ramp, hotter whiter): `float heat = clamp(d * (1.2 - 0.6 * h) * flicker / fire_flicker_mean, 0.0, 1.0);`. At the mean it is today's heat.
  - The brightness: `rgb = (c * d + body_color * halo) * flicker` stays.
- `fire_point_light_flicker :: proc(flicker: f32) -> f32`: `FIRE_FLICKER_MEAN + (flicker - FIRE_FLICKER_MEAN) * FIRE_POINT_LIGHT_SHARE`, with `FIRE_POINT_LIGHT_SHARE :: 0.5`. A lamp runs 0.625 to 1.175 with the mean at 0.85, so at the mean it is as bright as the firebox lamp is today.
- `gather_machine_lights` (`render_entities.odin`): the furnace passes `fire_point_light_flicker(fire_flicker(seconds, flame_salt(furnace.origin, furnace.frame), frame.reduced_motion))` to `append_machine_lights`.
- The header comments of `render_flames.odin` and `fire_flicker` drop "flame_flicker keeps 0274's model": every fire reads `fire_flicker`.

### Field torches: a point light each

`src/loop_field_session.odin`:
- `FIELD_TORCH_LIGHT_COLOR :: [3]f32{1.0, 0.55, 0.2}` (the firebox lamp's `[255, 140, 52]`). `FIELD_TORCH_LIGHT_RADIUS_METRES :: 5.0` (`data/lighting.sjson`: a torch lights a room of about 10 m).
- `field_torch_flicker :: proc(torch: Field_Torch, seconds: f64, reduced_motion: bool) -> f32`: `fire_flicker(seconds, flame_salt(World_Coordinate(torch.sample), BLOCK_FRAME), reduced_motion)`. `field_torch_flame_draw` takes its flicker from it.
- `field_torch_point_light :: proc(torch: Field_Torch, spacing_millimetres: int, seconds: f64, reduced_motion: bool) -> Point_Light`:
  - Position: at the flame's middle, the box's centre plus the planet's up times `FIELD_TORCH_SIZE_METRES / 2 + FLAME_TORCH_HEIGHT * FIELD_TORCH_FLAME_SCALE / 2`.
  - Colour: `FIELD_TORCH_LIGHT_COLOR * fire_point_light_flicker(field_torch_flicker(...))`.
  - The radius above and no clip box, so it lights the ground, the walls and the player.
- `append_field_torch_lights :: proc(lights: ^[dynamic]Point_Light, torches: []Field_Torch, spacing_millimetres: int, eye: [3]f32, seconds: f64, reduced_motion: bool)`: every torch whose box centre is within `FLAME_DRAW_DISTANCE_METRES` of the eye (the test `append_field_torch_flames` uses), so a torch lights where its flame draws.
- `gather_field_scene_point_lights :: proc(scene: Field_Scene, eye: [3]f32) -> (nearest: [MAXIMUM_POINT_LIGHTS]Point_Light, count: int)`:
  1. Today's body of `set_field_scene_point_lights` up to `nearest_point_lights`: the arms, `gather_machine_lights`, the window lights and the pod's move.
  2. Then `append_field_torch_lights` with `model_frame_seconds(scene.frame)` and `scene.frame.reduced_motion`, after the move loop: the torches stand on the field, not in the pod.
  3. Then `nearest_point_lights(lights[:], eye)`.

  `set_field_scene_point_lights` calls it with `camera.position` and uploads as now.

The slots work as 0224 and 0229 left them: one list, nearest the camera first, eight kept, nothing reserved. A torch is one more participant:
- In the cabin, the pod's lamps (at most six, 0224) and the portholes are nearer than any torch outside. The portholes give no light at heat 0, and no torch stands within 64 m during the fall.
- In a cave, the near torches win over a far arm or furnace, and the near torches are what light the view.

The field's baked block light from the torch emitter stays steady and white. The point light adds the colour and the flicker on top (DESIGN.md: point lights never replace the field's light).

### Block torches: the fire's flicker per torch

`src/render_flames.odin`:
- `MAXIMUM_BLOCK_TORCH_FLICKERS :: 16`, matching `torch_flickers[16u]` in `chunk.fs` and `water.fs`.
- `BLOCK_TORCH_LIGHT_REACH_BLOCKS :: f32(MAXIMUM_LIGHT)`: a level 15 torch's light ends 15 blocks out.
- `BLOCK_LIGHT_FLICKER_SHARE :: 0.15`: the share of the fire's swing that a cave's light takes, about 1. The range is 0.93 to 1.10. The old sines ran 0.96 to 1, and the full 0.4 to 1.5 would pulse a whole cave by half.
- `block_torch_flicker :: proc(cell: World_Coordinate, seconds: f64, reduced_motion: bool) -> f32`: `fire_flicker(seconds, flame_salt(cell, BLOCK_FRAME), reduced_motion)`. `torch_flame_draw` takes its flicker from it.
- `block_torch_light_factor :: proc(flicker: f32) -> f32`: `1 + (flicker - FIRE_FLICKER_MEAN) * BLOCK_LIGHT_FLICKER_SHARE`. It is 1 at the mean and under reduced motion.
- `chunk_torch_cells :: proc(renderer: ^Chunk_Renderer, allocator := context.temp_allocator) -> []World_Coordinate`: every chunk render's `flames`, not culled by the frustum, because a torch behind the camera lights faces in view.
- `block_torch_flicker_uniform :: proc(cells: []World_Coordinate, eye: [3]f32, seconds: f64, reduced_motion: bool) -> (torches: [MAXIMUM_BLOCK_TORCH_FLICKERS][4]f32, count: int)`:
  - The cells nearest the eye first by the cell's centre (`cell + 0.5`), cut to the cap. It is an insertion like `nearest_point_lights`, ties in list order.
  - xyz is the centre and w is `block_torch_light_factor(block_torch_flicker(cell, ...))`.
  - Unused slots are all zero. A w of 0 ends the shader's loop, and a factor is never below 0.93.

`src/render_chunks.odin`:
- Remove `LIGHT_FLICKER_FIRST_SECONDS`, `LIGHT_FLICKER_SECOND_SECONDS`, `LIGHT_FLICKER_MINIMUM`, `light_flicker` and the flicker uploads in `apply_weather`. `apply_weather` keeps its seconds for the wind and the clouds.
- `Chunk_Renderer.flicker_location` and `Water_Renderer.flicker_location` (`render_water.odin`) become `torch_flickers_location`, looked up as `"torch_flickers"`.
- `apply_torch_flickers :: proc(renderer: ^Chunk_Renderer, torches: [MAXIMUM_BLOCK_TORCH_FLICKERS][4]f32)`: `SetShaderValueV(.VEC4, MAXIMUM_BLOCK_TORCH_FLICKERS)` on the chunk shader and the water shader.

`src/loop.odin`, `draw_session_world`:
- The `frame := Model_Frame{...}` line moves above `draw_chunks`. Everything it reads is set before that point.
- Before `draw_chunks`: `apply_torch_flickers(&state.presentation.renderer, block_torch_flicker_uniform(chunk_torch_cells(&state.presentation.renderer), camera.position, model_frame_seconds(frame), frame.reduced_motion))`.
- The block light so moves from the render clock to the flames' tick clock, and a paused game stills both.

`data/shaders/chunk.fs` and `water.fs`:
- `uniform float flicker;` becomes `uniform vec4 torch_flickers[16u];`, with `const float torch_reach_blocks = 15.0;`.
- New `float torch_light_flicker(vec3 position)`, line for line the same in both. It loops over the slots until w is 0. For each slot, share = `clamp(1.0 - distance(torch.xyz, position) / torch_reach_blocks, 0.0, 1.0)` squared; offset += share times (w - 1); weight += share. It returns `1.0 + offset / max(weight, 1.0)`.
- The light line reads `light_curve(fragment_block_light) * torch_light_flicker(fragment_world_position)`, still clamped at 1 per channel as now.
- The result: near one torch a face takes that torch's swing, between torches a blend weighted by nearness, and past every listed torch's reach 1. There is no seam at a chunk edge.
- Every integer literal carries `u`.
- The torch is the only block with `light_level` (`data/blocks.sjson`), so all block light is torch light.

What keeps it aperiodic: each torch's factor is its flame's `fire_flicker`, which has hashed bands and hashed flares and no period, salted by its cell. The shader has no clock, only weights.

### Tests

`src/render_flames_test.odin`:
- `test_the_flame_flicker_has_no_period` becomes `test_the_ember_glow_has_no_period`: the ember assertions only, with `FIRE_FLICKER_MEAN`. `fire_flicker` has its own test from 0286.
- `test_the_furnace_burns_only_while_it_works`: the lamp's factor equals `fire_point_light_flicker(draws[0].flicker)` within 1e-5 and lies in `fire_point_light_flicker(FIRE_FLICKER_LOWEST)` to `fire_point_light_flicker(FIRE_FLICKER_HIGHEST)`, keeping the hue. Every draw's flicker is within `FIRE_FLICKER_LOWEST` to `FIRE_FLICKER_HIGHEST`.
- `test_flame_vertex_color_carries_the_quad_values`:
  - Red bytes: flicker 1.5 gives 255, 3 clamps to 255, 0 gives 0 and 0.4 gives 68.
  - Decoded as `flame.vs` does (`byte / 255 * 1.5`), 0.85 comes back within 1.5 / 255.
  - The seed and aspect assertions stay.
- `test_a_field_torch_lights_with_its_flames_flicker`, at spacing 500:
  - At 10.25 s and 3600.5 s, a torch near the eye gives one light. Its colour is `FIELD_TORCH_LIGHT_COLOR * fire_point_light_flicker(field_torch_flame_draw(...).flicker)` at the same seconds (exact f32), its radius `FIELD_TORCH_LIGHT_RADIUS_METRES`, no clip box, above its box along the up.
  - A torch past `FLAME_DRAW_DISTANCE_METRES` adds none.
  - Under reduced motion the colour is `FIELD_TORCH_LIGHT_COLOR * FIRE_FLICKER_MEAN`.
- `test_field_torch_lights_share_the_eight_slots_unmoved`: build a `Field_Scene{state = &state, pod_transform = <a translation>, window_lights = <two lights>}` with twelve torches round the eye (spacing 500). `gather_field_scene_point_lights` returns eight, nearest first. The window lights come back moved by the transform, and a torch light comes back at `field_torch_point_light`'s position, unmoved.
- `test_the_block_torch_light_flickers_with_its_flame_and_has_no_period`, over 1860 ticks at 60 Hz:
  - For two neighbouring cells, `block_torch_flicker` equals `torch_flame_draw(cell, ...).flicker` at the same seconds.
  - The factor stays within `block_torch_light_factor(FIRE_FLICKER_LOWEST)` to `block_torch_light_factor(FIRE_FLICKER_HIGHEST)`.
  - `flicker_statistics(factor series).worst_lag_ratio` is at least 0.7. The ratio does not change with the scale.
  - The two cells' mean difference is at least 0.6 times the first's `mean_pair_difference`.
- `test_the_block_torch_flickers_are_capped_nearest_first`: 40 cells round the eye give 16 slots, nearest first by the centre, w the cell's factor at the seconds. With 3 cells, slots 3 to 15 are zero.

`src/shader_source_test.odin`:
- `test_the_block_shaders_share_the_torch_flicker`:
  - `chunk.fs` and `water.fs` both declare `uniform vec4 torch_flickers[%du];` with `MAXIMUM_BLOCK_TORCH_FLICKERS`.
  - Their `torch_light_flicker` bodies are equal, extracted as `shader_point_light_sum` extracts its sum.
  - Neither declares `uniform float flicker;`.
  - `torch_reach_blocks` is `MAXIMUM_LIGHT` written as a float.
- `test_the_flame_shaders_read_the_fire_flicker_bounds`: `flame.vs` holds `const float fire_flicker_highest = %v;` with `FIRE_FLICKER_HIGHEST`, and `flame.fs` holds `const float fire_flicker_mean = %v;` with `FIRE_FLICKER_MEAN`.

`src/accessibility_test.odin`, the reduced motion test: lines 135 and 136 (`flame_flicker`) are replaced.
- `block_torch_light_factor(block_torch_flicker(cell, 12.5, true))` equals the same at 99 s, and equals 1.
- `field_torch_flicker(torch, 12.5, true)` equals `FIRE_FLICKER_MEAN`.

### Docs

`doc/presentation.md`:
- The field session, the scene bullet: "the working arms', machines' and torches' lights gathered round the camera". The torches' lights come from those within `FLAME_DRAW_DISTANCE_METRES`, are not moved by the pod's transform, and flicker with their flames.
- Chunk meshes, the sky light bullet:
  - Block light takes each torch's fire flicker by nearness: `block_torch_flicker_uniform` (the 16 nearest), `BLOCK_LIGHT_FLICKER_SHARE`, and `torch_light_flicker` in `chunk.fs` and `water.fs`.
  - It runs on the tick clock and stands at 1 under reduced motion.
- Machine models, the Flames bullet:
  - The flicker is `fire_flicker` (0.4 to 1.5), carried over `FIRE_FLICKER_HIGHEST` in the byte. It moves the reach (`0.82 + 0.12 * flicker`), the brightness and the place on the ramp.
  - The firebox lamp and a field torch's light take `fire_point_light_flicker`, and the block light takes `block_torch_light_factor`.
  - Under reduced motion these hold at `FIRE_FLICKER_MEAN`.

Code comments:
- The header comments of `render_point_lights.odin` (the gathered lights include the field torches), `chunk.fs`, `water.fs` (the flicker paragraph), `flame.vs` and `flame.fs` (the range).
- `render_player.odin`'s `flicker_seconds`: it now feeds the weather's wind and clouds.
- The header of `render_flames.odin`.

`DESIGN.md`, Fire: no change. "Every fire lights what is round it" already covers the torches, and the ramp sentence of 0286 covers the flame's whitening.

### Hand-back check

- A list that grows without bound is capped where it draws: the field torches are cut by distance and then to the eight slots. The block torches are cut to `MAXIMUM_BLOCK_TORCH_FLICKERS` before the upload.
- A new participant in a shared budget: the field torches join the eight slots by distance (above). Nothing else shares the block torches' uniform.
- Tests never touch the machine's state: all the tests above are pure.
- The rest (memory freed mid frame, file writes, start-up loads, parsed numbers, saves, UI audits) do not apply.

### For the main agent

- **The depths are guesses for the couch.**
  - Block light takes `BLOCK_LIGHT_FLICKER_SHARE` 0.15 (0.93 to 1.10 about 1).
  - The point lights (the firebox lamp and the field torch) take `FIRE_POINT_LIGHT_SHARE` 0.5 (0.625 to 1.175 about 0.85).
  - The flames themselves take the full 0.4 to 1.5.
  - The 0286 portholes' light takes the full swing too. If you want every point light alike, set the point share to 1. The firebox lamp then dims to 0.4 in a dip.
- **The flame's mean height drops.** Reach at the mean drops from 0.97 to 0.92 of the quad, so the flames read 5 percent shorter. Enlarging the quads instead (the record's `height` and `FLAME_TORCH_HEIGHT`) is the alternative and would touch the furnace record.
- **The block world goes with 0237.** The per torch blend costs a 16-slot loop per chunk and water fragment, the phone included. The cheaper option is one uniform flicker from the torch nearest the camera, which is not per torch. I designed the per torch one because the item asks for it.
- **The field's baked torch light stays steady and white** under the flickering warm point light. Making it flicker too would need `field.fs` to blend per torch as the chunk shader does. I left it out because the item does not ask for it.

### Decisions (main agent, 2026-10-05)

1. Approved as revised against 0286: every fire reads `fire_flicker`, `flame_flicker` goes, one band table for every fire until the furnace pass.
2. The depths as designed, each a named constant for the couch: the point lights at `FIRE_POINT_LIGHT_SHARE` 0.5, the block light at `BLOCK_LIGHT_FLICKER_SHARE` 0.15, the flames at the full swing. The portholes' light keeps its full swing of 0286, since a wall of fire outside the glass is not a lamp.
3. The flames 5 percent shorter at the mean: accepted, the flares fill the quad. The quads stay.
4. The block world blends per torch as designed: the Fire rule is what the item is for, and the cost goes with the block world (0237).
5. The field's baked torch light stays steady and white under the point light.
