# 0197: Trees on the planet

Status: todo (implied by 0196, 2026-10-03: wood must come from somewhere before tree farms; after 0196)

## Goal

Logs come from the planet. Today `log` is mined from the block world's tree blocks (`mined_from` in `data/items.sjson`), and the field planet has no trees, so a field world's only wood is its kit.

## Change

- A first pass of trees as field entities: a trunk and a crown placed by the planet generation on the surface above the sea by a hash of the sample (so the same seed grows the same trees on every machine), in groves rather than evenly (no perceivable repetition, `DESIGN.md`), none on the home's pad.
- Mine held on a trunk in reach fells it after a few seconds (the block world's rule for a log block, `PICK_UP_SECONDS` or the block's mining time) and yields logs; the crown goes with it. A tree is a save entity and a generation one: a felled tree is remembered in the save, the rest regenerate.
- The planet record names the density and the species' model and tint (`data/planets.sjson`), the tree's model is a placeholder as the pod's is (`tools/make_placeholder_models.py`).
- `doc/content.md` (Trees), `doc/architecture.md` (the field's entities, the generation), the log.

## Controls

- Mine on a trunk, the same control as mining the ground and picking up (0195); the hint beside a trunk reads "Fell".

## Verify

- The build and check commands of 0168.
- Tests: the same seed places the same trees; a felled tree yields logs and stays felled after a save and load; no tree stands on the pad; the hash agrees on two sessions.
- The couch: the user fells a tree near the home and planks a pad.
