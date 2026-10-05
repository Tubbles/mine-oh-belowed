package game

import "core:slice"
import "platform"

// The pod (work item 0179, doc/content.md, The pod): the start on the
// field. The session stands it on the floor of the crater at the home
// (0199, crater_relief in generation_planet.odin): a free frame on the
// floor position whose forward is the heading's yaw step (free_frame_at),
// and the pod on it with its bottom row on the floor and its outer hatch,
// the model's front, towards the forward. No foundations are laid. The
// pod has no panel, no slots and no item (machines.sjson).
//
// Its fixtures (work item 0198): the record's fixtures key lists the
// hatches, the locker, the crafting bench and the oxygen generator, each
// its own entity on the pod's frame in cells the pod leaves to it
// (machine_held_cells). A hatch is closed (solid) or open (passable, its
// top row aimable), toggled on its own as an airlock (toggle_hatch from
// entity_pod_airlock.odin, 0222, 0231). The cells the
// hatches seal off from the outside are the pod's sealed room, derived
// from the occupancy (rebuild_sealed_rooms) and never saved. A pod of
// another size in a save (an older build's) is replaced at load
// (upgrade_resized_pods). The first pod's locker is the field world's
// quest reward target (work item 0210, pod_locker).

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
// the heading's yaw step (a tangent there), with its hatches closed and
// its fixtures. It is added directly, as place_on_bare_ground adds a
// machine, since no foundation is under it. ok is false when the
// machines have no pod.
place_pod :: proc(entities: ^Entities, machines: Machine_Registry, floor_position: World_Position, heading: [3]i64, pitch_millimetres: int) -> (frame: Frame_Id, ok: bool) {
	pod := find_machine_of_kind(machines, .Pod)
	if pod == NO_MACHINE {
		return BLOCK_FRAME, false
	}
	origin, axes := free_frame_at(floor_position, heading, pitch_millimetres)
	frame = add_frame(&entities.frames, origin, axes, pitch_millimetres)
	pod_machine := machines.machines[pod]
	add_entity(entities, machines, pod, pod_origin(pod_machine), POD_ROTATION, frame)
	place_pod_fixtures(entities, machines, pod_machine, pod_origin(pod_machine), POD_ROTATION, frame)
	rebuild_sealed_rooms(entities, machines)
	return frame, true
}

// Where fixture index of a pod placed at pod_origin with pod_rotation
// stands: the minimum corner of its box's cells after the pod's turn, and
// its own turn added to the pod's.
pod_fixture_placement :: proc(pod: Machine, pod_origin: World_Coordinate, pod_rotation: u8, index: int) -> (origin: World_Coordinate, rotation: u8) {
	box := pod.fixture_boxes[index]
	first := rotate_footprint_cell({box.from.x, box.from.z}, pod.footprint.x, pod.footprint.z, pod_rotation)
	last := rotate_footprint_cell({box.to.x, box.to.z}, pod.footprint.x, pod.footprint.z, pod_rotation)
	origin = pod_origin + {min(first.x, last.x), box.from.y, min(first.y, last.y)}
	return origin, (pod.fixtures[index].rotation + pod_rotation) % 4
}

// Each fixture of the pod's record as its own entity, in record order.
place_pod_fixtures :: proc(entities: ^Entities, machines: Machine_Registry, pod: Machine, origin: World_Coordinate, rotation: u8, frame: Frame_Id) {
	for index in 0 ..< pod.fixture_count {
		fixture_origin, fixture_rotation := pod_fixture_placement(pod, origin, rotation, index)
		add_entity(entities, machines, pod.fixtures[index].machine, fixture_origin, fixture_rotation, frame)
	}
}

