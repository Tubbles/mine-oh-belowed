package game

// Placing vessel parts (work item 0361, doc/vessels.md, Place). No new
// binding: Place with a part held puts it where the aim says, and Rotate
// turns it as it turns a machine's ghost. With equipment held the nearest
// free slot of its size along the view ray takes it (aim_vessel_slot),
// and aimed at no slot Place does nothing and tells No_Free_Slot. With
// structure held the aimed face of a vessel's structure takes it
// (structure_face_origin), anything else on a frame refuses it
// (Needs_Vessel_Structure), and bare ground starts a new vessel there
// (start_vessel). The placement editor (0215) is not used: a slot or a
// face fixes the place.
//
// Place's press queues the placement in the player's tick
// (queue_vessel_placement) and the drain applies it at the end of the tick
// in order with the other placements (drain_vessel_placement), checking it
// again against the world the commands before it left. Integer only.

Vessel_Placement_Kind :: enum u8 {
	None,
	New_Vessel,
	Structure,
	Equipment,
}

// A new vessel's frame stands on hit facing heading's yaw step, origin is
// the piece's cell there; a structure piece's or equipment's origin is a
// cell of frame.
Vessel_Placement :: struct {
	kind:     Vessel_Placement_Kind,
	machine:  Machine_Id,
	rotation: u8,
	frame:    Frame_Id,
	origin:   World_Coordinate,
	hit:      World_Position,
	heading:  [3]i64,
}

// Where Place with the held vessel part puts it (decision 5 of 0361), or
// the reason it does not; kind None and no refusal when nothing is aimed
// at with structure held, or no vessel part is held.
field_vessel_placement :: proc(entities: ^Entities, content: Simulation_Content, player: Field_Player) -> (placement: Vessel_Placement, refusal: Field_Edit_Refusal) {
	if player.tool != .Vessel_Part || int(player.held_machine) >= len(content.machines.machines) {
		return {}, .None
	}
	record, found := vessel_part_record(content.vessel_parts, player.held_machine)
	if !found {
		return {}, .None
	}
	machine := content.machines.machines[player.held_machine]
	placement = Vessel_Placement{machine = player.held_machine, rotation = player.placement_rotation % 4}
	if record.role == .Equipment {
		frame, low, aimed := aim_vessel_slot(entities, content, player, record.size)
		if !aimed {
			return {}, .No_Free_Slot
		}
		placement.kind, placement.frame, placement.origin = .Equipment, frame, low
		return placement, .None
	}
	target := player.frame_target
	switch {
	case target.hit:
		aimed, aimed_record, is_part := vessel_part_of(entities, content.vessel_parts, entity_from_occupant(target.occupant.handle))
		if !is_part || aimed_record.role != .Structure {
			return {}, .Needs_Vessel_Structure
		}
		axis, sign := face_normal_axis(target.adjacent - target.cell)
		held_size := rotated_footprint_size(machine.footprint, placement.rotation)
		placement.kind, placement.frame = .Structure, target.frame
		placement.origin = structure_face_origin(aimed.origin, aimed.size, target.adjacent, axis, sign, held_size)
		return placement, .None
	case player.target.hit:
		placement.kind = .New_Vessel
		placement.hit, placement.heading = player.target.position, field_player_heading(player)
		placement.origin = field_footprint_origin({}, machine.footprint, placement.rotation)
		return placement, .None
	}
	return {}, .None
}

// A live vessel part whose role is structure.
vessel_part_is_structure :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle) -> bool {
	_, record, found := vessel_part_of(entities, content.vessel_parts, handle)
	return found && record.role == .Structure
}

// The axis and the sign of a face's normal (one component is 1 or -1);
// the up for a zero normal.
face_normal_axis :: proc(normal: World_Coordinate) -> (axis: int, sign: i32) {
	for index in 0 ..< 3 {
		if normal[index] != 0 {
			return index, normal[index] < 0 ? -1 : 1
		}
	}
	return FRAME_UP, 1
}

