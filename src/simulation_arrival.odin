package game

import "platform"

// The arrival (work item 0200, doc/architecture.md, The field session,
// The arrival): a new world's first ticks are the pod's fall. While it
// falls every player is strapped into the pod's chair (0223) and its
// input frame is cut to the look (arrival_input), in the tick and in the
// prediction; at the end of its last tick, or when the pause menu's Skip
// applies (Skip_Arrival_Command), it lands (land_field_arrival) with the
// pod's hatches closed, telling each strapped player Touchdown_Confirmed:
// the airlock opens the inner one as a player comes to it
// (entity_pod_airlock.odin, 0222).
// Its table follows the felled trees in entities.bin, so it is hashed,
// travels in the join snapshot, and a world loaded or joined past the
// fall never falls again. The presentation (render_arrival.odin) reads it
// and never writes it.

// start_tick is the tick the fall began (the new world's), fall_ticks its
// length (0 for no fall), landed_tick the tick it landed (0 while falling
// or without a fall; ticks start at 1, so 0 is never a landing).
Field_Arrival :: struct {
	start_tick:  u64,
	fall_ticks:  u64,
	landed_tick: u64,
}

// A new world's fall, from start_field_world (not the benchmark's).
begin_field_arrival :: proc(field: ^Field_Simulation, tick: u64, fall_ticks: int) {
	field.arrival = {start_tick = tick, fall_ticks = u64(fall_ticks)}
}

field_arrival_falling :: proc(arrival: Field_Arrival) -> bool {
	return arrival.fall_ticks > 0 && arrival.landed_tick == 0
}

// The hit's tick, settle_ticks before the planned landing: the pod
// rests at its end (rest_field_pod, 0270).
field_arrival_hit_tick :: proc(arrival: Field_Arrival, settle_ticks: int) -> u64 {
	return arrival.start_tick + arrival.fall_ticks - u64(settle_ticks)
}

// Before the hit: the pause menu offers Skip arrival only then, so a
// Skip never cuts the hit's shake and dust short (a Skip arriving later
// still lands).
field_arrival_skippable :: proc(arrival: Field_Arrival, tick: u64, settle_ticks: int) -> bool {
	return field_arrival_falling(arrival) && tick < field_arrival_hit_tick(arrival, settle_ticks)
}

// The fall's last tick has run (or is running).
field_arrival_due :: proc(arrival: Field_Arrival, tick: u64) -> bool {
	return field_arrival_falling(arrival) && tick >= arrival.start_tick + arrival.fall_ticks
}

// The frame a player's tick reads: the look alone while the world falls,
// no walk and no action (0223).
arrival_input :: proc(arrival: Field_Arrival, frame: Input_Frame) -> Input_Frame {
	if field_arrival_falling(arrival) {
		held := frame
		held.move = {}
		held.pressed, held.just_pressed = {}, {}
		return held
	}
	return frame
}

// Every player into the pod's chair for the fall (0223), from
// start_field_world: the players present before it began.
strap_players_for_the_fall :: proc(state: ^Simulation_State, machines: Machine_Registry, tuning: Field_Player_Tuning) {
	for &player in state.players {
		seat_field_player(&state.world.entities, machines, tuning, &player.field, .Strapped)
	}
}

// Lands the fall at the state's tick. The hatches stay closed (0222);
// every strapped player is told touchdown (0223), a Skip's landing too.
// A landing at or before the hit's tick hits first (a Skip, or
// arrival_settle_ticks 0), since the hit's own (tick_field_session_players)
// then never comes.
land_field_arrival :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if field_arrival_falling(state.field.arrival) && state.tick <= field_arrival_hit_tick(state.field.arrival, content.field.pod_rest.settle_ticks) {
		hit_field_arrival(state, content)
	}
	state.field.arrival.landed_tick = state.tick
	for player, index in state.players {
		if player.field.seat == .Strapped {
			append(&state.events, Simulation_Event{player = index, kind = .Touchdown_Confirmed})
		}
	}
}

// The hit (work items 0270, 0271): the crater dug, then the pod rested.
hit_field_arrival :: proc(state: ^Simulation_State, content: Simulation_Content) {
	dig_impact_crater(state)
	update_field_sky_after_edits(&state.field.world)
	rest_field_pod(state, content)
}

