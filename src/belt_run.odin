package game

import "core:fmt"

// Belt and pipe runs between poles (work item 0176, doc/logistics.md,
// Runs): Satisfactory's free belts. A run joins two endpoints, each a belt
// pole or a frame cell's belt end, along a curve the game derives from
// their positions and facings: a cubic Hermite whose tangents lie along
// the facings, a share of the span long, kept as its four Bezier control
// points. The polyline is the curve at BELT_RUN_SUBDIVISIONS + 1 fixed
// parameters with the basis in 1/BELT_RUN_BASIS_ONE, and the arc length is
// the sum of its segments by vector_length: integers only, so every
// machine of a lockstep session computes the same bytes.
//
// A run either inclines or turns, never both, within the span, slope and
// turn of data/game.sjson (belt_runs); one that breaks a constraint is
// refused with the reason. A belt run is a segment of its belt line as
// long as its arc length in line units at the start frame's pitch
// (belt.odin, append_belt_segment), so items keep their distance along
// the line across it; the shape only maps a distance to a point
// (belt_run_point_at) for the renderer. A pipe run carries the pipe's
// look only: the fluid networks do not connect through runs yet.
//
// A belt pole is an entity (Machine_Kind.Belt_Pole): placed free it is a
// one cell frame of its own, its facing the frame's forward; snapped it
// stands on a frame's foundation facing a frame direction. A run is no
// entity: its pool entry has a handle and a machine but no cell.

BELT_RUN_SUBDIVISIONS :: 32
// 2 (32 - k)^3, 6 k (32 - k)^2, 6 k^2 (32 - k) and 2 k^3 sum to it, so the
// Bernstein basis at k / 32 is exact.
BELT_RUN_BASIS_ONE :: 65536
#assert(2 * BELT_RUN_SUBDIVISIONS * BELT_RUN_SUBDIVISIONS * BELT_RUN_SUBDIVISIONS == BELT_RUN_BASIS_ONE)
// Each end's tangent is this share of the span in 1/BELT_RUN_BASIS_ONE:
// 4 - 2 sqrt 2 (1.1716), at which a quarter turn follows its circle (a
// third of the tangent is the Bezier circle's 0.5523 of the radius).
BELT_RUN_TANGENT_SHARE :: 76781
// The polyline is evaluated in 1/2^8 of a position unit for the arc
// length, then rounded to whole units.
BELT_RUN_FINE_SHIFT :: 8
// A free pole faces the yaw step nearest the chord, up to half a step
// off, so an incline must allow more (belt_runs.aligned_degrees).
#assert(MINIMUM_BELT_RUN_ALIGNED_DEGREES >= 360 / FRAME_YAW_STEPS / 2 + 1)
// A free pole faces its frame's forward (belt_direction_offset(1) is +z).
BELT_POLE_FREE_ROTATION :: 1
MINIMUM_BELT_POLE_HEIGHT_MILLIMETRES :: 250
MAXIMUM_BELT_POLE_HEIGHT_MILLIMETRES :: 4000

Belt_Run_Kind :: enum u8 {
	Belt,
	Pipe,
}

Belt_Pole :: struct {
	using common: Entity_Common,
}

// A pole (pole set; frame and cell copied from it) or the belt end of a
// frame cell. facing is the quarter turn round the frame's up items travel
// in there: from the start the run leaves along it, at the end it
// arrives along it. A pole's is its rotation or the reverse, whichever
// the run's chord is nearer.
Belt_Run_Endpoint :: struct {
	pole:   Entity_Handle,
	frame:  Frame_Id,
	cell:   World_Coordinate,
	facing: u8,
}

BELT_RUN_START :: 0
BELT_RUN_END :: 1

// Derived from the control points (belt_run_curve), never saved.
Belt_Run_Curve :: struct {
	polyline:     [BELT_RUN_SUBDIVISIONS + 1]World_Position,
	// Position units, the sum of the polyline's segments.
	arc_length:   i64,
	// The arc length in line units: BELT_UNITS_PER_BLOCK a cell of the
	// start frame's pitch, rounded to the nearest, at least one.
	length_units: i32,
}

