# 0261: The viewer's body hidden when the third person camera reaches the eye

Status: implementing (2026-10-05)

## Goal

A player whose third person camera has been pulled in to the eye sees the world as in first person, not the inside of their own body: below a distance from the eye the viewer's body is not drawn for that viewport.

## Controls

No binding changes.

## Change

- The field's third person camera reports its pulled distance (0220's `field_third_person_position` or its caller); below a threshold (the body's radius plus the near plane, in metres) the viewport skips the viewer's body, as the first person mode does. The block world's camera gets the same rule if its pull-in reaches the eye.
- Presentation only, per viewport per frame.
- Docs: `doc/architecture.md` (the camera bullet of The player on the field), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: with the camera at the eye the viewer's body is not in the draw list; at the settings' distance it is; the other player's body is drawn in both.
- The couch: third person against a wall, back up into it, the body vanishes instead of filling the screen.

## Specification (design, 2026-10-05)

### The rule

`VIEWER_BODY_HIDDEN_WITHIN_METRES :: 0.4` in `src/render_player.odin`, beside `THIRD_PERSON_WALL_MARGIN`. Comment: the drawn body's radius (0.3 m: `PLAYER_WIDTH / 2`, the fallback capsule's 0.3 in `field_player_capsule_ends`; the model's arms reach 0.3125 m from its axis) plus the field's near plane (`FIELD_NEAR_METRES`, 0.1 m), so a camera this close to the eye would put the near plane into the body; the block world's near plane (raylib's 0.05 m) is nearer, so the one value covers both worlds. It is a literal, not `PLAYER_WIDTH / 2 + FIELD_NEAR_METRES`: `FIELD_NEAR_METRES` lives in `loop_field_session.odin` and naming it from the render cluster adds a render to loop edge the code map does not record; a test pins the sum instead. Float metres, presentation only.

