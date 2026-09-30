package game

import "core:strings"
import "core:testing"
import "model_vox"

// Model meshing tests (work item 0055): models are built in memory.

make_test_voxel_model :: proc(size: [3]i32, filled: [][3]i32, allocator := context.allocator) -> model_vox.Voxel_Model {
	model := model_vox.Voxel_Model {
		size        = size,
		cells       = make([]u8, int(size.x * size.y * size.z), allocator),
		palette     = model_vox.vox_default_palette_colours(),
		model_count = 1,
	}
	for position in filled {
		model.cells[model_vox.voxel_cell_index(size, position)] = 1
	}
	return model
}

@(test)
test_a_single_voxel_has_six_faces :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}}
	model := make_test_voxel_model({1, 1, 1}, filled[:])
	defer delete(model.cells)
	meshes, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_layers(meshes)
	mesh := meshes[.Lit]
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(mesh.positions), 24)
	testing.expect_value(t, len(mesh.indices), 36)
	testing.expect_value(t, len(meshes[.Emissive].positions), 0)
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
	defer delete(model.cells)
	meshes, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_layers(meshes)
	mesh := meshes[.Lit]
	testing.expect_value(t, problem, "")
	// Two ends and four long faces merged across both voxels.
	testing.expect_value(t, len(mesh.positions), 24)

	// Different colours do not merge: the four long faces split in two.
	model.cells[model_vox.voxel_cell_index(model.size, {1, 0, 0})] = 2
	split, split_problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_layers(split)
	testing.expect_value(t, split_problem, "")
	testing.expect_value(t, len(split[.Lit].positions), 40)
}

@(test)
test_a_model_scales_to_the_footprint :: proc(t: ^testing.T) {
	// 16 voxels per side on a 2 by 2 by 2 footprint: one voxel is an
	// eighth of a block, at the footprint's minimum corner.
	filled := [?][3]i32{{0, 0, 0}}
	model := make_test_voxel_model({16, 16, 16}, filled[:])
	defer delete(model.cells)
	testing.expect_value(t, model_scale(model.size, {2, 2, 2}), [3]f32{0.125, 0.125, 0.125})
	testing.expect_value(t, model_scale({16, 8, 8}, {2, 1, 1}), [3]f32{0.125, 0.125, 0.125})
	meshes, problem := mesh_voxel_model(model, {2, 2, 2})
	defer destroy_model_layers(meshes)
	mesh := meshes[.Lit]
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
	defer delete(model.cells)
	meshes, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_layers(meshes)
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
test_emissive_faces_mesh_apart_without_the_shade :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}, {1, 0, 0}}
	model := make_test_voxel_model({2, 1, 1}, filled[:])
	defer delete(model.cells)
	model.cells[model_vox.voxel_cell_index(model.size, {1, 0, 0})] = EMISSIVE_PALETTE_START
	model.palette[EMISSIVE_PALETTE_START] = {200, 100, 50, 255}
	meshes, problem := mesh_voxel_model(model, {1, 1, 1})
	defer destroy_model_layers(meshes)
	testing.expect_value(t, problem, "")
	// Each voxel keeps five faces, the shared one is covered.
	testing.expect_value(t, len(meshes[.Lit].positions), 20)
	testing.expect_value(t, len(meshes[.Emissive].positions), 20)
	for colour in meshes[.Emissive].colors {
		testing.expect_value(t, colour, [4]u8{200, 100, 50, 255})
	}
	testing.expect_value(t, palette_index_layer(EMISSIVE_PALETTE_START - 1), Model_Layer.Lit)
	testing.expect_value(t, palette_index_layer(255), Model_Layer.Emissive)
}

@(test)
test_the_model_top_is_its_highest_voxel :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}, {1, 5, 1}}
	model := make_test_voxel_model({2, 8, 2}, filled[:])
	defer delete(model.cells)
	testing.expect_value(t, voxel_model_top(model), 6)
	empty := make_test_voxel_model({2, 2, 2}, nil)
	defer delete(empty.cells)
	testing.expect_value(t, voxel_model_top(empty), 0)
}

@(test)
test_a_machine_without_a_model_keeps_its_box :: proc(t: ^testing.T) {
	models := [?]Uploaded_Machine_Model{{}, {body = {.Lit = {vertexCount = 24}, .Emissive = {}}, top = 1.5}, {body = {.Lit = {}, .Emissive = {vertexCount = 8}}}}
	renderer := Model_Renderer{models = models[:]}
	_, found := machine_model(renderer, 0)
	testing.expect(t, !found)
	model: Uploaded_Machine_Model
	model, found = machine_model(renderer, 1)
	testing.expect(t, found && model.body[.Lit].vertexCount == 24)
	_, found = machine_model(renderer, 2)
	testing.expect(t, found, "a model of glow voxels only is a model")
	_, found = machine_model(renderer, NO_MACHINE)
	testing.expect(t, !found)
	_, found = machine_model({}, 0)
	testing.expect(t, !found)
	testing.expect_value(t, machine_model_top(renderer, {machine = 1, size = {2, 2, 2}}), 1.5)
	testing.expect_value(t, machine_model_top(renderer, {machine = 0, size = {2, 3, 2}}), 3)
}

