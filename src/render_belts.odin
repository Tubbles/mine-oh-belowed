package game

import "core:slice"
import rl "vendor:raylib"

// Belts: one quad mesh per shape, built once with its v texture axis
// along the flow, so one scroll offset (the distance items travelled)
// animates every shape by rewriting four texture coordinates per mesh,
// once per belt speed per frame, before the belts of that speed are
// drawn. Items are small cubes coloured like their placeholder icon,
// drawn one DrawCube each (no instancing yet), at most eight per block.
// A splitter is the flat surface on both halves inside a wire frame, with
// an arrow along its direction.

BELT_SURFACE_HEIGHT :: 0.03
BELT_ITEM_SIZE :: 0.2
BELT_LANE_OFFSET :: 0.25
// Items on a lift ride in front of its surface, towards the entry side.
BELT_LIFT_ITEM_INSET :: 0.15
BELT_TEXTURE_SIZE :: 16
BELT_STRIPES_PER_BLOCK :: 4
BELT_BASE_COLOR :: rl.Color{58, 58, 64, 255}
BELT_STRIPE_COLOR :: rl.Color{104, 104, 112, 255}
BELT_EDGE_COLOR :: rl.Color{200, 160, 40, 255}
BELT_GHOST_ARROW_COLOR :: rl.Color{255, 255, 255, 200}
BELT_FAST_TINT :: rl.Color{255, 140, 130, 255}
SPLITTER_FRAME_COLOR :: rl.Color{200, 160, 40, 255}
SPLITTER_ARROW_COLOR :: rl.Color{240, 220, 80, 255}
SPLITTER_FRAME_HEIGHT :: 0.4
SPLITTER_ARROW_HEIGHT :: 0.42

