# 0337: The tree tiles' relief cost

Status: todo (2026-11-07)

From 0314's design. 0310's tree tiles read the relief once per candidate tree: 1.27 million reads for the home's 1,024 m view at 8 km, about a third of that view's generation cost once 0314 has bounded the chunks and grids. They came after the pre-0306 baseline 0314 measures against, so 0314 left them out.

## Goal

A fresh view's tree tiles cost a small share of its generation, with the same trees.

## Controls

None.

## Change

- Measure the reads per tile and per view from 0314's extended `test_report_the_relief_cost` (its tree line).
- Candidates: 0314's box ranges reused to reject a tile's candidates in water or above the tree line without reading their columns, one read per tree instead of per candidate, the far cards' tiles reading a coarser relief. The trees stay the bytes they are, or the change is recorded through the planet record.
- Docs: `doc/architecture.md` (World generation, the trees); the log.

## Verify

- The checks and the suite, with 0310's tree tests unchanged.
- The tree line of the report before and after, in the night window.
