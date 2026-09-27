package game

import "core:strings"
import rl "vendor:raylib"

// The only UI file that calls raylib: it turns the draw list into pixels.
// raylib's default font is a 10 pixel bitmap scaled up; a TTF from
// data/fonts/ replaces it once one is chosen.

DEFAULT_FONT_SPACING_FACTOR :: 0.1

to_pixels :: proc(rectangle: Ui_Rectangle, pixels_per_unit: f32) -> rl.Rectangle {
	return {rectangle.x * pixels_per_unit, rectangle.y * pixels_per_unit, rectangle.width * pixels_per_unit, rectangle.height * pixels_per_unit}
}

to_raylib_color :: proc(color: Ui_Color) -> rl.Color {
	return rl.Color(color)
}

// Text width scales linearly with the size, so measuring at the size in
// units gives the width in units.
raylib_measure_text :: proc(text: string, size: f32) -> f32 {
	text_c := strings.clone_to_cstring(text, context.temp_allocator)
	return rl.MeasureTextEx(rl.GetFontDefault(), text_c, size, size * DEFAULT_FONT_SPACING_FACTOR).x
}

execute_text_command :: proc(command: Draw_Command, pixels_per_unit: f32) {
	box := to_pixels(command.rectangle, pixels_per_unit)
	size := command.text_size * pixels_per_unit
	spacing := size * DEFAULT_FONT_SPACING_FACTOR
	text_c := strings.clone_to_cstring(command.text, context.temp_allocator)
	width := rl.MeasureTextEx(rl.GetFontDefault(), text_c, size, spacing).x
	x := box.x
	switch command.alignment {
	case .Left:
	case .Centre:
		x += (box.width - width) / 2
	case .Right:
		x += box.width - width
	}
	y := box.y + (box.height - size) / 2
	rl.DrawTextEx(rl.GetFontDefault(), text_c, {x, y}, size, spacing, to_raylib_color(command.color))
}

// The block atlas, for placeholder item icons.
Icon_Atlas :: struct {
	texture: rl.Texture2D,
	layout:  Atlas_Layout,
}

execute_atlas_tile_command :: proc(command: Draw_Command, atlas: Icon_Atlas, pixels_per_unit: f32) {
	origin := atlas_tile_origin(atlas.layout, command.tile)
	width, height := f32(atlas.texture.width), f32(atlas.texture.height)
	uv_size := atlas_tile_uv_size(atlas.layout)
	source := rl.Rectangle{origin.x * width, origin.y * height, uv_size.x * width, uv_size.y * height}
	rl.DrawTexturePro(atlas.texture, source, to_pixels(command.rectangle, pixels_per_unit), {}, 0, rl.WHITE)
}

// The texture of the last drawn image (the map), uploaded again when the
// command's revision or size changes.
Ui_Image_Cache :: struct {
	texture:  rl.Texture2D,
	size:     [2]i32,
	revision: u64,
}

release_ui_images :: proc(images: ^Ui_Image_Cache) {
	if images.texture.id != 0 {
		rl.UnloadTexture(images.texture)
	}
	images^ = {}
}

upload_ui_image :: proc(images: ^Ui_Image_Cache, command: Draw_Command) {
	if images.texture.id != 0 && images.size == command.image_size && images.revision == command.image_revision {
		return
	}
	if images.texture.id == 0 || images.size != command.image_size {
		release_ui_images(images)
		image := rl.Image {
			data    = raw_data(command.pixels),
			width   = command.image_size.x,
			height  = command.image_size.y,
			mipmaps = 1,
			format  = .UNCOMPRESSED_R8G8B8A8,
		}
		images.texture = rl.LoadTextureFromImage(image)
	} else {
		rl.UpdateTexture(images.texture, raw_data(command.pixels))
	}
	images.size, images.revision = command.image_size, command.image_revision
}

execute_image_command :: proc(command: Draw_Command, images: ^Ui_Image_Cache, pixels_per_unit: f32) {
	if images == nil || len(command.pixels) != int(command.image_size.x * command.image_size.y) || len(command.pixels) == 0 {
		return
	}
	upload_ui_image(images, command)
	source := rl.Rectangle{0, 0, f32(command.image_size.x), f32(command.image_size.y)}
	rl.DrawTexturePro(images.texture, source, to_pixels(command.rectangle, pixels_per_unit), {}, 0, rl.WHITE)
}

execute_draw_command :: proc(command: Draw_Command, focus: Ui_Id, atlas: Icon_Atlas, images: ^Ui_Image_Cache, pixels_per_unit: f32) {
	switch command.kind {
	case .Fill:
		rl.DrawRectangleRec(to_pixels(command.rectangle, pixels_per_unit), to_raylib_color(command.color))
	case .Outline:
		rl.DrawRectangleLinesEx(to_pixels(command.rectangle, pixels_per_unit), command.thickness * pixels_per_unit, to_raylib_color(command.color))
	case .Focus_Outline:
		if command.widget == focus {
			rl.DrawRectangleLinesEx(to_pixels(command.rectangle, pixels_per_unit), command.thickness * pixels_per_unit, to_raylib_color(command.color))
		}
	case .Text:
		execute_text_command(command, pixels_per_unit)
	case .Clip_Begin:
		box := to_pixels(command.rectangle, pixels_per_unit)
		rl.BeginScissorMode(i32(box.x), i32(box.y), i32(box.width), i32(box.height))
	case .Clip_End:
		rl.EndScissorMode()
	case .Atlas_Tile:
		execute_atlas_tile_command(command, atlas, pixels_per_unit)
	case .Image:
		execute_image_command(command, images, pixels_per_unit)
	}
}

execute_draw_list :: proc(state: Ui_State, atlas: Icon_Atlas, images: ^Ui_Image_Cache) {
	for command in state.draw_list {
		execute_draw_command(command, state.focus, atlas, images, state.pixels_per_unit)
	}
}