// The face snap (decision 6 of 0361): along the face's normal the new
// piece starts at the layer of the aimed cell's adjacent cell, growing
// away from the face. Across the face, on each axis, a piece at least as
// wide as the aimed part is centred on it (the odd cell on the high
// side), a narrower one is centred on the aimed cell (offset (size - 1) /
// 2, the centre rule of 0215) and clamped inside the aimed part's extent.
// So rings stack aligned and a small piece follows the aim along a long
// one. Sizes are rotated footprints.
structure_face_origin :: proc(aimed_origin: World_Coordinate, aimed_size: [3]i32, adjacent: World_Coordinate, normal_axis: int, normal_sign: i32, held_size: [3]i32) -> World_Coordinate {
	origin: World_Coordinate
	for axis in 0 ..< 3 {
		switch {
		case axis == normal_axis:
			origin[axis] = normal_sign > 0 ? adjacent[axis] : adjacent[axis] - held_size[axis] + 1
		case held_size[axis] >= aimed_size[axis]:
			origin[axis] = aimed_origin[axis] - (held_size[axis] - aimed_size[axis]) / 2
		case:
			centred := adjacent[axis] - (held_size[axis] - 1) / 2
			origin[axis] = clamp(centred, aimed_origin[axis], aimed_origin[axis] + aimed_size[axis] - held_size[axis])
		}
	}
	return origin
}

// The nearest free slot of the size along the player's view ray: the
// structure pieces on the vessel frames within the reach plus
// MAXIMUM_FOOTPRINT_SIZE pitches (frame_within_reach), their free slots of
// the size, the eye and the look turned into the frame's axes and each
// box into position units, the nearest entry (fixed_ray_box_entry) below the
// aim limit (field_aim_limit: the terrain, frame or trunk hit), the first
// in pool and slot order on a tie. A box holding the eye is skipped, so a
// deck's top slot does not catch a player standing in it.
aim_vessel_slot :: proc(entities: ^Entities, content: Simulation_Content, player: Field_Player, size: int) -> (frame: Frame_Id, low: World_Coordinate, found: bool) {
	tuning := content.field.tuning
	eye := field_player_eye(player, tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	best := field_aim_limit(player, tuning)
	for part in entities.vessel_parts.entries {
		if !part.alive || !vessel_part_is_structure(entities, content, part.handle) || vessel_index(entities, part.frame) < 0 {
			continue
		}
		record, frame_found := find_frame(&entities.frames, part.frame)
		extent := entities.frames.extents[part.frame] or_else {}
		pitch := frame_pitch_units(record)
		if !frame_found || extent.cell_count == 0 || !frame_within_reach(record, extent, eye, tuning.reach + MAXIMUM_FOOTPRINT_SIZE * pitch) {
			continue
		}
		local_eye := frame_local_position(record, eye)
		local_look := frame_local_direction(record, look)
		machine := content.machines.machines[part.machine]
		slots := machine.part_slots
		for slot in slots[:machine.part_slot_count] {
			if vessel_slot_size_of(content.vessel_parts, part_slot_box_cells(slot.box)) != size {
				continue
			}
			slot_low, slot_high := placed_part_slot_box(part.common, machine, slot)
			if !part_slot_box_is_free(entities, part.frame, slot_low, slot_high) {
				continue
			}
			box_low := [3]i64{i64(slot_low.x), i64(slot_low.y), i64(slot_low.z)} * pitch
			box_high := [3]i64{i64(slot_high.x) + 1, i64(slot_high.y) + 1, i64(slot_high.z) + 1} * pitch
			if distance, hit := fixed_ray_box_entry(local_eye, local_look, box_low, box_high); hit && distance < best {
				best, frame, low, found = distance, part.frame, slot_low, true
			}
		}
	}
	return frame, low, found
}

// The cells a placement's part holds (machine_held_cells), on the frame it
// lands in: for a new vessel the frame it would make. found is false for
// None or a frame that is gone.
vessel_placement_cells :: proc(entities: ^Entities, content: Simulation_Content, placement: Vessel_Placement) -> (frame: Frame, cells: []World_Coordinate, found: bool) {
	pitch := content.field.foundation_pitch_millimetres
	switch placement.kind {
	case .None:
		return {}, nil, false
	case .New_Vessel:
		origin, axes := free_frame_at(placement.hit, placement.heading, pitch)
		frame = Frame{origin = origin, axes = axes, pitch_millimetres = pitch}
	case .Structure, .Equipment:
		frame = find_frame(&entities.frames, placement.frame) or_return
	}
	return frame, machine_held_cells(placement.origin, content.machines.machines[placement.machine], placement.rotation), true
}

// The refusal of a vessel placement, None when it may go ahead; the drain
// and the ghost both ask it. Every kind: Nothing_Held, then, but for a new
// vessel, Unknown_Frame when the frame is gone or is no vessel's. A new
// vessel: Inside_A_Vessel where the hit lies in another vessel's extent
// or the ground under it (point_in_a_vessel: a ring's hollow, a slot
// beside it), then Frame_Cell_Taken where its cells meet another frame's
// entities.
// Structure: Frame_Cell_Taken, then Needs_Vessel_Structure without a held
// cell face to face with the vessel's structure. Equipment: No_Free_Slot
// unless a structure piece offers the box and it is free, then
// One_Control_Unit. Then Tree_In_The_Way and Would_Bury_Player.
vessel_placement_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, player: Player, placement: Vessel_Placement) -> Field_Edit_Refusal {
	entities := &state.world.entities
	machine := content.machines.machines[placement.machine]
	if inventory_count(player.inventory, machine.item) == 0 {
		return .Nothing_Held
	}
	if placement.kind != .New_Vessel && vessel_index(entities, placement.frame) < 0 {
		return .Unknown_Frame
	}
	frame, cells, found := vessel_placement_cells(entities, content, placement)
	if !found {
		return .Unknown_Frame
	}
	switch placement.kind {
	case .None:
		return .None
	case .New_Vessel:
		if point_in_a_vessel(entities, content.machines, placement.hit) {
			return .Inside_A_Vessel
		}
		if new_frame_cells_meet_a_frame(&entities.frames, frame, cells) {
			return .Frame_Cell_Taken
		}
	case .Structure:
		for cell in cells {
			if frame_cell_is_occupied(&entities.frames, placement.frame, cell) {
				return .Frame_Cell_Taken
			}
		}
		if !cells_touch_vessel_structure(entities, content, placement.frame, cells) {
			return .Needs_Vessel_Structure
		}
	case .Equipment:
		high := placement.origin + World_Coordinate(rotated_footprint_size(machine.footprint, placement.rotation)) - 1
		if !vessel_slot_offered(entities, content, placement.frame, placement.origin, high, NO_ENTITY) || !part_slot_box_is_free(entities, placement.frame, placement.origin, high) {
			return .No_Free_Slot
		}
		if machine.kind == .Vessel_Control_Unit && vessel_control_unit_count(entities, content.machines, placement.frame) > 0 {
			return .One_Control_Unit
		}
	}
	if placement_cells_meet_a_trunk(state, content, frame, cells) {
		return .Tree_In_The_Way
	}
	for cell in cells {
		if field_placement_buries_a_player(state, content.field.tuning, frame, cell) {
			return .Would_Bury_Player
		}
	}
	return .None
}

