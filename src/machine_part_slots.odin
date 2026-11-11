package game

import "core:fmt"

// The generic slots a vessel's structure piece brings (work item 0361,
// doc/vessels.md): boxes of cells round or inside its footprint that
// equipment of the box's size goes into. A slot is a box of the
// unrotated footprint's cells; it turns with the piece. Nothing records
// what fills a slot: the equipment standing in its box is the filler
// (part_slot_filler, vessel.odin). An inside slot's cells are not held by
// the piece (machine_held_cells), so an empty ring is hollow.

MAXIMUM_PART_SLOTS :: 8

// Inside the footprint, outside it beside a face, or under its bottom.
Part_Slot_Side :: enum u8 {
	Inside,
	Outside,
	Underneath,
}

@(rodata)
part_slot_side_names := [Part_Slot_Side]string {
	.Inside     = "inside",
	.Outside    = "outside",
	.Underneath = "underneath",
}

// As written in data/machines.sjson: from and to inclusive, cells of the
// unrotated footprint (x along the width, y up, z along the depth).
Part_Slot_Definition :: struct {
	side: string,
	from: Machine_Cell_Definition,
	to:   Machine_Cell_Definition,
}

Part_Slot :: struct {
	box:  Cell_Box,
	side: Part_Slot_Side,
}

// Whether a box lies where its side says, against the unrotated footprint
// (x, y, z as Machine.footprint): an inside box in the footprint; an
// underneath box under it (to.y is -1) and overlapping it in x and z; an
// outside box clear of it, not wholly below it, and touching one face (to
// is -1 or from is the size on that axis) while overlapping it on the
// other two axes.
part_slot_box_fits_side :: proc(box: Cell_Box, footprint: [3]i32, side: Part_Slot_Side) -> bool {
	overlaps :: proc(box: Cell_Box, footprint: [3]i32, axis: int) -> bool {
		return box.from[axis] < footprint[axis] && box.to[axis] >= 0
	}
	switch side {
	case .Inside:
		for axis in 0 ..< 3 {
			if box.from[axis] < 0 || box.to[axis] >= footprint[axis] {
				return false
			}
		}
		return true
	case .Underneath:
		return box.to.y == -1 && overlaps(box, footprint, 0) && overlaps(box, footprint, 2)
	case .Outside:
		if overlaps(box, footprint, 0) && overlaps(box, footprint, 1) && overlaps(box, footprint, 2) {
			return false
		}
		if box.to.y < 0 {
			return false
		}
		for axis in 0 ..< 3 {
			touches := box.to[axis] == -1 || box.from[axis] == footprint[axis]
			first, second := (axis + 1) % 3, (axis + 2) % 3
			if touches && overlaps(box, footprint, first) && overlaps(box, footprint, second) {
				return true
			}
		}
	}
	return false
}

