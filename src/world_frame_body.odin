package game

// The collision volumes of a machine's model (work item 0230,
// doc/architecture.md, Frames). The record keeps them in
// 1/COLLISION_UNITS_PER_CELL of a cell in the model's frame (x and z
// centred on the unrotated footprint, y from its bottom, +x the front); a
// body is one placed machine's volumes in position units of its frame
// with its quarter turn. Signed distances in integers (exact outside, the
// depth to the nearest face inside) and a sphere traced ray; integer
// only, so every machine of a lockstep game agrees.

// Volumes per model, a box shell counting four.
COLLISION_VOLUME_LIMIT :: 64
COLLISION_UNITS_PER_CELL :: 4096
// Sphere tracing steps of a ray against a body; a grazing ray that needs
// more misses.
COLLISION_RAY_STEPS :: 64
// A traced ray within this many position units of a volume hits it.
COLLISION_RAY_HIT_UNITS :: 2
// normalize_fixed divides by the floor of the length, so a vector a few
// hundred units long comes out up to 1/length off; collision_unit scales
// it up by this first while the scaled vector stays exact.
COLLISION_NORMAL_SCALE :: 1024

Collision_Volume_Kind :: enum u8 {
	Box,
	Round,
}

// partial false is the full turn. start and end are unit vectors
// (UNIT_VECTOR_ONE) in the plane across the axis, their components along
// the axis's first and second perpendicular (collision_perpendicular_axes);
// the sector runs from start to end by the right hand rule about the
// axis, and wide when it spans more than half a turn.
Collision_Sector :: struct {
	partial: bool,
	start:   [2]i64,
	end:     [2]i64,
	wide:    bool,
}

// A box's from and to are its minimum and maximum corners (axis, the
// radii, shell and sector unused, shell always 0 after the reader expands
// a box shell). A round's are its axis's points at its two ends,
// from[axis] < to[axis], equal on the other two axes, with the outer
// radius at each, the shell's thickness along the radius (0 solid) and its
// sector. bound_*: the box round the volume (a round one's full turn),
// for the cull. In model units on the record, in position units in a body.
Collision_Volume :: struct {
	kind:          Collision_Volume_Kind,
	axis:          int,
	from:          [3]i64,
	to:            [3]i64,
	radius_from:   i64,
	radius_to:     i64,
	shell:         i64,
	sector:        Collision_Sector,
	bound_minimum: [3]i64,
	bound_maximum: [3]i64,
}

// The machine's occupant as its held cells carry it; a copy of its frame
// (a frame never re-tangents); the model frame's origin in the frame's
// axes in position units; the quarter turns; a radius round centre
// holding every volume; the volumes in position units.
Frame_Body :: struct {
	occupant:     Occupant,
	frame:        Frame,
	centre:       [3]i64,
	rotation:     u8,
	bound:        i64,
	volumes:      [COLLISION_VOLUME_LIMIT]Collision_Volume,
	volume_count: int,
}

// The unit vector along vector, scaled up first while that stays exact
// (COLLISION_NORMAL_SCALE); ok is false for the zero vector.
collision_unit :: proc(vector: [3]i64) -> (unit: [3]i64, ok: bool) {
	if max(abs(vector.x), abs(vector.y), abs(vector.z)) < VECTOR_LENGTH_EXACT_LIMIT / COLLISION_NORMAL_SCALE {
		return normalize_fixed(vector * COLLISION_NORMAL_SCALE)
	}
	return normalize_fixed(vector)
}

// Placement.

// The order the sector's angles run in: x: y, z; y: z, x; z: x, y.
collision_perpendicular_axes :: proc(axis: int) -> (first, second: int) {
	return (axis + 1) % 3, (axis + 2) % 3
}

scale_collision_length :: proc(value, pitch_units: i64) -> i64 {
	return floor_divide_i64(value * pitch_units, COLLISION_UNITS_PER_CELL)
}

