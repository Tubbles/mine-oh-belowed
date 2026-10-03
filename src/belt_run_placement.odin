package game

// Placing belt and pipe runs on the field with the gamepad (work item
// 0176, doc/logistics.md, Runs). With the belt or the pipe run tool held,
// the first Place picks the run's start: the pole or belt end the
// selection assist offers nearest the reticle, else a new pole snapped to
// the targeted frame cell, else a new free pole on the targeted ground.
// The ghost draws the curve from it to the reticle's candidate for the end
// as the player aims, the second Place queues the run on the field
// placement queue (entity_frames.odin), and Back forgets the start. The
// drain validates the run against the world as the placements before it
// left it: the endpoints still exist, the new poles' cells are free and
// carried, the constraints hold. A new pole takes a pole item; the run
// itself takes no item until the slice's content (0179) prices it.

// The assist offers an endpoint whose point lies this close to the
// reticle's ray.
BELT_RUN_ASSIST_RADIUS_MILLIMETRES :: 750

Belt_Run_Candidate_Kind :: enum u8 {
	// A pole or belt end that exists: endpoint.
	Existing,
	// A new pole standing free on hit.
	Free_Pole,
	// A new pole on a frame cell: endpoint's frame and cell.
	Snapped_Pole,
}

Belt_Run_Candidate :: struct {
	kind:     Belt_Run_Candidate_Kind,
	endpoint: Belt_Run_Endpoint,
	hit:      World_Position,
}

// The run command: its kind, its belt or pipe and its two candidates.
Field_Run_Placement :: struct {
	kind:       Belt_Run_Kind,
	machine:    Machine_Id,
	candidates: [2]Belt_Run_Candidate,
}

// What two candidates would make: the endpoints (a new pole's facing
// chosen, its handle still none), the geometry, and the chord new free
// poles take as their heading.
Belt_Run_Plan :: struct {
	endpoints: [2]Belt_Run_Endpoint,
	geometry:  Belt_Run_Geometry,
	chord:     [3]i64,
}

// An endpoint the assist may offer and the point a run would meet it at.
Belt_Run_Option :: struct {
	endpoint: Belt_Run_Endpoint,
	point:    World_Position,
}

// The content's machine when it is of the kind, NO_MACHINE otherwise (a
// test content leaves the ids zero).
field_content_machine :: proc(content: Field_Simulation_Content, machine: Machine_Id, kind: Machine_Kind) -> Machine_Id {
	if int(machine) >= len(content.machines.machines) || content.machines.machines[machine].kind != kind {
		return NO_MACHINE
	}
	return machine
}

// The run a tool lays, found false for another tool or missing machines.
field_run_tool :: proc(content: Field_Simulation_Content, tool: Field_Held_Tool) -> (kind: Belt_Run_Kind, machine: Machine_Id, found: bool) {
	if field_content_machine(content, content.belt_pole, .Belt_Pole) == NO_MACHINE {
		return
	}
	#partial switch tool {
	case .Belt_Run:
		kind, machine = .Belt, field_content_machine(content, content.run_belt, .Belt)
	case .Pipe_Run:
		kind, machine = .Pipe, field_content_machine(content, content.run_pipe, .Pipe)
	case:
		return
	}
	return kind, machine, machine != NO_MACHINE
}

// The assist.

// The option nearest the reticle's ray (look is a unit vector) among those
// in front of the eye within reach and within radius of the ray, -1 for
// none. A tie keeps the first.
nearest_belt_run_option :: proc(options: []Belt_Run_Option, eye: World_Position, look: [3]i64, reach, radius: i64) -> int {
	best, best_across := -1, i64(max(i64))
	for option, index in options {
		offset := cast([3]i64)(option.point - eye)
		along := fixed_dot(offset, look)
		if along <= 0 || vector_length(offset) > reach {
			continue
		}
		across := vector_length(offset - fixed_scale(look, along))
		if across <= radius && across < best_across {
			best, best_across = index, across
		}
	}
	return best
}

