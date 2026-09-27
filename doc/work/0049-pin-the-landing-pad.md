# 0049 A loaded world keeps its landing pad

Status: implemented
Milestone: M10

## Goal

The pad and the starter veins are computed from the seed by the spawn search, so a change to the spawn rules (0045 made one) moves an existing world's pad on load, with the saved chunks still holding the old one. Now that saves survive builds (0047) the pad must be pinned.

## Deliverables

- `world.sjson` carries the landing pad's centre. A loaded world sets the generator's pad from the file and skips the spawn search; a file without a pad falls back to the search. New worlds are unchanged.
- Tests: the world file round trip keeps the pad; a loaded world starts on the file's pad; a file without one, or a new world, goes through the search.

## Verify

- Builds and tests pass.
- User: a world saved today keeps its pad after the next generation change.

## Notes

Implemented by the main agent (2026-09-27). The simulation state keeps its `Landing_Pad_Site` so the world file writer has it; `saved_world_start` in `src/main.odin` does the load side, `start_session` tries it before `choose_world_start`.