scale_collision_point :: proc(point: [3]i64, pitch_units: i64) -> [3]i64 {
	return {scale_collision_length(point.x, pitch_units), scale_collision_length(point.y, pitch_units), scale_collision_length(point.z, pitch_units)}
}

// From model units to position units of a frame of pitch_units per cell;
// the sector unchanged.
scale_collision_volume :: proc(volume: Collision_Volume, pitch_units: i64) -> Collision_Volume {
	scaled := volume
	scaled.from = scale_collision_point(volume.from, pitch_units)
	scaled.to = scale_collision_point(volume.to, pitch_units)
	scaled.radius_from = scale_collision_length(volume.radius_from, pitch_units)
	scaled.radius_to = scale_collision_length(volume.radius_to, pitch_units)
	scaled.shell = scale_collision_length(volume.shell, pitch_units)
	scaled.bound_minimum = scale_collision_point(volume.bound_minimum, pitch_units)
	scaled.bound_maximum = scale_collision_point(volume.bound_maximum, pitch_units)
	return scaled
}

// The model frame's origin in the frame's axes, position units: the
// rotated footprint's centre on x and z, its bottom on y, as
// model_transform draws the model.
frame_body_centre :: proc(origin: World_Coordinate, size: [3]i32, pitch: i64) -> [3]i64 {
	return {(2 * i64(origin.x) + i64(size.x)) * pitch / 2, i64(origin.y) * pitch, (2 * i64(origin.z) + i64(size.z)) * pitch / 2}
}

// A point of a placed model's frame (point in 1/COLLISION_UNITS_PER_CELL
// cell, x and z centred, y from the bottom) in the world (work item
// 0223: the pod's seated eye). size is the entity's rotated size.
model_point_in_frame :: proc(frame: Frame, origin: World_Coordinate, size: [3]i32, rotation: u8, point: [3]i64) -> World_Position {
	pitch := frame_pitch_units(frame)
	local := frame_body_centre(origin, size, pitch) + body_direction_to_frame(rotation, scale_collision_point(point, pitch))
	return frame.origin + World_Position(frame_world_direction(frame, local))
}

// size is the entity's rotated size: the model centred on the rotated
// footprint as model_transform draws it.
make_frame_body :: proc(frame: Frame, occupant: Occupant, origin: World_Coordinate, size: [3]i32, rotation: u8, volumes: []Collision_Volume) -> Frame_Body {
	pitch := frame_pitch_units(frame)
	body := Frame_Body {
		occupant = occupant,
		frame    = frame,
		centre   = frame_body_centre(origin, size, pitch),
		rotation = rotation,
	}
	body.volume_count = min(len(volumes), COLLISION_VOLUME_LIMIT)
	extent: [3]i64
	for index in 0 ..< body.volume_count {
		body.volumes[index] = scale_collision_volume(volumes[index], pitch)
		for axis in 0 ..< 3 {
			extent[axis] = max(extent[axis], abs(body.volumes[index].bound_minimum[axis]), abs(body.volumes[index].bound_maximum[axis]))
		}
	}
	body.bound = vector_length(extent)
	return body
}

// The cosine and sine of rotation quarter turns, model_transform's tables.
quarter_turn :: proc(rotation: u8) -> (cosine, sine: i64) {
	cosines := [4]i64{1, 0, -1, 0}
	sines := [4]i64{0, 1, 0, -1}
	return cosines[rotation % 4], sines[rotation % 4]
}

// A direction of the model's frame in the frame's axes (model_transform's
// rotation).
body_direction_to_frame :: proc(rotation: u8, direction: [3]i64) -> [3]i64 {
	cosine, sine := quarter_turn(rotation)
	return {cosine * direction.x - sine * direction.z, direction.y, sine * direction.x + cosine * direction.z}
}

body_direction_from_frame :: proc(rotation: u8, direction: [3]i64) -> [3]i64 {
	cosine, sine := quarter_turn(rotation)
	return {cosine * direction.x + sine * direction.z, direction.y, -sine * direction.x + cosine * direction.z}
}

