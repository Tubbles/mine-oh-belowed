package game

import "core:fmt"
import "core:math"

// The top down map (work item 0038): the explored columns coloured by
// their surface block and shaded by height, entities as dots, the player
// as a marker, and the prospecting records on top. The map is one image of
// MAP_IMAGE_SIZE pixels square, one pixel per block at the finest zoom
// and 2, 4, 8 or 16 blocks per pixel coarser, painted here and uploaded by
// the draw layer whenever it changes. Opening it reads the surfaces of the
// explored columns once (live for loaded columns); while it is open the
// image is repainted when the view moves and every MAP_REPAINT_SECONDS
// for the entities and records. Bumpers, the mouse wheel or the right
// stick zoom, the left stick, the movement keys or a pointer drag pan, B
// or Open_Map closes.

MAP_IMAGE_SIZE :: 256
MAP_ZOOM_LEVEL_COUNT :: 5
// The zoom the map opens at: 2 blocks per pixel.
MAP_DEFAULT_ZOOM :: 1
MAP_PAN_PIXELS_PER_SECOND :: 160.0
MAP_STICK_ZOOM_THRESHOLD :: 0.5
MAP_STICK_ZOOM_SECONDS :: 0.3
MAP_REPAINT_SECONDS :: 0.5
MAP_LEGEND_WIDTH :: 360
MAP_PLAYER_MARKER_SIZE :: 14.0
MAP_BRIGHTNESS_LOW :: 0.65
MAP_BRIGHTNESS_HIGH :: 1.15

MAP_UNEXPLORED_COLOR :: Ui_Color{14, 16, 22, 255}
MAP_ENTITY_COLOR :: Ui_Color{240, 240, 245, 255}
MAP_ASSAYED_COLOR :: Ui_Color{236, 176, 64, 255}
MAP_READING_COLOR :: Ui_Color{225, 80, 60, 255}
MAP_CORE_SAMPLE_COLOR :: Ui_Color{80, 210, 220, 255}
MAP_CORE_SAMPLE_VEIN_COLOR :: Ui_Color{250, 240, 90, 255}
MAP_SEISMIC_COLOR :: Ui_Color{200, 110, 230, 255}
MAP_RESOLVED_COLOR :: Ui_Color{255, 170, 255, 255}
MAP_PLAYER_COLOR :: Ui_Color{255, 255, 255, 255}
// How far the assayed colour covers the ground inside a footprint.
MAP_ASSAYED_BLEND :: 0.45
// Pixels of the direction line of a magnetometer reading at full strength.
MAP_READING_LINE_PIXELS :: 10

// The map screen's state, kept by the session. surfaces and pixels are
// owned here.
Map_View :: struct {
	active:            bool,
	// Block x and z at the centre of the image.
	centre:            [2]f32,
	zoom:              int,
	surfaces:          map[Chunk_Column]Column_Surface,
	pixels:            [dynamic]Ui_Color,
	revision:          u64,
	painted_frame:     Map_Frame,
	repaint_seconds:   f32,
	stick_zoom_seconds: f32,
	drag_pointer:      [2]f32,
	dragging:          bool,
}

// Which blocks the image shows: pixel (x, z) covers the blocks from
// origin + pixel * blocks_per_pixel.
Map_Frame :: struct {
	origin:           [2]i32,
	blocks_per_pixel: i32,
	size:             i32,
}

destroy_map_view :: proc(view: ^Map_View) {
	delete(view.surfaces)
	delete(view.pixels)
	view^ = {}
}

map_blocks_per_pixel :: proc(zoom: int) -> i32 {
	return i32(1) << uint(clamp(zoom, 0, MAP_ZOOM_LEVEL_COUNT - 1))
}

