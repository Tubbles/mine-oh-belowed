package game

import "core:fmt"
import "core:math/linalg"
import "model_obj"

// OBJ machine models to meshes (work item 0204), no raylib here:
// render_models.odin uploads the result, the same Model_Layers as the
// voxel mesher's (model_mesh.odin). The model is in cells of the
// unrotated footprint already (model_obj.odin), so nothing is scaled.
// Every triangle gets three vertices of its own (flat shading), coloured
// Kd times a shade of its normal; emissive ones go to their own layer
// unshaded. The group named part is the moving part.

// The shade of a normal is MODEL_SHADE_BASE plus its dot with
// MODEL_SHADE_GRADIENT, clamped to 0..1. Chosen so an axis aligned box's
// faces come within 0.1 of model_face_shades (-x 0.745, +x 0.805, -y
// 0.55, +y 1.0, -z 0.69, +z 0.86): a linear shade makes opposite faces
// sum to twice the base, and x and z differ so two side faces meet at a
// visible edge. The gradient is 0.242 long, so a normal tilted up,
// forward and right would pass 1: the clamp.
MODEL_SHADE_BASE :: 0.775
MODEL_SHADE_GRADIENT :: [3]f32{0.03, 0.225, 0.085}

// For a unit normal.
model_normal_shade :: proc(normal: [3]f32) -> f32 {
	return clamp(MODEL_SHADE_BASE + linalg.dot(normal, MODEL_SHADE_GRADIENT), 0, 1)
}

// Counter-clockwise seen from the front, as raylib culls; zero for zero
// area.
triangle_winding_normal :: proc(corners: [3][3]f32) -> [3]f32 {
	cross := linalg.cross(corners[1] - corners[0], corners[2] - corners[0])
	length := linalg.length(cross)
	return length > 0 ? cross / length : {}
}

// The file's normal when it gave one, else the winding's.
obj_triangle_normal :: proc(triangle: model_obj.Obj_Triangle) -> [3]f32 {
	if triangle.normal != {} {
		return triangle.normal
	}
	return triangle_winding_normal(triangle.corners)
}

// Emissive triangles keep Kd: the glow is not shaded.
obj_triangle_colour :: proc(triangle: model_obj.Obj_Triangle) -> [4]u8 {
	colour := [4]u8{triangle.colour.r, triangle.colour.g, triangle.colour.b, 255}
	if triangle.emissive {
		return colour
	}
	return shade_colour(colour, model_normal_shade(obj_triangle_normal(triangle)))
}

append_model_triangle :: proc(mesh: ^Model_Mesh, corners: [3][3]f32, colour: [4]u8, normal: [3]f32) {
	base := u16(len(mesh.positions))
	for corner, index in corners {
		append(&mesh.positions, corner)
		append(&mesh.normals, normal)
		append(&mesh.colors, colour)
		append(&mesh.indices, base + u16(index))
	}
}

// The triangles whose part flag matches. A triangle without a normal
// (zero area and no vn) draws nothing and is skipped. The meshes are in
// allocator, also on a problem.
mesh_obj_triangles :: proc(model: model_obj.Obj_Model, part: bool, allocator := context.allocator) -> (meshes: Model_Layers, problem: string) {
	for layer in Model_Layer {
		meshes[layer] = make_model_mesh(allocator)
	}
	for triangle in model.triangles {
		if triangle.part != part || obj_triangle_normal(triangle) == {} {
			continue
		}
		mesh := &meshes[triangle.emissive ? .Emissive : .Lit]
		if len(mesh.positions) + 3 > MESH_PART_VERTEX_LIMIT {
			return meshes, fmt.tprintf("more than %d vertices", MESH_PART_VERTEX_LIMIT)
		}
		append_model_triangle(mesh, triangle.corners, obj_triangle_colour(triangle), obj_triangle_normal(triangle))
	}
	return meshes, ""
}

model_layers_vertex_count :: proc(meshes: Model_Layers) -> int {
	return len(meshes[.Lit].positions) + len(meshes[.Emissive].positions)
}

// Over every position of both. Only called with a non-empty body.
model_layers_bounds :: proc(body, part: Model_Layers) -> (minimum, maximum: [3]f32) {
	minimum, maximum = max(f32), min(f32)
	for layers in ([2]Model_Layers{body, part}) {
		for mesh in layers {
			for position in mesh.positions {
				minimum = linalg.min(minimum, position)
				maximum = linalg.max(maximum, position)
			}
		}
	}
	return minimum, maximum
}

// "" when x and z stay within the footprint and y above its bottom, each
// with MODEL_FOOTPRINT_TOLERANCE_CELLS of slack. No bound above.
model_footprint_problem :: proc(minimum, maximum: [3]f32, footprint: [3]i32) -> string {
	for axis in ([2]int{0, 2}) {
		half := f32(footprint[axis]) / 2
		name := axis == 0 ? "x" : "z"
		if maximum[axis] > half + MODEL_FOOTPRINT_TOLERANCE_CELLS {
			return fmt.tprintf("reaches %s %.3f, past the footprint's %.3f", name, maximum[axis], half)
		}
		if minimum[axis] < -half - MODEL_FOOTPRINT_TOLERANCE_CELLS {
			return fmt.tprintf("reaches %s %.3f, past the footprint's %.3f", name, minimum[axis], -half)
		}
	}
	if minimum.y < -MODEL_FOOTPRINT_TOLERANCE_CELLS {
		return fmt.tprintf("reaches y %.3f, below the footprint's bottom", minimum.y)
	}
	return ""
}

// The body, the part and the top read off the mesh. Pure, so the tests
// use it without files. Nothing is kept on a problem.
mesh_obj_machine_model :: proc(model: model_obj.Obj_Model, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string) {
	if mesh.body, problem = mesh_obj_triangles(model, false, allocator); problem == "" {
		mesh.part, problem = mesh_obj_triangles(model, true, allocator)
	}
	has_part := model_layers_vertex_count(mesh.part) > 0
	switch {
	case problem != "":
	case model_layers_vertex_count(mesh.body) == 0:
		problem = "no triangles"
	case motion_has_part(machine.motion.kind) && !has_part:
		problem = fmt.tprintf("no group named part for its %v motion", machine.motion.kind)
	case !motion_has_part(machine.motion.kind) && has_part:
		problem = "a group named part but its motion moves none"
	case:
		minimum, maximum := model_layers_bounds(mesh.body, mesh.part)
		problem = model_footprint_problem(minimum, maximum, machine.footprint)
		mesh.top = maximum.y
	}
	if problem != "" {
		destroy_machine_model_mesh(mesh)
		return {}, problem
	}
	return mesh, ""
}

// The problem names the machine, the file and the line.
load_obj_machine_model_mesh :: proc(path: string, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string) {
	model, read_problem := model_obj.load_obj_model_file(path, context.temp_allocator)
	if read_problem != "" {
		return {}, fmt.tprintf("machine %q: %s", machine.id, read_problem)
	}
	defer model_obj.destroy_obj_model(model)
	if mesh, problem = mesh_obj_machine_model(model, machine, allocator); problem != "" {
		return {}, fmt.tprintf("machine %q: model %s: %s", machine.id, machine.model, problem)
	}
	return mesh, ""
}
