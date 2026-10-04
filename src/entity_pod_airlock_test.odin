package game

import "core:fmt"
import "core:slice"
import "core:testing"

// The pod's airlock (work items 0222, 0231): a door is open exactly while
// a player's capsule is within reach of it, standing or crouched, so a
// crawl has the near door open, both shut in the middle, the far one
// open.

// The shipped pod_airlock.
test_pod_airlock_tuning :: proc() -> Pod_Airlock_Tuning {
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	return make_pod_airlock_tuning(shipped.pod_airlock)
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

// Each player's capsule, in the temp allocator.
test_airlock_capsules :: proc(tuning: Field_Player_Tuning, players: []Field_Player) -> []Field_Capsule {
	capsules := make([]Field_Capsule, len(players), context.temp_allocator)
	for player, index in players {
		capsules[index] = field_player_capsule(tuning, player)
	}
	return capsules
}

// Whether the rule wants the door open: a capsule within reach of its
// cells.
test_door_wanted :: proc(entities: ^Entities, machines: Machine_Registry, frame: Frame, door: Entity_Handle, capsules: []Field_Capsule, reach: i64) -> bool {
	return capsules_near_cells(frame, common_cells(pool_get(&entities.foundations, door).common, machines), capsules, reach)
}

// The exact rule after a step: each door open exactly while the rule
// wants it. False, with a failure, when one is not.
expect_test_doors_follow_the_rule :: proc(t: ^testing.T, entities: ^Entities, machines: Machine_Registry, frame: Frame, doors: []Entity_Handle, capsules: []Field_Capsule, reach: i64, label: string, tick: u64) -> bool {
	for door, index in doors {
		wanted := test_door_wanted(entities, machines, frame, door, capsules, reach)
		if hatch_is_open(entities, door) != wanted {
			testing.expectf(t, false, "%s: tick %d: door %d open %v, wanted %v", label, tick, index, hatch_is_open(entities, door), wanted)
			return false
		}
	}
	return true
}

// A standing player walks up to the inner door from the lane: it opens
// on the tick the capsule comes within the reach and shuts on the tick it
// is past it on the way back, no hold. The inner door, since a standing
// capsule cannot reach the outer one on cells: the pod's solid row over
// the 2 row outside box keeps it 0.5 m off the outer face.
@(test)
test_a_standing_player_opens_the_inner_door_within_the_reach_and_shuts_it_past_it :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		machines := make_test_machines()
		world := make_test_field(Test_Terrain{kind = .Flat}, spacing)
		defer destroy_field_world(&world)
		entities: Entities
		defer destroy_entities(&entities)
		frame, pod := place_test_pod(&entities, machines)
		tuning := test_field_tuning(spacing)
		airlock := test_pod_airlock_tuning()
		inner := pod.fixture_boxes[TEST_INNER_HATCH]
		start := Cell_Box{from = {inner.from.x - 2, 0, inner.from.z}, to = {inner.from.x - 1, 0, inner.to.z}}
		player := make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, start), frame.axes[FRAME_FORWARD])
		doors := [2]Entity_Handle{test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)}
		face := test_door_face(frame, pod, TEST_INNER_HATCH, false)
		step := (tuning.walk_speed + VELOCITY_FRACTION_ONE - 1) / VELOCITY_FRACTION_ONE
		latest := tuning.capsule_radius + airlock.reach + step + FIELD_GROUND_TOLERANCE
		label := fmt.tprintf("%d mm", spacing)
		opened, shut, outer_opened := false, false, false
		for tick in u64(1) ..= 240 {
			input := tick <= 120 ? FIELD_WALK_FORWARD : Field_Player_Input{move = {0, -FIELD_MOVE_ONE}}
			run_field_player_with_frames(&world, &entities.frames, tuning, &player, input, 1)
			capsules := test_airlock_capsules(tuning, {player})
			was_open := hatch_is_open(&entities, doors[1])
			tick_pod_airlocks(&entities, machines, capsules, airlock, tick)
			if !expect_test_doors_follow_the_rule(t, &entities, machines, frame, doors[:], capsules, airlock.reach, label, tick) {
				break
			}
			outer_opened = outer_opened || hatch_is_open(&entities, doors[0])
			if !was_open && hatch_is_open(&entities, doors[1]) && tick <= 120 && !opened {
				opened = true
				before := face - frame_local_position(frame, player.position).z
				testing.expectf(t, before <= latest, "%s: the inner opened at tick %d with the feet %d before it (at most %d)", label, tick, before, latest)
			}
			if was_open && !hatch_is_open(&entities, doors[1]) && tick > 120 {
				shut = true
			}
		}
		testing.expectf(t, opened, "%s: the inner never opened on the walk", label)
		testing.expectf(t, shut && !hatch_is_open(&entities, doors[1]), "%s: the inner did not shut on the walk back", label)
		testing.expectf(t, !outer_opened, "%s: the outer opened", label)
	}
}

