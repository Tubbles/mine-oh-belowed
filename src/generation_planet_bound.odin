package game

import "generation_seed"

// The relief's range over a box of samples (work item 0314,
// doc/architecture.md, World generation). A chunk or a grid is cut into
// boxes of RELIEF_BOX_SAMPLES samples per axis, each into eight boxes of
// half that. The first sample of a box that needs the relief computes a
// range holding surface_column's relief at every sample of the box, by
// interval arithmetic over every term of uncratered_column: each term
// takes the point code's own integer steps, and every step is monotone in
// each of its inputs over the values it can take (a truncating division
// keeps the order), so the step at its inputs' ends bounds it at every
// point between; the fades, whose truncations dip, are widened by the most
// they fall (FADE_FALL_LIMIT). The noises are bounded per lattice cell,
// the region's curves by their slope, the projection onto the sphere by
// its bulge and the sites by their cubes. A sample the range decides
// (planet_sample_by_bound: open air over it, deep or plain stone under it)
// gets exactly the bytes its column gives, so no record changes and old
// and new worlds generate the same bytes. The boxes the crater may reach
// and the ground of a box a carving site may reach are left to the
// column.

// A closed range of integers.
Value_Range :: struct {
	lowest, highest: i64,
}

// An axis aligned box of points, both corners in it.
Point_Box :: struct {
	lowest, highest: [3]i64,
}

// Every column of the box's samples has its surface_column relief in
// relief; carving when a carving site (0324) may reach one of them; crater
// when the crater may change a sample (impact_crater_reaches_box), and
// then nothing is decided and relief is not computed.
Relief_Box_Bound :: struct {
	relief:  Value_Range,
	carving: bool,
	crater:  bool,
}

// The ranges of Landform_Reading's fields over a box of points; mask,
// region, hill and warped hold the points whose wildness is above 0, the
// only ones the landmarks read them at.
Landform_Range :: struct {
	relief, wildness, region, mask, hill: Value_Range,
	warped:                               Point_Box,
}

RELIEF_BOX_SAMPLES :: 8
RELIEF_BOXES_PER_AXIS :: (FIELD_GRID_SIZE + RELIEF_BOX_SAMPLES - 1) / RELIEF_BOX_SAMPLES
RELIEF_BOX_COUNT :: RELIEF_BOXES_PER_AXIS * RELIEF_BOXES_PER_AXIS * RELIEF_BOXES_PER_AXIS
RELIEF_HALF_BOX_SAMPLES :: RELIEF_BOX_SAMPLES / 2
RELIEF_HALF_BOXES_PER_AXIS :: (FIELD_GRID_SIZE + RELIEF_HALF_BOX_SAMPLES - 1) / RELIEF_HALF_BOX_SAMPLES
RELIEF_HALF_BOX_COUNT :: RELIEF_HALF_BOXES_PER_AXIS * RELIEF_HALF_BOXES_PER_AXIS * RELIEF_HALF_BOXES_PER_AXIS
#assert(FIELD_CHUNK_SIZE <= FIELD_GRID_SIZE)

// More lattice cells than this on an axis, and lattice_noise_range gives
// the full range.
NOISE_RANGE_CELL_LIMIT :: 2
// The most noise_fade and quintic_fade fall from a fraction to any larger
// one: their truncations make them dip by a unit or a few in places, so
// neither is monotone in integers. test_the_fades_fall_at_most_the_limit
// proves it over every fraction from 0 to NOISE_ONE.
FADE_FALL_LIMIT :: 3
// The curve range's sampling: a point per this much noise, at most this
// many pieces.
CURVE_RANGE_PIECE :: 128
CURVE_RANGE_PIECES :: 32

// The boxes of RELIEF_BOX_SAMPLES and of RELIEF_HALF_BOX_SAMPLES of one
// chunk or grid, their bounds computed on first use: first is its first
// sample (a grid's at -1), samples its samples per axis, step the samples
// between two of its own and spacing_millimetres the positions' (the fine
// one, as the loops convert their samples). A box of 4 at h per axis lies
// in the box of 8 at h / 2; both arrays index box.x + per_axis * (box.y +
// per_axis * box.z) with their own per_axis, for a chunk too. About 21 KB,
// on the generating worker's stack.
Relief_Boxes :: struct {
	first:               Sample_Coordinate,
	step:                i32,
	samples:             i32,
	spacing_millimetres: int,
	bounds:              [RELIEF_BOX_COUNT]Relief_Box_Bound,
	computed:            [RELIEF_BOX_COUNT]bool,
	half_bounds:         [RELIEF_HALF_BOX_COUNT]Relief_Box_Bound,
	half_computed:       [RELIEF_HALF_BOX_COUNT]bool,
}