// Aligned to whole pixels, so panning moves the image a pixel at a time.
map_frame_for :: proc(centre: [2]f32, zoom: int) -> Map_Frame {
	blocks_per_pixel := map_blocks_per_pixel(zoom)
	half := MAP_IMAGE_SIZE / 2 * blocks_per_pixel
	origin := [2]i32{i32(math.floor(centre.x)) - half, i32(math.floor(centre.y)) - half}
	origin = {floor_divide(origin.x, blocks_per_pixel) * blocks_per_pixel, floor_divide(origin.y, blocks_per_pixel) * blocks_per_pixel}
	return Map_Frame{origin = origin, blocks_per_pixel = blocks_per_pixel, size = MAP_IMAGE_SIZE}
}

// The pixel holding a block column, and whether it lies in the image.
map_pixel_of :: proc(frame: Map_Frame, x, z: i32) -> (pixel: [2]i32, inside: bool) {
	pixel = {floor_divide(x - frame.origin.x, frame.blocks_per_pixel), floor_divide(z - frame.origin.y, frame.blocks_per_pixel)}
	return pixel, pixel.x >= 0 && pixel.y >= 0 && pixel.x < frame.size && pixel.y < frame.size
}

// The block column in the middle of a pixel.
map_block_of :: proc(frame: Map_Frame, pixel: [2]i32) -> [2]i32 {
	return frame.origin + pixel * frame.blocks_per_pixel + frame.blocks_per_pixel / 2
}

set_map_pixel :: proc(pixels: []Ui_Color, frame: Map_Frame, pixel: [2]i32, color: Ui_Color) {
	if pixel.x >= 0 && pixel.y >= 0 && pixel.x < frame.size && pixel.y < frame.size {
		pixels[pixel.y * frame.size + pixel.x] = color
	}
}

blend_color :: proc(base, over: Ui_Color, amount: f32) -> Ui_Color {
	result: Ui_Color
	for channel in 0 ..< 3 {
		result[channel] = u8(f32(base[channel]) * (1 - amount) + f32(over[channel]) * amount)
	}
	result[3] = 255
	return result
}

// Lower ground darker, higher ground lighter.
shade_by_height :: proc(color: Ui_Color, height: i16) -> Ui_Color {
	span := f32(TERRAIN_MAXIMUM_HEIGHT - TERRAIN_MINIMUM_HEIGHT)
	fraction := clamp((f32(height) - TERRAIN_MINIMUM_HEIGHT) / span, 0, 1)
	brightness := MAP_BRIGHTNESS_LOW + (MAP_BRIGHTNESS_HIGH - MAP_BRIGHTNESS_LOW) * fraction
	result: Ui_Color
	for channel in 0 ..< 3 {
		result[channel] = u8(clamp(f32(color[channel]) * brightness, 0, 255))
	}
	result[3] = 255
	return result
}

// The top face colour of every block, in the temp allocator.
map_block_colors :: proc(blocks: Block_Registry) -> []Ui_Color {
	colors := make([]Ui_Color, len(blocks.definitions), context.temp_allocator)
	for definition, index in blocks.definitions {
		top := definition.texture.top
		colors[index] = {top[0], top[1], top[2], 255}
	}
	return colors
}

surface_color :: proc(cell: Surface_Cell, colors: []Ui_Color) -> Ui_Color {
	if !surface_cell_is_known(cell) || int(cell.block) >= len(colors) {
		return MAP_UNEXPLORED_COLOR
	}
	return shade_by_height(colors[cell.block], cell.height)
}

paint_map_surface :: proc(pixels: []Ui_Color, frame: Map_Frame, surfaces: map[Chunk_Column]Column_Surface, colors: []Ui_Color) {
	for z in 0 ..< frame.size {
		for x in 0 ..< frame.size {
			block := map_block_of(frame, {x, z})
			pixels[z * frame.size + x] = surface_color(surface_at(surfaces, block.x, block.y), colors)
		}
	}
}

