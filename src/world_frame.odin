package game

// Foundation frames (work item 0174, doc/architecture.md, Frames): a
// frame is a local grid of cells with an origin, three orthonormal axes
// (right, up, forward) and a pitch. Cell (x, y, z) spans x to x + 1 along
// the right axis, y to y + 1 along the up and z to z + 1 along the
// forward, in pitches from the origin, so the origin is the minimum corner
// of cell (0, 0, 0). A frame never re-tangents and two frames never merge.
//
// The block world is frame 0 (BLOCK_FRAME): identity axes, origin zero,
// 1000 mm cells, present in every world without a record, so a block
// coordinate is a cell of frame 0.
//
// The occupant index says what stands in a cell of a frame: an opaque
// handle the world never interprets (the simulation packs its entity
// handle into it) and the flags the world reads (the raycast, the water).
// It is derived from the entities and rebuilt on load, never saved; the
// frame records are saved (save_state.odin).
//
// Integer only: the axes are unit vectors in UNIT_VECTOR_ONE, positions
// in 1/POSITION_UNITS_PER_METRE metre, so every machine of a lockstep
// session agrees on every cell's world position.

Frame_Id :: distinct u32

BLOCK_FRAME :: Frame_Id(0)
BLOCK_FRAME_PITCH_MILLIMETRES :: 1000

// The yaw of a frame round its up, in steps of a twenty fourth of a turn
// (15 degrees). 65536 angle units do not divide by 24, so the angle of a
// step is rounded (frame_yaw_angle).
FRAME_YAW_STEPS :: 24

// The axes' order in Frame.axes, which is also the order of a cell's
// components.
FRAME_RIGHT :: 0
FRAME_UP :: 1
FRAME_FORWARD :: 2

// The planet's north, which yaw step 0 faces where it is not along the
// up; at the poles the fallback.
FRAME_NORTH :: [3]i64{0, UNIT_VECTOR_ONE, 0}
FRAME_NORTH_FALLBACK :: [3]i64{0, 0, UNIT_VECTOR_ONE}

// What a frame stores and a save writes.
Frame :: struct {
	id:                Frame_Id,
	origin:            World_Position,
	// Right, up and forward, each of length UNIT_VECTOR_ONE.
	axes:              [3][3]i64,
	pitch_millimetres: int,
}

Frame_Cell :: struct {
	frame: Frame_Id,
	cell:  World_Coordinate,
}

// Packed by the simulation (entity_occupant_handle); zero is no occupant.
Occupant_Handle :: distinct u64

NO_OCCUPANT :: Occupant_Handle(0)

Occupant_Flag :: enum u8 {
	// Something stands on it and the player does not walk into it.
	Solid,
	// Kept for the field light (0173); the block light treats occupied
	// cells as air as before.
	Blocks_Light,
	// Water does not flow into the cell.
	Blocks_Water,
}

Occupant_Flags :: bit_set[Occupant_Flag;u8]

Occupant :: struct {
	handle: Occupant_Handle,
	flags:  Occupant_Flags,
}

// The occupied cells of a frame and the box round every cell occupied
// since the last rebuild (it grows, never shrinks), which the frame
// raycast tests before it walks.
Frame_Extent :: struct {
	cell_count: int,
	minimum:    World_Coordinate,
	maximum:    World_Coordinate,
}

// frames holds every frame but the block frame, in rising id order.
// last_id is the counter of ids handed out, saved with the frames.
Frame_Table :: struct {
	frames:    [dynamic]Frame,
	last_id:   u32,
	occupants: map[Frame_Cell]Occupant,
	extents:   map[Frame_Id]Frame_Extent,
}

destroy_frame_table :: proc(table: ^Frame_Table) {
	delete(table.frames)
	delete(table.occupants)
	delete(table.extents)
	table^ = {}
}

block_frame :: proc() -> Frame {
	return Frame {
		id = BLOCK_FRAME,
		axes = {{UNIT_VECTOR_ONE, 0, 0}, {0, UNIT_VECTOR_ONE, 0}, {0, 0, UNIT_VECTOR_ONE}},
		pitch_millimetres = BLOCK_FRAME_PITCH_MILLIMETRES,
	}
}

