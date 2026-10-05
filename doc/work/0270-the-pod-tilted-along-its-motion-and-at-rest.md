# 0270: The pod tilted along its motion and at rest

Status: todo (2026-10-05, from the user)

## Goal

The pod flies base first along its path, turned so the chair's porthole looks along the travel, and the path steepens towards vertical as the drag takes the forward speed, so the horizon shows once the flames die. At rest it lies tilted and rolled in its crater, the outer hatch pointing to the side or up, so the player climbs out; the cabin is walkable tilted. After 0269 (the path) and with 0271 (the crater it rests in).

## Controls

No binding changes.

## Change

- During the fall the pod's axes follow the path's tangent (presentation, with the offset of 0223); the seated eye follows the frame as it does.
- At the landing tick the simulation sets the pod frame's resting axes: a tilt up to a data bound (at most 20 degrees; the walkable angle is 60) and a roll, both hashed by the world's seed, with the outer hatch's direction never below the horizontal (`Frame.axes` already holds any unit vectors). The spawn, the seat, the hatches and the fixtures follow the frame.
- A joiner and a loaded world read the axes from the frame; old worlds keep their level pod.
- Docs: `doc/content.md` (The pod, The arrival), `doc/architecture.md` (Frames, The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: for seeds 1 to 64 the tilt is within the bound and the hatch's direction is level or up; a player walks the tilted cabin and crawls the bore; two machines hash alike through the landing; an old save loads level.
- The couch: unbuckle in a tilted cabin, climb out through the airlock.
