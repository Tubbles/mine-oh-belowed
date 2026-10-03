package game

import rl "shared:raylib"
import "shared:raylib/rlgl"

// The foundation frames' placeholder look (work item 0174): every
// foundation cell of a frame other than the block frame is drawn as a
// stone grey box at its frame's transform. The machines on the frames,
// the pod among them (it rides in the foundations' pool, 0179), are drawn
// by draw_entities under the same matrices (draw_entity_cells: the
// model scaled to its footprint's cells by model_transform, or a box per
// cell), since the field session draws them (0179). Floats are made here
// only; the frames themselves are integers.

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
		// The pod's cells are its model's (draw_entities).
		if common := entity_common(entities, handle); common == nil || machines.machines[common.machine].kind != .Foundation {
			continue
		}
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
		draw_frame_cell(key.cell, FRAME_FOUNDATION_COLOR)
		rlgl.PopMatrix()
	}
}

// The ghost's colour: the block ghost's refused colour when the
// placement would be refused.
frame_ghost_color :: proc(refusal: Field_Edit_Refusal) -> rl.Color {
	return refusal == .None ? FRAME_GHOST_COLOR : GHOST_INVALID_COLOR
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
