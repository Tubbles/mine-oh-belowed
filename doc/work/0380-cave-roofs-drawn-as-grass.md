# 0380: Cave roofs drawn as grass

Status: implementing (2026-11-12)

Found by the main agent in 0327's landing captures (2026-11-12, 8 km, default seed, the cave mouth by the spring at latitude 79.007, longitude 151.054): seen from inside, the cave's roof is drawn in the grass's green over its whole underside, where the floor is stone grey. A row of single bright pixels also runs across the floor in the same capture (`tmp/shot_terrain_caves/state/mine-oh-belowed/screenshots/cave_mouth_in.png`).

## Goal

A cave's roof and walls read as rock or soil from inside, never as grass. The stray pixels are 0381's (Decisions).

## Controls

None.

## Change

- Find which of the two it is: the roof's samples hold topsoil whose look takes the grass colour whatever way the face points (the ground look of 0307 keys the grass on the material and the slope), or the caves carve under a topsoil layer the generation should not leave hanging.
- Faces that point down, and faces under a roof, take the soil's or the rock's colour. The surface's grass does not change.
- The pixel row: find whether it is a seam between two meshes or the cover's instances, and close it if it is this item's.
- Docs: `doc/presentation.md` (The field session, the ground look).

## Verify

- The checks and the suite, with a test of the look of a face pointing down under a roof.
- The same capture before and after, sent to the user.

## Specification (design, 2026-11-12)

### Cause

Neither of the two the Change names. The roof's ground is topsoil within 2 m of the height map's top (2 m in from the capture's mouth) and stone deeper, as 0324 meant, and either way its faces take the rock: `field.fs` gives a face whose steepness (1 less the cosine to the up, lines 388 to 394) passes 0.357 all its topsoil as rock, and a face pointing down has a steepness near 2. The green is the light: `outdoor_light` (`field.fs` 170 to 174) lights a face pointing down by the bounce alone, the bounce is the globe's colour (`ground_bounce_color` of `renderer.globe_color`, `loop_field_session.odin` 85, `render_point_lights.odin` 155), which with a climate is the temperate moderate grass anchor (`field_globe_color`, `render_field.odin` 164), and the roof's sky light, the fill's from the mouth, lets it in. Only air open to the sky holds the full 255: the fill under a roof never reaches it. A probe meshed the lit 3 by 3 by 3 chunks at the design planet's spring mouth and at the capture's two chunks: of 632, 597 and 1564 vertices pointing down (normal under -0.5 against the up), none carries a grass share and none holds 255; 28, 24 and 35 lie at 250 to 254 (the mouth's lip), the rest at 249 or under.

The pixel row is not this item's: its dots lie where the cave floor crosses x = -1344 m (every dot's ray meets that plane 0.43 to 0.58 m under the feet), the border of two level 0 nodes, where no skirt hangs. Each node draws with its own translation (`render_field.odin` 456, `rl.MatrixTranslate(origin)`, `field.vs` `mvp * vertexPosition`), so a shared border vertex lands a fraction of a millimetre apart in the two nodes at 8 km from the origin, and single pixels between the edges show the globe behind (the dots are its lit green). It is on every node border; the dark cave floor makes it visible.

### Change

The bounce under a roof turns grey at its own luminance, chosen by the vertex's sky light. The generation, the light bytes, the records and the saves do not change: no remap, no log line. A vertex at the full sky light is drawn exactly as before.

- `data/shaders/model.fs`, `tree.fs`, `cover.fs`, `field.fs`: `outdoor_light` takes the bounce from its caller, the same text in all four (`test_the_lit_shaders_share_the_open_sky` compares it):

  ```glsl
  vec3 outdoor_light(vec3 normal, vec3 up, float sunlit, vec3 bounce)
  {
      float upward = 0.5 + 0.5 * dot(normal, up);
      return mix(bounce, sky_color, upward) + sun_color * (sunlit * max(dot(normal, sun_direction), 0.0));
  }
  ```

  The comment above it in each says the bounce is the caller's. `apply_haze`'s globe line in all four becomes `vec3 globe = min(globe_color * outdoor_light(up, up, 1.0, bounce_color), vec3(1.0));`. The light calls of `model.fs` (262), `tree.fs` (280) and `cover.fs` (238) pass `bounce_color` as the last argument: the models, the trees and the ground cover keep the planet's bounce.
- `data/shaders/field.fs`, after the steepness constants:

  ```glsl
  // Under a roof (0380): the vertex's sky light in bytes where the bounce
  // is wholly grey (a metre into the shade at the shipped falloff) and from
  // where it is wholly the planet's (only air open to the sky holds 255,
  // so the open ground is lit exactly as before), and the weights of a
  // colour's luminance (Rec. 709).
  const float roof_sky_light_shut = 249.0;
  const float roof_sky_light_open = 254.5;
  const vec3 luminance_weights = vec3(0.2126, 0.7152, 0.0722);
  ```

  In `main`, after `sunlit`, with a comment that the light from below a roof is the cave's own floor, not the planet's grass:

  ```glsl
      float roofed = 1.0 - smoothstep(roof_sky_light_shut, roof_sky_light_open, fragment_color.a * 255.0);
      vec3 roof_bounce = mix(bounce_color, vec3(dot(bounce_color, luminance_weights)), roofed);
      vec3 outdoor = fragment_color.a * outdoor_light(normal, normalize(fragment_world_position), sunlit, roof_bounce);
  ```

  At a sky light of 254.5 or over `roofed` is exactly 0 and `mix` returns `bounce_color` itself. The header comment gains one sentence on it. The water pass shares `main`, so water under a roof takes the grey bounce too.

### Tests

- `shader_source_test.odin`, `test_the_field_shader_greys_the_bounce_under_a_roof`: `field.fs` holds the three `main` lines above verbatim; its `outdoor_light` text (`shader_function_text`) holds the signature and `mix(bounce, sky_color, upward)` and not `bounce_color`; `roof_sky_light_shut` (`shader_float_constant`) equals `make_field_light_tuning(test_lighting_file(), 1000).spread[FIELD_LIGHT_FULL]` (249, the sky a metre into the shade); `roof_sky_light_open` lies over `FIELD_LIGHT_FULL - 1` and at or under `FIELD_LIGHT_FULL - 0.5`; `1 - math.smoothstep(shut, open, f32(FIELD_LIGHT_FULL))` is exactly 0 and at `shut` exactly 1.
- `generation_planet_caves_test.odin`, `test_the_fill_lights_a_cave_from_its_mouth` (already slow, it builds and lights the 27 chunks) goes on after its sky check: the roofed sample's node meshed as the finest level does (`gather_field_grid` in the temp allocator, `mesh_field_grid` with `planet.palette`, 1000, no skirt faces, `make_field_ground_look(generation, planet)`, `measure_cuts` true); with each vertex's up the chunk's origin in metres (`field_chunk_origin`) plus its position, normalised: the node holds vertices at `FIELD_LIGHT_FULL`; it holds vertices pointing down (normal under -0.5 against the up), each with a grass share of 0 (`cover_ground_shares` of its seven weights, the tangent's four and the ores' bytes by `unpack_test_bytes`, its snow and sand from the looks' second bytes, steepness 1 less the facing) and a sky light under `FIELD_LIGHT_FULL`; at least one of them holds a sky light from 1 to `roof_sky_light_shut` (read from `field.fs`). The probe's counts there: 2815 vertices, 1531 at full sky, 632 pointing down, 508 of them at 1 to 249. The test's comment names 0380.