range_union :: proc(first, second: Value_Range) -> Value_Range {
	return {min(first.lowest, second.lowest), max(first.highest, second.highest)}
}

range_add :: proc(first, second: Value_Range) -> Value_Range {
	return {first.lowest + second.lowest, first.highest + second.highest}
}

// factor * value / divisor at both ends, for a factor of 0 or more, which
// keeps the order.
range_scaled :: proc(range: Value_Range, factor, divisor: i64) -> Value_Range {
	return {factor * range.lowest / divisor, factor * range.highest / divisor}
}

// first * second / divisor over the ranges, truncated as the point code
// truncates: a product is bilinear, so its extremes lie at the corners,
// and the truncation keeps the order. A chain x * y / N * z / N is two
// calls.
range_product :: proc(first, second: Value_Range, divisor: i64) -> Value_Range {
	corners := [4]i64{first.lowest * second.lowest / divisor, first.lowest * second.highest / divisor, first.highest * second.lowest / divisor, first.highest * second.highest / divisor}
	return {min(corners[0], corners[1], corners[2], corners[3]), max(corners[0], corners[1], corners[2], corners[3])}
}

// noise_interpolate over the ranges. For a fraction in 0 to NOISE_ONE it
// never falls when either end rises, and for fixed ends it is monotone in
// the fraction, so the lowest ends at the fraction's two ends hold the
// least and the highest ends the most.
interpolate_range :: proc(first, second, fraction: Value_Range) -> Value_Range {
	return {
		min(noise_interpolate(first.lowest, second.lowest, fraction.lowest), noise_interpolate(first.lowest, second.lowest, fraction.highest)),
		max(noise_interpolate(first.highest, second.highest, fraction.lowest), noise_interpolate(first.highest, second.highest, fraction.highest)),
	}
}

// The range of noise_fade (with gradient quintic_fade) over a range of
// fractions within 0 to NOISE_ONE: the fade at a single fraction, else
// the ends widened by FADE_FALL_LIMIT (a fraction above the lowest fades
// to at least the lowest's fade less it, one below the highest to at most
// the highest's plus it) and kept within 0 to NOISE_ONE, where every
// fade lies.
fade_range :: proc(fraction: Value_Range, gradient: bool) -> Value_Range {
	fade := gradient ? quintic_fade : noise_fade
	if fraction.lowest == fraction.highest {
		value := fade(fraction.lowest)
		return {value, value}
	}
	return {max(fade(fraction.lowest) - FADE_FALL_LIMIT, 0), min(fade(fraction.highest) + FADE_FALL_LIMIT, NOISE_ONE)}
}

// The range of value_noise (or with gradient gradient_noise) at every
// point of the box, by monotonicity per lattice cell the box meets; more
// than NOISE_RANGE_CELL_LIMIT cells on an axis gives the full range, which
// holds both noises.
lattice_noise_range :: proc(seed: u64, box: Point_Box, wavelength: i64, gradient: bool) -> Value_Range {
	first_cell, last_cell: [3]i64
	for axis in 0 ..< 3 {
		first_cell[axis] = floor_divide_i64(box.lowest[axis], wavelength)
		last_cell[axis] = floor_divide_i64(box.highest[axis], wavelength)
		if last_cell[axis] - first_cell[axis] + 1 > NOISE_RANGE_CELL_LIMIT {
			return {-NOISE_ONE, NOISE_ONE}
		}
	}
	result := Value_Range{max(i64), min(i64)}
	for z in first_cell.z ..= last_cell.z {
		for y in first_cell.y ..= last_cell.y {
			for x in first_cell.x ..= last_cell.x {
				result = range_union(result, lattice_cell_noise_range(seed, box, {x, y, z}, wavelength, gradient))
			}
		}
	}
	return result
}

