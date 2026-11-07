package game

import "core:math"
import "core:slice"
import "generation_seed"

// The ground cover (work item 0311, doc/presentation.md, The field
// session): tufts, flowers, ferns, pebbles, boulders and ore specks,
// placed by each finest level mesh job on the triangles it just made
// (mesh_field_grid), so every instance sits on the drawn mesh, arrives
// with it under the node's one revision and leaves with a remesh: dug
// ground (the look's offset from the generated surface), wet ground,
// carved air without the sky and a frame's occupied cells carry none.
// A triangle's instances come from a hash of its grid edge in global
// sample coordinates and its half, so the same ground gives the same
// cover on every remesh and nothing repeats on a lattice; each kind's
// density reads the look's climate, the slope, the surfaces field.fs
// shows, a boundary term and a patch noise of its own (Planet_Cover).
// Presentation only: nothing reaches the simulation, the hash or the
// save, so floats are fine here.

// A vertex this far from the generated surface thins the cover, one
// twice as far carries none.
COVER_CUT_MILLIMETRES :: 200
// Below this sky light (of FIELD_LIGHT_FULL) a vertex is carved air under
// a roof or a cave, and its triangles carry none.
COVER_LEAST_SKY_LIGHT :: 128
// The rank's steps the draw's prefix counts are kept at.
COVER_RANK_STEPS :: 16
// Salts on generation.ground_look_seed, whose 0 to 2 the look uses: the
// triangles' hash, and the first kind's patch noise (one more a kind).
COVER_TRIANGLE_SEED :: 31
COVER_PATCH_SEED :: 32
// The most a foliage instance leans from the up.
COVER_TILT_DEGREES :: 10
// The tallest instance's reach: a node's box is widened by it for the
// frames that clear its cover.
COVER_FRAME_MARGIN_METRES :: 4
// field.fs's steepness (1 less the cosine to the local up) where rock
// starts and is full and where sand gives way, compared by a test.
GROUND_ROCK_START_STEEPNESS :: 0.234
GROUND_ROCK_FULL_STEEPNESS :: 0.357
GROUND_SAND_START_STEEPNESS :: 0.134
GROUND_SAND_END_STEEPNESS :: 0.234

// The surfaces a kind grows on, as Planet_Cover_Surfaces lists them.
Cover_Surface :: enum u8 {
	Grass,
	Sand,
	Snow,
	Rock,
	Stone,
	Hematite,
	Chalcopyrite,
	Coal,
}

// A kind as the placement reads it: the rate per square metre, the
// ranges (celsius, moisture percent, slope degrees) and their fades, the
// surfaces' shares 0 to 1, the boundary share, the patch noise's
// wavelength in position units (0 none) with its threshold and edge on
// the noise's -1 to 1, the width and height in metres, the sink's share
// of the height, the colour's source and colours, and whether it is
// foliage.
Field_Cover_Kind :: struct {
	rate:             f32,
	temperature:      [2]f32,
	moisture:         [2]f32,
	slope:            [2]f32,
	fades:            [3]f32,
	surfaces:         [Cover_Surface]f32,
	boundary:         f32,
	patch_wavelength: i64,
	patch_threshold:  f32,
	patch_edge:       f32,
	width:            [2]f32,
	height:           [2]f32,
	sink:             f32,
	color_from:       Cover_Color_Source,
	colors:           [MAXIMUM_COVER_COLORS][3]u8,
	color_count:      int,
	foliage:          bool,
}

// What the workers place with: on with a climate, kinds and a density;
// density is the row's share of the ranks kept, limit the most instances
// of a kind in a node, seed the triangles' hash.
Field_Cover_Table :: struct {
	on:         bool,
	kinds:      [MAXIMUM_COVER_KINDS]Field_Cover_Kind,
	kind_count: int,
	density:    f32,
	limit:      int,
	seed:       u64,
}

// A kind's instances in a node, sorted by rank (the bottom row's first
// element), and per rank step the count of those below its top.
Field_Cover_Instances :: struct {
	instances:   [dynamic]matrix[4, 4]f32,
	rank_counts: [COVER_RANK_STEPS]i32,
}

// A node's cover, a list per kind.
Field_Cover_Data :: struct {
	kinds: [MAXIMUM_COVER_KINDS]Field_Cover_Instances,
}

destroy_field_cover_data :: proc(data: Field_Cover_Data) {
	for kind in data.kinds {
		delete(kind.instances)
	}
}

