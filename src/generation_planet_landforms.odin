package game

import "generation_seed"

// The landforms of a planet (work item 0306, doc/architecture.md, World
// generation): plains, hills, ridged ranges and the valleys between them,
// a term of uncratered_relief added to the octaves, the basins, the
// terraces and the ledges of 0189, which become the small detail. After
// Minecraft's noise router: a region noise read through the record's
// curves gives the ground's height and the share of the ranges and the
// hills; the large terms read their noise at a warped point, which hides
// the lattice. The drama fades in with the distance from the home, so the
// crater and the first base lie on a plain for every seed. Integers and
// fixed point only, a pure function of the point, as the rest of the
// relief. A planet without landforms (the zero Planet_Landforms, a world
// file from before them) reads none of it.

// Perlin's twelve edge directions, four repeated, so a hash's top four
// bits pick one.
GRADIENT_NOISE_DIRECTIONS :: [16][3]i64 {
	{1, 1, 0}, {-1, 1, 0}, {1, -1, 0}, {-1, -1, 0},
	{1, 0, 1}, {-1, 0, 1}, {1, 0, -1}, {-1, 0, -1},
	{0, 1, 1}, {0, -1, 1}, {0, 1, -1}, {0, -1, -1},
	{1, 1, 0}, {-1, 1, 0}, {0, -1, 1}, {0, -1, -1},
}

// The curves' knots lie at the region noise's -0.6, -0.45 ... 0.6 (the
// noise's standard deviation is about 0.28); beyond the ends they are flat.
LANDFORM_KNOT_SPAN :: NOISE_ONE * 6 / 10
LANDFORM_KNOT_STEP :: 2 * LANDFORM_KNOT_SPAN / (LANDFORM_KNOT_COUNT - 1)

// 6t^5 - 15t^4 + 10t^3 of a fraction in 0 to NOISE_ONE: zero slope and
// zero curvature at both ends.
quintic_fade :: proc(fraction: i64) -> i64 {
	cube := fraction * fraction / NOISE_ONE * fraction / NOISE_ONE
	return cube * (fraction * (6 * fraction - 15 * NOISE_ONE) / NOISE_ONE + 10 * NOISE_ONE) / NOISE_ONE
}

// Gradient noise of one octave, from -NOISE_ONE to NOISE_ONE, zero at
// every lattice point. Not value noise: it has no axis aligned plateaus,
// which show at the landforms' amplitudes. The corners' dots are
// interpolated in value_noise's order.
gradient_noise :: proc(seed: u64, point: [3]i64, wavelength: i64) -> i64 {
	cell, fraction, fade: [3]i64
	for axis in 0 ..< 3 {
		cell[axis] = floor_divide_i64(point[axis], wavelength)
		fraction[axis] = (point[axis] - cell[axis] * wavelength) * NOISE_ONE / wavelength
		fade[axis] = quintic_fade(fraction[axis])
	}
	directions := GRADIENT_NOISE_DIRECTIONS
	hashes := noise_cell_hashes(seed, cell)
	corners: [8]i64
	for &corner, index in corners {
		offset := [3]i64{i64(index & 1), i64(index >> 1 & 1), i64(index >> 2)}
		direction := directions[hashes[index] >> 60]
		away := fraction - offset * NOISE_ONE
		corner = direction.x * away.x + direction.y * away.y + direction.z * away.z
	}
	for axis in 0 ..< 3 {
		width := 8 >> uint(axis + 1)
		for index in 0 ..< width {
			corners[index] = noise_interpolate(corners[2 * index], corners[2 * index + 1], fade[axis])
		}
	}
	return clamp(corners[0], -NOISE_ONE, NOISE_ONE)
}

// A Catmull-Rom curve through the knots times scale, flat beyond the end
// knots and clamped between the two knots it lies between, so it never
// leaves the knots' range (relief_bounds).
landform_curve :: proc(knots: [LANDFORM_KNOT_COUNT]int, noise: i64, scale: i64) -> i64 {
	position := clamp(noise + LANDFORM_KNOT_SPAN, 0, 2 * LANDFORM_KNOT_SPAN)
	index := min(position / LANDFORM_KNOT_STEP, LANDFORM_KNOT_COUNT - 2)
	t := (position - index * LANDFORM_KNOT_STEP) * NOISE_ONE / LANDFORM_KNOT_STEP
	p0 := i64(knots[max(index - 1, 0)]) * scale
	p1 := i64(knots[index]) * scale
	p2 := i64(knots[index + 1]) * scale
	p3 := i64(knots[min(index + 2, LANDFORM_KNOT_COUNT - 1)]) * scale
	t2 := t * t / NOISE_ONE
	t3 := t2 * t / NOISE_ONE
	value := 2 * p1 + (p2 - p0) * t / NOISE_ONE + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 / NOISE_ONE + (3 * p1 - p0 - 3 * p2 + p3) * t3 / NOISE_ONE
	return clamp(value / 2, min(p1, p2), max(p1, p2))
}

// A crest along each zero line of the noise, from NOISE_ONE there to none
// where |noise| reaches one half. The zero lines run long and branch, so
// the crests make ranges; Minecraft's fold puts its peaks on contours
// that close into rings round every extremum.
landform_ridge :: proc(noise: i64) -> i64 {
	ridge := max(NOISE_ONE - 2 * abs(noise), 0)
	return ridge * ridge / NOISE_ONE
}

