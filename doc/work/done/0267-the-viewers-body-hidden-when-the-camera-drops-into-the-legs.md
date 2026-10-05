# 0267: The viewer's body hidden when the pulled-in camera drops into the legs

Status: landed (2026-10-05, 603a7cc)

## Goal

Looking steeply up in third person, the camera's offset points down through the body and the ground pulls the camera in to about the feet, more than 0261's distance from the eye, so the body is drawn round the camera. The viewer sees the world there too, not the inside of their legs.

## Controls

No binding changes.

## Change

- 0261's distance measured to the body's axis segment (feet to eye) instead of to the eye alone, so a camera pulled into the legs hides the body as one pulled to the eye does; the feet and the height reach both cameras' seams (`field_viewport_camera`, `draw_session_world`).
- Docs: `doc/presentation.md` (The player), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: with the camera at the feet the viewer's body is not drawn; 0261's tests hold.
- The couch: third person on flat ground, look straight up: the body vanishes instead of the legs filling the screen.

## Specification (design, 2026-10-05)

### Why 0261 misses it

`viewer_body_shown` (`src/render_player.odin`) measures the camera to the eye only. At the pitch limit (89 degrees, `FIELD_PITCH_LIMIT`) with the settings' 4 m and 0.6 m shoulder, the offset points down through the body, the ground pulls the camera in (`field_camera_pulled_distance`, `third_person_position`) to about 0.2 m over the feet and 0.26 m off the axis, 1.42 m from the eye standing and 0.51 m crouched (eye 0.7 m), so the 0.4 m sphere round the eye does not hold it.

### The rule

The distance is measured to the segment from the feet to the eye (the body's axis up to the eye) instead of to the eye, with the same `VIEWER_BODY_HIDDEN_WITHIN_METRES` (0.4 m: the 0.3 m radius plus the field's 0.1 m near plane). The segment with its 0.4 m round ends covers the drawn body: the capsule's top is 0.2 m over the eye standing and 0.15 m crouched, its bottom is the feet. It subsumes 0261's rule: a camera at the eye is on the segment. Float metres, presentation only.

### Changes

- `src/render_player.odin`: `viewer_body_shown :: proc(mode: Camera_Mode, camera_position, eye, up: [3]f32, eye_height: f32) -> bool`: third person and the distance from the camera to the segment from `eye - up * eye_height` to `eye` at least `VIEWER_BODY_HIDDEN_WITHIN_METRES` (the closest point is the feet plus `up` times `clamp(dot(camera_position - feet, up), 0, eye_height)`; `up` is a unit vector). Its comment: "with the camera at least VIEWER_BODY_HIDDEN_WITHIN_METRES from the body's axis from the feet to the eye (0261, 0267)". The constant's comment: "A camera this close to the eye" becomes "A camera this close to the body's axis, from the feet to the eye (0267: looking up, the ground pulls the camera in to the feet),". Nothing else in the comment or the value changes.
- `src/render_field_camera.odin`: `field_viewer_body_shown :: proc(mode: Camera_Mode, camera_position: [3]f32, view: Field_Camera_View, tuning: Field_Player_Tuning, crouch_progress: f32) -> bool`: `viewer_body_shown` with `world_position_to_metres(view.eye)`, `unit_vector_to_f32(view.up)` and `field_eye_height_units(tuning, crouch_progress)` in metres (over `POSITION_UNITS_PER_METRE`). The field's one call, so both field seams take the crouched eye the view was built with. Placed after `field_player_view`.
- `src/loop_field_session.odin`, `field_viewport_camera`: the crouch progress goes to a local (`crouch_progress := field_crouch_progress_of(...)`) used by `field_player_view` and the return `field_viewer_body_shown(mode, camera.position, view, state.session.field_content.tuning, crouch_progress)`.
- `src/loop_planet_preview.odin`, `planet_preview_raylib_camera`: the same, with `body.crouching ? 1 : 0` in a local and `preview.session.field_content.tuning`.
- `src/loop.odin`, `draw_session_world`: `viewer_body_shown(player.camera_mode, view.position, player_eye(pose.position), {0, 1, 0}, PLAYER_EYE_HEIGHT)`. The block world has no crouched eye (`player_eye` is constant).

### Tests