// The impact's crater (work item 0271, doc/architecture.md, The arrival):
// a world whose record says crater_at_impact generates whole and its hit
// writes the baked generation into the field.

// Whether the crater stands dug at the tick: from the hit's tick on,
// after a Skip, and from the start of a world without a fall.
impact_crater_dug :: proc(planet: Planet, arrival: Field_Arrival, tick: u64, settle_ticks: int) -> bool {
	return planet.crater_at_impact && !field_arrival_skippable(arrival, tick, settle_ticks)
}

// Every loaded chunk's crater overlay applied in coordinate order
// (apply_field_crater_overlay, the generation computed it); a chunk
// without one costs nothing. The caller updates the sky. Returns how
// many chunks had one and how many samples it wrote.
dig_impact_crater :: proc(state: ^Simulation_State) -> (chunks, applied: int) {
	world := &state.field.world
	for coordinate in sorted_field_chunk_coordinates(world.chunks) {
		chunk := world.chunks[coordinate]
		if chunk.crater_overlay == nil {
			continue
		}
		chunks += 1
		applied += apply_field_crater_overlay(world, chunk)
	}
	return
}

// The pod's rest at the hit (work item 0270, doc/architecture.md, The
// arrival): the pose the pod hit in, its bed in the ground and the
// strapped players re-seated. Integer, from the placed frame and the
// data alone, so every machine rests alike in the same tick.

// Whether the arrival rests the pod at the end of this tick: the hit's
// tick of a fall that does not land in it (a landing rests the pod
// itself, land_field_arrival).
field_arrival_rests_now :: proc(arrival: Field_Arrival, tick: u64, settle_ticks: int) -> bool {
	return field_arrival_falling(arrival) && tick == field_arrival_hit_tick(arrival, settle_ticks) && !field_arrival_due(arrival, tick)
}

// Every material, for the bed's dig.
every_field_material :: proc() -> bit_set[Field_Material] {
	materials: bit_set[Field_Material]
	for material in Field_Material {
		materials += {material}
	}
	return materials
}

// The bed of the rested pod: the ground within half the footprint's
// width plus one sample spacing of the base centre set to the base's
// plane (the sample beyond the rim, so every sample a point on the rim
// interpolates is edited at every spacing), [0] digging what
// stands above it (every material), [1] filling below it with the
// material and tint, unbudgeted. Both level brushes of twice the
// density's range a pass: field_edit_step moves a sample at most the
// rate, and one pass must span saturated ground to saturated air (a rate
// of MAXIMUM_DENSITY stops at density 0, the surface on the sample
// instead of the plane).
pod_bed_edits :: proc(frame: Frame, pod: Entity_Common, machine: Machine, material: Field_Material, tint: u8, spacing_millimetres: int) -> [2]Field_Edit {
	radius := i64(max(machine.footprint.x, machine.footprint.z)) * frame_pitch_units(frame) / 2 + millimetres_to_position_units(spacing_millimetres)
	brush := Field_Brush{shape = .Level, radius = radius, rate = 2 * MAXIMUM_DENSITY}
	centre := pod_base_centre(frame, pod)
	up := frame.axes[FRAME_UP]
	dig := Field_Edit{mode = .Dig, brush = brush, centre = centre, up = up, diggable = every_field_material()}
	fill := Field_Edit{mode = .Place, brush = brush, centre = centre, up = up, material = material, tint = tint, budget = max(i64)}
	return {dig, fill}
}

// The ground the bed fills with: where a ray from a metre above the
// centre meets the ground down along the up within 3 m, the nearest
// sample that is ground, from the hit down a sample in quarter steps
// (the sample nearest the hit itself may be air at the surface). found
// is false when the ray meets no ground.
pod_bed_material :: proc(world: ^Field_World, spacing_millimetres: int, centre: World_Position, up: [3]i64) -> (material: Field_Material, tint: u8, found: bool) {
	metre := i64(POSITION_UNITS_PER_METRE)
	hit := raycast_field(world, spacing_millimetres, centre + World_Position(fixed_scale(up, metre)), -up, 3 * metre)
	if !hit.hit {
		return .Air, 0, false
	}
	quarter := sample_axis_to_position(1, spacing_millimetres) / 4
	for step in i64(0) ..= 4 {
		sample := nearest_field_sample(hit.position - World_Position(fixed_scale(up, step * quarter)), spacing_millimetres)
		if ground := field_world_get_sample(world, sample); ground.density > 0 {
			return ground.material, ground.tint, true
		}
	}
	return .Air, 0, false
}

