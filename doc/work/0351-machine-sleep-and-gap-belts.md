# 0351: Machine sleep and gap belts

Status: designed (2026-11-11)

Every entity ticks every tick, and a belt moves every item every tick (`work/performance_research_0340.md`, 2.5). The user (2026-11-11): "Decrease entity update loop for entities that are not provable to be interacted by anything in the coming short while". Under the lockstep an entity may skip ticks only when its state afterwards is provably the same as if it had ticked, decided from simulation state alone, never from a camera. Little today (0.27 ms a tick at 5,121 entities), the tick's largest item at M14's factory sizes.

## Goal

A factory's tick costs what is active in it, with every state hash equal to the always ticking game's.

## Controls

None.

## Change

- Wake lists: a machine with nothing to do leaves the active list and waits on what it lacks (a slot, a lane, a network), and a change there wakes it.
- Catch-up in closed form: a machine mid craft with steady inputs and power sleeps to the tick its craft ends; the per tick statistics accrue the same way, and a brownout change wakes its network.
- Networks whose members all sleep with an unchanged balance sleep as one.
- Belts store the gaps between items, as Factorio does, so a flowing line moves its end gaps only.
- The save's layout, if it changes, loads an old save.

## Verify

- The checks and the suite, with a reference test: the state hash at every tick equals the always ticking reference's over the benchmark's factory and the dev kits.
- The night's benchmark table before and after, and the tick's share in 0342's factory views.

## Specification (design, 2026-11-11)

Builds on 0342 (`Tick_Section`, its report's line counts): land after it. Part A is the machine sleep (the Change list's first three points), part B the gap lanes (the fourth). Neither needs the other: A marks lines changed through today's lanes, B keeps the marks.

### The rule

- Exact sleep: a sleeper's fields, once settled, equal the always ticking game's after every tick. So sleep state is derived: never saved, never hashed, and two peers may hold different sleep states. A load or a join starts with everything awake. A missed wake is therefore a desync against a joiner, not only a stuck machine; the reference tests are the proof.
- An entity may fall asleep only right after its own normal tick in its loop, decided from simulation state. Three modes:
  - `Waiting`: its next step changes nothing (a fixed point) until something it reads changes. Woken by a change of its own slots, of what it watches, of its satisfaction, or a wake of all.
  - `Idle_Inserter`: `Waiting`, except each tick adds one to `idle_streak` and to `inserter_idle_ticks`; also woken by a timer at its idle minute.
  - `Work`: its next n ticks change only counters by known amounts (fuel joules, progress, phase or bored ticks, power credit, wear ticks). A timer wakes it at the first tick whose step may differ (the wake tick). It ignores changes to its own slots, which cannot alter those ticks (the proofs below), and is woken by a satisfaction change.
- Settling applies the closed form through a tick without waking. Waking settles, removes the watches and clears the bit; the entity then runs normally from its next loop visit.
- Sleep: inserters, drills without fluid ports, furnaces, crafting machines (`Work`; `Waiting` only without fluid ports). Never: labs (their step reads the research state, which every lab and the queue change any tick; few per factory), lamps (one comparison a tick; their light sync is skipped instead), fluid machines and generators (the networks run every tick, the user 2026-11-11), launch pads, core sample drills, splitters and belts (part B makes a lane cheap instead).

### Per kind

T is the tick just run, n its steady ticks after it, the wake tick T + n + 1. p = `fuel_joules_per_tick`, σ the satisfaction, c the credit. Wear, when `machine_wears` and `bare_ground_life_ticks` > 0: w = life − `wear_ticks`; otherwise no limit.

Inserter (alive, not broken):

| After its tick | Mode | Watches | n |
|---|---|---|---|
| `Unpowered` | Waiting | none | |
| `At_Pickup`, `No_Filter` | Waiting | none | |
| `At_Pickup`, `Idle` | Idle_Inserter | source, target | ((minute − `idle_streak`) mod 2³², 0 read as 2³²) − 1 |
| `At_Pickup`, `No_Fuel` | Waiting | source, target | |
| `At_Drop`, `Waiting_For_Room` | Waiting | target | |
| swinging, `No_Fuel` | Waiting | none | |
| swinging, `Moving`, burner, fuel ≥ p | Work | none | min(swing − `phase_ticks` − 1, fuel / p, w − 1) |
| swinging, `Moving`, electric | Work | none | min(`ticks_until_step`(c, σ, swing − `phase_ticks`) − 1, w − 1) |

