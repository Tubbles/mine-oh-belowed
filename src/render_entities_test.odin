package game

import "core:math/linalg"
import "core:testing"

// Work item 0362: every machine placed on a frame is drawn where it
// stands, without GL.

// A stand-in model for every machine of the table, as test_uploaded_model
// gives one: a body of unit bounds and, for an inserter, the arm's parts.
stand_in_machine_models :: proc(machines: Machine_Registry) -> []Uploaded_Machine_Model {
	models := make([]Uploaded_Machine_Model, len(machines.machines), context.temp_allocator)
	unit := Model_Bounds{{-0.5, 0, -0.5}, {0.5, 1, 0.5}}
	for &model, index in models {
		model.body = test_uploaded_layers(24, 0)
		model.bounds[.Body] = unit
		model.top = 1
		if machines.machines[index].kind == .Inserter {
			for part in Arm_Part {
				model.arm[part] = test_uploaded_layers(24, 0)
				model.bounds[arm_part_slot(part)] = unit
			}
		}
	}
	return models
}

// Whether the transform's translation lies in the box.
translation_in_box :: proc(transform: matrix[4, 4]f32, minimum, maximum: [3]f32) -> bool {
	return point_in_posed_box({transform[0, 3], transform[1, 3], transform[2, 3]}, minimum, maximum)
}

// One entity of every record but the runs' kinds, the tree, the
// foundation, the pod (DrawMesh) and the launch pad (its tower is rlgl's
// batch) on a pad's frame: each has an instance of its machine on its
// cells under the frame's matrix, and the pad's cells are the foundations'
// bricks.
@(test)
test_every_machine_kind_reaches_the_fields_draw_list :: proc(t: ^testing.T) {
	machines := make_test_machines()
	world: World
	defer destroy_entities(&world.entities)
	pad := lay_test_pad(&world.entities, machines, 0, 0, {-1, 0, -1}, {1, 0, 1})
	Placed :: struct {
		machine: Machine_Id,
		common:  Entity_Common,
	}
	placed := make([dynamic]Placed, context.temp_allocator)
	for machine, index in machines.machines {
		#partial switch machine.kind {
		case .Belt, .Belt_Pole, .Pipe, .Tree, .Foundation, .Pod, .Launch_Pad:
			continue
		}
		slot := i32(len(placed))
		origin := World_Coordinate{(slot % 9) * 13, 1, (slot / 9) * 13}
		handle := add_entity(&world.entities, machines, Machine_Id(index), origin, 0, pad.id)
		common := entity_common(&world.entities, handle)
		testing.expectf(t, common != nil, "%s is placed", machine.id)
		if common != nil {
			append(&placed, Placed{Machine_Id(index), common^})
		}
	}
	models := Model_Renderer{models = stand_in_machine_models(machines)}
	table := frame_matrix_table(&world.entities.frames)
	instances := make([dynamic]Model_Instance, context.temp_allocator)
	frame := Model_Frame{world = &world, open_sky = true, tick_rate = 60, instances = &instances, frames = &table}
	draw_entities(&world, machines, models, Item_Registry{}, frame)
	transform := frame_render_matrix(pad)
	for entry in placed {
		low, high := entity_cell_box(entry.common.origin, entry.common.size)
		box_low, box_high := transformed_box(transform, low - 1, high + 1)
		found := false
		for instance in instances {
			found ||= instance.piece.machine == entry.machine && translation_in_box(instance.transform, box_low, box_high)
		}
		machine := machines.machines[entry.machine]
		testing.expectf(t, found, "%s (%v) at %v has no instance on its frame", machine.id, machine.kind, entry.common.origin)
	}
	cells, _, _ := build_foundation_bricks(&world.entities, machines)
	for z in i32(-1) ..= 1 {
		for x in i32(-1) ..= 1 {
			found := false
			for cell in cells {
				found ||= cell.frame == pad.id && cell.cell == {x, 0, z}
			}
			testing.expectf(t, found, "the pad's cell %v is a brick's", World_Coordinate{x, 0, z})
		}
	}
}