// One triangle's ground: the corners' mean climate (moisture in
// percent), the slope in degrees, the natural share 0 to 1 (cut) and the
// surfaces' shares.
Cover_Ground :: struct {
	celsius:       f32,
	moisture:      f32,
	slope_degrees: f32,
	cut:           f32,
	shares:        [Cover_Surface]f32,
}

// A frame's occupied cells sorted by (z, y, x) and the box in metres
// round their corners.
Cover_Frame :: struct {
	frame:            Frame,
	cells:            [dynamic]World_Coordinate,
	minimum, maximum: [3]f64,
}

// Each frame's cells; the caller deletes the list.
destroy_cover_frames :: proc(frames: []Cover_Frame) {
	for frame in frames {
		delete(frame.cells)
	}
}

// The table of the planet's kinds and the build target's row; off
// without a climate, kinds or a density.
make_field_cover_table :: proc(generation: Planet_Generation, planet: Planet, row: Field_Cover_Row) -> Field_Cover_Table {
	if planet.climate == {} || len(planet.cover.kinds) == 0 || row.density_percent <= 0 {
		return {}
	}
	table := Field_Cover_Table {
		on         = true,
		kind_count = min(len(planet.cover.kinds), MAXIMUM_COVER_KINDS),
		density    = f32(row.density_percent) / 100,
		limit      = row.node_limit,
		seed       = generation_seed.hash_combine(generation.ground_look_seed, COVER_TRIANGLE_SEED),
	}
	for index in 0 ..< table.kind_count {
		table.kinds[index] = field_cover_kind(planet.cover.kinds[index])
	}
	return table
}

// A data kind (checked by cover_problem) as the placement reads it.
field_cover_kind :: proc(kind: Planet_Cover_Kind) -> Field_Cover_Kind {
	shape, _ := parse_named_enum(cover_shape_names, kind.shape)
	source, _ := parse_named_enum(cover_color_source_names, kind.color_from)
	surfaces := kind.surfaces
	result := Field_Cover_Kind {
		rate             = f32(kind.per_hundred_square_metres) / 100,
		temperature      = {f32(kind.temperature_celsius[0]), f32(kind.temperature_celsius[1])},
		moisture         = {f32(kind.moisture_percent[0]), f32(kind.moisture_percent[1])},
		slope            = {f32(kind.slope_degrees[0]), f32(kind.slope_degrees[1])},
		fades            = {f32(kind.temperature_fade_celsius), f32(kind.moisture_fade_percent), f32(kind.slope_fade_degrees)},
		surfaces         = {.Grass = f32(surfaces.grass) / 100, .Sand = f32(surfaces.sand) / 100, .Snow = f32(surfaces.snow) / 100, .Rock = f32(surfaces.rock) / 100, .Stone = f32(surfaces.stone) / 100, .Hematite = f32(surfaces.hematite) / 100, .Chalcopyrite = f32(surfaces.chalcopyrite) / 100, .Coal = f32(surfaces.coal) / 100},
		boundary         = f32(kind.boundary_percent) / 100,
		patch_wavelength = metres_to_position_units(i64(kind.patch_wavelength_metres)),
		patch_threshold  = f32(kind.patch_threshold_percent) / 100,
		patch_edge       = f32(kind.patch_edge_percent) / 100,
		width            = {f32(kind.width_millimetres[0]), f32(kind.width_millimetres[1])} / MILLIMETRES_PER_METRE,
		height           = {f32(kind.height_millimetres[0]), f32(kind.height_millimetres[1])} / MILLIMETRES_PER_METRE,
		sink             = f32(kind.sink_percent) / 100,
		color_from       = source,
		color_count      = min(len(kind.colors), MAXIMUM_COVER_COLORS),
		foliage          = cover_shape_is_foliage(shape),
	}
	for index in 0 ..< result.color_count {
		color := kind.colors[index]
		result.colors[index] = {u8(clamp(color.r, 0, 255)), u8(clamp(color.g, 0, 255)), u8(clamp(color.b, 0, 255))}
	}
	return result
}

// 1 inside the range, falling linearly to 0 over the fade outside it.
cover_tent :: proc(value: f32, range: [2]f32, fade: f32) -> f32 {
	switch {
	case value < range[0]:
		return max(0, 1 - (range[0] - value) / fade)
	case value > range[1]:
		return max(0, 1 - (value - range[1]) / fade)
	}
	return 1
}

