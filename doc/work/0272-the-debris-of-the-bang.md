# 0272: The debris of the bang

Status: verified (2026-10-05)

## Goal

At the hit the ground flies: clods on ballistic arcs out of the crater as an inverted cone, the dust curtain along the rim, a bang over the crash, and the debris strewn round the pod for the first minutes. With 0271 (the crater) and after 0223 (the dust).

## Controls

No binding changes.

## Change

- Presentation only, hashed per piece like the dust puffs (`arrival_dust_puff`), nothing in the simulation: the ejecta curtain at about 45 degrees, the inner pieces fastest and farthest, half landing within a crater radius of the rim and none beyond five radii (the note's numbers), drawn as boxes in the ground's colour, resting where they land for a data number of seconds and sinking away; the dust ring moved from the pod to the rim; the shake stronger.
- Sounds: a bang layered on the crash and the patter of the fall, pitched by the world's hash, never on a fixed period.
- Data: the piece count and the seconds in `game.sjson`.
- Docs: `doc/presentation.md` (The arrival), `doc/log`.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`, `python3 tools/check_docs.py`, `python3 tools/code_graph.py --check doc/code_map.md`.
- Tests: every arc lands within five radii and half within one radius of the rim; no piece rests inside the pod's hull; the presentation leaves the hash alone.
- The couch: the bang from the chair, then the strewn clods outside.

## Specification (design, 2026-10-05)

Designed against the approved specifications and decisions of 0270 (`pod_base_centre`, `pod_rest_pose`, the dust about the planet's up, the Settled phase drawing the rested frame unmoved) and 0271 (`baked_planet_generation`, the crater dug at the hit, `Crater_Term`), read in 0270's worktree as it stood. Built on 0271's tip. Presentation only: nothing here writes the simulation, every value is a pure function of the piece's index, the seconds since the hit, the world's seed, the baked generation (the crater's shape and the natural relief) and the pod's frame, recomputed every frame. No save, record or network change.

### The rule

- A piece's launch share `s` (hashed, 0 inner to 1 outer) fixes everything ordered: it leaves the bowl at `ρ = ρ_min + (ρ_max − ρ_min)·s` from the crater's home, `ARRIVAL_DEBRIS_LAUNCH_SPREAD_SECONDS · s` (0.4) after the hit, so the inner pieces leave first. `ρ_min = max(floor radius, clear)`, `ρ_max = max(0.85 · radius, ρ_min + 0.5)`, `clear` the pod's base centre's horizontal distance from the home plus the pod's reach (below).
- It lands at `d = d_min / (1 − (1 − d_min / d_max)·u)` from the home, `u = clamp(1 − s + 0.1·(h − 0.5), 0, 1)`, `d_min = max(radius, clear + 1)`, `d_max = 5 · radius`: the blanket's thickness falls as the cube of the distance (the note), so with `d_min` the radius 62.5 percent land within a radius of the rim and none beyond five radii, the inner pieces farthest.
- Both points are the baked generation's surface on the radial through the point at that tangent distance along the hashed azimuth (the landing's azimuth jittered by up to ±0.075 rad): `field_surface_under(baked, position, 0)`. This is the simplest honest ground: the rim and the natural relief exactly as dug, three octaves and the ledges per point, well under a microsecond. Not the field: a raycast per piece per frame costs more and the dug field equals the baked generation outside the bed, which no piece reaches. A clod over ground a player dug later floats, accepted.
- The arc: `Δ = landing − launch`, `dy = Δ·up` (the planet's up at the home, gravity along it, so the curvature is in the points), `dx` the rest's length, `along` its unit. `lift = max(dx·tan θ − dy, 0.25·dx·tan θ)`, `T = sqrt(2·lift / g)`, `vy = dy / T + g·T / 2`: a true parabola from the launch to the landing exactly, leaving at `θ` (`arrival_debris_angle_degrees` jittered ±3 degrees), steeper only where the guard holds. Speed follows from the distance, so the inner pieces are fastest. `g` is 0269's `ARRIVAL_GRAVITY_METRES_PER_SECOND_SQUARED`.
- At rest the clod keeps the tumble it landed with, sunk a quarter of its edge. From `launch + T + rest·(0.7 + 0.3·h)` it sinks into the ground over `ARRIVAL_DEBRIS_FADE_SECONDS` (8) and is gone: the fade is a sinking, since translucent boxes need sorting against each other and the field.
- The pod's reach: `sqrt((w/2 + 1)² + (d/2 + 1)² + (h + 1)²)` cells times the pitch (6.6 m shipped), a sphere about the base centre holding the hull and a cell round it in any pose, so no arc starts inside it and every horizontal distance from the home grows along an arc.
- The material: stone for `s < 0.3` (dug from below the 2 m of topsoil), topsoil else, each piece's colour the material's tile mean times the palette's tint at the home times the field shader's `tint_scale` (2), its brightness hashed 0.85 to 1.1, each face shaded `0.5 + 0.5·max(n·up, 0)` times the scene's `day_factor`.

### Files and procedures

- New `src/render_arrival_debris.odin` (presentation cluster):
  - Constants `ARRIVAL_DEBRIS_SALT :: 0x64656272`, `ARRIVAL_DEBRIS_LAUNCH_SPREAD_SECONDS :: 0.4`, `ARRIVAL_DEBRIS_FADE_SECONDS :: 8.0`, `ARRIVAL_DEBRIS_FLIGHT_SECONDS :: 8.0` (the bound of launch plus flight, asserted at the largest crater), `ARRIVAL_DEBRIS_SMALLEST_METRES :: 0.15`, `ARRIVAL_DEBRIS_LARGEST_METRES :: 0.6` (edge `smallest + (largest − smallest)·h²`), `ARRIVAL_DEBRIS_TINT_SCALE :: 2.0`, `ARRIVAL_PATTER_SHARE :: 0.5`, `ARRIVAL_BANG_SOUND :: "arrival_bang"`, `ARRIVAL_PATTER_SOUNDS :: [3]string{"arrival_patter_1", "arrival_patter_2", "arrival_patter_3"}`.
  - `Arrival_Debris_Site :: struct { generation: Planet_Generation, home, up, east, north: [3]f32, radius_metres, floor_radius_metres, clear_metres, angle_radians: f32, pieces: int, rest_seconds: f32 }`.
  - `Arrival_Debris_Piece :: struct { launch, landing, along, spin_axis: [3]f32, launch_seconds, flight_seconds, reach_metres, vertical_speed, spin_radians_per_second, edge_metres, brightness, fade_seconds: f32, stone, sounds: bool, patter: int }`.
  - `arrival_debris_site :: proc(generation: Planet_Generation, config: Game_Config, pod_base: [3]f32, pod_reach_metres: f32) -> (site: Arrival_Debris_Site, found: bool)`: false when `generation.crater.reach == 0` or `arrival_debris_pieces` is 0. The generation `baked_planet_generation`'s, the home `crater.home` in metres, `up` its unit, `north` `frame_north_tangent` of the home's fixed unit, `east = north × up`.
  - `arrival_debris_ground :: proc(site: Arrival_Debris_Site, azimuth, distance_metres: f32) -> [3]f32`: the home plus `(east·cos + north·sin)·distance`, rounded to position units, through `field_surface_under`, back to metres.
  - `arrival_pod_reach_metres :: proc(machine: Machine, frame: Frame) -> f32`: the reach above.
  - `arrival_debris_piece :: proc(site: Arrival_Debris_Site, index: int, salt: u64) -> Arrival_Debris_Piece`: the rule, every hashed value `arrival_puff_fraction(hash_combine(hash_combine(salt, ARRIVAL_DEBRIS_SALT), index), key)` with its own key. `sounds` for a fraction below `ARRIVAL_PATTER_SHARE`, `patter` 0 to 2 hashed.
  - `arrival_debris_pose :: proc(piece: Arrival_Debris_Piece, seconds_since_hit: f32) -> (centre: [3]f32, turn: matrix[3, 3]f32, edge_metres: f32, visible: bool)`: hidden before the launch and after the fade, in flight `launch + along·reach·τ/T + up·(vy·τ − g·τ²/2 + edge/2)`, the turn `matrix3_rotate` about the spin axis by the rate times the flight's seconds so far.
  - `draw_arrival_debris :: proc(site: Arrival_Debris_Site, view: Arrival_View, salt: u64, colors: [2]rl.Color, light: f32)`: inside `BeginMode3D`, one `rlgl` quad batch of six shaded faces per visible piece, depth written, `min(site.pieces, MAXIMUM_ARRIVAL_DEBRIS_PIECES)` pieces.
  - `arrival_patter :: proc(site: Arrival_Debris_Site, index: int, salt: u64) -> (id: string, volume, pitch: f32, landing_seconds: f32, sounds: bool)`: volume `0.35 + 0.65·edge share`, pitch `0.8 + 0.4·h`.
  - `play_arrival_patter :: proc(mixer: ^Audio_Mixer, site: Arrival_Debris_Site, from_seconds, to_seconds: f32, salt: u64)`: every sounding piece whose landing lies in `(from, to]`. The mixer's 40 ms gap drops a collision, so the patter thins in its densest second.
- `render_arrival.odin`:
  - `arrival_settled_seconds :: proc(config: Game_Config) -> f32`: `max(ARRIVAL_DUST_SECONDS, ARRIVAL_DEBRIS_FLIGHT_SECONDS + rest + ARRIVAL_DEBRIS_FADE_SECONDS)` (166 s shipped). `arrival_view`'s Settled lasts it, not `ARRIVAL_DUST_SECONDS`: only the camera's Settled branch, the dust, the debris and the sounds read the phase, and the shake ends at its own seconds.
  - The shake: `ARRIVAL_SHAKE_METRES` 0.15 to 0.3, `ARRIVAL_SHAKE_SECONDS` 1.0 to 1.5.
  - The dust curtain replaces 0223's ring round the pod: `arrival_dust_puff(index, seconds_since_hit, salt, rim_metres) -> (azimuth, base_metres, drift_metres, height_metres, size_metres, alpha)`: base `rim·(0.9 + 0.2·h)`, drift outward `speed·0.8·(1 − exp(−t/0.8))`, height `0.3 + 3.5·h·(1 − exp(−t/1.2))`, size `1.2 + 3.5·t/ARRIVAL_DUST_SECONDS`, alpha as today. `ARRIVAL_DUST_PUFFS` 36 to 64. `draw_arrival_dust(site, view, salt, color)`: nothing at or past `ARRIVAL_DUST_SECONDS`, each puff on `arrival_debris_ground(site, azimuth, base)` moved out by the drift and up by the height, about the site's up and tangents (0270's frame based basis goes).
  - `Arrival_Sound_Memory.last_seconds_since_hit: f32`. `play_arrival_sounds(mixer, memory, view, arrival, paused, salt, site, site_found)`: the bang with the crash on the cut, pitched `arrival_sound_pitch(arrival, salt, 2)`. While Settled after a Descent or Settled frame, `play_arrival_patter` from the last seconds (0 after a Descent frame) to this frame's. A joiner's or a loaded world's first frame has `last_phase` None and plays nothing.
- `render_field.odin`: `Field_Renderer.material_colors: [FIELD_MATERIAL_TILE_COUNT][3]f32`, each tile's mean texel, set in `init_field_renderer`. `arrival_debris_colors :: proc(renderer: ^Field_Renderer, palette: [][3]int, site: Arrival_Debris_Site) -> [2]rl.Color` (in render_arrival_debris.odin): topsoil and stone, tinted by `palette[planet_tint(site.generation, home)]`.
- `loop_field_session.odin`: `field_arrival_debris_site :: proc(simulation: ^Simulation_State, content: Simulation_Content, config: Game_Config) -> (site: Arrival_Debris_Site, found: bool)`: `find_pod`, `pod_base_centre`, `arrival_pod_reach_metres` (no pod: the home and reach 0), `field_tree_generation(&simulation.field)^`. In `draw_field_viewport_world` while Settled: the site, `draw_arrival_debris` with `day_factor(sky.blend)`, then the dust in the debris' topsoil colour brightened 0.3 (the globe colour goes). `loop.odin`: `play_field_session_sounds(state, session, content)` builds the site while Settled and passes it.
- `data/game.sjson`, after `arrival_real_seconds`: `arrival_debris_pieces = 160`, `arrival_debris_rest_seconds = 150`, `arrival_debris_angle_degrees = 45`. The comment block gains: "At the hit arrival_debris_pieces (0 to 400) clods fly out of the crater on arcs leaving at arrival_debris_angle_degrees (30 to 60) above the horizontal, the inner ones fastest and farthest, none beyond five crater radii; they rest for up to arrival_debris_rest_seconds (0 to 900) and sink away (presentation only)." `Game_Config` gains the three ints, `arrival_problem` three `Config_Bound` rows with `MAXIMUM_ARRIVAL_DEBRIS_PIECES :: 400`, `MAXIMUM_ARRIVAL_DEBRIS_REST_SECONDS :: 900`, `MINIMUM_ARRIVAL_DEBRIS_ANGLE_DEGREES :: 30`, `MAXIMUM_ARRIVAL_DEBRIS_ANGLE_DEGREES :: 60`. `arrival_test_config` copies them.
- Sounds: `tools/make_placeholder_sounds.py` gains `arrival_bang()` (a crack of band noise 300 to 7000 Hz, attack 1 ms, decay 0.06 s, over a boom `sweep(60, 22, 2.0)` decaying 0.8 s and a rumble of band noise 30 to 200 Hz over 2.5 s decaying 0.9 s, normalised 0.95) and `arrival_patter(variant)` for 1 to 3 (a thud `sweep(140 − 20·variant, 70, 0.15)` decaying 0.04 s under band noise seeded `arrival_patter_<variant>`, 0.18 s, 200 to 1200 + 400·variant Hz, decaying 0.035 s, normalised 0.5), the docstring's list a line. Run it: only the four new files appear in `git status` (the script is deterministic). `data/sounds/sounds.sjson`: `arrival_bang` volume 1.0 and the three patters 0.5, all effects, and the comment's arrival line names them.

### Tests

- `render_arrival_debris_test.odin`, the shipped planet (`shipped_test_planets`, `default_planet`) at 500 mm, the pod placed at `field_home_site` of the baked generation (`place_pod`, as 0270's tests), the shipped config:
  - `test_every_clod_lands_within_five_radii_and_half_near_the_rim`: seeds 1 to 16: every piece's landing within `5·radius` plus 1 mm of the home along the tangent plane and at least `radius` from it, at least half within `2·radius`, the pose at `launch + T` equal to the landing within 1 mm, the inner half's mean reach above the outer half's.
  - `test_no_clod_rests_on_the_pod`: seeds 1 to 16, crater radii 4, 12 and 18 (rim 1, floor 2), the pod rested by `pod_rest_pose` at 15 and 25 degrees: at every 0.1 s of every arc and at rest, `world_to_frame_cell` of the centre in the rested frame lies outside the pod's cells (`origin` to `origin + size`) grown by one cell.
  - (implementer, 2026-10-05) The radius 4 crater has no rim (`{4, 1, 2, 0}`), since a rim of 1 m over its 2 m of bowl fails `crater_problem`. The landing's distance is measured where its radial meets the home's tangent plane, since the surface point lies along the radial, off the tangent distance by its share of the relief over the planet's radius; the arc's end is checked through `arrival_debris_flight_point`, since a pose at `launch + T` may round past the flight into the rest.
  - `test_the_clods_fly_within_their_bound`: crater radius 18, depth 8, rim 1, angles 30, 45 and 60: every `launch_seconds + flight_seconds` below `ARRIVAL_DEBRIS_FLIGHT_SECONDS`, and the pose hidden past `arrival_settled_seconds`.
  - `test_the_patter_has_no_period`: seed 1: the sounding pieces' landing seconds sorted span at least 2 s and their gaps' coefficient of variation is above 0.5.
- `test_the_arrivals_presentation_leaves_the_hash` (simulation_arrival_test.odin) calls `field_arrival_debris_site`, every piece, its pose and its patter, and the dust's puffs on the site each tick.
- `test_the_arrival_view_follows_the_timeline`: Settled at `descent + 240`, None at `descent + arrival_settled_seconds(config) · 60`.
- `test_arrival_values_are_bounded`: 401 pieces, 901 seconds, angle 29 and 61 each fail naming the key. `audio_test.odin`: `test_the_arrival_sounds_are_effects`: the shipped table lists the bang and the three patters as effects.

### Docs

- `doc/presentation.md`, The arrival: Phases: Settled lasts `arrival_settled_seconds`. The hit bullet: the shake at 0.3 m over 1.5 s; the dust curtain of 64 puffs along the rim on the ground there (`arrival_dust_puff`). New bullet: "The debris (0272, `render_arrival_debris.odin`): `arrival_debris_pieces` boxes leave the bowl at the hit, the inner ones first, on parabolas at about `arrival_debris_angle_degrees`, landing between the rim and five crater radii with the thickness falling as the cube of the distance, the inner ones farthest; they rest on the baked generation's surface, tumbled and sunk a quarter, for up to `arrival_debris_rest_seconds` and sink away over 8 s. Each is a pure function of its index, the seed and the ground, so a joiner or a load inside those seconds sees the same clods. Nothing on a planet without a crater or after a Skip." Sounds: the bang with the crash, the patter of half the clods as they land, three variants pitched per piece.
- `doc/content.md`, The arrival: one bullet for the three keys, their bounds and shipped values, "presentation only".
- `doc/code_map.md`: the presentation's file list gains `render_arrival_debris.odin`, the counts as the check asks.
- `doc/log/2026-10-05.md` at the landing:

  ```
  ## The debris of the bang (0272)

  Tags: field, arrival, debris, ejecta, dust, sound, presentation, 0272, m14

  Each clod's landing distance is drawn from the ejecta blanket's cube law between the rim and five crater radii and its arc solved to reach it, so the note's numbers hold by construction and no speed key exists. The ground is the baked generation's, not the field's: a clod over ground dug after the hit floats. The fade is a sinking, since translucent boxes need sorting. The dust ring moved from the pod to the rim. The Settled phase now lasts until the last clod has sunk (166 s shipped).
  ```

### Hand-back check lines that apply

- A list that grows without bound is capped where it draws: the piece count's bound 400 at load and the `min` in the draw and the patter. The puffs are a constant.
- A number parsed from text is range checked: the three keys in `arrival_problem`.
- Tests never touch the state directory: the tests above are pure or use the in-memory session.

### Questions answered

- A joiner after the hit sees the clods in flight or at rest exactly as the host, since `arrival_view` reads the snapshot's `Field_Arrival` and the tick, and hears no backlog of patter.
- No launch speed key: the speeds follow from the landing law, which a speed range would contradict.
- The shake's numbers stay constants of `render_arrival.odin` as before.

### For the main agent

1. The fade as a sinking into the ground rather than alpha. Accept?
2. 0223's dust ring round the pod moves to the rim as the curtain, none left at the pod. Keep a smaller ring at the pod too?
3. Half the clods sound (`ARRIVAL_PATTER_SHARE`). The couch may want fewer.

### Decisions (main agent, 2026-10-05)

1. The fade as a sinking into the ground: accepted, for the sorting reason given.
2. The dust moves entirely to the rim, none left at the pod: accepted. The Change bullet is corrected above.
3. Half the clods sound: accepted as the constant it is. The couch decides whether it drops.
4. The Settled phase lasting `arrival_settled_seconds` (166 s shipped): accepted. Its readers were checked on `main`: the camera's branch adds `arrival_shake_offset`, which is zero past its own seconds, the dust stops at `ARRIVAL_DUST_SECONDS`, the rest is the debris and the sounds.
5. The ground from the baked generation, not the field, with a clod over later dug ground floating: accepted and named in the log.
