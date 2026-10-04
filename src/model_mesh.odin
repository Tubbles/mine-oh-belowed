package game

import "core:fmt"
import "core:os"
import "model_obj"
import "model_vox"

// The two readers share the directory until 0206 removes model_vox.
#assert(model_obj.MODELS_DIRECTORY == model_vox.MODELS_DIRECTORY)

// Voxel models to meshes (work item 0055), no raylib here: render_models.odin
// uploads the result. Same coloured faces merge greedily per slice like the
// chunk mesher (world_mesh.odin), whose quad corners and index orders this
// reuses. A model of (sx, sy, sz) voxels covers its machine's unrotated
// footprint of (fx, fy, fz) blocks, so each axis scales by footprint over
// size (8 or 16 voxels per block as authored). Positions are in blocks,
// x and z centred on the footprint and y from its bottom, so one mesh per
// machine serves every rotation (model_transform).
//
// The vertex colour is the palette colour times a fixed shade per face
// direction, so the shape reads; the renderer multiplies it by the world
// light at the machine (model_motion.odin). Faces of the emissive palette
// indices (EMISSIVE_PALETTE_START and up) go to a mesh of their own
// without the shade, drawn at the glow brightness instead of the light.
// A machine whose motion moves a part has a second model file,
// <model>_part.vox, of the same size, meshed the same way.
//
// A machine whose data/models/<model>.obj exists takes that instead
// (work item 0204, model_triangle_mesh.odin): triangles in cells of the
// footprint, not scaled, flat shaded by MODEL_SHADE_BASE and
// MODEL_SHADE_GRADIENT, its group named part the moving part.
// model_face_shades serves the voxel mesher until 0206.

@(rodata)
model_face_shades := [Direction]f32 {
	.Negative_X = 0.72,
	.Positive_X = 0.86,
	.Negative_Y = 0.55,
	.Positive_Y = 1,
	.Negative_Z = 0.78,
	.Positive_Z = 0.92,
}

// Two shapes (0226): the voxel mesher shares a quad's four corners and
// writes indices, u16, so at most MESH_PART_VERTEX_LIMIT vertices a layer;
// the triangle mesher writes three vertices per triangle in order and no
// indices, drawn unindexed, bounded by the triangle budget
// (model_check.odin) only. Read a mesh's triangles through
// model_mesh_triangle, which serves both.
// normals holds one unit normal per position, its face's (0224: the model
// shader's point lights).
Model_Mesh :: struct {
	positions: [dynamic][3]f32,
	normals:   [dynamic][3]f32,
	colors:    [dynamic][4]u8,
	indices:   [dynamic]u16,
}

// Lit faces take the world light, emissive ones the glow brightness.
Model_Layer :: enum u8 {
	Lit,
	Emissive,
}

Model_Layers :: [Model_Layer]Model_Mesh

// The body and the moving part (empty without one), and the height of the
// highest voxel of either above the footprint's bottom, in blocks. An
// arm motion leaves body and part empty and fills arm (model_arm.odin),
// its top the folded arm's on the block frame.
Machine_Model_Mesh :: struct {
	body: Model_Layers,
	part: Model_Layers,
	arm:  [Arm_Part]Model_Layers,
	top:  f32,
}

Model_Rectangle :: struct {
	using rectangle: Face_Rectangle,
	index:           u8,
}

// The palette index of the face, or 0 where the voxel is empty or covered.
model_face_index :: proc(model: model_vox.Voxel_Model, position: [3]i32, direction: Direction) -> u8 {
	index := model_vox.voxel_at(model, position)
	if index == 0 || model_vox.voxel_at(model, position + direction_offsets[direction]) != 0 {
		return 0
	}
	return index
}

