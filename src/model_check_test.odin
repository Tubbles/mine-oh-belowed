package game

import "core:strings"
import "core:testing"

// The workbench's checks (work item 0207) against meshes built by hand,
// and over the shipped models. The meshes are in the temp allocator.

append_test_quad :: proc(mesh: ^Model_Mesh, corners: [4][3]f32) {
	first := [3][3]f32{corners[0], corners[1], corners[2]}
	second := [3][3]f32{corners[0], corners[2], corners[3]}
	append_model_triangle(mesh, first, {255, 255, 255, 255}, triangle_winding_normal(first))
	append_model_triangle(mesh, second, {255, 255, 255, 255}, triangle_winding_normal(second))
}

empty_test_layers :: proc() -> (layers: Model_Layers) {
	for layer in Model_Layer {
		layers[layer] = make_model_mesh(context.temp_allocator)
	}
	return layers
}

// Twelve outward triangles in the lit layer.
box_layers :: proc(minimum, maximum: [3]f32) -> Model_Layers {
	layers := empty_test_layers()
	a, b := minimum, maximum
	mesh := &layers[.Lit]
	append_test_quad(mesh, {{a.x, a.y, a.z}, {a.x, a.y, b.z}, {a.x, b.y, b.z}, {a.x, b.y, a.z}})
	append_test_quad(mesh, {{b.x, a.y, a.z}, {b.x, b.y, a.z}, {b.x, b.y, b.z}, {b.x, a.y, b.z}})
	append_test_quad(mesh, {{a.x, a.y, a.z}, {b.x, a.y, a.z}, {b.x, a.y, b.z}, {a.x, a.y, b.z}})
	append_test_quad(mesh, {{a.x, b.y, a.z}, {a.x, b.y, b.z}, {b.x, b.y, b.z}, {b.x, b.y, a.z}})
	append_test_quad(mesh, {{a.x, a.y, a.z}, {a.x, b.y, a.z}, {b.x, b.y, a.z}, {b.x, a.y, a.z}})
	append_test_quad(mesh, {{a.x, a.y, b.z}, {b.x, a.y, b.z}, {b.x, b.y, b.z}, {a.x, b.y, b.z}})
	return layers
}

// count small triangles in the lit layer.
triangles_layers :: proc(count: int) -> Model_Layers {
	layers := empty_test_layers()
	for _ in 0 ..< count {
		corners := [3][3]f32{{0, 0, 0}, {0.1, 0, 0}, {0, 0.1, 0}}
		append_model_triangle(&layers[.Lit], corners, {255, 255, 255, 255}, triangle_winding_normal(corners))
	}
	return layers
}

machine_with_motion :: proc(kind: Motion_Kind, axis: int, amplitude: f32, pivot: [3]f32 = {}) -> Machine_Motion {
	return Machine_Motion{kind = kind, axis = axis, amplitude = amplitude, period_seconds = 1, pivot = pivot}
}

problems_of :: proc(problems: []Model_Check_Problem, check: Model_Check) -> [dynamic]string {
	details := make([dynamic]string, context.temp_allocator)
	for problem in problems {
		if problem.check == check {
			append(&details, problem.detail)
		}
	}
	return details
}

@(test)
test_a_segment_crosses_only_the_interior :: proc(t: ^testing.T) {
	triangle := [3][3]f32{{0, 0, 0}, {2, 0, 0}, {0, 2, 0}}
	testing.expect(t, segment_crosses_triangle({0.5, 0.5, -1}, {0.5, 0.5, 1}, triangle))
	testing.expect(t, !segment_crosses_triangle({0.5, 0.5, -1}, {0.5, 0.5, 0}, triangle), "a segment ending on the plane")
	testing.expect(t, !segment_crosses_triangle({-1, 0.5, 0}, {3, 0.5, 0}, triangle), "a segment in the plane")
	testing.expect(t, !segment_crosses_triangle({1, 0, -1}, {1, 0, 1}, triangle), "a segment through the edge")
	testing.expect(t, !segment_crosses_triangle({3, 3, -1}, {3, 3, 1}, triangle), "a segment past it")
}

