# Mine oh Belowed: instructions for LLM agents

Read this together with the global `~/.claude/CLAUDE.md`. This file only adds what is specific to this project.

## Stack

- Language: Odin. Toolchain at `~/opt/odin` (release dev-2026-09). Do not install another Odin.
- Rendering, windowing, audio: raylib 6.0 through `vendor:raylib` (static, GLFW based).
- Controller input: SDL3 through `vendor:sdl3`, linked against the host `libSDL3.so.0` (3.4.16 on the couch machine). SDL is used for joystick, gamepad and sensor subsystems only, never for video.
- Content: SJSON files under `data/`, parsed with `core:encoding/json` using `Specification.SJSON`. Never hardcode a recipe, block, machine or technology in Odin code.
- Build and verify commands: see `doc/build.md`. The session that runs agents is usually headless, so a window cannot be opened. Agents verify with `odin check`, `odin test` and a full build. The user playtests.

## Layout

Follows the project structure from the global preferences: `doc/` (detail docs), `doc/log/` (dated decision logs, write once), `doc/work/` (work items with status `todo`, `implemented`, `verified`), `work/` and `tmp/` (untracked), `PLAN.md`, `DESIGN.md`, `TODO.md` (user inbox), `SUGGESTIONS.md`. Source under `src/`, content under `data/`, build output under `bin/`.

## Code rules

- Odin conventions: `snake_case` procedures and variables, `Ada_Case` types, `SCREAMING_CASE` constants. Full words in names, no abbreviations.
- Small pure procedures, structs as data carriers, arrays of structs, no OOP.
- One `game` package under `src/` split into files by concern. New packages only for leaf utilities with no back references, because Odin forbids import cycles.
- The simulation is deterministic: fixed 60 Hz tick, seeded RNG, no wall clock and no float accumulation in simulation state where fixed point works. Rendering interpolates, the simulation never reads the frame time.
- Gamepad first: every UI must work with focus navigation and with the trackpad pointer. Keyboard is only for string fields.
- Documentation is updated in the same commit as the behaviour it describes. Decisions go to `doc/log/YYYY-MM-DD.md`.
- Review and commit language: plain engineering vocabulary (malformed input, validate the size before allocating), see the global instructions.

## Work flow

Work items live in `doc/work/NNNN-slug.md` with a `Status` line and a `Verify` section. Subagents get one item at a time with the files they may touch and the verify commands. The main agent reviews the diff and commits.

The couch always runs the latest build. After every commit that lands on `main`, run `tools/install_play_build.sh`; it never waits for the game, since every install gets its own directory under `bin/play/builds/` and the launcher resolves the `bin/play/current` link at launch. A work item or a bug fix is not done until the play build is installed, and the wrap-up names the installed commit. The user reads the build stamp (commit and build time) from the title screen or the pause menu when reporting a bug.