Belt_Run :: struct {
	handle:         Entity_Handle,
	alive:          bool,
	kind:           Belt_Run_Kind,
	// The belt whose speed the run moves at, or the pipe it looks like.
	machine:        Machine_Id,
	endpoints:      [2]Belt_Run_Endpoint,
	control_points: [4]World_Position,
	curve:          Belt_Run_Curve `save:"-"`,
	// Set by rebuild_belt_lines for a belt run.
	line:           i32 `save:"-"`,
	line_index:     i32 `save:"-"`,
}

// What a run is shaped from: the ends' positions, the directions items
// travel in there, the ends' frame ups and the start frame's pitch.
Belt_Run_Geometry :: struct {
	positions:         [2]World_Position,
	directions:        [2][3]i64,
	ups:               [2][3]i64,
	pitch_millimetres: int,
}

// data/game.sjson's belt_runs in the simulation's units: position units
// and cosines in UNIT_VECTOR_ONE.
Belt_Run_Constraints :: struct {
	maximum_span:          i64,
	maximum_slope_percent: i64,
	turn_cosine:           i64,
	aligned_cosine:        i64,
	level_tolerance:       i64,
}

Belt_Run_Refusal :: enum u8 {
	None,
	// A pole or a frame is gone, or no flat belt faces the run at a belt end.
	Unknown_Endpoint,
	// The ends meet.
	Too_Short,
	// The pole or the belt end has a run on that side already.
	Endpoint_Taken,
	// A new pole's cell is taken or has no foundation under it.
	Pole_Blocked,
	Too_Long,
	Too_Steep,
	Turns_Too_Far,
	Inclines_And_Turns,
	// The pole's other run fixes the way items cross it, and this run
	// would leave (or arrive) against it.
	Reverses_At_Pole,
	// The belt the run ends at is fed from behind already.
	Belt_Already_Fed,
	// The belt the run starts at already feeds a belt or a splitter.
	Belt_Output_Taken,
}

make_belt_run_constraints :: proc(config: Belt_Runs_Config) -> Belt_Run_Constraints {
	return Belt_Run_Constraints {
		maximum_span = millimetres_to_position_units(config.maximum_span_millimetres),
		maximum_slope_percent = i64(config.maximum_slope_percent),
		turn_cosine = fixed_cosine(degrees_to_angle_units(config.maximum_turn_degrees)),
		aligned_cosine = fixed_cosine(degrees_to_angle_units(config.aligned_degrees)),
		level_tolerance = millimetres_to_position_units(config.level_tolerance_millimetres),
	}
}

validate_belt_pole_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 {
		return fmt.tprintf("belt pole %q must have a 1 by 1 by 1 footprint", definition.id)
	}
	if definition.height_millimetres < MINIMUM_BELT_POLE_HEIGHT_MILLIMETRES || definition.height_millimetres > MAXIMUM_BELT_POLE_HEIGHT_MILLIMETRES {
		return fmt.tprintf("belt pole %q has height_millimetres %d outside %d to %d", definition.id, definition.height_millimetres, MINIMUM_BELT_POLE_HEIGHT_MILLIMETRES, MAXIMUM_BELT_POLE_HEIGHT_MILLIMETRES)
	}
	return ""
}

// The geometry.

// The world direction of a quarter turn round the frame's up.
frame_facing_direction :: proc(frame: Frame, facing: u8) -> [3]i64 {
	offset := belt_direction_offset(facing)
	return frame.axes[FRAME_RIGHT] * i64(offset.x) + frame.axes[FRAME_FORWARD] * i64(offset.z)
}

// The middle of a cell's bottom face.
frame_cell_bottom :: proc(frame: Frame, cell: World_Coordinate) -> World_Position {
	return frame_cell_centre(frame, cell) - World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
}