// Back left, back right, front right, front left, with back at v 0.
BELT_QUAD_TEXCOORDS :: [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
// Both windings, so the quad shows from either side.
BELT_QUAD_INDICES :: [12]u16{0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2}

Belt_Renderer :: struct {
	ready:   bool,
	texture: rl.Texture2D,
	models:  [Belt_Shape]rl.Model,
}

// The quad of a shape pointing +x in a cell whose bottom centre is the origin.
belt_quad_corners :: proc(shape: Belt_Shape) -> [4][3]f32 {
	back_height, front_height := f32(BELT_SURFACE_HEIGHT), f32(BELT_SURFACE_HEIGHT)
	back_x, front_x := f32(-0.5), f32(0.5)
	switch shape {
	case .Flat:
	case .Ramp_Up:
		front_height += 1
	case .Ramp_Down:
		back_height += 1
	case .Lift_Up:
		back_x, front_x, back_height, front_height = 0, 0, 0, 1
	case .Lift_Down:
		back_x, front_x, back_height, front_height = 0, 0, 1, 0
	}
	return {{back_x, back_height, -0.5}, {back_x, back_height, 0.5}, {front_x, front_height, 0.5}, {front_x, front_height, -0.5}}
}

make_belt_texture :: proc() -> rl.Texture2D {
	image := rl.GenImageColor(BELT_TEXTURE_SIZE, BELT_TEXTURE_SIZE, BELT_BASE_COLOR)
	defer rl.UnloadImage(image)
	for y in i32(0) ..< BELT_TEXTURE_SIZE {
		for x in i32(0) ..< BELT_TEXTURE_SIZE {
			switch {
			case x == 0 || x == BELT_TEXTURE_SIZE - 1:
				rl.ImageDrawPixel(&image, x, y, BELT_EDGE_COLOR)
			case y % (BELT_TEXTURE_SIZE / BELT_STRIPES_PER_BLOCK) == 0:
				rl.ImageDrawPixel(&image, x, y, BELT_STRIPE_COLOR)
			}
		}
	}
	texture := rl.LoadTextureFromImage(image)
	rl.SetTextureWrap(texture, .REPEAT)
	return texture
}

make_belt_model :: proc(shape: Belt_Shape, texture: rl.Texture2D) -> rl.Model {
	corners := belt_quad_corners(shape)
	texcoords := BELT_QUAD_TEXCOORDS
	indices := BELT_QUAD_INDICES
	mesh := rl.Mesh {
		vertexCount   = 4,
		triangleCount = 4,
		vertices      = cast([^]f32)clone_for_raylib(corners[:]),
		texcoords     = cast([^]f32)clone_for_raylib(texcoords[:]),
		indices       = clone_for_raylib(indices[:]),
	}
	rl.UploadMesh(&mesh, true)
	model := rl.LoadModelFromMesh(mesh)
	rl.SetMaterialTexture(&model.materials[0], .ALBEDO, texture)
	return model
}

// Needs the window. Without a belt machine in the data there is nothing to draw.
init_belt_renderer :: proc(machines: Machine_Registry) -> Belt_Renderer {
	if find_belt_machine(machines, .Flat) == NO_MACHINE {
		return {}
	}
	renderer := Belt_Renderer{ready = true, texture = make_belt_texture()}
	for shape in Belt_Shape {
		renderer.models[shape] = make_belt_model(shape, renderer.texture)
	}
	return renderer
}

destroy_belt_renderer :: proc(renderer: ^Belt_Renderer) {
	if !renderer.ready {
		return
	}
	for model in renderer.models {
		rl.UnloadModel(model)
	}
	rl.UnloadTexture(renderer.texture)
}

// How far the surface has moved, in blocks, wrapped to one block.
belt_scroll_offset :: proc(tick: u64, alpha: f32, units_per_tick: u32) -> f32 {
	units := (tick % BELT_UNITS_PER_BLOCK) * u64(units_per_tick) % BELT_UNITS_PER_BLOCK
	return (f32(units) + alpha * f32(units_per_tick)) / BELT_UNITS_PER_BLOCK
}

scroll_belt_models :: proc(renderer: ^Belt_Renderer, offset: f32) {
	texcoords := BELT_QUAD_TEXCOORDS
	for &corner in texcoords {
		corner.y -= offset
	}
	for model in renderer.models {
		rl.UpdateMeshBuffer(model.meshes[0], 1, &texcoords, size_of(texcoords), 0)
	}
}

belt_direction_vector :: proc(direction: u8) -> [3]f32 {
	offset := belt_direction_offset(direction)
	return {f32(offset.x), f32(offset.y), f32(offset.z)}
}

// Where an item offset units into a belt block is drawn (bottom centre
// of the cube). A curve bends the lane from its entry side to its exit.
belt_item_point :: proc(belt: Belt, lane: Belt_Lane, offset: i32) -> [3]f32 {
	along := f32(offset) / BELT_UNITS_PER_BLOCK
	centre := [3]f32{f32(belt.origin.x) + 0.5, f32(belt.origin.y), f32(belt.origin.z) + 0.5}
	side := lane == .Right ? f32(BELT_LANE_OFFSET) : -f32(BELT_LANE_OFFSET)
	forward := belt_direction_vector(belt.rotation)
	right := belt_direction_vector(turn_right(belt.rotation)) * side
	surface := [3]f32{0, BELT_SURFACE_HEIGHT, 0}
	switch belt.shape {
	case .Flat:
		if belt.entry_direction != belt.rotation {
			return curve_item_point(belt, centre, right, side, along) + surface
		}
		return centre + forward * (along - 0.5) + right + surface
	case .Ramp_Up:
		return centre + forward * (along - 0.5) + right + surface + {0, along, 0}
	case .Ramp_Down:
		return centre + forward * (along - 0.5) + right + surface + {0, 1 - along, 0}
	case .Lift_Up:
		return centre + right - forward * BELT_LIFT_ITEM_INSET + {0, along, 0}
	case .Lift_Down:
		return centre + right - forward * BELT_LIFT_ITEM_INSET + {0, 1 - along, 0}
	}
	return centre
}

// A quadratic curve from the middle of the entry edge through the lane's
// corner to the middle of the exit edge.
curve_item_point :: proc(belt: Belt, centre, right: [3]f32, side, along: f32) -> [3]f32 {
	entry := belt_direction_vector(belt.entry_direction)
	entry_right := belt_direction_vector(turn_right(belt.entry_direction)) * side
	start := centre - entry * 0.5 + entry_right
	corner := centre + entry_right + right
	finish := centre + belt_direction_vector(belt.rotation) * 0.5 + right
	rest := 1 - along
	return start * (rest * rest) + corner * (2 * rest * along) + finish * (along * along)
}

item_cube_color :: proc(items: Item_Registry, item: Item_Id) -> rl.Color {
	if int(item) >= len(items.items) {
		return rl.MAGENTA
	}
	color := item_category_colors[items.items[item].category]
	return rl.Color{color.r, color.g, color.b, color.a}
}

// The belt of a line block, or the flat belt standing in for the half of
// a splitter's output line.
line_block_belt :: proc(entities: ^Entities, line: Belt_Line, block: i32) -> (belt: Belt, found: bool) {
	handle := line.belts[block]
	if handle.kind == .Splitter {
		splitter := pool_get(&entities.splitters, handle)
		if splitter == nil {
			return {}, false
		}
		return splitter_half_belt(splitter^, line.side), true
	}
	pointer := pool_get(&entities.belts, handle)
	if pointer == nil {
		return {}, false
	}
	return pointer^, true
}

draw_belt_line_items :: proc(world: ^World, items: Item_Registry, line: Belt_Line) {
	drawn := make([]u8, len(line.belts), context.temp_allocator)
	for lane in Belt_Lane {
		for entry in line.lanes[lane] {
			block := entry.position / BELT_UNITS_PER_BLOCK
			if drawn[block] >= MAXIMUM_BELT_ITEMS_DRAWN_PER_BLOCK {
				continue
			}
			belt, found := line_block_belt(&world.entities, line, block)
			if !found {
				continue
			}
			drawn[block] += 1
			point := belt_item_point(belt, lane, entry.position % BELT_UNITS_PER_BLOCK)
			rl.DrawCube(point + {0, BELT_ITEM_SIZE / 2, 0}, BELT_ITEM_SIZE, BELT_ITEM_SIZE, BELT_ITEM_SIZE, item_cube_color(items, entry.item))
		}
	}
}

// The distinct belt speeds of the data, slowest first.
belt_speeds :: proc(machines: Machine_Registry) -> []u32 {
	speeds := make([dynamic]u32, context.temp_allocator)
	for machine in machines.machines {
		if machine.kind == .Belt && !slice.contains(speeds[:], machine.belt_speed_units_per_second) {
			append(&speeds, machine.belt_speed_units_per_second)
		}
	}
	slice.sort(speeds[:])
	return speeds[:]
}

// Faster tiers are tinted so a fast belt reads apart from a slow one.
belt_tier_tint :: proc(tier: int) -> rl.Color {
	return tier == 0 ? rl.WHITE : BELT_FAST_TINT
}

// The meshes are shared, so the belts of each speed are drawn after the
// texture is scrolled for that speed. A splitter scrolls like the slowest
// belt.
draw_belt_surfaces :: proc(renderer: ^Belt_Renderer, world: ^World, machines: Machine_Registry, tick: u64, alpha: f32, tick_rate: int) {
	for speed, tier in belt_speeds(machines) {
		scroll_belt_models(renderer, belt_scroll_offset(tick, alpha, speed / u32(max(tick_rate, 1))))
		for belt in world.entities.belts.entries {
			if belt.alive && belt_speed(machines, belt) == speed {
				position := [3]f32{f32(belt.origin.x) + 0.5, f32(belt.origin.y), f32(belt.origin.z) + 0.5}
				rl.DrawModelEx(renderer.models[belt.shape], position, {0, 1, 0}, -90 * f32(belt.rotation), {1, 1, 1}, belt_tier_tint(tier))
			}
		}
		if tier == 0 {
			for splitter in world.entities.splitters.entries {
				if splitter.alive {
					draw_splitter(renderer, splitter)
				}
			}
		}
	}
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_belts :: proc(renderer: ^Belt_Renderer, world: ^World, items: Item_Registry, machines: Machine_Registry, tick: u64, alpha: f32, tick_rate: int) {
	if !renderer.ready {
		return
	}
	draw_belt_surfaces(renderer, world, machines, tick, alpha, tick_rate)
	for line in world.entities.belt_network.lines {
		draw_belt_line_items(world, items, line)
	}
}

draw_splitter :: proc(renderer: ^Belt_Renderer, splitter: Splitter) {
	for side in Splitter_Side {
		cell := splitter_half_cell(splitter.origin, splitter.rotation, side)
		position := [3]f32{f32(cell.x) + 0.5, f32(cell.y), f32(cell.z) + 0.5}
		rl.DrawModelEx(renderer.models[.Flat], position, {0, 1, 0}, -90 * f32(splitter.rotation), {1, 1, 1}, rl.WHITE)
	}
	centre := box_centre(splitter.origin, splitter.size)
	centre.y = f32(splitter.origin.y) + SPLITTER_FRAME_HEIGHT / 2
	extent := [3]f32{f32(splitter.size.x), SPLITTER_FRAME_HEIGHT, f32(splitter.size.z)}
	rl.DrawCubeWiresV(centre, extent, SPLITTER_FRAME_COLOR)
	draw_splitter_arrow(splitter.origin, splitter.size, splitter.rotation, SPLITTER_ARROW_COLOR)
}

// Across the middle of the footprint from its back edge to its front
// edge, with a small cube at the front.
draw_splitter_arrow :: proc(origin: World_Coordinate, size: [3]i32, rotation: u8, color: rl.Color) {
	centre := box_centre(origin, size)
	centre.y = f32(origin.y) + SPLITTER_ARROW_HEIGHT
	forward := belt_direction_vector(rotation)
	rl.DrawLine3D(centre - forward * 0.5, centre + forward * 0.5, color)
	rl.DrawCubeV(centre + forward * 0.45, {0.1, 0.1, 0.1}, color)
}

// The ghost of a belt: a thin slab and an arrow along the flow.
draw_belt_ghost :: proc(placement: Placement, color: rl.Color) {
	ghost := Belt{common = Entity_Common{origin = placement.origin, rotation = placement.rotation}, shape = placement.belt_shape, entry_direction = placement.rotation}
	start := belt_item_point(ghost, .Left, 0) + belt_item_point(ghost, .Right, 0)
	finish := belt_item_point(ghost, .Left, BELT_UNITS_PER_BLOCK - 1) + belt_item_point(ghost, .Right, BELT_UNITS_PER_BLOCK - 1)
	rl.DrawCubeV(block_centre(placement.origin), {1, 1, 1}, color)
	rl.DrawLine3D(start / 2, finish / 2, BELT_GHOST_ARROW_COLOR)
}
