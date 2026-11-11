package game

import "core:slice"
import "core:testing"
import "generation_seed"

// Work item 0314: the relief's range over a box of samples.

// A hashed value of the test's stream from 0 to range - 1.
test_bound_hash :: proc(stream, index: int, range: i64) -> i64 {
	return i64(generation_seed.hash_combine(generation_seed.hash_combine(0x0314, u64(stream)), u64(index)) % u64(range))
}

// A hashed unit direction.
test_bound_direction :: proc(index: int) -> [3]i64 {
	for attempt := 0; ; attempt += 1 {
		vector: [3]i64
		for axis in 0 ..< 3 {
			vector[axis] = test_bound_hash(axis + 3 * attempt, index, 1 << 21) - (1 << 20)
		}
		if unit, ok := normalize_fixed(vector); ok {
			return unit
		}
	}
}

// The most the fade falls from a fraction to any larger one, over every
// fraction from 0 to NOISE_ONE, and how many fractions fade outside 0 to
// NOISE_ONE.
test_fade_fall :: proc(fade: proc(fraction: i64) -> i64) -> (fall: i64, outside: int) {
	least := fade(NOISE_ONE)
	for fraction := i64(NOISE_ONE); fraction >= 0; fraction -= 1 {
		value := fade(fraction)
		least = min(least, value)
		fall = max(fall, value - least)
		outside += value < 0 || value > NOISE_ONE ? 1 : 0
	}
	return
}

// Neither fade is monotone in integers (their truncations dip), so the
// noise ranges widen the fades by FADE_FALL_LIMIT (fade_range).
@(test)
test_the_fades_fall_at_most_the_limit :: proc(t: ^testing.T) {
	testing.expect_value(t, noise_fade(0), 0)
	testing.expect_value(t, noise_fade(NOISE_ONE), NOISE_ONE)
	testing.expect_value(t, quintic_fade(0), 0)
	testing.expect_value(t, quintic_fade(NOISE_ONE), NOISE_ONE)
	for fade in ([2]proc(fraction: i64) -> i64{noise_fade, quintic_fade}) {
		fall, outside := test_fade_fall(fade)
		testing.expectf(t, fall <= FADE_FALL_LIMIT, "a fade falls %d", fall)
		testing.expect_value(t, outside, 0)
	}
}

// How often the procedure falls between neighbours over every noise from
// -NOISE_ONE to NOISE_ONE.
test_falls_over_the_noise :: proc(value: proc(noise: i64, context_value: rawptr) -> i64, context_value: rawptr) -> int {
	falls := 0
	before := value(-NOISE_ONE, context_value)
	for noise in i64(-NOISE_ONE + 1) ..= NOISE_ONE {
		next := value(noise, context_value)
		if next < before {
			falls += 1
		}
		before = next
	}
	return falls
}

@(test)
test_the_relief_terms_are_monotone :: proc(t: ^testing.T) {
	Octave_Case :: struct {
		amplitude_metres: int,
		shape:            Relief_Shape,
	}
	shipped := shipped_test_home_at(8000)
	before := pre_0306_test_home_at(8000)
	design := design_landform_test_planet(8000)
	cases := [?]Octave_Case {
		{shipped.relief_octaves[0].amplitude_metres, shipped.relief_shape},
		{before.relief_octaves[0].amplitude_metres, before.relief_shape},
		{design.relief_octaves[0].amplitude_metres, design.relief_shape},
		{12, {terrace_rise_millimetres = 1200, terrace_riser_permille = 10}},
		{12, {terrace_rise_millimetres = 1200, terrace_riser_permille = 990}},
		{12, {basin_depth_metres = 16, basin_threshold_percent = -90}},
		{12, {basin_depth_metres = 16, basin_threshold_percent = 0}},
		{12, {basin_depth_metres = 16, basin_threshold_percent = 90}},
	}
	for entry in cases {
		octave_case := entry
		falls := test_falls_over_the_noise(proc(noise: i64, context_value: rawptr) -> i64 {
			octave_case := (^Octave_Case)(context_value)
			return long_octave_relief(noise, octave_case.amplitude_metres, octave_case.shape)
		}, &octave_case)
		testing.expectf(t, falls == 0, "long_octave_relief falls %d times at %v", falls, entry)
	}
	for entry in ([5]int{1, 2, 3, 128, MAXIMUM_LEDGE_SHARPNESS}) {
		sharpness := entry
		falls := test_falls_over_the_noise(proc(noise: i64, context_value: rawptr) -> i64 {
			return ledge_profile(noise, (^int)(context_value)^)
		}, &sharpness)
		testing.expectf(t, falls == 0, "ledge_profile falls %d times at sharpness %d", falls, sharpness)
	}
	rises := 0
	for noise in i64(1) ..= NOISE_ONE {
		if landform_ridge(noise) > landform_ridge(noise - 1) || landform_ridge(-noise) > landform_ridge(-noise + 1) {
			rises += 1
		}
	}
	testing.expect_value(t, rises, 0)
	for planet in ([2]Planet{shipped, design}) {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		wild := metres_to_position_units(i64(planet.landforms.wild_metres))
		last := wild * wild * 11 / 10
		falls, unlike := 0, 0
		before_value := home_wildness_fraction(generation, 0)
		for index in i64(1) ..= 10_000 {
			squared := last * index / 10_000
			value := home_wildness_fraction(generation, squared)
			falls += value < before_value ? 1 : 0
			unlike += home_wildness_at_squared(generation, squared) != noise_fade(value) ? 1 : 0
			before_value = value
		}
		testing.expectf(t, falls == 0, "home_wildness_fraction falls %d times", falls)
		testing.expect_value(t, unlike, 0)
	}
	for landmarks in ([2]Planet_Landmarks{shipped.landmarks, design_landmark_test_planet(8000).landmarks}) {
		fall := test_mesa_raise_fall(landmarks)
		testing.expectf(t, fall <= mesa_raise_fall(landmarks), "mesa_raise_at falls %d", fall)
	}
}

