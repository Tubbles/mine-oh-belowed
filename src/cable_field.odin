package game

// Running a cable by hand on the field (work item 0368, doc/input.md,
// Bindings; cable.odin), and a pipe the same way (0374) between fluid
// ports. With a cable held, Place on a thing with a free power port (a
// free fluid port with a pipe held) takes the first end onto the port of
// that kind nearest the aimed face's centre and begins the run, a mode the
// player carries; Place on a second thing lays it there and takes its
// metres. Mine takes the run back,
// another hotbar slot ends it, and its first end gone or taken
// ends it with Cable_End_Gone. With no run and any tool held, Mine held
// on an aimed cable takes it up after PICK_UP_SECONDS. The run's begin,
// end and take back are player state set in the player's tick from its
// input frame; the cable laid and the cable taken up are placements the
// drain checks again in player order, so nothing new travels in the
// lockstep. The prediction (0182) runs the movement only, so the run and
// the take up the HUD shows are the confirmed tick's.

// The thing the player aims at on a frame and its free port of the kind
// nearest the centre of the hit face.
field_aimed_free_port :: proc(entities: ^Entities, machines: Machine_Registry, body: Field_Player, kind: Machine_Port_Kind) -> (end: Port_End, found: bool) {
	target := body.frame_target
	handle := aimed_entity(NO_ENTITY, target)
	if !target.hit || handle == NO_ENTITY {
		return {}, false
	}
	frame := find_frame(&entities.frames, target.frame) or_return
	port := free_port_nearest(entities, machines, handle, frame_face_centre(frame, target.cell, target.face), kind) or_return
	return Port_End{entity = handle, port = u8(port)}, true
}

// Called in the player's tick right after the move and the aim (0368).
// Ends a run that lost its tool or slot silently (a held line of the other
// kind than its first end's port is a lost tool), one whose first end is
// gone or taken with Cable_End_Gone. During a run Mine pressed takes it
// back, Place on a second thing queues the cable or tells why not and
// keeps the run, and Mine held does nothing else; Back does nothing, since
// its control carries Sneak too. With no run, a cable or pipe held and
// Place pressed on a thing begins one; otherwise the take up advances, and
// on every other tick its count is zero. took_dig: the Mine went to the
// cable, so the caller strips it from the felling, the pick up and the
// brush.
update_field_cable_tool :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool) {
	player := &state.players[index]
	body := &player.field
	entities := &state.world.entities
	kind, runs := field_tool_line_kind(body.tool)
	if body.cable_run {
		start_kind, start_found := port_end_kind(entities, content.machines, body.cable_start)
		if !runs || int(body.cable_slot) != player.selected_hotbar_slot || (start_found && start_kind != kind) {
			body.cable_run = false
		}
	}
	if body.cable_run && !port_end_is_free(entities, content.machines, body.cable_start) {
		body.cable_run = false
		player.field_refusal = .Cable_End_Gone
	}
	if body.cable_run {
		body.cable_take_up_ticks = 0
		switch {
		case .Dig in input.just_pressed:
			body.cable_run = false
		case .Place in input.just_pressed:
			queue_field_cable(state, content, index)
		}
		return .Dig in input.held || .Dig in input.just_pressed
	}
	if runs && .Place in input.just_pressed {
		body.cable_take_up_ticks = 0
		start, found := field_aimed_free_port(entities, content.machines, body^, kind)
		if !found {
			player.field_refusal = .No_Free_Port
			return false
		}
		body.cable_run, body.cable_start, body.cable_slot = true, start, u8(player.selected_hotbar_slot)
		return false
	}
	return advance_field_cable_take_up(state, content, index, input)
}

// The run's second end: the cable queued, or the refusal told and the run
// kept.
queue_field_cable :: proc(state: ^Simulation_State, content: Simulation_Content, index: int) {
	player := &state.players[index]
	kind, _ := field_tool_line_kind(player.field.tool)
	end, found := field_aimed_free_port(&state.world.entities, content.machines, player.field, kind)
	if !found {
		player.field_refusal = .No_Free_Port
		return
	}
	placement := Cable_Placement{ends = {player.field.cable_start, end}, item = selected_hotbar_stack(player^).item}
	held := i64(inventory_count(player.inventory, placement.item))
	if refusal := cable_placement_refusal(&state.world.entities, content, placement, held); refusal != .None {
		player.field_refusal = refusal
		return
	}
	append(&state.field.placements, Queued_Field_Placement{player = index, placement = Field_Placement{kind = .Cable, cable = placement}})
}

