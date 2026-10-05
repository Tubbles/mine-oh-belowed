# 0284: Every fire lights what is round it

Status: todo (2026-10-05, from the 0274 review)

## Goal

The fire rule of `DESIGN.md` holds for the torches as it does for the furnace after 0274: a field torch is a point light of the flame's colour, flickering with its own flame (the same hash and clock), and the block world's torch light flickers with its flame instead of the periodic two sine `light_flicker` of `render_chunks.odin`. The 0274 review found both gaps, which predate it.

## Controls

None.

## Change

- The field torches join the point light gathering (`set_field_scene_point_lights` takes only arm and machine lamps today), nearest first within the eight slots, the flame's flicker scaling the colour as the furnace lamp's does.
- The block world's `light_flicker` goes for the flame's hashed noise, per torch.
- Docs: `doc/presentation.md` (The field, Flames), `DESIGN.md` (Fire, if the wording needs the torches named).

## Verify

- Tests: a field torch within reach adds a light with the flame's colour; its flicker equals the flame's at the same seconds; the block torch's light is aperiodic.
- A headless screenshot of a torch lit cave on the field at night.
- The couch.
