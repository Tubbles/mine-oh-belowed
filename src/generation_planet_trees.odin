package game

import "generation_seed"

// The trees on the sphere (work item 0197, doc/content.md, Trees;
// doc/architecture.md, World generation). A jittered lattice of tree
// cubes on the sphere of the planet's radius: a candidate is a hashed
// point in its lattice cube projected onto the sphere, kept only when the
// projection stays in the same cube, so every point of the sphere belongs
// to one cube and no key is generated twice. Two placements read it. The
// groves (0197): grove centres on a coarse lattice, a grove cube holding
// a grove by the planet's share, a tree cube keeping its candidate with a
// chance that falls with the square of the distance from the nearest
// grove's centre, to none at the grove's reach. The forest (0310, in
// place of the groves while it is on): a candidate stands by a density
// read off the forest's cover (two noises and the moisture), the
// species' climate weights there and the slope, none nearer than the
// gap to a neighbouring cube's candidate of higher priority (Matérn's
// second rule, so a box's trees never depend on the box), its species
// drawn by the weights moved by each species' stand noise, its scale
// triangular in the species' range. Either way none within the clearing
// round the home, below the sea or a lake (0312) (with a margin), on a
// carving site (0324) or on ground steeper than the planet's slope. Keys
// sit on the sphere of the radius, not on the relief, so a relief term
// never moves a key; each tree has its own yaw, scale and shade from its
// hash. A standing tree is a pure function of the seed, the recorded
// planet and the key; the field spacing never moves a tree. Integers
// only.

PLANET_TREE_SEA_MARGIN_METRES :: 1
PLANET_TREE_SLOPE_PROBE_METRES :: 1
// A tree stands only where the ground this far under its relief is ground
// (0327, planet_tree_ground), so none stands over a cave or a notch.
PLANET_TREE_CAVE_PROBE_MILLIMETRES :: 1000
// The trunk's base lies this far below the generated surface, which
// covers a 35 degree slope under a 207 mm trunk.
PLANET_TREE_BASE_SINK_MILLIMETRES :: 300
// A grove tree's scale (0197); a forest's lies in its species' range
// (0310).
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
	// The forest (0310): on, its seed, its keys (Planet_Forest) in
	// position units and shares of NOISE_ONE, and the species' placement
	// keys.
	forest_on:             bool,
	forest_seed:           u64,
	cover_wavelength:      i64,
	clearing_wavelength:   i64,
	stand_wavelength:      i64,
	clearing_percent:      i64,
	stand_percent:         i64,
	full_slope_percent:    i64,
	cover_threshold:       i64,
	cover_edge:            i64,
	moisture_cover:        i64,
	scatter:               i64,
	// density_percent as a share.
	forest_density:        i64,
	meadow:                i64,
	gap:                   i64,
	fade_millicelsius:     i64,
	fade_permille:         i64,
	fade_height:           i64,
	fade_cover:            i64,
	species:               [MAXIMUM_TREE_SPECIES]Planet_Tree_Species_Placement,
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

