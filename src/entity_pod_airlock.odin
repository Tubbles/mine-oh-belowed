package game

import "core:math"
import "generation_seed"

// The pod's airlock (work item 0222, doc/content.md, Hatches): the two
// hatches of a pod open and close on their own. Once per tick after the
// players moved (tick_pod_airlocks), a door is near a player whose
// capsule comes within the reach of its cells, and wanted by a near
// player who faces it. A closed door opens for a player who wants it
// while both doors have finished their slide and the other is closed
// (the interlock); an open door no player is near closes after a hold
// drawn per hatch and tick, so the doors never close on a beat. Closes
// come before opens and at most one door opens per pod and tick, so the
// two never stand open at once. Lockstep state through
// Foundation.hatch_open, hatch_toggle_tick and hatch_close_tick; the
// prediction never runs it.

// A player faces a door within 60 degrees.
POD_AIRLOCK_FACING_COSINE :: UNIT_VECTOR_ONE / 2

// The reach in position units, the hold's bounds in ticks and the
// hatch's slide in ticks.
Pod_Airlock_Tuning :: struct {
	reach:                    i64,
	close_hold_minimum_ticks: i64,
	close_hold_maximum_ticks: i64,
	door_travel_ticks:        u64,
}

// From data/game.sjson's pod_airlock and the content's hatch. Called by
// make_field_content and the tests.
make_pod_airlock_tuning :: proc(config: Pod_Airlock_Config, machines: Machine_Registry, tick_rate: int) -> Pod_Airlock_Tuning {
	return Pod_Airlock_Tuning {
		reach = millimetres_to_position_units(config.reach_millimetres),
		close_hold_minimum_ticks = i64(config.close_hold_minimum_ticks),
		close_hold_maximum_ticks = i64(config.close_hold_maximum_ticks),
		door_travel_ticks = hatch_travel_ticks(machines, tick_rate),
	}
}

// The first hatch machine's slide in whole ticks, 0 without one. Rounded,
// never ceiled: the f32 0.8 times 60 is 48.0000007. At load only.
hatch_travel_ticks :: proc(machines: Machine_Registry, tick_rate: int) -> u64 {
	hatch := find_machine_of_kind(machines, .Hatch)
	if hatch == NO_MACHINE {
		return 0
	}
	period := machines.machines[hatch].motion.period_seconds
	return u64(max(0, int(math.round(f64(period) * f64(tick_rate)))))
}

// The first two hatch fixtures of a pod in record order: the outer, the
// inner.
Pod_Airlock :: struct {
	doors: [2]Entity_Handle,
}

// The pod's hatches at their fixture placements, no pool scan; found when
// two are there.
find_pod_airlock :: proc(entities: ^Entities, machines: Machine_Registry, pod: Entity_Common) -> (airlock: Pod_Airlock, found: bool) {
	record := machines.machines[pod.machine]
	count := 0
	for index in 0 ..< record.fixture_count {
		if machines.machines[record.fixtures[index].machine].kind != .Hatch {
			continue
		}
		origin, _ := pod_fixture_placement(record, pod.origin, pod.rotation, index)
		handle := entity_at(entities, origin, pod.frame)
		if _, is_hatch := hatch_state(entities, machines, handle); !is_hatch {
			continue
		}
		airlock.doors[count] = handle
		count += 1
		if count == 2 {
			return airlock, true
		}
	}
	return {}, false
}

// The airlock a hatch belongs to and which door it is; found false for a
// hatch of no airlock.
pod_airlock_of_hatch :: proc(entities: ^Entities, machines: Machine_Registry, hatch: Entity_Handle) -> (airlock: Pod_Airlock, door: int, found: bool) {
	if _, is_hatch := hatch_state(entities, machines, hatch); !is_hatch {
		return {}, 0, false
	}
	pod := pool_get(&entities.foundations, pod_on_frame(entities, machines, pool_get(&entities.foundations, hatch).frame))
	if pod == nil {
		return {}, 0, false
	}
	airlock = find_pod_airlock(entities, machines, pod.common) or_return
	for candidate, index in airlock.doors {
		if candidate == hatch {
			return airlock, index, true
		}
	}
	return {}, 0, false
}

// A hatch's slide has finished: never toggled, or toggled at tick t and
// the tick at least t plus the travel.
hatch_settled :: proc(hatch: Foundation, tick: u64, travel_ticks: u64) -> bool {
	return hatch.hatch_toggle_tick == 0 || tick + 1 >= hatch.hatch_toggle_tick + travel_ticks
}

// The ticks an open door with no player near waits before it closes,
// from the hatch's handle and the tick, within the bounds.
pod_airlock_close_hold :: proc(hatch: Entity_Handle, tick: u64, airlock: Pod_Airlock_Tuning) -> u64 {
	hash := generation_seed.hash_combine(u64(hatch.index) << 32 | u64(hatch.generation), tick)
	return u64(generation_seed.hash_to_range(hash, airlock.close_hold_minimum_ticks, airlock.close_hold_maximum_ticks))
}

// Any of the cells within reach of the capsule.
capsule_near_cells :: proc(frame: Frame, cells: []World_Coordinate, capsule: Field_Capsule, reach: i64) -> bool {
	for cell in cells {
		if capsule_within_frame_cell(frame, cell, capsule, reach) {
			return true
		}
	}
	return false
}

