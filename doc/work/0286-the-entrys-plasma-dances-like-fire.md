# 0286: The entry's plasma dances like fire

Status: todo (2026-10-05, from the user's play of the 0273 build)

## Goal

The plasma on the portholes during the entry (0273) moves like fire, not like a wave. The user (2026-10-05): "the flames are better, but they've still got far to go ... The flames doesnt flicker at all, they do not behave like flames at all. They have a very weird pinkish color which might be correct, but i think it needs to be mixed up a bit. Its like theyre moving like a wave of 1 Hz, while real flames dance around very skittishly and erratically." The yardstick is footage: a clip of a couple of seconds captured from the headless game, set beside clips of flames in general and of the glow seen through a window during an atmospheric entry, and the shader reworked until the game's clip reads as the footage. The same yardstick applies to the firebox and torch flames of 0274 once the user has seen them.

## Controls

None.

## Change

- The motion of `arrival.fs`: an erratic, fast flicker of the brightness and of the streaks (a flame's dance is a spectrum of fast irregular changes, nothing near a single slow wave), the streaks skittish, the colour a mix the heat and the flicker shift between the haze's pink violet and the ablator's orange and white rather than one hue, all without a period (DESIGN.md, no perceivable repetition), under the reduced motion setting as 0273 left it.
- The capture: a script that takes consecutive frames from a paused headless session and assembles a clip and a frame strip, so the main agent and the user judge the motion, not one still (`tools/` or `tmp/`, the design decides).
- Docs: `doc/presentation.md` (The entry's plasma), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: the flicker has no period over the entry's length, the brightness changes between consecutive ticks by a measured share, the colour spans the mix.
- A one second clip at the sparks, the peak and the fade from the headless game, sent to the user beside the reference clips.
- The couch.