// The first pod's locker, the field world's quest reward target (0210):
// the first alive pod of the foundations' pool in index order, and the
// first alive locker of the chests' pool in index order on its frame.
// found is false when there is no pod or it has no locker.
pod_locker :: proc(entities: ^Entities, machines: Machine_Registry) -> (locker: Entity_Handle, found: bool) {
	for pod in entities.foundations.entries {
		if !pod.alive || int(pod.machine) >= len(machines.machines) || machines.machines[pod.machine].kind != .Pod {
			continue
		}
		for entry in entities.chests.entries {
			if entry.alive && entry.frame == pod.frame && int(entry.machine) < len(machines.machines) && machines.machines[entry.machine].kind == .Locker {
				return entry.handle, true
			}
		}
		return NO_ENTITY, false
	}
	return NO_ENTITY, false
}

// The first alive pod in the foundations' pool order (the one
// field_pod_spawn spawns in) and its frame. found is false without a pod
// or its frame.
find_pod :: proc(entities: ^Entities, machines: Machine_Registry) -> (pod: Entity_Common, frame: Frame, found: bool) {
	for foundation in entities.foundations.entries {
		if foundation.alive && int(foundation.machine) < len(machines.machines) && machines.machines[foundation.machine].kind == .Pod {
			frame, found = find_frame(&entities.frames, foundation.frame)
			return foundation.common, frame, found
		}
	}
	return {}, {}, false
}

// The frame of the first alive pod, for the arrival's presentation
// (0200). found is false without a pod.
find_pod_frame :: proc(entities: ^Entities, machines: Machine_Registry) -> (frame: Frame, found: bool) {
	_, frame, found = find_pod(entities, machines)
	return
}

// The chair (work item 0223).

// The pod's seated eye in the world, from the record through the model's
// frame, integer.
pod_seat_eye :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> World_Position {
	return model_point_in_frame(frame, pod.origin, pod.size, pod.rotation, machine.seat.eye)
}

// The seated look at yaw 0 in the world, a unit vector.
pod_seat_facing :: proc(frame: Frame, pod: Entity_Common, machine: Machine) -> [3]i64 {
	return frame_world_direction(frame, body_direction_to_frame(pod.rotation, machine.seat.facing))
}

