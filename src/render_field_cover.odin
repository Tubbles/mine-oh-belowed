package game

import "core:math"
import rl "shared:raylib"
import "shared:raylib/rlgl"
import "generation_seed"
import "platform"

// The ground cover's draw (work item 0311, doc/presentation.md, The field
// session). Each kind's stand in shape is made in code (blades, flowers,
// ferns, pebbles, crystals; cover_shape_vertices), a few triangles each,
// without textures or discard, and goes up once as a vertex buffer; each
// finest node's instances (world_field_cover.odin) go up per kind with
// its mesh (upload_field_cover, from apply_field_mesh) and are drawn per
// kind and node between the terrain and the water (draw_field_cover), the
// prefix of the rank sorted instances its nearest point can show
// (cover_draw_count), through data/shaders/cover.vs and cover.fs, lit and
// hazed as the terrain. Each instance thins out by its rank from the
// kind's near to its far distance and shrinks to nothing over the last
// fifth of its reach, so nothing pops.

COVER_VERTEX_SHADER_PATH :: "shaders/cover.vs"
COVER_FRAGMENT_SHADER_PATH :: "shaders/cover.fs"
// A kind keeps its shape in every world: its seed is this and its index.
COVER_SHAPE_SEED :: 0x0311
// Every kind's reach ends this far inside the first level of detail's
// distance, so no instance stands on a node that is no longer finest.
COVER_LEVEL_MARGIN_METRES :: 8

// A shape's vertex: a position in the unit box (x and z -0.5 to 0.5, y 0
// to 1, the base at the origin), a normal and a colour whose alpha is 255
// where the vertex takes the instance's colour and 0 where it keeps its
// own.
Cover_Shape_Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
	color:    [4]u8,
}

#assert(size_of(Cover_Shape_Vertex) == 28)

// The shape's attributes where raylib binds vertexPosition, vertexNormal
// and vertexColor.
COVER_SHAPE_LAYOUT :: [3]Instanced_Attribute {
	{location = 0, size = 3, type = rlgl.FLOAT, offset = 0},
	{location = 2, size = 3, type = rlgl.FLOAT, offset = 12},
	{location = 3, size = 4, type = rlgl.UNSIGNED_BYTE, normalized = true, offset = 24},
}

// A flower's stem keeps its own green.
COVER_STEM_COLOR :: [3]u8{80, 112, 56}

Cover_Uniform :: enum {
	Near,
	Far,
	Part_Vertices,
	Foliage,
	Color_Scale,
	Camera_Position,
}

COVER_UNIFORM_NAMES :: [Cover_Uniform]cstring {
	.Near            = "cover_near",
	.Far             = "cover_far",
	.Part_Vertices   = "part_vertices",
	.Foliage         = "foliage",
	.Color_Scale     = "color_scale",
	.Camera_Position = "camera_position",
}

Cover_Locations :: [Cover_Uniform]i32

// A kind's shape on the GPU and what its draw sets: the vertices a part
// holds (0 for a stone), whether it is foliage (both faces, the lean),
// the scale its instances' colours take (cover_color_scale) and its reach
// in metres (cover_reach).
Field_Cover_Kind_Draw :: struct {
	shape_buffer:  u32,
	vertex_count:  i32,
	part_vertices: i32,
	foliage:       bool,
	color_scale:   [3]f32,
	near:          f32,
	far:           f32,
}

// The cover's shader and kinds, on once the shader loaded; drawn_count
// is the instances the last draw sent.
Field_Cover_Renderer :: struct {
	on:                    bool,
	shader:                rl.Shader,
	locations:             Cover_Locations,
	open_sky_locations:    [Open_Sky_Uniform]i32,
	spot_locations:        [6]i32,
	point_light_locations: [2]i32,
	// The sun's shadow's uniforms (0328, use_sun_shadow_sampler).
	sun_shadow_locations:  [Sun_Shadow_Uniform]i32,
	kinds:                 [MAXIMUM_COVER_KINDS]Field_Cover_Kind_Draw,
	kind_count:            int,
	drawn_count:           int,
}