### Docs

- `doc/presentation.md`, The field session, Light on the field: the open sky's light bullet says `outdoor_light` takes the bounce from its caller; the terrain bullet, after the sky light's gate, gains the roof's bounce: grey at its luminance under the full sky light, wholly at `roof_sky_light_shut`, none from `roof_sky_light_open`, so a cave's roof and walls show their rock (a face pointing down takes the rock's tile by the steepness) and the open ground is drawn as before; the models, the trees and the cover keep the planet's bounce.

### Hand-back check

No line applies: nothing frees memory, writes a file, loads at start, parses a number outside a test, changes a save or a budget, grows a list or touches the UI.

### Alternatives rejected

- The topsoil kept out of a cave's roof: the roof already draws as rock, and the generated bytes of today's caves would change.
- The bounce grey on every face, or on faces pointing down by the normal: a slope turned from the sun takes part of the bounce, so the open ground would change.
- A correction term in `field.fs`'s `main` alone: one file, but `outdoor_light`'s upward share restated in a second place.
- The strata tint as the roof's bounce colour: the tint taken twice, in the albedo and the light; grey leaves the rock its own colour.
- A wider band (the falloff's first band, 192 to 254): the roof's first 5 m would stay half green, which is the finding.
- A per vertex roof share from the mesher: no free vertex attribute, and the sky byte already says it.

### Questions to the main agent

- The pixel row as a new item in the field renderer's cluster (recommended): drawing the nodes so a shared vertex's eye relative position is the same bits in both, minding that at 333 mm a position unit is not a binary fraction of a metre.
- Grey at the bounce's luminance (recommended) or the rock's tint.
- `outdoor_light` with a bounce argument in the four shaders (recommended) or the correction term in `field.fs` only.

### Decisions (main agent, 2026-11-12)

1. The roof's bounce is grey at the bounce's own luminance.
2. The bounce is an argument of `outdoor_light` in the four shaders.
3. The pixel row is not this item's: it is 0381 (cracks between the finest nodes), which waits for the user. The goal's "no stray pixels" is struck here.
4. The main agent's capture diffs a frame of open surface against `main` beside the cave's before and after: pixels may differ only inside the mouth.
