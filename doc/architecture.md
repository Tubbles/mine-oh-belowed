# Architecture

How the game is put together. The agent rules (stack, imports, determinism, naming) are in [CLAUDE.md](../CLAUDE.md), what is drawn and heard in [presentation.md](presentation.md), building and shipping in [build.md](build.md).

- One `game` package, data oriented: procedures over arrays of structs, no entity component system.
- The simulation ticks at a fixed rate, owns the `World` and the game's records (`Game_Records`) and never reads the wall clock, the frame time, the settings or the socket.
- Worker threads only generate and mesh chunks; everything else runs on the main thread.

## Stack

- raylib's GLFW has the Wayland and the X11 backend and takes Wayland when the session offers one ([build.md](build.md), Display). The window asks for high DPI (`WINDOW_HIGHDPI`), so on a scaled Wayland desktop the framebuffer has the panel's pixels.
- raylib also gives rlgl rendering, textures, fonts and audio; SDL3 gives the controller ([input.md](input.md)).

## Frame and tick

Rule: frames render as fast as allowed, the simulation advances in fixed ticks, and only rendering interpolates.

- The frame renders at vsync or at the frame rate cap from the settings (both optional). An accumulator runs 60 ticks per second (`tick_rate` in `data/game.sjson`).
- The camera and the player's drawn pose interpolate from the previous tick's player state to the current one.
- Frame input reaches ticks through `Tick_Input_Accumulator` ([input.md](input.md), The input frame).
- Players are an array in the simulation state, each with its own camera and input frame; the game runs one.
- Random generators are seeded by the world seed, a chunk coordinate or the tick. Belt positions, fluid volumes, energy buffers, crafting progress and vein reservoirs are fixed point integers.
- Player physics is the one place plain `f32` accumulates: axis separated swept collision against block collision boxes (`block_shape.odin`: a cube's cell, a slab's half, the two boxes of stairs, none for torches) and the whole cells of entities other than belts and splitters. It stays deterministic for one binary and one input stream.
- The raycast hits a shaped block only where it meets its boxes, or a post's bounds.

## Sessions

- The window, renderer, UI and input backend exist once per process. A `Session` holds one world: the simulation, a copy of the generator with the world's seed and richness, the streaming state, the save location, the tick accumulator and the forced weather.
- The process state is `Frame_State` (`loop.odin`): the loop's own fields (configuration, content, session, frame timing, directories, settings) at the top, the rest in four groups, `interaction` (input, the UI and its fonts, the touch overlay, the title), `presentation` (the renderers, atlases, display state and sound), `developer` (diagnostics, the command socket, the texture editor and data browser) and `reload` (hot reload's watcher, arenas and request).
- The title state has no session. Starting or loading a world creates one; quit to title saves it, destroys it and drops the chunk meshes.
- Menus request session changes and the frame loop applies them after the frame, so a failed start toasts and leaves the menus in place.
- Biomes and vein tables load once and are copied per session; the research cost setting makes a per session scaled copy of the technology registry.

## Source layout

- Files by concern: `world_*.odin`, `generation_*.odin`, `render_*.odin`, `input_*.odin`, `ui_*.odin`, `data_*.odin`, `save_*.odin`, one file per entity kind (`furnace.odin`, `inserter.odin`), tests beside their file as `*_test.odin`.
- The files of the game package form seven clusters by prefix with an allowed dependency table between them; [code_map.md](code_map.md) lists every file by cluster.
- Leaf utilities with no back references are packages under `src/` (Odin forbids import cycles), each a cluster of its own: `src/platform/`, `src/generation_seed/`, `src/model_vox/`, `src/render_frustum/`, `src/run_length/`, `src/sjson_text/` (the 0145 pilot split) and `src/android_libc/` ([code_map.md](code_map.md), Packages).

## Threads and chunk streaming

Rule: workers never touch the `World`; results reach the main thread through mutex protected queues.