// Where a run meets a pole: height over the cell's bottom.
belt_pole_top :: proc(frame: Frame, cell: World_Coordinate, height_millimetres: int) -> World_Position {
	return frame_cell_bottom(frame, cell) + World_Position(fixed_scale(frame.axes[FRAME_UP], millimetres_to_position_units(height_millimetres)))
}

// Where a run meets a belt end: the middle of the cell's bottom edge the
// items leave by at the start, or enter by at the end.
belt_end_point :: proc(frame: Frame, cell: World_Coordinate, facing: u8, role: int) -> World_Position {
	half := fixed_scale(frame_facing_direction(frame, facing), frame_pitch_units(frame) / 2)
	return frame_cell_bottom(frame, cell) + World_Position(role == BELT_RUN_START ? half : -half)
}

// Of a pole's rotation and its reverse, the one nearer the chord.
belt_pole_facing_towards :: proc(frame: Frame, rotation: u8, chord: [3]i64) -> u8 {
	if fixed_dot(frame_facing_direction(frame, rotation), chord) >= 0 {
		return rotation % 4
	}
	return turn_right(rotation, 2)
}

// Of a frame's four facings, the one nearest the chord.
frame_facing_towards :: proc(frame: Frame, chord: [3]i64) -> u8 {
	best, best_dot := u8(0), i64(min(i64))
	for facing in u8(0) ..< 4 {
		if dot := fixed_dot(frame_facing_direction(frame, facing), chord); dot > best_dot {
			best, best_dot = facing, dot
		}
	}
	return best
}

// The flat belt facing the run at a belt end, or nil.
belt_at_run_end :: proc(entities: ^Entities, endpoint: Belt_Run_Endpoint) -> ^Belt {
	belt := belt_at(entities, endpoint.cell, endpoint.frame)
	if belt == nil || belt.shape != .Flat || belt.rotation != endpoint.facing % 4 {
		return nil
	}
	return belt
}

// The point and frame of an existing endpoint; found false when its pole,
// its frame or its belt is gone.
belt_run_endpoint_point :: proc(entities: ^Entities, machines: Machine_Registry, endpoint: Belt_Run_Endpoint, role: int) -> (point: World_Position, frame: Frame, found: bool) {
	frame = find_frame(&entities.frames, endpoint.frame) or_return
	if endpoint.pole == NO_ENTITY {
		if belt_at_run_end(entities, endpoint) == nil {
			return {}, frame, false
		}
		return belt_end_point(frame, endpoint.cell, endpoint.facing, role), frame, true
	}
	pole := pool_get(&entities.belt_poles, endpoint.pole)
	if pole == nil {
		return {}, frame, false
	}
	return belt_pole_top(frame, pole.origin, int(machines.machines[pole.machine].height_millimetres)), frame, true
}

// The geometry of two existing endpoints.
belt_run_geometry :: proc(entities: ^Entities, machines: Machine_Registry, endpoints: [2]Belt_Run_Endpoint) -> (geometry: Belt_Run_Geometry, found: bool) {
	for endpoint, role in endpoints {
		point, frame := belt_run_endpoint_point(entities, machines, endpoint, role) or_return
		geometry.positions[role] = point
		geometry.directions[role] = frame_facing_direction(frame, endpoint.facing)
		geometry.ups[role] = frame.axes[FRAME_UP]
		if role == BELT_RUN_START {
			geometry.pitch_millimetres = frame.pitch_millimetres
		}
	}
	return geometry, true
}

// The unit vector along the part of vector across up, or ok false.
tangent_direction :: proc(vector, up: [3]i64) -> (direction: [3]i64, ok: bool) {
	return normalize_fixed(project_onto_plane(vector, up))
}

// The mean of the ends' frame ups, so a run and its reverse are judged
// alike.
belt_run_mean_up :: proc(geometry: Belt_Run_Geometry) -> [3]i64 {
	up, ok := normalize_fixed(geometry.ups[BELT_RUN_START] + geometry.ups[BELT_RUN_END])
	if !ok {
		return geometry.ups[BELT_RUN_START]
	}
	return up
}

