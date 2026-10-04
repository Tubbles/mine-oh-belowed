package game

import "core:fmt"
import "core:slice"
import "core:testing"

// The pod's airlock (work item 0222): the doors open for a player close
// and facing them, close behind, and never stand open at once.

// The shipped pod_airlock at the test tick rate.
test_pod_airlock_tuning :: proc(machines: Machine_Registry) -> Pod_Airlock_Tuning {
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	return make_pod_airlock_tuning(shipped.pod_airlock, machines, TEST_TICK_RATE)
}

// The frame local coordinate along the airlock's axis (the frame's z,
// record x turned by POD_ROTATION) of a hatch box's outer (+x) or inner
// (-x) face on the frame of place_test_pod.
test_door_face :: proc(frame: Frame, pod: Machine, index: int, outer_side: bool) -> i64 {
	box := pod.fixture_boxes[index]
	x := outer_side ? box.to.x + 1 : box.from.x
	return i64(test_pod_record_cell(pod, {x, 0, box.from.z}).z) * frame_pitch_units(frame)
}

// A floor point on the airlock's axis (centred on the hatches' z span) at
// the frame local coordinate along the axis.
test_airlock_floor_point :: proc(frame: Frame, pod: Machine, along: i64) -> World_Position {
	centre := pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.open_cells[TEST_AIRLOCK_BOX])
	shift := along - frame_local_position(frame, centre).z
	return centre + World_Position(fixed_scale(frame.axes[FRAME_FORWARD], shift))
}

// The two hatches' open states.
test_airlock_doors_open :: proc(entities: ^Entities, frame: Frame, pod: Machine) -> (outer, inner: bool) {
	return hatch_is_open(entities, test_pod_fixture(entities, frame, pod, TEST_OUTER_HATCH)), hatch_is_open(entities, test_pod_fixture(entities, frame, pod, TEST_INNER_HATCH))
}

