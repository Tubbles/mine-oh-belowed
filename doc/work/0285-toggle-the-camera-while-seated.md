# 0285: Toggle the camera while seated

Status: todo (2026-10-05, from 0268)

## Goal

A player seated in the pod's chair after the touchdown toggles the third person camera as a standing one does. 0268 lifted the forced first person for `Seated`, but the seated tick (`tick_seated_field_player`, `SEATED_FIELD_ACTIONS`) still drops `Toggle_Camera_Mode`, so a seated player keeps the mode they sat down with. The strapped descent stays first person.

## Controls

No binding changes: the existing camera toggle reaches the seated tick.

## Change

- `SEATED_FIELD_ACTIONS` admits `Toggle_Camera_Mode` and the seated tick applies it as the standing one does; the strapped tick keeps dropping it. The simulation's action set changes, so the lockstep hash of a seated toggle is covered by a test.
- Docs: `doc/input.md` (the chair's actions), `doc/presentation.md` (the camera rule of 0223 and 0268).

## Verify

- Tests: a seated player's toggle changes the camera mode, a strapped one's does nothing, the hash agrees between host and joiner.
- The couch: sit, toggle, see the seated body.
