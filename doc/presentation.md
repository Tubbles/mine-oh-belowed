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

### Field meshes

The terrain field (M13) is drawn beside the blocks, for now only by the planet preview (`--planet-preview`, `loop_planet_preview.odin`, [build.md](build.md)).

- Mesher (`world_field_mesh.odin`): naive surface nets over a `Field_Grid`, the samples of a node and one more on every side. A cell the surface crosses gets one vertex at the mean of its edge crossings (linear in the `i8` densities, in 1/`FIELD_MESH_POSITION_UNITS` of a cell, integer throughout); each grid edge the surface crosses that starts inside the node becomes a quad between the four cells around it, wound against the density gradient. The quads reach the cells one step below the node, which the neighbour computes from the same samples, so neighbours of one level meet without a gap. Floats appear only in `field_mesh_from_surface`, the GPU's arrays.
- Per vertex: the normal against the cell's gradient (the density's change across the cell); the material weights, the share of the cell's ground corners per material (`Field_Surface_Vertex.weights`, four bytes, one per material slot, uploaded as the tangent attribute; the slots are topsoil, stone, deep stone and bedrock, and the ores of the veins' outcrops (0179) count as stone, `field_material_slot`, until the renderer takes more slots); the colour, the mean palette colour of the ground corners, the tint taken modulo the palette's length since a saved tint is not checked; the vertex light (0173, `field_vertex_light`): the mean of each channel of the field light over the cell's air corners (ground holds no light, so counting it would halve every surface's light), the sky light in the colour's alpha and the block light in the texture coordinate's first component (`Field_Mesh_Data.lights`, the one raylib attribute the field leaves free). The water's mesh takes the terrain's light at the same corners. A coarse grid takes the light of the loaded samples it reads and gives a generated sample full sky light in air and none in ground, as the generation does ([architecture.md](architecture.md), The field light).
- Level of detail (`world_field_lod.odin`): an octree over field chunks, a node of level L covering 2^L chunks a side and sampling every 2^L-th sample, so every node meshes 32 cells a side. `select_field_nodes` walks down from the 27 nodes around the camera of the first level as wide as the last distance, splitting every node that crosses the surface shell and lies within the last distance (about 4,000 visits a frame at 1 m spacing and 40,000 at 333 mm with a 4096 m view), and from the coarsest level on splits wherever `field_level_for_distance` asks for a finer level, against `field_view.level_distances_metres` of `data/game.sjson` (64, 160, 384 and 1024 m: full, half, quarter, eighth resolution; rising, at most `MAXIMUM_FIELD_VIEW_DISTANCE_METRES`, `field_view_problem`); nodes outside the shell the relief can reach and beyond the last distance are skipped. The finest level meshes from the loaded chunks; the coarser ones take the samples of the loaded chunks their grid reads and generate the rest from the planet on the worker (`generate_field_grid`), so an edit shows at every level ([architecture.md](architecture.md), Threads and chunk streaming). A loaded sample enters the coarse grid as its density over the step, except a saturated one on the generation's side of the surface, which keeps the generation's coarse density (`coarse_field_sample`). A coarse grid holds its densities in units of its own spacing (`field_grid_generation`): the planet's density saturates one spacing from the surface, so in the fine spacing a coarse edge would read full density at both ends and the slopes would terrace.
- Seams: a node's surface runs from half a cell below its origin to half a cell before its far border, so where a coarser node lies on its negative side a strip up to half a coarse cell wide between the two meshes is open from above. A node's mesh hangs an L shaped flap from its open border on the faces that border a coarser node or none (`field_node_skirt_faces`, carried by the mesh job; 0173's fix round), never between nodes of one level, which meet without a gap and where a straight leg leaving a curved surface (a dug pit's rim across a chunk border) stood in the air as a flat flap (`append_field_skirts`): from each border vertex one coarse cell (two cells) out of the node along the surface's slope and half a coarse cell below it, then a coarse cell further into the ground along the gradient. The outward leg covers the strip whichever side the coarser node is on; following the slope a little below the surface, it neither stands above the neighbour's ground nor fights it in depth. Each band continues the surface's winding, so it faces out of the node. The streaming keeps each node's skirt faces with its revision and meshes a node again when they change (a neighbour split or merged), so no seam opens when a neighbour's level changes. A node whose skirts would pass the u16 indices is drawn without them and logged, which `FIELD_MESH_VERTEX_BOUND` rules out for today's grid.
- Water (0172): the same job meshes a node's water as a second surface from the same grid (`mesh_field_water_grid`), the mesher over the water as a density (`field_water_density`: the water's level over the sample's own distance in the terrain's scale, a signed distance to the surface wherever the sample sits in its cell, so a level surface crosses every grid edge at its level, on the axes and off them; full water on an axis is +64, empty -64, and ground -127, so the water's surface closes against the terrain, which the terrain mesh covers). A coarse grid takes the water of the loaded chunks it reads through `coarse_field_water_density` (full water or empty air on the generated sea's side keeps the generated density, anything else is its density over the step) and the sea level rule elsewhere (`planet_sea_density`, the depth below the sea level in the grid's spacing, -127 in ground), which crosses at the same radius as the fine sea (`test_the_fine_and_coarse_sea_cross_at_one_radius`), so the sea shows at every level. The water has no skirts: its open border also runs along its faces against the ground, where a skirt would stand up out of the water as a fin, so the strip between two levels of detail stays open on water. Fill below half a sample has no surface of its own. One job, not a second one, so the water never lags the terrain it lies on and one revision covers both.
- The water pass (`draw_field_water`): after every node's terrain, the water meshes of the visible nodes through the field shader with `water_color` set (`FIELD_WATER_COLOR`: colour and opacity), alpha blended, without depth writes, and with the back faces culled, so the water's faces against the ground, which face into it, are not drawn and the water is not seen from below yet.
- The globe: drawn every frame before the nodes, a sphere in the palette's first colour `FIELD_GLOBE_MARGIN_METRES` below the lowest relief (`field_globe_radius_metres`), so the nodes cover it where they exist and it fills the planet's silhouette beyond the last distance (`draw_field`).
- The field shader (`data/shaders/field.vs`, `field.fs`, `render_field.odin`): each material's tile projected along the three axes and blended by the absolute normal to the fourth power, read at two scales 2 m and e times that apart so the tile's period never shows, the materials blended by the vertex weights (every material sampled at every fragment, since a mipmapped sample inside a branch has no defined derivatives where a pixel quad straddles a zero weight), the tint multiplied in (times two, the tiles being mid tones), the vertex light (the brighter of the block light and the sky light times the `daylight` uniform, `Field_Renderer.daylight`, 1 until the day cycle of 0179 sets it; the planet preview's `--planet-preview-daylight`) and a gentle sun term (`FIELD_SUN_DIRECTION`) on top, fog to `FIELD_FOG_COLOR` from `FOG_START_SHARE` of the last distance. With the `water_color` uniform's alpha above zero (the water pass) the surface takes its colour instead of the materials and its alpha as its opacity; the terrain pass sets it to zero, and the water is lit by the same vertex light and daylight. Point lights of working parts (0175, `render_point_lights.odin`) come on top of the field's light and never in its place: the renderer keeps the `MAXIMUM_POINT_LIGHTS` (8) nearest the camera (`nearest_point_lights`) and uploads their positions, radii and colours before `draw_field` (`set_field_point_lights`); the shader adds the albedo times each light's colour, falling off smoothly to nothing at its radius and half of it regardless of the facing, so the light is soft. Unused slots have radius 0 and come last, so the loop stops at the first one. The water pass, drawn through the same shader, takes the point lights too. Only the planet preview gathers them so far (its arms).

## Textures

- The block atlas has a 16 by 16 tile per block and face group: generated for the blocks in `data/textures/procedural.sjson` with the texture editor's edits over them (`texture_generate.odin`), else from `data/textures/blocks/`, else the block's colour (`render_atlas.odin`). Item icons have their own atlas (`render_icons.odin`).
- The field's materials (topsoil, stone, deep stone, bedrock and the ores hematite, chalcopyrite and coal of 0179) each get one tile generated by `generate_ore_tile` from `data/textures/field_materials.sjson` (`texture_field_materials.odin`, `FIELD_MATERIAL_TILE_COUNT`): flecks over a ground colour, crystal size 1, so the tile is isotropic and the triplanar projection shows no stripes. They go up with mipmaps, trilinear filtering and repeat wrapping, one texture per material on the material's maps in the materials' order; the shader samples the first four (`FIELD_TEXTURED_MATERIAL_COUNT`), so the ores' tiles are uploaded but drawn as stone until the shader and the vertex weights take them.
- Every texture goes up through `load_rgba_texture`, which converts a copy of any non RGBA image first: raylib uploads gray and gray alpha images with a texture swizzle that Winlator's Gladio drops, and they sample red on the phone (0106). Fonts are built as raylib's `LoadFontEx` does, with the glyph atlas through the same procedure (`ui_font.odin`).

### Per block variation

Rule: a tile never repeats identically from block to block (0088). `texture_variation.odin` mirrors the shader's choice for the tests.

- A hash of the block's integer position (the cell a hundredth of a block behind the face, so a face on a block boundary reads one cell) picks one of eight orientations of the tile (a mirror of x, then zero to three quarter turns), a whole texel slide wrapped inside the tile, and a brightness jitter (`TEXTURE_BRIGHTNESS_JITTER`).
- The slide keeps mirrored neighbours from forming a symmetric motif; a sliding tile must be periodic (`texture_periodicity_test.odin`).
- `face_tile_variation`: side faces of `keep_orientation` blocks stay upright and unshifted; faces of `framed` blocks (the log ends) turn and mirror but never slide.
- Water takes the jitter only: its tile keeps its orientation for the flow and needs no offset, being isotropic.

## Shaders

- `data/shaders/` holds `chunk.vs`, `chunk.fs`, `water.vs`, `water.fs`, `field.vs` and `field.fs`, GLSL 330. The chunk shader applies per vertex light and occlusion and discards texels with alpha below 0.5 (ground cover, the torch).
- Every integer literal carries the `u` suffix: Gladio appends `.0` to every bare integer on a line with a float variable (`hash >> 8` becomes `hash >> 8.0`, which does not compile). `shader_source_test.odin` fails on a bare integer literal (0105).
- `load_shader_pair` loads from memory and tries up to `SHADER_LOAD_ATTEMPTS` times, logging `shader: <name> failed to load, attempt <n> of 3`, since Gladio fails a compile now and then and succeeds on the next try. Nothing is released between attempts: a failed load returns raylib's default shader, which must never be unloaded.
- On Android `shader_source_for_gles` turns `#version 330` into `#version 300 es` with `precision highp float;` and `precision highp int;` for the 32 bit integer hashes. The chunk and water shaders, rewritten so, pass `glslangValidator` (`sudo dnf install glslang` in the Android container).

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

`ambient_life.odin` (pure) and `render_life.odin` (drawing), 0075: a function of the world seed, the tick, the render time and the camera. Depth tested without depth writes. Biome densities are each biome's `bird_density` in `data/biomes.sjson`.

- Birds: a world aligned grid of flock cells holds a flock where a hash lies below the `bird_density` of the biome at the loop's centre. A flock flies a rounded rectangle above the surface (`sample_column`) on tick time (`loop_seconds`), so it is at the same place at the same tick on every run. Every period and phase comes from a hash of the flock and the bird.
- Birds draw only by day and not in heavy rain (`life_presence`).
- Insects: one in `INSECT_FLOWER_SHARE` cells of a block a ground cover marks with `insects` gets motes on Lissajous paths (`Chunk_Render.covers`), by day.
- Fish: source water cells under an open cell with water two cells deep (`water_surface_cell`; the mesh shell reaches past the chunk, so the sea surface on a chunk's bottom layer counts); `apply_chunk_mesh` keeps one in `FISH_CELL_SHARE` (`Chunk_Render.fish`). A shadow glides a lemniscate below the surface, drawn before the water pass so the surface tints it.

## Cues

`cues.odin` (0162).

- Once a frame per viewport (split screen, 0178), before the player's animation, `observe_cue_counters` reads the counters of the viewport's player and the records, and `detect_cues` compares them with `Cue_Memory` (the last frame's): the walked distance, the placed counters (`placed_total`), `blocks_mined`, the dig (`Mining_State`) and the block now at its cell, the blocks at and under the feet, the launching pads, the shipments and the quest messages.
- It returns `Frame_Cues`: a bit set of `Cue` (footstep, place, block break, dig break with its cell and block, dig quarter, launch, shipment, discovery, survey) and the walk (cadence distance, moving) with the blocks at the feet.
- The first frame of a session only learns the counters, so a loaded world neither steps, swings, chimes nor drops a capsule.
- The walk is followed per tick, not per frame, so a display faster than the tick rate neither stops the walk every other frame nor steps twice: a footstep fires once per half walk cycle of the cadence distance, which counts each tick's walk divided by the cheat speed factor, so the cheat never quickens steps or bob (`WALK_CYCLE_MILLIMETRES`).
- The landing is not a counter: the particles add `Landing` to the frame's cues when the capsule descent ends, before the sounds read them.
- The player's animation, the particles and the sounds read the cues and keep only their own state between frames.

## Particles

`particles.odin`, `render_particles.odin` (0067).

- A pool of `PARTICLE_CAPACITY` whose next index wraps, so a new particle replaces the oldest. Each `Particle_Kind` has its gravity, drag, launch speed, lifetime and growth; the step is the frame time capped at `PARTICLE_MAXIMUM_FRAME_SECONDS`.
- `emitters_for_frame` reads the working machines and the digging player; a fraction of a spawn rounds by a hash of the frame and the cell, so no emitter keeps state.
- Read from the cues (Cues): a dig break bursts, a shipment drops a capsule under a parachute (`Particle_Memory` keeps the descent and the survey satellite's pass), a footstep kicks up dust.

## The player

`player_animation.odin`, `render_player_model.odin`, `render_player.odin` (0066).

- Six limb models (`data/models/player_*.vox`), each the whole frame with its limb filled, swing about pivots read from the voxel bounds; without them a capsule stands in.
- The walk phase is the cues' cadence distance (Cues).
- The mine chop runs on the render time while `Mining_State.active`; a place swing starts on the place cue.
- First person draws the right arm and the held stack in a second 3D pass with the depth test off; third person draws the body at the interpolated pose.

## Machine models

- A machine names a MagicaVoxel file in `data/models` by its `model` key (`model_vox.odin`: the first model's `SIZE`, `XYZI` and `RGBA`, z up mapped to y up), meshed once with a shade per face direction (`model_mesh.odin`) and drawn scaled to the footprint (`render_models.odin`). A machine without a model keeps the box `draw_entity_cells` draws; every machine but belts, pipes, foundations and belt poles has one.
- A model takes the world light of one cell above its footprint's centre (in front of a 1 by 1 machine). Palette indices from `EMISSIVE_PALETTE_START` glow; an optional `<model>_part.vox` moves per the machine's `motion` from the tick and entity state (`model_motion.odin`).
- `tools/make_placeholder_models.py` writes the placeholder models deterministically; rerun it after changing it and commit the files.
- The pod (0179, `pod.vox`, `pod()`): 48 by 64 by 48 voxels over its 6 by 8 by 6 cells, a white hull of about 3 by 3 by 4 m on a base plate with an orange band and roof, windows on the sides, a door opening on the front (+x, turned to the frame's forward by `place_pod`) and a bed inside. It loads with the machine models, but the frame renderer still draws a frame's machines as a box per cell (`draw_frames`), so the pod shows as its model only once models are drawn on frames.

### The arm

The inserter's arm (0175, `model_arm.odin`, `render_arm.odin`), the first model at real scale; it replaced the inserter's miniature crane.

- Files: `tools/make_placeholder_models.py` (`arm()`) writes six, `arm.vox` (the base) and `arm_turret.vox`, `arm_upper_arm.vox`, `arm_forearm.vox`, `arm_gripper.vox`, `arm_finger.vox` (`arm_part_suffixes` after the model's name), each the whole `ARM_MODEL_FRAME` (24 by 128 by 24 voxels) at `ARM_VOXEL_MILLIMETRES` (25) with only its part filled, standing in the authored pose: straight up, fingers up, the joints on the frame's vertical centre line, the shoulder 22 voxels up (0.55 m), the elbow 50 above it (1.25 m), the wrist 42 above that (1.05 m) and the hand between the fingertips 12 above the wrist (0.3 m), as `model_arm.odin` has them in metres. A machine with `motion = {kind = "arm"}` loads them all with the machine models (`load_arm_part_meshes`, into `Machine_Model_Mesh.arm`, one mesh per part and layer) instead of a body and a part; a missing or misshaped file refuses the models as any model does. Grimy steel and yellow warning paint with black hazard stripes; a work lamp (emissive) on the wrist block.
- Joints: the turret turns about the vertical (yaw), the upper arm about the shoulder, the forearm about the elbow and the gripper about the wrist, all about the arm's sideways axis; the finger is drawn twice, offset either side of the gripper by the grip (open `ARM_FINGER_OPEN_METRES`, closed `ARM_FINGER_CLOSED_METRES`). `arm_part_transforms` chains them from the joint angles; `arm_reach_angles` solves the two segments for a wrist position, the elbow up.
- Scale (`arm_dimensions`): the parts keep their thickness in metres on every frame. The segments together are 2.3 m against the 2 m reach, so the elbow stays bent at full reach (over 40 degrees, `test_the_elbow_stays_bent_at_full_reach`). They scale with the span from the shoulder to the wrist over a cell at the reach, so they are their authored length at 2 m over 500 mm and bend alike on every frame: shorter on the block frame's one metre, longer for the long inserter's 4 m. The hand stops `ARM_WORK_CLEARANCE_METRES` over the top of the target cell, a cell of the frame's pitch. The base plate's width follows the pitch, so the base fills one cell; the inserter's footprint in cells stays one by one by one until the slice's real sizes (0179). `arm_entity_transform` puts the arm on its footprint's bottom centre, turned to the facing, in the frame's cells.
- Animation (`arm_pose_at`): the pose is a pure function of the inserter's cycle fraction (`inserter_cycle_fraction`), so the cadence is the work: rest folded over the base at 0, reach to the pickup cell, grab, swing over the right hand side lifted and drawn in, lower onto the drop cell at one half, release, swing back and fold. An idle arm (nothing to pick) rests folded, an arm waiting for room holds over the drop cell, and an arm out of fuel or power stops mid move. The rest pose (`arm_rest_pose`) stands the upper arm with its elbow just behind the turret's axis and hangs the forearm forward to a wrist within the base for any length of the segments. The held item shows between the grab and the release (`arm_shows_held_item`), since the simulation takes it at the cycle's start. Tests: at rest the elbow, the wrist, the hand and the lamp lie within the base's footprint, and at full reach the hand is over the top of the drop cell and at the grab over the pickup cell, for every facing, on the 500, 333 and 1000 mm frames, the long arm and the block frame.
- Light: the lamp lights only while the arm moves (`Inserter_State.Moving`): at rest its emissive voxels are dark (`ARM_LAMP_DARK_SHARE` of the light round it), while the other machines' emissive voxels keep their old look at rest, lit like the rest of the model. While it moves a point light shines from the lamp (`arm_point_light`, `ARM_LIGHT_COLOR`, `ARM_LIGHT_RADIUS_METRES`) for the field shader (The field shader, above). The block world's renderer takes no point lights.
- Ghosts: an arm's placement ghost is the arm at rest, and its model top (`machine_model_top`) is the folded arm's on the block frame, so the ghost's chevron clears it.
- Without its models an inserter is drawn as the post and bar it had before, in its frame's cells, and the frame renderer draws an inserter's cell as a box unless its arm model loaded.

## Runs

Belt and pipe runs between poles (0176, `render_belt_runs.odin`; the curve: [logistics.md](logistics.md), Runs), drawn by the planet preview after the frames until the slice (0179) draws the field session.

- Swept meshes: one cross section per polyline point (`belt_run_sections`), its up blended from the start frame's up to the end frame's along the run, its right across the tangent (the neighbouring points' difference). A belt run is one quad per subdivision between two sections, a cell of the start frame's pitch wide at `BELT_SURFACE_HEIGHT` of a cell over the polyline, textured with the belt texture, its v counting cells along the run so the stripes keep the block belt's spacing, and scrolled at the run's belt speed as the belt meshes are (`belt_scroll_offset`); its sides hang `BELT_RUN_SIDE_DEPTH_SHARE` of the pitch below the surface, so a run seen edge on reads as a belt. Both windings, like the belt quad. A pipe run is a cylinder of `PIPE_COLOR` per subdivision, its radius `PIPE_RUN_RADIUS_SHARE` of the pitch, lying on the polyline.
- Items on a run stand at their distance through `belt_run_point_at`, offset across the section to their lane by `BELT_LANE_OFFSET` of the pitch, drawn as cubes of their category's colour.
- A belt pole is a post from its cell's bottom to the run end (`draw_belt_poles`); the frame renderer skips its cell.
- The ghost (`draw_belt_run_ghost`): once the run tool's start is picked, the curve to the reticle's candidate as an untextured see-through surface, white, red when the shape would be refused.

## Sound

`audio.odin` (mixer), `sound_events.odin` (triggers), 0068.

- Without an audio device every call is a no op. The mixer loads `data/sounds/sounds.sjson`: effects as `Sound`, never twice within `EFFECT_MINIMUM_GAP_SECONDS` (raylib replays a `Sound` on one voice), loops as `Music` fading to the frame's target over `LOOP_FADE_SECONDS`, so a loop nobody asks for fades out.
- Loops and ambience calls follow the ambience volume, other effects the effects volume, all the master volume.
- The effects follow the cues (Cues): footsteps by the material underfoot, mining hits per dig quarter by tool tier (at most `MINING_HIT_MAXIMUM_PER_SECOND`, paced by `Sound_Memory`), break, place, launch, landing, the discovery chime; the UI sounds follow `ui_sound_ids`.
- Hum: the nearest working machine (as the bottleneck markers define working) within `HUM_RANGE_BLOCKS` picks its family (fluid, electric, burner), with a drifting level.
- Ambience: the biome under the player picks a loop, or variants `ambience_<name>_1`, `_2` played in clusters of calls with long hashed pauses; a `day_only` ambience calls only by day.
- Rain plays at the intensity times the open sky at the eye; snow is silent.
