# Presentation

What the game draws and plays. It reads the world, the tick, the render time and the camera; the simulation never reads it back, and nothing here is saved (render state lives in `Frame_State` and resets with the session). Texture and sound values: [content.md](content.md).

- Every pass follows the no perceivable repetition principle ([DESIGN.md](../DESIGN.md)).
- Values (sizes, periods, rates, colours) are the constants atop each file named below.

## Frame order

Inside the 3D pass, in order: the sky, the solid chunks, entities and models, the bottleneck markers, fluid and power entities, belts, loose items, torch flames, fish shadows, the water pass, birds, insect motes, particles, weather, the player overlay. Then the hands, the underwater tint, the HUD and the UI (`loop.odin`).

## Chunk meshes

- Greedy meshing per chunk over the block atlas, remeshed on edit, culled per chunk. Only cubes join the greedy pass; slabs, stairs, posts and crosses mesh cell by cell, a border quad hidden by an opaque neighbour dropped.
- Texcoords run in blocks and repeat with `fract()` (`face_texcoord`); on side faces y runs down from the face's top, so a tile's top row is up on every side and a slab side shows the lower half.
- Water faces go to separate parts (`Chunk_Mesh_Data.water_parts`); lit posts become flame cells (`render_flames.odin`).
- Fog in the horizon colour ends one chunk inside `LOAD_RADIUS_HORIZONTAL` (`fog_distances`), so chunks fade into the sky.

| Vertex data | Carries (`world_mesh_light.odin`) |
|---|---|
| Colour red | Sky light |
| Colour green | The face's `Tile_Variation` (`orientation_flag_green`) |
| Colour blue | Ambient occlusion |
| Colour alpha | `SWAY_VERTEX_ALPHA` for vertices the wind sways (`sway_vertex_light`) |
| Normal | Red, green and blue block light (`block_light_normal`) |

- Sky light is scaled by the day factor and tinted by the sky tint; block light keeps its colour and takes one flicker for all lights (`light_flicker`), which stands still under reduced motion (`flicker_seconds`), as do the torch flames.
- Models light the same way without the flicker (`model_light_tint`).

## Textures

- The block atlas has a 16 by 16 tile per block and face group: generated for the blocks in `data/textures/procedural.sjson` with the texture editor's edits over them (`texture_generate.odin`), else from `data/textures/blocks/`, else the block's colour (`render_atlas.odin`). Item icons have their own atlas (`render_icons.odin`).
- Every texture goes up through `load_rgba_texture`, which converts a copy of any non RGBA image first: raylib uploads gray and gray alpha images with a texture swizzle that Winlator's Gladio drops, and they sample red on the phone (0106). Fonts are built as raylib's `LoadFontEx` does, with the glyph atlas through the same procedure (`ui_font.odin`).

### Per block variation

Rule: a tile never repeats identically from block to block (0088). `texture_variation.odin` mirrors the shader's choice for the tests.

- A hash of the block's integer position (the cell a hundredth of a block behind the face, so a face on a block boundary reads one cell) picks one of eight orientations of the tile (a mirror of x, then zero to three quarter turns), a whole texel slide wrapped inside the tile, and a brightness jitter (`TEXTURE_BRIGHTNESS_JITTER`).
- The slide keeps mirrored neighbours from forming a symmetric motif; a sliding tile must be periodic (`texture_periodicity_test.odin`).
- `face_tile_variation`: side faces of `keep_orientation` blocks stay upright and unshifted; faces of `framed` blocks (the log ends) turn and mirror but never slide.
- Water takes the jitter only: its tile keeps its orientation for the flow and needs no offset, being isotropic.

## Shaders

- `data/shaders/` holds `chunk.vs`, `chunk.fs`, `water.vs` and `water.fs`, GLSL 330. The chunk shader applies per vertex light and occlusion and discards texels with alpha below 0.5 (ground cover, the torch).
- Every integer literal carries the `u` suffix: Gladio appends `.0` to every bare integer on a line with a float variable (`hash >> 8` becomes `hash >> 8.0`, which does not compile). `shader_source_test.odin` fails on a bare integer literal (0105).
- `load_shader_pair` loads from memory and tries up to `SHADER_LOAD_ATTEMPTS` times, logging `shader: <name> failed to load, attempt <n> of 3`, since Gladio fails a compile now and then and succeeds on the next try. Nothing is released between attempts: a failed load returns raylib's default shader, which must never be unloaded.
- On Android `shader_source_for_gles` turns `#version 330` into `#version 300 es` with `precision highp float;` and `precision highp int;` for the 32 bit integer hashes. The four shaders, rewritten so, pass `glslangValidator` (`sudo dnf install glslang` in the Android container).

## Sky and day

- `render_day.odin` derives the frame's `Day_Sky` from the tick and the day length. The clear colour is the horizon colour, which shows below the dome.
- The sky pass (`render_sky.odin`) draws first without depth test or writes: a dome recoloured each frame, hashed stars, the sun, and the moon with its phase. Discs face the camera along their own direction (`disc_axes`), since raylib's billboards squash a disc high in the sky into an ellipse.

## Weather

- `weather_at(seed, tick, day_length_ticks)` (`weather.odin`) is a pure schedule, not state: each game hour gets a kind (`weather_kind_weights`) and a peak intensity from a hash of the seed and the hour, ramped at the hour's ends. Rain over a column colder than `SNOW_TEMPERATURE` falls as snow.
- `render_weather.odin` blends each look value from clear to the kind's by the intensity: fog distance, sky gloom, wind and cloud shadow (`weather_fog_scales`, `weather_glooms`, `weather_wind_strengths`, `weather_cloud_shadow_strengths`). Rain darkens the sky tint (wet ground).
- The renderer reads the weather once per frame (`session_weather`): the `weather` command's forced kind (`Session.weather_override`) wins, and with the Weather setting off it is clear.
- The fog distance, rain, snow, sway and cloud shadows need the Weather setting on and reduced motion off (`weather_motion_enabled`); under reduced motion the sky still greys and the rain is still heard.
- Rain and snow wrap into a cylinder around the camera, counted by the intensity and the sky light at the camera, so none fall under a roof. The chunk shaders sway plants by the wind and dim sky light by a drifting noise texture, without shadows at night.