// A kind's instances in one node on the GPU: the vertex array over its
// shape and its instances (upload_instanced_buffer), their count and the
// rank counts of Field_Cover_Instances.
Field_Cover_Node_Draw :: struct {
	vertex_array:    u32,
	instance_buffer: u32,
	count:           i32,
	rank_counts:     [COVER_RANK_STEPS]i32,
}

// The vertices a part of the shape holds; 0 for the stones, which are one
// part.
cover_part_vertices :: proc(shape: Cover_Shape) -> int {
	switch shape {
	case .Blades:
		return 9
	case .Flower:
		return 18
	case .Fern:
		return 12
	case .Pebble, .Crystal:
		return 0
	}
	return 0
}

// A grey of 0 to 1 as a colour, the alpha whether it takes the
// instance's colour.
cover_grey :: proc(grey: f32, takes_instance: bool) -> [4]u8 {
	value := u8(math.round(clamp(grey, 0, 1) * 255))
	return {value, value, value, takes_instance ? 255 : 0}
}

// A triangle with its face normal (up for one with no area).
append_cover_triangle :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, points: [3][3]f32, colors: [3][4]u8) {
	edge_first, edge_second := points[1] - points[0], points[2] - points[0]
	normal := [3]f32{edge_first.y * edge_second.z - edge_first.z * edge_second.y, edge_first.z * edge_second.x - edge_first.x * edge_second.z, edge_first.x * edge_second.y - edge_first.y * edge_second.x}
	length := math.sqrt(normal.x * normal.x + normal.y * normal.y + normal.z * normal.z)
	normal = length > 1e-9 ? normal / length : {0, 1, 0}
	for corner in 0 ..< 3 {
		append(vertices, Cover_Shape_Vertex{points[corner], normal, colors[corner]})
	}
}

// The 16 bits at 16 times the slot of the hash of the seed and the value,
// 0 to under 1.
cover_shape_unit :: proc(seed: u64, value: int, slot: uint) -> f32 {
	return cover_unit(generation_seed.hash_combine(seed, u64(value)), slot)
}

// The outward direction of a part and its side, a quarter turn on.
cover_part_directions :: proc(angle: f32) -> (out, side: [3]f32) {
	return {math.cos(angle), 0, math.sin(angle)}, {-math.sin(angle), 0, math.cos(angle)}
}

// The shape's non indexed triangles in the unit box (cover_part_vertices
// a part, parts of them for foliage), from the seed.
cover_shape_vertices :: proc(shape: Cover_Shape, parts: int, seed: u64, allocator := context.allocator) -> [dynamic]Cover_Shape_Vertex {
	vertices := make([dynamic]Cover_Shape_Vertex, allocator)
	switch shape {
	case .Blades:
		for part in 0 ..< parts {
			append_cover_blade(&vertices, seed, part, parts)
		}
	case .Flower:
		for part in 0 ..< parts {
			append_cover_flower(&vertices, seed, part, parts)
		}
	case .Fern:
		for part in 0 ..< parts {
			append_cover_frond(&vertices, seed, part, parts)
		}
	case .Pebble:
		append_cover_pebble(&vertices, seed)
	case .Crystal:
		append_cover_crystal(&vertices, seed)
	}
	return vertices
}