find_frame :: proc(table: ^Frame_Table, id: Frame_Id) -> (frame: Frame, found: bool) {
	if id == BLOCK_FRAME {
		return block_frame(), true
	}
	for candidate in table.frames {
		if candidate.id == id {
			return candidate, true
		}
	}
	return {}, false
}

add_frame :: proc(table: ^Frame_Table, origin: World_Position, axes: [3][3]i64, pitch_millimetres: int) -> Frame_Id {
	table.last_id += 1
	id := Frame_Id(table.last_id)
	append(&table.frames, Frame{id = id, origin = origin, axes = axes, pitch_millimetres = pitch_millimetres})
	return id
}

// A frame's record and its extent, once its cells are empty (the
// simulation's release_empty_frame decides when).
remove_frame :: proc(table: ^Frame_Table, id: Frame_Id) {
	for frame, index in table.frames {
		if frame.id == id {
			ordered_remove(&table.frames, index)
			break
		}
	}
	delete_key(&table.extents, id)
}

// The occupant index.

occupy_frame_cell :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate, occupant: Occupant) {
	key := Frame_Cell{frame, cell}
	extent, known := table.extents[frame]
	if key not_in table.occupants {
		extent.cell_count += 1
	}
	if known {
		extent.minimum = {min(extent.minimum.x, cell.x), min(extent.minimum.y, cell.y), min(extent.minimum.z, cell.z)}
		extent.maximum = {max(extent.maximum.x, cell.x), max(extent.maximum.y, cell.y), max(extent.maximum.z, cell.z)}
	} else {
		extent.minimum, extent.maximum = cell, cell
	}
	table.extents[frame] = extent
	table.occupants[key] = occupant
}

vacate_frame_cell :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) {
	key := Frame_Cell{frame, cell}
	if key not_in table.occupants {
		return
	}
	delete_key(&table.occupants, key)
	if extent, known := table.extents[frame]; known {
		extent.cell_count -= 1
		table.extents[frame] = extent
	}
}

frame_occupant :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) -> (occupant: Occupant, found: bool) {
	occupant, found = table.occupants[Frame_Cell{frame, cell}]
	return
}

frame_cell_is_occupied :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) -> bool {
	return Frame_Cell{frame, cell} in table.occupants
}

frame_cell_is_solid :: proc(table: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) -> bool {
	occupant, found := frame_occupant(table, frame, cell)
	return found && .Solid in occupant.flags
}

frame_cell_count :: proc(table: ^Frame_Table, frame: Frame_Id) -> int {
	extent := table.extents[frame] or_else {}
	return extent.cell_count
}

// Before the index is rebuilt from the entities; the frame records stay.
clear_frame_occupants :: proc(table: ^Frame_Table) {
	clear(&table.occupants)
	clear(&table.extents)
}

// The transforms.

frame_pitch_units :: proc(frame: Frame) -> i64 {
	return millimetres_to_position_units(frame.pitch_millimetres)
}

// The centre of a cell. Cells a few thousand pitches out keep the sum of
// axis times twice the cell times the pitch near 2^50, inside an i64.
frame_cell_centre :: proc(frame: Frame, cell: World_Coordinate) -> World_Position {
	pitch := frame_pitch_units(frame)
	sum: [3]i64
	for axis in 0 ..< 3 {
		sum += frame.axes[axis] * ((2 * i64(cell[axis]) + 1) * pitch)
	}
	return frame.origin + World_Position(sum / (2 * UNIT_VECTOR_ONE))
}

// The cell holding a position: the offset from the origin along each axis
// over the pitch, rounded down, which is the cell whose centre is
// nearest along that axis.
world_to_frame_cell :: proc(frame: Frame, position: World_Position) -> World_Coordinate {
	offset := cast([3]i64)(position - frame.origin)
	denominator := frame_pitch_units(frame) * UNIT_VECTOR_ONE
	cell: World_Coordinate
	for axis in 0 ..< 3 {
		along := offset.x * frame.axes[axis].x + offset.y * frame.axes[axis].y + offset.z * frame.axes[axis].z
		cell[axis] = i32(floor_divide_i64(along, denominator))
	}
	return cell
}

