# 0284: Every fire lights what is round it

Status: designing (2026-10-05)

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

Both flickers are computed on the CPU today (`flame_flicker`) and reach the flame shader as the quad's red byte; the shader's clock (the integer scroll of 0274) moves only the flow. So a light flickers with its flame when it calls the same procedure with the same salt, seconds and reduced motion flag as the flame's draw; one procedure per torch kind makes that structural. No data keys: the constants sit beside the flame's in Odin, as 0274's do.

### Field torches: a point light each

`src/loop_field_session.odin`:
- `FIELD_TORCH_LIGHT_COLOR :: [3]f32{1.0, 0.55, 0.2}` (the firebox lamp's `[255, 140, 52]`), `FIELD_TORCH_LIGHT_RADIUS_METRES :: 5.0` (`data/lighting.sjson`: a torch lights a room of about 10 m).
- `field_torch_flicker :: proc(torch: Field_Torch, seconds: f64, reduced_motion: bool) -> f32`: `flame_flicker(seconds, flame_salt(World_Coordinate(torch.sample), BLOCK_FRAME), reduced_motion)`. `field_torch_flame_draw` takes its flicker from it.
- `field_torch_point_light :: proc(torch: Field_Torch, spacing_millimetres: int, seconds: f64, reduced_motion: bool) -> Point_Light`: at the flame's middle (the box's centre plus the planet's up times `FIELD_TORCH_SIZE_METRES / 2 + FLAME_TORCH_HEIGHT * FIELD_TORCH_FLAME_SCALE / 2`), colour `FIELD_TORCH_LIGHT_COLOR * field_torch_flicker(...)`, the radius above, no clip box (it lights the ground, the walls and the player).
- `append_field_torch_lights :: proc(lights: ^[dynamic]Point_Light, torches: []Field_Torch, spacing_millimetres: int, eye: [3]f32, seconds: f64, reduced_motion: bool)`: every torch whose box centre is within `FLAME_DRAW_DISTANCE_METRES` of the eye (the test of `append_field_torch_flames`), so a torch lights where its flame draws.
- `gather_field_scene_point_lights :: proc(scene: Field_Scene, eye: [3]f32) -> (nearest: [MAXIMUM_POINT_LIGHTS]Point_Light, count: int)`: today's body of `set_field_scene_point_lights` up to `nearest_point_lights` (arms, `gather_machine_lights`, the window lights, the pod's move), then `append_field_torch_lights` with `model_frame_seconds(scene.frame)` and `scene.frame.reduced_motion` after the move loop (the torches stand on the field, not in the pod), then `nearest_point_lights(lights[:], eye)`. `set_field_scene_point_lights` calls it with `camera.position` and uploads as now.

The slots: one list, nearest the camera first, eight kept, as 0224 and 0229 left it. A torch is one more participant: in the cabin the pod's lamps (at most six, 0224) and the portholes (none at heat 0, and no torch within 64 m during the fall) are nearer than any torch outside; in a cave the near torches win over a far arm or furnace, which is what lights the view. Nothing reserves a slot. The 0273 log section does not mention "7 of 8" slots; the cabin count is 0224's (six lamps leave two).

The field's baked block light from the torch emitter stays steady and white; the point light adds the colour and the flicker on top (DESIGN.md's point lights rule, never in place of the field's light).

### Block torches: the flame's flicker per torch