`viewer_body_shown :: proc(mode: Camera_Mode, camera_position, eye: [3]f32) -> bool` in `src/render_player.odin`: `mode == .Third_Person && linalg.length(camera_position - eye) >= VIEWER_BODY_HIDDEN_WITHIN_METRES`. The one decision both worlds call. Measured from the eye, as pulled (a camera pulled to the eye, `field_camera_pulled_distance` 0 or the block world's `max(..., 0)`, is exactly at it).

### The seam (field)

- `field_viewport_camera` (`loop_field_session.odin`) returns `(camera: rl.Camera3D, body_shown: bool)`; `body_shown = viewer_body_shown(player.field.camera_mode, camera.position, world_position_to_metres(view.eye))`, from the pulled camera before `arrival_viewport_camera`'s shake (the descent hides the players anyway).
- `draw_field_viewport_world`: the nested call is split (`pulled, body_shown := field_viewport_camera(...)`, then `arrival_viewport_camera(..., pulled, ...)`), and the scene gets `viewer_body_shown = body_shown`. Per viewport per frame, so in split screen only the viewport whose camera is pulled in skips its own player.
- `Field_Scene` gains `viewer_body_shown: bool` after `viewer`; the struct's comment changes "its body only in third person" to "its body only where `viewer_body_shown` (third person, the camera at least `VIEWER_BODY_HIDDEN_WITHIN_METRES` from the eye, 0261)". Zero hides the viewer, so every builder sets it.
- `field_player_body_drawn :: proc(scene: Field_Scene, index: int) -> bool` (`loop_field_session.odin`): `index != scene.viewer || scene.viewer_body_shown`. `draw_field_players` calls it in place of its mode check. It is what the tests read: the 3D pass has no draw list (the draw list of the hand-back check is the UI's), so the per player decision is the testable seam.
- The planet preview: `planet_preview_raylib_camera` returns `(rl.Camera3D, bool)`, the walk's `viewer_body_shown(body.camera_mode, camera.position, world_position_to_metres(view.eye))`, `false` for the free camera; `planet_preview_scene` takes it as a third parameter `viewer_body_shown: bool` and sets the field; `draw_planet_preview` passes it on.

### The block world

Its pull-in reaches the eye (`third_person_position`: `max(hit.distance - THIRD_PERSON_WALL_MARGIN, 0)`; backed against a wall the body's 0.3 m half width leaves the camera about 0.1 m behind the eye), so the same rule applies. `draw_player_world_overlay` (`render_player.odin`) takes a last parameter `body_shown: bool` in place of its `player.camera_mode == .Third_Person` check; its comment "The body shows in third person only" becomes "The body shows where body_shown (viewer_body_shown, 0261)". `draw_session_world` (`loop.odin`) passes `viewer_body_shown(player.camera_mode, view.position, player_eye(pose.position))`. The first person arm pass stays on `player.camera_mode == .First_Person`: a pulled in third person camera draws no arm.

### Tests

- `test_the_viewers_body_is_shown_only_past_the_hidden_distance` (`render_player_test.odin`): with eye `{1, 2, 3}` and `.Third_Person`, false at the eye and at `eye + {0, 0, VIEWER_BODY_HIDDEN_WITHIN_METRES - 0.01}`, true at `eye + {VIEWER_BODY_HIDDEN_WITHIN_METRES + 0.01, 0, 0}` and at `eye + third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE_RANGE.minimum, 0)`; `.First_Person` false at that last point; `abs(VIEWER_BODY_HIDDEN_WITHIN_METRES - (PLAYER_WIDTH / 2 + FIELD_NEAR_METRES)) < 1e-6`.
- `test_the_field_viewers_body_is_hidden_with_the_camera_at_the_eye` (`render_field_camera_test.odin`): for `TEST_FIELD_SPACINGS`, the 4 m ledge and `near_eye` of `test_the_field_third_person_camera_stops_short_of_a_wall` (0.1 m short of the face, offset `{4, 0, 0}`); the position is the eye; `scene := Field_Scene{viewer = 0, viewer_body_shown = viewer_body_shown(.Third_Person, position, world_position_to_metres(near_eye))}`; `field_player_body_drawn(scene, 0)` false, `field_player_body_drawn(scene, 1)` true.
- `test_the_field_viewers_body_is_drawn_at_the_settings_distance` (same file): for `TEST_FIELD_SPACINGS`, the flat field and `start_crouch_test_player`, `view := field_player_view(player, tuning, 1, 0)`, the position from `field_third_person_position` with `field_third_person_offset(view, THIRD_PERSON_DISTANCE, 0.6)`; the scene as above: player 0 and player 1 both drawn.
- `test_the_block_viewers_body_is_hidden_when_the_camera_reaches_the_eye` (`player_test.odin`): the world, registry and eye of `test_third_person_camera_pulls_in_before_a_wall`; stone at `{-1, y, 0}` for y 1 to 6 (its face 0.5 m from the eye along x, the camera about 0.31 m out): `viewer_body_shown(.Third_Person, blocked, eye)` false; the same with stone at `{-2, y, 0}` only (about 1.33 m out): true.

### Docs

- `doc/presentation.md`, The player, the bullet "First person draws the right arm ...": append ", except while its camera is pulled in within `VIEWER_BODY_HIDDEN_WITHIN_METRES` (0.4 m, the body's 0.3 m radius plus the field's 0.1 m near plane) of the eye, where the viewport draws neither its own body nor the arm, as if in first person (`viewer_body_shown`, 0261); other players' bodies are drawn either way." This is the rule's one home.
- `doc/presentation.md`, The field session, the scene bullet: "every player's body but the viewer's in first person" becomes "every player's body but the viewer's in first person or with its camera pulled in to the eye (`Field_Scene.viewer_body_shown`, `field_player_body_drawn`, 0261)".
- `doc/architecture.md`, The player on the field, the cameras bullet, appended: "Pulled in within `VIEWER_BODY_HIDDEN_WITHIN_METRES` of the eye, the viewport skips the viewer's body ([presentation.md](presentation.md), The player)."
- `doc/code_map.md`: no change (no new cluster edge; the constant is a literal for that reason).
- `doc/log/2026-10-05.md`, the main agent's section at the landing, from:

  ## The viewer's body hidden with the camera at the eye (0261)

  Tags: field, block-world, camera, third-person, presentation, body, split-screen, 0261, m14

  The distance is measured from the eye, not from the body's capsule: the wall the item names puts the camera on the eye's line. The value is 0.4 m for both worlds, the field's near plane setting it; the block world's 0.05 m near plane would allow 0.35 m. The decision is taken on the pulled camera before the arrival's shake. Hidden, the view is first person without the arm: the arm pass follows the camera mode. Left: looking steeply up in third person, the offset points down through the body, the ground pulls the camera in to about the feet, more than 0.4 m from the eye, and the body is drawn round it.

### Hand-back check

None of the lines apply but the last: the new tests build their own fields, worlds and scenes and touch no state directory or settings. No memory is freed, no file written, nothing parsed, no save layout, budget, list or UI audit case changes.

### Verify

`taskset -c 8-15 nice -n 10 ./build.sh check`, `... ./build.sh check-android`, `... ./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.

### Screenshots (the main agent, a headless session on the item's build and on `main`'s for the pair)

```
tools/moc pause
tools/moc tick 800
tools/moc query entities pod
tools/moc teleport <x> <y> <z>
tools/moc look at <x2> <y2> <z2>
tools/moc camera third
tools/moc tick 2
tools/moc screenshot 0261-back-to-the-hull
tools/moc camera first
tools/moc tick 2
tools/moc screenshot 0261-first-person-same-spot
tools/moc teleport <latitude> <longitude>
tools/moc camera third
tools/moc tick 30
tools/moc screenshot 0261-open-ground
```

From the pod's `centre` C, `teleport` to the ground point P outside the hull along the pod's forward, 3.35 m from C (the 12 cell hull's half width at 0.5 m pitch plus the body's radius and 5 cm; the next tick pushes the feet out if that is ground), and `look at` P + (P − C) at eye height, so the camera's line runs back into the hull. Read: `0261-back-to-the-hull` shows the world as `0261-first-person-same-spot` does, no body (on `main` the same lines show the inside of the body); `0261-open-ground` (a latitude 0.05 degrees off the home) shows the body at the settings' distance. Where the cone's hull has open cells at P's height the camera is not pulled in; move P round the hull or use the cabin (`teleport pod`, `look 0 0`, `look 90 0`, `look 180 0`, `look 270 0`) and pick the bearing whose camera meets a wall.

### Open questions, answered

- Distance from the eye or from the body: the eye, as the item says; the camera is cast from the eye, so the wall case is on that line. The look-up case is left (the log names it).
- Field near plane (0.1) against the block world's (0.05): one constant, the larger sum; a separate 0.35 for the block world buys 5 cm nobody sees.
- Draw the first person arm while hidden: no, the arm pass is the first person mode's and the item asks only for the body to go.
- Before or after the arrival's shake: before, so the shake's few centimetres do not flicker the body at the threshold.
- The planet preview's walk: same rule, since `Field_Scene.viewer_body_shown`'s zero would otherwise hide its body for good.

### For the main agent

- The look-up case (third person, pitch near 89 degrees: the camera ends near the feet and inside the legs) is outside the eye rule. A rule on the distance to the body's axis segment would cover it at the cost of the feet and height in both cameras' seams; a new item if wanted.

Decided (main agent, 2026-10-05): approved as written; the look-up case is 0267, not this item.

Designed by reading the item, 0220's log and item, `render_field_camera.odin`, `render_player.odin`, `loop_field_session.odin`, `loop.odin`, `loop_planet_preview.odin`, the camera tests, `doc/commands.md`, `doc/code_map.md` and raylib's `rlgl.h` near plane; no build was run.