// Mine held on an aimed cable counts towards PICK_UP_SECONDS, as a pick
// up does; another cable aimed restarts the count, metres that do not fit
// tell Inventory_Full, and at the end the taking up is queued. took_dig
// whenever a cable is aimed and Mine is held. Without Mine held no cable
// is aimed at all, so the tick walks the cables only while Mine is held.
advance_field_cable_take_up :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool) {
	player := &state.players[index]
	body := &player.field
	entities := &state.world.entities
	if .Dig not_in input.held {
		body.cable_take_up_ticks = 0
		return false
	}
	aimed := field_aimed_cable(entities, content.machines, body^, content.field.tuning)
	if aimed < 0 {
		body.cable_take_up_ticks = 0
		return false
	}
	cable := entities.cables.cables[aimed]
	if cable.ends[0] != body.cable_take_up {
		body.cable_take_up, body.cable_take_up_ticks = cable.ends[0], 0
	}
	if !inventory_fits_all(player.inventory, content.items, []Item_Stack{{item = cable.item, count = cable.metres}}) {
		player.field_refusal = .Inventory_Full
		body.cable_take_up_ticks = 0
		return true
	}
	body.cable_take_up_ticks += 1
	if body.cable_take_up_ticks >= mining_required_ticks(PICK_UP_SECONDS, state.tick_rate) {
		append(&state.field.placements, Queued_Field_Placement{player = index, placement = Field_Placement{kind = .Cable_Removal, cable = {ends = {cable.ends[0], {}}}}})
		body.cable_take_up_ticks = 0
	}
	return true
}

// At the drain: the cable checked again against the world the commands
// before it left; refused, the refusal is told and the run stays (ended
// for Cable_End_Gone); else the span's metres leave the inventory, the
// cable is laid, counted (a cable only), and the run ends.
drain_field_cable :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, placement: Cable_Placement) {
	entities := &state.world.entities
	refusal := cable_placement_refusal(entities, content, placement, i64(inventory_count(player.inventory, placement.item)))
	if refusal != .None {
		player.field_refusal = refusal
		if refusal == .Cable_End_Gone {
			player.field.cable_run = false
		}
		return
	}
	metres := port_span_metres(entities, content.machines, placement.ends[0], placement.ends[1])
	inventory_remove(player.inventory, placement.item, int(metres))
	add_cable(entities, content, Cable{ends = placement.ends, item = placement.item, metres = u16(metres)})
	if item_is_cable(content.items, placement.item) {
		state.records.statistics.cables_run += 1
	}
	player.field.cable_run = false
}

// At the drain: the cable found again by its end; gone, nothing; its
// metres not fitting, Inventory_Full; else taken up into the inventory.
drain_field_cable_removal :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, end: Port_End) {
	entities := &state.world.entities
	index := port_end_cable(&entities.cables, end)
	if index < 0 {
		return
	}
	cable := entities.cables.cables[index]
	if !inventory_fits_all(player.inventory, content.items, []Item_Stack{{item = cable.item, count = cable.metres}}) {
		player.field_refusal = .Inventory_Full
		return
	}
	remove_cable(entities, content.machines, index)
	add_picked_up(player, content.items, cable.item, int(cable.metres))
}

// Where a carried run reaches the player's hand: 300 mm below the eye and
// 250 mm to its right.
cable_hand_point :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> World_Position {
	down := fixed_scale(player.up, -millimetres_to_position_units(300))
	right := fixed_scale(field_player_right(player), millimetres_to_position_units(250))
	return field_player_eye(player, tuning) + World_Position(down + right)
}

// The take up's progress as a pick up's (the HUD's ring).
cable_take_up_mining_state :: proc(player: Field_Player, tick_rate: int) -> Mining_State {
	return Mining_State{active = player.cable_take_up_ticks > 0, progress_ticks = player.cable_take_up_ticks, required_ticks = mining_required_ticks(PICK_UP_SECONDS, tick_rate)}
}
