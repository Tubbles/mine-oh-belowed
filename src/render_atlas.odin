package game

import rl "vendor:raylib"

// Placeholder block atlas generated at startup: one 16 by 16 tile per face
// group per block, the base colour from blocks.sjson plus a little per texel
// noise. No image files.

ATLAS_TILE_SIZE :: 16
ATLAS_COLUMNS :: 16
// Largest brightness offset the noise adds to or removes from a texel.
ATLAS_NOISE_AMPLITUDE :: 12
ATLAS_NOISE_SEED :: 0x6d696e65

Atlas_Layout :: struct {
	columns: int,
	rows:    int,
}

atlas_layout_for_block_count :: proc(block_count: int) -> Atlas_Layout {
	tile_count := block_count * FACE_GROUP_COUNT
	return Atlas_Layout{columns = ATLAS_COLUMNS, rows = max(1, (tile_count + ATLAS_COLUMNS - 1) / ATLAS_COLUMNS)}
}

atlas_tile_index :: proc(block: Block_Id, group: Face_Group) -> int {
	return int(block) * FACE_GROUP_COUNT + int(group)
}

atlas_tile_origin :: proc(layout: Atlas_Layout, tile_index: int) -> [2]f32 {
	column := tile_index % layout.columns
	row := tile_index / layout.columns
	return {f32(column) / f32(layout.columns), f32(row) / f32(layout.rows)}
}

atlas_tile_uv_size :: proc(layout: Atlas_Layout) -> [2]f32 {
	return {1 / f32(layout.columns), 1 / f32(layout.rows)}
}

atlas_pixel_width :: proc(layout: Atlas_Layout) -> int {
	return layout.columns * ATLAS_TILE_SIZE
}

atlas_pixel_height :: proc(layout: Atlas_Layout) -> int {
	return layout.rows * ATLAS_TILE_SIZE
}

// splitmix64 finaliser: a fixed integer hash, so the atlas is identical on
// every run and every machine.
hash_u64 :: proc(value: u64) -> u64 {
	mixed := value + 0x9e3779b97f4a7c15
	mixed = (mixed ~ (mixed >> 30)) * 0xbf58476d1ce4e5b9
	mixed = (mixed ~ (mixed >> 27)) * 0x94d049bb133111eb
	return mixed ~ (mixed >> 31)
}

texel_noise :: proc(tile_index, x, y: int) -> int {
	key := u64(ATLAS_NOISE_SEED) ~ (u64(tile_index) << 32) ~ (u64(y) << 16) ~ u64(x)
	return int(hash_u64(key) % (2 * ATLAS_NOISE_AMPLITUDE + 1)) - ATLAS_NOISE_AMPLITUDE
}

noisy_texel :: proc(base: [3]u8, noise: int) -> [4]u8 {
	texel: [4]u8 = 255
	for channel in 0 ..< 3 {
		texel[channel] = u8(clamp(int(base[channel]) + noise, 0, 255))
	}
	return texel
}

fill_tile :: proc(pixels: [][4]u8, layout: Atlas_Layout, tile_index: int, base: [3]u8) {
	width := atlas_pixel_width(layout)
	origin_x := tile_index % layout.columns * ATLAS_TILE_SIZE
	origin_y := tile_index / layout.columns * ATLAS_TILE_SIZE
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			pixels[(origin_y + y) * width + origin_x + x] = noisy_texel(base, texel_noise(tile_index, x, y))
		}
	}
}

// Row major RGBA pixels, atlas_pixel_width by atlas_pixel_height.
generate_atlas_pixels :: proc(registry: Block_Registry, layout: Atlas_Layout, allocator := context.allocator) -> [][4]u8 {
	pixels := make([][4]u8, atlas_pixel_width(layout) * atlas_pixel_height(layout), allocator)
	for definition, block_index in registry.definitions {
		for group in Face_Group {
			tile_index := atlas_tile_index(Block_Id(block_index), group)
			fill_tile(pixels, layout, tile_index, face_group_color(definition.texture, group))
		}
	}
	return pixels
}

// Point filtering keeps the texels sharp. There are no mipmaps, so tiles do
// not bleed into their neighbours at a distance.
upload_atlas :: proc(registry: Block_Registry, layout: Atlas_Layout) -> rl.Texture2D {
	pixels := generate_atlas_pixels(registry, layout, context.temp_allocator)
	image := rl.Image {
		data    = raw_data(pixels),
		width   = i32(atlas_pixel_width(layout)),
		height  = i32(atlas_pixel_height(layout)),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(texture, .POINT)
	return texture
}
