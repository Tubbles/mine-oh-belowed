# 0086 Pageable diagnostics with a render page

Status: todo
Milestone: M11

## Goal

Couch request (2026-09-28): "make the F3 screen pageable somehow, and add the effective screen resolution and other render details to it." Today F3 toggles one screen of input diagnostics (`src/diagnostics.odin`) and F4 a small world overlay.

## Deliverables

- Pages: F3 (`Toggle_Diagnostics`) cycles off, Input, Render, World, off; `Frame_State.show_diagnostics` becomes `diagnostics_page` (an enum with `Off`), the Developer screen's toggle (`src/ui_developer.odin`) becomes a choice row showing the page name that cycles the same way, and the pure `next_diagnostics_page(page)` has a test. Every page draws the same header line first: "Diagnostics 2/3 Render (F3 next)" (string keys for the page names), then its columns in the monospace face and size the screen uses today, over the same backdrop.
- Input page: today's F3 content, unchanged.
- Render page, from a `Render_Facts` struct the frame loop fills and a pure `render_page_lines(facts)` that a test covers: the build stamp; window mode, monitor size, window size, render size, window scale and session (x11 or xwayland, the 0084 facts); vsync and the frame rate cap from the settings; fps (`rl.GetFPS`) and the frame time in milliseconds averaged over the last second (a small ring in `Frame_State`); ticks run this frame and the accumulator; fog start and end and the weather kind and intensity and the day fraction; chunks loaded, drawn and their vertex count, meshes uploaded this frame and pending mesh jobs; water meshes drawn; live particles and weather particles; flames; the block, item and UI atlas sizes; whether the camera is under water.
- World page, from a `World_Facts` struct and a pure `world_page_lines(facts)`: what the F4 overlay shows today (world, light and streaming statistics) plus the entity counts by kind, loose items, belt lines and items on them, the water, leaf decay and light queues, veins registered, the player's position, chunk and biome, the active quest and the tick. The F4 overlay stays as it is.
- Tests (`src/diagnostics_test.odin`, new or extended): the page cycle, the header text, the render and world lines from fixed facts (no raylib), the frame time average over the ring.
- Docs: `doc/ui.md` (the diagnostics pages), `doc/input.md` (F3 cycles pages), `doc/commands.md` if the Developer screen text mentions the toggle, `doc/log/2026-09-28.md`, this item's Status and Notes.

## Verify

- Builds and tests pass.
- User: F3 steps through the three pages and off; the Render page shows 1694 by 1129 next to the monitor size on the scaled laptop and 1920 by 1080 on the couch.

## Notes

Files a subagent may touch: `src/diagnostics.odin`, new or existing `src/diagnostics_test.odin`, `src/loop.odin` (the page field, the facts, the ring and the draw call), `src/ui_developer.odin`, `src/ui_screens.odin` (the screen context field), `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
