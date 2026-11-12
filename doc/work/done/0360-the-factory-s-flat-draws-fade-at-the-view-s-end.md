# 0360: The factory's flat draws fade at the view's end

Status: landed (2026-11-12, 442e4f9)

Found by 0354's design: foundation slabs (`draw_frames`), belt runs and poles and torch boxes are drawn unhazed at every distance (0313 chose them so). At a 256 m view a factory 300 m away shows them standing on the faded ground with its machines faded out. Since 0347 the slabs are `draw_field_foundations` and, with the runs and the belt items, are culled at the haze's end, so they stop there on a step instead of showing past it.

## Goal

Everything of a factory fades at the view's end as its machines do.

## Controls

None.

## Change

- The slabs, belt runs, poles and torch boxes take the haze and the end fade of `apply_haze`, or end with the view.
- After 0347, which rewrites these draws, and 0355, which removes the poles.

## Verify

- The checks and the suite.
- Captures at a 256 m view of the profile's factory from 120 to 250 m, across the fade, and from beside it, before and after, sent to the user (decision 3).

## Specification (design, 2026-11-12)

Designed against `main` at `f98059f` (0347 landed as `9a6d5df`). Presentation only: shader colour and draw grouping; nothing reaches the tick, the hash, the save or the network. No setting, control, data key or new uniform. The poles are the runs' belt poles (`draw_belt_poles`); the power poles are not drawn on the field (0347 decision 4, 0362) and leave with 0368, so nothing here waits on 0355.

### Today (main at `f98059f`)

- Hazed: the machines' lit layer (`model.fs:276`, instanced by `draw_scene_model_instances`), the pod's lit layer (`DrawMesh`), the players' bodies, the globe, the terrain, the trees and the cover.
- Unhazed, flat through the model shader (`model.fs:265-268` returns `base`): the machines' emissive layer (`render_model_instances.odin:507`), the slabs and their edges (`render_frames.odin:277-283`, `295-309`), the belt items (`render_belt_runs.odin:262-268`).
- Unhazed, rlgl's batch through raylib's default shader: the runs and pipes (`render_belt_runs.odin:303-317`), the belt poles (`291-292`), the items arms hold (`render_entities.odin:152-155`, `179-181`), the vessel parts' boxes (`458-475`, no vessel part has a model), the fallback boxes of a machine without its model (`104-130`, `185-211`), the torch boxes (`loop_field_session.odin:331-336`), the edges without `glDrawArraysInstanced` (`render_frames.odin:299`).
- Unhazed by `DrawMesh` with raylib's default material: the pod's emissive layer (`render_models.odin:377-382`).
- Since 0347 every unhazed draw above stops on a step at the haze's end (`Model_View`, `loop_field_session.odin:664-669`), except the torch boxes, which are never culled and draw past the view at every distance.
- Never at the view's end: the ghosts, the run tool's curve and the placement editor's outline (the field's only selection outline) draw after `clear_model_open_sky` within the viewer's reach; the flames end at 64 m; the drill's bar and arrow and the launch pad's tower, rocket and fallback draw in raw cells inside the planet (0362).

### Decisions