// The poles and, for a belt run, the belt ends a run of the kind could
// start (role 0) or end (role 1) at: those without such a run yet.
belt_run_options :: proc(entities: ^Entities, machines: Machine_Registry, kind: Belt_Run_Kind, role: int) -> []Belt_Run_Option {
	options := make([dynamic]Belt_Run_Option, context.temp_allocator)
	for pole in entities.belt_poles.entries {
		endpoint := Belt_Run_Endpoint{pole = pole.handle, frame = pole.frame, cell = pole.origin, facing = pole.rotation}
		if !pole.alive || belt_run_endpoint_taken(entities, kind, endpoint, role) {
			continue
		}
		if point, _, found := belt_run_endpoint_point(entities, machines, endpoint, role); found {
			append(&options, Belt_Run_Option{endpoint = endpoint, point = point})
		}
	}
	for belt in entities.belts.entries {
		endpoint := Belt_Run_Endpoint{frame = belt.frame, cell = belt.origin, facing = belt.rotation}
		if kind != .Belt || !belt.alive || belt.shape != .Flat || belt_run_endpoint_taken(entities, kind, endpoint, role) {
			continue
		}
		if point, _, found := belt_run_endpoint_point(entities, machines, endpoint, role); found {
			append(&options, Belt_Run_Option{endpoint = endpoint, point = point})
		}
	}
	return options[:]
}

