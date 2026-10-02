package game

// The field counterpart of the voxel walk (work item 0170): march the
// field from a position along a direction in steps of a quarter sample,
// so no surface thicker than that is skipped, then refine the crossing by
// bisection on the density (refine_field_crossing). Integer only; the
// tool reach reads it now and the placement later.

FIELD_RAYCAST_STEPS_PER_SAMPLE :: 4

Field_Raycast_Hit :: struct {
	hit:      bool,
	position: World_Position,
	// Out of the ground, a unit vector in UNIT_VECTOR_ONE: the gradient at
	// the hit, or the radial up where it is zero (a ray starting deep in
	// the ground, field_normal_at).
	normal:   [3]i64,
	// The sample nearest the hit.
	sample:   Sample_Coordinate,
	// Along the ray from the origin, in position units.
	distance: i64,
}

// The point distance along a unit direction.
field_ray_point :: proc(origin: World_Position, direction: [3]i64, distance: i64) -> World_Position {
	return origin + World_Position(fixed_scale(direction, distance))
}

field_position_is_ground :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> bool {
	return field_density_at(world, spacing_millimetres, position) > 0
}

// The nearest sample on each axis.
nearest_field_sample :: proc(position: World_Position, spacing_millimetres: int) -> Sample_Coordinate {
	half := sample_axis_to_position(1, spacing_millimetres) / 2
	return world_position_to_sample(position + half, spacing_millimetres)
}

field_raycast_hit_at :: proc(world: ^Field_World, spacing_millimetres: int, origin: World_Position, direction: [3]i64, distance: i64) -> Field_Raycast_Hit {
	position := field_ray_point(origin, direction, distance)
	return Field_Raycast_Hit {
		hit = true,
		position = position,
		normal = field_normal_at(world, spacing_millimetres, position),
		sample = nearest_field_sample(position, spacing_millimetres),
		distance = distance,
	}
}

// direction is a unit vector, reach in position units. A ray starting in
// the ground hits at its origin.
raycast_field :: proc(world: ^Field_World, spacing_millimetres: int, origin: World_Position, direction: [3]i64, reach: i64) -> Field_Raycast_Hit {
	step := max(sample_axis_to_position(1, spacing_millimetres) / FIELD_RAYCAST_STEPS_PER_SAMPLE, 1)
	if field_position_is_ground(world, spacing_millimetres, origin) {
		return field_raycast_hit_at(world, spacing_millimetres, origin, direction, 0)
	}
	before: i64 = 0
	for before < reach {
		next := min(before + step, reach)
		if field_position_is_ground(world, spacing_millimetres, field_ray_point(origin, direction, next)) {
			distance := refine_field_crossing(world, spacing_millimetres, origin, direction, before, next)
			return field_raycast_hit_at(world, spacing_millimetres, origin, direction, distance)
		}
		before = next
	}
	return {}
}
