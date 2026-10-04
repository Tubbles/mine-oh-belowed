package game

import "core:fmt"
import "core:math/linalg"
import "core:os"
import "model_obj"

// The model workbench's checks (work item 0207, doc/build.md, The
// workbench): pure procedures over the meshes the game draws, in the
// mesher's frame (cells, x and z centred, y from the bottom; the arm in
// metres), floats only, run by --model-check (loop_model_check.odin) and
// by test_the_shipped_models_pass_the_checks, so a check is one piece of
// code run two ways. Models are presentation: nothing here touches the
// simulation.
//
// Cost: a body of at most 3200 and a part of at most 200 triangles give
// at most 16 x 200 x 3200 (about 10 million) box tests per machine, exact
// tests only where the boxes overlap, and the moving part's bounds filter
// the body first; over the budget the sweep does not run. The open cells
// are at most 4 boxes x 3400 triangles x 18 tests. The arm's voxel parts
// are a few hundred triangles each: 16 fractions x 5 moving sets against
// the base, well under a second unoptimised.

// The motion and the arm's cycle are checked at index / 16 for index 0
// to 15; 0 is the rest.
MODEL_CHECK_PHASE_COUNT :: 16
// DESIGN.md, Art direction: the maxima are enforced. The body's is the
// user's 3200 (2026-10-04, 0212): a machine at its real size spends it on
// its surface, a pole or a lamp stays far under it.
MODEL_BODY_TRIANGLES_MAXIMUM :: 3200
MODEL_PART_TRIANGLES_MAXIMUM :: 200
MODEL_MATERIAL_LIMIT :: 8
// The share of an edge and of a triangle's barycentric range a crossing
// must clear, so contact (touching faces, a shared edge) is no crossing.
MODEL_CROSSING_EPSILON :: 1e-4
// An edge counts as parallel to a triangle when |det| is at most this
// times |direction| |edge1| |edge2|: relative, so cells and metres alike.
MODEL_PARALLEL_EPSILON :: 1e-6
// Any frame but the block frame, for inserter_reach_on_frame.
MODEL_CHECK_FRAME :: Frame_Id(1)

Model_Check :: enum u8 {
	Load,
	Budget,
	Sweep,
	Footprint,
	Arm,
	Open_Cells,
}

@(rodata)
model_check_names := [Model_Check]string {
	.Load       = "load",
	.Budget     = "budget",
	.Sweep      = "sweep",
	.Footprint  = "footprint",
	.Arm        = "arm",
	.Open_Cells = "open_cells",
}

Model_Check_Problem :: struct {
	check:  Model_Check,
	detail: string, // in the temp allocator
}

// What the checks take of a machine: an OBJ model, the arm, a voxel
// model (skipped until 0205 and 0206 replace them) or nothing.
Model_Check_Subject :: enum u8 {
	None,
	Obj,
	Arm,
	Voxel,
}

Check_Triangle :: struct {
	corners:          [3][3]f32,
	minimum, maximum: [3]f32,
}

// count: the moving triangles crossing any still one; near: the first
// such moving triangle's centroid.
Triangle_Crossings :: struct {
	count:                     int,
	first_moving, first_still: int,
	near:                      [3]f32,
}

check_triangle :: proc(corners: [3][3]f32) -> Check_Triangle {
	return Check_Triangle {
		corners = corners,
		minimum = linalg.min(linalg.min(corners[0], corners[1]), corners[2]),
		maximum = linalg.max(linalg.max(corners[0], corners[1]), corners[2]),
	}
}

// Every triangle of the lit layer, then the emissive one (either shape,
// model_mesh_triangle), its corners through transform.
model_layers_check_triangles :: proc(layers: Model_Layers, transform: matrix[4, 4]f32, allocator := context.temp_allocator) -> [dynamic]Check_Triangle {
	triangles := make([dynamic]Check_Triangle, allocator)
	for layer in Model_Layer {
		mesh := layers[layer]
		for triangle in 0 ..< model_mesh_triangle_count(mesh) {
			corners := model_mesh_triangle(mesh, triangle)
			for &corner in corners {
				corner = transform_point(transform, corner)
			}
			append(&triangles, check_triangle(corners))
		}
	}
	return triangles
}

model_layers_triangle_count :: proc(layers: Model_Layers) -> int {
	return model_mesh_triangle_count(layers[.Lit]) + model_mesh_triangle_count(layers[.Emissive])
}

