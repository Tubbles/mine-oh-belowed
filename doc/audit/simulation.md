# Audit: the simulation cluster

The simulation cluster (work item 0143) is the factory: 16 entity kinds in typed pools, three derived networks, the players, inventories, crafting and the statistics, ticked in a fixed order by `tick_entities` and `simulation_tick`. 34 files and 14132 lines. Its core is plain values in arrays of structs with generational handles, already close to the shape a plugin or a component store needs; the debt is how the kinds are enumerated:

- A kind is enumerated by hand: 17 switches over `Entity_Kind` in 10 files, 83 loops over one named pool in 19 files, and 5 lists naming all 16 pools. A new kind touches about 12 places (section 4).
- The shared parts of the kinds (burner, power draw, fluid ports, progress, item slots) are fields repeated per struct and reached through per kind switches (`participant_power`, `entity_port_buffers`, `entity_slots`); the burner sequence is written five times and its burn fraction five times.
- Every placement or removal rebuilds whole networks from all pools, decided in six places, with no single topology change seam (the world audit's missing cell change seam is its sibling).
- The tick procedures take `^World` to reach simulation records: 136 of the 145 `world.` field reads in the cluster's files are `world.entities`, `world.statistics`, `world.research` and `world.shipments`.
- Verdict of section 7: no ECS. A kind table plus component locations over the existing pools, then shared component structs, removes the switches and the duplicated burner code without touching iteration order, and the first step without touching the save.

## 1. What the cluster is

Rule: the simulation owns what changes per tick in the factory; blocks belong to the world, prototypes to content.

- Responsibilities: entity storage and handles, placement rules and pick up, belts as transport lines, splitters, inserters, drills on veins, furnaces, crafting machines, labs and research, launch pads, fluid machines and fluid networks, electric networks and generators, lamps, loose items, the item transfer interface, players (movement, mining, placing, interaction), inventories and hand crafting, statistics and rate rings.
- Entry procedures: `tick_entities` (`entity.odin:523`, called by `simulation_tick`), per kind ticks `advance_drill`, `advance_inserter`, `advance_furnace`, `tick_assemblers`, `tick_labs`, `tick_launch_pads`, `tick_fluids`, `tick_electric_networks`, `tick_lamps`, `tick_loose_items`; the player `tick_player`.
- Placement and removal: `place_entity_with_player`, `commit_placement` (also the command socket's `place`), `add_entity`, `add_belt`, `add_splitter`, `pick_up_entity`, `remove_entity`, `rotate_targeted_entity`, `remove_for_developer`.
- Transfer verbs: `entity_accepts`, `entity_insert`, `entity_extract`, `entity_offered_items`, `entity_takes_item_kind` (machines), and the screens' verbs in `quick_transfer.odin` and `inventory_interaction.odin` (ui audit, section 3).

| File | Lines | Commits | Purpose |
|---|---|---|---|
| `entity.odin` | 576 | 24 | `Entity_Kind`, `Entity_Handle`, `Entity_Common`, `Entity_Pool`, `Entities`, add and remove, footprints, `tick_entities` |
| `entity_placement.odin` | 432 | 21 | `Placement` rules, `commit_placement`, command placement, rotation, pick up |
| `machine.odin` | 721 | 28 | `Machine_Kind` (25 kinds), `Machine` (46 fields), registry, per kind validation |
| `item_transfer.odin` | 249 | 13 | the transfer interface with its per kind acceptance rules |
| `belt.odin`, `belt_movement.odin`, `belt_placement.odin` | 1439 | 13 | lines and their rebuild, lane movement and belt ends, drag placement |
| `splitter.odin` | 294 | 1 | `Splitter`, round robin, filter, add, remove, rotate |
| `inserter.odin` | 335 | 6 | swing cycle, pick and drop, self feeding |
| `drill.odin` | 491 | 12 | vein draws, boring, revival, output |
| `furnace.odin` | 166 | 7 | `Furnace` and `refuel_from_slot`, the shared burner step |
| `assembler.odin` | 935 | 7 | crafting machines: recipe choice, fluids, energy, insertion limits |
| `recycler.odin` | 128 | 1 | recycle recipes and returns (graph: content) |
| `lab.odin` | 339 | 6 | `Lab`, `Research_State`, units and queueing |
| `launch_pad.odin` | 511 | 3 | assembly stages, launch, shipments |
| `fluid.odin` | 186 | 7 | the fluid registry (content shaped) |
| `fluid_machine.odin`, `machine_fluid_ports.odin` | 772 | 22 | `Pipe`, `Fluid_Machine` (9 machine kinds in one pool), port layouts |
| `fluid_network.odin` | 695 | 9 | segments, connections, per tick flow, head line |
| `power_machine.odin`, `power_network.odin` | 1020 | 19 | `Power_State`, `Pole`, `Lamp`, generators, nodes, memberships, balance |
| `loose_item.odin` | 298 | 2 | stacks lying in cells |
| `player.odin`, `player_interaction.odin`, `player_collision.odin` | 1100 | 46 | `Player`, movement, mining, block placing, collision |
| `player_animation.odin` | 223 | 4 | limb angles, head bob, footsteps |
| `inventory.odin`, `inventory_interaction.odin`, `crafting.odin` | 896 | 15 | `Item_Stack`, `Inventory`, slot clicks, hand crafting queue and planner |
| `statistics.odin` | 868 | 21 | `Statistics`, rate rings, the per kind `record_*` procedures |
| `production_statistics.odin` | 317 | 8 | statistics rows and bottleneck marker colours |
| `quick_transfer.odin` | 526 | 4 | quick move and transfer buttons (ui audit: split) |
| `tick_profile.odin` | 66 | 1 | `Tick_Section`, wall time per system |
| `developer.odin` | 549 | 8 | developer kits and requests |

Verdicts on edge assigned and misplaced files:

- `recycler.odin` (graph: content) is simulation: 9 of its 10 references in come from `assembler.odin`, 1 from `recipe.odin`; its content edges are the recipe tables it reads.
- `schematic.odin` (graph: content) and `prospecting.odin` (graph: world, per the world audit) define entity kinds (`Schematic_Crate`, `Core_Sample_Drill`) and run in the tick; both are simulation.
- `player_animation.odin` (prefix: simulation) is presentation: 18 of its 24 references in come from presentation files and 6 from the loop, none from the simulation.
- `production_statistics.odin` (graph: simulation) is split: `statistics_rows`, `fluid_statistics_rows` and `count_item_machines` are called only by `ui_statistics.odin`; the marker colours only by `render_entities.odin`, `render_fluids.odin` and `sound_events.odin`. The rows are ui view models; the marker colours are the simulation's one "is working" rule and stay with it.
- `inventory_interaction.odin` is split like `quick_transfer.odin`: `Slot_Grid_Kind`, `Active_Slot` and `Distribute_Gesture` are ui state (46 of its 64 references in are ui), `Held_Stack` and the slot verbs are simulation commands.
- `developer.odin` (graph: content): the kit files are content, `serve_developer_requests` and its verbs (`place_for_developer`, `remove_for_developer`) are simulation, as the loop audit says.

## 2. State

Rule: a pool entry is saved as it is; everything derived from pools is rebuilt on load or on a topology change.

`Entities` (`entity.odin:84`, 21 fields):

| Field | Kind | Writers |
|---|---|---|
| 16 pools (`chests` to `launch_pads`) | state, each an `Entity_Pool` of entries plus a free list | `add_entity` and `remove_entity` (player, developer, command socket), the per kind ticks, the screens (ui audit section 3), `read_entity_pools`, `settle_gone_machines` and `remap_machine_recipes`, `place_pending_crates` (crates), `place_capsule` (capsule) |
| `belt_network` | derived lines; lane items are state, saved as `Belt_Cell_Item` records | `rebuild_belt_lines` on every belt or splitter change and on load, `tick_belt_network` |
| `fluid_networks` | derived topology; each network's fluid is saved | `rebuild_fluid_networks`, `tick_fluid_networks` |
| `electric_networks` | derived nodes, wires, memberships; participants per tick | `rebuild_electric_networks`, `tick_electric_networks` |
| `cells` | derived occupant map | `add_entity`, `add_belt`, `remove_entity`, `rebuild_entity_cells` |
| `loose_items` | state, saved in the later tables | `tick_loose_items`, `spill_stack`, `drop_player_stack`, `lift_loose_items_out_of` |

The shape of an entity:

- Shared by all 16: `Entity_Common` (handle, machine, origin, rotation, size, alive), embedded as `using common` and the first field of every kind struct.
- Per kind fields beyond it: Chest 2, Capsule 1, Furnace 7, Belt 4, Inserter 12, Drill 15, Splitter 8, Pipe 1, Fluid_Machine 12, Pole 1, Lamp 2, Assembler 14, Lab 7, Schematic_Crate 1, Core_Sample_Drill 3, Launch_Pad 11.
- Derived caches stored on entities and saved with them: `Belt.line` and `line_index`, the splitter's `input_lines` and `output_lines` (set by `rebuild_belt_lines`); `Power_State.satisfaction` (copied from the network each tick); `Inserter.reach`, the `slot_count` of chests, inserters, drills, fluid machines and labs, the assembler's slot counts and `lets_water_through` (copied from the `Machine` at creation); `Machine_Output_Rate` on furnaces, drills and assemblers (statistics on the entity).
- Network membership is kept three ways: on the entity (belt lines), in a map on the network (`Electric_Networks.memberships`), and as derived segments owned by handle (`Fluid_Segment.owner`, found by a scan in `find_fluid_segment`).

Other state:

- `Player` (`player.odin:50`, 25 fields): body (position, velocity as `f32`), input modes, target, mining, `inventory`, the cursor stack `held`, `open_machine`, `belt_drag`, `crafting` (`Craft_Queue`), magnetometer. Writers: `tick_player`, the screens (ui audit), developer requests, the command socket, `read_players`.
- `Inventory` is a heap slice of `Item_Stack`; entities hold fixed arrays plus a count, so slots come in two shapes, joined only by `entity_slots` returning a slice.
- `Statistics` (`statistics.odin:75`, 55 fields) and `Research_State` sit on `World` (world audit section 2). 66 direct counter writes outside tests: 33 in `statistics.odin`, 33 in 13 other files (`power_network.odin` 9, `launch_pad.odin` 5, `prospecting.odin` 5, `venture.odin` 4, others 1 or 2).

## 3. Coupling

Rule: a machine reading blocks, veins or prototypes it needs is essential; a procedure taking `^World` to reach simulation records is reach through.

simulation -> world (497, probe over `tools/code_graph.py`'s parser):

- Types 302: `World_Coordinate` 113, `World` 107, `Block_Registry` 52, `Direction` 19, `Block_Id` 11.
- Block reads 61 and writes 4: `world_get_block` 26, `AIR_BLOCK` 10, `block_is_solid` 9, `block_shape` 6, water levels and their constants 10; `world_set_block` 4. By file they are placement (`entity_placement.odin` 64, `belt_placement.odin` 41), the player (`player_interaction.odin` 71, `player.odin` 24, `player_collision.odin` 24) and loose items (32). The entity tick itself reads blocks in three places: `belt_end_drop_cell`, `loose_item_can_fall` and `flowing_water_level_sum` (hydro turbines, every footprint cell every tick).
- Veins 37 (`Vein`, `Vein_Id`, `Vein_Content`, `registered_vein`, outcrops): the drills asking the world for game records the world audit moves off `World`.
- Chunk loaded checks written inline in `entity_placement.odin` (2), `belt_movement.odin`, `loose_item.odin`, `player.odin`, `schematic.odin`, `prospecting.odin`, `developer.odin` (2).
- Noise and misassignment: `light_level` 8 of 12 are the `Machine` field of that name; `Core_Sample_Drill` 12 and 8 more are `prospecting.odin`; `diagnostics.odin` 17 is the loop's.
- Invisible to the graph: field reach. 145 `world.` field reads in the cluster's files: `entities` 91, `statistics` 38, `settings` 7, `chunks` 7, `research` 6, `entity_lights` 2, `shipments` 1.

simulation -> content (486): `Item_Id` 118, `Item_Registry` 74, `Recipe_Registry` 37, `NO_ITEM` 37, `NO_RECIPE` 26, `Recipe` 19, `item_stack_size` 19, `text` 18, `Schematic_Crate` 17 (a misassigned kind), `Technology_Registry` 12. By file: `assembler.odin` 94, `crafting.odin` 42, `lab.odin` 34, `machine.odin` 33, `item_transfer.odin` 30. These are registry reads per tick, essential.

- Content logic that is code: `Recipe_Maker` (12 crafting categories) and `Machine_Kind` are enums, so a new crafting category or machine behaviour is a code change; tuning constants live in Odin (`INSERTION_LIMIT_CRAFTS`, `REVIVAL_CYCLE_FACTOR`, `FLARE_RELIEF_PERCENT`, `LAMP_ON_ABOVE`, `RECYCLE_RETURN_PERCENT`, `ASSEMBLY_STAGES`).

presentation -> simulation (289): `render_entities.odin` 56, `render_fluids.odin` 48, `render_belts.odin` 47, `render_player.odin` 40, `sound_events.odin` 38, `render_particles.odin` 19. What the renderer reads per entity:

- All kinds: `Entity_Common` (origin, size, rotation, machine) and the prototype (`Machine_Registry` 30, `Machine` 14).
- Working: `machine_marker_colour` 15 and `marker_means_working` 10, computed per frame from the state enum; no animation state is stored.
- Phase: `inserter_arm_fraction`, `drill_progress_fraction`, `launch_pad_progress`; the rest run on the clock (`clock_pose`).
- Held items: the inserter's; belt lane items through `Belt_Network` (`render_belts.odin`); pipe and port levels (`render_fluids.odin`); wires (`render_power.odin`).
- Presentation loops over named pools 35 times (`render_entities.odin` 15, `sound_events.odin` 6, `render_particles.odin` 5, `render_fluids.odin` 5, `render_power.odin` 2, `render_belts.odin` 2).
- Noise: `placed_total` 9, of which 8 are the field of that name in the animation and sound memories.

Other edges: simulation -> ui 70 (by file `diagnostics.odin` 23, `player.odin` 17, `belt_placement.odin` 11, `quick_transfer.odin` 11; mostly `Input_Frame` and the action types, plus 11 `column` noise), simulation -> loop 80 (`Simulation_Content` 66), content -> simulation 240 (`Item_Stack` 50, `Statistics` 17 and `item_counter` 12 from the quests, `developer.odin` 38, `schematic.odin` 19, `recycler.odin` 17).

Cycles inside the cluster: 31 of its files (with the three misassigned kind files) are one strongly connected component; only `fluid.odin`, `developer.odin`, `player_animation.odin`, `production_statistics.odin` and `quick_transfer.odin` are outside it. The mechanisms:

- `entity.odin` is in a mutual pair with 16 files: it calls each kind's constructor and remover, each kind calls `pool_get` and names `Entity_Common`.
- `machine.odin` is in a mutual pair with 12: `validate_machine_kind_fields` calls each kind's validator, each kind reads `Machine`.
- Belts and inserters: `inserter.odin` <-> `item_transfer.odin` (5/3), and the transfer dispatches to belts, launch pads and assemblers, which call back into it; `belt.odin` <-> `splitter.odin` (20/34); `belt_movement.odin` <-> `loose_item.odin` (belt ends drop stacks, stacks ride belts); `record_belt_dead_ends` scans the inserters for every held line end (`inserter_picks_from`).
- Fluids and machines: `entity.odin` <-> `fluid_network.odin` (8/38), since the network reads the buffers of four kinds.
- Power and everything: `machine.odin` <-> `power_machine.odin` (10/28), `entity.odin` <-> `power_network.odin` (5/22), `fluid_machine.odin` <-> `power_machine.odin` (9/18): generators are fluid machines.
- Statistics and the kinds: `record_furnace_tick`, `record_inserter_tick`, `record_drill_tick`, `record_crafting_machine_tick` take the kind structs, and the kind ticks call them.

## 4. Abstraction gaps

Switches over `Entity_Kind` (17 in 10 files; 11 in the cluster):

- `entity.odin`: `entity_common` (16 cases), `entity_slots` (10), `remove_entity` (16).
- `entity_placement.odin`: `entity_rotates`, `rotate_targeted_entity`.
- `item_transfer.odin`: `entity_accepts`, `giving_slots`, `entity_takes_item_kind` (16).
- `fluid_network.odin`: `entity_port_buffers` (4). `power_network.odin`: `participant_power` (8). `quick_transfer.odin`: `fill_slots`.
- Outside: `entity_pool_length` and `entity_common_at` (`save_state.odin`, 16 each), `pipe_connects_through` (`render_fluids.odin`), `open_machine_slot_filters`, `machine_slot_region` and `entity_status_text` (ui audit).
- Plus `add_entity`'s switch over `Machine_Kind` (25 kinds to 16 pools), and lists naming every pool without a switch: `destroy_entities`, `write_entity_pools`, `read_entity_pools`, `entity_counts` (`diagnostics.odin`), `draw_entities` (10 kinds).
- A new kind is therefore: `Entity_Kind`, `Entities`, `destroy_entities`, `entity_common`, `remove_entity`, `add_entity`, `entity_takes_item_kind`, the two save lists, `entity_pool_length`, `entity_common_at`, `entity_counts`, and any of the component switches below it takes part in.

Repeated patterns across kinds:

- Burner (Furnace, Inserter, Drill, Fluid_Machine, Assembler): `fuel_joules` and `fuel_item_joules` on five structs, one shared `refuel_from_slot`, but the pay sequence (refuel, fail with a state, subtract `fuel_joules_per_tick`) is written in `advance_furnace`, `drill_draws_energy`, `burn_inserter_fuel`, `advance_boiler`, `pay_assembler_energy`, with a looping variant in `deliver_combustion_generator_energy`. The burn fraction is five identical procedures (`furnace_burn_fraction` and its siblings); "has fuel" four (`assembler_has_fuel`, `boiler_has_fuel`, the burner half of `inserter_can_move`, `furnace_has_fuel` in `render_entities.odin`). The fuel slot index is five constants plus `slots[0]` in the assembler.
- Electric consumer (8 kinds carry `Power_State`): `collect_electric_participants` and `collect_crafting_participants` hold 8 per pool loops, `assign_electric_memberships` 8 calls, `participant_power` 8 cases, plus one wants procedure per kind. "Is electric" has two rules in four procedures: `crafting_machine_is_electric` and `machine_is_electric_consumer` test the watts, `inserter_is_electric` and `drill_is_electric` test `slot_count == 0` (equal only because the validators tie fuel slots to fuel power).
- Progress: seven counters under four names (`progress_ticks` on four kinds, `work_ticks` on two, `phase_ticks`, `bored_ticks`) and seven fraction procedures (ui audit section 7).
- Fluid ports (Drill, Fluid_Machine, Assembler, Launch_Pad; Pipe holds one buffer): the `buffers` and `closed` pair is listed per pool in `collect_fluid_segments` (5 loops), `reset_fluid_flows` (5 loops) and `entity_port_buffers` (4 cases).
- Contents on pick up: `entity_pickup_stacks` probes seven per kind helpers (`belt_block_stacks`, `inserter_held_stacks`, `drill_held_stacks`, `splitter_held_stacks`, `assembler_held_stacks`, `launch_pad_held_stacks`, `entity_slots`), each empty for other kinds.
- Statistics per kind: each kind tick copies the whole entry (`before := drill`) and diffs it in its own `record_*` procedure (six of them), so the statistics system is spread over every kind loop.
- "Working": `draw_entities`, `draw_machine_markers` and `working_hum_sources` loop over the same five pools computing `marker_means_working(machine_marker_colour(...))`; the benchmark has its own definition (`observe_machine_activity`, `benchmark_idle_machines`).

Missing seams:

- No topology change seam. `add_entity` and `remove_entity` decide per kind which networks to rebuild; `rotate_targeted_entity`, `toggle_power_switch`, `add_belt`, `reshape_belt`, `remove_belt` and the splitter's add, remove and rotate each call a rebuild themselves. Every rebuild runs over all pools: `rebuild_belt_lines` walks every belt after `belt_cell_items` snapshots every belt item, so a belt drag of up to 16 steps per tick rebuilds all lines up to 16 times. Nothing tells the world or the statistics.
- No per tick machine interface: `tick_entities` is a hand sequence; drills, inserters and furnaces tick inline in it, the rest through `tick_*` procedures of differing signatures (`tick_fluids` takes `^Entities`, the others `^World`).
- Kinds inside kinds: `Fluid_Machine` serves 9 `Machine_Kind` values with a union of their fields, `Pole` serves poles and switches; the assembler serves 11 recipe makers. The furnace is a fourth crafting shape (`furnace_recipe_for` by input, inputs taken at the finish in `finish_smelting` where the assembler takes them at the start in `start_assembler_craft`).

Bundles and god structs:

- 38 procedures start with `(world: ^World, content: Simulation_Content`, 23 with `(entities: ^Entities, content: Simulation_Content`, 22 with `(entities: ^Entities, machines: Machine_Registry`, and 44 carry `world: ^World, registry: Block_Registry`.
- `Entities` (21 fields), `Statistics` (55 counters written from 14 files), `Machine` (46 fields, the union of every kind's prototype, validated per kind by `validate_machine_kind_fields`), `Player` (25 fields mixing body, UI cursor and crafting queue).

## 5. Refactors, ranked by gain per risk

1. Cluster table and one electric rule. Map `schematic.odin`, `prospecting.odin`, `recycler.odin` to simulation and `player_animation.odin` to presentation in `tools/code_graph.py`'s file table; move `statistics_rows`, `fluid_statistics_rows`, `count_item_machines` and the row types beside `ui_statistics.odin`; replace `inserter_is_electric`, `drill_is_electric` and `crafting_machine_is_electric` by `machine_is_electric_consumer`. Files: those named, `render_entities.odin`. Guards: `./build.sh check`, `test_brownout_slows_an_electric_drill`, `test_burner_inserter_stalls_when_fuel_runs_out`, `production_statistics_test.odin`. Gain: the graph shows the real seams (presentation -> simulation loses 18, simulation -> ui view models leave), three predicates go. Risk: none. Prerequisite: yes.
2. A kind table over the pools. One `[Entity_Kind]` row per kind: its pool (entries base, stride, length through one generic procedure instantiated per pool) and its networks touched; `Entity_Common` stays the first field of every kind struct, asserted at compile time. `entity_common`, `entity_pool_length`, `entity_common_at`, `rebuild_entity_cells`, `entity_counts`, the pool half of `destroy_entities` and the `pool_remove` switch of `remove_entity` read the table. Files: `entity.odin`, `save_state.odin`, `diagnostics.odin`. Guards: `test_pool_handles_generation_free_and_reuse`, `test_add_and_remove_entity_updates_cells`, `test_save_load_run_matches_the_original`, `test_fluid_networks_rebuild_after_removing_a_middle_pipe`, `test_power_switch_splits_a_network`. Gain: 4 switches of 16 cases and 2 lists, about 200 lines; a new kind is a row plus its logic. Risk: low; no layout, save or order change. Prerequisite: yes, it is the engine side pool registry.
3. Component locations in the kind table. Per row the offset of `power` and of the `buffers` and `closed` pair (or none); `participant_power`, `entity_port_buffers`, `segment_buffer`, `reset_fluid_flows`, the machine loops of `collect_fluid_segments` and `assign_electric_memberships` read them. Files: `entity.odin`, `power_network.odin`, `fluid_network.odin`. Guards: `fluid_test.odin` (29), `oil_test.odin`, `test_revival_port_takes_mining_fluid_from_a_pipe`, `power_test.odin`, `test_power_simulation_is_deterministic`. Gain: 2 switches, 9 per pool loops, 8 membership calls and about 70 lines; a new consumer or port holder is a table entry. Risk: low (pool order kept). Prerequisite: no.
4. One burner step. A procedure paying one tick of fuel (refuel, subtract, report) and one burn fraction over the existing flat fields, used by the five pay sequences and the five fractions; the combustion generator keeps its loop. Files: `furnace.odin`, `drill.odin`, `inserter.odin`, `fluid_machine.odin`, `assembler.odin`, the ui section files. Guards: `test_furnace_smelts_and_burns_fuel_per_tick`, `test_burner_inserter_stalls_when_fuel_runs_out`, `test_drill_stalls_on_blocked_output_and_on_fuel`, `test_boiler_burns_fuel_and_turns_water_into_steam`, `test_combustion_generator_burns_solid_fuel`, `test_furnace_tick_counts_output_fuel_and_stalls`. Gain: about 50 lines, one burner rule. Risk: low, no save change. Prerequisite: no.
5. One per frame machine view. Build once per frame a list of (common, marker colour, working, phase, held item) from the pools; `draw_entities`, `draw_machine_markers`, `working_hum_sources` and the particle emitters read it. Files: `production_statistics.odin`, `render_entities.odin`, `sound_events.odin`, `render_particles.odin`, `loop.odin`. Guards: `test_marker_colour_of_every_state`, `test_nearest_working_machine_and_its_volume`, `render_particles_test.odin`, a new test of the list; drawing needs a playtest. Gain: about 15 of presentation's 35 pool loops and three copies of the working rule; the list is the per frame draw description a plugin boundary needs. Risk: low to medium (draw order, untested draws). Prerequisite: yes.
6. A topology change seam. One procedure taking the machine and the change (placed, removed, rotated, switched) that marks the belt, fluid and electric networks dirty and tells the world about freed cells (world audit refactor 2); the rebuild runs once before the next reader (the next tick's belts, or at once for a caller that reads the network right after). Files: `entity.odin`, `entity_placement.odin`, `belt.odin`, `splitter.odin`, `power_machine.odin`, `save_state.odin`. Guards: `test_belt_drag_places_a_run_in_the_world`, `test_fast_belt_drag_uses_fast_ramps`, `test_fluid_networks_rebuild_after_removing_a_middle_pipe`, `test_power_switch_splits_a_network`, `test_save_load_run_matches_the_original`. Gain: the rebuild rules in one place, one rebuild per tick instead of one per placed belt. Risk: medium; a reader between the change and the rebuild sees stale lines (the placement ghost, `entity_network`). Prerequisite: yes, it is the entity change notification of a plugin.
7. Tick procedures without `^World`. After the world audit's refactor 3, the kind ticks take `^Entities`, the game records and a block query instead of `^World`; `tick_entities` takes one tick context struct. Files: every kind file, `entity.odin`, `loop.odin`, the tests' world builders. Guards: `./build.sh test`. Gain: 136 field reaches become explicit parameters; the entity tick no longer needs the chunk store. Risk: low per line, large diff. Prerequisite: yes, for a package split and for wasm.
8. Shared component structs. Embed a burner, a port pair and a work progress struct (names to choose) in the kind structs; first teach the codec to match the fields of a `using` struct by name, so old saves keep `fuel_joules` (today `save_binary.odin` treats `common` as one nested field and would drop a moved field, keeping zero). Files: `save_binary.odin`, the kind files, `save_codec_test.odin`. Guards: `save_codec_test.odin`, `save_test.odin` with a fixture from before the change, `save_remap_test.odin`. Gain: the component procedures take one pointer, the offsets of refactor 3 become one per component. Risk: medium (save layout). Prerequisite: no.
9. Furnace as a fixed choice crafting machine: removes a kind, `furnace.odin` and five switch cases, but changes when inputs leave the slot (finish versus start) and a saved furnace mid smelt. Only on the user's decision; not recommended with the others.

## 6. Engine or game

Rule: the engine stores, finds and connects entities; the game decides what they do.

- Engine candidates: `Entity_Pool` with `pool_add`, `pool_get`, `pool_remove`; `Entity_Handle` with the kind as an opaque number the game registers (today a closed enum of game kinds); footprint rotation (`rotated_footprint_size`, `rotate_footprint_cell`, `footprint_cells`); the occupant index (world audit refactor 5); the graph maintenance (union find in `assign_fluid_networks`, `assign_electric_networks`, reach tests); the placement framework (`footprint_is_valid`, `footprint_is_supported`, `footprint_hits_player`, `cell_takes_machine`, `clear_cover_from`); rate rings; `tick_profile.odin`.
- Game: every kind's behaviour, the transfer rules of `item_transfer.odin`, the transport line model, recipes and crafting, power balance and dispatch order, fluid mixing and head line, research, launch and shipments, statistics counters, the kind specific placement rules (vein under a drill, water for offshore pumps and turbines).
- Both today: `Entities` (engine storage holding game networks), `add_entity` (engine registration plus game constructors and network choices), `Machine` (engine footprint and model fields beside game rates).

What the game would call on the engine per tick:

- Block reads in the entity tick: belt end drop cells, loose items falling and merging, hydro turbines' footprint water; everything else reads blocks only on a player action (placement, mining, movement collision).
- Block writes: `apply_spent_outcrops` and tree felling through `world_set_block`; entity lights through `sync_entity_lights` (lamps, every tick).
- The occupant index on placement and removal, through refactor 6's seam.

What the engine would need from the game:

- Per kind ticks: one call per tick into the game (`tick_entities` with its order), not one per kind; the order is the game's.
- Per kind serialization: none, if the codec compiles into the plugin; the type driven codec already writes every kind struct by schema, and only `write_entity_pools`, `read_entity_pools` and the positional framing list the kinds (world audit refactor 9).
- Rendering: the per frame view of refactor 5 (machine id, origin, size, rotation, working, phase, held item), belt lane items, pipe levels, wires and particle emitters. The renderer reads pools 35 times today.
- Panels: the query surface of the ui audit section 6 (slots, burner, progress, ports, power, state per handle).

Could the current shape move behind wasm without rewriting every machine: yes for the machines. Entity data is plain values with handles as indices (`entity.odin` header), the ticks are integer arithmetic over arrays of structs, and generics such as `Entity_Pool($T)` compile to wasm like any Odin. The work is at the edges, not in the kinds: the `^World` parameter (refactor 7 and the world audit's refactor 3), the block reads as host calls, the renderer's and panels' direct pool reads (refactor 5, ui audit refactor 8), and the player, whose `f32` movement and collision sweep read blocks many times per tick and would stay a heavy host caller or move to the engine side.

## 7. Entity component lens

Rule: a component earns its place when several kinds carry it and generic code can serve it; per kind semantics stay per kind under any storage.

Candidate components, the kinds that carry them and where their code lives:

| Component | Kinds | Code today |
|---|---|---|
| Placement (origin, size, rotation, machine) | all 16 | `Entity_Common`, `entity_common` switch, `common_cells` |
| Item slots with filters | Chest, Capsule, Furnace, Inserter, Drill, Fluid_Machine, Assembler, Lab, Schematic_Crate, Launch_Pad | `entity_slots` (10 cases, 4 count rules), `entity_accepts`, `giving_slots`, slot filters in the ui |
| Burner | Furnace, Inserter, Drill, Fluid_Machine, Assembler | five pay sequences and fractions (section 4) |
| Power draw | Inserter, Drill, Fluid_Machine, Lamp, Assembler, Lab, Core_Sample_Drill, Launch_Pad | `Power_State`, `participant_power`, 8 collect loops, 8 wants procedures |
| Power supply | Fluid_Machine (4 generator kinds) | `generator_available_joules`, `deliver_generator_energy` |
| Crafting or work progress | Furnace, Drill, Assembler, Lab, Core_Sample_Drill, Launch_Pad, Inserter | four counter names, seven fractions |
| Fluid ports and buffers | Drill, Fluid_Machine, Assembler, Launch_Pad (Pipe: one buffer) | `entity_port_buffers`, `collect_fluid_segments`, `reset_fluid_flows` |
| Network membership | Belt, Splitter (on the entity); electric (a map); fluid (derived segments) | three mechanisms (section 2) |
| Held item | Inserter, Drill | `inserter_held_stacks`, `drill_held_stacks` |
| Output rate | Furnace, Drill, Assembler | `Machine_Output_Rate`, `record_machine_output` in three loops |
| State and animation | 7 state enums; animation is derived per frame | marker colours, state texts per kind |

Systems that exist implicitly, in `tick_entities` order: belts (belts and splitters), belt ends (lines, blocks, cells, loose items), loose items, belt dead ends (lines and inserters), power (8 pools plus poles), drills (drills plus any target through the transfer interface), inserters (any pool through the transfer interface), furnaces, assemblers, labs (plus research), core sample drills, launch pads, fluids (fluid machines, then the networks over 5 pools), lamps (plus the world's lights), outcrops and crates. Six iterate one pool; power, fluids, drills, inserters and the dead end count reach several, and they already do it through accessors (`participant_power`, `entity_port_buffers`, `entity_accepts`), which are component queries written as switches.

What a component store with generic systems would remove: the 17 switches, the pool lists, the 18 per pool loops of power and fluids, the burner and progress duplication (about 100 lines), and a new kind's twelve edits. What it would cost here:

- The save: 16 pools written as entries plus free lists with by name struct schemas; a store is a new format with a converter from every old save (hand-back rule).
- Handles: `Entity_Handle` carries the kind that 17 switches and many `handle.kind ==` tests dispatch on; it is stored in `cells`, `Electric_Networks.memberships`, `Fluid_Segment.owner`, `Player.open_machine`, the player's target, the quest capsule and `Machine_Activity`.
- Determinism: results depend on pool index order (drills sharing a vein, inserters sharing a chest, generator shares in pool order); pools reuse freed slots but never move entries. A dense store with swap removal reorders on every removal; `test_power_simulation_is_deterministic` compares pools entry by entry and would be rewritten.
- The renderer's per kind draws (inserter arm, drill bit, rocket) and the kind panels (ui audit section 7) stay per kind whatever the storage.
- 350 direct pool field references in 39 files and 156 in 32 test files.
- The coupling it would not cut: the cycles come from `entity.odin` and `machine.odin` enumerating the kinds, from `item_transfer.odin` dispatching to per kind rules, and from `^World`; the first is removed by a kind table, the rest by refactors 6 and 7, none by the storage layout.

The middle path, sized: refactors 2 and 3 (a kind table with pool views and component offsets, no layout change) remove 6 of the 17 switches (`entity_common`, `entity_pool_length`, `entity_common_at`, the pool part of `remove_entity`, `participant_power`, `entity_port_buffers`), 9 per pool loops and about 270 lines, keep the save byte for byte and the iteration order exactly. Refactor 4 removes the burner duplication without a struct change; refactor 8 adds shared component structs once the codec reads `using` fields by name. The per kind switches that remain (`entity_accepts`, `giving_slots`, `entity_takes_item_kind`, the ui's panel switches) encode per kind rules, which an ECS would keep as per kind systems too.

Recommendation: do not adopt an ECS. Take the middle path: a kind table over the existing pools first (no save or order change), then shared component structs with codec support. Reasons: 16 kinds with 1 to 15 own fields do not need archetype storage for speed; the multi pool systems are few and already query through accessors; pool order is part of the game's determinism and comes free with pools; and the coupling that matters for a plugin cut is `^World` and the renderer's pool reads, which a store would not touch.

## 8. Tests

Rule: every kind has behaviour tests through its tick; the systems' interaction is covered by the benchmark and the quest chapter tests, the per frame reads are not.

- Covered per kind: belts (`belt_test.odin` 12, `belt_placement_test.odin` 8), splitters (14), inserters (16), drills (`drill_test.odin` 22, `deep_mining_test.odin` 14), furnaces (5, `byproduct_test.odin` 12 with the recycler), crafting machines (`assembler_test.odin` 9, `ore_processing_test.odin` 16, `chemistry_test.odin` 9, `oil_test.odin` 19), fluids (`fluid_test.odin` 29), power (`power_test.odin` 12, `combustion_test.odin` 16, `hydro_grid_test.odin` 15), labs (13), launch pads (9), crates (`schematic_test.odin` 11), core sample drills (`prospecting_test.odin` 14), loose items (13), the player (`player_test.odin` 32, `player_interaction_test.odin` 22), crafting (22), inventories (11 and 10), transfers (`item_transfer_test.odin` 3, `quick_transfer_test.odin` 20), statistics (12 and 6), pools and placement (`entity_test.odin` 7, `entity_placement_test.odin` 3). Determinism has its own tests per system (`test_power_simulation_is_deterministic`, `test_inserter_fed_pad_is_deterministic`, `test_bore_drill_line_is_deterministic`) and `test_save_load_run_matches_the_original` across a save.
- Uncovered: removing or picking up a launch pad or a revival port drill, and rotating a revival port drill, so those fluid rebuild branches of `remove_entity` and `rotate_targeted_entity` run in no test; `working_hum_sources`, `draw_machine_markers` and `draw_entities` (the working rule is tested only through `test_marker_colour_of_every_state`); `record_belt_dead_ends` only through a chapter test's counter (`quest_chapter_03_test.odin`); the cost of a rebuild per placed belt during a drag.
- Pinning implementation: `belt_test.odin` appends lane items to `Belt_Network` lines by index; the determinism tests compare pools entry by entry (right for determinism, but they fix the storage); `test_pool_handles_generation_free_and_reuse` fixes the free list order, which is the determinism contract rather than an accident; `combustion_test.odin` reads `Electric_Networks.participants` directly.
- The factory benchmark (`benchmark_factory.odin`, `test_factory_benchmark`): sizes 1 and 4 run `BENCHMARK_TEST_WARM_UP_MINUTES` (2) plus one measured minute and require that no placed machine is idle (`benchmark_idle_machines`), which checks the chain power -> electric drills -> belts, splitters and lifts -> four inserter types -> furnaces -> assemblers -> lab, and tar pits -> refinery -> cracking -> chemical plant -> flare, with boilers, steam engines, combustion and fuel generators, a power switch and lamps. It does not place burner drills or burner inserters, pumps, storage tanks, hydro turbines, crates, core sample drills or launch pads, and it drops no loose items.

## Claims to spot check

1. `entity_common` (`entity.odin:180`), `entity_pool_length` (`save_state.odin:458`) and `entity_common_at` (`save_state.odin:499`) each switch over all 16 kinds, and every kind struct has `using common: Entity_Common` as its first field (for example `Furnace` at `furnace.odin:28`, `Launch_Pad` at `launch_pad.odin:64`), which is what refactor 2's table relies on.
2. The burner pay sequence is written five times: `advance_furnace` (`furnace.odin:117`), `drill_draws_energy` (`drill.odin:127`), `burn_inserter_fuel` (`inserter.odin:154`), `advance_boiler` (`fluid_machine.odin:162`), `pay_assembler_energy` (`assembler.odin:727`), each calling `refuel_from_slot` then subtracting `fuel_joules_per_tick`.
3. Each placement rebuilds whole networks: `add_entity` (`entity.odin:370`) calls `rebuild_fluid_networks` and `rebuild_electric_networks` over all pools, and `add_belt` (`belt.odin:663`) snapshots every belt item with `belt_cell_items` before `rebuild_belt_lines` walks every belt.
4. The save codec matches fields by name within one struct and has no case for `using` fields (`save_binary.odin:29` and the schema writer at `save_binary.odin:342`), so moving `fuel_joules` into an embedded struct would drop it from old saves.
5. Of the 145 `world.` field reads in the cluster's files, 136 are simulation records: `world.entities` 91, `world.statistics` 38, `world.research` 6, `world.shipments` 1 (grep over the 34 files of section 1).
