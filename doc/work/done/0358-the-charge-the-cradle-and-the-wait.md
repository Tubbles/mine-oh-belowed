# 0358: The charge, the cradle and the wait

Status: landed (2026-11-11, 86b1ff5)

The player is a machine (user, 2026-11-11). Of 0353's proposal for what a machine keeps of the human's survival design the user said: "shared sleep stays, but not as sleep, just like a \"wait\" feature. charging cradle is fine. pod stays as is for the moment". Then: "Yes drop food and oxygen as needs".

## Goal

The bed is a charging cradle, the shared sleep is a wait, and the player's needs are a machine's.

## Controls

No new binding. Interact on the cradle starts and stops the wait, exactly as Interact on the pod's chair sits and stands, the glyph bar saying Wait and Stop waiting (main agent, 2026-11-11, at the design's approval: the bed had no use to follow).

## Change

- The design found that the survival needs were never built: no health, hunger, oxygen or battery stat, no food, no canister, no HUD bar, no sleep and no usable bed. What exists and changes is the pod's oxygen generator fixture, the sealed room's oxygen supply, the bed's geometry and a few strings.
- The oxygen generator becomes the charge controller, the bed the charging cradle on the pod's record, and the wait is built: when every connected player waits in a cradle, eight hours pass.
- The charge itself is written into `DESIGN.md` and `PLAN.md` for the survival milestone and not simulated here.
- Docs: `DESIGN.md` (The player and what of the human's survival becomes history), `PLAN.md`, `doc/content.md`, the strings.

## Verify

- The checks and the suite.
- Captures of the cradle and the wait's screen, sent to the user.

## Specification (design, 2026-11-11)

### What the code holds and what each becomes

No survival stat exists: no health, hunger, oxygen or battery value, no food or canister item, no HUD bar, no sleep, no bed entity, and no quest, kit, technology, recipe or fluid names any of them (`git log -S hunger` finds only the tooltip; survival plays as peaceful, `World_Settings.mode`). The bed is geometry of the pod's model only: `bed()` in `tools/models/machines/pod.py`, strapped on the lean wall at 315 degrees over the airlock housing, its collision a cone shell over 303 to 327 degrees.

| What | Where | Becomes |
| --- | --- | --- |
| The oxygen generator fixture | record `oxygen_generator`; `Machine_Kind.Oxygen_Generator` and its checks (`machine.odin`); `entity.odin` 330, 688; `ui_machine.odin` (row "Oxygen: unlimited"); `render_entities.odin` (lit while it supplies a room); `render_fluids.odin` 64 | The charge controller: same cell, model and panel; record `charge_controller` with `former_ids = ["oxygen_generator"]`, kind `charge_controller`, row "Cradle supply: unlimited", always lit |
| The sealed room's supply | `Oxygen_Supply`, `Sealed_Room.supplier` and `.oxygen`, `room_supplier`, `oxygen_generator_supplies_a_room` (`entity_pod.odin`) | Removed. The room's cells stay, derived, read by the F3 line only |
| The F3 line | `sealed_room_line`, `World_Facts.sealed_room_oxygen` (`diagnostics.odin`), `loop.odin` 1229 | "sealed room: inside the pod" or "sealed room: outside" |
| The bed | `pod.py` | The charging cradle: a `cradle` key on the pod's record beside `seat`, aimed through the pod's collision; model unchanged |
| Strings | `machine_oxygen_generator`, `describe_machine_oxygen_generator`, `oxygen_generator_supply_unlimited`, `new_world_mode_tooltip`, `describe_machine_pod_hatch` | Strings below |
| Oxygen as a gas, food, crops, the suit's tanks, breathable rooms | `DESIGN.md`, `PLAN.md` only (no fluid record) | Oxygen stays design text as an industrial gas; the rest becomes history (Docs) |

### Data

- `data/machines.sjson`: the record `oxygen_generator` becomes `id = "charge_controller"`, `name_key = "machine_charge_controller"`, `description_key = "describe_machine_charge_controller"`, `former_ids = ["oxygen_generator"]`, `model = "oxygen_generator"` (comment: the oxygen generator's model until a sealed lab remakes it, 0358), kind `charge_controller`, the rest as now. The pod's fifth fixture names `charge_controller`, same cell and rotation. The header's kind lists (lines 57, 70) and the oxygen generators' paragraph (82 to 84) name the charge controller: no slots, power or ports.
- The pod gains after `seat`: `cradle = {cells = {from = {x = 7, y = 3, z = 7}, to = {x = 9, y = 5, z = 9}}, eye = [1.5, 5.1, 1.5], facing = "-z"}`, commented: the bed of `pod.py`; rows 3 to 5 so the airlock drum's top and the cabinets under the bed (row 2) are not the cradle; the eye 0.4 m off the pillow facing across the cabin to the charge controller. Computed from `pod.py`'s `wall(315, 2.6)`: the bed's collision spans x 7 to 9, y 2 to 5, z 7 to 9; the box leaves its foot in row 2 out and takes in a 12 cm strip of the inner shutter's tower (x 7, y 3 to 4, z 7), accepted. The box overlaps no open cells box, fixture or the seat.
- No `game.sjson` key: `WAIT_HOURS :: 8` (DESIGN.md's rule; the Mission Control line says eight) and `WAIT_SETTLE_SECONDS :: 3` are constants in `simulation_field.odin`.

### Code

All integer; the wait writes `day_offset_ticks` only.

- `machine.odin`: `Machine_Kind.Oxygen_Generator` becomes `.Charge_Controller` (`"charge_controller"`), with its validation messages ("charge controller %q ..."), `world_kinds`, the fixture kinds and their problem string ("... crafting_bench or charge_controller"). `Machine_Definition.cradle: Maybe(Pod_Seat_Definition)` and `Machine.cradle: Pod_Seat` beside `seat`.
  - `validate_pod_place :: proc(definitions: []Machine_Definition, index: int, place: Pod_Seat_Definition, word: string) -> (cells: Cell_Box, problem: string)`: the checks `validate_pod_seat` makes today but the door rule, `word` ("seat" or "cradle") in the messages, so the seat's read as now ("machine %q has a %s, which only a pod may", "pod %q %s cells overlap fixture %d", ...).
  - `validate_pod_seat`: `validate_pod_place` then the across-the-door rule. `validate_pod_cradle :: proc(definitions: []Machine_Definition, index: int) -> string`: `validate_pod_place`, then "pod %q cradle cells overlap the seat"; any facing word. Called after `validate_pod_seat` (line 859).
  - `resolve_pod_place :: proc(place: Maybe(Pod_Seat_Definition)) -> Pod_Seat` replaces `resolve_pod_seat`; it resolves `seat` and `cradle`.
- `input_actions.odin`: `Input_Frame.connected: bool`: set only by `input_frame_of`, a record carried the player's input this tick, so the player is connected; false in the UI's frames, the socket's `tick` and the planet preview. `lockstep.odin`: `input_frame_of` sets it; `lockstep_state_hash`'s comment: the wait writes `day_offset_ticks` from the players' seats, which the hash covers, and no tick reads it.
- `player.odin`: `Player.connected: bool` tagged `save:"-"`: `Input_Frame.connected` of the player's last field tick; the same on every machine, never saved or hashed. `Player_Event.Wait_Finished`. `field_chair_takes_interact` renamed `field_pod_seat_takes_interact`, true for a standing body aimed at the chair or the cradle.
- `player_field.odin`: `Field_Seat.Cradled` after `Seated`; `Field_Player.cradled_tick: u64` after `seat` (the tick the body entered the cradle); `field_seat_in_chair :: proc(seat: Field_Seat) -> bool` (Strapped or Seated).
- `entity_pod.odin`:
  - `pod_box_contains_cell :: proc(pod: Entity_Common, machine: Machine, box: Cell_Box, cell: World_Coordinate) -> bool`, `pod_seat_contains_cell`'s body with the box a parameter; the seat's calls it.
  - `pod_cradle_eye :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> World_Position`, `pod_cradle_facing :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> [3]i64`, `field_aimed_cradle :: proc(entities: ^Entities, machines: Machine_Registry, target: Frame_Raycast_Hit) -> bool`: the seat's three with `machine.cradle`.
  - `place_body_at_eye :: proc(eye: World_Position, tuning: Field_Player_Tuning, body: ^Field_Player) -> bool`: `place_body_in_seat`'s body, which calls it.
  - `cradle_field_player :: proc(entities: ^Entities, machines: Machine_Registry, tuning: Field_Player_Tuning, body: ^Field_Player, tick: u64) -> bool`: as `seat_field_player` at the first pod's cradle, then `seat = .Cradled`, `cradled_tick = tick`; false, nothing changed, without one. `stand_field_player_from_seat` stands from the cradle too (comment).
  - `field_player_capsules` leaves Cradled bodies out: the cradled eye's capsule comes 5 cm from the inner hatch's cells, inside the airlock's 150 mm. The airlock is its only caller.
  - The sealed room: `Oxygen_Supply`, `supplier`, `oxygen`, `room_supplier`, `oxygen_generator_supplies_a_room` go; `rebuild_sealed_rooms` appends `{pod, frame, cells}`; `take_old_pod_fixtures` names `.Charge_Controller`; comments.
- `entity.odin` 330, 688, `render_fluids.odin` 64: `.Charge_Controller`. `render_entities.odin`: `foundation_model_working` returns true for it. `ui_machine.odin`: `.Charge_Controller` in both area switches, `charge_controller_area_size` and `charge_controller_panel_region` (the old procs renamed) drawing `charge_controller_supply_unlimited`.
- `diagnostics.odin`: `World_Facts.sealed_room_oxygen` goes; `sealed_room_line :: proc(inside: bool) -> string`. `loop.odin` 1229 goes. `world_chunk.odin` 45: "until the charge (M15)".
- `simulation_field.odin`:
  - `interact_on_field_chair` renamed `interact_on_field_pod_seat`: Strapped, Seated or Cradled stand whatever the aim; standing, aimed at the chair it sits as now, aimed at the cradle `cradle_field_player(..., state.tick)` and sneaking clears; never while falling. `seated_field_frame` gives Cradled `STRAPPED_FIELD_ACTIONS` already (comment only).
  - `tick_field_session_players`: before `arrival_input`, `state.players[index].connected = index < len(inputs) && inputs[index].connected`; after `tick_pod_airlocks`, in the same not-falling branch, `finish_field_wait(state, content)`.
  - `field_wait_counts :: proc(players: []Player) -> (waiting, units: int)`: the connected players and those of them Cradled.
  - `field_wait_due :: proc(players: []Player, tick, settle_ticks: u64) -> bool`: units above 0, all waiting, every one with `cradled_tick + settle_ticks <= tick`.
  - `waited_day_offset :: proc(offset, day_length_ticks: u64) -> u64`: `(offset + day_length_ticks * WAIT_HOURS / WEATHER_HOURS_PER_DAY) % day_length_ticks` (the day's 24 hours of `weather.odin`), the offset as given for a day length of 0.
  - `finish_field_wait :: proc(state: ^Simulation_State, content: Simulation_Content)`: when due (settle `WAIT_SETTLE_SECONDS * tick_rate`), the offset moves and every connected Cradled player stands (`stand_field_player_from_seat`) with a `Wait_Finished` event. A cradled entry not connected stays.
- `simulation_arrival.odin` 220: the hit re-seats only `field_seat_in_chair` bodies.
- `developer.odin`: `set_field_seat_for_developer` takes Cradled through `cradle_field_player`, refused "there is no cradle". `command_field.odin`: `.Cradled = "cradled"`; `seat wait`; usage "seat <stand|sit|wait>".
- `loop_field_session.odin`: `first_seated_player` counts `field_seat_in_chair` bodies; `field_player_body_pose` is Hidden for Cradled (no lying pose; the bed stands for it); `field_view_camera_mode` is first person for Strapped and Cradled.
- `hud.odin`: `Hud_Context.wait_waiting, wait_units: int`. `field_chair_hint_key` renamed `field_pod_seat_hint_key`: Cradled `hint_stop_waiting`; standing aimed at the cradle `hint_wait`. `hud_waiting_text :: proc(waiting, units: int) -> string`: `hud_waiting` for units up to 1, else `hud_waiting_count` with `{waiting}` and `{units}` filled. `draw_field_wait :: proc(state: ^Ui_State, hud: Hud_Context)`: `ui_backdrop`, then the text fitted and centred in `{UI_PADDING, screen_units.y / 2 - CROSSHAIR_SIZE - UI_GAP - UI_ROW_HEIGHT, screen_units.x - 2 * UI_PADDING, UI_ROW_HEIGHT}`; `draw_hud` calls it first in a field session while the HUD's body is Cradled.
- `loop.odin`: `make_hud_context` fills the counts from `field_wait_counts`; `show_simulation_events`: `Wait_Finished` sends `mc_wait_finished` through `ui_mission_control_line`, as the touchdown does.
- `tools/models/records_test.py` 77 and `tools/model_lab/model_lab_test.py` 106 name `charge_controller`. `pod.py`: the module docstring's bed line (315 degrees, the charging cradle since 0358) and pocket line only, so the OBJ does not change.

### Save

- A save naming `oxygen_generator` loads it as `charge_controller` through `former_ids`, with the existing one line "save: loaded under renamed ids: machines oxygen_generator as charge_controller". A plain removal would refuse every field save: a placed machine of a vanished id refuses the file (`settle_gone_machines`).
- `Field_Seat.Cradled` and `cradled_tick` read by name: older saves load as they were, no line. An older build reads Cradled as Standing.
- No item to drop: no oxygen or food canister was ever in the content.

### Strings

Removed: the three `oxygen_generator` keys. New or changed:

- `machine_charge_controller = "Charge controller"`
- `describe_machine_charge_controller = "Regulates the pod's panels and batteries into the charging cradle over the airlock."`
- `charge_controller_supply_unlimited = "Cradle supply: unlimited"`
- `hint_wait = "Wait"`, `hint_stop_waiting = "Stop waiting"`
- `hud_waiting = "Waiting in the cradle"`, `hud_waiting_count = "Waiting in the cradle: {waiting} of {units} units"`
- `mc_wait_finished = "Eight hours waited out in the cradle. The lease kept running."`
- `new_world_mode_tooltip = "Peaceful has no charge and no condition to watch. The other modes are kept with the world and play as peaceful for now"`
- `describe_machine_pod_hatch = "A hatch of the pod's airlock. It opens as a unit comes near and shuts behind it."`

### Tests

New:

- `test_the_pod_cradle_is_validated` (machine_test): the shipped cradle is present, cells (7, 3, 7) to (9, 5, 9), facing the model's -z; refused, each by its message: a cradle on a non pod, cells past the footprint, over open cells box 0, over fixture 0, over the seat, the eye outside its cells, the facing "up"; facing "+x" passes.
- `test_the_pod_cradle_eye_is_clear_of_the_bed` (entity_pod_test, as `test_the_pod_seat_eye_is_clear_of_the_chair`): with the pod's collision loaded no body within 100 mm of `pod_cradle_eye`; the facing a unit tangent.
- `test_a_cradled_player_holds_no_door_open` (entity_pod_test): `field_player_capsules` of a standing and a cradled player holds one capsule; `tick_pod_airlocks` with the cradled one alone leaves both hatches closed.
- `test_interact_on_the_cradle_waits_and_stops_waiting` (simulation_arrival_test, `// slow` as the chair's): arrival_ticks 0; aimed from the spawn at the model point [2.41, 4.14, 2.41] (the mattress, cell (8, 4, 8)) `field_aimed_cradle` and not `field_aimed_chair`; Interact: Cradled, the eye on `pod_cradle_eye`, `cradled_tick` the tick; 30 ticks of walk and Jump keep the position; Interact: Standing within 100 mm of the spawn. Its frames are not connected, so no wait runs.
- `test_every_unit_waiting_moves_the_day` (simulation_arrival_test, two players by `Add_Player_Command` as at line 477, frames `connected = true`): player 0 cradled at T, player 1 standing: after T + settle + 10 the offset is unchanged and 0 still Cradled; player 1 cradled at T2: nothing at T2 + settle - 1; at T2 + settle the offset is `waited_day_offset` of the old, both Standing at the spawn, one `Wait_Finished` each. A third entry standing and not connected changes nothing.
- `test_the_wait_counts_connected_units` and `test_the_waited_day_offset_moves_eight_hours` (simulation_field_test, pure): no player connected: 0 of 0, not due; one connected Cradled at 100 with settle 180: due at 280, not 279; a connected standing one blocks it; a standing one not connected does not; a cradled one not connected is not counted. `waited_day_offset(0, 72000) == 24000`, `(60000, 72000) == 12000`, `(5, 0) == 5`.
- `test_the_cradle_hints_wait_and_stop_waiting` (hud_test): aimed at a cradle cell `hint_wait`; Cradled `hint_stop_waiting`, kept on the bar; falling ""; `hud_waiting_text(1, 1)` and `(1, 3)` give the two strings filled.
- `test_a_cradled_player_is_hidden_and_sees_in_first_person` (render_field_camera_test): third person mode cradled still sees first person; a cradled body is Hidden, `first_seated_player` skips it.
- `test_the_seat_command_waits_in_the_cradle` (command_test, slow): `seat wait` answers "seat cradled", `query player` says "seat cradled", the eye on `pod_cradle_eye`; `seat stand`; refused while falling.
- `test_input_frame_of_marks_the_player_connected` (lockstep_test).
- `test_a_cradled_player_round_trips` (player_field_test, as `test_the_field_player_saves_its_seat`): Cradled and `cradled_tick` kept, `Player.connected` not written.
- `test_an_oxygen_generator_loads_as_the_charge_controller` (save_remap_test, as `test_an_old_foundation_loads_as_the_stone_brick_foundation`): a world saved by content whose `charge_controller` is `oxygen_generator` without former ids, one placed, loads one `charge_controller`; the remap's line is the one above.

Changed: `test_the_chair_takes_interact_like_a_switch` (the rename, Cradled and a standing body aimed at the cradle take Interact); `test_the_chair_hints_unbuckle_stand_and_sit` and the other callers of the renamed procs; `test_the_seat_command_sits_and_stands` (the usage); in entity_pod_test `TEST_GENERATOR` becomes `TEST_CHARGE_CONTROLLER`, the kind check, the sealed room tests lose their oxygen and supplier asserts, `sealed_room_line` gives the two new lines, the "touches the sealed room" block goes, `test_the_pod_counts_as_working_for_its_model` (the controller works before and after the hatches open), `test_machine_lights_shine_while_their_model_works` (3 lights after both hatches open, not 2), line 756's id; `entity_test` 305, `machine_test` 432, 765, 780, `diagnostics_test` 162 to 163; comments in `benchmark_test` 123. A test comparing `input_frame_of`'s result with a literal frame sets `connected` in it.

### UI audit

`Ui_Audit_Case.wait_counts: [2]int` sets the HUD's counts. New case "hud field waiting" (field session, seat Cradled, counts 1 of 2): the backdrop, the longest line fitted at every size, and a check as the strapped case's that "Stop waiting" stays beside its glyph. No case showed the oxygen generator's panel, and the controller's is the same panel.

### Docs

- `DESIGN.md`: Pillars 6, "Survival adds the machine's charge and its condition and allows a breakdown"; The world, "cold and heat raise the charge's drain in survival"; The player: the fifth bullet becomes the charge (the user's words, peaceful has none, the cradle fills it and waiting in it is the shared wait, propellant stays a tank, then the proposals below marked "proposed by 0358 for M15"), the sixth says "A breakdown" and "respawn at the pod"; Building: the sealed room bullet goes; phase 1, "solar panels and batteries that last the night, a charging cradle" and "the charge is the clock"; phase 6 drops "The first sealed dome and the first crops."; phase 8, "the jet pack" for "the suit and the jet pack"; phase 9, "the charge as the clock"; Space: "goes out with the jet pack", "the nearest hatch", the outpost without its airlock, the dock's "rooms", the dangers sentence becomes "The danger of a station is an empty battery bank on the night side of its orbit", the terraforming paragraph drops the suit's oxygen sentence; Multiplayer, "one wait rule".
- `PLAN.md`: M15 is "Survival, the charge and the modes" in the table and the heading; its text: the modes, the charge (its drains, the cradle's fill, the pod's supply), the condition with the slow drain at zero and the quiet breakdown, the respawn action, keep inventory, the death pack, weather's drains on the charge, the repair kit for the unit and the machines, the first breakdowns; "The charging cradle, the charge controller and the shared wait exist since 0358, nothing charged yet; M15 adds the charge and its fill, and the bench as the place crafting happens in survival"; Verify, "from the pod through its first night on the charge, with one breakdown and the pack recovered". M17, "The dock's rooms". M19's Verify drops "with the suit's oxygen stat gone".
- `SUGGESTIONS.md`, What The Last Caretaker's decisions leave open: the needs bullet names 0358's proposals as the user's to overturn, and the open question of a wait anywhere.
- `doc/content.md`, The pod: the fixture kinds and the shipped list, the old pod's fixtures, a `cradle` bullet after `seat` (keys, bounds, the shipped values and why); The pod's fixtures: the charge controller's bullet; Hatches: a cradled player is near no door; Models: the charge controller's model is the oxygen generator's.
- `doc/architecture.md`: Sealed rooms (no supply, the F3 line its one reader); The seat (Cradled, the cradle's Interact, the wait rule with `connected`, the settle, the offset); Save format (the 0358 lines above).
- `doc/hud.md`: Layout's centre (the wait's line over the backdrop), the glyph bar (Wait, Stop waiting), Notices (the wait's line). `doc/ui.md` 230: the charge controller. `doc/input.md`, X: the cradle waits and stops waiting. `doc/presentation.md` 184, 191, 195, 208. `doc/commands.md`: `seat <stand|sit|wait>`, `seat cradled`. `doc/developer_tools.md` 36: the F3 line. `doc/code_map.md`: `entity_pod.odin`, `simulation_field.odin`, `hud.odin`, and the counts `code_graph.py --check` asks for.

### Hand-back check

- A changed save layout: the former id and its line, the new seat and field read by name (Save).
- A number parsed from text: the cradle's cells and eye checked as the seat's.
- A long string fitted, at the smallest audit size: the wait's line (UI audit).
- A UI audit case: the new waiting case.
- Tests use temporary directories: the save test as its sibling does.

### Decisions

- The bed's cradle is a record key, as the chair is, not a fixture entity: a fixture's whole cells would collide inside the cabin where the pod's volumes do now, and the pod stays as built.
- The oxygen generator is renamed, not removed: its removal refuses old saves and empties a modelled pocket the user wants kept.
- The sealed room stays without its supply: it is derived and tested, and M15 may read it (shelter from weather's drain).
- A cradled unit is first person and not drawn: the model has no lying pose and the bed stands for it.
- The wait counts connected players only, through the records (`Input_Frame.connected`): a save from a session of three, loaded alone, keeps the other two entries, which would block the wait forever.
- After the wait every unit stands, so the rule does not fire again on the next tick; the 3 s settle shows the wait's screen to a lone unit.
- The charge is not simulated here: survival plays as peaceful, and no stat, bar, breakdown or respawn exists to hang it on (question 2).

### Proposals for the charge (M15; the user may overturn)

- Condition replaces health: the unit's integrity, mended only by the repair kit that mends machines, never by food or a medkit.
- The drain: a base draw that empties a full charge in about one default day idle, the lamp, digging, sprinting and the jet pack's thrust on top, and weather's cold and heat raising the base draw per planet, in watt hours in data, integer joules per tick with credits as `take_power_step`.
- At zero: walk only, no lamp, tools or jet pack, and the condition drains from full in about two minutes, never an instant breakdown (DESIGN.md's slow drain kept).
- The fill: the cradle fills an empty charge within the wait's eight hours, so a wait ends full. The pod's panels and batteries feed it through the charge controller, unlimited until 0355 gives the pod a network, then a consumer on it ("Power is never free"); a cable plugged into the unit from any network (The Last Caretaker's) is 0355's and M15's to design.
- Carried battery packs take the place the suit's canisters had; none exist today.
- In orbit the danger is an empty battery bank on the night side, not an open door.

### Questions to the main agent

1. Controls: the bed has no use and there is no sleep in the code, so "as the bed is" has nothing to follow. This specification uses Interact on the cradle's cells as on the chair (Wait; Interact again, Stop waiting). Confirm into the Controls section.
2. Scope: the charge is designed into `DESIGN.md` and `PLAN.md` for M15 and not simulated here. Confirm, or name a follow-up item.
3. The user's "just like a "wait" feature" may mean a wait anywhere, from the pause menu. This follows the item (the wait at the cradle); a pause menu Wait would set the same state without the eye, and the rule and the HUD stay.
4. A follow-up for the sealed lab (yours to write): the bed remade as a charging cradle and the oxygen generator's pocket as the charge controller, a rework round on the pod.

### Split

One implementer. If split: first the charge controller and the sealed room's supply (data, rename, F3 line, strings, their tests and docs), then the cradle and the wait.

### Decisions (main agent, 2026-11-11)

1. Question 1: confirmed, Interact on the cradle as on the chair (Controls, above).
2. Question 2: confirmed. The charge is design text for the survival milestone; no item simulates it until that milestone is picked.
3. Question 3: the wait is at the cradle. Whether the user meant a wait from anywhere is put to the user (`SUGGESTIONS.md`); the rule and the HUD would stay.
4. Question 4: the pod's remodelled cradle and charge controller are 0366, a sealed lab round after 0359's booklet round.
5. The proposals for the undecided points (condition, the drain, zero charge, the fill) go into `DESIGN.md` marked as proposals, as written.
6. `pod.py`'s docstring is corrected to the bed's 315 degrees in this item.
7. One implementer.
