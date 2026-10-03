package game

import rl "shared:raylib"
import "shared:raylib/rlgl"

// The foundation frames' placeholder look (work item 0174): every occupied
// cell of a frame other than the block frame is drawn as a box at its
// frame's transform, a slab of stone grey for a foundation and a box of
// orange for a machine, so the planet preview and the slice see frames
// before machines have meshes at their real sizes (0179). Floats are made
// here only; the frames themselves are integers.

FRAME_FOUNDATION_COLOR :: rl.Color{150, 146, 138, 255}
FRAME_MACHINE_COLOR :: rl.Color{214, 128, 52, 255}
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

// Inside BeginMode3D. One pass over the occupied cells, each under its
// frame's matrix (made once per frame), so the cost follows the cells and
// not the cells times the frames.
draw_frames :: proc(entities: ^Entities) {
	matrices := make(map[Frame_Id][16]f32, len(entities.frames.frames), context.temp_allocator)
	for frame in entities.frames.frames {
		matrices[frame.id] = transmute([16]f32)frame_render_matrix(frame)
	}
	for key, occupant in entities.frames.occupants {
		flat, found := matrices[key.frame]
		if !found {
			continue
		}
		rlgl.PushMatrix()
		rlgl.MultMatrixf(raw_data(flat[:]))
		foundation := entity_from_occupant(occupant.handle).kind == .Foundation
		draw_frame_cell(key.cell, foundation ? FRAME_FOUNDATION_COLOR : FRAME_MACHINE_COLOR)
		rlgl.PopMatrix()
	}
}

// Where Place would put a foundation, see-through.
draw_frame_ghost :: proc(frame: Frame, cell: World_Coordinate) {
	transform := frame_render_matrix(frame)
	flat := transmute([16]f32)transform
	rlgl.PushMatrix()
	rlgl.MultMatrixf(raw_data(flat[:]))
	centre := [3]f32{f32(cell.x) + 0.5, f32(cell.y) + 0.5, f32(cell.z) + 0.5}
	rl.DrawCubeV(centre, 1, FRAME_GHOST_COLOR)
	rl.DrawCubeWiresV(centre, 1, FRAME_EDGE_COLOR)
	rlgl.PopMatrix()
}
