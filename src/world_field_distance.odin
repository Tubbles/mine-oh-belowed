package game

// The terrain field read as a signed distance (work item 0170,
// doc/architecture.md, The player on the field): the density between
// samples is trilinear and the gradient a central difference half a
// sample to each side. The density is no distance once a side saturates
// (a spacing from the surface) and after a brush edit, so the probe finds
// the surface: it marches from the point along the gradient (inwards from
// the air, outwards from the ground; along the radial where the gradient
// is zero) in half sample steps until the density changes sign, bisects
// to the crossing, and reads the distance to it and the normal there; it
// marches along the radial and across it too and keeps the nearest
// crossing, so a corner does not hide the nearer surface.
// Used by the player's collision and the field raycast, integer only.

// Densities between samples are in steps times this.
DENSITY_FRACTION_ONE :: 65536
// The probe looks for a surface this many samples away at most.
FIELD_PROBE_REACH_SAMPLES :: 3
FIELD_PROBE_BISECTIONS :: 12

Field_Surface_Probe :: struct {
	// From the position to the surface in position units, positive in the
	// air. Without a surface within the reach: the reach, signed by the
	// side the position lies on.
	distance: i64,
	// Out of the ground at the crossing, a unit vector (field_normal_at);
	// the radial up without a surface.
	normal:   [3]i64,
	found:    bool,
}

field_sample_density :: proc(world: ^Field_World, sample: Sample_Coordinate) -> i64 {
	return i64(field_world_get_sample(world, sample).density) * DENSITY_FRACTION_ONE
}

// The sample at or below the position on each axis and the fraction
// beyond it in DENSITY_FRACTION_ONE.
field_cell_of :: proc(position: World_Position, spacing_millimetres: int) -> (base: Sample_Coordinate, fraction: [3]i64) {
	for axis in 0 ..< 3 {
		base[axis] = position_axis_to_sample(position[axis], spacing_millimetres)
		low := sample_axis_to_position(base[axis], spacing_millimetres)
		high := sample_axis_to_position(base[axis] + 1, spacing_millimetres)
		fraction[axis] = (position[axis] - low) * DENSITY_FRACTION_ONE / (high - low)
	}
	return
}

// The density at any position in steps times DENSITY_FRACTION_ONE,
// positive inside the ground. Missing chunks read as air.
field_density_at :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> i64 {
	base, fraction := field_cell_of(position, spacing_millimetres)
	corners: [8]i64
	for &corner, index in corners {
		corner = field_sample_density(world, base + {i32(index & 1), i32(index >> 1 & 1), i32(index >> 2)})
	}
	for axis in 0 ..< 3 {
		width := 8 >> uint(axis + 1)
		for index in 0 ..< width {
			first, second := corners[2 * index], corners[2 * index + 1]
			corners[index] = first + (second - first) * fraction[axis] / DENSITY_FRACTION_ONE
		}
	}
	return corners[0]
}

// Steps per spacing times DENSITY_FRACTION_ONE, pointing into the ground.
field_density_gradient :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> [3]i64 {
	half := sample_axis_to_position(1, spacing_millimetres) / 2
	gradient: [3]i64
	for axis in 0 ..< 3 {
		plus, minus := position, position
		plus[axis] += half
		minus[axis] -= half
		gradient[axis] = field_density_at(world, spacing_millimetres, plus) - field_density_at(world, spacing_millimetres, minus)
	}
	return gradient
}

// Out of the planet's centre: the up of a position, for directions the
// field leaves open.
radial_up :: proc(position: World_Position) -> [3]i64 {
	up, ok := normalize_fixed(cast([3]i64)(position))
	return ok ? up : {0, UNIT_VECTOR_ONE, 0}
}

// The gradient reversed and normalised, out of the ground; the radial up
// where the gradient is zero (the saturated band a spacing or more from
// the surface).
field_normal_at :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> [3]i64 {
	normal, ok := normalize_fixed(-field_density_gradient(world, spacing_millimetres, position))
	return ok ? normal : radial_up(position)
}

// The distance along the ray, between near and far, where the ground
// state of near's point ends.
refine_field_crossing :: proc(world: ^Field_World, spacing_millimetres: int, origin: World_Position, direction: [3]i64, near, far: i64) -> i64 {
	near_ground := field_position_is_ground(world, spacing_millimetres, field_ray_point(origin, direction, near))
	low, high := near, far
	for _ in 0 ..< FIELD_PROBE_BISECTIONS {
		middle := low + (high - low) / 2
		if field_position_is_ground(world, spacing_millimetres, field_ray_point(origin, direction, middle)) == near_ground {
			low = middle
		} else {
			high = middle
		}
	}
	return high
}

// The distance along a unit direction to where the ground state of the
// position ends, in half sample steps up to limit and bisected; found is
// false within limit.
march_to_field_surface :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position, direction: [3]i64, inside: bool, limit: i64) -> (distance: i64, found: bool) {
	step := max(sample_axis_to_position(1, spacing_millimetres) / 2, 1)
	for before: i64 = 0; before < limit; before += step {
		next := min(before + step, limit)
		if field_position_is_ground(world, spacing_millimetres, field_ray_point(position, direction, next)) != inside {
			return refine_field_crossing(world, spacing_millimetres, position, direction, before, next), true
		}
	}
	return limit, false
}

// The ways a probe marches, towards the ground from the air (away from it
// inside): along the gradient, along the radial, and along the gradient's
// part across the radial. A gradient between a floor and a wall points
// into the corner, and the march along it alone overreads the nearer
// surface; the radial and the across part find the floor and the wall.
field_probe_directions :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position, inside: bool) -> [3][3]i64 {
	outward := field_normal_at(world, spacing_millimetres, position)
	up := radial_up(position)
	across, across_ok := normalize_fixed(project_onto_plane(outward, up))
	directions := [3][3]i64{outward, up, across_ok ? across : outward}
	if !inside {
		for &direction in directions {
			direction = -direction
		}
	}
	return directions
}

// The nearest crossing of the three marches (field_probe_directions)
// within FIELD_PROBE_REACH_SAMPLES and half a step, so a surface exactly
// that far is found; each march after the first stops at the nearest one
// so far.
field_surface_probe :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> Field_Surface_Probe {
	spacing := sample_axis_to_position(1, spacing_millimetres)
	reach := FIELD_PROBE_REACH_SAMPLES * spacing + max(spacing / 2, 1)
	inside := field_position_is_ground(world, spacing_millimetres, position)
	nearest := reach
	nearest_direction: [3]i64
	found := false
	for direction in field_probe_directions(world, spacing_millimetres, position, inside) {
		if distance, crossed := march_to_field_surface(world, spacing_millimetres, position, direction, inside, nearest); crossed && distance < nearest {
			nearest, nearest_direction, found = distance, direction, true
		}
	}
	if !found {
		return {distance = inside ? -reach : reach, normal = radial_up(position)}
	}
	normal := field_normal_at(world, spacing_millimetres, field_ray_point(position, nearest_direction, nearest))
	return {distance = inside ? -nearest : nearest, normal = normal, found = true}
}
