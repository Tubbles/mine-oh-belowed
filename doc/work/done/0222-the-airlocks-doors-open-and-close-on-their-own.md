# 0222: The airlock's doors open and close on their own

Status: landed (2026-10-04, "Open and close the pod's airlock doors on their own (0222)", df4da68, play build installed the same day; the review weighed and its fix round done (a HUD test for the hidden Open hint, wording), the specification approved the same day with the decisions below, the implementer started on 0221's tree, from the user's pod notes of the art rounds, repeated on the phone the same day with the round three preview ("the doors stay open? I want them to only open individually when the player is really close and then close behind the player"): today the arrival opens both and nothing closes them; "doors that automatically open and close, but tightly enough so the player will have both doors closed around themselves while being in the middle", split off 0221 by its design stage; after 0221)

## Goal

The pod's two shutter doors work as an airlock without a press: a door opens for a player who comes to it and closes behind them, and the two never stand open at once, so a player crawling through has both doors closed round them in the middle, as the user asked. The user's words of the preview: a door opens only when the player is really close to it, the two open individually, and a door closes behind the player.

## Controls

No binding changes. Interact on a hatch stays as the override (it opens or closes the door as today, within the interlock: it refuses to open a door while the other is open). The automatic behaviour is lockstep state, hashed and saved like the toggles, never presentation.

## Change

- A lockstep step after the players move, per pod (`tick_pod_airlocks` or the name the design stage chooses): a door opens when a player's capsule stands within one cell of its outer side (the lane's cells before the inner door, the cells before the outer door) or crouches in the bore facing it, and only while the other door is closed (the interlock); it closes once no capsule meets its cells or its approach cells for a short hold (so a player who steps back does not see it flap). The hold is a data key of `data/game.sjson` with bounds.
- The arrival (0200) opens both doors at the fall's end so the player walks out; the interlock takes over after the first door closes. The design stage says how a loaded old world that starts with both closed behaves.
- The hatch cue (`play_hatch_sounds`) already plays every toggle, automatic ones included; a door that opens and closes on a fixed period would be a perceivable repetition, so the hold varies by a hash of the hatch and the tick, within its bounds (`DESIGN.md`, No perceivable repetition).

## Verify

- Tests: a crouched player entering the bore from the cabin has the inner door open and the outer closed, then both closed in the middle, then the outer open and the inner closed as they leave; the lockstep hash agrees between two machines over the sequence; Interact on the far door while the near one is open is refused.
- The couch: walk out and back in without a press, and never see both doors open at once after the arrival.

## Specification (design, 2026-10-04)

Designed against 0221's approved specification and its decisions (0222 lands after 0221): the hatches are 1 by 2 by 2 cells, rows 0 and 1, the outer the record's fixture 0 and the inner fixture 1, the bore the open cells box 2 (`TEST_AIRLOCK_BOX`) strictly between them, and the test helpers `pod_box_floor_centre`, `test_pod_record_cell`, `test_airlock_player` and `move_test_players_out_of_the_pod` exist. In the lab's 12 by 12 by 8 frame the outer hatch is at record cell {10, 0, 5} (x 10, z 5 to 6, y 0 to 1), the inner at {7, 0, 5}, the bore x 8 to 9, the lane's cells before the inner hatch x 6 and the cells before the outer x 11 and outside the footprint; if 0221 shrinks the footprint these shift with it. No code and no test names a literal cell: everything is derived from `pod.fixture_boxes`, `pod.open_cells` and the placed entities. No binding changes, no string keys.

### The rule in one paragraph

Per pod, once per tick after the players moved: a door is near a player when the player's capsule comes within `reach` (150 mm) of the door's cells, measured as the capsule's distance (the axis sampled as `capsule_meets_frame_cell` samples it) less its radius; a player wants a door when it is near and its heading is within 60 degrees of the direction from its feet to the centre of the door's cells, across the up. A closed door opens when a player wants it, it has finished its own slide, and the other door is closed and has finished its slide (the interlock). An open door that has finished its slide and that no player is near gets a close tick, the tick plus a hold drawn by a hash of the hatch and the tick between the two hold bounds; a player coming near clears it; at the close tick it closes through `toggle_hatch`, which still refuses while a capsule meets its cells (then the close tick stays and it retries every tick). Closes are applied before opens, and at most one door opens per pod per tick (fixture order, the outer first), so a closing and an opening never share a tick and both doors stand closed for at least one slide.

