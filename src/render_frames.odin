package game

import rl "shared:raylib"
import "shared:raylib/rlgl"

// The foundation frames' placeholder look (work item 0174): every
// foundation cell of a frame other than the block frame is drawn as a
// box at its frame's transform, in the flat colour of its record (the
// tier's, work item 0196, foundation_slab_color). The machines on the
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

draw_frame_cell :: proc(cell: World_Coordinate, color: rl.Color) {
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 0.5, f32(cell.z) + 0.5}
	rl.DrawCubeV(centre, FRAME_CELL_FILL, color)
	rl.DrawCubeWiresV(centre, FRAME_CELL_FILL, FRAME_EDGE_COLOR)
}

// Inside BeginMode3D. One pass over the occupied cells, each foundation
// under its frame's matrix (made once per frame), so the cost follows the
// cells and not the cells times the frames.
draw_frames :: proc(entities: ^Entities, machines: Machine_Registry) {
	matrices := make(map[Frame_Id][16]f32, len(entities.frames.frames), context.temp_allocator)
	for frame in entities.frames.frames {
		matrices[frame.id] = transmute([16]f32)frame_render_matrix(frame)
	}
	for key, occupant in entities.frames.occupants {
		flat, found := matrices[key.frame]
		handle := entity_from_occupant(occupant.handle)
		if !found || handle.kind != .Foundation {
			continue
		}
		// The pod's and the stations' cells are their models' (draw_entities).
		common := entity_common(entities, handle)
		if common == nil || machines.machines[common.machine].kind != .Foundation {
			continue
		}
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
		draw_frame_cell(key.cell, foundation_slab_color(machines.machines[common.machine]))
		rlgl.PopMatrix()
	}
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
