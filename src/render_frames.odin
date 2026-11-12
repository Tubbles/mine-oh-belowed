package game

import "core:slice"
import rl "shared:raylib"
import "shared:raylib/rlgl"

// The foundation frames' placeholder look (work item 0174): every
// foundation cell of a frame other than the block frame is drawn as a
// box at its frame's transform, in the flat colour of its record (the
// tier's, work item 0196, foundation_slab_color), instanced in bricks
// since 0347 (draw_field_foundations, below). The machines on the
// frames, the pod and the crafting stations among them (they ride in the
// foundations' pool, 0179 and 0196), are drawn
// by draw_entities under the same matrices (draw_entity_cells: the
// model scaled to its footprint's cells by model_transform, or a box per
// cell), since the field session draws them (0179). Floats are made here
// only; the frames themselves are integers.

// The pod's and the stations' box fallback (render_entities.odin).
FRAME_FOUNDATION_COLOR :: rl.Color{150, 146, 138, 255}
FRAME_EDGE_COLOR :: rl.Color{60, 58, 54, 255}
FRAME_GHOST_COLOR :: rl.Color{240, 240, 240, 90}
// A drawn box is this much of its cell, so neighbours show a seam.
FRAME_CELL_FILL :: 0.96

// Cell units of the frame to metres from the planet's centre: the axes
// scaled by the pitch as columns, the origin as the translation.
frame_render_matrix :: proc(frame: Frame) -> matrix[4, 4]f32 {
	pitch := f32(f64(frame.pitch_millimetres) / MILLIMETRES_PER_METRE)
	right := unit_vector_to_f32(frame.axes[FRAME_RIGHT]) * pitch
	up := unit_vector_to_f32(frame.axes[FRAME_UP]) * pitch
	forward := unit_vector_to_f32(frame.axes[FRAME_FORWARD]) * pitch
	origin := world_position_to_metres(frame.origin)
	return matrix[4, 4]f32{
		right.x, up.x, forward.x, origin.x,
		right.y, up.y, forward.y, origin.y,
		right.z, up.z, forward.z, origin.z,
		0, 0, 0, 1,
	}
}

// An entity's model transform on its frame: the frame's matrix before the
// footprint's (model_transform). The block frame's is the identity, since
// the block world draws in block coordinates.
entity_frame_matrix :: proc(entities: ^Entities, frame: Frame_Id) -> matrix[4, 4]f32 {
	if record, found := find_frame(&entities.frames, frame); found && frame != BLOCK_FRAME {
		return frame_render_matrix(record)
	}
	return 1
}

// The pitch of an entity's frame, the block frame's when the frame is
// gone, as entity_frame_matrix's identity.
entity_frame_pitch_millimetres :: proc(entities: ^Entities, frame: Frame_Id) -> int {
	if record, found := find_frame(&entities.frames, frame); found {
		return record.pitch_millimetres
	}
	return BLOCK_FRAME_PITCH_MILLIMETRES
}

draw_frame_cell :: proc(cell: World_Coordinate, color: rl.Color) {
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 0.5, f32(cell.z) + 0.5}
	rl.DrawCubeV(centre, FRAME_CELL_FILL, color)
	rl.DrawCubeWiresV(centre, FRAME_CELL_FILL, FRAME_EDGE_COLOR)
}

// The foundations' cells, instanced in bricks (work item 0347): every
// foundation cell of a frame other than the block frame is an instance of
// the unit cube scaled by FRAME_CELL_FILL at the cell's centre, in its
// frame's cells, its slab colour in the matrix's bottom row
// (instance_matrix_with_color). The cells are grouped per frame into
// bricks of FOUNDATION_BRICK_CELLS a side, each a range of one buffer with
// its box in cells. A pass tests each brick's box under its frame's
// matrix and draws a shown brick in one instanced draw under that matrix
// (draw_field_foundations): the sun's through the depth shader, the
// scene's through the model shader unlit and hazed (begin_flat_instances),
// then the edges as instanced lines over the same instances (the lines
// DrawCubeWiresV draws). The bricks are built again only when the frame
// table's revision (occupancy and pose) or the models' revision (a tier's
// new colour) moved, in prepare_field_frame before any pass, and go up
// only when their bytes changed (refresh_field_foundations). Without the
// model shader's instancing, the depth shader's or before the first
// upload, a brick's cells draw one by one (draw_frame_cell).
FOUNDATION_BRICK_CELLS :: 32

// A drawn foundation cell: its frame, its cell and its slab colour.
Foundation_Cell :: struct {
	frame: Frame_Id,
	cell:  World_Coordinate,
	color: rl.Color,
}