// The most mesa_raise_at falls from any earlier value of a sweep: of the
// noise over twice its range at four strengths, of the strength over 1
// to NOISE_ONE at nine noises, every unit.
test_mesa_raise_fall :: proc(landmarks: Planet_Landmarks) -> (fall: i64) {
	for strength in ([4]i64{1, NOISE_ONE / 4, NOISE_ONE / 2, NOISE_ONE}) {
		most := min(i64)
		for noise := i64(-2 * NOISE_ONE); noise <= 2 * NOISE_ONE; noise += 1 {
			value := mesa_raise_at(landmarks, noise, strength)
			most = max(most, value)
			fall = max(fall, most - value)
		}
	}
	for step in i64(-4) ..= 4 {
		noise := step * NOISE_ONE / 4
		most := min(i64)
		for strength := i64(1); strength <= NOISE_ONE; strength += 1 {
			value := mesa_raise_at(landmarks, noise, strength)
			most = max(most, value)
			fall = max(fall, most - value)
		}
	}
	return
}

// The noise of the kind at a point.
test_lattice_noise :: proc(seed: u64, point: [3]i64, wavelength: i64, gradient: bool) -> i64 {
	return gradient ? gradient_noise(seed, point, wavelength) : value_noise(seed, point, wavelength)
}

// A hashed box within 40 km of the origin, its extent up to 2.5
// wavelengths per axis, every fifth flat on one axis.
test_noise_box :: proc(index: int, wavelength: i64) -> Point_Box {
	box: Point_Box
	span := metres_to_position_units(40_000)
	for axis in 0 ..< 3 {
		box.lowest[axis] = test_bound_hash(10 + axis, index, 2 * span) - span
		extent := test_bound_hash(20 + axis, index, 5 * wavelength / 2 + 1)
		if index % 5 == 0 && index / 5 % 3 == axis {
			extent = 0
		}
		box.highest[axis] = box.lowest[axis] + extent
	}
	return box
}

@(test)
test_the_noise_ranges_hold_every_point :: proc(t: ^testing.T) {
	outside := 0
	inexact := 0
	for gradient in ([2]bool{false, true}) {
		for wavelength_metres in ([5]i64{12, 96, 180, 800, 2400}) {
			wavelength := metres_to_position_units(wavelength_metres)
			for index in 0 ..< 300 {
				seed := u64(test_bound_hash(1, index, 1 << 40))
				box := test_noise_box(index, wavelength)
				range := lattice_noise_range(seed, box, wavelength, gradient)
				extent := box.highest - box.lowest
				strides := [3]int{1, 7, 49}
				for point_index in 0 ..< 7 * 7 * 7 + 50 {
					point: [3]i64
					for axis in 0 ..< 3 {
						if point_index < 7 * 7 * 7 {
							step := i64(point_index / strides[axis] % 7)
							point[axis] = box.lowest[axis] + extent[axis] * step / 6
						} else {
							point[axis] = box.lowest[axis] + test_bound_hash(30 + axis, index * 50 + point_index, extent[axis] + 1)
						}
					}
					noise := test_lattice_noise(seed, point, wavelength, gradient)
					if noise < range.lowest || noise > range.highest {
						outside += 1
					}
				}
				single := lattice_noise_range(seed, {box.lowest, box.lowest}, wavelength, gradient)
				noise := test_lattice_noise(seed, box.lowest, wavelength, gradient)
				if single != (Value_Range{noise, noise}) {
					inexact += 1
				}
			}
		}
	}
	testing.expect_value(t, outside, 0)
	testing.expect_value(t, inexact, 0)
}