// The surfaces' shares of a triangle's ground: the material weights
// normalised, the topsoil split as field.fs splits it with a climate
// (rock on the steep, then snow, then sand on the gentle, the rest
// grass), stone the stone, deep stone and bedrock, the ores their own.
cover_ground_shares :: proc(weights: [FIELD_TEXTURED_MATERIAL_COUNT]f32, snow, sand, steepness: f32) -> (shares: [Cover_Surface]f32) {
	total: f32 = 0
	for weight in weights {
		total += weight
	}
	if total <= 0 {
		return {}
	}
	normalised := weights / total
	topsoil := normalised[field_material_slot(.Topsoil)]
	rock := topsoil * math.smoothstep(f32(GROUND_ROCK_START_STEEPNESS), f32(GROUND_ROCK_FULL_STEEPNESS), steepness)
	shares[.Rock] = rock
	shares[.Snow] = (topsoil - rock) * snow
	shares[.Sand] = (topsoil - rock - shares[.Snow]) * sand * (1 - math.smoothstep(f32(GROUND_SAND_START_STEEPNESS), f32(GROUND_SAND_END_STEEPNESS), steepness))
	shares[.Grass] = topsoil - rock - shares[.Snow] - shares[.Sand]
	shares[.Stone] = normalised[field_material_slot(.Stone)] + normalised[field_material_slot(.Deep_Stone)] + normalised[field_material_slot(.Bedrock)]
	shares[.Hematite] = normalised[field_material_slot(.Hematite_Ore)]
	shares[.Chalcopyrite] = normalised[field_material_slot(.Chalcopyrite_Ore)]
	shares[.Coal] = normalised[field_material_slot(.Coal_Ore)]
	return shares
}

// A kind's instances per square metre on the ground at the patch share:
// the rate times the climate's and the slope's tents, the shares the
// kind grows on (on), the boundary term, the patch and the cut. The
// boundary term reads the same weighed share (own, at most 1), so it is
// largest where the kind's surfaces meet others half and half.
cover_kind_density :: proc(kind: Field_Cover_Kind, ground: Cover_Ground, patch: f32) -> f32 {
	climate := cover_tent(ground.celsius, kind.temperature, kind.fades[0]) * cover_tent(ground.moisture, kind.moisture, kind.fades[1]) * cover_tent(ground.slope_degrees, kind.slope, kind.fades[2])
	if climate <= 0 {
		return 0
	}
	on: f32 = 0
	for share, surface in ground.shares {
		on += share * kind.surfaces[surface]
	}
	own := clamp(on, 0, 1)
	boundary := 1 - kind.boundary + kind.boundary * 4 * own * (1 - own)
	return kind.rate * climate * on * boundary * patch * ground.cut
}

// 1 without a patch noise, else the noise (-1 to 1) over the threshold
// across the edge, clamped.
cover_patch_share :: proc(kind: Field_Cover_Kind, noise: f32) -> f32 {
	if kind.patch_wavelength == 0 {
		return 1
	}
	return clamp((noise - kind.patch_threshold) / kind.patch_edge, 0, 1)
}

// 1 within COVER_CUT_MILLIMETRES of the generated surface, 0 past twice
// it, linear between.
cover_cut_share :: proc(offset_millimetres: f32) -> f32 {
	return clamp(2 - offset_millimetres / COVER_CUT_MILLIMETRES, 0, 1)
}

// The 16 bits of the hash at 16 times the slot, 0 to under 1.
cover_unit :: proc(hash: u64, slot: uint) -> f32 {
	return f32((hash >> (16 * slot)) & 0xFFFF) / 65536
}

// A kind's colour by the pick unit, for the kinds coloured from their
// list.
cover_picked_color :: proc(kind: Field_Cover_Kind, unit: f32) -> [3]u8 {
	if kind.color_count == 0 {
		return {255, 255, 255}
	}
	return kind.colors[min(int(unit * f32(kind.color_count)), kind.color_count - 1)]
}

