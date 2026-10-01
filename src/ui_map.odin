package game

import "core:fmt"
import "core:math"
import "core:slice"

// The top down map (work item 0038): the explored columns coloured by
// their surface block tinted with their biome's map colour (work item
// 0058) and shaded by height, entities as dots in the theme's colour of
// their machine item's category (work item 0071), the player
// as a marker, and the prospecting records on top, the markers and the
// legend in the colours of the palette setting (work item 0074); during a capsule
// descent a parachute over the landing pad and during a survey
// satellite's pass the satellite crossing west to east (work item 0069).
// The map is one image of
// MAP_IMAGE_SIZE pixels square, one pixel per block at the finest zoom
// and 2, 4, 8 or 16 blocks per pixel coarser, painted here and uploaded by
// the draw layer whenever it changes. Opening it reads the surfaces of the
// explored columns once (live for loaded columns); while it is open the
// image is repainted when the view moves and every MAP_REPAINT_SECONDS
// for the entities and records. The biome of every pixel comes from the
// generator (sample_column, pure), sampled only when the frame changes and
// reused for the pixels a pan keeps; the legend lists the biomes shown
// and marks the player's. Bumpers, the mouse wheel or the right
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
// The least width the legend keeps beside the image.
MAP_LEGEND_WIDTH :: 360
MAP_PLAYER_MARKER_SIZE :: 14.0
MAP_BRIGHTNESS_LOW :: 0.65
MAP_BRIGHTNESS_HIGH :: 1.15

MAP_UNEXPLORED_COLOR :: Ui_Color{14, 16, 22, 255}
// The default palette's map colours (DEFAULT_UI_THEME); the map draws
// the palette's (Palette_Color).
MAP_ASSAYED_COLOR :: Ui_Color{236, 176, 64, 255}
MAP_READING_COLOR :: Ui_Color{225, 80, 60, 255}
MAP_CORE_SAMPLE_COLOR :: Ui_Color{80, 210, 220, 255}
MAP_CORE_SAMPLE_VEIN_COLOR :: Ui_Color{250, 240, 90, 255}
MAP_SEISMIC_COLOR :: Ui_Color{200, 110, 230, 255}
MAP_RESOLVED_COLOR :: Ui_Color{255, 170, 255, 255}
MAP_PLAYER_COLOR :: Ui_Color{255, 255, 255, 255}
MAP_EVENT_MARKER_SIZE :: 20.0
MAP_PARACHUTE_COLOR :: Ui_Color{235, 120, 60, 255}
MAP_CAPSULE_COLOR :: Ui_Color{220, 220, 225, 255}
MAP_SATELLITE_COLOR :: Ui_Color{200, 225, 255, 255}
// How far the assayed colour covers the ground inside a footprint.
MAP_ASSAYED_BLEND :: 0.45
// How far the biome's map colour tints the surface block's colour.
MAP_BIOME_BLEND :: 0.5
MAP_LEGEND_SWATCH_SIZE :: 20
// The scale line and the eight marker entries.
MAP_LEGEND_FIXED_ROWS :: 9
// Pixels of the direction line of a magnetometer reading at full strength.
MAP_READING_LINE_PIXELS :: 10

// The map screen's state, kept by the session. surfaces, pixels and
// biomes are owned here. biomes holds the biome index of every pixel of
// biome_frame; biomes_shown is indexed by biome and marks those on an
// explored pixel of the last painted image.
Map_View :: struct {
	active:            bool,
	// Block x and z at the centre of the image.
	centre:            [2]f32,
	zoom:              int,
	surfaces:          map[Chunk_Column]Column_Surface,
	pixels:            [dynamic]Ui_Color,
	biomes:            [dynamic]int,
	biome_frame:       Map_Frame,
	biomes_shown:      [dynamic]bool,
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
	delete(view.biomes)
	delete(view.biomes_shown)
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
	return tinted_surface_color(cell, colors, {}, 0)
}

// The block's colour blended with the tint by amount, then shaded by
// height.
tinted_surface_color :: proc(cell: Surface_Cell, colors: []Ui_Color, tint: Ui_Color, amount: f32) -> Ui_Color {
	if !surface_cell_is_known(cell) || int(cell.block) >= len(colors) {
		return MAP_UNEXPLORED_COLOR
	}
	return shade_by_height(blend_color(colors[cell.block], tint, amount), cell.height)
}

map_biome_color :: proc(biome: Biome) -> Ui_Color {
	color := biome.definition.map_color
	return {color[0], color[1], color[2], 255}
}