### Decisions on the open points

- Approach cells and "really close": a distance, not cells. The approach cells are the one cell before each face of each door (the inner: the lane's x 6 and the bore's x 8; the outer: the bore's x 9 and x 11 outside), but only their 150 mm slab next to the face counts: the feet are within 450 mm of the door's face (radius 300 plus reach 150). Why 150: the user wants the door to open late; at the crouch's 1.3 m/s that is 7 ticks before contact, and a closed door is solid, so a player who walks up stops touching it (distance 0) and it opens then. Two hard limits follow from the 1 m bore and the crouched capsule's 0.6 m: a player resting in the middle of the bore is 200 mm from both doors, so with a reach under 200 neither door is near and both stay closed round them (the user's "both doors closed around themselves while being in the middle"); a player stopped against the far door is 400 mm from the near one, so with a reach under 400 the near door can close behind them (with 400 or more it never would, and the far one never opens). The bounds are 50 to 300 mm, the test below checks the shipped pod against the 400.
- Feet cell or capsule: the capsule's distance. In the 2 cell bore every feet cell is a cell before one of the doors, so a feet cell rule cannot leave the middle near neither door, and it cannot tell 50 mm from 450 mm before a door.
- Facing: needed on every side, not only in the bore. Without it a player at the locker or passing the door, or one leaving the bore backwards, would open a door. It is not needed to keep a door open: the close rule is "no player near", facing or not.
- Crouch: not tested by the step. A standing capsule cannot be in the bore (0221, decision 6), and a standing player outside may open the outer door and then has to crouch to pass, which is the user's rule.
- The hold: `close_hold_minimum_ticks` 36 and `close_hold_maximum_ticks` 72 (0.6 to 1.2 s), each 1 to 600, the minimum at most the maximum, in ticks as the arrival's keys are. The hold starts only once the door's opening slide (`period_seconds` 0.8 of `pod_hatch`, 48 ticks) has finished, so a door never reverses mid slide and stands fully open for the hold. The hash: `generation_seed.hash_combine(u64(handle.index) << 32 | u64(handle.generation), tick)` and `generation_seed.hash_to_range` over the bounds, as `leaf_decay_hash` and `leaf_decay_delay` do (`tree_felling.odin`); the handle and the tick are lockstep state, no wall clock.
- The slide's length: `door_travel_ticks`, `round(period_seconds * tick_rate)` of the content's first `.Hatch` machine, computed once at load (`make_pod_airlock_tuning`), an integer in the tuning; the simulation state stays integer.
- A loaded old world with both doors closed and the player inside: nothing special. An older save reads `hatch_close_tick` as 0 (none due) and `hatch_toggle_tick` 0 counts as settled, which is the state a fresh `place_pod` has, so the player walks or crawls up to a door facing it and it opens. A save from after the arrival (both open, 0198 to 0221): each door that no player is near closes after its hold, one that a player is near stays open until they leave it; no log line, since nothing is lost (as `Field_Player.crouching` loaded false before 0218).
- A player in a doorway: their capsule meets the door's cells, so it is near; the close tick is cleared every tick and the door stays open however long they stand there. `toggle_hatch`'s capsule check stays as the backstop for the close tick reached on the same tick a capsule arrives.
- Two players at opposite doors: whichever door a player wants first opens; the other player waits until that door closes (its player has left its reach and its hold has run) and has finished its slide. On the same tick the outer door wins (fixture order). A player standing in the open door keeps the other waiting, as an airlock does.
- The arrival: unchanged, it opens both through `toggle_hatch` at its last tick; the step does nothing while the world falls (so a spawn near a door cannot open it mid fall) and on the landing tick it runs before the landing. From the next tick both doors are open and settled after 48 ticks; each closes after its own hold unless a player is near it; then the interlock holds.
- `hatch_toggle_tick`, the slide and the cue: unchanged. An automatic toggle goes through `toggle_hatch`, which sets `hatch_toggle_tick`, rebuilds the cells and the sealed rooms; `hatch_open_fraction` and `play_hatch_sounds` follow it as they follow a press.
- Interact: within the interlock, opening a closed door is refused (no event, no toast, the A press still does not jump, as `without_field_interact_jump` already removes Jump on a hatch) while the other door is open or has not finished its closing slide; closing is as today. Interact stays an override of the moment: a door opened by Interact with no player near closes after its hold, and a door closed by Interact before a player who faces it within reach opens again once its slide has finished.
- The prediction never runs the step (as it never runs `toggle_hatch`): a predicted player meets a closed door until the confirmed tick opens it, a snap of at most the window.
- The save: one new field, `Foundation.hatch_close_tick: u64`. It cannot be derived: the hold runs from the tick the last player left, which no other field records, and a join snapshot or a load in mid hold must close the door on the same tick as the machine that saved.

### Files and procedures

`data/game.sjson`, after `arrival_window_pitch_degrees`:

```
// The pod's airlock (work item 0222, doc/content.md, Hatches): a hatch of
// the pod opens on its own for a player whose capsule comes within
// reach_millimetres (50 to 300) of it facing it, while the other hatch is
// closed and has finished its slide; an open hatch no capsule comes within
// the reach of closes after a hold drawn per hatch and tick from
// close_hold_minimum_ticks to close_hold_maximum_ticks (each 1 to 600, the
// minimum at most the maximum), so the doors never close on a beat. The
// reach stays under the airlock's 1 m less the crouched capsule's 0.6 m,
// so a player against the far hatch is out of the near one's reach.
pod_airlock = {
	reach_millimetres = 150
	close_hold_minimum_ticks = 36
	close_hold_maximum_ticks = 72
}
```

`src/data_load.odin`:

- `Pod_Airlock_Config :: struct { reach_millimetres: int, close_hold_minimum_ticks: int, close_hold_maximum_ticks: int }`, after `Field_Simulation_Config`.
- `Game_Config.pod_airlock: Pod_Airlock_Config`, after the arrival fields, comment "The pod's airlock (work item 0222, entity_pod_airlock.odin): how near a player opens a hatch and the bounds of the hold before an open one closes."
- `MINIMUM_POD_AIRLOCK_REACH_MILLIMETRES :: 50`, `MAXIMUM_POD_AIRLOCK_REACH_MILLIMETRES :: 300`, `MAXIMUM_POD_AIRLOCK_HOLD_TICKS :: 600`.
- `pod_airlock_problem :: proc(airlock: Pod_Airlock_Config) -> string`: `Config_Bound`s `pod_airlock.reach_millimetres` 50 to 300, `pod_airlock.close_hold_minimum_ticks` 1 to 600, `pod_airlock.close_hold_maximum_ticks` from the minimum to 600, the message `"%s %d is outside %d to %d"`. Called in `validate_game_config` after `arrival_problem`.

`src/field_mining.odin`: `Field_Content.pod_airlock: Pod_Airlock_Tuning` after `bare_ground`, comment "The pod's airlock (0222, entity_pod_airlock.odin)."

`src/simulation_field.odin`:

- `make_field_content` sets `pod_airlock = make_pod_airlock_tuning(config.pod_airlock, machines, config.tick_rate)`.
- `tick_field_session_players`, right after `finish_field_tick(state, content)`: `if !field_arrival_falling(state.field.arrival) { tick_pod_airlocks(&state.world.entities, content.machines, field_players_of(state.players[:]), content.field.tuning, content.field.pod_airlock, state.tick) }`. So the order is: every player's move and queues, the drain, the water and light, the airlocks, the refusal events, the landing.
- `interact_on_field`: before `toggle_hatch`, `if pod_airlock_refuses_opening(entities, machines, handle, state.tick, content.field.pod_airlock.door_travel_ticks) { return input, {} }`. The procedure's comment gains "within the airlock's interlock (pod_airlock_refuses_opening, 0222)".
- The file's header comment gains one sentence: after the players move and the queues drain, the pod's airlocks step (`tick_pod_airlocks`, 0222).

`src/entity.odin`: `Foundation.hatch_close_tick: u64` after `hatch_toggle_tick`; the struct's comment gains "and the tick an open hatch closes on its own (0222, entity_pod_airlock.odin), 0 when none is due; a save from before 0222 loads it 0".

`src/entity_pod.odin`:

- `toggle_hatch` sets `hatch.hatch_close_tick = 0` beside `hatch_toggle_tick`, on every toggle (press, arrival, airlock).
- `capsule_within_frame_cell :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule, margin: i64) -> bool`: today's body of `capsule_meets_frame_cell` with `distance < capsule.radius + margin`. `capsule_meets_frame_cell` becomes `return capsule_within_frame_cell(frame, cell, capsule, 0)`, its comment kept.
- The header comment's "toggled by Interact (toggle_hatch)" becomes "toggled by Interact (toggle_hatch) and on its own as an airlock (entity_pod_airlock.odin, 0222)".

New `src/entity_pod_airlock.odin` (package `game`, imports `core:math` and `generation_seed`), header comment: the pod's airlock (work item 0222, doc/content.md, Hatches), the rule paragraph above in short, lockstep state through `Foundation.hatch_open`, `hatch_toggle_tick` and `hatch_close_tick`, never run by the prediction.

- `POD_AIRLOCK_FACING_COSINE :: UNIT_VECTOR_ONE / 2`: a player faces a door within 60 degrees.
- `Pod_Airlock_Tuning :: struct { reach: i64, close_hold_minimum_ticks: i64, close_hold_maximum_ticks: i64, door_travel_ticks: u64 }`: the reach in position units, the hold bounds, the slide's length in ticks.
- `make_pod_airlock_tuning :: proc(config: Pod_Airlock_Config, machines: Machine_Registry, tick_rate: int) -> Pod_Airlock_Tuning`: the reach through `millimetres_to_position_units`, the bounds as they are, `door_travel_ticks = hatch_travel_ticks(machines, tick_rate)`. Called by `make_field_content` and the tests.
- `hatch_travel_ticks :: proc(machines: Machine_Registry, tick_rate: int) -> u64`: `u64(max(0, int(math.round(f64(motion.period_seconds) * f64(tick_rate)))))` of `find_machine_of_kind(machines, .Hatch)`, 0 without one. The f32 0.8 times 60 is 48.0000007, so round, never ceil.
- `Pod_Airlock :: struct { doors: [2]Entity_Handle }`: the first two hatch fixtures of a pod in record order (the outer, the inner).
- `find_pod_airlock :: proc(entities: ^Entities, machines: Machine_Registry, pod: Entity_Common) -> (airlock: Pod_Airlock, found: bool)`: for the record's fixtures whose machine is of kind `.Hatch`, in order, `entity_at(entities, origin, pod.frame)` at `pod_fixture_placement(record, pod.origin, pod.rotation, index)`, kept when `hatch_state` says it is a hatch; found when two are. No pool scan.
- `pod_airlock_of_hatch :: proc(entities: ^Entities, machines: Machine_Registry, hatch: Entity_Handle) -> (airlock: Pod_Airlock, door: int, found: bool)`: the pod on the hatch's frame (`pod_on_frame`), its airlock, and which door the hatch is; found false for a hatch of no airlock.
- `hatch_settled :: proc(hatch: Foundation, tick: u64, travel_ticks: u64) -> bool`: `hatch.hatch_toggle_tick == 0 || tick + 1 >= hatch.hatch_toggle_tick + travel_ticks` (toggled at tick t the slide ends at t plus the travel). Pure.
- `pod_airlock_close_hold :: proc(hatch: Entity_Handle, tick: u64, airlock: Pod_Airlock_Tuning) -> u64`: the hash above over `close_hold_minimum_ticks` to `close_hold_maximum_ticks` inclusive. Pure.
- `capsule_near_cells :: proc(frame: Frame, cells: []World_Coordinate, capsule: Field_Capsule, reach: i64) -> bool`: any cell with `capsule_within_frame_cell(frame, cell, capsule, reach)`. Pure.
- `player_faces_cells :: proc(frame: Frame, player: Field_Player, cells: []World_Coordinate) -> bool`: the mean of `frame_cell_centre` over the cells, `tangent_of(player.up, centre - player.position)` dotted (`fixed_dot`) with `field_player_heading(player)` above `POD_AIRLOCK_FACING_COSINE`. Pure.
- `Airlock_Door_Call :: struct { near: bool, wanted: bool }` and `airlock_door_call :: proc(frame: Frame, cells: []World_Coordinate, players: []Field_Player, tuning: Field_Player_Tuning, reach: i64) -> Airlock_Door_Call`: near when any player's `field_player_capsule` is near the cells, wanted when any near player also faces them. Pure.
- `close_airlock_door :: proc(entities: ^Entities, machines: Machine_Registry, door: Entity_Handle, call: Airlock_Door_Call, capsules: []Field_Capsule, airlock: Pod_Airlock_Tuning, tick: u64)`: for an open, settled door: near clears `hatch_close_tick`; else 0 sets it to `tick + pod_airlock_close_hold(door, tick, airlock)`; else at or past it `toggle_hatch(entities, machines, door, tick, capsules)` (a refusal keeps the close tick). A closed or sliding door is left alone.
- `airlock_door_may_open :: proc(door, other: Foundation, tick: u64, travel_ticks: u64) -> bool`: `!door.hatch_open && hatch_settled(door, ...) && !other.hatch_open && hatch_settled(other, ...)`. Pure.
- `step_pod_airlock :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame, airlock: Pod_Airlock, players: []Field_Player, tuning: Field_Player_Tuning, airlock_tuning: Pod_Airlock_Tuning, tick: u64)`: the two calls from the state at its start (each door's `common_cells`), `close_airlock_door` for door 0 then 1, then the first door in order with `wanted` and `airlock_door_may_open` opens through `toggle_hatch(entities, machines, door, tick, nil)` and no other.
- `tick_pod_airlocks :: proc(entities: ^Entities, machines: Machine_Registry, players: []Field_Player, tuning: Field_Player_Tuning, airlock: Pod_Airlock_Tuning, tick: u64)`: every alive pod of the foundations' pool by index (`toggle_hatch` changes entries in place, never appends), `find_pod_airlock`, its frame (`find_frame`), `step_pod_airlock`. Called by `tick_field_session_players` only.
- `pod_airlock_refuses_opening :: proc(entities: ^Entities, machines: Machine_Registry, hatch: Entity_Handle, tick: u64, travel_ticks: u64) -> bool`: true when the handle is a closed hatch of an airlock whose other door is open or not settled. Called by `interact_on_field`.
- `field_players_of :: proc(players: []Player) -> []Field_Player`: each player's `field`, in the temp allocator.

The costs: per pod and tick, two doors of 4 cells times the players times the capsule's 3 to 7 samples, and two `entity_at` lookups; no pool scan beyond the pods'.

### Save layout

`Foundation.hatch_close_tick` is read by name (`save_binary.odin`): a save without it loads 0, which is "none due", the value the step itself sets on the next tick. No remap, no format version, no log line. The field rides the foundations' pool, so it is in the state hash and the join snapshot; a block world writes no foundations and keeps its bytes.

### Tests

Helpers (`src/entity_pod_airlock_test.odin`, new):

- `test_pod_airlock_tuning :: proc(machines: Machine_Registry) -> Pod_Airlock_Tuning`: `make_pod_airlock_tuning` of the shipped `pod_airlock` (`parse_game_config(#load("../data/game.sjson"))`) at `TEST_TICK_RATE`.
- `test_door_face :: proc(frame: Frame, pod: Machine, index: int, outer_side: bool) -> i64`: the frame local coordinate along the airlock axis (`frame_local_position(...).z`, record x turned by `POD_ROTATION`) of a hatch box's outer (+x) or inner face, from `test_pod_record_cell`.
- `cross_test_airlock :: proc(t: ^testing.T, spacing: int, outward: bool)`: the crossing below; `outward` from the cabin to the outside, else back in.
- `test_field_game_config` (`player_test.odin`) copies `pod_airlock` from the shipped config.

New tests:

1. `test_a_crouched_player_crosses_the_airlock_with_one_door_open_at_a_time` (`entity_pod_airlock_test.odin`), at every `TEST_FIELD_SPACINGS`, `cross_test_airlock(t, spacing, true)`: the flat test field, `place_test_pod`, a player at `pod_box_floor_centre` of the record box one cell deep before the inner hatch's -x face over its z span (x `inner.x - 2` to `inner.x - 1`, row 0), facing `frame.axes[FRAME_FORWARD]`; a tick counter from 1, each tick `run_field_player_with_frames(..., 1)` and then `tick_pod_airlocks` with the one player. 30 ticks of `{held = {.Sneak}}`: both closed, the player crouching. Then `FIELD_SNEAK_FORWARD` each tick, at most 900 ticks, until the feet are 2 cells past the outer hatch's outer face, then input `{held = {.Sneak}}` for `door_travel_ticks + close_hold_maximum_ticks + door_travel_ticks + 2` ticks. Every tick: never both open. In order, each must happen: (a) the inner opens on a tick when the outer is closed and the feet are before the inner face by at most radius plus reach plus one tick of sneak travel (`sneak_speed` per tick, rounded up) plus `FIELD_GROUND_TOLERANCE` (it opened late); (b) the inner closes on a tick when the feet's cell (`frame_cell_of_feet`) is a bore cell (`machine_open_cells` of box `TEST_AIRLOCK_BOX`) and the outer is closed: both closed round the player in the bore; (c) the outer opens no earlier than `door_travel_ticks` after (b), with the inner closed, the feet in the bore; the inner stays closed to the end; (d) at the end the outer is closed and the feet outside the footprint. Each failure names the spacing and the stage reached.
2. `test_a_crouched_player_comes_back_in_through_the_airlock` (same file), `cross_test_airlock(t, spacing, false)`: start two cells before the outer hatch's outer face (`move_test_players_out_of_the_pod`'s point) facing `-frame.axes[FRAME_FORWARD]`, the roles swapped: the outer opens first, both closed with the feet in the bore, the inner opens after the travel, the end with the feet in the lane or the cabin box and the inner closed.
3. `test_the_airlock_is_lockstep_state_and_survives_a_save` (`simulation_field_test.odin`, after `test_toggling_a_hatch_is_lockstep_state`, its pattern): two sessions of one seed (`start_field_test_session`, `test_field_game_config`), `stage_generated_field_set`; each moves player 0's body (`move_field_player_body`) to the point of test 1, facing the forward; each tick feeds `Input_Frame{move = {0, 1}, pressed = {.Move, .Sneak}}` for 600 ticks. On the first tick session 0's inner hatch has `hatch_close_tick != 0`, session 0 is saved (`encode_save_files`) and loaded into a third session (as that test loads), which runs the remaining ticks with the same inputs. Asserted: the outer hatch's `hatch_toggle_tick` agrees across the three and is non zero (the outer opened), `simulation_state_hash` agrees at tick 600 across the three, and a fourth session fed no input hashes otherwise.
4. `test_interact_on_the_far_door_is_refused_while_the_near_one_is_open` (`simulation_field_test.odin`): one session; player 0's body at `test_airlock_player` (crouched, the bore's middle, facing the outer); `toggle_hatch` opens the inner at the state's tick; one tick of `{pressed = {.Sneak}}` (the aim), then one of `{pressed = {.Interact, .Sneak}, just_pressed = {.Interact}}`: the outer stays closed, the inner open, no `.Toggled_Switch` event. Then `toggle_hatch` closes the inner, `door_travel_ticks` ticks of `{pressed = {.Sneak}}` (the inner stays closed: the player in the middle is near neither door, and faces away from the inner), and Interact again: the outer opens with `.Toggled_Switch`.
5. `test_the_airlock_hold_varies_within_its_bounds` (`entity_pod_airlock_test.odin`), pure: for two handles `{.Foundation, 3, 1}` and `{.Foundation, 4, 1}` and ticks 1 to 1000, every `pod_airlock_close_hold` is within 36 to 72; each handle draws at least 20 distinct values; the two differ on at least 900 of the ticks; with minimum and maximum both 40 every hold is 40.
6. `test_an_airlock_door_stays_open_while_a_capsule_stands_in_it` (`entity_pod_airlock_test.odin`): flat field at 1000 mm, `place_test_pod`, the outer opened by `toggle_hatch` at tick 1; a crouched player at `pod_box_floor_centre` of the outer hatch's box (in its cells); `tick_pod_airlocks` from tick 2 to 600: the outer stays open and its `hatch_close_tick` stays 0. The player moved to two cells outside the outer face: the next step sets the close tick 36 to 72 ticks ahead (the door settled long before), and the door closes exactly on that tick. Then with the close tick set by hand to the current tick and the player put back in the door cells, a direct `close_airlock_door` with `near = false` and the capsule leaves it open with the close tick kept (`toggle_hatch`'s refusal).
7. `test_two_players_at_opposite_doors_take_turns` (`entity_pod_airlock_test.odin`): flat field at 1000 mm; player A crouched in the lane touching the inner hatch (feet `radius` before its -x face) facing it, player B outside touching the outer (feet `radius` past its +x face) facing it; both doors fresh. `tick_pod_airlocks` at tick 1: the outer opens, the inner stays closed. 300 more ticks: unchanged (B is near the outer). B moved 3 m away: the outer closes after its hold, and the inner opens no earlier than `door_travel_ticks` after; never both open.
8. `test_doors_left_open_close_on_their_own` (`entity_pod_airlock_test.odin`): both opened by `toggle_hatch` at tick 1 (an arrival, or a save from 0198 to 0221), no players: from tick 2, each closes at a tick from `1 + door_travel_ticks + 36` to `1 + door_travel_ticks + 72`, and neither opens again within 600 ticks.
9. `test_the_airlock_reach_leaves_room_in_the_bore` (`entity_pod_airlock_test.odin`), pure on the shipped record and config: the bore's length (box `TEST_AIRLOCK_BOX`'s x span times 500 mm) less twice the crouched capsule radius is above the reach, and half that length less the radius is above the reach too (the middle near neither door).
10. `test_the_pod_airlock_config_is_bounded` (`data_load_test.odin`): the shipped config passes `pod_airlock_problem`; reach 40 and 301, minimum 0, maximum below the minimum and 601 each give a problem naming the key.
11. `test_the_arrivals_open_doors_close_on_their_own` (`simulation_arrival_test.odin`): `arrival_test_config`, a still session to the landing (both open at `ARRIVAL_TEST_TICKS`), then `door_travel_ticks + 72 + 1` ticks with no input: both closed, each `hatch_toggle_tick` at least `ARRIVAL_TEST_TICKS + 1 + door_travel_ticks + 36`.

