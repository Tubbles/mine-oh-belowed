package game

import "platform"

// Vessels (work item 0361, doc/vessels.md): one system builds every
// vessel. A vessel is a frame of the frame table and a Vessel record keyed
// by it (Entities.vessels, sorted by frame id); its parts are entities of
// the vessel parts' pool on that frame, so the occupant index, the
// raycast, the collision and the pick up work on them unchanged. A part
// stores cells only, so the vessel's pose is its frame's alone.
//
// The structure (data/vessel_parts.sjson role structure) brings slots
// (machine_part_slots.odin); equipment goes into a free slot of its size.
// Nothing records what fills a slot: the equipment whose box is the slot's
// is its filler (part_slot_filler), so a load needs no fix-up and two
// pieces offering one box share it. A frame with a vessel record takes
// vessel parts only (frame_placement_refusal's Vessel_Frame), and vessel
// parts stand on vessel frames only (vessel_placement.odin). The vessel's
// last part releases its frame, and the frame's release drops the record
// (release_empty_frame, remove_vessel_record).

// A vessel's part: its common data only (the battery's charge and a
// tank's contents are 0355's and 0356's).
Vessel_Part :: struct {
	using common: Entity_Common,
}

// parts_replaced counts the swaps in place (0365); 0 until then.
Vessel :: struct {
	frame:          Frame_Id,
	parts_replaced: u32,
}

// The record of the vessel on frame, by binary search; -1 for none.
vessel_index :: proc(entities: ^Entities, frame: Frame_Id) -> int {
	low, high := 0, len(entities.vessels)
	for low < high {
		middle := (low + high) / 2
		if entities.vessels[middle].frame < frame {
			low = middle + 1
		} else {
			high = middle
		}
	}
	if low < len(entities.vessels) && entities.vessels[low].frame == frame {
		return low
	}
	return -1
}

// A new vessel: its frame standing on the hit as a free foundation's
// (free_frame_at), the record appended (a new frame's id is the highest,
// so the order holds) and the structure piece with its footprint centred
// on cell (0, 0, 0) (field_footprint_origin).
start_vessel :: proc(entities: ^Entities, machines: Machine_Registry, machine: Machine_Id, hit: World_Position, heading: [3]i64, pitch_millimetres: int, rotation: u8) -> (handle: Entity_Handle, frame: Frame_Id) {
	origin, axes := free_frame_at(hit, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	append(&entities.vessels, Vessel{frame = frame})
	cell := field_footprint_origin({}, machines.machines[machine].footprint, rotation % 4)
	handle = add_entity(entities, machines, machine, cell, rotation, frame)
	return handle, frame
}

// The record of the frame's vessel, once its frame is gone
// (release_empty_frame). Nothing for a frame of no vessel.
remove_vessel_record :: proc(entities: ^Entities, frame: Frame_Id) {
	if index := vessel_index(entities, frame); index >= 0 {
		ordered_remove(&entities.vessels, index)
	}
}

// A live vessel part's common data and its record; found is false for
// any other handle.
vessel_part_of :: proc(entities: ^Entities, registry: Vessel_Part_Registry, handle: Entity_Handle) -> (common: ^Entity_Common, record: Vessel_Part_Record, found: bool) {
	if handle.kind != .Vessel_Part {
		return nil, {}, false
	}
	part := pool_get(&entities.vessel_parts, handle)
	if part == nil {
		return nil, {}, false
	}
	record, found = vessel_part_record(registry, part.machine)
	return &part.common, record, found
}

// Every cell of the box, low to high inclusive, is unoccupied.
part_slot_box_is_free :: proc(entities: ^Entities, frame: Frame_Id, low, high: World_Coordinate) -> bool {
	for y in low.y ..= high.y {
		for z in low.z ..= high.z {
			for x in low.x ..= high.x {
				if frame_cell_is_occupied(&entities.frames, frame, {x, y, z}) {
					return false
				}
			}
		}
	}
	return true
}

// The equipment filling a placed slot box: the vessel part in the box's
// low cell when it is equipment whose origin is that cell and whose box
// is the slot's; NO_ENTITY when the slot is empty or something else
// stands in it.
part_slot_filler :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, low, high: World_Coordinate) -> Entity_Handle {
	handle := entity_at(entities, low, frame)
	common, record, found := vessel_part_of(entities, content.vessel_parts, handle)
	if !found || record.role != .Equipment || common.origin != low || common.origin + World_Coordinate(common.size) - 1 != high {
		return NO_ENTITY
	}
	return handle
}

// Some structure piece on the frame other than excluded has a slot whose
// placed box is low to high.
vessel_slot_offered :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, low, high: World_Coordinate, excluded: Entity_Handle) -> bool {
	for part in entities.vessel_parts.entries {
		if !part.alive || part.frame != frame || part.handle == excluded {
			continue
		}
		if record, found := vessel_part_record(content.vessel_parts, part.machine); !found || record.role != .Structure {
			continue
		}
		machine := content.machines.machines[part.machine]
		slots := machine.part_slots
		for slot in slots[:machine.part_slot_count] {
			slot_low, slot_high := placed_part_slot_box(part.common, machine, slot)
			if slot_low == low && slot_high == high {
				return true
			}
		}
	}
	return false
}