// A frame's cells in one brick: their range of the instances and their
// box in cells, from the lowest cell to the highest plus 1.
Foundation_Brick :: struct {
	frame:            Frame_Id,
	brick:            [3]i32,
	minimum, maximum: [3]f32,
	first, count:     int,
}

// The bricks of the frame table's revision and the models' revision they
// were built at, the cells and instances they range over, and the buffer
// those went up into (uploaded once they did).
Field_Foundations :: struct {
	built, uploaded:           bool,
	revision, models_revision: u64,
	cells:                     [dynamic]Foundation_Cell,
	bricks:                    [dynamic]Foundation_Brick,
	instances:                 [dynamic]matrix[4, 4]f32,
	buffer:                    Instance_Buffer,
}

// The unit cube to the cell's centre, scaled by FRAME_CELL_FILL, the
// colour in the bottom row.
foundation_cell_instance :: proc(cell: World_Coordinate, color: rl.Color) -> matrix[4, 4]f32 {
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 0.5, f32(cell.z) + 0.5}
	transform := matrix[4, 4]f32{
		FRAME_CELL_FILL, 0, 0, centre.x,
		0, FRAME_CELL_FILL, 0, centre.y,
		0, 0, FRAME_CELL_FILL, centre.z,
		0, 0, 0, 1,
	}
	return instance_matrix_with_color(transform, color)
}

foundation_brick_of :: proc(cell: World_Coordinate) -> [3]i32 {
	return {floor_divide(cell.x, FOUNDATION_BRICK_CELLS), floor_divide(cell.y, FOUNDATION_BRICK_CELLS), floor_divide(cell.z, FOUNDATION_BRICK_CELLS)}
}

// By frame, then brick (z, y, x), then cell (z, y, x).
foundation_cell_before :: proc(first, second: Foundation_Cell) -> bool {
	if first.frame != second.frame {
		return first.frame < second.frame
	}
	first_brick, second_brick := foundation_brick_of(first.cell), foundation_brick_of(second.cell)
	for axis in ([3]int{2, 1, 0}) {
		if first_brick[axis] != second_brick[axis] {
			return first_brick[axis] < second_brick[axis]
		}
	}
	for axis in ([3]int{2, 1, 0}) {
		if first.cell[axis] != second.cell[axis] {
			return first.cell[axis] < second.cell[axis]
		}
	}
	return false
}

// Every foundation cell on a frame of the table's records (the block
// frame's are not drawn) whose occupant is a foundation of a foundation
// machine, the pod's and the stations' cells being their models'
// (draw_entities), sorted (foundation_cell_before), a brick per run of one
// frame and brick, and an instance per cell.
build_foundation_bricks :: proc(entities: ^Entities, machines: Machine_Registry, allocator := context.temp_allocator) -> (cells: []Foundation_Cell, bricks: []Foundation_Brick, instances: []matrix[4, 4]f32) {
	known := make(map[Frame_Id]struct{}, len(entities.frames.frames), context.temp_allocator)
	for frame in entities.frames.frames {
		known[frame.id] = {}
	}
	list := make([dynamic]Foundation_Cell, allocator)
	for key, occupant in entities.frames.occupants {
		handle := entity_from_occupant(occupant.handle)
		if key.frame not_in known || handle.kind != .Foundation {
			continue
		}
		common := entity_common(entities, handle)
		if common == nil || machines.machines[common.machine].kind != .Foundation {
			continue
		}
		append(&list, Foundation_Cell{frame = key.frame, cell = key.cell, color = foundation_slab_color(machines.machines[common.machine])})
	}
	slice.sort_by(list[:], foundation_cell_before)
	brick_list := make([dynamic]Foundation_Brick, allocator)
	instances = make([]matrix[4, 4]f32, len(list), allocator)
	for cell, index in list {
		instances[index] = foundation_cell_instance(cell.cell, cell.color)
		brick := foundation_brick_of(cell.cell)
		low := [3]f32{f32(cell.cell.x), f32(cell.cell.y), f32(cell.cell.z)}
		last := len(brick_list) > 0 ? &brick_list[len(brick_list) - 1] : nil
		if last == nil || last.frame != cell.frame || last.brick != brick {
			append(&brick_list, Foundation_Brick{frame = cell.frame, brick = brick, minimum = low, maximum = low + 1, first = index, count = 1})
			continue
		}
		for axis in 0 ..< 3 {
			last.minimum[axis] = min(last.minimum[axis], low[axis])
			last.maximum[axis] = max(last.maximum[axis], low[axis] + 1)
		}
		last.count += 1
	}
	return list[:], brick_list[:], instances
}

