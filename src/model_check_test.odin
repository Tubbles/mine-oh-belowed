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

// The maxima only: a body of 3200 (0212) and a part of 200.
@(test)
test_a_model_over_the_budget_is_reported :: proc(t: ^testing.T) {
	empty := empty_test_layers()
	body_maximum := MODEL_BODY_TRIANGLES_MAXIMUM
	over := model_budget_problems(triangles_layers(MODEL_BODY_TRIANGLES_MAXIMUM + 1), empty, 1, body_maximum)
	testing.expect_value(t, len(over), 1)
	if len(over) == 1 {
		testing.expect(t, strings.contains(over[0].detail, "3201"), over[0].detail)
	}
	testing.expect_value(t, len(model_budget_problems(triangles_layers(MODEL_BODY_TRIANGLES_MAXIMUM), empty, 1, body_maximum)), 0)
	testing.expect_value(t, len(model_budget_problems(triangles_layers(199), empty, 1, body_maximum)), 0)
	part := model_budget_problems(triangles_layers(300), triangles_layers(201), 1, body_maximum)
	testing.expect_value(t, len(part), 1)
	if len(part) == 1 {
		testing.expect(t, strings.contains(part[0].detail, "part has 201"), part[0].detail)
	}
	testing.expect_value(t, len(model_budget_problems(triangles_layers(300), empty, 9, body_maximum)), 1)
	testing.expect_value(t, len(model_budget_problems(triangles_layers(200), triangles_layers(200), 8, body_maximum)), 0)
	testing.expect_value(t, len(model_budget_problems(triangles_layers(800), empty, 8, body_maximum)), 0)
}

// Work item 0221: the pod's body alone has the budget of 25600.
@(test)
test_the_pods_body_budget_is_25600 :: proc(t: ^testing.T) {
	testing.expect_value(t, model_body_triangles_maximum(.Pod), 25600)
	testing.expect_value(t, model_body_triangles_maximum(.Furnace), 3200)
	empty := empty_test_layers()
	testing.expect_value(t, len(model_budget_problems(triangles_layers(25600), empty, 1, 25600)), 0)
	over := model_budget_problems(triangles_layers(25601), empty, 1, 25600)
	testing.expect_value(t, len(over), 1)
	if len(over) == 1 {
		testing.expect(t, strings.contains(over[0].detail, "25601"), over[0].detail)
		testing.expect(t, strings.contains(over[0].detail, "25600"), over[0].detail)
	}
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
	for machine in machines {
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