// The noise over the box clipped to one lattice cell: per axis the
// fraction's range (the point code's at the clipped ends, a truncated
// division that keeps the order) and the fade's (fade_range); the corners
// exact for value noise and the dot's range for gradient noise,
// interpolated in value_noise's order (x pairs, then y, then z), a
// gradient noise clamped as the point code clamps.
lattice_cell_noise_range :: proc(seed: u64, box: Point_Box, cell: [3]i64, wavelength: i64, gradient: bool) -> Value_Range {
	fraction, fade: [3]Value_Range
	for axis in 0 ..< 3 {
		start := cell[axis] * wavelength
		low := max(box.lowest[axis], start)
		high := min(box.highest[axis], start + wavelength - 1)
		fraction[axis] = {(low - start) * NOISE_ONE / wavelength, (high - start) * NOISE_ONE / wavelength}
		fade[axis] = fade_range(fraction[axis], gradient)
	}
	corners: [8]Value_Range
	for &corner, index in corners {
		offset := [3]i64{i64(index & 1), i64(index >> 1 & 1), i64(index >> 2)}
		if gradient {
			corner = gradient_corner_range(seed, cell, offset, fraction)
		} else {
			value := lattice_value(seed, cell + offset)
			corner = {value, value}
		}
	}
	for axis in 0 ..< 3 {
		width := 8 >> uint(axis + 1)
		for index in 0 ..< width {
			corners[index] = interpolate_range(corners[2 * index], corners[2 * index + 1], fade[axis])
		}
	}
	if gradient {
		return {clamp(corners[0].lowest, -NOISE_ONE, NOISE_ONE), clamp(corners[0].highest, -NOISE_ONE, NOISE_ONE)}
	}
	return corners[0]
}

// The range of a gradient corner's dot, direction · (fraction - offset *
// NOISE_ONE), summed per axis; a direction component of -1 swaps the ends.
gradient_corner_range :: proc(seed: u64, cell, offset: [3]i64, fraction: [3]Value_Range) -> Value_Range {
	directions := GRADIENT_NOISE_DIRECTIONS
	direction := directions[hash_lattice(seed, cell + offset) >> 60]
	result: Value_Range
	for axis in 0 ..< 3 {
		away := Value_Range{fraction[axis].lowest - offset[axis] * NOISE_ONE, fraction[axis].highest - offset[axis] * NOISE_ONE}
		switch direction[axis] {
		case 1:
			result = range_add(result, away)
		case -1:
			result = range_add(result, {-away.highest, -away.lowest})
		}
	}
	return result
}

// The knot segment landform_curve reads at a noise.
landform_curve_segment :: proc(noise: i64) -> i64 {
	return min(clamp(noise + LANDFORM_KNOT_SPAN, 0, 2 * LANDFORM_KNOT_SPAN) / LANDFORM_KNOT_STEP, LANDFORM_KNOT_COUNT - 2)
}

// The range of landform_curve over a range of noise; a single noise gives
// its value. Between two sampled points the real curve moves at most its
// slope times half the piece (the clamps keep the slope, and the flat ends
// have none), and the integer curve lies within the rounding of the real
// one, so the sampled least and most widened by both hold it; the knots'
// hull of the segments spanned holds it as well (landform_curve clamps
// each segment between its two knots).
landform_curve_range :: proc(knots: [LANDFORM_KNOT_COUNT]int, noise: Value_Range, scale: i64) -> Value_Range {
	if noise.lowest == noise.highest {
		value := landform_curve(knots, noise.lowest, scale)
		return {value, value}
	}
	hull := Value_Range{max(i64), min(i64)}
	slope, rounding: i64 = 0, 0
	for index in landform_curve_segment(noise.lowest) ..= landform_curve_segment(noise.highest) {
		p0 := i64(knots[max(index - 1, 0)]) * scale
		p1 := i64(knots[index]) * scale
		p2 := i64(knots[index + 1]) * scale
		p3 := i64(knots[min(index + 2, LANDFORM_KNOT_COUNT - 1)]) * scale
		hull = range_union(hull, {min(p1, p2), max(p1, p2)})
		c1 := abs(p2 - p0)
		c2 := abs(2 * p0 - 5 * p1 + 4 * p2 - p3)
		c3 := abs(3 * p1 - p0 - 3 * p2 + p3)
		// The cubic's derivative per unit t, and its integer rounding.
		slope = max(slope, (c1 + 2 * c2 + 3 * c3) / 2 + 1)
		rounding = max(rounding, 4 + (c1 + c2 + 2 * c3) / NOISE_ONE)
	}
	width := noise.highest - noise.lowest
	pieces := clamp((width + CURVE_RANGE_PIECE - 1) / CURVE_RANGE_PIECE, 1, CURVE_RANGE_PIECES)
	sampled := Value_Range{max(i64), min(i64)}
	for piece in 0 ..= pieces {
		value := landform_curve(knots, noise.lowest + width * piece / pieces, scale)
		sampled = range_union(sampled, {value, value})
	}
	widen := slope * ceiling_divide_i64(width, pieces) / LANDFORM_KNOT_STEP / 2 + slope / NOISE_ONE + 2 * rounding + 1
	return {max(sampled.lowest - widen, hull.lowest), min(sampled.highest + widen, hull.highest)}
}