@(test)
test_touching_boxes_do_not_cross :: proc(t: ^testing.T) {
	first := model_layers_check_triangles(box_layers({0, 0, 0}, {1, 1, 1}), 1)
	touching := model_layers_check_triangles(box_layers({1, 0, 0}, {2, 1, 1}), 1)
	testing.expect_value(t, count_triangle_crossings(touching[:], first[:]).count, 0)
	// Offset on every axis, so no face of one lies in a face's plane of
	// the other.
	overlapping := model_layers_check_triangles(box_layers({0.9, 0.1, 0.1}, {1.9, 1.1, 1.1}), 1)
	crossings := count_triangle_crossings(overlapping[:], first[:])
	testing.expect(t, crossings.count > 0)
	minimum, maximum := check_triangles_bounds(overlapping[crossings.first_moving:crossings.first_moving + 1])
	testing.expect(t, check_boxes_overlap(minimum, maximum, {0.9, 0.1, 0.1}, {1, 1, 1}), "the first crossing triangle reaches into the overlap")
}

@(test)
test_a_part_cutting_the_body_is_reported_with_the_phase :: proc(t: ^testing.T) {
	body := box_layers({-0.9, 0, -0.9}, {0.9, 0.2, 0.9})
	part := box_layers({-0.1, 0.5, -0.1}, {0.1, 0.9, 0.1})
	problems := model_sweep_problems(machine_with_motion(.Pump, 1, -0.45), {2, 2, 2}, body, part)
	sweeps := problems_of(problems, .Sweep)
	testing.expect_value(t, len(sweeps), 7)
	if len(sweeps) == 7 {
		testing.expect(t, strings.has_prefix(sweeps[0], "phase 0.3125:"), sweeps[0])
		testing.expect(t, strings.has_prefix(sweeps[3], "phase 0.5000:"), sweeps[3])
		testing.expect(t, strings.has_prefix(sweeps[6], "phase 0.6875:"), sweeps[6])
	}
	testing.expect_value(t, len(problems_of(problems, .Footprint)), 0)
}

@(test)
test_a_part_leaving_the_footprint_is_reported :: proc(t: ^testing.T) {
	body := box_layers({-0.9, 0, -0.9}, {0.3, 0.9, 0.9})
	part := box_layers({0.5, 0.2, -0.2}, {0.9, 0.6, 0.2})
	problems := model_sweep_problems(machine_with_motion(.Pump, 0, 0.3), {2, 2, 2}, body, part)
	testing.expect_value(t, len(problems_of(problems, .Sweep)), 0)
	footprints := problems_of(problems, .Footprint)
	half := ""
	for detail in footprints {
		testing.expect(t, !strings.has_prefix(detail, "phase 0.0000:"), detail)
		if strings.has_prefix(detail, "phase 0.5000:") {
			half = detail
		}
	}
	testing.expect(t, strings.contains(half, "x 1.200"), half)
}

@(test)
test_a_clean_spinning_part_passes :: proc(t: ^testing.T) {
	body := box_layers({-0.9, 0, -0.9}, {0.9, 0.2, 0.9})
	part := box_layers({-0.8, 0.5, -0.1}, {0.8, 0.6, 0.1})
	problems := model_sweep_problems(machine_with_motion(.Spin, 1, 1, {1, 0, 1}), {2, 2, 2}, body, part)
	testing.expect_value(t, len(problems), 0)
}