same_bytes :: proc(first, second: $T/[]$E) -> bool {
	return slice.simple_equal(slice.to_bytes(first), slice.to_bytes(second))
}

// False while built at the frame table's revision and the models'.
// Otherwise built again: when the cells, bricks or instances differ
// bytewise from the stored ones they replace them, uploaded clears and the
// result is true; the revisions are stored either way, so a pose's change
// (the cells are in the frames' cells) uploads nothing.
refresh_field_foundations :: proc(foundations: ^Field_Foundations, entities: ^Entities, machines: Machine_Registry, models_revision: u64) -> (changed: bool) {
	if foundations.built && foundations.revision == entities.frames.revision && foundations.models_revision == models_revision {
		return false
	}
	cells, bricks, instances := build_foundation_bricks(entities, machines)
	changed = !same_bytes(cells, foundations.cells[:]) || !same_bytes(bricks, foundations.bricks[:]) || !same_bytes(instances, foundations.instances[:])
	if changed {
		clear(&foundations.cells)
		clear(&foundations.bricks)
		clear(&foundations.instances)
		append(&foundations.cells, ..cells)
		append(&foundations.bricks, ..bricks)
		append(&foundations.instances, ..instances)
		foundations.uploaded = false
	}
	foundations.built = true
	foundations.revision = entities.frames.revision
	foundations.models_revision = models_revision
	return changed
}

// Between frames, before any pass (prepare_field_frame,
// stream_planet_preview): refreshed, then up into the buffer while not
// uploaded.
update_field_foundations :: proc(foundations: ^Field_Foundations, entities: ^Entities, machines: Machine_Registry, models_revision: u64) {
	refresh_field_foundations(foundations, entities, machines, models_revision)
	if !foundations.uploaded {
		upload_instances_in_place(&foundations.buffer.buffer, &foundations.buffer.capacity, foundations.instances[:])
		foundations.uploaded = true
	}
}

// Inside BeginMode3D (or the sun's pass, shadows set): per frame, the bricks
// whose box under the frame's matrix the pass shows
// (model_frame_shows_cells), drawn under that matrix.
draw_field_foundations :: proc(foundations: ^Field_Foundations, models: Model_Renderer, frame: Model_Frame, entities: ^Entities, shadows: ^Sun_Shadow_Renderer) {
	shown := make([dynamic]Foundation_Brick, context.temp_allocator)
	start := 0
	for start < len(foundations.bricks) {
		frame_id := foundations.bricks[start].frame
		end := start + 1
		for end < len(foundations.bricks) && foundations.bricks[end].frame == frame_id {
			end += 1
		}
		transform := model_frame_entity_matrix(frame, entities, frame_id)
		clear(&shown)
		for brick in foundations.bricks[start:end] {
			if model_frame_shows_cells(frame, transform, brick.minimum, brick.maximum) {
				append(&shown, brick)
			}
		}
		if len(shown) > 0 {
			draw_foundation_bricks(foundations, models, transform, shown[:], shadows)
		}
		start = end
	}
}

// The bricks under the frame's matrix: instanced through the depth shader
// in the sun's pass, through the model shader unlit with their edges in
// the scene's, or their cells one by one.
draw_foundation_bricks :: proc(foundations: ^Field_Foundations, models: Model_Renderer, transform: matrix[4, 4]f32, bricks: []Foundation_Brick, shadows: ^Sun_Shadow_Renderer) {
	flat := transmute([16]f32)transform
	rlgl.PushMatrix()
	defer rlgl.PopMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	switch {
	case foundations.uploaded && shadows != nil && shadows.instanced_location != -1:
		set_sun_shadow_instanced(shadows^, true)
		begin_instanced_material(shadows.material)
		for brick in bricks {
			draw_mesh_instances(models.unit_cube, foundations.buffer.buffer, brick.first, brick.count)
		}
		end_instanced_material(shadows.material)
		set_sun_shadow_instanced(shadows^, false)
	case foundations.uploaded && shadows == nil && models.instancing_ready:
		begin_flat_instances(models, true)
		for brick in bricks {
			draw_mesh_instances(models.unit_cube, foundations.buffer.buffer, brick.first, brick.count)
		}
		end_flat_instances(models)
		draw_foundation_edges(foundations, models, bricks)
	case:
		for brick in bricks {
			for cell in foundations.cells[brick.first:][:brick.count] {
				draw_frame_cell(cell.cell, cell.color)
			}
		}
	}
}