// A position along the frame's axes, in position units from the origin.
frame_local_position :: proc(frame: Frame, position: World_Position) -> [3]i64 {
	offset := cast([3]i64)(position - frame.origin)
	return {fixed_dot(offset, frame.axes[FRAME_RIGHT]), fixed_dot(offset, frame.axes[FRAME_UP]), fixed_dot(offset, frame.axes[FRAME_FORWARD])}
}

// A world direction along the frame's axes.
frame_local_direction :: proc(frame: Frame, direction: [3]i64) -> [3]i64 {
	return {fixed_dot(direction, frame.axes[FRAME_RIGHT]), fixed_dot(direction, frame.axes[FRAME_UP]), fixed_dot(direction, frame.axes[FRAME_FORWARD])}
}

// The orientation of a new frame.

// The angle of a yaw step in ANGLE_UNITS_PER_TURN, rounded.
frame_yaw_angle :: proc(step: int) -> i32 {
	wrapped := step %% FRAME_YAW_STEPS
	return i32((wrapped * ANGLE_UNITS_PER_TURN + FRAME_YAW_STEPS / 2) / FRAME_YAW_STEPS)
}

// The planet's north on the tangent plane of up, or the fallback where
// the north is along the up (the poles).
frame_north_tangent :: proc(up: [3]i64) -> [3]i64 {
	for candidate in ([2][3]i64{FRAME_NORTH, FRAME_NORTH_FALLBACK}) {
		projected := project_onto_plane(candidate, up)
		if vector_length(projected) > UNIT_VECTOR_ONE / 16 {
			tangent, _ := normalize_fixed(projected)
			return tangent
		}
	}
	return {UNIT_VECTOR_ONE, 0, 0}
}

// The forward of yaw step step: the north tangent turned towards its
// cross with the up.
frame_forward :: proc(up: [3]i64, step: int) -> [3]i64 {
	north := frame_north_tangent(up)
	angle := frame_yaw_angle(step)
	turned := fixed_scale(north, fixed_cosine(angle)) + fixed_scale(fixed_cross(north, up), fixed_sine(angle))
	forward, ok := normalize_fixed(project_onto_plane(turned, up))
	if !ok {
		return north
	}
	return forward
}

// Right, up and forward from a unit up and a yaw step.
frame_axes :: proc(up: [3]i64, step: int) -> [3][3]i64 {
	forward := frame_forward(up, step)
	right, ok := normalize_fixed(fixed_cross(up, forward))
	if !ok {
		right = {UNIT_VECTOR_ONE, 0, 0}
	}
	return {right, up, forward}
}

// The yaw step whose forward is nearest heading (a tangent of up).
nearest_frame_yaw_step :: proc(up, heading: [3]i64) -> int {
	best, best_dot := 0, i64(min(i64))
	for step in 0 ..< FRAME_YAW_STEPS {
		if dot := fixed_dot(frame_forward(up, step), heading); dot > best_dot {
			best, best_dot = step, dot
		}
	}
	return best
}

// A free foundation's frame (doc/architecture.md, Frames): up along the
// radial at the hit, the yaw step of the heading, and cell (0, 0, 0)
// standing on the hit, centred over it.
free_frame_at :: proc(hit: World_Position, heading: [3]i64, pitch_millimetres: int) -> (origin: World_Position, axes: [3][3]i64) {
	up, ok := normalize_fixed(cast([3]i64)(hit))
	if !ok {
		up = {0, UNIT_VECTOR_ONE, 0}
	}
	axes = frame_axes(up, nearest_frame_yaw_step(up, heading))
	half := millimetres_to_position_units(pitch_millimetres) / 2
	origin = hit - World_Position(fixed_scale(axes[FRAME_RIGHT], half) + fixed_scale(axes[FRAME_FORWARD], half))
	return origin, axes
}