// Zero for none.
check_triangles_bounds :: proc(triangles: []Check_Triangle) -> (minimum, maximum: [3]f32) {
	if len(triangles) == 0 {
		return {}, {}
	}
	minimum, maximum = triangles[0].minimum, triangles[0].maximum
	for triangle in triangles[1:] {
		minimum = linalg.min(minimum, triangle.minimum)
		maximum = linalg.max(maximum, triangle.maximum)
	}
	return minimum, maximum
}

// Closed intervals on all three axes.
check_boxes_overlap :: proc(a_minimum, a_maximum, b_minimum, b_maximum: [3]f32) -> bool {
	for axis in 0 ..< 3 {
		if a_maximum[axis] < b_minimum[axis] || b_maximum[axis] < a_minimum[axis] {
			return false
		}
	}
	return true
}

// Möller and Trumbore: true when the segment passes through the
// triangle's interior, clear of its edges and of the segment's ends by
// MODEL_CROSSING_EPSILON; false when parallel to it.
segment_crosses_triangle :: proc(start, end: [3]f32, corners: [3][3]f32) -> bool {
	direction := end - start
	edge1, edge2 := corners[1] - corners[0], corners[2] - corners[0]
	normal_part := linalg.cross(direction, edge2)
	determinant := linalg.dot(edge1, normal_part)
	if abs(determinant) <= MODEL_PARALLEL_EPSILON * linalg.length(direction) * linalg.length(edge1) * linalg.length(edge2) {
		return false
	}
	offset := start - corners[0]
	u := linalg.dot(offset, normal_part) / determinant
	cross_part := linalg.cross(offset, edge1)
	v := linalg.dot(direction, cross_part) / determinant
	along := linalg.dot(edge2, cross_part) / determinant
	return along > MODEL_CROSSING_EPSILON && along < 1 - MODEL_CROSSING_EPSILON && u > MODEL_CROSSING_EPSILON && v > MODEL_CROSSING_EPSILON && 1 - u - v > MODEL_CROSSING_EPSILON
}

// Boxes first, then any edge of one through the other. Two triangles
// that are not coplanar intersect in a segment whose ends lie on edges,
// so this is exact up to the epsilon.
triangles_cross :: proc(a, b: Check_Triangle) -> bool {
	if !check_boxes_overlap(a.minimum, a.maximum, b.minimum, b.maximum) {
		return false
	}
	for corner in 0 ..< 3 {
		next := (corner + 1) % 3
		if segment_crosses_triangle(a.corners[corner], a.corners[next], b.corners) || segment_crosses_triangle(b.corners[corner], b.corners[next], a.corners) {
			return true
		}
	}
	return false
}

// The still triangles are first filtered by the moving set's bounds, then
// each moving triangle is tested against those left, counted once.
count_triangle_crossings :: proc(moving, still: []Check_Triangle) -> (crossings: Triangle_Crossings) {
	minimum, maximum := check_triangles_bounds(moving)
	near := make([dynamic]int, context.temp_allocator)
	for triangle, index in still {
		if check_boxes_overlap(triangle.minimum, triangle.maximum, minimum, maximum) {
			append(&near, index)
		}
	}
	for triangle, moving_index in moving {
		for still_index in near {
			if !triangles_cross(triangle, still[still_index]) {
				continue
			}
			if crossings.count == 0 {
				crossings.first_moving, crossings.first_still = moving_index, still_index
				crossings.near = (triangle.corners[0] + triangle.corners[1] + triangle.corners[2]) / 3
			}
			crossings.count += 1
			break
		}
	}
	return crossings
}

// Strictly inside.
point_strictly_in_box :: proc(point, minimum, maximum: [3]f32) -> bool {
	for axis in 0 ..< 3 {
		if point[axis] <= minimum[axis] || point[axis] >= maximum[axis] {
			return false
		}
	}
	return true
}

// The slab test: true when the part of the segment inside the box has a
// positive length. A segment parallel to an axis's planes whose
// coordinate is not strictly inside that axis's interval is outside.
segment_enters_box :: proc(start, end, minimum, maximum: [3]f32) -> bool {
	enter, exit: f32 = 0, 1
	direction := end - start
	for axis in 0 ..< 3 {
		if direction[axis] == 0 {
			if start[axis] <= minimum[axis] || start[axis] >= maximum[axis] {
				return false
			}
			continue
		}
		near := (minimum[axis] - start[axis]) / direction[axis]
		far := (maximum[axis] - start[axis]) / direction[axis]
		enter, exit = max(enter, min(near, far)), min(exit, max(near, far))
	}
	return exit > enter
}

