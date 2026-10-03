# 0212: The stone furnace, redone from the ground up under supervision

Status: todo (user, 2026-10-03: the 0205 models "are fine for very rough placeholder ideas ... but they are very flat, both geometry and color wise ... they need to be completely scrapped ... i want us to completely scrap a single machine and redo it from the ground up, with my supervision ... Lets do the stone furnace first. I want it to be larger, feeling awe-inspiring, formidable, and intimidating through sheer presence, more akin to satisfactory style machine sizes"; after 0211)

## Goal

The stone furnace is the first machine made in the chosen art direction, from nothing: larger than today's 2 by 2 by 2 cells, formidable through sheer presence as Satisfactory's machines are, modelled against the reference sheet of 0211's second session, with the user judging every round on the couch and in the previews.

## Change

- The footprint grows (the user chooses the size on the reference sheet; a candidate is 4 by 4 by 5 cells, 2 by 2 by 2.5 m, with the record's `footprint`, ports and open cells changed to match; the recipes, the quests and the dev kits that place it are checked for the new size, and an old save's furnace keeps its saved footprint through the remap of 0196's kind).
- The modeller never sees the old model (user, 2026-10-03: "When the subagent works on the new model it shall not have seen the old one"): before its worktree is handed over, the old `tools/models/machines/stone_furnace.py`, `data/models/stone_furnace.obj` and `.mtl` are deleted from it, and its brief names the reference sheet, the record, the kit and the workbench only, never the old script, the old previews or 0204's log entry. The design stage writes the block from the reference sheet.
- Rounds: the implementer hands back previews from the workbench (0207); the main agent sends them; the user says what to change; the same agent iterates until the user accepts. The accepted model lands with its reference sheet in `doc/art/`.
- What is learned about the kit (primitives the look needs, a material or shading rule) goes into `tools/models/kit.py`, `DESIGN.md` and the log, so the next machine starts from it. The other machines follow one at a time, each its own item.

## Controls

- None.

## Verify

- The workbench's check passes, the previews read as the reference sheet, the suite passes with the new footprint, an old save loads.
- The couch: the user stands next to it and it feels formidable.
