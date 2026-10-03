# 0018 Quest chapter 3: belts

Status: implemented
Milestone: M3

## Goal

Chapter 3 from `doc/quests.md` as data, including the main quest gate for phase 4 (an unattended ten minute run) that unlocks the steam engine recipe through the quest channel, and the hints about belts ending nowhere and inserters facing the wrong way.

## Deliverables

- `data/quests/chapter_03.sjson` with the quests from `doc/quests.md`: connect a drill to a furnace with a belt and an inserter, the coal loop, a chest at the end of a plate line, four drills feeding three furnaces, and the main quest "Prove the outpost" (sustain 10 iron plates per minute for ten minutes hands off) rewarding the steam engine recipe unlock and a capsule.
- New hint counters as needed: a belt line ending in nothing for a minute, an inserter with nothing to pick for a minute, both from the entity states.
- Mission Control strings for the chapter in the established tone.
- Tests: chapter loading, the new hint counters, the main quest unlock reaching the recipe channel.

## Verify

- Builds and tests pass.
- User: following the journal only, reach the steam engine recipe by running an unattended plate line for ten minutes.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/quests/chapter_03.sjson` (6 quests), the format comment in `data/quests/chapter_01.sjson`, `data/strings/en.sjson`, `quest.odin` (objective type `counter`, `produced_since_active`, three hint counters), `quest_runtime.odin` (activation baselines), `statistics.odin` (new counters, dead end recording), `belt.odin` and `belt_movement.odin` (per line dead end flag), `inserter.odin` (idle streak), `entity.odin` (tick wiring), `ui_journal.odin` (counter objective label), tests in `quest_chapter_03_test.odin` and `quest_test.odin`.

### Deviations

- Quests in order: `belt_parts` (craft 4 belts, 1 burner inserter), `connect` (place 1 drill, 2 belts, 1 burner inserter, then 10 iron plates produced since activation), `coal_loop` (10 fuel items lit by drills since activation), `plate_line` (place 1 wooden chest, 50 iron plates produced since activation), `four_drills` (4 drills and 3 furnaces placed in total), `prove` (main: 10 iron plates per minute for 10 minutes, hands off; rewards the steam engine recipe, 1 offshore pump, 1 boiler, 10 pipes).
- Not measured: that the drill, belt and inserter of `connect` feed the same furnace, that the coal drill feeds its own fuel slot (any fuelled drill counts), and that `plate_line`'s plates reach the chest. place counts placements since the game began, so the 3 furnaces of `four_drills` are already done from chapter 2.
- New objective type `counter` (a hint counter's growth since activation, with a required `label_key` for the journal text, `mining_ticks` rejected because objectives name no block). doc/quests.md's objective table bends here, like it did for `walk`. `produced_since_active` is a flag on craft objectives only; iron plates are furnace only, so "produced" is "smelted by furnaces".
- New counter `drill_fuel_burned` (a part of `fuel_burned`), because `fuel_burned` also counts furnaces and inserters.
- Inserter hint: the brief named `inserter_idle_ticks` with threshold 3600. That counter is summed over inserters and grows on healthy lines too (a burner inserter moves 36 per minute, a burner drill gives about 15 ore, a furnace 18.75 plates), so it would fire on a correct build within minutes. Added `inserter_idle_a_minute` instead: counted when one inserter reaches 60 s of uninterrupted Idle (`Inserter.idle_streak`), hint threshold 1. `inserter_idle_ticks` is unchanged.
- `belt_dead_end_ticks`: the belt tick sets `Belt_Line.front_held_at_dead_end` when a lane's front item stands at a dead end; `tick_entities` then counts one per such line per tick, except lines whose last block is an inserter's pickup cell (a drill to belt to inserter line always backs up there when the furnace is slower than the drill, and that is a feed, not a shelf). Hint at 3600.
- Both belt and inserter hints sit on `connect` only (hints watch only while their quest is active; repeating them on later quests would repeat the line). The drill fuel hint (`drill_out_of_fuel` 2) sits on `coal_loop`.
- doc/quests.md's "an inserter facing the wrong way" is approximated by the idle minute: a reversed inserter has nothing to pick.

### Not verified

The chapter in play (the user verify), the journal text lengths and the counter objective line on screen, the sustain run against a real plate line. The shipped chapter loads through the real loader (the binary started without a display got past data loading to the window error). `record_belt_dead_ends` scans the inserters for each held line per tick; cheap at current scale, not measured on a large base.

### Open questions

- Should the belt and inserter hints also watch during `plate_line` and `four_drills`?
- Should `connect` and `coal_loop` check the actual layout (e.g. an inserter feeding a drill's fuel slot from a belt)? That needs an entity graph query, not a counter.
- doc/quests.md needs the `counter` objective type, `produced_since_active` and the three counters in its "As implemented" notes; this run could not touch it.