CURVE_TEST_REACH :: NOISE_ONE + 1000
CURVE_TEST_BLOCK :: 512

// The curve at every noise of the test's reach, with the least and most
// of each block of CURVE_TEST_BLOCK of them, so a range's extremes take
// two partial blocks and the whole ones between.
Curve_Table :: struct {
	values: []i64,
	blocks: []Value_Range,
}

make_curve_table :: proc(knots: [LANDFORM_KNOT_COUNT]int, scale: i64) -> Curve_Table {
	count := int(2 * CURVE_TEST_REACH + 1)
	table := Curve_Table {
		values = make([]i64, count, context.temp_allocator),
		blocks = make([]Value_Range, (count + CURVE_TEST_BLOCK - 1) / CURVE_TEST_BLOCK, context.temp_allocator),
	}
	for &block in table.blocks {
		block = {max(i64), min(i64)}
	}
	for &value, index in table.values {
		value = landform_curve(knots, i64(index) - CURVE_TEST_REACH, scale)
		block := &table.blocks[index / CURVE_TEST_BLOCK]
		block^ = range_union(block^, {value, value})
	}
	return table
}

// The least and most of the curve over a range of noise.
curve_table_range :: proc(table: Curve_Table, noise: Value_Range) -> Value_Range {
	result := Value_Range{max(i64), min(i64)}
	first := int(noise.lowest + CURVE_TEST_REACH)
	last := int(noise.highest + CURVE_TEST_REACH)
	for index := first; index <= last; {
		if index % CURVE_TEST_BLOCK == 0 && index + CURVE_TEST_BLOCK - 1 <= last {
			result = range_union(result, table.blocks[index / CURVE_TEST_BLOCK])
			index += CURVE_TEST_BLOCK
		} else {
			result = range_union(result, {table.values[index], table.values[index]})
			index += 1
		}
	}
	return result
}

// The ranges of the curve that leave a value outside, of 2000 hashed
// ranges of each width; a width of 0 must give the value exactly.
test_curve_range_misses :: proc(knots: [LANDFORM_KNOT_COUNT]int, scale: i64, stream: int) -> int {
	table := make_curve_table(knots, scale)
	widths := [?]i64{0, 1, 10, 100, 1000, 10_000, 2 * NOISE_ONE}
	misses := 0
	for index in 0 ..< 2000 {
		width := widths[index % len(widths)]
		lowest := test_bound_hash(stream, index, 2 * CURVE_TEST_REACH - width + 1) - CURVE_TEST_REACH
		noise := Value_Range{lowest, lowest + width}
		range := landform_curve_range(knots, noise, scale)
		exact := curve_table_range(table, noise)
		if exact.lowest < range.lowest || exact.highest > range.highest || (width == 0 && range != exact) {
			misses += 1
		}
	}
	return misses
}

@(test) // slow
test_the_curve_range_holds_every_noise :: proc(t: ^testing.T) {
	Curve_Case :: struct {
		knots: [LANDFORM_KNOT_COUNT]int,
		scale: i64,
	}
	cases := make([dynamic]Curve_Case, context.temp_allocator)
	for planet in ([2]Planet{shipped_test_home_at(8000), design_landform_test_planet(8000)}) {
		append(&cases, Curve_Case{planet.landforms.region_heights_metres, POSITION_UNITS_PER_METRE})
		append(&cases, Curve_Case{planet.landforms.region_ranges_percent, NOISE_ONE})
		append(&cases, Curve_Case{planet.landforms.region_hills_percent, NOISE_ONE})
	}
	for index in 0 ..< 20 {
		entry: Curve_Case
		heights := index % 2 == 0
		entry.scale = heights ? POSITION_UNITS_PER_METRE : NOISE_ONE
		for &knot, knot_index in entry.knots {
			if heights {
				knot = int(test_bound_hash(40, index * LANDFORM_KNOT_COUNT + knot_index, MAXIMUM_RELIEF_DEPTH_METRES + MAXIMUM_RELIEF_HEIGHT_METRES + 1)) - MAXIMUM_RELIEF_DEPTH_METRES
			} else {
				knot = int(test_bound_hash(41, index * LANDFORM_KNOT_COUNT + knot_index, 101))
			}
		}
		append(&cases, entry)
	}
	for entry, index in cases {
		misses := test_curve_range_misses(entry.knots, entry.scale, 50 + index)
		testing.expectf(t, misses == 0, "%d of the curve %v's ranges miss a value", misses, entry.knots)
		free_all(context.temp_allocator)
	}
}