// A crouched crossing of the airlock on the flat test field, one tick at a
// time as the session runs it (the move, then the step). outward goes
// from the lane out, else from outside in. Every tick the doors follow
// the rule and never stand open at once; in order, the near door opens
// with the far one shut, both shut with the feet in the bore, the far one
// opens with the near one shut, and the far one shuts behind the player.
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
	airlock := test_pod_airlock_tuning()
	inner := pod.fixture_boxes[TEST_INNER_HATCH]
	near_index, far_index := TEST_INNER_HATCH, TEST_OUTER_HATCH
	player: Field_Player
	goal: i64
	if outward {
		start := Cell_Box{from = {inner.from.x - 2, 0, inner.from.z}, to = {inner.from.x - 1, 0, inner.to.z}}
		player = make_field_player(pod_box_floor_centre(frame, origin, pod, POD_ROTATION, start), frame.axes[FRAME_FORWARD])
		goal = test_door_face(frame, pod, TEST_OUTER_HATCH, true) + 2 * pitch
	} else {
		near_index, far_index = TEST_OUTER_HATCH, TEST_INNER_HATCH
		player = make_field_player(test_pod_outside_floor_point(frame, pod), -frame.axes[FRAME_FORWARD])
		// One cell past the inner face: the chair stops the capsule two
		// cells past it on the hatches' z span.
		goal = test_door_face(frame, pod, TEST_INNER_HATCH, false) - pitch
	}
	doors := [2]Entity_Handle{test_pod_fixture(&entities, frame, pod, near_index), test_pod_fixture(&entities, frame, pod, far_index)}
	bore := test_pod_box_cells(pod, TEST_AIRLOCK_BOX)
	label := fmt.tprintf("%d mm %s", spacing, outward ? "outward" : "inward")

	tick := u64(0)
	stage := 0
	failed := false
	run_tick :: proc(t: ^testing.T, world: ^Field_World, entities: ^Entities, machines: Machine_Registry, frame: Frame, tuning: Field_Player_Tuning, airlock: Pod_Airlock_Tuning, doors: []Entity_Handle, bore: []World_Coordinate, player: ^Field_Player, input: Field_Player_Input, tick: ^u64, stage: ^int, failed: ^bool, label: string) {
		tick^ += 1
		run_field_player_with_frames(world, &entities.frames, tuning, player, input, 1)
		capsules := test_airlock_capsules(tuning, {player^})
		tick_pod_airlocks(entities, machines, capsules, airlock, tick^)
		if failed^ {
			return
		}
		if !expect_test_doors_follow_the_rule(t, entities, machines, frame, doors, capsules, airlock.reach, label, tick^) {
			failed^ = true
			return
		}
		near_open, far_open := hatch_is_open(entities, doors[0]), hatch_is_open(entities, doors[1])
		if near_open && far_open {
			testing.expectf(t, false, "%s: both doors open at tick %d (stage %d)", label, tick^, stage^)
			failed^ = true
			return
		}
		in_bore := slice.contains(bore, frame_cell_of_feet(frame, player^))
		switch stage^ {
		case 0:
			stage^ = near_open ? 1 : 0
		case 1:
			stage^ = !near_open && !far_open && in_bore ? 2 : 1
		case 2:
			stage^ = far_open ? 3 : 2
		case 3:
			stage^ = !far_open ? 4 : 3
		}
	}

	for _ in 0 ..< 30 {
		run_tick(t, &world, &entities, machines, frame, tuning, airlock, doors[:], bore, &player, {held = {.Sneak}}, &tick, &stage, &failed, label)
	}
	testing.expectf(t, player.crouching && stage == 0, "%s: crouching %v, stage %d after the start", label, player.crouching, stage)
	for _ in 0 ..< 900 {
		feet := frame_local_position(frame, player.position).z
		if (outward && feet >= goal) || (!outward && feet <= goal) {
			break
		}
		run_tick(t, &world, &entities, machines, frame, tuning, airlock, doors[:], bore, &player, FIELD_SNEAK_FORWARD, &tick, &stage, &failed, label)
	}
	for _ in 0 ..< 30 {
		run_tick(t, &world, &entities, machines, frame, tuning, airlock, doors[:], bore, &player, {held = {.Sneak}}, &tick, &stage, &failed, label)
	}
	stage_names := [4]string{"the near door opens with the far one shut", "both shut with the feet in the bore", "the far door opens with the near one shut", "the far door shuts"}
	if stage < 4 {
		testing.expectf(t, false, "%s: the crossing never reached the stage where %s", label, stage_names[stage])
	}
	testing.expectf(t, !hatch_is_open(&entities, doors[0]) && !hatch_is_open(&entities, doors[1]), "%s: a door is open at the end", label)
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