// The squared chord from the point to every point of the box: per axis
// the nearest (0 when the box straddles the point) and the farthest
// squared offset, summed.
squared_chord_range :: proc(box: Point_Box, point: [3]i64) -> Value_Range {
	result: Value_Range
	for axis in 0 ..< 3 {
		low := box.lowest[axis] - point[axis]
		high := box.highest[axis] - point[axis]
		near: i64 = 0
		if low > 0 {
			near = low * low
		} else if high < 0 {
			near = high * high
		}
		result.lowest += near
		result.highest += max(low * low, high * high)
	}
	return result
}

// landform_ridge over a noise range: it never rises with |noise|.
ridge_range :: proc(noise: Value_Range) -> Value_Range {
	least := noise.lowest <= 0 && noise.highest >= 0 ? 0 : min(abs(noise.lowest), abs(noise.highest))
	most := max(abs(noise.lowest), abs(noise.highest))
	return {landform_ridge(most), landform_ridge(least)}
}

// The position projected as project_onto_sphere projects a sample.
projected_position :: proc(position: World_Position, radius: i64) -> [3]i64 {
	squared := position.x * position.x + position.y * position.y + position.z * position.z
	return project_onto_sphere(position, i64(integer_square_root(u64(squared))), radius)
}

// A box holding the points project_onto_sphere gives the samples of the
// box of positions. A sample's direction is a normalised positive
// combination of the corners' directions, so its projection lies within
// the hull of the corners' projections pushed out by the radius times one
// less the cosine of their spread round the centre's projection, which is
// the squared chord over twice the radius: the corners' box is widened by
// that, the chord's root lengthened by 8 and the box by 8 more, which
// cover the truncation of the projections and of the chords while every
// point of the box lies at least three quarters of the radius out (each
// projection then less than 3.1 units from the real one: the root's
// floor scales it by under 4/3 of a unit, the division truncates under a
// unit per axis). A box nearer the
// centre, or whose chord reaches the radius, gets the cube of the radius
// plus 8, which holds every projection.
projected_box :: proc(generation: Planet_Generation, lowest, highest: World_Position) -> Point_Box {
	radius := generation.radius
	reach := radius + 8
	cube := Point_Box{{-reach, -reach, -reach}, {reach, reach, reach}}
	nearest := i64(integer_square_root(u64(squared_chord_range({cast([3]i64)lowest, cast([3]i64)highest}, {}).lowest)))
	if 4 * nearest < 3 * radius {
		return cube
	}
	centre := projected_position(lowest + (highest - lowest) / 2, radius)
	result := Point_Box{{max(i64), max(i64), max(i64)}, {min(i64), min(i64), min(i64)}}
	farthest: i64 = 0
	for corner in 0 ..< 8 {
		position: World_Position
		for axis in 0 ..< 3 {
			position[axis] = (corner >> uint(axis)) & 1 == 0 ? lowest[axis] : highest[axis]
		}
		projected := projected_position(position, radius)
		for axis in 0 ..< 3 {
			result.lowest[axis] = min(result.lowest[axis], projected[axis])
			result.highest[axis] = max(result.highest[axis], projected[axis])
		}
		farthest = max(farthest, squared_chord(projected, centre))
	}
	root := i64(integer_square_root(u64(farthest)))
	if root >= radius {
		return cube
	}
	bulge := (root + 8) * (root + 8) / (2 * radius) + 8
	for axis in 0 ..< 3 {
		result.lowest[axis] -= bulge
		result.highest[axis] += bulge
	}
	return result
}