// A held cell of the vessel's structure lies face to face with one of the
// cells (a new piece's, vessel_placement_refusal).
cells_touch_vessel_structure :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, cells: []World_Coordinate) -> bool {
	for cell in cells {
		for offset in direction_offsets {
			_, record, found := vessel_part_of(entities, content.vessel_parts, entity_at(entities, cell + World_Coordinate(offset), frame))
			if found && record.role == .Structure {
				return true
			}
		}
	}
	return false
}

// The structure pieces on the frame but excluded, labelled by the face
// connected set they belong to: union find over the pieces whose held
// cells touch face to face (the six neighbours through the occupant
// index). Labels count up from 0 in the pool order of each set's first
// piece; the map is for lookups only. In the temp allocator. The
// decoupler's split reuses the labels.
vessel_structure_components :: proc(entities: ^Entities, content: Simulation_Content, frame: Frame_Id, excluded: Entity_Handle) -> (labels: map[Entity_Handle]int, count: int) {
	pieces := make([dynamic]Entity_Handle, context.temp_allocator)
	index_of := make(map[Entity_Handle]int, context.temp_allocator)
	for part in entities.vessel_parts.entries {
		if !part.alive || part.frame != frame || part.handle == excluded {
			continue
		}
		if record, found := vessel_part_record(content.vessel_parts, part.machine); found && record.role == .Structure {
			index_of[part.handle] = len(pieces)
			append(&pieces, part.handle)
		}
	}
	parents := make([]int, len(pieces), context.temp_allocator)
	for &parent, index in parents {
		parent = index
	}
	for handle, index in pieces {
		common := entity_common(entities, handle)
		for cell in entity_held_cells(common^, content.machines.machines[common.machine]) {
			for offset in direction_offsets {
				if other, found := index_of[entity_at(entities, cell + World_Coordinate(offset), frame)]; found {
					join_structure_components(parents, index, other)
				}
			}
		}
	}
	labels = make(map[Entity_Handle]int, len(pieces), context.temp_allocator)
	root_labels := make([]int, len(pieces), context.temp_allocator)
	for &label in root_labels {
		label = -1
	}
	for handle, index in pieces {
		root := structure_component_root(parents, index)
		if root_labels[root] < 0 {
			root_labels[root] = count
			count += 1
		}
		labels[handle] = root_labels[root]
	}
	return labels, count
}

// The root of a piece's set, the path halved on the way.
structure_component_root :: proc(parents: []int, index: int) -> int {
	root := index
	for parents[root] != root {
		parents[root] = parents[parents[root]]
		root = parents[root]
	}
	return root
}

// The two pieces' sets as one, the lower index the root.
join_structure_components :: proc(parents: []int, first, second: int) {
	first_root, second_root := structure_component_root(parents, first), structure_component_root(parents, second)
	if first_root < second_root {
		parents[second_root] = first_root
	} else if second_root < first_root {
		parents[first_root] = second_root
	}
}

// Why a vessel part may not be taken off (decision 8 of 0361): a
// structure piece whose filled slot no other piece offers holds its
// equipment (Holds_Equipment), and one whose removal leaves the rest of
// the structure in more than one face connected set holds the vessel
// together (Holds_The_Vessel_Together). Equipment, and anything else,
// always comes off: None.
vessel_part_removal_refusal :: proc(entities: ^Entities, content: Simulation_Content, handle: Entity_Handle) -> Field_Edit_Refusal {
	common, record, found := vessel_part_of(entities, content.vessel_parts, handle)
	if !found || record.role != .Structure {
		return .None
	}
	piece := common^
	machine := content.machines.machines[piece.machine]
	slots := machine.part_slots
	for slot in slots[:machine.part_slot_count] {
		low, high := placed_part_slot_box(piece, machine, slot)
		if part_slot_filler(entities, content, piece.frame, low, high) != NO_ENTITY && !vessel_slot_offered(entities, content, piece.frame, low, high, handle) {
			return .Holds_Equipment
		}
	}
	if _, count := vessel_structure_components(entities, content, piece.frame, handle); count > 1 {
		return .Holds_The_Vessel_Together
	}
	return .None
}

// The live control units on the frame (one a vessel, One_Control_Unit).
vessel_control_unit_count :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> int {
	count := 0
	for part in entities.vessel_parts.entries {
		if part.alive && part.frame == frame && machines.machines[part.machine].kind == .Vessel_Control_Unit {
			count += 1
		}
	}
	return count
}

// How far under a vessel's lowest row the ground still counts as the
// vessel's (point_in_a_vessel): a vessel stands on uneven ground with no
// flatness check, so the ground in a ring's hollow may lie below its
// frame's bottom row.
VESSEL_EXTENT_DEPTH_CELLS :: MAXIMUM_FOOTPRINT_SIZE

