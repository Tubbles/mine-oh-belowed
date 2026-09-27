# 0077 Readable text: TrueType fonts at exact pixel sizes, a font setting

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-27): vertical stems in the text are one pixel here and two pixels there at every UI scale short of a very large one, and the font itself reads poorly. The cause is raylib's built in 10 pixel bitmap font scaled by the UI scale. Text must come from TrueType fonts rasterised at the exact pixel size they are drawn at, and the user must be able to cycle through a set of free fonts in game to pick one.

## Deliverables

- Fonts in `data/fonts/<family>/` with their licence files (OFL, UFL, Apache), shipped: Atkinson Hyperlegible, IBM Plex Sans, Fira Sans, Ubuntu, Cantarell, Inter, Lexend, and JetBrains Mono for the diagnostics. `data/fonts/fonts.sjson` lists each family with its regular and bold file and its display name; strict loading.
- Rasterisation at exact pixel sizes: for every text size the UI uses (body, heading, glyph, slot count, diagnostics) times the pixels per unit of the current UI scale and resolution, the font is loaded with `rl.LoadFontEx` at that pixel size (a cache keyed by family, weight and pixel size, rebuilt when the UI scale or the window size changes, old fonts unloaded), drawn with bilinear filtering, and text positions snapped to whole pixels, so every stem has the same width. Measurement (`ui_text_width`) uses the same font, so layouts and the audit's approximation agree; update `approximate_text_width` to the chosen font's average advance.
- A `font` setting (settings screen, Display tab: a choice cycling through the families, applied at once and saved with the other settings) and a `--set=settings.font=<family>` override; the default is Atkinson Hyperlegible, chosen for legibility at a distance. Hot reload (0054) applies a changed fonts.sjson.
- The diagnostics overlay uses the monospace family at an exact pixel size too.
- Tests: fonts.sjson loading and validation, the size cache key, the pixel snapping, the setting round trip; the UI audit passes with the new metrics (its approximation constant follows the default font).

## Verify

- Builds and tests pass.
- User: cycle the font setting on the couch at UI scale 1.0 and 1.2; stems are even at every setting; pick a favourite.
