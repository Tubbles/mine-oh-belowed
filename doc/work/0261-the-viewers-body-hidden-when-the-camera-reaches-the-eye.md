# 0261: The viewer's body hidden when the third person camera reaches the eye

Status: todo (2026-10-05, from 0220)

## Goal

A player whose third person camera has been pulled in to the eye sees the world as in first person, not the inside of their own body: below a distance from the eye the viewer's body is not drawn for that viewport.

## Controls

No binding changes.

## Change

- The field's third person camera reports its pulled distance (0220's `field_third_person_position` or its caller); below a threshold (the body's radius plus the near plane, in metres) the viewport skips the viewer's body, as the first person mode does. The block world's camera gets the same rule if its pull-in reaches the eye.
- Presentation only, per viewport per frame.
- Docs: `doc/architecture.md` (the camera bullet of The player on the field), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: with the camera at the eye the viewer's body is not in the draw list; at the settings' distance it is; the other player's body is drawn in both.
- The couch: third person against a wall, back up into it, the body vanishes instead of filling the screen.
