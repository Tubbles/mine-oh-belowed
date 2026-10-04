# 0260: The pod's door faces the spring at every radius

Status: implementing (2026-10-04, in `.claude/worktrees/0260` on `item/0260` from `main` at 8aca2a0, the specification approved the same day with the decisions below; found by the 0184 implementer: `field_home_heading` (`src/simulation_field.odin`) passes the unnormalised difference from the home to the spring into `tangent_of`, which treats a look shorter than `UNIT_VECTOR_ONE / 16` as missing and falls back to +x; the shipped spring lies 204 m from the home at 8 km and 102 m at 4 km, so the door faces the spring only at 16 km; after 0184)

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

## Specification (design, 2026-10-04)

Everything below was tried in a scratch copy of `main` at `4dc96e0` (not in the repository): with the change and the test edits listed here, `odin check -vet -strict-style` is clean and the five tests named under Tests pass; with the change alone, the full suite ran 1907 tests and failed exactly the two field tests the item names, for the reasons given below.

### The change

`src/simulation_field.odin`, `field_home_heading`: the look becomes the normalised chord between the two unit directions; the radius parameter goes, since a unit chord does not depend on it.

```odin
// The heading at the home towards the first spring (towards +x on a
// planet without one, or with the spring on the home), a unit tangent:
// the chord from the home to the spring normalised before tangent_of,
// whose threshold of a sixteenth of a unit a chord of under 256 m in
// position units fell below (0260), so the heading is the same at every
// radius.
field_home_heading :: proc(planet: Planet, home: [3]i64) -> [3]i64 {
	look := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	if len(planet.springs) > 0 {
		if chord, ok := normalize_fixed(planet_spring_direction(planet.springs[0]) - home); ok {
			look = chord
		}
	}
	return tangent_of(home, look)
}
```

and in `field_home_site` the call becomes `field_home_heading(planet, home)`. It has no other caller (grep: `field_home_site` is its only one). `normalize_fixed` (`src/world_field_vector.odin`) is the existing procedure: integer `vector_length` (`integer_square_root`), then `vector * UNIT_VECTOR_ONE / length`; no new procedure, no float, so it is deterministic on every machine. Ranges: the difference of two unit vectors has components under 2^25, times 2^24 stays far inside an i64.

Why the chord clears `tangent_of` at every preset: the chord between two points of a sphere meets the tangent plane at either end at half the central angle. The shipped home (83, 132) and spring (83, 144) are 0.02548 rad apart (203.8 m at 8 km), so the unit chord's part along the home's radial is sin(0.01274) = 0.0127 of a unit and its tangent part cos(0.01274) = 0.99992 of a unit, against the threshold of 0.0625. It is radius independent, so the same at 4, 8 and 16 km. Precision: the unnormalised difference is about 0.0255 x 2^24 = 427,000 units, so the trig rounding of a unit or two per component turns the heading by about 1e-5 degrees. Only a spring within about 0.1 m of the home's direction on an 8 km planet would make the difference zero; then `ok` is false and the +x fallback holds as before.

### The heading and the door, by preset

The pod's frame forward is `nearest_frame_yaw_step` (`src/world_frame.odin`): the one of `FRAME_YAW_STEPS` (24, 15 degrees each) whose `frame_forward` has the largest `fixed_dot` with the heading, so at most 7.5 degrees off it. Step 0 faces the planet's north tangent and the step turns towards `north x up`, which is west, so step k's bearing is 360 - 15k degrees.

- By hand: the great circle bearing from the home to the spring is atan2(sin 12 cos 83, cos 83 sin 83 (1 - cos 12)) = 84.04 degrees (6 degrees north of due east). The nearest step is 18 (bearing 90, due east), 5.96 degrees off. The old heading at 4 and 8 km, +x projected at longitude 132, bears about 312 degrees (northwest), step 3 (bearing 315); at 16 km it was already the spring's, step 18.
- Read off the scratch run (a probe logging `field_home_site` and `nearest_frame_yaw_step` at spacing 1000 mm, default seed): the heading is `[-11245287, 212300, -12448831]` at all three presets, step 18 at all three, its dot with the spring's direction on the tangent plane 16777214 to 16777230 (1.0000), the frame forward's 16686637 to 16686648 (0.99460, 5.95 degrees). The implementer confirms these with the new test's own failure messages if they differ and puts the values it saw into the log section.