// A blade: from a base up to 0.15 out, half width 0.05, through a bend at
// mid height of half width 0.035, to a tip up to 0.5 out at 0.65 to 1
// high; three triangles, grey 0.5 at the base, 0.75 at the bend, 1 at the
// tip, all taking the instance's colour.
append_cover_blade :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, seed: u64, part, parts: int) {
	angle := (f32(part) + cover_shape_unit(seed, part, 0)) / f32(parts) * math.TAU
	base_radius := 0.15 * cover_shape_unit(seed, part, 1)
	tip_radius := base_radius + (0.5 - base_radius) * (0.4 + 0.6 * cover_shape_unit(seed, part, 2))
	height := 0.65 + 0.35 * cover_shape_unit(seed, part, 3)
	out, side := cover_part_directions(angle)
	base := out * base_radius
	bend := out * (base_radius + (tip_radius - base_radius) * 0.35) + {0, height / 2, 0}
	tip := out * tip_radius + {0, height, 0}
	base_left, base_right := base - side * 0.05, base + side * 0.05
	bend_left, bend_right := bend - side * 0.035, bend + side * 0.035
	low, middle, high := cover_grey(0.5, true), cover_grey(0.75, true), cover_grey(1, true)
	append_cover_triangle(vertices, {base_left, base_right, bend_right}, {low, low, middle})
	append_cover_triangle(vertices, {base_left, bend_right, bend_left}, {low, middle, middle})
	append_cover_triangle(vertices, {bend_left, bend_right, tip}, {middle, middle, high})
}

// The tilt of a flower's head outwards.
COVER_FLOWER_TILT_DEGREES :: 20
COVER_FLOWER_HEAD_RADIUS :: 0.14

// A flower: a stem of one triangle (half width 0.02, its own green) up to
// 0.75 to under 1, the head's tilted rim staying inside the box, and a
// head of five triangles round its top (radius 0.14, tilted 20 degrees
// out; the rim 1, the centre 0.8).
append_cover_flower :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, seed: u64, part, parts: int) {
	angle := (f32(part) + cover_shape_unit(seed, part, 0)) / f32(parts) * math.TAU
	radius := 0.3 * cover_shape_unit(seed, part, 1)
	tilt := f32(COVER_FLOWER_TILT_DEGREES) * math.RAD_PER_DEG
	highest := 1 - COVER_FLOWER_HEAD_RADIUS * math.sin(tilt)
	height := 0.75 + (highest - 0.75) * cover_shape_unit(seed, part, 2)
	out, side := cover_part_directions(angle)
	base := out * radius
	top := base + {0, height, 0}
	stem := [4]u8{COVER_STEM_COLOR.r, COVER_STEM_COLOR.g, COVER_STEM_COLOR.b, 0}
	append_cover_triangle(vertices, {base - side * 0.02, base + side * 0.02, top}, {stem, stem, stem})
	facing := [3]f32{0, math.cos(tilt), 0} + out * math.sin(tilt)
	across := [3]f32{facing.y * side.z - facing.z * side.y, facing.z * side.x - facing.x * side.z, facing.x * side.y - facing.y * side.x}
	turn := cover_shape_unit(seed, part, 3) * math.TAU / 5
	centre, rim := cover_grey(0.8, true), cover_grey(1, true)
	for petal in 0 ..< 5 {
		first := turn + f32(petal) * math.TAU / 5
		second := first + math.TAU / 5
		first_point := top + (side * math.cos(first) + across * math.sin(first)) * COVER_FLOWER_HEAD_RADIUS
		second_point := top + (side * math.cos(second) + across * math.sin(second)) * COVER_FLOWER_HEAD_RADIUS
		append_cover_triangle(vertices, {top, first_point, second_point}, {centre, rim, rim})
	}
}

