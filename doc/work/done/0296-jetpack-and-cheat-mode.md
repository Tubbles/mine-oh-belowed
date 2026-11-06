# 0296: Jetpack and cheat mode

Status: landed (2026-11-05, de05622)

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

## Specification (design, 2026-11-05)

Designed against 0291's item (not landed): the demo flag is `Field_Content.tech_demo` (`Simulation_Content.field`, reached from the frame loop as `state.session.field_content`); if 0291 lands it under another name, follow 0291. Units throughout: position units (1/4096 m), velocity units (1/65536 of a position unit per tick), ticks; no float in the simulation.

### The jet (`src/player_field.odin`)

- `Field_Player` gains, after `jump_tap_ticks`: `jet_budget_ticks: u16` (ticks of thrust left), `jetting: bool` (the jet is engaged: Jump has been held since it caught, cleared when Jump is released or the player stands), `cheat_movement: bool`. The save reads fields by name (`save_binary.odin`), so a save from before 0296 loads 0, false, false: an old player refills on its first ground ticks. Both the hash (`write_simulation_state` writes the players by value) and the prediction (`predict_field_player_motion` copies the player) carry them with no further change.
- `Field_Player_Tuning` gains: `jet_acceleration: i64` (velocity units per tick), `jet_speed_limit: i64` (velocity units), `jet_budget_ticks: u16`, `jet_refill_ticks_per_tick: u16`, `cheat_speed_factor: i64`, `cheat_jump_speed: i64` (velocity units), `cheat_jet_factor: i64`.
- `acceleration_to_velocity_step :: proc(millimetres_per_second_squared, tick_rate: int) -> i64`, beside `gravity_to_velocity_step`: `i64(mm) * POSITION_UNITS_PER_METRE * VELOCITY_FRACTION_ONE / (MILLIMETRES_PER_METRE * i64(tick_rate) * i64(tick_rate))`. With the shipped 20000 mm/s² at 60 Hz: 1491308 velocity units a tick, about twice the home planet's gravity step (731476 at 981 cm/s²).
- `make_field_player_tuning` fills them: `jet_acceleration = acceleration_to_velocity_step(config.jetpack_acceleration_millimetres_per_second_squared, tick_rate)`, `jet_speed_limit = speed_to_velocity(config.jet_speed_limit_millimetres_per_second, tick_rate)`, `jet_budget_ticks = u16(config.jetpack_budget_ticks)`, `jet_refill_ticks_per_tick = u16(config.jetpack_refill_ticks_per_tick)`, `cheat_speed_factor = i64(config.cheat_speed_factor)`, `cheat_jump_speed = jump_speed_for_height(millimetres_to_position_units(config.jump_height_millimetres * config.cheat_jump_factor), gravity)` (the root is not linear, so the cheat jump is its own launch speed), `cheat_jet_factor = i64(config.cheat_jet_factor)`.
- `field_jet_thrust :: proc(player: ^Field_Player, tuning: Field_Player_Tuning, input: Field_Player_Input) -> (thrust, limit: i64, jetting: bool)`, called in `walk_field_player` in the two non-walkable branches (steep ground and the air), before gravity: (1) `.Jump not_in input.held`: `player.jetting = false`, return 0, 0, false. (2) `!player.jetting`: it catches when `.Jump in input.just_pressed` (pressed again in the air) or `fixed_dot(player.velocity, player.up) <= 0` (at or past the apex; a slide counts); else return 0, 0, false. (3) `player.jet_budget_ticks == 0`: return 0, 0, false (jetting stays set). (4) `player.jet_budget_ticks -= 1`; `thrust = tuning.jet_acceleration`, `limit = tuning.jet_speed_limit`, both times `tuning.cheat_jet_factor` when `player.cheat_movement`; return thrust, limit, true. A held Jump from the ground launches the jump on the ground tick (unchanged); the next tick is airborne with the velocity along the up positive and no press, so nothing is spent until the apex.
- `limit_field_up_speed :: proc(velocity, up: [3]i64, limit: i64) -> [3]i64`: `along := fixed_dot(velocity, up)`; `along > limit` returns `velocity - fixed_scale(up, along - limit)`, else velocity. The cap holds the up component only, so the slide's or the fall's tangent part is left to `limit_speed`.
- `walk_field_player`, the air case: `thrust, limit, jetting := field_jet_thrust(player, tuning, input)`; `player.velocity = limit_speed(player.velocity - fixed_scale(player.up, tuning.gravity) + fixed_scale(player.up, thrust), tuning.fall_speed_limit)`; `if jetting { player.velocity = limit_field_up_speed(player.velocity, player.up, limit) }`. The steep case (`case ground.on`): the same three lines after `steep_walk_velocity`, with `tuning.slide_speed` in place of the fall limit (the existing line), so Jump held on a steep face lifts off at up to the slide speed and the air case takes over next tick (`probe_field_ground` reads a velocity away from the ground as air). The walkable case (`held_on_ground`): first `refill_field_jet(player, tuning)`, then the jump as now with `field_jump_speed(tuning, player.cheat_movement)` in place of `tuning.jump_speed`.
- `refill_field_jet :: proc(player: ^Field_Player, tuning: Field_Player_Tuning)`: `player.jetting = false`; `player.jet_budget_ticks = min(player.jet_budget_ticks + tuning.jet_refill_ticks_per_tick, tuning.jet_budget_ticks)` (u16 arithmetic; the bounds keep the sum under 7200). Walkable ground only: steep ground neither refills nor spends unless Jump is held, so a player sliding into a pit's steep wall keeps what is left to jet out with.
- Fly mode (`fly_field_player`) and the chair (`tick_seated_field_player`) never read the jet; the budget stays as it was. Under water the jet is the walk's (the field player does not swim, doc/architecture.md), so the same rule applies.
- Shipped numbers, for the main agent to weigh (not a test): at 60 Hz the jet's net lift is 759832 velocity units a tick, reaching the 9 m/s cap in 53 ticks; a full 90 tick budget from a standing jump's apex climbs about 9.5 m and coasts about 4 m more, some 13 m above the jump's 1.1 m. For "climb out of a pit or hop to a terrace" a budget of 45 to 60 ticks would do; left at the item's 90.