// Whether the frame cell lies in the seat's cells, turned and placed as
// pod_fixture_placement turns a fixture's box.
pod_seat_contains_cell :: proc(pod: Entity_Common, machine: Machine, cell: World_Coordinate) -> bool {
	box := machine.seat.cells
	first := rotate_footprint_cell({box.from.x, box.from.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	last := rotate_footprint_cell({box.to.x, box.to.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	low := cast([3]i32)pod.origin + {min(first.x, last.x), box.from.y, min(first.y, last.y)}
	high := cast([3]i32)pod.origin + {max(first.x, last.x), box.to.y, max(first.y, last.y)}
	return cell_box_contains(Cell_Box{from = low, to = high}, cast([3]i32)cell)
}

// The target hits an alive pod with a seat, on its frame, in a seat cell:
// the ray meets the chair's collision boxes, and frame_body_hit puts the
// hit's cell a quarter pitch inside the surface, in the chair's cells.
field_aimed_chair :: proc(entities: ^Entities, machines: Machine_Registry, target: Frame_Raycast_Hit) -> bool {
	if !target.hit {
		return false
	}
	handle := entity_from_occupant(target.occupant.handle)
	if handle.kind != .Foundation {
		return false
	}
	entry := pool_get(&entities.foundations, handle)
	if entry == nil || !entry.alive || int(entry.machine) >= len(machines.machines) {
		return false
	}
	machine := machines.machines[entry.machine]
	return machine.kind == .Pod && machine.seat.present && entry.frame == target.frame && pod_seat_contains_cell(entry.common, machine, target.cell)
}

// Puts the body in the first pod's chair: the eye on the seat's, the up
// the eye's normalised, the feet the standing eye height below it (so
// field_player_eye gives the seat's eye exactly), facing the seat, at
// rest. False, and nothing changed, without a pod that has a seat. The
// capsule then hangs 0.25 m below the cabin floor (eye 1.35 m, eye
// height 1.6 m): it meets nothing, and its edge stays 1.2 m from the
// inner hatch's cells, outside the airlock's reach.
seat_field_player :: proc(entities: ^Entities, machines: Machine_Registry, tuning: Field_Player_Tuning, body: ^Field_Player, seat: Field_Seat) -> bool {
	pod, frame, found := find_pod(entities, machines)
	if !found || !machines.machines[pod.machine].seat.present {
		return false
	}
	machine := machines.machines[pod.machine]
	eye := pod_seat_eye(frame, pod, machine)
	up, ok := normalize_fixed(cast([3]i64)eye)
	if !ok {
		return false
	}
	body.up = up
	body.position = eye - World_Position(fixed_scale(up, tuning.eye_height))
	body.previous_position = body.position
	body.forward = tangent_of(up, pod_seat_facing(frame, pod, machine))
	body.yaw, body.pitch = 0, 0
	body.velocity, body.motion_fraction = {}, {}
	body.on_ground = true
	body.crouching = false
	body.seat = seat
	return true
}

// Out of the chair onto the cabin's floor (field_pod_spawn) at rest; the
// forward, the yaw and the pitch kept, so the look does not jump.
stand_field_player_from_seat :: proc(entities: ^Entities, machines: Machine_Registry, body: ^Field_Player) {
	body.seat = .Standing
	spawn, found := field_pod_spawn(entities, machines)
	if !found {
		return
	}
	body.position = spawn.position
	body.previous_position = spawn.position
	body.up = spawn.up
	body.velocity, body.motion_fraction = {}, {}
	body.on_ground = false
}

// The hatches.

// A hatch's foundations' entry says whether it is open; false for any
// other handle.
hatch_is_open :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	if handle.kind != .Foundation {
		return false
	}
	entry := pool_get(&entities.foundations, handle)
	return entry != nil && entry.hatch_open
}

// For the HUD and the interact answer: whether the handle is a hatch and
// whether it is open.
hatch_state :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> (open: bool, is_hatch: bool) {
	if handle.kind != .Foundation {
		return false, false
	}
	entry := pool_get(&entities.foundations, handle)
	if entry == nil || int(entry.machine) >= len(machines.machines) || machines.machines[entry.machine].kind != .Hatch {
		return false, false
	}
	return entry.hatch_open, true
}

// An open hatch's cells: none solid, every row but the top an open cell
// the player walks and the aiming ray passes through, the top row
// neither, so the player walks under it and the ray stops at it, which
// keeps an open hatch what the HUD's target names (nothing acts on a
// hatch since 0231; a 2 row hatch: the player passes both rows, since it
// collides with solid cells only; the ray passes row 0).
occupy_open_hatch_cells :: proc(entities: ^Entities, common: Entity_Common, occupant: Occupant) {
	passed := Occupant{handle = occupant.handle, flags = occupant.flags - {.Solid} + {.Open}}
	top := Occupant{handle = occupant.handle, flags = occupant.flags - {.Solid}}
	for y in 0 ..< common.size.y {
		for z in 0 ..< common.size.z {
			for x in 0 ..< common.size.x {
				occupy_frame_cell(&entities.frames, common.frame, common.origin + {x, y, z}, y < common.size.y - 1 ? passed : top)
			}
		}
	}
}

// Every field player's capsule, in the temp allocator.
field_player_capsules :: proc(players: []Player, tuning: Field_Player_Tuning) -> []Field_Capsule {
	capsules := make([]Field_Capsule, len(players), context.temp_allocator)
	for player, index in players {
		capsules[index] = field_player_capsule(tuning, player.field)
	}
	return capsules
}

// Whether a capsule reaches into a cell's box: its axis sampled every
// half radius from the bottom to the top, both ends included, against
// the box. Exact enough for a door, where frame_cell_meets_capsule's
// bound would refuse a player standing beside it.
capsule_meets_frame_cell :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule) -> bool {
	return capsule_within_frame_cell(frame, cell, capsule, 0)
}

// Whether a capsule comes within margin of a cell's box, sampled as
// capsule_meets_frame_cell samples it (the airlock's reach, 0222).
capsule_within_frame_cell :: proc(frame: Frame, cell: World_Coordinate, capsule: Field_Capsule, margin: i64) -> bool {
	step := max(capsule.radius / 2, 1)
	pitch := frame_pitch_units(frame)
	along := i64(0)
	for {
		sample := capsule.bottom + World_Position(fixed_scale(capsule.up, min(along, capsule.length)))
		if distance, _ := cell_box_distance(frame_local_position(frame, sample), cell, pitch); distance < capsule.radius + margin {
			return true
		}
		if along >= capsule.length {
			return false
		}
		along += step
	}
}

// Opens or closes a hatch at tick and rebuilds its cells and the sealed
// rooms. False, changing nothing, unless the handle is an alive hatch, or
// when closing and a capsule meets one of its cells (the hatch stays
// open, no toast).
toggle_hatch :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, tick: u64, capsules: []Field_Capsule) -> bool {
	if _, is_hatch := hatch_state(entities, machines, handle); !is_hatch {
		return false
	}
	hatch := pool_get(&entities.foundations, handle)
	if hatch.hatch_open && hatch_meets_a_capsule(entities, machines, hatch.common, capsules) {
		return false
	}
	hatch.hatch_open = !hatch.hatch_open
	hatch.hatch_toggle_tick = tick + 1
	occupy_entity_cells(entities, machines, hatch.common)
	rebuild_sealed_rooms(entities, machines)
	return true
}

hatch_meets_a_capsule :: proc(entities: ^Entities, machines: Machine_Registry, hatch: Entity_Common, capsules: []Field_Capsule) -> bool {
	frame, found := find_frame(&entities.frames, hatch.frame)
	if !found {
		return false
	}
	for cell in common_cells(hatch, machines) {
		for capsule in capsules {
			if capsule_meets_frame_cell(frame, cell, capsule) {
				return true
			}
		}
	}
	return false
}

// The sealed room.

Oxygen_Supply :: enum u8 {
	None,
	Unlimited,
}

// The cells of a pod the outside does not reach, in its frame in scan
// order (y, then z, then x), the first oxygen generator in pool order
// touching them (NO_ENTITY for none) and the supply it gives.
Sealed_Room :: struct {
	pod:      Entity_Handle,
	frame:    Frame_Id,
	cells:    [dynamic]World_Coordinate,
	supplier: Entity_Handle,
	oxygen:   Oxygen_Supply,
}

destroy_sealed_rooms :: proc(entities: ^Entities) {
	for room in entities.sealed_rooms {
		delete(room.cells)
	}
	delete(entities.sealed_rooms)
	entities.sealed_rooms = {}
}

// The rooms of every alive pod, from the occupancy. Called when a pod is
// placed, a hatch toggles and a world loads.
rebuild_sealed_rooms :: proc(entities: ^Entities, machines: Machine_Registry) {
	for room in entities.sealed_rooms {
		delete(room.cells)
	}
	clear(&entities.sealed_rooms)
	for entry in entities.foundations.entries {
		if !entry.alive || int(entry.machine) >= len(machines.machines) || machines.machines[entry.machine].kind != .Pod {
			continue
		}
		cells := pod_sealed_cells(&entities.frames, entry.frame, entry.origin, entry.origin + World_Coordinate(entry.size) - 1)
		if len(cells) == 0 {
			continue
		}
		supplier := room_supplier(entities, machines, entry.frame, cells)
		room := Sealed_Room {
			pod      = entry.handle,
			frame    = entry.frame,
			supplier = supplier,
			oxygen   = supplier != NO_ENTITY ? .Unlimited : .None,
		}
		append(&room.cells, ..cells)
		append(&entities.sealed_rooms, room)
	}
}

// A cell of a frame the air passes: no occupant, or one that is not
// solid.
frame_cell_is_air :: proc(frames: ^Frame_Table, frame: Frame_Id, cell: World_Coordinate) -> bool {
	occupant, found := frame_occupant(frames, frame, cell)
	return !found || .Solid not_in occupant.flags
}

// The air cells of the box from minimum to maximum (inclusive) the
// outside does not reach, in scan order, in the temp allocator. The
// outside reaches the air cells of the box's four side faces and its top
// face; the bottom face is the hull's floor on the ground and lets
// nothing in. From there a breadth first fill over the six neighbours
// inside the box through air cells.
pod_sealed_cells :: proc(frames: ^Frame_Table, frame: Frame_Id, minimum, maximum: World_Coordinate) -> []World_Coordinate {
	size := maximum - minimum + 1
	volume := int(size.x * size.y * size.z)
	air := make([]bool, volume, context.temp_allocator)
	reached := make([]bool, volume, context.temp_allocator)
	queue := make([dynamic]World_Coordinate, 0, volume, context.temp_allocator)
	index_of := proc(local, size: World_Coordinate) -> int {
		return int((local.y * size.z + local.z) * size.x + local.x)
	}
	for y in 0 ..< size.y {
		for z in 0 ..< size.z {
			for x in 0 ..< size.x {
				local := World_Coordinate{x, y, z}
				air[index_of(local, size)] = frame_cell_is_air(frames, frame, minimum + local)
				outside_face := x == 0 || x == size.x - 1 || z == 0 || z == size.z - 1 || y == size.y - 1
				if outside_face && air[index_of(local, size)] {
					reached[index_of(local, size)] = true
					append(&queue, local)
				}
			}
		}
	}
	neighbours := [6]World_Coordinate{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for head := 0; head < len(queue); head += 1 {
		for offset in neighbours {
			next := queue[head] + offset
			if next.x < 0 || next.y < 0 || next.z < 0 || next.x >= size.x || next.y >= size.y || next.z >= size.z {
				continue
			}
			index := index_of(next, size)
			if air[index] && !reached[index] {
				reached[index] = true
				append(&queue, next)
			}
		}
	}
	cells := make([dynamic]World_Coordinate, context.temp_allocator)
	for y in 0 ..< size.y {
		for z in 0 ..< size.z {
			for x in 0 ..< size.x {
				index := index_of({x, y, z}, size)
				if air[index] && !reached[index] {
					append(&cells, minimum + {x, y, z})
				}
			}
		}
	}
	return cells[:]
}

// The first alive oxygen generator of the foundations' pool on the frame
// with a footprint cell face adjacent to a room cell, NO_ENTITY for none.
room_supplier :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id, cells: []World_Coordinate) -> Entity_Handle {
	room := make(map[World_Coordinate]bool, len(cells), context.temp_allocator)
	for cell in cells {
		room[cell] = true
	}
	neighbours := [6]World_Coordinate{{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1}}
	for entry in entities.foundations.entries {
		if !entry.alive || entry.frame != frame || int(entry.machine) >= len(machines.machines) || machines.machines[entry.machine].kind != .Oxygen_Generator {
			continue
		}
		for cell in common_cells(entry.common, machines) {
			for offset in neighbours {
				if cell + offset in room {
					return entry.handle
				}
			}
		}
	}
	return NO_ENTITY
}

// The sealed room the feet stand in (the cell a quarter pitch over them
// along the room's frame's up). The room's cells stay the room's: the
// caller reads them within the frame and keeps no slice. For the F3 line
// now and the suit's drain in M15.
sealed_room_at_feet :: proc(entities: ^Entities, feet: World_Position) -> (room: Sealed_Room, inside: bool) {
	for candidate in entities.sealed_rooms {
		frame, found := find_frame(&entities.frames, candidate.frame)
		if !found {
			continue
		}
		lift := World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 4))
		if slice.contains(candidate.cells[:], world_to_frame_cell(frame, feet + lift)) {
			return candidate, true
		}
	}
	return {}, false
}