// The sanity caps only (0275): a body of 9600 and a part of 600.
@(test)
test_a_model_over_the_cap_is_reported :: proc(t: ^testing.T) {
	empty := empty_test_layers()
	body_cap := MODEL_BODY_TRIANGLES_CAP
	over := model_cap_problems(triangles_layers(9601), empty, 1, body_cap)
	testing.expect_value(t, len(over), 1)
	if len(over) == 1 {
		testing.expect(t, strings.contains(over[0].detail, "9601"), over[0].detail)
		testing.expect(t, strings.contains(over[0].detail, "sanity cap 9600"), over[0].detail)
	}
	testing.expect_value(t, len(model_cap_problems(triangles_layers(9600), empty, 1, body_cap)), 0)
	testing.expect_value(t, len(model_cap_problems(triangles_layers(199), empty, 1, body_cap)), 0)
	part := model_cap_problems(triangles_layers(300), triangles_layers(601), 1, body_cap)
	testing.expect_value(t, len(part), 1)
	if len(part) == 1 {
		testing.expect(t, strings.contains(part[0].detail, "part has 601"), part[0].detail)
	}
	testing.expect_value(t, len(model_cap_problems(triangles_layers(300), triangles_layers(600), 1, body_cap)), 0)
	testing.expect_value(t, len(model_cap_problems(triangles_layers(300), empty, 9, body_cap)), 1)
	testing.expect_value(t, len(model_cap_problems(triangles_layers(300), empty, 8, body_cap)), 0)
}

// Work item 0221, 0275: the pod's body alone has the cap of 76800.
@(test)
test_the_pods_body_cap_is_76800 :: proc(t: ^testing.T) {
	testing.expect_value(t, model_body_triangles_cap(.Pod), 76800)
	testing.expect_value(t, model_body_triangles_cap(.Furnace), 9600)
	empty := empty_test_layers()
	testing.expect_value(t, len(model_cap_problems(triangles_layers(76800), empty, 1, 76800)), 0)
	over := model_cap_problems(triangles_layers(76801), empty, 1, 76800)
	testing.expect_value(t, len(over), 1)
	if len(over) == 1 {
		testing.expect(t, strings.contains(over[0].detail, "76801"), over[0].detail)
		testing.expect(t, strings.contains(over[0].detail, "76800"), over[0].detail)
	}
}

// Work item 0275: every reference model sits at most a third of its
// caps, so a mesh subdivided once over a reference's density fails. A
// denser reference fails here, and the cap is raised with it.
@(test)
test_the_caps_stand_three_times_above_the_reference_models :: proc(t: ^testing.T) {
	machines := shipped_machines()
	defer delete(machines)
	registry := Machine_Registry{machines = machines}
	references := model_reference_counts(test_data_directory(), registry)
	testing.expect_value(t, len(references), len(MODEL_REFERENCE_MACHINES))
	for reference in references {
		testing.expectf(t, reference.found, "%s: no reference model", reference.id)
		machine_id, _ := find_machine_id(registry, reference.id)
		kind := machines[machine_id].kind
		testing.expectf(t, 3 * reference.counts.body_triangles <= model_body_triangles_cap(kind), "%s: body %d", reference.id, reference.counts.body_triangles)
		testing.expectf(t, 3 * reference.counts.part_triangles <= MODEL_PART_TRIANGLES_CAP, "%s: part %d", reference.id, reference.counts.part_triangles)
		testing.expectf(t, reference.counts.materials <= MODEL_MATERIAL_LIMIT, "%s: %d materials", reference.id, reference.counts.materials)
	}
}

// Work item 0275: the counts lines of --model-check.
@(test)
test_the_counts_lines :: proc(t: ^testing.T) {
	testing.expect_value(t, model_counts_line("boiler", {336, 0, 7}, 9600), "boiler: counts: body 336 triangles (cap 9600), part 0 (cap 600), 7 materials (limit 8)")
	references := []Model_Reference{{"stone_furnace", {3173, 0, 8}, true}, {"pod", {}, false}}
	testing.expect_value(t, model_references_line(references), "model check: reference models stone_furnace (body 3173, part 0, 8 materials), pod (no model)")
}