// From the lane out: the inner opens, both shut round the player in the
// bore, the outer opens, and it shuts behind the player outside.
@(test)
test_a_crouched_crawl_out_has_both_doors_shut_in_the_middle :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		cross_test_airlock(t, spacing, true)
	}
}

// From outside in: the outer open and the inner shut, both shut in the
// middle, the inner open and the outer shut.
@(test)
test_a_crouched_crawl_in_has_both_doors_shut_in_the_middle :: proc(t: ^testing.T) {
	for spacing in TEST_FIELD_SPACINGS {
		cross_test_airlock(t, spacing, false)
	}
}

// Two players at the two doors open both at once; one walking off shuts
// its door on the next tick.
@(test)
test_two_players_at_the_two_doors_open_both :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	airlock := test_pod_airlock_tuning()
	outer := test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH)
	inner := test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)
	inside := make_field_player(test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_INNER_HATCH, false) - tuning.capsule_radius), frame.axes[FRAME_FORWARD])
	inside.crouching = true
	outside := make_field_player(test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_OUTER_HATCH, true) + tuning.capsule_radius), -frame.axes[FRAME_FORWARD])
	outside.crouching = true
	players := [2]Field_Player{inside, outside}
	tick_pod_airlocks(&entities, machines, test_airlock_capsules(tuning, players[:]), airlock, 1)
	testing.expect(t, hatch_is_open(&entities, outer) && hatch_is_open(&entities, inner), "both open at once")
	for tick in u64(2) ..= 301 {
		tick_pod_airlocks(&entities, machines, test_airlock_capsules(tuning, players[:]), airlock, tick)
		if !hatch_is_open(&entities, outer) || !hatch_is_open(&entities, inner) {
			testing.expectf(t, false, "tick %d: a door shut with a player at each", tick)
			break
		}
	}
	players[1].position = test_airlock_floor_point(frame, pod, test_door_face(frame, pod, TEST_OUTER_HATCH, true) + 3 * POSITION_UNITS_PER_METRE)
	tick_pod_airlocks(&entities, machines, test_airlock_capsules(tuning, players[:]), airlock, 302)
	testing.expect(t, !hatch_is_open(&entities, outer), "the outer shuts the tick its player is gone")
	testing.expect(t, hatch_is_open(&entities, inner), "the inner stays open for its player")
}

