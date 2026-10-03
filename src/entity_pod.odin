package game

// The pod (work item 0179, doc/content.md, The pod): the start on the
// field. The session lays it at the home: a free frame on the surface
// position whose forward is the heading's yaw step (place_free_foundation),
// a pad of POD_PAD_SIZE by POD_PAD_SIZE foundations on it, which cost
// nothing, and the pod centred on the pad with its door, the model's
// front, towards the forward. The pod has no panel, no slots and no item
// (machines.sjson); its oxygen and its bed wait for M15.

POD_PAD_SIZE :: 10
// The pad's first cell on x and z: the cells run from it to
// POD_PAD_FIRST_CELL + POD_PAD_SIZE - 1, round the first foundation at
// cell (0, 0, 0) over the surface position.
POD_PAD_FIRST_CELL :: -4
// A quarter turn takes the model's front (+x) to the frame's forward (+z),
// so the door faces the heading.
POD_ROTATION :: 1

// The pad's cells but (0, 0, 0), which the free foundation takes. In the
// temp allocator.
pod_pad_cells :: proc() -> []World_Coordinate {
	cells := make([dynamic]World_Coordinate, 0, POD_PAD_SIZE * POD_PAD_SIZE, context.temp_allocator)
	for z in i32(POD_PAD_FIRST_CELL) ..< POD_PAD_FIRST_CELL + POD_PAD_SIZE {
		for x in i32(POD_PAD_FIRST_CELL) ..< POD_PAD_FIRST_CELL + POD_PAD_SIZE {
			if x != 0 || z != 0 {
				append(&cells, World_Coordinate{x, 0, z})
			}
		}
	}
	return cells[:]
}

// From the surface position (cell (0, 0, 0)'s centre, free_frame_at) to
// the pad's front edge along the frame's forward, in position units.
pod_pad_front_reach :: proc(pitch_millimetres: int) -> i64 {
	pitch := millimetres_to_position_units(pitch_millimetres)
	return (POD_PAD_FIRST_CELL + POD_PAD_SIZE) * pitch - pitch / 2
}

// The pod's minimum corner, centred on the pad and standing on it.
pod_origin :: proc(pod: Machine) -> World_Coordinate {
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	return {POD_PAD_FIRST_CELL + (POD_PAD_SIZE - size.x) / 2, 1, POD_PAD_FIRST_CELL + (POD_PAD_SIZE - size.z) / 2}
}

// The pad and the pod at the surface position, the frame's forward the
// heading's yaw step (a tangent at the surface position). ok is false
// when the machines have no foundation or no pod, or the pod does not fit
// the pad; the pad stays then.
place_pod :: proc(entities: ^Entities, machines: Machine_Registry, surface_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool) {
	foundation := find_foundation_machine(machines)
	pod := find_machine_of_kind(machines, .Pod)
	if foundation == NO_MACHINE || pod == NO_MACHINE {
		return BLOCK_FRAME, false
	}
	_, frame = place_free_foundation(entities, machines, foundation, surface_position, heading, pitch_millimetres)
	for cell in pod_pad_cells() {
		place_on_frame(entities, machines, foundation, frame, cell, 0)
	}
	_, refusal := place_on_frame(entities, machines, pod, frame, pod_origin(machines.machines[pod]), POD_ROTATION)
	return frame, refusal == .None
}