// A crouched crossing of the airlock on the flat test field, one tick at a
// time as the session runs it (the move, then the step). outward goes
// from the lane out, else from outside in. The door the player meets
// first must open late, close round the player in the bore with the far
// one closed, the far one open no earlier than a slide after, and both
// stand closed at the end with the player through.
cross_test_airlock :: proc(t: ^testing.T, spacing: int, outward: bool) {
	machines := make_test_machines()
	world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
	defer destroy_field_world(&world)
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	origin := pod_origin(pod)
	pitch := frame_pitch_units(frame)
	tuning := test_field_tuning(spacing)
	airlock := test_pod_airlock_tuning(machines)
	inner := pod.fixture_boxes[TEST_INNER_HATCH]
	near_index, far_index := TEST_INNER_HATCH, TEST_OUTER_HATCH
	player: Field_Player
	near_face, goal: i64
	if outward {
		start := Cell_Box{from = {inner.from.x - 2, 0, inner.from.z}, to = {inner.from.x - 1, 0, inner.to.z}}
		player = make_field_player(pod_box_floor_centre(frame, origin, pod, POD_ROTATION, start), frame.axes[FRAME_FORWARD])
		near_face = test_door_face(frame, pod, TEST_INNER_HATCH, false)
		goal = test_door_face(frame, pod, TEST_OUTER_HATCH, true) + 2 * pitch
	} else {
		near_index, far_index = TEST_OUTER_HATCH, TEST_INNER_HATCH
		player = make_field_player(test_pod_outside_floor_point(frame, pod), -frame.axes[FRAME_FORWARD])
		near_face = test_door_face(frame, pod, TEST_OUTER_HATCH, true)
		// One cell past the inner face: the chair stops the capsule two
		// cells past it on the hatches' z span.
		goal = test_door_face(frame, pod, TEST_INNER_HATCH, false) - pitch
	}
	near_door := test_pod_fixture(&entities, frame, pod, near_index)
	far_door := test_pod_fixture(&entities, frame, pod, far_index)
	bore := test_pod_box_cells(pod, TEST_AIRLOCK_BOX)
	step := (tuning.sneak_speed + VELOCITY_FRACTION_ONE - 1) / VELOCITY_FRACTION_ONE
	latest := tuning.capsule_radius + airlock.reach + step + FIELD_GROUND_TOLERANCE
	label := fmt.tprintf("%d mm %s", spacing, outward ? "outward" : "inward")

	tick := u64(0)
	stage := 0
	both_closed_tick := u64(0)
	run_tick :: proc(world: ^Field_World, entities: ^Entities, machines: Machine_Registry, tuning: Field_Player_Tuning, airlock: Pod_Airlock_Tuning, player: ^Field_Player, input: Field_Player_Input, tick: ^u64) {
		tick^ += 1
		run_field_player_with_frames(world, &entities.frames, tuning, player, input, 1)
		players := [1]Field_Player{player^}
		tick_pod_airlocks(entities, machines, players[:], tuning, airlock, tick^)
	}
	observe :: proc(t: ^testing.T, entities: ^Entities, frame: Frame, near_door, far_door: Entity_Handle, player: Field_Player, bore: []World_Coordinate, near_face, latest: i64, outward: bool, tick: u64, stage: ^int, both_closed_tick: ^u64, travel: u64, label: string) {
		near_open, far_open := hatch_is_open(entities, near_door), hatch_is_open(entities, far_door)
		testing.expectf(t, !(near_open && far_open), "%s: both doors open at tick %d (stage %d)", label, tick, stage^)
		feet := frame_local_position(frame, player.position).z
		before := outward ? near_face - feet : feet - near_face
		in_bore := slice.contains(bore, frame_cell_of_feet(frame, player))
		switch stage^ {
		case 0:
			if near_open {
				testing.expectf(t, !far_open && before <= latest, "%s: the near door opened at tick %d with the feet %d before it (at most %d)", label, tick, before, latest)
				stage^ = 1
			}
		case 1:
			if !near_open {
				testing.expectf(t, in_bore && !far_open, "%s: the near door closed at tick %d with the feet in the bore %v", label, tick, in_bore)
				stage^ = 2
				both_closed_tick^ = tick
			}
		case 2:
			testing.expectf(t, !near_open, "%s: the near door opened again at tick %d", label, tick)
			if far_open {
				testing.expectf(t, tick >= both_closed_tick^ + travel && in_bore, "%s: the far door opened at tick %d, both closed since %d, the feet in the bore %v", label, tick, both_closed_tick^, in_bore)
				stage^ = 3
			}
		case 3:
			testing.expectf(t, !near_open, "%s: the near door opened again at tick %d", label, tick)
		}
	}

	for _ in 0 ..< 30 {
		run_tick(&world, &entities, machines, tuning, airlock, &player, {held = {.Sneak}}, &tick)
		observe(t, &entities, frame, near_door, far_door, player, bore, near_face, latest, outward, tick, &stage, &both_closed_tick, airlock.door_travel_ticks, label)
	}
	testing.expectf(t, player.crouching && stage == 0, "%s: crouching %v, stage %d after the start", label, player.crouching, stage)
	for _ in 0 ..< 900 {
		feet := frame_local_position(frame, player.position).z
		if (outward && feet >= goal) || (!outward && feet <= goal) {
			break
		}
		run_tick(&world, &entities, machines, tuning, airlock, &player, FIELD_SNEAK_FORWARD, &tick)
		observe(t, &entities, frame, near_door, far_door, player, bore, near_face, latest, outward, tick, &stage, &both_closed_tick, airlock.door_travel_ticks, label)
	}
	wait := airlock.door_travel_ticks + u64(airlock.close_hold_maximum_ticks) + airlock.door_travel_ticks + 2
	for _ in 0 ..< wait {
		run_tick(&world, &entities, machines, tuning, airlock, &player, {held = {.Sneak}}, &tick)
		observe(t, &entities, frame, near_door, far_door, player, bore, near_face, latest, outward, tick, &stage, &both_closed_tick, airlock.door_travel_ticks, label)
	}
	testing.expectf(t, stage == 3, "%s: the crossing reached stage %d of 3", label, stage)
	testing.expectf(t, !hatch_is_open(&entities, far_door), "%s: the far door is open at the end", label)
	feet := frame_cell_of_feet(frame, player)
	if outward {
		testing.expectf(t, feet.z - origin.z >= pod.footprint.x, "%s: the feet end in cell %v, inside the footprint", label, feet)
	} else {
		cabin := make([dynamic]World_Coordinate, context.temp_allocator)
		append(&cabin, ..test_pod_box_cells(pod, TEST_CABIN_BOX))
		append(&cabin, ..test_pod_box_cells(pod, TEST_LANE_BOX))
		testing.expectf(t, slice.contains(cabin[:], feet), "%s: the feet end in cell %v, not the lane's or the cabin's", label, feet)
	}
}