// A frond: four triangles along a midline rising to 0.85 at 0.35 out and
// drooping to 0.5 to 0.6 at 0.5 out, half widths 0, 0.09, 0.07, 0, grey
// 0.55 at the base to 1 to 0.85 at the tip; the frond's length 0.8 to 1
// of that.
append_cover_frond :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, seed: u64, part, parts: int) {
	angle := (f32(part) + 0.6 * cover_shape_unit(seed, part, 0)) / f32(parts) * math.TAU
	droop := 0.5 + 0.1 * cover_shape_unit(seed, part, 1)
	length := 0.8 + 0.2 * cover_shape_unit(seed, part, 2)
	out, side := cover_part_directions(angle)
	midline := [4][2]f32{{0, 0}, {0.15, 0.55}, {0.35, 0.85}, {0.5, droop}}
	half_widths := [4]f32{0, 0.09, 0.07, 0}
	greys := [4]f32{0.55, 0.8, 1, 0.85}
	left, right: [4][3]f32
	colors: [4][4]u8
	for point, index in midline {
		centre := (out * point[0] + {0, point[1], 0}) * length
		left[index], right[index] = centre - side * half_widths[index] * length, centre + side * half_widths[index] * length
		colors[index] = cover_grey(greys[index], true)
	}
	append_cover_triangle(vertices, {left[0], right[1], left[1]}, {colors[0], colors[1], colors[1]})
	append_cover_triangle(vertices, {left[1], right[1], right[2]}, {colors[1], colors[1], colors[2]})
	append_cover_triangle(vertices, {left[1], right[2], left[2]}, {colors[1], colors[2], colors[2]})
	append_cover_triangle(vertices, {left[2], right[2], right[3]}, {colors[2], colors[2], colors[3]})
}

// The icosahedron's corners (unnormalised) and faces.
COVER_GOLDEN :: 1.618034
COVER_ICOSAHEDRON_CORNERS :: [12][3]f32 {
	{-1, COVER_GOLDEN, 0}, {1, COVER_GOLDEN, 0}, {-1, -COVER_GOLDEN, 0}, {1, -COVER_GOLDEN, 0},
	{0, -1, COVER_GOLDEN}, {0, 1, COVER_GOLDEN}, {0, -1, -COVER_GOLDEN}, {0, 1, -COVER_GOLDEN},
	{COVER_GOLDEN, 0, -1}, {COVER_GOLDEN, 0, 1}, {-COVER_GOLDEN, 0, -1}, {-COVER_GOLDEN, 0, 1},
}
COVER_ICOSAHEDRON_FACES :: [20][3]int {
	{0, 11, 5}, {0, 5, 1}, {0, 1, 7}, {0, 7, 10}, {0, 10, 11},
	{1, 5, 9}, {5, 11, 4}, {11, 10, 2}, {10, 7, 6}, {7, 1, 8},
	{3, 9, 4}, {3, 4, 2}, {3, 2, 6}, {3, 6, 8}, {3, 8, 9},
	{4, 9, 5}, {2, 4, 11}, {6, 2, 10}, {8, 6, 7}, {9, 8, 1},
}

// A closed shape's faces turned outward from the centre, flat shaded,
// grey from bottom to top over y's 0 to 1.
append_cover_solid :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, corners: [][3]f32, faces: [][3]int, centre: [3]f32, bottom_grey, top_grey: f32) {
	for face in faces {
		points := [3][3]f32{corners[face[0]], corners[face[1]], corners[face[2]]}
		edge_first, edge_second := points[1] - points[0], points[2] - points[0]
		normal := [3]f32{edge_first.y * edge_second.z - edge_first.z * edge_second.y, edge_first.z * edge_second.x - edge_first.x * edge_second.z, edge_first.x * edge_second.y - edge_first.y * edge_second.x}
		outward := (points[0] + points[1] + points[2]) / 3 - centre
		if normal.x * outward.x + normal.y * outward.y + normal.z * outward.z < 0 {
			points[1], points[2] = points[2], points[1]
		}
		colors: [3][4]u8
		for point, index in points {
			colors[index] = cover_grey(bottom_grey + (top_grey - bottom_grey) * point.y, true)
		}
		append_cover_triangle(vertices, points, colors)
	}
}

// A pebble: an icosahedron, each corner moved by up to 22 percent along
// its radius by hash, x and z halved, y from 0 to 1; grey 0.72 at the
// bottom to 1 at the top.
append_cover_pebble :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, seed: u64) {
	corners := COVER_ICOSAHEDRON_CORNERS
	lowest, highest := max(f32), min(f32)
	for &corner, index in corners {
		length := math.sqrt(corner.x * corner.x + corner.y * corner.y + corner.z * corner.z)
		corner = corner / length * (1 + 0.22 * (2 * cover_shape_unit(seed, index, 0) - 1))
		lowest, highest = min(lowest, corner.y), max(highest, corner.y)
	}
	for &corner in corners {
		corner = {corner.x / 2, (corner.y - lowest) / (highest - lowest), corner.z / 2}
	}
	faces := COVER_ICOSAHEDRON_FACES
	append_cover_solid(vertices, corners[:], faces[:], {0, -lowest / (highest - lowest), 0}, 0.72, 1)
}

