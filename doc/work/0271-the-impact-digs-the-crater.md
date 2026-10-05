# 0271: The impact digs the crater

Status: todo (2026-10-05, from the user)

## Goal

A new world's ground is whole until the pod hits; the bang digs the crater, the bowl and its rim, out of the natural relief at the hit tick (0270's `field_arrival_hit_tick`, 60 ticks before the landing), on every machine alike, felling the trees within its reach. Old worlds keep the crater their generation baked. Today the generation bakes the planet record's crater at the home (0199) and the pod is placed on its floor (0221).

## Controls

No binding changes.

## Change

- The planet record's crater keys become the impact's shape; the generation no longer bakes it for a new world (a world records whether its crater is baked, so an old world loads as before).
- A crater edit of the field at the hit tick, before 0270's rest and bed run in the same tick: the generation's `crater_relief` applied once to the samples within the reach, in the simulation, deterministic; the trees inside the reach felled into logs by the bang. Built on 0270's specification (`rest_field_pod`, the hit tick), designed against it.
- The home search of 0180 runs on the natural relief; the pod frame is placed at generation where the crater's floor will be, the ground whole round it until the hit, and rests on the dug floor; the streaming meshes the reach finest from the first frame as today.
- Docs: `doc/content.md` (Planets, the crater), `doc/architecture.md` (The field session, The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the field at the home before and after the hit tick differs by the crater's profile and nowhere else; two machines hash alike through it; a join after the landing carries the crater; an old save loads unchanged; the trees in the reach are felled.
- The couch and the phone: a new world, the ground whole from the chair, the crater after the bang.
