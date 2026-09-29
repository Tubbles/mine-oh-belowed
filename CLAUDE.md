# Mine oh Belowed: instructions for LLM agents

Read this together with the global `~/.claude/CLAUDE.md`. This file only adds what is specific to this project.

## Stack

- Language: Odin. Toolchain at `~/opt/odin` (release dev-2026-09). Do not install another Odin.
- Rendering, windowing, audio: raylib 6.0 through the repository collection `shared:raylib` (the toolchain's binding copied, linking `shared/raylib/linux/libraylib.a`, built from source with GLFW's Wayland and X11 backends by `tools/build_raylib.sh`). Never import `vendor:raylib`.
- Controller input: SDL3 through `vendor:sdl3`, linked against the host `libSDL3.so.0` (3.4.16 on the couch machine). SDL is used for joystick, gamepad and sensor subsystems only, never for video.
- Content: SJSON files under `data/`, parsed with `core:encoding/json` using `Specification.SJSON`. Never hardcode a recipe, block, machine or technology in Odin code.
- Build and verify commands: see `doc/build.md`. The session that runs agents is usually headless, so a window cannot be opened. Agents verify through `build.sh` (`./build.sh check`, `./build.sh test`, `./build.sh release`), which passes the `shared` collection; a bare `odin check src` no longer compiles. The user playtests.

## Layout

Follows the project structure from the global preferences: `doc/` (detail docs), `doc/log/` (dated decision logs, write once), `doc/work/` (work items with status `todo`, `implemented`, `verified`), `work/` and `tmp/` (untracked), `PLAN.md`, `DESIGN.md`, `TODO.md` (user inbox), `SUGGESTIONS.md`. Source under `src/`, content under `data/`, build output under `bin/`.

## Code rules

- Odin conventions: `snake_case` procedures and variables, `Ada_Case` types, `SCREAMING_CASE` constants. Full words in names, no abbreviations.
- Small pure procedures, structs as data carriers, arrays of structs, no OOP.
- Never import `core:c/libc`: on Windows it links the static C runtime (`libucrt.lib`), which clashes with raylib's release library, built for the dynamic one (0102). Declare the one C function needed against `system:c` and `system:ucrt.lib`, as `raylib_log.odin` does. `core:sys/posix` links the same runtime, by its import alone: import it only in a file whose first line is `#+build !windows` (as `logging_posix.odin` and `command_socket_posix.odin`), with a `#+build windows` counterpart for the Windows side. A `when` block does not keep the import out. `test_static_runtime_imports_stay_out_of_windows` enforces both.
- One `game` package under `src/` split into files by concern. New packages only for leaf utilities with no back references, because Odin forbids import cycles.
- The simulation is deterministic: fixed 60 Hz tick, seeded RNG, no wall clock and no float accumulation in simulation state where fixed point works. Rendering interpolates, the simulation never reads the frame time.
- Shaders: every integer literal carries the `u` suffix (`hash >> 8u`), since Winlator's Gladio turns bare integers into floats on lines with float variables (0105). `shader_source_test.odin` enforces it.
- Gamepad first: every UI must work with focus navigation and with the trackpad pointer. Keyboard is only for string fields.
- Documentation is updated in the same commit as the behaviour it describes. Decisions go to `doc/log/YYYY-MM-DD.md`.
- No perceivable repetition (a major principle, `DESIGN.md`): sounds recur in clusters with long varying pauses and varied pitch, never on a fixed period; textures must not stripe or tile visibly, so they are isotropic or varied per block by a hash; animation cadences follow the world at a natural rate and never speed up with cheat speed. Every new sound, animation and texture is checked against this before it lands.
- Review and commit language: plain engineering vocabulary (malformed input, validate the size before allocating), see the global instructions.

## Work flow

Work items live in `doc/work/NNNN-slug.md` with a `Status` line and a `Verify` section. Subagents get one item at a time with the files they may touch and the verify commands. The main agent reviews the diff and commits.

The factory benchmark (`./build.sh bench`, `--benchmark=<size>`) runs sizes up to 16; larger factories are read off size 16, never built (user, 2026-09-28). Heavy benchmark runs follow the window and lock rules of the global instructions.

The couch always runs the latest build. After every commit that lands on `main` and changes `src/` or `data/`, run `tools/install_play_build.sh`; it never waits for the game, since every install gets its own directory under `bin/play/builds/` and the launcher resolves the `bin/play/current` link at launch. A work item or a bug fix is not done until the play build is installed, and the wrap-up names the installed commit. The user reads the build stamp (commit and build time) from the title screen or the pause menu when reporting a bug.