// The positions of a box's samples: size per axis from the first, the
// step apart.
test_box_positions :: proc(first: Sample_Coordinate, size, step: i32, spacing_millimetres: int) -> (lowest, highest: World_Position) {
	return sample_to_world_position(first, spacing_millimetres), sample_to_world_position(first + (size - 1) * step, spacing_millimetres)
}

// Whether every sample's projection of the box lies in projected_box.
test_projected_box_holds :: proc(generation: Planet_Generation, first: Sample_Coordinate, size, step: i32, spacing_millimetres: int) -> bool {
	lowest, highest := test_box_positions(first, size, step, spacing_millimetres)
	box := projected_box(generation, lowest, highest)
	for index in 0 ..< int(size * size * size) {
		local := [3]i32{i32(index) % size, i32(index) / size % size, i32(index) / (size * size)}
		projected := projected_position(sample_to_world_position(first + Sample_Coordinate(local * step), spacing_millimetres), generation.radius)
		for axis in 0 ..< 3 {
			if projected[axis] < box.lowest[axis] || projected[axis] > box.highest[axis] {
				return false
			}
		}
	}
	return true
}

// The axis directions and the diagonals of the axis planes.
TEST_AXIS_PLANE_DIRECTIONS :: [?][3]i64 {
	{1, 0, 0}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}, {0, 0, 1}, {0, 0, -1},
	{1, 1, 0}, {-1, 1, 0}, {1, -1, 0}, {-1, -1, 0},
	{1, 0, 1}, {-1, 0, 1}, {1, 0, -1}, {-1, 0, -1},
	{0, 1, 1}, {0, -1, 1}, {0, 1, -1}, {0, -1, -1},
}

@(test) // slow
test_the_projected_box_holds_every_sample :: proc(t: ^testing.T) {
	Box_Case :: struct {
		size, step:          i32,
		spacing_millimetres: int,
	}
	box_cases := [?]Box_Case{{8, 1, 1000}, {8, 2, 1000}, {8, 4, 1000}, {8, 8, 1000}, {8, 1, 333}, {4, 1, 1000}, {4, 2, 1000}, {4, 4, 1000}, {4, 8, 1000}, {4, 1, 333}}
	axis_plane_directions := TEST_AXIS_PLANE_DIRECTIONS
	failures := 0
	for radius_metres in ([4]int{1000, 4000, 8000, 16000}) {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, shipped_test_home_at(radius_metres), 1000)
		heights := [3]i64{generation.relief_lowest - metres_to_position_units(60), (generation.relief_lowest + generation.relief_highest) / 2, generation.relief_highest + metres_to_position_units(10)}
		for index in 0 ..< 200 + len(axis_plane_directions) {
			direction: [3]i64
			if index < len(axis_plane_directions) {
				direction, _ = normalize_fixed(axis_plane_directions[index] * UNIT_VECTOR_ONE)
			} else {
				direction = test_bound_direction(index)
			}
			for height in heights {
				position := World_Position(fixed_scale(direction, generation.radius + height))
				for entry in box_cases {
					first := world_position_to_sample(position, entry.spacing_millimetres)
					if !test_projected_box_holds(generation, first, entry.size, entry.step, entry.spacing_millimetres) {
						failures += 1
					}
				}
			}
		}
	}
	testing.expect_value(t, failures, 0)
}

// The places of the bound tests on the generation's sphere: the home, the
// spring at (79, 151), the nearest site of each kind, with caves (0327)
// the spring's cave mouth and the nearest notch of each kind
// (test_cave_places), and hashed directions.
test_bound_places :: proc(generation: Planet_Generation, hashed: int) -> [dynamic][3]i64 {
	places := make([dynamic][3]i64, context.temp_allocator)
	append(&places, generation.landform_home)
	append(&places, test_degree_point(generation, 79, 151))
	if generation.landmarks.site_spacing_metres > 0 {
		for kind in Landmark_Kind {
			if kind == .None {
				continue
			}
			if sites := test_landmark_sites(generation, kind, 1500); len(sites) > 0 {
				append(&places, sites[0].centre)
			}
		}
	}
	for position in test_cave_places(generation) {
		append(&places, projected_position(position, generation.radius))
	}
	for index in 0 ..< hashed {
		append(&places, fixed_scale(test_bound_direction(1000 + index), generation.radius))
	}
	return places
}

