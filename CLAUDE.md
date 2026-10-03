# Mine oh Belowed: instructions for LLM agents

Read this together with the global `~/.claude/CLAUDE.md`. This file holds the project's rules for agents; how things work is in the docs, entered through [doc/README.md](doc/README.md).

## Stack

- Language: Odin. Toolchain at `~/opt/odin` (release dev-2026-09). Do not install another Odin.
- Rendering, windowing, audio: raylib 6.0 through the repository collection `shared:raylib`, archives built by `tools/build_raylib.sh` ([doc/build.md](doc/build.md), The shared collection). Never import `vendor:raylib`.
- Controller input: SDL3 through `vendor:sdl3`, linked against the host `libSDL3.so.0`, with the joystick and gamepad subsystems only, never video ([doc/input.md](doc/input.md)).
- Android (0114): the same `game` package built as `libmain.so` for arm64, with raylib's input only. SDL code stays in files tagged `#+build !linux:android` ([doc/input.md](doc/input.md), Backends).
- Android-only code goes into `#+build linux:android` files (`main_android.odin`, `platform_android.odin`) or behind `when ODIN_PLATFORM_SUBTARGET == .Android`. Never a GLFW call outside a `when ODIN_PLATFORM_SUBTARGET != .Android` guard: `./build.sh check-android` fails on one ([doc/android.md](doc/android.md)).
- File watching: through `shared:fsw`. Never a polling scan of the data directory.
- Content: SJSON files under `data/`, parsed with `core:encoding/json` using `Specification.SJSON`. Never hardcode a recipe, block, machine or technology in Odin code.
- Build and verify through `build.sh` (`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `./build.sh release`), which passes the `shared` collection; a bare `odin check src` does not compile ([doc/build.md](doc/build.md)). The agents' session is usually headless, so no window opens. The user playtests.

## Layout

The project structure of the global preferences: `doc/` (detail docs, index in `doc/README.md`), `doc/log/` (dated decision logs, write once), `doc/work/` (work items with status `todo`, `implemented`, `verified`; the finished ones under `doc/work/done/`, the closed and folded ones under `doc/work/cancelled/`), `work/` and `tmp/` (untracked), `PLAN.md`, `DESIGN.md`, `TODO.md` (the user's inbox, the user writes there), `SUGGESTIONS.md` (agent follow ups and decisions needed, including the deferred work of a big series, never `TODO.md`). Source under `src/`, content under `data/`, build output under `bin/`. The entry to the source is [doc/code_map.md](doc/code_map.md): the clusters, their entry files and the allowed dependencies between them.

## Code rules

- Odin conventions: `snake_case` procedures and variables, `Ada_Case` types, `SCREAMING_CASE` constants. Full words in names, no abbreviations.
- Small pure procedures, structs as data carriers, arrays of structs, no OOP.
- Never import `core:c/libc`: on Windows it links the static C runtime, which clashes with raylib's release library (0102). Declare the one C function needed against `system:c` and `system:ucrt.lib`, as `raylib_log.odin` does.
- Import `core:sys/posix` only in a file whose first line is `#+build !windows` (as `logging_posix.odin`), with a `#+build windows` counterpart; a `when` block does not keep an import out. `test_static_runtime_imports_stay_out_of_windows` enforces both ([doc/build.md](doc/build.md), The C runtime).
- One `game` package under `src/` split into files by concern. New packages only for leaf utilities with no back references, because Odin forbids import cycles.
- The simulation is deterministic: fixed 60 Hz tick, seeded RNG, no wall clock and no float accumulation in simulation state where fixed point works. Rendering interpolates, the simulation never reads the frame time.
- Shaders: every integer literal carries the `u` suffix (`hash >> 8u`), since Winlator's Gladio turns bare integers into floats on lines with float variables (0105). `shader_source_test.odin` enforces it.
- Textures go up as RGBA through `load_rgba_texture` (`render_atlas.odin`), never through `rl.LoadTextureFromImage` directly: gray formats render red on the phone (0106).
- Gamepad first: every UI works with focus navigation and with the trackpad pointer. Keyboard is only for string fields. Touch is a virtual gamepad (0115): a world action reaches touch through a gamepad binding, never through a touch code path of its own, except the hotbar slot taps (0119) and the jump tap (0134), which press their action directly because no gamepad control does only that ([doc/touch_overlay.md](doc/touch_overlay.md)).
- No perceivable repetition (`DESIGN.md`): sounds recur in clusters with long varying pauses and varied pitch, never on a fixed period; textures do not stripe or tile visibly, so they are isotropic or varied per block by a hash; animation cadences follow the world and never speed up with cheat speed. Every new sound, animation and texture is checked against this before it lands.
- Documentation is updated in the same commit as the behaviour it describes, in the doc that owns the topic (one place per fact). Decisions go to `doc/log/YYYY-MM-DD.md`.
- Review and commit language: plain engineering vocabulary (malformed input, validate the size before allocating), see the global instructions.

## Work flow

Work items live in `doc/work/NNNN-slug.md` with a `Status` line and a `Verify` section. An item whose work has landed and whose play build is installed moves to `doc/work/done/` (`git mv`, the file unchanged, path references updated); an item closed or folded into another moves to `doc/work/cancelled/`; open items stay at the top of `doc/work/` (user, 2026-10-03). Subagents get one item at a time with the files they may touch and the verify commands. A second subagent reviews the diff afterwards (the global instructions, Subagents); the main agent weighs the review, has the implementer fix what holds, and commits.

Before handing back, an implementer walks the hand-back check below and says in its report what it changed because of it. The main agent reads the review's findings and the parts of the diff they touch, not the whole diff the reviewer covered, and runs the test suite once itself before the commit (user, 2026-09-30, `doc/log/2026-09-30.md`).

The factory benchmark (`./build.sh bench`, `--benchmark=<size>`) runs sizes up to 16; larger factories are read off size 16, never built (user, 2026-09-28). Heavy benchmark runs follow the window and lock rules of the global instructions.

The couch always runs the latest build. After every commit that lands on `main` and changes `src/` or `data/`, run `tools/install_play_build.sh` ([doc/build.md](doc/build.md), Play build); it never waits for the game. A work item or a bug fix is not done until the play build is installed, and the wrap-up names the installed commit. Exception during the M13 rebuild (user, 2026-10-02): from 0168 until 0179 plays, the block world may stop being playable and the play build is not installed; `./build.sh check` and `./build.sh test` stay green for every commit so the reviews can verify, and the couch keeps the last block build (7ce7e94). The user reads the build stamp (commit and build time) from the title screen or the pause menu when reporting a bug.

## Hand-back check

Each line is a finding of the 2026-09-30 reviews that cost a fix round. The implementer checks its change against every line before it reports.

- Anything that frees or replaces memory a frame may still draw from (an arena, a string table, a screen's rows) runs between frames through a request the loop serves (`serve_data_browser`, `serve_touch_layouts`), never inside the UI pass, and a test runs the frame and then reads the draw list.
- A file is written to `<path>.tmp` and renamed over the path (`write_file_replacing`), never in place. A copy refuses a destination equal to its source. A path built from a listing or a setting stays under the directory it belongs to.
- A start-up load that the game itself can make fail (an overlay copy, a setting) falls back and reports instead of exiting.
- A number parsed from text is range checked (`strconv.parse_i64` wraps silently). A rate scaled per tick accumulates credits (`take_power_step`) instead of truncating.
- A changed save layout loads an old save (a remap and one log line), and a behaviour change that stops old saves is named in the log and covered by the dev kits.
- A new participant in a shared budget (power, fluid, a queue that credits future outputs) is checked for what it does to the existing ones: a proportional share that keeps it busy, an entry stuck ahead of it in a queue.
- A list that grows without bound is capped where it draws (the HUD), a long string is fitted or wrapped, both checked at the smallest audit size.
- A UI audit case a change makes obsolete is replaced, so the state it showed (a waiting queue, a full inventory) is still drawn somewhere.
- Tests never touch the machine's state directory or settings; they use temporary directories (the overlay directory is "" under `odin test`).
