package game

import "base:intrinsics"
import "core:slice"

// The water field (work item 0172, doc/architecture.md, The water field):
// a fill per sample beside the terrain, 0 empty to FIELD_WATER_FULL, held
// only where the terrain density is at or below zero. Integer only and in
// one order, so every machine of a lockstep game moves the water alike.
//
// A sample's water fills its cell from the bottom along the radial: the
// cell's middle is the sample's distance to the planet's centre and its
// height the radial extent of the sample's cube (Field_Water_Span), so
// the water's level is the cell's bottom plus the fill's share of the
// height, in fill units (FIELD_WATER_FULL a sample) from the centre
// (field_water_level). The height makes the cells a level surface crosses
// a band that touches face to face on any slope of the sphere, which a
// height of one sample is not off the axes, so water levels there too.
// Each tick every sample awake when the tick began, chunks in coordinate
// order and samples in sample order (z, then y, then x, rising), moves
// fill to its six neighbours: first to those nearer the centre, then to
// the others, the fill that makes the two levels equal, rounded towards
// the mover, at most the room, the rate and the fill the sample held when
// the tick began. Down a column that is at least what fits, so the water
// falls until the cell below is full; across, it levels. Water arriving
// in a tick moves on in the next, so it spreads alike in every direction. A sample whose fill did
// not change for the still ticks sleeps; any change wakes the sample and
// those of its six neighbours that have something to do. Fill at or below
// the minimum on dry ground (a film) stops moving and drops by one every
// dry ticks. Volume is conserved but at the sources, the drying and a
// terrain place that has nowhere to push the water it displaces.
//
// Sources: a spring sample (the source bit, set by the generation) is
// refilled to full, and a sea edge sample (beside a missing sample that
// is sea) to the sea's fill at its level, each tick they are awake. A
// missing chunk's sample holds the sea's fill when the generation makes it
// air (field_sea_fill), and is a wall otherwise.

FIELD_SAMPLE_BIT_WORDS :: FIELD_CHUNK_SAMPLE_COUNT / 64
// One bit per sample, by sample index.
Field_Sample_Bits :: [FIELD_SAMPLE_BIT_WORDS]u64

// The six neighbours in sample order.
FIELD_WATER_NEIGHBOUR_OFFSETS :: [6][3]i32{{0, 0, -1}, {0, -1, 0}, {-1, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 1}}

// A sample's distance to the centre is taken in 1/2^FIELD_WATER_DISTANCE_SHIFT
// of a sample; the shifted square stays inside a u64 out to
// FAR_LIMIT_METRES at the finest spacing.
FIELD_WATER_DISTANCE_SHIFT :: 10
// The water's density for the mesher of full water in a cell on an axis:
// half a sample in the terrain's scale (DENSITY_STEPS_PER_SAMPLE a
// sample).
FIELD_WATER_DENSITY_HALF :: DENSITY_STEPS_PER_SAMPLE / 2

// A sample's cell as the water fills it, in fill units from the centre:
// the middle at the sample's distance, the height the radial extent of the
// sample's cube, |n.x| + |n.y| + |n.z| samples for the radial unit n (one
// on an axis, up to the square root of three on a diagonal).
Field_Water_Span :: struct {
	middle: i64,
	height: i64,
}

// field_water of data/game.sjson in the world's units.
Field_Water_Tuning :: struct {
	// Fill per tick per neighbour.
	rate:         i32,
	still_ticks:  u8,
	minimum_fill: i32,
	dry_ticks:    u64,
}

// The planet a field world lies on, as the water reads it: the generation
// for the samples outside the loaded chunks, and the sea's level in fill
// units from the centre. The zero value has no sea.
Field_Water_Planet :: struct {
	generation: Planet_Generation,
	sea_level:  i64,
}

// chunk is nil when the neighbour's chunk is not loaded; sea is then the
// missing sample's fill (field_sea_fill, 0 for a wall).
Field_Water_Neighbour :: struct {
	chunk:  ^Field_Chunk,
	index:  int,
	sample: Sample_Coordinate,
	span:   Field_Water_Span,
	sea:    i32,
}