// A burner drill on a pad on the planet: its bar's ends, under the frame's
// matrix, lie at the drill, far from the planet's centre, and a quarter
// turn of the bar moves them.
@(test)
test_a_drills_bar_lands_at_the_drill_on_its_frame :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	pad := lay_test_pad(&entities, machines, 0, 0, {-1, 0, -1}, {2, 0, 2})
	machine_id := test_machine(machines, "burner_mining_drill")
	machine := machines.machines[machine_id]
	handle := add_entity(&entities, machines, machine_id, {0, 1, 0}, 0, pad.id)
	drill := pool_get(&entities.drills, handle)^
	transform := entity_frame_matrix(&entities, pad.id)
	low, high := entity_cell_box(drill.origin, drill.size)
	box_low, box_high := transformed_box(transform, low - 0.5, high + 0.5)
	cycle := drill_active_cycle_ticks(machine, false, 60)
	// No progress, a quarter turn of the bar and half a cycle (two whole
	// turns, DRILL_BIT_TURNS_PER_CYCLE).
	progresses := [3]u32{0, cycle / (4 * DRILL_BIT_TURNS_PER_CYCLE), cycle / 2}
	starts: [3][3]f32
	for progress, index in progresses {
		drill.progress_ticks = progress
		start, end := drill_bar_ends(drill, machine, 60)
		starts[index] = start
		for point in ([2][3]f32{start, end}) {
			on_planet := transform_point(transform, point)
			testing.expectf(t, point_in_posed_box(on_planet, box_low, box_high), "progress %d: %v lies outside the drill's box %v to %v", progress, on_planet, box_low, box_high)
			testing.expectf(t, linalg.length(on_planet) > 1000, "progress %d: %v is near the planet's centre", progress, on_planet)
		}
	}
	testing.expectf(t, linalg.length(starts[1] - starts[0]) > 0.1, "a quarter turn moves the bar: %v and %v", starts[0], starts[1])
}

// A launch pad on a pad: no rocket while it waits for parts; assembling,
// ready and launching, the tower stands over its first cell and the rocket
// over the footprint's centre under the frame's matrix, opaque but while
// it launches.
@(test)
test_a_launch_pads_tower_and_rocket_stand_on_its_frame :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	frame := lay_test_pad(&entities, machines, 0, 0, {0, 0, 0}, {1, 0, 1})
	machine_id := find_machine_of_kind(machines, .Launch_Pad)
	machine := machines.machines[machine_id]
	handle := add_entity(&entities, machines, machine_id, {0, 1, 0}, 0, frame.id)
	pad := pool_get(&entities.launch_pads, handle)^
	pad.state = .Waiting_For_Parts
	testing.expect(t, !launch_pad_boxes(pad, machine, 60).rocket, "no rocket while waiting for parts")
	transform := entity_frame_matrix(&entities, frame.id)
	low, _ := entity_cell_box(pad.origin, pad.size)
	tower_low, tower_high := transformed_box(transform, low, {low.x + 1, low.y + LAUNCH_TOWER_HEIGHT, low.z + 1})
	centre := box_centre(pad.origin, pad.size)
	top := low.y + LAUNCH_PAD_PLATFORM_HEIGHT + ROCKET_HEIGHT + ROCKET_ASCENT_HEIGHT
	column_low, column_high := transformed_box(transform, {centre.x - 0.5, low.y, centre.z - 0.5}, {centre.x + 0.5, top, centre.z + 0.5})
	Stage :: struct {
		state:                    Launch_Pad_State,
		work_ticks, launch_ticks: u32,
	}
	stages := [3]Stage {
		{.Assembling, assembly_ticks(machine, 60) / 2, 0},
		{.Rocket_Ready, 0, 0},
		{.Launching, 0, max(machine.launch_seconds * 60, 1) / 2},
	}
	for stage in stages {
		pad.state, pad.work_ticks, pad.launch_ticks = stage.state, stage.work_ticks, stage.launch_ticks
		boxes := launch_pad_boxes(pad, machine, 60)
		testing.expectf(t, boxes.rocket, "%v: a rocket", stage.state)
		testing.expectf(t, boxes.tower_centre.x == low.x + 0.5 && boxes.tower_centre.z == low.z + 0.5, "%v: the tower %v over the first cell", stage.state, boxes.tower_centre)
		testing.expectf(t, boxes.rocket_centre.x == centre.x && boxes.rocket_centre.z == centre.z, "%v: the rocket %v over the centre", stage.state, boxes.rocket_centre)
		tower := transform_point(transform, boxes.tower_centre)
		testing.expectf(t, point_in_posed_box(tower, tower_low, tower_high) && linalg.length(tower) > 1000, "%v: the tower at %v stands on the frame", stage.state, tower)
		rocket := transform_point(transform, boxes.rocket_centre)
		testing.expectf(t, point_in_posed_box(rocket, column_low, column_high) && linalg.length(rocket) > 1000, "%v: the rocket at %v stands on the frame", stage.state, rocket)
		if stage.state == .Launching {
			testing.expectf(t, boxes.rocket_color.a < 255, "launching, the rocket fades: %d", boxes.rocket_color.a)
		} else {
			testing.expectf(t, boxes.rocket_color.a == 255, "%v: the rocket is opaque: %d", stage.state, boxes.rocket_color.a)
		}
	}
}