// A corner inside, an edge into the box, or one of the box's 12 edges
// through the triangle: the last covers a large wall slicing the box with
// no corner in it.
triangle_enters_box :: proc(triangle: Check_Triangle, minimum, maximum: [3]f32) -> bool {
	if !check_boxes_overlap(triangle.minimum, triangle.maximum, minimum, maximum) {
		return false
	}
	for corner in 0 ..< 3 {
		if point_strictly_in_box(triangle.corners[corner], minimum, maximum) || segment_enters_box(triangle.corners[corner], triangle.corners[(corner + 1) % 3], minimum, maximum) {
			return true
		}
	}
	extent := [2][3]f32{minimum, maximum}
	for axis in 0 ..< 3 {
		for corner in 0 ..< 4 {
			start, end: [3]f32
			start[axis], end[axis] = minimum[axis], maximum[axis]
			start[(axis + 1) % 3] = extent[corner & 1][(axis + 1) % 3]
			start[(axis + 2) % 3] = extent[corner >> 1][(axis + 2) % 3]
			end[(axis + 1) % 3], end[(axis + 2) % 3] = start[(axis + 1) % 3], start[(axis + 2) % 3]
			if segment_crosses_triangle(start, end, triangle.corners) {
				return true
			}
		}
	}
	return false
}

// The open cells' box in the model's frame, shrunk by
// MODEL_FOOTPRINT_TOLERANCE_CELLS on every side, so a wall flush with the
// opening's side is not inside it.
open_cell_box_in_model :: proc(box: Cell_Box, footprint: [3]i32) -> (minimum, maximum: [3]f32) {
	from := [3]f32{f32(box.from.x), f32(box.from.y), f32(box.from.z)}
	to := [3]f32{f32(box.to.x + 1), f32(box.to.y + 1), f32(box.to.z + 1)}
	minimum = footprint_point_to_model(from, footprint) + MODEL_FOOTPRINT_TOLERANCE_CELLS
	maximum = footprint_point_to_model(to, footprint) - MODEL_FOOTPRINT_TOLERANCE_CELLS
	return minimum, maximum
}

model_check_phase :: proc(index: int) -> f32 {
	return f32(index) / MODEL_CHECK_PHASE_COUNT
}

// Distinct (colour, emissive) pairs: the reader keeps no material names,
// so two materials of one colour count once.
obj_model_material_count :: proc(model: model_obj.Obj_Model) -> int {
	seen := make(map[[4]u8]bool, context.temp_allocator)
	for triangle in model.triangles {
		seen[{triangle.colour.r, triangle.colour.g, triangle.colour.b, u8(triangle.emissive)}] = true
	}
	return len(seen)
}

// The arm's reach in cells on a frame of the pitch. The preview uses it
// too.
model_check_arm_reach :: proc(machine: Machine, pitch_millimetres: int) -> i32 {
	return inserter_reach_on_frame(machine, Frame{id = MODEL_CHECK_FRAME, pitch_millimetres = pitch_millimetres})
}

// DESIGN.md's maxima; the part's line only for a part with triangles.
model_budget_problems :: proc(body, part: Model_Layers, material_count: int, allocator := context.temp_allocator) -> []Model_Check_Problem {
	problems := make([dynamic]Model_Check_Problem, allocator)
	if count := model_layers_triangle_count(body); count > MODEL_BODY_TRIANGLES_MAXIMUM {
		append(&problems, Model_Check_Problem{.Budget, fmt.tprintf("body has %d triangles, the budget is at most %d", count, MODEL_BODY_TRIANGLES_MAXIMUM)})
	}
	if count := model_layers_triangle_count(part); count > MODEL_PART_TRIANGLES_MAXIMUM {
		append(&problems, Model_Check_Problem{.Budget, fmt.tprintf("part has %d triangles, the budget is at most %d", count, MODEL_PART_TRIANGLES_MAXIMUM)})
	}
	if material_count > MODEL_MATERIAL_LIMIT {
		append(&problems, Model_Check_Problem{.Budget, fmt.tprintf("%d materials, the budget is %d", material_count, MODEL_MATERIAL_LIMIT)})
	}
	return problems[:]
}

