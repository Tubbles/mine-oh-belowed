# 0050 Headless factory benchmark

Status: implemented
Milestone: M10

## Goal

The performance pass needs a repeatable measurement, not a feeling on the couch: a headless integration test that builds a large factory, runs it for minutes of simulated time and reports the cost per tick per system, with a budget that fails when the simulation cannot hold 60 ticks per second on the couch machine.

## Deliverables

- A procedural base builder (`src/benchmark_factory.odin`) that lays out a factory of a given size from the shipped data on a flat test world: mining lines (electric drills on veins, belts to steel furnaces with inserters), an assembly block (assemblers making gears, circuits and science packs from belted plates, labs researching), a fluid block (offshore pumps, boilers, steam engines, a refinery with cracking and a chemical plant on tar), a power grid of poles and substations, splitters and belt lifts, plus a launch pad fed by inserters. Size 1 is a phase 4 base (about 200 entities), size 4 about a thousand entities, size 16 several thousand with belts in the tens of thousands of items. The builder is deterministic and asserts that every machine works after a warm up.
- A benchmark runner as a test (`src/benchmark_test.odin`): builds each size, ticks 10 simulated minutes, measures wall time per tick overall and per system (entities by kind, belts, fluids, power, lighting and water queues, statistics, quests) with `time.tick_now`, and logs a table. The test fails when size 4 exceeds 8 milliseconds per tick on average, half the 60 Hz budget, so CI runners have room; the numbers for every size go to the log as the record.
- A command line `--benchmark=<size>` in the release build that runs the same measurement without a window and prints the table, so the couch machine's and the Steam Deck's numbers can be quoted. The Steam Deck is a supported target (user, 2026-09-27): size 4 must hold 60 ticks per second there with room for rendering, so its budget is the one that counts.
- `doc/architecture.md` gains the measurement method, and `doc/content.md` "Learned from couch tests" the first numbers.

## Verify

- Builds and tests pass; the benchmark test prints its table.
- User: `./build/mine-oh-belowed --benchmark=16` on the couch machine finishes and the average tick stays under 16 milliseconds.

## Notes

Implementation pointers, decisions taken so the item is unambiguous (main agent, 2026-09-28). The item is large; land it whole, but keep every layer a small pure piece so the parts test on their own.