// landform_reading's steps on the ranges of a box of points on the
// sphere: {} without landforms, only the home's height while the box lies
// in the calm circle.
landform_reading_range :: proc(generation: Planet_Generation, box: Point_Box) -> Landform_Range {
	landforms := generation.landforms
	if landforms.region_wavelength_metres == 0 {
		return {}
	}
	home := metres_to_position_units(i64(landforms.home_metres))
	squared := squared_chord_range(box, generation.landform_home)
	wildness := fade_range({home_wildness_fraction(generation, squared.lowest), home_wildness_fraction(generation, squared.highest)}, false)
	if wildness.highest == 0 {
		return {relief = {home, home}}
	}
	reading := Landform_Range {
		wildness = wildness,
		warped   = box,
	}
	warp_amplitude := metres_to_position_units(i64(landforms.warp_metres))
	for axis in 0 ..< 3 {
		warp := lattice_noise_range(generation_seed.hash_combine(generation.landform_seed, u64(axis)), box, metres_to_position_units(i64(landforms.warp_wavelength_metres)), true)
		reading.warped.lowest[axis] += warp_amplitude * warp.lowest / NOISE_ONE
		reading.warped.highest[axis] += warp_amplitude * warp.highest / NOISE_ONE
		if axis == 0 {
			reading.mask = warp
		}
	}
	reading.region = lattice_noise_range(generation_seed.hash_combine(generation.landform_seed, 3), reading.warped, metres_to_position_units(i64(landforms.region_wavelength_metres)), true)
	base := landform_curve_range(landforms.region_heights_metres, reading.region, POSITION_UNITS_PER_METRE)
	reading.relief = range_add({home, home}, range_product({base.lowest - home, base.highest - home}, wildness, NOISE_ONE))
	reading.relief = range_add(reading.relief, landform_ranges_range(generation, reading))
	hill_share := range_scaled(landform_curve_range(landforms.region_hills_percent, reading.region, NOISE_ONE), 1, 100)
	if landforms.hill_metres > 0 && hill_share.highest > 0 {
		reading.hill = lattice_noise_range(generation_seed.hash_combine(generation.landform_seed, 5), reading.warped, metres_to_position_units(i64(landforms.hill_wavelength_metres)), true)
		height := range_scaled(reading.hill, metres_to_position_units(i64(landforms.hill_metres)), NOISE_ONE)
		height = range_product(height, {max(hill_share.lowest, 0), hill_share.highest}, NOISE_ONE)
		reading.relief = range_add(reading.relief, range_product(height, wildness, NOISE_ONE))
		// A point whose share is 0 or less skips the hills and reads hill 0.
		if hill_share.lowest <= 0 {
			reading.hill = range_union(reading.hill, {0, 0})
		}
	}
	return reading
}

// landform_range_relief over the reading's ranges, 0 where every point
// skips it. A point whose share is 0 or less skips the term, which the
// share's lowest raised to 0 holds; the spurs' factor and the ridge are
// never negative.
landform_ranges_range :: proc(generation: Planet_Generation, reading: Landform_Range) -> Value_Range {
	landforms := generation.landforms
	share := range_scaled(landform_curve_range(landforms.region_ranges_percent, reading.region, NOISE_ONE), 1, 100)
	if landforms.range_metres <= 0 || share.highest <= 0 {
		return {}
	}
	ridge := ridge_range(lattice_noise_range(generation_seed.hash_combine(generation.landform_seed, 4), reading.warped, metres_to_position_units(i64(landforms.range_wavelength_metres)), true))
	if ridge.highest > 0 && landforms.spur_percent > 0 {
		spur := ridge_range(lattice_noise_range(generation_seed.hash_combine(generation.landform_seed, 6), reading.warped, metres_to_position_units(i64(landforms.spur_wavelength_metres)), true))
		kept := i64(100 - landforms.spur_percent) * NOISE_ONE
		percent := i64(landforms.spur_percent)
		ridge = {ridge.lowest * (kept + percent * spur.lowest) / (100 * NOISE_ONE), ridge.highest * (kept + percent * spur.highest) / (100 * NOISE_ONE)}
	}
	height := range_scaled(ridge, metres_to_position_units(i64(landforms.range_metres)), NOISE_ONE)
	height = range_product(height, {max(share.lowest, 0), share.highest}, NOISE_ONE)
	return range_product(height, reading.wildness, NOISE_ONE)
}