// A point in the frame's axes (position units from its origin) in the
// model's frame.
body_point_from_frame :: proc(body: Frame_Body, local: [3]i64) -> [3]i64 {
	return body_direction_from_frame(body.rotation, local - body.centre)
}

// Distances: point in the volume's units and frame; normal a unit vector
// out of the volume, from the nearest surface point to the point, or out
// through the nearest face when inside; distance negative inside.

// Outside: the length of the offset from the box's nearest point and its
// direction. Inside: minus the depth to the nearest face and that face's
// outward axis (faces in the order -x, +x, -y, +y, -z, +z, the first on a
// tie).
box_signed_distance :: proc(point, minimum, maximum: [3]i64) -> (distance: i64, normal: [3]i64) {
	offset: [3]i64
	for axis in 0 ..< 3 {
		offset[axis] = point[axis] - clamp(point[axis], minimum[axis], maximum[axis])
	}
	if offset != {} {
		normal, _ = collision_unit(offset)
		return vector_length(offset), normal
	}
	depth := max(i64)
	for axis in 0 ..< 3 {
		if below := point[axis] - minimum[axis]; below < depth {
			depth, normal = below, {}
			normal[axis] = -UNIT_VECTOR_ONE
		}
		if above := maximum[axis] - point[axis]; above < depth {
			depth, normal = above, {}
			normal[axis] = UNIT_VECTOR_ONE
		}
	}
	return -depth, normal
}

// A round volume's cross section in the half plane of (radius, height),
// counter clockwise; for a solid, edge 3 is the axis and no surface.
Round_Section :: struct {
	corners: [4][2]i64,
	solid:   bool,
}

round_section :: proc(volume: Collision_Volume) -> Round_Section {
	h0, h1 := volume.from[volume.axis], volume.to[volume.axis]
	r0, r1, k := volume.radius_from, volume.radius_to, volume.shell
	if k == 0 {
		return {corners = {{0, h0}, {r0, h0}, {r1, h1}, {0, h1}}, solid = true}
	}
	return {corners = {{r0 - k, h0}, {r0, h0}, {r1, h1}, {r1 - k, h1}}}
}

dot_2d :: proc(first, second: [2]i64) -> i64 {
	return first.x * second.x + first.y * second.y
}

cross_2d :: proc(first, second: [2]i64) -> i64 {
	return first.x * second.y - first.y * second.x
}

segment_closest_point_2d :: proc(start, end, point: [2]i64) -> [2]i64 {
	d := end - start
	n := dot_2d(point - start, d)
	length_squared := dot_2d(d, d)
	if n <= 0 {
		return start
	}
	if n >= length_squared {
		return end
	}
	return start + d * n / length_squared
}

// Edge index runs from corner index to the next.
section_edge :: proc(section: Round_Section, index: int) -> (start, end: [2]i64) {
	return section.corners[index], section.corners[(index + 1) % 4]
}

// Inside when the point lies left of every edge; else the nearest point
// of the four edges, the axis too, the first on a tie.
section_closest_point :: proc(section: Round_Section, point: [2]i64) -> (closest: [2]i64, inside: bool) {
	inside = true
	for index in 0 ..< 4 {
		start, end := section_edge(section, index)
		if cross_2d(end - start, point - start) < 0 {
			inside = false
		}
	}
	if inside {
		return point, true
	}
	best := max(i64)
	for index in 0 ..< 4 {
		start, end := section_edge(section, index)
		candidate := segment_closest_point_2d(start, end, point)
		offset := point - candidate
		if squared := dot_2d(offset, offset); squared < best {
			best, closest = squared, candidate
		}
	}
	return closest, false
}

