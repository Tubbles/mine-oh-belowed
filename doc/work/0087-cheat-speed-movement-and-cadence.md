# 0087 Cheat speed: step up, jump two, and no faster cadence

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): with cheat speed on the player should climb single block heights without jumping and jump two blocks, and cheat speed must not speed up the head bob, the footsteps, the mining animation or the mining sound ("it sounds like an electric drill or machine gun").

## Deliverables

- Movement under cheat speed (`src/player.odin`, `cheat_speed_factor` and the collision sweep): a horizontal move blocked by a one block step while on the ground lifts the player onto it (a step up of at most 1.05 blocks, tried after the blocked sweep, only when the cells above the step are free), and the jump speed gives a two block apex (`PLAYER_JUMP_SPEED` scaled so the apex is 2.2 blocks with cheat speed on, 1.19 otherwise). Both only with cheat speed; normal play is unchanged.
- Cadence (`src/player_animation.odin`, `src/sound_events.odin`, `src/player_interaction.odin`): the walk phase, the head bob and the footsteps count the walked distance divided by the cheat speed factor, so a sprint at three times the speed bobs and steps at the normal rate; the mining chop animation and the mining hit sounds run at the normal mining cadence whatever the dig speed: hits at most `MINING_HIT_MAXIMUM_PER_SECOND` (3) and the chop period unchanged, so a tenth of the time dig plays one or two hits and the break.
- Tests: the step up lifts onto a one block ledge and not onto two, the cheat jump apex, the bob and footstep rate under cheat speed equal the normal rate, the hit rate cap.
- Docs: `doc/ui.md` or `doc/input.md` (cheat speed), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: with cheat speed on, walk up a one block ledge, jump onto a two block wall, and hear normal footsteps and mining hits.

## Notes

Files a subagent may touch: `src/player.odin`, `src/player_collision.odin`, `src/player_test.odin`, `src/player_animation.odin`, `src/player_animation_test.odin`, `src/sound_events.odin`, `src/sound_events_test.odin`, `src/player_interaction.odin`, `src/render_player.odin`, `src/loop.odin` (passing the cheat flag to the animation and sounds), the docs above, this file.
