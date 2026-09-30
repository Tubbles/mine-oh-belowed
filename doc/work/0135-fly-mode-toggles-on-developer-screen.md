# 0135: Fly mode toggles when the Developer screen is entered

Status: todo

## Goal

Report 1 of 0132 (user, 2026-09-30, phone and couch): "on gamepad and touch, when eg entering a submenu like dev, automatically toggles fly mode since that is the first item in that submenu." The report is ground truth. 0132 could not find the mechanism: headless, a Confirm held and released over the pause menu's Developer entry and a finger's press, hold and release on it queue no developer request (`src/ui_pointer_test.odin`), every UI edge lasts one frame, and the platform input paths (`make_ui_input`, both backends' frame readers, raylib's Android callbacks, the overlay under a screen) give no second edge.

## Leads and groundwork (0132)

- The toggle's knob slid from a stale position when its value had changed while the screen was closed (`knob_positions` was never cleared), which reads as a toggle on entry; 0132 snaps a toggle not drawn last frame to its value.
- The double tap Jump window (0112, developer mode toggles fly mode on two Jumps within 18 ticks) was frozen while a pausing screen was open, so a Jump before the pause and one after the resume toggled fly mode; 0132 clears the window when the world was blocked by a screen.
- Steam's input layer on the couch may send A a second way (a key or a click through GLFW a few frames after SDL's A). The layout is not stored locally and could not be read.
- Every change of fly mode now logs its cause and the tick (`fly: ...` through `log_printf`).

## Next step

The user reproduces once on the phone or the couch after the 0132 build and sends the log (`state/mine-oh-belowed/log.txt` under the app's files folder, or `adb logcat -s mine-oh-belowed`; on the couch `$XDG_STATE_HOME/mine-oh-belowed/log.txt`). The `fly:` line names the path that toggled it; the fix follows from there, with a test that reproduces it.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, plus the reproduction test of the found mechanism.
- The user: enter the Developer screen from the pause menu on the phone and on the couch, fly mode unchanged.