// A machine's part_slots: only a vessel_part lists them, at most
// MAXIMUM_PART_SLOTS, each of a known side, each corner's component within
// -MAXIMUM_FOOTPRINT_SIZE to 2 * MAXIMUM_FOOTPRINT_SIZE - 1 with from no
// greater than to, fitting its side (part_slot_box_fits_side), no two
// boxes overlapping, and the inside boxes leaving at least one cell of the
// footprint held, so the piece can be aimed at and picked up. The sizes are
// checked against the vessel parts' table (resolve_vessel_part_registry).
validate_part_slots :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if len(definition.part_slots) == 0 {
		return ""
	}
	if kind != .Vessel_Part {
		return fmt.tprintf("machine %q lists part_slots, which only a vessel_part may", definition.id)
	}
	if len(definition.part_slots) > MAXIMUM_PART_SLOTS {
		return fmt.tprintf("machine %q has more than %d part_slots", definition.id, MAXIMUM_PART_SLOTS)
	}
	footprint := [3]i32{i32(definition.footprint.width), i32(definition.footprint.height), i32(definition.footprint.depth)}
	boxes: [MAXIMUM_PART_SLOTS]Cell_Box
	inside_cells := i32(0)
	for slot, index in definition.part_slots {
		side, found := parse_named_enum(part_slot_side_names, slot.side)
		if !found {
			return fmt.tprintf("machine %q part_slots %d has unknown side %q", definition.id, index, slot.side)
		}
		from := [3]int{slot.from.x, slot.from.y, slot.from.z}
		to := [3]int{slot.to.x, slot.to.y, slot.to.z}
		for axis in 0 ..< 3 {
			if from[axis] < -MAXIMUM_FOOTPRINT_SIZE || to[axis] > 2 * MAXIMUM_FOOTPRINT_SIZE - 1 || from[axis] > to[axis] {
				return fmt.tprintf("machine %q part_slots %d is not a box within %d to %d", definition.id, index, -MAXIMUM_FOOTPRINT_SIZE, 2 * MAXIMUM_FOOTPRINT_SIZE - 1)
			}
		}
		box := Cell_Box{from = {i32(from.x), i32(from.y), i32(from.z)}, to = {i32(to.x), i32(to.y), i32(to.z)}}
		if !part_slot_box_fits_side(box, footprint, side) {
			return fmt.tprintf("machine %q part_slots %d does not lie %s the footprint", definition.id, index, part_slot_side_phrase(side))
		}
		for earlier in 0 ..< index {
			if cell_boxes_overlap(boxes[earlier], box) {
				return fmt.tprintf("machine %q part_slots %d and %d overlap", definition.id, earlier, index)
			}
		}
		boxes[index] = box
		if side == .Inside {
			cells := part_slot_box_cells(box)
			inside_cells += cells.x * cells.y * cells.z
		}
	}
	// The inside boxes lie in the footprint and do not overlap, so their
	// volumes add up to the cells they take.
	if inside_cells >= footprint.x * footprint.y * footprint.z {
		return fmt.tprintf("machine %q part_slots leave none of its footprint's cells held", definition.id)
	}
	return ""
}

// The side in the refusal's words.
part_slot_side_phrase :: proc(side: Part_Slot_Side) -> string {
	switch side {
	case .Inside:
		return "inside"
	case .Outside:
		return "outside beside a face of"
	case .Underneath:
		return "underneath"
	}
	return ""
}

// Validated before (validate_part_slots).
resolve_part_slots :: proc(definitions: []Part_Slot_Definition) -> (slots: [MAXIMUM_PART_SLOTS]Part_Slot, count: int) {
	for definition in definitions[:min(len(definitions), MAXIMUM_PART_SLOTS)] {
		side, _ := parse_named_enum(part_slot_side_names, definition.side)
		from, to := definition.from, definition.to
		slots[count] = Part_Slot {
			box  = {from = {i32(from.x), i32(from.y), i32(from.z)}, to = {i32(to.x), i32(to.y), i32(to.z)}},
			side = side,
		}
		count += 1
	}
	return slots, count
}

// Whether a cell of the unrotated footprint lies in one of the machine's
// inside slots, which the machine leaves empty (machine_held_cells).
cell_in_inside_slot :: proc(machine: Machine, cell: [3]i32) -> bool {
	slots := machine.part_slots
	for slot in slots[:machine.part_slot_count] {
		if slot.side == .Inside && cell_box_contains(slot.box, cell) {
			return true
		}
	}
	return false
}

// Whether the machine has an inside slot.
machine_has_inside_slot :: proc(machine: Machine) -> bool {
	slots := machine.part_slots
	for slot in slots[:machine.part_slot_count] {
		if slot.side == .Inside {
			return true
		}
	}
	return false
}

// A slot's box on a placed piece, in its frame's cells, inclusive: both
// corners turned as the footprint turns (rotate_footprint_cell is affine,
// so it holds outside the footprint too), then the minimum and the
// maximum, plus the origin.
placed_part_slot_box :: proc(common: Entity_Common, machine: Machine, slot: Part_Slot) -> (low, high: World_Coordinate) {
	width, depth := machine.footprint.x, machine.footprint.z
	first := rotate_footprint_cell({slot.box.from.x, slot.box.from.z}, width, depth, common.rotation)
	second := rotate_footprint_cell({slot.box.to.x, slot.box.to.z}, width, depth, common.rotation)
	low = common.origin + {min(first.x, second.x), slot.box.from.y, min(first.y, second.y)}
	high = common.origin + {max(first.x, second.x), slot.box.to.y, max(first.y, second.y)}
	return low, high
}
