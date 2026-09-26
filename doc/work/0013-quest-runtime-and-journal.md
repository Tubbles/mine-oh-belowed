# 0013 Quest runtime and journal, chapters 1 and 2

Status: todo
Milestone: M2

## Goal

The quest system from `doc/quests.md` as data and runtime, with chapters 1 and 2 written out, the HUD objective, contextual hints, Mission Control messages and reward capsules.

## Deliverables

- `data/quests/chapter_01.sjson` and `chapter_02.sjson` with the objective types from `doc/quests.md` (obtain, craft, place, sustain, research, deliver, discover), hints with their counter triggers, messages, rewards.
- Production statistics counters in the simulation (produced and obtained per item, placed per entity, machine stalls, fuel outs) as the day one system `doc/architecture.md` calls for; the quest runtime evaluates objective predicates against them every tick.
- Reward capsules: a landing pad block structure at the spawn, a capsule entity that lands with the reward items and can be emptied like a chest.
- Journal screen: chapters, active and completed quests, the focused quest's objectives with progress, the message log. HUD shows one active objective.
- Tests: every objective type against synthetic counters, hint triggers firing once, chapter completion order, data loading of both chapters.

## Verify

- Builds and tests pass.
- User: the M2 verify statement. Following the journal only, craft a stone furnace and an iron pickaxe using only the controller, starting from an empty inventory.