// A crystal: an octahedron with its tip at 1 and its girdle of four
// corners at 0.4 high and 0.45 out, each moved by up to 15 percent by
// hash; grey 0.75 at the bottom to 1 at the top.
append_cover_crystal :: proc(vertices: ^[dynamic]Cover_Shape_Vertex, seed: u64) {
	corners: [6][3]f32
	corners[0] = {0.05 * (2 * cover_shape_unit(seed, 0, 0) - 1), 1, 0.05 * (2 * cover_shape_unit(seed, 0, 1) - 1)}
	corners[5] = {0, 0, 0}
	for index in 1 ..= 4 {
		angle := (f32(index - 1) + 0.3 * (2 * cover_shape_unit(seed, index, 0) - 1)) * math.TAU / 4
		radius := 0.45 * (1 + 0.15 * (2 * cover_shape_unit(seed, index, 1) - 1))
		height := 0.4 * (1 + 0.15 * (2 * cover_shape_unit(seed, index, 2) - 1))
		corners[index] = {radius * math.cos(angle), height, radius * math.sin(angle)}
	}
	faces := [8][3]int{{0, 1, 2}, {0, 2, 3}, {0, 3, 4}, {0, 4, 1}, {5, 2, 1}, {5, 3, 2}, {5, 4, 3}, {5, 1, 4}}
	append_cover_solid(vertices, corners[:], faces[:], {0, 0.4, 0}, 0.75, 1)
}

// A kind's near and far in metres: both times the row's distance share,
// the far at most COVER_LEVEL_MARGIN_METRES inside the first level's
// distance and at least 0, the near at most the far.
cover_reach :: proc(kind: Planet_Cover_Kind, row: Field_Cover_Row, first_level_metres: f32) -> (near, far: f32) {
	share := f32(row.distance_percent) / 100
	far = clamp(f32(kind.far_metres) * share, 0, max(first_level_metres - COVER_LEVEL_MARGIN_METRES, 0))
	near = min(f32(kind.near_metres) * share, far)
	return near, far
}

// The scale a kind's instance colours take: the grass's the first
// colour over 128 times the grass tile's mean times 2, as field.fs scales
// the tint; the ground's likewise with the stone tile's mean; listed
// colours 1.
cover_color_scale :: proc(kind: Planet_Cover_Kind, grass_mean, stone_mean: [3]f32) -> [3]f32 {
	source, _ := parse_named_enum(cover_color_source_names, kind.color_from)
	first := len(kind.colors) > 0 ? field_color_float(kind.colors[0]) / 128 : [3]f32{1, 1, 1}
	switch source {
	case .Grass:
		return first * grass_mean * 2
	case .Ground:
		return first * stone_mean * 2
	case .Colors:
		return {1, 1, 1}
	}
	return {1, 1, 1}
}

// The instances of a node's kind to send at the distance: none at or past
// the far distance, all where every rank shows, else the prefix of the
// rank step the distance reaches (an instance of rank r reaches far less
// r times the span).
cover_draw_count :: proc(draw: Field_Cover_Node_Draw, near, far, distance: f32) -> i32 {
	if distance >= far {
		return 0
	}
	share: f32 = far > near ? (far - distance) / (far - near) : 1
	if share >= 1 {
		return draw.count
	}
	step := clamp(int(math.ceil(share * COVER_RANK_STEPS)) - 1, 0, COVER_RANK_STEPS - 1)
	return min(draw.rank_counts[step], draw.count)
}

