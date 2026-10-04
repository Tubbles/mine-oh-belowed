# 0234: A free crafting toggle on the Developer screen

Status: landed (2026-10-04, "Add a free crafting toggle to the Developer screen (0234)", 7a970ec, installed the same day; implementer agent acf08caa1140d4944, verified the same day with no fix round, in `.claude/worktrees/0234` on `item/0234` from 0233's snapshot, the specification approved the same day with the decisions below; from the user: "in the developer menu, can you add a new switch toggle that enables crafting without consuming materials, it just crafts the thing no matter if we have the required materials in the inventory, and doesn't consume any materials that happened to exist. Sort of an in game 'give' cheat mode. It doesnt unlock anything new, we already have that as a separate button")

## Goal

A developer toggle, Free crafting, beside Fly mode, No clip and Cheat speed on the Developer screen: while it is on, every craft the player orders (the inventory's hand crafts and the crafting stations' and benches' crafts) is accepted whatever the inventory holds and consumes nothing, so the player gives themselves items through the recipe browser. It unlocks nothing: a recipe still needs its unlock (Unlock all is the button for that) and its maker (a station recipe still needs the station), and the craft still takes the recipe's time (Cheat speed covers time).

## Controls

No binding changes. The toggle is a `ui_toggle` row on the Developer screen like Fly mode, reached by focus navigation and the pointer as the others are; the design stage places it (a fourth column of the first row or a new row) against the smallest audit size. Like the other developer toggles it queues a `Player_Command` that the next tick applies, so it is lockstep state the whole session shares, shown a frame later, with the "applies on resume" toast where the others show it.

## Change

- A flag beside the fly mode, no clip and cheat speed flags in the simulation's developer state (the design stage names it, says whether those are saved and hashed, and does the same for this one). A `Toggle_Free_Crafting` command in `player_command.odin` beside `Toggle_Cheat_Speed`.
- Crafting (`crafting.odin`): with the flag on, a queued craft of an unlocked recipe the player's makers allow plans no inputs and no intermediates (`make_craft_plan`, `plan_inputs`, `plan_intermediate`, `craft_refusal`'s availability), is never refused for a shortage and never waits for input (`craft_queue_waits_for_input`), and its run takes nothing from the inventory when it starts or finishes; the outputs land as today (a full inventory still refuses as today). Crafts queued before the toggle finish under the rule in force when their run starts; the design stage says what happens to a queue waiting for input when the toggle turns on (it starts) and to a free run when it turns off (it finishes free, since nothing was reserved).
- The recipe browser and the station panels show every unlocked recipe as craftable while the flag is on (the greyed shortage state off), with the planned counts the plan gives; the design stage lists the UI predicates that read the availability.
- Strings: `developer_free_crafting` in `data/strings/en.sjson` (and the other shipped languages' files if they carry the developer keys).
- Docs: `doc/developer_tools.md` (Developer screen, the toggle beside the others), `doc/crafting.md` or wherever the hand crafting rule lives (the cheat as one line), `doc/architecture.md` if the flag is saved, `doc/log/2026-10-04.md`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: with the flag on, a craft of an unlocked hand recipe with an empty inventory is accepted and finishes with the output and nothing taken; a craft with the inputs present leaves them untouched; a locked recipe is still refused; a station recipe without the station is still refused; a queue waiting for input starts when the flag turns on; two sessions with the toggle pressed on one hash alike; the Developer screen's toggle row at the smallest audit size (the UI audit).
- The couch: toggle it, craft a drill from nothing, toggle it off, the next craft asks for materials again.

## Specification (design, 2026-10-04)

### The flag

- `Simulation_State.free_crafting: bool` in `src/simulation_state.odin`, right after `cheat_speed`, with the comment: "Developer free crafting (0234): every craft a player orders plans and starts without ingredients. Not saved; hashed and carried in the join snapshot like cheat_speed." Per world, exactly as `cheat_speed` is (fly mode and no clip are per player on `Player`, cheat speed is the world's; a crafting cheat that a whole session shares belongs with cheat speed).
- Not saved, as `cheat_speed` is not (`make_world_file` and `entities.bin` never write it). A loaded save, old or new, starts with it off; nothing to remap.
- Hashed where `cheat_speed` is: `lockstep_state_hash` (`src/lockstep.odin`), one more line after the cheat speed fold: `result = fingerprint_u64(result, simulation.free_crafting ? 1 : 0)`. Its comment's "it covers cheat speed" becomes "it covers cheat speed, free crafting". `simulation_state_hash` is not touched (cheat speed is not in it either).
- Carried in the join snapshot like `cheat_speed` (`src/session_network.odin`): `Join_Snapshot.free_crafting: bool` after `cheat_speed`; `encode_join_snapshot` appends `append_u8(&bytes, simulation.free_crafting ? 1 : 0)` right after the cheat speed byte; `decode_join_snapshot` reads `snapshot.free_crafting = (read_u8(&reader) or_return) == 1` right after the cheat speed read; `adopt_join_snapshot` sets `simulation.free_crafting = snapshot.free_crafting` after the cheat speed line. Peers must run one build (`BUILD_STAMP` is checked at the join), so the extra byte needs no version step.
- Kept across a data reload like `cheat_speed`: `make_reloaded_simulation` (`src/data_reload.odin`) adds `state.free_crafting = old.free_crafting`.
- The command: `Developer_Action.Toggle_Free_Crafting` (`src/developer.odin`), appended as the enum's last value (after `Set_Filter`, so no older value moves) with the comment "Flips Simulation_State.free_crafting (0234)." The item's "a `Toggle_Free_Crafting` command in `player_command.odin`" is this: the other toggles are `Developer_Request` actions carried by the `Player_Command` union's `Developer_Request` variant, not variants of their own. Its apply in `serve_developer_request`: `case .Toggle_Free_Crafting: state.free_crafting = !state.free_crafting`. In `developer_request_valid` (`src/player_command.odin`) it joins the `case .Toggle_Fly_Mode, .Toggle_No_Clip, ...: return true` list.
- No socket command (`command.odin`'s `cheat_speed on|off` has no free crafting twin) and no diagnostics line: the item asks for neither (Questions 1).

### Crafting (`src/crafting.odin`)

Every changed procedure takes the flag as a trailing parameter `free_crafting := false` (never `free`, which is Odin's builtin), after `makers` and after `allocator` where a procedure has one, so the ninety odd test calls compile unchanged. Production callers pass it by name (`free_crafting = state.free_crafting`).

Data:
- `Craft_Queue.started_free: bool`, after `waiting_for`, documented in the struct comment: "started_free is set while the front craft started under free crafting and took nothing; it finishes, and cancels, without ingredients whatever the flag says by then." Saved: `entities.bin` reads struct fields by name, so a save from before 0234 loads it false, which is right (every craft then took its ingredients). No remap, no log line, as the hatch fields of 0198 and 0222. `remap_craft_queue` needs no change (it keeps the front fields, and `reset_front_craft` clears them when the front run is gone).
- `Craft_Plan.free_crafting: bool`, after `makers`, comment "Plans no ingredients: every input counts as held (0234)."
- `reset_front_craft` also clears `started_free`.

Procedures, signatures and what each does with the flag:
- `make_craft_plan :: proc(inventory: Inventory, recipes: Recipe_Registry, available: []bool, makers := HAND_MAKERS, free_crafting := false) -> Craft_Plan`: stores it in the plan.
- `plan_input` (signature unchanged): `if plan.free_crafting { return true }` first, so no shortfall is planned, no intermediate is queued and the virtual inventory is not charged. This covers `plan_inputs` and `take_planned_inputs`, its only callers. `plan_inputs`, `plan_recipe`, `plan_intermediate` stay as they are (with `plan_input` short circuited, `plan_intermediate` is reached in free mode only from `planned_input_state`, below).
- `planned_input_state` (signature unchanged): the first case becomes `case short <= 0 || plan.free_crafting: return {.Held, available}`, so no ingredient shows as Craftable or Missing while the flag is on.
- `plan_front_repair :: proc(queue: Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, available: []bool, makers := HAND_MAKERS, free_crafting := false) -> []Craft_Run`: returns nil when `free_crafting` (the waiting front starts free on the next tick, nothing needs to go ahead of it).
- `make_plan_after_queue :: proc(queue, inventory, recipes, available, makers := HAND_MAKERS, free_crafting := false) -> (plan: Craft_Plan, ahead: []Craft_Run)`: passes it to `plan_front_repair` and `make_craft_plan`.
- `plan_crafts :: proc(queue, inventory, recipes, available, recipe, count: int, makers := HAND_MAKERS, free_crafting := false) -> (ahead, runs: []Craft_Run, refusal: Craft_Refusal, shortage: Craft_Shortage)`: passes it to `make_plan_after_queue`.
- `plan_queue_crafts :: proc(queue, inventory, recipes, unlocks, recipe, count: int, makers := HAND_MAKERS, free_crafting := false) -> (...)`: passes it to `plan_crafts`. `craft_refusal` runs first unchanged, so `.Locked` and `.Not_Hand_Craftable` (the unlock and the maker) refuse as today; `.Queue_Full` refuses as today. With the flag the plan never fails, so `.Missing_Ingredients`, `.Recipe_Cycle` and `.Plan_Too_Deep` never come.
- `queue_crafts :: proc(queue: ^Craft_Queue, inventory, recipes, unlocks, recipe, count: int, makers := HAND_MAKERS, free_crafting := false) -> (refusal, shortage)`: passes it to `plan_queue_crafts`.
- `queue_accepts_crafts :: proc(queue, inventory, recipes, unlocks, recipe, count: int, makers := HAND_MAKERS, free_crafting := false) -> bool`: passes it on.
- `planned_crafts :: proc(queue, inventory, recipes, unlocks, recipe: int, makers: Recipe_Makers, allocator := context.allocator, free_crafting := false) -> Planned_Crafts`: passes it to both below.
- `planned_craft_count :: proc(queue, inventory, recipes, unlocks, recipe: int, makers := HAND_MAKERS, free_crafting := false) -> int`: passes it to every `queue_accepts_crafts`. With the flag it returns `PLANNED_CRAFT_COUNT_LIMIT` (999) for an accepted recipe whose run merges with the last, or fewer when the queue is full: "the planned counts the plan gives".
- `planned_input_states :: proc(queue, inventory, recipes, available: []bool, recipe: int, makers := HAND_MAKERS, allocator := context.allocator, free_crafting := false) -> []Planned_Input`: passes it to `make_plan_after_queue`.
- `start_front_craft :: proc(queue: ^Craft_Queue, inventory: Inventory, recipe: Recipe, free_crafting := false) -> bool`: with the flag it sets `waiting_for = NO_ITEM`, `started = true`, `started_free = true`, takes nothing and returns true; otherwise as today (`started_free` stays false).
- `advance_crafting :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry, tick_rate: int, free_crafting := false) -> (finished: int, finished_free: bool)`: passes the flag to `start_front_craft` only (a craft already started keeps its rule); the outputs land as today and a full inventory sets `waiting` as today; `finished_free` is `queue.started_free` read before `finish_front_craft` resets it, false whenever `finished == NO_RECIPE`. The two test calls (`advance_crafting_ticks`, `test_a_crafting_station_lets_the_hand_queue_cut_stone`) are statements and compile unchanged.
- `last_craft_cancels` (signature unchanged): `return !newest_craft_is_in_progress(queue) || queue.started_free || inventory_fits_all(...)`: a free craft in progress gives nothing back, so the room check does not apply.
- `cancel_last_craft` (signature unchanged): gives the ingredients back only when `newest_craft_is_in_progress(queue^) && !queue.started_free`.
- Untouched: `craft_refusal`, `first_missing_input`, `craft_queue_waits_for_input`, `hand_recipe_making`, `recipe_is_made_by`, `player_craft_makers`, `add_queued_runs` (its `taken` for a started front is right for a free front too: a free craft will not take its inputs, so they must not be charged again), `insert_runs_ahead`, `append_craft_run`, `finish_front_craft`.

Callers outside `crafting.odin`:
- `apply_player_command`, `Craft_Command` (`src/player_command.odin`): `queue_crafts(..., command.count, makers, state.free_crafting)`. `Cancel_Craft_Command` is unchanged.
- `tick_player` (`src/player.odin`): new trailing parameter, `tick_player :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content, players: []Player, index: int, frame: Input_Frame, tick_rate: int, tick: u64, cheat_speed := false, free_crafting := false) -> Player_Events`; its crafting lines become `if finished, finished_free := advance_crafting(&player.crafting, player.inventory, content.recipes, content.items, tick_rate, free_crafting); finished != NO_RECIPE {`, `record_produced_stacks` as today, `record_consumed_stacks` only `if !finished_free`. `simulation_tick`'s call (`src/simulation_world.odin`, the `tick_player(... state.cheat_speed)` line) appends `state.free_crafting`.
- `tick_field_session_player` (`src/simulation_field.odin`): the same two lines with `state.free_crafting`.

Rule in force, as the docs will say it: a craft starts under the flag as it is on the tick it reaches the front and starts, and finishes under the rule it started with.
- A queue waiting for input when the flag turns on: on the next tick `advance_crafting` starts the front free (`waiting_for` cleared), and every later craft starts free while the flag stays on.
- A craft started free when the flag turns off: finishes free, outputs land, nothing taken, no consumption recorded; cancelling it returns nothing.
- A craft started with its ingredients taken when the flag turns on: finishes as today (consumption recorded); cancelling it returns its ingredients as today.
- Crafts queued free and not started when the flag turns off (the rest of a run, later runs): they start under the paid rule, so a front lacking an ingredient waits for it like any front, and the next queue action's `plan_front_repair` puts makers ahead or leaves it waiting; Cancel last removes them. Questions 3.

### The UI

The screens read the flag through `Screen_Context.free_crafting: bool` (`src/ui_screens.odin`), right after `cheat_speed`, comment "The simulation's developer free crafting, before pending requests." Set in the frame loop beside cheat speed (`src/loop.odin`, `screen_context.free_crafting = session.simulation.free_crafting`). Tests and the audit leave it false.

The predicates, all in the recipe browser, which is also the panel of every crafting station and bench (0196); the inventory screen and `ui_crafting_machines.odin` read none of them:
- `craftable_recipes :: proc(recipes, unlocks, inventory, queue, allocator := context.allocator, makers := HAND_MAKERS, free_crafting := false) -> []bool` (`src/ui_recipe_browser.odin`): passes it to `queue_accepts_crafts`. With the flag every available recipe the makers make is craftable, so the greyed shortage state of `draw_recipe_row` and the "Craftable only" filter follow.
- `recipe_plan_key :: proc(queue, inventory, available: []bool, makers := HAND_MAKERS, free_crafting := false) -> u64`: `front` becomes `[4]u64{u64(queue.started), u64(queue.waiting_for), u64(transmute(u16)makers), u64(free_crafting)}`, so the cached marks and detail are planned again when the flag flips.
- `refresh_craftable_recipes :: proc(plans, recipes, unlocks, inventory, queue, makers := HAND_MAKERS, free_crafting := false)` and `refresh_recipe_detail_plan :: proc(plans, recipes, unlocks, inventory, queue, recipe: int, makers := HAND_MAKERS, free_crafting := false)`: pass it to the key and to `craftable_recipes` / `planned_crafts(..., makers, context.temp_allocator, free_crafting)`.
- `src/ui_recipes.odin`: `recipe_screen`'s `refresh_craftable_recipes(...)` and `recipe_detail_panel`'s `refresh_recipe_detail_plan(...)` append `screen_context.free_crafting`; `queue_checked_crafts`'s `plan_queue_crafts(...)` appends `screen_context.free_crafting`, so Craft, Craft five and the touch row's Craft buttons queue what the tick accepts. With the flag the ingredient rows draw in the Held colour (accent) with the held count ("0 / 5 Stone"), and "Can craft 999" shows. `apply_recipe_craft_input`'s `last_craft_cancels` reads `started_free` from the queue and needs no flag.

### The Developer screen (`src/ui_developer.odin`)

- A new row of its own, the second, under Fly mode, No clip and Cheat speed and above the overlays row: `ui_toggle` at `column_rectangle(row, 3, 0, UI_GAP)`, the row's other two columns empty, so the toggle has the width of the others. A fourth column of the first row was measured and refused: the panel is 1000 units at every audit size (the narrowest safe area, 1280 by 800 at UI scale 1.5, is 1036.8 units wide), content 968; four columns leave a label area of 140 units, which at text scale 1.6 (38.4 units, advance 0.37) holds 9 characters, so "Free crafting" (13) and the existing "Cheat speed" (11) would both be cut. Three columns leave 221 units, 15 characters, so "Free crafting" shows whole at every audit size and text scale.
- `developer_toggles :: proc(state: ^Ui_State, first_row, crafting_row, overlay_row: Ui_Rectangle, screen_context: Screen_Context)`: after the cheat speed toggle, `free_crafting := pending_toggle(screen_context.free_crafting, commands, unconfirmed, player, .Toggle_Free_Crafting)`, then `if ui_toggle(state, column_rectangle(crafting_row, 3, 0, UI_GAP), text("developer_free_crafting"), &free_crafting) { queue_developer_request(state, screen_context, Developer_Request{action = .Toggle_Free_Crafting}) }`, which toasts "Applies when the game resumes" as the others do; the overlays move to `overlay_row`. Its comment becomes "The queued toggles on the first two rows, the frame state overlays on the third". `developer_actions` calls it with three `cut_row(content)`.
- `DEVELOPER_ROW_COUNT` 13 to 14, its comment "Title, three toggle rows, ...". The file's header comment's "(fly mode and cheat speed among them)" gains "free crafting".
- String: `developer_free_crafting = "Free crafting"` in `data/strings/en.sjson`, after `developer_cheat_speed`. `en.sjson` is the only file under `data/strings/`.
- Focus: the row sits in the panel's focus graph like the others; the pointer tests that check the first row (`test_confirm_on_developer_toggles_nothing`, `test_tap_on_developer_toggles_nothing`) are unaffected.

### Tests

`src/crafting_test.odin` (the `Crafting_Test` harness, empty inventory unless said):
- `test_free_crafting_plans_no_ingredients`: `queue_crafts(..., burner_mining_drill, 1, HAND_MAKERS, true)` returns `.None` and the queue holds one run `{burner_mining_drill, 1}` (no gear or plate runs ahead); the same call with `false` returns `.Missing_Ingredients`; with `true`, `steel_furnace` (research, hand) returns `.Locked`, `iron_plate` returns `.Not_Hand_Craftable`, `stone_brick` (stone cutting) with `HAND_MAKERS` returns `.Not_Hand_Craftable`.
- `test_free_crafting_takes_nothing`: with the flag, queue `burner_mining_drill` and advance `recipe_ticks(drill, HAND_CRAFT_SPEED_PERCENT, TEST_TICK_RATE)` ticks of `advance_crafting(..., true)`: one drill, the inventory otherwise empty, the last call returns `(drill recipe, true)`. Then 5 stone held, `stone_furnace` queued and run free: one furnace and still 5 stone.
- `test_a_waiting_front_starts_when_free_crafting_turns_on`: 2 logs, 2 planks queued, the logs removed, 5 paid ticks: `craft_queue_waits_for_input`; one tick with the flag: `started`, `started_free`, `waiting_for == NO_ITEM`; run both crafts free: 8 planks, 0 logs, count 0.
- `test_a_craft_finishes_under_the_rule_it_started_with`: (a) a plank queued free with no log, one free tick, then 29 paid ticks: 4 planks, the finishing call returns `finished_free` true; (b) one log, a plank queued paid, one paid tick (the log taken), then 29 free ticks: 4 planks, `finished_free` false; (c) a plank queued free and started free in a one slot inventory filled with a stone: `last_craft_cancels` true, `cancel_last_craft` true, the inventory still one stone and no log.
- `test_craft_queue_saves_runs_and_reads_the_old_layout` (extended): the saved queue also has `started = true, started_free = true`, and `read == queue` still holds after the round trip; the old layout's read still equals `make_craft_queue()`, so `started_free` loads false.

`src/developer_test.odin`:
- `test_developer_toggles_free_crafting`: as `test_developer_toggles_cheat_speed`: `pending_toggle` flips for `.Toggle_Free_Crafting` and not for `.Toggle_Cheat_Speed`; the request applied twice sets and clears `simulation.free_crafting`; with the flag on, `lockstep_state_hash` differs from the hash with it off; `make_reloaded_simulation(simulation, content, test_game_config())` keeps it on (destroyed after).
- `test_free_crafting_crafts_from_nothing`: `make_developer_test_simulation`, the player's inventory cleared, the toggle applied; a `Craft_Command{burner_mining_drill, 1}` applied, then `simulation_tick(&simulation, content, {})` for the recipe's ticks plus one: one drill held, `records.statistics.consumed` of iron plate, iron gear and stone furnace 0, `produced` of the drill 1; a `steel_furnace` command (locked) and a `stone_brick` command (no station open) leave `crafting.count` 0; 5 stone held and a `stone_furnace` crafted: the stone stays 5; the toggle applied again and a `burner_mining_drill` command with the stone only: refused, `crafting.count` 0 (the couch check's last step).

`src/lockstep_test.odin`:
- `test_free_crafting_toggled_on_one_machine_keeps_the_hash`: two `make_lockstep_test_machine` (players 0 and 1, windows 3 and 2, chunk set off), player 1's inventory cleared on both; at frame 10 the first machine queues `Developer_Request{action = .Toggle_Free_Crafting}` for player 0, at frame 30 the second queues `Craft_Command{burner_mining_drill, 1}` for player 1; the loop of `test_two_simulations_fed_the_same_records_keep_the_same_hash` (inputs from `lockstep_test_input`, `relay_in_process`, `run_lockstep_test_ticks`) until both reach tick 600, the hashes compared at every due tick (at least one compared) and at the end; on both machines `free_crafting` is true and player 1 holds one drill.

`src/session_network_test.odin`:
- `test_the_join_snapshot_carries_free_crafting`: a host from `make_lockstep_test_machine(content, &generator, 0, 0)` with `free_crafting = true`; `encode_join_snapshot`, `decode_join_snapshot` ok and `snapshot.free_crafting` true; adopted into a `make_save_test_simulation` simulation with a `make_single_player_lockstep` lockstep: its `free_crafting` true (both destroyed after).

`src/ui_recipe_browser_test.odin`:
- `test_free_crafting_marks_every_unlocked_recipe_craftable`: empty inventory; `craftable_recipes(..., context.temp_allocator, HAND_MAKERS, true)[index] == (available[index] && .Hand in made_in)` for every recipe, and `burner_mining_drill` is false without the flag; `recipe_plan_key` differs between `false` and `true`; `planned_crafts(..., burner_mining_drill, HAND_MAKERS, context.temp_allocator, true)` has count `PLANNED_CRAFT_COUNT_LIMIT` and every input `.Held`.

`src/ui_pointer_test.odin`:
- `test_the_free_crafting_toggle_queues_its_request`: `open_pause_menu`, `.Developer` pushed, a frame; `state.requested_focus = ui_hash(ui_hash(0, "developer", -1), text("developer_free_crafting"), -1)`, a gamepad frame, then a confirm frame (as `test_confirm_on_developer_toggles_nothing`): `audit.simulation.player_commands` holds one `Developer_Request` whose action is `.Toggle_Free_Crafting`, and `state.toasts` ends with the text of `developer_applies_on_resume`.

UI audit: the existing `developer` case (`src/ui_audit_test.odin`, every size and text scale, focus walked) draws the new row; no new case, none made obsolete. It must pass unchanged.

### Docs

- `doc/developer_tools.md`, Developer screen: the table's Toggles row becomes "Fly mode; no clip (0112: flight passes through blocks); cheat speed (0044, 0087); below them, on a row of its own, free crafting (0234)". After the Cheat speed bullet add: "- Free crafting (0234): every craft the player orders, by hand, at a station or at a bench, is accepted whatever the inventory holds and takes nothing; the recipe browser marks every unlocked recipe of the makers craftable. It unlocks nothing (Unlock all does) and keeps the recipe's time and the station rule ([content.md](content.md), Hand crafting). A simulation flag like cheat speed: not saved, in the state hash and the join snapshot."
- `doc/content.md`, Hand crafting, a last bullet: "- Free crafting (0234, `Simulation_State.free_crafting`, the Developer screen): the plan charges no ingredient and queues no intermediate (`Craft_Plan.free_crafting`), so only the unlock, the maker and the queue's capacity refuse; a front craft starts without taking anything (`Craft_Queue.started_free`), finishes recording its products and no consumption, and cancelled gives nothing back. A craft finishes under the rule it started with: a front waiting for an ingredient starts on the first tick with the flag on, a craft that took its ingredients finishes as before, and crafts queued free that have not started when the flag turns off wait for their ingredients like any front. `started_free` is read by name, so a save from before 0234 loads it false; no remap, no log line."
- `doc/architecture.md`: the State hash bullet's "`simulation_state_hash`, cheat speed and the saved blocks" becomes "`simulation_state_hash`, cheat speed, free crafting and the saved blocks"; the bullet "Cheat speed is a simulation flag, not saved" becomes "Cheat speed and free crafting (0234) are simulation flags, not saved; the join snapshot carries both ([developer_tools.md](developer_tools.md))."
- `doc/log/2026-10-04.md`, appended:

```
## Free crafting on the Developer screen (0234)

Tags: developer, crafting, ui, lockstep, save

- A world flag beside cheat speed, not a player's: the session shares one recipe browser rule, and the flag is hashed, carried in the join snapshot and not saved exactly as cheat speed is. The request is a `Developer_Action` appended last, so no older value moves.
- A craft keeps the rule it started with (`Craft_Queue.started_free`, saved by name, an old save loads false): cancelling a free craft would otherwise refund ingredients it never took, and a paid craft finishing free would lose them. Crafts queued free that have not started when the flag turns off wait for their ingredients; a per run flag would keep them free but was not worth a second rule.
- A free craft records its products and no consumption, so the production statistics never show ingredients that were not used. Its products count as obtained like any item, so a discovery recipe can unlock through them, as through Give item.
- The toggle has a row of its own: four toggles in the first row cut "Free crafting" and "Cheat speed" at text scale 1.6 at every audit size.
```

### Hand-back check

- Changed save layout: `Craft_Queue.started_free` is new; the codec reads by name, an old save loads false, which is the right value; covered by the extended `test_craft_queue_saves_runs_and_reads_the_old_layout`, named in `doc/content.md` and the log. No other layout changes (the flag is not saved).
- Shared budget: the hand queue's `HAND_CRAFT_QUEUE_RUNS` still refuses with `.Queue_Full`; a free front never blocks the queue (it starts at once), so nothing waits behind it longer than before.
- UI audit: no case made obsolete; the `developer` case covers the new row.
- Tests use the in-memory simulations and the audit only; nothing touches the state directory.
- The other lines (memory freed in a frame, `.tmp` writes, start up loads, parsed numbers, unbounded lists) do not apply: no file, memory or parsed text changes.

### Questions answered

- Where the flag lives: per world, beside `cheat_speed` (above).
- Which UI predicates: only the recipe browser's three (`craftable_recipes`, `refresh_recipe_detail_plan` through `planned_crafts`, `queue_checked_crafts` through `plan_queue_crafts`) plus their cache key; station and bench panels are the browser.
- How "a run started free finishes free" maps on the code: the queue starts crafts one at a time, so the unit that keeps its rule is the craft in progress (the front craft), not the whole run (Questions 3).
- Statistics: products recorded, consumption not (needs `advance_crafting`'s second result).
- The row: a second row, column 0 of 3 (measured above).

### Questions for the main agent

1. No socket command `free_crafting on|off` and no `query player` line. The couch check runs through the screen; the socket would let a test or `tools/moc` drive it. Add it, or leave it out as now?
2. Items made free count as obtained, so a discovery recipe can unlock through a free craft (as through Give item). The user said "It doesnt unlock anything new"; I read that as "the toggle does not unlock recipes". Accept, or should free outputs skip the obtained scan (that would need the obtained record to know where an item came from, a much bigger change)?
3. Crafts queued free and not yet started when the flag turns off wait for their ingredients. A per run flag would make them finish free as queued, at the cost of a second saved field per run. Keep the per craft rule?

### Commands (implementer, in the item's worktree)

- `taskset -c 8-15 nice -n 10 ./build.sh check`
- `taskset -c 8-15 nice -n 10 ./build.sh check-android`
- `taskset -c 8-15 nice -n 10 ./build.sh test`
- `taskset -c 8-15 nice -n 10 python3 tools/check_docs.py`
- `taskset -c 8-15 nice -n 10 python3 tools/code_graph.py --check doc/code_map.md`

### Decisions at the approval (main agent, 2026-10-04)

1. The flag per world beside `cheat_speed`, not saved, in the lockstep hash and the join snapshot; `Craft_Queue.started_free` as a saved field read by name (an old save loads it false); the toggle as the first column of a new second row (four columns would cut the labels at text scale 1.6); the per run rule (a run started free finishes free, a run started with its inputs taken finishes as today, a craft queued free but not started when the toggle turns off waits for its ingredients): approved as specified.
2. Question 1: the socket gets `free_crafting <on|off>` beside `cheat_speed <on|off>` (`command.odin`: the help line, the command list, the toggle case and the state reader), with the same test shape as cheat speed's, so a headless session and the dev kits can drive it.
3. Question 2: items made free count as obtained, so a discovery recipe unlocks through them as it does through Give item: accepted, it is a cheat.
4. Question 3: the rule per run as specified: accepted.