// From the lane out: the inner door opens late, both close round the
// player in the bore, the outer opens a slide later, and the outer closes
// behind the player outside.
@(test)
test_a_crouched_player_crosses_the_airlock_with_one_door_open_at_a_time :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		cross_test_airlock(t, spacing, true)
	}
}

// From outside in, the roles swapped.
@(test)
test_a_crouched_player_comes_back_in_through_the_airlock :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		cross_test_airlock(t, spacing, false)
	}
}

// The hold stays in its bounds, varies by tick and by hatch, and is the
// bound when both bounds agree.
@(test)
test_the_airlock_hold_varies_within_its_bounds :: proc(t: ^testing.T) {
	airlock := Pod_Airlock_Tuning{close_hold_minimum_ticks = 36, close_hold_maximum_ticks = 72}
	first, second := Entity_Handle{.Foundation, 3, 1}, Entity_Handle{.Foundation, 4, 1}
	seen: [2]map[u64]bool
	seen[0] = make(map[u64]bool, context.temp_allocator)
	seen[1] = make(map[u64]bool, context.temp_allocator)
	differ := 0
	for tick in u64(1) ..= 1000 {
		holds := [2]u64{pod_airlock_close_hold(first, tick, airlock), pod_airlock_close_hold(second, tick, airlock)}
		for hold, index in holds {
			testing.expectf(t, hold >= 36 && hold <= 72, "tick %d: hold %d", tick, hold)
			seen[index][hold] = true
		}
		if holds[0] != holds[1] {
			differ += 1
		}
	}
	testing.expectf(t, len(seen[0]) >= 20 && len(seen[1]) >= 20, "%d and %d distinct holds", len(seen[0]), len(seen[1]))
	testing.expectf(t, differ >= 900, "the two hatches differ on %d ticks", differ)
	fixed := Pod_Airlock_Tuning{close_hold_minimum_ticks = 40, close_hold_maximum_ticks = 40}
	for tick in u64(1) ..= 100 {
		testing.expect_value(t, pod_airlock_close_hold(first, tick, fixed), 40)
	}
}

// A capsule in the open door keeps it open; out of reach the door closes
// exactly on its drawn tick; a close tick reached with a capsule in the
// door is refused and kept.
@(test)
test_an_airlock_door_stays_open_while_a_capsule_stands_in_it :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	airlock := test_pod_airlock_tuning(machines)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	testing.expect(t, toggle_hatch(&entities, machines, outer, 1, nil))
	player := make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.fixture_boxes[TEST_OUTER_HATCH]), frame.axes[FRAME_FORWARD])
	player.crouching = true
	players := [1]Field_Player{player}
	for tick in u64(2) ..= 600 {
		tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, tick)
		hatch := pool_get(&entities.foundations, outer)
		if !hatch.hatch_open || hatch.hatch_close_tick != 0 {
			testing.expectf(t, false, "tick %d: open %v, close tick %d", tick, hatch.hatch_open, hatch.hatch_close_tick)
			break
		}
	}
	players[0].position = test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_OUTER_HATCH, true) + 2 * frame_pitch_units(frame))
	tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, 601)
	close_tick := pool_get(&entities.foundations, outer).hatch_close_tick
	testing.expectf(t, close_tick >= 601 + 36 && close_tick <= 601 + 72, "the close tick %d", close_tick)
	for tick in u64(602) ..= close_tick {
		tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, tick)
		testing.expectf(t, hatch_is_open(&entities, outer) == (tick < close_tick), "tick %d of close tick %d: open %v", tick, close_tick, hatch_is_open(&entities, outer))
	}

	reopened := close_tick + 1
	testing.expect(t, toggle_hatch(&entities, machines, outer, reopened, nil))
	now := reopened + airlock.door_travel_ticks
	pool_get(&entities.foundations, outer).hatch_close_tick = now
	capsules := [1]Field_Capsule{field_player_capsule(tuning, player)}
	close_airlock_door(&entities, machines, outer, {}, capsules[:], airlock, now)
	testing.expect(t, hatch_is_open(&entities, outer), "the door closed on the capsule")
	testing.expect_value(t, pool_get(&entities.foundations, outer).hatch_close_tick, now)
}