### Tests

The two field tests hold no heading literal; they failed because the new spawn turns the scripted walk out of the pod 135 degrees, onto other ground.

- `test_a_field_walk_counts_and_a_flight_does_not` (`src/simulation_field_test.odin`): failed at `expect_value(..., distance_walked_millimetres, 0)` with 1. The 1 mm is not the flight: it is the settle tick (`tick_field_test_simulation(state, simulation_content, {})`, not flying) on the new spot before the door, which slips the feet `[-2, 67, 10]` units (probe) and `queue_field_player_edit` (`src/field_mining.odin`) counts the tangent part. Change: right after that settle tick, `walked_before_flight := state.records.statistics.distance_walked_millimetres`; the flight assertion becomes `testing.expect_value(t, state.records.statistics.distance_walked_millimetres, walked_before_flight)`. The `> 1000` walk assertion stays. This states the test's claim (a flight adds nothing) without depending on the ground under the spawn.
- `test_two_field_simulations_hash_alike_and_part_on_one_input`: failed at `"the script placed it back"` only (the hashes, the frame, the torch and the dug topsoil held). After the turn at tick 490 (`look_delta = {-1800, -200}` in `field_test_script_frame`) the reticle finds no ground within reach on the new slope (`target.hit` false on every tick 520 to 559). Probed variants of the tick 490 look: pitch -200 places nothing, -150 places 262e9 of 492e9 held, -100 places 54e9, -50, 0 and +100 aim at ground but place nothing (too near the player). Change: tick 490 becomes `frame.look_delta = {-1800, -150}`; the script's comment above `field_test_script_frame` stays true. Tick 490 is used only by this test (`test_two_field_simulations_hash_alike_after_a_walk_over_dug_ground` leaves the script at tick 480; it passed in the scratch run).
- Restored in `src/loop_planet_preview_test.odin`: `test_planet_preview_start_camera_frames_the_pod` is renamed `test_planet_preview_start_camera_frames_the_pod_and_the_spring` and gains the 0184 specification's assertion: "with yaw 0, the angle between the camera's look (`planet_preview_basis_to_world(basis, fly_camera_forward(camera))`) and the direction from the camera to the site is under 30 degrees, and to the first spring's surface point (`planet_spring_direction` scaled to the radius plus `surface_relief` there) under 30 degrees (a cone inside the 35 degree vertical half field of view, so both are in the frame whatever their bearing); the camera stands 35 to 45 m above the site along the up." Code, after the pod angle check:

  ```odin
  spring_direction := planet_spring_direction(home.planet.springs[0])
  spring_ground := home.generation.radius + surface_relief(home.generation, fixed_scale(spring_direction, home.generation.radius))
  spring := world_position_to_metres(World_Position(fixed_scale(spring_direction, spring_ground)))
  spring_angle := planet_preview_test_angle_degrees(look, spring - camera.position)
  testing.expectf(t, spring_angle < 30, "at %d m the spring lies %v degrees off the look", radius, spring_angle)
  ```

  Scratch run: the spring lies 10.9, 15.2 and 21.0 degrees off the look at 4, 8 and 16 km (the pod 20.0). The comment above the test is rewritten to: "The pod and the first spring lie inside a cone within the 35 degree vertical half field of view, whatever their bearing (0260: the door faces the spring at every preset)."
- New in `src/simulation_field_test.odin`, after `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin`: `test_the_home_heading_faces_the_spring_at_every_preset`. For each preset of `default_planet(shipped_test_planets())` (`shipped_test_home_at(radius)`, spacing 1000, `DEFAULT_WORLD_SEED`): `site, heading := field_home_site(...)`; `up` the normalised site; `towards` the normalised `project_onto_plane(fixed_scale(planet_spring_direction(planet.springs[0]), generation.radius) - site, up)`; asserts `fixed_dot(heading, towards) > UNIT_VECTOR_ONE * 9998 / 10000` (1 degree) and, with `_, axes := free_frame_at(site, heading, 500)`, `fixed_dot(axes[FRAME_FORWARD], towards) > UNIT_VECTOR_ONE * 9914 / 10000` (half a step, 7.5 degrees). Passed in the scratch copy; with the old code it fails at 4 and 8 km (0184 measured the spring 94 and 109 degrees off). Pure procedures, no state directory.
- `test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin` (its door check is against `heading`, cosine over 0.990) passes unchanged with the new 5.95 degrees.

