# 0046 UI bounds pass

Status: todo
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
