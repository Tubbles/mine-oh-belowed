package game

import "base:intrinsics"
import "generation_seed"
import "platform"

// Planet generation of the terrain field (work item 0168,
// doc/architecture.md, World generation): a pure function of the seed, the
// planet record, the sample spacing and the chunk coordinate, in integers
// and fixed point only, so every machine generates the same bytes. The
// surface is the radius plus value noise read at the sample's position
// projected onto the sphere of the radius (three dimensional, so no
// latitude and longitude and no pole). Strata go by depth below the local
// surface, the topsoil at least two of the generation's spacings deep
// (generation_topsoil_depth); bedrock starts at the planet's bedrock depth
// below the radius.
// The veins' outcrops replace the strata near the surface within their
// discs (0179, generation_planet_veins.odin).
// The relief's octaves are the planet record's (data/planets.sjson), at
// most OCTAVE_RELIEF_LIMIT_METRES in all (data_planet.odin), and its
// landforms (0306, generation_planet_landforms.odin) add the plains, the
// hills and the ranges, its landmarks (0323,
// generation_planet_landmarks.odin) the gorges, the mesas and the sites.
// A carving site's column (0324, Surface_Column) carves air between its
// ground and the height map's top (column_depth).
// The relief lies within the planet's bound
// (planet_relief_bounds), which the generation holds as relief_lowest and
// relief_highest. The crater at the home (0199, crater_relief) is the
// relief's last term: its floor is clamped to at least the bound's lowest
// and its result to at most its highest, so the bound holds with it. A
// world whose
// arrival digs the crater (0271, Planet.crater_at_impact) generates
// without the term (crater_baked false); the hit writes the baked
// generation into the field (dig_impact_crater).
// The waters (0312, generation_planet_waters.odin) fill the lakes beside
// the sea and add the derived springs beside the record's, read from the
// tiles over the whole planet (0326, generation_planet_water_tiles.odin)
// or, without them, from the features round the home.
// The chunks and the grids read no column for a sample the relief's range
// over its box of samples decides (0314, generation_planet_bound.odin),
// which gets the bytes its column would give.

TOPSOIL_DEPTH_METRES :: 2
DEEP_STONE_DEPTH_METRES :: 40
// The tint is one palette entry per cube of this edge.
TINT_REGION_METRES :: 256
// Samples farther out on any axis are air, which keeps the squared
// distance inside i64. Chunk coordinates are reachable up to about 2^26
// (field_chunk_origin multiplies the i32 by FIELD_CHUNK_SIZE); a planet
// within MAXIMUM_PLANET_RADIUS_METRES needs at most a few thousand.
FAR_LIMIT_METRES :: 2 * MAXIMUM_PLANET_RADIUS_METRES
// Fixed point one of the noise: values and fractions in 1/NOISE_ONE.
NOISE_ONE :: 65536
// Fixed point one of the crater's profile (crater_relief).
CRATER_ONE :: 65536

// The crater of a generation (work item 0199), lengths in position units:
// the home on the sphere, the floor's height above the radius, the
// floor's radius, the crest's radius, the reach of the rim's fall, the
// depth and the rim's height. Zero reach is no crater.
Crater_Term :: struct {
	home:         [3]i64,
	floor_height: i64,
	floor_radius: i64,
	radius:       i64,
	reach:        i64,
	depth:        i64,
	rim:          i64,
	// The relief bound's highest (0306), which the result stays under.
	ceiling:      i64,
}

// What every sample of one generation reads, in position units.
Planet_Generation :: struct {
	surface_seed:        u64,
	tint_seed:           u64,
	radius:              i64,
	bedrock_radius:      i64,
	spacing_millimetres: int,
	spacing:             i64,
	palette_length:      int,
	// The sea's surface, the radius plus the sea level (0172).
	sea_radius:          i64,
	relief_octaves:      [RELIEF_OCTAVE_COUNT]Relief_Octave,
	relief_shape:        Relief_Shape,
	// The veins' discs round the home (0179, generation_planet_veins.odin).
	veins:               Planet_Veins,
	// The crater at the home (0199, make_crater_term).
	crater:              Crater_Term,
	// Whether the relief holds the crater: false for a world whose
	// arrival's hit digs it (0271, baked_planet_generation).
	crater_baked:        bool,
	// The trees on the sphere (0197, generation_planet_trees.odin).
	trees:               Planet_Tree_Term,
	// The landforms (0306, generation_planet_landforms.odin): off at the
	// zero value; their seed and their centre, the home on the sphere.
	landforms:           Planet_Landforms,
	landform_seed:       u64,
	landform_home:       [3]i64,
	// The landmarks (0323, generation_planet_landmarks.odin): off at the
	// zero value; their seed. Their centre is the landforms'.
	landmarks:           Planet_Landmarks,
	landmark_seed:       u64,
	// The relief's bound from the radius (planet_relief_bounds).
	relief_lowest:       i64,
	relief_highest:      i64,
	// The climate's field (0307, generation_planet_climate.odin), off at
	// the zero value, and its seed; the ground look's seed
	// (world_field_ground_look.odin).
	climate:             Planet_Climate_Field,
	climate_seed:        u64,
	ground_look_seed:    u64,
	// The lakes (0312, generation_planet_waters.odin), borrowed from the
	// planet's water features; none without them.
	lakes:               []Planet_Lake,
	// The waters' tiles (0326), borrowed from the planet; nil without
	// them, whose lakes are the slice above.
	water_tiles:         ^Water_Tile_Cache,
}

