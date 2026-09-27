# 0077 Readable text: TrueType fonts at exact pixel sizes, a font setting

Status: implemented
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

## Notes

Implemented by a subagent (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (648 tests, new ones in `src/ui_font_test.odin`, plus cases in `src/data_watch_test.odin` and the settings round trip in `src/configuration_test.odin`; the UI audit now also draws the two font choices), `./build.sh`, `./build.sh release`, `mine-oh-belowed config` lists `settings.font = "exo_2"` and `settings.monospace_font = "jetbrains_mono"`, `--set=settings.font=nonsense` and `--set=settings.monospace_font=exo_2` are refused naming the accepted ids.

Files: new `src/ui_font.odin` (fonts.sjson loading and validation, the cache, measuring and drawing), `src/ui_font_test.odin`, `data/fonts/fonts.sjson`; changes to `src/ui_core.odin` (`Font_Weight`, `text_weight`, the command's weight, `Ui_State.fonts` and `measure_text`, the approximation factor), `src/ui_widgets.odin` (`emphasis` on `draw_text`, `fit_text`, `draw_text_fitted`), `src/ui_draw.odin`, `src/diagnostics.odin`, `src/ui_journal.odin` (the HUD quest title bold), `src/ui_screens.odin` (two font choices, the Display and Controls tabs scroll), `src/settings.odin`, `src/main.odin`, `src/loop.odin`, `src/hot_reload.odin`, `src/data_watch.odin`, strings.

### Model

- `data/fonts/fonts.sjson`: `families`, each with `id` (its directory), `name_key`, `regular`, `bold`, optional `monospace`. Strict: every key but `monospace` present, ids unique, at least one family of each kind, every file present; otherwise the game and `config` refuse to start. Order: the technical faces first (Exo 2 to Michroma), then the plain ones, then the two monospace families.
- `settings.font` (default `exo_2`) picks among the families without `monospace`, `settings.monospace_font` (default `jetbrains_mono`) among those with it, for the diagnostics and statistics overlays. Both are Display tab choices cycling in file order, applied from the next frame, saved with the other settings. An unknown id is a configuration error naming the layer and the ids (checked in main after the data directory is known, since the ids come from the data).
- Text of `text_size` units is rasterised with `rl.LoadFontEx` at `round(text_size * pixels_per_unit)` pixels with the printable ASCII characters plus every other code point of `strings/en.sjson`, bilinear filtering, spacing 0, and drawn at that size at a position rounded to whole pixels. Measuring uses the same font, divided by pixels per unit. The cache is keyed by family, weight and pixel size and dropped (fonts unloaded) when the family, the diagnostics family or pixels per unit (UI scale or window height) change, and on a fonts or strings reload.
- Bold: text at `UI_HEADING_TEXT_SIZE` or larger, and the HUD quest title (`emphasis`). The journal's quest title is a heading already.
- Hot reload: `fonts/fonts.sjson` and `.ttf`/`.otf` files under `fonts/<family>/` are a presentation category, reloaded in place. A reload keeps the old family list's arena until exit, since the settings may point at its ids.
- `approximate_text_width` (headless audit) uses 0.37 of the size per character, the default family's average advance over a sample sentence (Exo 2 measures 0.362).

### Measured fonts

raylib 6's loader reads all 21 families (checked with `rl.LoadFontData` in a scratch program; Orbitron lacks one printable ASCII glyph). stb_truetype renders a variable font's default instance only. The `fvar` defaults: weight 400 for Exo 2, Orbitron, IBM Plex Sans, Inter, Lexend, JetBrains Mono, but 300 (Light) for Jura, 200 (ExtraLight) for Oxanium and 100 (Thin) for Saira, which render that thin (ink per advance pixel: Saira 13.7, Jura 21.3, Oxanium 26.9 against 39.0 for Exo 2). Families with one file (the variable ones, Electrolize, Michroma, Share Tech Mono) name it for both weights, so their headings are not bold, the default Exo 2 included. Average advance as a fraction of the pixel size: Titillium Web 0.27, Saira 0.27, Rajdhani 0.30, Exo 2 0.36, Orbitron 0.42, Michroma 0.43, Oxanium 0.44.

### Deviations

- An unknown font id exits with status 1 like every other configuration error (`--set=settings.ui_scale=9` does too), not 2.
- The approximation test reads the default family's advances with a small TrueType reader in the test (`font_file_text_width`, stb_truetype's scaling): any raylib call reachable from a test makes the test build link X11, which `./build.sh test` does not provide. For the same reason `Ui_State` keeps a `measure_text` procedure the frame loop sets, instead of calling the font code directly.
- The Display and Controls tabs scroll: seven rows do not fit at UI scale 1.5.
- The monospace families are not offered as UI fonts.

### Not verified

The look: stems, the text sizes (a TTF's pixel size spans its ascent to descent, so the letters may read smaller than the old bitmap font's at the same size), the font choices, the diagnostics overlay's layout in a monospace font (its column positions and backdrop width were made for the old font), fonts reloading while the game runs, the non ASCII glyphs.