// One chunk's step in a tick: the samples awake and their fills when the
// tick began.
Field_Water_Pass :: struct {
	chunk: ^Field_Chunk,
	awake: Field_Sample_Bits,
	start: [FIELD_CHUNK_SAMPLE_COUNT]u8,
}

make_field_water_tuning :: proc(config: Field_Water_Config) -> Field_Water_Tuning {
	return Field_Water_Tuning {
		rate = i32(config.fill_rate_per_tick),
		still_ticks = u8(config.still_ticks_to_sleep),
		minimum_fill = i32(config.minimum_fill),
		dry_ticks = u64(config.dry_ticks_per_step),
	}
}

make_field_water_planet :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Water_Planet {
	return {generation = make_planet_generation(seed, planet, spacing_millimetres), sea_level = field_sea_level(planet, spacing_millimetres)}
}

// The sea's surface, the radius plus the sea level, in fill units from
// the centre, floored.
field_sea_level :: proc(planet: Planet, spacing_millimetres: int) -> i64 {
	return (i64(planet.radius_metres) + i64(planet.sea_level_metres)) * MILLIMETRES_PER_METRE * FIELD_WATER_FULL / i64(spacing_millimetres)
}

// The sample's distance to the centre in 1/2^FIELD_WATER_DISTANCE_SHIFT
// samples, floored.
field_water_fine_distance :: proc(sample: Sample_Coordinate) -> i64 {
	x, y, z := u64(abs(i64(sample.x))), u64(abs(i64(sample.y))), u64(abs(i64(sample.z)))
	return i64(integer_square_root((x * x + y * y + z * z) << (2 * FIELD_WATER_DISTANCE_SHIFT)))
}

field_water_span :: proc(sample: Sample_Coordinate) -> Field_Water_Span {
	fine := field_water_fine_distance(sample)
	taxicab := abs(i64(sample.x)) + abs(i64(sample.y)) + abs(i64(sample.z))
	height := i64(FIELD_WATER_FULL)
	if fine > 0 {
		height = max(height, (taxicab << FIELD_WATER_DISTANCE_SHIFT) * FIELD_WATER_FULL / fine)
	}
	return {middle = fine * FIELD_WATER_FULL >> FIELD_WATER_DISTANCE_SHIFT, height = height}
}

field_water_bottom :: proc(span: Field_Water_Span) -> i64 {
	return span.middle - span.height / 2
}

// The water's level in a cell: its bottom plus the fill's share of its
// height.
field_water_level :: proc(span: Field_Water_Span, fill: i32) -> i64 {
	return field_water_bottom(span) + i64(fill) * span.height / FIELD_WATER_FULL
}

// The level times FIELD_WATER_FULL, exact: the levelling compares these,
// so a move of one fill changes a difference by exactly the two heights
// and never turns back on a rounding.
field_water_level_exact :: proc(span: Field_Water_Span, fill: i32) -> i64 {
	return field_water_bottom(span) * FIELD_WATER_FULL + i64(fill) * span.height
}

// The fill the sea gives a cell: what lies below the sea level, from none
// to full, so the cell's level is the sea's within a fill.
field_sea_fill :: proc(sea_level: i64, span: Field_Water_Span) -> i32 {
	return i32(clamp(floor_divide_i64((sea_level - field_water_bottom(span)) * FIELD_WATER_FULL, span.height), 0, FIELD_WATER_FULL))
}

field_sample_bit :: proc(bits: ^Field_Sample_Bits, index: int) -> bool {
	return bits[index >> 6] & (u64(1) << uint(index & 63)) != 0
}

set_field_sample_bit :: proc(bits: ^Field_Sample_Bits, index: int) {
	bits[index >> 6] |= u64(1) << uint(index & 63)
}

clear_field_sample_bit :: proc(bits: ^Field_Sample_Bits, index: int) {
	bits[index >> 6] &~= u64(1) << uint(index & 63)
}