// The starter veins lie round the planet's home (the pod's, 0179,
// planet_home_direction).
make_planet_generation :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Planet_Generation {
	seeds := generation_seed.derive_purpose_seeds(seed)
	radius := metres_to_position_units(i64(planet.radius_metres))
	bounds := planet_relief_bounds(planet)
	generation := Planet_Generation {
		surface_seed = seeds[.Planet_Surface],
		tint_seed = seeds[.Planet_Tint],
		radius = radius,
		bedrock_radius = metres_to_position_units(i64(planet.radius_metres - planet.bedrock_depth_metres)),
		spacing_millimetres = spacing_millimetres,
		spacing = sample_axis_to_position(1, spacing_millimetres),
		palette_length = len(planet.palette),
		sea_radius = metres_to_position_units(i64(planet.radius_metres + planet.sea_level_metres)),
		relief_octaves = planet.relief_octaves,
		relief_shape = planet.relief_shape,
		veins = plan_planet_veins(seed, planet_home_direction(planet.home), radius),
		crater_baked = !planet.crater_at_impact,
		landforms = planet.landforms,
		landform_seed = seeds[.Planet_Landforms],
		landform_home = fixed_scale(planet_home_direction(planet.home), radius),
		landmarks = planet.landmarks,
		landmark_seed = seeds[.Planet_Landmarks],
		relief_lowest = bounds.lowest,
		relief_highest = bounds.highest,
		climate = planet_climate_field(planet.climate),
		climate_seed = seeds[.Planet_Climate],
		ground_look_seed = seeds[.Planet_Ground_Look],
		lakes = planet.water_features.lakes,
		water_tiles = planet.water_tiles,
	}
	generation.crater = make_crater_term(generation, planet.crater, planet_home_direction(planet.home))
	generation.trees = make_planet_tree_term(seed, planet.trees, planet.home, radius)
	return generation
}

// The generation with its crater: the ground as it stands once the hit
// has dug it (0271).
baked_planet_generation :: proc(generation: Planet_Generation) -> Planet_Generation {
	baked := generation
	baked.crater_baked = true
	return baked
}

// The crater's term at the home direction, its floor read off the
// uncratered relief there (one relief evaluation per generation).
make_crater_term :: proc(generation: Planet_Generation, crater: Planet_Crater, home_direction: [3]i64) -> Crater_Term {
	if crater == {} {
		return {}
	}
	home := fixed_scale(home_direction, generation.radius)
	depth := metres_to_position_units(i64(crater.depth_metres))
	return Crater_Term {
		home = home,
		floor_height = max(uncratered_relief(generation, home) - depth, generation.relief_lowest),
		floor_radius = metres_to_position_units(i64(crater.floor_radius_metres)),
		radius = metres_to_position_units(i64(crater.radius_metres)),
		reach = metres_to_position_units(i64(crater.radius_metres + CRATER_RIM_FALL_PER_HEIGHT * crater.rim_metres)),
		depth = depth,
		rim = metres_to_position_units(i64(crater.rim_metres)),
		ceiling = generation.relief_highest,
	}
}

// The floor of the square root, by Newton's method in integers from a
// power of two at or above the root, which falls to the floor in a few
// steps (the water's look takes one a sample of every full resolution
// grid, 0294).
integer_square_root :: proc(value: u64) -> u64 {
	if value < 2 {
		return value
	}
	root := u64(1) << ((64 - intrinsics.count_leading_zeros(value) + 1) / 2)
	for {
		next := (root + value / root) / 2
		if next >= root {
			return root
		}
		root = next
	}
}

