# 0022 Quest chapter 4: power

Status: todo
Milestone: M4

## Goal

Chapter 4 from `doc/quests.md` as data: pump, boiler and engine, the first pole, lights on (glass from sand), the electric drill, an assembler making gears, a lab and the first research, the brownout hint, a second engine, and the main quest "The first contract" (deliver 100 electronic circuits) whose reward opens phase 5 in message and capsule.

## Deliverables

- `data/quests/chapter_04.sjson` with the quests above using existing objective types, new hint counters for brownout ticks and machines without power, Mission Control strings in the established tone.
- Tests: chapter loading, the new counters, the sequence completing on synthetic counters, the reward landing.

## Verify

- Builds and tests pass.
- User: the M4 verify statement. Following the journal only, an unattended line mines iron ore, smelts it, assembles iron gear wheels into a chest, powered by steam, and completes at least one research.
