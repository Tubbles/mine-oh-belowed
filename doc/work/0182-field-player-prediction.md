# 0182: Prediction of the field player under the lockstep window

Status: implemented (M13 follow up, from the switch of 0179; before the multiplayer couch test)

## Goal

The local field player's view follows the input the same frame when the lockstep window is above zero. Today `rebuild_prediction` and `predict_player_motion` (`lockstep.odin`) move the block player only, so in an online session the field player's view lags by the window.

## Change

- The prediction runs `tick_field_player` on a copy of the local player's field state for the inputs not yet confirmed, as the block world's prediction does, against the loaded set and the frame table; the renderer draws the predicted feet and look, the simulation's state is untouched.
- When the confirmed state differs from the prediction, the correction follows the block world's rule (snap or blend, whichever it uses), documented in `doc/architecture.md` (Lockstep).
- Offline (window zero) nothing changes.

## Verify

- The build and check commands of 0168.
- Tests: with a window of three ticks the predicted position after a walk press equals the simulated one three ticks later; a predicted move into a wall corrects to the confirmed position; the simulation's hash is the same with and without the prediction.
- Two machines on the home network: the user judges the walk's response at the window the session settles on.
