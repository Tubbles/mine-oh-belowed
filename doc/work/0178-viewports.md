# 0178: Viewports: up to four local players on one screen

Status: todo (after 0177)

## Goal

Split screen: one simulation, up to four local players, each with a viewport holding a camera, a HUD, screens, a selection and an input device; the interaction and presentation groups of `Frame_State` per viewport, the developer and reload groups global; the render pass once per viewport; frame requests per player where they belong to a screen and global where they belong to the game (decision 30; 0167, Split screen).

## Change

- A viewport record in the loop cluster: the player's index in the simulation's player array, the camera, its `Frame_Interaction` and `Frame_Presentation`, its `Ui_State` and `Screen_Context`, its input device (a gamepad id through SDL, the keyboard and mouse, or the touch overlay), its screen rectangle. `Frame_State` holds the viewports beside the global groups.
- Layout: one viewport full screen, two side by side or stacked (a setting), three and four in quarters; the UI audit sizes gain a quarter of 1080p and the HUD and screens fit it (the smallest audit size rule of the hand-back check).
- Input: a gamepad joining (a press of Start on an unassigned pad) adds a local player and a viewport; the bindings per device as today.
- Rendering: the world drawn once per viewport with the level of detail of 0169; the presentation's per frame memories (the cue detector of 0162) per viewport.
- Requests: a screen's request (open a data file, take a screenshot) carries its viewport; quit, reload and save are global.
- `doc/architecture.md` (Frame and tick: viewports), `doc/ui.md` (the audit sizes), `doc/input.md` (joining) updated.

## Verify

- The build and check commands of 0168; `ui_audit_test.odin` at the quarter size.
- Tests: two viewports draw two draw lists from one simulation with different cameras; a pad press adds a viewport and a player at the pod; a screen request from the second viewport serves that viewport's screen and not the first's; a global request serves once; the frame with four viewports runs the tick once.
- The couch: four pads, four viewports, the user judges the legibility at the quarter size.
