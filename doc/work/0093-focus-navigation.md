# 0093 Focus navigation that follows rows and columns

Status: implemented
Milestone: M11

## Goal

Couch report (2026-09-28): on the Developer screen, pressing right from "Fly mode" lands on the middle button of the row below ("Statistics overlay") instead of "Cheat speed" beside it. The rule must be general, not a fix for one screen.

## Deliverables

- `find_focus_neighbour` (`src/ui_core.odin`) becomes a two pass beam search: first among the widgets of the same panel that lie ahead in the direction and whose extent across the direction overlaps the focused widget's extent (a widget in the same row for left and right, the same column for up and down), the nearest along the direction wins, ties by the smallest perpendicular offset; only when no widget overlaps does the second pass fall back to the weighted score used today. Wrapping (the behind fallback) stays for the second pass only.
- Tests (`src/ui_core_test.odin` or the existing focus tests): the Developer screen layout as rectangles (two rows of three buttons with a gap): right from the first lands on the second, down on the one below, right from the last stays or wraps as today; a settings column of full width rows; a grid of slots; a row whose neighbour is taller than the focused widget; a widget with nothing in its row falls back to the nearest below.
- Docs: `doc/ui.md` (the focus rule), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: the Developer screen and every panel navigate along rows and columns.

## Notes

Files a subagent may touch: `src/ui_core.odin`, `src/ui_core_test.odin` (new or existing), `src/ui_audit_test.odin`, the docs above, this file.

Implemented: `src/ui_core.odin` (`focus_extents_overlap`, `find_focus_in_line`, `find_focus_by_score`, `find_focus_neighbour` running them in turn), `src/ui_core_test.odin` (six tests: the Developer rows of two over three, two rows of three, a column of full width rows, a grid of slots, a taller neighbour in the row, the fallback to the nearest below), `doc/ui.md`, `doc/log/2026-09-28.md`. 959 tests pass.

