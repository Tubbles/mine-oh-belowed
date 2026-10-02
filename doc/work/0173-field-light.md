# 0173: The field light

Status: todo (after 0172)

## Goal

Light on the field: a byte of level per sample carried by a flood fill with a falloff curve from data, gentle near the source and steep at the edge, so a torch lights a room; sky light by a radial march cached as the second channel and carried into cave mouths by the fill; the mesher reads both as vertex light (0167, Light; decision 14).

## Change

- A `world_field_light` file on the pattern of `world_light.odin`: two channels per sample (block light, sky light) as bytes; addition and removal queues; the falloff per step read from a curve in data (`data/lighting.sjson` or the planet record, say which) instead of one per block; a light emitter is a sample with a source level (the torch of the slice from the material table, the lamp from its machine record).
- Sky light: at generation and under an edit's shadow, a march from each sample outward along its radial to the planet's maximum terrain altitude; a sample that reaches the sky unobstructed has full sky light, and the flood fill carries it inward with the curve, so a cave mouth is lit and its depths are not.
- Vertex light in the mesher: the mean of the samples around a vertex, as `world_mesh_light.odin` does for blocks; the shader of 0169 multiplies it in.
- Values in data: the torch's and the lamp's source levels and the curve, tuned so a torch reads as an 8 to 10 m room and a lamp as a 16 to 20 m hall.
- `doc/architecture.md` (light) and `doc/presentation.md` (vertex light) updated.

## Verify

- The build and check commands of 0168.
- Tests: a torch in a closed room lights every sample of an 8 m room above the dark threshold and a 20 m hall does not; removing the torch returns every sample to dark; a sample under open sky has full sky light, one under a 2 m overhang has none directly and some from the fill at the mouth; digging a shaft from the surface lights the samples below it along the radial and nothing beside them; the same edits on two instances give the same bytes.
- A headless render of a dug cave with one torch read by the main agent: a lit room, not a spot.
