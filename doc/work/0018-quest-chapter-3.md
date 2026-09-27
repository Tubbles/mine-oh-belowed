# 0018 Quest chapter 3: belts

Status: todo
Milestone: M3

## Goal

Chapter 3 from `doc/quests.md` as data, including the main quest gate for phase 4 (an unattended ten minute run) that unlocks the steam engine recipe through the quest channel, and the hints about belts ending nowhere and inserters facing the wrong way.

## Deliverables

- `data/quests/chapter_03.sjson` with the quests from `doc/quests.md`: connect a drill to a furnace with a belt and an inserter, the coal loop, a chest at the end of a plate line, four drills feeding three furnaces, and the main quest "Prove the outpost" (sustain 10 iron plates per minute for ten minutes hands off) rewarding the steam engine recipe unlock and a capsule.
- New hint counters as needed: a belt line ending in nothing for a minute, an inserter with nothing to pick for a minute, both from the entity states.
- Mission Control strings for the chapter in the established tone.
- Tests: chapter loading, the new hint counters, the main quest unlock reaching the recipe channel.

## Verify

- Builds and tests pass.
- User: following the journal only, reach the steam engine recipe by running an unattended plate line for ten minutes.