// The renderer's cover: off without a climate, kinds or a density, or
// when its shaders do not load (one error line; the field draws without
// it); else each kind's shape up, its colour scale from the grass and the
// stone tiles' means and its reach. After init_field_renderer.
init_field_cover_renderer :: proc(renderer: ^Field_Renderer, data_directory: string, planet: Planet, row: Field_Cover_Row, first_level_metres: f32) {
	renderer.cover = {}
	if planet.climate == {} || len(planet.cover.kinds) == 0 || row.density_percent <= 0 {
		return
	}
	shader, ok := load_shader_pair(data_directory, COVER_VERTEX_SHADER_PATH, COVER_FRAGMENT_SHADER_PATH, "cover")
	if !ok {
		platform.log_printf("error: the cover shaders did not load, the field draws without its cover")
		return
	}
	cover := &renderer.cover
	cover.shader = shader
	names := COVER_UNIFORM_NAMES
	for name, uniform in names {
		cover.locations[uniform] = rl.GetShaderLocation(shader, name)
	}
	cover.open_sky_locations = open_sky_locations(shader)
	cover.spot_locations = spot_light_locations(shader)
	cover.point_light_locations = {rl.GetShaderLocation(shader, "point_light_positions"), rl.GetShaderLocation(shader, "point_light_colors")}
	cover.sun_shadow_locations = use_sun_shadow_sampler(shader)
	cover.kind_count = min(len(planet.cover.kinds), MAXIMUM_COVER_KINDS)
	stone_mean := renderer.material_colors[field_material_slot(.Stone)]
	for index in 0 ..< cover.kind_count {
		kind := planet.cover.kinds[index]
		shape, _ := parse_named_enum(cover_shape_names, kind.shape)
		vertices := cover_shape_vertices(shape, kind.parts, generation_seed.hash_combine(COVER_SHAPE_SEED, u64(index)), context.temp_allocator)
		draw := &cover.kinds[index]
		draw.shape_buffer = rlgl.LoadVertexBuffer(raw_data(vertices), i32(len(vertices) * size_of(Cover_Shape_Vertex)), false)
		draw.vertex_count = i32(len(vertices))
		draw.part_vertices = i32(cover_part_vertices(shape))
		draw.foliage = cover_shape_is_foliage(shape)
		draw.color_scale = cover_color_scale(kind, renderer.grass_color, stone_mean)
		draw.near, draw.far = cover_reach(kind, row, first_level_metres)
	}
	cover.on = true
}

destroy_field_cover_renderer :: proc(cover: ^Field_Cover_Renderer) {
	if cover.on {
		for kind in cover.kinds[:cover.kind_count] {
			rlgl.UnloadVertexBuffer(kind.shape_buffer)
		}
		rl.UnloadShader(cover.shader)
	}
	cover^ = {}
}

// A node's instances up per kind, with the rank counts; nothing when the
// cover is off. The data stays the caller's.
upload_field_cover :: proc(cover: Field_Cover_Renderer, data: Field_Cover_Data) -> (draws: [MAXIMUM_COVER_KINDS]Field_Cover_Node_Draw) {
	if !cover.on {
		return draws
	}
	layout := COVER_SHAPE_LAYOUT
	for index in 0 ..< cover.kind_count {
		instances := data.kinds[index].instances[:]
		if len(instances) == 0 {
			continue
		}
		draw := &draws[index]
		draw.vertex_array, draw.instance_buffer = upload_instanced_buffer(cover.kinds[index].shape_buffer, layout[:], size_of(Cover_Shape_Vertex), instances)
		draw.count = i32(len(instances))
		draw.rank_counts = data.kinds[index].rank_counts
	}
	return draws
}

unload_field_cover_node :: proc(draws: [MAXIMUM_COVER_KINDS]Field_Cover_Node_Draw) {
	for draw in draws {
		unload_instanced_buffer(draw.vertex_array, draw.instance_buffer)
	}
}