// landmark_relief over the ranges: the relief range unchanged without
// landmarks or wildness; otherwise raised by the most the mesas and the
// sites raise and cut by the most a gorge and a sinkhole cut, clamped and
// floored as the point code clamps and floors. A point of wildness 0
// skips the landmarks, so its relief stays in the lowest. carving when a
// carving site may reach the box.
landmark_relief_range :: proc(generation: Planet_Generation, box: Point_Box, relief: Value_Range, reading: Landform_Range) -> (result: Value_Range, carving: bool) {
	landmarks := generation.landmarks
	if landmarks.site_spacing_metres == 0 || reading.wildness.highest == 0 {
		return relief, false
	}
	floor := max(generation.sea_radius - generation.radius + metres_to_position_units(i64(landmarks.dry_metres)), generation.relief_lowest)
	gorge := landmark_gorge_most(generation, relief, reading, floor)
	mesa := landmark_mesa_range(generation, box, reading)
	site_raise, site_cut: i64
	site_raise, site_cut, carving = landmark_sites_most(generation, box)
	result.highest = min(relief.highest + mesa.highest + site_raise, generation.relief_highest)
	result.lowest = min(relief.lowest + mesa.lowest, generation.relief_highest)
	if reading.wildness.lowest == 0 {
		result.lowest = min(result.lowest, relief.lowest)
	}
	if gorge > 0 {
		result.lowest = min(result.lowest, max(relief.lowest - gorge, floor))
	}
	if site_cut > 0 {
		result.lowest = min(result.lowest, max(result.lowest - site_cut, floor))
	}
	return
}

// The most a gorge may cut in the box, 0 when none can: the patch's ramp
// is largest at the mask's lowest, and the cut needs the meandered noise
// nearer 0 than the gorge's width at full strength (landmark_gorge_cut's
// width is at most that, its cut at most the depth).
landmark_gorge_most :: proc(generation: Planet_Generation, relief: Value_Range, reading: Landform_Range, floor: i64) -> i64 {
	landmarks := generation.landmarks
	if landmarks.gorge_metres <= 0 || landmarks.gorge_width_permille <= 0 || relief.highest <= floor {
		return 0
	}
	fade := i64(landmarks.mask_fade_percent) * NOISE_ONE / 100
	if landmark_ramp(-reading.mask.lowest, i64(landmarks.gorge_mask_percent) * NOISE_ONE / 100, fade) <= 0 {
		return 0
	}
	noise := lattice_noise_range(generation_seed.hash_combine(generation.landmark_seed, 1), reading.warped, metres_to_position_units(i64(landmarks.gorge_wavelength_metres)), true)
	noise = range_add(noise, range_scaled(reading.hill, i64(landmarks.gorge_meander_percent), 100))
	least := noise.lowest <= 0 && noise.highest >= 0 ? 0 : min(abs(noise.lowest), abs(noise.highest))
	if least >= i64(landmarks.gorge_width_permille) * NOISE_ONE / 1000 {
		return 0
	}
	return metres_to_position_units(i64(landmarks.gorge_metres))
}

// The most mesa_raise_at falls when its noise or its strength rises: its
// two tiers are fades of ramps that never fall, each fade falling at most
// FADE_FALL_LIMIT, and the scaling's truncation a unit more.
mesa_raise_fall :: proc(landmarks: Planet_Landmarks) -> i64 {
	return metres_to_position_units(i64(landmarks.mesa_metres)) * 2 * FADE_FALL_LIMIT / NOISE_ONE + 1
}

// The mesas' raise over the box: 0 at the lowest unless every point's
// strength is above 0, mesa_raise_at at the ends of the strength's and
// the roughened noise's ranges otherwise, widened by mesa_raise_fall (a
// point under the threshold raises 0).
landmark_mesa_range :: proc(generation: Planet_Generation, box: Point_Box, reading: Landform_Range) -> Value_Range {
	landmarks := generation.landmarks
	if landmarks.mesa_metres <= 0 {
		return {}
	}
	fade := i64(landmarks.mask_fade_percent) * NOISE_ONE / 100
	threshold := i64(landmarks.mesa_mask_percent) * NOISE_ONE / 100
	patch := Value_Range{landmark_ramp(reading.mask.lowest, threshold, fade), landmark_ramp(reading.mask.highest, threshold, fade)}
	if patch.highest <= 0 {
		return {}
	}
	share := range_scaled(landform_curve_range(landmarks.region_mesas_percent, reading.region, NOISE_ONE), 1, 100)
	share.lowest = max(share.lowest, 0)
	strength := range_product(range_product(patch, share, NOISE_ONE), reading.wildness, NOISE_ONE)
	if strength.highest <= 0 {
		return {}
	}
	noise := lattice_noise_range(generation_seed.hash_combine(generation.landmark_seed, 2), box, metres_to_position_units(i64(landmarks.mesa_wavelength_metres)), true)
	noise = range_add(noise, range_scaled(reading.hill, i64(landmarks.mesa_rough_percent), 100))
	fall := mesa_raise_fall(landmarks)
	mesa := Value_Range{0, mesa_raise_at(landmarks, noise.highest, strength.highest) + fall}
	if strength.lowest > 0 {
		mesa.lowest = max(mesa_raise_at(landmarks, noise.lowest, strength.lowest) - fall, 0)
	}
	return mesa
}

