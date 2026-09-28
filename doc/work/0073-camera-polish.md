# 0073 Camera polish

Status: implemented
Milestone: M11

## Goal

Field of view, a sprint kick and the third person shoulder as settings, all off under reduced motion. The head bob and its toggle came with 0066.

## Deliverables

- FOV setting, sprint FOV kick, third person shoulder offset setting (the head bob toggle is 0066's).
- Tests: the settings round trip and the reduced motion rule.

## Verify

- Builds and tests pass.
- User: Try each on the couch.

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous. The head bob toggle went to 0066; 0074 adds the reduced motion rule that turns the kick and the bob off together, so this item only adds the settings and reads them.

- Settings (`src/settings.odin`, defaults, `src/configuration.odin` ranges and `src/configuration_test.odin`, the Display tab in `src/ui_screens.odin` after the window rows, strings): `field_of_view` (degrees, 60 to 110, default 70, replacing `CAMERA_FIELD_OF_VIEW_DEGREES` in `src/render_chunks.odin`), `sprint_field_of_view_kick` (degrees added while sprinting, 0 to 15, default 6, eased in and out over 0.3 seconds by a pure blend of the frame time), `third_person_distance` (2 to 8 blocks, default `THIRD_PERSON_DISTANCE`) and `third_person_shoulder` (-1 to 1 blocks sideways, default 0.6 so the player stands to the left of centre; `third_person_position` in `src/render_player.odin` offsets along the camera's right vector and keeps its wall pull in). Sliders like UI scale, applied at once.
- Tests: the configuration round trip and the out of range refusals, the kick blend over time, the shoulder offset direction from the yaw, the UI audit with the rows.
- Docs: `doc/ui.md` (the settings), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: `src/settings.odin`, `src/configuration.odin`, `src/configuration_test.odin`, `src/ui_screens.odin`, `src/ui_audit_test.odin`, `src/render_chunks.odin`, `src/render_player.odin`, `src/render_player_test.odin` if it exists or new, `src/loop.odin` (the camera call), `data/strings/en.sjson`, the docs above, this file.

Implemented: `src/settings.odin` (the four settings, defaults and slider ranges), `src/configuration.odin` (their range checks), `src/configuration_test.odin` (round trip, both range ends, out of range and type refusals), `src/ui_screens.odin` (`camera_settings` after the window rows, 18 Display rows), `data/strings/en.sjson`, `src/render_chunks.odin` (`fly_camera_to_raylib` takes the field of view, the constant is gone), `src/render_player.odin` (`third_person_offset`, `camera_right`, `advance_sprint_kick`, `sprint_field_of_view`), `src/render_player_test.odin` (new: the kick blend and the shoulder direction), `src/loop.odin` (`Frame_State.sprint_kick` and the camera call), `doc/ui.md`, `doc/log/2026-09-28.md`. Outside the list, `src/player_test.odin` and `src/render_player_model_test.odin` follow the changed signature and the removed constant (see the log). The UI audit's Display tab case walks the new rows. 935 tests pass.
