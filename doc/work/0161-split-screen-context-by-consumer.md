# 0161: Split Screen_Context by consumer

Status: todo (after 0160)

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