- `test_the_viewers_body_is_shown_only_past_the_hidden_distance` (`src/render_player_test.odin`): every call gains `{0, 1, 0}, PLAYER_EYE_HEIGHT`; its assertions hold unchanged (the cases lie at the eye's level or above it, where the segment's nearest point is the eye).
- `test_the_viewers_body_is_hidden_near_the_axis_from_the_feet_to_the_eye` (same file, new): eye `{1, 2, 3}`, `.Third_Person`. For eye heights `PLAYER_EYE_HEIGHT` (1.6, the shipped standing eye) and 0.7 (the shipped `crouch_eye_height_millimetres`), with `feet := eye - {0, height, 0}`: hidden at the feet, at `feet + {0, height / 2, 0} + {VIEWER_BODY_HIDDEN_WITHIN_METRES - 0.01, 0, 0}` and at `feet - {0, VIEWER_BODY_HIDDEN_WITHIN_METRES - 0.01, 0}`; shown at `feet + {0, height / 2, 0} + {VIEWER_BODY_HIDDEN_WITHIN_METRES + 0.01, 0, 0}`, at `feet - {0, VIEWER_BODY_HIDDEN_WITHIN_METRES + 0.01, 0}` and at `eye + {0, VIEWER_BODY_HIDDEN_WITHIN_METRES + 0.01, 0}`. A tilted up `{0, 0.6, 0.8}` with side `{0, 0.8, -0.6}`: hidden at `eye - up * 0.8 + side * (VIEWER_BODY_HIDDEN_WITHIN_METRES - 0.01)`, shown at `+ 0.01`, so the axis follows the up, not y.
- `test_the_field_viewers_body_is_hidden_with_the_camera_at_the_eye` and `test_the_field_viewers_body_is_drawn_at_the_settings_distance` (`src/render_field_camera_test.odin`): call `field_viewer_body_shown(.Third_Person, position, view, tuning, 0)`; the first builds `view := Field_Camera_View{eye = near_eye, up = {0, UNIT_VECTOR_ONE, 0}}` and `tuning := test_field_tuning(spacing)`. Assertions unchanged.
- `test_the_field_viewers_body_is_hidden_looking_straight_up` (same file, new): for `TEST_FIELD_SPACINGS`, the flat field, `start_crouch_test_player`, `player.pitch = FIELD_PITCH_LIMIT`; for crouch progress 0 and 1: `view := field_player_view(player, tuning, 1, crouch_progress)`, `position` from `field_third_person_position` with `field_third_person_offset(view, THIRD_PERSON_DISTANCE, 0.6)`; expect `f32_distance(position, world_position_to_metres(view.eye)) >= VIEWER_BODY_HIDDEN_WITHIN_METRES` (the case 0261's rule showed: about 1.42 m standing, 0.51 m crouched), `!field_viewer_body_shown(.Third_Person, position, view, tuning, crouch_progress)`, and with the scene of the 0261 tests `field_player_body_drawn(scene, 0)` false, `field_player_body_drawn(scene, 1)` true.
- `test_the_block_viewers_body_is_hidden_when_the_camera_reaches_the_eye` (`src/player_test.odin`): the calls gain `{0, 1, 0}, PLAYER_EYE_HEIGHT`; assertions unchanged (the near camera is about 0.3 m off the axis, the far one about 1.3 m).
- `test_the_block_viewers_body_is_hidden_looking_straight_up` (same file, new): `make_floor_world(registry, 32)` (floor top at y 1), eye `{0.5, 2.6, 0.5}`, `camera := third_person_position(&world, registry, eye, third_person_offset({0, 1, 0}, 0, THIRD_PERSON_DISTANCE, 0.6))` (about 0.2 m over the floor, 0.26 m off the axis); expect `f32_distance(camera, eye) >= VIEWER_BODY_HIDDEN_WITHIN_METRES` and `!viewer_body_shown(.Third_Person, camera, eye, {0, 1, 0}, PLAYER_EYE_HEIGHT)`.

### Docs

- `doc/presentation.md`, The player, the bullet "First person draws the right arm ...": "pulled in within `VIEWER_BODY_HIDDEN_WITHIN_METRES` (0.4 m, the body's 0.3 m radius plus the field's 0.1 m near plane) of the eye" becomes "... of the body's axis from the feet to the eye (looking steeply up the ground pulls it in to the feet, 0267)"; "(`viewer_body_shown`, 0261)" becomes "(`viewer_body_shown`, 0261, 0267)".
- `doc/presentation.md`, The field session, the scene bullet: "with its camera pulled in to the eye" becomes "with its camera pulled in to the body".
- `doc/architecture.md`, The player on the field, the cameras bullet, the last sentence: "of the eye" becomes "of the body's axis from the feet to the eye".
- `doc/code_map.md`: no change (no new file, no new edge: `loop_field_session.odin` and `loop_planet_preview.odin` already call `render_field_camera.odin`).
- `doc/log/2026-10-05.md`, the main agent's section at the landing, from:

  ## The viewer's body hidden with the camera in the legs (0267)

  Tags: field, block-world, camera, third-person, presentation, body, 0261, 0267, m14

  The distance is measured to the segment from the feet to the eye, with 0261's 0.4 m, which subsumes the eye rule and covers the head through the round end (the capsule's top is 0.2 m over the eye). Looking straight up at the settings' distance the ground leaves the camera about 0.26 m off the axis at 0.6 m shoulder, hidden; at the full 1 m shoulder about 0.43 m, outside the body and its near plane, so the body is drawn from beside, not from inside.

### Hand-back check

None of the lines apply but the last: the new tests build their own fields, worlds and scenes and touch no state directory or settings. No memory is freed, no file written, nothing parsed, no save layout, budget, list or UI audit case changes.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `... ./build.sh check-android`, `... ./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.

### Open questions, answered

- Segment to the eye or the whole capsule (feet to top): to the eye, as the item says. The top lies inside the eye's 0.4 m end, so the capsule's height adds a parameter and changes nothing drawn.
- The margin: 0261's constant kept. The radius plus the near plane holds round the axis as round the eye.
- Where the feet come from: derived from the eye along the up by the eye height the view was built with, not from the player's position, so the segment is interpolated as the eye is and dips with the crouch's eased progress.
- The block world: same rule, the up `{0, 1, 0}` and `PLAYER_EYE_HEIGHT`. Its look-up case pulls the camera to the same spot as the field's.

### For the main agent

- At the full 1 m shoulder (`THIRD_PERSON_SHOULDER_RANGE` maximum) looking straight up, the camera ends about 0.43 m off the axis, 0.03 m past the threshold, and the body is drawn seen from beside the legs, filling much of the view. Geometrically it is outside the body and its near plane, so the rule shows it. Raising the threshold to catch it would hide the body by walls where it renders fine. Kept as is unless the couch says otherwise.

### Decisions (main agent, 2026-10-05)

1. The threshold stays at 0261's 0.4 m measured to the segment from the feet to the eye. At the full 1 m shoulder looking straight up the camera ends about 0.43 m off the axis and the body is drawn from beside the legs; the couch decides whether that reads wrong, and a new item raises the margin if it does.