// Every pixel whose middle column lies in the disc.
paint_map_disc :: proc(pixels: []Ui_Color, frame: Map_Frame, centre: World_Coordinate, radius: i32, color: Ui_Color, amount: f32) {
	first, _ := map_pixel_of(frame, centre.x - radius, centre.z - radius)
	last, _ := map_pixel_of(frame, centre.x + radius, centre.z + radius)
	for z in max(first.y, 0) ..= min(last.y, frame.size - 1) {
		for x in max(first.x, 0) ..= min(last.x, frame.size - 1) {
			block := map_block_of(frame, {x, z})
			if column_in_disc(centre, radius, block.x, block.y) {
				index := z * frame.size + x
				pixels[index] = blend_color(pixels[index], color, amount)
			}
		}
	}
}

// Pixels within about one pixel of the circle.
paint_map_circle :: proc(pixels: []Ui_Color, frame: Map_Frame, centre: World_Coordinate, radius: i32, color: Ui_Color) {
	width := f32(frame.blocks_per_pixel) * 0.75
	first, _ := map_pixel_of(frame, centre.x - radius - frame.blocks_per_pixel, centre.z - radius - frame.blocks_per_pixel)
	last, _ := map_pixel_of(frame, centre.x + radius + frame.blocks_per_pixel, centre.z + radius + frame.blocks_per_pixel)
	for z in max(first.y, 0) ..= min(last.y, frame.size - 1) {
		for x in max(first.x, 0) ..= min(last.x, frame.size - 1) {
			block := map_block_of(frame, {x, z})
			dx, dz := f32(block.x - centre.x), f32(block.y - centre.z)
			if abs(math.sqrt(dx * dx + dz * dz) - f32(radius)) <= width {
				pixels[z * frame.size + x] = color
			}
		}
	}
}

// A plus sign centred on the column.
paint_map_cross :: proc(pixels: []Ui_Color, frame: Map_Frame, x, z: i32, color: Ui_Color) {
	pixel, _ := map_pixel_of(frame, x, z)
	for offset in -2 ..= i32(2) {
		set_map_pixel(pixels, frame, pixel + {offset, 0}, color)
		set_map_pixel(pixels, frame, pixel + {0, offset}, color)
	}
}

