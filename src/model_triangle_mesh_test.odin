package game

import "core:math/linalg"
import "core:os"
import "core:strings"
import "core:testing"
import "model_obj"
import "model_vox"
import "platform"

// OBJ mesher tests (work item 0204): models built in memory or parsed
// from text here; the file tests use a temporary directory they create
// and remove.

TEST_OBJ_MATERIALS :: "newmtl grey\nKd 0.5 0.25 1\nKe 0 0 0\n"

// A unit box on the bottom of a one cell footprint, every face wound
// counter-clockwise seen from outside.
TEST_OBJ_BOX :: `mtllib box.mtl
v -0.5 0 -0.5
v 0.5 0 -0.5
v 0.5 0 0.5
v -0.5 0 0.5
v -0.5 1 -0.5
v 0.5 1 -0.5
v 0.5 1 0.5
v -0.5 1 0.5
usemtl grey
f 1 2 3 4
f 8 7 6 5
f 1 5 6 2
f 2 6 7 3
f 3 7 8 4
f 4 8 5 1
`

test_obj_box :: proc() -> model_obj.Obj_Model {
	materials, material_problem := model_obj.parse_material_library(TEST_OBJ_MATERIALS, context.temp_allocator)
	assert(material_problem == "")
	model, problem := model_obj.parse_obj_model(TEST_OBJ_BOX, materials[:], context.temp_allocator)
	assert(problem == "")
	return model
}

// One lit grey triangle, in the temp allocator.
test_obj_triangles :: proc(triangles: ..model_obj.Obj_Triangle) -> model_obj.Obj_Model {
	model := model_obj.Obj_Model{triangles = make([dynamic]model_obj.Obj_Triangle, context.temp_allocator)}
	append(&model.triangles, ..triangles)
	return model
}

test_obj_triangle :: proc(corners: [3][3]f32, part := false) -> model_obj.Obj_Triangle {
	return {corners = corners, colour = {100, 100, 100}, part = part}
}

direction_unit_vector :: proc(direction: Direction) -> [3]f32 {
	offset := direction_offsets[direction]
	return {f32(offset.x), f32(offset.y), f32(offset.z)}
}

@(test)
test_a_box_keeps_the_voxel_shades :: proc(t: ^testing.T) {
	expected := [Direction]f32 {
		.Negative_X = 0.745,
		.Positive_X = 0.805,
		.Negative_Y = 0.55,
		.Positive_Y = 1,
		.Negative_Z = 0.69,
		.Positive_Z = 0.86,
	}
	for direction in Direction {
		shade := model_normal_shade(direction_unit_vector(direction))
		testing.expectf(t, abs(shade - model_face_shades[direction]) <= 0.1, "%v: %v against the voxel %v", direction, shade, model_face_shades[direction])
		testing.expectf(t, abs(shade - expected[direction]) < 1e-4, "%v: %v", direction, shade)
	}
	testing.expect_value(t, model_normal_shade(linalg.normalize(MODEL_SHADE_GRADIENT)), 1)
}

@(test)
test_a_face_without_normals_is_shaded_from_its_winding :: proc(t: ^testing.T) {
	upward := test_obj_triangle({{0, 0, 0}, {0, 0, 1}, {1, 0, 0}})
	testing.expect_value(t, obj_triangle_colour(upward), [4]u8{100, 100, 100, 255})
	downward := test_obj_triangle({{0, 0, 0}, {1, 0, 0}, {0, 0, 1}})
	testing.expect_value(t, obj_triangle_colour(downward), shade_colour({100, 100, 100, 255}, 0.55))
	for corners in ([2][3][3]f32{upward.corners, downward.corners}) {
		with_normal := test_obj_triangle(corners)
		with_normal.normal = {1, 0, 0}
		testing.expect_value(t, obj_triangle_colour(with_normal), shade_colour({100, 100, 100, 255}, model_normal_shade({1, 0, 0})))
	}
}

