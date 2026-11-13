package game

import "generation_seed"

// Cables (work item 0368, doc/fluids.md, Power): every power connection
// is a cable run by hand from one power port to another (machine_ports.odin).
// A cable is one symmetric record of its two port ends, its item (light,
// heavy or trunk, the item deciding what it carries) and its whole
// metres; the table is saved (save_state.odin, write_cable_table) and the
// netlist of power_network.odin is built from it. A cable's span is
// measured from its ends' port points whenever it is laid, aimed at or
// drawn; the netlist never sees a position.
//
// The run and the take up by hand are cable_field.odin's; the draw is
// render_cables.odin's.

// A port of a placed entity, by its index in the machine's ports.
Port_End :: struct {
	entity: Entity_Handle,
	port:   u8,
}

// Saved.
Cable :: struct {
	ends:   [2]Port_End,
	item:   Item_Id,
	metres: u16,
}

// cables is saved; watts (the least of the item's and its two ports'
// capacities, per cable) and port_cable (each end's cable) are derived:
// kept by add_cable and remove_cable, rebuilt by settle_cables. The map
// is only looked up, never iterated.
Cable_Table :: struct {
	cables:     [dynamic]Cable,
	watts:      [dynamic]i64,
	port_cable: map[Port_End]int,
}

// What a run lays: its two ends and its item.
Cable_Placement :: struct {
	ends: [2]Port_End,
	item: Item_Id,
}

destroy_cable_table :: proc(table: ^Cable_Table) {
	delete(table.cables)
	delete(table.watts)
	delete(table.port_cable)
}

// Points.

// The centre of a cell's face: the cell's centre moved half a pitch
// along the frame axis of the face.
frame_face_centre :: proc(frame: Frame, cell: World_Coordinate, face: Direction) -> World_Position {
	pitch := frame_pitch_units(frame)
	offset := direction_offsets[face]
	sum: [3]i64
	for axis in 0 ..< 3 {
		sum += frame.axes[axis] * ((2 * i64(cell[axis]) + 1 + i64(offset[axis])) * pitch)
	}
	return frame.origin + World_Position(sum / (2 * UNIT_VECTOR_ONE))
}

port_point_on_frame :: proc(frame: Frame, common: Entity_Common, machine: Machine, port: int) -> World_Position {
	face := placed_machine_port_face(common, machine, machine.ports[port])
	return frame_face_centre(frame, face.cell, face.face)
}

// A live entity's power port's point; found is false for a dead entity,
// a port that is no power port, or a frame that is gone.
power_port_point :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> (point: World_Position, found: bool) {
	common := entity_common(entities, end.entity)
	if common == nil {
		return {}, false
	}
	machine := machines.machines[common.machine]
	if !machine_port_is_power(machine, int(end.port)) {
		return {}, false
	}
	frame := find_frame(&entities.frames, common.frame) or_return
	return port_point_on_frame(frame, common^, machine, int(end.port)), true
}

// The distance in whole metres, rounded up, at least 1.
chord_metres :: proc(first, second: World_Position) -> i64 {
	length := vector_length(cast([3]i64)(second - first))
	return max(ceiling_divide_i64(length, POSITION_UNITS_PER_METRE), 1)
}

// 0 when either end has no point.
port_span_metres :: proc(entities: ^Entities, machines: Machine_Registry, first, second: Port_End) -> i64 {
	first_point, first_found := power_port_point(entities, machines, first)
	second_point, second_found := power_port_point(entities, machines, second)
	if !first_found || !second_found {
		return 0
	}
	return chord_metres(first_point, second_point)
}

// The watts a cable carries: the least of its item's and both its ports'.
cable_watts :: proc(content: Simulation_Content, entities: ^Entities, cable: Cable) -> i64 {
	watts := i64(0)
	if item_is_cable(content.items, cable.item) {
		watts = i64(content.items.items[cable.item].cable_kilowatts) * 1000
	}
	for end in cable.ends {
		common := entity_common(entities, end.entity)
		if common == nil {
			continue
		}
		machine := content.machines.machines[common.machine]
		if machine_port_is_power(machine, int(end.port)) {
			watts = min(watts, machine.ports[end.port].capacity)
		}
	}
	return watts
}

// Ports.