// 0 within calm_metres of the home, NOISE_ONE from wild_metres out, a
// smoothstep between; no root beyond the wild ground.
home_wildness :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	offset := point - generation.landform_home
	return home_wildness_at_squared(generation, offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
}

// home_wildness at the squared chord from the home.
home_wildness_at_squared :: proc(generation: Planet_Generation, squared: i64) -> i64 {
	return noise_fade(home_wildness_fraction(generation, squared))
}

// The wildness's smoothstep input at the squared chord from the home: 0
// within calm_metres, NOISE_ONE from wild_metres out (no root there).
// It never falls with the chord (the box bound reads it at both ends of a
// range, 0314); the smoothstep in integers does (fade_range).
home_wildness_fraction :: proc(generation: Planet_Generation, squared: i64) -> i64 {
	landforms := generation.landforms
	wild := metres_to_position_units(i64(landforms.wild_metres))
	if squared >= wild * wild {
		return NOISE_ONE
	}
	calm := metres_to_position_units(i64(landforms.calm_metres))
	distance := i64(integer_square_root(u64(squared)))
	return clamp((distance - calm) * NOISE_ONE / (wild - calm), 0, NOISE_ONE)
}

// What the landforms read at a point, kept for the landmarks (0323): the
// landforms' relief, home_wildness, the region noise, the warped point,
// the first warp noise (axis 0, -NOISE_ONE to NOISE_ONE), which places
// the landmarks' patches, and the hill noise (0 where the hills are off
// or their share is 0).
Landform_Reading :: struct {
	relief, wildness, region: i64,
	warped:                   [3]i64,
	mask, hill:               i64,
}

// The landforms' height over the radius at the point on the sphere: the
// region's height blended from home_metres by the wildness, the ranges
// and the hills by their shares and the wildness. 0 without landforms.
// The skips change no value (each skipped term is exactly 0) and keep the
// home area, the sea floor and the lowlands cheap.
landform_relief :: proc(generation: Planet_Generation, point: [3]i64) -> i64 {
	return landform_reading(generation, point).relief
}

// The landforms' relief with the values it computes on the way: {}
// without landforms, only the home's height within the calm circle.
landform_reading :: proc(generation: Planet_Generation, point: [3]i64) -> Landform_Reading {
	landforms := generation.landforms
	if landforms.region_wavelength_metres == 0 {
		return {}
	}
	home := metres_to_position_units(i64(landforms.home_metres))
	wildness := home_wildness(generation, point)
	if wildness == 0 {
		return {relief = home}
	}
	reading := Landform_Reading {
		wildness = wildness,
		warped   = point,
	}
	for axis in 0 ..< 3 {
		warp := gradient_noise(generation_seed.hash_combine(generation.landform_seed, u64(axis)), point, metres_to_position_units(i64(landforms.warp_wavelength_metres)))
		reading.warped[axis] += metres_to_position_units(i64(landforms.warp_metres)) * warp / NOISE_ONE
		if axis == 0 {
			reading.mask = warp
		}
	}
	reading.region = gradient_noise(generation_seed.hash_combine(generation.landform_seed, 3), reading.warped, metres_to_position_units(i64(landforms.region_wavelength_metres)))
	base := landform_curve(landforms.region_heights_metres, reading.region, POSITION_UNITS_PER_METRE)
	reading.relief = home + (base - home) * wildness / NOISE_ONE
	range_share := landform_curve(landforms.region_ranges_percent, reading.region, NOISE_ONE) / 100
	if landforms.range_metres > 0 && range_share > 0 {
		reading.relief += landform_range_relief(generation, reading.warped, range_share, wildness)
	}
	hill_share := landform_curve(landforms.region_hills_percent, reading.region, NOISE_ONE) / 100
	if landforms.hill_metres > 0 && hill_share > 0 {
		reading.hill = gradient_noise(generation_seed.hash_combine(generation.landform_seed, 5), reading.warped, metres_to_position_units(i64(landforms.hill_wavelength_metres)))
		reading.relief += metres_to_position_units(i64(landforms.hill_metres)) * reading.hill / NOISE_ONE * hill_share / NOISE_ONE * wildness / NOISE_ONE
	}
	return reading
}

// The ranges' height at the warped point: the ridge, notched by the spurs
// into peaks and saddles, times the share and the wildness.
landform_range_relief :: proc(generation: Planet_Generation, warped: [3]i64, range_share, wildness: i64) -> i64 {
	landforms := generation.landforms
	ridge := landform_ridge(gradient_noise(generation_seed.hash_combine(generation.landform_seed, 4), warped, metres_to_position_units(i64(landforms.range_wavelength_metres))))
	if ridge > 0 && landforms.spur_percent > 0 {
		spur := landform_ridge(gradient_noise(generation_seed.hash_combine(generation.landform_seed, 6), warped, metres_to_position_units(i64(landforms.spur_wavelength_metres))))
		ridge = ridge * (i64(100 - landforms.spur_percent) * NOISE_ONE + i64(landforms.spur_percent) * spur) / (100 * NOISE_ONE)
	}
	return metres_to_position_units(i64(landforms.range_metres)) * ridge / NOISE_ONE * range_share / NOISE_ONE * wildness / NOISE_ONE
}
