package game

import "core:fmt"
import "core:image"
import "core:slice"
import "core:testing"

@(test)
test_atlas_layout_and_tile_origins :: proc(t: ^testing.T) {
	layout := atlas_layout_for_block_count(6)
	testing.expect_value(t, layout, Atlas_Layout{columns = 16, rows = 2})
	testing.expect_value(t, atlas_tile_index(Block_Id(5), .Bottom), 17)
	testing.expect_value(t, atlas_tile_origin(layout, 17), [2]f32{1.0 / 16, 0.5})
	testing.expect_value(t, atlas_tile_uv_size(layout), [2]f32{1.0 / 16, 0.5})
}

@(test)
test_atlas_pixels_are_deterministic_and_near_base_colour :: proc(t: ^testing.T) {
	definitions := [?]Block_Definition {
		{id = "air"},
		{id = "stone", solid = true, texture = {top = {100, 110, 120}, side = {10, 20, 30}, bottom = {250, 250, 250}}},
	}
	registry := Block_Registry {
		definitions = definitions[:],
	}
	layout := atlas_layout_for_block_count(len(definitions))
	first := generate_atlas_pixels(registry, layout, nil, context.temp_allocator)
	second := generate_atlas_pixels(registry, layout, nil, context.temp_allocator)
	testing.expect(t, slice.equal(first, second))
	top_tile := atlas_tile_index(Block_Id(1), .Top)
	width := atlas_pixel_width(layout)
	distinct_values := make(map[u8]bool, context.temp_allocator)
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			texel := first[y * width + top_tile * ATLAS_TILE_SIZE + x]
			testing.expect(t, abs(int(texel.r) - 100) <= ATLAS_NOISE_AMPLITUDE)
			testing.expect_value(t, texel.a, 255)
			distinct_values[texel.r] = true
		}
	}
	testing.expect(t, len(distinct_values) > 1, "the tile has noise")
}

atlas_tile_texels :: proc(pixels: [][4]u8, layout: Atlas_Layout, tile_index: int) -> (tile: Tile_Pixels) {
	width := atlas_pixel_width(layout)
	origin := tile_pixel_origin(layout, tile_index)
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			tile[y * ATLAS_TILE_SIZE + x] = pixels[(origin.y + y) * width + origin.x + x]
		}
	}
	return tile
}

read_test_block_tile :: proc(name: string) -> Tile_Pixels {
	tile, found := read_tile_file(texture_file_path(test_data_directory(), BLOCK_TEXTURES_DIRECTORY, name))
	assert(found, name)
	return tile
}

@(test)
test_block_texture_file_lands_in_its_tile :: proc(t: ^testing.T) {
	definitions := [?]Block_Definition{{id = "air"}, {id = "stone", solid = true, texture = {top = 128, side = 128, bottom = 128}}}
	registry := Block_Registry {
		definitions = definitions[:],
	}
	layout := atlas_layout_for_block_count(len(definitions))
	pixels := generate_atlas_pixels(registry, layout, read_block_textures(registry, test_data_directory()), context.temp_allocator)
	stone := read_test_block_tile("stone")
	for group in Face_Group {
		testing.expect_value(t, atlas_tile_texels(pixels, layout, atlas_tile_index(Block_Id(1), group)), stone)
	}
}

@(test)
test_block_without_texture_file_falls_back_to_colour :: proc(t: ^testing.T) {
	definitions := [?]Block_Definition{{id = "air"}, {id = "no_such_block", solid = true, texture = {top = 90, side = 90, bottom = 90}}}
	registry := Block_Registry {
		definitions = definitions[:],
	}
	layout := atlas_layout_for_block_count(len(definitions))
	tiles := read_block_textures(registry, test_data_directory())
	testing.expect(t, tiles[1][.Top] == nil && tiles[1][.Side] == nil && tiles[1][.Bottom] == nil)
	with_files := generate_atlas_pixels(registry, layout, tiles, context.temp_allocator)
	without_files := generate_atlas_pixels(registry, layout, nil, context.temp_allocator)
	testing.expect(t, slice.equal(with_files, without_files))
}

@(test)
test_face_group_file_overrides_the_plain_file :: proc(t: ^testing.T) {
	tiles := read_block_face_tiles(test_data_directory(), "grass")
	plain := read_test_block_tile("grass")
	top := read_test_block_tile("grass_top")
	testing.expect(t, top != plain)
	testing.expect_value(t, tiles[.Top].?, top)
	testing.expect_value(t, tiles[.Side].?, read_test_block_tile("grass_side"))
	testing.expect_value(t, tiles[.Bottom].?, plain)
}

@(test)
test_texture_of_wrong_size_is_refused :: proc(t: ^testing.T) {
	small := image.Image {
		width    = 8,
		height   = 8,
		channels = 4,
		depth    = 8,
	}
	_, problem := tile_from_image(&small)
	testing.expect(t, problem != "")
	deep := image.Image {
		width    = ATLAS_TILE_SIZE,
		height   = ATLAS_TILE_SIZE,
		channels = 4,
		depth    = 16,
	}
	_, problem = tile_from_image(&deep)
	testing.expect(t, problem != "")
	// Not a PNG at all: refused, so the block keeps its colour tile.
	_, found := read_tile_file(fmt.tprintf("%s/%s", test_data_directory(), BLOCKS_FILE_NAME))
	testing.expect(t, !found)
}