// What Place would pick as the role's endpoint: the assist's option, else
// a new pole on the targeted frame cell, else one on the targeted ground.
field_run_candidate :: proc(player: Field_Player, entities: ^Entities, content: Field_Simulation_Content, kind: Belt_Run_Kind, role: int) -> (candidate: Belt_Run_Candidate, found: bool) {
	options := belt_run_options(entities, content.machines, kind, role)
	eye := field_player_eye(player, content.tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	nearest := nearest_belt_run_option(options, eye, look, content.tuning.reach, millimetres_to_position_units(BELT_RUN_ASSIST_RADIUS_MILLIMETRES))
	switch {
	case nearest >= 0:
		return Belt_Run_Candidate{kind = .Existing, endpoint = options[nearest].endpoint}, true
	case player.frame_target.hit:
		return Belt_Run_Candidate{kind = .Snapped_Pole, endpoint = {frame = player.frame_target.frame, cell = player.frame_target.adjacent}}, true
	case player.target.hit:
		return Belt_Run_Candidate{kind = .Free_Pole, hit = player.target.position}, true
	}
	return {}, false
}

// The plan.

// A candidate's point and up before its facing is known: a pole's top
// does not depend on it, and a belt end's facing is the belt's.
belt_run_candidate_point :: proc(entities: ^Entities, content: Field_Simulation_Content, candidate: Belt_Run_Candidate, role: int) -> (point: World_Position, found: bool) {
	height := int(content.machines.machines[content.belt_pole].height_millimetres)
	switch candidate.kind {
	case .Existing:
		point, _ = belt_run_endpoint_point(entities, content.machines, candidate.endpoint, role) or_return
		return point, true
	case .Free_Pole:
		up, ok := normalize_fixed(cast([3]i64)candidate.hit)
		return candidate.hit + World_Position(fixed_scale(up, millimetres_to_position_units(height))), ok
	case .Snapped_Pole:
		frame := find_frame(&entities.frames, candidate.endpoint.frame) or_return
		return belt_pole_top(frame, candidate.endpoint.cell, height), true
	}
	return {}, false
}

// A candidate's endpoint for the role and the frame it stands in once the
// chord is known: an existing pole faces as belt_pole_endpoint says, a
// new free pole the yaw step of the chord, a new snapped pole the frame
// direction nearest it.
belt_run_candidate_endpoint :: proc(entities: ^Entities, content: Field_Simulation_Content, kind: Belt_Run_Kind, candidate: Belt_Run_Candidate, role: int, chord: [3]i64) -> (endpoint: Belt_Run_Endpoint, frame: Frame, found: bool) {
	switch candidate.kind {
	case .Existing:
		endpoint = candidate.endpoint
		if endpoint.pole != NO_ENTITY {
			endpoint = belt_pole_endpoint(entities, endpoint.pole, chord, kind, role) or_return
		}
		frame = find_frame(&entities.frames, endpoint.frame) or_return
		return endpoint, frame, true
	case .Free_Pole:
		origin, axes := free_frame_at(candidate.hit, chord, content.foundation_pitch_millimetres)
		frame = Frame{origin = origin, axes = axes, pitch_millimetres = content.foundation_pitch_millimetres}
		return Belt_Run_Endpoint{facing = BELT_POLE_FREE_ROTATION}, frame, true
	case .Snapped_Pole:
		frame = find_frame(&entities.frames, candidate.endpoint.frame) or_return
		endpoint = candidate.endpoint
		endpoint.facing = frame_facing_towards(frame, chord)
		return endpoint, frame, true
	}
	return
}

// The run two candidates would make, found false when one is gone.
plan_belt_run :: proc(entities: ^Entities, content: Field_Simulation_Content, kind: Belt_Run_Kind, candidates: [2]Belt_Run_Candidate) -> (plan: Belt_Run_Plan, found: bool) {
	for candidate, role in candidates {
		plan.geometry.positions[role] = belt_run_candidate_point(entities, content, candidate, role) or_return
	}
	plan.chord = cast([3]i64)(plan.geometry.positions[BELT_RUN_END] - plan.geometry.positions[BELT_RUN_START])
	for candidate, role in candidates {
		endpoint, frame := belt_run_candidate_endpoint(entities, content, kind, candidate, role, plan.chord) or_return
		plan.endpoints[role] = endpoint
		plan.geometry.directions[role] = frame_facing_direction(frame, endpoint.facing)
		plan.geometry.ups[role] = frame.axes[FRAME_UP]
		if role == BELT_RUN_START {
			plan.geometry.pitch_millimetres = frame.pitch_millimetres
		}
	}
	return plan, true
}

new_pole_count :: proc(candidates: [2]Belt_Run_Candidate) -> int {
	count := 0
	for candidate in candidates {
		count += candidate.kind == .Existing ? 0 : 1
	}
	return count
}

// The refusal of a run command, as the field reports it and as the run
// reports it.
field_run_placement_refusal :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: Field_Miner, run: Field_Run_Placement) -> (refusal: Field_Edit_Refusal, run_refusal: Belt_Run_Refusal) {
	entities := &simulation.entities
	plan, found := plan_belt_run(entities, content, run.kind, run.candidates)
	if !found {
		return .Run_Refused, .Unknown_Endpoint
	}
	if inventory_count(player.inventory, content.machines.machines[content.belt_pole].item) < new_pole_count(run.candidates) {
		return .Nothing_Held, .None
	}
	for candidate, role in run.candidates {
		switch candidate.kind {
		case .Existing:
			if endpoint_refusal := belt_run_endpoint_refusal(entities, run.kind, plan.endpoints[role], role, plan.chord); endpoint_refusal != .None {
				return .Run_Refused, endpoint_refusal
			}
		case .Snapped_Pole:
			if frame_placement_refusal(entities, content.machines, content.belt_pole, candidate.endpoint.frame, candidate.endpoint.cell, plan.endpoints[role].facing) != .None {
				return .Run_Refused, .Pole_Blocked
			}
		case .Free_Pole:
			origin, axes := free_frame_at(candidate.hit, plan.chord, content.foundation_pitch_millimetres)
			if field_placement_buries_a_player(simulation, content.tuning, Frame{origin = origin, axes = axes, pitch_millimetres = content.foundation_pitch_millimetres}, {}) {
				return .Would_Bury_Player, .None
			}
		}
	}
	if run.candidates[BELT_RUN_START].kind == .Existing && run.candidates[BELT_RUN_END].kind == .Existing && same_run_endpoint(plan.endpoints[BELT_RUN_START], plan.endpoints[BELT_RUN_END]) {
		return .Run_Refused, .Too_Short
	}
	if shape := belt_run_shape_refusal(plan.geometry, content.belt_runs); shape != .None {
		return .Run_Refused, shape
	}
	return .None, .None
}