// Every triangle's winding normal points away from the centre.
expect_outward_winding :: proc(t: ^testing.T, mesh: Model_Mesh, centre: [3]f32, name: string) {
	testing.expectf(t, len(mesh.indices) > 0, "%s has no triangles", name)
	for triangle := 0; triangle + 2 < len(mesh.indices); triangle += 3 {
		corners: [3][3]f32
		for &corner, index in corners {
			corner = mesh.positions[mesh.indices[triangle + index]]
		}
		middle := (corners[0] + corners[1] + corners[2]) / 3
		normal := triangle_winding_normal(corners)
		testing.expectf(t, linalg.dot(normal, middle - centre) > 0, "%s: triangle %d winds inward", name, triangle / 3)
	}
}

@(test)
test_obj_and_voxel_meshes_wind_alike :: proc(t: ^testing.T) {
	filled := [?][3]i32{{0, 0, 0}}
	voxel := make_test_voxel_model({1, 1, 1}, filled[:])
	defer delete(voxel.cells)
	voxel_meshes, voxel_problem := mesh_voxel_model(voxel, {1, 1, 1})
	defer destroy_model_layers(voxel_meshes)
	testing.expect_value(t, voxel_problem, "")
	expect_outward_winding(t, voxel_meshes[.Lit], {0, 0.5, 0}, "the voxel")

	obj_meshes, obj_problem := mesh_obj_triangles(test_obj_box(), false)
	defer destroy_model_layers(obj_meshes)
	testing.expect_value(t, obj_problem, "")
	testing.expect_value(t, len(obj_meshes[.Lit].positions), 36)
	expect_outward_winding(t, obj_meshes[.Lit], {0, 0.5, 0}, "the OBJ box")
}

@(test)
test_emissive_triangles_mesh_apart_without_the_shade :: proc(t: ^testing.T) {
	lit := test_obj_triangle({{0, 0, 0}, {0, 1, 0}, {0, 0, 1}})
	glow := lit
	glow.emissive = true
	glow.colour = {255, 140, 48}
	meshes, problem := mesh_obj_triangles(test_obj_triangles(lit, glow), false)
	defer destroy_model_layers(meshes)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(meshes[.Lit].positions), 3)
	testing.expect_value(t, len(meshes[.Emissive].positions), 3)
	for colour in meshes[.Emissive].colors {
		testing.expect_value(t, colour, [4]u8{255, 140, 48, 255})
	}
	// It faces +x.
	for colour in meshes[.Lit].colors {
		testing.expect_value(t, colour, shade_colour({100, 100, 100, 255}, model_normal_shade({1, 0, 0})))
	}
}

@(test)
test_an_obj_model_must_stay_on_its_footprint :: proc(t: ^testing.T) {
	machine := Machine{id = "test", model = "test", footprint = {2, 2, 2}}
	Footprint_Case :: struct {
		point:   [3]f32,
		problem: string,
	}
	cases := [?]Footprint_Case {
		{{1.05, 0, 0}, "x 1.050"},
		{{0, 0, -1.05}, "z -1.050"},
		{{0, -0.05, 0}, "y -0.050"},
		{{1.01, 0, 0}, ""},
		{{0, 3.5, 0}, ""},
	}
	for test_case in cases {
		model := test_obj_triangles(test_obj_triangle({test_case.point, {0, 0, 0}, {0, 0.5, 0.5}}))
		mesh, problem := mesh_obj_machine_model(model, machine)
		defer destroy_machine_model_mesh(mesh)
		if test_case.problem == "" {
			testing.expectf(t, problem == "", "%v: %q", test_case.point, problem)
		} else {
			testing.expectf(t, strings.contains(problem, test_case.problem), "%v: %q", test_case.point, problem)
		}
	}
	tall, problem := mesh_obj_machine_model(test_obj_triangles(test_obj_triangle({{0, 3.5, 0}, {0, 0, 0}, {0, 0.5, 0.5}})), machine)
	defer destroy_machine_model_mesh(tall)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, tall.top, 3.5)
}

