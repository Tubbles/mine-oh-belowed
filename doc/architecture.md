# Architecture

## Stack

- Odin dev-2026-09. Data oriented, procedures and structs, matching the code rules in `CLAUDE.md`.
- raylib 6.0 through `vendor:raylib` for the window, OpenGL rendering through rlgl, textures, fonts and audio. The bundled Linux build is static and uses GLFW.
- SDL3 through `vendor:sdl3` for controller input only (joystick, gamepad and sensor subsystems). SDL video is never initialised. raylib's GLFW gamepad path remains as the fallback for generic controllers.

## Process structure

- Main loop: render at vsync, simulate at a fixed 60 ticks per second with an accumulator. Only the camera interpolates between ticks, from the previous tick's player state to the current one.
- Frames and ticks run at different rates, so frame input is accumulated between ticks: `look_delta` (pixels) and `just_pressed` (edges) are events that sum up and the first tick after them takes the whole sum, held state (move, look, pressed) is a level and every tick reads the latest frame. A second tick in the same frame sees zero events.
- The simulation owns the `World` and the players. The player body is ticked in the simulation, never per frame, with axis separated swept collision against blocks. Player physics is the one place plain `f32` is allowed to accumulate, until the world scale is settled; it stays deterministic for the same binary and input.
- The simulation never reads the wall clock. Random numbers come from generators seeded by world seed, chunk coordinate or tick.
- Fixed point everywhere a simulation quantity accumulates: belt positions, fluid volumes, energy buffers, crafting progress, vein reservoirs are integers with a fixed scale. Floats stay in rendering and input. Debug builds hash the simulation state every tick, and a test runs two simulations from one seed and compares the hashes.
- Players are an array in the world state, each with its own camera and input frame. The alpha runs one player. Split screen co-op adds more without a redesign.
- Chunk generation and meshing run on worker threads (`core:thread`, processor cores minus one, at most six) and hand results to the main thread through mutex protected queues. Workers never touch the `World`: a generate job carries only a coordinate, a mesh job carries private copies of the chunk and its six neighbours. Per frame limits keep the main thread smooth (16 generated chunks inserted, 8 mesh jobs submitted, 6 non empty mesh uploads, 48 jobs pending). A chunk is meshed once all neighbours inside the load volume are loaded, and stale mesh results are dropped by revision. The simulation is single threaded in the alpha.
- Generation is a pure function of the world seed and the chunk coordinate. Features that cross chunk borders (trees, vein outcrops) come from per column and per region hashes any chunk can recompute, so load order and thread count never change the world. Each purpose (height, moisture, caves, trees, veins) has its own sub seed derived from the world seed.

## Sessions

The window, renderer, UI and input backend are created once per process. A `Session` holds one world: the simulation, a copy of the generator with the world's seed and richness, the streaming state, the save location and the tick accumulator. The title state has no session; starting or loading a world creates one, quit to title saves and destroys it and drops the chunk meshes. Menus request session changes on the title state and the frame loop applies them after the frame, so a failed start shows a toast and leaves the menus in place. Biomes and vein tables load once and are copied per session; the research cost setting is a per session scaled copy of the technology registry.

## Packages

One `game` package under `src/`, split into files by concern: `world_*.odin`, `generation_*.odin`, `simulation_*.odin`, `render_*.odin`, `input_*.odin`, `ui_*.odin`, `data_*.odin`, `save_*.odin`. Odin forbids import cycles and a game's concerns are tightly coupled, so packages are only split off for leaf utilities with no back references (configuration loading, noise helpers). `odin test src` runs the tests of the package.

## World storage