// width by height over the direction's u and v axes, like slice_local.
model_face_mask :: proc(model: model_vox.Voxel_Model, direction: Direction, slice: int, allocator := context.allocator) -> (mask: []u8, width, height: int) {
	axis := direction_axis(direction)
	u_axis, v_axis := (axis + 1) % 3, (axis + 2) % 3
	width, height = int(model.size[u_axis]), int(model.size[v_axis])
	mask = make([]u8, width * height, allocator)
	for v in 0 ..< height {
		for u in 0 ..< width {
			position: [3]i32
			position[axis], position[u_axis], position[v_axis] = i32(slice), i32(u), i32(v)
			mask[u + v * width] = model_face_index(model, position, direction)
		}
	}
	return mask, width, height
}

model_row_matches :: proc(mask: []u8, width, u, v, run: int, index: u8) -> bool {
	for offset in 0 ..< run {
		if mask[u + offset + v * width] != index {
			return false
		}
	}
	return true
}

// Grows each rectangle along u, then along v while whole rows match.
// Consumes the mask.
model_greedy_rectangles :: proc(mask: []u8, width, height: int, allocator := context.allocator) -> [dynamic]Model_Rectangle {
	rectangles := make([dynamic]Model_Rectangle, allocator)
	for v in 0 ..< height {
		for u in 0 ..< width {
			index := mask[u + v * width]
			if index == 0 {
				continue
			}
			rectangle := Model_Rectangle{rectangle = {u = u, v = v, width = 1, height = 1}, index = index}
			for u + rectangle.width < width && mask[u + rectangle.width + v * width] == index {
				rectangle.width += 1
			}
			for v + rectangle.height < height && model_row_matches(mask, width, u, v + rectangle.height, rectangle.width, index) {
				rectangle.height += 1
			}
			for row in v ..< v + rectangle.height {
				for column in u ..< u + rectangle.width {
					mask[column + row * width] = 0
				}
			}
			append(&rectangles, rectangle)
		}
	}
	return rectangles
}

model_scale :: proc(size, footprint: [3]i32) -> [3]f32 {
	return {f32(footprint.x) / f32(size.x), f32(footprint.y) / f32(size.y), f32(footprint.z) / f32(size.z)}
}

shade_colour :: proc(colour: [4]u8, shade: f32) -> [4]u8 {
	return {u8(f32(colour.r) * shade + 0.5), u8(f32(colour.g) * shade + 0.5), u8(f32(colour.b) * shade + 0.5), 255}
}

direction_unit_vector :: proc(direction: Direction) -> [3]f32 {
	offset := direction_offsets[direction]
	return {f32(offset.x), f32(offset.y), f32(offset.z)}
}

append_model_quad :: proc(mesh: ^Model_Mesh, corners: [4][3]f32, colour: [4]u8, positive: bool, normal: [3]f32) {
	base := u16(len(mesh.positions))
	for corner in corners {
		append(&mesh.positions, corner)
		append(&mesh.normals, normal)
		append(&mesh.colors, colour)
	}
	order := positive ? positive_quad_indices : negative_quad_indices
	for index in order {
		append(&mesh.indices, base + index)
	}
}

// Indexed or not (0226).
model_mesh_triangle_count :: proc(mesh: Model_Mesh) -> int {
	if len(mesh.indices) > 0 {
		return len(mesh.indices) / 3
	}
	return len(mesh.positions) / 3
}

// The vertices of the triangle's corners: through the indices when there
// are any, else three in order.
model_mesh_triangle_vertices :: proc(mesh: Model_Mesh, triangle: int) -> [3]int {
	if len(mesh.indices) > 0 {
		first := 3 * triangle
		return {int(mesh.indices[first]), int(mesh.indices[first + 1]), int(mesh.indices[first + 2])}
	}
	return {3 * triangle, 3 * triangle + 1, 3 * triangle + 2}
}

model_mesh_triangle :: proc(mesh: Model_Mesh, triangle: int) -> [3][3]f32 {
	vertices := model_mesh_triangle_vertices(mesh, triangle)
	return {mesh.positions[vertices[0]], mesh.positions[vertices[1]], mesh.positions[vertices[2]]}
}

