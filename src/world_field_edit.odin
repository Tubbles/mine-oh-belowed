package game

// Brush edits of the terrain field (work item 0171, doc/architecture.md,
// The terrain field's brushes): a dig lowers the density of every sample
// within the brush by its rate, bounded at air; a place raises it, bounded
// at full ground, from one material; the level mode moves the samples
// towards the plane through the hit across the player's up, a dig from
// above and a place from below. Integer only and in one sample order (z,
// then y, then x, rising), so every machine of a lockstep game edits
// alike.
//
// The volume of a sample's ground is the positive part of its density,
// MAXIMUM_DENSITY steps the whole sample: a dig counts what it takes off
// the positive part per material, a place what it adds. Samples at zero
// or below are air (material Air, tint 0), as the generation makes them,
// so a place followed by a dig of the same samples returns exactly what
// it took. A place raises only air and ground of its own material, so it
// never turns one material into another. The world never names an item:
// the simulation converts the steps (field_mining.odin).

Field_Edit_Mode :: enum u8 {
	Dig,
	Place,
}

// A brush of data/game.sjson in the world's units.
Field_Brush :: struct {
	shape:  Field_Brush_Shape,
	// Position units.
	radius: i64,
	// Density steps per sample per edit.
	rate:   i32,
}

Field_Edit :: struct {
	mode:     Field_Edit_Mode,
	brush:    Field_Brush,
	centre:   World_Position,
	// The level plane's normal, a unit vector (the player's up).
	up:       [3]i64,
	// Dig: the materials the tool reaches; ground of any other material is
	// left and reported in the result's blocked.
	diggable: bit_set[Field_Material],
	// Place: the material and tint of the samples it turns to ground, and
	// the most density steps it may add in all; it stops once they are
	// spent.
	material: Field_Material,
	tint:     u8,
	budget:   i64,
}

Field_Edit_Result :: struct {
	// Density steps of ground removed (dig) or added (place) per material.
	steps:   [Field_Material]i64,
	blocked: bit_set[Field_Material],
}

make_field_brush :: proc(config: Field_Brush_Config) -> Field_Brush {
	shape, _ := field_brush_shape_from_name(config.shape)
	return {shape = shape, radius = millimetres_to_position_units(config.radius_millimetres), rate = i32(config.rate_density_steps_per_tick)}
}

make_field_brushes :: proc(configs: []Field_Brush_Config, allocator := context.allocator) -> []Field_Brush {
	brushes := make([]Field_Brush, len(configs), allocator)
	for config, index in configs {
		brushes[index] = make_field_brush(config)
	}
	return brushes
}

// The density a sample takes on the level plane: positive below it.
field_plane_density :: proc(edit: Field_Edit, position: World_Position, spacing_millimetres: int) -> i8 {
	height := fixed_dot(cast([3]i64)(position - edit.centre), edit.up)
	return depth_to_density(-height, spacing_millimetres)
}

// The density the edit moves a sample towards.
field_edit_target :: proc(edit: Field_Edit, position: World_Position, spacing_millimetres: int) -> i8 {
	if edit.brush.shape == .Level {
		return field_plane_density(edit, position, spacing_millimetres)
	}
	return edit.mode == .Dig ? -MAXIMUM_DENSITY : MAXIMUM_DENSITY
}

// One sample's density after the edit, at most the rate towards the
// target and never past it; the old density when the edit leaves it.
field_edit_step :: proc(mode: Field_Edit_Mode, old, target: i8, rate: i32) -> i8 {
	if mode == .Dig {
		return i8(max(i32(old) - rate, min(i32(target), i32(old))))
	}
	return i8(min(i32(old) + rate, max(i32(target), i32(old))))
}

field_ground_volume :: proc(density: i8) -> i64 {
	return i64(max(density, 0))
}

// Air at zero density and below, as the generation makes it.
field_edited_sample :: proc(density: i8, material: Field_Material, tint: u8) -> Field_Sample {
	if density <= 0 {
		return {density, .Air, 0}
	}
	return {density, material, tint}
}

dig_field_sample :: proc(world: ^Field_World, sample: Sample_Coordinate, old: Field_Sample, new_density: i8, edit: Field_Edit, result: ^Field_Edit_Result) {
	if old.density > 0 && old.material not_in edit.diggable {
		result.blocked += {old.material}
		return
	}
	result.steps[old.material] += field_ground_volume(old.density) - field_ground_volume(new_density)
	field_world_set_sample(world, sample, field_edited_sample(new_density, old.material, old.tint))
}

// Returns false once the budget is spent.
place_field_sample :: proc(world: ^Field_World, sample: Sample_Coordinate, old: Field_Sample, new_density: i8, edit: Field_Edit, result: ^Field_Edit_Result) -> bool {
	left := edit.budget - result.steps[edit.material]
	if left <= 0 {
		return false
	}
	if old.density > 0 && old.material != edit.material {
		return true
	}
	density := new_density
	if field_ground_volume(density) - field_ground_volume(old.density) > left {
		density = i8(field_ground_volume(old.density) + left)
	}
	result.steps[edit.material] += field_ground_volume(density) - field_ground_volume(old.density)
	tint := old.density > 0 ? old.tint : edit.tint
	field_world_set_sample(world, sample, field_edited_sample(density, edit.material, tint))
	return true
}

