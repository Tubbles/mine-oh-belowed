# 0269: The fall as an atmospheric entry

Status: todo (2026-10-05, from the user)

## Goal

The fall reads as an entry seen from the chair: black space with stars, the sky brightening as the atmosphere thickens, the portholes glowing pink, then red, then white hot as the drag peaks, the flames dying as the speed drops, the ground rushing up at terminal speed, the bang. The stages follow the path, not timers: the heat is the air's density times the speed cubed, so the flames rise as the pod sinks into the air and die when the drag has taken its speed. The research is in `work/research/arrival-entry-2026-10-05.md` (untracked, 2026-10-05).

## Controls

No binding changes.

## Change

- The arrival's data (`game.sjson`): the start above the atmosphere's top, the entry angle, the speed curve or the drag that makes it, the atmosphere's scale height and the fall's seconds (about 30 by the note, the user tunes them), replacing `arrival_flame_ticks`; the landing tick stays the simulation's.
- The sky's colour by the camera's altitude: black with stars above the atmosphere's top, the day's sky below (`render_sky.odin`, presentation only).
- The window shader's colour and strength from the heat (pink, orange, white hot, dull red, out); the roar from the heat; a buffeting shake at the peak.
- Docs: `doc/content.md` (The arrival), `doc/presentation.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the curve ends at the floor on the landing tick and never runs backwards; the heat is zero at the start and at the hit and peaks once between; the sky is black at the start altitude; the presentation leaves the hash alone.
- The couch and the phone: a new world from black space to the bang, screenshots at the start, the peak and the fade.
