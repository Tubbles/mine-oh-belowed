# 0021 Assembler, lab and the technology screen

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (kinds `assembler` and `lab`, machines `assembler_1` and `lab`), `data/technologies.sjson` (`science_packs`, `prerequisites`, `placeholder`), `data/strings/en.sjson`, new `assembler.odin`, `lab.odin` (lab entity, research queue, technology status), `technology_browser.odin` (pure part of the technology screen), `ui_technologies.odin`, `ui_crafting_machines.odin` (assembler and lab panels), tests in `assembler_test.odin`, `lab_test.odin` and `recipe_browser_test.odin`, plus changes to technology, machine, recipe (assembler slot limit), entity, placement (pick up returns a craft in progress), item transfer, inventory interaction (`Slot_Filter` is now a struct with an `Item` kind), power network, World (`research`), Simulation_Content (`technologies`), loop, main, recipe browser and its screen, machine panel, screens, inventory tabs, input actions and bindings, UI input, diagnostics, renderer and the test world.

### Model and deviations

- Technology cost names its pack items: `science_packs = ["science_pack_1"]`, one of each per unit. The lab's slots are the distinct pack items of all technologies in order of first appearance (`Technology_Registry.science_packs`), copied into `Machine_Registry.lab_packs` after loading because machines load before technologies.
- Prerequisites must be listed earlier in the file, which rules out cycles without a graph search. Chain: automation first; logistics, electric mining and steel processing need automation; optics needs electric mining; fluid handling and prospecting need steel processing; logistics science needs logistics; fast belts need logistics science. `doc/content.md` gives no prerequisites, so this chain is a proposal.
- Unlock lists were already filled for every technology whose recipes exist; only `logistics_science` and `fast_belts` are empty and are now `placeholder = true`. The loader rejects any other technology that unlocks nothing. Placeholders show and can be researched (they open nothing).
- The research queue lives in `World.research` so the lab tick and the power demand reach it; completion sets a flag that `simulation_tick` applies with `mark_technology_researched` right after the entity tick, since the unlocks live in `Simulation_State`.
- Queueing another technology starts it from zero (progress is not kept per technology) and drops any unit in progress with its packs; queueing the queued one again keeps its progress. Labs start a unit only while units done plus units in progress are short of the cost, so several labs never overshoot; the count of units in progress is recomputed every tick, so picking up a lab mid unit loses nothing but that unit.
- Assembler state check order: no recipe, missing ingredients, output full (checked before a craft starts, so a finished craft always fits), then no power. A lab with nothing left to start (the other labs hold the last units) shows "No research".
- Changing an assembler's recipe hands every slot plus the ingredients of a craft in progress to the player and is refused with a toast when they do not fit. Picking an assembler up also returns the craft in progress.
- Inserters fill an assembler input or lab slot up to the stack size; there is no Factorio style insertion limit of about two crafts.
- Recipe selection: the assembler panel's recipe button opens the recipe browser in a selection mode (`Recipe_Browser.selecting_for`) with `selection_filter`: assembler recipes that are available, craftable toggle and crafting input off. Confirm sets the recipe and pops back to the panel. A machine panel now stays open under the recipe browser or the technology screen (`close_slot_screens` checks the whole stack).
- Technology screen: `Open_Technologies` on keyboard T, a pause menu button, a third inventory tab and a button in the lab panel. The list is sorted by name with a "Hide researched" toggle rather than grouped by status, so the letter jump stays meaningful. No gamepad button for it (like journal and power).
- No toast when research completes; the technology screen, the lab panel and the diagnostics line show it.

### Not verified

Everything visual and the feel: the assembler and lab panels (slot rows, bars, recipe button) at 720p, 1080p and UI scale 1.5, the technology screen layout and text widths, the selection mode title and glyph bar, the third inventory tab, the pause menu height with seven buttons, the placeholder colours of assemblers and labs, focus movement and the pointer on the new rows and buttons. The user verify (assembler fed by inserters makes gears, labs research automation, the assembler recipe loses its silhouette) is covered in tests but not played. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Should research progress be kept per technology when the queue is switched (Factorio does)?
- Is the prerequisite chain above the wanted one?
- Should placeholder technologies be hidden or unqueueable until their recipes exist?
- A toast (and a quest notice) when research completes?
- Insertion limit for assemblers and labs, so one inserter does not pour a whole belt into one machine?
- `doc/fluids.md` (as implemented notes: queue in the world, restart on switch, state order, placeholder rule, prerequisites order), `doc/content.md` (prerequisites column, machine values now in `data/machines.sjson`), `doc/input.md` (T) and `doc/ui.md` (selection mode, technology screen) need updates; this run could not touch them.