field_sample_bits_any :: proc(bits: ^Field_Sample_Bits) -> bool {
	for word in bits {
		if word != 0 {
			return true
		}
	}
	return false
}

// The water as the mesher's density: its level over the sample's own
// distance in the terrain's scale (DENSITY_STEPS_PER_SAMPLE a sample),
// a signed distance to the surface wherever the sample sits, so a level
// surface crosses every grid edge at its level. Full water is half the
// cell's height above the sample (FIELD_WATER_DENSITY_HALF on an axis),
// empty water half below, and ground -MAXIMUM_DENSITY, so the water's
// surface closes against the terrain, which the terrain mesh covers.
field_water_density :: proc(terrain: i8, fill: u8, sample: Sample_Coordinate) -> i8 {
	if terrain > 0 {
		return -MAXIMUM_DENSITY
	}
	span := field_water_span(sample)
	steps := floor_divide_i64((field_water_level(span, i32(fill)) - span.middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL)
	return i8(clamp(steps, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// A missing sample's fill: the sea's where the generation makes it air, 0
// (a wall) in ground.
field_missing_sample_sea :: proc(planet: Field_Water_Planet, sample: Sample_Coordinate, span: Field_Water_Span) -> i32 {
	fill := field_sea_fill(planet.sea_level, span)
	if fill == 0 || planet_sample(planet.generation, sample_to_world_position(sample, planet.generation.spacing_millimetres)).density > 0 {
		return 0
	}
	return fill
}

field_chunk_sample :: proc(chunk: ^Field_Chunk, index: int) -> Sample_Coordinate {
	return field_chunk_origin(chunk.coordinate) + Sample_Coordinate(field_index_to_local(index))
}

// The chunk and index of the sample beside sample at offset; nil when its
// chunk is not loaded. chunk holds sample.
field_water_cell :: proc(world: ^Field_World, chunk: ^Field_Chunk, sample: Sample_Coordinate, offset: [3]i32) -> (neighbour: ^Field_Chunk, index: int) {
	next := sample + Sample_Coordinate(offset)
	local := next - field_chunk_origin(chunk.coordinate)
	neighbour = chunk
	for axis in 0 ..< 3 {
		if local[axis] < 0 || local[axis] >= FIELD_CHUNK_SIZE {
			neighbour = world.chunks[sample_to_field_chunk_coordinate(next)] or_else nil
			break
		}
	}
	return neighbour, sample_to_field_index(next)
}

field_water_neighbours :: proc(world: ^Field_World, chunk: ^Field_Chunk, sample: Sample_Coordinate) -> [6]Field_Water_Neighbour {
	neighbours: [6]Field_Water_Neighbour
	for offset, slot in FIELD_WATER_NEIGHBOUR_OFFSETS {
		next := sample + Sample_Coordinate(offset)
		neighbour := &neighbours[slot]
		neighbour.chunk, neighbour.index = field_water_cell(world, chunk, sample, offset)
		neighbour.sample = next
		neighbour.span = field_water_span(next)
		if neighbour.chunk == nil {
			neighbour.sea = field_missing_sample_sea(world.water_planet, next, neighbour.span)
		}
	}
	return neighbours
}

// The fill the neighbour can take: none in ground or a missing chunk.
field_water_room :: proc(neighbour: Field_Water_Neighbour) -> i32 {
	if neighbour.chunk == nil || neighbour.chunk.density[neighbour.index] > 0 {
		return 0
	}
	return FIELD_WATER_FULL - i32(neighbour.chunk.water[neighbour.index])
}

// The fill the neighbour shows: a missing sea sample is the sea outside
// the simulated region.
field_water_neighbour_fill :: proc(neighbour: Field_Water_Neighbour) -> i32 {
	if neighbour.chunk == nil {
		return neighbour.sea
	}
	if neighbour.chunk.density[neighbour.index] > 0 {
		return 0
	}
	return i32(neighbour.chunk.water[neighbour.index])
}

// Whether a sample has anything to do awake: it holds water, or it is
// air that can be a source (a spring, or below sea level beside the sea).
field_water_can_wake :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) -> bool {
	if chunk.water[index] > 0 || field_sample_bit(&chunk.water_source, index) {
		return true
	}
	return chunk.density[index] <= 0 && field_sample_below_sea(world, chunk, index)
}

field_sample_below_sea :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) -> bool {
	return field_sea_fill(world.water_planet.sea_level, field_water_span(field_chunk_sample(chunk, index))) > 0
}

wake_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) {
	if !field_water_can_wake(world, chunk, index) {
		return
	}
	chunk.water_still[index] = 0
	if !field_sample_bit(&chunk.water_awake, index) {
		set_field_sample_bit(&chunk.water_awake, index)
		world.water_awake_chunks[chunk.coordinate] = {}
	}
}

// Sleeping leaves the still ticks at zero, so a settled chunk equals its
// generation again.
sleep_field_water_sample :: proc(chunk: ^Field_Chunk, index: int) {
	clear_field_sample_bit(&chunk.water_awake, index)
	chunk.water_still[index] = 0
}

// The sample and its six neighbours in loaded chunks.
wake_field_water_around :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	wake_field_water_sample(world, chunk, index)
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		if neighbour, neighbour_index := field_water_cell(world, chunk, sample, offset); neighbour != nil {
			wake_field_water_sample(world, neighbour, neighbour_index)
		}
	}
}

