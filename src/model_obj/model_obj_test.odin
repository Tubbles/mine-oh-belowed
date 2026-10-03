package model_obj

import "core:os"
import "core:strings"
import "core:testing"
import "../platform"

// OBJ and MTL reader tests (work item 0204): text written here. The file
// tests use a temporary directory they create and remove.

TEST_MATERIALS :: "newmtl grey\nKd 0.5 0.25 1\nKe 0 0 0\nnewmtl glow\nKd 1 0.549 0.188\nKe 1 0.5 0\n"

test_materials :: proc() -> [dynamic]Obj_Material {
	materials, problem := parse_material_library(TEST_MATERIALS, context.temp_allocator)
	assert(problem == "")
	return materials
}

@(test)
test_a_quad_is_fan_triangulated :: proc(t: ^testing.T) {
	text := "v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nusemtl grey\nf 1 2 3 4\n"
	model, problem := parse_obj_model(text, test_materials()[:])
	defer destroy_obj_model(model)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(model.triangles), 2)
	if len(model.triangles) != 2 {
		return
	}
	testing.expect_value(t, model.triangles[0].corners, [3][3]f32{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}})
	testing.expect_value(t, model.triangles[1].corners, [3][3]f32{{0, 0, 0}, {1, 1, 0}, {0, 1, 0}})
}

@(test)
test_every_corner_form_is_read :: proc(t: ^testing.T) {
	text := "v 0 0 0\nv 1 0 0\nv 0 0 1\nvt 0 0\nvn 0 2 0\nusemtl grey\nf 1 2 3\nf 1/1 2/1 3/1\nf 1//1 2//1 3//1\nf 1/1/1 2/1/1 3/1/1\n"
	model, problem := parse_obj_model(text, test_materials()[:])
	defer destroy_obj_model(model)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(model.triangles), 4)
	if len(model.triangles) != 4 {
		return
	}
	testing.expect_value(t, model.triangles[0].normal, [3]f32{})
	testing.expect_value(t, model.triangles[1].normal, [3]f32{})
	testing.expect_value(t, model.triangles[2].normal, [3]f32{0, 1, 0})
	testing.expect_value(t, model.triangles[3].normal, [3]f32{0, 1, 0})
}

@(test)
test_the_part_group_is_the_moving_part :: proc(t: ^testing.T) {
	faces := "f 1 2 3\n"
	text := strings.concatenate({"v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl grey\n", faces, "o body\n", faces, "o part\n", faces, "g\n", faces, "g part\n", faces, "g other\n", faces}, context.temp_allocator)
	model, problem := parse_obj_model(text, test_materials()[:])
	defer destroy_obj_model(model)
	testing.expect_value(t, problem, "")
	expected := [?]bool{false, false, true, false, true, false}
	testing.expect_value(t, len(model.triangles), len(expected))
	for triangle, index in model.triangles {
		testing.expectf(t, triangle.part == expected[index], "face %d: part %v", index, triangle.part)
	}
}

@(test)
test_emissive_materials_come_from_ke :: proc(t: ^testing.T) {
	text := "newmtl grey\nNs 250\nKa 1 1 1\nKd 0.5 0.25 1\nKs 0.5 0.5 0.5\nKe 0 0 0\nNi 1.45\nd 1\nillum 2\nnewmtl glow\nKd 1 0.549 0.188\nKe 1 0.5 0\n"
	materials, problem := parse_material_library(text)
	defer delete(materials)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(materials), 2)
	if len(materials) != 2 {
		return
	}
	testing.expect_value(t, materials[0].colour, [3]u8{128, 64, 255})
	testing.expect(t, !materials[0].emissive)
	testing.expect_value(t, materials[1].colour, [3]u8{255, 140, 48})
	testing.expect(t, materials[1].emissive)

	model, model_problem := parse_obj_model("v 0 0 0\nv 1 0 0\nv 0 1 0\nusemtl glow\nf 1 2 3\n", materials[:])
	defer destroy_obj_model(model)
	testing.expect_value(t, model_problem, "")
	testing.expect(t, len(model.triangles) == 1 && model.triangles[0].emissive && model.triangles[0].colour == {255, 140, 48})
}

Malformed_Text_Case :: struct {
	text:   string,
	prefix: string,
}

