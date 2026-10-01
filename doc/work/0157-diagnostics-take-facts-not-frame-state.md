# 0157: Diagnostics take facts, not the frame state

Status: todo (after 0155)

## Goal

Refactor 4 of the loop audit (`doc/audit/loop.md`, section 5). `diagnostics.odin` is developer tool code (the tools cluster), but twelve of its procedures take the whole `Frame_State` by value and reach through `state.session.simulation` fifteen times, `state.ui.fonts`, `state.input.raw`, the content tables, `state.settings.bottleneck_overlay`, `state.session.streaming`, the generator, the accumulator and two renderer counters. The loop audit's refactor 5 (0158, grouping `Frame_State`) wants fewer procedures that take the whole state first.

## Change

- One struct the loop builds once per frame when a diagnostics page or the world overlay is shown (name it after what it is, for example `Diagnostics_Context`): a pointer to the simulation state, the technologies, the streaming facts, the generator and accumulator facts the pages read, the input frame, the fonts, the content tables the pages name, the bottleneck overlay setting, the page selector, and the renderer counters (which may join `Render_Facts`). Pointers where the page reads live state (the simulation), values where it reads a number. Built by one procedure in `loop.odin`; `diagnostics.odin` never names `Frame_State` afterwards (`grep -c Frame_State src/diagnostics.odin` prints 0).
- `draw_diagnostics_page`, `draw_world_overlay`, `mapped_lines` and the `*_text` procedures take the struct (or the one field they read, where that is a single value). `diagnostics_test.odin` builds the struct directly instead of a `Frame_State`.
- `tools/code_graph.py`: `hot_reload.odin` moves from the content cluster to the loop, as the audit's section 2 asks (every procedure in it takes `^Frame_State` and is served between frames). `doc/code_map.md`: the content -> loop record falls by the references that leave it; any record that rises because references changed cluster is explained in the item's notes (the 0147 precedent), never raised silently; `python3 tools/code_graph.py --check doc/code_map.md` prints "0 new or grown".
- `doc/developer_tools.md` (or the doc that owns the diagnostics pages) names the struct in one sentence if it describes how the pages get their numbers; otherwise no doc change.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `diagnostics.odin` has no `Frame_State`; the pages themselves need a playtest (the user), named in the wrap-up.