// The cable on the end, -1 for none.
port_end_cable :: proc(table: ^Cable_Table, end: Port_End) -> int {
	if index, found := table.port_cable[end]; found {
		return index
	}
	return -1
}

// A live entity's power port with no cable on it.
port_end_is_free :: proc(entities: ^Entities, machines: Machine_Registry, end: Port_End) -> bool {
	common := entity_common(entities, end.entity)
	if common == nil || !machine_port_is_power(machines.machines[common.machine], int(end.port)) {
		return false
	}
	return port_end_cable(&entities.cables, end) < 0
}

// The entity's free power port whose point is nearest the point, the
// lowest index on a tie.
free_power_port_nearest :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, point: World_Position) -> (port: int, found: bool) {
	common := entity_common(entities, handle)
	if common == nil {
		return 0, false
	}
	frame := find_frame(&entities.frames, common.frame) or_return
	machine := machines.machines[common.machine]
	best := i64(max(i64))
	for index in 0 ..< machine.port_count {
		end := Port_End{entity = handle, port = u8(index)}
		if !port_end_is_free(entities, machines, end) {
			continue
		}
		offset := cast([3]i64)(port_point_on_frame(frame, common^, machine, index) - point)
		distance := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		if distance < best {
			best, port, found = distance, index, true
		}
	}
	return
}

// Why a cable cannot be laid, in this order, or None: the first end not
// free (Cable_End_Gone), the second not free (No_Free_Port), one entity
// at both ends, a span past the item's, fewer metres held than the span
// (the developer command holds max(i64)), and on two frames a vessel's
// end that is not its connector. A loop is laid (0377: its chord carries
// nothing until then).
cable_placement_refusal :: proc(entities: ^Entities, content: Simulation_Content, placement: Cable_Placement, metres_held: i64) -> Field_Edit_Refusal {
	machines := content.machines
	first, second := placement.ends[0], placement.ends[1]
	switch {
	case !port_end_is_free(entities, machines, first):
		return .Cable_End_Gone
	case !port_end_is_free(entities, machines, second):
		return .No_Free_Port
	case first.entity == second.entity:
		return .Same_Thing
	}
	span := port_span_metres(entities, machines, first, second)
	if !item_is_cable(content.items, placement.item) || span > i64(content.items.items[placement.item].cable_span_metres) {
		return .Cable_Too_Short
	}
	if metres_held < span {
		return .Not_Enough_Cable
	}
	first_frame, second_frame := entity_common(entities, first.entity).frame, entity_common(entities, second.entity).frame
	if first_frame == second_frame {
		return .None
	}
	for end in placement.ends {
		if vessel_index(entities, entity_common(entities, end.entity).frame) < 0 {
			continue
		}
		if _, record, found := vessel_part_of(entities, content.vessel_parts, end.entity); !found || !record.connector {
			return .Not_A_Connector
		}
	}
	return .None
}

// The table.

// Lays the cable and rebuilds the netlist.
add_cable :: proc(entities: ^Entities, content: Simulation_Content, cable: Cable) {
	table := &entities.cables
	append(&table.cables, cable)
	append(&table.watts, cable_watts(content, entities, cable))
	index := len(table.cables) - 1
	for end in cable.ends {
		table.port_cable[end] = index
	}
	rebuild_electric_networks(entities, content.machines)
}

// The cable at index leaves the table, the last one taking its index; no
// rebuild.
remove_cable_record :: proc(table: ^Cable_Table, index: int) {
	for end in table.cables[index].ends {
		delete_key(&table.port_cable, end)
	}
	unordered_remove(&table.cables, index)
	unordered_remove(&table.watts, index)
	if index < len(table.cables) {
		for end in table.cables[index].ends {
			table.port_cable[end] = index
		}
	}
}

// Takes the cable up and rebuilds the netlist.
remove_cable :: proc(entities: ^Entities, machines: Machine_Registry, index: int) {
	remove_cable_record(&entities.cables, index)
	rebuild_electric_networks(entities, machines)
}