@(test)
test_malformed_obj_text_is_refused_naming_the_line :: proc(t: ^testing.T) {
	PREAMBLE :: "v 0 0 0\nv 1 0 0\nv 0 1 0\nvn 0 0 1\nusemtl grey\n"
	cases := [?]Malformed_Text_Case {
		{"v 0 0 0\nusemtl stone\n", "line 2:"},
		{PREAMBLE + "f 0 1 2\n", "line 6:"},
		{PREAMBLE + "f 1 2 9\n", "line 6:"},
		{PREAMBLE + "f -1 -2 -3\n", "line 6:"},
		{PREAMBLE + "f 1 2\n", "line 6:"},
		{"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n", "line 4:"},
		{"v 1 2\n", "line 1:"},
		{"v 0 0 0\nv 1 nan 2\n", "line 2:"},
		{PREAMBLE + "f 1//7 2//7 3//7\n", "line 6:"},
		{PREAMBLE + "f 1/1/1/1 2 3\n", "line 6:"},
		{PREAMBLE + "f 99999999999999999999 2 3\n", "line 6:"},
	}
	for test_case in cases {
		model, problem := parse_obj_model(test_case.text, test_materials()[:])
		destroy_obj_model(model)
		testing.expectf(t, strings.has_prefix(problem, test_case.prefix), "%q: %q", test_case.text, problem)
	}
}

@(test)
test_malformed_mtl_text_is_refused_naming_the_line :: proc(t: ^testing.T) {
	cases := [?]Malformed_Text_Case {
		{"Kd 1 0 0\n", "line 1:"},
		{"newmtl a\nKd 1.5 0 0\n", "line 2:"},
		{"newmtl a\nKd 1 0\n", "line 2:"},
		{"newmtl a\nKd 1 0 0\nKe -1 0 0\n", "line 3:"},
		{"newmtl a\nKd 1 0 0\nnewmtl a\n", "line 3:"},
		{"newmtl a\nKd 1 0 0\n# a comment\nnewmtl b\nKe 0 0 0\n", "line 4:"},
	}
	for test_case in cases {
		materials, problem := parse_material_library(test_case.text)
		delete(materials)
		testing.expectf(t, strings.has_prefix(problem, test_case.prefix), "%q: %q", test_case.text, problem)
	}
}

write_test_file :: proc(directory, name, text: string) -> string {
	path := platform.join_path(directory, name)
	assert(os.write_entire_file(path, text) == nil)
	return path
}

TEST_BOX_OBJ :: `mtllib box.mtl
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

@(test)
test_a_model_file_problem_names_the_file_and_the_line :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-obj-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(directory)

	missing := write_test_file(directory, "missing.obj", "# a model\nmtllib missing.mtl\n")
	_, problem := load_obj_model_file(missing)
	testing.expectf(t, strings.contains(problem, missing) && strings.contains(problem, "line 2:") && strings.contains(problem, "missing.mtl"), "%q", problem)

	broken_library := write_test_file(directory, "broken.mtl", "newmtl a\nKd 2 0 0\n")
	write_test_file(directory, "broken.obj", "mtllib broken.mtl\n")
	_, problem = load_obj_model_file(platform.join_path(directory, "broken.obj"))
	testing.expectf(t, strings.has_prefix(problem, strings.concatenate({"invalid model ", broken_library, ": line 2:"}, context.temp_allocator)), "%q", problem)

	outside := write_test_file(directory, "outside.obj", "mtllib ../outside.mtl\n")
	_, problem = load_obj_model_file(outside)
	testing.expectf(t, strings.contains(problem, outside) && strings.contains(problem, "line 1:"), "%q", problem)

	absent := platform.join_path(directory, "absent.obj")
	_, problem = load_obj_model_file(absent)
	testing.expectf(t, strings.contains(problem, absent), "%q", problem)
}

@(test)
test_a_model_file_loads_with_its_material_library :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-obj-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(directory)
	write_test_file(directory, "box.mtl", TEST_MATERIALS)
	model, problem := load_obj_model_file(write_test_file(directory, "box.obj", TEST_BOX_OBJ))
	defer destroy_obj_model(model)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(model.triangles), 12)
	for triangle in model.triangles {
		testing.expect_value(t, triangle.colour, [3]u8{128, 64, 255})
	}
	testing.expect(t, is_material_library_name("box_2.mtl") && !is_material_library_name(".mtl") && !is_material_library_name("Box.mtl") && !is_material_library_name("box.obj"))
}
