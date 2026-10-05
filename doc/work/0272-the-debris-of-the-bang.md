# 0272: The debris of the bang

Status: todo (2026-10-05, from the user)

## Goal

At the hit the ground flies: clods on ballistic arcs out of the crater as an inverted cone, the dust curtain along the rim, a bang over the crash, and the debris strewn round the pod for the first minutes. With 0271 (the crater) and after 0223 (the dust).

## Controls

No binding changes.

## Change

- Presentation only, hashed per piece like the dust puffs (`arrival_dust_puff`), nothing in the simulation: the ejecta curtain at about 45 degrees, the inner pieces fastest and farthest, half landing within a crater radius of the rim and none beyond five radii (the note's numbers), drawn as boxes in the ground's colour, resting where they land for a data number of seconds and fading; the dust ring along the rim; the shake stronger.
- Sounds: a bang layered on the crash and the patter of the fall, pitched by the world's hash, never on a fixed period.
- Data: the piece count and the seconds in `game.sjson`.
- Docs: `doc/presentation.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: every arc lands within five radii and half within one radius of the rim; no piece rests inside the pod's hull; the presentation leaves the hash alone.
- The couch: the bang from the chair, then the strewn clods outside.