// The cosine of the sharpest of the turns between the two facings and
// between each facing and the chord, all across up: one for a straight
// run.
belt_run_turn_cosine :: proc(geometry: Belt_Run_Geometry, up: [3]i64) -> i64 {
	start, _ := tangent_direction(geometry.directions[BELT_RUN_START], up)
	end, _ := tangent_direction(geometry.directions[BELT_RUN_END], up)
	cosine := fixed_dot(start, end)
	if chord, ok := tangent_direction(cast([3]i64)(geometry.positions[BELT_RUN_END] - geometry.positions[BELT_RUN_START]), up); ok {
		cosine = min(cosine, fixed_dot(start, chord), fixed_dot(end, chord))
	}
	return cosine
}

// Whether a direction rises more than the slope over its run across up.
direction_too_steep :: proc(direction, up: [3]i64, slope_percent: i64) -> bool {
	return abs(fixed_dot(direction, up)) * 100 > vector_length(project_onto_plane(direction, up)) * slope_percent
}

// The constraints of the shape, across the mean up: the span, then level
// runs may turn up to the maximum, and inclines must keep their facings
// and chord aligned and the belt within the slope. With aligned end
// tangents the curve is steepest at its middle, where the derivative runs
// along P3 + P2 - P1 - P0 of the control points, so the chord and the
// middle are checked.
belt_run_shape_refusal :: proc(geometry: Belt_Run_Geometry, constraints: Belt_Run_Constraints) -> Belt_Run_Refusal {
	chord := cast([3]i64)(geometry.positions[BELT_RUN_END] - geometry.positions[BELT_RUN_START])
	span := vector_length(chord)
	switch {
	case span == 0:
		return .Too_Short
	case span > constraints.maximum_span:
		return .Too_Long
	}
	up := belt_run_mean_up(geometry)
	cosine := belt_run_turn_cosine(geometry, up)
	if abs(fixed_dot(chord, up)) <= constraints.level_tolerance {
		return cosine >= constraints.turn_cosine ? .None : .Turns_Too_Far
	}
	if cosine < constraints.aligned_cosine {
		return .Inclines_And_Turns
	}
	control := belt_run_control_points(geometry)
	middle := cast([3]i64)(control[3] + control[2] - control[1] - control[0])
	if direction_too_steep(chord, up, constraints.maximum_slope_percent) || direction_too_steep(middle, up, constraints.maximum_slope_percent) {
		return .Too_Steep
	}
	return .None
}

// The curve.

// The Hermite curve's Bezier points: the ends, and a third of each
// tangent (BELT_RUN_TANGENT_SHARE of the span along the facing) in from
// them.
belt_run_control_points :: proc(geometry: Belt_Run_Geometry) -> [4]World_Position {
	start, end := geometry.positions[BELT_RUN_START], geometry.positions[BELT_RUN_END]
	tangent := vector_length(cast([3]i64)(end - start)) * BELT_RUN_TANGENT_SHARE / BELT_RUN_BASIS_ONE
	return {
		start,
		start + World_Position(fixed_scale(geometry.directions[BELT_RUN_START], tangent / 3)),
		end - World_Position(fixed_scale(geometry.directions[BELT_RUN_END], tangent / 3)),
		end,
	}
}

// The curve at parameter step / BELT_RUN_SUBDIVISIONS in 1/2^BELT_RUN_FINE_SHIFT
// of a position unit, rounded down.
belt_run_fine_point :: proc(control_points: [4]World_Position, step: int) -> [3]i64 {
	along, rest := i64(step), i64(BELT_RUN_SUBDIVISIONS - step)
	weights := [4]i64{2 * rest * rest * rest, 6 * along * rest * rest, 6 * along * along * rest, 2 * along * along * along}
	sum: [3]i64
	for weight, index in weights {
		sum += cast([3]i64)control_points[index] * weight
	}
	return shift_vector_down(sum, 16 - BELT_RUN_FINE_SHIFT)
}

