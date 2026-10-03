package game

// The ray against the occupied cells of the foundation frames (work item
// 0174): the ray goes into each frame's axes and walks its cells in the
// order it crosses them (the voxel walk of world_raycast.odin in integers),
// so the nearest occupied cell of any frame is found without missing a
// thin one. The field's ray (raycast_field) and this one run side by side
// and the nearer hit wins (aim_field_player_at_frames). The block frame is
// the block world's and is left out.

Frame_Raycast_Hit :: struct {
	hit:      bool,
	frame:    Frame_Id,
	cell:     World_Coordinate,
	// The face of the hit cell the ray entered through, in the frame's
	// axes, and the cell in front of it, where a snapped foundation goes.
	face:     Direction,
	adjacent: World_Coordinate,
	// Along the ray from the origin, in position units.
	distance: i64,
	occupant: Occupant,
}

// One axis of the walk: distances along the ray in position units.
Frame_Ray_Axis :: struct {
	step:              i32,
	distance_to_border: i64,
	distance_per_cell: i64,
}

FRAME_RAY_NO_BORDER :: max(i64)

frame_ray_axis :: proc(local_origin, local_direction, pitch: i64, cell: i32) -> Frame_Ray_Axis {
	switch {
	case local_direction > 0:
		border := (i64(cell) + 1) * pitch
		return {1, (border - local_origin) * UNIT_VECTOR_ONE / local_direction, pitch * UNIT_VECTOR_ONE / local_direction}
	case local_direction < 0:
		border := i64(cell) * pitch
		return {-1, (border - local_origin) * UNIT_VECTOR_ONE / local_direction, -pitch * UNIT_VECTOR_ONE / local_direction}
	}
	return {0, FRAME_RAY_NO_BORDER, FRAME_RAY_NO_BORDER}
}

nearest_frame_ray_axis :: proc(axes: [3]Frame_Ray_Axis) -> int {
	nearest := 0
	for axis in 1 ..< 3 {
		if axes[axis].distance_to_border < axes[nearest].distance_to_border {
			nearest = axis
		}
	}
	return nearest
}

// The frame's cells in a sphere: the centre of its extent and a radius
// round every cell of it, in position units.
frame_extent_sphere :: proc(frame: Frame, extent: Frame_Extent) -> (centre: World_Position, radius: i64) {
	low := frame_cell_centre(frame, extent.minimum)
	high := frame_cell_centre(frame, extent.maximum)
	centre = low + (high - low) / 2
	radius = vector_length(cast([3]i64)(high - low)) / 2 + frame_pitch_units(frame)
	return
}

frame_within_reach :: proc(frame: Frame, extent: Frame_Extent, origin: World_Position, reach: i64) -> bool {
	centre, radius := frame_extent_sphere(frame, extent)
	return vector_length(cast([3]i64)(centre - origin)) <= reach + radius
}

// direction is a unit vector, reach in position units. A cell counts
// when its occupant has every flag of required.
raycast_frame :: proc(table: ^Frame_Table, frame: Frame, origin: World_Position, direction: [3]i64, reach: i64, required: Occupant_Flags = {}) -> Frame_Raycast_Hit {
	pitch := frame_pitch_units(frame)
	local_origin := frame_local_position(frame, origin)
	local_direction := frame_local_direction(frame, direction)
	cell := world_to_frame_cell(frame, origin)
	if occupant, found := frame_occupant(table, frame.id, cell); found && required <= occupant.flags {
		return {hit = true, frame = frame.id, cell = cell, face = .Positive_Y, adjacent = cell + {0, 1, 0}, occupant = occupant}
	}
	axes: [3]Frame_Ray_Axis
	for axis in 0 ..< 3 {
		axes[axis] = frame_ray_axis(local_origin[axis], local_direction[axis], pitch, cell[axis])
	}
	for _ in 0 ..< 3 * (reach / pitch + 2) {
		axis := nearest_frame_ray_axis(axes)
		distance := axes[axis].distance_to_border
		if distance > reach {
			return {}
		}
		previous := cell
		cell[axis] += axes[axis].step
		axes[axis].distance_to_border += axes[axis].distance_per_cell
		if occupant, found := frame_occupant(table, frame.id, cell); found && required <= occupant.flags {
			return {hit = true, frame = frame.id, cell = cell, face = entered_face(axis, axes[axis].step), adjacent = previous, distance = max(distance, 0), occupant = occupant}
		}
	}
	return {}
}

// The nearest hit over every frame with a cell, in frame order; none for
// a nil table.
raycast_frames :: proc(table: ^Frame_Table, origin: World_Position, direction: [3]i64, reach: i64, required: Occupant_Flags = {}) -> Frame_Raycast_Hit {
	nearest: Frame_Raycast_Hit
	if table == nil {
		return nearest
	}
	for frame in table.frames {
		extent := table.extents[frame.id] or_else {}
		if extent.cell_count == 0 || !frame_within_reach(frame, extent, origin, reach) {
			continue
		}
		if hit := raycast_frame(table, frame, origin, direction, reach, required); hit.hit && (!nearest.hit || hit.distance < nearest.distance) {
			nearest = hit
		}
	}
	return nearest
}