Changed: `test_a_new_world_holds_its_players_through_the_fall` and the other arrival tests are expected unchanged (the step skips the fall and runs before the landing). Expected unchanged, rerun: `test_toggling_a_hatch_is_lockstep_state` (the inner opened by the press settles at 48 ticks and closes no earlier than 84, after its 61 ticks), the scripted hash tests, `test_both_hatches_close_round_a_crouched_player_in_the_airlock`, `test_closing_a_hatch_on_a_player_is_refused`, the save tests. A simulation level test that opens the hatches and later expects one still open fails now when no player is near it: the implementer names each with its line in the report and keeps it working by putting the player near or asserting the new behaviour, never by disabling the step.

### Docs (same commit)

- `doc/content.md`, Hatches: the Interact bullet says opening is refused within the interlock and that Interact is an override of the moment; a new bullet "The airlock (0222)" with the rule paragraph, the reach and the hold keys, the settled slide, the doorway, the two players, the old saves.
- `doc/content.md`, The arrival: the `arrival_ticks` bullet adds that the airlock closes the opened doors once no player is near them.
- `doc/content.md`, The pod: the saved state names the close tick.
- `doc/architecture.md`, The field session: a bullet after the arrival's on the step's place in the tick (after `finish_field_tick`, before the landing, skipped while the world falls), never in the prediction, hashed and saved. Save format, the hatch bullet: `hatch_close_tick` read by name, an older save loads it 0.
- `doc/presentation.md`: the hatch slide bullet and the hatch cue sentence of The arrival say that the airlock's toggles drive them like a press and that the interlock waits for the slide, so the two doors are never drawn open at once after the landing.
- `doc/code_map.md`: the `entity_pod_airlock.odin` line after `entity_pod.odin` ("the pod's airlock (0222): the doors open for a player close and facing them and close behind, `tick_pod_airlocks`, the interlock `pod_airlock_refuses_opening`"); the simulation cluster's presentation reach gains the hatch's slide period read in `hatch_travel_ticks` (0222), with the counts `tools/code_graph.py --check` reports.
- `doc/log/2026-10-04.md`: "The airlock's doors on their own (0222)", tags `pod, airlock, hatch, lockstep, save, m15`: the distance rule and why not cells, the 150 mm and its two limits, facing, the interlock waiting for the slide, the hold and its hash, the arrival, the old saves, the new field.