// The biome of every pixel with the biome colours, and which biomes an
// explored pixel shows. Empty biomes paint without a tint.
Map_Biome_Layer :: struct {
	biomes: []int,
	colors: []Ui_Color,
	shown:  []bool,
}

// The map colour of every biome, in the temp allocator.
map_biome_colors :: proc(biomes: []Biome) -> []Ui_Color {
	colors := make([]Ui_Color, len(biomes), context.temp_allocator)
	for biome, index in biomes {
		colors[index] = map_biome_color(biome)
	}
	return colors
}

paint_map_surface :: proc(pixels: []Ui_Color, frame: Map_Frame, surfaces: map[Chunk_Column]Column_Surface, colors: []Ui_Color, layer: Map_Biome_Layer) {
	for z in 0 ..< frame.size {
		for x in 0 ..< frame.size {
			index := z * frame.size + x
			block := map_block_of(frame, {x, z})
			cell := surface_at(surfaces, block.x, block.y)
			if len(layer.biomes) == 0 {
				pixels[index] = surface_color(cell, colors)
				continue
			}
			biome := layer.biomes[index]
			pixels[index] = tinted_surface_color(cell, colors, layer.colors[biome], MAP_BIOME_BLEND)
			layer.shown[biome] ||= surface_cell_is_known(cell)
		}
	}
}

// The biome of a pixel: kept from the previous frame when that frame, at
// the same zoom, covered the pixel's middle column, sampled otherwise.
map_pixel_biome :: proc(generator: ^Generator, previous: []int, previous_frame, frame: Map_Frame, pixel: [2]i32) -> int {
	block := map_block_of(frame, pixel)
	reusable := previous_frame.blocks_per_pixel == frame.blocks_per_pixel && len(previous) == int(previous_frame.size * previous_frame.size)
	if !reusable {
		return sample_column(generator, block.x, block.y).biome
	}
	if old_pixel, inside := map_pixel_of(previous_frame, block.x, block.y); inside {
		return previous[old_pixel.y * previous_frame.size + old_pixel.x]
	}
	return sample_column(generator, block.x, block.y).biome
}