// The samples of the box whose uncratered column's relief lies outside
// the box's range, or whose carve is a carving kind the range does not
// flag.
test_relief_box_misses :: proc(generation: Planet_Generation, first: Sample_Coordinate, size, step: i32) -> int {
	lowest, highest := test_box_positions(first, size, step, generation.spacing_millimetres)
	relief, carving, _, _ := uncratered_relief_range(generation, projected_box(generation, lowest, highest))
	misses := 0
	for index in 0 ..< int(size * size * size) {
		local := [3]i32{i32(index) % size, i32(index) / size % size, i32(index) / (size * size)}
		position := sample_to_world_position(first + Sample_Coordinate(local * step), generation.spacing_millimetres)
		column := uncratered_column(generation, projected_position(position, generation.radius))
		if column.relief < relief.lowest || column.relief > relief.highest || (column.carve.site.kind in CARVING_KINDS && !carving) {
			misses += 1
		}
	}
	return misses
}

// The samples of the box whose density a cave changes (sample_depth
// against the same without the cave) while the box's bound says no cave,
// the sample lies at or under its cave floor or cave_sample_clear holds;
// and those a notch changes (against column_depth) while the bound says
// no notch or the sample lies at or under its notch floor (0327).
test_cave_box_misses :: proc(generation: Planet_Generation, first: Sample_Coordinate, size, step: i32) -> int {
	lowest, highest := test_box_positions(first, size, step, generation.spacing_millimetres)
	bound := relief_box_bound(generation, lowest, highest)
	if bound.crater {
		return 0
	}
	misses := 0
	for index in 0 ..< int(size * size * size) {
		local := [3]i32{i32(index) % size, i32(index) / size % size, i32(index) / (size * size)}
		position := sample_to_world_position(first + Sample_Coordinate(local * step), generation.spacing_millimetres)
		_, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
		if !needs_relief {
			continue
		}
		height := distance - generation.radius
		column := surface_column(generation, on_sphere)
		caved := depth_to_density(sample_depth(generation, column, cave_column(generation, column, on_sphere), position, distance, on_sphere), generation.spacing_millimetres)
		notched := depth_to_density(sample_depth(generation, column, {}, position, distance, on_sphere), generation.spacing_millimetres)
		plain := depth_to_density(column_depth(column, height), generation.spacing_millimetres)
		if caved != notched && (!bound.caves || height <= bound.cave_floor || cave_sample_clear(generation, bound, position, distance, on_sphere)) {
			misses += 1
		}
		if notched != plain && (!bound.undercut || height <= bound.undercut_floor) {
			misses += 1
		}
	}
	return misses
}

@(test) // slow
test_the_relief_box_bound_holds_every_sample :: proc(t: ^testing.T) {
	planets := [?]Planet {
		shipped_test_home_at(4000),
		shipped_test_home_at(8000),
		shipped_test_home_at(16000),
		design_landform_test_planet(8000),
		design_landmark_test_planet(8000),
		design_carving_test_planet(8000),
		design_caves_test_planet(8000),
		pre_0306_test_home_at(8000),
	}
	for planet, planet_index in planets {
		generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
		misses := 0
		for place in test_bound_places(generation, 40) {
			up, _ := normalize_fixed(place)
			relief := uncratered_relief(generation, place)
			for under in ([3]i64{0, 8, 40}) {
				position := World_Position(fixed_scale(up, generation.radius + relief - metres_to_position_units(under)))
				first := world_position_to_sample(position, generation.spacing_millimetres)
				for size in ([2]i32{8, 4}) {
					for step in ([2]i32{1, 8}) {
						misses += test_relief_box_misses(generation, first, size, step)
						misses += test_cave_box_misses(generation, first, size, step)
					}
				}
			}
		}
		testing.expectf(t, misses == 0, "planet %d: %d samples outside their box's range", planet_index, misses)
		free_all(context.temp_allocator)
	}
}

