package game

import "core:fmt"

// Voxel models to meshes (work item 0055), no raylib here: render_models.odin
// uploads the result. Same coloured faces merge greedily per slice like the
// chunk mesher (world_mesh.odin), whose quad corners and index orders this
// reuses. A model of (sx, sy, sz) voxels covers its machine's unrotated
// footprint of (fx, fy, fz) blocks, so each axis scales by footprint over
// size (8 or 16 voxels per block as authored). Positions are in blocks,
// x and z centred on the footprint and y from its bottom, so one mesh per
// machine serves every rotation (model_transform).
//
// Entity boxes are drawn unlit, and so are models: the vertex colour is the
// palette colour times a fixed shade per face direction, so the shape
// reads without world light.

@(rodata)
model_face_shades := [Direction]f32 {
	.Negative_X = 0.72,
	.Positive_X = 0.86,
	.Negative_Y = 0.55,
	.Positive_Y = 1,
	.Negative_Z = 0.78,
	.Positive_Z = 0.92,
}

// u16 indices, so at most MESH_PART_VERTEX_LIMIT vertices.
Model_Mesh :: struct {
	positions: [dynamic][3]f32,
	colors:    [dynamic][4]u8,
	indices:   [dynamic]u16,
}

Model_Rectangle :: struct {
	using rectangle: Face_Rectangle,
	index:           u8,
}

// The palette index of the face, or 0 where the voxel is empty or covered.
model_face_index :: proc(model: Voxel_Model, position: [3]i32, direction: Direction) -> u8 {
	index := voxel_at(model, position)
	if index == 0 || voxel_at(model, position + direction_offsets[direction]) != 0 {
		return 0
	}
	return index
}

// width by height over the direction's u and v axes, like slice_local.
model_face_mask :: proc(model: Voxel_Model, direction: Direction, slice: int, allocator := context.allocator) -> (mask: []u8, width, height: int) {
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

append_model_quad :: proc(mesh: ^Model_Mesh, corners: [4][3]f32, colour: [4]u8, positive: bool) {
	base := u16(len(mesh.positions))
	for corner in corners {
		append(&mesh.positions, corner)
		append(&mesh.colors, colour)
	}
	order := positive ? positive_quad_indices : negative_quad_indices
	for index in order {
		append(&mesh.indices, base + index)
	}
}

// Voxel corners to blocks, centred across the footprint.
place_model_corners :: proc(corners: [4][3]f32, scale: [3]f32, footprint: [3]i32) -> (placed: [4][3]f32) {
	centre := [3]f32{f32(footprint.x) / 2, 0, f32(footprint.z) / 2}
	for corner, index in corners {
		placed[index] = corner * scale - centre
	}
	return placed
}

mesh_model_slice :: proc(mesh: ^Model_Mesh, model: Voxel_Model, footprint: [3]i32, direction: Direction, slice: int) -> string {
	mask, width, height := model_face_mask(model, direction, slice, context.temp_allocator)
	scale := model_scale(model.size, footprint)
	for rectangle in model_greedy_rectangles(mask, width, height, context.temp_allocator) {
		if len(mesh.positions) + QUAD_VERTEX_COUNT > MESH_PART_VERTEX_LIMIT {
			return fmt.tprintf("more than %d vertices", MESH_PART_VERTEX_LIMIT)
		}
		corners := place_model_corners(quad_corners(direction, slice, rectangle.rectangle), scale, footprint)
		colour := shade_colour(model.palette[rectangle.index], model_face_shades[direction])
		append_model_quad(mesh, corners, colour, direction_is_positive(direction))
	}
	return ""
}

// footprint is the machine's unrotated footprint (Machine.footprint). The
// mesh is in allocator, also on a problem.
mesh_voxel_model :: proc(model: Voxel_Model, footprint: [3]i32, allocator := context.allocator) -> (mesh: Model_Mesh, problem: string) {
	mesh = Model_Mesh {
		positions = make([dynamic][3]f32, allocator),
		colors    = make([dynamic][4]u8, allocator),
		indices   = make([dynamic]u16, allocator),
	}
	for direction in Direction {
		for slice in 0 ..< int(model.size[direction_axis(direction)]) {
			if problem = mesh_model_slice(&mesh, model, footprint, direction, slice); problem != "" {
				return mesh, problem
			}
		}
	}
	if len(mesh.positions) == 0 {
		return mesh, "no voxels"
	}
	return mesh, ""
}

destroy_model_mesh :: proc(mesh: Model_Mesh) {
	delete(mesh.positions)
	delete(mesh.colors)
	delete(mesh.indices)
}

// The mesh of the machine's model; the problem names the machine, the
// file and the chunk.
load_machine_model_mesh :: proc(data_directory: string, machine: Machine, allocator := context.allocator) -> (mesh: Model_Mesh, problem: string) {
	model: Voxel_Model
	if model, problem = load_voxel_model_file(model_file_path(data_directory, machine.model), context.temp_allocator); problem != "" {
		return {}, fmt.tprintf("machine %q: %s", machine.id, problem)
	}
	if mesh, problem = mesh_voxel_model(model, machine.footprint, allocator); problem != "" {
		destroy_model_mesh(mesh)
		return {}, fmt.tprintf("machine %q: model %s: %s", machine.id, machine.model, problem)
	}
	return mesh, ""
}

// By Machine_Id; a machine without a model has an empty mesh. Nothing is
// kept on a problem.
load_machine_model_meshes :: proc(machines: Machine_Registry, data_directory: string, allocator := context.allocator) -> (meshes: []Model_Mesh, problem: string) {
	meshes = make([]Model_Mesh, len(machines.machines), allocator)
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

destroy_model_meshes :: proc(meshes: []Model_Mesh, allocator := context.allocator) {
	for mesh in meshes {
		destroy_model_mesh(mesh)
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
