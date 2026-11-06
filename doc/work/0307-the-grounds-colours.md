# 0307: The ground's colours: grass, rock, sand and snow

Status: todo (2026-11-06)

Milestone: the world generation series 0306 to 0313, built on 0306's relief. The user (2026-11-06): "better visuals because right now it is very bland and depressing to look at", "varied textures". The research is `work/world_generation_research.md`.

## Goal

The ground stops being one orange brown. Gentle open ground is grass coloured by a climate (lush green, dry yellow, dark cold green), steep faces show rock, a band of sand lines the sea and the lakes, cold heights carry snow, and a broad colour variation keeps the distance from looking tiled. The hard edged 256 m tint cubes go.

## Controls

None.

## Change

- A climate field of the planet (temperature and moisture), integer noise in the generation, one pure function read by the mesher now and by the biomes (0308) and the trees (0310) later. Height cools it (a lapse), so the snow line follows the relief of 0306.
- Look layers in the field shader over the strata: grass, sand, snow and the steep face's rock, chosen from the slope against the local up (the radial), the height above the sea and the climate, blended rather than cut. They are looks, not materials: a dug surface still yields topsoil (real surface materials are 0309).
- The climate's ground colours in data: a few anchors over temperature and moisture (Minecraft's grass colour map), the snow line and the sand band beside them, in the planet record.
- Generated tiles for grass, sand and snow in `data/textures/field_materials.sjson`'s manner, isotropic, each with its grain (DESIGN.md, Art direction: sand smooth, rock faceted).
- The fragment's texture reads do not grow: the design picks a scheme that pays for the new layers (only a vertex's dominant materials sampled, or a texture array) and names the count before and after. The Deck's budget holds (DESIGN.md, Targets).
- A dug pit's floor: the design names the rule that keeps fresh cuts from turning to grass (the generated surface, a mark per sample) or why a green pit floor is acceptable until 0309.
- Docs: `doc/presentation.md` (The field), `doc/content.md` (Planets, the field's textures); the log.

## Verify

- The checks, the suite, `shader_source_test.odin`.
- The captures of 0306 (the spring start, the home, a far point, from the ground and from 40 m and 120 m up) before and after this item, and one of a dug pit; sent to the user.