// Voxel corners to blocks, centred across the footprint.
place_model_corners :: proc(corners: [4][3]f32, scale: [3]f32, footprint: [3]i32) -> (placed: [4][3]f32) {
	centre := [3]f32{f32(footprint.x) / 2, 0, f32(footprint.z) / 2}
	for corner, index in corners {
		placed[index] = corner * scale - centre
	}
	return placed
}

palette_index_layer :: proc(index: u8) -> Model_Layer {
	return index >= EMISSIVE_PALETTE_START ? .Emissive : .Lit
}

// Emissive faces keep their palette colour: the glow is not shaded.
model_face_colour :: proc(model: model_vox.Voxel_Model, index: u8, direction: Direction) -> [4]u8 {
	if palette_index_layer(index) == .Emissive {
		return shade_colour(model.palette[index], 1)
	}
	return shade_colour(model.palette[index], model_face_shades[direction])
}

mesh_model_slice :: proc(meshes: ^Model_Layers, model: model_vox.Voxel_Model, footprint: [3]i32, direction: Direction, slice: int) -> string {
	mask, width, height := model_face_mask(model, direction, slice, context.temp_allocator)
	scale := model_scale(model.size, footprint)
	for rectangle in model_greedy_rectangles(mask, width, height, context.temp_allocator) {
		mesh := &meshes[palette_index_layer(rectangle.index)]
		if len(mesh.positions) + QUAD_VERTEX_COUNT > MESH_PART_VERTEX_LIMIT {
			return fmt.tprintf("more than %d vertices", MESH_PART_VERTEX_LIMIT)
		}
		// The scale is positive and per axis, so the face direction stays
		// the normal after place_model_corners.
		corners := place_model_corners(quad_corners(direction, slice, rectangle.rectangle), scale, footprint)
		append_model_quad(mesh, corners, model_face_colour(model, rectangle.index, direction), direction_is_positive(direction), direction_unit_vector(direction))
	}
	return ""
}

make_model_mesh :: proc(allocator := context.allocator) -> Model_Mesh {
	return Model_Mesh {
		positions = make([dynamic][3]f32, allocator),
		normals = make([dynamic][3]f32, allocator),
		colors = make([dynamic][4]u8, allocator),
		indices = make([dynamic]u16, allocator),
	}
}

// footprint is the machine's unrotated footprint (Machine.footprint). The
// meshes are in allocator, also on a problem.
mesh_voxel_model :: proc(model: model_vox.Voxel_Model, footprint: [3]i32, allocator := context.allocator) -> (meshes: Model_Layers, problem: string) {
	for layer in Model_Layer {
		meshes[layer] = make_model_mesh(allocator)
	}
	for direction in Direction {
		for slice in 0 ..< int(model.size[direction_axis(direction)]) {
			if problem = mesh_model_slice(&meshes, model, footprint, direction, slice); problem != "" {
				return meshes, problem
			}
		}
	}
	if len(meshes[.Lit].positions) + len(meshes[.Emissive].positions) == 0 {
		return meshes, "no voxels"
	}
	return meshes, ""
}

destroy_model_mesh :: proc(mesh: Model_Mesh) {
	delete(mesh.positions)
	delete(mesh.normals)
	delete(mesh.colors)
	delete(mesh.indices)
}

destroy_model_layers :: proc(meshes: Model_Layers) {
	for mesh in meshes {
		destroy_model_mesh(mesh)
	}
}

destroy_machine_model_mesh :: proc(mesh: Machine_Model_Mesh) {
	destroy_model_layers(mesh.body)
	destroy_model_layers(mesh.part)
	destroy_arm_part_meshes(mesh.arm)
}

// One above the highest filled voxel, 0 for an empty model.
voxel_model_top :: proc(model: model_vox.Voxel_Model) -> i32 {
	for y := model.size.y - 1; y >= 0; y -= 1 {
		for z in 0 ..< model.size.z {
			for x in 0 ..< model.size.x {
				if model_vox.voxel_at(model, {x, y, z}) != 0 {
					return y + 1
				}
			}
		}
	}
	return 0
}

// The id of the part file of a model.
model_part_id :: proc(model: string) -> string {
	return fmt.tprintf("%s_part", model)
}

