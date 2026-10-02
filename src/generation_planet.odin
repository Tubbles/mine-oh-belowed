package game

import "generation_seed"

// Planet generation of the terrain field (work item 0168,
// doc/architecture.md, World generation): a pure function of the seed, the
// planet record, the sample spacing and the chunk coordinate, in integers
// and fixed point only, so every machine generates the same bytes. The
// surface is the radius plus value noise read at the sample's position
// projected onto the sphere of the radius (three dimensional, so no
// latitude and longitude and no pole). Strata go by depth below the local
// surface; bedrock starts at the planet's bedrock depth below the radius.

Relief_Octave :: struct {
	wavelength_metres: i64,
	amplitude_metres:  i64,
}

RELIEF_OCTAVES :: [3]Relief_Octave{{512, 24}, {128, 8}, {32, 2}}
// The sum of the octaves' amplitudes: the local surface lies within this
// of the radius.
MAXIMUM_RELIEF_METRES :: RELIEF_OCTAVES[0].amplitude_metres + RELIEF_OCTAVES[1].amplitude_metres + RELIEF_OCTAVES[2].amplitude_metres
#assert(len(RELIEF_OCTAVES) == 3, "MAXIMUM_RELIEF_METRES sums every octave")
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

// What every sample of one generation reads, in position units.
Planet_Generation :: struct {
	surface_seed:        u64,
	tint_seed:           u64,
	radius:              i64,
	bedrock_radius:      i64,
	spacing_millimetres: int,
	spacing:             i64,
	palette_length:      int,
}

make_planet_generation :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Planet_Generation {
	seeds := generation_seed.derive_purpose_seeds(seed)
	return Planet_Generation {
		surface_seed = seeds[.Planet_Surface],
		tint_seed = seeds[.Planet_Tint],
		radius = metres_to_position_units(i64(planet.radius_metres)),
		bedrock_radius = metres_to_position_units(i64(planet.radius_metres - planet.bedrock_depth_metres)),
		spacing_millimetres = spacing_millimetres,
		spacing = sample_axis_to_position(1, spacing_millimetres),
		palette_length = len(planet.palette),
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

// The local surface's height above the radius at a point on the sphere.
surface_relief :: proc(seed: u64, point: [3]i64) -> i64 {
	relief: i64 = 0
	for octave, index in RELIEF_OCTAVES {
		noise := value_noise(generation_seed.hash_combine(seed, u64(index)), point, metres_to_position_units(octave.wavelength_metres))
		relief += metres_to_position_units(octave.amplitude_metres) * noise / NOISE_ONE
	}
	return relief
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
	surface := generation.radius + surface_relief(generation.surface_seed, project_onto_sphere(position, distance, generation.radius))
	depth := surface - distance
	density := depth_to_density(depth, generation.spacing_millimetres)
	if density <= 0 {
		return {density, .Air, 0}
	}
	return {density, planet_stratum(depth, distance, generation.bedrock_radius), planet_tint(generation, position)}
}

// Fills chunk; safe on any thread. The chunk is not marked dirty, the
// world does that when it takes the chunk (field_world_insert_chunk).
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
}