hash_lattice :: proc(seed: u64, cell: [3]i64) -> u64 {
	return generation_seed.hash_combine(generation_seed.hash_combine(seed, u64(cell.x)), generation_seed.pack_pair(i32(cell.y), i32(cell.z)))
}

// From -NOISE_ONE to NOISE_ONE - 1, from the top 17 bits.
lattice_value :: proc(seed: u64, cell: [3]i64) -> i64 {
	return i64(hash_lattice(seed, cell) >> 47) - NOISE_ONE
}

// Smoothstep of a fraction in 0 to NOISE_ONE.
noise_fade :: proc(fraction: i64) -> i64 {
	return fraction * fraction / NOISE_ONE * (3 * NOISE_ONE - 2 * fraction) / NOISE_ONE
}

noise_interpolate :: proc(first, second, fraction: i64) -> i64 {
	return first + (second - first) * fraction / NOISE_ONE
}

// Trilinear value noise of one octave, from -NOISE_ONE to NOISE_ONE.
value_noise :: proc(seed: u64, point: [3]i64, wavelength: i64) -> i64 {
	cell, fraction: [3]i64
	for axis in 0 ..< 3 {
		cell[axis] = floor_divide_i64(point[axis], wavelength)
		fraction[axis] = noise_fade((point[axis] - cell[axis] * wavelength) * NOISE_ONE / wavelength)
	}
	corners: [8]i64
	for &corner, index in corners {
		corner = lattice_value(seed, cell + {i64(index & 1), i64(index >> 1 & 1), i64(index >> 2)})
	}
	for axis in 0 ..< 3 {
		width := 8 >> uint(axis + 1)
		for index in 0 ..< width {
			corners[index] = noise_interpolate(corners[2 * index], corners[2 * index + 1], fraction[axis])
		}
	}
	return corners[0]
}

// A column of the ground at a point on the sphere (0324): the height
// map's top over the radius and the carve of the carving site it lies in
// (kind None elsewhere).
Surface_Column :: struct {
	relief: i64,
	carve:  Landmark_Carve,
}

// The local surface's height above the radius at a point on the sphere:
// the shaped relief with the crater at the home (0199) when the
// generation bakes it (crater_baked, 0271).
surface_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	return surface_column(generation, point).relief
}

// The column at a point on the sphere, its relief through the crater
// when the generation bakes it. No carving site reaches the crater: a
// site keeps the calm circle plus its reach from the home, and the calm
// circle holds the crater (landforms_planet_problem).
surface_column :: proc(generation: Planet_Generation, point: [3]i64) -> Surface_Column {
	column := uncratered_column(generation, point)
	if generation.crater_baked {
		column.relief = crater_relief(generation.crater, crater_distance(generation.crater, point), column.relief)
	}
	return column
}

// The relief without the crater (uncratered_column).
uncratered_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	return uncratered_column(generation, point).relief
}

// The column without the crater: the octaves, the first shaped by the
// basins and the terraces, the ledges (0189, Relief_Shape), the
// landforms (0306) and last the landmarks (0323), which raise and cut
// that sum and carve under a carving site's raise (0324). With the zero
// shape, no landforms and no landmarks it is the octaves' sum.
uncratered_column :: proc(generation: Planet_Generation, point: [3]i64) -> Surface_Column {
	relief: i64 = 0
	for octave, index in generation.relief_octaves {
		noise := relief_octave_noise(generation, index, octave.wavelength_metres, point)
		if index == 0 {
			relief += long_octave_relief(noise, octave.amplitude_metres, generation.relief_shape)
		} else {
			relief += metres_to_position_units(i64(octave.amplitude_metres)) * noise / NOISE_ONE
		}
	}
	reading := landform_reading(generation, point)
	column: Surface_Column
	column.relief, column.carve = landmark_relief(generation, point, relief + ledge_relief(generation, point) + reading.relief, reading)
	return column
}

// The depth into the ground at a height over the radius in the column:
// the height map's depth, with a carving site the least of it and the
// carve's distance over the site's ground, so nothing under the ground
// and nothing over the top is carved.
column_depth :: proc(column: Surface_Column, height: i64) -> i64 {
	depth := column.relief - height
	if column.carve.site.kind in CARVING_KINDS {
		depth = min(depth, landmark_carve_distance(column.carve, height - column.carve.ground))
	}
	return depth
}