// The machine's model: its .obj when that exists, else its .vox and part
// file (an arm its part files); the problem names the machine, the file
// and the line or the chunk.
load_machine_model_mesh :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string) {
	if machine.motion.kind == .Arm {
		mesh.arm, problem = load_arm_part_meshes(data_directory, machine, allocator)
		mesh.top = arm_rest_top_metres(arm_dimensions_on_frame(machine.inserter_reach, BLOCK_FRAME_PITCH_MILLIMETRES))
		return mesh, problem
	}
	if obj := model_obj.model_file_path(data_directory, machine.model); os.is_file(obj) {
		return load_obj_machine_model_mesh(obj, machine, allocator)
	}
	return load_voxel_machine_model_mesh(data_directory, machine, allocator)
}

// The machine's <model>.vox and, for a motion that moves a part, its part
// file.
load_voxel_machine_model_mesh :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (mesh: Machine_Model_Mesh, problem: string) {
	body, part: model_vox.Voxel_Model
	if body, problem = model_vox.load_voxel_model_file(model_vox.model_file_path(data_directory, machine.model), context.temp_allocator); problem != "" {
		return {}, fmt.tprintf("machine %q: %s", machine.id, problem)
	}
	if motion_has_part(machine.motion.kind) {
		part_id := model_part_id(machine.model)
		if part, problem = model_vox.load_voxel_model_file(model_vox.model_file_path(data_directory, part_id), context.temp_allocator); problem != "" {
			return {}, fmt.tprintf("machine %q: %s", machine.id, problem)
		}
		if part.size != body.size {
			return {}, fmt.tprintf("machine %q: model %s is %v voxels, its body %v", machine.id, part_id, part.size, body.size)
		}
	}
	if mesh.body, problem = mesh_voxel_model(body, machine.footprint, allocator); problem == "" && part.cells != nil {
		mesh.part, problem = mesh_voxel_model(part, machine.footprint, allocator)
	}
	if problem != "" {
		destroy_machine_model_mesh(mesh)
		return {}, fmt.tprintf("machine %q: model %s: %s", machine.id, machine.model, problem)
	}
	mesh.top = f32(max(voxel_model_top(body), voxel_model_top(part))) * model_scale(body.size, machine.footprint).y
	return mesh, ""
}

// By Machine_Id; a machine without a model has empty meshes. Nothing is
// kept on a problem.
load_machine_model_meshes :: proc(machines: Machine_Registry, data_directory: string, allocator := context.allocator) -> (meshes: []Machine_Model_Mesh, problem: string) {
	meshes = make([]Machine_Model_Mesh, len(machines.machines), allocator)
	for machine, index in machines.machines {
		if machine.model == "" {
			continue
		}
		if meshes[index], problem = load_machine_model_mesh(data_directory, machine, allocator); problem != "" {
			destroy_model_meshes(meshes, allocator)
			return nil, problem
		}
	}
	return meshes, ""
}

destroy_model_meshes :: proc(meshes: []Machine_Model_Mesh, allocator := context.allocator) {
	for mesh in meshes {
		destroy_machine_model_mesh(mesh)
	}
	delete(meshes, allocator)
}

// Model space to the world for an entity at origin with its rotated size:
// quarter turns about the vertical axis through the footprint's centre,
// each taking +x to +z like belt_direction_offset, then onto the
// footprint's bottom centre.
model_transform :: proc(origin: World_Coordinate, size: [3]i32, rotation: u8) -> matrix[4, 4]f32 {
	cosines := [4]f32{1, 0, -1, 0}
	sines := [4]f32{0, 1, 0, -1}
	cosine, sine := cosines[rotation % 4], sines[rotation % 4]
	centre_x := f32(origin.x) + f32(size.x) / 2
	centre_z := f32(origin.z) + f32(size.z) / 2
	return matrix[4, 4]f32{
		cosine, 0, -sine, centre_x,
		0, 1, 0, f32(origin.y),
		sine, 0, cosine, centre_z,
		0, 0, 0, 1,
	}
}
