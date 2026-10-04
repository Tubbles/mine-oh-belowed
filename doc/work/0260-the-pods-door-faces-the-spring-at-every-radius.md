# 0260: The pod's door faces the spring at every radius

Status: todo (2026-10-04, found by the 0184 implementer: `field_home_heading` (`src/simulation_field.odin`) passes the unnormalised difference from the home to the spring into `tangent_of`, which treats a look shorter than `UNIT_VECTOR_ONE / 16` as missing and falls back to +x; the shipped spring lies 204 m from the home at 8 km and 102 m at 4 km, so the door faces the spring only at 16 km; after 0184)

## Goal

The pod lands with its door towards the first spring at every radius preset, as 0179 intended, so the walk to water is the walk out of the door and the preview's shots along the door direction hold the spring's basin.

## Controls

No binding changes.

## Change

- `field_home_heading` normalises the home to spring difference before `tangent_of` (or `tangent_of` takes a normalised look), in fixed point, so the heading is the same on every machine.
- The spawn heading of a new world changes with it: `test_a_field_walk_counts_and_a_flight_does_not` and `test_two_field_simulations_hash_alike_and_part_on_one_input` carry the old heading in their expectations and are updated, with the new values read off a run and named in the log. A world saved before the fix keeps its pod where it stands (the frame is saved); only a new world lands turned.
- The 0184 preview's spring test comes back (`test_planet_preview_start_camera_frames_the_pod_and_the_spring` as the 0184 specification wrote it), and `doc/build.md`'s screenshot paragraph names the spring's basin again.
- Docs: `doc/architecture.md` (the home and the spawn), `doc/content.md` if it states the door's direction, `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: the heading points within a few degrees of the spring at 4, 8 and 16 km; the two field tests pass with their updated expectations; the preview's spring test passes at every radius preset.
- The screenshot `--planet-preview-screenshot` shows the spring's basin along the door direction at 8 km.
