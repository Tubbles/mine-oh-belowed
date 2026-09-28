# 0096 Chapter 2: the drill before the fifty plates, and a spent outcrop that says so

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): chapter 2's "plates" quest (obtain 50 iron plates) empties the starter iron outcrop's visible blocks before the player has placed a drill on it, which does not feel right. The user chose options 1 and 4: reorder chapter 2 so the burner mining drill comes right after gears and the fifty plates become the drill's quest, and tell the player when the last outcrop block goes that the vein continues below.

## Deliverables

- `data/quests/chapter_02.sjson`: the quest order becomes furnaces, copper, gears, drill (placed on the iron outcrop, with a hint if it stands on no vein), plates (50 iron plates produced since activation, `produced_since_active`, so the drill's output counts), storage, survey, invoice; the "plates" quest text and its Mission Control lines say the drill feeds the furnaces now. Rewards stay with their quests. `doc/quests.md`'s chapter 2 paragraph follows. The chapter 2 test (`src/quest_chapter_02_test.odin`) follows the new order and asserts the drill quest precedes the plates.
- The spent outcrop: when a player mines the last outcrop block of a surface vein whose units remain (the vein registry knows both, `src/world_vein.odin`; `Hint_Counter` or a new quest message hook in `src/quest_runtime.odin`), Mission Control says once per vein "The outcrop is spent on the surface. The vein continues below: a drill on this ground still taps it." (`mc_outcrop_spent`), and the map keeps the vein's footprint drawn as the assayed footprint layer does for a vein with no outcrop left (`src/ui_map.odin`, `src/prospecting.odin` if the footprint layer needs the vein even when unassayed: a spent outcrop counts as known). The HUD's vein line under the crosshair already names the vein on its columns.
- Tests: the chapter order and the drill gate, the spent outcrop message fires once per vein and not while blocks remain, the map draws the footprint of a spent vein.
- Docs: `doc/quests.md`, `doc/content.md` (the outcrop line), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: chapter 2 asks for the drill before the fifty plates; mining the last visible ore block brings the Mission Control line and the map still shows the vein.

## Notes

Files a subagent may touch: `data/quests/chapter_02.sjson`, `data/strings/en.sjson`, `src/quest_chapter_02_test.odin`, `src/quest_runtime.odin`, `src/quest.odin` (a hint counter if needed), `src/statistics.odin` (the counter), `src/world_vein.odin`, `src/world_vein_test.odin`, `src/player_interaction.odin` (the hook where an outcrop block is mined), `src/ui_map.odin`, `src/prospecting.odin`, `src/prospecting_test.odin`, the docs above, this file.
