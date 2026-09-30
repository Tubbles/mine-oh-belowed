# 0146: The cut between engine and game logic (design brief)

Status: todo (design, not to be implemented before the user and the main agent have fleshed it out together)

## Goal

The user's direction for after the architecture cleanup (2026-09-30): a cut between engine code and game logic, with the game logic behind WebAssembly plugins as in the user's repository heimdall, and possibly an entity component system to lower the coupling. Both need a lot more design between the user and the main agent before any code moves. This item holds the questions, the evidence the audits (0143) gather for them, and the pattern heimdall already uses, so the design conversation starts from facts.

## The heimdall pattern (read from `github.com/Tubbles/heimdall`, 2026-09-30)

- The engine (`src/`: config, console, input, level, log, player, plugin, point, rect, render, wasm, wasm_host_procs, wasm_libm_shims) is a native Odin program. A plugin (`plugin/`) is an Odin package built to wasm and loaded through wasmtime (`module/wasmtime-bindings`, `module/wasm-bindings`).
- The plugin exports `init`, `update(delta_time)` and `draw` with the C calling convention, sets up the Odin context and runtime itself, and calls back into a raylib shaped API (`module/waylib`) that the engine implements as host functions; the host reads guest memory through bounds checked views (`guest_bytes`, `guest_value`, `guest_string`), little endian on both sides, raylib types with the same layout.
- Each plugin has its own wasmtime store, module and instance, so one can be unloaded or reloaded alone; a trap disables the plugin until the next reload.
- Configuration is SJSON (`heimdall_config.sjson`) as here.

## What this game would need beyond that pattern

- The plugin surface here is not a frame (`update`, `draw`) but a deterministic tick over shared world state: machines, belts, fluids, power, quests and recipes read and write chunks, entities and inventories every tick at 60 Hz. The audits answer how much data crosses the boundary per tick and whether it can be batched into a few calls.
- Determinism and saves: the plugin's state must be part of the save and replay deterministically; heimdall keeps plugin state inside the guest memory, which the save codec would have to serialize or the plugin would have to expose.
- Content stays in `data/`; the question is which rules read it: the engine (a generic machine that runs a recipe) or the plugin (the recipe semantics). The audits mark each cluster as engine, game or both.
- Rendering of game entities: the engine draws chunks and models; the plugin would describe what to draw (entity kinds, animation state) rather than draw.
- Lifetime, interop and intercom: load order, reload with a live world, calls from plugin to plugin, error isolation, versioning of the interface, and the performance of the wasm boundary at the tick rate (measured with the factory benchmark before deciding).

## The entity component lens

- Today entities are arrays of structs per kind (`Entities` with 21 fields) with a fixed tick order; the audits list which per entity data would be components and which systems exist implicitly.
- An ECS lowers coupling only if the systems stop reaching into each other's arrays; the audits find where that reach-through is today.

## Next steps

- After 0143 and 0145: the main agent writes a design proposal under `doc/` from the audits' engine or game sections and the pilot split's cost, with the open questions above answered or marked; the user and the main agent flesh it out together before any work item implements it.

## Verify

- Nothing to run: the item is closed when the design proposal exists and the user has approved it, or when the user drops the direction, recorded in `doc/log/`.