// The new poles of a run command, placed; the endpoints with their
// handles.
place_planned_poles :: proc(entities: ^Entities, content: Field_Simulation_Content, run: Field_Run_Placement, plan: Belt_Run_Plan) -> (endpoints: [2]Belt_Run_Endpoint, placed: [2]Entity_Handle) {
	endpoints = plan.endpoints
	for candidate, role in run.candidates {
		switch candidate.kind {
		case .Existing:
			continue
		case .Free_Pole:
			placed[role], _ = place_free_belt_pole(entities, content.machines, content.belt_pole, candidate.hit, plan.chord, content.foundation_pitch_millimetres)
		case .Snapped_Pole:
			placed[role], _ = place_on_frame(entities, content.machines, content.belt_pole, candidate.endpoint.frame, candidate.endpoint.cell, plan.endpoints[role].facing)
		}
		if endpoint, found := belt_pole_endpoint(entities, placed[role], plan.chord, run.kind, role); found {
			endpoints[role] = endpoint
		}
	}
	return
}

// The poles place_planned_poles placed, taken away again with the frames
// a free pole brought (release_empty_frame).
remove_planned_poles :: proc(entities: ^Entities, machines: Machine_Registry, placed: [2]Entity_Handle) {
	for handle in placed {
		if handle != NO_ENTITY {
			remove_entity(entities, machines, handle)
		}
	}
}

// One queued run: refused as the other placements are, or its new poles
// placed (one pole item each) and the run added. Should the run refuse
// after all (the poles stand a rounding off the plan), the poles are taken
// away again and nothing is paid.
drain_field_run_placement :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: ^Field_Miner, run: Field_Run_Placement) {
	if refusal, run_refusal := field_run_placement_refusal(simulation, content, player^, run); refusal != .None {
		player.refusal, player.refused_material, player.run_refusal = refusal, .Air, run_refusal
		return
	}
	entities := &simulation.entities
	plan, _ := plan_belt_run(entities, content, run.kind, run.candidates)
	endpoints, placed := place_planned_poles(entities, content, run, plan)
	if _, refusal := add_belt_run(entities, content.machines, content.belt_runs, run.kind, run.machine, endpoints); refusal != .None {
		remove_planned_poles(entities, content.machines, placed)
		player.refusal, player.refused_material, player.run_refusal = .Run_Refused, .Air, refusal
		return
	}
	inventory_remove(player.inventory, content.machines.machines[content.belt_pole].item, new_pole_count(run.candidates))
}

// The tool.

// Place with a run tool held picks the start, then queues the run to the
// end; Back or a change of tool forgets the start.
update_field_run_tool :: proc(player: ^Field_Player, entities: ^Entities, content: Field_Simulation_Content, input: Field_Player_Input) -> (placement: Field_Placement, wanted: bool) {
	kind, machine, found := field_run_tool(content, player.tool)
	switch {
	case !found || .Back in input.just_pressed:
		player.run_started = false
		return
	case .Place not_in input.just_pressed:
		return
	}
	role := player.run_started ? BELT_RUN_END : BELT_RUN_START
	candidate := field_run_candidate(player^, entities, content, kind, role) or_return
	if !player.run_started {
		player.run_start, player.run_started = candidate, true
		return
	}
	player.run_started = false
	return Field_Placement{kind = .Run, run = Field_Run_Placement{kind = kind, machine = machine, candidates = {player.run_start, candidate}}}, true
}

// The ghost: once the start is picked, the run to the reticle's candidate
// and why it would be refused (shape only; the drain checks the rest).
field_run_ghost :: proc(player: Field_Player, entities: ^Entities, content: Field_Simulation_Content) -> (curve: Belt_Run_Curve, geometry: Belt_Run_Geometry, refusal: Belt_Run_Refusal, found: bool) {
	kind, _, tool_found := field_run_tool(content, player.tool)
	if !tool_found || !player.run_started {
		return
	}
	end := field_run_candidate(player, entities, content, kind, BELT_RUN_END) or_return
	plan := plan_belt_run(entities, content, kind, {player.run_start, end}) or_return
	curve = belt_run_curve(belt_run_control_points(plan.geometry), plan.geometry.pitch_millimetres)
	return curve, plan.geometry, belt_run_shape_refusal(plan.geometry, content.belt_runs), true
}
