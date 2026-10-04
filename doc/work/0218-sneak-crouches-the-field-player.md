# 0218: Sneak crouches the field player

Status: verified (2026-10-04, fix round done on item/0218; worktree `.claude/worktrees/0218` on `item/0218` from `main`, the specification approved the same day with the decisions below; user: "lets also make it so 'sneak' is a visible crouching, so we can sneak into 1 meter holes"; folds the field's missing sneak toggle)

## Goal

Sneak on the field is a crouch the player can see: the capsule shrinks to a crouch height so the player fits through a 1 m gap (two cells at the shipped 500 mm spacing), the eye drops with it, and the body is drawn crouched for the other players and the third person camera. Standing up waits for headroom, so a player who releases Sneak inside a tunnel stays crouched until the tunnel opens. Today Sneak only slows the walk (`field_walk_speed`) and descends in fly mode; the capsule is 1.8 m whatever the player does.

## Change

- **The crouch state.** `Field_Player.crouching: bool`, simulation state, set each tick from the sneak state: on while Sneak is on and the player is on foot (not flying); off again only when the standing capsule has room at the feet (`field_capsule_overlaps` with the standing tuning), else it stays on. The sneak speed follows the crouch, not the button, so a player stuck under a ceiling walks at the sneak speed until they stand. Fly mode keeps the standing capsule and Sneak's descent.
- **The sneak toggle on the field (folded bug).** The Accessibility tab's Sneak setting (`sneak_toggles` on the frame, 0074) is honoured by the block world's `tick_player` through `update_sneaking` and `with_sneaking` and by nothing on the field: `tick_field_session_player` and `predict_field_player_motion` build the field input from the frame's held buttons alone (`field_tick_input`). The same two procedures are applied there, so a toggled sneak crouches and un-crouches on the field as it slows the block world's walk; `Player.sneaking` is the truth on the field too.
- **The heights.** Two new keys in `field_player` of `data/game.sjson`: `crouch_height_millimetres` (above two radii, below `capsule_height_millimetres`) and `crouch_eye_height_millimetres` (inside the crouch capsule), shipped so the crouched capsule fits a 1 m gap with the ground tolerance to spare (900 and 750 are the proposal; the design stage checks them against `FIELD_GROUND_TOLERANCE` and the sphere count). The tick's tuning is chosen per player per tick from the crouch flag (a tuning with the crouch heights in place of the standing ones), so every capsule procedure keeps its `tuning` parameter and the step, mantle, ledge and ground probes read the crouched capsule without a change of their own.
- **Lockstep and the save.** The crouch is derived from the input record every tick and from the world's headroom, so the record does not change. `crouching` is saved with the field player and hashed; an old save loads it false, which is right for a player standing in the open, and a saved crouch under a ceiling loads crouched.
- **The eye.** The first person camera reads `field_player_eye` at the crouch height; the eye's height change is eased in presentation over `CROUCH_EASE_SECONDS` (about 0.15 s, frame time, presentation only), so the view dips instead of jumping.
- **The body.** The other players and the third person view draw the crouch: the capsule fallback at the crouch height, and the limb model lowered by the crouch delta with the legs folded at their pivots if `player_limb_angles` and the limb pivots allow it, else the body scaled along the up to the crouch height; the design stage picks and says why. The pose eases like the eye.
- **Out of scope.** The block world's sneak (`player.odin`, the slow walk with the edge check) is unchanged and its docs say so; the touch overlay's Default layout has no Sneak control (0134) and keeps none; no HUD change.

## Controls

No binding changes. Sneak (B, R5 on the gamepad; Left Control on the keyboard since fe4c600; a user touch layout's B) keeps its one meaning in the world: on foot it crouches and slows the walk, in fly mode it descends; the hold or toggle setting applies on the field as in the block world. In the placement editor (0215) B stays Sneak, so a player can crouch while walking round a ghost. This is the keybinding pass: the control's meaning grows a visible effect and gains no second meaning.

## Verify

- Tests (names chosen by the design stage): a crouched player walks through a 1 m gap that stops a standing one; standing up is refused under a 1 m ceiling and succeeds once out; the eye is at the crouch height while crouched; the sneak toggle crouches and un-crouches on the field; the sneak speed applies while crouched after the button is released under a ceiling; the save round trip keeps `crouching` and an old save loads it false; the state hash changes with it; the prediction on a copy matches the tick; a crouched body is drawn lower than a standing one (the capsule fallback and the model).
- The couch: the smallest brush digs a 2 m hole, so make the tunnel by digging a trench into a bank and roofing it a metre over its floor with foundation blocks (or by placing ground back); crouch in, release Sneak inside (stays crouched), walk out and stand; in multiplayer the other player sees the crouch.

## Specification (design, 2026-10-04)

### Decisions on what the item left open

- **Heights: 850 and 700 mm, not the proposed 900 and 750.** The item assumes a shipped spacing of 500 mm; the default world spacing is 1000 mm (`DEFAULT_SAMPLE_SPACING_MILLIMETRES`, `world_field.odin`), with 333 and 500 the other choices. Measured on the bilinear cross-section of whole-sample tunnels (full ground 127, air -128, surface at 127/255 of the way): a 1 m slab gap at any spacing, and a 2 by 2 sample tube at 500 mm, take a capsule up to 1002 mm; a 1 by 1 sample tube at 1000 mm (one air sample, the smallest 1 m hole at the default spacing) takes only 904 mm, because the blurred corners round the section into a diamond and lift the bottom sphere 150 mm off the centre line. The overlap test passes while a sphere is no nearer than `capsule_radius - FIELD_PENETRATION_TOLERANCE` (300 - 3.9 mm), and the feet may hover up to `FIELD_GROUND_TOLERANCE` (4096 / 64 = 64 units, 15.6 mm) after a drop. Margins at 900: 1002 - 900 - 16 = 86 mm in the slab, 904 - 900 - 16 < 0 in the 1000 mm tube (it does not fit). At 850: 136 mm in the slab, 904 - 850 - 16 = 38 mm in the tube. Sphere count at 850: span 850 - 600 = 250, `ceiling_divide(250, 300) + 1` = 2 spheres, centres 300 and 550 mm above the feet, top 850. The eye at 700 keeps it 150 mm under the crouched top (standing: 200 under 1800) and inside the squashed helmet (the model's head spans 1.44 to 1.75 m, times 850 / 1800 = 0.68 to 0.83 m).
- **The body: scaled along the up, not lowered with folded legs.** The limb model has one segment per leg (`tools/make_placeholder_models.py`, `player_leg`: voxels 0 to 12 of 29, 0.81 m, pivot at the hip only) and no knee. The crouch drops the top by 950 mm, more than the whole leg, so lowering the torso by the delta puts the hips under the ground; swinging the legs forward 90 degrees at the hip lowers the hips only to the leg's depth (3 voxels, 0.19 m) and leaves the helmet at about 1.19 m, above the 0.85 m capsule. The body transform scales its up column by the eased ratio instead (1 standing, 850 / 1800 = 0.472 crouched); the capsule fallback is drawn at the eased height. A knee pose needs split leg models, a model item, not this one.
- **Un-crouch in every mode needs headroom**, flying included: a player who starts flying under a ceiling stays crouched until the standing capsule fits. The one exception is flying with no clip, which has no collision and stands at once.
- **The sneak speed follows the crouch**: `field_walk_speed` takes the crouch flag in place of reading Sneak from the held buttons. Sprint while crouched walks at the sneak speed. Fly mode keeps reading Sneak from the held buttons for its descent.
- **Every reader of the eye and the capsule follows the crouch** without new parameters: `field_player_eye` and `field_player_capsule` pick the crouch heights from the player's flag, so the aim rays (terrain, frames, trees, torches, the run tool), the place's bury check, the frame placement's capsule check and the hatch's capsule check all use the crouched body. Consequences, intended: a crouched player can place ground or a frame above the crouched head and then cannot stand there; a crouched player mantles into a 1 m hole up a face (`find_field_ledge` checks the crouched capsule); the step into a tunnel lower than the standing body plus a step is refused while standing and taken crouched.
- **The easing**: one progress per player index from 0 (standing) to 1 (crouched), advanced by the frame time in `prepare_field_frame`, a full swing in `CROUCH_EASE_SECONDS` (0.15), smoothstepped, as the sprint kick does (`advance_sprint_kick`). It is not turned off by reduced motion: it replaces a jump of 0.9 m by a short glide, which is the gentler of the two. The planet preview snaps (its developer walk passes 0 or 1 from the flag), which keeps that tool's code untouched apart from the new argument.
- **No log line at load**: the save codec is self-describing (`save_binary.odin`, a field the file lacks keeps its value), so `Field_Player.crouching` needs no remap and an old save's player loads with it false. The decision log paragraph records it.

### Simulation (integer only)

`src/data_load.odin`
- `Field_Player_Config`: add after `eye_height_millimetres`, with a comment line each: `crouch_height_millimetres: int` (the capsule while crouched, 0218) and `crouch_eye_height_millimetres: int` (the eye while crouched).
- `field_player_problem`: two bounds after the eye's, `{"crouch_height_millimetres", player.crouch_height_millimetres, 2 * player.capsule_radius_millimetres + 1, player.capsule_height_millimetres - 1}` and `{"crouch_eye_height_millimetres", player.crouch_eye_height_millimetres, 1, player.crouch_height_millimetres}`. Update the procedure's comment: the crouch below the standing capsule and above its caps, its eye inside it.

`data/game.sjson`, `field_player`: `crouch_height_millimetres = 850` and `crouch_eye_height_millimetres = 700` after `eye_height_millimetres`; extend the block's comment by one sentence: Sneak on foot crouches to the crouch height (0218).

`src/player_field.odin`
- `Field_Player_Tuning`: add `crouch_capsule_height: i64` and `crouch_eye_height: i64` (position units) after `eye_height`; `make_field_player_tuning` fills them with `millimetres_to_position_units` of the two keys.
- `Field_Player`: add `crouching: bool` after `on_ground`, commented: Sneak on foot, held until the standing capsule has room (`update_field_crouch`, 0218); a save from before 0218 loads it false.
- New `field_posture_tuning :: proc(tuning: Field_Player_Tuning, crouching: bool) -> Field_Player_Tuning`: the tuning with `capsule_height` and `eye_height` replaced by the crouch ones when crouching, else unchanged. The crouch fields stay in the result, so a crouched posture of a crouched posture is the same tuning. Called by `tick_field_player`, `field_player_eye`, `field_player_capsule`, `move_and_aim_field_player`, `update_field_crouch`. Callers pass the base tuning (`content.field.tuning`) everywhere outside the tick.
- `field_player_eye`: the eye height from `field_posture_tuning(tuning, player.crouching).eye_height`. Signature unchanged.
- New `update_field_crouch :: proc(world: ^Field_World, frames: ^Frame_Table, tuning: Field_Player_Tuning, player: ^Field_Player, sneak: bool)`: `sneak && !player.flying` sets `crouching`; otherwise a crouching player stands when flying with no clip, or when `!field_capsule_overlaps(world, frames, field_posture_tuning(tuning, false), player.position, player.up)`; else stays crouched. `tuning` is the base tuning.
- `field_walk_speed :: proc(tuning: Field_Player_Tuning, held: Field_Player_Buttons, crouching: bool) -> i64`: crouching gives `sneak_speed`, then Sprint in held `sprint_speed`, else `walk_speed`. `walk_field_player` passes `player.crouching`. Update the comment.
- `tick_field_player`: after `turn_field_player`, call `update_field_crouch(world, frames, tuning, player, .Sneak in input.held)`, then `posture := field_posture_tuning(tuning, player.crouching)` and pass `posture` to `fly_field_player`, `field_ground_loaded` and `walk_field_player` and to the target's `raycast_field` (its eye through `field_player_eye(player^, posture)`, its reach and spacing unchanged). The order is the determinism point: the crouch is decided from the input and the world before the move, in the tick and in the prediction alike.
- File header comment: one sentence on the crouch (Sneak on foot shrinks the capsule to the crouch height; standing waits for room).

`src/field_trees.odin`, `move_and_aim_field_player`: pass `field_posture_tuning(tuning, player.crouching)` to `push_field_player_out_of_trunks` (after `tick_field_player`, so it is this tick's flag). `aim_field_player_at_frames` and `aim_field_player_at_trees` stay as they are (their eye goes through `field_player_eye`).

`src/field_mining.odin`, `field_player_capsule`: build the capsule from `field_posture_tuning(tuning, player.crouching)`. Comment: the crouched body while crouching (0218). Its callers (`field_place_buries_a_player`, `entity_frames.odin` line 386, `field_player_capsules` in `entity_pod.odin`) are unchanged.

`src/simulation_field.odin`, `tick_field_session_player`: as `tick_player` does, first `player.sneaking = update_sneaking(player.sneaking, frame)`, then `interact_on_field(state, content, index, with_sneaking(frame, player.sneaking))`; the rest unchanged. `interact_on_field` keeps its signature.

`src/lockstep.odin`, `predict_field_player_motion`: `player.sneaking = update_sneaking(player.sneaking, frame)` first, then `without_field_interact_jump(player^, ..., with_sneaking(frame, player.sneaking))`. Add to its comment: the sneak state, as the tick's. The record is unchanged (`sneak_toggles` already rides it).

The state hash and the save need no code: `Player` is written whole by `write_value_of` (`save_state.odin`, `write_simulation_state`), which feeds `simulation_state_hash` and the lockstep hash, so `Field_Player.crouching` and the field's now live `Player.sneaking` are saved and hashed.

### Presentation (f32, frame time, never read by the tick)

`src/render_field_camera.odin`
- `CROUCH_EASE_SECONDS :: 0.15` with a comment (a full swing of the crouch's progress, 0218).
- `advance_field_crouch :: proc(progress: f32, crouching: bool, frame_seconds: f32) -> f32`: towards 1 while crouching, towards 0 otherwise, `frame_seconds / CROUCH_EASE_SECONDS` a frame, clamped, as `advance_sprint_kick`.
- `field_crouch_progress_of :: proc(progress: []f32, index: int) -> f32`: the entry, 0 out of range.
- `field_crouch_eased :: proc(progress: f32) -> f32`: smoothstep `p * p * (3 - 2 * p)`.
- `field_eye_height_units :: proc(tuning: Field_Player_Tuning, progress: f32) -> i64`: `eye_height` plus `(crouch_eye_height - eye_height)` times the eased progress, rounded towards zero.
- `field_body_up_scale :: proc(tuning: Field_Player_Tuning, progress: f32) -> f32`: 1 plus `(crouch_capsule_height / capsule_height - 1)` times the eased progress.
- `field_player_view :: proc(player: Field_Player, tuning: Field_Player_Tuning, alpha: f32, crouch_progress: f32) -> Field_Camera_View`: the eye is `player.position + up * field_eye_height_units(tuning, crouch_progress)` (base tuning), the interpolation unchanged. Header comment: the eye dips over the crouch's progress.

`src/render_field.odin`: `Field_Renderer` gains `crouch_progress: [dynamic]f32` (each player's eased crouch by player index, advanced in `prepare_field_frame`, 0218); `destroy_field_renderer` deletes it before the reset.

`src/loop_field_session.odin`
- `prepare_field_frame`: after the daylight, `resize(&renderer.crouch_progress, len(session.simulation.players))` and for each index `advance_field_crouch(progress, lockstep_view_player(&session.lockstep, &session.simulation, index).field.crouching, state.frame_seconds)` (the prediction for a local player, as the scene draws it). It runs once a frame before any viewport draws, and the draws read the entries by value.
- `field_viewport_camera` and the `.Descent` branch of `arrival_viewport_camera`: pass `field_crouch_progress_of(state.presentation.field_renderer.crouch_progress[:], viewport.player)` to `field_player_view`.
- `field_player_body_transform :: proc(feet: [3]f32, player: Field_Player, up_scale: f32) -> matrix[4, 4]f32`: the up column times `up_scale`. Comment: squashed along the up while crouched.
- `field_player_capsule_ends :: proc(feet, up: [3]f32, height: f32) -> (bottom, top: [3]f32)`: `feet + up * 0.3` and `feet + up * (height - 0.3)`, the two centres today's draw uses at 1.8.
- `draw_field_player_capsule :: proc(feet, up: [3]f32, height: f32)`: draws between `field_player_capsule_ends`.
- `draw_field_player_body :: proc(scene: Field_Scene, player: Field_Player, crouch_progress: f32)`: `scale := field_body_up_scale(scene.content.field.tuning, crouch_progress)`; the fallback capsule at `f32(tuning.capsule_height) / POSITION_UNITS_PER_METRE * scale`, the model with `field_player_body_transform(feet, player, scale)`. `draw_field_players` passes `field_crouch_progress_of(scene.renderer.crouch_progress[:], index)`.

`src/loop_model_preview.odin`, line 195: `draw_field_player_capsule(model_preview_capsule_feet(pitch), {0, 1, 0}, MODEL_PREVIEW_CAPSULE_HEIGHT_METRES)`.

`src/loop_planet_preview.odin`, `planet_preview_raylib_camera`: `field_player_view(body, preview.session.field_content.tuning, alpha, body.crouching ? 1 : 0)`.

`src/render_field_camera_test.odin`: the three existing `field_player_view` calls gain the argument 0.

### Tests

`src/player_field_test.odin`
- `test_field_player_config` gains `crouch_height_millimetres = 850, crouch_eye_height_millimetres = 700`.
- Harness: `Test_Terrain_Kind` gains `Tunnel`, and `Test_Terrain` gains `tube_samples: i32` (0: the roof covers every z; n: only the n sample columns from z = 0 up are open under it). A tunnel is written per sample, not as a signed distance, so the gap is whole samples at every spacing (a signed distance with surfaces on the 1000 mm samples gives density 0 through the whole gap): `test_tunnel_density :: proc(terrain: Test_Terrain, position: World_Position, spacing_millimetres: int) -> i8` is `MAXIMUM_DENSITY` when `site_height(position) <= 0`, or when `position.x >= metres_to_position_units(TEST_LEDGE_FACE_METRES)` and (`site_height(position) > terrain.ledge_height` or, with `tube_samples > 0`, `position.z < 0 || position.z >= i64(tube_samples) * sample_axis_to_position(1, spacing_millimetres)`), else `-MAXIMUM_DENSITY`; `fill_test_chunk` takes it for `.Tunnel` in place of `depth_to_density`. With `ledge_height` 1 m the open rows are the samples above the floor up to 1 m (3 at 333 mm, 2 at 500, 1 at 1000): floor surface half a sample above the site, gap 0.999 to 1.000 m. Helper `TEST_ONE_METRE_TUNNEL :: Test_Terrain{kind = .Tunnel, ledge_height = POSITION_UNITS_PER_METRE}`. `FIELD_SNEAK_FORWARD :: Field_Player_Input{move = {0, FIELD_MOVE_ONE}, held = {.Sneak}}`. Every start is `make_field_player(test_site_point(0, POSITION_UNITS_PER_METRE, 0), {UNIT_VECTOR_ONE, 0, 0})` (a metre up, clear of the floor half a sample above the site at 1000 mm; z = 0, the 1000 mm tube's column) settled with 30 idle ticks. The roof's face lies half a sample before its first sample column (1.5 to 1.83 m); the sneak walks 1.3 m/s, 2.6 m in 120 ticks.
- `test_a_crouched_field_player_walks_under_a_one_metre_ceiling`: every spacing of `TEST_FIELD_SPACINGS`, the slab: a standing walk of 120 ticks ends with `position.x` below the face; a fresh player with `FIELD_SNEAK_FORWARD` for 240 ticks ends past the face plus 1 m, and each of the last 60 ticks it is on the ground, `crouching`, and `!field_capsule_overlaps` with `field_posture_tuning(tuning, true)`.
- `test_a_crouched_field_player_fits_a_one_sample_tube_at_the_default_spacing`: 1000 mm, `tube_samples = 1`: the sneak walk of 240 ticks ends past the face plus 1 m (the 850 mm choice; it fails at 900).
- `test_standing_up_waits_for_headroom`: 500 mm slab: sneak in for 120 ticks, then 30 ticks of `{}`: still `crouching` and `field_player_eye(player, tuning)` equals `position + up * crouch_eye_height`; then 150 ticks of `{move = {0, -FIELD_MOVE_ONE}}`: out past the face minus 1 m and not crouching, the eye at `eye_height`.
- `test_the_sneak_speed_follows_the_crouch`: 500 mm slab, sneaked 120 ticks in, then 60 ticks of forward with Sprint held and Sneak released: the feet moved along x within 10 percent of 1.3 m/s for one second (`tuning.sneak_speed` times 60 over `VELOCITY_FRACTION_ONE`), and less than half of the sprint's 5.6 m.
- `test_fly_mode_keeps_the_standing_capsule`: flat ground, 500 mm, `flying = true` and 30 ticks with Sneak held: never `crouching`, and the feet went down (the descent).
- `test_the_field_player_config_is_bounded`: adds a crouch height of 600 (two radii) refused, one of 1800 (the standing height) refused, a crouch eye of 0 and one of 851 refused.
- `test_the_field_player_saves_its_crouch`: a `Field_Player` with `crouching = true` round trips through `write_value_of` and `read_value_of`; a `Field_Player_Before_Crouch :: struct { yaw: i32 }` written and read into a zero `Field_Player` gives `crouching` false and the yaw.

`src/simulation_field_test.odin` (sessions from `start_field_test_session(test_field_game_config(), make_field_test_game_content())`, ticked with `tick_field_test_simulation`)
- `test_the_sneak_toggle_crouches_the_field_player`: frames with `sneak_toggles = true`: a Sneak press (in `pressed` and `just_pressed`), then 20 frames without it, then a press, then 10 without: after the first press and through the 20 the player is `sneaking` and `crouching`; after the second press and the 10 neither (the cabin has room).
- `test_the_field_prediction_crouches_as_the_tick`: the same frames; before each tick a copy of `players[0]` goes through `predict_field_player_motion` with the frame; after the tick the copy's `sneaking`, `field.crouching` and `field.position` equal the ticked player's.
- `test_the_crouch_changes_the_state_hash`: the session's `simulation_state_hash` changes when `players[0].field.crouching` is set.

`src/render_field_camera_test.odin` (tuning `test_field_tuning(500)`)
- `test_the_field_crouch_eases_over_its_seconds`: from 0, ten steps of a tenth of `CROUCH_EASE_SECONDS` crouching reach 1; one long step back gives 0; half a swing gives 0.5 within 1e-4; `field_crouch_progress_of` gives 0 out of range.
- `test_the_field_eye_follows_the_eased_crouch`: `field_player_view` at alpha 1 puts the eye at `eye_height` over the feet at progress 0, at `crouch_eye_height` at 1 and strictly between at 0.5.
- `test_a_crouched_field_body_is_drawn_lower`: `field_player_capsule_ends` at the height `field_body_up_scale(tuning, 1) * 1.8` has its top centre 0.55 m above the feet (1.5 m standing); `transform_point(field_player_body_transform(feet, player, field_body_up_scale(tuning, 1)) * player_model_scale(), {0, 29, 0})` lies 0.472 times as far above the feet along the up as with scale 1.

### Docs (same commit)

- `doc/architecture.md`, The player on the field: a bullet on the crouch (Sneak on foot sets `crouching`, standing waits until the standing capsule fits, flying with no clip excepted; the tick's tuning is `field_posture_tuning` of the flag, decided before the move; the eye, the aim, the bury, frame and hatch checks use the crouched body; the walk is at the sneak speed while crouched; fly mode keeps the standing capsule and Sneak's descent; Sneak's hold or toggle applies as in the block world through `update_sneaking`). The fly mode bullet: nothing to change.
- `doc/content.md`, the `field_player` bullet: the two keys with their bounds (above two radii and below the standing height; inside the crouch) and the shipped 0.85 m and 0.7 m, with the reason (a 1 m hole of whole samples at every spacing, the 1000 mm one-sample tube taking at most 0.904 m).
- `doc/input.md`, Hold or toggle: the last paragraph says `update_sneaking` and `with_sneaking` run in the field tick and its prediction too (0218), and that on the field Sneak on foot crouches; the block world's sneak (the slow walk with the edge check) is unchanged.
- `doc/presentation.md`: the field section's per viewport bullet gains the eye's dip over `CROUCH_EASE_SECONDS`; the `prepare_field_frame` bullet the crouch progress per player; the scene bullet: a crouched body is the model squashed along the up to the crouch height (the legs have no knee) or the capsule at that height.
- `doc/code_map.md`: the `render_field_camera.odin` entry adds the crouch's easing and eye (0218).
- `doc/log/2026-10-04.md`: a paragraph tagged `#field-player #crouch #save`: the heights 850 and 700 over the proposed 900 and 750 with the 904 mm arithmetic; the squash over folded legs and why; an old save's player loads standing and `Player.sneaking` is now live on the field, both through the self-describing codec without a remap.

### Hand-back check lines that apply

- Memory a frame may draw from: `crouch_progress` is resized in `prepare_field_frame`, before any viewport draws, and read by value; it is freed only in `destroy_field_renderer` at the session's end. Nothing frees it mid frame.
- A start-up load that can fail: an overlay `game.sjson` copied before 0218 lacks the two keys and fails the bound; `load_start_data` already falls back to the shipped data and reports (`main.odin`), which the implementer confirms by reading, not by a new path.
- A number parsed from text is range checked: the two bounds.
- A changed save layout loads an old save: `test_the_field_player_saves_its_crouch`, and the log paragraph.
- Tests never touch the machine's state: the session tests use the existing in-memory helpers.
- The others (file writes, shared budgets, unbounded lists, UI audit cases) do not apply: no file, budget, list or screen changes.

### Questions for the main agent

- The couch step "dig a 1 m tunnel into a bank with the pickaxe": the shipped brushes are spheres of 1 and 2 m radius and the level brush (`field_brushes`), so a dig makes a hole about 2 m across, not a 1 m tunnel. The couch check may need the tunnel built (dig a big hole, place ground back to a 1 m roof, or foundation blocks over a trench), or a smaller brush, which is another item. The Verify line may want rewording.
- The third person camera is not pulled in by the field (existing), so in a 1 m tunnel it sits in the rock behind the player; out of this item's scope, maybe worth an item.

### Decisions at the approval (main agent, 2026-10-04)

1. The heights 850 and 700 mm are approved over the item's 900 and 750: the default spacing is 1000 mm and its one sample tube takes a capsule of at most 904 mm.

Measured at the verification (2026-10-04): the 1000 mm one sample tube takes a capsule of about 1 m, like the slab (the tube test passes with a crouch of up to 1000 mm and fails from 1050), so 850 leaves 150 mm of margin.
2. The body squashed along the up is approved for the placeholder limb models; the crouch pose is redone with the player model when that model goes through the lab.
3. The couch step is reworded above (the brushes dig 2 m holes).
4. The third person camera sitting in the rock behind a crouched player in a tunnel is the camera's existing limit (it is not pulled in by the field) and is work item `0220-the-third-person-camera-pulled-in-by-the-field.md`, after this one.