// One instance from four hashes (slots read by cover_unit): hashes[0]
// the rank (0), the caller's barycentric units (1, 2) and the yaw (3);
// hashes[1] the width (0, 1) and the height (2, 3), each the mean of two
// units; hashes[2] the depth (a stone's the mean of 0 and 1, foliage's
// the width times 0.85 to 1.15 by 0) and foliage's lean (2, up to
// COVER_TILT_DEGREES towards the bearing of 3); hashes[3] the shade (0,
// 216 to 255; the colour's pick 1 is the caller's). A stone's up lies
// halfway to the ground's normal. The columns are the right, the up and
// the forward times the width, the height and the depth, the translation
// the base in world metres, sunk along the up by the sink's share of the
// height and by half the width on a slope up to 45 degrees; the bottom
// row the rank, the sky light, the block light and the shade packed, and
// the colour packed (field_pack_bytes), then 1. cover.vs rebuilds it to
// 0, 0, 0, 1.
cover_instance :: proc(kind: Field_Cover_Kind, point, up, normal: [3]f64, slope_tangent: f32, light: [Field_Light_Channel]u8, color: [3]u8, hashes: [4]u64) -> matrix[4, 4]f32 {
	rank := cover_unit(hashes[0], 0)
	yaw := f64(cover_unit(hashes[0], 3)) * math.TAU
	width := math.lerp(kind.width[0], kind.width[1], (cover_unit(hashes[1], 0) + cover_unit(hashes[1], 1)) / 2)
	height := math.lerp(kind.height[0], kind.height[1], (cover_unit(hashes[1], 2) + cover_unit(hashes[1], 3)) / 2)
	depth := width * (0.85 + 0.3 * cover_unit(hashes[2], 0))
	axis_up := up
	if !kind.foliage {
		depth = math.lerp(kind.width[0], kind.width[1], (cover_unit(hashes[2], 0) + cover_unit(hashes[2], 1)) / 2)
		axis_up = cover_normalized(up + normal, up)
	}
	right, forward := cover_tangents(axis_up, yaw)
	if kind.foliage {
		lean := f64(cover_unit(hashes[2], 2)) * COVER_TILT_DEGREES * math.RAD_PER_DEG
		bearing := f64(cover_unit(hashes[2], 3)) * math.TAU
		toward := right * math.cos(bearing) + forward * math.sin(bearing)
		turn := cover_cross(axis_up, toward)
		right = cover_rotated(right, turn, lean)
		axis_up = cover_rotated(axis_up, turn, lean)
		forward = cover_rotated(forward, turn, lean)
	}
	sink := f64(kind.sink * height + 0.5 * max(width, depth) * min(slope_tangent, 1))
	base := point - axis_up * sink
	right_column := cover_vector_f32(right * f64(width))
	up_column := cover_vector_f32(axis_up * f64(height))
	forward_column := cover_vector_f32(forward * f64(depth))
	shade := u8(216 + cover_unit(hashes[3], 0) * 40)
	lights := field_pack_bytes({light[.Sky], light[.Block], shade})
	return matrix[4, 4]f32{
		right_column.x, up_column.x, forward_column.x, f32(base.x),
		right_column.y, up_column.y, forward_column.y, f32(base.y),
		right_column.z, up_column.z, forward_column.z, f32(base.z),
		rank, lights, field_pack_bytes(color), 1,
	}
}

// The instance's base in world metres, its top (the base plus the up
// column) and its rank.
cover_instance_base :: proc(instance: matrix[4, 4]f32) -> [3]f32 {
	return {instance[0, 3], instance[1, 3], instance[2, 3]}
}

cover_instance_top :: proc(instance: matrix[4, 4]f32) -> [3]f32 {
	return cover_instance_base(instance) + {instance[0, 1], instance[1, 1], instance[2, 1]}
}

cover_instance_rank :: proc(instance: matrix[4, 4]f32) -> f32 {
	return instance[3, 0]
}

cover_cross :: proc(first, second: [3]f64) -> [3]f64 {
	return {first.y * second.z - first.z * second.y, first.z * second.x - first.x * second.z, first.x * second.y - first.y * second.x}
}

cover_dot :: proc(first, second: [3]f64) -> f64 {
	return first.x * second.x + first.y * second.y + first.z * second.z
}

// The vector at length 1, the fallback when it has none.
cover_normalized :: proc(vector, fallback: [3]f64) -> [3]f64 {
	length := math.sqrt(cover_dot(vector, vector))
	return length > 1e-9 ? vector / length : fallback
}

cover_vector_f32 :: proc(vector: [3]f64) -> [3]f32 {
	return {f32(vector.x), f32(vector.y), f32(vector.z)}
}

