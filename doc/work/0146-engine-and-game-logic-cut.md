# 0146: The engine and the game: the cut, the plugins and the object model (design brief)

Status: todo (design, on the back burner since 2026-10-02: the user wants the smooth world of `doc/log/2026-10-02.md` first and the plugin system kept in mind as the code goes; the cut below stays the guide for where code belongs, and `doc/work/0167-smooth-world-engine-brief.md` carries the engine side forward)

## The direction (user, 2026-09-30 and 2026-10-01)

A voxel 3D engine on which any style of game can be built (RPG, RTS, MMO, puzzle, MOBA, first or third person), with everything game logic and design related living at the plugin level: a WebAssembly plugin engine as in the user's repository heimdall, and Mine oh Belowed implemented as the first plugin. That needs a plugin management layer with clean definitions of lifetime, interop and intercom, a vision of what the engine is (where the cut falls), and an object composition strategy that lowers the coupling the audits measured (`doc/audit/`, 0143).

## The heimdall pattern (read from `github.com/Tubbles/heimdall`, 2026-09-30)

- The engine (`src/`: config, console, input, level, log, player, plugin, point, rect, render, wasm, wasm_host_procs, wasm_libm_shims) is a native Odin program. A plugin (`plugin/`) is an Odin package built to wasm and loaded through wasmtime (`module/wasmtime-bindings`, `module/wasm-bindings`).
- The plugin exports `init`, `update(delta_time)` and `draw` with the C calling convention, sets up the Odin context and runtime itself, and calls back into a raylib shaped API (`module/waylib`) that the engine implements as host functions; the host reads guest memory through bounds checked views (`guest_bytes`, `guest_value`, `guest_string`), little endian on both sides, raylib types with the same layout.
- Each plugin has its own wasmtime store, module and instance, so one can be unloaded or reloaded alone; a trap disables the plugin until the next reload.
- Configuration is SJSON (`heimdall_config.sjson`) as here.

## The cut, as the audits draw it

Rule: the engine decides when a tick, a frame or a request runs and owns everything that knows no item, machine, recipe or quest; the plugin decides what a tick does.

The engine knows:

- Voxels: chunks of block ids, a block registry the plugin supplies at load (shape, light emission and attenuation, opacity, collision, texture tiles, variant rules), light, meshing, streaming with workers, the raycast over blocks, the chunk codec, a cell occupant index (opaque handle plus flags such as blocks light, blocks water, solid) so light, water, raycast and collision know a cell is taken without knowing by what (world audit, refactor 5).
- Assets by id: models, textures, sounds, fonts, shaders, loaded from files the plugin names.
- Per frame descriptions the plugin hands over: a camera, a draw list (model id, transform, animation phase, tint, light cell), particle spawns, sounds to play, lights, the UI draw list (the UI toolkit makes no raylib call today and compiles into the plugin: ui audit).
- Input: devices, bindings, the action layer, the touch overlay as a virtual gamepad; the plugin declares its actions and receives an input frame per tick.
- The frame and tick order, the request pattern served between frames, hot reload of assets and plugins, the command socket transport, configuration, settings persistence, logging, the platform pairs, file IO for saves (the bytes come from the plugin).
- Services every game wants and that the engine can make a quality of its own: the "no perceivable repetition" clusters for sounds and animation cadences (`DESIGN.md`), the deterministic tick with replay, the scheduled cell queue (water, decay) as a generic service if its rules can be expressed to the engine, else water stays a plugin system over the block API.

The plugin owns:

- All entities, their storage and their systems (the sixteen kinds and the three networks here), placement rules, the players' logic, inventories, crafting, recipes, technologies, quests, contracts, the venture, the dev kits; the screens and the HUD's meaning; the vein tables, biomes, features and spawn rules (generation could be a plugin called once per chunk per worker: world audit, section 6); the save codec for its own state (a schema codec compiled into the plugin survives a rebuilt plugin, a raw memory snapshot does not).

The interface, per tick and per frame:

- One `update` call per tick with the input frames; inside it the plugin reads and writes blocks through host functions (26 read sites and 4 write sites in the simulation today, mostly placement; cheap as host calls, or batched as lists).
- Into the plugin as queued inputs applied at the start of its next tick, never written from outside: chunk arrivals with the game's records (today `insert_generated_chunk` writes `World` on the frame side), the screens' writes (22 procedures and 9 field writes today, ui audit), command socket edits. With those queued the plugin is a pure function of its inputs: replay, lockstep and an MMO server follow from it.
- Out of the plugin per tick: an event list (what happened since the last tick: the sound and animation memories diff counters today, presentation audit); per frame: the draw list, the UI draw list, the camera, the sounds. The renderer reads shared parts in 23 of its 35 pool loops today, so the per frame machine view is the seam (presentation audit).