// Whether a room's supplier is the handle. For the draw.
oxygen_generator_supplies_a_room :: proc(entities: ^Entities, handle: Entity_Handle) -> bool {
	for room in entities.sealed_rooms {
		if room.supplier == handle {
			return true
		}
	}
	return false
}

// The old pod at load.

// A pod of an older build replaced at load: its frame, its saved
// footprint before rotation (x the width, y the height, z the depth, as
// Machine.footprint), the new pod, how many of the old locker's stacks
// its locker took and how many did not fit (0221).
Upgraded_Pod :: struct {
	old_frame:      Frame_Id,
	old_footprint:  [3]i32,
	pod:            Entity_Handle,
	moved_stacks:   int,
	dropped_stacks: int,
}

// The centre of a box's floor on a frame, from its minimum corner and
// size. Integer.
pod_floor_centre :: proc(frame: Frame, origin: World_Coordinate, size: [3]i32) -> World_Position {
	pitch := frame_pitch_units(frame)
	right := fixed_scale(frame.axes[FRAME_RIGHT], (2 * i64(origin.x) + i64(size.x)) * pitch / 2)
	up := fixed_scale(frame.axes[FRAME_UP], i64(origin.y) * pitch)
	forward := fixed_scale(frame.axes[FRAME_FORWARD], (2 * i64(origin.z) + i64(size.z)) * pitch / 2)
	return frame.origin + World_Position(right + up + forward)
}

