# 0348: The sun's shadow map reused

Status: todo (2026-11-11)

The sun's shadow map is drawn every frame for every viewport: 0328 estimated 0.3 to 0.7 ms on the GPU and 0.4 to 1.2 ms on the CPU a viewport (`work/performance_research_0340.md`, 2.3). While the eye stands still nothing in it changes for many frames.

## Goal

The shadow pass costs nothing in the frames where its map would come out the same.

## Controls

None.

## Change

- The map is kept and redrawn when its snapped centre moved, the sun turned past a set angle, or a caster in its box changed (a frame, a felled tree, an edited chunk, a player, a moving part).
- Moving casters over a still map: a small pass of their own, or a redraw while one moves, as the design finds cheaper.

## Verify

- The checks and the suite, with a test per invalidation that the map is redrawn.
- 0342's table: the shadow pass in the still views and in split screen, before and after.
- Captures after a placement and after a felling showing no stale shadow, sent to the user.
