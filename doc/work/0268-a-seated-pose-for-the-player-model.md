# 0268: A seated pose for the player model

Status: todo (2026-10-05, from the 0223 design)

## Goal

A player sitting in the pod's chair is seen by the others as a seated body, legs bent and hands on the armrests, instead of not at all. Until this lands 0223 draws no body for a seated player.

## Controls

No binding changes.

## Change

- A seated pose for the player model (the limbs of `draw_field_players`), chosen where the seat is not Standing, the body placed on the chair's seat cells with the eye at the pod record's `seat.eye`; the viewer's own body stays hidden while seated (first person).
- Docs: `doc/presentation.md` (The player), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: a seated other player is drawn with the seated pose; the seated viewer is not drawn.
- The couch and a second machine: one player sits, the other sees them in the chair.
