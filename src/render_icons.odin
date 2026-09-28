package game

import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// The item atlas (work item 0060): one 16 by 16 tile per item, the tile
// index the Item_Id, read from data/textures/items/<id>.png. An item
// without a file has an empty, transparent tile and keeps the icon of
// item_icon's fallbacks: its block's atlas tile or two letters. Built
// with the block atlas, at start, on a content reload and when a texture
// file changes.

ITEM_TEXTURES_DIRECTORY :: "textures/items"
// Texels at least this opaque count towards an item's average colour.
ITEM_OPAQUE_ALPHA :: 128
// The side of an item's icon on a belt or on the ground, in blocks.
ITEM_BILLBOARD_SIZE :: 0.4

item_atlas_layout_for_item_count :: proc(item_count: int) -> Atlas_Layout {
	return Atlas_Layout{columns = ATLAS_COLUMNS, rows = max(1, (item_count + ATLAS_COLUMNS - 1) / ATLAS_COLUMNS)}
}

// The CPU side, which tests build without a window.
Item_Icon_Pixels :: struct {
	layout:         Atlas_Layout,
	// Row major RGBA, atlas_pixel_width by atlas_pixel_height.
	pixels:         [][4]u8,
	// Indexed by Item_Id: the item's file filled its tile.
	loaded:         []bool,
	// Indexed by Item_Id: the average of the tile's opaque texels, for a
	// place that needs one colour per item; zero without a file.
	average_colors: []Ui_Color,
}

Item_Atlas :: struct {
	texture:        rl.Texture2D,
	layout:         Atlas_Layout,
	loaded:         []bool,
	average_colors: []Ui_Color,
}

average_opaque_color :: proc(tile: Tile_Pixels) -> Ui_Color {
	sum: [3]int
	count := 0
	for texel in tile {
		if texel.a >= ITEM_OPAQUE_ALPHA {
			sum += {int(texel.r), int(texel.g), int(texel.b)}
			count += 1
		}
	}
	if count == 0 {
		return {}
	}
	return {u8(sum.r / count), u8(sum.g / count), u8(sum.b / count), 255}
}

generate_item_icon_pixels :: proc(items: Item_Registry, data_directory: string, allocator := context.allocator) -> Item_Icon_Pixels {
	layout := item_atlas_layout_for_item_count(len(items.items))
	icons := Item_Icon_Pixels {
		layout         = layout,
		pixels         = make([][4]u8, atlas_pixel_width(layout) * atlas_pixel_height(layout), allocator),
		loaded         = make([]bool, len(items.items), allocator),
		average_colors = make([]Ui_Color, len(items.items), allocator),
	}
	for item, index in items.items {
		tile, found := read_tile_file(texture_file_path(data_directory, ITEM_TEXTURES_DIRECTORY, item.id))
		if !found {
			continue
		}
		copy_tile(icons.pixels, atlas_pixel_width(layout), tile_pixel_origin(layout, index), tile)
		icons.loaded[index] = true
		icons.average_colors[index] = average_opaque_color(tile)
	}
	return icons
}

// Point filtered like the block atlas. The item registry learns which
// items have a tile (Item_Registry.icon_loaded); it points into the atlas.
upload_item_atlas :: proc(items: ^Item_Registry, data_directory: string) -> Item_Atlas {
	icons := generate_item_icon_pixels(items^, data_directory)
	defer delete(icons.pixels)
	image := rl.Image {
		data    = raw_data(icons.pixels),
		width   = i32(atlas_pixel_width(icons.layout)),
		height  = i32(atlas_pixel_height(icons.layout)),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureFilter(texture, .POINT)
	items.icon_loaded = icons.loaded
	return Item_Atlas{texture = texture, layout = icons.layout, loaded = icons.loaded, average_colors = icons.average_colors}
}

destroy_item_atlas :: proc(atlas: ^Item_Atlas) {
	if atlas.texture.id != 0 {
		rl.UnloadTexture(atlas.texture)
	}
	delete(atlas.loaded)
	delete(atlas.average_colors)
	atlas^ = {}
}

// A content reload or a texture change: the registry may be new, so it
// learns its icons again.
replace_item_atlas :: proc(atlas: ^Item_Atlas, items: ^Item_Registry, data_directory: string) {
	destroy_item_atlas(atlas)
	atlas^ = upload_item_atlas(items, data_directory)
}

// The atlas rectangle of an item's tile, in texels.
item_atlas_source :: proc(atlas: Item_Atlas, item: Item_Id) -> rl.Rectangle {
	origin := tile_pixel_origin(atlas.layout, int(item))
	return {f32(origin.x), f32(origin.y), ATLAS_TILE_SIZE, ATLAS_TILE_SIZE}
}

item_has_icon :: proc(atlas: Item_Atlas, item: Item_Id) -> bool {
	return int(item) < len(atlas.loaded) && atlas.loaded[item]
}

// What the world draws item icons with: camera facing quads of their tiles.
Item_Billboards :: struct {
	camera: rl.Camera3D,
	atlas:  Item_Atlas,
}

// Transparent texels would write depth and hide whatever is drawn behind
// them afterwards, so icons are drawn without depth writes, between these
// two. The batch is flushed first, since the depth mask applies at once.
begin_item_billboards :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
}

end_item_billboards :: proc() {
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
}

// The icon standing on bottom, facing the camera. False for an item
// without an icon, which the caller draws as a cube.
draw_item_billboard :: proc(billboards: Item_Billboards, item: Item_Id, bottom: [3]f32) -> bool {
	if !item_has_icon(billboards.atlas, item) {
		return false
	}
	centre := bottom + {0, ITEM_BILLBOARD_SIZE / 2, 0}
	rl.DrawBillboardRec(billboards.camera, billboards.atlas.texture, item_atlas_source(billboards.atlas, item), centre, {ITEM_BILLBOARD_SIZE, ITEM_BILLBOARD_SIZE}, rl.WHITE)
	return true
}