- A chunk is 32 by 32 by 32 blocks in flat arrays: block id (`u16`), light (`u8`, sky light in the high nibble, block light in the low nibble). Chunks live in a hash map keyed by chunk coordinate.
- Water levels are block ids: the source block plus seven flowing water ids marked by a `water_level` field in the block data. This keeps the chunk layout and serialisation unchanged and saves water levels for free.
- Light: generation workers compute a chunk's initial sky light from its own columns. Everything that crosses chunk borders or follows an edit runs on the main thread inside the simulation tick through bounded queues (a removal queue and an addition queue, removals first), so the final values never depend on visiting order. Every `world_set_block` is recorded as a block change that the next tick turns into light updates and, next to water, water updates.
- Water flow is Minecraft style cellular flow, scheduled per cell with a fixed delay, run in scheduling order and bounded per tick, on the main thread.
- Mesh jobs copy the chunk plus a one cell shell of blocks and light from all 26 neighbours, because smooth lighting and ambient occlusion need edge and corner neighbours. The vertex colour packs sky light, block light and occlusion into red, green and blue; the fragment shader scales sky light by the day factor.
- Entities (machines, belts, inserters, chests) are not blocks. They occupy block volumes and each occupied cell holds the entity handle, so a raycast hits the entity and placement checks are cell lookups.
- Meshing: greedy meshing per chunk into a raylib `Mesh` with a texture atlas, uploaded with `UploadMesh`. Remesh on edit, frustum culling per chunk, fog hides the load boundary. A custom shader applies per vertex light and ambient occlusion.

## Simulation

- Entity pools per type (`[dynamic]Mining_Drill`, `[dynamic]Inserter`, and so on) with generational handles. Each type has its own update procedure over its own array. No general entity component system.
- Belts follow the transport line model: items are fixed point offsets along a line, lines merge and split at belt junctions. Ramps and lifts are lines with a different geometry, not special cases in the item logic.
- Fluid and electric networks are rebuilt on topology change and evaluated per tick in fixed point.
- Recipes have any number of inputs and any number of outputs, each an item or a fluid, from the very first recipe. Machines have typed slots. There is no single output fast path to retrofit later.
- Crafting machines hold a recipe id and a progress counter. Recipes are prototypes resolved to dense indices at load time.
- Veins are entities, not block data: a reservoir struct with per ore amounts, centre, radius and size class, placed per region of 8 by 8 chunk columns so that every footprint lies inside its region. Generation threads compute footprints, the main thread registers each vein once when the first chunk of an overlapping column loads. Drills will hold a vein handle. There are no per block ore counters.
- Fluids use one network model with a phase per fluid. Segments balance by fill fraction per connection with a per tick flow cap; a liquid segment only feeds neighbours at its height or lower, a running pump lifts its output network above that rule, and gas networks ignore height.
- Production statistics counters (produced, obtained, delivered per item, placed per machine, machine stalls, fuel burned, blocks mined, distance walked, and three rings per item for produced and consumed rates: 60 per second buckets, 60 per ten second buckets and 60 per minute buckets, the coarser fed from the finer, all saved) live on the `World` next to the entity pools. Furnaces, crafting machines and drills carry a 60 bucket ring of their own output for the panel rate readout. The quest runtime, the statistics screen and the bottleneck overlay all read them.
- Shipments (tick and cargo of every rocket launched) live on the `World` next to the statistics and are saved; launch requests from the UI are served inside the simulation tick because the shipment needs the tick.
- The venture state (0041: the open contracts with their deliveries and offer counts, the venture credit, and catalogue orders waiting for the next tick) lives on the `World` and is saved; the levels of infinite technologies live in the research state next to the queued technology, since drills and labs read them every tick. Shipments are served right after the launches in the same tick: contracts oldest first, then free trade. `Simulation_Content` carries a read only pointer to the session's generator, set per frame and nil in tests, so the orbital survey can chart veins in chunks that were never loaded.
- Developer requests (0043) are a list on the simulation state filled by the Developer screen and by `--chapter` and `--give`, served at the start of the next tick and never saved, so the UI frame changes no simulation state itself. The day cycle reads the tick plus a day offset the developer menu can set; the offset is saved through the world file's day time field, so the save format is unchanged and older saves load with offset 0.
- Logging (0043): when stderr is not a terminal, as under Steam, the log file is put on the stderr descriptor so Odin's runtime reports (bounds checks, type assertions) land in `log.txt`; the game's own lines go once to the log and once to the original stderr. The main thread's assertion failures and SIGSEGV or SIGILL write a back trace to the log before the process ends.
- Quests are data: chapters of objectives whose predicates are evaluated against the statistics counters, placed entity counts and research state every tick. The journal reads the same state.