// Every change of a fill goes through here: the chunks that mesh the
// sample are marked, and the sample and its neighbours wake.
set_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	chunk.water[index] = u8(fill)
	mark_field_chunks_around_sample_dirty(world, chunk.coordinate, sample)
	world.edited_chunks[chunk.coordinate] = {}
	wake_field_water_around(world, chunk, index, sample)
}

// A place turned a wet sample into ground: its fill goes to the
// neighbours with room in sample order, and what fits nowhere is dropped
// and counted.
displace_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	left := i32(chunk.water[index])
	set_field_water(world, chunk, index, sample, 0)
	for neighbour in field_water_neighbours(world, chunk, sample) {
		amount := min(left, field_water_room(neighbour))
		if amount > 0 {
			set_field_water(world, neighbour.chunk, neighbour.index, neighbour.sample, i32(neighbour.chunk.water[neighbour.index]) + amount)
			left -= amount
		}
	}
	world.water_dropped += i64(left)
}

// After a terrain set (field_world_set_sample): ground pushes the water
// out, and the sample and its neighbours wake, so a dug hole floods on
// the next tick.
follow_field_terrain_with_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	if chunk.density[index] > 0 && chunk.water[index] > 0 {
		displace_field_water(world, chunk, index, sample)
	}
	wake_field_water_around(world, chunk, index, sample)
}

// The samples of a loaded neighbour's face towards the chunk at
// coordinate, with the index of the sample across the face in that chunk.
// offset leads from coordinate to the neighbour.
field_face_pairs :: proc(offset: [3]i32, allocator := context.temp_allocator) -> [dynamic][2]int {
	pairs := make([dynamic][2]int, 0, FIELD_CHUNK_SIZE * FIELD_CHUNK_SIZE, allocator)
	axis := offset.x != 0 ? 0 : (offset.y != 0 ? 1 : 2)
	face, across: [3]i32
	face[axis] = offset[axis] < 0 ? FIELD_CHUNK_SIZE - 1 : 0
	across[axis] = offset[axis] < 0 ? 0 : FIELD_CHUNK_SIZE - 1
	for first in i32(0) ..< FIELD_CHUNK_SIZE {
		for second in i32(0) ..< FIELD_CHUNK_SIZE {
			face[(axis + 1) % 3], face[(axis + 2) % 3] = first, second
			across[(axis + 1) % 3], across[(axis + 2) % 3] = first, second
			append(&pairs, [2]int{field_local_to_index(face), field_local_to_index(across)})
		}
	}
	return pairs
}