// The box round a vessel's parts in its frame's cells, inclusive: their
// footprints and their slots' boxes, so a ring's hollow and the room
// beside it are the vessel's. found is false for a frame without parts.
vessel_extent :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> (extent: Cell_Box, found: bool) {
	for part in entities.vessel_parts.entries {
		if !part.alive || part.frame != frame {
			continue
		}
		machine := machines.machines[part.machine]
		extent, found = grow_cell_box(extent, found, Cell_Box{from = cast([3]i32)part.origin, to = cast([3]i32)part.origin + part.size - 1})
		slots := machine.part_slots
		for slot in slots[:machine.part_slot_count] {
			low, high := placed_part_slot_box(part.common, machine, slot)
			extent, found = grow_cell_box(extent, found, Cell_Box{from = cast([3]i32)low, to = cast([3]i32)high})
		}
	}
	return extent, found
}

// The box grown to take in the other, or the other when there was none.
grow_cell_box :: proc(box: Cell_Box, found: bool, other: Cell_Box) -> (Cell_Box, bool) {
	if !found {
		return other, true
	}
	grown := box
	for axis in 0 ..< 3 {
		grown.from[axis] = min(grown.from[axis], other.from[axis])
		grown.to[axis] = max(grown.to[axis], other.to[axis])
	}
	return grown, true
}

// Whether a point lies in a vessel's extent (vessel_extent) or in the
// ground under it, down to VESSEL_EXTENT_DEPTH_CELLS below its lowest row:
// a new vessel begun there would stand in the first one's room, a ring's
// hollow or a slot beside it (Inside_A_Vessel).
point_in_a_vessel :: proc(entities: ^Entities, machines: Machine_Registry, point: World_Position) -> bool {
	for vessel in entities.vessels {
		frame, frame_found := find_frame(&entities.frames, vessel.frame)
		extent, found := vessel_extent(entities, machines, vessel.frame)
		if !frame_found || !found {
			continue
		}
		extent.from.y -= VESSEL_EXTENT_DEPTH_CELLS
		if cell_box_contains(extent, cast([3]i32)world_to_frame_cell(frame, point)) {
			return true
		}
	}
	return false
}

// The save (save_state.odin, write_simulation_state).

// Every live part with its frame, which Entity_Common leaves out of the
// pool's bytes, in pool order.
vessel_part_frame_records :: proc(entities: ^Entities) -> []Entity_Frame_Record {
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	for part in entities.vessel_parts.entries {
		if part.alive {
			append(&records, Entity_Frame_Record{handle = part.handle, frame = part.frame})
		}
	}
	return records[:]
}

// In a field world, always, last (after the water bodies' table): the
// parts' pool, the parts' frames and the vessel records. The frame tables
// and the wear table, read before it, skip the parts.
write_vessel_tables :: proc(bytes: ^[dynamic]byte, entities: ^Entities) {
	write_pool(bytes, &entities.vessel_parts)
	write_list(bytes, vessel_part_frame_records(entities))
	write_list(bytes, entities.vessels[:])
}

// See write_vessel_tables. A save from before 0361 ends before the table
// and loads with no vessels and one log line. False for a live part whose
// machine is of no vessel kind, a frame record naming a dead part or an
// unknown frame, vessel records out of order or naming no frame, or a
// live part on a frame of no vessel. The occupancy follows
// (rebuild_entity_cells).
read_vessel_tables :: proc(reader: ^Byte_Reader, entities: ^Entities, machines: Machine_Registry) -> bool {
	clear(&entities.vessel_parts.entries)
	clear(&entities.vessel_parts.free)
	clear(&entities.vessels)
	if bytes_left(reader^) == 0 {
		platform.log_printf("save: written before vessels (0361), no vessels")
		return true
	}
	read_pool(reader, &entities.vessel_parts, .Vessel_Part, machines) or_return
	for part in entities.vessel_parts.entries {
		if part.alive && !machine_kind_is_vessel(machines.machines[part.machine].kind) {
			return false
		}
	}
	records := make([dynamic]Entity_Frame_Record, context.temp_allocator)
	read_list(reader, &records) or_return
	for record in records {
		part := pool_get(&entities.vessel_parts, record.handle)
		if _, found := find_frame(&entities.frames, record.frame); part == nil || !found || record.frame == BLOCK_FRAME {
			return false
		}
		part.frame = record.frame
	}
	read_list(reader, &entities.vessels) or_return
	previous := BLOCK_FRAME
	for vessel in entities.vessels {
		if _, found := find_frame(&entities.frames, vessel.frame); vessel.frame <= previous || !found {
			return false
		}
		previous = vessel.frame
	}
	for part in entities.vessel_parts.entries {
		if part.alive && vessel_index(entities, part.frame) < 0 {
			return false
		}
	}
	return true
}
