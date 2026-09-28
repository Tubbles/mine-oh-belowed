# 0098 Developer mode: finish the active quest

Status: todo
Milestone: M11

## Goal

Couch request (2026-09-28): the Developer screen needs a "Finish the active quest" button.

## Deliverables

- A developer request `Finish_Active_Quest` (`src/developer.odin`, queued like the chapter completion and applied between ticks) that completes the active quest as if its objectives were met: its rewards (items to the capsule's pending rewards, recipes and technologies) are granted through the same path the chapter completion uses, its complete message is logged, and the next quest activates; nothing happens when every quest is done.
- The Developer screen (`src/ui_developer.odin`) gets the button "Finish active quest" next to the chapter buttons, with the same toast as the other queued requests, and the command socket gets `quest finish` (`src/command.odin`, `doc/commands.md`).
- Tests: the request completes the active quest with its rewards and activates the next one, and does nothing at the end; the command parses; the UI audit with the button.
- Docs: `doc/ui.md` (the Developer screen list), `doc/commands.md`, `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: the button completes the current quest and the journal moves on.

## Notes

Files a subagent may touch: `src/developer.odin`, `src/developer_test.odin`, `src/ui_developer.odin`, `src/quest_runtime.odin`, `src/quest_runtime_test.odin`, `src/command.odin`, `src/command_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
