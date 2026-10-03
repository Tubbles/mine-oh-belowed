package game

import "generation_seed"

// The trees on the sphere (work item 0197, doc/content.md, Trees;
// doc/architecture.md, World generation). Two jittered lattices on the
// sphere of the planet's radius: grove centres on a coarse one, trees on
// a fine one. A candidate is a hashed point in its lattice cube projected
// onto the sphere, kept only when the projection stays in the same cube,
// so every point of the sphere belongs to one cube and no key is
// generated twice. A grove cube holds a grove by the planet's share; a
// tree cube keeps its candidate with a chance that falls with the square
// of the distance from the nearest grove's centre, to none at the grove's
// reach. None within the clearing round the home, below the sea (with a
// margin) or on ground steeper than the planet's slope. Keys sit on the
// sphere of the radius, not on the relief, so a relief term never moves a
// key; each tree has its own yaw, scale and shade from its hash. A
// standing tree is a pure function of the seed, the recorded planet and
// the key; the field spacing never moves a tree. Integers only.

PLANET_TREE_SEA_MARGIN_METRES :: 1
PLANET_TREE_SLOPE_PROBE_METRES :: 1
// The trunk's base lies this far below the generated surface, which
// covers a 35 degree slope under a 207 mm trunk.
PLANET_TREE_BASE_SINK_MILLIMETRES :: 300
PLANET_TREE_MINIMUM_SCALE_PERCENT :: 85
PLANET_TREE_MAXIMUM_SCALE_PERCENT :: 115
PLANET_TREE_MINIMUM_SHADE_PERCENT :: 92
PLANET_TREE_MAXIMUM_SHADE_PERCENT :: 108
// The jitter per axis takes this many bits of the cube's hash.
PLANET_TREE_JITTER_BITS :: 21
// A box of more tree cubes is a programming error.
PLANET_TREE_BOX_CELL_LIMIT :: 1 << 20

// The tree lattice's cube; unique per tree on the planet.
Tree_Key :: [3]i32

// What the generation reads, in position units; spacing 0 is no trees.
Planet_Tree_Term :: struct {
	grove_seed:            u64,
	tree_seed:             u64,
	spacing:               i64,
	grove_spacing:         i64,
	grove_radius:          i64,
	clearing:              i64,
	grove_share_percent:   i64,
	density_percent:       i64,
	maximum_slope_percent: i64,
	species_count:         int,
	// The home on the sphere of the radius.
	home:                  [3]i64,
}

Planet_Tree :: struct {
	key:           Tree_Key,
	// The trunk's bottom: the generated surface less
	// PLANET_TREE_BASE_SINK_MILLIMETRES along up.
	base:          World_Position,
	// The unit radial.
	up:            [3]i64,
	// Angle units from the north tangent towards its cross with up.
	yaw:           i32,
	scale_percent: u8,
	// The draw's brightness.
	shade_percent: u8,
	// Modulo the species count.
	species:       u8,
}

// The zero term for no trees (a share of 0 or no species).
make_planet_tree_term :: proc(seed: u64, trees: Planet_Trees, home: Planet_Home, radius: i64) -> Planet_Tree_Term {
	if trees.grove_share_percent <= 0 || len(trees.species) == 0 {
		return {}
	}
	seeds := generation_seed.derive_purpose_seeds(seed)
	return Planet_Tree_Term {
		grove_seed            = seeds[.Planet_Groves],
		tree_seed             = seeds[.Planet_Trees],
		spacing               = metres_to_position_units(i64(trees.tree_spacing_metres)),
		grove_spacing         = metres_to_position_units(i64(trees.grove_spacing_metres)),
		grove_radius          = metres_to_position_units(i64(trees.grove_radius_metres)),
		clearing              = metres_to_position_units(i64(trees.clearing_metres)),
		grove_share_percent   = i64(trees.grove_share_percent),
		density_percent       = i64(trees.density_percent),
		maximum_slope_percent = i64(trees.maximum_slope_percent),
		species_count         = len(trees.species),
		home                  = fixed_scale(planet_home_direction(home), radius),
	}
}

// The cube's hashed point projected onto the sphere of the radius; ok
// when the projection stays in the cube (and the point is not the
// centre).
lattice_candidate :: proc(seed: u64, cell: [3]i64, spacing, radius: i64) -> (on_sphere: [3]i64, hash: u64, ok: bool) {
	hash = hash_lattice(seed, cell)
	point: [3]i64
	for axis in 0 ..< 3 {
		jitter := i64(hash >> uint(axis * PLANET_TREE_JITTER_BITS) & (1 << PLANET_TREE_JITTER_BITS - 1)) * spacing >> PLANET_TREE_JITTER_BITS
		point[axis] = cell[axis] * spacing + jitter
	}
	distance := vector_length(point)
	if distance == 0 {
		return {}, hash, false
	}
	on_sphere = project_onto_sphere(World_Position(point), distance, radius)
	for axis in 0 ..< 3 {
		if floor_divide_i64(on_sphere[axis], spacing) != cell[axis] {
			return {}, hash, false
		}
	}
	return on_sphere, hash, true
}