// Each component shifted down, rounding towards minus infinity.
shift_vector_down :: proc(vector: [3]i64, shift: uint) -> [3]i64 {
	return {vector.x >> shift, vector.y >> shift, vector.z >> shift}
}

// The polyline, the arc length and the length in line units at the pitch.
belt_run_curve :: proc(control_points: [4]World_Position, pitch_millimetres: int) -> Belt_Run_Curve {
	curve: Belt_Run_Curve
	fine: [BELT_RUN_SUBDIVISIONS + 1][3]i64
	half := i64(1) << (BELT_RUN_FINE_SHIFT - 1)
	for step in 0 ..= BELT_RUN_SUBDIVISIONS {
		fine[step] = belt_run_fine_point(control_points, step)
		curve.polyline[step] = World_Position(shift_vector_down(fine[step] + half, BELT_RUN_FINE_SHIFT))
	}
	fine_length: i64
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		fine_length += vector_length(fine[step + 1] - fine[step])
	}
	curve.arc_length = (fine_length + half) >> BELT_RUN_FINE_SHIFT
	curve.length_units = belt_run_length_units(curve.arc_length, pitch_millimetres)
	return curve
}

// Position units to line units at the pitch, rounded to the nearest, at
// least one.
belt_run_length_units :: proc(arc_length: i64, pitch_millimetres: int) -> i32 {
	denominator := i64(POSITION_UNITS_PER_METRE) * i64(pitch_millimetres)
	units := (arc_length * BELT_UNITS_PER_BLOCK * MILLIMETRES_PER_METRE + denominator / 2) / denominator
	return i32(max(units, 1))
}

// The point distance line units from the run's start along the polyline,
// and the segment it lies on: for the renderer, and for collision when
// runs get it.
belt_run_point_at :: proc(run: Belt_Run, distance: i32) -> (point: World_Position, segment: int) {
	curve := run.curve
	if curve.length_units <= 0 {
		return curve.polyline[0], 0
	}
	target := curve.arc_length * i64(clamp(distance, 0, curve.length_units)) / i64(curve.length_units)
	walked: i64
	for step in 0 ..< BELT_RUN_SUBDIVISIONS {
		offset := cast([3]i64)(curve.polyline[step + 1] - curve.polyline[step])
		length := vector_length(offset)
		if walked + length >= target && length > 0 {
			return curve.polyline[step] + World_Position(offset * (target - walked) / length), step
		}
		walked += length
	}
	return curve.polyline[BELT_RUN_SUBDIVISIONS], BELT_RUN_SUBDIVISIONS - 1
}

// The pool.

// A belt run in the belt lines; pipe runs are not.
belt_run_in_lines :: proc(run: Belt_Run) -> bool {
	return run.alive && run.kind == .Belt
}

same_run_endpoint :: proc(first, second: Belt_Run_Endpoint) -> bool {
	if first.pole != NO_ENTITY || second.pole != NO_ENTITY {
		return first.pole == second.pole
	}
	return first.frame == second.frame && first.cell == second.cell
}

// Whether a live run of the kind already starts (role 0) or ends (role 1)
// at the endpoint's pole or belt end.
belt_run_endpoint_taken :: proc(entities: ^Entities, kind: Belt_Run_Kind, endpoint: Belt_Run_Endpoint, role: int) -> bool {
	for run in entities.belt_runs.entries {
		if run.alive && run.kind == kind && same_run_endpoint(run.endpoints[role], endpoint) {
			return true
		}
	}
	return false
}