// A 2 by 2 dot, and for a reading that found a vein a line towards it
// as long as the reading was strong.
paint_map_reading :: proc(pixels: []Ui_Color, frame: Map_Frame, reading: Magnetometer_Reading) {
	pixel, _ := map_pixel_of(frame, reading.origin.x, reading.origin.y)
	for offset in ([4][2]i32{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
		set_map_pixel(pixels, frame, pixel + offset, MAP_READING_COLOR)
	}
	length := math.sqrt(f32(reading.offset.x * reading.offset.x + reading.offset.y * reading.offset.y))
	if !reading.found || length == 0 {
		return
	}
	direction := [2]f32{f32(reading.offset.x), f32(reading.offset.y)} / length
	steps := max(int(f32(MAP_READING_LINE_PIXELS) * f32(reading.strength) / MAGNETOMETER_FULL), 2)
	for step in 1 ..= steps {
		point := direction * f32(step)
		set_map_pixel(pixels, frame, pixel + {i32(math.round(point.x)), i32(math.round(point.y))}, MAP_READING_COLOR)
	}
}

paint_map_entities :: proc(pixels: []Ui_Color, frame: Map_Frame, cells: map[World_Coordinate]Entity_Handle) {
	for cell in cells {
		if pixel, inside := map_pixel_of(frame, cell.x, cell.z); inside {
			pixels[pixel.y * frame.size + pixel.x] = MAP_ENTITY_COLOR
		}
	}
}

// The prospecting layers over the ground: assayed footprints, seismic
// outlines, core samples and magnetometer readings, in that order.
paint_map_records :: proc(pixels: []Ui_Color, frame: Map_Frame, world: ^World) {
	for assayed in world.assayed_veins {
		paint_map_disc(pixels, frame, assayed.centre, assayed.radius, MAP_ASSAYED_COLOR, MAP_ASSAYED_BLEND)
	}
	for outline in world.seismic_outlines {
		paint_map_circle(pixels, frame, outline.centre, outline.radius, outline.resolved ? MAP_RESOLVED_COLOR : MAP_SEISMIC_COLOR)
	}
	for sample in world.core_samples {
		paint_map_cross(pixels, frame, sample.position.x, sample.position.z, sample.vein_found ? MAP_CORE_SAMPLE_VEIN_COLOR : MAP_CORE_SAMPLE_COLOR)
	}
	for reading in world.magnetometer_readings {
		paint_map_reading(pixels, frame, reading)
	}
}

paint_map :: proc(view: ^Map_View, frame: Map_Frame, world: ^World, blocks: Block_Registry) {
	resize(&view.pixels, int(frame.size * frame.size))
	paint_map_surface(view.pixels[:], frame, view.surfaces, map_block_colors(blocks))
	paint_map_entities(view.pixels[:], frame, world.entities.cells)
	paint_map_records(view.pixels[:], frame, world)
	view.painted_frame = frame
	view.revision += 1
	view.repaint_seconds = 0
}

// Input.

// Bumpers and the wheel step at once, the right stick steps while held.
// The right bumper, the wheel up and the stick up zoom in (fewer blocks
// per pixel).
map_zoom_step :: proc(view: ^Map_View, input: Ui_Input, seconds: f32) -> int {
	step := 0
	if input.tab_previous || input.scroll_wheel < 0 {
		step += 1
	}
	if input.tab_next || input.scroll_wheel > 0 {
		step -= 1
	}
	stick := input.right_stick.y
	if abs(stick) < MAP_STICK_ZOOM_THRESHOLD {
		view.stick_zoom_seconds = 0
		return step
	}
	if view.stick_zoom_seconds <= 0 {
		step += stick > 0 ? -1 : 1
		view.stick_zoom_seconds = MAP_STICK_ZOOM_SECONDS
	}
	view.stick_zoom_seconds -= seconds
	return step
}

// The left stick moves the view (up is north on the map, towards -z), a
// pointer drag drags the ground along.
pan_map :: proc(view: ^Map_View, state: ^Ui_State, image: Ui_Rectangle) {
	blocks_per_pixel := f32(map_blocks_per_pixel(view.zoom))
	view.centre += {state.input.move.x, -state.input.move.y} * MAP_PAN_PIXELS_PER_SECOND * blocks_per_pixel * state.frame_seconds
	dragging := state.pointer_held && state.pointer_source != .None
	if dragging && view.dragging {
		blocks_per_unit := f32(MAP_IMAGE_SIZE) * blocks_per_pixel / image.width
		view.centre -= (state.pointer - view.drag_pointer) * blocks_per_unit
	}
	view.dragging = dragging && (view.dragging || rectangle_contains(image, state.pointer))
	view.drag_pointer = state.pointer
}

// Opening centres on the player and reads the surfaces.
activate_map_view :: proc(view: ^Map_View, world: ^World, player: Player) {
	view.active = true
	view.centre = {player.position.x, player.position.z}
	if view.zoom == 0 && view.revision == 0 {
		view.zoom = MAP_DEFAULT_ZOOM
	}
	view.dragging = false
	collect_explored_surfaces(world, &view.surfaces)
	view.painted_frame = {}
}

// Drawing.

map_point_units :: proc(image: Ui_Rectangle, frame: Map_Frame, position: [2]f32) -> [2]f32 {
	units_per_block := image.width / f32(frame.size * frame.blocks_per_pixel)
	return {image.x + (position.x - f32(frame.origin.x)) * units_per_block, image.y + (position.y - f32(frame.origin.y)) * units_per_block}
}

// A square on the player's position with a dot where the player looks.
draw_map_player :: proc(state: ^Ui_State, image: Ui_Rectangle, frame: Map_Frame, player: Player) {
	point := map_point_units(image, frame, {player.position.x, player.position.z})
	if !rectangle_contains(image, point) {
		return
	}
	half := f32(MAP_PLAYER_MARKER_SIZE / 2)
	draw_fill(state, {point.x - half, point.y - half, 2 * half, 2 * half}, MAP_PLAYER_COLOR)
	draw_outline(state, {point.x - half, point.y - half, 2 * half, 2 * half}, UI_PANEL_COLOR)
	yaw := player.yaw * math.RAD_PER_DEG
	facing := point + [2]f32{math.cos(yaw), math.sin(yaw)} * MAP_PLAYER_MARKER_SIZE * 1.2
	draw_fill(state, {facing.x - half / 2, facing.y - half / 2, half, half}, MAP_PLAYER_COLOR)
}

draw_map_legend :: proc(state: ^Ui_State, area: Ui_Rectangle, view: ^Map_View) {
	content := area
	scale := fmt.tprintf("%s: %d %s", text("map_scale"), map_blocks_per_pixel(view.zoom), text("map_blocks_per_pixel"))
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), scale, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	entries := [?]struct {
		color: Ui_Color,
		key:   string,
	} {
		{MAP_PLAYER_COLOR, "map_legend_player"},
		{MAP_ENTITY_COLOR, "map_legend_machines"},
		{MAP_ASSAYED_COLOR, "map_legend_assayed"},
		{MAP_READING_COLOR, "map_legend_magnetometer"},
		{MAP_CORE_SAMPLE_COLOR, "map_legend_core_sample"},
		{MAP_CORE_SAMPLE_VEIN_COLOR, "map_legend_core_sample_vein"},
		{MAP_SEISMIC_COLOR, "map_legend_seismic"},
		{MAP_RESOLVED_COLOR, "map_legend_resolved"},
	}
	for entry in entries {
		row := cut_top(&content, UI_ROW_HEIGHT)
		swatch := Ui_Rectangle{row.x, row.y + (row.height - 20) / 2, 20, 20}
		draw_fill(state, swatch, entry.color)
		draw_text(state, {row.x + 32, row.y, row.width - 32, row.height}, text(entry.key), UI_BODY_TEXT_SIZE, .Left)
	}
}