// A chunk arrived: the wet samples of the loaded chunks' faces towards it
// whose sample across the face is air with room wake, so water a missing
// chunk held as a wall flows on. A settled sea against an arriving sea
// stays asleep.
wake_field_water_facing :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate) {
	chunk := world.chunks[coordinate]
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		neighbour := world.chunks[coordinate + Field_Chunk_Coordinate(offset)] or_else nil
		if neighbour == nil {
			continue
		}
		for pair in field_face_pairs(offset) {
			if neighbour.water[pair[0]] > 0 && chunk.density[pair[1]] <= 0 && chunk.water[pair[1]] < FIELD_WATER_FULL {
				wake_field_water_sample(world, neighbour, pair[0])
			}
		}
	}
}

// A chunk left: the samples of the loaded chunks' faces towards it below
// sea level and short of full wake, so they become sea edges if the
// missing samples are sea.
wake_field_water_beside_missing :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate) {
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		neighbour := world.chunks[coordinate + Field_Chunk_Coordinate(offset)] or_else nil
		if neighbour == nil {
			continue
		}
		for pair in field_face_pairs(offset) {
			index := pair[0]
			if neighbour.density[index] <= 0 && neighbour.water[index] < FIELD_WATER_FULL && field_sample_below_sea(world, neighbour, index) {
				wake_field_water_sample(world, neighbour, index)
			}
		}
	}
}

// The fill a source refills the sample to: full for a spring, the sea's
// fill at its level beside a missing sample that is sea, 0 for no source.
field_water_source_fill :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour) -> i32 {
	if field_sample_bit(&chunk.water_source, index) {
		return FIELD_WATER_FULL
	}
	for neighbour in neighbours {
		if neighbour.chunk == nil && neighbour.sea > 0 {
			return field_sea_fill(world.water_planet.sea_level, span)
		}
	}
	return 0
}

// Fill at or below the minimum that can neither fall nor rests on full
// water: it stops and dries.
field_water_is_film :: proc(fill: i32, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, tuning: Field_Water_Tuning) -> bool {
	if fill > tuning.minimum_fill {
		return false
	}
	for neighbour in neighbours {
		if neighbour.span.middle < span.middle && (field_water_room(neighbour) > 0 || field_water_neighbour_fill(neighbour) == FIELD_WATER_FULL) {
			return false
		}
	}
	return true
}

move_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, neighbour: Field_Water_Neighbour, amount: i32) {
	set_field_water(world, chunk, index, sample, i32(chunk.water[index]) - amount)
	set_field_water(world, neighbour.chunk, neighbour.index, neighbour.sample, i32(neighbour.chunk.water[neighbour.index]) + amount)
}

// The fill that makes the two levels equal, rounded to the nearest with
// a half rounded down (towards the mover), at most left, the neighbour's
// room and the rate. What is left between the two is then under half a
// fill either way, so the move never turns back and a level settles
// within half a fill a step.
field_water_share :: proc(chunk: ^Field_Chunk, index: int, span: Field_Water_Span, neighbour: Field_Water_Neighbour, tuning: Field_Water_Tuning, left: i32) -> i32 {
	room := field_water_room(neighbour)
	if room == 0 {
		return 0
	}
	difference := field_water_level_exact(span, i32(chunk.water[index])) - field_water_level_exact(neighbour.span, i32(neighbour.chunk.water[neighbour.index]))
	if difference <= 0 {
		return 0
	}
	heights := span.height + neighbour.span.height
	equal := floor_divide_i64(2 * difference - heights + 2 * heights - 1, 2 * heights)
	return i32(min(equal, i64(left), i64(room), i64(tuning.rate)))
}