## Object composition: the recommendation

Rule: the engine is entity agnostic; composition is the plugin's, provided by a game kit every plugin compiles in.

- The engine has no entity kinds and no generic entity store. It never iterates game entities: it needs per frame descriptions and the cell occupant flags, nothing more. A host side entity store would put every component read of a 60 Hz factory tick behind a host call, which is the one cost wasm cannot pay; entities therefore live in guest memory, and the engine reads views of them (pointer and length) as heimdall does.
- The game kit (a collection shared by plugins, as heimdall's `module/`) gives the programming model of an entity component system without its dynamic storage: kinds are the archetypes, fixed at compile time; a kind struct embeds the component structs it carries (`using`); a kind table lists each kind's pool and the offset of every component it carries; systems iterate component views across kinds (a burner system over every kind with a burner, a progress system, a port system, a power system); handles are generational and carry the kind; pool index order is the iteration order, so determinism comes free. This is the simulation audit's middle path (its section 7), which the audit sized for this game: it removes the per kind switches and the duplicated burner and progress code, keeps the save byte for byte for the first step, and asks for codec support of `using` fields for the second.
- The view interface is the part that must be right for a general engine, because a second game with runtime composition (status effects on an RPG character, buffs in a MOBA) can add a dynamic component store behind the same views without the systems changing. The kit starts static because the first plugin has fixed kinds and its determinism depends on pool order; a dynamic store is added when a game needs it, not before (the user's rule against speculative flexibility).
- Why not a classic dynamic ECS from the start: handles would lose the kind that the renderer, the panels and the save dispatch on; a dense store with swap removal reorders on every removal, which breaks the determinism the tests pin; the save needs a new format; and the audits show the coupling that matters (ticks taking `^World`, the renderer's direct pool reads) is cut by seams, not by storage.
- Content as prototypes: a machine definition in data could list the components it carries (burner, slots, ports, power) instead of per kind fields; the content audit's section 7 ties this to the kind table. Decided with the kit.

## What the refactor queue builds (0143, Implementation notes)

- Pure moves and the bug fixes: the tree the cut starts from (0147 to 0151).
- The hubs: the game's records off `World` and ticks without `^World` give the plugin its state and the engine its block API; `Frame_State` in groups separates engine groups from game groups; `Screen_Context` by consumer and the UI views out of `Session` separate the engine session from the game's views.
- The seams: the queued writes, the per frame machine view, the per tick event list, the draw list, the cell occupant index, chunk arrivals as a list. Each is one boundary call in the future interface, built and tested inside one package first.
- The tables: the kind table with component locations is the first piece of the game kit.

## Open questions for the design session

- Lifetime: load order, a plugin reload with a live world (the loop audit names `reload_simulation`'s encode, load, decode route), what happens on a trap mid tick (roll back the tick, or disable the plugin and keep the world).
- Interop: the host function surface and its versioning; strings and structs across the boundary (heimdall's guest views); the cost per tick measured with the factory benchmark before the design is fixed.
- Intercom: several plugins (the game plus mods, or the game split into plugins) and how they call each other: through the engine as events, or direct exports; whether the game kit's handles cross plugin borders.
- The UI toolkit: compiled into the plugin with a draw list and text measurement across, or an engine service driven per widget call (the per call cost decides).
- Water and other cellular systems: engine service with plugin rules, or plugin system over the block API.
- Generation: in the engine with content tables, or a plugin instance per worker thread.
- Saves: plugin owned bytes with the schema codec in the kit, the engine owning the files and the world's blocks.
- Networking for MMO and lockstep: what the deterministic tick with queued inputs gives for free and what it does not (interest management, authority).
- Assets: who owns the pipeline (vox models, generated textures, generated sounds) and whether generation moves into plugins.

## Next steps

- After the refactor queue's hubs and the first seams: the main agent writes the design proposal from this brief, the audits' engine or game sections and the pilot split's cost, with the open questions answered or marked; the user and the main agent flesh it out together before any work item implements it.

## Verify

- Nothing to run: the item is closed when the design proposal exists and the user has approved it, or when the user drops the direction, recorded in `doc/log/`.
