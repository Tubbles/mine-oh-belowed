# 0088 Break texture repetition, fix the torch and tool icons

Status: implemented
Milestone: M11

## Goal

Couch report (2026-09-28): water and ore outcrops look stripey because the same tile repeats; the torch icon is still a dirt tile; pickaxe handles are turned a quarter in the icons. The design principle in `DESIGN.md` (no perceivable repetition) applies.

## Deliverables

- Per block variation in the chunk and water fragment shaders (`data/shaders/chunk.fs`, `water.fs`): a hash of the block's integer world position (from `fragment_world_position` floored) picks one of eight tile orientations (four quarter turns, mirrored or not) for the tile's texcoords and a brightness jitter of plus or minus 4 percent, so a field of one block never shows the same tile twice in a row. Blocks whose texture has a direction opt out with a `keep_orientation` flag in `data/blocks.sjson` (logs, grass side, the cover plants, stairs and slabs in data as they are drawn per cell); the mesher passes the flag per vertex (a spare bit: the vertex colour green channel is unused since 0072, use it as 0 or 255).
- Texture redesign in `tools/make_placeholder_textures.py`: water and the ore family get isotropic noise with no direction (no diagonal stripes, no rows), leaves and stone likewise; the torch gets a stick with a flame head as its block texture and item icon; tools are drawn with the handle vertical and the head at the top right (the pickaxe, the hammer, the magnetometer as it is). Regenerate only the changed families and commit the changed files; report which files changed.
- Tests: the orientation choice per hash is a pure procedure mirrored in Odin (`tile_orientation(hash) -> (turns, mirrored)`) with a test that the eight cases occur and that flagged blocks keep orientation 0; the mesher's flag bit per vertex; the atlas test still passes.
- Docs: `doc/architecture.md` (the shader line), `doc/content.md` (the flag and the generator), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: a lake and an outcrop show no stripes; the torch has an icon; pickaxe handles stand upright.

## Notes

Files a subagent may touch: `data/shaders/chunk.fs`, `data/shaders/water.fs`, `src/world_mesh.odin`, `src/world_mesh_light.odin`, `src/world_mesh_test.odin`, `src/world_block.odin`, `src/world_block_test.odin`, new `src/texture_variation.odin` and `src/texture_variation_test.odin`, `tools/make_placeholder_textures.py`, changed files under `data/textures/`, `data/blocks.sjson`, the docs above, this file.

Implemented: `data/shaders/chunk.fs` (hash, orientation, jitter, the green channel flag) and `water.fs` (jitter only, the flow keeps the tile's axes), `src/texture_variation.odin` (the mirror: `texture_variation_hash`, `tile_orientation`, `face_tile_orientation`, `face_keeps_orientation`, `orient_tile_texcoord`, `texture_variation_brightness`) with `src/texture_variation_test.odin`, `src/world_block.odin` (`keep_orientation`, `block_keeps_orientation`), `src/world_mesh_light.odin` (`KEEP_ORIENTATION_GREEN`, `orientation_flag_green`, `vertex_color`), `src/world_mesh.odin` (the flag per vertex in `append_quad` and `append_shaped_quad`), tests in `src/world_mesh_test.odin` and `src/world_block_test.odin`, `data/blocks.sjson` (the flag on logs, grass, dry grass, brick, the rock strata family, the torch, the ground cover, the slabs and stairs), `tools/make_placeholder_textures.py`, `doc/architecture.md`, `doc/content.md`, `doc/log/2026-09-28.md`. The flag holds the side faces only; tops and bottoms always vary. Changed textures (64): under `data/textures/blocks/` stone, deep_stone, stone_slab, stone_stairs, the seven ores and gold_quartz (with its top and bottom), every leaves block and every water level (with their top and bottom files), torch; under `data/textures/items/` stone, deep_stone, stone_slab, stone_stairs, leaves, torch, the three pickaxes and the geologist's hammer. `data/ui/icons/category_tool.png` (drawn with `draw_pickaxe`) changed too and was copied in, so the checked in files match the generator. Meshing per chunk (`test_report_generation_and_meshing_time`, run alone): 34.5 to 38.0 ms before, 34.2 to 34.5 ms after. 981 tests pass.