Source and target are `entity_at` of the pickup and drop cells; a belt stands for its line. minute = `INSERTER_IDLE_MINUTE_SECONDS` × tick rate (the wrap keeps the per tick u32 add exact), swing = `inserter_swing_ticks` of the phase. Wear counts every `Moving` tick, paid or not. Proof of Work: the swing step reads only its own fuel buffer, credit and phase ticks; a fuel item fed into its slot matters only at the refuel tick, which is a wake tick.

Drill (alive, not broken, `fluid_port_count` 0):

| After its tick | Mode | Watches | n |
|---|---|---|---|
| held not empty, `Waiting_For_Room`, `No_Output` or `Output_Refused` | Waiting | drop target | |
| held empty, `Vein_Exhausted` | Waiting | none | |
| `No_Fuel`, `Unpowered` | Waiting | none | |
| held empty, `Mining` or `Boring` equal to `drill_activity` now, burner, fuel ≥ p | Work | none | Mining: min(fuel / p, cycle − progress − 1, w − 1); Boring: min(fuel / p, boring − bored, w − 1) |
| the same, electric | Work | none | Mining: min(`ticks_until_step`(c, σ, cycle − progress), `ticks_until_step`(c, σ, w)) − 1; Boring: min(`ticks_until_step`(c, σ, boring − bored), `ticks_until_step`(c, σ, w) − 1) |

cycle = `drill_active_cycle_ticks(machine, false, rate)`, boring = `drill_boring_ticks`. Electric wear counts per paid step, burner per tick. A held bonus unit (`Mining` with held not empty) stays awake. The steady step reads the vein only for exhaustion, and another drill exhausting it wakes the drill.

Furnace:

| After its tick | Mode | n |
|---|---|---|
| `Idle`, `Output_Full`, `No_Fuel` | Waiting | |
| `Burning`, `furnace_recipe(input)` == `recipe`, `furnace_has_room`, fuel ≥ p | Work | min(fuel / p, `recipe_ticks` − progress − 1, w − 1) |

Proof of Work: between its own finishes the input only grows (the same item, `furnace_accepting_slot`) and the outputs only shrink (`giving_slots`), so the recipe and the room hold.

Crafting machine:

| After its tick | Mode | n |
|---|---|---|
| `working`, `Working`, burner, fuel ≥ p | Work | min(fuel / p, total − progress − 1, w − 1) |
| `working`, `Working`, electric | Work | min(`ticks_until_step`(c, σ, total − progress), `ticks_until_step`(c, σ, w)) − 1 |
| no fluid ports, any other state | Waiting | |

total = `recipe_ticks(recipe, speed_percent, rate)`. A started craft took its inputs and fluids, so neither slots nor ports are read before its finish. A Waiting machine with ports would read buffers the network writes every tick, so it stays awake.

