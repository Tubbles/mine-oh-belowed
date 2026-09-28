# 0084 Display diagnostics and a gamescope launch

Status: implemented
Milestone: M11

## Goal

Laptop report (2026-09-28): in Borderless the Resolution row shows 1694 by 1129 on a 2880 by 1920 panel and cannot be changed. The desktop is scaled 170 percent (2880 over 1694 is 1.700) and the vendored raylib is X11 only (its static library has no Wayland symbols), so the game runs through XWayland, which hands X11 applications the scaled screen and upscales them. The game cannot reach the panel through that path; it can say so, and it can be launched through gamescope, which presents an X11 application at the panel's full size without a global desktop setting. The Wayland native path is item 0085.

## Deliverables

- Logging: right after the window opens and on every display change (`update_display`, `src/display.odin`), one log line `display: monitor W x H, window W x H, render W x H, scale X x Y, session <x11|xwayland>` from `GetMonitorWidth` and `GetMonitorHeight`, `GetScreenWidth` and `GetScreenHeight`, `GetRenderWidth` and `GetRenderHeight`, `GetWindowScaleDPI`, and `xwayland` when `WAYLAND_DISPLAY` is set in the environment (the backend is X11, so a Wayland session means XWayland). The text comes from a pure `display_diagnostics_text(...)` with a test.
- The Resolution row (`resolution_choice` in `src/ui_screens.odin`): when the session is XWayland or the window scale is not 1, the dimmed value in Borderless reads "1694 x 1129 (desktop scaled)" and the row's tooltip explains: "The desktop hands X11 applications a scaled screen. Launch through gamescope, or let X11 applications scale themselves in the desktop settings, for the panel's full size." A pure `display_is_desktop_scaled(scale, wayland_display_set) -> bool` with a test; the screen context carries the two facts from the frame state.
- Launcher: `tools/install_play_build.sh` writes a launcher that, when `MINE_OH_BELOWED_GAMESCOPE` is set and `gamescope` is on the path, runs `exec gamescope $MINE_OH_BELOWED_GAMESCOPE -- <binary> "$@"`, the variable holding gamescope's own arguments (`-f -W 2880 -H 1920` on the laptop), and otherwise runs the binary as today; a missing gamescope logs one line to stderr and runs the binary. `doc/build.md` gets the laptop example and the reason.
- Tests: the diagnostics text, the desktop scaled decision, the UI audit with the note shown.
- Docs: `doc/build.md`, `doc/ui.md` (the note), `doc/log/2026-09-28.md`, this item's Status and Notes.

## Verify

- Builds and tests pass.
- User: on the laptop the log names the session and the sizes, the row shows the note, and `MINE_OH_BELOWED_GAMESCOPE="-f -W 2880 -H 1920" bin/mine-oh-belowed` gives the full panel.

## Notes

Files a subagent may touch: `src/display.odin`, `src/display_test.odin`, `src/loop.odin` (the log call and the screen context fields), `src/ui_screens.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, `tools/install_play_build.sh`, the docs above, this file.

Implemented: `src/display.odin` (the diagnostics text, the desktop scaled decision, the log call in `update_display`), `src/display_test.odin`, `src/loop.odin` (the log after the window opens, the window scale read every frame, the session read once, the screen context fields), `src/ui_screens.odin` (the Resolution row's note and tooltip in Borderless), `src/ui_audit_test.odin` (the desktop scaled Display tab case), `data/strings/en.sjson`, `tools/install_play_build.sh` (the gamescope branch), `doc/build.md`, `doc/ui.md`, `doc/log/2026-09-28.md`. 881 tests pass.