// The facing a pole's other run of the kind fixes for the role: a leaving
// run takes the facing the arriving run left the pole with, an arriving
// run the facing the leaving run starts with.
belt_pole_fixed_facing :: proc(entities: ^Entities, kind: Belt_Run_Kind, pole: Entity_Handle, role: int) -> (facing: u8, found: bool) {
	other := BELT_RUN_END - role
	for run in entities.belt_runs.entries {
		if run.alive && run.kind == kind && run.endpoints[other].pole == pole {
			return run.endpoints[other].facing, true
		}
	}
	return 0, false
}

// A pole's facing for a run against its other run's: it must be that
// facing and must not point against the chord, or items would turn round
// on the pole.
belt_pole_refusal :: proc(entities: ^Entities, kind: Belt_Run_Kind, endpoint: Belt_Run_Endpoint, role: int, chord: [3]i64) -> Belt_Run_Refusal {
	fixed, found := belt_pole_fixed_facing(entities, kind, endpoint.pole, role)
	if !found {
		return .None
	}
	frame, _ := find_frame(&entities.frames, endpoint.frame)
	if fixed != endpoint.facing % 4 || fixed_dot(frame_facing_direction(frame, fixed), chord) < 0 {
		return .Reverses_At_Pole
	}
	return .None
}

// A belt end's belt against the lines as they stand: the start's belt
// must not feed anything already, the end's must not be fed from behind.
belt_end_refusal :: proc(entities: ^Entities, endpoint: Belt_Run_Endpoint, role: int) -> Belt_Run_Refusal {
	belt := belt_at_run_end(entities, endpoint)
	if belt == nil {
		return .Unknown_Endpoint
	}
	link := compute_belt_links(entities).belts[belt.handle.index]
	switch {
	case role == BELT_RUN_START && link.connection != .None:
		return .Belt_Output_Taken
	case role == BELT_RUN_END && link.previous != NO_ENTITY:
		return .Belt_Already_Fed
	}
	return .None
}

// What refuses an existing endpoint of a run of the kind: a run on that
// side already, a pole the run would cross backwards, a belt fed or
// feeding already.
belt_run_endpoint_refusal :: proc(entities: ^Entities, kind: Belt_Run_Kind, endpoint: Belt_Run_Endpoint, role: int, chord: [3]i64) -> Belt_Run_Refusal {
	switch {
	case belt_run_endpoint_taken(entities, kind, endpoint, role):
		return .Endpoint_Taken
	case endpoint.pole != NO_ENTITY:
		return belt_pole_refusal(entities, kind, endpoint, role, chord)
	case kind == .Belt:
		return belt_end_refusal(entities, endpoint, role)
	}
	return .None
}

// Everything that refuses a run between two existing endpoints.
belt_run_refusal :: proc(entities: ^Entities, machines: Machine_Registry, constraints: Belt_Run_Constraints, kind: Belt_Run_Kind, endpoints: [2]Belt_Run_Endpoint) -> Belt_Run_Refusal {
	geometry, found := belt_run_geometry(entities, machines, endpoints)
	switch {
	case !found:
		return .Unknown_Endpoint
	case same_run_endpoint(endpoints[BELT_RUN_START], endpoints[BELT_RUN_END]):
		return .Too_Short
	}
	chord := cast([3]i64)(geometry.positions[BELT_RUN_END] - geometry.positions[BELT_RUN_START])
	for endpoint, role in endpoints {
		if refusal := belt_run_endpoint_refusal(entities, kind, endpoint, role, chord); refusal != .None {
			return refusal
		}
	}
	return belt_run_shape_refusal(geometry, constraints)
}