`src/render_flames.odin`:
- `MAXIMUM_BLOCK_TORCH_FLICKERS :: 16` (matches `torch_flickers[16u]` in `chunk.fs` and `water.fs`), `BLOCK_TORCH_LIGHT_REACH_BLOCKS :: f32(MAXIMUM_LIGHT)` (a level 15 torch's light ends 15 blocks out), `BLOCK_LIGHT_FLICKER_SHARE :: 0.4` (the share of the flame's dip the block light takes: 0.88 to 1, mean 0.94).
- `block_torch_flicker :: proc(cell: World_Coordinate, seconds: f64, reduced_motion: bool) -> f32`: `flame_flicker(seconds, flame_salt(cell, BLOCK_FRAME), reduced_motion)`. `torch_flame_draw` takes its flicker from it.
- `block_torch_light_factor :: proc(flicker: f32) -> f32`: `1 - (1 - flicker) * BLOCK_LIGHT_FLICKER_SHARE`.
- `chunk_torch_cells :: proc(renderer: ^Chunk_Renderer, allocator := context.temp_allocator) -> []World_Coordinate`: every chunk render's `flames`, not culled by the frustum (a torch behind the camera lights faces in view).
- `block_torch_flicker_uniform :: proc(cells: []World_Coordinate, eye: [3]f32, seconds: f64, reduced_motion: bool) -> (torches: [MAXIMUM_BLOCK_TORCH_FLICKERS][4]f32, count: int)`: the cells nearest the eye first by the cell's centre (`cell + 0.5`), cut to the cap (an insertion like `nearest_point_lights`, ties in list order); xyz the centre, w `block_torch_light_factor(block_torch_flicker(cell, ...))`; unused slots all zero (w 0 ends the shader's loop, a factor is never below 0.88).

`src/render_chunks.odin`:
- Remove `LIGHT_FLICKER_FIRST_SECONDS`, `LIGHT_FLICKER_SECOND_SECONDS`, `LIGHT_FLICKER_MINIMUM`, `light_flicker` and the flicker uploads in `apply_weather` (it keeps its seconds for the wind and the clouds).
- `Chunk_Renderer.flicker_location` and `Water_Renderer.flicker_location` (`render_water.odin`) become `torch_flickers_location`, looked up as `"torch_flickers"`.
- `apply_torch_flickers :: proc(renderer: ^Chunk_Renderer, torches: [MAXIMUM_BLOCK_TORCH_FLICKERS][4]f32)`: `SetShaderValueV(.VEC4, MAXIMUM_BLOCK_TORCH_FLICKERS)` on the chunk and the water shader.

`src/loop.odin`, `draw_session_world`: the `frame := Model_Frame{...}` line moves above `draw_chunks` (everything it reads is set before), and before `draw_chunks` `apply_torch_flickers(&state.presentation.renderer, block_torch_flicker_uniform(chunk_torch_cells(&state.presentation.renderer), camera.position, model_frame_seconds(frame), frame.reduced_motion))`. The block light so moves from the render clock to the flames' tick clock: a paused game stills both.

`data/shaders/chunk.fs` and `water.fs`: `uniform float flicker;` becomes `uniform vec4 torch_flickers[16u];`, with `const float torch_reach_blocks = 15.0;` and `float torch_light_flicker(vec3 position)`, line for line the same in both: over the slots until w is 0, share = `clamp(1.0 - distance(torch.xyz, position) / torch_reach_blocks, 0.0, 1.0)` squared, dimming += share times (1 - w), weight += share; returns `1.0 - dimming / max(weight, 1.0)`. The light line reads `light_curve(fragment_block_light) * torch_light_flicker(fragment_world_position)`. Near one torch the face takes its flame's dip, between torches a blend weighted by nearness, past every listed torch's reach 1, so no seam and no chunk edge. Every integer literal with `u`. Torch is the only block with `light_level` (`data/blocks.sjson`), so all block light is torch light.

What keeps it aperiodic: each torch's factor is its flame's value noise at two rates (`flame_noise`, hashed steps, no period), salted by its cell; the shader has no clock, only weights. The two sines go.

### Tests

`src/render_flames_test.odin`:
- `test_a_field_torch_lights_with_its_flames_flicker`: at 10.25 s and 3600.5 s, a torch near the eye gives one light whose colour is `FIELD_TORCH_LIGHT_COLOR` times `field_torch_flame_draw(...).flicker` at the same seconds (exact f32), radius `FIELD_TORCH_LIGHT_RADIUS_METRES`, no clip box, above its box along the up; a torch past `FLAME_DRAW_DISTANCE_METRES` adds none; under reduced motion the colour is `FIELD_TORCH_LIGHT_COLOR * FLAME_FLICKER_MEAN`. At spacing 500.
- `test_field_torch_lights_share_the_eight_slots_unmoved`: a `Field_Scene{state = &state, pod_transform = <a translation>, window_lights = <two lights>}` with twelve torches round the eye (spacing 500): `gather_field_scene_point_lights` returns eight, nearest first; the window lights come back moved by the transform, a torch light at `field_torch_point_light`'s position unmoved.
- `test_the_block_torch_light_flickers_with_its_flame_and_has_no_period`: for two neighbouring cells, `block_torch_flicker` equals `torch_flame_draw(cell, ...).flicker` at the same seconds; the factor series at 60 samples a second for an hour stays in 0.88 to 1, moves more than 0.04, differs at every lag from 1 to 600 samples by more than 0.008 somewhere, and the two cells' series part by more than 0.008.
- `test_the_block_torch_flickers_are_capped_nearest_first`: 40 cells round the eye: 16 slots, nearest first by the centre, w the cell's factor at the seconds; with 3 cells, slots 3 to 15 are zero.

