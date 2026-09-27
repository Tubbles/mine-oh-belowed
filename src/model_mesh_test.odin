package game

import "core:testing"
import rl "vendor:raylib"

// Model meshing tests (work item 0055): models are built in memory.

make_test_voxel_model :: proc(size: [3]i32, filled: [][3]i32, allocator := context.allocator) -> Voxel_Model {
	model := Voxel_Model {
		size        = size,
		cells       = make([]u8, int(size.x * size.y * size.z), allocator),
		palette     = vox_default_palette_colours(),
		model_count = 1,
	}
	for position in filled {
		model.cells[voxel_cell_index(size, position)] = 1
	}
	return model
}

@(test)
test_a_single_voxel_has_six_faces :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}}
	model := make_test_voxel_model({1, 1, 1}, filled[:])
	defer destroy_voxel_model(model)
	mesh, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_mesh(mesh)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(mesh.positions), 24)
	testing.expect_value(t, len(mesh.indices), 36)
	// The top face is the palette colour, the bottom shaded darker.
	testing.expect(t, in_slice([4]u8{255, 255, 255, 255}, mesh.colors[:]))
}

in_slice :: proc(value: [4]u8, values: [][4]u8) -> bool {
	for candidate in values {
		if candidate == value {
			return true
		}
	}
	return false
}

@(test)
test_a_bar_merges_its_long_faces :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}, {1, 0, 0}}
	model := make_test_voxel_model({2, 1, 1}, filled[:])
	defer destroy_voxel_model(model)
	mesh, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_mesh(mesh)
	testing.expect_value(t, problem, "")
	// Two ends and four long faces merged across both voxels.
	testing.expect_value(t, len(mesh.positions), 24)

	// Different colours do not merge: the four long faces split in two.
	model.cells[voxel_cell_index(model.size, {1, 0, 0})] = 2
	split, split_problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_mesh(split)
	testing.expect_value(t, split_problem, "")
	testing.expect_value(t, len(split.positions), 40)
}

@(test)
test_a_model_scales_to_the_footprint :: proc(t: ^testing.T) {
	// 16 voxels per side on a 2 by 2 by 2 footprint: one voxel is an
	// eighth of a block, at the footprint's minimum corner.
	filled := [?][3]i32{{0, 0, 0}}
	model := make_test_voxel_model({16, 16, 16}, filled[:])
	defer destroy_voxel_model(model)
	testing.expect_value(t, model_scale(model.size, {2, 2, 2}), [3]f32{0.125, 0.125, 0.125})
	testing.expect_value(t, model_scale({16, 8, 8}, {2, 1, 1}), [3]f32{0.125, 0.125, 0.125})
	mesh, problem := mesh_voxel_model(model, {2, 2, 2})
	defer destroy_model_mesh(mesh)
	testing.expect_value(t, problem, "")
	minimum, maximum := mesh.positions[0], mesh.positions[0]
	for position in mesh.positions {
		minimum = {min(minimum.x, position.x), min(minimum.y, position.y), min(minimum.z, position.z)}
		maximum = {max(maximum.x, position.x), max(maximum.y, position.y), max(maximum.z, position.z)}
	}
	testing.expect_value(t, minimum, [3]f32{-1, 0, -1})
	testing.expect_value(t, maximum, [3]f32{-0.875, 0.125, -0.875})
}

@(test)
test_an_empty_model_is_refused :: proc(t: ^testing.T) {
	model := make_test_voxel_model({2, 2, 2}, nil)
	defer destroy_voxel_model(model)
	mesh, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_mesh(mesh)
	testing.expect_value(t, problem, "no voxels")
}

@(test)
test_the_model_turns_with_the_entity :: proc(t: ^testing.T) {
	for rotation in u8(0) ..< 4 {
		transform := model_transform({10, 5, -3}, {2, 2, 2}, rotation)
		forward := transform * [4]f32{1, 0, 0, 0}
		testing.expect_value(t, forward.xyz, belt_direction_vector(rotation))
		testing.expect_value(t, transform * [4]f32{0, 0, 0, 1}, [4]f32{11, 5, -2, 1})
	}
	// The unrotated corner cell (0, 0) of a 3 by 2 footprint lands where
	// rotate_footprint_cell puts it: the model's cell centre (-1, -0.5)
	// after a quarter turn is the rotated 2 by 3 box's cell (1, 0).
	transform := model_transform({0, 0, 0}, {2, 1, 3}, 1)
	testing.expect_value(t, transform * [4]f32{-1, 0, -0.5, 1}, [4]f32{1.5, 0, 0.5, 1})
}

@(test)
test_a_machine_without_a_model_keeps_its_box :: proc(t: ^testing.T) {
	meshes := [?]rl.Mesh{{}, {vertexCount = 24}}
	renderer := Model_Renderer{meshes = meshes[:]}
	_, found := machine_model_mesh(renderer, 0)
	testing.expect(t, !found)
	mesh: rl.Mesh
	mesh, found = machine_model_mesh(renderer, 1)
	testing.expect(t, found && mesh.vertexCount == 24)
	_, found = machine_model_mesh(renderer, NO_MACHINE)
	testing.expect(t, !found)
	_, found = machine_model_mesh({}, 0)
	testing.expect(t, !found)
}

@(test)
test_the_shipped_machine_models_mesh :: proc(t: ^testing.T) {
	machines := [?]Machine {
		{id = "burner_mining_drill", footprint = {2, 2, 2}, model = "burner_mining_drill"},
		{id = "stone_furnace", footprint = {2, 2, 2}, model = "stone_furnace"},
		{id = "wooden_chest", footprint = {1, 1, 1}, model = "wooden_chest"},
		{id = "iron_chest", footprint = {1, 1, 1}},
	}
	meshes, problem := load_machine_model_meshes(Machine_Registry{machines = machines[:]}, test_data_directory())
	defer destroy_model_meshes(meshes)
	testing.expect_value(t, problem, "")
	for mesh, index in meshes {
		testing.expectf(t, (len(mesh.positions) > 0) == (machines[index].model != ""), "%s has %d vertices", machines[index].id, len(mesh.positions))
	}

	machines[2].model = "no_such_model"
	_, problem = load_machine_model_meshes(Machine_Registry{machines = machines[:]}, test_data_directory())
	testing.expect(t, problem != "", "a missing model file is refused")
	testing.expect(t, is_model_id("wooden_chest") && !is_model_id("../chest") && !is_model_id(""))
}