// To the neighbours nearer the centre first, then to the others, at most
// budget in all; returns the fill moved out.
spread_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, tuning: Field_Water_Tuning, budget: i32) -> i32 {
	allowed := min(budget, i32(chunk.water[index]))
	left := allowed
	for nearer in ([2]bool{true, false}) {
		for neighbour in neighbours {
			if (neighbour.span.middle < span.middle) != nearer {
				continue
			}
			if amount := field_water_share(chunk, index, span, neighbour, tuning, left); amount > 0 {
				move_field_water(world, chunk, index, sample, neighbour, amount)
				left -= amount
			}
		}
	}
	return allowed - left
}

// One awake sample's tick; start is its fill when the tick began.
step_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, tuning: Field_Water_Tuning, tick: u64, start: u8) {
	if chunk.density[index] > 0 {
		chunk.water_flow[index] = 0
		sleep_field_water_sample(chunk, index)
		return
	}
	sample := field_chunk_sample(chunk, index)
	span := field_water_span(sample)
	neighbours := field_water_neighbours(world, chunk, sample)
	before := chunk.water[index]
	budget := i32(start)
	if source := field_water_source_fill(world, chunk, index, span, neighbours); source > i32(before) {
		set_field_water(world, chunk, index, sample, source)
		budget = source
	}
	fill := i32(chunk.water[index])
	moved: i32 = 0
	film := fill > 0 && field_water_is_film(fill, span, neighbours, tuning)
	switch {
	case film:
		if tuning.dry_ticks > 0 && tick % tuning.dry_ticks == 0 {
			set_field_water(world, chunk, index, sample, fill - 1)
		}
	case fill > 0:
		moved = spread_field_water(world, chunk, index, sample, span, neighbours, tuning, budget)
	}
	chunk.water_flow[index] = u8(min(moved, 255))
	// A film stays awake until it has dried.
	if film || moved > 0 || chunk.water[index] != before {
		chunk.water_still[index] = 0
		return
	}
	chunk.water_still[index] = u8(min(int(chunk.water_still[index]) + 1, 255))
	if chunk.water_still[index] >= tuning.still_ticks {
		sleep_field_water_sample(chunk, index)
	}
}

// The bits above bit in a word.
field_bits_above :: proc(bit: u64) -> u64 {
	return bit == 63 ? 0 : ~u64(0) << (bit + 1)
}

// The samples awake when the tick began, in sample order.
step_field_water_pass :: proc(world: ^Field_World, pass: ^Field_Water_Pass, tuning: Field_Water_Tuning, tick: u64) {
	for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
		bits := pass.awake[word]
		for bits != 0 {
			bit := u64(intrinsics.count_trailing_zeros(bits))
			index := word * 64 + int(bit)
			step_field_water_sample(world, pass.chunk, index, tuning, tick, pass.start[index])
			bits &= field_bits_above(bit)
		}
	}
}

// z, then y, then x, rising, as the samples.
field_chunk_coordinate_before :: proc(first, second: Field_Chunk_Coordinate) -> bool {
	if first.z != second.z {
		return first.z < second.z
	}
	if first.y != second.y {
		return first.y < second.y
	}
	return first.x < second.x
}

// The water's tick (in tick_field_simulation, after the edits): the
// samples awake when it began, chunks in coordinate order, each moving at
// most the fill it held then. A sample woken during the step runs from
// the next tick.
step_field_water :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: u64) {
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(world.water_awake_chunks), context.temp_allocator)
	for coordinate in world.water_awake_chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	passes := make([dynamic]^Field_Water_Pass, 0, len(coordinates), context.temp_allocator)
	for coordinate in coordinates {
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			delete_key(&world.water_awake_chunks, coordinate)
			continue
		}
		pass := new(Field_Water_Pass, context.temp_allocator)
		pass.chunk, pass.awake, pass.start = chunk, chunk.water_awake, chunk.water
		append(&passes, pass)
	}
	for pass in passes {
		step_field_water_pass(world, pass, tuning, tick)
	}
	for pass in passes {
		if !field_sample_bits_any(&pass.chunk.water_awake) {
			delete_key(&world.water_awake_chunks, pass.chunk.coordinate)
		}
	}
}