// For a point inside: the least distance to an edge (the axis skipped for
// a solid) and that edge's outward normal.
section_depth :: proc(section: Round_Section, point: [2]i64) -> (depth: i64, normal: [2]i64) {
	depth = max(i64)
	for index in 0 ..< 4 {
		if section.solid && index == 3 {
			continue
		}
		start, end := section_edge(section, index)
		d := end - start
		length := vector_length({d.x, d.y, 0})
		if length == 0 {
			continue
		}
		if candidate := cross_2d(d, point - start) / length; candidate < depth {
			unit, _ := collision_unit({d.y, -d.x, 0})
			depth, normal = candidate, {unit.x, unit.y}
		}
	}
	return depth, normal
}

sector_contains :: proc(sector: Collision_Sector, across: [2]i64) -> bool {
	if !sector.partial || across == {0, 0} {
		return true
	}
	if !sector.wide {
		return cross_2d(sector.start, across) >= 0 && cross_2d(across, sector.end) >= 0
	}
	return !(cross_2d(sector.end, across) > 0 && cross_2d(across, sector.start) > 0)
}

// The 3D vector with across on the axis's two perpendiculars and along on
// the axis.
lift_across :: proc(axis: int, across: [2]i64, along: i64) -> [3]i64 {
	first, second := collision_perpendicular_axes(axis)
	lifted: [3]i64
	lifted[first], lifted[second], lifted[axis] = across.x, across.y, along
	return lifted
}

// The distance from the point (across, height) to the section placed in
// the half plane of the unit face direction; outward is the face's normal
// away from the sector, the normal where the point lies over the section
// or on it.
sector_face_distance :: proc(section: Round_Section, axis: int, face: [2]i64, outward: [2]i64, across: [2]i64, height: i64) -> (distance: i64, normal: [3]i64) {
	along := dot_2d(across, face) / UNIT_VECTOR_ONE
	closest, inside := section_closest_point(section, {along, height})
	offset := lift_across(axis, across - face * closest.x / UNIT_VECTOR_ONE, height - closest.y)
	distance = vector_length(offset)
	// Over the section the offset runs across the face, whose outward
	// normal is exact where the offset's rounding is not.
	unit, ok := collision_unit(offset)
	if inside || !ok {
		return distance, lift_across(axis, outward, 0)
	}
	return distance, unit
}

round_signed_distance :: proc(volume: Collision_Volume, point: [3]i64) -> (distance: i64, normal: [3]i64) {
	axis := volume.axis
	first, second := collision_perpendicular_axes(axis)
	across := [2]i64{point[first] - volume.from[first], point[second] - volume.from[second]}
	height := point[axis]
	radius := i64(integer_square_root(u64(across.x * across.x + across.y * across.y)))
	radial := [2]i64{UNIT_VECTOR_ONE, 0}
	if unit, ok := collision_unit({across.x, across.y, 0}); ok {
		radial = {unit.x, unit.y}
	}
	section := round_section(volume)
	sector := volume.sector
	start_outward := [2]i64{sector.start.y, -sector.start.x}
	end_outward := [2]i64{-sector.end.y, sector.end.x}
	if !sector_contains(sector, across) {
		start_distance, start_normal := sector_face_distance(section, axis, sector.start, start_outward, across, height)
		end_distance, end_normal := sector_face_distance(section, axis, sector.end, end_outward, across, height)
		if end_distance < start_distance {
			return end_distance, end_normal
		}
		return start_distance, start_normal
	}
	closest, inside := section_closest_point(section, {radius, height})
	if !inside {
		offset := [2]i64{radius - closest.x, height - closest.y}
		normal, _ = collision_unit(lift_across(axis, radial * offset.x / UNIT_VECTOR_ONE, offset.y))
		return vector_length({offset.x, offset.y, 0}), normal
	}
	depth, section_normal := section_depth(section, {radius, height})
	normal, _ = collision_unit(lift_across(axis, radial * section_normal.x / UNIT_VECTOR_ONE, section_normal.y))
	if sector.partial {
		faces := [2][2]i64{sector.start, sector.end}
		outwards := [2][2]i64{start_outward, end_outward}
		for face, index in faces {
			if face_distance, _ := sector_face_distance(section, axis, face, outwards[index], across, height); face_distance < depth {
				depth, normal = face_distance, lift_across(axis, outwards[index], 0)
			}
		}
	}
	return -depth, normal
}

