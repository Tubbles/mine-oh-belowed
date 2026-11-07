# 0317: A field session without its renderer

Status: todo (2026-11-07)

Found in 0307's headless capture: a field shader Mesa refused (a GLSL reserved word) left `start_field_presentation` false. The session then drew only the HUD over the sky, and the developer command `tick 20` never finished, since the field's chunks stream from the viewports' node selection and that comes only from a loaded renderer. The game neither reported the problem on screen nor stopped. A player would see an empty sky and a world that never moves, with the cause only in the log.

## Goal

A field session whose renderer fails tells the player why and returns to the title, the way other failed loads report (`CLAUDE.md`, the hand-back check: a start-up load the game can make fail falls back and reports instead of exiting).

## Controls

None.

## Change

- When `start_field_presentation` fails after its overlay fallback (0307), the session ends with a toast naming the file and the log line. Or the field streams without a renderer and only the drawing is skipped, if a dedicated server or a test needs that. The design picks one and says why.
- A test that a failed field presentation does not leave a running session whose ticks wait forever.
- Docs: `doc/architecture.md` (the overlay fallback paragraph), the strings.

## Verify

- The checks and the suite.
- A headless session on a data copy whose `field.fs` does not compile (`MINE_OH_BELOWED_DATA`) shows the toast and the title.
