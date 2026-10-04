# 0184: The planet preview starts at the home

Status: implementing (2026-10-04, in `.claude/worktrees/0184` on `item/0184` from `main` at 716805e, the specification approved the same day with the decisions below, first item of M14's look stream (0237); M13 follow up, from the wiring of 0179; whenever the assistant needs it)

## Goal

The planet preview's screenshots show the pod, the starter outcrops and the spring's basin. Today `planet_preview_start_camera` (`loop_planet_preview.odin`) starts over the pole with the fly camera's up along the pole, while the home lies about 560 m away at 8 km, so the preview's scene (the pit, the pads, the arms, the run) and the pod never share a shot (2026-10-03, the shots needed a temporary data edit moving the home to the pole).

## Change

- The preview starts over the planet's home (`planet_home_direction`), its fly camera and the screenshot's fixed camera taking the radial there as their up, the yaw towards the spring; the walk mode spawns as a session does, in front of the pod's door.
- The preview's scene lands beside the pod's pad (the pit and the pads a few metres further along the heading), so one shot holds the pod, a pad with the arms, the run and an outcrop.
- `doc/build.md` (the command line's preview flags) updated.

## Verify

- The build and check commands of 0168; the preview's tests.
- Screenshots read by the main agent: `--planet-preview-walk` with `--planet-preview-pitch=-10` shows the pod and an outcrop; the default pitch still shows the pit and the torch.

## Specification (design, 2026-10-04)

### What changed since the item was written

The item predates the crater (0199) and the cabin spawn (0221). A session now spawns its player inside the pod's cabin facing the door, and the pod stands on the 4 m floor of a crater whose bowl climbs 4 m to a crest at 12 m and whose rim reaches 18 m (`data/planets.sjson`, `crater`). From the cabin or from in front of the door the bowl hides everything outside the crater, and a pad 9 m ahead of the door would stand in the bowl. From outside the crater at eye height the crest hides the pod. The one ground level vantage that sees both the pod and the land outside is the crest itself, so the walk spawn stands there (question 1 below), and the pads go outside the 18 m reach on the walker's left.

### Geometry (all in the home's frame)

The home's frame is the pod's: `site, heading := field_home_site(generation, planet)`, then `_, axes := free_frame_at(site, heading, foundation_pitch_millimetres)`, exactly as `place_pod` builds it, so `axes[FRAME_FORWARD]` is the pod's door direction (the yaw step nearest the first spring) and `axes[FRAME_UP]` the radial at the site. `axes[FRAME_RIGHT]` is `up × forward`, which is the walker's LEFT (the field player's right is `forward × up`, `field_player_right`). Offsets below are "forward" along `axes[FRAME_FORWARD]` and "frame right" along `axes[FRAME_RIGHT]`, from the site (the crater floor's centre, the pod's centre within a quarter metre).

- Free camera start and fixed screenshot camera (one camera, question 3): 40 m above the site along the up and 40 m back (forward -40 m), yaw 0 (along the door direction, towards the spring) plus `--planet-preview-yaw`, pitch -25. The pod is 45 degrees below the horizontal, 20 degrees under the frame's centre; the spring (204 m from the home at 8 km, 102 m at 4 km, 408 m at 16 km) is 7 to 16 degrees over the centre; the horizon (about 800 m from 40 m up) at 25 degrees over it. The pod is 57 m from the camera, inside the finest level distance (64 m). Outcrops 30 to 80 m from the home ahead or beside the pod fall between.
- Walk spawn: forward -10.9 m, frame right +5.1 m (12.03 m from the site: the crest), on the generated surface plus `FIELD_SPAWN_CLEARANCE_MILLIMETRES`, heading the door direction, yaw `--planet-preview-yaw`, pitch 0. The pod's centre lies 25 degrees to the walker's right, its footprint between 8 and 46 degrees (the horizontal half field of view is 51 degrees at 1280 by 720 and 70 degrees vertical). From the eye (crest plus 1.6 m, 5.6 m over the floor) at pitch -10 the pod's middle is 7 degrees and its base 15 degrees below the frame's centre.
- Pit: unchanged (`dig_planet_preview_pit`, 3.3 m ahead of the feet along the heading, 1.5 m below them, radius 2.5 m). It lands 9.2 m from the site on the bowl's inner slope behind the pod; the sphere stays 6.6 m from the site, clear of the pod's corners at 4.3 m. A pit is dug, nothing stands in it.
- First pad: its centre's point at forward +5 m, frame right +20 m (20.6 m from the site; its nearest corner 18.8 m, outside the 18 m reach), on the generated surface, its free frame's heading the home's forward (so its frame takes the pod's yaw step). From the walker it lies 43 degrees to the left, 22 m away; the sight line from the eye runs along the crest (its closest approach to the site is 11.1 m, 0.13 m under the crest) and then down the rim's outer slope, so the pad is not hidden. The arms and the column stay on their cells (`PLANET_PREVIEW_RESTING_ARM_CELL`, `PLANET_PREVIEW_REACHING_ARM_CELL`: x -2 is towards the crater, facing the walker).
- Second pad and run: unchanged code (`lay_planet_preview_run`): 12 m from the first along its forward plus its frame right, which is further out and away from the crater (about 31 m from the site, 44 degrees left of the walker, 34 m away). `clear_trees_under_frames` clears trees under both, as today.

### Procedures (all in `src/loop_planet_preview.odin` unless named)

- New struct `Planet_Preview_Basis :: struct { forward, up, right: [3]f32 }`: the free camera's frame; a `Fly_Camera` local vector (x along the yaw 0 forward, y up, z the yaw +90 right, `render_fly_camera.odin`'s convention) maps to `x * forward + y * up + z * right`.
- New `planet_preview_basis :: proc(axes: [3][3]i64) -> Planet_Preview_Basis`: forward `unit_vector_to_f32(axes[FRAME_FORWARD])`, up `unit_vector_to_f32(axes[FRAME_UP])`, right `-unit_vector_to_f32(axes[FRAME_RIGHT])` (forward × up). Called once in `run_planet_preview`.
- New `planet_preview_basis_to_world :: proc(basis: Planet_Preview_Basis, local: [3]f32) -> [3]f32`. Called by the three procedures below that read the free camera.
- New `planet_preview_home :: proc(generation: Planet_Generation, planet: Planet, pitch_millimetres: int) -> (site: World_Position, axes: [3][3]i64)`: `field_home_site` then `free_frame_at` as above. Called in `run_planet_preview` with `session.field_content.foundation_pitch_millimetres`.
- New `planet_preview_home_point :: proc(site: World_Position, axes: [3][3]i64, forward_millimetres, frame_right_millimetres: int) -> World_Position`: `site + fixed_scale(axes[FRAME_FORWARD], millimetres_to_position_units(forward)) + fixed_scale(axes[FRAME_RIGHT], millimetres_to_position_units(frame_right))`. Not on the ground; callers pass it through `field_surface_under`.
- Changed `planet_preview_start_camera :: proc(site: World_Position, basis: Planet_Preview_Basis, yaw_degrees: int) -> Fly_Camera`: position `world_position_to_metres(site) + basis.up * PLANET_PREVIEW_START_HEIGHT_METRES - basis.forward * PLANET_PREVIEW_START_BACK_METRES`, yaw `f32(yaw_degrees)`, pitch `PLANET_PREVIEW_START_PITCH`. Used for both the interactive start and the screenshot.
- Removed `planet_preview_screenshot_camera`, `PLANET_PREVIEW_SCREENSHOT_CLEARANCE_METRES`, `PLANET_PREVIEW_SCREENSHOT_PITCH`, `PLANET_PREVIEW_START_YAW` and the comment above it (the pole and longitude 132 no longer apply). The `if screenshot_path != ""` camera override in `run_planet_preview` goes.
- New `planet_preview_free_camera :: proc(camera: Fly_Camera, basis: Planet_Preview_Basis, field_of_view: f32) -> rl.Camera3D`: position `camera.position`, target `camera.position + planet_preview_basis_to_world(basis, linalg.normalize(fly_camera_forward(camera)))`, up `basis.up`, perspective. Replaces the `fly_camera_to_raylib` call in `planet_preview_raylib_camera`. `fly_camera_to_raylib` and `Fly_Camera` stay untouched (the block world uses them).
- Changed `fly_planet_preview`: the velocity goes through `planet_preview_basis_to_world(preview.basis, fly_camera_velocity(...))`, so Jump and Sneak move along the home's radial and the move keys along its tangent plane. The basis stays the home's when the camera flies far (as the pole's +y did before); the walk mode keeps its own up.
- New `planet_preview_home_walker :: proc(generation: Planet_Generation, site: World_Position, axes: [3][3]i64, yaw_degrees: int) -> Field_Player`: `feet := field_surface_under(generation, planet_preview_home_point(site, axes, -PLANET_PREVIEW_WALK_BACK_MILLIMETRES, PLANET_PREVIEW_WALK_FRAME_RIGHT_MILLIMETRES), millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES))`, `body := make_field_player(feet, axes[FRAME_FORWARD])`, `body.yaw = degrees_to_angle_units(yaw_degrees)`. Pure; called by `run_planet_preview` when `walk` is set (interactive and screenshot alike).
- New `planet_preview_body_under_camera :: proc(preview: ^Planet_Preview) -> Field_Player`: today's body of `start_planet_preview_walk` (the surface under the free camera, heading where it looks), with `forward` now `planet_preview_basis_to_world(preview.basis, fly_camera_forward(preview.camera))`. Called by the G key in `update_planet_preview_input`.
- Changed `start_planet_preview_walk :: proc(preview: ^Planet_Preview, body: Field_Player)`: sets `planet_preview_player(preview).field = body` and resets `walking`, `tick_seconds`, `tick_input`, `turn_remainder` as today.
- Changed `lay_planet_preview_foundations`: the free foundation's hit is `field_surface_under(generation, planet_preview_home_point(preview.home_site, preview.home_axes, PLANET_PREVIEW_PAD_FORWARD_MILLIMETRES, PLANET_PREVIEW_PAD_FRAME_RIGHT_MILLIMETRES), 0)` and its heading `preview.home_axes[FRAME_FORWARD]` (no longer the player's heading). The rest (the square, the column, the arms, the run, the trees) stays.
- `Planet_Preview` gains `home_site: World_Position`, `home_axes: [3][3]i64` and `basis: Planet_Preview_Basis`, set in `run_planet_preview` before the camera.
- Changed `run_planet_preview`: a new last parameter `yaw_degrees: int`, range checked after the pitch as `-PLANET_PREVIEW_YAW_LIMIT_DEGREES` to `PLANET_PREVIEW_YAW_LIMIT_DEGREES` with the log line `error: --planet-preview-yaw=%d is outside %d to %d` and exit 1; makes `generation := make_planet_generation(seed, planet, spacing)` once; fills the three new fields; `camera = planet_preview_start_camera(home_site, basis, yaw_degrees)`; with `walk`, `start_planet_preview_walk(&preview, planet_preview_home_walker(generation, home_site, home_axes, yaw_degrees))`; the startup log line adds the home: `planet preview: %s, seed %d, radius %d m, home at latitude %d longitude %d`.
- Constants: `PLANET_PREVIEW_START_HEIGHT_METRES :: 40` and `PLANET_PREVIEW_START_PITCH :: -25` stay (now above the home's crater floor); new `PLANET_PREVIEW_START_BACK_METRES :: 40`, `PLANET_PREVIEW_WALK_BACK_MILLIMETRES :: 10900`, `PLANET_PREVIEW_WALK_FRAME_RIGHT_MILLIMETRES :: 5100`, `PLANET_PREVIEW_PAD_FORWARD_MILLIMETRES :: 5000`, `PLANET_PREVIEW_PAD_FRAME_RIGHT_MILLIMETRES :: 20000`, `PLANET_PREVIEW_YAW_LIMIT_DEGREES :: 180`; removed `PLANET_PREVIEW_PAD_DISTANCE_MILLIMETRES`. Each carries a comment with the metres it puts the thing at relative to the crater (the crest at 12 m, the reach at 18 m) and that the walk numbers assume the shipped crater, which the tests pin.
- `src/main.odin`: new field `planet_preview_yaw: int` with usage `<degrees>: turns the planet preview's start camera and walker from the pod's door direction (towards the first spring), from -180 to 180, positive to the right (default 0)` and a comment `// Work item 0184`; passed as the last argument of `run_planet_preview`; added to the preview flags that start the preview (line 275, `|| command_line.planet_preview_yaw != 0`) and to `workbench_conflict`'s second line (`|| command_line.planet_preview_yaw != 0`). Zero needs no default in `parse_command_line`.
- The file's header comment (lines 34 to 56) rewritten for the new cameras, the walk spawn on the crest and the pad outside the crater; the run's header in `loop_planet_preview_runs.odin` is still true and stays.

No simulation, save, record, network or string key change: the preview writes the session's state between ticks as before and never saves.

### Tests

New file `src/loop_planet_preview_test.odin` (package game; pure procedures only, no window, no state directory). Each runs at every radius preset of the shipped home (`shipped_test_home_at` over `default_planet(shipped_test_planets()).radius_presets_metres`), spacing 1000 mm, `DEFAULT_WORLD_SEED`, pitch 500 mm, with `site, axes := planet_preview_home(make_planet_generation(...), planet, 500)`.

- `test_planet_preview_basis_follows_the_home`: `basis.up` is within 0.001 of the site's unit radial; forward, up and right are unit length and pairwise orthogonal within 0.001; `planet_preview_basis_to_world(basis, fly_camera_forward(Fly_Camera{yaw = 90}))` is within 0.001 of `unit_vector_to_f32(fixed_cross(axes[FRAME_FORWARD], axes[FRAME_UP]))` (yaw turns right as the field player's yaw does).
- `test_planet_preview_start_camera_frames_the_pod_and_the_spring`: with yaw 0, the angle between the camera's look (`planet_preview_basis_to_world(basis, fly_camera_forward(camera))`) and the direction from the camera to the site is under 30 degrees, and to the first spring's surface point (`planet_spring_direction` scaled to the radius plus `surface_relief` there) under 30 degrees (a cone inside the 35 degree vertical half field of view, so both are in the frame whatever their bearing); the camera stands 35 to 45 m above the site along the up.
- `test_planet_preview_walker_stands_on_the_crest`: for `planet_preview_home_walker(generation, site, axes, 0)`: the feet's distance from the site on the site's tangent plane (`vector_length(project_onto_plane(feet - site, axes[FRAME_UP]))`) is within 0.5 m of `planet.crater.radius_metres`; the site lies ahead (positive along `field_player_heading`) and to the right (positive along `field_player_right`) at a bearing between 15 and 35 degrees (right times 1000 over ahead between 268 and 700); `fixed_dot(field_player_heading(body), axes[FRAME_FORWARD])` is over 0.99 of `UNIT_VECTOR_ONE`. With yaw 40 the heading's dot with the forward is within 0.01 of the cosine of 40 degrees.
- `test_planet_preview_pads_stand_outside_the_crater_in_view`: the first pad's point (`planet_preview_home_point(site, axes, PLANET_PREVIEW_PAD_FORWARD_MILLIMETRES, PLANET_PREVIEW_PAD_FRAME_RIGHT_MILLIMETRES)`) lies, on the tangent plane, farther from the site than the crater's reach (`radius_metres + CRATER_RIM_FALL_PER_HEIGHT * rim_metres`, 18 m) plus the pad's half diagonal (`(2 * PLANET_PREVIEW_PAD_HALF_WIDTH + 1) * 500 mm * 1414 / 2000`); from the walker of yaw 0 it lies ahead and left at under 50 degrees (minus right times 1000 over ahead under 1192). The second pad's point (the first pad's `free_frame_at` frame on the ground, `frame_cell_bottom(frame, {})` plus `planet_preview_run_direction(frame)` times `PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES`) is ahead and left under 50 degrees too.
- `src/main_test.odin`, `test_command_line_seed_and_debug_terrain`: `empty.planet_preview_yaw` is 0, `--planet-preview-yaw=-40` parses to -40. `test_command_line_model_workbench_flags`: `--planet-preview-yaw=30` joins the loop of flags `--model-check` refuses.

### Docs

- `doc/build.md`, the flags table: a row `--planet-preview-yaw=<degrees>` (the start camera's and the walker's turn from the pod's door direction, -180 to 180, default 0); the `--planet-preview-walk` row unchanged.
- `doc/build.md`, the `--planet-preview` paragraph: the fly camera starts 40 m above the home's crater floor and 40 m behind the pod, looking along its door towards the first spring 25 degrees down, the home's radial its up (moving along the home's tangent plane and radial wherever it flies); the sentence about the pole showing neither the pod nor the veins goes.
- `doc/build.md`, the `--planet-preview-screenshot` paragraph: the fixed camera is the start camera (the pod, the outcrops round it, the spring and its basin and the horizon in one frame); the pole, longitude 132 and the finest distance less 2 m go; the frame count and the save rule stay. Name `--planet-preview-yaw` as the way to turn the shot towards an outcrop or a biome edge.
- `doc/build.md`, the walk mode paragraph: `--planet-preview-walk` stands the player on the crater's crest behind the pod and to its left (10.9 m back, 5.1 m aside), heading along the door, turned by the yaw flag; G still stands it under the free camera. The pit paragraph's numbers stay.
- `doc/build.md`, the foundations paragraph (0174): the pad lies 5 m ahead of the pod and 20 m to its side, outside the crater's 18 m reach, on the walker's left, not 9 m ahead; the runs paragraph (0176) gains that the second pad lies further out, and its command line stays.
- `doc/presentation.md`: no paragraph describes the preview's cameras (line 55 names the preview only), so no change; the implementer confirms with `grep -n "pole" doc/presentation.md`.
- `doc/code_map.md`, line 73: add the home (`planet_preview_home`, the walk spawn on the crest, `planet_preview_home_walker`) to the file's line.
- `doc/log/2026-10-04.md`: one paragraph tagged `#planet-preview #0184`: the walk spawn on the crest instead of the cabin or the door and why, the one camera for start and screenshot, the yaw flag.
- `SUGGESTIONS.md` line 135 stays (it lists the items made).

### Hand-back check lines that apply

- A number parsed from text is range checked: `--planet-preview-yaw` is checked against -180 to 180 in `run_planet_preview` before any window opens, as the pitch is.
- Tests never touch the machine's state directory: the new tests are pure and open no window.
- The rest (frees between frames, file writes, start-up fallbacks, save layouts, shared budgets, unbounded lists, audit cases) do not apply: no memory is freed, no file is written but the screenshot (unchanged), no save, no UI.

### Screenshots for the main agent to read

Built with `./build.sh`, each under `xvfb-run -a -s "-screen 0 1280x720x24" build/mine-oh-belowed ...`:

1. `--planet-preview-screenshot=tmp/preview_0184_home.png`: the pod in the crater in the lower half, the land towards the spring, the spring's basin and the horizon in the upper half; outcrops if any lie in the frame.
2. `--planet-preview-walk --planet-preview-screenshot=tmp/preview_0184_level.png --planet-preview-pitch=-10`: the pod in the crater on the right, the first pad with its two arms and column and the run to the second pad on the left, the land beyond; the item's Verify needs an outcrop here too (question 4).
3. `--planet-preview-walk --planet-preview-screenshot=tmp/preview_0184_pit.png`: the pit dug into the bowl's slope ahead with the torch at its bottom.

### Open questions answered

- Fly camera up: a basis in the preview, not a new field on `Fly_Camera`, because `Fly_Camera`, `fly_camera_to_raylib` and `fly_camera_velocity` are the block world's too (`loop.odin`, `player.odin`, `render_player.odin`) and the field player's camera already has its own up (`field_camera`).
- Yaw towards the spring: the pod's frame forward, the yaw step nearest the spring (at most 7.5 degrees off it), so the pod faces straight into the shot and the pads take the pod's yaw step.
- Pads relative to the home's frame rather than the walker's heading, so turning the walker with the yaw flag turns the view and keeps the scene where the crater allows it.

### Decisions at the approval (main agent, 2026-10-04)

1. Question 1: the walker on the crater's crest behind and left of the pod, as specified. The item's "in front of the pod's door" predates the crater and the cabin spawn; the shots want the pod and the land in one view.
2. Question 2: `--planet-preview-yaw` stays, range checked as specified. The look items of 0237 aim their shots with it.
3. Question 3: the old screenshot camera's framing (62 m over the pole, 8 degrees down) goes. The level of detail seams of 0169 were verified then; a far view is still had from the walk mode with `--planet-preview-pitch=0` and the yaw flag, and a later level of detail item sets its own shot.

### Questions for the main agent

1. The walk spawn: the item says "as a session does, in front of the pod's door". Since 0221 a session spawns in the cabin, and from the door the bowl hides the pads and the land outside while the pod stays behind the camera. The specification stands the walker on the crest behind and left of the pod instead. Accept, or keep the door and give up the pod and the pads in the walk shots?
2. `--planet-preview-yaw` is new and not in the item. It is there because whether an outcrop falls in either shot depends on the seed's vein bearings (each vein in its third of the turn, 30 to 80 m out), which cannot be read without running the generation, and the brief's later biome edge needs the same aim. Keep it, or drop it and record which shots show an outcrop?
3. The fixed screenshot camera becomes the start camera (40 m up, 40 m back, 25 degrees down). The old one (62 m over the pole, 8 degrees down, the horizon near the last level distance) was framed for the level seams; nothing else reads it. Accept losing that framing?
4. Not determinable without a run: whether the default seed puts an outcrop in shot 1 or 2, and how much of the first pad shows over the rim's outer slope, which depends on the relief round the crest (the margins computed on the bare crater profile are 0.3 to 0.5 m). The main agent reads shots 1 and 2 first; the pad constants and the yaw are the knobs.
5. 0180 (open) will move the home to the nearest dry point and may stand the spawn on edited ground. The preview follows it through `field_home_site`; if 0180 changes that procedure's signature, the preview's `planet_preview_home` follows in 0180's change.