// The scene's slabs' edges as instanced lines, or each cell's
// DrawCubeWiresV through the flat batch without glDrawArraysInstanced.
draw_foundation_edges :: proc(foundations: ^Field_Foundations, models: Model_Renderer, bricks: []Foundation_Brick) {
	if models.draw_lines_instanced == nil {
		begin_flat_batch(models)
		for brick in bricks {
			for cell in foundations.cells[brick.first:][:brick.count] {
				rl.DrawCubeWiresV({f32(cell.cell.x) + 0.5, f32(cell.cell.y) + 0.5, f32(cell.cell.z) + 0.5}, FRAME_CELL_FILL, FRAME_EDGE_COLOR)
			}
		}
		end_flat_batch(models)
		return
	}
	begin_flat_instances(models, false)
	for brick in bricks {
		draw_mesh_line_instances(models.cube_edges, foundations.buffer.buffer, brick.first, brick.count, models.draw_lines_instanced)
	}
	end_flat_instances(models)
}

// With the field renderer, between frames.
release_field_foundations :: proc(foundations: ^Field_Foundations) {
	delete(foundations.cells)
	delete(foundations.bricks)
	delete(foundations.instances)
	release_instance_buffer(&foundations.buffer)
	foundations^ = {}
}

// A foundation's slab in its record's colour, opaque.
foundation_slab_color :: proc(machine: Machine) -> rl.Color {
	return rl.Color{machine.color[0], machine.color[1], machine.color[2], 255}
}

// The ghost's colour: the block ghost's refused colour when the
// placement would be refused.
frame_ghost_color :: proc(refusal: Field_Edit_Refusal) -> rl.Color {
	return refusal == .None ? FRAME_GHOST_COLOR : GHOST_INVALID_COLOR
}

// The placement editor's outline (0215): white, red where the placement
// would be refused, lifted off the cells' floor so it does not flicker
// into the ground, its walls and rims this thick and the chevron's length
// this share of the shorter side. Static: nothing pulses (DESIGN.md, No
// perceivable repetition). The outline is low walls a cell tall (0219),
// see through under an opaque rim: the flat strips of 0215 sank into a
// slope (user, 2026-10-04). A bare placement's corners read within the
// flatness limit (250 mm) of its centre, where the outline's floor
// stands, so at the shipped 500 mm pitch at least 260 mm of wall and the
// whole rim show at the worst corner.
PLACEMENT_OUTLINE_COLOR :: rl.Color{240, 240, 240, 220}
PLACEMENT_OUTLINE_REFUSED_COLOR :: rl.Color{230, 60, 50, 220}
PLACEMENT_OUTLINE_LIFT_CELLS :: 0.02
PLACEMENT_OUTLINE_WIDTH_CELLS :: 0.1
// The walls' full height, the rim included, and the rim's.
PLACEMENT_OUTLINE_HEIGHT_CELLS :: 1.0
PLACEMENT_OUTLINE_RIM_CELLS :: 0.04
// The walls' alpha, against the colour's 220.
PLACEMENT_OUTLINE_WALL_ALPHA :: 70
PLACEMENT_OUTLINE_ARROW_SHARE :: 0.6

placement_outline_color :: proc(refusal: Field_Edit_Refusal) -> rl.Color {
	return refusal == .None ? PLACEMENT_OUTLINE_COLOR : PLACEMENT_OUTLINE_REFUSED_COLOR
}

// The model's +x front turned as model_transform turns it.
machine_front_direction :: proc(rotation: u8) -> [3]f32 {
	fronts := [4][3]f32{{1, 0, 0}, {0, 0, 1}, {-1, 0, 0}, {0, 0, -1}}
	return fronts[rotation % 4]
}

// A chevron scaled about centre.
scaled_ghost_chevron :: proc(chevron: Ghost_Chevron, centre: [3]f32, scale: f32) -> Ghost_Chevron {
	result := chevron
	for &triangle in result {
		for &corner in triangle {
			corner = centre + (corner - centre) * scale
		}
	}
	return result
}

// One box of the outline in the frame's cells; rim is the opaque top.
Footprint_Outline_Box :: struct {
	centre: [3]f32,
	size:   [3]f32,
	rim:    bool,
}