// Work item 0221: a hatch's part sliding up through the pod's body is
// reported against its fixture; clear of its path it is not. Model frame:
// the pod's x from -2 to 2, the door's x from 1 to 2.
@(test)
test_a_hatch_part_cutting_the_pod_is_reported :: proc(t: ^testing.T) {
	pod := Machine{kind = .Pod, footprint = {4, 4, 4}, fixture_count = 1}
	pod.fixtures[0] = Pod_Fixture{cell = {3, 0, 1}, rotation = 0}
	pod.fixture_boxes[0] = Cell_Box{from = {3, 0, 1}, to = {3, 1, 2}}
	hatch := Machine{id = "test_hatch", kind = .Hatch, footprint = {1, 2, 2}, motion = {kind = .Slide, axis = 1, amplitude = 2, period_seconds = 0.8}}
	part := box_layers({-0.05, 0, -0.9}, {0.05, 1.9, 0.9})
	blocked := fixture_part_crossing_problems(pod, 0, hatch, box_layers({1.0, 2.5, -2}, {2, 3, 2}), part)
	testing.expect(t, len(blocked) > 0, "a block over the door's path cuts the part")
	if len(blocked) > 0 {
		testing.expect_value(t, blocked[0].check, Model_Check.Sweep)
		testing.expect(t, strings.has_prefix(blocked[0].detail, "fixture 0"), blocked[0].detail)
	}
	testing.expect_value(t, len(fixture_part_crossing_problems(pod, 0, hatch, box_layers({-2, 2.5, -2}, {-1, 3, 2}), part)), 0)
}

// The iris of the check tests (work item 0231): four blades about the
// door's centre, blade 0 at the top pinned at y 1.9.
TEST_CHECK_IRIS :: Machine_Motion{kind = .Iris, axis = 0, blades = 4, pivot = {0.5, 1, 1}, hinge = {0.5, 1.9, 1}, amplitude = 0.25, period_seconds = 0.15}

// The first problem of the check, found false without one.
first_check_problem :: proc(problems: []Model_Check_Problem, check: Model_Check) -> (problem: Model_Check_Problem, found: bool) {
	for candidate in problems {
		if candidate.check == check {
			return candidate, true
		}
	}
	return {}, false
}

// Work item 0231: the sweep poses every blade of an iris, so a slab only
// blade 2 (turned half a turn, y 0.05 to 0.5) crosses is found and named;
// a slab beside the blades' x is clear at every fraction.
@(test)
test_the_sweep_poses_every_iris_blade :: proc(t: ^testing.T) {
	footprint := [3]i32{1, 2, 2}
	part := box_layers({-0.05, 1.5, -0.1}, {0.05, 1.95, 0.1})
	crossed, found := first_check_problem(model_sweep_problems(TEST_CHECK_IRIS, footprint, box_layers({-0.1, 0.2, -0.5}, {0.1, 0.3, 0.5}), part), .Sweep)
	testing.expect(t, found, "the slab under the door cuts no blade")
	testing.expect(t, strings.has_prefix(crossed.detail, "phase 0.0000 blade 2"), crossed.detail)
	_, beside := first_check_problem(model_sweep_problems(TEST_CHECK_IRIS, footprint, box_layers({0.3, 0.2, -0.5}, {0.4, 0.3, 0.5}), part), .Sweep)
	testing.expect(t, !beside, "a slab beside the blades cuts one")
}

// Work item 0231: every blade of a hatch's iris is swept against the
// pod's body and its open cells boxes. Model frame: the pod's x from -2
// to 2, the door's x from 1 to 2, its centre at x 1.5.
@(test)
test_every_iris_blade_is_swept_against_the_pod :: proc(t: ^testing.T) {
	pod := Machine{kind = .Pod, footprint = {4, 4, 4}, fixture_count = 1}
	pod.fixtures[0] = Pod_Fixture{cell = {3, 0, 1}, rotation = 0}
	pod.fixture_boxes[0] = Cell_Box{from = {3, 0, 1}, to = {3, 1, 2}}
	hatch := Machine{id = "test_hatch", kind = .Hatch, footprint = {1, 2, 2}, motion = TEST_CHECK_IRIS}
	part := box_layers({-0.05, 1.5, -0.1}, {0.05, 1.95, 0.1})
	crossed, found := first_check_problem(fixture_part_crossing_problems(pod, 0, hatch, box_layers({1.4, 0.2, -0.5}, {1.6, 0.3, 0.5}), part), .Sweep)
	testing.expect(t, found, "the slab under the door cuts no blade")
	testing.expect(t, strings.has_prefix(crossed.detail, "fixture 0 (test_hatch) blade 2"), crossed.detail)
	clear_body := box_layers({1.4, 2.5, -0.5}, {1.6, 3, 0.5})
	testing.expect_value(t, len(fixture_part_crossing_problems(pod, 0, hatch, clear_body, part)), 0)
	pod.open_cell_box_count = 1
	pod.open_cells[0] = Cell_Box{from = {3, 0, 1}, to = {3, 0, 2}}
	problems := fixture_part_crossing_problems(pod, 0, hatch, clear_body, part)
	inside, inside_found := first_check_problem(problems, .Open_Cells)
	testing.expect(t, inside_found, "no blade found in the door's bottom row")
	testing.expect(t, strings.has_prefix(inside.detail, "fixture 0 (test_hatch) blade "), inside.detail)
	_, swept := first_check_problem(problems, .Sweep)
	testing.expect(t, !swept, "the clear slab cuts a blade")
}

