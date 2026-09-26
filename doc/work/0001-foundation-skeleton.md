# 0001 Foundation: build script and skeleton

Status: todo
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
