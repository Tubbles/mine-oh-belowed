package game

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
	first := generate_atlas_pixels(registry, layout, context.temp_allocator)
	second := generate_atlas_pixels(registry, layout, context.temp_allocator)
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