// The metres of every cable on the entity, one stack per item in the
// order the items first appear in the table, in the temp allocator.
entity_cable_stacks :: proc(entities: ^Entities, handle: Entity_Handle) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, context.temp_allocator)
	outer: for cable in entities.cables.cables {
		if cable.ends[0].entity != handle && cable.ends[1].entity != handle {
			continue
		}
		for &stack in stacks {
			if stack.item == cable.item {
				stack.count += cable.metres
				continue outer
			}
		}
		append(&stacks, Item_Stack{item = cable.item, count = cable.metres})
	}
	return stacks[:]
}

// Every cable on the entity leaves the table; the caller rebuilds
// (remove_entity's deferred rebuild).
remove_entity_cables :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) {
	table := &entities.cables
	for index := len(table.cables) - 1; index >= 0; index -= 1 {
		if index < len(table.cables) && (table.cables[index].ends[0].entity == handle || table.cables[index].ends[1].entity == handle) {
			remove_cable_record(table, index)
		}
	}
}

// The shape.

port_end_before :: proc(first, second: Port_End) -> bool {
	if first.entity.kind != second.entity.kind {
		return first.entity.kind < second.entity.kind
	}
	if first.entity.index != second.entity.index {
		return first.entity.index < second.entity.index
	}
	return first.port < second.port
}

// The same both ways: the lower end (kind, index, port) first.
cable_hash :: proc(cable: Cable) -> u64 {
	lower, upper := cable.ends[0], cable.ends[1]
	if port_end_before(upper, lower) {
		lower, upper = upper, lower
	}
	hash := u64(0x6361626c65)
	for end in ([2]Port_End{lower, upper}) {
		hash = generation_seed.hash_combine(hash, u64(end.entity.kind) | u64(end.entity.index) << 8 | u64(end.port) << 40)
	}
	return hash
}

// 2 to 4 percent of the span by the cable's hash, at most 70 to 100
// percent of half the lower end's pitch, so the lowest point stays above
// the lower port's cell bottom. Integer, so the aim and the draw agree.
cable_sag_millimetres :: proc(cable: Cable, span_millimetres: i64, lower_pitch_millimetres: int) -> i64 {
	hash := cable_hash(cable)
	sag := span_millimetres * (20 + i64(hash % 21)) / 1000
	limit := i64(lower_pitch_millimetres) / 2 * (70 + i64((hash >> 8) % 31)) / 100
	return min(sag, limit)
}

// The chord at step / steps, lowered along down by the parabola of the
// sag.
cable_curve_point :: proc(first, second: World_Position, down: [3]i64, sag_units: i64, step, steps: int) -> World_Position {
	step, steps := i64(step), i64(max(steps, 1))
	chord := first + (second - first) * World_Position(step) / World_Position(steps)
	lowered := 4 * step * (steps - step) * sag_units / (steps * steps)
	return chord + World_Position(fixed_scale(down, lowered))
}

// The inputs of cable_curve_point for a live cable: its ports' points,
// the first end's frame's down, and its sag by the lower end's pitch.
cable_curve :: proc(entities: ^Entities, machines: Machine_Registry, cable: Cable) -> (first, second: World_Position, down: [3]i64, sag_units: i64, found: bool) {
	first = power_port_point(entities, machines, cable.ends[0]) or_return
	second = power_port_point(entities, machines, cable.ends[1]) or_return
	first_frame := find_frame(&entities.frames, entity_common(entities, cable.ends[0].entity).frame) or_return
	second_frame := find_frame(&entities.frames, entity_common(entities, cable.ends[1].entity).frame) or_return
	down, sag_units = cable_down_and_sag(cable, first_frame, second_frame, first, second)
	return first, second, down, sag_units, true
}

// The first frame's up negated, and the sag in position units by the
// pitch of the lower end's frame (the lower along that down).
cable_down_and_sag :: proc(cable: Cable, first_frame, second_frame: Frame, first, second: World_Position) -> (down: [3]i64, sag_units: i64) {
	down = -first_frame.axes[FRAME_UP]
	lower_pitch := first_frame.pitch_millimetres
	if fixed_dot(cast([3]i64)(second - first), down) > 0 {
		lower_pitch = second_frame.pitch_millimetres
	}
	span_millimetres := vector_length(cast([3]i64)(second - first)) * MILLIMETRES_PER_METRE / POSITION_UNITS_PER_METRE
	return down, millimetres_to_position_units(int(cable_sag_millimetres(cable, span_millimetres, lower_pitch)))
}

