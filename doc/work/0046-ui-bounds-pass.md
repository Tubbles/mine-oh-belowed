# 0046 UI bounds pass

Status: implemented
Milestone: M10

## Goal

Couch test 1 (2026-09-27), 1080p with UI scale 1.2: several UI elements reach outside the window and long strings run off their panels. Everything on screen stays inside the screen, and text breaks lines where it must.

## Deliverables

- An audit test that builds every screen headless (a `Ui_State` with `approximate_text_width`, a world from the save test's builder, a `Screen_Context` like `make_screen_context` fills) at 1280 by 720 and 1920 by 1080 with UI scale 1.0, 1.2 and 1.5, and checks that every draw command's rectangle lies inside the screen. Screens: title, new world, load (with saves), confirm delete, pause, settings (every tab), developer, inventory, every machine panel kind (furnace, crafting machines, drill, inserter, chest, lab, pipe and fluid machines, recycler, launch pad with its three tabs, splitter, pole, power switch), recipes (browse and selection), technologies, journal (chapter and contracts tabs), statistics (every tab), power, map, prospecting, on-screen keyboard, and the HUD with a long objective and a long toast. The test stays so regressions fail CI.
- Fix everything the audit finds: panels sized past the safe area shrink or scroll, long strings wrap (`wrap_text`) or end with an ellipsis, rows in the load list become columns (name, chapter, played, saved), the glyph bar stays inside the safe area at every scale.
- A manual check list in the work item notes of what the audit cannot see (overlapping text, icon alignment).

## Verify

- Builds and tests pass, the audit test included.
- User: at 1080p and UI scale 1.2 and 1.5 every screen fits, including the load screen and the journal.

## Notes

Implementation notes from the subagent run (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (577 tests, the audit included), `./build.sh`, `./build.sh release`.

### The audit

`src/ui_audit_test.odin`, `test_every_screen_stays_inside_the_screen`. The save test's site (every entity kind) plus one of every machine it lacks, 120 ticks run, the quest with the longest text active and every other quest done, four Mission Control lines, a full craft queue waiting, the drill targeted, two saves (32 wide characters, a 20 digit seed, one marked not loadable), open contracts, and the shipped strings (a thread local string table, since other tests read the global one). Sizes: 1920 by 1080 at 1.0, 1.2 and 1.5, 1280 by 800 at 1.0, 1.2 and 1.5, each with keyboard and with gamepad glyphs. Cases: title, new world, on-screen keyboard, load, confirm delete, HUD (toasts), HUD with the hotbar radial, HUD with a magnetometer selected, pause (developer mode), settings on each tab, developer, inventory, the machine panel of every machine with a panel (the launch pad on each tab), recipes, recipe selection, technologies, the journal on every chapter tab and the contracts tab, statistics on each tab, power, map. Every case walks the focus over every widget with the info panel open. Checks per draw command: on the screen and inside the panel it was drawn in (clipped commands by their visible part), text not wider than its rectangle nor taller; per panel: inside the safe area and not under the glyph bar's commands. Runs in about 2 s.

### What the audit found before the fixes

- Tooltips docked off the left edge of the screen wherever the panel had no room on its right (every screen with tooltips, every size), and long tooltips overran their two row box.
- Machine panel: 1376 to 1544 wide, past the safe area at 1.5 on 1080p and at 1.2 on 1280 by 800 for every machine, and at 1.2 on 1080p for chests, the capsule and the launch pad; the launch pad was also taller than the safe area at 1.0.
- Load: 1400 wide panel off screen at 1.5; the one line save rows overran at every size.
- Pause (864 tall) past the safe area from 1.2, off screen at 1.5; developer and new world past it at 1.5; power overview (992 tall) past it at every size.
- HUD: a long Mission Control toast 2329 units wide; a full craft queue and its waiting line off the left edge at 1.2 and 1.5.
- Recipes and technologies: the fixed 380 and 560 wide columns left the detail 36 to 118 units at 1.5 and on 1280 by 800, so names, costs and prerequisites ran out.
- Statistics detail 188 wide at 1.5; journal chapter tabs too narrow for their names at 1.5 and quest detail lines squeezed to no height; map legend line too wide at every size; settings binding rows too wide.
- With the later checks: the glyph bar past the safe area on the recipe screen at 1280 by 800 at 1.5 with keyboard glyphs, and clamped panels (the map at every size) under the glyph bar.

### Model

- `fit_text` and `draw_text_fitted` end a line with "..." where it does not fit; `wrap_text_lines` wraps to a line count. Buttons, toggles, choices, sliders, tabs, list rows and data lines (`detail_line`) fit their labels; descriptions (quest text, recipe facts, technology cost and prerequisites, tooltips) wrap.
- `fitted_panel` clamps a panel to an area; `ui_panel_area` is the safe area above the glyph bar, where every screen now puts its panels (they sit about 30 units higher than before). `Scroll_Region` scrolls content taller than its area: the right stick and the wheel scroll it, a focused widget keeps itself in view, the drawn content counts for the scroll range. Used by the pause menu rows, the new world rows, the developer actions and the machine side of the machine panel.
- Machine panel: the machine side takes what the player's slots leave of the width; chests, crafting inputs and outputs, lab packs and launch pad parts and cargo wrap their slots to it (`slot_columns`, `slot_rows_height`), the furnace bar narrows.
- Toasts wrap to at most 3 lines, at most 0.55 of the safe width; the HUD objective takes at most 0.4 of it and wraps its progress lines. The craft queue wraps into rows above the hotbar's left and its waiting line wraps to 2 lines.
- Glyph bar: when the hints do not fit the safe width, hints go from the end of the list, keeping the last (Back), with an unlabelled bumper hint paired to a dropped one. The glyph box no longer overlaps its label by a few units.
- Load list: a column heading row (Name, Seed, Played, Last) and truncating columns; the "cannot load" marker right aligned in the name column, up to 0.8 of it. `save_row_text` became `save_row_cells`.
- Recipes, technologies, statistics, journal, power: columns take at most a share of the panel (0.24 and 0.34, 0.6, 0.4, 0.4); the journal detail leaves the log at least its share and the log takes the rest; the journal's contracts tab splits the width in half; the map legend takes the width beside the image. Power overview detail lines are 0.6 rows high, so the panel is shorter at every scale. The inventory drops its heading (the first tab repeats it) where it would not fit.

### Deviations

- No UI scale clamp: every screen fits at 1.5 on 1280 by 800 too, so 1280 by 800 at 1.5 joined the audit instead and the settings tooltip is unchanged.
- Load columns are name, seed, played and saved (the brief), not chapter.
- `Draw_Command` gained a `panel` field and the glyph bar registers the safe area as a panel, for the audit; `text()` reads a thread local table when one is set (`thread_string_table`, set by the audit only).
- Texts are measured with `approximate_text_width` (0.55 of the size). A run with 0.65 also passed.

### Manual check list (what the audit cannot see)

- Overlaps inside panels: toggle and slider labels against the check box and the track, choice labels against values, the journal detail against the log, HUD toasts against the objective, the brownout line and the compass, the craft queue rows against the hotbar's item name, the magnetometer dial against the target lines, a tooltip over the widget it describes on full width panels.
- Scrolling: the pause menu, new world and developer rows and the machine side at 1.5 scroll with the focus, the right stick and the wheel; the pointer over a row scrolled out of a list or region still hovers it (as lists did before).
- Truncation where the meaning suffers at 1.5: the load list marker, settings binding rows, map legend, technology and recipe names, catalogue buttons.
- Icon alignment: slot icons in wrapped rows, recipe row icons, glyph boxes, the "..." in the default font.
- Colours: the load list headings and marker, the waiting line.
- The real font's widths against the approximation.

