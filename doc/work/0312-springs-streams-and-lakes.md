# 0312: Springs, streams and lakes in the highlands

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, after 0306. The user (2026-11-06): elevation "for testing the water tech demos".

## Goal

Water belongs to the landscape: springs at valley heads in the highlands, lakes filled in basins above the sea, streams running between them under the water field, all from the seed. The tech demo can start at a spring with a long fall to the sea.

## Controls

None.

## Change

- Springs generated from the relief (valley heads, a count per area from data) beside the record's springs; lakes in basins above the sea filled at generation as the sea is, each a water body (0293).
- The cost of many sources under both water models measured, and a cap or a sleep rule if needed.
- Old worlds keep their water: off in a world record without it.
- Docs: `doc/fluids.md`, `doc/content.md` (Planets); the log.

## Verify

- The checks and the suite.
- A map of the springs and lakes over 0306's relief map; a clip of a stream from its spring to a lake in the tech demo; sent to the user.