// The cosine and sine of the rest's lean.
pod_rest_turn :: proc(tilt_degrees: int) -> (cosine, sine: i64) {
	angle := degrees_to_angle_units(tilt_degrees)
	return fixed_cosine(angle), fixed_sine(angle)
}

// Rests the first pod: its frame to pod_rest_pose (set_frame_pose), its
// bed dug and filled (the dug steps go to nobody, the trees over the dug
// ground fall, the sky follows as drain_field_edits ends), then every
// player in the chair re-seated on the rested frame, its look turned with
// the pod, so the camera after the hit looks where the drawn camera
// looked as the descent ended. Nothing without a pod, and tilt 0 rests
// nothing: the placed pose stands, unbedded.
rest_field_pod :: proc(state: ^Simulation_State, content: Simulation_Content) {
	if content.field.pod_rest.tilt_degrees == 0 {
		return
	}
	entities := &state.world.entities
	pod, placed, found := find_pod(entities, content.machines)
	if !found {
		return
	}
	machine := content.machines.machines[pod.machine]
	tilt := content.field.pod_rest.tilt_degrees
	origin, axes := pod_rest_pose(placed, pod, machine, tilt)
	set_frame_pose(&entities.frames, placed.id, origin, axes)
	rested, _ := find_frame(&entities.frames, placed.id)
	bed_pod(state, content, rested, pod, machine)
	up, heading := placed.axes[FRAME_UP], pod_travel_heading(placed, pod, machine)
	cosine, sine := pod_rest_turn(tilt)
	for &player in state.players {
		body := &player.field
		if body.seat == .Standing {
			continue
		}
		look := field_look_direction(body.forward, body.up, body.yaw, body.pitch)
		turned, _ := normalize_fixed(rotate_in_plane(look, up, heading, cosine, sine))
		if !place_body_in_seat(rested, pod, machine, content.field.tuning, body) {
			continue
		}
		body.forward = tangent_of(body.up, turned)
		body.yaw = 0
		body.pitch = clamp(angle_of_sine(fixed_dot(turned, body.up)), -FIELD_PITCH_LIMIT, FIELD_PITCH_LIMIT)
	}
}

// The rested pod's bed (pod_bed_edits), its material read before the
// dig; no fill without ground under the base.
bed_pod :: proc(state: ^Simulation_State, content: Simulation_Content, rested: Frame, pod: Entity_Common, machine: Machine) {
	field := &state.field
	centre := pod_base_centre(rested, pod)
	material, tint, ground := pod_bed_material(&field.world, field.spacing_millimetres, centre, rested.axes[FRAME_UP])
	edits := pod_bed_edits(rested, pod, machine, material, tint, field.spacing_millimetres)
	edits[0].tick = state.tick
	apply_field_edit(&field.world, field.spacing_millimetres, edits[0])
	fell_trees_over_dug_ground(state, content, edits[0])
	if ground {
		apply_field_edit(&field.world, field.spacing_millimetres, edits[1])
	}
	update_field_sky_after_edits(&field.world)
}

// The save table.

// Always in a field world, after the felled trees (write_simulation_state),
// so a save without it is one from before 0200.
write_field_arrival_table :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation) {
	append_u64(bytes, field.arrival.start_tick)
	append_u64(bytes, field.arrival.fall_ticks)
	append_u64(bytes, field.arrival.landed_tick)
}

// A save from before 0200 ends before the table and loads with no fall,
// its hatches as saved, with one log line. False for a fall longer than
// MAXIMUM_ARRIVAL_TICKS or a landing before its start.
read_field_arrival_table :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool {
	field.arrival = {}
	if bytes_left(reader^) == 0 {
		platform.log_printf("save: written before the arrival (0200), the world starts landed")
		return true
	}
	arrival: Field_Arrival
	arrival.start_tick = read_u64(reader) or_return
	arrival.fall_ticks = read_u64(reader) or_return
	arrival.landed_tick = read_u64(reader) or_return
	if arrival.fall_ticks > MAXIMUM_ARRIVAL_TICKS || (arrival.landed_tick != 0 && arrival.landed_tick < arrival.start_tick) {
		return false
	}
	field.arrival = arrival
	return true
}
