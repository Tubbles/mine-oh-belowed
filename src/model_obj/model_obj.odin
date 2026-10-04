package model_obj

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "../platform"

// Wavefront OBJ machine models with an MTL material file (work item
// 0204), no raylib and no game types here: meshing is in
// model_triangle_mesh.odin and the upload in render_models.odin. A
// machine names its model by id in data/machines.sjson; the file is
// data/models/<id>.obj, its materials in the .mtl its mtllib line names.
//
// The OBJ subset: v (a position, numbers after the third ignored), vn (a
// normal), vt (ignored, there are no textures), f with three or more
// corners in the forms v, v/vt, v//vn and v/vt/vn (positive 1-based
// indices of what came before; fan triangulated), o and g (a group: the
// faces after the group named part are the moving part, every other face
// is the body), usemtl, mtllib (one plain file name beside the .obj) and
// #. The MTL subset: newmtl, Kd (the colour, 0 to 1 per channel, read as
// display bytes without gamma) and Ke (any channel above 0 makes the
// material emissive). Every other keyword of either file is ignored. A
// # after content is not a comment.
//
// The frame is the game's: one unit is one cell of the machine's
// unrotated footprint, x and z centred on it, y from its bottom, +x the
// front, y up, right handed. Corners keep the file's order.

MODELS_DIRECTORY :: "models"
MODEL_FILE_EXTENSION :: ".obj"
MATERIAL_FILE_EXTENSION :: ".mtl"
PART_GROUP_NAME :: "part"
// More digits than this cannot be in range, and strconv would wrap them.
MAXIMUM_INDEX_DIGITS :: 9

Obj_Material :: struct {
	name:     string, // a slice of the material file's text
	colour:   [3]u8, // Kd
	emissive: bool, // any Ke channel above 0
}

Obj_Triangle :: struct {
	corners:  [3][3]f32, // file order, the file's frame (cells)
	normal:   [3]f32, // normalised sum of the face's vn; zero when a corner has none or the sum is zero
	colour:   [3]u8,
	emissive: bool,
	part:     bool, // in the group named part
}

Obj_Model :: struct {
	triangles: [dynamic]Obj_Triangle,
}

// Indices from 1 into the positions and normals; normal 0 for none.
Obj_Corner :: struct {
	position: int,
	normal:   int,
}

// What the OBJ parse has read so far; the lists are in the temp allocator.
Obj_Parse_State :: struct {
	positions: [dynamic][3]f32,
	normals:   [dynamic][3]f32,
	material:  int, // -1 before any usemtl
	part:      bool,
}

// What the MTL parse has read so far.
Mtl_Parse_State :: struct {
	materials:    [dynamic]Obj_Material,
	// Parallel to materials: the newmtl line and whether Kd was read.
	newmtl_lines: [dynamic]int,
	colour_read:  [dynamic]bool,
}

// In the temp allocator.
model_file_path :: proc(data_directory, id: string) -> string {
	return platform.join_path(data_directory, MODELS_DIRECTORY, fmt.tprintf("%s%s", id, MODEL_FILE_EXTENSION))
}

// A model's collision volumes (work item 0230), read by the game package
// (machine_collision.odin), not here. In the temp allocator.
COLLISION_FILE_SUFFIX :: ".collision.sjson"

collision_file_path :: proc(data_directory, id: string) -> string {
	return platform.join_path(data_directory, MODELS_DIRECTORY, fmt.tprintf("%s%s", id, COLLISION_FILE_SUFFIX))
}

// A non-empty stem of a to z, 0 to 9 and _, then .mtl: no directory.
is_material_library_name :: proc(name: string) -> bool {
	if !strings.has_suffix(name, MATERIAL_FILE_EXTENSION) || len(name) == len(MATERIAL_FILE_EXTENSION) {
		return false
	}
	for character in name[:len(name) - len(MATERIAL_FILE_EXTENSION)] {
		if !(character >= 'a' && character <= 'z' || character >= '0' && character <= '9' || character == '_') {
			return false
		}
	}
	return true
}

// The lines of a file, line i + 1 at index i. In the temp allocator.
split_text_lines :: proc(text: string) -> []string {
	return strings.split(text, "\n", context.temp_allocator)
}

// The fields of a line without its trailing \r and blanks, nil for an
// empty line or a comment. In the temp allocator.
line_fields :: proc(line: string) -> []string {
	fields := strings.fields(strings.trim_space(line), context.temp_allocator)
	if len(fields) == 0 || strings.has_prefix(fields[0], "#") {
		return nil
	}
	return fields
}

// The single mtllib line's name, "" when there is none.
material_library_name :: proc(text: string) -> (name: string, line: int, problem: string) {
	for line_text, index in split_text_lines(text) {
		fields := line_fields(line_text)
		if len(fields) == 0 || fields[0] != "mtllib" {
			continue
		}
		if name != "" {
			return "", index + 1, fmt.tprintf("line %d: a second mtllib", index + 1)
		}
		if len(fields) != 2 || !is_material_library_name(fields[1]) {
			return "", index + 1, fmt.tprintf("line %d: mtllib must name one plain .mtl file (a to z, 0 to 9, _)", index + 1)
		}
		name, line = fields[1], index + 1
	}
	return name, line, ""
}