@(test)
test_a_triangle_inside_an_open_cell_is_reported :: proc(t: ^testing.T) {
	boxes := []Cell_Box{{from = {1, 0, 0}, to = {1, 1, 1}}}
	footprint := [3]i32{2, 2, 2}
	empty := empty_test_layers()
	testing.expect_value(t, len(model_open_cell_problems(boxes, footprint, box_layers({-1, 0, -1}, {0, 2, 1}), empty, "open cells box")), 0)
	small := empty_test_layers()
	small_corners := [3][3]f32{{0.4, 1, 0}, {0.6, 1, 0}, {0.5, 1.1, 0}}
	append_model_triangle(&small[.Lit], small_corners, {255, 255, 255, 255}, triangle_winding_normal(small_corners))
	inside := model_open_cell_problems(boxes, footprint, small, empty, "open cells box")
	testing.expect_value(t, len(inside), 1)
	if len(inside) == 1 {
		testing.expect(t, strings.has_prefix(inside[0].detail, "open cells box 0 "), inside[0].detail)
		testing.expect(t, strings.contains(inside[0].detail, "(body 0)"), inside[0].detail)
	}
	wall := empty_test_layers()
	append_test_quad(&wall[.Lit], {{0.5, -0.4, -1.3}, {0.5, -0.4, 1.7}, {0.5, 2.6, 1.7}, {0.5, 2.6, -1.3}})
	testing.expect_value(t, len(model_open_cell_problems(boxes, footprint, wall, empty, "open cells box")), 1)
	flush := empty_test_layers()
	append_test_quad(&flush[.Lit], {{0, 0, -1}, {0, 0, 1}, {0, 2, 1}, {0, 2, -1}})
	testing.expect_value(t, len(model_open_cell_problems(boxes, footprint, flush, empty, "open cells box")), 0)
}

// Work item 0198: a body triangle in a pod's fixture box is reported
// with the fixture box's label.
@(test)
test_a_body_in_a_fixture_box_is_found :: proc(t: ^testing.T) {
	boxes := []Cell_Box{{from = {1, 0, 0}, to = {1, 1, 1}}}
	footprint := [3]i32{2, 2, 2}
	small := empty_test_layers()
	small_corners := [3][3]f32{{0.4, 1, 0}, {0.6, 1, 0}, {0.5, 1.1, 0}}
	append_model_triangle(&small[.Lit], small_corners, {255, 255, 255, 255}, triangle_winding_normal(small_corners))
	problems := model_open_cell_problems(boxes, footprint, small, empty_test_layers(), "fixture box")
	testing.expect_value(t, len(problems), 1)
	if len(problems) == 1 {
		testing.expect_value(t, problems[0].check, Model_Check.Open_Cells)
		testing.expect(t, strings.has_prefix(problems[0].detail, "fixture box 0"), problems[0].detail)
	}
	// The whole OBJ check reads a machine's fixture boxes: the shipped
	// pod with a fixture box laid over its chair (0221).
	machines := make_test_machines()
	walled := machines.machines[find_machine_of_kind(machines, .Pod)]
	walled.fixture_boxes[0] = Cell_Box{from = {3, 0, 6}, to = {4, 0, 7}}
	walled.fixture_count = 1
	found := false
	for problem in check_obj_machine_model(test_data_directory(), machines.machines, walled) {
		found ||= problem.check == .Open_Cells && strings.has_prefix(problem.detail, "fixture box 0")
	}
	testing.expect(t, found, "the pod's chair in a fixture box is found")
}