// The first and last sample within reach of the centre on each axis.
field_edit_bounds :: proc(edit: Field_Edit, spacing_millimetres: int) -> (first, last: Sample_Coordinate) {
	for axis in 0 ..< 3 {
		first[axis] = position_axis_to_sample(edit.centre[axis] - edit.brush.radius, spacing_millimetres)
		last[axis] = position_axis_to_sample(edit.centre[axis] + edit.brush.radius, spacing_millimetres) + 1
	}
	return
}

field_sample_in_brush :: proc(edit: Field_Edit, position: World_Position) -> bool {
	offset := cast([3]i64)(position - edit.centre)
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z <= edit.brush.radius * edit.brush.radius
}

// The sample's density after the edit and whether the edit reaches it:
// within the brush and in a loaded chunk.
field_edit_sample_change :: proc(world: ^Field_World, spacing_millimetres: int, edit: Field_Edit, sample: Sample_Coordinate) -> (old: Field_Sample, new_density: i8, reached: bool) {
	position := sample_to_world_position(sample, spacing_millimetres)
	if !field_sample_in_brush(edit, position) || sample_to_field_chunk_coordinate(sample) not_in world.chunks {
		return {}, 0, false
	}
	old = field_world_get_sample(world, sample)
	return old, field_edit_step(edit.mode, old.density, field_edit_target(edit, position, spacing_millimetres), edit.brush.rate), true
}

// Applies the edit to the loaded chunks; samples of chunks not loaded are
// left. Marks the changed chunks dirty through field_world_set_sample.
apply_field_edit :: proc(world: ^Field_World, spacing_millimetres: int, edit: Field_Edit) -> Field_Edit_Result {
	result: Field_Edit_Result
	first, last := field_edit_bounds(edit, spacing_millimetres)
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				sample := Sample_Coordinate{x, y, z}
				old, new_density, reached := field_edit_sample_change(world, spacing_millimetres, edit, sample)
				if !reached || new_density == old.density {
					continue
				}
				if edit.mode == .Dig {
					dig_field_sample(world, sample, old, new_density, edit, &result)
				} else if !place_field_sample(world, sample, old, new_density, edit, &result) {
					return result
				}
			}
		}
	}
	return result
}

// A capsule: the segment from bottom along the unit up for length, and
// everything within radius of it.
Field_Capsule :: struct {
	bottom: World_Position,
	up:     [3]i64,
	length: i64,
	radius: i64,
}

field_distance_to_capsule_axis :: proc(capsule: Field_Capsule, point: World_Position) -> i64 {
	along := clamp(fixed_dot(cast([3]i64)(point - capsule.bottom), capsule.up), 0, capsule.length)
	nearest := capsule.bottom + World_Position(fixed_scale(capsule.up, along))
	return vector_length(cast([3]i64)(point - nearest))
}

// The trilinear density reads a sample from a cell on every side, so a
// changed sample moves the surface anywhere within a spacing of it on each
// axis; a sphere of 7/4 spacing holds that cube.
FIELD_SAMPLE_SUPPORT_QUARTERS :: 7

// Whether a place would raise a sample whose support meets the capsule: a
// dry run over the samples the edit visits, taking those it raises (air,
// or ground of its own material below the target). The budget is not
// applied, so the answer is conservative.
field_place_meets_capsule :: proc(world: ^Field_World, spacing_millimetres: int, edit: Field_Edit, capsule: Field_Capsule) -> bool {
	support := sample_axis_to_position(FIELD_SAMPLE_SUPPORT_QUARTERS, spacing_millimetres) / 4
	first, last := field_edit_bounds(edit, spacing_millimetres)
	for z in first.z ..= last.z {
		for y in first.y ..= last.y {
			for x in first.x ..= last.x {
				sample := Sample_Coordinate{x, y, z}
				old, new_density, reached := field_edit_sample_change(world, spacing_millimetres, edit, sample)
				if !reached || new_density <= old.density || (old.density > 0 && old.material != edit.material) {
					continue
				}
				if field_distance_to_capsule_axis(capsule, sample_to_world_position(sample, spacing_millimetres)) < capsule.radius + support {
					return true
				}
			}
		}
	}
	return false
}

// The ground sample of the cell round the position with the greatest
// density, air when the cell holds none: the material and tint under the
// reticle.
field_ground_sample_at :: proc(world: ^Field_World, spacing_millimetres: int, position: World_Position) -> Field_Sample {
	base, _ := field_cell_of(position, spacing_millimetres)
	best := FIELD_AIR_SAMPLE
	for corner in 0 ..< 8 {
		value := field_world_get_sample(world, base + Sample_Coordinate(field_corner_offset(corner)))
		if value.density > 0 && value.density > best.density {
			best = value
		}
	}
	return best
}