// The box's nearest point lies inside the sphere and its farthest corner
// outside: the cheap reject before lattice_candidate.
cube_straddles_sphere :: proc(minimum, maximum: [3]i64, radius: i64) -> bool {
	nearest, farthest: i64
	for axis in 0 ..< 3 {
		near := clamp(0, minimum[axis], maximum[axis])
		far := max(abs(minimum[axis]), abs(maximum[axis]))
		nearest += near * near
		farthest += far * far
	}
	return nearest <= radius * radius && farthest >= radius * radius
}

// The grove centres (on the sphere) of the grove cubes overlapping the box
// widened by the grove's reach.
planet_groves_near :: proc(term: Planet_Tree_Term, radius: i64, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> [][3]i64 {
	groves := make([dynamic][3]i64, allocator)
	first, last: [3]i64
	for axis in 0 ..< 3 {
		first[axis] = floor_divide_i64(minimum[axis] - term.grove_radius, term.grove_spacing)
		last[axis] = floor_divide_i64(maximum[axis] + term.grove_radius, term.grove_spacing)
	}
	for x in first.x ..= last.x {
		for y in first.y ..= last.y {
			for z in first.z ..= last.z {
				cell := [3]i64{x, y, z}
				if !cube_straddles_sphere(cell * term.grove_spacing, cell * term.grove_spacing + term.grove_spacing, radius) {
					continue
				}
				centre, hash, ok := lattice_candidate(term.grove_seed, cell, term.grove_spacing, radius)
				if ok && i64(generation_seed.hash_combine(hash, 1) % 100) < term.grove_share_percent {
					append(&groves, centre)
				}
			}
		}
	}
	return groves[:]
}

// The largest share of NOISE_ONE over the groves within reach: one at a
// centre, falling with the square of the distance to none at the reach.
grove_strength :: proc(groves: [][3]i64, grove_radius: i64, point: [3]i64) -> i64 {
	strongest: i64 = 0
	for centre in groves {
		offset := point - centre
		squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
		if squared < grove_radius * grove_radius {
			strongest = max(strongest, NOISE_ONE - squared * NOISE_ONE / (grove_radius * grove_radius))
		}
	}
	return strongest
}

// The relief rises at most the slope over the probe in either tangent.
planet_tree_slope_ok :: proc(generation: Planet_Generation, on_sphere, up: [3]i64) -> bool {
	north := frame_north_tangent(up)
	east := fixed_cross(north, up)
	probe := metres_to_position_units(PLANET_TREE_SLOPE_PROBE_METRES)
	along_north := surface_relief(generation, on_sphere + fixed_scale(north, probe)) - surface_relief(generation, on_sphere - fixed_scale(north, probe))
	along_east := surface_relief(generation, on_sphere + fixed_scale(east, probe)) - surface_relief(generation, on_sphere - fixed_scale(east, probe))
	allowed := 2 * probe * generation.trees.maximum_slope_percent
	return (along_north * along_north + along_east * along_east) * 100 * 100 <= allowed * allowed
}

// A value in minimum to maximum from the hash.
tree_hash_percent :: proc(hash: u64, minimum, maximum: i64) -> u8 {
	return u8(generation_seed.hash_to_range(hash, minimum, maximum))
}

// The tree of a kept candidate, the cheapest rules first: the grove's
// chance, the clearing, the sea, the slope.
planet_tree_from_candidate :: proc(generation: Planet_Generation, cell: [3]i64, on_sphere: [3]i64, hash: u64, strength: i64) -> (tree: Planet_Tree, ok: bool) {
	term := generation.trees
	if i64(generation_seed.hash_combine(hash, 1) % NOISE_ONE) >= strength * term.density_percent / 100 {
		return {}, false
	}
	offset := on_sphere - term.home
	if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= term.clearing * term.clearing {
		return {}, false
	}
	relief := surface_relief(generation, on_sphere)
	if relief < generation.sea_radius - generation.radius + metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES) {
		return {}, false
	}
	up, _ := normalize_fixed(on_sphere)
	if !planet_tree_slope_ok(generation, on_sphere, up) {
		return {}, false
	}
	return Planet_Tree {
			key           = {i32(cell.x), i32(cell.y), i32(cell.z)},
			base          = World_Position(on_sphere + fixed_scale(up, relief - millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES))),
			up            = up,
			yaw           = i32(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 2), 0, ANGLE_UNITS_PER_TURN - 1)),
			scale_percent = tree_hash_percent(generation_seed.hash_combine(hash, 3), PLANET_TREE_MINIMUM_SCALE_PERCENT, PLANET_TREE_MAXIMUM_SCALE_PERCENT),
			species       = u8(generation_seed.hash_combine(hash, 4) % u64(term.species_count)),
			shade_percent = tree_hash_percent(generation_seed.hash_combine(hash, 5), PLANET_TREE_MINIMUM_SHADE_PERCENT, PLANET_TREE_MAXIMUM_SHADE_PERCENT),
		},
		true
}