// The vector turned about the unit axis by the angle (Rodrigues).
cover_rotated :: proc(vector, axis: [3]f64, angle: f64) -> [3]f64 {
	cosine, sine := math.cos(angle), math.sin(angle)
	return vector * cosine + cover_cross(axis, vector) * sine + axis * cover_dot(axis, vector) * (1 - cosine)
}

// The right and the forward on the plane of the unit up, turned by the
// yaw from a fixed reference, so a place's frame never depends on the
// node: right is up cross forward, as the models' axes.
cover_tangents :: proc(up: [3]f64, yaw: f64) -> (right, forward: [3]f64) {
	reference := abs(up.y) < 0.9 ? [3]f64{0, 1, 0} : [3]f64{1, 0, 0}
	first := cover_normalized(cover_cross(reference, up), {1, 0, 0})
	second := cover_cross(up, first)
	forward = first * math.cos(yaw) + second * math.sin(yaw)
	right = cover_cross(up, forward)
	return right, forward
}

// A vertex as the placement reads it: its world position in metres, its
// normal, its point on the sphere (for the patch noises), its natural
// share, whether its triangles carry none (wet or dark) and per kind its
// patch share, -1 until a triangle asks for it.
Cover_Vertex :: struct {
	position:  [3]f64,
	normal:    [3]f64,
	on_sphere: [3]i64,
	cut:       f32,
	blocked:   bool,
	patch:     [MAXIMUM_COVER_KINDS]f32,
}

// Whether any of the eight samples of the cell holding the vertex holds
// water, the cell clamped into the grid.
cover_vertex_is_wet :: proc(grid: ^Field_Grid, position: [3]i32) -> bool {
	cell: [3]i32
	for axis in 0 ..< 3 {
		cell[axis] = clamp(floor_divide(position[axis], FIELD_MESH_POSITION_UNITS), -1, FIELD_GRID_CELLS - 1)
	}
	for corner in 0 ..< 8 {
		if grid.water[field_grid_index(cell + field_corner_offset(corner))] > 0 {
			return true
		}
	}
	return false
}

// The vertices' placement inputs (temp allocator).
cover_vertices :: proc(surface: Field_Surface, grid: ^Field_Grid, look: Field_Ground_Look, spacing_millimetres: int) -> []Cover_Vertex {
	vertices := make([]Cover_Vertex, len(surface.vertices), context.temp_allocator)
	generation := look.generation
	for vertex, index in surface.vertices {
		position := field_vertex_world_position(grid, vertex.position, spacing_millimetres)
		normal := field_vertex_normal(vertex.gradient)
		result := &vertices[index]
		result.position = [3]f64{f64(position.x), f64(position.y), f64(position.z)} / POSITION_UNITS_PER_METRE
		result.normal = {f64(normal.x), f64(normal.y), f64(normal.z)}
		result.on_sphere = project_onto_sphere(position, vector_length(([3]i64)(position)), generation.radius)
		result.cut = cover_cut_share(f32(vertex.look.offset_millimetres))
		result.blocked = vertex.light[.Sky] < COVER_LEAST_SKY_LIGHT || cover_vertex_is_wet(grid, vertex.position)
		for &patch in result.patch {
			patch = -1
		}
	}
	return vertices
}

// The vertex's patch share of the kind, read once.
cover_vertex_patch :: proc(vertex: ^Cover_Vertex, kind: Field_Cover_Kind, kind_index: int, ground_look_seed: u64) -> f32 {
	if vertex.patch[kind_index] < 0 {
		noise: f32 = 0
		if kind.patch_wavelength > 0 {
			noise = f32(value_noise(generation_seed.hash_combine(ground_look_seed, u64(COVER_PATCH_SEED + kind_index)), vertex.on_sphere, kind.patch_wavelength)) / NOISE_ONE
		}
		vertex.patch[kind_index] = cover_patch_share(kind, noise)
	}
	return vertex.patch[kind_index]
}

// The triangle's hash: the table's seed, its quad's grid edge in global
// sample coordinates and axis, and its half.
cover_triangle_key :: proc(seed: u64, grid: ^Field_Grid, edge: [4]i32, half: int) -> u64 {
	key := seed
	for axis in 0 ..< 3 {
		key = generation_seed.hash_combine(key, u64(u32(edge[axis] + grid.origin[axis])))
	}
	key = generation_seed.hash_combine(key, u64(edge[3]))
	return generation_seed.hash_combine(key, u64(half))
}

