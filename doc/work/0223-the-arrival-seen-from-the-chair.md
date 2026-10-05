# 0223: The arrival seen from the chair

Status: todo (2026-10-04, from the user's pod notes and 0221; detailed by the user 2026-10-05)

## Goal

A new world starts in the chair of the pod, strapped in: the player looks around freely from the first tick and sees the fiery inferno of the atmospheric entry raging outside the windows, the cabin round them with the screens lit, the hit shaking the cabin. Controls beyond the look are withheld until touchdown is confirmed; then the player unbuckles, stands up and walks. The chair stays a seat afterwards: the player can sit in it at any time. Today the descent hides the pod and draws a shader window over the whole viewport (0200, [doc/presentation.md](../presentation.md), The arrival), and the player stands in the cabin from the first tick (0221).

## Controls

No new binding. From the first tick the look turns the seated eye; the sticks' walk, Jump, Sneak, Mine, Place and the tools do nothing while strapped in. Once touchdown is confirmed the HUD shows Interact on the chair as "Unbuckle"; Interact (X, the touch tap on the chair) unbuckles and stands the player in the cabin. Afterwards Interact on the chair sits the player (the look free, the walk and the tools off) and Interact again stands them up; Jump does nothing while seated (A jumps alone, 0233). The chair takes Interact like a switch, so the touch tap routes to it (0233).

## Change

- The seated state per player (strapped during the fall, seated later) in the simulation, deterministic, with the eye in the chair's seat read from the pod's record; a joiner arriving after the fall spawns standing as today.
- The pod drawn during the descent, moving with the camera along the path, the window shader's flames moved from the viewport's edges to the windows' glass, the planet seen through them along the path as today; the hit's shake kept; "touchdown confirmed" as a cue and a HUD line.
- Docs: `doc/presentation.md` (The arrival), `doc/architecture.md` (The field session, the start), `doc/content.md` (the pod), `doc/input.md` (Interact on the chair), `doc/hud.md`, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the fall ignores the walk and the tools and takes the look; Interact before touchdown does nothing, after it stands the player; Interact on the chair seats and unseats; the arrival's presentation leaves the hash alone; two machines hash alike through a fall with input.
- The couch and the phone: a new world from the chair to the first steps outside, the flames in the windows.
