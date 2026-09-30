# 0143: Architecture audit, one report per cluster

Status: implemented

## Goal

The second step of the architecture cleanup (user, 2026-09-30). The measurements say the debt is coupling, not clutter: 182 of 193 non-test files form one strongly connected component, `Frame_State` has 69 fields, `Ui_State` 58, `Screen_Context` 54, and `loop.odin` changed in 86 commits. The audits find where the seams are, which refactors buy the most, and gather the evidence for two ideas the user wants weighed later (0146): a cut between engine and game logic with the game logic behind wasm plugins, and an entity component system to lower the coupling.

## Clusters

One subagent per cluster, in series, each writing `doc/audit/<cluster>.md`. The prefixes below are the core of each cluster; `tools/code_graph.py` (0142) assigns the single file prefixes (`tick`, `weather`, `venture`, `schematic`, `recycler`, `prospecting`, `production`, `landing`, `discovery`, `deck`, `biome`, `tree`, `quick`, `diagnostics`, `developer`, `hot`, `benchmark`) to the cluster they have the most edges into, and the audit corrects that assignment in its report where it is wrong.

- `loop`: `loop.odin`, `main.odin`, `main_android.odin`, `session.odin`, `simulation.odin`, `hot_reload.odin`, the hubs `Frame_State`, `Screen_Context` and `Ui_State`, the frame and tick order, the requests served between frames.
- `ui`: `ui_*`, `hud.odin`, `touch_overlay.odin`, `input_*`, `bindings.odin`, `text_input.odin`, `system_keyboard_*`, `haptics_*`.
- `world`: `world_*` (except the screen), `generation_*`, `save_*`, `block_shape.odin`: the chunk storage, light, water, meshing, streaming, the save codec.
- `simulation`: `entity*`, `belt*`, `splitter.odin`, `inserter.odin`, `fluid*`, `power_*`, `machine*`, `assembler.odin`, `furnace.odin`, `drill.odin`, `lab.odin`, `launch_pad.odin`, `crafting.odin`, `inventory*`, `item_transfer.odin`, `player*`, `loose_item.odin`, `statistics.odin`.
- `presentation`: `render_*`, `model_*`, `texture_*`, `particles.odin`, `ambient_life.odin`, `audio.odin`, `sound_events.odin`, `display.odin`, `raylib_log.odin`.
- `content`: `data_*`, `item.odin`, `recipe*` (except the browser), `technology.odin`, `quest*`, `contract.odin`, `notes.odin`, `configuration*`, `settings.odin`, `command*`, `logging_*`, `local_zone_*`, `platform_*`, `export_*`, `sjson_text.odin`, `run_length.odin`, `jni_indices.odin`.

## Each report

Written for a reader who knows the game but not the code, in the docs' style (summary on top, rule first, one fact per bullet, names verified). Sections:

1. What the cluster is: responsibilities, entry procedures, the files with their one line purpose.
2. State: the structs it owns, who else writes them, what lives in the hubs (`Frame_State`, `World`, `Entities`, `Ui_State`, `Screen_Context`) on its behalf.
3. Coupling: its edges in and out from `tools/code_graph.py`, which of them are essential and which are reach-through (a screen reading the world directly, a simulation file calling UI), the cycles it takes part in.
4. Abstraction gaps: repeated patterns without a shared procedure, missing seams, parameters passed in bundles that should be types, god structs, places where a feature was added by a branch in a hub instead of a table.
5. Refactors, ranked: each with the files touched, the tests that guard it, the expected gain (edges cut, hub fields removed, lines removed) and the risk, so the main agent can turn it into a work item without a second look.
6. Engine or game: which parts are engine (platform, rendering, input, the UI toolkit, world storage, data loading, the save codec, the command socket) and which are game logic (content rules, machines, quests, recipes, progression), which parts are both today, and what interface the game side would need from the engine if it sat behind a plugin boundary (calls per tick, data crossing the boundary, determinism, save state).
7. Entity component lens: which per entity data would become components, which systems exist implicitly (the tick order), where arrays of structs already give the same shape, and what an ECS would cost and buy here.
8. Tests: what is covered, what is not, which tests pin implementation rather than behaviour.

