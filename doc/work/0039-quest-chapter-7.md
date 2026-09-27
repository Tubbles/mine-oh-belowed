# 0039 Quest chapter 7: scale

Status: implemented
Milestone: M8

## Goal

Chapter 7 from `doc/quests.md`: a second vein feeding the base, a deep vein tapped from the surface, a two floor factory, hydro power, a cave schematic. Main quest gate: the launch pad permit (a `rocket_program` quest gated placeholder).

## Deliverables

- `data/quests/chapter_07.sjson` with quests on existing and new counters (bore drill placed and producing, a schematic found, a turbine generating, a substation placed, a sustained plate rate of 60 per minute), hints for a bore drill without a deep vein below and for a turbine in still water, Mission Control strings in tone, the main quest delivering aluminium plate and silicon and rewarding the `rocket_program` placeholder plus items.
- Tests: chapter loading, the sequence, the counters, the ordering test.

## Verify

- Builds and tests pass.
- User: couch test 4. A base with several veins, a deep vein tapped from the surface, and a two floor factory keeps 60 ticks per second.

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: new `data/quests/chapter_07.sjson` and `src/quest_chapter_07_test.odin`; changes to `statistics.odin` (four counters, `TURBINE_STILL_WATER_SECONDS`), `quest.odin` and `quest_runtime.odin` (four hint counters), `drill.odin` (bore drill units), `entity_placement.odin` (`Placement.no_deep_vein`, refused Place counted), `fluid_machine.odin` (`still_water_ticks`), `power_network.odin` (turbine energy and the still water streak; `apply_electric_balance` takes the tick rate); data in `technologies.sjson` (`rocket_program`), `strings/en.sjson`, `quests/chapter_01.sjson` (counter list, including the 0036 and 0038 counters it was missing); the quest, recipe and lab tests (chapter count, technology count, technology screen order, placeholder comments).

### Chapter 7 as shipped

1. `second_vein`: research `prospecting`, `veins_assayed` 2 since activation, 4 electric mining drills placed in total.
2. `deep_permit`: research `electrolysis`, `core_samples_taken` 1, 1 bore drill, `bore_drill_units` 200; hint "The drill needs a vein below it. The venture needs a contractor who checks." on `bore_drill_no_vein_attempts` 3.
3. `aluminium`: 50 aluminium plate and 20 silicon produced since activation.
4. `two_floors`: 10 belt lifts and 20 concrete blocks placed.
5. `hydro`: research `hydro_power`, 1 hydro turbine, `turbine_kilojoules` 10000 (10 MJ); hint "A turbine in still water is a sculpture." on `turbine_still_water_ticks` 1.
6. `grid`: research `electric_grid`, 1 substation.
7. `schematic`: `schematics_found` 1; hint "The seismic charge found rock. The venture found the invoice." on `seismic_shots` 1.
8. `sixty`: sustain 60 iron plates per minute for 5 minutes.
9. `launch_pad_permit` (main): deliver 100 aluminium plate and 50 silicon (3 of 8 capsule slots); rewards `rocket_program` through `unlocks_technology`, 200 steel, 100 plastic bars (5 slots).

No reorder was needed: the whole chapter ordering test passes with chapter 7 appended.

### Deviations and choices

- Turbine energy: the statistic is `turbine_joules` as asked, but the counter the quest reads is `turbine_kilojoules` (`turbine_joules / 1000`, count 10000), because the journal prints counter progress as plain integers and "0 / 10000000" is unreadable. Same pattern as `distance_walked` over millimetres.
- `turbine_still_water_ticks` counts streaks, not ticks: it grows by one when a turbine reaches 600 ticks (`TURBINE_STILL_WATER_SECONDS` 10 at 60 Hz) in a row in state `No_Water`, and again only after water returned and a new streak reached 600. The name is the one in the brief, which a threshold of 1 only makes sense with. "Producing zero" is read as no flowing water (`No_Water`), not zero delivered: a turbine in flowing water with no consumer is `Idle` and is not a sculpture.
- `bore_drill_no_vein_attempts` counts a pressed Place whose footprint is otherwise valid and only the deep vein is missing, in `place_entity_with_player`, not in `placement_at` (that runs every frame for the ghost). A footprint refused for another reason as well does not count.
- `bore_drill_units` counts units when they leave the drill (`output_drill_item`), like `produced`; a unit held for lack of room counts once it goes out.
- `two_floors` asks for concrete only: a place objective names one item, and asphalt needs `bitumen_paving`, which no quest researches (the ordering test would fail on it).
- `rocket_program`: `placeholder = true`, `quest_gate = true`, `unlocks = []`. Guessed: prerequisite `electrolysis`, 300 packs of 30 s, science packs 1 and 2.
- `doc/quests.md` bends (not edited, outside the file list): the hint counter list needs the four new counters, chapter 7 needs an "As implemented" note, and the outline's "two floor factory" is only approximated by placements. Chapter 6's `mc_deep_mining_permit_done` still says the bore drill schematics are "pending", which 0035 made stale.
- Saves: `Statistics` and `Fluid_Machine` gained fields, so older saves are refused by the layout fingerprint.

### Not verified

Everything played or seen: the journal lines ("Kilojoules from hydro turbines 0 / 10000"), the tone of the new lines in context, and the pacing of every count (200 bore drill units is under four minutes of one bore drill after its three minute bore; 10 MJ is about 42 s of a turbine at 240 kW with enough load). Research objectives on science pack 2 technologies (electrolysis, hydro power, electric grid) rely on `logistics_science`, which no quest asks for; the ordering test checks prerequisites, not packs. The shipped data loads through the real loader (the binary gets past content loading and fails only at opening a window).

### Open questions

- Should `two_floors` accept asphalt too (a place objective over several items, or a `bitumen_paving` research objective first)?
- Should `turbine_still_water_ticks` be renamed to what it counts (for example `turbines_in_still_water`)?
- Should the still water hint also fire for a turbine in flowing water with nothing to power?