// The part over its motion at MODEL_CHECK_PHASE_COUNT phases: never
// through the body, and inside the footprint as 0204's loader bounds the
// model at rest. At most one line per check and phase.
model_sweep_problems :: proc(motion: Machine_Motion, footprint: [3]i32, body, part: Model_Layers, allocator := context.temp_allocator) -> []Model_Check_Problem {
	problems := make([dynamic]Model_Check_Problem, allocator)
	if !motion_has_part(motion.kind) || model_layers_triangle_count(part) == 0 {
		return problems[:]
	}
	still := model_layers_check_triangles(body, 1)
	for index in 0 ..< MODEL_CHECK_PHASE_COUNT {
		phase := model_check_phase(index)
		moving := model_layers_check_triangles(part, motion_transform(motion, footprint, phase))
		if crossings := count_triangle_crossings(moving[:], still[:]); crossings.count > 0 {
			detail := fmt.tprintf("phase %.4f: %d part triangles cut the body, the first (part %d, body %d) near (%.3f, %.3f, %.3f)", phase, crossings.count, crossings.first_moving, crossings.first_still, crossings.near.x, crossings.near.y, crossings.near.z)
			append(&problems, Model_Check_Problem{.Sweep, detail})
		}
		minimum, maximum := check_triangles_bounds(moving[:])
		if problem := model_footprint_problem(minimum, maximum, footprint); problem != "" {
			append(&problems, Model_Check_Problem{.Footprint, fmt.tprintf("phase %.4f: the part %s", phase, problem)})
		}
	}
	return problems[:]
}

// The first triangle of the set inside the box, and how many are.
triangles_in_box :: proc(triangles: []Check_Triangle, minimum, maximum: [3]f32) -> (count, first: int) {
	first = -1
	for triangle, index in triangles {
		if triangle_enters_box(triangle, minimum, maximum) {
			first = count == 0 ? index : first
			count += 1
		}
	}
	return count, first
}

// The body and the part at rest against each open cell box: one line per
// box with triangles inside.
model_open_cell_problems :: proc(boxes: []Cell_Box, footprint: [3]i32, body, part: Model_Layers, label: string, allocator := context.temp_allocator) -> []Model_Check_Problem {
	problems := make([dynamic]Model_Check_Problem, allocator)
	sets := [2][dynamic]Check_Triangle{model_layers_check_triangles(body, 1), model_layers_check_triangles(part, 1)}
	set_names := [2]string{"body", "part"}
	for box, box_index in boxes {
		minimum, maximum := open_cell_box_in_model(box, footprint)
		total, first, first_set := 0, -1, 0
		for set, set_index in sets {
			count, set_first := triangles_in_box(set[:], minimum, maximum)
			if first < 0 && set_first >= 0 {
				first, first_set = set_first, set_index
			}
			total += count
		}
		if total == 0 {
			continue
		}
		corners := sets[first_set][first].corners
		near := (corners[0] + corners[1] + corners[2]) / 3
		detail := fmt.tprintf("%s %d (cells %v to %v): %d triangles inside, the first (%s %d) near (%.3f, %.3f, %.3f)", label, box_index, box.from, box.to, total, set_names[first_set], first, near.x, near.y, near.z)
		append(&problems, Model_Check_Problem{.Open_Cells, detail})
	}
	return problems[:]
}

@(rodata)
arm_check_part_names := [Arm_Part]string {
	.Base      = "base",
	.Turret    = "turret",
	.Upper_Arm = "upper_arm",
	.Forearm   = "forearm",
	.Gripper   = "gripper",
	.Finger    = "finger",
}

// The moving sets of the arm at one pose, placed as draw_arm_colored
// places them: the upper arm, the forearm, the gripper and both fingers.
// The turret turns in place on the base's axis, so it is left out.
Arm_Check_Set :: struct {
	part:      Arm_Part,
	transform: matrix[4, 4]f32,
}

arm_check_sets :: proc(dimensions: Arm_Dimensions, angles: Arm_Joint_Angles) -> [5]Arm_Check_Set {
	voxels := arm_voxel_scale()
	parts := arm_part_transforms(dimensions, angles)
	fingers := arm_finger_transforms(parts[.Gripper], angles.grip)
	return {
		{.Upper_Arm, parts[.Upper_Arm] * voxels},
		{.Forearm, parts[.Forearm] * voxels},
		{.Gripper, parts[.Gripper] * voxels},
		{.Finger, fingers[0] * voxels},
		{.Finger, fingers[1] * voxels},
	}
}

