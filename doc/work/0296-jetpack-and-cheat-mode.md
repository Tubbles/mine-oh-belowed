# 0296: Jetpack and cheat mode

Status: todo (2026-11-05)

Milestone: the water tech demo (0291); the player stream.

## Goal

The field player can jet: holding Jump in the air thrusts along the up with a budget that refills on the ground, so the player can climb out of a dug pit or hop to a terrace; and a cheat mode runs and flies faster and jumps higher so a planet of 8 km is explorable in minutes. Sprint (L3) and jump (A) stay as they are.

## Controls

- Jetpack: Jump (A) held while airborne after the jump's apex, or pressed again in the air, thrusts along the up at `jetpack_acceleration` until the `jetpack_budget_ticks` is spent; the budget refills at `jetpack_refill_ticks` per tick on the ground. No new binding: the jump button gains the jet in the air, which it has no meaning for today, and nothing changes while an item is held. A HUD bar under the crosshair shows the budget while it is below full.
- Cheat mode: Right stick click (R3, free in the world) toggles cheat movement in the tech demo and under `--dev`; a HUD tag "CHEAT" shows while on. In cheat mode walk, sprint, fly and fly sprint speeds multiply by `cheat_speed_factor`, the jump height by `cheat_jump_factor`, the jet thrust by `cheat_jet_factor`.
- Fly: the double-tap Jump toggle of developer mode is enabled in the tech demo too (`Field_Player_Input.developer` set for the demo); no new binding.

## Change

- `player_field.odin`: `Field_Player.jet_budget`, the jet branch in `walk_field_player` (airborne, Jump held, budget left: velocity += up times acceleration times the tick, capped at `jet_speed_limit`), the refill on `on_ground`; `cheat_movement` on `Field_Player`, read by `field_walk_speed`, `fly_field_player` and the jump; `Field_Player_Button.Toggle_Cheat`; `field_tick_input` maps the new action `Toggle_Cheat_Movement` (R3 in `data/bindings.sjson`, world layer) to it.
- `data/game.sjson` `field_player`: `jetpack_acceleration_millimetres_per_second_squared` (20000), `jetpack_budget_ticks` (90), `jetpack_refill_ticks_per_tick` (2), `jet_speed_limit_millimetres_per_second` (9000), `cheat_speed_factor` (4), `cheat_jump_factor` (3), `cheat_jet_factor` (3).
- HUD: the jet bar and the cheat tag in `ui_hud.odin` (the field's HUD).
- Docs: `doc/input.md` (the field controls), `doc/content.md` (the keys), the log.

## Verify

- The checks and the suite.
- Tests in `player_field_test.odin`: a jump then Jump held climbs higher than the jump alone and stops when the budget is spent; the budget refills on the ground; cheat mode's walk covers 4 times the distance in 60 ticks and the jump reaches 3 times the height; the touch overlay's jump tap still jumps; determinism: two players stepped alike hash alike.