// One triangle's corners as the placement reads them.
Cover_Triangle :: struct {
	corners:  [3]^Cover_Vertex,
	surfaces: [3]Field_Surface_Vertex,
}

// The triangle's ground from its corners' means; the slope of the mean
// normal against the radial at the centroid, whose unit is radial; the
// area in square metres.
cover_triangle_ground :: proc(triangle: Cover_Triangle) -> (ground: Cover_Ground, radial, normal: [3]f64, area: f64) {
	a, b, c := triangle.corners[0], triangle.corners[1], triangle.corners[2]
	area = math.sqrt(cover_dot(cover_cross(b.position - a.position, c.position - a.position), cover_cross(b.position - a.position, c.position - a.position))) / 2
	radial = cover_normalized(a.position + b.position + c.position, {0, 1, 0})
	normal = cover_normalized(a.normal + b.normal + c.normal, radial)
	facing := clamp(cover_dot(normal, radial), -1, 1)
	weights: [FIELD_TEXTURED_MATERIAL_COUNT]f32
	snow, sand: f32
	for corner in triangle.surfaces {
		ground.celsius += corner.look.celsius / 3
		ground.moisture += corner.look.moisture * 100 / 3
		snow += f32(corner.look.snow) / (3 * 255)
		sand += f32(corner.look.sand) / (3 * 255)
		for weight, slot in corner.weights {
			weights[slot] += f32(weight) / (3 * 255)
		}
	}
	ground.slope_degrees = f32(math.acos(facing) * math.DEG_PER_RAD)
	ground.cut = (a.cut + b.cut + c.cut) / 3
	ground.shares = cover_ground_shares(weights, snow, sand, f32(1 - facing))
	return ground, radial, normal, area
}

// The colour an instance takes by its kind's source: the corners' mean
// grass colour, their mean strata tint, or the picked one.
cover_triangle_color :: proc(kind: Field_Cover_Kind, triangle: Cover_Triangle, pick: f32) -> [3]u8 {
	sum: [3]f32
	switch kind.color_from {
	case .Grass:
		for corner in triangle.surfaces {
			sum += field_color_float({int(corner.look.grass.r), int(corner.look.grass.g), int(corner.look.grass.b)})
		}
	case .Ground:
		for corner in triangle.surfaces {
			sum += field_color_float({int(corner.color.r), int(corner.color.g), int(corner.color.b)})
		}
	case .Colors:
		return cover_picked_color(kind, pick)
	}
	return field_color_bytes(sum / 3)
}

// The corners' mean light.
cover_triangle_light :: proc(triangle: Cover_Triangle) -> (light: [Field_Light_Channel]u8) {
	for channel in Field_Light_Channel {
		sum := 0
		for corner in triangle.surfaces {
			sum += int(corner.light[channel])
		}
		light[channel] = u8((sum + 1) / 3)
	}
	return light
}