// The arm's parts at MODEL_CHECK_PHASE_COUNT cycle fractions on a frame of
// the pitch clear its base: one line per crossing set and fraction.
arm_clearance_problems :: proc(machine: Machine, arm: [Arm_Part]Model_Layers, pitch_millimetres: int, allocator := context.temp_allocator) -> []Model_Check_Problem {
	problems := make([dynamic]Model_Check_Problem, allocator)
	dimensions := arm_dimensions_on_frame(model_check_arm_reach(machine, pitch_millimetres), pitch_millimetres)
	for index in 0 ..< MODEL_CHECK_PHASE_COUNT {
		fraction := model_check_phase(index)
		angles := arm_pose_at(dimensions, fraction)
		base := model_layers_check_triangles(arm[.Base], arm_part_transforms(dimensions, angles)[.Base] * arm_voxel_scale())
		for set in arm_check_sets(dimensions, angles) {
			moving := model_layers_check_triangles(arm[set.part], set.transform)
			crossings := count_triangle_crossings(moving[:], base[:])
			if crossings.count == 0 {
				continue
			}
			name := arm_check_part_names[set.part]
			detail := fmt.tprintf("fraction %.4f: %d %s triangles cut the base, the first (%s %d, base %d) near (%.3f, %.3f, %.3f) m", fraction, crossings.count, name, name, crossings.first_moving, crossings.first_still, crossings.near.x, crossings.near.y, crossings.near.z)
			append(&problems, Model_Check_Problem{.Arm, detail})
		}
	}
	return problems[:]
}

model_check_subject :: proc(data_directory: string, machine: Machine) -> Model_Check_Subject {
	switch {
	case machine.model == "":
		return .None
	case machine.motion.kind == .Arm:
		return .Arm
	case os.is_file(model_obj.model_file_path(data_directory, machine.model)):
		return .Obj
	}
	return .Voxel
}

model_check_load_problem :: proc(problem: string, allocator := context.temp_allocator) -> []Model_Check_Problem {
	problems := make([]Model_Check_Problem, 1, allocator)
	problems[0] = {.Load, problem}
	return problems
}

// An OBJ model: the loader's refusal is the one load line; then the
// budget, and only within it (so the sweep's cost stays bounded) the
// sweep and the open cells.
check_obj_machine_model :: proc(data_directory: string, machine: Machine, allocator := context.temp_allocator) -> []Model_Check_Problem {
	mesh, problem := load_machine_model_mesh(data_directory, machine, context.temp_allocator)
	if problem != "" {
		return model_check_load_problem(problem, allocator)
	}
	defer destroy_machine_model_mesh(mesh)
	model: model_obj.Obj_Model
	if model, problem = model_obj.load_obj_model_file(model_obj.model_file_path(data_directory, machine.model), context.temp_allocator); problem != "" {
		return model_check_load_problem(problem, allocator)
	}
	defer model_obj.destroy_obj_model(model)
	problems := make([dynamic]Model_Check_Problem, allocator)
	append(&problems, ..model_budget_problems(mesh.body, mesh.part, obj_model_material_count(model)))
	if len(problems) > 0 {
		return problems[:]
	}
	append(&problems, ..model_sweep_problems(machine.motion, machine.footprint, mesh.body, mesh.part))
	open_cells := machine.open_cells
	append(&problems, ..model_open_cell_problems(open_cells[:machine.open_cell_box_count], machine.footprint, mesh.body, mesh.part, "open cells box"))
	// No pod geometry where a fixture's model stands (0198).
	fixture_boxes := machine.fixture_boxes
	append(&problems, ..model_open_cell_problems(fixture_boxes[:machine.fixture_count], machine.footprint, mesh.body, mesh.part, "fixture box"))
	return problems[:]
}

// Reads the machine's files. Nothing for a machine without a model.
check_machine_model :: proc(data_directory: string, machine: Machine, pitch_millimetres: int, allocator := context.temp_allocator) -> []Model_Check_Problem {
	switch model_check_subject(data_directory, machine) {
	case .None:
	case .Obj:
		return check_obj_machine_model(data_directory, machine, allocator)
	case .Arm:
		mesh, problem := load_machine_model_mesh(data_directory, machine, context.temp_allocator)
		if problem != "" {
			return model_check_load_problem(problem, allocator)
		}
		defer destroy_machine_model_mesh(mesh)
		return arm_clearance_problems(machine, mesh.arm, pitch_millimetres, allocator)
	case .Voxel:
		return model_check_load_problem("a voxel model; the checks take OBJ models and the arm", allocator)
	}
	return nil
}

// <machine>: <check>: <detail>, in the temp allocator.
model_check_report_line :: proc(machine_id: string, problem: Model_Check_Problem) -> string {
	return fmt.tprintf("%s: %s: %s", machine_id, model_check_names[problem.check], problem.detail)
}
