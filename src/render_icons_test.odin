package game

import "core:testing"

@(test)
test_item_atlas_packs_every_item_to_its_own_tile :: proc(t: ^testing.T) {
	items := make_test_items()
	icons := generate_item_icon_pixels(items, test_data_directory(), context.temp_allocator)
	layout := item_atlas_layout_for_item_count(len(items.items))
	testing.expect_value(t, icons.layout, layout)
	testing.expect_value(t, len(icons.pixels), atlas_pixel_width(layout) * atlas_pixel_height(layout))
	testing.expect(t, layout.columns * layout.rows >= len(items.items))
	origins := make(map[[2]int]bool, context.temp_allocator)
	for item, index in items.items {
		testing.expectf(t, icons.loaded[index], "%s has an icon file", item.id)
		origin := tile_pixel_origin(layout, index)
		testing.expectf(t, origin not_in origins, "%s has a tile of its own", item.id)
		origins[origin] = true
		uv_origin := atlas_tile_origin(layout, index)
		testing.expect_value(t, [2]f32{f32(origin.x), f32(origin.y)}, uv_origin * [2]f32{f32(atlas_pixel_width(layout)), f32(atlas_pixel_height(layout))})
		file, found := read_tile_file(texture_file_path(test_data_directory(), ITEM_TEXTURES_DIRECTORY, item.id))
		testing.expect(t, found)
		testing.expect_value(t, atlas_tile_texels(icons.pixels, layout, index), file)
	}
	testing.expect_value(t, atlas_tile_uv_size(layout) * [2]f32{f32(atlas_pixel_width(layout)), f32(atlas_pixel_height(layout))}, [2]f32{ATLAS_TILE_SIZE, ATLAS_TILE_SIZE})
}

@(test)
test_item_without_icon_file_has_an_empty_tile :: proc(t: ^testing.T) {
	definitions := [?]Item{{id = "no_such_item"}}
	items := Item_Registry {
		items = definitions[:],
	}
	icons := generate_item_icon_pixels(items, test_data_directory(), context.temp_allocator)
	testing.expect(t, !icons.loaded[0])
	testing.expect_value(t, icons.average_colors[0], Ui_Color{})
	empty: Tile_Pixels
	testing.expect_value(t, atlas_tile_texels(icons.pixels, icons.layout, 0), empty)
}

@(test)
test_item_icon_prefers_the_icon_file :: proc(t: ^testing.T) {
	items := make_test_items()
	stone := test_item(items, "stone")
	plate := test_item(items, "iron_plate")
	testing.expect_value(t, item_icon(items, stone).kind, Item_Icon_Kind.Block_Tile)
	testing.expect_value(t, item_icon(items, plate).kind, Item_Icon_Kind.Lettered)
	loaded := make([]bool, len(items.items), context.temp_allocator)
	loaded[stone], loaded[plate] = true, true
	items.icon_loaded = loaded
	testing.expect_value(t, item_icon(items, stone), Item_Icon{kind = .Item_Tile, tile = int(stone)})
	testing.expect_value(t, item_icon(items, plate), Item_Icon{kind = .Item_Tile, tile = int(plate)})
	loaded[stone] = false
	testing.expect_value(t, item_icon(items, stone).kind, Item_Icon_Kind.Block_Tile)
}

@(test)
test_item_average_color_counts_opaque_texels :: proc(t: ^testing.T) {
	half: Tile_Pixels
	for &texel, index in half {
		texel = index % 2 == 0 ? {200, 40, 20, 255} : {0, 0, 255, 0}
	}
	testing.expect_value(t, average_opaque_color(half), Ui_Color{200, 40, 20, 255})
	// The stone item shows the stone block's texture: grey noise, every
	// texel opaque, all three channels moved alike.
	items := make_test_items()
	icons := generate_item_icon_pixels(items, test_data_directory(), context.temp_allocator)
	stone := icons.average_colors[test_item(items, "stone")]
	testing.expect(t, stone.r == stone.g && stone.g == stone.b && stone.a == 255)
	testing.expect(t, abs(int(stone.r) - 128) <= 12)
}