// The ids and footprints of data/machines.sjson, resolved without the
// item registry.
shipped_machines :: proc(allocator := context.allocator) -> []Machine {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	machines := make([]Machine, len(file.machines), allocator)
	for definition, index in file.machines {
		machines[index] = resolve_machine(definition, NO_ITEM)
	}
	return machines
}

// Every machine but belts and pipes has a model, every model file loads
// and meshes, and a motion that moves a part has its part file.
@(test)
test_the_shipped_machine_models_mesh :: proc(t: ^testing.T) {
	machines := shipped_machines()
	defer delete(machines)
	meshes, problem := load_machine_model_meshes(Machine_Registry{machines = machines}, test_data_directory())
	defer destroy_model_meshes(meshes)
	testing.expect_value(t, problem, "")
	if problem != "" {
		return
	}
	for machine, index in machines {
		mesh := meshes[index]
		without_model := machine.kind == .Belt || machine.kind == .Pipe
		testing.expectf(t, (machine.model == "") == without_model, "%s: model %q", machine.id, machine.model)
		body_vertices := len(mesh.body[.Lit].positions) + len(mesh.body[.Emissive].positions)
		testing.expectf(t, (body_vertices > 0) == !without_model, "%s has %d vertices", machine.id, body_vertices)
		part_vertices := len(mesh.part[.Lit].positions) + len(mesh.part[.Emissive].positions)
		testing.expectf(t, (part_vertices > 0) == motion_has_part(machine.motion.kind), "%s: a %v motion and %d part vertices", machine.id, machine.motion.kind, part_vertices)
		testing.expectf(t, without_model || mesh.top > 0 && mesh.top <= f32(machine.footprint.y), "%s: top %v", machine.id, mesh.top)
	}
}

@(test)
test_a_missing_model_or_part_file_is_refused :: proc(t: ^testing.T) {
	machines := [?]Machine {
		{id = "wooden_chest", footprint = {1, 1, 1}, model = "wooden_chest"},
		{id = "iron_chest", footprint = {1, 1, 1}},
	}
	meshes, problem := load_machine_model_meshes(Machine_Registry{machines = machines[:]}, test_data_directory())
	testing.expect_value(t, problem, "")
	destroy_model_meshes(meshes)

	machines[0].motion = {kind = .Spin, period_seconds = 1}
	_, problem = load_machine_model_meshes(Machine_Registry{machines = machines[:]}, test_data_directory())
	testing.expect(t, strings.contains(problem, "wooden_chest_part.vox"), problem)

	machines[0].motion = {}
	machines[0].model = "no_such_model"
	_, problem = load_machine_model_meshes(Machine_Registry{machines = machines[:]}, test_data_directory())
	testing.expect(t, problem != "", "a missing model file is refused")
	testing.expect(t, is_model_id("wooden_chest") && !is_model_id("../chest") && !is_model_id(""))
}

// A spinning part turns about the middle of its voxels, so it does not
// wobble: the pivot names that middle on the two other axes.
@(test)
test_shipped_spinning_parts_turn_about_their_middle :: proc(t: ^testing.T) {
	machines := shipped_machines()
	defer delete(machines)
	for machine in machines {
		if machine.motion.kind != .Spin {
			continue
		}
		path := model_vox.model_file_path(test_data_directory(), model_part_id(machine.model))
		part, problem := model_vox.load_voxel_model_file(path, context.temp_allocator)
		testing.expect_value(t, problem, "")
		minimum, maximum := part.size, [3]i32{-1, -1, -1}
		for z in 0 ..< part.size.z {
			for y in 0 ..< part.size.y {
				for x in 0 ..< part.size.x {
					if model_vox.voxel_at(part, {x, y, z}) != 0 {
						minimum = {min(minimum.x, x), min(minimum.y, y), min(minimum.z, z)}
						maximum = {max(maximum.x, x), max(maximum.y, y), max(maximum.z, z)}
					}
				}
			}
		}
		scale := model_scale(part.size, machine.footprint)
		for axis in 0 ..< 3 {
			if axis == machine.motion.axis {
				continue
			}
			middle := f32(minimum[axis] + maximum[axis] + 1) / 2 * scale[axis]
			testing.expectf(t, abs(middle - machine.motion.pivot[axis]) < 0.01, "%s: pivot %v, the part's middle on axis %d is %v", machine.id, machine.motion.pivot, axis, middle)
		}
	}
}
