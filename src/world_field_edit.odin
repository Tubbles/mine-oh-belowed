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
	// Dig: the brush's rate in percent per material, the material table's
	// dig_rate_percent (0179); zero leaves the rate as the brush has it.
	// The tick spreads a fraction of a step over the ticks
	// (scaled_dig_rate).
	dig_rate_percent: [Field_Material]i32,
	tick:     u64,
}

// A material's dig rate bounds (data/materials.sjson).
MINIMUM_DIG_RATE_PERCENT :: 10
MAXIMUM_DIG_RATE_PERCENT :: 400

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

// The brush's rate on ground whose dig rate is percent: rate times
// percent over 100 a tick on average, the fraction carried by the tick
// instead of dropped, so any 100 ticks in a row take exactly rate times
// percent steps. Zero percent leaves the rate.
scaled_dig_rate :: proc(rate, percent: i32, tick: u64) -> i32 {
	if percent == 0 {
		return rate
	}
	scaled := i64(rate) * i64(percent)
	phase := i64(tick % 100)
	return i32(scaled * (phase + 1) / 100 - scaled * phase / 100)
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
	rate := edit.brush.rate
	if edit.mode == .Dig && old.density > 0 {
		rate = scaled_dig_rate(rate, edit.dig_rate_percent[old.material], edit.tick)
	}
	return old, field_edit_step(edit.mode, old.density, field_edit_target(edit, position, spacing_millimetres), rate), true
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

// The impact's dig (work item 0271, doc/architecture.md, The arrival).

// The crater changes only samples whose projection onto the sphere lies
// within its reach of the home, so within the reach, scaled out to the
// relief band's top (reach * (radius + relief) / radius) and a spacing
// for the grid, of the home's axis (the line from the centre through the
// home), at every depth. The unit vector along the axis and that
// distance.
impact_crater_axis :: proc(generation: Planet_Generation) -> (axis: [3]i64, reach: i64) {
	term := generation.crater
	axis, _ = normalize_fixed(term.home)
	relief_reach := metres_to_position_units(MAXIMUM_RELIEF_METRES) + generation.spacing
	return axis, term.reach + term.reach * relief_reach / max(generation.radius, 1) + generation.spacing
}

// Whether any sample of the box can change: its centre within the axis's
// reach plus a spacing and its half diagonal of the axis, on the home's
// side of the centre, the box meeting the relief band down to the stone
// face below it. Squared lengths in i64, no root but the centre's
// distance.
impact_crater_reaches_box :: proc(generation: Planet_Generation, box: Field_Box) -> bool {
	if generation.crater.reach == 0 {
		return false
	}
	axis, reach := impact_crater_axis(generation)
	centre := cast([3]i64)(box.minimum + (box.maximum - box.minimum) / 2)
	half := vector_length(cast([3]i64)(box.maximum - box.minimum)) / 2 + 1
	ahead := fixed_dot(centre, axis)
	offset := centre - fixed_scale(axis, ahead)
	near := reach + generation.spacing + half
	if ahead <= -half || offset.x * offset.x + offset.y * offset.y + offset.z * offset.z > near * near {
		return false
	}
	relief_reach := metres_to_position_units(MAXIMUM_RELIEF_METRES) + generation.spacing
	distance := vector_length(centre)
	return distance - half < generation.radius + relief_reach && distance + half >= generation.radius - relief_reach - metres_to_position_units(DEEP_STONE_DEPTH_METRES)
}

// Writes the chunk's crater overlay (generate_field_chunk) into the
// world, in index order, through field_world_set_sample, so the water,
// the light and the save follow, then frees it. A sample already holding
// the baked value is left. The chunk is the world's. Returns how many
// samples it wrote.
apply_field_crater_overlay :: proc(world: ^Field_World, chunk: ^Field_Chunk) -> (applied: int) {
	origin := field_chunk_origin(chunk.coordinate)
	for entry in chunk.crater_overlay {
		if field_chunk_get_sample(chunk, int(entry.index)) == entry.sample {
			continue
		}
		field_world_set_sample(world, origin + Sample_Coordinate(field_index_to_local(int(entry.index))), entry.sample)
		applied += 1
	}
	drop_field_crater_overlay(chunk)
	return
}

drop_field_crater_overlay :: proc(chunk: ^Field_Chunk) {
	delete(chunk.crater_overlay)
	chunk.crater_overlay = nil
}