// The ground cover on the surface's triangles before its skirts (the
// finest level only, with the table and the look on), in allocator: per
// triangle none when a corner is wet, dark or cut through; else per kind
// floor(area times density plus a hashed share) instances, each from four
// hashes of the triangle's key, the kind and its index, skipped at a rank
// at or above the table's density and when a frame's cell holds it
// (cover_instance_cleared). Per kind sorted by rank, cut to the table's
// limit, with its rank counts.
place_field_cover :: proc(surface: Field_Surface, grid: ^Field_Grid, look: Field_Ground_Look, table: Field_Cover_Table, spacing_millimetres: int, frames: []Cover_Frame, allocator := context.allocator) -> (data: Field_Cover_Data) {
	if !table.on || !look.on || grid.step != 1 {
		return {}
	}
	for &kind in data.kinds {
		kind.instances = make([dynamic]matrix[4, 4]f32, allocator)
	}
	vertices := cover_vertices(surface, grid, look, spacing_millimetres)
	ground_look_seed := look.generation.ground_look_seed
	for triangle_index in 0 ..< surface.skirt_index_start / 3 {
		triangle: Cover_Triangle
		skipped := false
		for corner in 0 ..< 3 {
			index := surface.indices[3 * triangle_index + corner]
			triangle.corners[corner] = &vertices[index]
			triangle.surfaces[corner] = surface.vertices[index]
			skipped ||= vertices[index].blocked || vertices[index].cut <= 0
		}
		if skipped {
			continue
		}
		ground, radial, normal, area := cover_triangle_ground(triangle)
		if area <= 0 {
			continue
		}
		facing := cover_dot(normal, radial)
		slope_tangent := facing > 1e-3 ? f32(math.sqrt(max(1 - facing * facing, 0)) / facing) : 1000
		key := cover_triangle_key(table.seed, grid, surface.quad_edges[triangle_index / 2], triangle_index % 2)
		a, b, c := triangle.corners[0].position, triangle.corners[1].position, triangle.corners[2].position
		light := cover_triangle_light(triangle)
		for kind_index in 0 ..< table.kind_count {
			kind := table.kinds[kind_index]
			density := cover_kind_density(kind, ground, 1)
			if density <= 0 {
				continue
			}
			patch: f32 = 0
			for corner in triangle.corners {
				patch += cover_vertex_patch(corner, kind, kind_index, ground_look_seed) / 3
			}
			seed := generation_seed.hash_combine(key, u64(kind_index))
			count := int(f32(area) * density * patch + cover_unit(seed, 0))
			for instance_index in 0 ..< count {
				hashes: [4]u64
				for &hash, slot in hashes {
					hash = generation_seed.hash_combine(seed, u64(4 * instance_index + 1 + slot))
				}
				if cover_unit(hashes[0], 0) >= table.density {
					continue
				}
				along, across := f64(cover_unit(hashes[0], 1)), f64(cover_unit(hashes[0], 2))
				if along + across > 1 {
					along, across = 1 - along, 1 - across
				}
				point := a + (b - a) * along + (c - a) * across
				color := cover_triangle_color(kind, triangle, cover_unit(hashes[3], 1))
				instance := cover_instance(kind, point, cover_normalized(point, radial), normal, slope_tangent, light, color, hashes)
				if cover_instance_cleared(frames, instance) {
					continue
				}
				append(&data.kinds[kind_index].instances, instance)
			}
		}
	}
	for &kind in data.kinds[:table.kind_count] {
		finish_cover_instances(&kind, table.limit)
	}
	return data
}

// Sorted by rank, cut to the limit (the lowest ranks kept), the rank
// counts made.
finish_cover_instances :: proc(kind: ^Field_Cover_Instances, limit: int) {
	slice.sort_by(kind.instances[:], proc(first, second: matrix[4, 4]f32) -> bool {
		return cover_instance_rank(first) < cover_instance_rank(second)
	})
	if len(kind.instances) > limit {
		resize(&kind.instances, limit)
	}
	kind.rank_counts = cover_rank_counts(kind.instances[:])
}

// Per rank step the count of the instances (sorted by rank) under its
// top, (step + 1) / COVER_RANK_STEPS.
cover_rank_counts :: proc(instances: []matrix[4, 4]f32) -> (counts: [COVER_RANK_STEPS]i32) {
	next := 0
	for step in 0 ..< COVER_RANK_STEPS {
		top := f32(step + 1) / COVER_RANK_STEPS
		for next < len(instances) && cover_instance_rank(instances[next]) < top {
			next += 1
		}
		counts[step] = i32(next)
	}
	return counts
}

// Whether the instance's base, middle or top lies in an occupied cell of
// a frame: each point in world position units, for each frame whose box
// holds it, its cell found among the frame's sorted cells.
cover_instance_cleared :: proc(frames: []Cover_Frame, instance: matrix[4, 4]f32) -> bool {
	if len(frames) == 0 {
		return false
	}
	base := cover_instance_base(instance)
	top := cover_instance_top(instance)
	for point in ([3][3]f32{base, (base + top) / 2, top}) {
		metres := [3]f64{f64(point.x), f64(point.y), f64(point.z)}
		for &frame in frames {
			if !cover_box_holds(frame.minimum, frame.maximum, metres) {
				continue
			}
			position := World_Position{i64(math.round(metres.x * POSITION_UNITS_PER_METRE)), i64(math.round(metres.y * POSITION_UNITS_PER_METRE)), i64(math.round(metres.z * POSITION_UNITS_PER_METRE))}
			if _, found := slice.binary_search_by(frame.cells[:], world_to_frame_cell(frame.frame, position), cover_cell_order); found {
				return true
			}
		}
	}
	return false
}

cover_box_holds :: proc(minimum, maximum, point: [3]f64) -> bool {
	return point.x >= minimum.x && point.x <= maximum.x && point.y >= minimum.y && point.y <= maximum.y && point.z >= minimum.z && point.z <= maximum.z
}