map_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	view, world := screen_context.map_view, screen_context.world
	if view == nil || world == nil {
		pop_screen(&state.screens)
		return
	}
	if !view.active {
		activate_map_view(view, world, screen_context.player^)
	}
	ui_backdrop(state)
	panel := ui_safe_area(state)
	ui_panel_begin(state, "map", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("map_title"), UI_HEADING_TEXT_SIZE, .Left)
	side := min(content.height, content.width - MAP_LEGEND_WIDTH - UI_PADDING)
	image := Ui_Rectangle{content.x, content.y, side, side}
	legend := Ui_Rectangle{image.x + side + UI_PADDING, content.y, MAP_LEGEND_WIDTH, content.height}
	view.zoom = clamp(view.zoom + map_zoom_step(view, state.input, state.frame_seconds), 0, MAP_ZOOM_LEVEL_COUNT - 1)
	pan_map(view, state, image)
	frame := map_frame_for(view.centre, view.zoom)
	view.repaint_seconds += state.frame_seconds
	if frame != view.painted_frame || view.repaint_seconds >= MAP_REPAINT_SECONDS {
		paint_map(view, frame, world, screen_context.blocks)
	}
	draw_image(state, image, view.pixels[:], {frame.size, frame.size}, view.revision)
	draw_outline(state, image, UI_PANEL_BORDER_COLOR)
	draw_map_player(state, image, frame, screen_context.player^)
	draw_map_legend(state, legend, view)
	ui_panel_end(state)
	hints := [?]Glyph_Hint{{.Tab_Previous, ""}, {.Tab_Next, text("hint_zoom")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}
