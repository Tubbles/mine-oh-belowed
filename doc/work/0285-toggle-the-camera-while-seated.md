# 0285: Toggle the camera while seated

Status: verified (2026-10-05)

## Goal

A player seated in the pod's chair after the touchdown toggles the third person camera as a standing one does. 0268 lifted the forced first person for `Seated`, but the seated tick (`tick_seated_field_player`, `SEATED_FIELD_ACTIONS`) still drops `Toggle_Camera_Mode`, so a seated player keeps the mode they sat down with. The strapped descent stays first person.

## Controls

No binding changes: the existing camera toggle reaches the seated tick.

## Change

- `SEATED_FIELD_ACTIONS` admits `Toggle_Camera_Mode` and the seated tick applies it as the standing one does. The strapped tick keeps dropping it. The simulation's action set changes, so the lockstep hash of a seated toggle is covered by a test.
- Docs: `doc/input.md` (the chair's actions), `doc/presentation.md` (the camera rule of 0223 and 0268).

## Verify

- Tests: a seated player's toggle changes the camera mode, a strapped one's does nothing, the hash agrees between host and joiner.
- The couch: sit, toggle, see the seated body.

## Specification (design, 2026-10-05)

Designed against 0268's worktree (`.claude/worktrees/0268`, snapshot `6b2e833`), not `main`: `field_view_camera_mode` there already returns the stored mode for `Seated`. Build this item's worktree from `item/0268`.

### Answers

- The camera mode is simulation state: `Field_Player.camera_mode` is a field of `Player.field`, written by `write_value_of` in `write_simulation_state`, so it enters `simulation_state_hash` and `lockstep_state_hash`. The toggle already travels as `Toggle_Camera_Mode` in the input record's action set, so no record, save or command change. The hash test below covers a seated toggle.
- Where the strapped player loses the toggle: at the frame cut, by seat. `seated_field_frame` serves both seats today with one set, so it gains the seat. The seated tick also checks the seat itself, so a direct call with a strapped body and a toggle changes nothing either.
- The prediction (`predict_field_player_motion`) runs the same cut and the same tick (`move_and_aim_field_player` calls `tick_field_player`), so a seated toggle shows at once, as a standing one does. Nothing to add there.
- A toggle in the tick that stands the player from the chair: `interact_on_field_chair` runs before the cut, so the seat is already Standing and the standing tick applies the toggle. Unchanged.

### Code

- `src/simulation_field.odin`
  - `SEATED_FIELD_ACTIONS :: Action_Set{.Open_Aimed, .Toggle_Camera_Mode}`: what a Seated player's frame keeps. Comment names 0285.
  - New `STRAPPED_FIELD_ACTIONS :: Action_Set{.Open_Aimed}`: what a Strapped player's frame keeps (0223's set, unchanged for the strapped body).
  - `seated_field_frame :: proc(frame: Input_Frame, seat: Field_Seat) -> Input_Frame`: masks `pressed` and `just_pressed` with `SEATED_FIELD_ACTIONS` when `seat == .Seated`, else `STRAPPED_FIELD_ACTIONS`. Update its comment. Callers: `tick_field_session_player` (same file) and `predict_field_player_motion` (`src/lockstep.odin`), both pass `player.field.seat`. Update the comment above `tick_field_session_player` ("keeps the look and Open_Aimed alone") to name the camera toggle while Seated.
- `src/player_field.odin`
  - `tick_seated_field_player` (signature unchanged): when `player.seat == .Seated`, calls `apply_field_player_toggles(player, input.just_pressed & {.Toggle_Camera_Mode})` first, so only the camera toggles and fly and no clip stay untouched. Its comment drops "no toggle" and says the camera toggles while Seated, never Strapped (0285).
- `field_view_camera_mode` (`src/loop_field_session.odin`) unchanged.

### Tests

- `src/simulation_arrival_test.odin`, `test_the_camera_toggles_seated_and_not_strapped`: `arrival_test_config` with `arrival_ticks = 0` (as `test_interact_on_the_chair_seats_and_unseats`), one session. The frame `Input_Frame{pressed = {.Toggle_Camera_Mode, .Toggle_Fly_Mode, .Toggle_No_Clip}, just_pressed = the same}`. Player 0 put in with `seat_field_player(..., .Strapped)`, camera First_Person: one tick with the frame leaves `camera_mode` First_Person, `flying` and `no_clip` false. `seat_field_player(..., .Seated)`: one tick with the frame gives Third_Person, `flying` and `no_clip` false, `seat` Seated and `position` unchanged. A second tick gives First_Person. Then a direct `tick_seated_field_player` on a copy of the body set Strapped with `just_pressed = {.Toggle_Camera_Mode}` leaves the mode as it was.
- `src/lockstep_test.odin`, `test_the_prediction_toggles_the_camera_seated_and_not_strapped`: as `test_the_prediction_holds_a_seated_player`, a copy of player 0 Seated, one `predict_field_player_motion` with the toggle frame gives Third_Person and the same position. A copy Strapped gives First_Person.
- `src/simulation_arrival_test.odin`, `test_a_seated_camera_toggle_keeps_two_sessions_alike`: three sessions as in the first test, player 0 Seated in each. The first two tick the toggle frame, then ten empty frames, and their `simulation_state_hash` agree (the host and the joiner applying the same record). The third ticks only empty frames and its hash differs from the first, which shows the mode is hashed.
- Existing tests that stay valid unchanged: `test_the_prediction_holds_a_seated_player`, `test_interact_on_the_chair_seats_and_unseats`, `test_toggle_camera_mode`, `render_field_camera_test.odin`'s `field_view_camera_mode` cases.

### Docs

- `doc/input.md`, the Interact bullet (the chair, "Strapped in or seated the look is free ..."): add that seated, not strapped, the camera toggle switches first and third person as on foot (0285).
- `doc/presentation.md`, The player, the seated bullet: replace "Seated by choice it is the stored mode the player sat down with, since the toggle does nothing in the chair" with: seated by choice it is the stored mode, which the camera toggle switches in the chair as on foot (0285).
- `doc/architecture.md`, Bodies, the seat bullet (0223): the session tick cuts the frame to the look and Open_Aimed, and Seated also keeps Toggle_Camera_Mode, which the seated tick applies (`seated_field_frame` by seat, 0285).
- `doc/code_map.md`: no new procedure, nothing to change. Run its check.

### Hand-back check

- Old saves: no layout change. A save with a seated player loads with its stored mode, which now toggles. Nothing to log.
- Shared budget, unbounded lists, memory freed under a frame, file writes, parsed numbers, UI audit cases: none apply.
- Tests use the in-memory field sessions only, no state directory.

### For the main agent

- Nothing left open. Only `doc/presentation.md` states the rule 0285 replaces (a seated player keeps the mode it sat down with). If 0268's log section, written at its landing, repeats that rule, 0285's log section names the change.

### Decisions (main agent, 2026-10-05)

1. Approved as designed, on 0268's snapshot. The log section of 0285 names the change to 0268's rule (a seated player kept the mode they sat down with).
