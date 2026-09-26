# Architecture

## Stack

- Odin dev-2026-09. Data oriented, procedures and structs, matching the code rules in `CLAUDE.md`.
- raylib 6.0 through `vendor:raylib` for the window, OpenGL rendering through rlgl, textures, fonts and audio. The bundled Linux build is static and uses GLFW.
- SDL3 through `vendor:sdl3` for controller input only (joystick, gamepad and sensor subsystems). SDL video is never initialised. raylib's GLFW gamepad path remains as the fallback for generic controllers.

## Process structure

- Main loop: render at vsync, simulate at a fixed 60 ticks per second with an accumulator. Only the camera interpolates between ticks.
- The simulation never reads the wall clock. Random numbers come from generators seeded by world seed, chunk coordinate or tick.
- Players are an array in the world state, each with its own camera and input frame. The alpha runs one player. Split screen co-op adds more without a redesign.
- Chunk generation and meshing run on worker threads (`core:thread`) and hand results to the main thread through queues. The simulation is single threaded in the alpha.

## Packages

One `game` package under `src/`, split into files by concern: `world_*.odin`, `generation_*.odin`, `simulation_*.odin`, `render_*.odin`, `input_*.odin`, `ui_*.odin`, `data_*.odin`, `save_*.odin`. Odin forbids import cycles and a game's concerns are tightly coupled, so packages are only split off for leaf utilities with no back references (configuration loading, noise helpers). `odin test src` runs the tests of the package.

## World storage

- A chunk is 32 by 32 by 32 blocks in flat arrays: block id (`u16`), light (`u8`, sky and block nibbles). Chunks live in a hash map keyed by chunk coordinate.
- Entities (machines, belts, inserters, chests) are not blocks. They occupy block volumes and each occupied cell holds the entity handle, so a raycast hits the entity and placement checks are cell lookups.
- Meshing: greedy meshing per chunk into a raylib `Mesh` with a texture atlas, uploaded with `UploadMesh`. Remesh on edit, frustum culling per chunk, fog hides the load boundary. A custom shader applies per vertex light and ambient occlusion.

## Simulation

- Entity pools per type (`[dynamic]Mining_Drill`, `[dynamic]Inserter`, and so on) with generational handles. Each type has its own update procedure over its own array. No general entity component system.
- Belts follow the transport line model: items are fixed point offsets along a line, lines merge and split at belt junctions. Ramps and lifts are lines with a different geometry, not special cases in the item logic.
- Fluid and electric networks are rebuilt on topology change and evaluated per tick in fixed point.
- Crafting machines hold a recipe id and a progress counter. Recipes are prototypes resolved to dense indices at load time.

## Data driven content

`data/*.sjson` holds blocks, items, recipes, machines, technologies, strata and ore tables, biomes. Files are parsed with `core:encoding/json` (`Specification.SJSON`) into prototype tables at startup. String ids are resolved to dense integer indices once. In development builds the data directory is watched and reloaded.

## Save format

Worlds live under `$XDG_DATA_HOME/mine-oh-belowed/saves/<world>/`: a `world.sjson` with seed, settings and tick, region files holding chunks as a per chunk palette plus run length encoded indices, and entities serialised per chunk. Odin's `core:compress/zlib` only inflates, so there is no zlib compressor in the standard library. Palette plus run length encoding suits voxel data and needs no dependency. Autosave pauses the simulation, writes dirty chunks, and resumes.

## Input abstraction

Actions, not buttons. An `Action` enum (move, look, jump, mine, place, rotate, pipette, hotbar radial, inventory, map, pause, and so on) and an `Input_Frame` struct that a backend fills every frame. Backends: SDL3 for the Steam Controller with its full feature set, raylib gamepad for generic controllers, keyboard and mouse for development. Bindings live in configuration, not in code. Details in [input.md](input.md).

## Configuration

SJSON with the layering from the global preference: `$XDG_CONFIG_DIRS`, `$XDG_CONFIG_HOME/mine-oh-belowed/config.sjson`, `config.d/*.sjson`, command line flags. No per project layer, the game has no project dimension. Unknown keys and wrong types are errors. A `config` subcommand dumps the files found and the effective values. Saves go to `$XDG_DATA_HOME`, logs to `$XDG_STATE_HOME`.

## Testing

Pure procedures (noise to strata mapping, belt line arithmetic, recipe resolution, run length coding) get unit tests run with `odin test`. A determinism test runs the simulation twice from the same seed for a fixed number of ticks and compares state hashes. Rendering and input are verified by playing.

## Performance target

1080p at 60 frames per second on the couch machine (AMD Navi 10, Radeon RX 5700 class), 60 ticks per second with several thousand belts and hundreds of machines. Chunk generation must keep up with a sprinting player.