// The outline of the rectangle low to high (exclusive) of the frame's
// cells: four walls just inside its edges, from the low row's floor
// lifted by PLACEMENT_OUTLINE_LIFT_CELLS up to under the rim (entries 0
// to 3), and the four rims over them (entries 4 to 7).
footprint_outline_boxes :: proc(low, high: World_Coordinate) -> [8]Footprint_Outline_Box {
	floor := f32(low.y) + PLACEMENT_OUTLINE_LIFT_CELLS
	wall_top := floor + PLACEMENT_OUTLINE_HEIGHT_CELLS - PLACEMENT_OUTLINE_RIM_CELLS
	boxes: [8]Footprint_Outline_Box
	for edge, index in footprint_outline_edges(low, high) {
		boxes[index] = {{edge.centre.x, (floor + wall_top) / 2, edge.centre.y}, {edge.size.x, wall_top - floor, edge.size.y}, false}
		boxes[index + 4] = {{edge.centre.x, wall_top + PLACEMENT_OUTLINE_RIM_CELLS / 2, edge.centre.y}, {edge.size.x, PLACEMENT_OUTLINE_RIM_CELLS, edge.size.y}, true}
	}
	return boxes
}

// An edge's strip on the xz plane: its centre and its size.
Footprint_Outline_Edge :: struct {
	centre: [2]f32,
	size:   [2]f32,
}

// The four strips just inside the rectangle's edges, as thick as
// PLACEMENT_OUTLINE_WIDTH_CELLS.
footprint_outline_edges :: proc(low, high: World_Coordinate) -> [4]Footprint_Outline_Edge {
	low_x, low_z, high_x, high_z := f32(low.x), f32(low.z), f32(high.x), f32(high.z)
	width, depth := high_x - low_x, high_z - low_z
	thickness := f32(PLACEMENT_OUTLINE_WIDTH_CELLS)
	half := thickness / 2
	return {
		{{low_x + width / 2, low_z + half}, {width, thickness}},
		{{low_x + width / 2, high_z - half}, {width, thickness}},
		{{low_x + half, low_z + depth / 2}, {thickness, depth}},
		{{high_x - half, low_z + depth / 2}, {thickness, depth}},
	}
}

// The chevron's centre: the footprint's xz centre at the rims' top.
footprint_outline_arrow_centre :: proc(low, high: World_Coordinate) -> [3]f32 {
	floor := f32(low.y) + PLACEMENT_OUTLINE_LIFT_CELLS
	return {(f32(low.x) + f32(high.x)) / 2, floor + PLACEMENT_OUTLINE_HEIGHT_CELLS, (f32(low.z) + f32(high.z)) / 2}
}

// The see-through walls' colour.
placement_outline_wall_color :: proc(color: rl.Color) -> rl.Color {
	return {color.r, color.g, color.b, PLACEMENT_OUTLINE_WALL_ALPHA}
}

// The outline of the rectangle low to high (exclusive) of the frame's
// cells as low walls (footprint_outline_boxes): the walls see through,
// drawn without writing depth so the far ones show through the near ones,
// then the opaque rims, and with arrow a chevron along the front at the
// rims' top, as long as PLACEMENT_OUTLINE_ARROW_SHARE of the shorter side.
draw_footprint_outline :: proc(frame: Frame, low, high: World_Coordinate, rotation: u8, arrow: bool, color: rl.Color) {
	flat := transmute([16]f32)frame_render_matrix(frame)
	rlgl.PushMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	defer rlgl.PopMatrix()
	boxes := footprint_outline_boxes(low, high)
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthMask()
	for box in boxes[:4] {
		rl.DrawCubeV(box.centre, box.size, placement_outline_wall_color(color))
	}
	rlgl.DrawRenderBatchActive()
	rlgl.EnableDepthMask()
	for box in boxes[4:] {
		rl.DrawCubeV(box.centre, box.size, color)
	}
	if !arrow {
		return
	}
	front := machine_front_direction(rotation)
	centre := footprint_outline_arrow_centre(low, high)
	length := PLACEMENT_OUTLINE_ARROW_SHARE * min(f32(high.x - low.x), f32(high.z - low.z))
	chevron := ghost_chevron_triangles(centre - front * length / 2, centre + front * length / 2, {front.z, 0, -front.x})
	draw_ghost_chevron(scaled_ghost_chevron(chevron, centre, length / GHOST_CHEVRON_LENGTH), color)
}

// Where Place would put a foundation or a machine, see-through.
draw_frame_ghost :: proc(frame: Frame, cell: World_Coordinate, color: rl.Color) {
	transform := frame_render_matrix(frame)
	flat := transmute([16]f32)transform
	rlgl.PushMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 0.5, f32(cell.z) + 0.5}
	rl.DrawCubeV(centre, 1, color)
	rl.DrawCubeWiresV(centre, 1, FRAME_EDGE_COLOR)
	rlgl.PopMatrix()
}
