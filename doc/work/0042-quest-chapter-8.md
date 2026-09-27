# 0042 Quest chapter 8: rocket program and the soft ending

Status: todo
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
