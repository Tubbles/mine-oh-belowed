# 0043 Developer mode for accelerated couch testing

Status: implemented
Milestone: M10

## Goal

Get a tester into a specific game state quickly, from the couch, without a keyboard: a developer menu reachable on the gamepad, command line flags that skip ahead, and the runtime error text landing in the log so a crash on the couch leaves a trace.

## Deliverables

- `--dev` flag that enables a Developer entry in the pause menu with: toggle fly mode, toggle diagnostics, toggle the bottleneck overlay, give the starting kit of a chosen chapter (a list of chapters), complete quests up to a chosen chapter (marks them done, delivers their rewards, unlocks quest gated technologies), unlock all recipes and technologies, set the time of day, teleport to spawn or to the landing pad. Every entry works with focus navigation and the pointer, so no keyboard is needed. The `developer_mode` setting (settings screen, saved with the other settings) shows the entry too, so the couch needs no launch options (user request 2026-09-27).
- Command line: `--give=<item>:<count>` (repeatable), `--chapter=<n>` (start a new world with chapters below n completed and their kits given), `--dev`. `--unlock-all` stays.
- Chapter kits in data: `data/dev_kits.sjson`, one per chapter, with the items a player typically holds at that chapter's start, so `--chapter=4` gives a base's worth of belts, inserters, drills, furnaces, a pump, a boiler and an engine.
- Crash traces: Odin's runtime assertion and bounds check messages go to stderr, which Steam hides. Install an assertion failure procedure and a segmentation fault and illegal instruction signal handler (through `core:sys/posix` or `core:os` if available) that append the message and a best effort backtrace (`core:debug/trace` if the toolchain provides it) to the game log before re raising, so a couch crash leaves its reason in `log.txt`. Test the assertion path headless.
- Autosave interval in the settings screen (it exists in `Settings` but has no widget), 0 (off) to 60 minutes in steps of 1 (the configuration file still accepts up to `MAXIMUM_AUTOSAVE_MINUTES`), plus a "Save now" toast confirmation that already exists.
- Tests: kit loading, `--chapter` completing quests and delivering rewards, `--give` parsing, the developer menu's state changes as pure procedures, the log handler writing an assertion message.

## Verify

- Builds and tests pass.
- User: from the couch, open the pause menu, choose Developer, give the chapter 4 kit and fly to the spawn, all with the controller; then force an assertion in a test build and find its message in the log.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (565 tests, 11 new in `developer_test.odin`), `./build.sh`, `./build.sh release`, `--help`, bad `--give` and `--chapter` values (exit 2), and `--dev --chapter=4 --give=iron_plate:50 --seed=1 --name=dev-test`, which stops only at opening a window.

Files: new `data/dev_kits.sjson`, `src/developer.odin` (kits, command line parsing, requests and the procedures that serve them), `src/ui_developer.odin` (the screen), `src/developer_test.odin`; changes to main (flags, kit loading), loop (requests on the simulation, served at the start of a tick; day offset), logging (crash traces), recipe unlocks (`mark_everything_unlocked` shared with `--unlock-all`), save world (day offset), pause and settings screens, strings.

### Model and deviations

- Requests: `Simulation_State.developer_requests`, filled by the screen and by `--chapter`/`--give`, served by `serve_developer_requests` at the start of `simulation_tick` (after the tick counter, before the players). Not saved. The Developer screen sits above the pause menu, so the simulation stays paused and a request applies once the game resumes; a toast says so. The fly mode check box shows the state after the pending toggles. Diagnostics and the bottleneck overlay are frame state and toggle at once.
- Complete quests up to chapter n walks the active quest forward with `queue_rewards`, `activate_quest` and `next_quest`: each earlier quest is marked done and its rewards queued (items to `pending_rewards`, recipes and technologies unlocked). Deliveries are not taken from the capsule. Only the final activation's Mission Control line stays in the message log and toasts, so the journal is not flooded. It never moves the active quest backwards. Chapter 8 has no quest file, so "up to chapter 8" completes every quest.
- Kits: `data/dev_kits.sjson`, one kit per chapter in order (a `chapter` field that must count up from 1), 8 kits. Loaded after the items, strict: unknown items and counts outside 1 to 10000 stop the start.
- Time of day: the day cycle is a function of the tick, and the tick drives statistics, contracts and quest timing, so the time is set through a new `Simulation_State.day_offset_ticks` (render and diagnostics use `simulation_day_ticks`). It is saved through `world.sjson`'s existing `day_time_ticks` (now tick plus offset) and restored on load; older saves give offset 0. No save format change.
- Teleport: to the pad's centre block (`session.start.landing_pad`), which is also the spawn, so there is one teleport button.
- Command line: `--chapter` and `--give` start a world directly like `--seed`; `--chapter` with `--load` is refused. `--give` shape is checked with the other flags, items and the chapter range after the data loads, both exit 2. `--chapter` queues "complete quests" then "give kit", then the `--give` items. A new world still saves at once before the first tick, as before, so the queued requests are not in that first save.
- Crash traces: when stderr is not a terminal, `open_log_file` keeps a copy of the original stderr (`dup`) and points stderr at the log (`dup2`). The game's own lines go to the original stderr and the log once, the runtime's messages (bounds check, type assertion) to the log only. `log_assertion_failure` (main thread's `context.assertion_failure_proc`) writes a `crash:` line and a back trace from `core:debug/trace`, then traps. SIGSEGV and SIGILL handlers (`SA_RESETHAND`) write a raw `backtrace_symbols_fd` trace and re raise; no alternate signal stack, so a stack overflow gets no trace. Worker threads keep the default assertion procedure (their message still reaches the log through stderr, without a back trace). The dup2 path and the signal handler cannot be unit tested; only the text formatting is.
- Autosave: a slider row on the Display tab, 0 (shown as Off) to 60 in steps of 1 (the review cut the briefed 1440: a stick cannot walk that many steps).

### Guessed numbers

All kit contents (see the file's comment): roughly the previous chapters' rewards plus a base's worth of machines, each kit under about 40 inventory slots. `MAXIMUM_DEVELOPER_GRANT_COUNT` 10000. Time of day targets: dawn, noon, dusk and midnight at quarter days from sunrise.

### Not verified

Everything visual: the Developer screen layout (1000 units wide, ten rows, eight chapter buttons per row), the pause menu with eleven buttons, the autosave slider, focus movement across the button rows with the gamepad. A real crash from the couch writing its trace to `log.txt` (the user verify).

### Open questions

- Should `--chapter` worlds skip the immediate save, or save after the first tick so the save holds the chapter state?
- Should the Developer screen replace the pause menu (like Recipes) so requests apply at once, instead of on resume?

