# 0143: Architecture audit, one report per cluster

Status: todo

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
