# 0039 Quest chapter 7: scale

Status: todo
Milestone: M8

## Goal

Chapter 7 from `doc/quests.md`: a second vein feeding the base, a deep vein tapped from the surface, a two floor factory, hydro power, a cave schematic. Main quest gate: the launch pad permit (a `rocket_program` quest gated placeholder).

## Deliverables

- `data/quests/chapter_07.sjson` with quests on existing and new counters (bore drill placed and producing, a schematic found, a turbine generating, a substation placed, a sustained plate rate of 60 per minute), hints for a bore drill without a deep vein below and for a turbine in still water, Mission Control strings in tone, the main quest delivering aluminium plate and silicon and rewarding the `rocket_program` placeholder plus items.
- Tests: chapter loading, the sequence, the counters, the ordering test.

## Verify

- Builds and tests pass.
- User: couch test 4. A base with several veins, a deep vein tapped from the surface, and a two floor factory keeps 60 ticks per second.
