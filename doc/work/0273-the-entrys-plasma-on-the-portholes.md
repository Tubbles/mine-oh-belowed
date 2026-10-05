# 0273: The entry's plasma on the portholes

Status: todo (2026-10-05, from the user)

## Goal

The flames on the portholes during the fall are redone from research (`work/research/flames-2026-10-05.md`, untracked): not triangles growing from the rim with a tint drifting red to white (user, 2026-10-05: "kindergarten tier"), but the plasma sheath an astronaut sees, a pink violet haze that brightens with the heat, streaks and sparks streaming aft across the glass, white only in the brightest cores, the sheath hiding the outside at the peak, soot on the glass after it, and the cabin pulsing in the haze's light. The hue family never drifts; the heat drives brightness, reach, speed and sparks (DESIGN.md, Fire). After 0269 (the heat curve) and 0270 (the travel across the glass).

## Controls

No binding changes.

## Change

- `data/shaders/arrival.fs` rewritten as a flow field on the disc: a haze in a fixed pink violet to orange family whose brightness follows `heat`; value noise fBm stretched along the travel axis and scrolled aft at a speed following the heat, soft edged with a glow, white in the cores near the peak (the look is Techtonica's, soft and realistic leaning, never banded); hashed sparks streaking aft, their rate following the heat; the disc's alpha rising to 1 near the peak; soot from the rim inward after the peak (`cooling`), kept at a low share once landed; flicker from noise without period, still under reduced motion. No hue changes with the heat or the cooling.
- Each porthole a point light in the haze's colour, its brightness the heat times the flicker, through the pod's lights as the lamps go (`moved_point_light`), none at heat 0.
- The stages of the descent read as a sequence of structures, not of hues: black, a pink haze, sparks in it, bright streaming at the peak, fading, sooty glass.
- Data: the haze's two colours and the soot's kept share in `game.sjson`, or on the planet's `atmosphere` if the gas should set the hue; the design decides.
- Docs: `doc/presentation.md` (The arrival, The windows), `doc/content.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`; `shader_source_test.odin` on the new shader (the `u` suffixes).
- Tests: the window light's brightness follows the heat and is 0 at heat 0; the flicker has no period; the presentation leaves the hash alone.
- Screenshots through a porthole at the haze, the sparks, the peak and the soot (the 0269 recipe), sent to the user before the landing.
- The couch: the fall from the chair reads as an entry.