### Hand-back check lines that apply

- A changed save layout loads an old save: the field is read by name and 0 is the correct value; no remap or log line, named in the log entry; tests 3 and 8 cover a save mid hold and the old both open state.
- A number parsed from text is range checked: `pod_airlock_problem`, test 10.
- A new participant in a shared budget: the doors share the interlock; the queue cannot stick, since the open door closes as soon as its player leaves its reach (test 7), and test 9 keeps a player waiting at the far door out of the near door's reach.
- Tests never touch the machine's state directory: the save in test 3 goes through `encode_save_files` in memory as the existing hatch test does.
- The others (frame memory, file writes, start-up loads, unbounded lists, UI audit cases) do not apply.

### Commands (implementer, in the item's worktree)

`./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, each prefixed `taskset -c 8-15 nice -n 10`.

### Questions for the main agent

1. The arrival's opening becomes a short flourish: both doors open at the landing and close about 1.4 to 2 s later (the slide plus the hold) unless the player is already at one, so the player who walks out finds them closed and they open again as they come. Keep it as decided, or drop the arrival's opening (the doors open as the player comes anyway, and the couch would never see both open at once)?
2. The HUD hint on a closed hatch still says Open while the interlock refuses it. Leave it, or a later item for a "waiting" hint?

### Decisions at the approval (main agent, 2026-10-04)

1. The arrival no longer opens the doors: both start closed at the landing and the inner one opens when the player comes to it, which is the user's rule ("only open individually when the player is really close"); a flourish of both doors opening and closing on their own two seconds after the landing would be the one thing the user asked not to see. The implementer removes the arrival's toggle and adapts the arrival's test and docs (0200, 0223 draws the arrival from the chair later and takes this as given); a loaded old world with both doors open closes them by the hold like any other.
2. The Open hint on a closed hatch is hidden while the interlock refuses it (the hint reads `pod_airlock_refuses_opening`, the same predicate Interact reads), so the HUD never offers what a press would refuse.
3. The 150 mm reach, the 60 degree facing, the hold of 36 to 72 ticks hashed from the hatch handle and the tick, the interlock waiting for the other door's slide, `Foundation.hatch_close_tick` read by name with an old save loading 0: approved as specified.
4. Interact stays the override within the interlock as specified: a door closed by a press in front of a facing player reopens after its slide, a door opened from afar closes after its hold.