// The chunk generated with the crater's overlay against the samples one
// by one: the bytes, the sky light (none in ground and in shaded air) and
// the overlay, which with the crater at the impact lists exactly the
// samples impact_crater_sample changes, in index order. Returns the
// samples that differ.
test_bounded_chunk_differences :: proc(planet: Planet, generation: Planet_Generation, coordinate: Field_Chunk_Coordinate, seed: u64 = DEFAULT_WORLD_SEED) -> int {
	chunk := new(Field_Chunk, context.temp_allocator)
	generate_field_chunk(seed, planet, generation.spacing_millimetres, coordinate, chunk, crater_overlay = true)
	defer drop_field_crater_overlay(chunk)
	origin := field_chunk_origin(coordinate)
	differences := 0
	overlay := 0
	for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		position := sample_to_world_position(origin + Sample_Coordinate(field_index_to_local(index)), generation.spacing_millimetres)
		sample, shaded, _ := planet_sample_reading(generation, position)
		sky := sample.density > 0 || shaded ? 0 : FIELD_LIGHT_FULL
		if field_chunk_get_sample(chunk, index) != sample || chunk.sky_light[index] != u8(sky) {
			differences += 1
		}
		if !planet.crater_at_impact {
			continue
		}
		if baked, changed := impact_crater_sample(generation, position); changed {
			listed := overlay < len(chunk.crater_overlay) && chunk.crater_overlay[overlay] == Field_Crater_Sample{index = i32(index), sample = baked}
			differences += listed ? 0 : 1
			overlay += 1
		}
	}
	return differences + abs(len(chunk.crater_overlay) - overlay)
}

// The node's generated grid against the samples one by one at its step's
// generation, and planet_sample_reading_boxed against them too. Returns
// the samples that differ.
test_bounded_grid_differences :: proc(generation: Planet_Generation, node: Field_Node) -> int {
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	coarse := field_grid_generation(generation, grid.step)
	boxes := new(Relief_Boxes, context.temp_allocator)
	boxes^ = {
		first               = grid.origin - grid.step,
		step                = grid.step,
		samples             = FIELD_GRID_SIZE,
		spacing_millimetres = generation.spacing_millimetres,
	}
	differences := 0
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				position := sample_to_world_position(grid.origin + Sample_Coordinate([3]i32{x, y, z} * grid.step), generation.spacing_millimetres)
				sample, shaded, carved := planet_sample_reading(coarse, position)
				index := field_grid_index({x, y, z})
				sky := field_sample_is_ground(sample.density) || shaded ? 0 : FIELD_LIGHT_FULL
				if (Field_Sample{grid.density[index], grid.material[index], grid.tint[index]}) != sample || grid.sky_light[index] != u8(sky) {
					differences += 1
				}
				boxed, boxed_shaded, boxed_carved := planet_sample_reading_boxed(coarse, position, boxes, {x + 1, y + 1, z + 1})
				if boxed != sample || boxed_shaded != shaded || boxed_carved != carved {
					differences += 1
				}
			}
		}
	}
	return differences
}

// The surface's position at a point on the sphere, raised by a height.
test_surface_position :: proc(generation: Planet_Generation, point: [3]i64, height: i64) -> World_Position {
	up, _ := normalize_fixed(point)
	return World_Position(fixed_scale(up, generation.radius + surface_relief(generation, point) + height))
}

// The positions the generation test reads round: the home's surface, a
// chunk over it and one and two under it, the spring's surface, an
// arch's and a grotto's, with caves the spring's cave mouth and the
// nearest notches (test_cave_places), and four hashed directions'
// surfaces.
test_bounded_positions :: proc(generation: Planet_Generation) -> [dynamic]World_Position {
	positions := make([dynamic]World_Position, context.temp_allocator)
	home := generation.landform_home
	chunk := metres_to_position_units(FIELD_CHUNK_SIZE) * i64(generation.spacing_millimetres) / MILLIMETRES_PER_METRE
	for height in ([4]i64{0, chunk, -chunk, -2 * chunk}) {
		append(&positions, test_surface_position(generation, home, height))
	}
	append(&positions, test_surface_position(generation, test_degree_point(generation, 79, 151), 0))
	if generation.landmarks.site_spacing_metres > 0 {
		for kind in ([2]Landmark_Kind{.Arch, .Grotto}) {
			if sites := test_landmark_sites(generation, kind, 1500); len(sites) > 0 {
				append(&positions, sample_to_world_position(test_site_sample(generation, sites[0], true, metres_to_position_units(2)), generation.spacing_millimetres))
			}
		}
	}
	for position in test_cave_places(generation) {
		append(&positions, position)
	}
	for index in 0 ..< 4 {
		append(&positions, test_surface_position(generation, fixed_scale(test_bound_direction(2000 + index), generation.radius), 0))
	}
	return positions
}

// With caves (0327) the spring's cave mouth (its open sample) and the
// centres of the nearest gorge's and mesa's notches, those found.
test_cave_places :: proc(generation: Planet_Generation) -> [dynamic]World_Position {
	positions := make([dynamic]World_Position, context.temp_allocator)
	if generation.caves == {} {
		return positions
	}
	if open, _, found := test_cave_mouth(generation, test_bound_camera(generation, 79, 151)); found {
		append(&positions, sample_to_world_position(open, generation.spacing_millimetres))
	}
	for kind in Notch_Kind {
		if point, notch, found := test_nearest_notch(generation, kind); found {
			up, _ := normalize_fixed(point)
			append(&positions, World_Position(fixed_scale(up, generation.radius + notch.centre)))
		}
	}
	return positions
}

