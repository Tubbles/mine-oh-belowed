# 0021 Assembler, lab and the technology screen

Status: todo
Milestone: M4

## Goal

The assembler making data recipes with inserter fed slots, the lab consuming science packs to research technologies, and the technology screen for queuing research, completing the M4 research loop.

## Deliverables

- Assembler entity (3 by 3 by 2, 75 kW, speed 0.5) with recipe selection in its panel through the recipe browser filtered to assembler recipes, input and output slots derived from the chosen recipe, slot rules on the transfer interface, progress and state (no recipe, missing ingredients, output full, no power).
- Lab entity (3 by 3 by 2, 60 kW) consuming science packs from its slots for the queued technology at speed 1, several labs sharing one technology's progress, completion marking the technology researched.
- Technology screen per `doc/fluids.md`, reachable from the pause menu and the inventory tabs, with letter wheel and the two navigation styles, showing status, cost and unlocks, queuing one technology.
- The science pack 1 recipe already exists; check the technology costs in `data/technologies.sjson` against `doc/content.md` and fill the empty unlock lists that have recipes in the data.
- Tests: assembler slot derivation and crafting with byproducts, ingredient routing through the transfer interface, lab consumption and completion, shared progress between two labs, research unlocking recipes, technology screen filtering and ordering, determinism over 1200 ticks.

## Verify

- Builds and tests pass.
- User: an assembler fed by inserters makes gears, a lab fed with science packs researches automation, and the newly available recipe shows up in the browser without silhouette.
