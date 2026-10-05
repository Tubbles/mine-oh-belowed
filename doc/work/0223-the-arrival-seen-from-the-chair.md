# 0223: The arrival seen from the chair

Status: todo (2026-10-04, from the user's pod notes and 0221)

## Goal

The fall of a new world is watched from the chair of the remade pod (0221): the cabin round the player, the screens lit, a porthole with the planet growing in it and the flames of the entry rising past its glass, the hit shaking the cabin, then the doors opening. Today the descent hides the pod and draws a shader window over the whole viewport (0200, [doc/presentation.md](../presentation.md), The field session, The arrival).

## Change

- The pod is drawn during the descent, moving with the camera along the path (today the frames are hidden because the hull would block the view), the eye seated in the chair (a record key, say `seat = {x, y, z}` in cells of the pod's footprint, from the modeller's report of 0221), looking at the porthole the design stage picks from the model.
- The window shader's flames move from the viewport's edges to the porthole's glass, the planet seen through it along the path as today.
- The hit cuts to the standing eye at the spawn as today, with the shake.

## Verify

- Tests: the arrival's presentation still leaves the hash alone (`test_the_arrivals_presentation_leaves_the_hash`); the seated eye lies inside an open cell of the record; the porthole's cell is on the hull.
- The couch: a new world from the chair to the open doors, on the couch and on the phone.