// The most a site raises and cuts in the box, and whether a carving site
// may reach it: every lattice cube the box meets, the site placed as the
// point code places it, skipped where the box lies past its reach (the
// reading's own refusal).
landmark_sites_most :: proc(generation: Planet_Generation, box: Point_Box) -> (raise, cut: i64, carving: bool) {
	spacing := metres_to_position_units(i64(generation.landmarks.site_spacing_metres))
	first, last: [3]i64
	for axis in 0 ..< 3 {
		first[axis] = floor_divide_i64(box.lowest[axis], spacing)
		last[axis] = floor_divide_i64(box.highest[axis], spacing)
	}
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				cell := [3]i64{x, y, z}
				site, candidate := landmark_site_candidate(generation, cell)
				if site.kind == .None {
					continue
				}
				placed := place_landmark_site(generation, cell, site, candidate)
				if placed.kind == .None {
					continue
				}
				outer := landmark_site_outer(placed)
				if squared_chord_range(box, placed.centre).lowest >= outer * outer {
					continue
				}
				switch {
				case placed.kind in CARVING_KINDS:
					carving = true
					raise = max(raise, landmark_raise_most(placed))
				case placed.kind == .Sinkhole:
					cut = max(cut, placed.height)
				case:
					raise = max(raise, placed.height)
				}
			}
		}
	}
	return
}

// uncratered_column's relief over a box of points on the sphere: the
// octaves (the first through long_octave_relief, monotone in its noise),
// the ledges (ledge_profile, monotone), the landforms and then the
// landmarks over the sum.
uncratered_relief_range :: proc(generation: Planet_Generation, box: Point_Box) -> (relief: Value_Range, carving: bool) {
	for octave, index in generation.relief_octaves {
		noise := lattice_noise_range(generation_seed.hash_combine(generation.surface_seed, u64(index)), box, metres_to_position_units(i64(octave.wavelength_metres)), false)
		if index == 0 {
			relief = range_add(relief, {long_octave_relief(noise.lowest, octave.amplitude_metres, generation.relief_shape), long_octave_relief(noise.highest, octave.amplitude_metres, generation.relief_shape)})
		} else {
			relief = range_add(relief, range_scaled(noise, metres_to_position_units(i64(octave.amplitude_metres)), NOISE_ONE))
		}
	}
	shape := generation.relief_shape
	if shape.ledge_amplitude_millimetres != 0 {
		noise := lattice_noise_range(generation_seed.hash_combine(generation.surface_seed, RELIEF_OCTAVE_COUNT), box, metres_to_position_units(i64(shape.ledge_wavelength_metres)), false)
		profile := Value_Range{ledge_profile(noise.lowest, shape.ledge_sharpness), ledge_profile(noise.highest, shape.ledge_sharpness)}
		relief = range_add(relief, range_scaled(profile, millimetres_to_position_units(shape.ledge_amplitude_millimetres), NOISE_ONE))
	}
	reading := landform_reading_range(generation, box)
	return landmark_relief_range(generation, box, range_add(relief, reading.relief), reading)
}

// The bound of the samples between two positions (both corners samples):
// nothing decided when the crater may reach them, otherwise the
// uncratered relief's range over their projections.
relief_box_bound :: proc(generation: Planet_Generation, lowest, highest: World_Position) -> Relief_Box_Bound {
	if impact_crater_reaches_box(generation, {lowest, highest}) {
		return {crater = true}
	}
	relief, carving := uncratered_relief_range(generation, projected_box(generation, lowest, highest))
	return {relief = relief, carving = carving}
}

