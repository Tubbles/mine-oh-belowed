package game

import "generation_seed"
import "platform"

// Planet generation of the terrain field (work item 0168,
// doc/architecture.md, World generation): a pure function of the seed, the
// planet record, the sample spacing and the chunk coordinate, in integers
// and fixed point only, so every machine generates the same bytes. The
// surface is the radius plus value noise read at the sample's position
// projected onto the sphere of the radius (three dimensional, so no
// latitude and longitude and no pole). Strata go by depth below the local
// surface; bedrock starts at the planet's bedrock depth below the radius.
// The veins' outcrops replace the strata near the surface within their
// discs (0179, generation_planet_veins.odin).
// The relief's octaves are the planet record's (data/planets.sjson), at
// most MAXIMUM_RELIEF_METRES in all (data_planet.odin). The crater at the
// home (0199, crater_relief) is the relief's last term: its floor is
// clamped to at least -MAXIMUM_RELIEF_METRES and its result to at most
// +MAXIMUM_RELIEF_METRES, so the bound holds with it.

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
	// The trees on the sphere (0197, generation_planet_trees.odin).
	trees:               Planet_Tree_Term,
}

// The starter veins lie round the planet's home (the pod's, 0179,
// planet_home_direction).
make_planet_generation :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Planet_Generation {
	seeds := generation_seed.derive_purpose_seeds(seed)
	radius := metres_to_position_units(i64(planet.radius_metres))
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
	}
	generation.crater = make_crater_term(generation, planet.crater, planet_home_direction(planet.home))
	generation.trees = make_planet_tree_term(seed, planet.trees, planet.home, radius)
	return generation
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
		floor_height = max(uncratered_relief(generation, home) - depth, -metres_to_position_units(MAXIMUM_RELIEF_METRES)),
		floor_radius = metres_to_position_units(i64(crater.floor_radius_metres)),
		radius = metres_to_position_units(i64(crater.radius_metres)),
		reach = metres_to_position_units(i64(crater.radius_metres + CRATER_RIM_FALL_PER_HEIGHT * crater.rim_metres)),
		depth = depth,
		rim = metres_to_position_units(i64(crater.rim_metres)),
	}
}

// The floor of the square root, bit by bit.
integer_square_root :: proc(value: u64) -> u64 {
	remainder := value
	root: u64 = 0
	bit: u64 = 1 << 62
	for bit > value {
		bit >>= 2
	}
	for bit != 0 {
		if remainder >= root + bit {
			remainder -= root + bit
			root = (root >> 1) + bit
		} else {
			root >>= 1
		}
		bit >>= 2
	}
	return root
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

// The local surface's height above the radius at a point on the sphere:
// the shaped relief with the crater at the home (0199).
surface_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	return crater_relief(generation.crater, crater_distance(generation.crater, point), uncratered_relief(generation, point))
}

// The relief without the crater: the octaves, the first shaped by the
// basins and the terraces, and the ledges (0189, Relief_Shape). With the
// zero shape it is the octaves' sum.
uncratered_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	relief: i64 = 0
	for octave, index in generation.relief_octaves {
		noise := relief_octave_noise(generation, index, octave.wavelength_metres, point)
		if index == 0 {
			relief += long_octave_relief(noise, octave.amplitude_metres, generation.relief_shape)
		} else {
			relief += metres_to_position_units(i64(octave.amplitude_metres)) * noise / NOISE_ONE
		}
	}
	return relief + ledge_relief(generation, point)
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
// to the reach, the relief past it. At most +MAXIMUM_RELIEF_METRES.
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
	return min(result, metres_to_position_units(MAXIMUM_RELIEF_METRES))
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

planet_stratum :: proc(depth, distance, bedrock_radius: i64) -> Field_Material {
	switch {
	case distance <= bedrock_radius:
		return .Bedrock
	case depth < metres_to_position_units(TOPSOIL_DEPTH_METRES):
		return .Topsoil
	case depth < metres_to_position_units(DEEP_STONE_DEPTH_METRES):
		return .Stone
	}
	return .Deep_Stone
}

planet_tint :: proc(generation: Planet_Generation, position: World_Position) -> u8 {
	region_edge := metres_to_position_units(TINT_REGION_METRES)
	cell := [3]i64{floor_divide_i64(position.x, region_edge), floor_divide_i64(position.y, region_edge), floor_divide_i64(position.z, region_edge)}
	return u8(hash_lattice(generation.tint_seed, cell) % u64(generation.palette_length))
}