// The player's heading lies within 60 degrees of the direction from its
// feet to the centre of the cells, across the up. The offset is projected
// and normalized before the dot, since it is in position units.
player_faces_cells :: proc(frame: Frame, player: Field_Player, cells: []World_Coordinate) -> bool {
	if len(cells) == 0 {
		return false
	}
	first := frame_cell_centre(frame, cells[0])
	sum: [3]i64
	for cell in cells {
		sum += cast([3]i64)(frame_cell_centre(frame, cell) - first)
	}
	offset := cast([3]i64)(first - player.position) + sum / i64(len(cells))
	towards, ok := normalize_fixed(project_onto_plane(offset, player.up))
	return ok && fixed_dot(towards, field_player_heading(player)) > POD_AIRLOCK_FACING_COSINE
}

// Whether any player is near a door and whether a near one faces it.
Airlock_Door_Call :: struct {
	near:   bool,
	wanted: bool,
}

airlock_door_call :: proc(frame: Frame, cells: []World_Coordinate, players: []Field_Player, tuning: Field_Player_Tuning, reach: i64) -> Airlock_Door_Call {
	call: Airlock_Door_Call
	for player in players {
		if !capsule_near_cells(frame, cells, field_player_capsule(tuning, player), reach) {
			continue
		}
		call.near = true
		call.wanted = call.wanted || player_faces_cells(frame, player, cells)
	}
	return call
}

// An open, settled door: a near player clears its close tick; with none
// due one is drawn; at or past it the door closes, which toggle_hatch
// refuses while a capsule meets its cells (the close tick stays, so it
// retries). A closed or sliding door is left alone.
close_airlock_door :: proc(entities: ^Entities, machines: Machine_Registry, door: Entity_Handle, call: Airlock_Door_Call, capsules: []Field_Capsule, airlock: Pod_Airlock_Tuning, tick: u64) {
	hatch := pool_get(&entities.foundations, door)
	if hatch == nil || !hatch.hatch_open || !hatch_settled(hatch^, tick, airlock.door_travel_ticks) {
		return
	}
	switch {
	case call.near:
		hatch.hatch_close_tick = 0
	case hatch.hatch_close_tick == 0:
		hatch.hatch_close_tick = tick + pod_airlock_close_hold(door, tick, airlock)
	case tick >= hatch.hatch_close_tick:
		toggle_hatch(entities, machines, door, tick, capsules)
	}
}

// The interlock: the door closed, the other closed, both settled.
airlock_door_may_open :: proc(door, other: Foundation, tick: u64, travel_ticks: u64) -> bool {
	return !door.hatch_open && hatch_settled(door, tick, travel_ticks) && !other.hatch_open && hatch_settled(other, tick, travel_ticks)
}

// One pod's airlock for a tick: the calls from the state at its start,
// the closes in door order, then the first door wanted and allowed
// opens, and no other.
step_pod_airlock :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame, airlock: Pod_Airlock, players: []Field_Player, tuning: Field_Player_Tuning, airlock_tuning: Pod_Airlock_Tuning, tick: u64) {
	calls: [2]Airlock_Door_Call
	for door, index in airlock.doors {
		calls[index] = airlock_door_call(frame, common_cells(pool_get(&entities.foundations, door).common, machines), players, tuning, airlock_tuning.reach)
	}
	capsules := make([]Field_Capsule, len(players), context.temp_allocator)
	for player, index in players {
		capsules[index] = field_player_capsule(tuning, player)
	}
	for door, index in airlock.doors {
		close_airlock_door(entities, machines, door, calls[index], capsules, airlock_tuning, tick)
	}
	for door, index in airlock.doors {
		other := airlock.doors[1 - index]
		if calls[index].wanted && airlock_door_may_open(pool_get(&entities.foundations, door)^, pool_get(&entities.foundations, other)^, tick, airlock_tuning.door_travel_ticks) {
			toggle_hatch(entities, machines, door, tick, nil)
			return
		}
	}
}

// Every alive pod of the foundations' pool by index (toggle_hatch changes
// entries in place and never appends). Called by
// tick_field_session_players only.
tick_pod_airlocks :: proc(entities: ^Entities, machines: Machine_Registry, players: []Field_Player, tuning: Field_Player_Tuning, airlock: Pod_Airlock_Tuning, tick: u64) {
	for index in 0 ..< len(entities.foundations.entries) {
		pod := entities.foundations.entries[index]
		if !pod.alive || int(pod.machine) >= len(machines.machines) || machines.machines[pod.machine].kind != .Pod {
			continue
		}
		doors, found := find_pod_airlock(entities, machines, pod.common)
		frame, frame_found := find_frame(&entities.frames, pod.frame)
		if found && frame_found {
			step_pod_airlock(entities, machines, frame, doors, players, tuning, airlock, tick)
		}
	}
}

// Interact's interlock: the handle is a closed hatch of an airlock whose
// other door is open or still sliding. Called by interact_on_field and
// the HUD's hint.
pod_airlock_refuses_opening :: proc(entities: ^Entities, machines: Machine_Registry, hatch: Entity_Handle, tick: u64, travel_ticks: u64) -> bool {
	airlock, door, found := pod_airlock_of_hatch(entities, machines, hatch)
	if !found || pool_get(&entities.foundations, hatch).hatch_open {
		return false
	}
	other := pool_get(&entities.foundations, airlock.doors[1 - door])
	return other.hatch_open || !hatch_settled(other^, tick, travel_ticks)
}

// Each player's field body, in the temp allocator.
field_players_of :: proc(players: []Player) -> []Field_Player {
	bodies := make([]Field_Player, len(players), context.temp_allocator)
	for player, index in players {
		bodies[index] = player.field
	}
	return bodies
}