// Whether ground at least a spacing thick stands over the column's
// carved span: the carved air in a column is one span from the ground up
// (landmark_carve_distance), so ground a spacing under the top closes it.
column_roofed :: proc(column: Surface_Column, spacing: i64) -> bool {
	if column.carve.site.kind not_in CARVING_KINDS {
		return false
	}
	roof := column.relief - column.carve.ground - spacing
	return roof > 0 && landmark_carve_distance(column.carve, roof) > 0
}

// Whether the height over the radius lies in the column's carved air
// under a roof, so the generation gives it no sky. The caller checks the
// sample is air.
column_shades :: proc(column: Surface_Column, height, spacing: i64) -> bool {
	if column.carve.site.kind not_in CARVING_KINDS {
		return false
	}
	return landmark_carve_distance(column.carve, height - column.carve.ground) <= 0 && column_roofed(column, spacing)
}

// Whether the height over the radius lies in the column's carved air: the
// height map alone makes it ground and the carve air (0324), which a lake
// leaves dry (0312). The caller checks the sample is air.
column_carves :: proc(column: Surface_Column, height: i64, spacing_millimetres: int) -> bool {
	return column.carve.site.kind in CARVING_KINDS && depth_to_density(column.relief - height, spacing_millimetres) > 0
}

// The ledges' noise takes the seed after the octaves'.
relief_octave_noise :: proc(generation: Planet_Generation, index, wavelength_metres: int, point: [3]i64) -> i64 {
	return value_noise(generation_seed.hash_combine(generation.surface_seed, u64(index)), point, metres_to_position_units(i64(wavelength_metres)))
}

// The first octave with the basins added and then terraced, within its
// amplitude above and its amplitude and the basins' depth below.
long_octave_relief :: proc(noise: i64, amplitude_metres: int, shape: Relief_Shape) -> i64 {
	amplitude := metres_to_position_units(i64(amplitude_metres))
	height := amplitude * noise / NOISE_ONE + basin_relief(noise, shape)
	lowest := -amplitude - metres_to_position_units(i64(shape.basin_depth_metres))
	return clamp(terrace_height(height, shape), lowest, amplitude)
}

// Zero at and above the threshold, down to the depth where the noise is
// lowest, growing with the square of the share below the threshold, so a
// basin's rim leaves the ground without a crease.
basin_relief :: proc(noise: i64, shape: Relief_Shape) -> i64 {
	threshold := i64(shape.basin_threshold_percent) * NOISE_ONE / 100
	if shape.basin_depth_metres == 0 || noise >= threshold {
		return 0
	}
	share := min((threshold - noise) * NOISE_ONE / (threshold + NOISE_ONE), NOISE_ONE)
	return -metres_to_position_units(i64(shape.basin_depth_metres)) * share / NOISE_ONE * share / NOISE_ONE
}

// Steps of the rise: within each, a flat tread for all but the riser's
// share of the span, then the riser climbing the whole rise.
terrace_height :: proc(height: i64, shape: Relief_Shape) -> i64 {
	if shape.terrace_rise_millimetres == 0 {
		return height
	}
	rise := millimetres_to_position_units(shape.terrace_rise_millimetres)
	step := floor_divide_i64(height, rise)
	within := height - step * rise
	tread := rise * i64(1000 - shape.terrace_riser_permille) / 1000
	climbed := within > tread ? (within - tread) * rise / (rise - tread) : 0
	return step * rise + climbed
}

// The ledge's profile across the noise's zero, from -NOISE_ONE to
// NOISE_ONE: 1 - (1 - |noise|) raised to the sharpness, with the noise's
// sign. Steepest at the zero (the sharpness times the noise's slope) and
// flat towards either side, so the ground steps once along each zero
// line, the sharper the narrower the step.
ledge_profile :: proc(noise: i64, sharpness: int) -> i64 {
	shaped := fixed_power(NOISE_ONE - abs(noise), sharpness)
	return noise < 0 ? shaped - NOISE_ONE : NOISE_ONE - shaped
}

// A fraction in 0 to NOISE_ONE raised to the exponent, by squaring.
fixed_power :: proc(fraction: i64, exponent: int) -> i64 {
	result: i64 = NOISE_ONE
	base := fraction
	for remaining := exponent; remaining > 0; remaining >>= 1 {
		if remaining & 1 != 0 {
			result = result * base / NOISE_ONE
		}
		base = base * base / NOISE_ONE
	}
	return result
}

// The chord from the crater's home to the point on the sphere, in
// position units; past the reach it is reach + 1 without a root, which
// every sample but the few round the home takes.
crater_distance :: proc(term: Crater_Term, point: [3]i64) -> i64 {
	offset := point - term.home
	squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
	if squared > term.reach * term.reach {
		return term.reach + 1
	}
	return i64(integer_square_root(u64(squared)))
}