// A run between two existing endpoints after belt_run_refusal; a belt run
// rebuilds the lines, keeping the items on them.
add_belt_run :: proc(entities: ^Entities, machines: Machine_Registry, constraints: Belt_Run_Constraints, kind: Belt_Run_Kind, machine: Machine_Id, endpoints: [2]Belt_Run_Endpoint) -> (handle: Entity_Handle, refusal: Belt_Run_Refusal) {
	if refusal = belt_run_refusal(entities, machines, constraints, kind, endpoints); refusal != .None {
		return NO_ENTITY, refusal
	}
	geometry, _ := belt_run_geometry(entities, machines, endpoints)
	control_points := belt_run_control_points(geometry)
	run := Belt_Run {
		kind           = kind,
		machine        = machine,
		endpoints      = endpoints,
		control_points = control_points,
		curve          = belt_run_curve(control_points, geometry.pitch_millimetres),
	}
	records := belt_cell_items(entities)
	handle = pool_add(&entities.belt_runs, .Belt_Run, run)
	if kind == .Belt {
		rebuild_belt_lines(entities, machines, records)
	}
	return handle, .None
}

remove_belt_run :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	run := pool_get(&entities.belt_runs, handle)
	if run == nil {
		return false
	}
	kind, endpoints := run.kind, run.endpoints
	records := belt_cell_items(entities)
	pool_remove(&entities.belt_runs, handle)
	if kind == .Belt {
		rebuild_belt_lines(entities, machines, records)
	}
	for endpoint in endpoints {
		release_empty_frame(entities, endpoint.frame)
	}
	return true
}

// Before a pole goes: the runs on it go with it.
remove_belt_runs_on_pole :: proc(entities: ^Entities, machines: Machine_Registry, pole: Entity_Handle) {
	for run in entities.belt_runs.entries {
		if run.alive && (run.endpoints[BELT_RUN_START].pole == pole || run.endpoints[BELT_RUN_END].pole == pole) {
			remove_belt_run(entities, machines, run.handle)
		}
	}
}