// The bound of the box of RELIEF_BOX_SAMPLES (with half of
// RELIEF_HALF_BOX_SAMPLES) holding the sample offset from boxes.first (0
// to samples - 1 per axis), computed on first use from the positions of
// the box's first sample and its last. A box of 4's bound is intersected
// with its 8's, which holds its samples too.
relief_box_bound_at :: proc(generation: Planet_Generation, boxes: ^Relief_Boxes, offset: [3]i32, half: bool) -> Relief_Box_Bound {
	size := i32(half ? RELIEF_HALF_BOX_SAMPLES : RELIEF_BOX_SAMPLES)
	per_axis := half ? RELIEF_HALF_BOXES_PER_AXIS : RELIEF_BOXES_PER_AXIS
	box := offset / size
	index := int(box.x) + per_axis * (int(box.y) + per_axis * int(box.z))
	computed := half ? &boxes.half_computed[index] : &boxes.computed[index]
	stored := half ? &boxes.half_bounds[index] : &boxes.bounds[index]
	if computed^ {
		return stored^
	}
	first := box * size
	last: [3]i32
	for axis in 0 ..< 3 {
		last[axis] = min(first[axis] + size - 1, boxes.samples - 1)
	}
	lowest := sample_to_world_position(boxes.first + Sample_Coordinate(first * boxes.step), boxes.spacing_millimetres)
	highest := sample_to_world_position(boxes.first + Sample_Coordinate(last * boxes.step), boxes.spacing_millimetres)
	bound := relief_box_bound(generation, lowest, highest)
	if half && !bound.crater {
		whole := relief_box_bound_at(generation, boxes, offset, false)
		if !whole.crater {
			bound.relief = {max(bound.relief.lowest, whole.relief.lowest), min(bound.relief.highest, whole.relief.highest)}
			bound.carving = bound.carving && whole.carving
		}
	}
	computed^ = true
	stored^ = bound
	return bound
}

// The sample at the position, offset from boxes.first, when its box of 8
// decides it, else when its box of 4 does (not under a crater's 8).
planet_sample_by_boxes :: proc(generation: Planet_Generation, boxes: ^Relief_Boxes, offset: [3]i32, position: World_Position, distance: i64) -> (sample: Field_Sample, decided: bool) {
	whole := relief_box_bound_at(generation, boxes, offset, false)
	sample, decided = planet_sample_by_bound(generation, whole, position, distance)
	if decided || whole.crater {
		return
	}
	return planet_sample_by_bound(generation, relief_box_bound_at(generation, boxes, offset, true), position, distance)
}

// The sample at the position when the bound decides it, the bytes
// planet_sample_at_column gives in every column the bound holds:
// - open air at or over the highest plus a spacing: the depth is at most
//   minus a spacing, so the density saturates at -MAXIMUM_DENSITY, and a
//   carve lies under the top, so the air is neither carved nor shaded;
// - deep stone at or under the lowest less the deep stone's depth (and at
//   least a spacing and the topsoil), which saturates the density;
// - plain stone over the highest less the deep stone's depth and at or
//   under the lowest less the topsoil and the outcrop, so the depth lies
//   between them in every column;
// either stone bedrock within the bedrock's radius, as planet_stratum
// and the outcrop keep it. A carving site's carved air lies under the
// top, so only the air is decided in its box; nothing under the crater.
planet_sample_by_bound :: proc(generation: Planet_Generation, bound: Relief_Box_Bound, position: World_Position, distance: i64) -> (sample: Field_Sample, decided: bool) {
	if bound.crater {
		return
	}
	height := distance - generation.radius
	if height >= bound.relief.highest + generation.spacing {
		return FIELD_AIR_SAMPLE, true
	}
	if bound.carving {
		return
	}
	topsoil := generation_topsoil_depth(generation)
	deep := max(metres_to_position_units(DEEP_STONE_DEPTH_METRES), generation.spacing, topsoil)
	top := max(topsoil, metres_to_position_units(OUTCROP_DEPTH_METRES))
	material: Field_Material
	switch {
	case height <= bound.relief.lowest - deep:
		material = .Deep_Stone
	case height > bound.relief.highest - metres_to_position_units(DEEP_STONE_DEPTH_METRES) && height <= bound.relief.lowest - top:
		material = .Stone
	case:
		return
	}
	if distance <= generation.bedrock_radius {
		material = .Bedrock
	}
	return {MAXIMUM_DENSITY, material, planet_tint(generation, position)}, true
}

// planet_sample_reading with the boxes: the shortcut, then the sample the
// box bound decides (neither shaded nor carved), then the column.
planet_sample_reading_boxed :: proc(generation: Planet_Generation, position: World_Position, boxes: ^Relief_Boxes, offset: [3]i32) -> (sample: Field_Sample, shaded, carved: bool) {
	shortcut, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
	if !needs_relief {
		return shortcut, false, false
	}
	if bounded, decided := planet_sample_by_boxes(generation, boxes, offset, position, distance); decided {
		return bounded, false, false
	}
	return planet_sample_reading_at(generation, position, distance, on_sphere)
}
