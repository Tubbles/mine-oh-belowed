# 0200: The arrival: the fall, the flames, the crash, the doors open

Status: verified (2026-10-03, the eight findings fixed, the fall geometry retaken at 45 degrees from 400 m with the window pitched 20 degrees up; implemented 2026-10-03; designed 2026-10-03, approved with two changes; user, 2026-10-03: "when starting a new world the first 10 seconds is falling down towards the planet from an angle, we can see it approaching through a window, and then getting closer and flames start erupt from atmospheric drag, and then a violent crash down and the doors open"; after 0199)

## Goal

A new world opens with the landing. For ten seconds the player sits in the pod and sees the ground come up through the window at an angle, flames tear past as the air thickens, the pod hits hard, and the hatches open. Today a new world starts standing in front of the pod.

## Change

- The arrival is simulation time: the new world's first `arrival_ticks` (600 at 60 Hz, in `game.sjson`) are the fall; the player is seated in the cabin and cannot move; at the last tick the pod's hatches (0198) open through the same toggle every machine runs, so the hash agrees. A loaded save past the arrival and a joiner never see it (the world's tick is past it). The pause menu's Skip ends it early (a command that sets the tick's remaining fall to zero on every machine, so it is lockstep too).
- The presentation draws the pod's descent: the pod model on a straight path from the start point (the crater's up tilted by `arrival_angle_degrees`, the start `arrival_start_metres` above the floor) to its resting place, eased so the last second is the fastest; the camera sits at the cabin window looking along the path, so the terrain comes up at an angle; the planet's terrain under the path is drawn from the field renderer's levels (the coarsest level reaches `level_distances_metres[3]`, 1024 m today, so the start is at most about that high; a view from orbit needs a far level that is not in scope here, say so if the start looks too low to read as a fall and the user picks the height).
- Flames from drag: in the last four seconds a shader effect over the window, rooted in the window's edges, bright at the leading edge, no fixed period (`DESIGN.md`, no perceivable repetition), plus a low roar that rises; at the hit a hard shake of the camera, a dust cloud outside, a crash sound, then silence and the hatch sound as the doors open. Sounds through the cue system (0181 if it has landed, else the block world's cue path).
- The crater (0199) is already there under the pod: the fall ends in it, no terrain changes at the hit.
- `doc/architecture.md` (the arrival: the ticks, the presentation), `doc/content.md` (the arrival's values in `game.sjson`), `doc/ui.md` (Skip), the log.

## Controls

- During the fall nothing moves the player; Pause works, and the pause menu shows Skip arrival. After the hatches open the world's controls are what they are.

## Verify

- The build and check commands of 0168.
- Tests: a new world's player cannot move for `arrival_ticks` and the hatches are closed until the last tick, open after; a joiner at tick 1000 and a save loaded at tick 1000 start with no fall; Skip ends the fall on two sessions at the same tick; the shake and the flames are presentation only (the hash is the same with and without them).
- Headless: a screenshot at tick 300 (mid fall, the ground through the window) and at tick 500 (flames at their height, the hit comes at 540), sent to the user; then the couch.

## Specification (design, 2026-10-03)

Built on `main` at 6169d29 (0198 and 0199 landed). Two new files: `src/simulation_arrival.odin` (simulation cluster by its prefix) and `src/render_arrival.odin` (presentation cluster), with `src/simulation_arrival_test.odin` and `src/render_arrival_test.odin`; two shaders, three sounds. No change to `tools/code_graph.py`.

### The model in one paragraph

The simulation holds one small struct, `Field_Arrival` on `Field_Simulation`: the tick the fall began, its length and the tick it landed. A new world from `start_field_world` begins it; while it falls, every player's input frame is replaced by an empty one, in the tick and in the prediction; at the end of tick `start_tick + fall_ticks` (or at the start of the tick a `Skip_Arrival_Command` applies) it lands: `landed_tick` is set and every closed hatch opens through `toggle_hatch`. It is saved as a table after the felled trees in `entities.bin`, so it is hashed, travels in the join snapshot, and a world loaded or joined past the fall has `landed_tick` set and never falls again. The presentation is a pure function of that struct, the tick and the interpolation alpha (`arrival_view`): a descent phase (the window camera along the tilted path, the pod and the frames hidden, the window overlay with the flames, the roar) and a settled phase after the hit (the shake, the dust, the crash, then the hatch sound when the simulation lands). Nothing in the presentation writes the simulation.

### Timeline at the shipped values (tick 0 is the new world, 60 Hz)

| Ticks | Simulation | Presentation |
|---|---|---|
| 1 to 300 | input held, hatches closed | descent, window overlay, no flames |
| 300 to 540 | input held | descent, flames rise over `arrival_flame_ticks` (240, the last four seconds of the descent), roar rises |
| 540 | input held | the hit: normal first person camera in the closed cabin, shake, crash, roar fades (0.5 s loop fade) |
| 540 to 600 | input held | settled: shake decays, silence |
| 600 (end of tick) | lands: `landed_tick = 600`, both hatches open (`toggle_hatch`, slide over 0.8 s) | hatch sound, dust outside the open doors for 4 s after the hit |
| 601 on | input taken | nothing |

The hit is `arrival_settle_ticks` (60) before the landing so the crash is followed by a second of silence before the doors, as the item's sentence asks ("a crash sound, then silence and the hatch sound"). The simulation's landing stays the last tick of `arrival_ticks`.

### Data (`data/game.sjson`, flat keys after `salvage_percent`, with a comment block naming 0200)

| Key | Shipped | Bounds (`arrival_problem`) | Read by |
|---|---|---|---|
| `arrival_ticks` | 600 | 0 (no fall: the world starts with the hatches closed and no hold, as 0198) or `arrival_settle_ticks + arrival_flame_ticks + 1` to `MAXIMUM_ARRIVAL_TICKS` (3600) | simulation (`begin_field_arrival`) |
| `arrival_settle_ticks` | 60 | 0 to 300 | presentation |
| `arrival_flame_ticks` | 240 | 0 to 1200 | presentation |
| `arrival_start_metres` | 500 | 20 to 4096, and the path length `arrival_start_metres / cos(arrival_angle_degrees)` at most `FOG_START_SHARE * field_view.level_distances_metres[FIELD_COARSEST_LEVEL]` (0.6 x 1024 = 614 m shipped) | presentation |
| `arrival_angle_degrees` | 30 | 0 to 60 | presentation |

The start height bound: the field shader fogs from `FOG_START_SHARE` of the last level distance to all of it (`use_field_shader`, `fog_start`, `fog_end`), and beyond the coarsest level only the unfogged globe is drawn. The camera looks along the path at the crater, so the crater sits at the path's length from the camera; past 614 m it starts in fog, past 1024 m it is not drawn. 500 m at 30 degrees gives a path of 577 m: the crater is clear from the first frame, and the top of the view (about 25 degrees below the horizon at a 70 degree field of view) meets the ground about 780 m past the crater, inside the 1024 m the levels mesh round the resting eye. This is a final approach, not a view from orbit (question 1).

`Game_Config` gains the five `int` fields after `salvage_percent`, with a comment. `validate_game_config` calls `arrival_problem(config)` before its last return.

- `arrival_problem :: proc(config: Game_Config) -> string` (`data_load.odin`, beside `bare_ground_problem`): each bound above with a `fmt.tprintf` naming the key and the range, the path check last ("arrival_start_metres %d at arrival_angle_degrees %d makes a path of %d m, above %d m where the coarsest level's fog starts"), computed in `f64` (load time, not simulation).
- `MAXIMUM_ARRIVAL_TICKS :: 3600`, `MAXIMUM_ARRIVAL_SETTLE_TICKS :: 300`, `MAXIMUM_ARRIVAL_FLAME_TICKS :: 1200`, `MINIMUM_ARRIVAL_START_METRES :: 20`, `MAXIMUM_ARRIVAL_ANGLE_DEGREES :: 60` beside it. `MAXIMUM_ARRIVAL_TICKS` is also the save's bound (below).
- `test_field_game_config` (`player_test.odin`) does not copy the arrival keys, so every existing field test keeps `arrival_ticks = 0` and no fall. The arrival tests set `config.arrival_ticks = 600` and the presentation keys from the shipped file.

### Simulation (`src/simulation_arrival.odin`, new)

File header comment: the arrival (0200), the hold, the landing, Skip, the save table, pointing at architecture.md, The field session, The arrival.

- `Field_Arrival :: struct { start_tick: u64, fall_ticks: u64, landed_tick: u64 }`: the tick the world began the fall (the new world's tick, 0), the fall's length (`arrival_ticks` then, 0 for no fall) and the tick it landed (0 while falling or without a fall; ticks start at 1, so 0 never is a landing). Field of `Field_Simulation` (`field_mining.odin`) named `arrival`, after `felled_trees_recorded`, with a comment: saved in its table, hashed.
- `begin_field_arrival :: proc(field: ^Field_Simulation, tick: u64, fall_ticks: int)`: sets `field.arrival = {start_tick = tick, fall_ticks = u64(fall_ticks)}`. Called in `start_field_world` (`session.odin`) inside `if !plan.loading`, right after `enable_new_field_world`, with `simulation.tick` and `config.arrival_ticks`. Not in `enable_new_field_world`, so the benchmark (`benchmark_factory.odin`) has no fall.
- `field_arrival_falling :: proc(arrival: Field_Arrival) -> bool`: `fall_ticks > 0 && landed_tick == 0`.
- `field_arrival_due :: proc(arrival: Field_Arrival, tick: u64) -> bool`: falling and `tick >= start_tick + fall_ticks`.
- `arrival_input :: proc(arrival: Field_Arrival, frame: Input_Frame) -> Input_Frame`: `Input_Frame{}` while falling, else `frame`.
- `land_field_arrival :: proc(state: ^Simulation_State, content: Simulation_Content)`: `state.field.arrival.landed_tick = state.tick`, then every alive foundations' entry of kind `.Hatch` that is not `hatch_open`, in pool order, through `toggle_hatch(&state.world.entities, content.machines, entry.handle, state.tick, nil)` (opening never checks capsules). The same loop as `open_test_pod_hatches` in `simulation_field_test.odin`; that helper then calls this procedure's loop or stays (it opens hatches without landing; keep it, its comment "as the end of the fall will (0200)" becomes "as the end of the fall does (land_field_arrival)").
- `tick_field_session_players` (`simulation_field.odin`): the frame of each player becomes `arrival_input(state.field.arrival, index < len(inputs) ? inputs[index] : Input_Frame{})` before `pressed[index]` is read; after the refusals loop at the end, `if field_arrival_due(state.field.arrival, state.tick) { land_field_arrival(state, content) }`. So ticks `start + 1` to `start + fall` hold the input (600 ticks) and the hatches open at the end of the last one.
- `Skip_Arrival_Command :: struct { unused: u8 }` (`player_command.odin`, after `Close_Machine_Command`'s declaration, with a comment: the pause menu's Skip arrival, 0200; lands the fall on every machine at the tick it applies), appended last to the `Player_Command` union (after `Inserter_Hand_Command`, so no other variant's tag moves). `apply_player_command`: `case Skip_Arrival_Command: if field_arrival_falling(state.field.arrival) { land_field_arrival(state, content) }`, idempotent, so a second Skip or one after the landing does nothing. `player_command_valid`: in the `return true` case list. It is relayed like every player command (`command_is_relayed`), rides `Input_Record.commands`, and is not saved (the list never is).
- `rebuild_prediction` (`lockstep.odin`): the predicted input is `arrival_input(simulation.field.arrival, stamped.input)`, so a local player's prediction does not walk during the fall either (a block session's arrival is zero, so it changes nothing there).
- `find_pod_frame :: proc(entities: ^Entities, machines: Machine_Registry) -> (frame: Frame, found: bool)` (`entity_pod.odin`, after `field_pod_spawn`): the frame of the first alive pod in pool order, the loop `field_pod_spawn` runs. For the presentation.
- `start_planet_preview_session` (`loop_planet_preview.odin`): after a successful `start_session`, `session.simulation.field.arrival = {}` with a comment (the preview's walk has no fall).

The save table (in `simulation_arrival.odin`):

- `write_field_arrival_table :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation)`: `append_u64` of `start_tick`, `fall_ticks`, `landed_tick`. Called in `write_simulation_state` after `write_felled_tree_table`. Its comment and `write_simulation_state`'s name the table (0200).
- `read_field_arrival_table :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool`: `field.arrival = {}`; with no bytes left it logs `save: written before the arrival (0200), the world starts landed` and returns true; else reads the three, false when `fall_ticks > MAXIMUM_ARRIVAL_TICKS` or `landed_tick != 0 && landed_tick < start_tick` (malformed). Called in `read_simulation_state` after `read_felled_tree_table`. A pre 0200 save, whose last table is the felled trees, loads with a zero arrival: no fall, hatches as saved.
- Layout change: 24 bytes appended after the felled tree table, no format version step (the later tables' rule). Remap: none needed, absent reads as no fall. Log line: the one above. The hash covers it through `write_simulation_state`.
- A world past the arrival needs nothing beyond the tick? Not quite: a Skip before the planned end must survive a save and a join snapshot taken inside the planned window, and a save taken during the fall must resume it, so `landed_tick` and the start are saved. A world landed long ago needs only "landed", which `landed_tick != 0` says.

### Screens (`src/ui_screens.odin`, `src/loop.odin`)

- `Screen_Context` gains `arrival_falling: bool` (comment: the world's fall runs, 0200; the pause menu offers Skip arrival). `make_screen_context` sets it after the player is ready: `field_arrival_falling(session.simulation.field.arrival)`.
- `pause_screen`: `button_count` adds `(screen_context.arrival_falling ? 1 : 0)`.
- `pause_world_buttons`: first row, before the journal, when `screen_context.arrival_falling`: `ui_button(state, cut_top(content, UI_ROW_HEIGHT), text("pause_skip_arrival"))`; pressed and `screen_context.player_commands != nil`: `queue_player_command(screen_context.player_commands, screen_context.player_index, Skip_Arrival_Command{})` and `state.screens.count = 0` (the menu closes, so an offline world's ticks run again and apply it); then `cut_top(content, UI_GAP)`. No pending check: the command is idempotent. A split screen guest sees it too (any player may end the fall; it ends for all). A viewport waiting for its player never shows it (`pause_world_buttons` does not run).
- No other screen changes: the inventory, map and journal still open during the fall (question 4).

String key (`data/strings/en.sjson`, after `pause_save`): `pause_skip_arrival = "Skip arrival"`.

### Presentation (`src/render_arrival.odin`, new; presentation cluster)

File header comment: the arrival's presentation (0200), render only, read from `Field_Arrival`, the tick and the alpha; nothing here reaches the simulation; the hash is the same with and without it.

Constants: `ARRIVAL_VERTEX_SHADER_PATH :: "shaders/arrival.vs"`, `ARRIVAL_FRAGMENT_SHADER_PATH :: "shaders/arrival.fs"`, `ARRIVAL_DUST_SECONDS :: 4.0`, `ARRIVAL_DUST_PUFFS :: 36`, `ARRIVAL_SHAKE_SECONDS :: 1.0`, `ARRIVAL_SHAKE_METRES :: 0.15`, `ARRIVAL_SHAKE_HERTZ :: 17.3`, `ARRIVAL_ROAR_SOUND :: "arrival_roar"`, `ARRIVAL_CRASH_SOUND :: "arrival_crash"`, `ARRIVAL_HATCH_SOUND :: "hatch_open"`, `ARRIVAL_PITCH_SHARE :: 0.06`, `ARRIVAL_WALL_COLOR :: [3]f32{0.10, 0.10, 0.11}`.

Types:

- `Arrival_Phase :: enum u8 { None, Descent, Settled }`.
- `Arrival_View :: struct { phase: Arrival_Phase, progress: f32, flame_strength: f32, seconds: f32, seconds_since_hit: f32 }`: progress 0 to 1 over the descent (not eased), flame strength 0 to 1, seconds since the fall began (the shader's time), seconds since the hit.
- `Arrival_Sound_Memory :: struct { last_phase: Arrival_Phase, saw_fall: bool, hatch_heard: bool }`.
- `Arrival_Presentation :: struct { shader: rl.Shader, shader_ready: bool, sound_memory: Arrival_Sound_Memory }`. New field `arrival: Arrival_Presentation` of `Frame_Presentation` (`loop.odin`), after `field_renderer_ready`.

Procedures (pure unless said):

- `arrival_view :: proc(arrival: Field_Arrival, tick: u64, alpha: f32, config: Game_Config) -> Arrival_View`: None when `fall_ticks == 0`, or skipped (`landed_tick != 0 && landed_tick < start_tick + fall_ticks`). `elapsed := f32(tick - start_tick) + alpha` (0 when `tick < start_tick`), `descent := f32(fall_ticks) - f32(config.arrival_settle_ticks)`. Not landed and `elapsed < descent`: Descent with `progress = elapsed / descent`, `flame_strength = clamp((elapsed - (descent - f32(config.arrival_flame_ticks))) / f32(max(config.arrival_flame_ticks, 1)), 0, 1)` squared (it rises slowly then fast). Else `elapsed < descent + ARRIVAL_DUST_SECONDS * tick_rate`: Settled with `seconds_since_hit = (elapsed - descent) / tick_rate`. Else None. `seconds = elapsed / tick_rate`. Called by `draw_field_viewport_world` and the sound call. The frame passes `session.simulation.tick` and `interpolation_alpha(session.accumulator)`; offline under the pause menu the tick stands, so the fall stands.
- `arrival_eased_share :: proc(progress: f32) -> f32`: `progress * progress`, the share of the path covered; its speed grows to the end, so the last second is the fastest.
- `arrival_path_direction :: proc(up, forward: [3]f32, angle_degrees: int) -> [3]f32`: `up * cos + (-forward) * sin` of the angle, unit: from the resting place towards the start, the crater's up tilted backwards from the pod's door, so the camera looking along the path faces the same way the player faces when the fall ends.
- `arrival_start_offset :: proc(direction: [3]f32, start_metres, angle_degrees: int) -> [3]f32`: `direction * start_metres / cos(angle)`, so the start is `start_metres` above the floor.
- `arrival_descent_camera :: proc(eye: [3]f32, view: Arrival_View, up, forward: [3]f32, config: Game_Config, field_of_view: f32) -> rl.Camera3D`: position `eye + offset * (1 - arrival_eased_share(view.progress))`, target `position - direction`, up `forward * cos + up * sin` (perpendicular to the path, so the horizon stays level across the window), `fovy = field_of_view`, perspective. `up` and `forward` are the pod frame's axes (`find_pod_frame`, `unit_vector_to_f32(frame.axes[FRAME_UP])`, `[FRAME_FORWARD]`), `eye` the viewer's interpolated eye (`world_position_to_metres(field_player_view(...).eye)`). Without a pod the descent uses the player's up and forward.
- `arrival_noise :: proc(seconds: f32, salt: u64) -> f32`: value noise in -1 to 1 at `ARRIVAL_SHAKE_HERTZ`: `generation_seed.hash_u64` of the floor of `seconds * hertz` mixed with the salt, smoothstep between the two neighbouring values. Hashed, so no period.
- `arrival_shake_offset :: proc(seconds_since_hit: f32, salt: u64) -> (position, look: [3]f32)`: zero past `ARRIVAL_SHAKE_SECONDS`; else amplitude `ARRIVAL_SHAKE_METRES * (1 - s / ARRIVAL_SHAKE_SECONDS)^2`, position offset from three `arrival_noise` axes (salts `salt`, `salt + 1`, `salt + 2`), look offset half the amplitude from three more salts (the target moves more than the eye, a turn).
- `arrival_dust_puff :: proc(index: int, seconds_since_hit: f32, salt: u64) -> (radius_metres, height_metres, size_metres, alpha: f32, angle: f32)`: per puff hashed angle (0 to tau), start radius 3.5 to 5 m, outward speed 2 to 5 m/s eased by `1 - exp(-s / 0.8)`, rise 0.3 m plus up to 1.8 m eased by `1 - exp(-s / 1.2)`, size 0.8 m growing by 2.5 m over `ARRIVAL_DUST_SECONDS`, alpha `0.55 * (1 - s / ARRIVAL_DUST_SECONDS)^1.5`. Hashed per index, so no ring or rhythm shows.
- `draw_arrival_dust :: proc(frame: Frame, view: Arrival_View, salt: u64, color: rl.Color)`: inside `BeginMode3D`, after the scene, with `rlgl.DisableDepthMask()` and enabled after: each puff a `rl.DrawSphereEx` (6 rings, 8 slices) at the frame origin plus `right * cos(angle) + forward * sin(angle)` times the radius plus `up * height`, in `color` faded by alpha. Colour: `field_globe_color(planet.palette)` brightened by 0.3 (`rl.ColorBrightness`).
- `init_arrival_presentation :: proc(data_directory: string) -> Arrival_Presentation`: `load_shader_pair(data_directory, ARRIVAL_VERTEX_SHADER_PATH, ARRIVAL_FRAGMENT_SHADER_PATH, "arrival")`; on failure the log line `arrival: the window shader did not load; the fall draws without its window` and `shader_ready = false` (the fall still plays). Called at the end of `start_field_presentation` after the renderer is ready; `destroy_arrival_presentation(presentation: ^Arrival_Presentation)` unloads the shader when ready, called from `stop_field_presentation`. The sound memory resets in `enter_session` beside `sound_memory = {}`.
- `draw_arrival_window :: proc(presentation: ^Arrival_Presentation, view: Arrival_View, size: [2]f32, salt: u64)`: in pixel drawing after the 3D pass, only in Descent and with the shader ready: `rl.BeginShaderMode`, uniforms `flame_strength`, `seconds`, `aspect` (`size.x / size.y`), `flame_seed` (`f32(salt % 1000) / 1000`), `wall_color` (via `set_shader_float` and `rl.SetShaderValue` with `.VEC3`), then `rl.DrawTexturePro` of the default white texture (built as `draw_torch_flames` builds it) from `{0, 0, 1, 1}` onto `{0, 0, size.x, size.y}`, `rl.EndShaderMode`. `size` is the viewport rectangle's width and height (the window for one viewport, the target for split screen, both drawn from the origin).
- `play_arrival_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Arrival_Sound_Memory, view: Arrival_View, arrival: Field_Arrival, paused: bool, salt: u64)`: Descent and not paused: `set_loop_target(mixer, ARRIVAL_ROAR_SOUND, view.flame_strength)` and `saw_fall = true`; the frame where `last_phase` was Descent and the phase is Settled: `play_effect(mixer, ARRIVAL_CRASH_SOUND, 1, pitch)`; `arrival.landed_tick != 0 && memory.saw_fall && !memory.hatch_heard`: `play_effect(mixer, ARRIVAL_HATCH_SOUND, 1, pitch)` and `hatch_heard = true` (a Skip plays the doors without the crash); then `last_phase = view.phase`. Pitch `1 + ARRIVAL_PITCH_SHARE * (2 * hash_fraction(sound_hash(arrival.start_tick, salt, ...)) - 1)` with a different third argument per sound. A loaded or joined world past the fall never saw it, so it hears nothing.
- `salt` everywhere is the world seed (`session.simulation.world.settings.seed`).

Call sites:

- `Field_Scene` (`loop_field_session.odin`) gains `hide_frames: bool` (comment: the arrival's descent, every viewer is inside the pod, whose hull would hide the window's view). `draw_field_scene` skips `draw_frames`, `draw_entities`, `draw_field_players` and `draw_field_ghosts` when it is set; the field, the trees, the runs and the torches draw as before. The planet preview leaves it false.
- `draw_field_viewport_world` returns `Arrival_View`: after `alpha`, `view := arrival_view(session.simulation.field.arrival, session.simulation.tick, alpha, state.config)`, the pod's frame through `find_pod_frame`. Descent: the camera is `arrival_descent_camera(...)` (stored in `viewport.presentation.camera` as `field_viewport_camera` does), `scene.hide_frames = true`. Settled and not `state.settings.reduced_motion`: the field camera's position and target move by `arrival_shake_offset` (position by the first, target by both). Settled with a pod: `draw_arrival_dust` after `draw_field_scene`, before `EndMode3D`. The node selection, the streaming and the tree cache stay round the resting eye (`field_viewport_eyes` unchanged), so the crater is meshed finest from the first frame and nothing remeshes along the path.
- `draw_viewport_world` (`loop.odin`), field branch: `view := draw_field_viewport_world(...)`, `begin_render_pixel_drawing()`, then `draw_arrival_window(&state.presentation.arrival, view, {f32(viewport.rectangle.width), f32(viewport.rectangle.height)}, seed)`.
- The sound call, in the frame procedure beside `play_frame_sounds` (`loop.odin`, the `// The sounds read the block world` lines): `if viewport_player_ready(session, state.viewports[0]) && field { play_arrival_sounds(&state.presentation.audio, &state.presentation.arrival.sound_memory, arrival_view(..., interpolation_alpha(session.accumulator), state.config), session.simulation.field.arrival, top_screen(state.viewports[0].interaction.ui.screens) == .Pause, seed) }`. Once a frame from the first viewport, as the mixer is global. The HUD is unchanged.

### Shaders

- `data/shaders/arrival.vs`: `#version 330`, raylib's default attribute and uniform names (`vertexPosition`, `vertexTexCoord`, `mvp`), passes `fragment_texture_coordinate`.
- `data/shaders/arrival.fs`: `#version 330`; header comment (0200, `render_arrival.odin`, the u suffix rule). The quad's coordinate centred and aspect corrected, `p = (uv - 0.5) * vec2(aspect, 1.0)`. The window a rounded box of half size `vec2(0.38 * aspect, 0.36)` and corner radius 0.07 (`d` its signed distance). Outside (`d > 0`): `wall_color`, lighter by 0.08 on a bevel for `d < 0.012`, alpha 1. Inside: `depth = -d`; the leading edge is the window's bottom (the side the pod's motion presses into the air, as the camera's up is tilted back along the path): `lead = clamp(0.5 - p.y / 0.72, 0.0, 1.0)` with `p.y` growing downwards on the screen (flip the sign if raylib's texture coordinate runs the other way; the screenshot at tick 500 decides), `weight = 0.25 + 0.75 * lead`; `along = atan(p.y, p.x) * 3.0`; a four octave value noise `n` of `vec2(along * 4.0, depth * 9.0 - seconds * 6.0 * speed)` with the octaves' scales 1.0, 2.03, 4.11, 8.37 and speeds 1.0, 1.37, 1.91, 2.53 (no two in a ratio of small integers, so the pattern never repeats), offset by `flame_seed`; `height = flame_strength * weight * 0.22 * (0.6 + 0.8 * n)`; `flame = 1.0 - smoothstep(0.0, max(height, 0.0001), depth)`; colour `mix(vec3(1.0, 0.35, 0.05), vec3(1.0, 0.9, 0.6), flame * flame)`, alpha `flame`, plus an orange glow over the whole window of alpha `0.12 * flame_strength`. Floats only; any integer literal (an array size, a loop) takes the `u` suffix (`shader_source_test.odin`). The noise's hash is `fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453)`.
- `shader_source_test.odin` checks both automatically. Its two "at least six shipped shaders" counts stay true (eight now); update the messages' list "(chunk, water and field)" to add "and arrival".

### Sounds

- `data/sounds/sounds.sjson`: `{id = "arrival_roar", file = "arrival_roar.wav", volume = 0.7, kind = "loop"}`, `{id = "arrival_crash", file = "arrival_crash.wav", volume = 1.0, kind = "effect"}`, `{id = "hatch_open", file = "hatch_open.wav", volume = 0.6, kind = "effect"}`, after `capsule_landing`; the header comment's id list names them (0200).
- `tools/make_placeholder_sounds.py`: `arrival_roar()` (`loop_noise` of band 30 to 600 Hz, 4 s, seamless), `arrival_crash()` (a 40 Hz to 25 Hz `sweep` thump of 0.9 s under `shaped(band_noise(..., 1.4, 80.0, 2500.0), 0.002, 0.5)` debris), `hatch_open()` (a hiss, `shaped(band_noise(..., 0.9, 1500.0, 6000.0), 0.02, 0.4)`, over a low 0.8 s slide rumble, `band_noise` 60 to 300 Hz), added to `sound_set` and its docstring list; run it once and commit the three `.wav` files.
- No perceivable repetition: each plays once per world, its pitch varied by the world's hash; the roar is a seamless loop whose level rises with the flames and fades out.

### Tests

`src/simulation_arrival_test.odin` (default planet radius and the shipped spacing, `make_field_test_game_content`, `start_field_test_session` with `test_field_game_config()` and `arrival_ticks = 600`, `tick_field_test_simulation`):

- `test_a_new_world_holds_its_players_through_the_fall`: two sessions, one fed a walk, a jump, a turn and Interact on the inner hatch every tick (`FIELD_PREDICTION_TEST_WALK` plus `.Jump`, `.Interact` pressed), one fed nothing; after each of ticks 1 to 600 their players' field states are equal and both sessions' hashes equal; after tick 599 both hatches are closed and `landed_tick == 0`; after tick 600 both are open (`hatch_is_open`), `landed_tick == 600`, `hatch_toggle_tick == 601`; at tick 610 the walking session's player has moved away from the other's.
- `test_arrival_ticks_zero_starts_landed`: with `arrival_ticks = 0` the walk moves the player on tick 1, the hatches stay closed (0198), `field_arrival_falling` is false.
- `test_skip_ends_the_fall_on_two_sessions_at_the_same_tick`: sessions A and B (new worlds, same seed, arrival 600, window 2 as `start_field_lockstep_test_session` sets one, minus its 60 idle ticks); A queues `Skip_Arrival_Command` on `player_commands` at tick 200 and its records are stamped (`hold_local_commands`, `stamp_local_record`); each record A delivers is cloned (commands included) into B through `receive_input_record`, B stamping none; both run their ready ticks (`run_field_lockstep_test_ticks`). Both land on the same tick (the one A's record was stamped for), both hatches open on both, the hashes are equal at that tick and 10 ticks later, and a second Skip on A after it changes nothing (`landed_tick` unchanged).
- `test_a_save_loaded_after_the_fall_has_no_fall`: run 1000 ticks, save the session to a temporary directory and load it through `start_session` with `plan.loading` (the pattern of the loaded session tests in `simulation_field_test.odin`, line 257); the loaded arrival has `landed_tick == 600`, `field_arrival_falling` is false, the hatches are open, the first tick with the walk moves the player, and `arrival_view(..., tick 1000, ...)` is None.
- `test_a_joiner_after_the_fall_has_no_fall`: run 1000 ticks, `encode_save_files` and start the joined session from the files (`plan.files`, as `make_loopback_test_session`), queue an `Add_Player_Command` for a second player and tick: the new player spawns in the cabin and moves on the next tick with the walk; the arrival is landed and `arrival_view` None.
- `test_a_save_taken_during_the_fall_resumes_it`: save at tick 300 and load; the loaded world is still falling (`landed_tick == 0`), lands at tick 600 and not before; a session skipped at tick 100 and saved at tick 200 loads landed (`landed_tick == 101`, the hatches open).
- `test_a_save_from_before_the_arrival_loads_landed`: `write_simulation_state` of a landed field world with the last 24 bytes cut off, read back with `read_simulation_state`: true, `arrival` zero, nothing falls.
- `test_the_arrivals_presentation_leaves_the_hash`: two sessions through 700 ticks; on one, every tick calls `arrival_view`, `arrival_descent_camera`, `arrival_shake_offset`, every `arrival_dust_puff` and `find_pod_frame` on its state (no draw call, no window); `lockstep_state_hash` equal at ticks 300, 540, 600 and 700.

`src/render_arrival_test.odin` (pure, no window):

- `test_the_arrival_view_follows_the_timeline`: shipped values; ticks 0, 299 (descent, flames 0), 420 (flames between 0 and 1), 539 (descent, flames near 1), 540 (settled, 0 s since the hit), 600 with `landed_tick` 600 (settled), 780 (None); a skipped arrival (`landed_tick` 101) is None at ticks 101 and 600; `fall_ticks` 0 is None.
- `test_the_fall_ends_at_the_eye_and_its_last_second_is_fastest`: the camera position at progress 0 lies `start / cos(angle)` from the eye and `start` above it along the up (within a centimetre), at progress 1 on the eye; over 9 one second slices of the 540 tick descent each covers more than the one before.
- `test_the_shake_fades_and_never_repeats`: zero after `ARRIVAL_SHAKE_SECONDS`; within the first second the offsets at 120 sample times are not all equal and no candidate period of 1 to 60 frames reproduces the sequence.
- `test_arrival_values_are_bounded` (`data_load_test.odin` if that is where `validate_game_config` is tested, else here): the shipped `game.sjson` validates; 700 m at 30 degrees fails naming the path; `arrival_ticks` 200 with settle 60 and flames 240 fails; 0 passes.

UI:

- `test_the_pause_menu_offers_skip_during_the_fall` (`ui_pointer_test.odin`, beside the pause menu's tests): with `arrival_falling` the menu has the button `pause_button_id("pause_skip_arrival")`, activating it queues one `Skip_Arrival_Command` for the viewport's player and empties the screen stack; without it there is no such button.
- `ui_audit_test.odin`: `Ui_Audit_Case` gains `arrival_falling: bool`, passed into the case's screen context; new case `{name = "pause, arrival", screens = {.Pause}, arrival_falling = true, walk_focus = true}` beside the split screen guest's pause cases, so the taller menu is audited at every audit size, the smallest included.

### Docs

- `doc/architecture.md`, The field session: a bullet "The arrival (0200, `simulation_arrival.odin`)" after The start: `Field_Arrival`, `begin_field_arrival` in `start_field_world` for a new world only, the hold (`arrival_input` in the tick and the prediction), the landing at the end of the last tick or at a Skip (`land_field_arrival`, the hatches through `toggle_hatch`), the Skip as a relayed player command, the table and why it is saved (a skip or a save inside the window), a loaded or joined world past it never falls, the presentation reads it and never writes. The Start bullet's "its hatches closed" gains "until the arrival lands them open". Save format: the arrival table after the felled trees (24 bytes, absent in a pre 0200 save, which loads landed with one log line). Multiplayer, the prediction bullet: the prediction holds during the fall.
- `doc/presentation.md`, The field session: a subsection "The arrival" with the phases, the camera along the tilted path from the resting eye, the hidden frames, the selection round the resting eye, the window overlay and its shader, the flames, the hit `arrival_settle_ticks` before the landing, the shake (off under reduced motion), the dust, the three sounds (played by `play_arrival_sounds`, the field's only sounds until 0181), the start height bound and why. Shaders: `arrival.vs` and `arrival.fs`. The Sound section's effects list adds the arrival's.
- `doc/content.md`: a section "The arrival" after The pod (before Blocks): the five keys of `game.sjson` with their shipped values, bounds and the path bound's reason; `arrival_ticks = 0` is no fall. The pod's "A new world lays it" bullet: the players spawn in its cabin behind the closed hatches, which the arrival opens. Sounds: the three ids.
- `doc/ui.md`, Architecture, Screens, the pause menu line: "Skip arrival (during a new world's fall, 0200), Resume, ..." in its place after Resume, and that it closes the menu and ends the fall for every player.
- `doc/code_map.md`: the simulation cluster's file list gains `simulation_arrival.odin`, the presentation cluster's `render_arrival.odin`, the counts in the cluster table and the intro, `Frame_Presentation`'s field count (17), as `check_docs.py` and `code_graph.py --check` require.
- `doc/log/<landing date>.md`, "## The arrival (0200)", tags `arrival, pod, hatch, lockstep, save, presentation, shaders, sounds, m14`: the fall is simulation time and the presentation draws everything (why: lockstep and the hash); Skip is a player command, idempotent, any player; the table is saved (why not the tick alone); the hit 60 ticks before the landing for the silence; the start height bound from the coarsest level's fog, 500 m at 30 degrees, a view from orbit needs a far level; the pod is hidden during the descent and the window is an overlay (the model's windows are opaque panes); old saves load landed with one log line, no format step; the planet preview and the benchmark have no fall.

### Hand-back check lines that apply

- Memory a frame draws from: the shader is loaded at `start_field_presentation` and unloaded at `stop_field_presentation`, both outside the UI pass; nothing frees during a frame.
- A start-up load the game can make fail: the arrival shader falls back (logged, no window overlay) and never stops the session.
- A changed save layout loads an old save: the absent table reads as landed with one log line; `test_a_save_from_before_the_arrival_loads_landed`. Behaviour change for old saves: none (they are past the fall).
- A number parsed from text is range checked: the five keys in `arrival_problem`; the save's `fall_ticks` against `MAXIMUM_ARRIVAL_TICKS`.
- A UI audit case: "pause, arrival" added; no case becomes obsolete.
- Tests never touch the machine's state directory: the save and load tests use temporary directories.
- The others (file writes, shared budgets, lists that grow, long strings) do not apply: "Skip arrival" fits the pause panel's width, checked by the audit at the smallest size.

### Questions the item left open, answered

- Where the window is: the model's two windows are opaque soot panes in the side walls (`tools/models/machines/pod.py`, `build_hull`), so a camera at them sees nothing. The camera sits at the viewer's own eye on the path, the frames and the players are not drawn during the descent (every viewer is inside the pod), and the window is a screen overlay whose frame is the cabin wall. The pod is not drawn falling, since no viewer is outside it.
- The tilt's direction: backwards from the door, so the view along the path faces the way the player faces at the hit and the cut to the cabin keeps the heading.
- The leading edge: the window's bottom, since the camera's up is tilted back along the path.
- When the doors open against the hit: the hit at `arrival_ticks - arrival_settle_ticks`, the doors at `arrival_ticks`.
- Skip mid descent: the presentation ends at once, no crash and no dust; the hatch sound plays as the doors open.
- What holds during the fall: the input frame of the tick, whole (move, look, Interact, the hotbar). The screens' commands (crafting, slot moves) still apply.
- The selection's centre: the resting eye, not the falling camera, so nothing remeshes along the path and the crater is finest at the hit.
- Sounds in a field session: the block world's cue path is off for the field (`!field` before `play_frame_sounds`), so the arrival calls the mixer itself (`play_effect`, `set_loop_target`) with a memory of its own, the same calls the cue path makes.
- A joiner during the fall: it sees the rest of the fall from its join tick; one after it sees nothing.

### Questions to the main agent

1. The start: 500 m above the crater floor along a 30 degree path, bounded by the coarsest level's fog (0.6 x 1024 m). It reads as the final approach, not a fall from orbit. A start higher than about 530 m at 30 degrees needs `level_distances_metres[3]` raised (up to 4096, which meshes about 16 times the area at the coarsest level every frame for the whole game) or a far level drawn only for the fall, neither in scope. Does the user want to see 500 m first?
2. The Verify section's flame screenshot at tick 560 falls in the settle second after the hit; the specification moves it to tick 500 (flames near full). The mid fall screenshot stays at tick 300 (the flames just starting). Approve the hit 60 ticks before the landing, or should the hit coincide with the doors (no silence)?
3. The pod is hidden during the descent and the window is a screen overlay (above). If the user wants the model's window glazed and the camera at it, that is a model change for the 0205 series.
4. Only the world controls are held during the fall; Inventory, Map, Journal and the other screen keys still open their screens. Hold them too?
5. `hatch_open` plays only at the arrival's landing; Interact's toggles stay silent until 0181 brings the field's cues. Fine?

### Approval (main agent, 2026-10-03)

Approved as written, with the five questions answered and two changes:

1. The start height ships at 500 m on the 30 degree path, a final approach. The user sees it first; a fall from higher needs a far level and is an item of its own if they ask for it. The data bound stays as specified, so raising the value without that level fails the load with the named reason.
2. The hit 60 ticks before the doors is approved: crash, a second of silence, the doors. The Verify section's flame screenshot moves from tick 560 to tick 500 (the fall's flames at their height); the mid fall screenshot stays at tick 300.
3. The pod hidden during the descent with the window as a screen overlay is approved. A glazed window is the furnace series' concern (0212 onwards), not this item's.
4. Changed: the screens are held too. During the fall only Pause opens a screen; the inventory, map, journal and every other screen binding do nothing (the item's Controls section: nothing moves the player, Pause works). The seam is where the viewport reads the screen bindings in `loop.odin` or `ui_screens.odin`: while `Screen_Context.arrival_falling` (or the session's `field_arrival_falling`, whichever that code reaches), every screen opener but Pause is skipped; a screen already open when the fall starts cannot exist (the world is new). One test presses the inventory binding during the fall and finds no screen open, and after the landing finds the inventory open.
5. Changed: the hatch sound is the general hatch cue, not an arrival special case. `play_hatch_sounds :: proc(mixer: ^Audio_Mixer, memory: ^Arrival_Sound_Memory, entities: ^Entities, tick: u64, salt: u64)` in `render_arrival.odin`: the memory holds `last_hatch_tick: u64`, set to the session's tick in `enter_session`; each frame it plays `hatch_slide` once for every alive hatch whose `hatch_toggle_tick` lies after `last_hatch_tick` and at or before `tick` (open and close alike, the slide is the same), the pitch varied by a hash of the hatch's handle, its toggle tick and the salt, then sets `last_hatch_tick = tick`. The arrival's doors and a Skip's doors are covered by it, so `saw_fall` and `hatch_heard` go and the sound id is `hatch_slide` (file `hatch_slide.wav`, the same placeholder). A loaded or joined world never replays old toggles, since the memory starts at the load's tick. Interact's open and close sound from this item on; 0181 keeps the rest of the field's cues.

Implementation starts in the world stream after 0210's snapshot (the two items share `entity_pod.odin`, `simulation_field.odin`, `save_state.odin`, `loop.odin`, the strings, the code map and the log), in `.claude/worktrees/0200` on `item/0200` made from `item/0210`.