volume_signed_distance :: proc(volume: Collision_Volume, point: [3]i64) -> (distance: i64, normal: [3]i64) {
	if volume.kind == .Box {
		return box_signed_distance(point, volume.from, volume.to)
	}
	return round_signed_distance(volume, point)
}

volume_within_reach :: proc(volume: Collision_Volume, point: [3]i64, reach: i64) -> bool {
	for axis in 0 ..< 3 {
		if point[axis] < volume.bound_minimum[axis] - reach || point[axis] > volume.bound_maximum[axis] + reach {
			return false
		}
	}
	return true
}

// The nearest volume within reach of a point of the model's frame, the
// first in file order on a tie; the reach as the distance and found false
// when none is nearer.
body_signed_distance :: proc(body: Frame_Body, point: [3]i64, reach: i64) -> (distance: i64, normal: [3]i64, found: bool) {
	distance = reach
	for index in 0 ..< body.volume_count {
		volume := body.volumes[index]
		if !volume_within_reach(volume, point, reach) {
			continue
		}
		if candidate, candidate_normal := volume_signed_distance(volume, point); candidate < distance {
			distance, normal, found = candidate, candidate_normal, true
		}
	}
	return
}

// Registration (called by the simulation, entity.odin).

// Replaces the body of the same occupant handle, else inserts it before
// the first body with a larger handle, so the bodies stay sorted.
register_frame_body :: proc(table: ^Frame_Table, body: Frame_Body) {
	for &existing, index in table.bodies {
		if existing.occupant.handle == body.occupant.handle {
			existing = body
			return
		}
		if existing.occupant.handle > body.occupant.handle {
			inject_at(&table.bodies, index, body)
			return
		}
	}
	append(&table.bodies, body)
}

unregister_frame_body :: proc(table: ^Frame_Table, handle: Occupant_Handle) {
	for body, index in table.bodies {
		if body.occupant.handle == handle {
			ordered_remove(&table.bodies, index)
			return
		}
	}
}

// Probe and ray.

// The nearest volume of any body within reach of position, in body
// order (ascending occupant handle), the first on a tie; none for a nil
// table.
frame_body_probe :: proc(table: ^Frame_Table, position: World_Position, reach: i64) -> Field_Surface_Probe {
	nearest := Field_Surface_Probe{distance = reach}
	if table == nil {
		return nearest
	}
	for &body in table.bodies {
		local := frame_local_position(body.frame, position)
		if vector_length(local - body.centre) > body.bound + reach {
			continue
		}
		distance, normal, found := body_signed_distance(body, body_point_from_frame(body, local), reach)
		if found && distance < nearest.distance {
			nearest = {distance = distance, normal = frame_world_direction(body.frame, body_direction_to_frame(body.rotation, normal)), found = true}
		}
	}
	return nearest
}

// A ray traced through the body's volumes by their exact distances, so it
// never passes through one; frame_normal in the frame's axes. A ray
// starting inside hits at 0; one grazing a face for more than
// COLLISION_RAY_STEPS steps misses.
raycast_frame_body :: proc(body: Frame_Body, origin: World_Position, direction: [3]i64, reach: i64) -> (distance: i64, frame_normal: [3]i64, hit: bool) {
	local := frame_local_position(body.frame, origin)
	if vector_length(local - body.centre) > body.bound + reach {
		return
	}
	start := body_point_from_frame(body, local)
	step := body_direction_from_frame(body.rotation, frame_local_direction(body.frame, direction))
	travelled := i64(0)
	for _ in 0 ..< COLLISION_RAY_STEPS {
		gap, normal, found := body_signed_distance(body, start + step * travelled / UNIT_VECTOR_ONE, reach - travelled + COLLISION_RAY_HIT_UNITS)
		if !found {
			return
		}
		if gap <= COLLISION_RAY_HIT_UNITS {
			return travelled, body_direction_to_frame(body.rotation, normal), true
		}
		travelled += gap
		if travelled > reach {
			return
		}
	}
	return
}

