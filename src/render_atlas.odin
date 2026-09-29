package game

import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"
import "core:slice"
import rl "shared:raylib"

// The block atlas, built at startup and on a reload: one 16 by 16 tile per
// face group per block. A tile comes from data/textures/blocks/<id>.png,
// or from <id>_top.png, <id>_side.png or <id>_bottom.png for its group
// when that file exists. A block with an entry in
// data/textures/procedural.sjson takes its generated tile for all three
// groups instead (texture_generate.odin, work item 0099). A block or group
// without either falls back to its base colour from blocks.sjson plus a
// little per texel noise.

ATLAS_TILE_SIZE :: 16
ATLAS_COLUMNS :: 16
// Largest brightness offset the noise adds to or removes from a texel.
ATLAS_NOISE_AMPLITUDE :: 12
ATLAS_NOISE_SEED :: 0x6d696e65
BLOCK_TEXTURES_DIRECTORY :: "textures/blocks"
TEXTURE_FILE_EXTENSION :: ".png"

// One tile's texels, row major.
Tile_Pixels :: [ATLAS_TILE_SIZE * ATLAS_TILE_SIZE][4]u8

// A block's tiles read from files, by face group; nil takes the colour tile.
Block_Face_Tiles :: [Face_Group]Maybe(Tile_Pixels)

@(rodata)
face_group_file_suffixes := [Face_Group]string {
	.Top    = "_top",
	.Side   = "_side",
	.Bottom = "_bottom",
}

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

tile_pixel_origin :: proc(layout: Atlas_Layout, tile_index: int) -> [2]int {
	return {tile_index % layout.columns * ATLAS_TILE_SIZE, tile_index / layout.columns * ATLAS_TILE_SIZE}
}

copy_tile :: proc(pixels: [][4]u8, width: int, origin: [2]int, tile: Tile_Pixels) {
	tile := tile
	for y in 0 ..< ATLAS_TILE_SIZE {
		row := (origin.y + y) * width + origin.x
		copy(pixels[row:row + ATLAS_TILE_SIZE], tile[y * ATLAS_TILE_SIZE:(y + 1) * ATLAS_TILE_SIZE])
	}
}

fill_tile :: proc(pixels: [][4]u8, layout: Atlas_Layout, tile_index: int, base: [3]u8) {
	width := atlas_pixel_width(layout)
	origin := tile_pixel_origin(layout, tile_index)
	for y in 0 ..< ATLAS_TILE_SIZE {
		for x in 0 ..< ATLAS_TILE_SIZE {
			pixels[(origin.y + y) * width + origin.x + x] = noisy_texel(base, texel_noise(tile_index, x, y))
		}
	}
}

// Row major RGBA pixels, atlas_pixel_width by atlas_pixel_height. tiles is
// indexed by Block_Id; a block past its end takes the colour tiles.
generate_atlas_pixels :: proc(registry: Block_Registry, layout: Atlas_Layout, tiles: []Block_Face_Tiles, allocator := context.allocator) -> [][4]u8 {
	pixels := make([][4]u8, atlas_pixel_width(layout) * atlas_pixel_height(layout), allocator)
	for definition, block_index in registry.definitions {
		for group in Face_Group {
			tile_index := atlas_tile_index(Block_Id(block_index), group)
			if block_index < len(tiles) {
				if tile, found := tiles[block_index][group].?; found {
					copy_tile(pixels, atlas_pixel_width(layout), tile_pixel_origin(layout, tile_index), tile)
					continue
				}
			}
			fill_tile(pixels, layout, tile_index, face_group_color(definition.texture, group))
		}
	}
	return pixels
}

// A texture file must be 16 by 16 with 8 bit channels; the decoder
// already added the alpha channel an RGB file lacks.
tile_from_image :: proc(decoded: ^image.Image) -> (tile: Tile_Pixels, problem: string) {
	if decoded.width != ATLAS_TILE_SIZE || decoded.height != ATLAS_TILE_SIZE {
		return {}, fmt.tprintf("the image is %d by %d pixels, not %d by %d", decoded.width, decoded.height, ATLAS_TILE_SIZE, ATLAS_TILE_SIZE)
	}
	if decoded.channels != 4 || decoded.depth != 8 {
		return {}, fmt.tprintf("the image has %d channels of %d bits, not RGBA of 8 bits", decoded.channels, decoded.depth)
	}
	copy(tile[:], slice.reinterpret([][4]u8, decoded.pixels.buf[:]))
	return tile, ""
}