// Smoothstep of a fraction clamped to 0 to CRATER_ONE: zero slope at both
// ends.
crater_smoothstep :: proc(fraction: i64) -> i64 {
	clamped := clamp(fraction, 0, CRATER_ONE)
	return clamped * clamped * (3 * CRATER_ONE - 2 * clamped) / (CRATER_ONE * CRATER_ONE)
}

// The relief with the crater at the distance from its home: the floor's
// height out to the floor radius, a smooth blend of it into the relief
// plus the rim out to the crest, the rim falling back to the relief out
// to the reach, the relief past it. At most the term's ceiling, the
// relief bound's highest.
crater_relief :: proc(term: Crater_Term, distance, relief: i64) -> i64 {
	if term.reach == 0 || distance >= term.reach {
		return relief
	}
	result: i64
	if distance <= term.radius {
		share := crater_smoothstep((distance - term.floor_radius) * CRATER_ONE / (term.radius - term.floor_radius))
		result = relief + (CRATER_ONE - share) * (term.floor_height - relief) / CRATER_ONE + term.rim * share / CRATER_ONE
	} else {
		share := crater_smoothstep((distance - term.radius) * CRATER_ONE / (term.reach - term.radius))
		result = relief + term.rim * (CRATER_ONE - share) / CRATER_ONE
	}
	return min(result, term.ceiling)
}

// Within the ledge's amplitude either side; no noise is read while it is
// off.
ledge_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	shape := generation.relief_shape
	if shape.ledge_amplitude_millimetres == 0 {
		return 0
	}
	noise := relief_octave_noise(generation, RELIEF_OCTAVE_COUNT, shape.ledge_wavelength_metres, point)
	return millimetres_to_position_units(shape.ledge_amplitude_millimetres) * ledge_profile(noise, shape.ledge_sharpness) / NOISE_ONE
}

// The position scaled onto the sphere of the radius.
project_onto_sphere :: proc(position: World_Position, distance, radius: i64) -> [3]i64 {
	point: [3]i64
	for axis in 0 ..< 3 {
		point[axis] = position[axis] * radius / max(distance, 1)
	}
	return point
}

