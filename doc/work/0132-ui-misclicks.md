# 0132: Misclicks in the menus

Status: todo

## Goal

Reported on 2026-09-30 from the phone and the couch, three ways the menus act without being asked. Each report is ground truth; the mechanism named below is what the code reading found and the headless reproduction must confirm it (or find the real one) before the fix.

1. "On gamepad and touch, when eg entering a submenu like dev, automatically toggles fly mode since that is the first item in that submenu."
2. "On touch, when dragging to eg scroll the available options, the drag initiation also triggers a toggle, so if i happen to initiate drag on lets say vsync, that option will toggle."
3. "When tapping the ui scale slider specifically it will resize and change the value, triggering a sort of domino effect ending in one of the two end values (max or min)."

## What the code says

- `ui_interact` (`src/ui_widgets.odin`) grants `activated = (focused && state.confirm) || (hovered && state.click)`, and `state.click` is the press edge (`ui_begin`, `src/ui_core.odin`: `mouse_pressed || pad_pressed`), so a pointer activates a widget the moment it lands, before a tap can be told from a drag (report 2). The item slots have their own press state machine since 0124 (`Slot_Drag`, `UI_SLOT_DRAG_SLOP`); nothing else has.
- `ui_slider` sets `dragging = id` on the press and re-derives the value from the track and the pointer every frame while `pointer_held`. A UI scale change moves the track under a still finger, whose position in units is not recomputed (`update_pointer` only reads the mouse when it moved or pressed), so the value chases the layout until an end (report 3).
- Scroll regions (`scroll_region_end`) scroll with the right stick and the wheel only. A finger has no way to scroll a list, which is what the drag in report 2 was for.
- Report 1: every edge is one frame wide (`update_frame` in `src/loop.odin` samples the input once per render frame, `actions_just_pressed` is `current - previous`, `mouse_pressed` is `down && !previous.down`), a pushed screen keeps the stale focus and `ui_resolve` falls back to the first widget at the end of the next frame, and the reading found no second edge. Reproduce it headless before anything else: the screen frame helpers in `src/ui_inventory_test.odin` drive frames with inputs; open the pause menu with a gamepad, focus Developer, press Confirm, then run the following frames with Confirm held and released, and assert that no developer request is queued; the same with a touch tap (`pointer_is_touch`, `mouse_pressed`, then `mouse_down` for a few frames, then released) on the Developer button. If the headless run does not reproduce, read the platform's input path (raylib backend on the phone: `read_raylib_input_frame`, `touch_overlay_gamepad`, `apply_touch_overlay_aim`, `apply_touch_overlay_hotbar`; SDL3 on the couch; a Steam Input desktop layout that sends A as a mouse click at the hidden pointer, `ui_pointer_over`) and do not close the item without a test that shows the mechanism.

## Change

- Pointer activation on release: a press records the widget under the pointer and the press position (`Ui_State`, like `Slot_Drag`); a widget activates when the pointer is released over the same widget and the pointer has not moved beyond `UI_SLOT_DRAG_SLOP` since the press. The gamepad's Confirm on the focused widget stays as it is. Item slots keep 0124's rules. Sliders and steppers keep the press for the start of a drag. The 0124 outside-tap-to-close rule and the `ui_frame_sound_events` click sound follow the new activation (the sound on the release).
- Finger scrolling: a press inside a scroll region that moves beyond the slop scrolls the region by the pointer's movement (touch and trackpad pointer; the mouse keeps the wheel and may scroll this way too), and cancels the pending activation. The focus does not follow the pointer during the scroll drag.
- Sliders: the value follows the pointer on the press and afterwards only on frames where the pointer moved (`pointer_moved`), never from a still pointer; so a layout change under the finger changes nothing until the finger moves. `pixels_per_unit` changes are applied to the stored pointer position as well, so the pointer's unit position stays true after a UI scale change.
- Whatever report 1's mechanism turns out to be, its fix carries a test that fails before and passes after.
- Docs: `doc/ui.md` (the pointer section: activation on release, finger scrolling, the slider rule), `doc/log/2026-09-30.md`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: a press on a toggle followed by a release on it flips it once; a press followed by a move beyond the slop and a release flips nothing and scrolls the region by the movement; a press on a toggle released outside it flips nothing; the UI scale slider pressed once at a position and held still over several frames with the layout rescaled between them keeps the value of the press; the report 1 reproduction.
- The user: on the phone, open Developer from the pause menu, fly mode unchanged; drag the Display settings list up and down starting on vsync, vsync unchanged; tap the UI scale slider once, one value change.