// Two players at opposite doors take turns: the outer first, the inner
// once the outer has closed and finished its slide.
@(test)
test_two_players_at_opposite_doors_take_turns :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	airlock := test_pod_airlock_tuning(machines)
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	inside := make_field_player(test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_INNER_HATCH, false) - tuning.capsule_radius), frame.axes[FRAME_FORWARD])
	inside.crouching = true
	outside := make_field_player(test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_OUTER_HATCH, true) + tuning.capsule_radius), -frame.axes[FRAME_FORWARD])
	players := [2]Field_Player{inside, outside}
	tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, 1)
	testing.expect(t, hatch_is_open(&entities, outer) && !hatch_is_open(&entities, inner), "the outer opens first")
	for tick in u64(2) ..= 301 {
		tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, tick)
		if !hatch_is_open(&entities, outer) || hatch_is_open(&entities, inner) {
			testing.expectf(t, false, "tick %d: the outer closed or the inner opened while the outside player stands at the outer", tick)
			break
		}
	}
	players[1].position = test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_OUTER_HATCH, true) + 3 * POSITION_UNITS_PER_METRE)
	closed_tick, opened_tick := u64(0), u64(0)
	for tick in u64(302) ..= 700 {
		tick_pod_airlocks(&entities, machines, players[:], tuning, airlock, tick)
		outer_open, inner_open := hatch_is_open(&entities, outer), hatch_is_open(&entities, inner)
		testing.expectf(t, !(outer_open && inner_open), "tick %d: both open", tick)
		if !outer_open && closed_tick == 0 {
			closed_tick = tick
		}
		if inner_open && opened_tick == 0 {
			opened_tick = tick
		}
	}
	testing.expectf(t, closed_tick >= 302 + 36 && closed_tick <= 302 + 72, "the outer closed at tick %d", closed_tick)
	testing.expectf(t, opened_tick != 0 && opened_tick >= closed_tick + airlock.door_travel_ticks, "the inner opened at tick %d, the outer closed at %d", opened_tick, closed_tick)
}

// Both doors left open (a save from 0198 to 0221), no players: each
// closes after its slide and its hold, and neither opens again.
@(test)
test_doors_left_open_close_on_their_own :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	airlock := test_pod_airlock_tuning(machines)
	doors := [2]Entity_Handle{test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)}
	for door in doors {
		testing.expect(t, toggle_hatch(&entities, machines, door, 1, nil))
	}
	closed: [2]u64
	for tick in u64(2) ..= 600 {
		tick_pod_airlocks(&entities, machines, nil, tuning, airlock, tick)
		for door, index in doors {
			open := hatch_is_open(&entities, door)
			if !open && closed[index] == 0 {
				closed[index] = tick
			}
			testing.expectf(t, !open || closed[index] == 0, "tick %d: door %d opened again", tick, index)
		}
	}
	first, last := 1 + airlock.door_travel_ticks + 36, 1 + airlock.door_travel_ticks + 72
	for tick, index in closed {
		testing.expectf(t, tick >= first && tick <= last, "door %d closed at tick %d, not within %d to %d", index, tick, first, last)
	}
}

// The shipped reach leaves a crouched player resting in the middle of the
// bore near neither door, and one against the far door out of the near
// door's reach.
@(test)
test_the_airlock_reach_leaves_room_in_the_bore :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod := machines.machines[find_machine_of_kind(machines, .Pod)]
	shipped, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	tuning := test_field_tuning(1000)
	radius := field_posture_tuning(tuning, true).capsule_radius
	reach := test_pod_airlock_tuning(machines).reach
	box := pod.open_cells[TEST_AIRLOCK_BOX]
	length := millimetres_to_position_units(int(box.to.x - box.from.x + 1) * shipped.foundation_pitch_millimetres)
	testing.expectf(t, length - 2 * radius > reach, "against the far door the near one is %d away, within the reach %d", length - 2 * radius, reach)
	testing.expectf(t, length / 2 - radius > reach, "in the middle the doors are %d away, within the reach %d", length / 2 - radius, reach)
}