// Both doors open with nobody near (a save from 0198 to 0230 may hold
// that) shut on the first tick; a player in the outer doorway keeps it
// open and the inner shut.
@(test)
test_a_door_open_with_nobody_near_shuts_on_the_first_tick :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame, pod := place_test_pod(&entities, machines)
	tuning := test_field_tuning(1000)
	airlock := test_pod_airlock_tuning()
	doors := [2]Entity_Handle{test_pod_fixture(&entities, frame, pod, TEST_OUTER_HATCH), test_pod_fixture(&entities, frame, pod, TEST_INNER_HATCH)}
	for door in doors {
		testing.expect(t, toggle_hatch(&entities, machines, door, 1, nil))
	}
	tick_pod_airlocks(&entities, machines, nil, airlock, 2)
	for door, index in doors {
		testing.expectf(t, !hatch_is_open(&entities, door), "door %d is open after the first tick", index)
		testing.expect_value(t, pool_get(&entities.foundations, door).hatch_toggle_tick, 3)
	}
	for door in doors {
		testing.expect(t, toggle_hatch(&entities, machines, door, 3, nil))
	}
	player := make_field_player(pod_box_floor_centre(frame, pod_origin(pod), pod, POD_ROTATION, pod.fixture_boxes[TEST_OUTER_HATCH]), frame.axes[FRAME_FORWARD])
	player.crouching = true
	capsules := test_airlock_capsules(tuning, {player})
	for tick in u64(4) ..= 600 {
		tick_pod_airlocks(&entities, machines, capsules, airlock, tick)
		if !hatch_is_open(&entities, doors[0]) || hatch_is_open(&entities, doors[1]) {
			testing.expectf(t, false, "tick %d: outer open %v, inner open %v with a player in the outer doorway", tick, hatch_is_open(&entities, doors[0]), hatch_is_open(&entities, doors[1]))
			break
		}
	}
}

// The shipped reach leaves a crouched player resting in the middle of the
// bore near neither door.
@(test)
test_the_airlock_reach_leaves_both_doors_shut_in_the_middle :: proc(t: ^testing.T) {
	machines := make_test_machines()
	pod := machines.machines[find_machine_of_kind(machines, .Pod)]
	shipped, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	tuning := test_field_tuning(1000)
	radius := field_posture_tuning(tuning, true).capsule_radius
	reach := test_pod_airlock_tuning().reach
	box := pod.open_cells[TEST_AIRLOCK_BOX]
	length := millimetres_to_position_units(int(box.to.x - box.from.x + 1) * shipped.foundation_pitch_millimetres)
	testing.expectf(t, length / 2 - radius > reach, "in the middle the doors are %d away, within the reach %d", length / 2 - radius, reach)
}

// A hatch as 0222 saved it, with the close tick 0231 removed.
Foundation_Before_0231 :: struct {
	using common:      Entity_Common,
	hatch_open:        bool,
	hatch_toggle_tick: u64,
	hatch_close_tick:  u64,
}

// A 0222 save's hatch loads: the close tick is skipped by name and the
// rest reads as written.
@(test)
test_a_hatch_saved_before_0231_loads_without_its_close_tick :: proc(t: ^testing.T) {
	old := Foundation_Before_0231 {
		common = Entity_Common{machine = 3, origin = {1, 2, 3}},
		hatch_open = true,
		hatch_toggle_tick = 41,
		hatch_close_tick = 99,
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &old)
	read: Foundation
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_value_of(&reader, &read))
	testing.expect_value(t, reader.problem, "")
	testing.expect(t, read.hatch_open, "the hatch loads open")
	testing.expect_value(t, read.hatch_toggle_tick, 41)
	testing.expect_value(t, read.common.machine, 3)
	testing.expect_value(t, read.common.origin, World_Coordinate{1, 2, 3})
}