## Water pass

`render_water.odin` (0065).

- Water parts carry per vertex the cell's flow direction (downhill, zero for a source) and a shore value; both are part of the greedy face key, so water merges only where they match.
- `draw_water_chunks` uses its own material (`water.vs`, `water.fs`, sharing the atlas, hot reloaded with the chunk pair): alpha blending, depth test on, depth writes and backface culling off. The shader scrolls ripples over world x and z, runs the texture along the flow and lays a foam band along the shore.
- With the camera in water both materials take an underwater fog and a tint covers the view.

## Ambient life

`ambient_life.odin` (pure) and `render_life.odin` (drawing), 0075: a function of the world seed, the tick, the render time and the camera. Depth tested without depth writes. Biome densities are in [content.md](content.md).

- Birds: a world aligned grid of flock cells holds a flock where a hash lies below the `bird_density` of the biome at the loop's centre. A flock flies a rounded rectangle above the surface (`sample_column`) on tick time (`loop_seconds`), so it is at the same place at the same tick on every run. Every period and phase comes from a hash of the flock and the bird.
- Birds draw only by day and not in heavy rain (`life_presence`).
- Insects: one in `INSECT_FLOWER_SHARE` cells of a block a ground cover marks with `insects` gets motes on Lissajous paths (`Chunk_Render.covers`), by day.
- Fish: source water cells under an open cell with water two cells deep (`water_surface_cell`; the mesh shell reaches past the chunk, so the sea surface on a chunk's bottom layer counts); `apply_chunk_mesh` keeps one in `FISH_CELL_SHARE` (`Chunk_Render.fish`). A shadow glides a lemniscate below the surface, drawn before the water pass so the surface tints it.

## Particles

`particles.odin`, `render_particles.odin` (0067).

- A pool of `PARTICLE_CAPACITY` whose next index wraps, so a new particle replaces the oldest. Each `Particle_Kind` has its gravity, drag, launch speed, lifetime and growth; the step is the frame time capped at `PARTICLE_MAXIMUM_FRAME_SECONDS`.
- `emitters_for_frame` reads the working machines and the digging player; a fraction of a spawn rounds by a hash of the frame and the cell, so no emitter keeps state.
- `Particle_Memory` keeps the last dig (a break bursts) and shipment count (a new shipment drops a capsule under a parachute).

## The player

`player_animation.odin`, `render_player_model.odin`, `render_player.odin` (0066).

- Six limb models (`data/models/player_*.vox`), each the whole frame with its limb filled, swing about pivots read from the voxel bounds; without them a capsule stands in.
- The walk phase is a cadence distance summed tick by tick from `distance_walked_millimetres`, divided by the cheat speed factor so the cheat never quickens steps or bob (`WALK_CYCLE_MILLIMETRES`).
- The mine chop runs on the render time while `Mining_State.active`; a place swing starts when the placed counters (`placed`, `blocks_placed`) grew.
- Whether the player moves is decided per new tick, not per frame, so a display faster than the tick rate does not stop the walk every other frame.
- First person draws the right arm and the held stack in a second 3D pass with the depth test off; third person draws the body at the interpolated pose.

## Machine models

- A machine names a MagicaVoxel file in `data/models` by its `model` key (`model_vox.odin`: the first model's `SIZE`, `XYZI` and `RGBA`, z up mapped to y up), meshed once with a shade per face direction (`model_mesh.odin`) and drawn scaled to the footprint (`render_models.odin`). A machine without a model keeps the box `draw_entity_cells` draws; every machine but belts and pipes has one.
- A model takes the world light of one cell above its footprint's centre (in front of a 1 by 1 machine). Palette indices from `EMISSIVE_PALETTE_START` glow; an optional `<model>_part.vox` moves per the machine's `motion` from the tick and entity state (`model_motion.odin`).
- `tools/make_placeholder_models.py` writes the placeholder models deterministically; rerun it after changing it and commit the files.

## Sound

`audio.odin` (mixer), `sound_events.odin` (triggers), 0068.

- Without an audio device every call is a no op. The mixer loads `data/sounds/sounds.sjson`: effects as `Sound`, never twice within `EFFECT_MINIMUM_GAP_SECONDS` (raylib replays a `Sound` on one voice), loops as `Music` fading to the frame's target over `LOOP_FADE_SECONDS`, so a loop nobody asks for fades out.
- Loops and ambience calls follow the ambience volume, other effects the effects volume, all the master volume.
- The triggers compare the world with `Sound_Memory` (the first frame of a session only learns): footsteps per half walk cycle by the material underfoot, mining hits per dig quarter by tool tier (at most `MINING_HIT_MAXIMUM_PER_SECOND`), break, place, launch, landing, the discovery chime, the UI sounds (`ui_sound_ids`).
- Hum: the nearest working machine (as the bottleneck markers define working) within `HUM_RANGE_BLOCKS` picks its family (fluid, electric, burner), with a drifting level.
- Ambience: the biome under the player picks a loop, or variants `ambience_<name>_1`, `_2` played in clusters of calls with long hashed pauses; a `day_only` ambience calls only by day.
- Rain plays at the intensity times the open sky at the eye; snow is silent.
