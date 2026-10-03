# 0199: The pod sits in an impact crater, no pad

Status: todo (user, 2026-10-03: "the pod shouldn't come with foundation, it should just be buried directly in the ground inside an impact crater"; after 0198)

## Goal

The pod lies where it fell: half buried in the ground at the bottom of a crater it made, with no pad of foundations around it. Today `place_pod` (`entity_pod.odin`) lays a free frame with a pad of `POD_PAD_SIZE` foundations that cost nothing and the pod on it, and the players spawn in front of its door (`field_home_player`).

## Change

- The crater is a field edit of the new world at the home site, deterministic from the seed and the planet record: a bowl dug to a depth and radius the planet names (`crater` in `data/planets.sjson`: `radius_metres`, `depth_metres`, `rim_metres`), a rim raised around it with the dug material, the floor flat enough for the pod. It is applied once when the world is created (`enable_new_field_world`), before the pod is placed, through the brush edits that exist (`apply_field_edit`), so a joiner's snapshot and a loaded save hold it as changed chunks and no machine regenerates it differently.
- The pod's frame stands on the crater floor with its floor cell at the floor's level, sunk so the hull's base is below the rim's ground; no foundations are placed (`pod_pad_cells` goes, `POD_PAD_SIZE` goes, 0196's pad foundation is the benchmark's only). The crater is wide enough that the airlock (0198) opens onto the floor and a ramp of slope the player walks (0189's slopes) leads out over the rim.
- The players spawn inside the pod (0200 opens the hatch; before it, the spawn is inside with the hatches open), not in front of it; `field_home_player` reads the pod's cabin cell.
- The planet preview's walk start (0184) and the dry spawn (0180) follow the crater floor.
- `doc/content.md` (The pod: the crater, no pad; Planets: the crater record), `doc/architecture.md` (the new world's home edit), the log.

## Controls

- None.

## Verify

- The build and check commands of 0168.
- Tests: a new world's home has a bowl below the generated surface and a rim above it within the record's radii; the pod's floor cell is at the floor's level and no foundation entity exists; two sessions with the seed hash alike after the edit; a save round trips the crater as changed chunks; the spawn is inside the cabin.
- The couch: the user starts a world in the pod, walks out of the airlock onto the crater floor and up the rim.