// The chunks and the nodes of levels 1 to 3 round the places
// (test_bounded_positions) against the samples one by one; each node
// once, since the places round the home share the coarse ones. One test
// per planet, so the runner spreads them over its threads.
test_bounded_generation_differences :: proc(planet: Planet) -> (chunk_differences, grid_differences: int) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	nodes := make([dynamic]Field_Node, context.temp_allocator)
	for position in test_bounded_positions(generation) {
		coordinate := sample_to_field_chunk_coordinate(world_position_to_sample(position, generation.spacing_millimetres))
		chunk_differences += test_bounded_chunk_differences(planet, generation, coordinate)
		for level in i32(1) ..= 3 {
			if node := test_surface_node(position, generation.spacing_millimetres, level); !slice.contains(nodes[:], node) {
				append(&nodes, node)
			}
		}
	}
	for node in nodes {
		grid_differences += test_bounded_grid_differences(generation, node)
	}
	return
}

// The shipped home with the crater dug at the impact, so the chunks list
// its overlay; with its caves (0327), whose mouth and notches the places
// hold.
@(test) // slow
test_the_bounded_generation_matches_the_samples :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.crater_at_impact = true
	chunk_differences, grid_differences := test_bounded_generation_differences(planet)
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

@(test) // slow
test_the_bounded_generation_matches_the_samples_with_the_crater_baked :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.crater_at_impact = false
	chunk_differences, grid_differences := test_bounded_generation_differences(planet)
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

// The shipped home without its caves: 0314's case.
@(test) // slow
test_the_bounded_generation_matches_the_samples_without_the_caves :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.crater_at_impact = true
	planet.caves = {}
	chunk_differences, grid_differences := test_bounded_generation_differences(planet)
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

// Notch air whose box of 4 holds no cave, open to the sky through a
// tunnel 3 m up its radial (seed 7, found by 0327's verification): the
// chunk leaves it unshaded as the samples do, the march reading the
// column's caves whatever the box's flag.
@(test) // slow
test_the_bounded_chunk_shades_notch_air_under_a_tunnel :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	generation := make_planet_generation(7, planet, 1000)
	sample := Sample_Coordinate{-1630, 7759, 1289}
	coordinate := sample_to_field_chunk_coordinate(sample)
	testing.expect_value(t, coordinate, Field_Chunk_Coordinate{-51, 242, 40})
	position := sample_to_world_position(sample, 1000)
	_, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
	testing.expect(t, needs_relief, "the sample reads its column")
	boxes := new(Relief_Boxes, context.temp_allocator)
	boxes^ = {
		first               = field_chunk_origin(coordinate),
		step                = 1,
		samples             = FIELD_CHUNK_SIZE,
		spacing_millimetres = 1000,
	}
	_, decided, caves := planet_sample_by_boxes(generation, boxes, cast([3]i32)(sample - boxes.first), position, distance, on_sphere)
	testing.expect(t, !decided && !caves, "the box of 4 leaves the sample to its column without caves")
	value, shaded, _ := planet_sample_reading(generation, position)
	testing.expect(t, value.density <= 0 && !shaded, "the sample is air open through the tunnel")
	testing.expect_value(t, test_bounded_chunk_differences(planet, generation, coordinate, 7), 0)
}

