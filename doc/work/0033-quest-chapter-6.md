# 0033 Quest chapter 6: fluids

Status: todo
Milestone: M7

## Goal

Chapter 6 from `doc/quests.md`: a water network with a pump uphill, the tar pit pump, refinery, gases into tanks, plastic on both routes, waste gas into a generator, and the main quest gate: a deep mining permit that unlocks bore drills and the seismic survey (placeholder technologies until M8).

## Deliverables

- `data/quests/chapter_06.sjson` with those quests using existing objective types, hints for a closed mixing port ("Two fluids, one pipe. The pipe declined.") on a new counter of mixing refusals and for the flare stack burning more than a threshold, Mission Control strings in the established tone, the main quest delivering plastic and sulfur and rewarding the `deep_mining` placeholder technology plus items that exist.
- Tests: chapter loading, sequence on synthetic counters, the mixing counter, the ordering test.

## Verify

- Builds and tests pass.
- User: couch test 3. Plastic is produced on both routes and the waste gas runs a generator.
