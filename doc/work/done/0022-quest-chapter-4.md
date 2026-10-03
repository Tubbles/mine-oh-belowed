# 0022 Quest chapter 4: power

Status: implemented
Milestone: M4

## Goal

Chapter 4 from `doc/quests.md` as data: pump, boiler and engine, the first pole, lights on (glass from sand), the electric drill, an assembler making gears, a lab and the first research, the brownout hint, a second engine, and the main quest "The first contract" (deliver 100 electronic circuits) whose reward opens phase 5 in message and capsule.

## Deliverables

- `data/quests/chapter_04.sjson` with the quests above using existing objective types, new hint counters for brownout ticks and machines without power, Mission Control strings in the established tone.
- Tests: chapter loading, the new counters, the sequence completing on synthetic counters, the reward landing.

## Verify

- Builds and tests pass.
- User: the M4 verify statement. Following the journal only, an unattended line mines iron ore, smelts it, assembles iron gear wheels into a chest, powered by steam, and completes at least one research.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `data/quests/chapter_04.sjson` and `src/quest_chapter_04_test.odin`; `data/strings/en.sjson`; `src/lab.odin` (progress per technology, placeholder refusal, `apply_finished_research` returns the technology), `src/technology.odin` (`MAXIMUM_TECHNOLOGIES`), `src/item_transfer.odin` (insertion limit), `src/quest_runtime.odin` (`Quest_Message.argument_key`, notices carry messages, `log_research_complete`), `src/loop.odin` (`apply_research_result`, toasts), `src/ui_journal.odin`; tests added to `lab_test.odin` and `assembler_test.odin`, adjusted in `quest_test.odin`, `quest_runtime_test.odin` and `quest_chapter_03_test.odin`.

### Carry overs from 0021

- Research progress is kept per technology (`Research_State.units_kept`, a fixed array of 64, the loader rejects more technologies). A unit in progress is still dropped with its packs on a switch; only whole units are kept.
- A finished technology logs "Research complete: {name}" in the message log and as a toast. Messages and notices are now `Quest_Message` with an optional `argument_key` whose text replaces `{name}`.
- Inserters and drills fill an assembler input slot only while it holds fewer than twice the recipe's count of that ingredient, and a lab slot while it holds fewer than two packs. The whole hand goes in while under the limit (so a slot can end slightly above it). The inserter still picks the item up and waits for room, as in Factorio. The player's panel is not limited.
- Placeholder technologies have status Locked and `queue_research` refuses them with "Not licensed yet".

### Chapter 4 and deviations

- Order: `steam`, `first_pole`, `first_research`, `assembly`, `electric_drill`, `second_engine`, `first_contract` (main). The brief's order had `assembly` and `electric_drill` before `first_research`, but the assembler recipe is behind automation and the electric drill recipe behind electric mining (which needs automation), so both moved after the first research. The test `test_shipped_quests_never_need_a_locked_recipe` plays every shipped chapter in order and checks that no place, craft, obtain, deliver or sustain objective names an item whose every recipe is still locked, and that research objectives follow their prerequisites.
- `first_pole`: the lamp recipe is behind optics, so the quest places 2 small poles and obtains 5 glass (sand to glass is a discovery recipe). Obtain counts since the game began, so glass from chapter 2 counts.
- The counters `brownout_ticks` and `unpowered_machine_ticks` already existed from 0020 (enum, loader names, statistics); this item only uses them as hints on `first_research` (600 and 1800 ticks) and tests them.
- `first_contract` rewards 50 copper plates and 50 iron plates: no crusher or washer item exists yet. Mission Control's line says plates enclosed as working capital.
- `assembly` counts gears produced after activation, including gears crafted by hand. Nothing checks that the poles reach the engine or that the electric drill replaced a burner drill.
- doc/quests.md bends: its chapter 4 outline lists a lamp ("lights on") and a separate "first science pack" quest; here the lamp is replaced by glass and the science pack is implied by the research objective. Its "As implemented" notes need a chapter 4 entry (order, glass, reward), and doc/fluids.md needs the 0021 behaviour updates (progress kept per technology, insertion limit, placeholders locked, completion toast). This run could not touch them.

### Not verified

The chapter in play, all text lengths on screen (journal, HUD objective, the research toast), the feel of the insertion limit on a real line (inserters now wait holding an item). The shipped data loads through the real loader (the binary started without a display got past data loading to the window error).

### Open questions

- Should the insertion limit cap the hand so the slot never exceeds the limit, rather than accepting the whole hand while under it?
- Should a partial unit survive a research switch (Factorio keeps it), instead of dropping the unit and its packs?
- Should the brownout and unpowered hints also watch during later quests, since they fire only while `first_research` is active?
- Once phase 5 items exist, should the contract reward switch to 1 crusher and 1 washer?