// The gripper's main box of arm_gripper (tools/make_placeholder_models.py)
// in the mesher's centred voxel units; folded at rest it hangs about 0.60
// to 0.83 m up, 0.06 to 0.26 m off the axis.
@(test)
test_the_arm_check_finds_a_part_in_the_base :: proc(t: ^testing.T) {
	machine := Machine{kind = .Inserter, reach_millimetres = 2000, motion = {kind = .Arm}}
	arm: [Arm_Part]Model_Layers
	for part in Arm_Part {
		arm[part] = empty_test_layers()
	}
	arm[.Gripper] = box_layers({-4, 112, -4}, {4, 121, 4})
	arm[.Base] = box_layers({-12, 0, -12}, {12, 16, 12})
	testing.expect_value(t, len(arm_clearance_problems(machine, arm, 500)), 0)
	arm[.Base] = box_layers({-12, 28, -12}, {12, 30, 12})
	problems := arm_clearance_problems(machine, arm, 500)
	testing.expect(t, len(problems) > 0)
	if len(problems) > 0 {
		testing.expect_value(t, problems[0].check, Model_Check.Arm)
		testing.expect(t, strings.has_prefix(problems[0].detail, "fraction 0.0000:"), problems[0].detail)
		testing.expect(t, strings.contains(problems[0].detail, "gripper"), problems[0].detail)
	}
}

@(test)
test_the_model_check_report_line :: proc(t: ^testing.T) {
	line := model_check_report_line("burner_mining_drill", {.Sweep, "phase 0.5000: x"})
	testing.expect_value(t, line, "burner_mining_drill: sweep: phase 0.5000: x")
}

@(test)
test_the_shipped_models_pass_the_checks :: proc(t: ^testing.T) {
	machines := shipped_machines()
	defer delete(machines)
	counts: [Model_Check_Subject]int
	for &machine in machines {
		// A shipped collision file is loaded and checked (0230).
		volumes, problem := load_machine_collision(test_data_directory(), machine, context.temp_allocator)
		testing.expectf(t, problem == "", "%s: %s", machine.id, problem)
		machine.collision = volumes
		subject := model_check_subject(test_data_directory(), machine)
		counts[subject] += 1
		if subject != .Obj && subject != .Arm {
			continue
		}
		for problem in check_machine_model(test_data_directory(), machines, machine, 500) {
			testing.expect(t, false, model_check_report_line(machine.id, problem))
		}
	}
	testing.expectf(t, counts[.Obj] >= 26 && counts[.Arm] >= 5, "%d obj and %d arm subjects", counts[.Obj], counts[.Arm])
}

// A collision volume inside an open cells box is reported (work item
// 0230); one flush with the box's side lies inside the slack.
@(test)
test_the_collision_check_finds_a_volume_in_an_open_cells_box :: proc(t: ^testing.T) {
	machine := Machine{id = "test", footprint = {4, 4, 4}}
	machine.open_cells[0] = {from = {0, 0, 0}, to = {1, 3, 1}}
	machine.open_cell_box_count = 1
	// The box spans x and z -2 to 0 cells; the volume enters it by a
	// quarter cell along x.
	entering := test_collision_volume({kind = "box", from = {-0.25, 0, -2}, to = {1, 2, 0}})
	machine.collision = []Collision_Volume{entering}
	problems := model_collision_problems(machine)
	testing.expect_value(t, len(problems), 1)
	if len(problems) == 1 {
		testing.expect_value(t, problems[0].check, Model_Check.Collision)
		testing.expectf(t, strings.contains(problems[0].detail, "volume 0 enters open cells box 0"), "%q", problems[0].detail)
	}
	flush := test_collision_volume({kind = "box", from = {0, 0, -2}, to = {1, 2, 0}})
	machine.collision = []Collision_Volume{flush}
	testing.expect_value(t, len(model_collision_problems(machine)), 0)
}