`src/shader_source_test.odin`: `test_the_block_shaders_share_the_torch_flicker`: `chunk.fs` and `water.fs` declare `uniform vec4 torch_flickers[%du];` with `MAXIMUM_BLOCK_TORCH_FLICKERS`, their `torch_light_flicker` bodies are equal (extracted as `shader_point_light_sum` does), neither declares `uniform float flicker;`, and `torch_reach_blocks` is `MAXIMUM_LIGHT` as a float literal.

`src/accessibility_test.odin`, the reduced motion test: `block_torch_light_factor(block_torch_flicker(cell, 12.5, true))` equals that at 99 s and `block_torch_light_factor(FLAME_FLICKER_MEAN)`; `field_torch_flicker` the same for a torch.

### Docs

- `doc/presentation.md`, The field session, the scene bullet: "the working arms', machines' and torches' lights gathered round the camera", the torches' within `FLAME_DRAW_DISTANCE_METRES`, not moved by the pod's transform, flickering with their flames.
- `doc/presentation.md`, Chunk meshes, the sky light bullet: block light takes each torch's flame flicker by nearness (`block_torch_flicker_uniform`, the 16 nearest, `BLOCK_LIGHT_FLICKER_SHARE`, `torch_light_flicker` in `chunk.fs` and `water.fs`), on the tick clock, at the mean under reduced motion.
- `doc/presentation.md`, Machine models, the Flames bullet: one sentence that a torch's light, the field's point light and the block light, takes its flame's flicker (`field_torch_flicker`, `block_torch_flicker`).
- Code comments: `render_point_lights.odin`'s header (the gathered lights include the field torches), `chunk.fs`'s and `water.fs`'s header (the flicker paragraph), `render_player.odin`'s `flicker_seconds` (now the weather's wind and clouds), `render_flames.odin`'s header.
- `DESIGN.md`, Fire: no change, "every fire lights what is round it" already covers the torches.

### Hand-back check

- A list that grows without bound is capped where it draws: the field torches are cut by distance and then to the eight slots; the block torches to `MAXIMUM_BLOCK_TORCH_FLICKERS` before the upload.
- A new participant in a shared budget: the field torches join the eight slots by distance (above); nothing else shares the block torches' uniform.
- Tests never touch the machine's state: all the tests above are pure.
- The rest (memory freed mid frame, file writes, start-up loads, parsed numbers, saves, UI audits) do not apply.

### For the main agent

- `BLOCK_LIGHT_FLICKER_SHARE` 0.4 (block light 0.88 to 1, was 0.96 to 1) is a guess for the couch: the full flame swing (0.7 to 1, as the firebox lamp and the field torch's point light take it) on all of a cave's light read as too strong on paper.
- The block world goes with 0237. The per torch blend costs a 16 slot loop per chunk and water fragment (the phone too); the cheaper option is one uniform flicker from the torch nearest the camera, which is not per torch. Designed the per torch one since the item asks for it.
- The field's baked torch light stays steady and white under the flickering warm point light; making it flicker too would need the field shader to blend per torch as above. Left out as not asked.

### Decisions (main agent, 2026-10-05)

1. Held until 0286 lands: the flicker the lights follow becomes the shared `fire_flicker` of `render_flames.odin` (four hashed bands and hashed flares, 0.4 to 1.5), which the flames of 0274 then take too, so `field_torch_flicker` and `block_torch_flicker` are revised against it before this item is approved. The per torch blend, the 0.4 light share and the steady baked field light are decided then.
