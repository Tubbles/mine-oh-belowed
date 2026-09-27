package game

import rl "vendor:raylib"

// The only UI file that calls raylib, with ui_font.odin for the text: it
// turns the draw list into pixels. Text comes from the TrueType families
// in data/fonts/, rasterised at the exact pixel size it is drawn at.

to_pixels :: proc(rectangle: Ui_Rectangle, pixels_per_unit: f32) -> rl.Rectangle {
	return {rectangle.x * pixels_per_unit, rectangle.y * pixels_per_unit, rectangle.width * pixels_per_unit, rectangle.height * pixels_per_unit}
}

to_raylib_color :: proc(color: Ui_Color) -> rl.Color {
	return rl.Color(color)
}

execute_text_command :: proc(command: Draw_Command, fonts: ^Font_Cache, pixels_per_unit: f32) {
	if fonts != nil && len(fonts.families) > 0 {
		draw_ui_text(fonts, command, to_pixels(command.rectangle, pixels_per_unit), pixels_per_unit)
	}
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

execute_draw_command :: proc(command: Draw_Command, focus: Ui_Id, atlas: Icon_Atlas, images: ^Ui_Image_Cache, fonts: ^Font_Cache, pixels_per_unit: f32) {
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
		execute_text_command(command, fonts, pixels_per_unit)
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
		execute_draw_command(command, state.focus, atlas, images, state.fonts, state.pixels_per_unit)
	}
}
