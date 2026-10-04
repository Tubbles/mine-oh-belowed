package game

// The foundation frames as solid ground for the field player (work item
// 0174): every solid occupied cell is a box in its frame's axes, so the
// capsule's probe, the drop and the ground ray see a foundation pad as
// they see the field. The player's collision takes the nearer of the
// field and the frames (field_solid_probe, field_solid_raycast). A
// machine with collision volumes collides by them (frame_probe,
// raycast_frames_and_bodies, 0230); its cells are Shaped and skipped
// here. Integer only, as the field's probe.

// From a point in a frame's axes (position units from its origin) to a
// cell's box. Outside: the length of the offset from the box's nearest
// point and its direction. Inside: minus the depth to the nearest face
// and that face's outward axis.
cell_box_distance :: proc(local: [3]i64, cell: World_Coordinate, pitch: i64) -> (distance: i64, normal: [3]i64) {
	low := [3]i64{i64(cell.x), i64(cell.y), i64(cell.z)} * pitch
	return box_signed_distance(local, low, low + pitch)
}

// A cell the field player collides with: solid and not Shaped (a
// machine with collision volumes collides by its body instead, 0230).
frame_cell_collides :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) -> bool {
	occupant, found := frame_occupant(table, frame, cell)
	return found && .Solid in occupant.flags && .Shaped not_in occupant.flags
}

// A direction in a frame's axes as a world direction.
frame_world_direction :: proc(frame: Frame, local: [3]i64) -> [3]i64 {
	return fixed_scale(frame.axes[FRAME_RIGHT], local.x) + fixed_scale(frame.axes[FRAME_UP], local.y) + fixed_scale(frame.axes[FRAME_FORWARD], local.z)
}

// The nearest solid cell of one frame within reach, visiting only the
// cells of the frame's extent inside the reach's box.
frame_solid_probe_in :: proc(table: ^Frame_Table, frame: Frame, extent: Frame_Extent, position: World_Position, reach: i64) -> Field_Surface_Probe {
	pitch := frame_pitch_units(frame)
	local := frame_local_position(frame, position)
	low, high: [3]i32
	for axis in 0 ..< 3 {
		low[axis] = max(i32(floor_divide_i64(local[axis] - reach, pitch)), extent.minimum[axis])
		high[axis] = min(i32(floor_divide_i64(local[axis] + reach, pitch)), extent.maximum[axis])
	}
	nearest := Field_Surface_Probe{distance = reach}
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				cell := World_Coordinate{x, y, z}
				if !frame_cell_collides(table, frame.id, cell) {
					continue
				}
				if distance, normal := cell_box_distance(local, cell, pitch); distance < nearest.distance {
					nearest = {distance = distance, normal = frame_world_direction(frame, normal), found = true}
				}
			}
		}
	}
	return nearest
}

// The nearest solid cell of any frame within reach of position, and the
// pitch of its frame; not found (and the reach as the distance) when
// there is none or the table is nil.
frame_solid_probe :: proc(table: ^Frame_Table, position: World_Position, reach: i64) -> (nearest: Field_Surface_Probe, pitch: i64) {
	nearest.distance = reach
	if table == nil {
		return
	}
	for frame in table.frames {
		extent := table.extents[frame.id] or_else {}
		if extent.cell_count == 0 || !frame_within_reach(frame, extent, position, reach) {
			continue
		}
		if probe := frame_solid_probe_in(table, frame, extent, position, reach); probe.found && probe.distance < nearest.distance {
			nearest, pitch = probe, frame_pitch_units(frame)
		}
	}
	return
}

// The frames' probe: the nearest solid cell (frame_solid_probe), or a
// body's volume (frame_body_probe) where strictly nearer.
frame_probe :: proc(table: ^Frame_Table, position: World_Position, reach: i64) -> Field_Surface_Probe {
	cells, _ := frame_solid_probe(table, position, reach)
	if bodies := frame_body_probe(table, position, reach); bodies.found && bodies.distance < cells.distance {
		return bodies
	}
	return cells
}

// The field's probe, or the frames' where a solid cell or a volume within
// frame_reach is nearer.
field_solid_probe :: proc(world: ^Field_World, frames: ^Frame_Table, spacing_millimetres: int, position: World_Position, frame_reach: i64) -> Field_Surface_Probe {
	probe := field_surface_probe(world, spacing_millimetres, position)
	if cells := frame_probe(frames, position, frame_reach); cells.found && cells.distance < probe.distance {
		return cells
	}
	return probe
}

// The field's ray, or the first solid frame cell or volume where that is
// nearer, with the entered face's or the volume's normal.
field_solid_raycast :: proc(world: ^Field_World, frames: ^Frame_Table, spacing_millimetres: int, origin: World_Position, direction: [3]i64, reach: i64) -> Field_Raycast_Hit {
	hit := raycast_field(world, spacing_millimetres, origin, direction, reach)
	cells, normal := raycast_frames_and_bodies(frames, origin, direction, reach, {.Solid})
	if !cells.hit || (hit.hit && hit.distance <= cells.distance) {
		return hit
	}
	position := field_ray_point(origin, direction, cells.distance)
	return Field_Raycast_Hit{hit = true, position = position, normal = normal, sample = nearest_field_sample(position, spacing_millimetres), distance = cells.distance}
}
