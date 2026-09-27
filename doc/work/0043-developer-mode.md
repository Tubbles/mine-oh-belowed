# 0043 Developer mode for accelerated couch testing

Status: todo
Milestone: M10

## Goal

Get a tester into a specific game state quickly, from the couch, without a keyboard: a developer menu reachable on the gamepad, command line flags that skip ahead, and the runtime error text landing in the log so a crash on the couch leaves a trace.

## Deliverables

- `--dev` flag (and `dev = true` in configuration) that enables a Developer entry in the pause menu with: toggle fly mode, toggle diagnostics, toggle the bottleneck overlay, give the starting kit of a chosen chapter (a list of chapters), complete quests up to a chosen chapter (marks them done, delivers their rewards, unlocks quest gated technologies), unlock all recipes and technologies, set the time of day, teleport to spawn or to the landing pad. Every entry works with focus navigation and the pointer, so no keyboard is needed.
- Command line: `--give=<item>:<count>` (repeatable), `--chapter=<n>` (start a new world with chapters below n completed and their kits given), `--dev`. `--unlock-all` stays.
- Chapter kits in data: `data/dev_kits.sjson`, one per chapter, with the items a player typically holds at that chapter's start, so `--chapter=4` gives a base's worth of belts, inserters, drills, furnaces, a pump, a boiler and an engine.
- Crash traces: Odin's runtime assertion and bounds check messages go to stderr, which Steam hides. Install an assertion failure procedure and a segmentation fault and illegal instruction signal handler (through `core:sys/posix` or `core:os` if available) that append the message and a best effort backtrace (`core:debug/trace` if the toolchain provides it) to the game log before re raising, so a couch crash leaves its reason in `log.txt`. Test the assertion path headless.
- Autosave interval in the settings screen (it exists in `Settings` but has no widget), 1 to 30 minutes, plus a "Save now" toast confirmation that already exists.
- Tests: kit loading, `--chapter` completing quests and delivering rewards, `--give` parsing, the developer menu's state changes as pure procedures, the log handler writing an assertion message.

## Verify

- Builds and tests pass.
- User: from the couch, open the pause menu, choose Developer, give the chapter 4 kit and fly to the spawn, all with the controller; then force an assertion in a test build and find its message in the log.
