# 0324: Arches, overhangs and caves in the generation

Status: todo (2026-11-07)

The user (2026-11-07): "Minecraft is really good at this, with gorges, cliffs, and even arcs, and other exciting features." An arch, a natural bridge, an overhang or a cave mouth needs ground above air. The field holds that, since players dig caves, but the generation is a height map (`planet_sample_at_relief`: the density is the depth below one surface height), so it can make none of them. 0323 makes the height map landforms. This item adds a three-dimensional density term.

## Goal

Rare arches and natural bridges, overhanging cliffs and cave mouths that open into the hills, generated deterministically, which a player can walk under and into.

## Controls

None.

## Change

- A three-dimensional term in the sample's density, after Minecraft's noise caves (cheese and spaghetti) and its overhangs, bounded to a shell near the surface and to where its features are wanted (rock faces, ranges, gorge walls). Integer and fixed point, as the relief is.
- What reads the surface as a height map follows it. The design lists each reader and its answer:
  - the sky light march (`field_relief_top`);
  - the ground look's natural share (0307);
  - the trees' placement;
  - the springs;
  - the dry home search and the arrival's crater;
  - `planet_sample_shortcut`'s bounds;
  - the relief map mode;
  - the level of detail.
- Old worlds keep their ground through the record.
- The cost per sample and per view is measured, against 0314's work.
- Docs: `doc/content.md` (Planets), `doc/architecture.md` (World generation).

## Verify

- The checks and the suite, with the bound, determinism and old world parity tests.
- Captures under an arch, beside an overhang and into a cave mouth, sent to the user.
