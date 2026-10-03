package game

// The pod (work item 0179, doc/content.md, The pod): the start on the
// field. The session stands it on the floor of the crater at the home
// (0199, crater_relief in generation_planet.odin): a free frame on the
// floor position whose forward is the heading's yaw step (free_frame_at),
// and the pod on it with its bottom row on the floor and its door, the
// model's front, towards the forward. No foundations are laid. The pod
// has no panel, no slots and no item (machines.sjson); its oxygen and its
// bed wait for M15.

// A quarter turn takes the model's front (+x) to the frame's forward (+z),
// so the door faces the heading.
POD_ROTATION :: 1

// The pod's minimum corner: centred on cell (0, 0, 0), an even size's
// extra cell on the high side as the old pad's was, its bottom row on
// cell row 0, whose base is the floor.
pod_origin :: proc(pod: Machine) -> World_Coordinate {
	size := rotated_footprint_size(pod.footprint, POD_ROTATION)
	return {-(size.x - 1) / 2, 0, -(size.z - 1) / 2}
}

// The pod on a new free frame at the floor position, the frame's forward
// the heading's yaw step (a tangent there). It is added directly, as
// place_on_bare_ground adds a machine, since no foundation is under it.
// ok is false when the machines have no pod.
place_pod :: proc(entities: ^Entities, machines: Machine_Registry, floor_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool) {
	pod := find_machine_of_kind(machines, .Pod)
	if pod == NO_MACHINE {
		return BLOCK_FRAME, false
	}
	origin, axes := free_frame_at(floor_position, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	add_entity(entities, machines, pod, pod_origin(machines.machines[pod]), POD_ROTATION, frame)
	return frame, true
}
