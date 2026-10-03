package game

// Placement on foundation frames (work item 0174, doc/architecture.md,
// Frames). A foundation placed by snapping to a frame's cell joins that
// frame exactly; one placed free starts a new frame with its up along the
// radial at the hit and the yaw of the player's heading rounded to a
// twenty fourth of a turn. Two frames never merge, a frame never
// re-tangents, and the terrain under a frame is not changed. A machine on
// a frame occupies its footprint's cells, which must be free, and stands
// on solid occupants (a foundation) under its bottom cells; a foundation
// needs no support. The cells are integer triples, so the footprint, belt
// and lane logic of the block world runs on a frame unchanged.
//
// On the field (until the slice, 0179, puts the field on Simulation_State)
// the field simulation keeps its foundations and frames in an Entities of
// its own, and a placement is a command queued in the player's tick and
// applied at the end of the tick in order, as the brush edits are
// (drain_field_placements).

Frame_Placement_Refusal :: enum u8 {
	None,
	Unknown_Frame,
	// A footprint cell is taken.
	Occupied,
	// A bottom cell of a machine has no solid occupant under it.
	Unsupported,
}

frame_placement_refusal :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> Frame_Placement_Refusal {
	if _, found := find_frame(&entities.frames, frame); !found {
		return .Unknown_Frame
	}
	definition := machines.machines[machine]
	for cell in footprint_cells(origin, definition.footprint, rotation) {
		if frame_cell_is_occupied(&entities.frames, frame, cell) {
			return .Occupied
		}
		if definition.kind != .Foundation && cell.y == origin.y && !frame_cell_is_solid(&entities.frames, frame, cell - UP) {
			return .Unsupported
		}
	}
	return .None
}

// A machine or a snapped foundation at origin in frame.
place_on_frame :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, frame: Frame_Id, origin: World_Coordinate, rotation: u8) -> (handle: Entity_Handle, refusal: Frame_Placement_Refusal) {
	if refusal = frame_placement_refusal(entities, machines, machine, frame, origin, rotation); refusal != .None {
		return NO_ENTITY, refusal
	}
	return add_entity(entities, machines, machine, origin, rotation, frame), .None
}