// found is false for a missing file, and for one that does not decode to
// a tile, which is logged. The decoding uses the temp allocator.
read_tile_file :: proc(path: string) -> (tile: Tile_Pixels, found: bool) {
	if !os.exists(path) {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v, using the colour tile", path, read_error)
		return {}, false
	}
	decoded, decode_error := png.load_from_bytes(data, {.alpha_add_if_missing}, context.temp_allocator)
	if decode_error != nil {
		log_printf("error: cannot decode %s: %v, using the colour tile", path, decode_error)
		return {}, false
	}
	problem: string
	tile, problem = tile_from_image(decoded)
	if problem != "" {
		log_printf("error: %s: %s, using the colour tile", path, problem)
		return {}, false
	}
	return tile, true
}

texture_file_path :: proc(data_directory, directory, name: string) -> string {
	return fmt.tprintf("%s/%s/%s%s", data_directory, directory, name, TEXTURE_FILE_EXTENSION)
}

// A generated tile serves every group, before any file is looked for.
// Otherwise the plain file serves every group a group file does not
// override.
read_block_face_tiles :: proc(data_directory, block_id: string, generated: Maybe(Tile_Pixels) = nil) -> (tiles: Block_Face_Tiles) {
	if tile, found := generated.?; found {
		for group in Face_Group {
			tiles[group] = tile
		}
		return tiles
	}
	plain, plain_found := read_tile_file(texture_file_path(data_directory, BLOCK_TEXTURES_DIRECTORY, block_id))
	for group in Face_Group {
		name := fmt.tprintf("%s%s", block_id, face_group_file_suffixes[group])
		if tile, found := read_tile_file(texture_file_path(data_directory, BLOCK_TEXTURES_DIRECTORY, name)); found {
			tiles[group] = tile
		} else if plain_found {
			tiles[group] = plain
		}
	}
	return tiles
}

// Indexed by Block_Id, in the temp allocator. procedural holds the
// entries of load_procedural_textures.
read_block_textures :: proc(registry: Block_Registry, data_directory: string, procedural: []Procedural_Texture) -> []Block_Face_Tiles {
	tiles := make([]Block_Face_Tiles, len(registry.definitions), context.temp_allocator)
	for definition, block_index in registry.definitions {
		generated := generate_procedural_tile(procedural, registry, Block_Id(block_index))
		tiles[block_index] = read_block_face_tiles(data_directory, definition.id, generated)
	}
	return tiles
}

// Point filtering keeps the texels sharp. There are no mipmaps, so tiles do
// not bleed into their neighbours at a distance. The procedural entries
// are read again on every upload, the texture edits from the state
// directory with them.
upload_atlas :: proc(registry: Block_Registry, layout: Atlas_Layout, data_directory: string) -> rl.Texture2D {
	edits_path := texture_edits_path()
	procedural := load_procedural_textures(data_directory, edits_path, registry)
	pixels := generate_atlas_pixels(registry, layout, read_block_textures(registry, data_directory, procedural), context.temp_allocator)
	image := rl.Image {
		data    = raw_data(pixels),
		width   = i32(atlas_pixel_width(layout)),
		height  = i32(atlas_pixel_height(layout)),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := load_rgba_texture(image)
	rl.SetTextureFilter(texture, .POINT)
	return texture
}

// The block's tiles of all three face groups replaced in the uploaded
// atlas in place (the texture editor, work item 0100): the chunk meshes
// keep their texcoords, so the world shows the tile in the next frame.
update_atlas_block_tile :: proc(texture: rl.Texture2D, layout: Atlas_Layout, block: Block_Id, tile: Tile_Pixels) {
	tile := tile
	for group in Face_Group {
		origin := tile_pixel_origin(layout, atlas_tile_index(block, group))
		rectangle := rl.Rectangle{f32(origin.x), f32(origin.y), ATLAS_TILE_SIZE, ATLAS_TILE_SIZE}
		rl.UpdateTextureRec(texture, rectangle, raw_data(tile[:]))
	}
}

// Every texture goes up as RGBA (0106). raylib uploads gray and gray alpha
// images as one or two channel textures with a texture swizzle that
// Winlator's Gladio drops, so they sample red on the phone. Another format
// is converted on a copy, since ImageFormat frees the pixels it replaces
// and the callers' images often point at Odin memory.
load_rgba_texture :: proc(image: rl.Image) -> rl.Texture2D {
	if image.format == .UNCOMPRESSED_R8G8B8A8 {
		return rl.LoadTextureFromImage(image)
	}
	converted := rl.ImageCopy(image)
	rl.ImageFormat(&converted, .UNCOMPRESSED_R8G8B8A8)
	texture := rl.LoadTextureFromImage(converted)
	rl.UnloadImage(converted)
	return texture
}