// The aim.

CABLE_AIM_RADIUS_MILLIMETRES :: 250
CABLE_AIM_STEP_MILLIMETRES :: 200

// The cable the reticle is on: its curve points every
// CABLE_AIM_STEP_MILLIMETRES tested as field_aimed_torch tests a torch
// (along the look before the terrain or frame hit, within the reach,
// across at most the radius), a cable whose middle lies too far to reach
// any point skipped. The smallest along wins, ties by the smaller across,
// then the lower index; -1 for none.
field_aimed_cable :: proc(entities: ^Entities, machines: Machine_Registry, player: Field_Player, tuning: Field_Player_Tuning) -> int {
	if len(entities.cables.cables) == 0 {
		return -1
	}
	eye := field_player_eye(player, tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	radius := millimetres_to_position_units(CABLE_AIM_RADIUS_MILLIMETRES)
	step_units := millimetres_to_position_units(CABLE_AIM_STEP_MILLIMETRES)
	limit := field_aim_limit(player, tuning)
	best, best_along, best_across := -1, i64(max(i64)), i64(max(i64))
	for cable, index in entities.cables.cables {
		first, second, down, sag, found := cable_curve(entities, machines, cable)
		if !found {
			continue
		}
		chord := vector_length(cast([3]i64)(second - first))
		middle := first + (second - first) / 2
		if vector_length(cast([3]i64)(middle - eye)) > tuning.reach + chord / 2 + sag {
			continue
		}
		steps := int(max(ceiling_divide_i64(chord, step_units), 1))
		for step in 0 ..= steps {
			offset := cast([3]i64)(cable_curve_point(first, second, down, sag, step, steps) - eye)
			along := fixed_dot(offset, look)
			if along <= 0 || along >= limit || vector_length(offset) > tuning.reach {
				continue
			}
			across := vector_length(offset - fixed_scale(look, along))
			if across > radius {
				continue
			}
			if along < best_along || (along == best_along && across < best_across) {
				best, best_along, best_across = index, along, across
			}
		}
	}
	return best
}

// The save (save_state.odin, write_cable_table).

// After the pools are read: a cable whose item reads as none or is no
// cable, whose port is no power port of its entity's machine, or whose
// end the load deleted (deleted_ids, handle_was_deleted) is dropped and
// counted; one whose metres pass MAXIMUM_CABLE_SPAN_METRES keeps that
// many, counted, so taking it up returns no more than any span; an end on
// a dead entity otherwise or two cables on one port end refuse the file.
// Derives watts and port_cable. remap is nil outside a load.
settle_cables :: proc(entities: ^Entities, content: Simulation_Content, remap: ^Content_Remap) -> (dropped, clamped: int, problem: string) {
	table := &entities.cables
	clear(&table.watts)
	clear(&table.port_cable)
	kept := 0
	for cable in table.cables {
		deleted := false
		for end in cable.ends {
			if entity_common(entities, end.entity) != nil {
				continue
			}
			if !handle_was_deleted(remap, end.entity) {
				return dropped, clamped, "the save has a cable whose end is gone"
			}
			deleted = true
		}
		if deleted || !item_is_cable(content.items, cable.item) || !cable_ports_are_power(entities, content.machines, cable) {
			dropped += 1
			continue
		}
		table.cables[kept] = cable
		if cable.metres > MAXIMUM_CABLE_SPAN_METRES {
			table.cables[kept].metres = MAXIMUM_CABLE_SPAN_METRES
			clamped += 1
		}
		kept += 1
	}
	resize(&table.cables, kept)
	for cable, index in table.cables {
		for end in cable.ends {
			if _, taken := table.port_cable[end]; taken {
				return dropped, clamped, "the save has two cables on one port"
			}
			table.port_cable[end] = index
		}
		append(&table.watts, cable_watts(content, entities, cable))
	}
	return dropped, clamped, ""
}

cable_ports_are_power :: proc(entities: ^Entities, machines: Machine_Registry, cable: Cable) -> bool {
	for end in cable.ends {
		common := entity_common(entities, end.entity)
		if common == nil || !machine_port_is_power(machines.machines[common.machine], int(end.port)) {
			return false
		}
	}
	return true
}