// The open sky's, the torchlight's and the sun's shadow's (0328) uniforms
// of the cover's shader (set_field_frame_lights).
set_field_cover_frame_lights :: proc(cover: Field_Cover_Renderer, lights: Field_Frame_Lights) {
	if !cover.on {
		return
	}
	set_open_sky_uniforms(cover.shader, cover.open_sky_locations, lights)
	set_spot_light_uniforms(cover.shader, cover.spot_locations, lights.spot)
	set_sun_shadow_uniforms(cover.shader, cover.sun_shadow_locations, lights.sun_shadow)
}

// The point lights' uniforms of the cover's shader
// (set_field_point_lights).
set_field_cover_point_lights :: proc(cover: Field_Cover_Renderer, positions, colors: ^[MAXIMUM_POINT_LIGHTS][4]f32) {
	if !cover.on {
		return
	}
	rl.SetShaderValueV(cover.shader, cover.point_light_locations[0], positions, .VEC4, MAXIMUM_POINT_LIGHTS)
	rl.SetShaderValueV(cover.shader, cover.point_light_locations[1], colors, .VEC4, MAXIMUM_POINT_LIGHTS)
}

set_cover_float :: proc(cover: Field_Cover_Renderer, uniform: Cover_Uniform, value: f32) {
	value := value
	rl.SetShaderValue(cover.shader, cover.locations[uniform], &value, .FLOAT)
}

// Inside BeginMode3D, after the terrain and before the water, over the
// terrain's visible nodes: the batch flushed, the shader with mvp as
// raylib's instanced draw sets it and the camera; kind by kind its
// uniforms, both faces for foliage and the back faces culled for the
// stones, then per node with instances of the kind the prefix its box's
// nearest point can show. The sun's shadow map (0328, 0 for none) is bound
// on its unit for the whole draw.
draw_field_cover :: proc(renderer: ^Field_Renderer, camera: rl.Camera3D, visible: []Field_Node_Render, shadow_texture: u32) {
	cover := &renderer.cover
	cover.drawn_count = 0
	if !cover.on || len(visible) == 0 {
		return
	}
	rlgl.DrawRenderBatchActive()
	shader := cover.shader
	rl.SetShaderValueMatrix(shader, shader.locs[int(rl.ShaderLocationIndex.MATRIX_MVP)], instanced_mvp())
	position := camera.position
	rl.SetShaderValue(shader, cover.locations[.Camera_Position], &position, .VEC3)
	bind_sun_shadow_texture(shader, shadow_texture)
	node_metres := f32(field_node_samples(0)) * f32(renderer.spacing_millimetres) / MILLIMETRES_PER_METRE
	for index in 0 ..< cover.kind_count {
		kind := cover.kinds[index]
		set_cover_float(cover^, .Near, kind.near)
		set_cover_float(cover^, .Far, kind.far)
		set_cover_float(cover^, .Part_Vertices, f32(kind.part_vertices))
		set_cover_float(cover^, .Foliage, kind.foliage ? 1 : 0)
		scale := kind.color_scale
		rl.SetShaderValue(shader, cover.locations[.Color_Scale], &scale, .VEC3)
		if kind.foliage {
			rlgl.DisableBackfaceCulling()
		} else {
			rlgl.EnableBackfaceCulling()
		}
		rlgl.EnableShader(shader.id)
		for render in visible {
			draw := render.cover[index]
			if draw.count == 0 {
				continue
			}
			count := cover_draw_count(draw, kind.near, kind.far, box_distance_metres(render.origin, render.origin + node_metres, camera.position))
			if count == 0 {
				continue
			}
			rlgl.EnableVertexArray(draw.vertex_array)
			rlgl.DrawVertexArrayInstanced(0, kind.vertex_count, count)
			cover.drawn_count += int(count)
		}
	}
	unbind_sun_shadow_texture(shadow_texture)
	rlgl.EnableBackfaceCulling()
	rlgl.DisableVertexArray()
	rlgl.DisableShader()
}