// The face of the normal's largest component (x before y before z on a
// tie) and its sign.
face_of_frame_normal :: proc(normal: [3]i64) -> Direction {
	axis := 0
	for candidate in 1 ..< 3 {
		if abs(normal[candidate]) > abs(normal[axis]) {
			axis = candidate
		}
	}
	faces := [3][2]Direction{{.Negative_X, .Positive_X}, {.Negative_Y, .Positive_Y}, {.Negative_Z, .Positive_Z}}
	return faces[axis][normal[axis] >= 0 ? 1 : 0]
}

// A body's hit as a cell hit: the cell holding the hit point moved a
// quarter pitch into the volume, the face of the normal and the cell in
// front of it, so placement and the pick up path work unchanged.
frame_body_hit :: proc(body: Frame_Body, origin: World_Position, direction: [3]i64, distance: i64, frame_normal: [3]i64) -> Frame_Raycast_Hit {
	pitch := frame_pitch_units(body.frame)
	local := frame_local_position(body.frame, origin) + frame_local_direction(body.frame, direction) * distance / UNIT_VECTOR_ONE - frame_normal * (pitch / 4) / UNIT_VECTOR_ONE
	cell := World_Coordinate{i32(floor_divide_i64(local.x, pitch)), i32(floor_divide_i64(local.y, pitch)), i32(floor_divide_i64(local.z, pitch))}
	face := face_of_frame_normal(frame_normal)
	return Frame_Raycast_Hit {
		hit = true,
		frame = body.frame.id,
		cell = cell,
		face = face,
		adjacent = cell + World_Coordinate(direction_offsets[face]),
		distance = distance,
		occupant = body.occupant,
	}
}

// The nearest body hit (the first on a tie) with its normal in world
// axes; none for a nil table.
raycast_frame_bodies :: proc(table: ^Frame_Table, origin: World_Position, direction: [3]i64, reach: i64) -> (hit: Frame_Raycast_Hit, normal: [3]i64) {
	if table == nil {
		return
	}
	for &body in table.bodies {
		distance, frame_normal, found := raycast_frame_body(body, origin, direction, reach)
		if found && (!hit.hit || distance < hit.distance) {
			hit = frame_body_hit(body, origin, direction, distance, frame_normal)
			normal = frame_world_direction(body.frame, frame_normal)
		}
	}
	return
}

// The cells (Shaped ones passed) and the bodies: a body hit strictly
// nearer than the cells' wins with its normal, else the cells' hit with
// its entered face's normal. The bodies count for every required and
// excluded the callers pass: a body's occupant is Solid and never Open.
raycast_frames_and_bodies :: proc(table: ^Frame_Table, origin: World_Position, direction: [3]i64, reach: i64, required: Occupant_Flags = {}, excluded: Occupant_Flags = {}) -> (hit: Frame_Raycast_Hit, normal: [3]i64) {
	cells := raycast_frames(table, origin, direction, reach, required, excluded + {.Shaped})
	body, body_normal := raycast_frame_bodies(table, origin, direction, reach)
	if body.hit && (!cells.hit || body.distance < cells.distance) {
		return body, body_normal
	}
	return cells, frame_face_normal(table, cells)
}

// The hit's entered face as a world direction; zero for no hit.
frame_face_normal :: proc(table: ^Frame_Table, hit: Frame_Raycast_Hit) -> [3]i64 {
	if !hit.hit {
		return {}
	}
	frame, _ := find_frame(table, hit.frame)
	offset := direction_offsets[hit.face]
	return frame_world_direction(frame, {i64(offset.x) * UNIT_VECTOR_ONE, i64(offset.y) * UNIT_VECTOR_ONE, i64(offset.z) * UNIT_VECTOR_ONE})
}