1. **Every flat draw takes `apply_haze`** with the sky share 1, the models': the aerial haze and the end fade, on the open sky only (`outdoor_on`, whose zero uniforms give no number outside a field session). This alone covers the slabs, their edges, the belt items and the machines' emissive layers. Near, the flat draws take the aerial haze the lit layer already takes: at most 2 percent within 30 m, 8 at 128 m.
2. **rlgl's batch draws through the model shader's flat mode** between `begin_flat_batch` and `end_flat_batch` (`rl.BeginShaderMode` and `rl.EndShaderMode`, flat on). Flat without `instanced_on` means the batch: `model.vs` takes the vertex itself as the world position. rlgl moves a batch vertex by the stack on the CPU (`rlVertex3f`) and at every flush writes `matModel` from the stack's transform at that moment (`rlDrawRenderBatch`, lines 3056 to 3059 of raylib 6.2's `rlgl.h`), so a flush inside a frame's push or `DrawCube`'s own would apply a transform twice.
3. **The flat mode reads `texture0`** at `fragment_texcoord`: the belt surface's texture in the batch; for the meshes the material's white default (`begin_instanced_material` binds it at unit 0; their texcoord attribute is off, `UploadMesh`). Before the haze a batch draw then looks exactly as raylib's default shader drew it, and rlgl sets `colDiffuse` to white at the flush.
4. **What draws in a flat batch**: the runs, pipes and poles (`draw_belt_runs`), the torch boxes (`draw_field_torches`), the edges' fallback, and in the scene's `draw_entities` every pool's batch draws but the foundations' (the held items, the vessel parts' boxes, the fallback boxes; question 1). The foundations' pool stays out: the pod draws there by `DrawMesh`, and its lit layer would read `flat_on` at 1. Between a flat batch's begin and end nothing draws through the model shader by `DrawMesh` or instanced and nothing sets its switches, since the flush at the end reads the program's uniforms as they stand then. Gate in `draw_entities`: the pass has a view and collects instances (`model_frame_flat_batch`), so every model in those pools appends an instance.
5. **The cull meets the fade**: the view's distance is `haze.fog_end` (`loop_field_session.odin:667`), where the end fade's `smoothstep(fog_start, max(fog_end, fog_start + 1.0), reach)` reaches 1; a culled box's nearest point lies past it (`model_view_shows`, `box_distance_metres`), so every culled fragment was already the end colour and nothing pops. The run, pole, brick and posed boxes enclose what they draw. The torch boxes stay unculled: past the view they draw in the end colour.
6. **The sun's pass is unchanged.** A faded slab still casts through its brick, as a hazed machine casts today; the haze is the scene's colour and the kept map's key (0348) holds none, so no map redraws. The runs, poles and torches cast nothing, as before. The receivers lie within 64 m (48 on Android), short of the shortest view's 154 m fog start.
7. **Left unhazed**: the pod's emissive layer (question 2), the flames, the debris, the ghosts, and every fallback without the model shader's instancing (`flat_batch_ready` false).

Cost: a flat fragment runs `apply_haze` (two square roots, three or four exponentials and a power over about 50 other operations, the lit layer's own haze) and one texture read, against three multiplications today; a lit fragment adds 16 shadow texel reads and up to 8 lights to that, so a slab stays well below it. Each flat batch flushes rlgl's batch at its begin and end: up to 8 more batch draws a viewport.

### Files and procedures

`data/shaders/model.vs`
- `in vec2 vertexTexCoord;` after `vertexColor`; `uniform float flat_on;` after `instance_tint_on`; `out vec2 fragment_texcoord;` after `fragment_tint`.
- In `main`, after `vec4 local = ...`, in place of the world position line:
  ```glsl
      bool batch_vertex = flat_on > 0.5 && instanced_on < 0.5;
      fragment_world_position = batch_vertex ? local.xyz : (matModel * local).xyz;
  ```
  and `    fragment_texcoord = vertexTexCoord;` after `fragment_color`.
- Header: flat without instancing is rlgl's batch drawn through the shader (0360, `begin_flat_batch`), its vertices already in the world's metres, and why `matModel` is not read for it (decision 2); the texcoord passes to the flat mode's `texture0`.

`data/shaders/model.fs`
- `in vec2 fragment_texcoord;` after `fragment_tint`; `uniform sampler2D texture0;` after `flat_on`.
- `main` (the "Selected, not mixed by outdoor_on" comment moves up with its line):
  ```glsl
      vec4 base = fragment_color * colDiffuse * fragment_tint;
      // Selected, not mixed by outdoor_on: ...
      bool outdoor = outdoor_on > 0.5;
      if (flat_on > 0.5) {
          vec4 unlit = base * texture(texture0, fragment_texcoord);
          finalColor = vec4(outdoor ? apply_haze(unlit.rgb, fragment_world_position, camera_position, 1.0) : unlit.rgb, unlit.a);
          return;
      }
      vec3 normal = normalize(fragment_normal);
  ```
  then the lit path as today, reading the same `outdoor`.
- Header: "Without a texture sampler: raylib's default texture is white, so leaving it out changes nothing." goes; the flat mode's sentence becomes: with `flat_on` at 1 the colour is the vertex colour times `colDiffuse`, the tint and `texture0` (white for the meshes, the belt's texture for a run in rlgl's batch), raylib's default shader, hazed on the open sky as the lit layer (0360): the emissive layer, the slabs and their edges, the belt items and, through the batch, the runs, the poles and the torch boxes.
- GLSL: no integer literal is added; `batch_vertex`, `unlit`, `texture0`, `fragment_texcoord` and `vertexTexCoord` are no reserved word. Under the ES 3.00 rewrite `flat_on` has the prepended `highp` in both stages, as ES requires of a uniform both declare, and `texture0` keeps the fragment stage's default `lowp` sampler, as `tree.fs` and `water.fs` declare it.

`src/render_models.odin`
- `Model_Renderer.flat_batch_ready: bool` after `instancing_ready`, comment: rlgl's batch may draw through the flat mode (0360, `begin_flat_batch`): the instancing uniforms and `texture0` found.
- `use_model_shader`, after the instancing log line: `renderer.flat_batch_ready = renderer.instancing_ready && shader.locs[int(rl.ShaderLocationIndex.MAP_ALBEDO)] != -1`; when instancing is ready and the batch is not, the log line `models: the model shader samples no texture0, the runs and the torch boxes draw unhazed` (an overlay copy from before 0360, which would draw the belts untextured).
- Header: the emissive layer's flat mode "hazed on the open sky (0360)".

`src/render_model_instances.odin`
- Pure, beside `model_frame_takes_instances`: `model_frame_flat_batch :: proc(frame: Model_Frame) -> bool`: `frame.view != nil && frame.instances != nil`, the scene's pass collecting instances, where no model of `draw_entities`' pools draws by `DrawMesh` but the pod.
- `begin_flat_instances`: after `begin_instanced_material`, `matModel` set to `rlgl.GetMatrixTransform()` as `draw_scene_model_instances` sets it (a frame's matrix for the slabs, the identity for the items), so the fragment's world position is right for the haze.
- `begin_flat_batch :: proc(renderer: Model_Renderer)`: nothing unless `flat_batch_ready`; `rl.BeginShaderMode(renderer.material.shader)` (it flushes what the batch holds under the shader before), then `set_model_instancing(renderer, false, false, true)`.
- `end_flat_batch :: proc(renderer: Model_Renderer)`: nothing unless `flat_batch_ready`; `rl.EndShaderMode()` (the flush, flat on), then `set_model_instancing(renderer, false, false, false)`.
- Comment over the pair: decision 2's reason and decision 4's rule (no `DrawMesh`, instanced draw or switch through the model shader in between).
- Header: the flat mode is hazed, and rlgl's batch takes it through `begin_flat_batch`.

`src/render_frames.odin`
- `draw_foundation_edges`, the path without `draw_lines_instanced`: `begin_flat_batch(models)` before the cells' `DrawCubeWiresV` loop, `end_flat_batch(models)` after it.
- Header: "through the model shader unlit (begin_flat_instances)" becomes "unlit and hazed".

`src/render_belt_runs.odin`
- `draw_belt_runs`: `begin_flat_batch(draw.models)` before `draw_belt_poles`, `end_flat_batch(draw.models)` after the runs' loop and before `draw_belt_run_items`, whose instanced draw sets the switches itself. A zero `Belt_Run_Draw` keeps today's draw.
- Header: the runs and poles go through the model shader's flat batch, hazed (0360).

`src/loop_field_session.odin`
- `draw_field_torches :: proc(torches: []Field_Torch, spacing_millimetres: int, models: Model_Renderer)`: the loop between `begin_flat_batch(models)` and `end_flat_batch(models)`; `draw_field_scene` passes `scene.models`.
- `draw_field_scene`'s comment: the slabs, the runs, the poles, the belt items, the torch boxes and the emissive layers draw flat through the model shader and are hazed as the machines (0360).

`src/render_entities.odin`
- `draw_entities`: `flat := model_frame_flat_batch(frame)`; when `flat`, `begin_flat_batch(models)` before the chests' loop and `end_flat_batch(models)` before the foundations' loop, and again round the vessel parts' loop. The comment says why the foundations' pool stays out (the pod's `DrawMesh`). The sun's pass (no view) and the block world (neither) draw as today.

### Tests

`src/shader_source_test.odin`, `test_the_flat_mode_takes_the_haze` (0360):
- `model.vs` (`read_tree_shader`) holds `\nin vec2 vertexTexCoord;\n`, `\nuniform float flat_on;\n`, `\nout vec2 fragment_texcoord;\n`, `    fragment_texcoord = vertexTexCoord;\n` and decision 2's two lines exactly.
- `model.fs` holds `\nin vec2 fragment_texcoord;\n` and `\nuniform sampler2D texture0;\n`; its `void main(` (`shader_function_text`) holds the `unlit` line and the `finalColor` line of the flat branch exactly, `    bool outdoor = outdoor_on > 0.5;\n` before `    if (flat_on > 0.5) {\n`, and no `finalColor = base;`.
- The existing tests cover the rest: `apply_haze` equal in the four shaders, the bare integers, the reserved words.

`src/render_model_instances_test.odin`, `test_only_the_scenes_collecting_pass_draws_its_batch_flat`: `model_frame_flat_batch` is true with a view and an instance list, false with a view alone (the models draw by `DrawMesh`), false with an instance list and `casters` set but no view (the sun's pass), false for the zero frame.

### Docs

- `doc/presentation.md`, Light on the field, the haze bullet: its last two sentences become: "The foundations' slabs and their edges, the machines' emissive layers, the runs and poles, the belt items, the items an arm holds, the torch boxes and the vessel parts' boxes take the same haze, unlit, through the model shader's flat mode (0360, Machine models); the flames, the debris and the pod's emissive layer stay unhazed (about 8 percent at the trees' 128 m at the radius's height). The slabs, the machines, the runs, the poles and the belt items are not drawn past the haze's end (`Model_View`, 0347), where the end fade has already brought all of them to the end colour, so nothing pops there."
- `doc/presentation.md`, Machine models, the instanced path bullet: "with `flat_on` draws the emissive layer, the slabs and the belt items unlit, as raylib's default shader does" becomes "with `flat_on` draws the emissive layer, the slabs and the belt items unlit, the vertex colour times the colour and `texture0` as raylib's default shader does, hazed on the open sky (0360)"; then: flat without `instanced_on` is rlgl's batch through the model shader (`begin_flat_batch`: the runs and poles, the torch boxes, and in the scene every pool of `draw_entities` but the foundations', whose pod draws by `DrawMesh`), whose vertex `model.vs` takes as its world position (decision 2's reason in one clause); a model shader without `texture0` leaves those to raylib's default shader, unhazed, with one log line (`Model_Renderer.flat_batch_ready`).
- `doc/presentation.md`, Runs, the culling bullet: the runs and poles draw through the model shader's flat batch, the items unlit and hazed, as the slabs (0360).
- `doc/code_map.md`, the `render_model_instances.odin` line: the flat batch through the model shader (`begin_flat_batch`, `model_frame_flat_batch`, 0360).

### Hand-back check

- Memory a frame draws from: nothing is freed, replaced or added; no buffer or arena changes.
- A start-up load the game can make fail: an overlay `model.vs` or `model.fs` from before 0360 has no `texture0`, so `flat_batch_ready` is false with one log line and the batch draws through raylib's default shader as today; the instanced flat draws stay unhazed under the old flat branch. Nothing exits.
- Tests touch no machine state: shader text read from `data/shaders`, a frame in memory.
- Not applicable: file writes, parsed numbers, save, record and network layouts, shared budgets, lists reaching the HUD, UI audit cases.

### Rejected

- A CPU haze in the batch's vertex colours: a second `apply_haze` in Odin to keep in step, and a vertex colour multiplies the belt's texture, so it cannot lift it towards the sky.
- A shader of the batch's own: a fifth `apply_haze` and another load and fallback path for the same colour.
- The runs, poles and torch boxes as meshes or instances: a rewrite of the swept runs (scrolled per frame, both windings) for a colour.
- Ending them with the view by alpha or dither, as the cards end: unhazed inside the view, off the machines on them, and alpha needs sorting.
- A fourth uniform for the batch: flat without instancing already says it, and `instancing_ready` keeps its three.
- `matModel` set to the identity before the batch: rlgl writes it again at every flush.
- The whole of `draw_entities` in one flat batch: the pod's `DrawMesh` would read `flat_on` at 1.
- The end fade alone on the flat draws: a slab would read clearer than the machine on it from 30 m on, and the item asks for both.

### Captures (taken by the main agent)

At noon, paused, before (`main`) and after (the item's build); the runs and the torches go in by their tools through 0341's input commands, since `place` refuses runs.
- A, the fade: `view_distance 256`, 0347's `factory_large` with a few runs between its pads, a pole each and torches on its far pads, the eye about 20 m up and 200 m from its near edge so it spans 154 to 256 m. Before: the slabs, edges, runs, poles, glows and torch boxes in their own colours on the faded ground, ending on a step at 256 m. After: they fade with the machines, no step.
- B, the item's: the same from 300 m: the factory culled whole before and after (0347), the ground alike (question 3).
- C, near: 0342's `factory` view at 1024 m: alike before and after within the aerial haze (at most 2 percent within 30 m); the belts keep their texture and scroll.

### Questions to the main agent

1. The flat batches in `draw_entities` (the held items, the vessel parts' boxes, the fallback boxes) go past the item's list. The vessel parts are boxes until their models and stand among a factory's machines; a held item (0.2 m) is about a pixel at 1080p at the shortest view's fog start (154 m). Recommendation: keep (two pairs of calls and a pure gate). Declined: strike that bullet, `model_frame_flat_batch` with its test, and those words in the docs.
2. The pod's emissive layer stays unhazed: 0347 keeps the pod on `DrawMesh` with raylib's default material for that layer (decision 5 gives no reason I found), and a `DrawMesh` in the flat mode would meet decision 2's batch rule. Its portholes and screens show unfaded from 154 m until its box passes the view, as today. Recommendation: leave it here, a new item if the captures show it.
3. Since 0347 a factory wholly past 256 m is culled before and after, so the Verify's capture at 300 m shows only the ground in both. Recommendation: add capture A (about 200 m out, spanning the fade), where before and after differ, and keep B as the item asks.

### Decisions (main agent, 2026-11-12)

1. The batch draws of `draw_entities` (held items, vessel part boxes, fallback boxes) go into the flat batches as specified.
2. The pod's emissive layer stays unhazed. A new item if a capture shows it.
3. The captures: the profile's factory pad placed so it spans the fade at a 256 m view (about 200 m out), before and after, and a near factory that must not change. Slabs and machines through `place` are enough; runs and torches are not laid for the capture. The 300 m capture is dropped: since 0347 it shows ground both times.
4. This item is 0347's fallout (its decision 1) and was started for that reason on 2026-11-12.
