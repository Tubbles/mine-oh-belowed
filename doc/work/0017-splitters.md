# 0017 Splitters

Status: todo
Milestone: M3

## Goal

Splitters across two belts with round robin distribution, input and output priority, and one output filter, with their panel.

## Deliverables

- Splitter entity kind (2 by 1 by 1) with direction, placement across two lanes of belts, line integration so that both inputs and both outputs are line ends and starts.
- Round robin per item across outputs with priority flags and a filter item, per `doc/logistics.md`, all data fields on the entity.
- Panel with the priority toggles and the filter slot.
- Tests: even split of one input, merge of two inputs, priority output taking everything until full, filter routing, and determinism.

## Verify

- Builds and tests pass.
- User: split a plate belt into two chests evenly, then set a priority and watch one chest fill first.
