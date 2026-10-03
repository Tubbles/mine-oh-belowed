# 0017 Splitters

Status: implemented
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

## Notes

Implementation notes from the subagent run (2026-09-27).

Files: `data/machines.sjson` (kind `splitter`, machine `splitter`), `data/strings/en.sjson`, `splitter.odin` (entity, routing, splitter node, add, remove, rotate), `splitter_test.odin`, plus changes to belt (links, lines, order, item records), belt movement, entity, placement, item transfer, machine, machine panel, a `ui_choice` widget, the belt renderer, the placement ghost, and the test world and machine tests.

### Model

- Each half is a one block line of its own (the half's output line, holding just the splitter handle), created after the belt lines. It continues into whatever stands in front of the half exactly like a flat belt would (straight, side load, curve, another splitter's input). A belt facing into a half from behind ends its line with the new end kind `Splitter`; from the side or head on it is a dead end. So the network sees two line ends and two line starts per splitter, four in all.
- The line order became a depth first walk with splitter nodes in it (`order` entries below zero name a splitter). A splitter node runs after its output lines and before its input lines. For each lane it takes the input whose turn it is (or the priority input) first and moves that input's front item into an output when the item reaches the entry edge this tick. An item arriving n units past the edge lands n units into the half, capped a spacing behind the half's back item like a straight hand off, so crossing costs no distance (tested against a straight seven belt run tick by tick).
- An item that does not cross waits up to the edge, or a spacing behind the back item of the output it may take (the one that frees first), or like a dead end when none of its outputs has anything in front.
- Round robin state is per lane on the splitter (`next_output`, `next_input`) and advances only when an item crosses. With a filter set there is no round robin: the filter item goes only to the filter side and every other item only to the other side, each stalling when its side is full. Output priority tries the priority half first; input priority serves the priority input first each tick, so the other input only fills gaps.

### Deviations and choices

- Footprint: `width = 1, depth = 2, height = 1` in the data, because the unrotated flow runs along x (like every other entity's rotation 0) and the two halves sit across it. It is the 2 by 1 by 1 of `doc/content.md` read as two across the flow.
- Placement: direction relative to the facing like inserters; the targeted cell becomes the left half and the right half extends to the right of the flow. No player overlap check (the splitter is walked over like belts, but does not carry the player). A splitter cannot be placed onto existing belts: the gap has to be free.
- Rotate turns a placed splitter half way round (a quarter turn would move a cell); items inside stay in their cells.
- A splitter is a transfer interface entity that neither takes nor gives, so inserters and drills ignore it. Picking it up returns the items inside its halves; items of a removed splitter are otherwise dropped from the lines like a removed belt's.
- Items change halves at the entry edge, so an item routed to the other side jumps sideways by a block when it enters the splitter (placeholder rendering, no lateral animation).
- Panel toggles use a new small `ui_choice` widget (label left, value right, fixed id so focus stays on it when the value changes), built from the same `ui_interact` pieces as `ui_toggle`. The filter slot reuses the inserter's ghost filter behaviour (`inserter_filter_after_input`).
- `tick_belt_network` takes the splitter pool as an optional third argument; `compute_belt_line_order` takes it as an optional second one.

### Not verified

Everything visual and the feel: the splitter surfaces and frame, the arrow and its direction relative to the facing, the ghost, items jumping between halves, the panel layout and focus order at 720p and 1080p and UI scale 1.5, the choice rows with gamepad and mouse, the filter slot. The user verify (plate belt split into two chests, then a priority) is not run. The shipped data was loaded through the real loader by starting the binary without a display.

### Open questions

- Should placing a splitter onto a belt replace it (Factorio's fast replace)? Right now the player has to pick up the belt first.
- Is the targeted cell as the left half the right placement gesture, or should the splitter centre on the seam between two cells?
- Should a splitter carry the player like a belt?
- `doc/logistics.md` needs an "As implemented in 0017" note (half lines, the `Splitter` line end, the node order, crossing and waiting positions, per lane round robin, filter without round robin, half turn rotation, footprint orientation), and `doc/content.md` (splitter values in `data/machines.sjson`); this run could not touch them.
