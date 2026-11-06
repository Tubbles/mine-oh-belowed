# 0313: Light and air on the landscape

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313. The user (2026-11-06): "just generally better visuals".

## Goal

The landscape has depth and time of day: a warm sun and a cool sky light from above with a ground bounce from below in place of one grey ambient, distance haze tinted by the sky and the sun's side (aerial perspective) so ranges stand behind each other, and the sun's shadow of the terrain and the trees where the budget allows.

## Controls

None.

## Change

- The field, model and tree shaders' light terms and the fog, the colours from `data/lighting.sjson` and the day clock.
- Shadows as their own decision in the design: a cascade on the couch behind a setting, none on the phone.
- Docs: `doc/presentation.md`; the log.

## Verify

- The checks, the suite, `shader_source_test.odin`.
- Captures at dawn, noon and dusk from the ground and from 120 m up; the frame cost on the couch and the Deck's setting; sent to the user.