cover_boxes_meet :: proc(first_minimum, first_maximum, second_minimum, second_maximum: [3]f64) -> bool {
	for axis in 0 ..< 3 {
		if first_maximum[axis] < second_minimum[axis] || second_maximum[axis] < first_minimum[axis] {
			return false
		}
	}
	return true
}

// Cells by (z, y, x).
cover_cell_order :: proc(cell, key: World_Coordinate) -> slice.Ordering {
	for axis := 2; axis >= 0; axis -= 1 {
		if cell[axis] != key[axis] {
			return cell[axis] < key[axis] ? .Less : .Greater
		}
	}
	return .Equal
}

// Every frame of the table with occupied cells (the block frame left
// out), in id order, its cells sorted and its box from its cells' centres
// widened by half a pitch's diagonal, in allocator.
snapshot_cover_frames :: proc(table: ^Frame_Table, allocator := context.allocator) -> [dynamic]Cover_Frame {
	occupied := make([dynamic]Frame_Cell, 0, len(table.occupants), context.temp_allocator)
	for key in table.occupants {
		if key.frame != BLOCK_FRAME {
			append(&occupied, key)
		}
	}
	slice.sort_by(occupied[:], proc(first, second: Frame_Cell) -> bool {
		if first.frame != second.frame {
			return first.frame < second.frame
		}
		return cover_cell_order(first.cell, second.cell) == .Less
	})
	frames := make([dynamic]Cover_Frame, allocator)
	next := 0
	for frame in table.frames {
		for next < len(occupied) && occupied[next].frame < frame.id {
			next += 1
		}
		cover := Cover_Frame{frame = frame, cells = make([dynamic]World_Coordinate, allocator)}
		for next < len(occupied) && occupied[next].frame == frame.id {
			append(&cover.cells, occupied[next].cell)
			next += 1
		}
		if len(cover.cells) == 0 {
			delete(cover.cells)
			continue
		}
		cover.minimum, cover.maximum = cover_frame_box(frame, cover.cells[:])
		append(&frames, cover)
	}
	return frames
}

// The box in metres round the cells' corners: their centres' box widened
// by half the pitch's diagonal.
cover_frame_box :: proc(frame: Frame, cells: []World_Coordinate) -> (minimum, maximum: [3]f64) {
	minimum, maximum = max(f64), min(f64)
	for cell in cells {
		centre := frame_cell_centre(frame, cell)
		metres := [3]f64{f64(centre.x), f64(centre.y), f64(centre.z)} / POSITION_UNITS_PER_METRE
		for axis in 0 ..< 3 {
			minimum[axis] = min(minimum[axis], metres[axis])
			maximum[axis] = max(maximum[axis], metres[axis])
		}
	}
	reach := f64(frame.pitch_millimetres) / MILLIMETRES_PER_METRE * math.SQRT_THREE / 2
	return minimum - reach, maximum + reach
}

// Deep copies of the frames whose box meets the given one, in allocator;
// nil when none does.
cover_frames_meeting :: proc(frames: []Cover_Frame, minimum, maximum: [3]f64, allocator := context.allocator) -> []Cover_Frame {
	count := 0
	for frame in frames {
		if cover_boxes_meet(frame.minimum, frame.maximum, minimum, maximum) {
			count += 1
		}
	}
	if count == 0 {
		return nil
	}
	result := make([]Cover_Frame, count, allocator)
	next := 0
	for frame in frames {
		if !cover_boxes_meet(frame.minimum, frame.maximum, minimum, maximum) {
			continue
		}
		result[next] = frame
		result[next].cells = make([dynamic]World_Coordinate, len(frame.cells), allocator)
		copy(result[next].cells[:], frame.cells[:])
		next += 1
	}
	return result
}

// A finest node's box in metres, from its origin a node's samples on,
// widened by the margin on every side.
field_cover_node_box :: proc(node: Field_Node, spacing_millimetres: int, margin_metres: f64) -> (minimum, maximum: [3]f64) {
	origin := sample_to_world_position(field_node_origin(node), spacing_millimetres)
	minimum = [3]f64{f64(origin.x), f64(origin.y), f64(origin.z)} / POSITION_UNITS_PER_METRE
	size := f64(field_node_samples(node.level)) * f64(spacing_millimetres) / MILLIMETRES_PER_METRE
	return minimum - margin_metres, minimum + size + margin_metres
}