// A pole placed free: a new frame standing on the hit (free_frame_at)
// facing the heading's yaw step, holding the pole at cell (0, 0, 0).
place_free_belt_pole :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, hit: World_Position, heading: [3]i64, pitch_millimetres: int) -> (handle: Entity_Handle, frame: Frame_Id) {
	origin, axes := free_frame_at(hit, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	return add_entity(entities, machines, machine, {}, BELT_POLE_FREE_ROTATION, frame), frame
}

// An existing pole as the role's endpoint of a run of the kind: facing
// the way its other run fixes (belt_pole_fixed_facing), else the way
// nearer the chord.
belt_pole_endpoint :: proc(entities: ^Entities, pole: Entity_Handle, chord: [3]i64, kind: Belt_Run_Kind, role: int) -> (endpoint: Belt_Run_Endpoint, found: bool) {
	entry := pool_get(&entities.belt_poles, pole)
	if entry == nil {
		return {}, false
	}
	frame := find_frame(&entities.frames, entry.frame) or_return
	facing := belt_pole_facing_towards(frame, entry.rotation, chord)
	if fixed, fixed_found := belt_pole_fixed_facing(entities, kind, pole, role); fixed_found {
		facing = fixed
	}
	return Belt_Run_Endpoint{pole = pole, frame = entry.frame, cell = entry.origin, facing = facing}, true
}

// A frame whose last occupant has left and that no run's endpoint names
// loses its record (remove_frame), so a free entity leaves no frame
// behind. A belt end's frame stays while a run names it, so the run
// reconnects when a belt returns to its cell.
release_empty_frame :: proc(entities: ^Entities, frame: Frame_Id) {
	if frame == BLOCK_FRAME || frame_cell_count(&entities.frames, frame) > 0 {
		return
	}
	for run in entities.belt_runs.entries {
		if run.alive && (run.endpoints[BELT_RUN_START].frame == frame || run.endpoints[BELT_RUN_END].frame == frame) {
			return
		}
	}
	remove_frame(&entities.frames, frame)
}

// The lines.

// The belt run arriving at a pole, the first in pool order.
belt_run_arriving_at_pole :: proc(entities: ^Entities, pole: Entity_Handle) -> (index: int, found: bool) {
	for run, candidate in entities.belt_runs.entries {
		if belt_run_in_lines(run) && run.endpoints[BELT_RUN_END].pole == pole {
			return candidate, true
		}
	}
	return 0, false
}

// The links runs add to compute_belt_links: the flat belt a run starts at
// feeds the run instead of its own output cell, a run arriving at a pole
// continues into the run leaving it, and a run ending at a belt end
// continues into that belt. The claims that follow settle a belt fed
// twice.
link_belt_runs :: proc(entities: ^Entities, links: Belt_Links) {
	for run, index in entities.belt_runs.entries {
		if !belt_run_in_lines(run) {
			continue
		}
		start := run.endpoints[BELT_RUN_START]
		if start.pole == NO_ENTITY {
			if belt := belt_at_run_end(entities, start); belt != nil {
				links.belts[belt.handle.index] = Belt_Link{target = run.handle, connection = .Straight}
			}
		} else if feeder, found := belt_run_arriving_at_pole(entities, start.pole); found {
			links.runs[feeder] = Belt_Link{target = run.handle, connection = .Straight}
		}
		if end := run.endpoints[BELT_RUN_END]; end.pole == NO_ENTITY {
			if belt := belt_at_run_end(entities, end); belt != nil {
				links.runs[index] = Belt_Link{target = belt.handle, connection = .Straight}
			}
		}
	}
}

// The save: the end of the frame tables (entity_frames.odin,
// write_frame_tables).

// Every live pole with its frame, which Entity_Common leaves out of the
// pool's bytes; the frame tables' list skips the poles, since it is read
// before this table.
belt_pole_frame_records :: proc(entities: ^Entities) -> []Entity_Frame_Record {
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	for pole in entities.belt_poles.entries {
		if pole.alive {
			append(&records, Entity_Frame_Record{handle = pole.handle, frame = pole.frame})
		}
	}
	return records[:]
}

// The pole pool, the poles' frames and the run pool, at the end of the
// frame tables. A world that never had a pole or a run writes nothing
// here, so its bytes and its state hash are those of a build before runs.
write_belt_run_tables :: proc(bytes: ^[dynamic]byte, entities: ^Entities) {
	if len(entities.belt_poles.entries) == 0 && len(entities.belt_runs.entries) == 0 {
		return
	}
	write_pool(bytes, &entities.belt_poles)
	write_list(bytes, belt_pole_frame_records(entities))
	write_pool(bytes, &entities.belt_runs)
}

// A live run's endpoints name known frames and live poles standing in
// those frames and cells, and its start frame's pitch gives its curve
// again.
restore_belt_run_curve :: proc(entities: ^Entities, run: ^Belt_Run) -> bool {
	for endpoint in run.endpoints {
		if _, found := find_frame(&entities.frames, endpoint.frame); !found {
			return false
		}
		if endpoint.pole == NO_ENTITY {
			continue
		}
		pole := pool_get(&entities.belt_poles, endpoint.pole)
		if pole == nil || pole.frame != endpoint.frame || pole.origin != endpoint.cell {
			return false
		}
	}
	frame, _ := find_frame(&entities.frames, run.endpoints[BELT_RUN_START].frame)
	run.curve = belt_run_curve(run.control_points, frame.pitch_millimetres)
	return true
}

// See write_belt_run_tables. A save that ends before them loads with no
// poles and no runs.
read_belt_run_tables :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool {
	clear(&entities.belt_poles.entries)
	clear(&entities.belt_poles.free)
	clear(&entities.belt_runs.entries)
	clear(&entities.belt_runs.free)
	if bytes_left(reader^) == 0 {
		return true
	}
	read_pool(reader, &entities.belt_poles, .Belt_Pole, machines) or_return
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		pole := pool_get(&entities.belt_poles, record.handle)
		if _, found := find_frame(&entities.frames, record.frame); pole == nil || !found {
			return false
		}
		pole.frame = record.frame
	}
	read_pool(reader, &entities.belt_runs, .Belt_Run, machines) or_return
	for &run in entities.belt_runs.entries {
		if run.alive && !restore_belt_run_curve(entities, &run) {
			return false
		}
	}
	return true
}