// Dense caves at the shores of the three lakes nearest the shipped home
// with tiles (0339): the first two shore chunks holding more than 20
// samples of cave air and the nodes of levels 1 to 3 at their centres
// against the samples one by one. A sample read alone reads the tiles'
// lakes in place (water_tile_cave_lake_fade), a chunk or a grid its list,
// so this is also the two paths' parity.
@(test) // slow
test_the_bounded_generation_matches_the_samples_by_a_lake :: proc(t: ^testing.T) {
	planet := shipped_test_home_at(8000)
	planet.caves = DENSE_TEST_CAVES
	planet.water_tiles = make_water_tile_cache(DEFAULT_WORLD_SEED, planet)
	defer destroy_water_tile_cache(planet.water_tiles)
	generation := make_planet_generation(DEFAULT_WORLD_SEED, planet, 1000)
	nearest := test_nearest_lakes(generation, planet.water_tiles, 3)
	defer {
		for lake in nearest {
			delete(lake.mask)
		}
		delete(nearest)
	}
	candidates := make([dynamic]Field_Chunk_Coordinate)
	defer delete(candidates)
	for lake in nearest {
		for coordinate in test_lake_shore_chunks(generation, lake, 8) {
			append(&candidates, coordinate)
		}
		free_all(context.temp_allocator)
	}
	without := planet
	without.caves = {}
	caved := new(Field_Chunk)
	defer free(caved)
	plain := new(Field_Chunk)
	defer free(plain)
	chunks := make([dynamic]Field_Chunk_Coordinate)
	defer delete(chunks)
	for coordinate in candidates {
		if len(chunks) == 2 {
			break
		}
		if slice.contains(chunks[:], coordinate) {
			continue
		}
		caved^ = {}
		plain^ = {}
		generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate, caved)
		generate_field_chunk(DEFAULT_WORLD_SEED, without, 1000, coordinate, plain)
		free_all(context.temp_allocator)
		cave_air := 0
		for sample in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			cave_air += caved.density[sample] <= 0 && plain.density[sample] > 0 ? 1 : 0
		}
		if cave_air > 20 {
			append(&chunks, coordinate)
		}
	}
	testing.expect_value(t, len(chunks), 2)
	nodes := make([dynamic]Field_Node)
	defer delete(nodes)
	chunk_differences, grid_differences := 0, 0
	for coordinate in chunks {
		chunk_differences += test_bounded_chunk_differences(planet, generation, coordinate)
		free_all(context.temp_allocator)
		position := sample_to_world_position(field_chunk_origin(coordinate) + FIELD_CHUNK_SIZE / 2, 1000)
		for level in i32(1) ..= 3 {
			if node := test_surface_node(position, 1000, level); !slice.contains(nodes[:], node) {
				append(&nodes, node)
			}
		}
	}
	for node in nodes {
		grid_differences += test_bounded_grid_differences(generation, node)
		free_all(context.temp_allocator)
	}
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

@(test) // slow
test_the_bounded_generation_matches_the_samples_before_0306 :: proc(t: ^testing.T) {
	chunk_differences, grid_differences := test_bounded_generation_differences(pre_0306_test_home_at(8000))
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

@(test) // slow
test_the_bounded_generation_matches_the_samples_with_the_carving :: proc(t: ^testing.T) {
	chunk_differences, grid_differences := test_bounded_generation_differences(design_carving_test_planet(8000))
	testing.expect_value(t, chunk_differences, 0)
	testing.expect_value(t, grid_differences, 0)
}

// The camera 2 m over the ground at a latitude and longitude.
test_bound_camera :: proc(generation: Planet_Generation, latitude, longitude: int) -> World_Position {
	return test_surface_position(generation, test_degree_point(generation, latitude, longitude), metres_to_position_units(2))
}

// Of the samples the shortcut sends to the relief in the 7 by 7 by 7
// chunks round the camera's, those the box bound leaves to the column.
test_box_bound_left :: proc(generation: Planet_Generation, camera: World_Position) -> (needing, left: int) {
	centre := sample_to_field_chunk_coordinate(world_position_to_sample(camera, generation.spacing_millimetres))
	boxes := new(Relief_Boxes, context.temp_allocator)
	for chunk_z in i32(-3) ..= 3 {
		for chunk_y in i32(-3) ..= 3 {
			for chunk_x in i32(-3) ..= 3 {
				origin := field_chunk_origin(centre + {chunk_x, chunk_y, chunk_z})
				boxes^ = {
					first               = origin,
					step                = 1,
					samples             = FIELD_CHUNK_SIZE,
					spacing_millimetres = generation.spacing_millimetres,
				}
				for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
					local := field_index_to_local(index)
					position := sample_to_world_position(origin + Sample_Coordinate(local), generation.spacing_millimetres)
					_, distance, on_sphere, needs_relief := planet_sample_shortcut(generation, position)
					if !needs_relief {
						continue
					}
					needing += 1
					if _, decided, _ := planet_sample_by_boxes(generation, boxes, local, position, distance, on_sphere); !decided {
						left += 1
					}
				}
			}
		}
	}
	return
}

// The bound leaves 1.33M of 8.43M (15.8 percent) round the spring, 1.49M
// (17.7 percent) with the caves (0327).
@(test) // slow
test_the_box_bound_leaves_few_columns :: proc(t: ^testing.T) {
	generation := make_planet_generation(DEFAULT_WORLD_SEED, shipped_test_home_at(8000), 1000)
	needing, left := test_box_bound_left(generation, test_bound_camera(generation, 79, 151))
	testing.expectf(t, needing > 0 && left * 100 < needing * 20, "the bound leaves %d of %d samples", left, needing)
}