// Only when the frame changed: a full image is about 65 thousand column
// samples, a pan by a pixel only a row or a column of them.
update_map_biomes :: proc(view: ^Map_View, frame: Map_Frame, generator: ^Generator) {
	if frame == view.biome_frame && len(view.biomes) == int(frame.size * frame.size) {
		return
	}
	previous := make([]int, len(view.biomes), context.temp_allocator)
	copy(previous, view.biomes[:])
	resize(&view.biomes, int(frame.size * frame.size))
	for z in 0 ..< frame.size {
		for x in 0 ..< frame.size {
			view.biomes[z * frame.size + x] = map_pixel_biome(generator, previous, view.biome_frame, frame, {x, z})
		}
	}
	view.biome_frame = frame
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
paint_map_reading :: proc(pixels: []Ui_Color, frame: Map_Frame, reading: Magnetometer_Reading, color: Ui_Color) {
	pixel, _ := map_pixel_of(frame, reading.origin.x, reading.origin.y)
	for offset in ([4][2]i32{{0, 0}, {1, 0}, {0, 1}, {1, 1}}) {
		set_map_pixel(pixels, frame, pixel + offset, color)
	}
	length := math.sqrt(f32(reading.offset.x * reading.offset.x + reading.offset.y * reading.offset.y))
	if !reading.found || length == 0 {
		return
	}
	direction := [2]f32{f32(reading.offset.x), f32(reading.offset.y)} / length
	steps := max(int(f32(MAP_READING_LINE_PIXELS) * f32(reading.strength) / MAGNETOMETER_FULL), 2)
	for step in 1 ..= steps {
		point := direction * f32(step)
		set_map_pixel(pixels, frame, pixel + {i32(math.round(point.x)), i32(math.round(point.y))}, color)
	}
}

// The dot colour of a machine: its item's category's marker, the
// machine marker for one without an item (the drop capsule), under the
// palette (map_dot_color).
machine_marker_color :: proc(theme: Ui_Theme, machines: Machine_Registry, items: Item_Registry, machine: Machine_Id, palette := Marker_Palette.Default) -> Ui_Color {
	if int(machine) >= len(machines.machines) {
		return map_dot_color(theme, palette, .Machine)
	}
	item := machines.machines[machine].item
	if int(item) >= len(items.items) {
		return map_dot_color(theme, palette, .Machine)
	}
	return map_dot_color(theme, palette, items.items[item].category)
}

// Indexed by Machine_Id, in the temp allocator.
machine_marker_colors :: proc(theme: Ui_Theme, machines: Machine_Registry, items: Item_Registry, palette := Marker_Palette.Default) -> []Ui_Color {
	colors := make([]Ui_Color, len(machines.machines), context.temp_allocator)
	for &color, index in colors {
		color = machine_marker_color(theme, machines, items, Machine_Id(index), palette)
	}
	return colors
}

paint_map_entities :: proc(pixels: []Ui_Color, frame: Map_Frame, entities: ^Entities, marker_colors: []Ui_Color) {
	for cell, handle in entities.cells {
		pixel, inside := map_pixel_of(frame, cell.x, cell.z)
		common := entity_common(entities, handle)
		if inside && common != nil && int(common.machine) < len(marker_colors) {
			pixels[pixel.y * frame.size + pixel.x] = marker_colors[common.machine]
		}
	}
}

// The prospecting layers over the ground: assayed footprints, seismic
// outlines, core samples and magnetometer readings, in that order, in
// the palette's colours.
paint_map_records :: proc(pixels: []Ui_Color, frame: Map_Frame, records: ^Game_Records, colors: [Palette_Color]Ui_Color) {
	for assayed in records.assayed_veins {
		paint_map_disc(pixels, frame, assayed.centre, assayed.radius, colors[.Map_Assayed], MAP_ASSAYED_BLEND)
	}
	for outline in records.seismic_outlines {
		paint_map_circle(pixels, frame, outline.centre, outline.radius, colors[outline.resolved ? .Map_Resolved : .Map_Seismic])
	}
	for sample in records.core_samples {
		paint_map_cross(pixels, frame, sample.position.x, sample.position.z, colors[sample.vein_found ? .Map_Core_Sample_Vein : .Map_Core_Sample])
	}
	for reading in records.magnetometer_readings {
		paint_map_reading(pixels, frame, reading, colors[.Map_Magnetometer])
	}
}

// Without a generator the surface has no biome tint. marker_colors is
// indexed by Machine_Id (machine_marker_colors); colors is the palette's.
paint_map :: proc(view: ^Map_View, frame: Map_Frame, world: ^World, records: ^Game_Records, blocks: Block_Registry, generator: ^Generator, marker_colors: []Ui_Color, colors: [Palette_Color]Ui_Color) {
	resize(&view.pixels, int(frame.size * frame.size))
	layer: Map_Biome_Layer
	if generator != nil {
		update_map_biomes(view, frame, generator)
		resize(&view.biomes_shown, len(generator.biomes))
		slice.fill(view.biomes_shown[:], false)
		layer = {biomes = view.biomes[:], colors = map_biome_colors(generator.biomes), shown = view.biomes_shown[:]}
	}
	paint_map_surface(view.pixels[:], frame, view.surfaces, map_block_colors(blocks), layer)
	paint_map_entities(view.pixels[:], frame, &world.entities, marker_colors)
	paint_map_records(view.pixels[:], frame, records, colors)
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
activate_map_view :: proc(view: ^Map_View, world: ^World, explored: map[Chunk_Column]Column_Surface, player: Player) {
	view.active = true
	view.centre = {player.position.x, player.position.z}
	if view.zoom == 0 && view.revision == 0 {
		view.zoom = MAP_DEFAULT_ZOOM
	}
	view.dragging = false
	collect_explored_surfaces(world, explored, &view.surfaces)
	view.painted_frame = {}
	// The biome table may have been reloaded since the map was last open.
	view.biome_frame = {}
}

// Drawing.

map_point_units :: proc(image: Ui_Rectangle, frame: Map_Frame, position: [2]f32) -> [2]f32 {
	units_per_block := image.width / f32(frame.size * frame.blocks_per_pixel)
	return {image.x + (position.x - f32(frame.origin.x)) * units_per_block, image.y + (position.y - f32(frame.origin.y)) * units_per_block}
}

// A square on the player's position with a dot where the player looks.
draw_map_player :: proc(state: ^Ui_State, image: Ui_Rectangle, frame: Map_Frame, player: Player, color: Ui_Color) {
	point := map_point_units(image, frame, {player.position.x, player.position.z})
	if !rectangle_contains(image, point) {
		return
	}
	half := f32(MAP_PLAYER_MARKER_SIZE / 2)
	draw_fill(state, {point.x - half, point.y - half, 2 * half, 2 * half}, color)
	draw_outline(state, {point.x - half, point.y - half, 2 * half, 2 * half}, UI_PANEL_COLOR)
	yaw := player.yaw * math.RAD_PER_DEG
	facing := point + [2]f32{math.cos(yaw), math.sin(yaw)} * MAP_PLAYER_MARKER_SIZE * 1.2
	draw_fill(state, {facing.x - half / 2, facing.y - half / 2, half, half}, color)
}

// Along the pad's row, from half the image's span west of the pad to half
// east of it, over the pad halfway through the pass.
satellite_map_position :: proc(frame: Map_Frame, pad: [2]f32, pass: Satellite_Pass) -> [2]f32 {
	span := f32(frame.size * frame.blocks_per_pixel)
	return {pad.x + (satellite_pass_fraction(pass) - 0.5) * span, pad.y}
}

// A canopy over a capsule.
draw_map_parachute :: proc(state: ^Ui_State, point: [2]f32) {
	size := f32(MAP_EVENT_MARKER_SIZE)
	draw_fill(state, {point.x - size / 2, point.y - size / 2, size, size / 2}, MAP_PARACHUTE_COLOR)
	draw_fill(state, {point.x - size / 4, point.y, size / 2, size / 2}, MAP_CAPSULE_COLOR)
}

// A body between two panels.
draw_map_satellite :: proc(state: ^Ui_State, point: [2]f32) {
	size := f32(MAP_EVENT_MARKER_SIZE)
	draw_fill(state, {point.x - size / 2, point.y - size / 8, size, size / 4}, MAP_SATELLITE_COLOR)
	draw_fill(state, {point.x - size / 4, point.y - size / 4, size / 2, size / 2}, MAP_CAPSULE_COLOR)
}

// The capsule descent and the satellite pass the frame loop keeps
// (render_particles.odin); a marker is left out where it would leave the
// image.
draw_map_events :: proc(state: ^Ui_State, image: Ui_Rectangle, frame: Map_Frame, memory: ^Particle_Memory, pad: Landing_Pad_Site) {
	if memory == nil || !pad.present {
		return
	}
	inside := inset(image, MAP_EVENT_MARKER_SIZE / 2)
	centre := [2]f32{f32(pad.centre.x) + 0.5, f32(pad.centre.z) + 0.5}
	if point := map_point_units(image, frame, centre); memory.descent.active && rectangle_contains(inside, point) {
		draw_map_parachute(state, point)
	}
	if point := map_point_units(image, frame, satellite_map_position(frame, centre, memory.satellite)); memory.satellite.active && rectangle_contains(inside, point) {
		draw_map_satellite(state, point)
	}
}

draw_map_legend_row :: proc(state: ^Ui_State, content: ^Ui_Rectangle, color: Ui_Color, label: string, label_color := UI_TEXT_COLOR) {
	row := cut_top(content, UI_ROW_HEIGHT)
	swatch := Ui_Rectangle{row.x, row.y + (row.height - MAP_LEGEND_SWATCH_SIZE) / 2, MAP_LEGEND_SWATCH_SIZE, MAP_LEGEND_SWATCH_SIZE}
	draw_fill(state, swatch, color)
	draw_text_fitted(state, {row.x + 32, row.y, row.width - 32, row.height}, label, UI_BODY_TEXT_SIZE, .Left, label_color)
}

// The biome rows the legend needs: a heading and one per biome shown.
map_biome_legend_rows :: proc(view: ^Map_View, generator: ^Generator) -> int {
	if generator == nil || len(view.biomes_shown) != len(generator.biomes) {
		return 0
	}
	rows := 1
	for shown in view.biomes_shown {
		rows += shown ? 1 : 0
	}
	return rows
}

// The biomes an explored pixel shows, the player's in the accent colour
// and marked, as long as rows fit.
draw_map_biome_legend :: proc(state: ^Ui_State, content: ^Ui_Rectangle, view: ^Map_View, generator: ^Generator, player: Player) {
	if map_biome_legend_rows(view, generator) == 0 || content.height < 2 * UI_ROW_HEIGHT {
		return
	}
	here := sample_column(generator, i32(math.floor(player.position.x)), i32(math.floor(player.position.z))).biome
	draw_text_fitted(state, cut_top(content, UI_ROW_HEIGHT), text("map_legend_biomes"), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	for biome, index in generator.biomes {
		if !view.biomes_shown[index] || content.height < UI_ROW_HEIGHT {
			continue
		}
		name := text(biome.definition.name_key)
		if index == here {
			draw_map_legend_row(state, content, map_biome_color(biome), format_message_text(text("map_legend_here"), name), UI_ACCENT_COLOR)
		} else {
			draw_map_legend_row(state, content, map_biome_color(biome), name)
		}
	}
}

Map_Legend_Entry :: struct {
	color: Palette_Color,
	key:   string,
}

@(rodata)
map_legend_entries := [?]Map_Legend_Entry {
	{.Map_Player, "map_legend_player"},
	{.Map_Machine, "map_legend_machines"},
	{.Map_Assayed, "map_legend_assayed"},
	{.Map_Magnetometer, "map_legend_magnetometer"},
	{.Map_Core_Sample, "map_legend_core_sample"},
	{.Map_Core_Sample_Vein, "map_legend_core_sample_vein"},
	{.Map_Seismic, "map_legend_seismic"},
	{.Map_Resolved, "map_legend_resolved"},
}

// The biomes go below the other entries, or in a second column when the
// height does not hold both (large UI scales).
draw_map_legend :: proc(state: ^Ui_State, area: Ui_Rectangle, view: ^Map_View, generator: ^Generator, player: Player, colors: [Palette_Color]Ui_Color) {
	content := area
	biome_content := &content
	second_column: Ui_Rectangle
	if f32(MAP_LEGEND_FIXED_ROWS + map_biome_legend_rows(view, generator)) * UI_ROW_HEIGHT > area.height {
		second_column = content
		content = cut_left(&second_column, (area.width - UI_GAP) / 2)
		cut_left(&second_column, UI_GAP)
		biome_content = &second_column
	}
	scale := fmt.tprintf("%s: %d %s", text("map_scale"), map_blocks_per_pixel(view.zoom), text("map_blocks_per_pixel"))
	draw_text_fitted(state, cut_top(&content, UI_ROW_HEIGHT), scale, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	for entry in map_legend_entries {
		draw_map_legend_row(state, &content, colors[entry.color], text(entry.key))
	}
	draw_map_biome_legend(state, biome_content, view, generator, player)
}

map_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	if screen_context.views == nil || screen_context.world == nil {
		pop_screen(&state.screens)
		return
	}
	view, world := &screen_context.views.map_view, screen_context.world
	if !view.active {
		activate_map_view(view, world, screen_context.records.explored, screen_context.player^)
	}
	ui_backdrop(state)
	panel := ui_panel_area(state)
	ui_panel_begin(state, "map", panel)
	content := inset(panel, UI_PADDING)
	ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text("map_title"), UI_HEADING_TEXT_SIZE, .Left)
	side := min(content.height, content.width - MAP_LEGEND_WIDTH - UI_PADDING)
	image := Ui_Rectangle{content.x, content.y, side, side}
	// The legend takes the width the square image leaves.
	legend := Ui_Rectangle{image.x + side + UI_PADDING, content.y, content.width - side - UI_PADDING, content.height}
	palette := state.accessibility.palette
	colors := ui_theme(state).palettes[palette]
	view.zoom = clamp(view.zoom + map_zoom_step(view, state.input, state.frame_seconds), 0, MAP_ZOOM_LEVEL_COUNT - 1)
	pan_map(view, state, image)
	frame := map_frame_for(view.centre, view.zoom)
	view.repaint_seconds += state.frame_seconds
	if frame != view.painted_frame || view.repaint_seconds >= MAP_REPAINT_SECONDS {
		paint_map(view, frame, world, screen_context.records, screen_context.blocks, screen_context.generator, machine_marker_colors(ui_theme(state), screen_context.machines, screen_context.items, palette), colors)
	}
	draw_image(state, image, view.pixels[:], {frame.size, frame.size}, view.revision)
	draw_outline(state, image, UI_PANEL_BORDER_COLOR)
	draw_map_events(state, image, frame, screen_context.particle_memory, screen_context.landing_pad)
	draw_map_player(state, image, frame, screen_context.player^, colors[.Map_Player])
	draw_map_legend(state, legend, view, screen_context.generator, screen_context.player^, colors)
	ui_panel_end(state)
	if touch_row_shows(state) {
		// Painted anew next frame, since the frame changes with the zoom.
		view.zoom = clamp(view.zoom + map_touch_zoom_step(ui_touch_row(state, MAP_TOUCH_BUTTONS)), 0, MAP_ZOOM_LEVEL_COUNT - 1)
		return
	}
	hints := [?]Glyph_Hint{{.Tab_Previous, ""}, {.Tab_Next, text("hint_zoom")}, {.Back, text("hint_close")}}
	ui_glyph_bar(state, hints[:])
}

// The touch row (0137): the bumpers' zoom as buttons.
MAP_TOUCH_BUTTONS :: Touch_Buttons{.Zoom_In, .Zoom_Out, .Back}

// Zoom in shows fewer blocks per pixel, as the right bumper.
map_touch_zoom_step :: proc(button: Touch_Button) -> int {
	#partial switch button {
	case .Zoom_In:
		return -1
	case .Zoom_Out:
		return 1
	}
	return 0
}
