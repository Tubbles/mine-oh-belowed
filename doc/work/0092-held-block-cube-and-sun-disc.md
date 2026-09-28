# 0092 A held block as a cube, sun and moon discs that face the player

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): holding a block item shows a flat texture face in the hand; it should be the block. The sun turns into an ellipse as it climbs.

## Deliverables

- First person hand (`src/render_player.odin`, 0066): an item that places a block draws a small cube of about 0.35 blocks in the hand with the block's atlas tiles on its faces (top, side, bottom groups, the item atlas is not used), lit like the arm; every other item keeps its icon billboard. A pure `held_block_cube_corners` with a test.
- Sky discs (`src/render_sky.odin`, 0064): the sun, the moon and its shadow disc are drawn as quads facing the camera along the disc's own direction (right and up from the direction vector, not the camera's axes, drawn with `rl.DrawBillboardPro` given those vectors or through rlgl), so a disc high in the sky stays round; the satellite quad the same. A pure `disc_axes(direction) -> (right, up)` with a test that both are unit length and perpendicular to the direction at the zenith and at the horizon.
- Docs: `doc/ui.md` (the hand), `doc/architecture.md` (the sky line), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: a held stone block is a cube; the sun is round at noon.

## Notes

Files a subagent may touch: `src/render_player.odin`, `src/render_player_test.odin`, `src/render_player_model.odin`, `src/render_sky.odin`, `src/render_sky_test.odin`, the docs above, this file.
