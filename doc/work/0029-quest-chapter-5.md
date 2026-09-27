# 0029 Quest chapter 5: contracts

Status: implemented
Milestone: M6

## Goal

Chapter 5 from `doc/quests.md`: sorting mixed ore, crusher and washer, the first slag and where it goes, the recycler, an alloy line, and the production statistics screen introduced by a contract that asks for a rate. Main quest gate: a delivery that unlocks oil processing, "the venture has acquired the extraction rights", which opens phase 6.

## Deliverables

- `data/quests/chapter_05.sjson` with those quests using existing objective types (research ore processing, place crusher and washer, produce bronze, deliver concrete, sustain a plate rate read from the statistics), hints for a byproduct output stalling a machine ("Slag does not vanish. Give it somewhere to go.") and for the recycler, Mission Control strings in the established tone, the main quest reward unlocking a `oil_processing` placeholder technology through the quest channel and paying items that exist.
- Update the chapter 4 first contract reward to a crusher and a washer now that they exist.
- Tests: chapter loading, the chapter sequence on synthetic counters, the whole chapter ordering test still passing.

## Verify

- Builds and tests pass.
- User: couch test 2. A line that turns mixed ore into two alloys while every byproduct ends in a use or a sink.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `data/quests/chapter_05.sjson` and `src/quest_chapter_05_test.odin`; changes to `quest.odin` (place objectives on block items, `on_activation` hints, `unlocks_technology` rewards, hint counter `recycled`), `quest_runtime.odin`, `statistics.odin` (`blocks_placed` per item, `recycled`), `player_interaction.odin`, `ui_journal.odin`, `data/quests/chapter_01.sjson` (format description), `chapter_04.sjson`, `technologies.sjson`, `strings/en.sjson`, and the quest, chapter 4, lab and recipe tests.

### Chapter 5 as shipped

1. `low_grade`: research `steel_processing`, research `ore_processing`, obtain 20 `hematite_low_grade`.
2. `processing_line`: place 1 crusher and 1 washer, 50 crushed hematite produced since activation.
3. `slag`: place 20 slag heaps and 10 concrete blocks; hint "Slag does not vanish. Give it somewhere to go." when `furnace_output_full` grows by 3.
4. `alloys`: 40 bronze plates and 20 steel produced since activation.
5. `recycling`: research `recycling`, place 1 recycler, counter `recycled` 20; hint on `inventory_full_ticks` 1800 (30 s) pointing at the recycler.
6. `statistics`: sustain 30 iron plates per minute for 5 minutes (not hands off); the statistics hint fires on activation.
7. `extraction_rights` (main): deliver 200 concrete and 100 brass plates; rewards: `oil_processing` technology, 50 steel, 100 electronic circuits.

### Deviations and choices

- Reorder: `ore_processing` needs `steel_processing`, so the steel research objective moved from `alloys` to `low_grade`, before ore processing. `alloys` has no research objective.
- Low grade ore of any kind: obtain takes one item, so it is low grade hematite. The text says it comes from a drill, since hand mining yields high grade.
- Hematite through the washer: `produced` counts drill output too (`drill.odin` records it), so it cannot tell washed ore apart. The objective counts crushed hematite (crusher only) instead.
- Gravel from slag: no counter tells it from gravel from crushing ore (`consumed` of slag would, but no objective reads consumed counters). The slag quest instead places 20 slag heaps (the sink) and 10 concrete blocks (the use), through a new per item `Statistics.blocks_placed` counter and place objectives that name an `item` instead of an `entity` (the item must place a block). Counted since the game began, like machine placements.
- Slag hint: on `furnace_output_full` only. `Crafting_Output_Full` (the alloy furnace) is not a hint counter; a second hint with the same line on it would fire twice.
- New counter `recycled`: items recyclers took, counted when a recycling craft finishes (`record_craft_outputs`), not when an inserter loads one. Also a hint counter.
- Activation hint: `{on_activation = true, text_key}` with no counter or threshold resolves to a threshold 0 hint, which fires in the tick the quest activates. A threshold of 0 without the flag is still an error, so a forgotten threshold does not silently fire at once.
- The statistics hint reads "The venture reads rates, not effort. So should you. Statistics: N, or the pause menu." The pause menu part is added because N is keyboard only.
- Technology through the quest channel: rewards take `{unlocks_technology}`, which marks the technology researched (`mark_technology_researched`) at completion. `oil_processing` is a placeholder (unlocks nothing, labs refuse it, 100 packs of 30 s, after `ore_processing`). The reward validation accepts any known technology.
- Chapter 4: the first contract pays 1 crusher and 1 washer; its completion line no longer mentions plates or schematics ("A crusher and a washer are enclosed. The low grade ore is already on its way."). The crusher and washer work before `ore_processing` is researched, since fixed choice machines do not check recipe unlocks (0026).
- The ordering test now treats reward technologies as researched from the next quest on, and place objectives on items check the item.
- `doc/quests.md` bends: the objective table gains place by item, the hint list gains `recycled` and `on_activation`, rewards gain `unlocks_technology`, and chapter 5 needs an "As implemented" note. This run could not edit it. The format description in `chapter_01.sjson` is updated.
- Saves: `Statistics` gained two fields, so the layout fingerprint changes and older saves are refused, as with 0028.

### Not verified

Everything played or seen: the journal lines ("Place Slag 0/20" reads the item name, not "slag heap"), the toast timing of the activation hint next to the quest's opening line, whether 200 concrete plus 100 brass (6 of the capsule's 8 slots) fits alongside what players leave in the capsule, and the pacing of all counts. The shipped data loads through the real loader (the binary gets past quest loading and fails only at opening a window).

### Open questions

- Once `oil_processing` unlocks real recipes it stops being a placeholder, and the labs would then offer it. Add a quest only flag on technologies at that point?
- Should consumed counters become objectives (a `consume` type), so the slag quest can ask for slag crushed into gravel rather than slag heaps?
- Should the place objective on slag read "Slag heap" in the journal (the block's name) rather than the item's?
- 200 concrete and 100 brass take 6 of 8 capsule slots. Lower the counts or grow the capsule?