- The world: built in code, not generated. `build_benchmark_world(world, blocks, chunk_radius)` (new `src/benchmark_factory.odin`) fills the chunks of a square of `chunk_radius` around the origin at chunk y -1 and 0 with stone, the top layer of chunk y 0 (world y 31) grass, chunk y 1 and 2 air, every chunk marked loaded and lit as `carve_save_test_floor` and the test harness do (`src/save_test.odin`, `load_chunk_now`, `fill_chunk_light_levels`), so relative y 0 stands on the surface at world y 32. The generator serves only the vein types and the vein registration (`add_vein_for_developer` through `Developer_Request{.Add_Vein}`): `session_generator(base_generator, DEFAULT_WORLD_SEED, 100)` in the game, `make_test_generator(DEFAULT_WORLD_SEED)` in the test. The simulation comes from `make_simulation` as `make_save_test_simulation` makes it (player on the surface near the origin, the landing pad far in a corner of the floor, `world.settings.seed` set); `Simulation_Content` from the shipped tables (`load_game_data` in the game, `make_test_content` in the test). No streaming, no session, no window.
- The factory is content, so its layout is data: module blueprints under `data/blueprints/benchmark/` in the blueprint format of `doc/commands.md` (`origin = [0, 0, 0]`, `commands`), plus a manifest `data/blueprints/benchmark.sjson`: `modules = [{file = "mining_iron.sjson", extent = [width, depth], copies_per_size = n, veins = [{type = "iron", size_class = "deposit", x = 3, z = 3}]}]` (veins relative to the module origin, added before the module's commands run; `extent` is the footprint the layout tiles by). The builder (`benchmark_layout(manifest, size) -> []Module_Placement`, pure) puts each module kind in its own column along x (pitch the extent's width plus a gap of 4) and `copies_per_size * size` copies along z (pitch the depth plus 4), the whole grid centred on the origin, and `build_benchmark_factory` runs each copy through `run_blueprint` with the origin overridden to the copy's cell (`Blueprint.origin_kind = .Cell`), through a `Command_Context` of the simulation and content only (no control, no screenshots; check `command_content` copes with a nil control, else pass an empty `Command_Control`). A failed command is a build failure that names the module, the copy and the command.
- New blueprint command `recipe <recipe> <x> <y> <z>` (`src/command.odin`, `blueprint_coordinate_index`, the help list, `doc/commands.md`), served by `Developer_Request{.Set_Recipe}` (`src/developer.odin`) through the path the assembler's panel uses to change a recipe (`Recipe_Change_Refusal` in `src/ui_recipes.odin` names it), refused with the panel's reasons; assemblers, chemical plants and every other machine with `recipe_choice` other than `.Fixed` need it, and the modules use it.
- Modules, all self contained (own power, own inputs from own veins, so a module never depends on another and the copies scale linearly), each proven to run on its own: mining and smelting (electric drills on an iron and a copper vein, belts with a splitter and a belt lift on the way, steel furnaces fed by inserters, coal from a coal vein, plates into chests); assembly (belted plates from the module's own furnaces into assemblers making iron gears, electronic circuits and science pack 1, a lab researching a queued technology, `research` is not a blueprint command so the lab's technology is queued by the builder in code through `queue_research` on the first available technology); power (offshore pumps on a water pool laid with `block water`, boilers fed coal by belt from a coal drill, steam engines, poles, a substation and a power switch on); oil (tar pit pumps on a tar pool laid with `block tar`, a refinery, a cracking unit and a chemical plant making plastic into a chest, a flare stack on the waste gas); launch pad (a pad with inserters loading rocket parts from chests stocked by `insert`, the only stocked input in the base). Starter fuel by `insert` is allowed to spin a module up; everything must still run at the end of ten simulated minutes from its own veins. The counts per size are the manifest's `copies_per_size`, chosen so size 1 lands near 200 entities (belts count) and size 4 near a thousand; state the counts in the report.
- The timing: a new `src/tick_profile.odin` with `Tick_Section :: enum {Players, Unlocks, Belts, Loose_Items, Power, Drills, Inserters, Furnaces, Assemblers, Labs, Core_Sample_Drills, Launch_Pads, Fluids, Lamps, Outcrops_And_Crates, Venture, Research, Statistics, Quests, World}` and `Tick_Profile :: struct {seconds: [Tick_Section]f64, ticks: int}`; `profile_section(profile: ^Tick_Profile, section, start: time.Tick)` adds `time.tick_since(start)` when `profile != nil`. `simulation_tick` (`src/loop.odin`) and `tick_entities` (`src/entity.odin`) gain a trailing `profile: ^Tick_Profile = nil` parameter and wrap their steps; no existing caller changes. World is `tick_world` (light and water queues, block changes, felling).
- The runner: `run_factory_benchmark(size, generator, content, config, warm_up_ticks, measured_ticks) -> Benchmark_Report` builds the world and the factory, ticks the warm up with a profile of its own, then the measured ticks with the profile the report keeps, and fills the report: the entity counts by kind, the items on belts, the average and the worst tick in milliseconds, the average per section, and the idle machines after the warm up (`benchmark_idle_machines(world, content) -> []Idle_Machine{machine: Machine_Id, cell}`: a machine is idle when its own progress did not move over the last minute of the warm up, judged per kind from the entity state the panels show, such as a drill's mined count, a furnace's or an assembler's output growth, a lab's progress, an engine's power, a pump's or a refinery's fluid produced, an inserter's idle streak; say per kind which field decides). `format_benchmark_report(report) -> string` renders the table once for both callers: a row per section with milliseconds per tick and the share, the total, the counts, the idle list.
- `--benchmark=<size>` (`Command_Line.benchmark: int` in `src/main.odin`, usage "run the headless factory benchmark of this size for ten simulated minutes and print the table"; a conflict with `--load`, `--seed`, `--name`, `--chapter`, `--debug-terrain` in `command_line_conflict`): in `main` after `load_game_data` and before `start_input_backend`, so no window and no controller: size 1 to 16 (64 at first; capped at 16 by the user on 2026-09-28, larger sizes are read off 16), a warm up of two simulated minutes, ten measured minutes, the table on stdout, exit 0, exit 1 when the build fails or a machine idles.
- The test (`src/benchmark_test.odin`): `test_factory_benchmark` builds sizes 1 and 4, warms up one simulated minute, measures one (the suite must stay quick; the ten minutes are the command line's), asserts the build succeeds and no machine idles, logs the table with `log.infof` as `test_report_generation_and_meshing_time` does, and asserts the size 4 average under 8 milliseconds per tick only `when ODIN_OPTIMIZATION_MODE == .Speed`, since the plain test build is unoptimised and its numbers are not the release's; in other builds the numbers are logged only. Pure tests besides: the manifest and every module blueprint parse and name shipped machines, recipes, veins and blocks; `benchmark_layout` gives non overlapping rectangles for sizes 1, 4 and 16 with the expected copy counts; `build_benchmark_world` makes the floor (spot checks of blocks and loaded chunks); the profile adds sections only when given; the `recipe` command sets and refuses.
- `build.sh` gains `bench`: `odin test src -o:speed -define:ODIN_TEST_NAMES=game.test_factory_benchmark`, the optimised run that enforces the budget; `doc/build.md` documents it and `--benchmark`. CI keeps the plain suite.
- Docs: `doc/architecture.md` (the measurement method: the profile, the flat world, the module grid), `doc/content.md` "Learned from couch tests" (the first numbers, marked as the couch machine's, the Steam Deck's still to come), `doc/commands.md` (the `recipe` command, the benchmark blueprints), `doc/log/2026-09-28.md`, this item's Status and an Implemented paragraph with the table for sizes 1 and 4 from `./build.sh bench`.

Files a subagent may touch: new `src/benchmark_factory.odin`, `src/benchmark_test.odin`, `src/tick_profile.odin`, `src/tick_profile_test.odin`; `src/loop.odin` (the profile parameter of `simulation_tick` only), `src/entity.odin` (the profile parameter of `tick_entities` only), `src/command.odin`, `src/command_test.odin`, `src/developer.odin`, `src/developer_test.odin`, `src/main.odin`, `src/main_test.odin`, `build.sh`, new files under `data/blueprints/benchmark/` and `data/blueprints/benchmark.sjson`, the docs above, this file.

## Implemented

Implemented: `src/tick_profile.odin` (`Tick_Section`, `Tick_Profile`, `profile_now`, `profile_section`) with the optional profile parameter of `simulation_tick` (`src/loop.odin`) and `tick_entities` (`src/entity.odin`); `src/benchmark_factory.odin` (manifest and plan loading and validation, `benchmark_layout`, `benchmark_floor`, `build_benchmark_world`, `add_benchmark_vein`, `build_benchmark_factory`, the idle watch `observe_machine_activity` and `benchmark_idle_machines`, `run_factory_benchmark`, `format_benchmark_report`, `run_command_line_benchmark`); the blueprint commands `recipe` and `filter` (`src/command.odin`, `Developer_Action.Set_Recipe` and `Set_Filter` in `src/developer.odin`); `--benchmark=<size>` (`src/main.odin`); `./build.sh bench`; the manifest `data/blueprints/benchmark.sjson` and the modules `data/blueprints/benchmark/smelting.sjson`, `assembly.sjson`, `power.sjson` and `oil.sjson`, each proven alone for twelve simulated minutes before the grid. Tests: `src/benchmark_test.odin` (plan, layout for sizes 1, 4 and 16, floor, and the run of sizes 1 and 4), `src/tick_profile_test.odin`, `test_command_recipe_and_filter` (`src/command_test.odin`), `test_command_line_benchmark_size_and_conflicts` (`src/main_test.odin`). Docs: `doc/architecture.md`, `doc/build.md`, `doc/commands.md`, `doc/content.md`, `doc/log/2026-09-28.md`. 1016 tests pass.

Departures from the notes, reasons in the log: no launch pad module (a pad assembles and launches only from its panel's buttons, and its rocket fuel needs a sulfur and light oil chain of its own); a `filter` command beside `recipe` (every furnace line has to sort low grade ore and gravel off, or a furnace holding one low grade ore stops its line); copper is smelted in the assembly module on a mixed vein rather than in a second mining module; the test warms up two minutes, not one (the flare stack behind two cracking units first burns in the second minute); the floor is a rectangle under the grid, not a square; veins are added through `make_added_vein` and `add_vein`, not `add_vein_for_developer`, which refuses columns where the generator's own veins would be; research costs are scaled to 1000 times; the player stands in a floor corner, not near the origin, where the grid is; belts hold hundreds of items at size 16 (755), not tens of thousands, since every belt runs into consumers and a sink chest and nothing backs up.

Counts per size (copies_per_size 1 for every module): smelting 72 entities, assembly 122, power 56, oil 70, so size 1 is 321 with the capsule and size 4 1281 (belts count). Tables for sizes 1 and 4 from `./build.sh bench` on the couch machine (host `bazzite`, Ryzen 7 2700X), headless:

```
factory benchmark size 1, 2.0 minutes warm up, 1.0 minutes measured
section                 ms/tick   share
Players                  0.0019    7.8%
Unlocks                  0.0006    2.4%
Belts                    0.0008    3.0%
Loose_Items              0.0003    1.1%
Power                    0.0056   22.5%
Drills                   0.0008    3.1%
Inserters                0.0037   14.9%
Furnaces                 0.0005    2.2%
Assemblers               0.0013    5.1%
Labs                     0.0003    1.3%
Core_Sample_Drills       0.0003    1.1%
Launch_Pads              0.0005    2.1%
Fluids                   0.0042   16.6%
Lamps                    0.0015    6.2%
Outcrops_And_Crates      0.0003    1.1%
Venture                  0.0003    1.3%
Research                 0.0003    1.1%
Statistics               0.0010    4.0%
Quests                   0.0005    1.9%
World                    0.0003    1.4%
sections                 0.0250  100.0%
tick average             0.0261
tick worst               0.0461
entities: Chest 12, Furnace 4, Capsule 1, Belt 138, Inserter 38, Drill 9, Splitter 3, Pipe 37, Fluid_Machine 19, Pole 43, Lamp 8, Assembler 8, Lab 1, total 321; items on belts 37
idle machines after the warm up: 0

factory benchmark size 4, 2.0 minutes warm up, 1.0 minutes measured
section                 ms/tick   share
Players                  0.0020    2.7%
Unlocks                  0.0006    0.8%
Belts                    0.0022    3.0%
Loose_Items              0.0003    0.4%
Power                    0.0208   28.2%
Drills                   0.0024    3.3%
Inserters                0.0147   20.0%
Furnaces                 0.0014    1.8%
Assemblers               0.0042    5.6%
Labs                     0.0005    0.6%
Core_Sample_Drills       0.0003    0.4%
Launch_Pads              0.0005    0.7%
Fluids                   0.0144   19.6%
Lamps                    0.0059    8.0%
Outcrops_And_Crates      0.0003    0.4%
Venture                  0.0003    0.5%
Research                 0.0003    0.4%
Statistics               0.0018    2.5%
Quests                   0.0005    0.7%
World                    0.0004    0.5%
sections                 0.0737  100.0%
tick average             0.0748
tick worst               0.1342
entities: Chest 48, Furnace 16, Capsule 1, Belt 552, Inserter 152, Drill 36, Splitter 12, Pipe 148, Fluid_Machine 76, Pole 172, Lamp 32, Assembler 32, Lab 4, total 1281; items on belts 174
idle machines after the warm up: 0
```