## Data driven content

`data/*.sjson` holds blocks, items, recipes, machines, technologies, vein types and ore tables, biomes, quest chapters. Files are parsed with `core:encoding/json` (`Specification.SJSON`) into prototype tables at startup. String ids are resolved to dense integer indices once. In development builds the data directory is watched and reloaded.

## Strings and units

Every player facing string lives in `data/strings/en.sjson` and is referenced by key, from the first screen that shows text. One procedure formats quantities with their units (per minute, kW, MW, L), so the realism units stay consistent and localisation later is a data change. The developer diagnostics screen is the one exception and may use literal strings.

## Save format

Worlds live under `$XDG_DATA_HOME/mine-oh-belowed/saves/<world>/` (override with `MINE_OH_BELOWED_SAVES`): a `world.sjson` with format version, name, seed, world settings, tick and day time; `entities.bin`, a hand written little endian file holding every entity pool and the world's simulation state (players, research, quests, statistics, unlocks, pending block and water updates) driven by Odin type information so a new field cannot be left out silently, with a header fingerprint of the struct layout and of the game data ids that refuses mismatched saves; and `regions/<x>_<z>.bin` holding only modified chunks as a per chunk palette plus run length encoded indices. Unmodified chunks regenerate from the seed. Light is not saved: a loaded chunk recomputes its sky light with the generation column procedure and re seeds block and entity lights. Networks are rebuilt after load. Saving pauses the simulation, writes to a `.saving` directory and swaps it into place through a `.previous` directory, so a crash never leaves a half written save. Autosave counts simulated ticks. Odin's `core:compress/zlib` only inflates, so there is no zlib compressor in the standard library; palette plus run length encoding suits voxel data and needs no dependency.

## Input abstraction

Actions, not buttons. An `Action` enum (move, look, jump, mine, place, rotate, pipette, hotbar radial, inventory, map, pause, and so on) and an `Input_Frame` struct that a backend fills every frame. Backends: SDL3 for the Steam Controller with its full feature set, raylib gamepad for generic controllers, keyboard and mouse for development. Bindings live in configuration, not in code. Details in [input.md](input.md).

## Configuration

SJSON with the layering from the global preference: `$XDG_CONFIG_DIRS`, `$XDG_CONFIG_HOME/mine-oh-belowed/config.sjson`, `config.d/*.sjson`, then `--set=<key>=<value>` flags. No per project layer, the game has no project dimension. Files are parsed as generic SJSON trees and merged with provenance per key (objects merge, scalars and arrays replace), then mapped onto the typed `Configuration` (settings, bindings, paths) with strict checks: an unknown key, a wrong type or an out of range value is an error naming the file. `mine-oh-belowed config` prints the files in precedence order and the effective values with their source. The settings screen writes `config.d/90-settings.sjson`. Saves go to `$XDG_DATA_HOME`, the log to `$XDG_STATE_HOME/mine-oh-belowed/log.txt` through one logging procedure that also prints to stderr.

## Testing

Pure procedures (noise to strata mapping, belt line arithmetic, recipe resolution, run length coding) get unit tests run with `odin test`. A determinism test runs the simulation twice from the same seed for a fixed number of ticks and compares state hashes. Rendering and input are verified by playing.

## Performance target

1080p at 60 frames per second on the couch machine (AMD Navi 10, Radeon RX 5700 class), 60 ticks per second with several thousand belts and hundreds of machines. Chunk generation must keep up with a sprinting player.
