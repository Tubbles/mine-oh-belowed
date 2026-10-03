# 0013 Quest runtime and journal, chapters 1 and 2

Status: implemented
Milestone: M2

## Goal

The quest system from `doc/quests.md` as data and runtime, with chapters 1 and 2 written out, the HUD objective, contextual hints, Mission Control messages and reward capsules.

## Deliverables

- `data/quests/chapter_01.sjson` and `chapter_02.sjson` with the objective types from `doc/quests.md` (obtain, craft, place, sustain, research, deliver, discover), hints with their counter triggers, messages, rewards.
- Production statistics counters in the simulation (produced and obtained per item, placed per entity, machine stalls, fuel outs) as the day one system `doc/architecture.md` calls for; the quest runtime evaluates objective predicates against them every tick.
- Reward capsules: a landing pad block structure at the spawn, a capsule entity that lands with the reward items and can be emptied like a chest.
- Journal screen: chapters, active and completed quests, the focused quest's objectives with progress, the message log. HUD shows one active objective.
- Tests: every objective type against synthetic counters, hint triggers firing once, chapter completion order, data loading of both chapters.

## Verify

- Builds and tests pass.
- User: the M2 verify statement. Following the journal only, craft a stone furnace and an iron pickaxe using only the controller, starting from an empty inventory.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/quests/chapter_01.sjson` (9 quests, the format is documented at its top), `data/quests/chapter_02.sjson` (8 quests), `statistics.odin` (counters and the rate ring), `quest.odin` (data, validation, loading), `quest_runtime.odin` (tick, hints, completion, rewards, capsule landing), `landing_pad.odin` (pad stamping, capsule), `ui_journal.odin` (journal screen, HUD objective, word wrap), tests in `statistics_test.odin`, `quest_test.odin`, `quest_runtime_test.odin`, plus changes to entity, machine, furnace tick, player, mining, placement, crafting, recipe unlocks, generation, loop, main, input, UI core, pause menu, HUD, diagnostics, `blocks.sjson`, `machines.sjson` and the strings.

### Deviations

- Statistics live in `World.statistics`, next to the entities, so `tick_player` and `tick_entities` reach them without new parameters (the same reasoning as the entity pools in 0011). Counters: produced (crafted and smelted), obtained, delivered, placed per machine, mining ticks per block type, furnace stalls (out of fuel, output full, counted on entering the state), fuel burned, blocks mined, distance walked (millimetres, on foot only), inventory full ticks, world actions. The rolling rate is 60 per second buckets per item; the rate is the current second so far plus the 59 before.
- Obtained is the growth of what players hold (inventory and cursor) from one tick to the next, not a hook in each path, because taking from a machine happens in the UI between ticks. It covers mining, taking from machines and the capsule, and crafting. Side effects: crafted items and ingredients returned by a cancel count as obtained, and putting a stack into a chest and taking it back counts again. Starting items do not count.
- Delivered works the same way on the capsule's contents: growth since the last tick counts, landing rewards do not. A deliver objective's progress is what was put in since the quest became active and is still in the capsule; completion removes that many.
- obtain, craft, place and walk count since the game began, so work done ahead of the journal counts. Hints count from activation. place counts placements, not standing machines (placing and picking up one furnace three times satisfies "place 3").
- The landing pad is stamped by world generation, not placed on first load: the spawn is a function of the seed and generation a pure function of seed and chunk, so the pad regenerates identically on every load with no flag to save. The generator gets the site before streaming starts. The pad clears 10 blocks of air above itself. The capsule is an entity added by `make_simulation` at the pad corner the player faces. `--debug-terrain` has no pad blocks; its capsule stands on the terrain near the origin.
- The capsule is a machine of the new kind `capsule` in `machines.sjson` with no item: it cannot be picked up (a long Mine press on it does nothing) and opens like a chest (8 slots, no sort).
- Mission Control lines and the capsule landing show as toasts; the journal's message log shows game time (m:ss) derived from the tick rather than the raw tick.
- The pause menu's Journal button replaces the pause menu, like Recipes, since the journal does not pause.

### Where doc/quests.md had to bend

- Beat 1 (arrival) is a quest with no objectives: it completes on the first tick, and its line is the opening message.
- Beat 2 needs an objective type the table lacks: `walk` (blocks walked on foot). "Looked around" is not measured.
- Beat 3's hint "holds mine on grass for two seconds" is cumulative: 120 ticks of holding Mine on grass since the quest began (grass breaks in 0.75 s, so a continuous two seconds cannot happen).
- Beat 6's line ("Hematite. The venture pays for plates, not rocks.") is the completion message. Beat 8's line ("Smelting takes time. Time is billed.") is a hint on the first fuel item burned, so it fills the wait.
- Beat 9 is chapter 1's main quest; its reward (50 coal, 10 iron plates) lands in the capsule.
- Chapter 2: the burner mining drill is crafted, not placed on the outcrop, and there is no refuelling quest, because drills are not entities yet. "200 plates in storage" is left out (no storage counter). The survey quest discovers charcoal, glass and the circuit. The main quest delivers 100 iron plates; belts and burner inserters exist as items, so the reward is 20 belts and 4 burner inserters and unlocks nothing.
- The fuel and chest hints of chapter 2 sit on the plate stock quest (hints only watch while their quest is active).

### Not verified

Everything visual and the feel: the journal layout (list, detail, log split) at 720p, 1080p and UI scale 1.5, word wrap with the real font, the HUD objective block top right against the toasts top left, silhouette rows, the capsule's placeholder cubes and the pad texture, the pad on sloped terrain (it floats where the ground is lower and cuts where it is higher), sky light above the pad right after generation, the toast length of long Mission Control lines, the J binding and the pause menu button with the controller. The user verify (the M2 run following the journal only) is not run. The shipped quest files were loaded through the real loader by starting the binary without a display.

### Open questions

- Should chapters run in parallel instead of in sequence? The brief says one active quest per chapter; this run plays all quests in one sequence.
- Should place count standing machines instead of placements?
- Should crafted items stay out of obtained, and should the obtain objective count from activation?
- The journal opens on the first chapter tab; open on the active quest's chapter instead?
- A gamepad button for Open_Journal (only J and the pause menu for now)?
- `doc/quests.md` (walk objective, arrival as an empty quest, where the lines sit), `doc/ui.md` (journal layout), `doc/input.md` (J) and `doc/architecture.md` (statistics in the world, obtained by holdings growth) need updates; this run could not touch them.

