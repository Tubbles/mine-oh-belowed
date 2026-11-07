# 0326: Waters over the whole planet

Status: todo (2026-11-07)

0312 finds springs and lakes on one grid within 2.5 km of the home (at most half the radius), once per session on the main thread. Past it the ground has no derived springs and no lakes, which a player meets after a few minutes' walk on the 8 km planet.

## Goal

Derived springs and lakes everywhere on the planet, by the same rules as 0312's, without a longer start.

## Controls

None.

## Change

- Tiles of 0312's grid over the planet, found lazily as chunks are wanted and shared by the generation workers, deterministic on every machine whatever order they are asked in. A lake or a drainage crossing a tile's edge is found whole.
- The home's tile is the one the session waits for; the others are found on the workers.
- The relief map draws every tile it covers.
- Docs: `doc/architecture.md` (World generation, the waters).

## Verify

- The checks and the suite, with a test that two orders of asking for the tiles give the same springs and lakes.
- The relief map of the whole 8 km planet, sent to the user.