Sleep only when n + 1 ≥ `MINIMUM_SLEEP_TICKS` (4: a sleep costs about one machine tick of bookkeeping), never under `reference`, and never while a watched line changed this tick (its `changed_tick` equals the schedule's tick: a flowing belt would wake it at once). Waiting has no n.

Settling k ticks: burner Work: fuel −= k·p, the counter += k, wear += k. Electric Work: (s, c′) = `power_steps_after`(c, σ, k): credit = c′, the counter += s, wear += k for an inserter, s for a drill or crafting machine. Idle_Inserter: `idle_streak` += u32(k), wrapping. Waiting: nothing. The counter is `phase_ticks`, `progress_ticks` or `bored_ticks` by the state. Every other statistic of these kinds changes only on a lit item, a finish, an output or a state change, all on normal ticks; the output rate rings are lazy already.

### Wakes

- Own slots and watched entities: `entity_insert` and `entity_extract` when they moved anything; after its tick, every drill, inserter, furnace, crafting machine, lab, launch pad and fluid machine whose slots changed in it (`note_slots_changed` on the `before` copy the loops keep); `apply_launch_requests` on a launched pad; `tick_quests` on the reward target when its slots changed (copy before, compare after). Any other write of an entity's slots outside a command must call `note_entity_changed`: the implementer checks every write site of `entity_slots(`.
- Lines: every write of a lane sets `Belt_Line.changed` (an item moved, a hand off on both lines, a side load, a splitter pass on both lines, a drop off an end, an insert, an extract, the planet preview's insert). `notify_changed_lines` runs after `drop_items_off_belt_ends` and after `tick_loose_items`; `belt_insert_item` and `belt_extract_item` call `note_line_changed` at once, since they run inside the Drills and Inserters loops, where the loop position decides the settle.
- Satisfaction: `deliver_power_satisfaction` wakes a sleeper whose satisfaction changes, settling with the old value through T − 1, then writes the new.
- Veins: `exhaust_vein` calls `wake_drills_on_vein`.
- Timers: due timers wake at the start of the entity tick.
- All: `wake_all_entities` first in `add_entity`, `remove_entity`, `add_belt`, `remove_belt`, `reshape_belt`, `add_splitter`, `remove_splitter`, `rotate_splitter`, the belt run adds and removes, `rebuild_belt_lines`, `rebuild_fluid_networks`, `rebuild_electric_networks` (so `toggle_power_switch` too); `apply_player_command` when `player_command_touches_entities`; `serve_command_request`; `apply_item_use` after `read_schematic` returns a recipe (a found alternate changes what furnaces and fixed machines run). Settings and recipes change only through these.

### Settle target and the idle count

- `settle_target` = the schedule's tick when the entity's loop already passed it this tick (phase `After`, a later phase than its own, or its own with index ≤ `loop_index`), else the tick − 1. Loops visit through `next_awake_index`, which rereads the bits, so an entity woken ahead of the loop runs normally this tick.
- `inserter_idle_ticks` stays eager: at the end of the Inserters loop it gains `idle_sleepers − idle_fresh + idle_owed`, then the last two are zeroed. Falling asleep as Idle_Inserter during the Inserters phase adds one to `idle_fresh` (its own tick counted). A wake of an Idle_Inserter: `idle_sleepers` − 1; during the Inserters phase, `idle_fresh` − 1 when its `since` is this tick, `idle_owed` + 1 when `since` is older and the target is this tick.

### Who settles before reading

`write_world_state` (the save, the reload's encode, the state hash, the join snapshot, 0345's snapshot); `update_session` after the frame's ticks when it ran any, and `loop_planet_preview.odin` after its tick (the renderer, panels, HUD and sounds read settled counters, one closed form per sleeper per frame); `execute_command` before any command; `warm_up_benchmark` before `benchmark_idle_machines`; the tests' tick helpers.

### Power and fluid seams (for 0355 and 0356)

- Power: a sleeper stays a participant every tick. `collect_electric_participants` appends its offer and network frozen at sleep (`Entity_Sleep.offer`, `.network`, computed by the same `*_wants_power` and `entity_network`), skipping the wants and the map lookup. Every consumer's satisfaction is written through `deliver_power_satisfaction`. Whatever replaces the balance keeps those two: read the participants' offers each tick, write satisfaction through that procedure. The offers of Work sleepers depend only on fields their steady ticks hold (phase, held, working); those of Waiting sleepers on inputs that wake them.
- Fluids: no hook. A sleeper's port buffers stay nodes the network reads and writes every tick; no Work step reads them and no entity with ports sleeps Waiting. 0356 may rewrite the network freely if it never writes item slots or craft fields; letting a machine with ports wait asleep needs a wake on a port change.

### Files and procedures

`src/entity_sleep.odin`, new, simulation cluster:

- `MINIMUM_SLEEP_TICKS :: 4`. `Sleep_Mode :: enum u8 {Awake, Waiting, Idle_Inserter, Work}`, `Sleep_Wear :: enum u8 {None, Per_Tick, Per_Step}`, `Sleep_Phase :: enum u8 {Before, Belts, Power, Drills, Inserters, Furnaces, Assemblers, Later, After}`, `Sleep_Timer :: struct {tick: u64, handle: Entity_Handle}`.
- `Entity_Sleep :: struct {mode: Sleep_Mode, electric: bool, wear: Sleep_Wear, since, settled, wake_tick: u64, fuel_per_tick: u32, offer: u64, network: int, watched: [2]Entity_Handle}`: `wake_tick` 0 for none, `watched` `NO_ENTITY` for none.
- `Entity_Schedule :: struct {tick: u64, phase: Sleep_Phase, loop_index: int, asleep: [Entity_Kind][dynamic]u64, sleep: [Entity_Kind][dynamic]Entity_Sleep, sleeper_count: int, timers: priority_queue.Priority_Queue(Sleep_Timer), stale_timers: int, watchers: map[Entity_Handle][dynamic]Entity_Handle, idle_sleepers, idle_fresh, idle_owed: u64, lights_synced: bool, kinds_slept: bit_set[Entity_Kind], reference: bool, allocator: runtime.Allocator}`. `reference` true means nothing sleeps, lights sync every tick and lanes move point by point: the always ticking game, for tests. The per entity data lives here, not on `Entity_Common`, so the pools and the loops' `before` copies keep their size. Timers order by tick, then kind and index.
- `Entities` gains `schedule: Entity_Schedule`; `destroy_entities` calls `destroy_entity_schedule`.

| Procedure | Does | Called from |
|---|---|---|
| `next_awake_index :: proc(schedule: ^Entity_Schedule, kind: Entity_Kind, from, count: int) -> int` | first index ≥ from with a clear bit (whole words skipped), else count | the drill, inserter, furnace and crafting machine loops |
| `entity_is_asleep :: proc(schedule: ^Entity_Schedule, handle: Entity_Handle) -> bool` | the bit | everywhere a sleeper is told apart |
| `settle_target :: proc(schedule: ^Entity_Schedule, handle: Entity_Handle) -> u64` | above | settling |
| `power_steps_after :: proc(credit, satisfaction: u32, ticks: u64) -> (steps: u64, credit_after: u32)` | (c + ticks·σ) / `POWER_FULL` and the rest: `take_power_step` ticks times, since c < `POWER_FULL` ≥ σ | settling |
| `ticks_until_step :: proc(credit, satisfaction: u32, steps: u64) -> u64` | ⌈(steps·`POWER_FULL` − c) / σ⌉, the first tick paying step `steps`; σ, steps ≥ 1 | the plans |
| `plan_inserter_sleep :: proc(tick_context: Entity_Tick_Context, inserter: Inserter, tick: u64) -> Entity_Sleep`, `plan_drill_sleep`, `plan_furnace_sleep`, `plan_assembler_sleep` | the tables, pure; `Awake` for no sleep | after the entity's tick in its loop |
| `put_to_sleep :: proc(entities: ^Entities, handle: Entity_Handle, plan: Entity_Sleep)` | refuses as above, else `since` = `settled` = tick, bit, timer, watches (a belt's line's `watchers`, else `watchers`), counts, `kinds_slept` | the loops |
| `settled_inserter :: proc(inserter: Inserter, sleep: Entity_Sleep, ticks: u64) -> Inserter`, `settled_drill`, `settled_furnace`, `settled_assembler` | the closed forms, pure | `settle_entity` |
| `settle_entity :: proc(entities: ^Entities, handle: Entity_Handle)` | through its target | wakes, `settle_sleeping_entities` |
| `settle_sleeping_entities :: proc(entities: ^Entities)` | every sleeper, through the bits | the settle points |
| `wake_entity :: proc(entities: ^Entities, handle: Entity_Handle)` | settle, idle count, unwatch (swap remove from its two lists), clear the bit; the timer stays and counts stale | the wakes |
| `wake_all_entities :: proc(entities: ^Entities)` | every sleeper woken, then the map, the lines' lists and the heap cleared; `lights_synced` false | above |
| `begin_entity_sleep_tick :: proc(entities: ^Entities)` | tick + 1, phase `Before`, pops due timers (drops stale ones: entity awake or another wake tick) and wakes them; rebuilds the heap from the sleepers when `stale_timers` > `sleeper_count` + 64 | first in `tick_entities`, section `Sleep` |
| `note_entity_changed :: proc(entities: ^Entities, handle: Entity_Handle)` | a belt: `note_line_changed`; else the entity itself if asleep `Waiting` or `Idle_Inserter`, and its watchers | the wakes |
| `note_slots_changed :: proc(entities: ^Entities, handle: Entity_Handle, before, after: []Item_Stack)` | `note_entity_changed` when they differ | the loops |
| `note_line_changed :: proc(entities: ^Entities, line: i32)` | wakes and clears the line's watchers, `changed` false, `changed_tick` the schedule's tick | the belts |
| `notify_changed_lines :: proc(entities: ^Entities)` | `note_line_changed` for every changed line | `tick_entities` |
| `wake_drills_on_vein :: proc(entities: ^Entities, vein: Vein_Id)` | every sleeping drill on it | `exhaust_vein` |
| `finish_idle_inserter_ticks :: proc(schedule: ^Entity_Schedule, statistics: ^Statistics)` | the idle count above | after the inserter loop |
| `destroy_entity_schedule :: proc(schedule: ^Entity_Schedule)` | frees | `destroy_entities` |

Changes elsewhere:

- `entity.odin` `tick_entities`: `begin_entity_sleep_tick`; the phase set before each section; the drill, inserter and furnace loops as `for index := next_awake_index(...); index < count; index = next_awake_index(..., index + 1)` with `loop_index`; after an entity's tick, `note_slots_changed` then `put_to_sleep(plan_*)`; `notify_changed_lines` after `drop_items_off_belt_ends` and after `tick_loose_items`; `finish_idle_inserter_ticks` after the inserter loop; phase `After` at the end. `tick_assemblers` the same with phase `Assemblers`; `tick_labs`, `tick_launch_pads`, `tick_fluids` call `note_slots_changed` per entity.
- `power_network.odin`: the frozen offers in `collect_electric_participants` and `collect_crafting_participants`; `deliver_power_satisfaction :: proc(entities: ^Entities, handle: Entity_Handle, satisfaction: u32)` in `apply_electric_balance`.
- `power_machine.odin` `tick_lamps`: a lit flip sets `lights_synced` false. `simulation_world.odin` `tick_entities_on_world`: syncs the lights only when not synced or under `reference`, then marks them synced.
- `belt.odin`: `Belt_Line` gains `watchers: [dynamic]Entity_Handle`, `changed: bool`, `changed_tick: u64`; freed with the line. `belt_movement.odin`: `advance_lane_items` and `advance_loop_lane` return whether anything moved; `tick_belt_network` gains `reference := false` (part B).
- `save_state.odin` `write_world_state`: `settle_sleeping_entities` first. `command.odin`: settle first in `execute_command`, wake all first in `serve_command_request`. `player_command.odin`: `player_command_touches_entities :: proc(command: Player_Command) -> bool`, false for `Research_Command`, `Craft_Command`, `Cancel_Craft_Command`, `Hotbar_Slot_Command`, `Foundation_Block_Command`, `Close_Machine_Command`, `Add_Player_Command`, `Chunk_Ready_Command`, `Field_Chunk_Ready_Command`. `loop.odin`, `loop_planet_preview.odin`, `benchmark_factory.odin`, `prospecting.odin`, `drill.odin`, `item_transfer.odin`, `quest_runtime.odin`, `launch_pad.odin`: as listed above.
- `tick_profile.odin`: `Tick_Section.Sleep` first of the entity sections ("the due timers' wakes"). 0342's report gains a tick line (its test's counts become 29 tick lines and 122 lines if 0342 lands with 28 and 121); the F3 machines group covers Sleep through Outcrops_And_Crates.

### Part B: gap lanes

- `belt.odin`: `Lane_Item :: struct {item: Item_Id, gap: i32}` (the gap to the item ahead, the front's 0); `Lane_Point :: struct {item: Item_Id, position: i32}` (today's `Lane_Item`, for readers); `Belt_Lane_Items :: struct {items: [dynamic]Lane_Item, front, back, compressed, overlaps: i32}` (items back first, front last as today; `front` and `back` are positions; `compressed` counts the items right behind the front with gap exactly `BELT_ITEM_SPACING`; `overlaps` the gaps below it); `Belt_Line.lanes: [Belt_Lane]Belt_Lane_Items`.
- `src/belt_lane.odin`, new, simulation cluster:
  - `lane_points :: proc(lane: Belt_Lane_Items, allocator := context.temp_allocator) -> []Lane_Point`, back first;
  - `lane_from_points :: proc(lane: ^Belt_Lane_Items, points: []Lane_Point)`: replaces the lane, points ascending with ties kept in order;
  - `lane_front_point :: proc(lane: Belt_Lane_Items) -> (point: Lane_Point, found: bool)`;
  - `lane_pop_front :: proc(lane: ^Belt_Lane_Items) -> Lane_Point`, O(1) (`compressed` − 1 when positive);
  - `lane_push_back :: proc(lane: ^Belt_Lane_Items, item: Item_Id, position: i32)`: position ≤ back, asserted;
  - `lane_insert_point :: proc(lane: ^Belt_Lane_Items, item: Item_Id, position: i32) -> bool`: today's `lane_insert` and its spacing rule;
  - `lane_has_room_at :: proc(lane: Belt_Lane_Items, position: i32) -> bool`;
  - `lane_remove_at :: proc(lane: ^Belt_Lane_Items, index: int) -> Item_Id`: the gap behind absorbs the removed one's;
  - `refresh_lane_caches :: proc(lane: ^Belt_Lane_Items)`: `back`, `compressed` and `overlaps` from `front` and the gaps;
  - `advance_gap_lane :: proc(lane: ^Belt_Lane_Items, speed, front_limit: i32) -> (moved: bool, visited: int)`;
  - `advance_lane_points :: proc(points: []Lane_Point, speed, front_limit: i32)`: today's `advance_lane_items`, kept as the reference.
- The move is today's rule (position′ = max(position, min(position + speed, limit)), limit = the position′ ahead − spacing) as movements: the front moves m = clamp(front_limit − front, 0, speed); each item behind moves m = clamp(gap − spacing + m ahead, 0, speed) and its gap gains m ahead − m. Exact shortcuts: the compressed run moves the front's m with gaps unchanged, so it is skipped; once m ahead equals speed with `overlaps` 0, everything behind moves speed with gaps unchanged, so the walk stops; `back` gains the last movement. `compressed` then grows while the item behind the run has gap spacing (amortised, it never shrinks within a tick); `overlaps` drops when a gap reaches spacing (a gap never falls below it once there).
- Call sites: `advance_belt_line` (loops materialise points, run `advance_loop_lane`, write back; under `reference` every lane goes through `advance_lane_points`), the hand offs, `lane_front_limit` (the next lane's `back`), `lane_front_at_dead_end`, `drop_items_off_belt_ends`, `belt_insert_item`, `belt_has_room`, `belt_extract_item`, `nearest_belt_item_excluding` (positions walked from the front), `splitter.odin` (`output_landing` and `splitter_input_front_limit` read `back`; the pass pops and pushes back; `splitter_held_stacks`), `belt.odin` (`belt_cell_items`, `restore_belt_items` sorting points per lane then `lane_from_points`, `belt_block_stacks`), `render_belts.odin`, `render_belt_runs.odin` (`draw_belt_run_item` takes a `Lane_Point`), `loop_planet_preview_runs.odin`, and the tests' lane reads through `lane_points`. The save's `Belt_Cell_Item` records are unchanged.
- Correct whether lines in unloaded areas run or stop: a representation, deciding neither.

### Save, records and data

No layout change, no remap, no log line. `Lane_Item` changes in memory only. No data keys: `MINIMUM_SLEEP_TICKS` is a constant.

### Tests

- `entity_sleep_test.odin`: `Sleep_Pair :: struct {worlds: [2]World, records: [2]Game_Records}` (the second under `reference`), `make_sleep_pair`, `tick_sleep_pair :: proc(t: ^testing.T, pair: ^Sleep_Pair, content: Simulation_Content, ticks: int, before_tick: proc(world: ^World, content: Simulation_Content, tick: int) = nil) -> bool` (both through `tick_entities_on_world`, the digest equal after every tick, else an error naming the first tick), digest = `write_world_state` then `write_machine_wear_table` (wear is `save:"-"` in the pools).
- `test_sleep_matches_reference_factory` (`// slow`): the size 1 benchmark factory built twice as `run_factory_benchmark` builds it, the second under `reference`; 7200 ticks; `simulation_state_hash` equal after every tick; `kinds_slept` holds Inserter, Drill, Furnace and Assembler.
- `test_sleep_matches_reference_burner_line`: the chapter kits' machines in a block world: two burner mining drills on one finite vein (sized so one exhausts it near tick 6000 while the other sleeps), dropping into a stone furnace and a chest; burner inserters feeding coal from a chest holding too little for the run, and taking plates into a chest that fills; 10800 ticks, equal every tick.
- `test_sleep_matches_reference_in_a_brownout`: `make_drill_power_test`'s world plus an electric inserter between two chests and an electric crafting machine loaded for many crafts on the same pole; the engine's offer set before each tick (the `tick_with_engine_offer` poke) through 1500, 750, 333, 1, 0, 1500 J, 600 ticks each; equal every tick.
- `test_sleep_matches_reference_on_bare_ground`: `make_block_wear_test` worlds; an unfounded burner furnace smelting, an unfounded electric drill at half power, an unfounded burner inserter moving plates; `WEAR_TEST_LIFE_TICKS` × 2 ticks; equal every tick, `len(breakdowns)` equal after every tick.
- `test_the_idle_minute_counts_on_its_tick`: an inserter between two empty chests, a pair, 3700 ticks: equal every tick, `inserters_idle_a_minute` 1 from tick 3600 in both, the sleeping one asleep at ticks 100 and 3000.
- `test_a_woken_idle_inserter_keeps_the_idle_count`: an idle inserter watching a chest that a second inserter fills, once with the idle one first in the pool and once second; 600 ticks each, equal every tick.
- `test_a_load_starts_awake_and_hashes_alike`: `make_wear_test` with a furnace smelting and an inserter between chests, 300 ticks, encoded and decoded into a second simulation as `test_the_wear_round_trips_a_save_and_an_older_save_loads_unworn` does, both ticked 600 ticks: `simulation_state_hash` equal after every tick (the joiner).
- `test_power_steps_after_matches_take_power_step`: credits 0 to 999 by 37, σ in {1, 7, 333, 500, 999, 1000}, ticks 0 to 2000 by 7: steps and credit equal iterating `take_power_step`.
- `test_ticks_until_step_is_the_first_paying_tick`: the same grid, steps 1 to 50.
- `test_settle_target_follows_the_loop_order`: every phase against a drill, an inserter, a furnace and a crafting machine at indexes below, at and above `loop_index`.
- `test_wake_all_leaves_nothing_asleep`: after `wake_all_entities` no bit, list, timer or count remains and the digest equals the reference's.
- `test_nothing_sleeps_under_reference`: the burner line under `reference` for 600 ticks: `sleeper_count` 0, `kinds_slept` empty.
- Part B (`belt_lane_test.odin`): `test_gap_lane_moves_like_points` (200 seeded lanes of 0 to 40 items, gaps from {0, 1, 63, 64, 65, 128, 320}, speeds {1, 8, 16, 64}, front limits from below the front to far ahead, 300 ticks: points equal `advance_lane_points` after every tick, caches equal `refresh_lane_caches`); `test_gap_lane_writes_keep_the_caches` (seeded pops, pushes, inserts and removes); `test_a_backed_up_and_a_flowing_lane_visit_few_items` (1000 items compressed against a dead end, and 1000 spaced 128 under a free front: `visited` at most 2 a tick after the first).
- The suite runs with sleep on. The tick helpers `tick_test_entities` (`inserter_test.odin`), `run_test_entities` (`machine_wear_test.odin`) and `run_furnace` (`furnace_test.odin`) call `wake_all_entities` before and `settle_sleeping_entities` after. A test that ticks by itself and pokes or reads counters gets the same two calls. A failure that is neither a poke nor a read is a missed wake: fixed in the code, never in the test. No expected value changes.

### Docs

- `doc/architecture.md`, Simulation: a "Machine sleep (0351)" group: the exactness rule and what follows from it, the modes, what sleeps and what never does with the reasons, the wakes, the settle points, `reference`. Line 145's "(every entity ticks and ...)" becomes "(every entity is simulated, a sleeper in closed form, and ...)". Performance: the reference tests and the `Sleep` section.
- `doc/logistics.md`, Belts: the gap lanes and their cost (a flowing or backed up lane touches its front only), the lines' watchers, linking architecture.md for the sleep.
- `doc/fluids.md`, Balance: frozen offers and `deliver_power_satisfaction`; Fluid networks: a machine with ports sleeps only mid craft.
- `doc/code_map.md`: `entity_sleep.odin` and `belt_lane.odin` under simulation; world's "Reaches into" simulation record + 1 for the settle in `write_world_state` (accepted, 0351); whatever else `code_graph.py --check` reports.

### Hand-back check

- Memory a frame draws from: nothing is freed in the UI pass; `wake_all_entities` frees the watcher lists and rebuilds the heap only inside ticks, commands and structure changes; the frame's settle writes counters only; `lane_points` uses the temp allocator.
- Rate per tick: `power_steps_after` is `take_power_step`'s credit arithmetic in closed form, tested against it.
- Save layout: unchanged (above).
- Shared budget: a sleeper stays a participant every tick with the offer its awake tick would make, so the balance, the generators' shares and the brownout are the always ticking game's; a satisfaction change wakes before the new value is used. The fluid networks see the same buffers. No queue credits.
- A list that grows: watcher lists hold at most two entries per sleeper and empty on wake; the heap is rebuilt when stale entries pass the sleepers plus 64; the bits and the per entity array follow the pools. Nothing drawn.
- Tests: block worlds and in-memory simulations, no state directory.
- File writes, start-up loads, parsed numbers, strings, UI audits: none.

### Decisions on the item's open points

1. "Networks whose members all sleep sleep as one": not done. Generators never sleep (they burn per tick), and power and pipes run everywhere at all times (the user, 2026-11-11); 0355 and 0356 make them cheap. "A brownout change wakes its network" holds as: a changed satisfaction wakes each sleeper that gets it.
2. Catch-up in closed form, O(1) a wake, no replay.
3. The statistics: events only, except `inserter_idle_ticks`, kept eager by count.
4. Presentation: one settle a frame, not settled copies at each read: one call covers renderer, panels, HUD and sounds.
5. Structure changes and entity commands wake everything: simple and safe; finer wakes become an item if 0342's views show building costs.
6. The Verify's "dev kits" are inventories: the burner line test runs their machines.
7. Belts in unloaded areas (undecided, the coordinator 2026-11-11): part B is correct either way; part A's watchers follow lines whatever ticks them.

### Questions to the main agent

1. Do belts run in unloaded areas? If they stop, that is its own item: "unloaded" must come from lockstep state (the simulated chunk set), and a stopped line notes its change when it resumes.
2. Split part B into its own item? It touches about 90 test sites and has its own risk; part A does not need it.
3. Keep `reference` in production code? It is the tests' switch and could give the benchmark a before and after in one build.
4. Every entity command wakes everything: with players at panels in a session, sleep pauses while they click. Accept for now?
5. `record_belt_dead_ends` costs lines × inserters every tick (the Statistics section), unrelated to sleep: a new item?

### Decisions (main agent, 2026-11-11)

1. Question 1 (belts where no player is) is the user's and open: "Jury's still out on the conveyor belts" (`SUGGESTIONS.md`). Part B holds either way.
2. Question 2: Part B is its own item, 0363, implemented from this specification's Part B. This item is Part A.
3. Question 3: the `reference` flag stays in production code, for the paired tests and for a before and after in one build.
4. Question 4: accepted. An entity command wakes everything.
5. Question 5: `record_belt_dead_ends` is 0364.
6. Order: not started before 0342's first table. The user's bar is an early factory of a handful of machines, where the machines' ticks may cost nothing worth this item's risk (a missed wake desyncs a joiner). It is implemented when the tick sections of the factory views, or a larger factory's, show the machines' ticks in the frame, and after 0355 if that item is in flight, since it rewrites the power balance the closed forms stand on.
