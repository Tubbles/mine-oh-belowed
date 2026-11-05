# 0297: Sun and torchlight

Status: todo (2026-11-05)

Milestone: the water tech demo (0291); the presentation stream.

## Goal

The field is lit by the sun where it stands in the sky: a directional term from the day clock's sun direction, strong at noon, gone at night, with the sky light as the ambient, so slopes facing the sun are bright and the water's sheet and waves catch it; and the player carries a torchlight, a spotlight from the eye along the view, strong enough to light a cave or a night-time dig, toggled on the D-pad.

## Controls

- Torchlight: D-pad up toggles the torchlight in the tech demo and under `--dev` (D-pad up is Pipette in the world, which has no use without an inventory game; in the tech demo the binding's world meaning is the torchlight, a mode choice, documented in `doc/input.md`). A HUD glyph shows it on.
- Time of day: D-pad down in the tech demo steps the clock through noon, evening, midnight, morning (Drop_Stack's binding, unused in the demo), so the sun can be judged; the clock otherwise runs at the world's day length.

## Change

- `data/shaders/field.fs` and `model.fs` (and the water pass if separate): `sun_direction` set per frame from `sun_direction(day_fraction)` turned into the chunk's frame (the field is drawn in world space, so the planet-space direction is used directly) and weighted by `daylight`; the lighting becomes ambient (sky light times a `sky_ambient` of 0.35 at noon) plus the directional term (max(0, dot(normal, sun)) times daylight) plus block light plus point lights; a spotlight: uniforms `spot_position`, `spot_direction`, `spot_cos_inner`, `spot_cos_outer`, `spot_range`, `spot_color`, set in `draw_field` from the camera when the torchlight is on, zero otherwise, with inverse-square falloff and a smooth cone edge. Every integer literal carries `u`.
- `render_field.odin` `use_field_shader` / `draw_field`: the new uniforms, set each frame beside `daylight`; `Field_View.torchlight` toggled by the new action `Toggle_Torchlight` (D-pad up, world layer, tech demo and dev) and `Step_Time_Of_Day` (D-pad down, tech demo) in `data/bindings.sjson`, served in the field session's frame.
- Keys in `data/game.sjson` presentation: `sky_ambient`, `sun_strength`, `torchlight_strength`, `torchlight_cone_degrees` (28 inner, 36 outer), `torchlight_range_metres` (40).
- Docs: `doc/presentation.md` (Light on the field), `doc/input.md`, the log.

## Verify

- The checks and the suite; `shader_source_test.odin` passes on the changed shaders.
- Tests: the sun direction uniform follows the clock (noon up, midnight down) in a draw list test; the torchlight toggle sets and clears the uniforms; the time step cycles the four times.
- The couch: at noon a slope facing the sun is visibly brighter than its back; at night the torchlight lights the dig; the water sheet and the waves catch the sun (the user).
