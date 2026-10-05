# 0267: The viewer's body hidden when the pulled-in camera drops into the legs

Status: todo (2026-10-05, from the 0261 design)

## Goal

Looking steeply up in third person, the camera's offset points down through the body and the ground pulls the camera in to about the feet, more than 0261's distance from the eye, so the body is drawn round the camera. The viewer sees the world there too, not the inside of their legs.

## Controls

No binding changes.

## Change

- 0261's distance measured to the body's axis segment (feet to eye) instead of to the eye alone, so a camera pulled into the legs hides the body as one pulled to the eye does; the feet and the height reach both cameras' seams (`field_viewport_camera`, `draw_session_world`).
- Docs: `doc/presentation.md` (The player), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: with the camera at the feet the viewer's body is not drawn; 0261's tests hold.
- The couch: third person on flat ground, look straight up: the body vanishes instead of the legs filling the screen.
