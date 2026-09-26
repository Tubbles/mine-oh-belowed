# 0001 Foundation: build script and skeleton

Status: implemented
Milestone: M0

## Goal

A buildable `src/` skeleton and a `build.sh` so that CI, the Steam shortcut and every later work item have something to build and launch.

## Deliverables

- `build.sh` with `debug` (default) and `release` modes, creating `tmp/linker-shims/` as described in `doc/build.md`, output to `bin/mine-oh-belowed`.
- `src/` single `game` package: main loop with fixed 60 Hz tick accumulator and vsync render, a window titled "Mine oh Belowed", and a controller diagnostics screen that draws live values of every input the active input backend reports.
- Input action layer as described in `doc/architecture.md` with a raylib gamepad backend and a keyboard and mouse backend. The SDL3 backend comes from 0002.
- `data/` directory with one placeholder SJSON file loaded at startup through `core:encoding/json` with `Specification.SJSON`, to prove the data path.
- One unit test (for example run length coding) so `odin test src` exercises something.
- Remove the `src/` guard from `.github/workflows/ci.yml`.

## Verify

- `~/opt/odin/odin check src -vet -strict-style` clean.
- `~/opt/odin/odin test src` passes.
- `./build.sh` and `./build.sh release` produce `bin/mine-oh-belowed`.
- CI green on the pushed commit.
- User: launching the binary opens the window and the diagnostics screen shows stick and button values from any connected pad.

## Notes

- Bindings are hardcoded tables in `src/input_raylib.odin` following the layout in `doc/input.md`. Moving them to configuration is left for the configuration work. `Hotbar_Radial` has no gamepad binding because it needs the left trackpad (SDL3, work item 0002). Keyboard: WASD move, mouse look, Space jump, left and right mouse mine and place, R rotate, Q or middle mouse pipette, Tab radial, E inventory, M map, Escape pause, Enter confirm, Backspace back.
- `Input_Frame` has a third vector, `look_delta`, for pointer style look in pixels (mouse now, trackpad and gyro later), because it cannot share units with the rate style stick `look`.
- Escape is bound to Pause, so raylib's exit key is disabled. The window closes through the window manager or Steam, not a key.
- `tick_rate` from `data/game.sjson` drives the tick accumulator, validated to 1 to 1000.
- Extra test: `src/data_load_test.odin` parses the shipped `data/game.sjson` through `#load`, which proves the SJSON path without opening a window.
- Not verified by the agent (headless session): opening the window, the diagnostics screen, gamepad values, text size at 1080p. Only `--version`, the unknown argument error and the missing data directory error were run.
