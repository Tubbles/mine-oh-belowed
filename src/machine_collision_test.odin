package game

import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "platform"

// The collision file's reader (work item 0230, machine_collision.odin).

// The example of 0230's specification.
TEST_COLLISION_FILE :: `// The collision volumes of the model pod.
volumes = [
	{kind = "round", axis = "y", from = [0, 0, 0], to = [0, 2.2, 0], radius_from = 5, radius_to = 5, shell = 0.4, sector = [102.6, 77.4]}
	{kind = "round", axis = "y", from = [0, 2.2, 0], to = [0, 6.8, 0], radius_from = 5, radius_to = 2.4125, shell = 0.2875}
	{kind = "box", from = [1.12, 0, 1], to = [4.6, 2.75, 1.75]}
	{kind = "box", axis = "y", from = [-1, 0, -1], to = [1, 2, 1], shell = 0.1}
]
`

TEST_POD_FOOTPRINT :: [3]i32{12, 8, 12}

@(test)
test_a_collision_file_reads_into_volumes_in_model_units :: proc(t: ^testing.T) {
	file, error := parse_collision_file(transmute([]byte)string(TEST_COLLISION_FILE), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, collision_file_problem(file, "pod.collision.sjson", "pod", TEST_POD_FOOTPRINT), "")
	volumes := resolve_collision_volumes(file.volumes, context.temp_allocator)
	testing.expect_value(t, len(volumes), 7)
	first := volumes[0]
	testing.expect_value(t, first.kind, Collision_Volume_Kind.Round)
	testing.expect_value(t, first.axis, 1)
	testing.expect_value(t, first.from, [3]i64{0, 0, 0})
	testing.expect_value(t, first.to, [3]i64{0, 9011, 0})
	testing.expect_value(t, first.shell, 1638)
	angle := 102.6 * math.RAD_PER_DEG
	expected := [2]i64{i64(math.cos(angle) * UNIT_VECTOR_ONE), i64(math.sin(angle) * UNIT_VECTOR_ONE)}
	testing.expectf(t, first.sector.partial && abs(first.sector.start.x - expected.x) <= UNIT_VECTOR_ONE >> 12 && abs(first.sector.start.y - expected.y) <= UNIT_VECTOR_ONE >> 12, "the sector's start %v", first.sector.start)
	testing.expect(t, first.sector.wide)
	testing.expect_value(t, first.bound_minimum, [3]i64{-20480, 0, -20480})
	testing.expect_value(t, first.bound_maximum, [3]i64{20480, 9011, 20480})
	box := volumes[2]
	testing.expect_value(t, box.bound_minimum, [3]i64{4588, 0, 4096})
	testing.expect_value(t, box.bound_maximum, [3]i64{18842, 11264, 7168})
	shell := i64(410)
	walls := [4][2][3]i64 {
		{{-4096, 0, -4096}, {4096, 8192, -4096 + shell}},
		{{-4096, 0, 4096 - shell}, {4096, 8192, 4096}},
		{{-4096, 0, -4096}, {-4096 + shell, 8192, 4096}},
		{{4096 - shell, 0, -4096}, {4096, 8192, 4096}},
	}
	for wall, index in walls {
		volume := volumes[3 + index]
		testing.expectf(t, volume.kind == .Box && volume.from == wall[0] && volume.to == wall[1] && volume.shell == 0, "wall %d: %v to %v", index, volume.from, volume.to)
	}
}

// The problem of a file of one volume, or of the volumes given.
test_collision_problem :: proc(definitions: []Collision_Volume_Definition) -> string {
	return collision_file_problem({volumes = definitions}, "data/models/test.collision.sjson", "test", {4, 4, 4})
}

