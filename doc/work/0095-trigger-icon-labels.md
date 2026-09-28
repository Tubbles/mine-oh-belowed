# 0095 Trigger icons read LT and RT

Status: todo
Milestone: M11

## Goal

Couch report (2026-09-28): the trigger icons say L and R, which reads as the bumpers (L1 and R1). They should say LT and RT.

## Deliverables

- `tools/make_placeholder_textures.py` draws `trigger_left` and `trigger_right` with the labels LT and RT and `bumper_left` and `bumper_right` with L1 and R1 (two glyphs each, a 3 by 5 pixel font already in the script), regenerated and committed; report which files changed.
- Docs: `doc/ui.md` (the icon set line), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: the glyph bar shows LT and RT on the triggers.

## Notes

Files a subagent may touch: `tools/make_placeholder_textures.py`, the four icon files under `data/ui/icons/`, the docs above, this file.
