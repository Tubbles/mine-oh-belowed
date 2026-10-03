# 0157: Diagnostics take facts, not the frame state

Status: implemented

## Goal

Refactor 4 of the loop audit (`doc/audit/loop.md`, section 5). `diagnostics.odin` is developer tool code (the tools cluster), but twelve of its procedures take the whole `Frame_State` by value and reach through `state.session.simulation` fifteen times, `state.ui.fonts`, `state.input.raw`, the content tables, `state.settings.bottleneck_overlay`, `state.session.streaming`, the generator, the accumulator and two renderer counters. The loop audit's refactor 5 (0158, grouping `Frame_State`) wants fewer procedures that take the whole state first.

## Change

- One struct the loop builds once per frame when a diagnostics page or the world overlay is shown (name it after what it is, for example `Diagnostics_Context`): a pointer to the simulation state, the technologies, the streaming facts, the generator and accumulator facts the pages read, the input frame, the fonts, the content tables the pages name, the bottleneck overlay setting, the page selector, and the renderer counters (which may join `Render_Facts`). Pointers where the page reads live state (the simulation), values where it reads a number. Built by one procedure in `loop.odin`; `diagnostics.odin` never names `Frame_State` afterwards (`grep -c Frame_State src/diagnostics.odin` prints 0).
- `draw_diagnostics_page`, `draw_world_overlay`, `mapped_lines` and the `*_text` procedures take the struct (or the one field they read, where that is a single value). `diagnostics_test.odin` builds the struct directly instead of a `Frame_State`.
- `tools/code_graph.py`: `hot_reload.odin` moves from the content cluster to the loop, as the audit's section 2 asks (every procedure in it takes `^Frame_State` and is served between frames). `doc/code_map.md`: the content -> loop record falls by the references that leave it; any record that rises because references changed cluster is explained in the item's notes (the 0147 precedent), never raised silently; `python3 tools/code_graph.py --check doc/code_map.md` prints "0 new or grown".
- `doc/developer_tools.md` (or the doc that owns the diagnostics pages) names the struct in one sentence if it describes how the pages get their numbers; otherwise no doc change.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `diagnostics.odin` has no `Frame_State`; the pages themselves need a playtest (the user), named in the wrap-up.

## Notes

`Diagnostics_Context` (`diagnostics.odin`), built by `diagnostics_context` (`loop.odin`) in the frame's diagnostics switch only when a page or the F4 overlay shows; the World page builds it once and hands it to `world_facts` as well.

| Field | Why |
| --- | --- |
| `simulation: ^Simulation_State` | live state with many reads (tick, world chunks, veins, light, labs, players, unlocks, quests, records); a pointer instead of the copy `Frame_State` by value made |
| `technologies: Technology_Registry` | research line; two slices, so a value |
| `blocks`, `items`, `quests` | the content tables the player, quest and objective lines name |
| `input: Input_Frame` | the Input page's mapped and raw columns |
| `fonts: ^Font_Cache` | every page draws through it |
| `page: Diagnostics_Page` | the header and the page switch |
| `bottleneck_overlay: bool` | the overlay's bottleneck line |
| `pending_job_count`, `seed` | the streaming line reads one number of `Chunk_Streaming` and one of `Generator`, so values, no `Session` |
| `tick_interpolation: f64` | `interpolation_alpha(session.accumulator)`, computed by the builder; the field is not named `interpolation_alpha` because the graph counts a field named like a procedure as a reference |
| `drawn_chunk_count`, `vertex_count` | the world line; `Render_Facts` has them too but is built on the Render page alone, while the overlay line shows on every page |

Procedures changed: `mapped_lines`, `draw_diagnostics`, `draw_diagnostics_page`, `world_statistics_text`, `streaming_statistics_text`, `world_overlay_statistics_lines`, `draw_world_overlay`, `append_player_lines`, `research_diagnostics_text`, `quest_diagnostics_text`, `objective_counters_text` take the struct; `light_statistics_text` takes `^Simulation_State`, the one field it reads. `light_statistics_text` and `append_player_lines` now read the live world through the pointer instead of a copy of the `World` struct; both only read. `world_facts` takes the context beside the state. `test_diagnostics_lines_print_the_context` (`diagnostics_test.odin`) builds the struct over `make_developer_test_simulation` without a window and pins the overlay's world line (`chunks 0  drawn 3  vertices 9`), its streaming line (`pending jobs 7` ... `seed 42`) and the Input page's tick line (`tick 0`).

`hot_reload.odin` was already in the loop cluster (`"hot"` was in the loop's prefixes when the code map landed in 0144, commit `a7700c6`), so `tools/code_graph.py` is unchanged and content -> loop stays 19.

Records (`doc/code_map.md`):

| Edge | Before | After |
| --- | --- | --- |
| tools -> loop | 16 | 3 (the 12 `Frame_State` references and `interpolation_alpha` left) |

No record rose.
