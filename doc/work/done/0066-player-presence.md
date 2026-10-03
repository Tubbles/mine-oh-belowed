# 0066 The player has hands

Status: implemented
Milestone: M11

## Goal

The player is a capsule. First person hands with the held tool and a swing, a third person body, walk and mine animations, footstep dust.

## Deliverables

- First person: hands and the held item or tool from the model pipeline, a swing on mine and place, a bob that respects the reduced motion setting.
- Third person: a body model with walk, sprint, mine and place animations; the camera keeps its shoulder offset.
- Tests: animation phase from movement and mining state.

## Verify

- Builds and tests pass.
- User: Screenshots in both camera modes.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. Lands after 0067 particles (the footstep dust uses its pool); read 0067's Implemented paragraph first.

- Models through the pipeline (0055): `tools/make_placeholder_models.py` gains a player set written to `data/models/`: `player_torso.vox`, `player_head.vox`, `player_arm_left.vox`, `player_arm_right.vox`, `player_leg_left.vox`, `player_leg_right.vox`, at 16 voxels per block inside a 0.6 by 1.8 by 0.6 block frame (10 by 29 by 10 voxels, the torso and head above the legs, the arms beside the torso), in a suit colour with a darker visor, generated deterministically and committed. A new `src/render_player_model.odin` loads the set with the vox reader and mesh builder (`model_vox.odin`, `model_mesh.odin`) into one `Player_Model` of six uploaded layers with a pivot per limb (the shoulder for an arm, the hip for a leg, in the model frame), rebuilt on a model file change like machine models (`reload_models`, `src/hot_reload.odin`). Missing files fall back to the capsule drawn today.
- Animation, in a new `src/player_animation.odin` (pure, tested): the walk phase comes from the walked distance the statistics already count (`distance_walked_millimetres`, one cycle per 1.6 metres), so no animation state is kept and the phase is deterministic; arms and legs swing in opposition by up to 35 degrees at walking speed and 50 sprinting (`player.sprinting`), zero when the distance did not change since the last frame (the renderer keeps the last frame's distance in `Frame_State`); the mine swing: while the player's mining progress is active (`Mining_State.active`) the right arm swings down and back over 0.4 seconds repeatedly, phase from the render time; the place swing: one 0.25 second swing when the placed counters grew since the last frame (`statistics.placed` and `blocks_placed` totals kept in the same frame memory); head bob: a vertical sine from the walk phase, amplitude 0.03 blocks walking and 0.05 sprinting, applied to the first person camera position and off under the new `head_bob` setting (`src/settings.odin`, default true, a toggle on the Display tab, `src/ui_screens.odin`, `src/configuration_test.odin`, strings). 0073 loses its "head bob toggle" deliverable to this item (edit its file to say so); 0074 folds the toggle into reduced motion later.
- First person: after the world and before the UI, inside a second short 3D pass with the depth test off (`rlgl.DisableDepthTest`, batch flushed) so the arm draws over the world: the right arm model posed relative to the camera (lower right of the view, its shoulder pivot fixed to the camera, the swing and bob applied) and the held item as its icon billboard at the hand (`Item_Billboards`, 0060), or a tool's icon; nothing when the hotbar slot is empty. The arm follows the interpolated pose, not the tick.
- Third person: the body from the six limbs at the interpolated pose (`interpolate_player_pose`), turned by the yaw, limbs posed by the phases above, the head pitched with the look; replaces `draw_player_body`'s capsule when the model loaded. The camera keeps `THIRD_PERSON_DISTANCE` and `THIRD_PERSON_HEIGHT`.
- Footstep dust: each time the walk phase crosses a half cycle while `player.on_ground` and not in water, a small puff burst (6 particles of the `Puff` kind, 0067) in the colour of the block under the feet, through the particle system in `Frame_State`; also off under the head bob setting? No: dust stays, only the bob is motion the setting governs.
- Tests (`src/player_animation_test.odin`, `src/render_player_model_test.odin`): the walk phase from the distance, swing angles at phase 0, a quarter and a half, sprint amplitude, the mine swing period, the place swing fires once per growth of the counters, the bob amplitude and the setting, the step detector fires once per half cycle, the player model set loads from the committed files with the expected voxel bounds per limb and pivots inside the frame, the configuration round trips `head_bob`, the UI audit passes with the toggle.
- Docs: `doc/ui.md` (the setting, the hands), `doc/architecture.md` (rendering: the player), `doc/content.md` (the model set in `data/models/`), `doc/work/done/0073-camera-polish.md` (the head bob line), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: new `src/render_player_model.odin`, `src/render_player_model_test.odin`, `src/player_animation.odin`, `src/player_animation_test.odin`; `src/render_player.odin`, `src/hot_reload.odin`, `src/loop.odin` (the state fields, the model load and the draw calls), `src/settings.odin`, `src/configuration_test.odin`, `src/ui_screens.odin`, `src/ui_audit_test.odin`, `tools/make_placeholder_models.py`, new `data/models/player_*.vox`, `data/strings/en.sjson`, the docs above, `doc/work/done/0073-camera-polish.md`, this file.

Implemented: new `src/player_animation.odin` (the walk phase, the swings, the head bob, the step detector, `Player_Animation_Memory`) and `src/player_animation_test.odin`; new `src/render_player_model.odin` (the limb set's loader, the pivots from the voxel bounds, the body, limb and first person transforms, the upload and reload) and `src/render_player_model_test.odin`; `src/render_player.odin` (the bob in `player_view_camera`, the body in place of the capsule, `draw_first_person_hands`, the footstep dust); `src/loop.odin` (the `Frame_State` fields, the model's load and unload, the memory reset in `enter_session`, the animation, bob and draws in `draw_session_world`, whose world pass now ends before the first person pass); `src/hot_reload.odin` (`reload_models` also reloads the player); `src/settings.odin` (`head_bob`), `src/ui_screens.odin` (the Display tab toggle), `src/configuration_test.odin`, `data/strings/en.sjson`; `tools/make_placeholder_models.py` and the six `data/models/player_*.vox`; `doc/ui.md`, `doc/architecture.md`, `doc/content.md`, `doc/work/done/0073-camera-polish.md`. Decisions the item left open are in `doc/log/2026-09-28.md`. 858 tests pass.
