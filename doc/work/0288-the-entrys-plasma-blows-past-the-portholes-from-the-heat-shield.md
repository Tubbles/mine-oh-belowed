# 0288: The entry's plasma blows past the portholes from the heat shield

Status: todo (2026-10-05, from the user's play of the 0286 build; 0287 folded in)

## Goal

The plasma of 0286 flickers like fire but sits still on the glass. The user (2026-10-05): "now it starts to look more like fire -- but a "static" fire like when we're sitting next to a fireplace. But we are blasting through the atmosphere in superterminal velocity, the flames need to "blow past" in a very high speed. Again look up some gif online to get a feel for how fast it should go ... Also the fire is physically not situated correctly, its connected to the window instead of connected from under the pod (and just happen to blow past the window so we can see it). Also right now its burning in between the inner glass and the outer glass, it looks like the fire comes from within the walls". So: the sheath is a layer outside the hull that the heat shield under the pod sheds, streaming past the porthole at the entry's speed, seen through the sleeve's tube; nothing of it belongs to the window.

## Controls

None.

## Change

- The speed, from footage: the design downloads clips of a window during an entry (the Soyuz descent module's window footage, Crew Dragon's and the Shuttle's reentry cameras) and of fast flames, with `curl` and `ffmpeg` or `magick` to cut frames, counts in how many frames a streak crosses the window and how the brightness jumps between frames, and states the game's flow in glass radii a tick at each heat. At the peak a feature crosses the glass in a few frames, not a third of a second.
- The place: the plasma's plane moves out of the sleeve to the hull's outer skin or beyond it, so the fire is seen through the sleeve's depth and its rim crops the view at an angle as a real porthole's does. 0287's "seen whole from the chair" goal is dropped with it, its plate fix kept: the two cabin wall plates that run through the bores of windows 0 and 2 (its design, `tools/models/machines/pod.py`, `upper_walls`) are shortened and `test_nothing_of_the_pod_crosses_a_porthole` guards every later pod script.
- The source: the flow enters each window from the side nearest the pod's base (the heat shield meets the air first, the sheath wraps up the hull from there) and leaves at the far side, never born at the rim; the haze reads as a layer streaming past, brightest where it enters, with the streaks' length and the sparks' life set by the speed, under reduced motion as 0286 left it.
- The window light's inset recomputed from the new plane so it stays where 0273 put it. Docs: `doc/presentation.md` (The arrival, the windows bullet), `doc/content.md` (Models, `windows`), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, the shader source test.
- Tests: the plasma's plane lies outside the hull's skin for every shipped window, the flow's entry side is the base's side, a feature's crossing time at the peak lies within the footage's range, nothing of the pod crosses a bore.
- Clips at the sparks, the peak and the fade (`tools/capture_clip.sh`) sent to the user beside the footage's frame strips.
- The couch.