// Every alive pod whose saved size is not its record's (an older build's)
// is replaced by the record's pod with its fixtures, on a new frame
// standing on the old floor's centre, facing the old frame's forward. The
// old fixtures go with it once the new pod stands (0221), the old
// locker's stacks into the new locker as far as its slots go; a pod that
// cannot be placed leaves its old fixtures where they are.
// Runs on the loaded pools before the occupancy is built
// (rebuild_loaded_world), so the old entry is only taken out of its pool.
// In the temp allocator.
upgrade_resized_pods :: proc(entities: ^Entities, machines: Machine_Registry) -> []Upgraded_Pod {
	upgraded := make([dynamic]Upgraded_Pod, context.temp_allocator)
	entry_count := len(entities.foundations.entries)
	for index in 0 ..< entry_count {
		entry := entities.foundations.entries[index]
		if !entry.alive || int(entry.machine) >= len(machines.machines) {
			continue
		}
		machine := machines.machines[entry.machine]
		if machine.kind != .Pod || entry.size == rotated_footprint_size(machine.footprint, entry.rotation) {
			continue
		}
		frame, found := find_frame(&entities.frames, entry.frame)
		if !found {
			continue
		}
		floor := pod_floor_centre(frame, entry.origin, entry.size)
		pool_remove(&entities.foundations, entry.handle)
		new_frame, placed := place_pod(entities, machines, floor, frame.axes[FRAME_FORWARD], frame.pitch_millimetres)
		if !placed {
			continue
		}
		stacks, _ := take_old_pod_fixtures(entities, machines, entry.frame)
		moved_stacks := fill_pod_locker(entities, machines, new_frame, stacks)
		append(&upgraded, Upgraded_Pod{old_frame = entry.frame, old_footprint = rotated_footprint_size(entry.size, entry.rotation), pod = pod_on_frame(entities, machines, new_frame), moved_stacks = moved_stacks, dropped_stacks = len(stacks) - moved_stacks})
	}
	return upgraded[:]
}

