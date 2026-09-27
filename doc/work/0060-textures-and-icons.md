# 0060 Block textures and item icons

Status: todo
Milestone: M11

## Goal

Blocks are flat colours from a generated atlas and items have no icons. A texture set at Minecraft flatness, generated first and hand made later, and an icon per item.

## Deliverables

- `data/textures/blocks/<id>.png` and `data/textures/items/<id>.png`, 16 pixels, loaded into atlases at start and on hot reload (0054); a block or item without a file falls back to today's colour.
- A generator script (`tools/make_placeholder_textures.py`) produces the first set: noise per material, ore speckles on the outcrop blocks, wood grain, leaf mottling, so the whole world is textured on day one.
- Item icons drawn in slots, the hotbar, the recipe browser and on belts.
- Tests: atlas packing, fallback, the audit still passes with icons.

## Verify

- Builds and tests pass.
- User: Screenshots of the pad area and the inventory.