### Cheat movement

- `toggle_field_cheat_movement :: proc(player: ^Field_Player, input: Field_Player_Input)`: `if .Toggle_Cheat in input.just_pressed && input.developer { player.cheat_movement = !player.cheat_movement }`; called in `tick_field_player` right after `apply_field_player_toggles` (standing only; the chair's frame is cut to the look). One gate for the toggle and the fly double tap: `input.developer`, which rides in the input record (`Record_Input.developer`), so every machine toggles alike.
- `field_walk_speed :: proc(tuning: Field_Player_Tuning, held: Field_Player_Buttons, crouching, cheat_movement: bool) -> i64`: the walk and the sprint speeds times `tuning.cheat_speed_factor` when `cheat_movement`; the sneak speed as it is (a crouch under a ceiling stays slow). The one caller in `walk_field_player` passes `player.cheat_movement`; `test_the_sneak_speed_follows_the_crouch` passes false.
- `field_fly_speed :: proc(tuning: Field_Player_Tuning, held: Field_Player_Buttons, cheat_movement: bool) -> i64`: `.Sprint in held ? fly_sprint_speed : fly_speed`, times the factor when cheating; `fly_field_player` reads it in place of its first line.
- `field_jump_speed :: proc(tuning: Field_Player_Tuning, cheat_movement: bool) -> i64`: `cheat_movement ? tuning.cheat_jump_speed : tuning.jump_speed`.
- The jet thrust and its cap times `cheat_jet_factor` (above). Bounds: every cheat product stays under the controller's 8 m a tick (`field_player_speed_problem`, below), so the i64 products hold as before.
- `Field_Player_Button.Toggle_Cheat` after `Toggle_Camera_Mode` (comment: R3's cheat movement, 0296, honoured with `developer`). `field_tick_input` (`src/simulation_field.odin`) adds `{.Toggle_Cheat_Movement, .Toggle_Cheat}` to its table.

### The action, the binding and the gate

- `Action.Toggle_Cheat_Movement` (`src/input_actions.odin`) after `Toggle_No_Clip`, comment: "R3 in the world (0296): cheat movement on the field, honoured in the tech demo and under --dev; in menus the click is Menu_Drop." Added to `WORLD_ACTIONS` after `.Toggle_No_Clip`. The enum goes from 60 to 61 members, so `Action_Set` stays 64 bits and the record and save layouts do not change.
- `data/bindings.sjson`, after the Sprint LEFT_STICK line: `// R3 toggles cheat movement on the field in the tech demo and under --dev (0296); in menus the click is Menu_Drop.` then `{action = "Toggle_Cheat_Movement" device = "gamepad" control = "RIGHT_STICK" context = "world"}`. The reference tables of `src/bindings_test.odin` gain `{.RIGHT_THUMB, .Toggle_Cheat_Movement}` (raylib) and `{.RIGHT_STICK, .Toggle_Cheat_Movement}` (SDL3). No keyboard binding.
- The gate: `src/loop.odin` `viewport_world_input` passes `developer_mode_on(state) || field_tech_demo_on(state)` to `world_input`; `field_tech_demo_on :: proc(state: ^Frame_State) -> bool { return state.session != nil && state.session.field_content.tech_demo }` beside `viewport_world_input`. Nothing else reads it: the Developer pause entry, F8 and the data watch keep `developer_mode_on`. `--dev` sets `developer_mode` in `main.odin` (`Command_Line.developer_mode` into `content.developer_mode`), the demo sets `tech_demo` on its field content (0291). The planet preview already sets `frame.developer = true`, so the cheat works there too.

### HUD (`src/hud.odin`)

- Constants: `HUD_JET_BAR_WIDTH :: HUD_MINING_BAR_WIDTH`, `HUD_JET_BAR_HEIGHT :: 4.0`.
- `jet_bar_fraction :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> (fraction: f32, shown: bool)`: shown when `tuning.jet_budget_ticks > 0 && player.jet_budget_ticks < tuning.jet_budget_ticks`; `fraction = f32(player.jet_budget_ticks) / f32(tuning.jet_budget_ticks)` (presentation only).
- `draw_jet_bar :: proc(state: ^Ui_State, player: Field_Player, tuning: Field_Player_Tuning)`: nothing unless shown; `centre := state.screen_units / 2`; `ui_progress_bar(state, {centre.x - HUD_JET_BAR_WIDTH / 2, centre.y + CROSSHAIR_SIZE + (UI_GAP - HUD_JET_BAR_HEIGHT) / 2, HUD_JET_BAR_WIDTH, HUD_JET_BAR_HEIGHT}, fraction)`: under the crosshair, inside the 8 unit gap above the first target line (`hud_target_line_top` at line 0), so the lines never move.
- `draw_cheat_tag :: proc(state: ^Ui_State, player: Field_Player)`: when `player.cheat_movement`, `draw_text(state, {centre.x + CROSSHAIR_SIZE + UI_GAP, centre.y - UI_ROW_HEIGHT / 2, 4 * UI_ROW_HEIGHT, UI_ROW_HEIGHT}, text("hud_cheat_movement"), UI_BODY_TEXT_SIZE, .Left, UI_ACCENT_COLOR)`: right of the crosshair on its line, clear of the mining bar above and the lines below.
- `draw_hud`: after the crosshair or ring block and before the screens return, `if hud.field_session { field := hud_field_player(screen_context, hud); draw_jet_bar(state, field, screen_context.content.field.tuning); draw_cheat_tag(state, field) }`, so the predicted body's budget shows and touch sees the bar too.
- String key `hud_cheat_movement = "CHEAT"` in `data/strings/en.sjson` (`test_shipped_strings_cover_the_ui` scans `hud.odin`).

### Data (`data/game.sjson` `field_player`, `src/data_load.odin`)

- `Field_Player_Config` gains `jetpack_acceleration_millimetres_per_second_squared`, `jetpack_budget_ticks`, `jetpack_refill_ticks_per_tick`, `jet_speed_limit_millimetres_per_second`, `cheat_speed_factor`, `cheat_jump_factor`, `cheat_jet_factor` (all `int`); shipped 20000, 90, 2, 9000, 4, 3, 3, appended after `fly_sprint_speed_millimetres_per_second` with one comment line. `test_field_player_config` carries the same values.
- Constants beside `MAXIMUM_FIELD_PLAYER_SPEED_MILLIMETRES_PER_SECOND`: `MAXIMUM_FIELD_JET_ACCELERATION_MILLIMETRES_PER_SECOND_SQUARED :: 1000000`, `MAXIMUM_FIELD_JET_BUDGET_TICKS :: 3600`, `MAXIMUM_FIELD_CHEAT_FACTOR :: 8`.
- `field_player_problem` bounds: acceleration 1 to the constant; budget 1 to 3600; refill 1 to `jetpack_budget_ticks`; `jet_speed_limit_millimetres_per_second` 1 to `speed`; the three factors 1 to 8; and `{"jump_height_millimetres times cheat_jump_factor", jump_height * cheat_jump_factor, 1, length}`.
- `field_player_speed_problem` entries added: `jet_speed_limit_millimetres_per_second`; `walk_speed_millimetres_per_second times cheat_speed_factor` (value walk * factor), the same for sprint, fly and fly sprint; `jet_speed_limit_millimetres_per_second times cheat_jet_factor`. One more line: `jetpack_acceleration_millimetres_per_second_squared` above `MAXIMUM_FIELD_PLAYER_MILLIMETRES_PER_TICK * tick_rate * tick_rate` is refused with the same wording (an acceleration of more than 8 m a tick a tick).

### Tests

`src/player_field_test.odin`, flat terrain at 1000 mm unless said (the site has 64 m of loaded air above it and 32 m of loaded ground along -x):
- `test_the_jet_carries_the_jump_higher_until_the_budget_is_spent`: stand 20 ticks; Jump held; for up to 300 ticks with `{held = {.Jump}}` track the apex and stop when `jet_budget_ticks == 0`; assert the budget was full after the first 10 held ticks (nothing spent before the apex), apex >= 3 * `jump_height_millimetres` (the shipped numbers give about 13 m), then tick with `{}` up to 600 ticks until `on_ground`; assert it lands, the budget is 0 on that tick, 2 after one more tick, full (90) after 45 ticks on the ground and 88 after 44.
- `test_a_second_jump_press_in_the_air_jets_at_once`: launch with Jump held one tick, three ticks of `{}`, then one tick `{held = {.Jump}, just_pressed = {.Jump}}` while rising: budget 89; five more held ticks: 84. The touch overlay's jump tap is exactly this one tick press (`test_a_tap_in_the_jump_zone_jumps_without_an_aim` in `touch_overlay_test.odin` still passes untouched): on the ground it jumps the 1.1 m as `test_the_jump_rises_its_height` asserts.
- `test_cheat_movement_multiplies_the_walk_the_jump_and_the_fly`: `{just_pressed = {.Toggle_Cheat}}` without `developer` leaves `cheat_movement` false; with it true. Heading `{-UNIT_VECTOR_ONE, 0, 0}`: a plain player's 30 tick walk and a cheating player's 30 tick walk, the cheat's x displacement within `tenth_sample(1000)` of 4 times the plain one. The cheat's jump (Jump held one tick, apex over 90 ticks) within a quarter of a sample of 3300 mm (the discrete launch's half tick of velocity grows with the speed). Fly: `{just_pressed = {.Toggle_Fly_Mode}}`, then `{held = {.Jump}}` for 60 ticks rises 48 m within `POSITION_UNITS_PER_METRE / 16` (the plain fly test's 12 m times 4), on the flat site.
- `test_two_field_players_stepped_alike_stay_alike`: two players from the same start through the same script (20 ticks stand, the cheat toggle with `developer`, 100 ticks Jump held, 100 ticks `{}`); after every tick positions, velocities and budgets equal; at the end the `write_value_of` bytes equal. `test_the_field_player_source_stays_integer`: `#load("player_field.odin", string)` contains no `f32`, `f64` or `math.` (as `test_static_runtime_imports_stay_out_of_windows` reads sources).
- `test_the_field_player_saves_its_jet_and_cheat`: `jet_budget_ticks = 7`, `jetting = true`, `cheat_movement = true` round trip; `Field_Player_Before_Crouch{yaw = 7}` loads 0, false, false.
- `test_the_field_player_config_is_bounded` extended: budget 0 refused, refill 91 over the budget of 90 refused, `cheat_speed_factor` 0 and 9 refused; `field_player_speed_problem` with `cheat_speed_factor = 8` passes at 60 Hz (fly sprint times 8 is 4800 mm a tick) and is refused at 30 Hz (9600) while the plain fly sprint passes there.
- `src/hud_test.odin` `test_the_jet_bar_and_cheat_tag_follow_the_field_player`: `jet_bar_fraction` not shown at a full budget, 0.5 at 45 of 90; with `use_shipped_strings` and `ui_begin(&state, {}, {1920, 1080}, 0.5, 1, 1)`: `draw_cheat_tag` with the flag on puts "CHEAT" in the draw list (`draw_list_has_text`), off adds nothing; `draw_jet_bar` at 45 of 90 adds commands, at 90 none.
- `src/input_actions_test.odin`: `.Toggle_Cheat_Movement in WORLD_ACTIONS` beside the `Open_Aimed` assertion; `src/simulation_field_test.odin`: `field_tick_input` of a frame with `.Toggle_Cheat_Movement` just pressed yields `.Toggle_Cheat` in `just_pressed`.

### Docs

- `doc/input.md`: the Gamepad table's Right stick row ("Look. Click: cheat movement on and off on the field in the tech demo and under `--dev` (0296)"); a new section "## The jetpack and cheat movement" after "Fly mode and no clip": Jump held past the apex or pressed again in the air thrusts along the up on an integer budget of ticks that refills on walkable ground, the bar under the crosshair, the touch jump tap's one tick press, R3's toggle and what it multiplies (walk, sprint, fly, fly sprint by `cheat_speed_factor`, the jump height by `cheat_jump_factor`, the jet by `cheat_jet_factor`; sneak, mining and the animation cadences unchanged), the "CHEAT" tag, the gate (`field_tech_demo_on`, `developer_mode_on`) and that the demo's `developer` frame makes the Jump double tap fly there too; the Fly mode section gets that last sentence's cross reference.
- `doc/architecture.md`, The player on the field: one bullet on the jet's mechanics (the budget, the latch, the thrust before gravity, the up cap, the refill on walkable ground only, fly and the chair untouched) and the cheat flag as player state in the hash.
- `doc/content.md`, the `field_player` bullet: the seven keys with bounds and shipped values and the cheat products' tick check.
- `doc/hud.md`: the Layout table's Centre row and a Targeting bullet (the jet bar in the gap under the crosshair while the budget is below full, the CHEAT tag right of the crosshair).
- `doc/code_map.md`: `player_field.odin` (the jet and the cheat, 0296) and `hud.odin` (the jet bar) lines; `tools/code_graph.py --check` after.
- `doc/touch_overlay.md`: unchanged.

### Hand-back check

- A number parsed from text is range checked: every new key is a `Config_Bound` and the cheat products go through `field_player_speed_problem` (above). A rate scaled per tick accumulates credits: the budget is whole ticks and the refill whole ticks a tick, nothing is truncated.
- A changed save layout loads an old save: new fields by name, zero and false (the save test above); no log line, since nothing is remapped.
- A list that grows without bound is capped where it draws: the bar is one rectangle, the tag one fitted line; nothing grows.
- Tests touch no state directory: the field tests build their world in memory, the HUD test draws into a `Ui_State`.

### Open questions, answered

- Determinism: integer only; `field_jet_thrust`, the cap and the refill use i64 and u16, and the source test keeps floats out of `player_field.odin`.
- Under water: the same as in the air (no buoyancy exists); when a later item adds swimming it decides. In the chair: no jet, no toggle, the budget kept.
- Cheat and fall damage: there is none (0167 leaves it to survival); nothing to multiply or exempt.
- Where the refill counts: walkable ground only, not a slide, so the budget is a known quantity when the player lifts off a steep face.
- The cheat and the cadences: `DESIGN.md` forbids cadences speeding up with cheat speed; the field's walk cadence (`cues.odin`) divides by `cheat_speed_factor(Simulation_State.cheat_speed)`, which this item does not set, so a cheating walk's footsteps would quicken fourfold. Question to the main agent: fold `cheat_movement` into the cue's divisor (the cue memory reads the player; `Cue_Counters.cheat_speed` could be `cheat_speed || player.field.cheat_movement`, divided by the field factor), or accept it for the demo. The design leaves the cues untouched.
- The double tap and the second press: in the demo `developer` is on, so a second Jump press within `JUMP_DOUBLE_TAP_TICKS` (18 ticks, 300 ms) of the launch toggles fly, as the item asks, and a press after the window jets. The item's shipped jump takes about 28 ticks to its apex, so the two do not collide in practice; documented in input.md. If the main agent would rather the demo never fly by double tap, the frame's `developer` stays and `update_field_jump_double_tap` would need a second flag; not done here.

### Main agent's decisions (approval, 2026-11-05)

- The shipped budget stays at 90 ticks: a planet with pits and terraces wants the climb; the bar shows what is left.
- The cadences: fold `cheat_movement` into the cue's divisor (`Cue_Counters.cheat_speed` becomes `cheat_speed || player.field.cheat_movement`, divided by `cheat_speed_factor`), so the footsteps keep their cadence per metre as `DESIGN.md` demands; test it beside the existing cue test.
- The double tap: as designed (a second press within the window flies under `developer`, a later press jets).
- Approved.