// Place's press with a vessel part held (queue_field_player_edit): the
// refusal to the player's field_refusal, or the placement queued for the
// drain.
queue_vessel_placement :: proc(state: ^Simulation_State, content: Simulation_Content, index: int) {
	player := &state.players[index]
	placement, refusal := field_vessel_placement(&state.world.entities, content, player.field)
	if refusal != .None {
		player.field_refusal, player.field_refused_material = refusal, .Air
		return
	}
	if placement.kind == .None {
		return
	}
	append(&state.field.placements, Queued_Field_Placement{player = index, placement = Field_Placement{kind = .Vessel_Part, vessel = placement}})
}

// A placement vessel_placement_refusal let through: a new vessel
// (start_vessel), or the part on its frame. Returns the part.
apply_vessel_placement :: proc(entities: ^Entities, content: Simulation_Content, placement: Vessel_Placement) -> Entity_Handle {
	switch placement.kind {
	case .None:
	case .New_Vessel:
		handle, _ := start_vessel(entities, content.machines, placement.machine, placement.hit, placement.heading, content.field.foundation_pitch_millimetres, placement.rotation)
		return handle
	case .Structure, .Equipment:
		return add_entity(entities, content.machines, placement.machine, placement.origin, placement.rotation, placement.frame)
	}
	return NO_ENTITY
}

// At the drain, in order with the other placements: the refusal, or the
// part placed with one item taken and counted for the quests
// (record_placed).
drain_vessel_placement :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, placement: Vessel_Placement) {
	if refusal := vessel_placement_refusal(state, content, player^, placement); refusal != .None {
		player.field_refusal, player.field_refused_material = refusal, .Air
		return
	}
	apply_vessel_placement(&state.world.entities, content, placement)
	inventory_remove(player.inventory, content.machines.machines[placement.machine].item, 1)
	record_placed(&state.records.statistics, placement.machine)
}