@(test)
test_the_collision_reader_refuses_malformed_volumes_naming_the_file :: proc(t: ^testing.T) {
	round := Collision_Volume_Definition{kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 1, 0}, radius_from = 1, radius_to = 1}
	malformed: [dynamic]Collision_Volume_Definition
	defer delete(malformed)
	append(&malformed, Collision_Volume_Definition{kind = "box", from = {0, 0, 0}, to = {2.1, 1, 1}})
	with_radius_from := round
	with_radius_from.radius_from = 0
	append(&malformed, with_radius_from)
	with_radius_to := round
	with_radius_to.radius_to = -1
	append(&malformed, with_radius_to)
	with_shell := round
	with_shell.shell = 1
	append(&malformed, with_shell)
	append(&malformed, Collision_Volume_Definition{kind = "sphere", from = {0, 0, 0}, to = {1, 1, 1}})
	append(&malformed, Collision_Volume_Definition{kind = "round", axis = "w", from = {0, 0, 0}, to = {0, 1, 0}, radius_from = 1, radius_to = 1})
	append(&malformed, Collision_Volume_Definition{kind = "box", from = {0, 0, 0}, to = {1, 1, 1}, sector = []f64{10, 20}})
	same := round
	same.sector = []f64{10, 10}
	append(&malformed, same)
	far := round
	far.sector = []f64{0, 800}
	append(&malformed, far)
	off_axis := round
	off_axis.to = {0.5, 1, 0}
	append(&malformed, off_axis)
	// NaN, which the SJSON reader accepts, fails every check closed.
	nan_shell := round
	nan_shell.shell = math.nan_f64()
	append(&malformed, nan_shell)
	nan_angle := round
	nan_angle.sector = []f64{math.nan_f64(), 90}
	append(&malformed, nan_angle)
	nan_box_shell := Collision_Volume_Definition{kind = "box", axis = "y", from = {0, 0, 0}, to = {1, 1, 1}, shell = math.nan_f64()}
	append(&malformed, nan_box_shell)
	nan_corner := Collision_Volume_Definition{kind = "box", from = {math.nan_f64(), 0, 0}, to = {1, 1, 1}}
	append(&malformed, nan_corner)
	for definition, index in malformed {
		// Each behind one valid volume, so the index is named as 1.
		problem := test_collision_problem([]Collision_Volume_Definition{round, definition})
		testing.expectf(t, strings.contains(problem, "data/models/test.collision.sjson") && strings.contains(problem, "volume 1 "), "case %d: %q", index, problem)
	}
	boxes := make([]Collision_Volume_Definition, 65, context.temp_allocator)
	for &box in boxes {
		box = {kind = "box", from = {0, 0, 0}, to = {1, 1, 1}}
	}
	problem := test_collision_problem(boxes)
	testing.expectf(t, strings.contains(problem, "data/models/test.collision.sjson") && strings.contains(problem, "65 volumes"), "%q", problem)
	shells := make([]Collision_Volume_Definition, 17, context.temp_allocator)
	for &box in shells {
		box = {kind = "box", axis = "y", from = {-1, 0, -1}, to = {1, 1, 1}, shell = 0.1}
	}
	problem = test_collision_problem(shells)
	testing.expectf(t, strings.contains(problem, "data/models/test.collision.sjson") && strings.contains(problem, "68 volumes"), "%q", problem)
	file, _ := parse_collision_file(transmute([]byte)string(TEST_COLLISION_FILE), context.temp_allocator)
	testing.expect_value(t, collision_file_problem(file, "pod.collision.sjson", "pod", TEST_POD_FOOTPRINT), "")
}

@(test)
test_a_machine_without_a_collision_file_has_no_volumes :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-collision-test-*", context.temp_allocator)
	assert(error == nil)
	defer os.remove_all(directory)
	models := platform.join_path(directory, "models")
	testing.expect_value(t, os.make_directory_all(models), nil)
	volumes, problem := load_machine_collision(directory, Machine{id = "bare", footprint = TEST_POD_FOOTPRINT}, context.temp_allocator)
	testing.expect(t, volumes == nil && problem == "")
	machine := Machine{id = "pod", model = "pod", footprint = TEST_POD_FOOTPRINT}
	volumes, problem = load_machine_collision(directory, machine, context.temp_allocator)
	testing.expect(t, volumes == nil && problem == "")
	path := platform.join_path(models, "pod.collision.sjson")
	testing.expect_value(t, os.write_entire_file(path, transmute([]byte)string(TEST_COLLISION_FILE)), nil)
	volumes, problem = load_machine_collision(directory, machine, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(volumes), 7)
	testing.expect_value(t, os.write_entire_file(path, transmute([]byte)string("volumes = [")), nil)
	volumes, problem = load_machine_collision(directory, machine, context.temp_allocator)
	testing.expectf(t, volumes == nil && strings.contains(problem, path) && strings.contains(problem, "cannot parse"), "%q", problem)
}