// Far outside and deep inside skip the noise: the local surface lies
// within MAXIMUM_RELIEF_METRES of the radius, and a density saturates one
// spacing from it.
planet_sample :: proc(generation: Planet_Generation, position: World_Position) -> Field_Sample {
	for axis in 0 ..< 3 {
		if abs(position[axis]) >= metres_to_position_units(FAR_LIMIT_METRES) {
			return FIELD_AIR_SAMPLE
		}
	}
	squared := position.x * position.x + position.y * position.y + position.z * position.z
	distance := i64(integer_square_root(u64(squared)))
	relief_reach := metres_to_position_units(MAXIMUM_RELIEF_METRES) + generation.spacing
	if distance >= generation.radius + relief_reach {
		return FIELD_AIR_SAMPLE
	}
	if distance < generation.radius - relief_reach - metres_to_position_units(DEEP_STONE_DEPTH_METRES) {
		material := distance <= generation.bedrock_radius ? Field_Material.Bedrock : Field_Material.Deep_Stone
		return {MAXIMUM_DENSITY, material, planet_tint(generation, position)}
	}
	on_sphere := project_onto_sphere(position, distance, generation.radius)
	surface := generation.radius + surface_relief(generation, on_sphere)
	depth := surface - distance
	density := depth_to_density(depth, generation.spacing_millimetres)
	if density <= 0 {
		return {density, .Air, 0}
	}
	material := planet_outcrop_material(generation.veins, planet_stratum(depth, distance, generation.bedrock_radius), depth, on_sphere)
	return {density, material, planet_tint(generation, position)}
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
// crosses partly, so the generated sea is level and settled.
fill_field_chunk_sea :: proc(planet: Planet, spacing_millimetres: int, chunk: ^Field_Chunk) {
	sea_level := field_sea_level(planet, spacing_millimetres)
	origin := field_chunk_origin(chunk.coordinate)
	if !field_chunk_reaches_below(origin, sea_level) {
		return
	}
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		if chunk.density[index] <= 0 {
			chunk.water[index] = u8(field_sea_fill(sea_level, field_water_span(origin + Sample_Coordinate(field_index_to_local(index)))))
		}
	}
}

// The spring's direction from the centre, a unit vector: latitude 90 is
// +y, longitude 0 lies towards +x and 90 towards +z.
planet_spring_direction :: proc(spring: Planet_Spring) -> [3]i64 {
	latitude := degrees_to_angle_units(spring.latitude_degrees)
	longitude := degrees_to_angle_units(spring.longitude_degrees)
	across := fixed_cosine(latitude)
	return {across * fixed_cosine(longitude) / UNIT_VECTOR_ONE, fixed_sine(latitude), across * fixed_sine(longitude) / UNIT_VECTOR_ONE}
}

// The first air sample above the surface under the spring, climbing from
// the local surface in quarter spacings up to the highest relief, the
// sample nearest each point; found is false when none is air, so a spring
// never becomes a source inside ground.
planet_spring_sample :: proc(generation: Planet_Generation, spring: Planet_Spring) -> (sample: Sample_Coordinate, found: bool) {
	direction := planet_spring_direction(spring)
	surface := generation.radius + surface_relief(generation, fixed_scale(direction, generation.radius))
	highest := generation.radius + metres_to_position_units(MAXIMUM_RELIEF_METRES) + generation.spacing
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

// The springs whose sample lies in the chunk become full, awake sources;
// a spring with no air above its surface is skipped with a log line.
mark_field_chunk_springs :: proc(generation: Planet_Generation, planet: Planet, chunk: ^Field_Chunk) {
	for spring in planet.springs {
		sample, found := planet_spring_sample(generation, spring)
		if !found {
			platform.log_printf("field: the spring at latitude %d, longitude %d has no air above its surface, skipped", spring.latitude_degrees, spring.longitude_degrees)
			continue
		}
		if sample_to_field_chunk_coordinate(sample) != chunk.coordinate {
			continue
		}
		index := sample_to_field_index(sample)
		chunk.water[index] = FIELD_WATER_FULL
		set_field_sample_bit(&chunk.water_source, index)
		set_field_sample_bit(&chunk.water_awake, index)
	}
}

// Fills chunk; safe on any thread. The chunk is not marked dirty, the
// world does that when it takes the chunk (field_world_insert_chunk). The
// water: the sea below the planet's sea level and the springs (0172); the
// light: full sky in every air sample (0173, light_generated_field_chunk).
generate_field_chunk :: proc(seed: u64, planet: Planet, spacing_millimetres: int, coordinate: Field_Chunk_Coordinate, chunk: ^Field_Chunk) {
	generation := make_planet_generation(seed, planet, spacing_millimetres)
	origin := field_chunk_origin(coordinate)
	chunk.coordinate = coordinate
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		sample := origin + Sample_Coordinate(field_index_to_local(index))
		value := planet_sample(generation, sample_to_world_position(sample, spacing_millimetres))
		chunk.density[index] = value.density
		chunk.material[index] = value.material
		chunk.tint[index] = value.tint
	}
	fill_field_chunk_sea(planet, spacing_millimetres, chunk)
	mark_field_chunk_springs(generation, planet, chunk)
	light_generated_field_chunk(chunk)
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