// Depth in position units into density steps, clamped into the byte.
depth_to_density :: proc(depth: i64, spacing_millimetres: int) -> i8 {
	steps := floor_divide_i64(depth * DENSITY_STEPS_PER_SAMPLE * MILLIMETRES_PER_METRE, i64(spacing_millimetres) * POSITION_UNITS_PER_METRE)
	return i8(clamp(steps, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

planet_stratum :: proc(depth, distance, bedrock_radius, topsoil_depth: i64) -> Field_Material {
	switch {
	case distance <= bedrock_radius:
		return .Bedrock
	case depth < topsoil_depth:
		return .Topsoil
	case depth < metres_to_position_units(DEEP_STONE_DEPTH_METRES):
		return .Stone
	}
	return .Deep_Stone
}

// The topsoil's depth below the local surface in the generation's
// spacing: TOPSOIL_DEPTH_METRES, or two spacings of a coarse grid wider
// than a metre (0322), so a coarse surface cell's ground corners read
// topsoil as the finest grid's do instead of the stone under it, which
// striped the far ground along the contours.
generation_topsoil_depth :: proc(generation: Planet_Generation) -> i64 {
	return max(metres_to_position_units(TOPSOIL_DEPTH_METRES), 2 * generation.spacing)
}

planet_tint :: proc(generation: Planet_Generation, position: World_Position) -> u8 {
	region_edge := metres_to_position_units(TINT_REGION_METRES)
	cell := [3]i64{floor_divide_i64(position.x, region_edge), floor_divide_i64(position.y, region_edge), floor_divide_i64(position.z, region_edge)}
	return u8(hash_lattice(generation.tint_seed, cell) % u64(generation.palette_length))
}

planet_sample :: proc(generation: Planet_Generation, position: World_Position) -> Field_Sample {
	sample, _ := planet_sample_shaded(generation, position)
	return sample
}

// The sample at the position and whether it is carved air under a roof
// (column_shades), which the generation leaves without sky (0324).
planet_sample_shaded :: proc(generation: Planet_Generation, position: World_Position) -> (sample: Field_Sample, shaded: bool) {
	sample, shaded, _ = planet_sample_reading(generation, position)
	return
}

// The sample at the position, whether it is carved air under a roof
// (column_shades) and whether it is carved air at all (column_carves),
// which a lake leaves dry (0312).
planet_sample_reading :: proc(generation: Planet_Generation, position: World_Position) -> (sample: Field_Sample, shaded, carved: bool) {
	shortcut, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
	if !needs_relief {
		return shortcut, false, false
	}
	return planet_sample_reading_at(generation, position, distance, on_sphere)
}

// planet_sample_reading past the shortcut, from its distance and its
// point on the sphere: the column's sample.
planet_sample_reading_at :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64) -> (sample: Field_Sample, shaded, carved: bool) {
	column := surface_column(generation, on_sphere)
	sample = planet_sample_at_column(generation, position, distance, on_sphere, column)
	if sample.density <= 0 {
		height := distance - generation.radius
		shaded = column_shades(column, height, generation.spacing)
		carved = column_carves(column, height, generation.spacing_millimetres)
	}
	return
}

// Far outside and deep inside skip the noise: the local surface lies
// within the planet's relief bound (relief_lowest to relief_highest from
// the radius), and a density saturates one spacing from it. Otherwise needs_relief, with the distance from the
// centre and the position projected onto the sphere.
planet_sample_shortcut :: proc(generation: Planet_Generation, position: World_Position) -> (sample: Field_Sample, distance: i64, on_sphere: [3]i64, needs_relief: bool) {
	for axis in 0 ..< 3 {
		if abs(position[axis]) >= metres_to_position_units(FAR_LIMIT_METRES) {
			return FIELD_AIR_SAMPLE, 0, {}, false
		}
	}
	squared := position.x * position.x + position.y * position.y + position.z * position.z
	distance = i64(integer_square_root(u64(squared)))
	if distance >= generation.radius + generation.relief_highest + generation.spacing {
		return FIELD_AIR_SAMPLE, distance, {}, false
	}
	if distance < generation.radius + generation.relief_lowest - generation.spacing - metres_to_position_units(DEEP_STONE_DEPTH_METRES) {
		material := distance <= generation.bedrock_radius ? Field_Material.Bedrock : Field_Material.Deep_Stone
		return {MAXIMUM_DENSITY, material, planet_tint(generation, position)}, distance, {}, false
	}
	return {}, distance, project_onto_sphere(position, distance, generation.radius), true
}

// The sample at the position whose surface stands relief above the
// radius, without a carve (the crater's baked sample).
planet_sample_at_relief :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64, relief: i64) -> Field_Sample {
	return planet_sample_at_column(generation, position, distance, on_sphere, Surface_Column{relief = relief})
}

// The sample at the position in the column: the density from the
// column's depth (column_depth), the stratum and the outcrop from the
// height map's depth, so a carved face shows the stone it was cut from
// and only the top keeps its topsoil, the tint.
planet_sample_at_column :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64, column: Surface_Column) -> Field_Sample {
	height := distance - generation.radius
	density := depth_to_density(column_depth(column, height), generation.spacing_millimetres)
	if density <= 0 {
		return {density, .Air, 0}
	}
	depth := column.relief - height
	material := planet_outcrop_material(generation.veins, planet_stratum(depth, distance, generation.bedrock_radius, generation_topsoil_depth(generation)), depth, on_sphere)
	return {density, material, planet_tint(generation, position)}
}

// The baked generation's sample beside a whole one computed from the
// relief without the crater (0271) and whether the two differ: false at
// or past the crater's reach. No second projection or relief.
impact_crater_baked_sample :: proc(generation: Planet_Generation, position: World_Position, distance: i64, on_sphere: [3]i64, relief: i64, whole: Field_Sample) -> (baked: Field_Sample, changed: bool) {
	term := generation.crater
	from_home := crater_distance(term, on_sphere)
	if term.reach == 0 || from_home >= term.reach {
		return whole, false
	}
	baked = planet_sample_at_relief(generation, position, distance, on_sphere, crater_relief(term, from_home, relief))
	return baked, baked != whole
}

// The baked generation's sample at the position and whether it differs
// from the whole one (impact_crater_baked_sample); false past the
// shortcut. The tests name the changed samples with it.
impact_crater_sample :: proc(generation: Planet_Generation, position: World_Position) -> (baked: Field_Sample, changed: bool) {
	whole, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
	if !needs_relief {
		return whole, false
	}
	relief := uncratered_relief(generation, on_sphere)
	return impact_crater_baked_sample(generation, position, distance, on_sphere, relief, planet_sample_at_relief(generation, position, distance, on_sphere, relief))
}