// Takes the old pod's fixtures off its frame (0221): every alive hatch,
// crafting bench and oxygen generator and every alive locker on the
// frame. None of these kinds has an item, so all of them on the frame are
// the pod's. Returns the lockers' non empty stacks in slot order, in the
// temp allocator, and how many entries went.
take_old_pod_fixtures :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> (locker_stacks: []Item_Stack, removed: int) {
	stacks := make([dynamic]Item_Stack, context.temp_allocator)
	for entry in entities.foundations.entries {
		if !entry.alive || entry.frame != frame {
			continue
		}
		kind := machines.machines[entry.machine].kind
		if kind == .Hatch || kind == .Crafting_Bench || kind == .Oxygen_Generator {
			pool_remove(&entities.foundations, entry.handle)
			removed += 1
		}
	}
	for &entry in entities.chests.entries {
		if !entry.alive || entry.frame != frame || machines.machines[entry.machine].kind != .Locker {
			continue
		}
		for stack in entry.slots[:entry.slot_count] {
			if !stack_is_empty(stack) {
				append(&stacks, stack)
			}
		}
		pool_remove(&entities.chests, entry.handle)
		removed += 1
	}
	return stacks[:], removed
}

// The first alive locker on the frame takes the stacks into its slots in
// order, at most its slot count; returns how many it took.
fill_pod_locker :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id, stacks: []Item_Stack) -> int {
	for &entry in entities.chests.entries {
		if !entry.alive || entry.frame != frame || machines.machines[entry.machine].kind != .Locker {
			continue
		}
		taken := min(len(stacks), entry.slot_count)
		copy(entry.slots[:taken], stacks[:taken])
		return taken
	}
	return 0
}

