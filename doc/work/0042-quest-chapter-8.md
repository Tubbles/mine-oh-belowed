# 0042 Quest chapter 8: rocket program and the soft ending

Status: implemented
Milestone: M9

## Goal

Chapter 8 from `doc/quests.md`: launch pad, rocket parts, the first shipment, a contract with a soft deadline, the orbital survey bought with a shipment, and the soft ending: the venture declares the outpost self sufficient in one sentence and the contracts continue.

## Deliverables

- Two carry overs first: chapter 7 gains a `research logistics_science` objective early (science pack 2 technologies need it), and chapter 6's permit line no longer calls the bore drill schematics pending.
- `data/quests/chapter_08.sjson`: research rocketry, place the launch pad, produce rocket parts, the first launch (`rockets_launched`), complete one contract, buy an orbital survey, research an infinite technology once, and the main quest "self sufficient": ship a total of 1000 items across shipments (a shipped total counter). Its completion message is the soft ending sentence, followed by a note that contracts continue. Hints: parts missing at the pad, cargo empty at launch.
- After the last quest completes the journal shows "Contracts continue" and the HUD objective line shows the current open contract instead of a quest.
- Tests: chapter loading, the sequence, the carry overs, the ordering test, the HUD objective source after the last quest.

## Verify

- Builds and tests pass.
- User: couch test 5. The first rocket shipment leaves and the returns arrive.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (585 tests), `./build.sh`, `./build.sh release`, and a headless start that stops at "could not open a window" after the quests load.

- Chapter 7's deep permit researches `logistics` and `logistics_science` before `electrolysis`. `logistics` is there too because `logistics_science` needs it and no earlier quest researches it, so the ordering test would fail without it.
- `ship` objective: an item and a count, or only a count for every item. It reads `Statistics.shipped` and the new `items_shipped` sum (kept in `record_shipment`), since the game began. `items_shipped` is also a hint counter.
- Research on an infinite technology needed no new code: `apply_finished_research` marks the technology researched in the unlocks on its first finished level, while `technology_status` keeps calling it available. The runtime header, the chapter 1 comment and a test say so.
- New counters `launch_parts_missing` and `launch_cargo_empty` count the launch pad panel's Assemble and Launch buttons when refused (`launch_refusal`, `assembly_refusal`). A launch with no cargo cannot happen, so the second counts refused requests. Interact on a pad that cannot launch opens the panel and counts nothing.
- Chapter 8 counter objectives count from activation: a contract fulfilled by the first launch does not count for the "contract" quest.
- After the last quest the HUD shows the oldest open contract (`hud_objective_source`, `draw_contract_objective`) and the last chapter's journal tab starts with "Contracts continue". The UI audit keeps a quest active, so neither is covered by it.
- Saves: the three new `Statistics` fields change the layout fingerprint and the new quests the content fingerprint, so older saves are refused (`header_problem`).
