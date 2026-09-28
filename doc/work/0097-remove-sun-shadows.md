# 0097 Remove the sun shadow map

Status: implemented
Milestone: M11

## Goal

Couch verdict (2026-09-28) on 0072's sun shadows: "a clear downgrade, the sun is not a pure directional light like the mode does, it is also much more of an ambient light source; it creates ugly visual artifacts as it shines at a very steep angle onto the side of eg. trees." The sky light propagation already gives the soft shading under crowns and in gullies that the sun should give here. The shadow map goes; the coloured block light and the flicker of 0072 stay.

## Deliverables

- Remove `src/render_shadows.odin` and its test, `data/shaders/shadow.vs` and `shadow.fs`, the `shadows` setting (`src/settings.odin`, `src/configuration_test.odin`, the Display tab row in `src/ui_screens.odin`, its strings), the shadow uniforms and sampling from `data/shaders/chunk.fs` and `water.fs` and their locations in `src/render_chunks.odin` and `src/render_water.odin`, the pass call in `src/loop.odin`, the shader pair from `src/data_watch.odin` and `src/hot_reload.odin` (and their tests), and the Deck note in `doc/work/0076-steam-deck.md`. A configuration file that still names `shadows` must not fail to load: the loader's strict unknown key check would refuse it, so keep the key accepted and ignored for this release with a log line, and say so in `doc/ui.md`.
- `doc/architecture.md`, `doc/ui.md`, `doc/work/0072-lighting-polish.md` (a line that the shadows were removed by 0097 and why), `doc/log/2026-09-28.md`, this item. `SUGGESTIONS.md` gets a line: if shadows ever return they must be soft and low contrast, treating the sun as mostly ambient, and never a hard directional map.

## Verify

- Builds and tests pass; a settings file with `shadows = true` still loads.
- User: no Sun shadows row; the world looks as before the shadows.

## Notes

Files a subagent may touch: the files named above, `src/render_chunks.odin`, `src/render_water.odin`, `src/loop.odin`, `src/settings.odin`, `src/configuration.odin`, `src/configuration_test.odin`, `src/ui_screens.odin`, `src/ui_audit_test.odin`, `src/data_watch.odin`, `src/data_watch_test.odin`, `src/hot_reload.odin`, `data/shaders/chunk.fs`, `data/shaders/water.fs`, `data/strings/en.sjson`, `SUGGESTIONS.md`, the docs above, this file.

Implemented: removed `src/render_shadows.odin`, `src/render_shadows_test.odin`, `data/shaders/shadow.vs` and `shadow.fs`; the shadow uniforms, sampling and face normal out of `data/shaders/chunk.fs` and `water.fs`; the locations and the depth pass renderer out of `src/render_chunks.odin` and `src/render_water.odin`; the `apply_shadows` call in `src/loop.odin`; the shader pair in `src/data_watch.odin` (its test now expects `shaders/shadow.fs` ignored, `src/data_watch_test.odin`) and `src/hot_reload.odin`; the setting in `src/settings.odin`, the Display row in `src/ui_screens.odin` (`DISPLAY_SETTINGS_ROW_COUNT` 17) and its strings in `data/strings/en.sjson`. `src/configuration.odin` accepts `settings.shadows` through `RETIRED_CONFIGURATION_KEYS` and ignores it with one log line; `src/configuration_test.odin` loads a file with `shadows = true`. Docs: `doc/architecture.md`, `doc/ui.md`, `doc/work/0072-lighting-polish.md`, `doc/work/0076-steam-deck.md`, `SUGGESTIONS.md`, `doc/log/2026-09-28.md`. 949 tests pass (the five shadow tests removed).