// The alive pod on a frame, NO_ENTITY for none.
pod_on_frame :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame_Id) -> Entity_Handle {
	for entry in entities.foundations.entries {
		if entry.alive && entry.frame == frame && machines.machines[entry.machine].kind == .Pod {
			return entry.handle
		}
	}
	return NO_ENTITY
}

// After the loaded world is rebuilt: each old frame goes when nothing
// else stands on it, every player whose feet lie in a new pod's box moves
// to its cabin, and one log line per pod.
finish_pod_upgrades :: proc(state: ^Simulation_State, machines: Machine_Registry, upgraded: []Upgraded_Pod) {
	entities := &state.world.entities
	for upgrade in upgraded {
		release_empty_frame(entities, upgrade.old_frame)
		pod := pool_get(&entities.foundations, upgrade.pod)
		if pod == nil {
			continue
		}
		moved := move_players_into_the_pod(state, machines, pod.common)
		// Width, depth, height, the record's order.
		old, new := upgrade.old_footprint, machines.machines[pod.machine].footprint
		platform.log_printf("save: the pod of an older build (%d by %d by %d cells) is replaced by the pod of %d by %d by %d cells with its hatches and fixtures, on a frame of its own at the old floor; %d players moved into its cabin, %d stacks moved into its locker, %d dropped", old.x, old.z, old.y, new.x, new.z, new.y, moved, upgrade.moved_stacks, upgrade.dropped_stacks)
	}
}

// Moves every player whose feet lie in the pod's box to the cabin's
// spawn; returns how many moved.
move_players_into_the_pod :: proc(state: ^Simulation_State, machines: Machine_Registry, pod: Entity_Common) -> int {
	entities := &state.world.entities
	frame, found := find_frame(&entities.frames, pod.frame)
	spawn, spawn_found := field_pod_spawn(entities, machines)
	if !found || !spawn_found {
		return 0
	}
	moved := 0
	for &player in state.players {
		cell := frame_cell_of_feet(frame, player.field)
		if cell_box_contains(Cell_Box{from = cast([3]i32)pod.origin, to = cast([3]i32)pod.origin + pod.size - 1}, cast([3]i32)cell) {
			move_field_player_body(&player.field, spawn)
			moved += 1
		}
	}
	return moved
}

// The cell of the frame the feet stand in, a quarter pitch over them.
frame_cell_of_feet :: proc(frame: Frame, player: Field_Player) -> World_Coordinate {
	lift := fixed_scale(player.up, frame_pitch_units(frame) / 4)
	return world_to_frame_cell(frame, player.position + World_Position(lift))
}

// Puts a body at a spawn's place and look, at rest; the tool, the
// targets and the run start stay.
move_field_player_body :: proc(body: ^Field_Player, spawn: Field_Player) {
	body.position = spawn.position
	body.previous_position = spawn.previous_position
	body.up = spawn.up
	body.forward = spawn.forward
	body.yaw = 0
	body.pitch = 0
	body.velocity = {}
	body.motion_fraction = {}
	body.on_ground = false
	body.seat = .Standing
}