// Whether any sample of the chunk can hold sea: the nearest sample to
// the centre lies within a cell's half height of the sea level.
field_chunk_reaches_below :: proc(origin: Sample_Coordinate, sea_level: i64) -> bool {
	squared: i64 = 0
	for axis in 0 ..< 3 {
		nearest := i64(clamp(0, origin[axis], origin[axis] + FIELD_CHUNK_SIZE - 1))
		squared += nearest * nearest
	}
	reach := sea_level / FIELD_WATER_FULL + 2
	return squared < reach * reach
}

// Every sample below the sea level that is not ground holds the sea's
// fill (field_sea_fill), asleep: full below, the cells the sea level
// crosses partly, so the generated sea is level and settled. Each is the
// sea's (WATER_OWNER_SEA, the bodies model's body 0, 0293) under either
// model, so a pristine coastal chunk equals its generation.
fill_field_chunk_sea :: proc(planet: Planet, spacing_millimetres: int, chunk: ^Field_Chunk) {
	sea_level := field_sea_level(planet, spacing_millimetres)
	origin := field_chunk_origin(chunk.coordinate)
	if !field_chunk_reaches_below(origin, sea_level) {
		return
	}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.density[index] <= 0 {
			fill := field_sea_fill(sea_level, field_water_span(origin + Sample_Coordinate(field_index_to_local(index))))
			chunk.water[index] = u8(fill)
			if fill > 0 {
				chunk.water_owner[index] = WATER_OWNER_SEA
			}
		}
	}
}

// The spring's direction from the centre, a unit vector: latitude 90 is
// +y, longitude 0 lies towards +x and 90 towards +z.
planet_spring_direction :: proc(spring: Planet_Spring) -> [3]i64 {
	return planet_direction_at(degrees_to_angle_units(spring.latitude_degrees), degrees_to_angle_units(spring.longitude_degrees))
}

// The unit direction from the centre at a latitude and longitude in
// ANGLE_UNITS_PER_TURN, laid out as planet_spring_direction's (the
// command socket's surface teleport, 0183).
planet_direction_at :: proc(latitude, longitude: i32) -> [3]i64 {
	across := fixed_cosine(latitude)
	return {across * fixed_cosine(longitude) / UNIT_VECTOR_ONE, fixed_sine(latitude), across * fixed_sine(longitude) / UNIT_VECTOR_ONE}
}

// The first air sample above the surface under the spring, climbing from
// the local surface in quarter spacings up to the highest relief, the
// sample nearest each point; found is false when none is air, so a spring
// never becomes a source inside ground.
planet_spring_sample :: proc(generation: Planet_Generation, spring: Planet_Spring) -> (sample: Sample_Coordinate, found: bool) {
	return planet_spring_sample_at(generation, planet_spring_direction(spring))
}

// planet_spring_sample at a unit direction: a record's spring or a derived
// one (0312).
planet_spring_sample_at :: proc(generation: Planet_Generation, direction: [3]i64) -> (sample: Sample_Coordinate, found: bool) {
	surface := generation.radius + surface_relief(generation, fixed_scale(direction, generation.radius))
	highest := generation.radius + generation.relief_highest + generation.spacing
	half := generation.spacing / 2
	for height := surface; height <= highest; height += generation.spacing / 4 {
		point := World_Position(fixed_scale(direction, height))
		sample = world_position_to_sample(point + {half, half, half}, generation.spacing_millimetres)
		if planet_sample(generation, sample_to_world_position(sample, generation.spacing_millimetres)).density <= 0 {
			return sample, true
		}
	}
	return {}, false
}

// The springs whose sample lies in the chunk become full, awake sources:
// the record's, a spring with no air above its surface skipped with a log
// line, then the derived ones (0312, the tiles' near the chunk with them,
// 0326) whose radial passes near the chunk
// (planet_spring_may_lie_in_chunk), one without air skipped quietly.
mark_field_chunk_springs :: proc(generation: Planet_Generation, planet: Planet, chunk: ^Field_Chunk) {
	for spring in planet.springs {
		sample, found := planet_spring_sample(generation, spring)
		if !found {
			platform.log_printf("field: the spring at latitude %d, longitude %d has no air above its surface, skipped", spring.latitude_degrees, spring.longitude_degrees)
			continue
		}
		mark_field_chunk_spring(chunk, sample)
	}
	for spring in planet_derived_springs_near_chunk(generation, planet, chunk.coordinate) {
		if !planet_spring_may_lie_in_chunk(generation, spring.direction, chunk.coordinate) {
			continue
		}
		if sample, found := planet_spring_sample_at(generation, spring.direction); found {
			mark_field_chunk_spring(chunk, sample)
		}
	}
}

