# 0161: Split Screen_Context by consumer

Status: implemented

## Goal

Refactor 7 of the UI audit (`doc/audit/ui.md`, section 5; the field table in section 2). `Screen_Context` (`ui_screens.odin`) has 54 top level fields passed whole to every screen and the HUD: 8 process fields, 14 content tables copied from `Game_Content`, 10 simulation fields, 4 session views, 9 developer fields, 9 HUD and touch derivations the loop computes. Nine fields are read in exactly one place; `draw_hud` takes the whole struct for 4 HUD fields plus its world reads. After 0152 the content group is `Simulation_Content` plus names, after 0159 the views are one struct, after 0160 the request pointers are one. `audit_screen_context` (`ui_audit_test.odin`) builds the whole struct for every case and shrinks with it.

## Change

- The content group becomes one embedded field (`using content: Game_Content` or the narrower struct the screens read; the implementer greps which of the 14 tables the screens use and says whether `Simulation_Content` plus names covers them), so a screen reads `screen_context.items` as today while the struct lists one field.
- The developer group becomes one pointer to the loop's developer tools group (`Frame_Developer_Tools`, 0158) or a small struct of what `ui_developer.odin` and the two editors read; the implementer chooses after reading the 9 fields' readers and says why.
- A HUD context for `draw_hud` and `draw_biome_banner`: the 4 touch derivations (`touch_aims`, `mining_ring_centre`, `touch_hud_buttons`, `discovery_card_clearance`), the biome index (the frame samples the column once and the banner stops calling `sample_column` on the generator every frame, the UI audit's section on `biome_banner.odin`), the player and the world reads the HUD makes. `draw_hud` takes it instead of the whole `Screen_Context`; `make_screen_context` or a sibling builds it.
- The session views pointer group (0159) and the request set pointer (0160) stay single fields. The simulation fields stay as they are unless one is read in a single place and can move with its reader; list them in the notes rather than moving them.
- `Screen_Context` ends with about 12 top level fields; `audit_screen_context` builds the groups; every UI audit case still draws (`ui_audit_test.odin` unchanged in what it asserts).
- `doc/ui.md` (or wherever `Screen_Context` is described; `doc/architecture.md` if there) names the groups in one sentence. `doc/code_map.md`: records lowered where the tool lets, never raised silently.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh check-windows`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/check_dead_code.py`, `python3 tools/code_graph.py --check doc/code_map.md`; the UI audit at every size; a playtest (the user) of the HUD, the biome banner on a biome change, the developer screen and both editors.

## Notes

Fields at the start (53 after 0160, grep of `screen_context.<field>` outside the tests, plus `audit_screen_context`):

| Group | Field | Read by |
|---|---|---|
| process | settings | `ui_screens.odin`, `ui_developer.odin`, `ui_data_browser.odin` |
| process | monitor_size, platform, font_families, bindings | `ui_screens.odin` (1 each) |
| process | requests | `ui_screens.odin`, `ui_title.odin`, `ui_developer.odin`, `ui_data_browser.odin`, `ui_texture_editor.odin` |
| process | save_requested | `ui_screens.odin` |
| process | title | `ui_screens.odin`, `ui_title.odin` |
| content | items, machines, fluids, recipes, technologies, blocks, veins, quests, contracts | items in 14 files, machines 12, fluids 8, recipes 7, technologies 6, blocks 5, veins 4, `hud.odin` among them; quests `ui_journal.odin`, contracts `hud.odin` and `ui_contracts.odin` |
| content | notes, item_sort_ranks, recipe_names, recipe_order | `ui_journal.odin`; `ui_inventory.odin` and `ui_machine.odin`; `ui_recipes.odin` and `ui_crafting_machines.odin`; `ui_recipes.odin` (1) |
| simulation | player, world, records | 8, 11 and 11 files |
| simulation | player_index | `ui_inventory.odin` (1) |
| simulation | tick_rate, tick, unlocks, quest_state | 10, 3, 4 and 2 files |
| simulation | generator | `biome_banner.odin`, `ui_map.odin` |
| simulation | cheat_speed | `hud.odin`, `ui_developer.odin` |
| simulation | developer_requests | `ui_developer.odin` |
| simulation | landing_pad | `ui_developer.odin`, `ui_map.odin` |
| session views | browser, technology_browser, statistics_view, map_view | `ui_recipes.odin` and `ui_crafting_machines.odin`, `ui_technologies.odin`, `ui_statistics.odin`, `ui_map.odin`; `run_screens` resets two |
| developer | developer_mode | `ui_screens.odin` (the pause menu, 1) |
| developer | diagnostics_page, show_world_overlay, developer_chapter_count, data_changed | `ui_developer.odin` |
| developer | texture_editor, data_browser | `ui_developer.odin` and the editor's own screen |
| HUD | touch_aims, mining_ring_centre, touch_hud_buttons, discovery_card_clearance | `hud.odin` |
| HUD | biome_banner | `biome_banner.odin` |
| presentation | particle_memory | `ui_map.odin` (1) |
| touch | touch_layouts, touch_layout_editor, default_touch_layout | `ui_screens.odin`, `ui_touch_layout_editor.odin` |

After: 30 fields. Process 8 (unchanged); content 5 (`using content: Simulation_Content`, notes, item_sort_ranks, recipe_names, recipe_order); simulation 11 (player, player_index, world, records, tick_rate, unlocks, quest_state, tick, cheat_speed, developer_requests, landing_pad); `views: ^Session_Views`; `developer: Developer_Context`; particle_memory; the three touch layout fields. The HUD's fields left for `Hud_Context`, a parameter of `draw_hud`. The "about 12" of the audit counted the process and simulation groups as one field each, which this item keeps as they are.

Choices:

- Content: `Simulation_Content` plus the four presentation tables, not `Game_Content`. `Game_Content` is a loop type (`loop.odin`) and the comment on `Frame_Request` keeps the loop's types out of the clusters below it; naming it would raise ui -> loop. The embedded struct carries the session's view (`content_with_found_schematics(frame_simulation_content(state), ...)`), so `technologies` is the session's copy with the research cost, `recipes` carries the found schematics and `generator` is the session's, all under their old names; nothing shadows. `statistics_simulation_content` returns the embedded struct (blocks, fluids, quests, contracts and the generator are no longer zero; `entity_accepts` and its callees read none of them).
- Developer: a small `Developer_Context` built by `make_developer_context`, not a pointer to `Frame_Developer_Tools`: that is a loop type too, and two of the fields have other owners (`data_changed` is the reload's data watch, `chapter_count` the content's kits). `developer_mode` moved into it as `enabled`, since `Simulation_Content` does not carry it.
- Views: one `^Session_Views`, nil without a world; the map screen checks it before taking the map view's address.
- HUD: `Hud_Context` (`hud.odin`) holds the four touch derivations, the banner, the biome index and the generator's biomes for the name; `make_hud_context` (`loop.odin`) samples the column once per frame and `draw_biome_banner` takes the context. `draw_hud` takes it as a second parameter rather than through `Screen_Context`, so the screens no longer carry the HUD's fields. The player, world and content reads of `hud.odin` (player, items, recipes, tick_rate, quest_state, quests, records, contracts, tick, world, unlocks, machines, fluids, veins, blocks, cheat_speed) stay on `Screen_Context`: `draw_quest_objective` goes through `objective_line`, `journal_quest_view` and `objective_label`, which the journal shares and which take `Screen_Context`.
- Simulation fields read in one place, not moved: player_index (`ui_inventory.odin`), developer_requests (`ui_developer.odin`); particle_memory (presentation, `ui_map.odin`).

Records: no recorded edge changed (`code_graph.py --check`: 0 new or grown, ui -> loop 9, ui -> tools 43). Allowed edges: ui -> world 112 to 109 (the banner's `sample_column` and its generator reads), ui -> content 904 to 899, ui -> simulation 840 to 838; loop -> world 68 to 69 (`sample_column` in `make_hud_context`), loop -> ui 237 to 241 (the two new types and builders).

Behaviour: the banner advances with the same biome in the same frames as before. The column is now sampled every frame with a world, a screen open included (before only while the HUD got past its screen check); `sample_column` is pure, so only the cost moves. `test_biome_banner_draws_the_biome_of_the_hud_context` covers the banner without a generator; the audit samples the biome itself (`audit_hud_context`).