// The tree cubes from the one holding minimum to the one holding maximum,
// x outermost, then y, then z; the box is in position units on or near
// the sphere of the radius (callers project onto it). Nothing for the zero
// term.
planet_trees_in_box :: proc(generation: ^Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> [dynamic]Planet_Tree {
	trees := make([dynamic]Planet_Tree, allocator)
	term := generation.trees
	if term.spacing == 0 {
		return trees
	}
	groves := planet_groves_near(term, generation.radius, minimum, maximum)
	if len(groves) == 0 {
		return trees
	}
	first, last: [3]i64
	for axis in 0 ..< 3 {
		first[axis] = floor_divide_i64(minimum[axis], term.spacing)
		last[axis] = floor_divide_i64(maximum[axis], term.spacing)
	}
	size := last - first + 1
	assert(size.x * size.y * size.z <= PLANET_TREE_BOX_CELL_LIMIT, "planet_trees_in_box: the box holds too many tree cubes")
	for x in first.x ..= last.x {
		for y in first.y ..= last.y {
			for z in first.z ..= last.z {
				append_planet_tree(&trees, generation, groves, {x, y, z})
			}
		}
	}
	return trees
}

// The cube's tree, when it has one.
append_planet_tree :: proc(trees: ^[dynamic]Planet_Tree, generation: ^Planet_Generation, groves: [][3]i64, cell: [3]i64) {
	term := generation.trees
	if !cube_straddles_sphere(cell * term.spacing, cell * term.spacing + term.spacing, generation.radius) {
		return
	}
	on_sphere, hash, ok := lattice_candidate(term.tree_seed, cell, term.spacing, generation.radius)
	if !ok {
		return
	}
	strength := grove_strength(groves, term.grove_radius, on_sphere)
	if strength == 0 {
		return
	}
	if tree, kept := planet_tree_from_candidate(generation^, cell, on_sphere, hash, strength); kept {
		append(trees, tree)
	}
}

// The key's cube alone.
planet_tree_at_key :: proc(generation: ^Planet_Generation, key: Tree_Key) -> (tree: Planet_Tree, found: bool) {
	if generation.trees.spacing == 0 {
		return {}, false
	}
	corner := [3]i64{i64(key.x), i64(key.y), i64(key.z)} * generation.trees.spacing
	trees := planet_trees_in_box(generation, corner, corner)
	if len(trees) == 0 {
		return {}, false
	}
	return trees[0], true
}

// The box round the position projected onto the sphere of the radius,
// reach and one tree spacing either way on every axis.
planet_tree_box_round :: proc(generation: ^Planet_Generation, position: World_Position, reach: i64) -> (minimum, maximum: [3]i64) {
	distance := vector_length(cast([3]i64)(position))
	centre := project_onto_sphere(position, distance, generation.radius)
	margin := reach + generation.trees.spacing
	return centre - margin, centre + margin
}

// Right, up and forward of a tree: forward the north tangent turned by the
// yaw towards its cross with up and projected, as frame_forward with any
// angle, right their cross as frame_axes.
tree_axes :: proc(up: [3]i64, yaw: i32) -> [3][3]i64 {
	north := frame_north_tangent(up)
	turned := fixed_scale(north, fixed_cosine(yaw)) + fixed_scale(fixed_cross(north, up), fixed_sine(yaw))
	forward, ok := normalize_fixed(project_onto_plane(turned, up))
	if !ok {
		forward = north
	}
	right, right_ok := normalize_fixed(fixed_cross(up, forward))
	if !right_ok {
		right = {UNIT_VECTOR_ONE, 0, 0}
	}
	return {right, up, forward}
}

// x, then y, then z.
tree_key_before :: proc(first, second: Tree_Key) -> bool {
	if first.x != second.x {
		return first.x < second.x
	}
	if first.y != second.y {
		return first.y < second.y
	}
	return first.z < second.z
}