@(test)
test_a_part_group_follows_the_motion :: proc(t: ^testing.T) {
	body := test_obj_triangle({{0, 0, 0}, {0, 1, 0}, {0, 0, 0.5}})
	part := test_obj_triangle({{0, 0, 0}, {0, 1, 0}, {0, 0, -0.5}}, part = true)
	machine := Machine{id = "test", model = "test", footprint = {2, 2, 2}, motion = {kind = .Pump, axis = 1, amplitude = -0.25, period_seconds = 1}}
	_, problem := mesh_obj_machine_model(test_obj_triangles(body), machine)
	testing.expectf(t, strings.contains(problem, "no group named part"), "%q", problem)
	for kind in ([2]Motion_Kind{.None, .Glow}) {
		still := machine
		still.motion = {kind = kind, period_seconds = 1}
		_, problem = mesh_obj_machine_model(test_obj_triangles(body, part), still)
		testing.expectf(t, strings.contains(problem, "moves none"), "%v: %q", kind, problem)
	}
	mesh: Machine_Model_Mesh
	mesh, problem = mesh_obj_machine_model(test_obj_triangles(body, part), machine)
	defer destroy_machine_model_mesh(mesh)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(mesh.part[.Lit].positions), 3)
	testing.expect_value(t, len(mesh.body[.Lit].positions), 3)
}

@(test)
test_an_obj_layer_past_the_vertex_limit_is_refused :: proc(t: ^testing.T) {
	model := test_obj_triangles()
	triangle := test_obj_triangle({{0, 0, 0}, {0, 1, 0}, {0, 0, 1}})
	for _ in 0 ..< 21845 {
		append(&model.triangles, triangle)
	}
	meshes, problem := mesh_obj_triangles(model, false)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(meshes[.Lit].positions), 65535)
	destroy_model_layers(meshes)

	append(&model.triangles, triangle)
	meshes, problem = mesh_obj_triangles(model, false)
	testing.expect_value(t, problem, "more than 65536 vertices")
	destroy_model_layers(meshes)
}

@(test)
test_a_degenerate_triangle_is_skipped :: proc(t: ^testing.T) {
	meshes, problem := mesh_obj_triangles(test_obj_triangles(test_obj_triangle({{0, 0, 0}, {1, 1, 1}, {2, 2, 2}})), false)
	defer destroy_model_layers(meshes)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(meshes[.Lit].positions) + len(meshes[.Emissive].positions), 0)
}

