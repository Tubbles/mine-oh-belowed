# 0225: The pod's cabin is dark until its lamps light it

Status: todo (2026-10-04, from the user's note on the first lit cabin shots of 0224, "i like the colors but it still looks flat"; the main agent's reading of the cause is below)

## Goal

Inside the pod the lamps carve pools of light out of a dark cabin, as the booklet's interior does, instead of adding a little warmth to a room that is already lit at full daylight.

## Why it looks flat

A field session lights every model with the full sky light (`Model_Frame.open_sky`, `model_frame_light` in `render_models.odin`, 0179: machines stand on frames the block light does not reach), the pod's hull and its fixtures included, whatever surrounds them. The point lights of 0224 only add on top (`model.fs`, the sum is added to the base), so a lamp inside the cabin brightens a wall that is already at its brightest and the far side of the cabin is as bright as the near side. The lamps' pools can only show when the base inside is dark. The point lights cast no shadows and never will in this renderer; the depth comes from the base being dark and the lamps local.

## Controls

No binding changes.

## Change

- The base light of the pod's own model and of its fixtures (the hatches, the locker, the bench and the oxygen generator placed by `validate_pod_fixtures`) is scaled by a record key on the pod, `interior_light_share` (0 to 1, the pod ships a low value such as 0.25), applied to the light tint of their lit layers before the point lights add; the emissive layers keep their brightness, so the screens and strips stay lit. The hull seen from outside takes the same scale: the pod is a dark shell outside too, which the portholes' and the door's emissive patches offset. The design stage settles whether the share also applies to players' bodies seen inside the cabin (the viewer never sees their own body in first person; a second player inside would glow at full daylight against the dark walls) and to loose items.
- The simulation reads nothing of it; presentation only, the hash untouched.
- Docs: `doc/presentation.md` (Machine models: the pod bullet), `doc/content.md` (the key).

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the key is bounded (a value outside 0 to 1 is refused with the machine named); the pod's and its fixtures' light tint carries the share and an ordinary machine's does not; the emissive layer's brightness is unchanged by it; the hash of a session with the key equals the hash without it.
- A headless screenshot pass (`tmp/pod_shots.sh`) with the lab's model and its two lamps: the walls near the lamps read as pools and the far side of the cabin stays dark.
