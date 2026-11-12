# 0372: A blue slab under the view when looking down

Status: landed (2026-11-12, aa7244f)

0342's check captures of the factory view (2026-11-11, `--dev --input=none`, fly on, the look 33 degrees down, the wooden foundation held) show a flat blue trapezoid across the bottom fifth of the picture, behind the hotbar, in one viewport and in both of two. It keeps its place on the screen in every viewport, so it moves with the camera. The spring and the other views, looking level with fly off, do not show it. What it is has not been read in the code: the player's own body seen from its eye is the main agent's guess, and the implementer's reading (the hotbar) does not fit, since the hotbar's slots are drawn over it.

## Goal

Looking down shows the ground, or a body that reads as one.

## Controls

None.

## Change

- Find what draws it (the player's body in first person, a held item's model, fly mode's own draw) and with which pitch and mode it appears.
- Hide what the eye is inside of, or draw it so it reads.

## Verify

- The checks and the suite.
- Captures looking down at 33 and at 80 degrees, on foot and flying, in one and two viewports, sent to the user.

## Specification (design, 2026-11-12)

### Cause

The slab is the top face of the other player's torso, seen from inside that player's head. `tools/frame_profile.py` frames every player of a run on one stand (`frame_players`: `fly on`, `teleport <feet>`, `look at`, then the same lines `as 1`), and the factory runs in two viewports before one (`planned_runs`), so in every factory capture player 1 stands at player 0's feet with player 0's look; `viewport remove` leaves player 1's entry in the world (`leave_local_player`, `session_network.odin:1086`: "its entry stays in the world for a later join"). The field's walk does not keep bodies apart (`tick_field_player` takes no other player), so two players on one spot also happen in play.

- Drawn by `draw_field_players` (`loop_field_session.odin:540`) through `draw_field_player_body` (`:437`): `field_player_body_drawn` (`:454`) hides only the viewer's own body, never another's.
- The torso (`tools/make_placeholder_models.py`, `player_torso`, voxels x 3..6, y 13..22, z 2..7 at 16 a metre, centred by `player_model_point`) has its top at 1.4375 m, 0.1625 m under the 1.6 m eye (`eye_height_millimetres`), 0.25 m deep and 0.375 m wide. The head (`player_head`, 1.4375 to 1.8125 m) holds the eye, so its faces are back faces and culled. At the capture's pitch (33.1 down) and 70 degree field of view the face's front edge falls at row 810.5 and its corners at x 212 and 1708 of 1920; the captures show the edge at about 810 and the corners at 212 and 1709, the sides meeting at the look's horizon point (y 35 against 39), symmetric about the centre. The arm tops start 69 degrees down, just under the view's bottom edge.
- Colour: the suit, `SUIT` (60, 110, 200), measured (45, 90, 173) on the near left to (64, 123, 228) on the far right, opaque and untextured, under the open sky with the head's shadow on it.
- When: the camera within the other body's head and the look more than about 17 degrees down (the front edge 52.4 degrees under the eye less half the 70 degree field), on foot or flying alike. It sits on the other body, not on the camera: it seemed to move with the camera because both players had the same feet and look.
- Evidence beyond the geometry: every frame profile factory capture (tmp/0342/check_factory, check_factory2, tmp/frame_profile/night, after, after_0347, check_0347) was taken with player 1 on the stand and shows it; `tmp/fade_main` framed the same stand with no `viewport add` (its log has no second player) and shows none. The GPU (radeonsi against llvmpipe) is not the difference.
- Ruled out: the ghosts are white or red and see-through (`FRAME_GHOST_COLOR`, `GHOST_INVALID_COLOR`) and the stand lies past the reach (`stand_fits`); the water is see-through (`FIELD_WATER_COLOR` alpha 0.62); a field session draws no hands (`draw_first_person_hands` only from the block world's pass, `loop.odin:1377`) and no underwater overlay (`draw_viewport_world` returns before it, `loop.odin:954`); fly mode draws nothing of its own; the flat batch's slabs, edges, torch boxes and runs are none of them blue; the capsule (`FIELD_PLAYER_CAPSULE_COLOR`) stands in only without the model, which loads.

A defect: a body the near plane cuts into reads as a flat blue sheet, never as a body. The viewer should see what lies beyond it, the ground, as 0261 already decided for the viewer's own body: the camera within `VIEWER_BODY_HIDDEN_WITHIN_METRES` (0.4 m, the body's radius plus the near plane) of a body's axis puts the near plane into it, so it is not drawn. Recommendation: apply that rule to every other standing body. Alternative: keep the bodies apart in the walk (players push each other), a simulation change under the hash and the lockstep, which also stops the overlap but not a teleport onto another; a separate item if the user wants it.

Presentation only: the simulation, the hash and the save are untouched; the sun's shadow pass still draws every body (a body the viewer stands in casts its shadow as before).

### Change

`src/render_player.odin`:
- `camera_clear_of_body :: proc(camera_position, eye, up: [3]f32, eye_height: f32) -> bool`: the camera at least `VIEWER_BODY_HIDDEN_WITHIN_METRES` from the body's axis from the feet to the eye; the distance part of `viewer_body_shown`, moved out as is. `viewer_body_shown` becomes `mode == .Third_Person && camera_clear_of_body(...)`, behaviour unchanged. The comment on `VIEWER_BODY_HIDDEN_WITHIN_METRES` says it holds for any body's axis (0372).

`src/loop_field_session.odin`:
- `field_player_feet :: proc(scene: Field_Scene, player: Field_Player) -> [3]f32`: the feet between the ticks at `scene.frame.alpha`, the two lines moved out of `draw_field_player_body`, which calls it.
- `field_standing_body_clear :: proc(scene: Field_Scene, player: Field_Player, crouch_progress: f32, camera: [3]f32) -> bool`: `camera_clear_of_body` for the body at `field_player_feet`, its up (`unit_vector_to_f32(player.up)`), its eye that up times the eye height at its crouch progress (`field_eye_height_units(scene.content.field.tuning, crouch_progress)` in metres, as `field_viewer_body_shown` converts it). Pure.
- `draw_field_players :: proc(scene: Field_Scene, camera: Maybe([3]f32) = nil)`: as now, but a `.Standing` body is skipped when a camera is given and `field_standing_body_clear` is false. The pose (`field_player_body_pose`, `field_player_body_drawn`) is unchanged, so the seated and cradled rules and their tests stay. The comment names 0372 and that nil (the sun's shadow pass, `draw_sun_shadow_models`, unchanged call) draws every body.
- `draw_field_scene`: `draw_field_players(scene, transform_point(linalg.inverse(view.transform), camera.position))`, the camera taken back into the space the bodies are drawn in (`view.transform` is the pod's transform or the identity, as `draw_field_viewport_world` does for the arrival's eye at `:1104`). The planet preview draws through the same scene and needs nothing.

No data key, no binding, no string, no save change.

### Tests

`src/render_field_camera_test.odin`, beside the 0261 tests:
- `test_another_standing_body_round_the_camera_is_not_drawn`: a `Field_Scene` with `content.field.tuning = test_field_tuning(1000)`, `frame.alpha = 1` and a `Field_Player` standing at `test_site_point(0, 0, 0)` (`previous_position` the same) with up `{0, UNIT_VECTOR_ONE, 0}`. `field_standing_body_clear` is false with the camera at its eye (1.6 m up, the profile's two players on one spot), at 0.39 m beside its axis at 0.8 m up, and at 0.39 m under its feet; true at 0.41 m beside and with the camera 4 m behind its eye and 0.75 m up (third person). Crouched (progress 1): false at its crouched eye (0.7 m), true at 1.6 m over its feet (0.9 m over that eye). Moving: `previous_position` 1 m back along x and `frame.alpha` 0.5, false with the camera at the eye over the halfway feet and true at the eye over `position` (0.5 m from the halfway axis), so the feet are interpolated.
- The `viewer_body_shown` tests of `render_player_test.odin` and `player_test.odin` pin the moved distance and keep passing unchanged.

### Docs

- `doc/presentation.md`, The field session, the scene bullet: after "(`Field_Scene.viewer_body_shown`, `field_player_body_drawn`, 0261)" add that another standing body whose axis the camera lies within `VIEWER_BODY_HIDDEN_WITHIN_METRES` of is not drawn either, the camera taken back through the pod's transform (two players on one spot, which the walk allows; the eye in the other's head saw its torso's top as a flat blue sheet, `field_standing_body_clear`, 0372), and that the sun's shadow pass still draws every body.
- `doc/presentation.md`, The player, the first person bullet: "other players' bodies are drawn either way" becomes "other players' bodies are drawn either way, on the field except a standing one the camera lies within that distance of (0372)".

### Hand-back check

None of the lines applies: nothing frees memory, writes a file, loads at start, parses a number, changes a save, joins a budget, grows a list, touches a UI audit case or a state directory. Said so in the report.

### Captures (main agent, before the implementation and after it)

A headless session as the usual capture script starts it (`--dev --input=none`, the default seed, the frame profile's world; isolated XDG directories; `SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT=0x0000/0x0000`), each line through `tools/moc`. The stand is the frame profile's factory stand (`teleport -684.914 7947.753 709.772`, answered "latitude 82.9255 longitude 133.9789"), the look its bearing (`yaw 68.8`).

1. Preparation: `pause`, `tick 1920`, `resume`, `seat stand`, `camera first`, `weather clear`, `time noon`, `view_distance 512`, `press Hotbar_Slot_1` (the wooden foundation, slot 1 of a new world).
2. Control, one player: `fly on`, `teleport -684.914 7947.753 709.772`, `look 68.8 -33`, `screenshot solo_fly33` (no slab before or after).
3. Flying, two viewports: `viewport add` (the answer names the player, 1), `as 1 fly on`, `as 1 teleport -684.914 7947.753 709.772`, `as 1 look 68.8 -33`, `screenshot fly33_2vp`; `look 68.8 -80`, `as 1 look 68.8 -80`, `screenshot fly80_2vp`.
4. Flying, one viewport: `viewport remove` (player 1 stays on the stand), `screenshot fly80_1vp`; `look 68.8 -33`, `screenshot fly33_1vp`.
5. On foot, two viewports: `viewport add` (note the index it answers, n), `fly off`, `teleport 82.926 133.979`, `as <n> fly off`, `as <n> teleport 82.926 133.979`, `tools/moc --until 'on_ground true' query player`, `look 68.8 -33`, `as <n> look 68.8 -33`, `screenshot foot33_2vp`; `look 68.8 -80`, `as <n> look 68.8 -80`, `screenshot foot80_2vp`.
6. On foot, one viewport: `viewport remove`, `screenshot foot80_1vp`; `look 68.8 -33`, `screenshot foot33_1vp`.
7. After only, a guard: `viewport add`, the new player framed as in 5 (`as <m>`), `camera third`, `look 68.8 -33`, `screenshot third33_2vp`: viewport 1's camera stands 4 m behind, so both bodies are drawn.

Before: the slab in every capture of 3 to 6 (at 80 degrees the torso's top fills most of the lower half), none in 2. After: the ground (and the pad from the stand) in every one, as in 2.

### Open questions answered

- What draws it: the other player's torso (above), not the viewer's own body (hidden in first person since 0261), a held item's model or fly mode.
- With which pitch and mode: more than about 17 degrees down at 70 degrees, the camera inside another body; flying does not matter.
- Hide or draw it so it reads: hide. No body can read from inside its own head, and 0261 chose hiding for the same near plane case; a fade near the camera would need see-through model draws and sorting for a case seen only when two players overlap.

### Not decided (for the main agent)

- A split screen player who left keeps a standing body where it left (0178's kept entry), which is why the one viewport factory captures show one. Whether a left player's body should stay drawn is a question for the user, outside this item.
- A seated body is not covered (the chair's eye is a standing player's only if the walk can bring an eye into the chair, which was not checked); the change touches the standing pose only.

### Decisions (main agent, 2026-11-12)

1. Approved as specified: another standing body round the camera is hidden by the rule 0261 has for the viewer's own.
2. Keeping bodies apart in the walk is not this item (a simulation change under the hash).
3. Whether a split screen player who left keeps a drawn body where it stood (0178) is asked of the user, outside this item. A seated body is not covered here.