- Workers: `core:thread`, processor cores minus one, 1 to 6 (`default_worker_count`). A generate job carries a coordinate; a mesh job carries private copies of the chunk and a one cell shell of blocks and light from all 26 neighbours.
- Per frame limits: 16 generated chunks inserted, 8 mesh jobs submitted, 6 non empty mesh uploads, 48 jobs pending (`world_streaming.odin`).
- Loading reaches `LOAD_RADIUS_HORIZONTAL` (6) chunks out and `LOAD_RADIUS_VERTICAL` (3) up and down; chunks unload one chunk beyond.
- A chunk is meshed once all its neighbours inside the load volume are loaded. Stale mesh results are dropped by revision.

## World generation

Rule: generation is a pure function of the world seed and the chunk coordinate, so load order and thread count never change the world.

- Each purpose (height, moisture, caves, trees, veins) has its own sub seed from the world seed. Features that cross chunk borders (trees, outcrops) come from per column and per region hashes any chunk can recompute.
- `terrain_height` is one pure function of the sub seeds and a column, in layers: continental swell into lowlands and raised masses, ridged ranges and hills on raised ground at a domain warped position, plateaus pulled up to multiples of 12 blocks above sea level with a cliff band, damped detail, then river valleys.
- A chunk generates terrain and caves, the schematic crate site, trees and boulders, outcrops, clears the column above every outcrop, sets the ground cover (at most one cross per column from a column hash, never in a vein footprint), stamps the landing pad, then computes its sky light (`generation_chunk.odin`). Vein footprints are open to the sky; ground cover is not opaque.
- `GENERATOR_VERSION` counts terrain changes (Save format).

## World storage

- A chunk is 32 by 32 by 32 blocks in flat arrays: block id (`u16`) and light (`u16`, four nibbles from the highest: sky, red, green, blue). Chunks live in a map keyed by chunk coordinate, each on the heap.
- Water levels are block ids: the source and seven flowing ids marked by `water_level` in `data/blocks.sjson` (8 the source, 7 to 1 flowing), so the chunk layout and the save hold them for free.
- Every `world_set_block` records a block change; the next tick turns the changes into light and water updates.
- Entities (machines, belts, inserters, chests) are not blocks: each occupied cell maps to the entity handle in `World.entities.cells` and stays air in the chunk, so a raycast hits the entity and placement checks are cell lookups.
- `World` holds the chunks, the saved chunks, the block changes, the settings, the veins and their outcrops, light, water and, for now, the entities. The game's records are not on it (Simulation).

### Light