// The sample, when the chunk holds it, a full, awake source.
mark_field_chunk_spring :: proc(chunk: ^Field_Chunk, sample: Sample_Coordinate) {
	if sample_to_field_chunk_coordinate(sample) != chunk.coordinate {
		return
	}
	index := sample_to_field_index(sample)
	chunk.water[index] = FIELD_WATER_FULL
	set_field_sample_bit(&chunk.water_source, index)
	set_field_sample_bit(&chunk.water_awake, index)
}

// Fills chunk; safe on any thread. The chunk is not marked dirty, the
// world does that when it takes the chunk (field_world_insert_chunk). The
// water: the sea below the planet's sea level, the lakes (0312,
// fill_field_chunk_lakes, carved air under their level left dry), and the
// record's and the derived springs (0172, 0312); the
// light: full sky in every air sample (0173, light_generated_field_chunk)
// but carved air under a roof (0324, column_shades), which arrives
// without sky and is lit by the fill from the chunk's lit air
// (Field_Chunk.generated_shade).
// With crater_overlay, a chunk of the simulated set (the workers', the
// staged set's) of a world whose hit digs the crater, its box meeting the
// crater's cylinder (impact_crater_reaches_box), also records the baked
// sample wherever it differs from the whole one (0271,
// Field_Chunk.crater_overlay), from the same projection and relief.
// A sample the relief's range over its box decides (0314,
// planet_sample_by_boxes) reads no column: it is ground or open air the
// crater does not reach, so it has no shade, no carve and no overlay.
generate_field_chunk :: proc(seed: u64, planet: Planet, spacing_millimetres: int, coordinate: Field_Chunk_Coordinate, chunk: ^Field_Chunk, crater_overlay := false) {
	generation := make_planet_generation(seed, planet, spacing_millimetres)
	origin := field_chunk_origin(coordinate)
	chunk.coordinate = coordinate
	overlay := crater_overlay && planet.crater_at_impact && impact_crater_reaches_box(generation, field_node_box(field_chunk_node(coordinate), spacing_millimetres))
	shaded, carved: Field_Sample_Bits
	boxes := Relief_Boxes {
		first               = origin,
		step                = 1,
		samples             = FIELD_CHUNK_SIZE,
		spacing_millimetres = spacing_millimetres,
	}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		sample := origin + Sample_Coordinate(field_index_to_local(index))
		position := sample_to_world_position(sample, spacing_millimetres)
		value, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
		decided := false
		if needs_relief {
			value, decided = planet_sample_by_boxes(generation, &boxes, field_index_to_local(index), position, distance)
		}
		if needs_relief && !decided {
			column := surface_column(generation, on_sphere)
			value = planet_sample_at_column(generation, position, distance, on_sphere, column)
			if value.density <= 0 && column_shades(column, distance - generation.radius, generation.spacing) {
				set_field_sample_bit(&shaded, index)
			}
			if value.density <= 0 && column_carves(column, distance - generation.radius, spacing_millimetres) {
				set_field_sample_bit(&carved, index)
			}
			if overlay {
				if baked, changed := impact_crater_baked_sample(generation, position, distance, on_sphere, column.relief, value); changed {
					append(&chunk.crater_overlay, Field_Crater_Sample{index = i32(index), sample = baked})
				}
			}
		}
		chunk.density[index] = value.density
		chunk.material[index] = value.material
		chunk.tint[index] = value.tint
	}
	fill_field_chunk_sea(planet, spacing_millimetres, chunk)
	fill_field_chunk_lakes(generation, chunk, &carved)
	mark_field_chunk_springs(generation, planet, chunk)
	light_generated_field_chunk(chunk)
	chunk.generated_shade = field_sample_bits_any(&shaded)
	if chunk.generated_shade {
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if field_sample_bit(&shaded, index) {
				chunk.sky_light[index] = 0
			}
		}
	}
}

// The sea's density in the generation's spacing at a position, as the
// terrain's: positive below the sea's surface (sea_radius, where the fine
// water mesh crosses too, field_sea_fill), -MAXIMUM_DENSITY in ground, so
// a coarse grid shows the sea between its samples at the fine sea's
// height.
planet_sea_density :: proc(generation: Planet_Generation, position: World_Position, terrain: i8) -> i8 {
	if terrain > 0 {
		return -MAXIMUM_DENSITY
	}
	squared := position.x * position.x + position.y * position.y + position.z * position.z
	return depth_to_density(generation.sea_radius - i64(integer_square_root(u64(squared))), generation.spacing_millimetres)
}
