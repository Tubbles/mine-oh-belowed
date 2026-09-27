# 0080 Display settings: window mode, resolution, vsync, frame rate cap

Status: todo
Milestone: M11

## Goal

Couch request (2026-09-27): "We need a setting for fullscreen/borderless fullscreen/windowed, screen resolution, vsync, and target fps." The game opens a fixed 1280 by 720 resizable window with the vsync hint and no frame rate cap (`run_game` in `src/loop.odin`), and nothing in the settings touches the window.

## Deliverables

- Settings (`Settings` in `src/settings.odin`, defaults in `DEFAULT_SETTINGS`): `window_mode` (enum `Window_Mode`: `windowed`, `borderless`, `fullscreen`; default `borderless`, since the game is played from the couch and Steam's gamescope presents the window full screen anyway), `resolution` as `[width, height]` with `[0, 0]` meaning the monitor's current size (the default), `vsync` (bool, default true), `frame_rate_cap` (int, 0 for none, the default). Configuration mapping in `src/configuration.odin` and the writer in `src/configuration_output.odin` with the strict checks the other keys have: an unknown mode, a resolution outside 320 to 7680 per axis, a cap outside 0 to 480 or not a whole number is an error naming the file. `--set=settings.window_mode=windowed` works like the other keys and `mine-oh-belowed config` prints them.
- Applying, in a new `src/display.odin`: a pure `display_changes(previous, next: Settings) -> Display_Changes` that says what to do (mode change, size change, vsync change, cap change), and `apply_display_changes(changes)` that does it with raylib: `ToggleBorderlessWindowed`, `SetWindowState`/`ClearWindowState` with `.FULLSCREEN_MODE`, `SetWindowSize` (and `SetWindowPosition` to centre a window on its monitor), `SetWindowState`/`ClearWindowState` with `.VSYNC_HINT` (raylib's desktop platform sets the swap interval at run time for that flag; verify in raylib's `rcore_desktop_glfw.c`, the vendored library is 6.0), `SetTargetFPS`. At start, `run_game` builds the config flags and the window size from the settings (`.VSYNC_HINT` only when vsync is on, the resolution or the monitor size) and applies the mode after `InitWindow`. Changes from the settings screen apply at once, like the font choice, and are saved with the other settings (`write_changed_settings`).
- raylib specifics to honour: `FLAG_FULLSCREEN_MODE` uses the window size as the video mode, so the resolution row applies to windowed and fullscreen; borderless uses the monitor's current mode and the row is drawn dimmed with the monitor size. raylib lists no video modes, so the resolution choices are a fixed list (1280 by 720, 1280 by 800, 1600 by 900, 1920 by 1080, 1920 by 1200, 2560 by 1440, 2560 by 1600, 3840 by 2160) filtered to the current monitor's size, plus "Native". A configured resolution not in the list is kept and shown as its numbers.
- UI (`display_settings` in `src/ui_screens.odin`, the Display tab): rows Window mode (choice), Resolution (choice), Vsync (toggle), Frame rate cap (choice: Off, 30, 40, 60, 90, 120, 144, 165, 240), each with a tooltip, above the UI scale row. Focus navigation and the pointer work as on the other rows. Strings in `data/strings/en.sjson`.
- The simulation is untouched: the fixed tick and the accumulator already absorb any frame rate. The UI reads the screen size each frame (`loop.odin`, `GetScreenWidth`), so it reflows after a change; check that the chunk renderer, the model renderer and the font cache need nothing on a resize (the font cache rasterises per pixel size, which follows the UI scale, not the window).
- Tests: configuration parsing of the four keys (valid, each out of range case, an unknown mode name), the settings file round trip, `display_changes` for every pair of differing fields and for no change, the resolution choice list filter and the "Native" entry, and the UI audit covering the Display tab with the new rows. No test opens a window.
- Docs: `doc/ui.md` (the Display tab paragraph, including the gamescope note: in Steam Game Mode the compositor presents the window full screen whatever the mode, and a windowed resolution becomes the size gamescope scales), `doc/architecture.md` (the main loop line says "render at vsync": now vsync or a cap from the settings), `doc/work/0076-steam-deck.md` (the frame rate cap setting comes from 0080; 0076 keeps the Deck preset), `doc/log/2026-09-27.md`, this item's Status and Notes.

## Verify

- `~/opt/odin/odin check src -vet -strict-style`, `./build.sh test`, `./build.sh release`.
- User: on the couch switch between the three modes and back without a restart, pick 1920 by 1080, turn vsync off and cap at 60, and see the cap in the statistics overlay's fps; the settings survive a restart.

## Notes

Files a subagent may touch: `src/settings.odin`, `src/settings_test.odin`, `src/configuration.odin`, `src/configuration_output.odin`, `src/configuration_test.odin`, `src/loop.odin` (window creation and the settings apply hook only), new `src/display.odin` and `src/display_test.odin`, `src/ui_screens.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, `doc/ui.md`, `doc/architecture.md`, `doc/work/0076-steam-deck.md`, `doc/log/2026-09-27.md`, this file. Raylib bindings: `~/opt/odin/vendor/raylib/raylib.odin` (read only).
