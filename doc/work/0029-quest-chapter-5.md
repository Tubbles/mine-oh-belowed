# 0029 Quest chapter 5: contracts

Status: todo
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