@(test)
test_an_obj_model_wins_over_a_voxel_model :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-obj-mesh-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(directory)
	models := platform.join_path(directory, model_obj.MODELS_DIRECTORY)
	testing.expect_value(t, os.make_directory(models), nil)
	obj := platform.join_path(models, "box.obj")
	testing.expect_value(t, os.write_entire_file(obj, TEST_OBJ_BOX), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(models, "box.mtl"), TEST_OBJ_MATERIALS), nil)
	testing.expect_value(t, os.write_entire_file(platform.join_path(models, "box.vox"), #load("../data/models/steel_furnace.vox")), nil)
	machine := Machine{id = "box", model = "box", footprint = {1, 1, 1}}

	mesh, problem := load_machine_model_mesh(directory, machine)
	testing.expect_value(t, problem, "")
	lit := mesh.body[.Lit]
	testing.expect_value(t, len(lit.positions), 36)
	testing.expect_value(t, len(lit.indices), 36)
	testing.expect(t, in_slice({128, 64, 255, 255}, lit.colors[:]), "the top face is the Kd colour")
	destroy_machine_model_mesh(mesh)

	testing.expect_value(t, os.remove(obj), nil)
	mesh, problem = load_machine_model_mesh(directory, machine)
	testing.expect_value(t, problem, "")
	lit = mesh.body[.Lit]
	testing.expect(t, len(lit.positions) > 0 && len(lit.indices) != len(lit.positions), "the voxel mesh shares quad corners")
	destroy_machine_model_mesh(mesh)
}

shipped_machine :: proc(machines: []Machine, id: string) -> (machine: Machine, found: bool) {
	for candidate in machines {
		if candidate.id == id {
			return candidate, true
		}
	}
	return {}, false
}

// The emissive layer's colours are all colour, its centroid is returned.
emissive_layer_centroid :: proc(t: ^testing.T, mesh: Model_Mesh, colour: [4]u8) -> (centroid: [3]f32) {
	for position in mesh.positions {
		centroid += position / f32(len(mesh.positions))
	}
	for vertex_colour in mesh.colors {
		testing.expect_value(t, vertex_colour, colour)
	}
	return centroid
}

// A shipped OBJ machine and whether its model glows (work item 0205).
Shipped_Obj_Machine :: struct {
	id:    string,
	glows: bool,
}

@(test)
test_the_shipped_obj_machines_load :: proc(t: ^testing.T) {
	shipped := [?]Shipped_Obj_Machine {
		{"stone_furnace", true},
		{"burner_mining_drill", true},
		{"wooden_chest", false},
		{"iron_chest", false},
		{"electric_mining_drill", true},
		{"small_pole", false},
		{"big_pole", false},
		{"boiler", true},
		{"steam_engine", true},
		{"offshore_pump", false},
		{"assembler_1", true},
		{"splitter", false},
		{"lamp", true},
		{"power_switch", true},
		{"schematic_crate", true},
		{"wood_gasifier", true},
		{"storage_tank", false},
		{"pump", false},
		{"lab", true},
		{"stone_cutting_table", false},
		{"stone_cutter", true},
	}
	machines := shipped_machines()
	defer delete(machines)
	for entry in shipped {
		id := entry.id
		machine, found := shipped_machine(machines, id)
		testing.expectf(t, found, "%s is shipped", id)
		testing.expectf(t, os.is_file(model_obj.model_file_path(test_data_directory(), machine.model)), "%s has an .obj", id)
		mesh, problem := load_machine_model_mesh(test_data_directory(), machine)
		defer destroy_machine_model_mesh(mesh)
		testing.expectf(t, problem == "", "%s: %q", id, problem)
		body_triangles := model_layers_triangle_count(mesh.body)
		testing.expectf(t, body_triangles >= 1 && body_triangles <= MODEL_BODY_TRIANGLES_MAXIMUM, "%s: %d body triangles", id, body_triangles)
		part_triangles := model_layers_triangle_count(mesh.part)
		if motion_has_part(machine.motion.kind) {
			testing.expectf(t, part_triangles >= 1 && part_triangles <= MODEL_PART_TRIANGLES_MAXIMUM, "%s: %d part triangles", id, part_triangles)
		} else {
			testing.expectf(t, part_triangles == 0, "%s: %d part triangles without a moving part", id, part_triangles)
		}
		glow_vertices := len(mesh.body[.Emissive].positions) + len(mesh.part[.Emissive].positions)
		testing.expectf(t, (glow_vertices > 0) == entry.glows, "%s: %d glowing vertices, glows %v", id, glow_vertices, entry.glows)
		if id == "stone_furnace" {
			// The glow faces the front (+x): the export axes.
			centroid := emissive_layer_centroid(t, mesh.body[.Emissive], {255, 140, 48, 255})
			testing.expectf(t, centroid.x > 0.5, "the furnace's glow centroid %v", centroid)
		}
		library, error := os.read_entire_file(platform.join_path(test_data_directory(), model_obj.MODELS_DIRECTORY, strings.concatenate({id, model_obj.MATERIAL_FILE_EXTENSION}, context.temp_allocator)), context.temp_allocator)
		testing.expect_value(t, error, nil)
		materials := strings.count(string(library), "newmtl ")
		testing.expectf(t, materials >= 1 && materials <= MODEL_MATERIAL_LIMIT, "%s: %d materials", id, materials)
		for suffix in ([2]string{"", "_part"}) {
			gone := strings.concatenate({id, suffix}, context.temp_allocator)
			testing.expectf(t, !os.is_file(model_vox.model_file_path(test_data_directory(), gone)), "%s.vox is gone", gone)
		}
	}
}