### Save rule

No save, record or network layout change. The pod's frame (origin and axes) is saved: `write_frame_tables` / `read_frame_tables` (`src/entity_frames.odin`, called from `src/save_state.odin`) write and read `entities.frames.frames` whole, and `field_pod_spawn` reads the saved frame's forward, so a loaded world, a joiner and a resized old pod (`upgrade_resized_pods`, `src/entity_pod.odin` line 437, which re-places it with the old frame's `axes[FRAME_FORWARD]`) keep the old door. Only `enable_new_field_world` (a new world) and `field_home_player` (content without a pod) read the new heading. No remap, no log line in the game; the log section names that an old world keeps its door.

### Docs

- `doc/architecture.md`, The field session, the bullet "The start:" (line 47): after "its frame's forward the yaw step of the heading towards the first spring" insert " (`field_home_heading`: the home to spring chord normalised and projected onto the home's tangent plane, so the spring's distance does not matter; the shipped door lies 6 degrees off the spring at every preset, 0260)".
- `doc/content.md`: no edit. Lines 134 and 220 already say the pod lands with its door (heading) towards the first spring, which is now true at every preset; the mechanism lives in `architecture.md` (one place per fact).
- `doc/build.md`, the `--planet-preview-screenshot` paragraph (line 138): "the pod in its crater, the groves and the land ahead to the horizon in one frame" becomes "the pod in its crater, the groves, the land ahead towards the first spring, the spring and its basin and the horizon in one frame".
- `doc/log/2026-10-04.md`, a new section at the end:

  ```
  ## The pod's door faces the spring at every radius (0260)

  Tags: field, pod, spawn, heading, lockstep, 0260, m14
  ```

  then one paragraph: `field_home_heading` normalises the home to spring chord before `tangent_of`, replacing the scaling by the radius of 2026-10-03, which cleared the sixteenth of a unit threshold only with the spring over 256 m away (16 km); the heading is now the same at every preset (the values read off the run: the heading vector, yaw step 18, 5.95 degrees off the spring), and a new world's pod at 4 and 8 km turns from step 3 (northwest) to step 18; a saved world keeps its door (the frame is saved); the walk test now measures the flight from the walked count after the settle tick (the new spot slips 1 mm), and the hash test's turn at tick 490 looks 150 instead of 200 up, since the new slope left no ground in reach.

`tools/check_docs.py` and the code map: no file added or renamed, so `doc/code_map.md` does not change.

### Hand-back check

- The save layout line: no layout change and no old save stopped (above). Applies, satisfied.
- Deterministic simulation (Code rules): integer and fixed point only (`normalize_fixed`, `tangent_of`), no float, no wall clock; two machines of one build make the same pod. The hash test covers it.
- A number parsed from text: the latitude and longitude are already bounded by the planet record's checks; nothing new parsed.
- The other lines (memory freed during a frame, file writes, start up loads, shared budgets, unbounded lists, UI audits, tests touching the state directory) do not apply: no UI, no file, no budget; the tests are pure.

### Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`, each pinned with `taskset -c 8-15 nice -n 10`.
- The screenshot the main agent reads: `--planet-preview-screenshot=tmp/preview_0260_spring.png` at the default 8 km: the pod in the crater in the lower half with its door towards the camera's look, and about 15 degrees over the frame's centre, 204 m out along the door direction, the spring and the water running into its hollow below the sea about 30 m from it, before the horizon.

### Questions to the main agent

1. The radius parameter of `field_home_heading` goes (the unit chord needs none). Keeping it and normalising `fixed_scale(spring, radius) - fixed_scale(home, radius)` instead works too, with headings that differ by rounding between presets; dropping it was chosen for the "same at every radius" claim the new test and the log can state.
2. The hash test's tick 490 retune (-200 to -150) and the walk test's baseline are test script edits, not behaviour; confirm that is acceptable rather than moving `move_test_players_out_of_the_pod` to a fixed bearing.

### Decisions at the approval (main agent, 2026-10-04)

1. Question 1: the radius parameter goes. The chord between two unit directions does not depend on the radius, and the test and the log can then state that the heading is the same at every preset.
2. Question 2: the two test script edits are accepted (the hash test's tick 490 look at -150, the walk test's baseline taken after the settle tick). Both keep each test's claim and avoid a change to `move_test_players_out_of_the_pod` that every field test would feel.