- Workers compute a new chunk's sky light from its own columns. Everything that crosses chunk borders or follows an edit runs on the main thread inside the tick through bounded queues, removals before additions, so the result does not depend on visiting order.
- Block light is coloured: the queues carry the channel, every channel spreads alike and never mixes, and two emitters mix by the larger level per channel. The budget (`MAXIMUM_LIGHT_STEPS_PER_TICK`, 4096) counts nodes over all channels, so a white emitter costs three times one channel.
- Emitters take their colour from `light_color` (`block_light_color`, the lamp's `Machine.light_color`); `World.entity_lights` maps a lit entity's cell to its colour.

### Water

- Minecraft style cellular flow on the main thread: a change next to water schedules the cell `WATER_FLOW_DELAY_TICKS` (10) later, updates run in scheduling order, at most 256 per tick.
- A machine's cells stay dry (a hydro turbine excepted), and an entity picked up or removed by the developer menu schedules water around the cells it leaves (`schedule_water_around_freed_cells`), so a pool flows into them.

## Simulation

- Entity pools per type (`Entity_Pool` of furnaces, inserters, drills and so on) with generational handles (`Entity_Handle`: kind, index, generation). Each type has its own update procedure over its own array.
- Belts are transport lines ([logistics.md](logistics.md)); fluid and electric networks are rebuilt on topology change and evaluated per tick in fixed point ([fluids.md](fluids.md)).
- Recipes have any number of item or fluid inputs and outputs; crafting machines hold a recipe index and a progress counter. Recipes resolve to dense indices at load.
- Veins are entities, not block data: a reservoir with per ore amounts, centre, radius and size class, placed per region of 8 by 8 chunk columns (`REGION_SIZE_IN_CHUNKS`) so each footprint lies inside its region. Workers compute footprints; the main thread registers a vein once when the first chunk of an overlapping column loads. Drills hold a vein handle; there are no per block ore counters.
- `vein_at_column` finds the registered surface vein under a column for drill placement and the HUD; the geologist's hammer asks for an outcrop block. While the landing pad exists, a region's surface veins also include the starter veins centred in it, after the natural veins and without the natural veins they overlap.
- The game's records are one struct on `Simulation_State` beside the `World` (`Game_Records`, `simulation_state.odin`): statistics, research, shipments, contracts, venture credit, catalogue orders, the five prospecting lists, crate sites, the explored columns and the leaf decay queue. The entity tick's procedures reach the records through their context (next bullet); a tick still on `^World` takes the record it writes (`statistics: ^Statistics`) or the records beside it; the screens reach them through `Screen_Context.records`. Chunk arrival registers the crate sites and the explored column into them (`insert_generated_chunk`), and the world tick runs the leaf decay queue on the world's blocks (`tick_world`).
- The entity tick never takes `^World`: `tick_entities` and the kind ticks under it take an `Entity_Tick_Context` (`simulation_world.odin`) built once per tick by `world_tick_context`, holding the entities, the records, the content, the tick rate, the world's settings, the vein registry's fields (still on `World`) and the block interface: a block query (block and whether its chunk is loaded) and a block write, as procedure values with a data pointer (`Block_Query`, `Block_Write`), the two calls the plugin boundary will carry. `tick_entities_on_world` runs it, then syncs the lit lamps into the world's light (`sync_entity_lights`). The player tick, the magnetometer, the item uses (`apply_item_use`, through the simulation state), the launch requests and the world's own tick (`tick_world`) still take `^World`; the player tick is the next cut.
- Statistics live in the records (`statistics.odin`): produced, obtained, delivered, consumed, voided per item, placed per machine, stalls, fuel burned, blocks mined, distance walked, and per item rate rings of 60 buckets each at one second, ten seconds and one minute, the coarser fed from the finer, all saved. Furnaces, crafting machines and drills keep a 60 bucket ring of their own output for the panel rate. The quests, the statistics screen and the bottleneck overlay read them.
- Shipments (tick and cargo of every launch) live in the records and are saved. The UI's launch requests are served inside the tick, since a shipment needs the tick.
- The venture (`venture.odin`: open contracts, deliveries, offer counts, credit, catalogue orders) lives in the records and is saved. Shipments are served right after the launches: contracts oldest first, then free trade. Levels of infinite technologies live in the research state, since drills and labs read them every tick.
- `Simulation_Content.generator` points at the session's generator (nil in tests), so the orbital survey can chart veins in chunks never loaded.
- Quests are data evaluated against the statistics, entity counts and research state every tick ([quests.md](quests.md)).
- Developer requests are a list on the simulation state (`developer_requests`), filled by the Developer screen, `--chapter` and `--give`, served at the start of the next tick and never saved. The command socket serves the same requests between ticks ([commands.md](commands.md)). Veins added by command live in `World.veins` with `added` set.
- Cheat speed is a simulation flag, not saved ([developer_tools.md](developer_tools.md)). The day cycle reads the tick plus `day_offset_ticks`, saved through the world file's day time field.

## Data driven content

- `data/*.sjson` holds blocks (`name_key`; `discoverable` for an ore that reads "Unknown ore" until its drop was obtained), items, recipes, machines, fluids, technologies, vein types and ore tables, biomes, tree species, quest chapters (`data/quests/`), contracts, developer kits and the touch overlay's layout (`touch_overlay.sjson`, loaded with the tables though only the input layer reads it). The values live in `data/*.sjson`, the rules behind them in [content.md](content.md).
- `load_game_data` parses them with `core:encoding/json` (`Specification.SJSON`) into prototype tables in an arena the frame state owns, one per load. String ids resolve to dense indices once.
- `Game_Content` embeds the registries the simulation reads (`Simulation_Content`) and adds the presentation tables (notes, the touch layout, display names and orders) and the process flags. A session hands the simulation that embedded value with its scaled technologies and its generator (`frame_simulation_content`), and the tick, the command socket's developer requests and the screens see the recipes with the found schematics (`content_with_found_schematics`).

### Hot reload

- The operating system reports changes under the data directory through `shared:fsw` (inotify on Linux, ReadDirectoryChangesW on Windows); the main thread takes the events every frame without reading a file's status. A watcher that cannot open logs one `data: cannot watch` line and stays off for the run.
- What reloads is `--watch-data=<off|presentation|all>` or `settings.watch_data` (default: presentation in developer mode, else off).
- Presentation files reload in place (`data_file_category`): strings, bindings, developer kits, shaders, fonts, models, sounds, textures (both atlases rebuilt; the chunk meshes stay, since the layout depends on the block count alone) and the UI theme (`ui/theme.sjson` and `ui/icons/`). A file that fails keeps the old data and says so.
- Content tables reload only on request: the `reload` command, F8 in developer mode, the Developer screen, or with `watch_data` all after a quiet second.
- A content reload encodes the world through the save codec in memory, the data loads and validates as at start, and the world is decoded back with the content remap; loaded chunks keep their blocks, remapped and remeshed.
- A generator change affects only chunks loaded afterwards; `game.sjson` needs a restart.

### Data edits overlay

Rule: the editors never write a data file; an edit is a copy under `<state>/mine-oh-belowed/data_edits/<relative path>` that wins over the data file (the screen: [developer_tools.md](developer_tools.md), Data files screen).

- Every SJSON file and the shaders are read through `read_data_file(data_directory, relative_path, allocator)` (`data_load.odin`). It takes the overlay copy when one exists and logs `data: <relative path> from the data edits overlay <path>` once per read; a broken copy is reported like a broken data file, naming the overlay path.
- The quest chapter list comes from the data directory's listing. Binary files (png, wav, vox, ttf) and the blueprints never read the overlay.
- The overlay is not watched: the Data files screen's Save and Discard edit (`save_data_edit`, `discard_data_edit`, served by `serve_data_browser` between frames) return the changed file's category, and the frame loop passes them to `apply_data_edit_change(state, changed)` (`hot_reload.odin`), which does what the watcher would for those files, still before the frame's draw.
- Save writes the parsed tree through `sjson_text` (`sjson_text.odin`) in the data files' style: the root without braces, bare keys with `=`, tabs, a container of leaves on one line, integers kept integers and floats given a point, so the text parses back to an equal tree. `json.marshal` is not used: it prints 0.5 as 0.5000000000000000.
- The copy has none of the data file's comments and its object keys sorted by name (`json.Object` keeps no order). Reconciling a copy into the checked in file happens outside the game, by hand or by an agent ([DESIGN.md](../DESIGN.md), Editors).
- A broken copy never stops the start: `main` loads the fonts, bindings, game config, strings and game data through `load_start_data` (`main.odin`); when that fails with the overlay read, `turn_data_edits_off` logs it, turns the overlay off for the run (`data_edits_reading.off`, consulted through `reading_data_edits_directory`) and `main` loads again from the data files. A second failure exits. The chunk shaders and the UI theme, loaded after the window opens, fall back the same way.
- `data_edits_reading` is thread local: the game reads data on the main thread only, and under `odin test` each test thread gets its own overlay directory ("" unless a test sets one), so tests see the shipped data whatever the machine holds.

## Strings and units

- Every player facing string lives in `data/strings/en.sjson` and is referenced by key. The developer diagnostics pages may use literal strings.
- One procedure family formats quantities with their units (per minute, kW, MW, L), so the realism units stay consistent and localisation is a data change.

## Save format

Worlds live under `$XDG_DATA_HOME/mine-oh-belowed/saves/<world>/` (`MINE_OH_BELOWED_SAVES` or `paths.saves` override it).

| File | Holds |
|---|---|
| `world.sjson` | Format version, generator version, name, seed, world settings, tick, day time, last played, the landing pad's centre |
| `entities.bin` | Magic `MOBE`, header, the content id tables, then every entity pool and the simulation state (players, research, quests, statistics, unlocks, shipments, venture, pending block and water updates, loose items, leaf decay) |
| `regions/<x>_<z>.bin` | Only modified chunks of a region, each as a palette plus run length encoded indices |

- `entities.bin` is written by a codec driven by Odin type information (`save_binary.odin`), so a new field cannot be left out silently. Structs carry a schema of field names, shallow kinds and sizes: fields can be added, removed or reordered, and only a retyped field refuses the file. Enums and bit sets go by name; an unknown name reads as zero.
- A fixed array saved shorter than this build's fills its start; a longer one refuses. A slice of fixed length, such as the inventory, refuses on any length change.
- The body writes the world's lists and the records interleaved in the order of format version 2 (`write_world_state` takes both), so moving the records off `World` (0154) left the bytes unchanged.
- Tables added after format version 2 follow the players at the end in the order they were added, each read only while bytes are left (`write_later_tables`, `read_later_tables`): the loose items, then the leaf decay queue. An older file loads with them empty without a version step.
- Loading maps every saved id to this build's by name (`save_remap.odin`): the distinct id types inside the codec, every id indexed array and plain index explicitly, chunk palettes as regions load. What vanished is dropped (a stack empties, a queued technology dequeues, a gone active quest gives way to the first quest not done); a placed machine, a registered vein's type or a chunk block that vanished refuses the file.
- Kept by index, not remapped: vein size classes, quest objective and hint arrays, contract deliveries.
- A file without a generator version reads as 1. An older generator version still loads, is marked "terrain changed" in the load list, and its unmodified chunks regenerate with the new terrain. A file without a pad centre falls back to the spawn search.
- The title's save list (`save_list.odin`) reads each save's versions and content tables, so a save of another format shows as not loadable instead of failing at load.
- Unmodified chunks regenerate from the seed. Light is not saved: a loaded chunk recomputes sky light with the generation procedure and re-seeds block and entity lights. Networks are rebuilt after load.
- Saving runs on the main thread between ticks, writes to `<world>.saving` and swaps it in through `<world>.previous`, so a crash leaves a complete save; with only `.previous` left, loading falls back to it. Autosave counts simulated ticks.
- Regions use palette plus run length, not zlib: `core:compress/zlib` only inflates.

## Configuration and directories

- SJSON layers, lowest first: `$XDG_CONFIG_DIRS/mine-oh-belowed/config.sjson` (last entry to first), `$XDG_CONFIG_HOME/mine-oh-belowed/config.sjson`, `config.d/*.sjson` by file name, then `--set=<key>=<value>`. No project layer.
- Trees merge with provenance per key (objects merge, scalars and arrays replace), then map onto `Configuration` (settings, bindings, paths) strictly: an unknown key, a wrong type or an out of range value is an error naming the file. `settings.shadows` is a retired key, accepted and ignored with a log line.
- `mine-oh-belowed config` prints the files in precedence order and the effective values with their source.
- Every screen that changes a setting writes `config.d/90-settings.sjson`, strings quoted. The export settings `settings.export_directory` (default empty) and `settings.export_on_save` (default false) are ordinary keys, so the phone's file can set them over USB.
- The touch layout editor writes `touch_overlay.sjson` beside `config.d/`, a file of its own, no configuration layer ([touch_overlay.md](touch_overlay.md)).
- The files the game writes and reads back (the settings, the touch layouts, the texture edits, the data edits, the export) go through `platform.write_file_replacing`: written beside the path as `<path>.tmp`, then renamed over it, so a crash or a full disk mid write leaves the old file whole. A save gets the same guarantee from its staging directory, renamed whole.
- A `config.d/90-settings.sjson` that stops the start (cut off, or a value the validation refuses, found by loading again without it) is renamed to `90-settings.sjson.broken`, one `configuration:` log line names it and the problem, the game starts on the other layers, and the title screen toasts it once (`load_configuration_at_start`, 0149). A problem in any other file or in `--set` still logs the error and exits: the user wrote those, and strictness surfaces their typos.
- `platform_directories` (`platform_paths.odin`) is the one place that reads the base directories from the environment; the pure path helpers apply the rules. Every directory is made through `make_directory_path`, never `os.make_directory_all` ([android.md](android.md) has why).

| Base | Linux | Windows | Android |
|---|---|---|---|
| Config home | `$XDG_CONFIG_HOME`, else `~/.config` | `%APPDATA%` | `<files>/config` |
| Config dirs | `$XDG_CONFIG_DIRS`, else `/etc/xdg` | none | none |
| Data home (saves) | `$XDG_DATA_HOME`, else `~/.local/share` | `%APPDATA%` | `<files>/share` |
| State home | `$XDG_STATE_HOME`, else `~/.local/state` | `%LOCALAPPDATA%` | `<files>/state` |
| Runtime directory | `$XDG_RUNTIME_DIR` | none | none |

- A relative XDG value is ignored. On Windows a missing variable means no directory and a leading `~/` stays as written. On Android `<files>` is the activity's external files folder, else the internal one.
- The state directory `<state home>/mine-oh-belowed/` holds `log.txt` (on Windows the log sits beside the executable), `screenshots/`, `texture_edits.sjson` and `data_edits/` (mirroring the data directory: `data_edits/blocks.sjson`, `data_edits/quests/chapter_01.sjson`).

## Logging

- `log_printf` writes every line to stderr and to `<state>/mine-oh-belowed/log.txt` (appended, one header line per start with the build stamp); on Android also to logcat.
- When stderr is not a terminal (Steam), the log file is put on the stderr descriptor so Odin's runtime reports (bounds checks, type assertions) land in the log; the game's own lines go once to the log and once to the original stderr.
- raylib's trace log takes the same path through a callback (`raylib_log.odin`), which drops GLFW's feature unavailable error (65548): on Wayland every window position query raises one, raylib makes them at start and on every monitor lookup, and nothing is wrong.
- After the display line the start logs one `gl:` line with the GL vendor, renderer, version and GLSL version (`log_gl_info`: `glGetString` through `glfwGetProcAddress`, so nothing links libGL or opengl32; on Android straight from `libGLESv3`), because a translation layer under Wine can reject a shader without naming itself.
- The SDL3 backend logs the joysticks SDL sees at start and one line per joystick added or removed (name, vendor, product, GUID, whether SDL has a gamepad mapping), so a controller SDL sees but does not map is told apart from one it never sees.
- Main thread assertions and panics log a back trace; SIGSEGV and SIGILL write a raw back trace from the signal handler before the process ends (not on Windows or Android).

## Platforms

Rule: platform code is split by build tags, never by `when` around an import, since an import of `core:sys/posix` links the static C runtime on Windows by itself ([build.md](build.md), Windows).

| Concern | Shared | POSIX (`#+build !windows`) | Windows (`#+build windows`) |
|---|---|---|---|
| Logging | `logging.odin` | `logging_posix.odin` (redirect, signal handlers) | `logging_windows.odin` (stderr as is, no redirect, no handlers) |
| Command socket | `command_socket.odin` | `command_socket_posix.odin` | `command_socket_windows.odin` (stubs: no socket on Windows, [build.md](build.md), What the Windows build lacks) |
| Local time zone | `local_zone.odin` | `local_zone_posix.odin` | `local_zone_windows.odin` (`GetTimeZoneInformation`, since ICU aborts under Wine) |

- Android splits by the subtarget tags `#+build linux:android` and `#+build !linux:android`: `main_android.odin`, `input_sdl3_android.odin`, `haptics_android.odin`, `system_keyboard_android.odin`, in the platform package `platform_android.odin`, `jni_android.odin` and `export_access_android.odin`, and the leaf package `android_libc/` ([android.md](android.md)).

## Testing

- `./build.sh test` runs the tests of the game package and the packages under `src/` (`odin test -all-packages`). Pure procedures get unit tests: noise and generation, belt line arithmetic, recipe resolution, run length coding, the save codec and remap.
- Determinism: the `*_is_deterministic` tests run two identical worlds (belts, inserters, generation, fluids, combustion and more) and compare their state; `simulation_state_hash` hashes the save bytes for the save and reload tests.
- Tests that guard rules: `test_static_runtime_imports_stay_out_of_windows`, `test_game_sources_do_not_call_make_directory_all` (`platform_paths_test.odin`), the shader literal check (`shader_source_test.odin`), `texture_periodicity_test.odin`.
- Rendering and input are verified by playing.

## Performance

Target: 1080p at 60 frames per second on the couch machine (AMD Navi 10, Radeon RX 5700 class), 60 ticks per second with several thousand belts and hundreds of machines; chunk generation keeps up with a sprinting player.

- The headless factory benchmark (`benchmark_factory.odin`) runs through `test_factory_benchmark` (sizes 1 and 4, two minutes of warm up and one measured) and `--benchmark=<size>` (1 to 16, two and ten minutes; [build.md](build.md)). `./build.sh bench` runs the test optimised and fails when size 4 averages 8 ms per tick or more.
- Sizes stop at 16 (`BENCHMARK_LARGEST_SIZE`): the cost per tick is close to linear in the size, so larger factories are read off size 16, and a size 64 build took minutes of network rebuilds.
- The profile: `simulation_tick` and `tick_entities` take an optional `^Tick_Profile` (`tick_profile.odin`) and add each step's wall time to its `Tick_Section`. Without a profile no clock is read. The runner also times each whole tick for the average and the worst.
- The flat world: no generation and no streaming. `build_benchmark_world` fills every chunk column under the layout plus one chunk of margin, chunk y -1 and 0 stone with grass on top (world y 31), y 1 and 2 air, all under full sky light. The generator serves only the vein tables; veins are added where the manifest puts them, checked against each other only.
- The pad and the player stand in opposite corners of the floor. Research costs 1000 times its packs, so the one technology the builder queues outlasts every run.
- The layout is content: `data/blueprints/benchmark.sjson` lists modules with a footprint, copies per size and veins. `benchmark_layout` gives each module a column along x and its copies along z, 4 blocks apart, centred on the origin. Each copy runs its blueprint from `data/blueprints/benchmark/` (origin `[0, 0, 0]`, overridden with the copy's cell) through `run_blueprint`, after its veins are added.
- Modules: `smelting.sjson` (iron), `assembly.sjson` (gears, circuits, science pack 1 and a lab), `power.sjson` (steam), `oil.sjson` (refinery, cracking, plastic, flare); each file's header comment describes it. Every module has its own veins and power, so the cost grows linearly and no module starves another.
- A machine without progress over the last minute of the warm up is idle and fails the test and the command: drills and furnaces by their output rate, inserters by an idle streak of a whole minute, crafting machines, labs, fluid machines and launch pads by their working state on some tick. A generator in the Idle state is a reserve behind a lower dispatch order, not idle (0140).