The main agent reads each report, spot checks its claims, and appends the key findings to `doc/log/YYYY-MM-DD.md` as the audit's section, so the findings are documented as they arrive. The reports are checked in under `doc/audit/` and listed in `doc/README.md`.

## Verify

- `python3 tools/check_docs.py` passes with the reports in the tree (every name they cite exists).
- The main agent's spot check: five claims per report against the code.
- `./build.sh check` and `./build.sh test` unchanged (audits change no code).

## Implementation notes

Six reports under `doc/audit/` (loop 163 lines, ui 224, world 174, simulation 241, presentation 201, content 205), one Opus agent each in series, five claims per report spot checked by the main agent against the code (all thirty held), each report's findings appended to `doc/log/2026-09-30.md` as it landed. `python3 tools/check_docs.py` passes with the reports; no code changed.

Decisions the audits settle:

- No entity component system. The simulation audit sizes it against the code: sixteen kinds with few fields, multi pool systems that already go through accessors, pool index order as part of the determinism, and coupling that no storage layout touches. The middle path is a `[Entity_Kind]` table with pool views and component locations over the existing pools, then shared component structs once the save codec reads `using` fields.
- The engine or game cut, as the six reports draw it: engine is the frame loop and the request pattern, the input layer and the UI toolkit (which makes no raylib call), world storage with light, water, meshing, streaming and the save codec, the generation framework, the atlas, meshes, shaders and the audio device, the loader framework, strings, configuration, logging, the command transport and the platform pairs. Game is the tick order and the machines, placement rules, the screens and the HUD's meaning, the vein tables, biomes and spawn, the per kind draws and sound choices, the registries' semantics, quests, contracts, the venture and the dev kits. The seams a plugin boundary needs, none of which exists yet: a queue for the simulation writes that land outside the tick (the screens' 22 procedures and 9 field writes, chunk arrivals, the command socket), a per frame machine view for the renderer and the panels, a draw list instead of direct raylib calls, a per tick event list instead of the memories diffing counters, and ticks that take the simulation records instead of `^World`. 0146 builds on this.
- Cluster corrections for `tools/code_graph.py`: `hot_reload.odin` to loop; `developer.odin`, `quest_runtime.odin`, `recipe_unlocks.odin`, `venture.odin`, `recycler.odin`, `schematic.odin`, `prospecting.odin` to simulation; `player_animation.odin` and `weather.odin` to presentation; `quick_transfer.odin` to ui; `platform` and `tools` (command socket, data browser, export) as clusters of their own. 0144 writes the map from this.

Bugs found on the way, queued in `SUGGESTIONS.md`: three files written in place against the hand-back rule (settings, touch layouts, texture edits) with `main` exiting on a malformed settings file; water never scheduled when a machine leaves a cell; the glyph bar ignoring rebindings; belt items positioned per tick under an interpolating belt surface (to be seen on the couch first); the shader copies of the variation hash and light curve untested; the content loaders accepting unknown keys; the generator naming blocks in code.

The refactor queue across the reports, in the order the prerequisites suggest (each entry is ranked in its report with files, guards, gain and risk):

1. Pure moves and the cluster table, no behaviour change: the simulation state out of `loop.odin`; rename `column` and move `world_settings_from_file` and the JNI helpers; `Box` and the coordinate helpers to the world files; `join_save_path`, `sorted_object_keys` and the build stamp parameter to free the platform leaves; the toolkit pieces out of the screen files. This is the 0145 prerequisite.
2. The bug fixes above.
3. The hubs: embed `Simulation_Content` in `Game_Content`; narrow the serve procedures; the game's records off `World` (byte compatible); ticks without `^World`; `Frame_State` into groups; `Screen_Context` by consumer; the UI views out of `Session`.
4. The tables: the `[Entity_Kind]` table with component locations; one burner step; the screen table; one theme copy; one loader body with unknown key refusal and the hand written lookups on `find_definition_index`; one request table in the loop.
5. The seams: the per frame machine view; the cell change and topology seam; chunk arrivals as a list the tick drains; one per tick event detector; the draw list.
6. Decisions for the user: the name framed save top level; shared component structs after codec support; the furnace as a crafting machine; a full package split after 0145.