// Three finite numbers from the fields; more are allowed when extra is.
@(private)
parse_three_floats :: proc(fields: []string, extra: bool) -> (values: [3]f32, ok: bool) {
	if len(fields) < 3 || (!extra && len(fields) != 3) {
		return {}, false
	}
	for index in 0 ..< 3 {
		value, parsed := strconv.parse_f32(fields[index])
		if !parsed || math.is_nan(value) || math.is_inf(value) {
			return {}, false
		}
		values[index] = value
	}
	return values, true
}

// A 1-based index within 1..count; plain digits only.
@(private)
parse_index :: proc(text: string, count: int) -> (index: int, ok: bool) {
	if text == "" || len(text) > MAXIMUM_INDEX_DIGITS {
		return 0, false
	}
	for character in text {
		if character < '0' || character > '9' {
			return 0, false
		}
	}
	index, ok = strconv.parse_int(text, 10)
	return index, ok && index >= 1 && index <= count
}

// v, v/vt, v//vn or v/vt/vn; the vt slot is ignored.
@(private)
parse_corner :: proc(token: string, state: Obj_Parse_State) -> (corner: Obj_Corner, problem: string) {
	parts := strings.split(token, "/", context.temp_allocator)
	if len(parts) > 3 {
		return {}, fmt.tprintf("corner %q has more than three parts", token)
	}
	ok: bool
	if corner.position, ok = parse_index(parts[0], len(state.positions)); !ok {
		return {}, fmt.tprintf("corner %q: the position is not an index of 1 to %d", token, len(state.positions))
	}
	if len(parts) == 3 && parts[2] != "" {
		if corner.normal, ok = parse_index(parts[2], len(state.normals)); !ok {
			return {}, fmt.tprintf("corner %q: the normal is not an index of 1 to %d", token, len(state.normals))
		}
	}
	return corner, ""
}

// The normalised sum of the corners' normals, zero when one has none.
@(private)
face_normal :: proc(corners: []Obj_Corner, normals: [][3]f32) -> [3]f32 {
	sum: [3]f32
	for corner in corners {
		if corner.normal == 0 {
			return {}
		}
		sum += normals[corner.normal - 1]
	}
	length := math.sqrt(sum.x * sum.x + sum.y * sum.y + sum.z * sum.z)
	return length > 0 ? sum / length : {}
}

@(private)
find_material :: proc(materials: []Obj_Material, name: string) -> int {
	for material, index in materials {
		if material.name == name {
			return index
		}
	}
	return -1
}

// A face fan triangulated into model, corners 0, i, i + 1.
@(private)
parse_face :: proc(model: ^Obj_Model, fields: []string, state: Obj_Parse_State, materials: []Obj_Material) -> string {
	if len(fields) < 3 {
		return "a face needs three corners or more"
	}
	if state.material < 0 {
		return "a face before any usemtl"
	}
	corners := make([]Obj_Corner, len(fields), context.temp_allocator)
	for token, index in fields {
		problem: string
		if corners[index], problem = parse_corner(token, state); problem != "" {
			return problem
		}
	}
	material := materials[state.material]
	normal := face_normal(corners, state.normals[:])
	for index in 1 ..< len(corners) - 1 {
		triangle := Obj_Triangle{normal = normal, colour = material.colour, emissive = material.emissive, part = state.part}
		fan := [3]Obj_Corner{corners[0], corners[index], corners[index + 1]}
		for corner, slot in fan {
			triangle.corners[slot] = state.positions[corner.position - 1]
		}
		append(&model.triangles, triangle)
	}
	return ""
}

// One OBJ line's keyword and its fields after it.
@(private)
parse_obj_line :: proc(model: ^Obj_Model, state: ^Obj_Parse_State, keyword: string, fields: []string, materials: []Obj_Material) -> string {
	switch keyword {
	case "v", "vn":
		values, ok := parse_three_floats(fields, keyword == "v")
		if !ok {
			return fmt.tprintf("%s needs three finite numbers", keyword)
		}
		append(keyword == "v" ? &state.positions : &state.normals, values)
	case "o", "g":
		state.part = len(fields) > 0 && fields[0] == PART_GROUP_NAME
	case "usemtl":
		name := len(fields) > 0 ? fields[0] : ""
		if state.material = find_material(materials, name); state.material < 0 {
			return fmt.tprintf("unknown material %q", name)
		}
	case "f":
		return parse_face(model, fields, state^, materials)
	}
	return ""
}