// The zero term for no trees (a grove share of 0 with the forest off,
// or no species).
make_planet_tree_term :: proc(seed: u64, trees: Planet_Trees, home: Planet_Home, radius: i64) -> Planet_Tree_Term {
	forest_on := planet_forest_on(trees.forest)
	if (trees.grove_share_percent <= 0 && !forest_on) || len(trees.species) == 0 {
		return {}
	}
	seeds := generation_seed.derive_purpose_seeds(seed)
	term := Planet_Tree_Term {
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
	if forest_on {
		fill_forest_term(&term, trees, seeds[.Planet_Forest])
	}
	return term
}

// The forest's keys into the term (0310).
fill_forest_term :: proc(term: ^Planet_Tree_Term, trees: Planet_Trees, forest_seed: u64) {
	forest := trees.forest
	term.forest_on = true
	term.forest_seed = forest_seed
	term.cover_wavelength = metres_to_position_units(i64(forest.cover_wavelength_metres))
	term.clearing_wavelength = metres_to_position_units(i64(forest.clearing_wavelength_metres))
	term.stand_wavelength = metres_to_position_units(i64(forest.stand_wavelength_metres))
	term.clearing_percent = i64(forest.clearing_percent)
	term.stand_percent = i64(forest.stand_percent)
	term.full_slope_percent = i64(forest.full_slope_percent)
	term.cover_threshold = i64(forest.cover_threshold_percent) * NOISE_ONE / 100
	term.cover_edge = i64(forest.edge_percent) * NOISE_ONE / 100
	term.moisture_cover = i64(forest.moisture_cover_percent) * NOISE_ONE / 100
	term.scatter = i64(forest.scatter_percent) * NOISE_ONE / 100
	term.forest_density = i64(trees.density_percent) * NOISE_ONE / 100
	term.meadow = metres_to_position_units(i64(forest.meadow_metres))
	term.gap = millimetres_to_position_units(forest.minimum_gap_millimetres)
	term.fade_millicelsius = i64(forest.species_fade_celsius) * 1000
	term.fade_permille = i64(forest.species_fade_moisture_percent) * 10
	term.fade_height = metres_to_position_units(i64(forest.species_fade_metres))
	term.fade_cover = i64(forest.species_fade_cover_percent) * NOISE_ONE
	for species, index in trees.species[:min(len(trees.species), MAXIMUM_TREE_SPECIES)] {
		term.species[index] = tree_species_placement(species)
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

// The ground a tree may stand on, both placements' rule: the relief
// there, not ok on a carving site (0324: a fin, a knoll or a cap, nor
// over an arch's flank where the carve opens the column), below the sea
// or under a lake's level (0312), each with the margin, nor where a cave
// or a notch (0327) leaves air PLANET_TREE_CAVE_PROBE_MILLIMETRES under
// the relief. The caves are read without the lakes, so the rule may
// refuse a tree by a lake whose fade took the cave away, never keep one
// over a cave.
planet_tree_ground :: proc(generation: Planet_Generation, on_sphere: [3]i64) -> (relief: i64, ok: bool) {
	column := surface_column(generation, on_sphere)
	if column.carve.site.kind in CARVING_KINDS {
		return 0, false
	}
	margin := metres_to_position_units(PLANET_TREE_SEA_MARGIN_METRES)
	if column.relief < generation.sea_radius - generation.radius + margin {
		return 0, false
	}
	if level, found := planet_lake_level_at(generation.lakes, on_sphere, generation.radius); found && column.relief < level + margin {
		return 0, false
	}
	if (column.cave_share > 0 || column.undercut.reach > 0) && !planet_tree_cave_probe_ground(generation, column, on_sphere) {
		return 0, false
	}
	return column.relief, true
}

// Whether the sample PLANET_TREE_CAVE_PROBE_MILLIMETRES under the column's
// relief along its radial is ground with the caves and the notches, read
// with a copy of the generation without lakes or tiles.
planet_tree_cave_probe_ground :: proc(generation: Planet_Generation, column: Surface_Column, on_sphere: [3]i64) -> bool {
	dry := generation
	dry.lakes = nil
	dry.water_tiles = nil
	up, _ := normalize_fixed(on_sphere)
	distance := dry.radius + column.relief - millimetres_to_position_units(PLANET_TREE_CAVE_PROBE_MILLIMETRES)
	depth := sample_depth(dry, column, cave_column(dry, column, on_sphere), World_Position(fixed_scale(up, distance)), distance, on_sphere)
	return depth_to_density(depth, dry.spacing_millimetres) > 0
}

// The tree of a candidate kept by a placement: its trunk's base the
// relief less the sink along up, its yaw and shade from the hash.
planet_tree_at :: proc(cell, on_sphere, up: [3]i64, relief: i64, hash: u64, scale_percent, species: u8) -> Planet_Tree {
	return Planet_Tree {
		key           = {i32(cell.x), i32(cell.y), i32(cell.z)},
		base          = World_Position(on_sphere + fixed_scale(up, relief - millimetres_to_position_units(PLANET_TREE_BASE_SINK_MILLIMETRES))),
		up            = up,
		yaw           = i32(generation_seed.hash_to_range(generation_seed.hash_combine(hash, 2), 0, ANGLE_UNITS_PER_TURN - 1)),
		scale_percent = scale_percent,
		species       = species,
		shade_percent = tree_hash_percent(generation_seed.hash_combine(hash, 5), PLANET_TREE_MINIMUM_SHADE_PERCENT, PLANET_TREE_MAXIMUM_SHADE_PERCENT),
	}
}

// Within the clearing round the home (by the chord).
planet_tree_in_clearing :: proc(term: Planet_Tree_Term, on_sphere: [3]i64) -> bool {
	offset := on_sphere - term.home
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= term.clearing * term.clearing
}

// The tree of a kept candidate, the cheapest rules first: the grove's
// chance, the clearing, the ground (planet_tree_ground), the slope.
planet_tree_from_candidate :: proc(generation: Planet_Generation, cell: [3]i64, on_sphere: [3]i64, hash: u64, strength: i64) -> (tree: Planet_Tree, ok: bool) {
	term := generation.trees
	if i64(generation_seed.hash_combine(hash, 1) % NOISE_ONE) >= strength * term.density_percent / 100 {
		return {}, false
	}
	if planet_tree_in_clearing(term, on_sphere) {
		return {}, false
	}
	relief := planet_tree_ground(generation, on_sphere) or_return
	up, _ := normalize_fixed(on_sphere)
	if !planet_tree_slope_ok(generation, on_sphere, up) {
		return {}, false
	}
	scale := tree_hash_percent(generation_seed.hash_combine(hash, 3), PLANET_TREE_MINIMUM_SCALE_PERCENT, PLANET_TREE_MAXIMUM_SCALE_PERCENT)
	species := u8(generation_seed.hash_combine(hash, 4) % u64(term.species_count))
	return planet_tree_at(cell, on_sphere, up, relief, hash, scale, species), true
}

// The forest (0310).

// The value's share of NOISE_ONE between start and start plus width.
forest_ramp :: proc(value, start, width: i64) -> i64 {
	return clamp((value - start) * NOISE_ONE / max(width, 1), 0, NOISE_ONE)
}

// The forest's cover, 0 to NOISE_ONE: the cover noise mixed with the
// clearing noise, moved by the moisture's distance from the middle,
// through the ramp from the threshold over the edge.
forest_cover :: proc(term: Planet_Tree_Term, point: [3]i64, moisture: i64) -> i64 {
	first := gradient_noise(generation_seed.hash_combine(term.forest_seed, 0), point, term.cover_wavelength)
	second := gradient_noise(generation_seed.hash_combine(term.forest_seed, 1), point, term.clearing_wavelength)
	noise := ((100 - term.clearing_percent) * first + term.clearing_percent * second) / 100 + term.moisture_cover * (moisture - 500) / 500
	return forest_ramp(noise, term.cover_threshold, term.cover_edge)
}

// The cover's share by the distance from the home: none within the
// meadow, rising (smoothstep) to all at twice it.
forest_meadow_share :: proc(term: Planet_Tree_Term, point: [3]i64) -> i64 {
	if term.meadow == 0 {
		return NOISE_ONE
	}
	offset := point - term.home
	squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	if squared >= 4 * term.meadow * term.meadow {
		return NOISE_ONE
	}
	distance := i64(integer_square_root(u64(squared)))
	return noise_fade(clamp((distance - term.meadow) * NOISE_ONE / term.meadow, 0, NOISE_ONE))
}

// NOISE_ONE from least to most, falling to 0 over fade either side.
species_tent :: proc(value, least, most, fade: i64) -> i64 {
	if value < least {
		return clamp(NOISE_ONE - (least - value) * NOISE_ONE / fade, 0, NOISE_ONE)
	}
	if value > most {
		return clamp(NOISE_ONE - (value - most) * NOISE_ONE / fade, 0, NOISE_ONE)
	}
	return NOISE_ONE
}

// Each species' weight at the climate (millicelsius, permille, position
// units over the sea, the cover's share), at most its weight percent
// times NOISE_ONE, and their sum; a species out of a range stops at its
// first 0.
species_climate_weights :: proc(term: Planet_Tree_Term, temperature, moisture, height, cover: i64) -> (weights: [MAXIMUM_TREE_SPECIES]i64, total: i64) {
	for index in 0 ..< min(term.species_count, MAXIMUM_TREE_SPECIES) {
		species := term.species[index]
		weight := i64(species.weight_percent) * NOISE_ONE
		weight = weight * species_tent(temperature, i64(species.temperature_celsius[0]) * 1000, i64(species.temperature_celsius[1]) * 1000, term.fade_millicelsius) / NOISE_ONE
		if weight == 0 {
			continue
		}
		weight = weight * species_tent(moisture, i64(species.moisture_percent[0]) * 10, i64(species.moisture_percent[1]) * 10, term.fade_permille) / NOISE_ONE
		if weight == 0 {
			continue
		}
		weight = weight * species_tent(height, metres_to_position_units(i64(species.height_metres[0])), metres_to_position_units(i64(species.height_metres[1])), term.fade_height) / NOISE_ONE
		if weight == 0 {
			continue
		}
		weight = weight * species_tent(cover * 100, i64(species.cover_percent[0]) * NOISE_ONE, i64(species.cover_percent[1]) * NOISE_ONE, term.fade_cover) / NOISE_ONE
		weights[index] = weight
		total += weight
	}
	return weights, total
}

// Each weight moved by its species' stand noise, so a species gathers in
// stands where several fit; returns the new sum.
forest_stand_weights :: proc(term: Planet_Tree_Term, point: [3]i64, weights: ^[MAXIMUM_TREE_SPECIES]i64) -> (total: i64) {
	for &weight, index in weights {
		if weight == 0 {
			continue
		}
		noise := gradient_noise(generation_seed.hash_combine(term.forest_seed, 16 + u64(index)), point, term.stand_wavelength)
		weight = weight * (NOISE_ONE + term.stand_percent * noise / 100) / NOISE_ONE
		total += weight
	}
	return total
}

// The species the pick (below the weights' sum) lands on, walking the
// weights in order.
forest_species_pick :: proc(weights: [MAXIMUM_TREE_SPECIES]i64, pick: i64) -> u8 {
	left := pick
	for weight, index in weights {
		if left < weight {
			return u8(index)
		}
		left -= weight
	}
	return 0
}

// A scale from least to most, triangular: the mean of two 16 bit draws of
// the hash.
forest_scale_percent :: proc(hash: u64, least, most: int) -> u8 {
	t := (i64(hash & 0xFFFF) + i64(hash >> 16 & 0xFFFF)) / 2
	return u8(i64(least) + i64(most - least) * t / 0xFFFF)
}

// The candidate's priority in the gap: the lower stands.
forest_gap_priority :: proc(hash: u64) -> u64 {
	return generation_seed.hash_combine(hash, 6)
}

// Matérn's second rule: false when a neighbouring cube's candidate lies
// nearer than the gap with a lower priority. Only the neighbours whose
// cube comes within the gap of the candidate are read (per axis -1 when
// nearer the low face than the gap, +1 likewise high), so a gap within
// the spacing reads at most the 26 round it.
forest_gap_keeps :: proc(term: Planet_Tree_Term, radius: i64, cell, on_sphere: [3]i64, hash: u64) -> bool {
	if term.gap == 0 {
		return true
	}
	low, high: [3]i64
	for axis in 0 ..< 3 {
		within := on_sphere[axis] - cell[axis] * term.spacing
		low[axis] = within < term.gap ? -1 : 0
		high[axis] = term.spacing - within <= term.gap ? 1 : 0
	}
	mine := forest_gap_priority(hash)
	for x in low.x ..= high.x {
		for y in low.y ..= high.y {
			for z in low.z ..= high.z {
				if x == 0 && y == 0 && z == 0 {
					continue
				}
				point, other_hash, ok := lattice_candidate(term.tree_seed, cell + {x, y, z}, term.spacing, radius)
				if !ok {
					continue
				}
				offset := point - on_sphere
				if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z < term.gap * term.gap && forest_gap_priority(other_hash) < mine {
					return false
				}
			}
		}
	}
	return true
}

// The slope in percent from two probes PLANET_TREE_SLOPE_PROBE_METRES
// along the north tangent and its cross with up.
forest_slope_percent :: proc(generation: Planet_Generation, on_sphere, up: [3]i64, relief: i64) -> i64 {
	north := frame_north_tangent(up)
	east := fixed_cross(north, up)
	probe := metres_to_position_units(PLANET_TREE_SLOPE_PROBE_METRES)
	along_north := surface_relief(generation, on_sphere + fixed_scale(north, probe)) - relief
	along_east := surface_relief(generation, on_sphere + fixed_scale(east, probe)) - relief
	return i64(integer_square_root(u64(along_north * along_north + along_east * along_east))) * 100 / probe
}

// The slope's share: all up to the full slope, none at the maximum.
forest_slope_share :: proc(term: Planet_Tree_Term, slope_percent: i64) -> i64 {
	return NOISE_ONE - forest_ramp(slope_percent, term.full_slope_percent, term.maximum_slope_percent - term.full_slope_percent)
}

// The forest's tree of a candidate, the cheapest rules first, against one
// draw of the hash: the clearing, the cover with the meadow (or the
// scatter) times the density, the gap, the ground, the species' climate
// weights, the slope; then the species by the weights moved by the stands
// and the scale.
forest_tree_from_candidate :: proc(generation: Planet_Generation, cell, on_sphere: [3]i64, hash: u64) -> (tree: Planet_Tree, ok: bool) {
	term := generation.trees
	if planet_tree_in_clearing(term, on_sphere) {
		return {}, false
	}
	draw := i64(generation_seed.hash_combine(hash, 1) % NOISE_ONE)
	moisture := planet_moisture(generation, on_sphere)
	cover := forest_cover(term, on_sphere, moisture) * forest_meadow_share(term, on_sphere) / NOISE_ONE
	upper := max(cover, term.scatter) * term.forest_density / NOISE_ONE
	if draw >= upper {
		return {}, false
	}
	if !forest_gap_keeps(term, generation.radius, cell, on_sphere, hash) {
		return {}, false
	}
	relief := planet_tree_ground(generation, on_sphere) or_return
	height := relief - (generation.sea_radius - generation.radius)
	weights, total := species_climate_weights(term, planet_temperature(generation, on_sphere, height), moisture, height, cover)
	exact := upper * min(total / 100, NOISE_ONE) / NOISE_ONE
	if draw >= exact {
		return {}, false
	}
	up, _ := normalize_fixed(on_sphere)
	if draw >= exact * forest_slope_share(term, forest_slope_percent(generation, on_sphere, up, relief)) / NOISE_ONE {
		return {}, false
	}
	stand_total := forest_stand_weights(term, on_sphere, &weights)
	species := forest_species_pick(weights, i64(generation_seed.hash_combine(hash, 4) % u64(max(stand_total, 1))))
	scale := term.species[species].scale_percent
	return planet_tree_at(cell, on_sphere, up, relief, hash, forest_scale_percent(generation_seed.hash_combine(hash, 3), scale[0], scale[1]), species), true
}

// The forest's density at a point of the sphere, a share of NOISE_ONE (the
// candidate's chance there without the draw and the gap), for the tests;
// land is false where no tree may stand (planet_tree_ground).
forest_density_at :: proc(generation: Planet_Generation, on_sphere: [3]i64) -> (density: i64, land: bool) {
	term := generation.trees
	relief, ground := planet_tree_ground(generation, on_sphere)
	if !ground {
		return 0, false
	}
	if !term.forest_on || planet_tree_in_clearing(term, on_sphere) {
		return 0, true
	}
	moisture := planet_moisture(generation, on_sphere)
	cover := forest_cover(term, on_sphere, moisture) * forest_meadow_share(term, on_sphere) / NOISE_ONE
	upper := max(cover, term.scatter) * term.forest_density / NOISE_ONE
	height := relief - (generation.sea_radius - generation.radius)
	_, total := species_climate_weights(term, planet_temperature(generation, on_sphere, height), moisture, height, cover)
	exact := upper * min(total / 100, NOISE_ONE) / NOISE_ONE
	up, _ := normalize_fixed(on_sphere)
	return exact * forest_slope_share(term, forest_slope_percent(generation, on_sphere, up, relief)) / NOISE_ONE, true
}

// The tree cubes from the one holding minimum to the one holding maximum,
// x outermost, then y, then z; the box is in position units on or near
// the sphere of the radius (callers project onto it). The forest's trees
// while it is on (0310), else the groves'. Nothing for the zero term.
// With the waters' tiles (0326) the cubes read a copy of the generation
// whose lakes are those that may hold a point of the cubes' box
// (generation_lakes_near_sphere_box) and whose tiles are nil, so
// planet_tree_ground reads one short list and the shared generation is
// never written.
planet_trees_in_box :: proc(generation: ^Planet_Generation, minimum, maximum: [3]i64, allocator := context.temp_allocator) -> [dynamic]Planet_Tree {
	trees := make([dynamic]Planet_Tree, allocator)
	term := generation.trees
	if term.spacing == 0 {
		return trees
	}
	groves: [][3]i64
	if !term.forest_on {
		groves = planet_groves_near(term, generation.radius, minimum, maximum)
		if len(groves) == 0 {
			return trees
		}
	}
	first, last: [3]i64
	for axis in 0 ..< 3 {
		first[axis] = floor_divide_i64(minimum[axis], term.spacing)
		last[axis] = floor_divide_i64(maximum[axis], term.spacing)
	}
	size := last - first + 1
	assert(size.x * size.y * size.z <= PLANET_TREE_BOX_CELL_LIMIT, "planet_trees_in_box: the box holds too many tree cubes")
	cubes := generation
	listed: Planet_Generation
	if generation.water_tiles != nil {
		listed = generation^
		listed.lakes = generation_lakes_near_sphere_box(generation^, first * term.spacing, (last + 1) * term.spacing)
		listed.water_tiles = nil
		cubes = &listed
	}
	for x in first.x ..= last.x {
		for y in first.y ..= last.y {
			for z in first.z ..= last.z {
				append_planet_tree(&trees, cubes, groves, {x, y, z})
			}
		}
	}
	return trees
}

// The cube's tree, when it has one: the forest's (0310) or the groves'.
append_planet_tree :: proc(trees: ^[dynamic]Planet_Tree, generation: ^Planet_Generation, groves: [][3]i64, cell: [3]i64) {
	term := generation.trees
	if !cube_straddles_sphere(cell * term.spacing, cell * term.spacing + term.spacing, generation.radius) {
		return
	}
	on_sphere, hash, ok := lattice_candidate(term.tree_seed, cell, term.spacing, generation.radius)
	if !ok {
		return
	}
	if term.forest_on {
		if tree, kept := forest_tree_from_candidate(generation^, cell, on_sphere, hash); kept {
			append(trees, tree)
		}
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