// The glow and still kinds, the poles, the switch, the lamp and the
// splitter are still casters, the spin and bob kinds moving ones; placing
// a boiler on a frame moves the frame table's revision, so the kept sun
// shadow map draws it.
@(test)
test_fluid_and_power_machines_cast_still_or_moving_by_their_motion :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	pad := lay_test_pad(&entities, machines, 0, 0, {0, 0, 0}, {1, 0, 1})
	expect_moves :: proc(t: ^testing.T, entities: ^Entities, machines: Machine_Registry, id: string, origin: World_Coordinate, frame: Frame_Id, moves: bool) {
		machine_id := test_machine(machines, id)
		revision := entities.frames.revision
		handle := add_entity(entities, machines, machine_id, origin, 0, frame)
		testing.expectf(t, sun_shadow_entity_moves(handle.kind, machines.machines[machine_id]) == moves, "%s moves: %v", id, !moves)
		testing.expectf(t, entities.frames.revision != revision, "placing %s moves the frame table's revision", id)
	}
	for id, index in ([6]string{"boiler", "storage_tank", "small_pole", "power_switch", "lamp", "splitter"}) {
		expect_moves(t, &entities, machines, id, {i32(index) * 13, 1, 0}, pad.id, false)
	}
	for id, index in ([2]string{"steam_engine", "pump"}) {
		expect_moves(t, &entities, machines, id, {i32(index) * 13, 1, 13}, pad.id, true)
	}
}

// Hand made records of a boiler, a power switch and a lamp with a lamp
// each: working (producing, on, lit) they gather three lights, idle none.
@(test)
test_the_fluid_and_power_pools_gather_their_lamps :: proc(t: ^testing.T) {
	records := [3]Machine{{kind = .Boiler, footprint = {3, 2, 2}}, {kind = .Power_Switch, footprint = {1, 1, 1}}, {kind = .Lamp, footprint = {1, 1, 1}}}
	for &record in records {
		record.lights[0] = {position = {0, 0.5, 0}, color = {1, 0.9, 0.7}, radius_cells = 3}
		record.light_count = 1
	}
	machines := Machine_Registry{machines = records[:]}
	entities: Entities
	defer destroy_entities(&entities)
	boiler := pool_add(&entities.fluid_machines, .Fluid_Machine, Fluid_Machine{common = {machine = 0, origin = {0, 1, 0}, size = {3, 2, 2}}, state = .Producing})
	switch_handle := pool_add(&entities.poles, .Pole, Pole{common = {machine = 1, origin = {5, 1, 0}, size = {1, 1, 1}}, on = true})
	lamp := pool_add(&entities.lamps, .Lamp, Lamp{common = {machine = 2, origin = {8, 1, 0}, size = {1, 1, 1}}, lit = true})
	lights := make([dynamic]Point_Light, context.temp_allocator)
	gather_machine_lights(&lights, &entities, machines, Model_Renderer{}, Model_Frame{})
	testing.expect_value(t, len(lights), 3)
	pool_get(&entities.fluid_machines, boiler).state = .Idle
	pool_get(&entities.poles, switch_handle).on = false
	pool_get(&entities.lamps, lamp).lit = false
	clear(&lights)
	gather_machine_lights(&lights, &entities, machines, Model_Renderer{}, Model_Frame{})
	testing.expect_value(t, len(lights), 0)
}