// The OBJ subset. triangles is in allocator, also on a problem.
parse_obj_model :: proc(text: string, materials: []Obj_Material, allocator := context.allocator) -> (model: Obj_Model, problem: string) {
	model.triangles = make([dynamic]Obj_Triangle, allocator)
	state := Obj_Parse_State {
		positions = make([dynamic][3]f32, context.temp_allocator),
		normals   = make([dynamic][3]f32, context.temp_allocator),
		material  = -1,
	}
	for line_text, index in split_text_lines(text) {
		fields := line_fields(line_text)
		if len(fields) == 0 {
			continue
		}
		if problem = parse_obj_line(&model, &state, fields[0], fields[1:], materials); problem != "" {
			return model, fmt.tprintf("line %d: %s", index + 1, problem)
		}
	}
	return model, ""
}

// Kd in 0 to 1 per channel, to display bytes.
@(private)
parse_material_colour :: proc(fields: []string) -> (colour: [3]u8, ok: bool) {
	values := parse_three_floats(fields, false) or_return
	for value, index in values {
		if value < 0 || value > 1 {
			return {}, false
		}
		colour[index] = u8(value * 255 + 0.5)
	}
	return colour, true
}

// Ke: emissive when any channel is above 0; negative is refused.
@(private)
parse_material_emission :: proc(fields: []string) -> (emissive: bool, ok: bool) {
	values := parse_three_floats(fields, false) or_return
	for value in values {
		if value < 0 {
			return false, false
		}
		emissive ||= value > 0
	}
	return emissive, true
}

// One MTL line's keyword and its fields after it.
@(private)
parse_mtl_line :: proc(state: ^Mtl_Parse_State, keyword: string, fields: []string, line: int) -> string {
	if keyword == "newmtl" {
		if len(fields) == 0 {
			return "newmtl without a name"
		}
		if find_material(state.materials[:], fields[0]) >= 0 {
			return fmt.tprintf("material %q is defined twice", fields[0])
		}
		append(&state.materials, Obj_Material{name = fields[0]})
		append(&state.newmtl_lines, line)
		append(&state.colour_read, false)
		return ""
	}
	if keyword != "Kd" && keyword != "Ke" {
		return ""
	}
	if len(state.materials) == 0 {
		return fmt.tprintf("%s before any newmtl", keyword)
	}
	material := &state.materials[len(state.materials) - 1]
	ok: bool
	if keyword == "Kd" {
		material.colour, ok = parse_material_colour(fields)
		state.colour_read[len(state.materials) - 1] = true
		return ok ? "" : "Kd needs three numbers of 0 to 1"
	}
	material.emissive, ok = parse_material_emission(fields)
	return ok ? "" : "Ke needs three finite numbers of 0 or more"
}

// The MTL subset. materials is in allocator, also on a problem.
parse_material_library :: proc(text: string, allocator := context.allocator) -> (materials: [dynamic]Obj_Material, problem: string) {
	state := Mtl_Parse_State {
		materials    = make([dynamic]Obj_Material, allocator),
		newmtl_lines = make([dynamic]int, context.temp_allocator),
		colour_read  = make([dynamic]bool, context.temp_allocator),
	}
	for line_text, index in split_text_lines(text) {
		fields := line_fields(line_text)
		if len(fields) == 0 {
			continue
		}
		if problem = parse_mtl_line(&state, fields[0], fields[1:], index + 1); problem != "" {
			return state.materials, fmt.tprintf("line %d: %s", index + 1, problem)
		}
	}
	for read, index in state.colour_read {
		if !read {
			return state.materials, fmt.tprintf("line %d: material %q has no Kd", state.newmtl_lines[index], state.materials[index].name)
		}
	}
	return state.materials, ""
}

// The materials of the library the OBJ text names, beside path; empty
// without an mtllib. The problem is the whole message. In the temp
// allocator.
@(private)
load_material_library :: proc(path, text: string) -> (materials: [dynamic]Obj_Material, problem: string) {
	name, line, name_problem := material_library_name(text)
	if name_problem != "" {
		return nil, fmt.tprintf("invalid model %s: %s", path, name_problem)
	}
	if name == "" {
		return make([dynamic]Obj_Material, context.temp_allocator), ""
	}
	library_path := platform.join_path(os.dir(path), name)
	library, read_error := os.read_entire_file(library_path, context.temp_allocator)
	if read_error != nil {
		return nil, fmt.tprintf("invalid model %s: line %d: cannot read %s: %v", path, line, library_path, read_error)
	}
	if materials, problem = parse_material_library(string(library), context.temp_allocator); problem != "" {
		return nil, fmt.tprintf("invalid model %s: %s", library_path, problem)
	}
	return materials, ""
}

// The problem names the file and the line. Nothing is kept on a problem.
load_obj_model_file :: proc(path: string, allocator := context.allocator) -> (model: Obj_Model, problem: string) {
	text, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		return {}, fmt.tprintf("cannot read %s: %v", path, read_error)
	}
	materials: [dynamic]Obj_Material
	if materials, problem = load_material_library(path, string(text)); problem != "" {
		return {}, problem
	}
	if model, problem = parse_obj_model(string(text), materials[:], allocator); problem != "" {
		destroy_obj_model(model)
		return {}, fmt.tprintf("invalid model %s: %s", path, problem)
	}
	return model, ""
}

destroy_obj_model :: proc(model: Obj_Model) {
	delete(model.triangles)
}