// A foundation placed free: a new frame standing on the hit (free_frame_at)
// holding it at cell (0, 0, 0).
place_free_foundation :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, hit: World_Position, heading: [3]i64, pitch_millimetres: int) -> (handle: Entity_Handle, frame: Frame_Id) {
	origin, axes := free_frame_at(hit, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	return add_entity(entities, machines, machine, {}, 0, frame), frame
}

// The field content's foundation, NO_MACHINE when its machines have none
// (a content without machines, as the field tests make).
field_foundation :: proc(content: Field_Simulation_Content) -> Machine_Id {
	if int(content.foundation) >= len(content.machines.machines) || content.machines.machines[content.foundation].kind != .Foundation {
		return NO_MACHINE
	}
	return content.foundation
}

// The first machine of kind foundation, NO_MACHINE when the data has none.
find_foundation_machine :: proc(machines: Machine_Registry) -> Machine_Id {
	for machine, index in machines.machines {
		if machine.kind == .Foundation {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

// The field.

// A place command: a snapped placement names the frame and the cell, a
// free one the hit and the heading its new frame takes; a run (0176,
// belt_run_placement.odin) its two candidates instead.
Field_Placement_Kind :: enum u8 {
	Machine,
	Run,
}

Field_Placement :: struct {
	kind:      Field_Placement_Kind,
	run:       Field_Run_Placement,
	machine:   Machine_Id,
	new_frame: bool,
	frame:     Frame_Id,
	cell:      World_Coordinate,
	hit:       World_Position,
	heading:   [3]i64,
}

Queued_Field_Placement :: struct {
	player:    int,
	placement: Field_Placement,
}

// The frame target and the field target are both cast; the nearer stays
// and the other is cleared, so a brush never digs through a foundation.
aim_field_player_at_frames :: proc(player: ^Field_Player, frames: ^Frame_Table, tuning: Field_Player_Tuning) {
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	player.frame_target = raycast_frames(frames, field_player_eye(player^, tuning), look, tuning.reach)
	switch {
	case !player.frame_target.hit:
	case !player.target.hit || player.frame_target.distance <= player.target.distance:
		player.target = {}
	case:
		player.frame_target = {}
	}
}

// Where Place with the foundation held puts one: against the targeted
// frame's face, or free on the targeted ground.
field_player_placement :: proc(player: Field_Player, foundation: Machine_Id) -> (placement: Field_Placement, wanted: bool) {
	switch {
	case foundation == NO_MACHINE || player.tool != .Foundation:
		return {}, false
	case player.frame_target.hit:
		return Field_Placement{machine = foundation, frame = player.frame_target.frame, cell = player.frame_target.adjacent}, true
	case player.target.hit:
		return Field_Placement{machine = foundation, new_frame = true, hit = player.target.position, heading = field_player_heading(player)}, true
	}
	return {}, false
}

// The frame a placement lands in and its cell; for a free one the frame
// it would start, so the ghost draws where the foundation will be.
field_placement_frame :: proc(frames: ^Frame_Table, placement: Field_Placement, pitch_millimetres: int) -> (frame: Frame, cell: World_Coordinate, found: bool) {
	if placement.new_frame {
		origin, axes := free_frame_at(placement.hit, placement.heading, pitch_millimetres)
		return Frame{origin = origin, axes = axes, pitch_millimetres = pitch_millimetres}, {}, true
	}
	frame, found = find_frame(frames, placement.frame)
	return frame, placement.cell, found
}

// A cell whose box could reach into a player's capsule: its centre within
// the capsule's radius and half the cell's diagonal of the capsule's axis.
// Half the root of three, in ten thousandths, rounded up.
FRAME_CELL_HALF_DIAGONAL_TEN_THOUSANDTHS :: 8661

frame_cell_meets_capsule :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule) -> bool {
	half_diagonal := frame_pitch_units(frame) * FRAME_CELL_HALF_DIAGONAL_TEN_THOUSANDTHS / 10000 + 1
	return field_distance_to_capsule_axis(capsule, frame_cell_centre(frame, cell)) < capsule.radius + half_diagonal
}

field_placement_buries_a_player :: proc(simulation: ^Field_Simulation, tuning: Field_Player_Tuning, frame: Frame, cell: World_Coordinate) -> bool {
	for player in simulation.players {
		if frame_cell_meets_capsule(frame, cell, field_player_capsule(tuning, player.body)) {
			return true
		}
	}
	return false
}

// The refusal of a queued placement, None when it may go ahead.
field_placement_refusal :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: Field_Miner, placement: Field_Placement) -> Field_Edit_Refusal {
	frame, cell, found := field_placement_frame(&simulation.entities.frames, placement, content.foundation_pitch_millimetres)
	switch {
	case !found:
		return .Unknown_Frame
	case inventory_count(player.inventory, content.machines.machines[placement.machine].item) == 0:
		return .Nothing_Held
	case !placement.new_frame && frame_placement_refusal(&simulation.entities, content.machines, placement.machine, placement.frame, cell, 0) != .None:
		return .Frame_Cell_Taken
	case field_placement_buries_a_player(simulation, content.tuning, frame, cell):
		return .Would_Bury_Player
	}
	return .None
}

// The end of the tick, after the brush edits: every queued placement in
// order, each taking one foundation item; then the queue is empty.
drain_field_placements :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content) {
	for queued in simulation.placements {
		player := &simulation.players[queued.player]
		placement := queued.placement
		if placement.kind == .Run {
			drain_field_run_placement(simulation, content, player, placement.run)
			continue
		}
		if refusal := field_placement_refusal(simulation, content, player^, placement); refusal != .None {
			player.refusal, player.refused_material = refusal, .Air
			continue
		}
		if placement.new_frame {
			place_free_foundation(&simulation.entities, content.machines, placement.machine, placement.hit, placement.heading, content.foundation_pitch_millimetres)
		} else {
			place_on_frame(&simulation.entities, content.machines, placement.machine, placement.frame, placement.cell, 0)
		}
		inventory_remove(player.inventory, content.machines.machines[placement.machine].item, 1)
	}
	clear(&simulation.placements)
}

// The save (save_state.odin, write_later_tables).

// An entity off the block frame; Entity_Common.frame is left out of the
// pools' bytes.
Entity_Frame_Record :: struct {
	handle: Entity_Handle,
	frame:  Frame_Id,
}

// Every live entity off frame 0, in pool order. The belt poles' frames
// are saved with their pool after these tables (write_belt_run_tables).
entity_frame_records :: proc(entities: ^Entities) -> []Entity_Frame_Record {
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	for kind in Entity_Kind {
		if kind == .Belt_Pole {
			continue
		}
		for index in 0 ..< entity_pool_length(entities, kind) {
			common := entity_common_at(entities, kind, index)
			if common != nil && common.alive && common.frame != BLOCK_FRAME {
				append(&records, Entity_Frame_Record{handle = common.handle, frame = common.frame})
			}
		}
	}
	return records[:]
}

// The foundations, the frame records, the frame id counter and the
// entities off frame 0, then the belt poles and runs (0176,
// write_belt_run_tables). A world that never had a frame, a foundation, a
// pole or a run writes nothing, so its bytes and its state hash are those
// of a build before frames.
write_frame_tables :: proc(bytes: ^[dynamic]byte, entities: ^Entities) {
	if len(entities.frames.frames) == 0 && len(entities.foundations.entries) == 0 && len(entities.belt_poles.entries) == 0 && len(entities.belt_runs.entries) == 0 {
		return
	}
	write_pool(bytes, &entities.foundations)
	write_list(bytes, entities.frames.frames[:])
	append_u32(bytes, entities.frames.last_id)
	write_list(bytes, entity_frame_records(entities))
	write_belt_run_tables(bytes, entities)
}

// Ids rising from 1 up to the counter, and a pitch the transforms can
// divide by.
frames_are_consistent :: proc(table: Frame_Table) -> bool {
	previous := u32(0)
	for frame in table.frames {
		if u32(frame.id) <= previous || u32(frame.id) > table.last_id || frame.pitch_millimetres < MINIMUM_FOUNDATION_PITCH_MILLIMETRES || frame.pitch_millimetres > MAXIMUM_FOUNDATION_PITCH_MILLIMETRES {
			return false
		}
		previous = u32(frame.id)
	}
	return true
}

// See write_frame_tables. A save without them loads with every entity on
// frame 0: a save from before frames and a new world that never had a
// frame look alike (the header's version did not change, since the
// tables only append), so nothing is logged; no entity moves and no id is
// remapped.
read_frame_tables :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool {
	clear(&entities.foundations.entries)
	clear(&entities.foundations.free)
	clear(&entities.frames.frames)
	entities.frames.last_id = 0
	if bytes_left(reader^) == 0 {
		return read_belt_run_tables(reader, entities, machines)
	}
	read_pool(reader, &entities.foundations, .Foundation, machines) or_return
	read_list(reader, &entities.frames.frames) or_return
	entities.frames.last_id = read_u32(reader) or_return
	frames_are_consistent(entities.frames) or_return
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		common := entity_common(entities, record.handle)
		if _, found := find_frame(&entities.frames, record.frame); common == nil || !found {
			return false
		}
		common.frame = record.frame
	}
	return read_belt_run_tables(reader, entities, machines)
}
