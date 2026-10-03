# 0060 Block textures and item icons

Status: implemented
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

## Notes

Implementation pointers (main agent, 2026-09-28), decisions taken so the item is unambiguous:

- Block textures: `data/textures/blocks/<block id>.png`, 16 by 16 RGBA, one file for all three face groups, with optional `<id>_top.png`, `<id>_side.png` and `<id>_bottom.png` overriding a group (grass: a green top and a dirt side with a grass fringe). `generate_atlas_pixels` (`src/render_atlas.odin`) copies a decoded file into the tile and falls back to today's noisy colour tile for a block or group without one, so the atlas layout, `atlas_tile_index` and the mesher stay as they are. Decode with `core:image/png` (tests decode without raylib; raylib only uploads), reject a file that is not 16 by 16 with a logged problem and the fallback. The point filtered, mipmap free upload stays.
- Item icons: `data/textures/items/<item id>.png`, 16 by 16 RGBA with transparency, packed into an item atlas of the same tile size (`Item_Atlas_Layout` from the item count, a tile per item, in a new `src/render_icons.odin`), uploaded next to the block atlas and rebuilt with it. `Item_Icon` (`src/item.odin`) gains the kind `Item_Tile`; `item_icon` returns it for an item with a file, keeps `Block_Tile` for a block placing item without one, and `Lettered` for the rest. `Icon_Atlas` (`src/ui_draw.odin`) carries both atlases and a new `Item_Tile` draw command draws from the item one; `draw_item_icon` (`src/ui_widgets.odin`) handles the kind, so slots, the hotbar, the recipe browser and every other icon follow. Belts and loose items (`src/render_belts.odin`, `src/render_loose_items.odin`): an item with an icon is a camera facing billboard of its tile (`rl.DrawBillboardRec` with the atlas source rectangle), 0.4 blocks, in place of the coloured cube; an item without one keeps the cube. Each item's average opaque colour is kept with the atlas for the map and any other place that needs one colour.
- Generator: `tools/make_placeholder_textures.py`, standard library only (zlib and struct write the PNGs, the pattern of `tools/make_placeholder_models.py`), deterministic, writing every block and item file, run once and its output committed. It reads the ids and the face colours from `data/blocks.sjson` and the ids and categories from `data/items.sjson` with small regular expressions (the files are regular; say so in the script's docstring), so a new block or item gets a texture on the next run. Blocks by material family from the id (stone, dirt, sand, grass, ore, log, leaves, water, snow, rock, tar, concrete, brick, and a default): noise per family, ore speckles in the ore's colour over stone, vertical bark grain and a ring top for logs, mottled leaves, a grass top with a dirt side. Items by category and a colour table for the common materials (iron, copper, tin, lead, zinc, nickel, gold, aluminium, steel, coal, stone, glass, wood) with a hash colour otherwise: plates as rounded rectangles, ores as lumps, gears as toothed rings, tools as simple silhouettes, machines as a box with a darker base, packs as a flask, blocks as their block's texture. The whole set is a placeholder; hand made art comes later and only replaces files.
- Hot reload (0054): a `Textures` category in `src/data_watch.odin` for `textures/blocks/*.png` and `textures/items/*.png`, applied in `src/hot_reload.odin` like models (rebuild both atlases; the chunk meshes keep their tile coordinates since the layout depends on the block count alone). A content reload rebuilds them too, as it does today.
- Tests (`src/render_atlas_test.odin`, new `src/render_icons_test.odin`): a generated block file decodes to 16 by 16 and lands in its tile, a missing file falls back to the colour tile, a face group override wins over the plain file, a wrong size is refused with the fallback, the item atlas packs every item to a distinct tile and its origin and size match the layout, `item_icon` picks `Item_Tile`, `Block_Tile` and `Lettered` as described, the average colour of a known file, and the UI audit passes with icons (it draws slots already). Tests read the committed files under `data/textures/`.
- Docs: `doc/ui.md` (the placeholder icon line becomes the texture and icon files and the fallbacks), `doc/architecture.md` (the meshing line's atlas and the hot reload categories), `doc/content.md` (a Textures section: the file naming, the face group overrides, the generator), `doc/log/2026-09-28.md`, this item's Status and Notes.

Files a subagent may touch: `src/render_atlas.odin`, `src/render_atlas_test.odin`, new `src/render_icons.odin` and `src/render_icons_test.odin`, `src/ui_draw.odin`, `src/ui_widgets.odin`, `src/item.odin`, `src/render_belts.odin`, `src/render_loose_items.odin`, `src/render_chunks.odin`, `src/data_watch.odin`, `src/data_watch_test.odin`, `src/hot_reload.odin`, `src/loop.odin` (atlas ownership and the `ui_end` call), `src/ui_audit_test.odin`, new `tools/make_placeholder_textures.py`, new `data/textures/blocks/*.png` and `data/textures/items/*.png`, the docs above, this file.

Implemented: `src/render_atlas.odin` (block texture files with face group overrides and the colour fallback), new `src/render_icons.odin` (item atlas, average colours, billboards), `src/item.odin` (`Item_Tile` icon kind, `Item_Registry.icon_loaded`), `src/ui_core.odin` (the `Item_Tile` draw command kind, one enum member), `src/ui_draw.odin`, `src/ui_widgets.odin`, `src/render_chunks.odin`, `src/render_belts.odin`, `src/render_loose_items.odin`, `src/loop.odin`, `src/data_watch.odin`, `src/hot_reload.odin`, `data/strings/en.sjson` (`reload_textures_done`), tests in `src/render_atlas_test.odin`, new `src/render_icons_test.odin`, `src/data_watch_test.odin` and `src/ui_audit_test.odin` (the audit draws the shipped icons). `tools/make_placeholder_textures.py` wrote 100 block files (46 blocks, air has none, plus face group overrides) and 130 item files. 766 tests pass, 8 of them new. Decisions are in `doc/log/2026-09-28.md`.
