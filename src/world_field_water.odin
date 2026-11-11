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
// those of its six neighbours that have something to do (inside the step
// at its end, and only for a fill the tick changed, 0367). Fill at or below
// the minimum on dry ground (a film) stops moving and drops by one every
// dry ticks. Volume is conserved but at the sources, the drying, the set's
// edge, the sea under teleport and a terrain place that has nowhere to
// push the water it displaces.
//
// Sources: a spring sample (the source bit, set by the generation) is
// refilled by the spring's rate up to full (0367), and a sea edge sample
// (beside a missing sample that is sea) to the sea's fill at its level,
// each tick they are awake. A
// missing chunk's sample holds the sea's fill when the generation makes it
// air (field_sea_fill), and is a wall otherwise.
//
// The set's edge (0370): moving water leaves the simulation across it, under
// both models. A missing chunk's sample takes a mover's share against the
// water the generation puts there (field_water_outside: the sea's fill or
// a lake's, the higher, none in dry air), banded and capped as any move,
// and the fill goes to Field_World.water_to_edge; the generation's ground
// stays a wall. Only a move reads it: the room (field_water_room) of a
// missing sample stays 0, so the films, the displacement and the pull keep
// it a wall, and asleep water at the edge stays asleep. Under teleport a
// sea sample at its sea fill takes a move as the sea, the fill going to
// water_to_sea (field_water_sea_sink_fill), so the teleport sea does not
// rise.
//
// The dead band and the pressure pull (0292, the tech demo's teleport
// model): a move between two cells that overlap in height needs a head
// above minimum_head (static friction: a settled lake is still), while a
// fall into a cell entirely below is never banded. A not-full sample
// resting on full water that moved nothing searches the full body under
// it, depth first and upwards first, for the surface sample with the
// highest level (pull_field_water_pressure), and when that level stands
// more than one fill of each cell plus the band above its own, the
// equalising fill moves from there to here in one step: communicating
// vessels, a U-tube. The search is bounded per search and per tick; a
// search that finds no head sets the sample's failed bit, which any change
// next door clears. A film's drying is a sink, not a flow: it wakes nobody,
// and a film nobody refills above the band dries alone and sleeps.
//
// The bodies model (0293, world_field_water_body.odin): step_field_water
// dispatches on the world's model. Under bodies the still water is the
// bodies', and the rule above runs only on the front (the awake samples
// that are no body's still water) in two passes: every front sample plans
// its moves in the step's order, comparing the two projected fills (the
// tick-start fill plus the moves planned into and out of the sample so
// far), at most its tick-start fill less what it planned out and the
// receiver's projected room (0298: tick-start fills on both sides let a
// thin layer swap a checkerboard every tick), then every move applies at
// once. A move into a body's
// water or the sea's goes to its volume. Front water resting on a body's
// water, or that a body's level rose over, is absorbed; front water still
// for the still ticks in no body's basin seeds a body. No pressure pull and
// no sea edge refill run under bodies: the bodies level and the sea's claim
// owns its samples.
//
// The look (0294, world_field_water_look.odin): every change of a fill
// through set_field_water stamps the sample as moving for
// FIELD_WATER_MOVED_TICKS (water_moved, counted down by
// expire_field_water_moved while awake), so the mesher draws it as a
// sheet; a body's derived bytes are not movement. The step records the
// tick's arrivals into standing water (impacts, stream mouths), digs and
// pump intakes as events (Field_World.water_events) for the surface
// waves, which never feed back into the water.

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
	rate:                           i32,
	// The most fill a spring pours a tick (0367).
	spring_rate:                    i32,
	still_ticks:                    u8,
	minimum_fill:                   i32,
	dry_ticks:                      u64,
	// The pressure pull (0292): on or off, the samples one search visits
	// at most, the visits of a tick at most, and the dead band in fill.
	pressure:                       bool,
	pressure_visit_budget:          i32,
	pressure_visit_budget_per_tick: i64,
	minimum_head:                   i32,
	// The bodies (0293): the weir's fill a tick per sample of head, its
	// cap and floor a tick and its dead band in fill over the sill, the
	// flood's visits a tick and its rise cap in samples.
	weir_rate_per_head:             i64,
	weir_cap:                       i32,
	weir_floor:                     i32,
	weir_dead_band:                 i32,
	flood_visit_budget:             i64,
	flood_rise_samples:             i32,
	// The demo's buckets (0295): the fill a press pours or takes and the
	// ticks between pours while Place is held.
	bucket_fill_per_press:          i32,
	bucket_repeat_ticks:            u8,
}

// The last tick's pressure pulls (Field_World.water_pressure): the
// teleports made, the samples the searches visited, the searches that
// found no head. Reset at the top of step_field_water; not saved, not
// hashed.
Field_Water_Pressure_Counts :: struct {
	teleports, visits, failures: i64,
}

// The last water step's work (Field_World.water_step_counts, 0367's
// probe, test_report_the_water_at_a_flowing_spring): the fill writes
// (set_field_water); the moves and their fill (move_field_water, the
// front's planned moves); the wake checks (wake_field_water_sample) and
// the wakes that set a clear awake bit; the neighbour sets built
// (field_water_neighbours); the pull's searches past its early returns
// and those its tick's budget postponed; the fill the springs poured
// (a teleport spring's spread, a front spring's planned moves and its pour
// into a body or the sea); the spans computed (field_water_span) in all,
// in the wake checks and in the searches; the front's apply, its chunks,
// the samples it visits (their awake and received bits) and those among
// them planned or given a delta. Reset at the top of
// step_field_water_keeping_events; not saved, not hashed, never read by
// the rules.
Field_Water_Step_Counts :: struct {
	writes, moves, moved_fill, wake_checks, wakes, neighbour_sets, searches, postponed, spring_outflow: i64,
	spans, wake_spans, search_spans, apply_chunks, apply_visits, apply_samples:                        i64,
}

// One write of the step for the probe (Field_World.water_write_log): the
// sample and its fill before the write.
Field_Water_Write :: struct {
	chunk:  ^Field_Chunk,
	index:  int,
	before: u8,
}

// The spans this thread computed (field_water_span), for the step's
// counts: the workers' meshing counts its own; never read by the rules.
@(thread_local)
field_water_span_count: i64

// The chunks one search may visit; a further chunk is a wall to it.
FIELD_WATER_SEARCH_CHUNK_LIMIT :: 8

// One tick's search state (make_field_water_search), reset before every
// search: the chunks visited with a bit per visited sample, and the depth
// first stack.
Field_Water_Search :: struct {
	chunks:      [FIELD_WATER_SEARCH_CHUNK_LIMIT]Field_Water_Search_Chunk,
	chunk_count: int,
	stack:       [dynamic]Field_Water_Search_Cell,
}

Field_Water_Search_Chunk :: struct {
	chunk:   ^Field_Chunk,
	visited: Field_Sample_Bits,
}

Field_Water_Search_Cell :: struct {
	chunk:  ^Field_Chunk,
	index:  int,
	sample: Sample_Coordinate,
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
		spring_rate = i32(config.spring_fill_per_tick),
		still_ticks = u8(config.still_ticks_to_sleep),
		minimum_fill = i32(config.minimum_fill),
		dry_ticks = u64(config.dry_ticks_per_step),
		pressure = config.pressure,
		pressure_visit_budget = i32(config.pressure_visit_budget),
		pressure_visit_budget_per_tick = i64(config.pressure_visit_budget_per_tick),
		minimum_head = i32(config.minimum_head),
		weir_rate_per_head = i64(config.weir_rate_per_head),
		weir_cap = i32(config.weir_cap),
		weir_floor = i32(config.weir_floor),
		weir_dead_band = i32(config.weir_dead_band),
		flood_visit_budget = i64(config.flood_visit_budget),
		flood_rise_samples = i32(config.flood_rise_samples),
		bucket_fill_per_press = i32(config.bucket_fill_per_press),
		bucket_repeat_ticks = u8(config.bucket_repeat_ticks),
	}
}

// The dead band in exact level units.
field_water_band :: proc(tuning: Field_Water_Tuning) -> i64 {
	return i64(tuning.minimum_head) * FIELD_WATER_FULL
}

// The stack is reserved for the most a search can push: six for the
// seeds and six for every visit.
make_field_water_search :: proc(tuning: Field_Water_Tuning, allocator := context.temp_allocator) -> ^Field_Water_Search {
	search := new(Field_Water_Search, allocator)
	search.stack = make([dynamic]Field_Water_Search_Cell, 0, 6 * int(tuning.pressure_visit_budget) + 6, allocator)
	return search
}

// Marks the sample visited; false when it was already, or when its chunk
// would be the one past the limit (a wall to this search).
field_water_search_visit :: proc(search: ^Field_Water_Search, chunk: ^Field_Chunk, index: int) -> bool {
	entry: ^Field_Water_Search_Chunk
	for slot in 0 ..< search.chunk_count {
		if search.chunks[slot].chunk == chunk {
			entry = &search.chunks[slot]
			break
		}
	}
	if entry == nil {
		if search.chunk_count >= FIELD_WATER_SEARCH_CHUNK_LIMIT {
			return false
		}
		entry = &search.chunks[search.chunk_count]
		entry.chunk, entry.visited = chunk, {}
		search.chunk_count += 1
	}
	if field_sample_bit(&entry.visited, index) {
		return false
	}
	set_field_sample_bit(&entry.visited, index)
	return true
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
	field_water_span_count += 1
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

field_sample_bits_count :: proc(bits: ^Field_Sample_Bits) -> int {
	count := 0
	for word in bits {
		count += int(intrinsics.count_ones(word))
	}
	return count
}

// The water field's totals for the overlay's water line (0291): the fill
// over every loaded chunk, and the awake samples and chunks of the awake
// set. One byte sum per chunk, taken once a second by the loop.
Field_Water_Census :: struct {
	fill:          i64,
	awake_samples: int,
	awake_chunks:  int,
}

field_water_census :: proc(world: ^Field_World) -> Field_Water_Census {
	census: Field_Water_Census
	for _, chunk in world.chunks {
		for fill in chunk.water {
			census.fill += i64(fill)
		}
	}
	census.awake_chunks = len(world.water_awake_chunks)
	for coordinate in world.water_awake_chunks {
		if chunk := world.chunks[coordinate] or_else nil; chunk != nil {
			census.awake_samples += field_sample_bits_count(&chunk.water_awake)
		}
	}
	return census
}

// A fill sum as whole cubic metres at the spacing: a full sample holds
// one cube of the spacing.
field_water_cubic_metres :: proc(fill: i64, spacing_millimetres: int) -> i64 {
	spacing := i64(spacing_millimetres)
	return fill * spacing * spacing * spacing / (FIELD_WATER_FULL * 1_000_000_000)
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

// The water a missing sample holds as the generation makes it (0370, the
// set's edge), through the world's cache: -1 in a world without a planet
// (the tests' worlds) and where the generation makes ground (a wall),
// else the sea's fill or a lake's, the higher, 0 for dry air.
field_water_outside :: proc(world: ^Field_World, sample: Sample_Coordinate, span: Field_Water_Span) -> i32 {
	if cached, found := world.water_outside[sample]; found {
		return cached
	}
	planet := world.water_planet
	outside: i32 = -1
	if planet.generation.spacing_millimetres != 0 && planet_sample(planet.generation, sample_to_world_position(sample, planet.generation.spacing_millimetres)).density <= 0 {
		outside = max(field_sea_fill(planet.sea_level, span), planet_lake_fill_at(planet.generation, sample))
	}
	world.water_outside[sample] = outside
	return outside
}

// The fill moving water gives a neighbour whose chunk is not loaded
// (0370): banded and capped as every move, against the water the
// generation puts there; none into a wall.
field_water_edge_share :: proc(world: ^Field_World, span: Field_Water_Span, fill: i32, neighbour: Field_Water_Neighbour, tuning: Field_Water_Tuning, left: i32) -> i32 {
	outside := field_water_outside(world, neighbour.sample, neighbour.span)
	if outside < 0 {
		return 0
	}
	return field_water_share_from(span, fill, neighbour.span, outside, FIELD_WATER_FULL - outside, tuning, left)
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
	world.water_step_counts.neighbour_sets += 1
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
// air that can be a source (a spring, or below sea level beside the sea)
// or that rests on full water (a pull may fill it).
// Under bodies a body's or the sea's still sample never wakes (its byte
// is derived), and only water or a source has something to do.
field_water_can_wake :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) -> bool {
	if world.water_model == .Bodies {
		if chunk.water_owner[index] != WATER_OWNER_NONE && !field_sample_bit(&chunk.water_awake, index) {
			return false
		}
		return chunk.water[index] > 0 || field_sample_bit(&chunk.water_source, index)
	}
	if chunk.water[index] > 0 || field_sample_bit(&chunk.water_source, index) {
		return true
	}
	if chunk.density[index] > 0 {
		return false
	}
	if field_sample_below_sea(world, chunk, index) {
		return true
	}
	sample := field_chunk_sample(chunk, index)
	return field_water_rests_on_full(field_water_span(sample), field_water_neighbours(world, chunk, sample))
}

field_sample_below_sea :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) -> bool {
	return field_sea_fill(world.water_planet.sea_level, field_water_span(field_chunk_sample(chunk, index))) > 0
}

// A loaded neighbour nearer the centre is full water; a missing sea sample
// does not count (the sea edge refill covers it).
field_water_rests_on_full :: proc(span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour) -> bool {
	for neighbour in neighbours {
		if field_water_is_full_below(span, neighbour) {
			return true
		}
	}
	return false
}

field_water_is_full_below :: proc(span: Field_Water_Span, neighbour: Field_Water_Neighbour) -> bool {
	return neighbour.chunk != nil && neighbour.span.middle < span.middle && neighbour.chunk.density[neighbour.index] <= 0 && neighbour.chunk.water[neighbour.index] == FIELD_WATER_FULL
}

// Every change next door clears the pull's failed bit, whether or not
// the sample can wake.
wake_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) {
	world.water_step_counts.wake_checks += 1
	spans_before := field_water_span_count
	defer world.water_step_counts.wake_spans += field_water_span_count - spans_before
	// The bit is hashed (0293): clearing it is a change.
	if field_sample_bit(&chunk.water_pressure_failed, index) {
		clear_field_sample_bit(&chunk.water_pressure_failed, index)
		note_field_chunk_change(chunk)
	}
	if !field_water_can_wake(world, chunk, index) {
		return
	}
	chunk.water_still[index] = 0
	note_field_chunk_change(chunk)
	if !field_sample_bit(&chunk.water_awake, index) {
		world.water_step_counts.wakes += 1
		note_field_water_change(world, chunk, index, field_chunk_sample(chunk, index), false)
		set_field_sample_bit(&chunk.water_awake, index)
		world.water_awake_chunks[chunk.coordinate] = {}
	}
}

// Wakes the sample whatever it holds: front water put into a body's dry
// air, or old water the bodies take over as front.
force_wake_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) {
	chunk.water_still[index] = 0
	note_field_chunk_change(chunk)
	if !field_sample_bit(&chunk.water_awake, index) {
		world.water_step_counts.wakes += 1
		note_field_water_change(world, chunk, index, field_chunk_sample(chunk, index), false)
		set_field_sample_bit(&chunk.water_awake, index)
		world.water_awake_chunks[chunk.coordinate] = {}
	}
}

// Sleeping leaves the still ticks at zero, so a settled chunk equals its
// generation again, and ends the moving stamp (0294). A sample that was
// awake or moving is noted first (0367): an owned sample turning from
// front to its owner's plane, or a moving sheet coming to rest, is a
// change of the look the step's end marks.
sleep_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) {
	if field_sample_bit(&chunk.water_awake, index) || chunk.water_moved[index] != 0 {
		note_field_water_change(world, chunk, index, field_chunk_sample(chunk, index), false)
	}
	clear_field_sample_bit(&chunk.water_awake, index)
	chunk.water_still[index] = 0
	chunk.water_moved[index] = 0
	note_field_chunk_change(chunk)
}

// The water step's touches (0367): while the step runs, a change of a
// sample's look inputs (its fill, its moving stamp, its awake bit) notes
// the sample once with those inputs as the step found them, and the
// step's end marks only the samples whose inputs differ then
// (finish_field_water_touches), so a write the tick undoes marks no chunk.
// Outside the step every mark is immediate. A body's level marks and an
// owner's change stay immediate inside the step too. Under teleport
// (defer_wakes) a write's wakes wait for the step's end as well and happen
// only for a sample whose fill then differs from the tick's start, so a
// write the tick undoes wakes nobody and clears no failed bit (the bodies'
// writes are already the tick's net change).

// A sample's look inputs as the step found them: its fill, whether it
// moves (water_moved over zero) and whether it is front (awake and no
// spring, which an owned sample draws as the slab, not its owner's plane);
// and whether it was awake, for the deferred wakes.
Field_Water_Touch :: struct {
	chunk:               ^Field_Chunk,
	index:               int,
	water:               u8,
	moved, front, awake: bool,
}

// Field_World.water_touches: the step's notes, each sample once
// (Field_Chunk.water_touched), on while the step runs.
Field_Water_Touches :: struct {
	list:            [dynamic]Field_Water_Touch,
	on, defer_wakes: bool,
}

field_water_sample_is_front :: proc(chunk: ^Field_Chunk, index: int) -> bool {
	return field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index)
}

begin_field_water_touches :: proc(world: ^Field_World, defer_wakes: bool) {
	clear(&world.water_touches.list)
	world.water_touches.on, world.water_touches.defer_wakes = true, defer_wakes
}

// Before a change of the sample's look inputs: while the step runs, its
// first note keeps the inputs as they stand; outside it, the chunks that
// mesh the sample are marked when mark is set.
note_field_water_change :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, mark: bool) {
	touches := &world.water_touches
	if !touches.on {
		if mark {
			mark_field_look_dirty(world, chunk.coordinate, sample)
		}
		return
	}
	if field_sample_bit(&chunk.water_touched, index) {
		return
	}
	set_field_sample_bit(&chunk.water_touched, index)
	append(&touches.list, Field_Water_Touch{chunk = chunk, index = index, water = chunk.water[index], moved = chunk.water_moved[index] != 0, front = field_water_sample_is_front(chunk, index), awake = field_sample_bit(&chunk.water_awake, index)})
}

// The step's end: the written samples whose fill differs from their note
// wake with their neighbours (their order changes nothing, a wake writes
// no fill; a wake's own note is appended and read below). A written sample
// whose fill equals its note but that went to sleep during the step while
// holding water then (a film that dried empty in its own run and was given
// its fill back) wakes alone, or it would never dry; any other undone write
// leaves no moving stamp on a sample asleep, which nothing would count
// down. Then every noted sample whose fill, moving stamp or (owned) front
// differs from its note marks the chunks that mesh it; the notes clear.
finish_field_water_touches :: proc(world: ^Field_World) {
	touches := &world.water_touches
	if touches.defer_wakes {
		touches.defer_wakes = false
		written := len(touches.list)
		for position in 0 ..< written {
			touch := touches.list[position]
			chunk, index := touch.chunk, touch.index
			if !field_sample_bit(&chunk.water_written, index) {
				continue
			}
			clear_field_sample_bit(&chunk.water_written, index)
			switch {
			case chunk.water[index] != touch.water:
				wake_field_water_around(world, chunk, index, field_chunk_sample(chunk, index))
			case field_sample_bit(&chunk.water_awake, index):
			case touch.awake && chunk.water[index] > 0:
				wake_field_water_sample(world, chunk, index)
			case:
				chunk.water_moved[index] = 0
			}
		}
	}
	for touch in touches.list {
		chunk, index := touch.chunk, touch.index
		clear_field_sample_bit(&chunk.water_touched, index)
		front_changed := chunk.water_owner[index] != WATER_OWNER_NONE && field_water_sample_is_front(chunk, index) != touch.front
		if chunk.water[index] != touch.water || (chunk.water_moved[index] != 0) != touch.moved || front_changed {
			mark_field_look_dirty(world, chunk.coordinate, field_chunk_sample(chunk, index))
		}
	}
	clear(&touches.list)
	touches.on, touches.defer_wakes = false, false
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
// sample are marked (at the step's end inside the step,
// note_field_water_change), and the sample and its neighbours wake (at the
// step's end inside a teleport step, for a changed fill only).
set_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	world.water_step_counts.writes += 1
	if world.water_write_log != nil {
		append(world.water_write_log, Field_Water_Write{chunk = chunk, index = index, before = chunk.water[index]})
	}
	note_field_water_change(world, chunk, index, sample, true)
	if i32(chunk.water[index]) != fill {
		chunk.water_moved[index] = FIELD_WATER_MOVED_TICKS
	}
	chunk.water[index] = u8(fill)
	note_field_chunk_change(chunk)
	if world.water_touches.defer_wakes {
		set_field_sample_bit(&chunk.water_written, index)
		return
	}
	wake_field_water_around(world, chunk, index, sample)
}

// A body's derived byte (0293): the byte, the meshes and the edited
// chunks follow, nobody wakes; nothing when it is unchanged.
write_field_water_quiet :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	if i32(chunk.water[index]) == fill {
		return
	}
	note_field_water_change(world, chunk, index, sample, true)
	chunk.water[index] = u8(fill)
	note_field_chunk_change(chunk)
}

// Front water under bodies (0293): the byte as set_field_water writes it,
// and the sample awake whoever owns it, so water in a body's dry air is
// front.
set_front_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	set_field_water(world, chunk, index, sample, fill)
	if fill > 0 || field_sample_bit(&chunk.water_source, index) {
		force_wake_field_water_sample(world, chunk, index)
	}
}

// Whether a move into the sample goes to a body's volume: the sea's
// samples, and a body's still samples under its level (the released
// samples are the pending flood's). The body is returned.
field_water_sample_credits :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, span: Field_Water_Span) -> (id: Water_Body_Id, credited: bool) {
	owner := chunk.water_owner[index]
	if owner == WATER_OWNER_SEA {
		return WATER_BODY_SEA, true
	}
	body, owned := water_owner_body(world, owner)
	if !owned || body == WATER_BODY_SEA {
		return 0, false
	}
	if field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index) {
		return 0, false
	}
	return body, field_water_bottom(span) < world.water_bodies[body].level
}

// The front's fill in a sample: a body's still sample holds none of it
// (its byte is the body's).
field_water_front_fill :: proc(chunk: ^Field_Chunk, index: int) -> i32 {
	if chunk.water_owner[index] != WATER_OWNER_NONE && !field_sample_bit(&chunk.water_awake, index) {
		return 0
	}
	return i32(chunk.water[index])
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
// the next tick. A wet sample turned ground, or ground turned air beside
// water, is a dig event for the surface waves (0294).
follow_field_terrain_with_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, was_ground: bool) {
	if chunk.density[index] > 0 {
		if chunk.water[index] > 0 {
			push_field_water_event(world, .Dig, sample, i32(chunk.water[index]))
		}
	} else if was_ground && field_sample_has_wet_face_neighbour(world, chunk, sample) {
		push_field_water_event(world, .Dig, sample, FIELD_WATER_FULL)
	}
	if world.water_model == .Bodies {
		follow_field_terrain_with_bodies(world, chunk, index, sample)
		return
	}
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

// The fill a source refills the sample to: its fill plus the spring's rate
// up to full for a spring (0367), the sea's fill at its level beside a
// missing sample that is sea, 0 for no source.
field_water_source_fill :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, fill: i32, spring_rate: i32) -> i32 {
	if field_sample_bit(&chunk.water_source, index) {
		return min(FIELD_WATER_FULL, fill + spring_rate)
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

// A film's drying: a sink, not a flow, so nobody wakes. The sample
// sleeps once dry (step_field_water_sample).
dry_field_water_film :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	note_field_water_change(world, chunk, index, sample, true)
	chunk.water[index] -= 1
	note_field_chunk_change(chunk)
}

move_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, neighbour: Field_Water_Neighbour, amount: i32) {
	world.water_step_counts.moves += 1
	world.water_step_counts.moved_fill += i64(amount)
	set_field_water(world, chunk, index, sample, i32(chunk.water[index]) - amount)
	set_field_water(world, neighbour.chunk, neighbour.index, neighbour.sample, i32(neighbour.chunk.water[neighbour.index]) + amount)
}

// A move out of the simulated water (0370): the sender written down and
// the fill credited to the sink (the set's edge, the sea), nothing
// written beyond.
move_field_water_out :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, amount: i32, sink: ^i64) {
	world.water_step_counts.moves += 1
	world.water_step_counts.moved_fill += i64(amount)
	set_field_water(world, chunk, index, sample, i32(chunk.water[index]) - amount)
	sink^ += i64(amount)
}

// Whether the cell below lies entirely under the mover's: a fall, which
// the dead band never holds. Cells that overlap in height (lateral, the
// sphere's staircase) are banded.
field_water_is_drop :: proc(span, below: Field_Water_Span) -> bool {
	return field_water_bottom(below) + below.height <= field_water_bottom(span)
}

// The fill that makes the two levels equal, rounded to the nearest with
// a half rounded down (towards the mover), at most left, the neighbour's
// room and the rate. What is left between the two is then under half a
// fill either way, so the move never turns back and a level settles
// within half a fill a step. Nothing moves for a difference at or under
// the dead band unless the move is a drop (0292).
field_water_share :: proc(chunk: ^Field_Chunk, index: int, span: Field_Water_Span, neighbour: Field_Water_Neighbour, tuning: Field_Water_Tuning, left: i32) -> i32 {
	room := field_water_room(neighbour)
	if room == 0 {
		return 0
	}
	return field_water_share_from(span, i32(chunk.water[index]), neighbour.span, i32(neighbour.chunk.water[neighbour.index]), room, tuning, left)
}

// The pure core of field_water_share: the levels from the two fills given
// (the bodies' front gives the projected fills, 0298).
field_water_share_from :: proc(span: Field_Water_Span, fill: i32, neighbour_span: Field_Water_Span, neighbour_fill: i32, room: i32, tuning: Field_Water_Tuning, left: i32) -> i32 {
	if room <= 0 {
		return 0
	}
	difference := field_water_level_exact(span, fill) - field_water_level_exact(neighbour_span, neighbour_fill)
	if difference <= (field_water_is_drop(span, neighbour_span) ? 0 : field_water_band(tuning)) {
		return 0
	}
	heights := span.height + neighbour_span.height
	equal := floor_divide_i64(2 * difference - heights + 2 * heights - 1, 2 * heights)
	return i32(min(equal, i64(left), i64(room), i64(tuning.rate)))
}

// To the neighbours nearer the centre first, then to the others, at most
// budget in all; returns the fill moved out. A move into standing water
// (more than a film, or resting on full water) is an impact from above
// or a stream mouth from the side (0294). A neighbour whose chunk is not
// loaded takes its share as the set's edge (0370): the fill leaves the
// simulation, no event. A sea sample at its sea fill takes its share as
// the sea (0370, field_water_sea_sink_fill): the fill goes to
// water_to_sea, the sea's byte stays.
spread_field_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, tuning: Field_Water_Tuning, budget: i32) -> i32 {
	allowed := min(budget, i32(chunk.water[index]))
	left := allowed
	for nearer in ([2]bool{true, false}) {
		for neighbour in neighbours {
			if (neighbour.span.middle < span.middle) != nearer {
				continue
			}
			if neighbour.chunk == nil {
				if amount := field_water_edge_share(world, span, i32(chunk.water[index]), neighbour, tuning, left); amount > 0 {
					move_field_water_out(world, chunk, index, sample, amount, &world.water_to_edge)
					left -= amount
				}
				continue
			}
			sea := field_water_sea_sink_fill(world, neighbour)
			amount: i32
			if sea > 0 {
				amount = field_water_share_from(span, i32(chunk.water[index]), neighbour.span, sea, FIELD_WATER_FULL - sea, tuning, left)
			} else {
				amount = field_water_share(chunk, index, span, neighbour, tuning, left)
			}
			if amount <= 0 {
				continue
			}
			if field_water_neighbour_fill(neighbour) > tuning.minimum_fill || field_water_rests_on_full(neighbour.span, field_water_neighbours(world, neighbour.chunk, neighbour.sample)) {
				push_field_water_event(world, nearer ? .Impact : .Stream_Mouth, neighbour.sample, amount)
			}
			if sea > 0 {
				move_field_water_out(world, chunk, index, sample, amount, &world.water_to_sea)
			} else {
				move_field_water(world, chunk, index, sample, neighbour, amount)
			}
			left -= amount
		}
	}
	return allowed - left
}

// The sea fill a loaded neighbour holds as the sea (0370): the sea owns
// it (fill_field_chunk_sea marks the generated sea under either model), it
// is not ground and holds at least its fill at the sea's level, over 0;
// else 0, so a sea sample under its fill (after a pump or a dig beside
// it) fills as any sample.
field_water_sea_sink_fill :: proc(world: ^Field_World, neighbour: Field_Water_Neighbour) -> i32 {
	if neighbour.chunk.water_owner[neighbour.index] != WATER_OWNER_SEA || neighbour.chunk.density[neighbour.index] > 0 {
		return 0
	}
	sea := field_sea_fill(world.water_planet.sea_level, neighbour.span)
	if sea <= 0 || i32(neighbour.chunk.water[neighbour.index]) < sea {
		return 0
	}
	return sea
}

// Whether the two samples share a face.
field_samples_are_face_neighbours :: proc(first, second: Sample_Coordinate) -> bool {
	return abs(first.x - second.x) + abs(first.y - second.y) + abs(first.z - second.z) == 1
}

// A sample of the search: a surface when it is partial, or full with a
// neighbour farther from the centre that has room. neighbours are read
// only for a full sample.
field_water_search_is_surface :: proc(fill: i32, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour) -> bool {
	if fill < FIELD_WATER_FULL {
		return true
	}
	for neighbour in neighbours {
		if neighbour.chunk != nil && neighbour.span.middle > span.middle && field_water_room(neighbour) > 0 {
			return true
		}
	}
	return false
}

// The pressure pull of a not-full sample resting on full water that moved
// nothing: a depth first search through the full body under it (the
// seeds the full neighbours nearer the centre, in slot order; from a full
// sample its neighbours nearer or level first, then the farther, so the
// farther pop first and the search climbs out of a tunnel before it
// wanders the lake bed; a missing chunk, ground and an empty sample are
// never pushed, since an empty sample is neither a head nor a path; a
// partial sample is visited but not expanded) for the surface sample with the
// highest level that is no face neighbour of the receiver (those level by
// the plain rule) and stands more than one fill of each cell plus the band
// above the receiver's level. The share from there to here moves in one
// step. A search that finds nothing, or a banded share of nothing, sets
// the failed bit, so the sample does not search again until a change
// next door clears it; a tick whose visits are spent postpones the search
// without a flag. The head gives from its fill as it stands, the one
// place the rule reads a current fill as a budget; the order is fixed, so
// every machine does alike.
pull_field_water_pressure :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, span: Field_Water_Span, neighbours: [6]Field_Water_Neighbour, tuning: Field_Water_Tuning, search: ^Field_Water_Search) -> (moved: i32, postponed: bool) {
	if field_sample_bit(&chunk.water_pressure_failed, index) {
		return 0, false
	}
	if world.water_pressure.visits >= tuning.pressure_visit_budget_per_tick {
		world.water_step_counts.postponed += 1
		return 0, true
	}
	world.water_step_counts.searches += 1
	spans_before := field_water_span_count
	defer world.water_step_counts.search_spans += field_water_span_count - spans_before
	search.chunk_count = 0
	clear(&search.stack)
	field_water_search_visit(search, chunk, index)
	for neighbour in neighbours {
		if field_water_is_full_below(span, neighbour) && field_water_search_visit(search, neighbour.chunk, neighbour.index) {
			append(&search.stack, Field_Water_Search_Cell{neighbour.chunk, neighbour.index, neighbour.sample})
		}
	}
	// The receiver's level plus its own fill and the band; a candidate adds
	// one fill of its own cell.
	floor := field_water_level_exact(span, i32(chunk.water[index])) + span.height + field_water_band(tuning)
	best: Field_Water_Search_Cell
	best_span: Field_Water_Span
	best_level: i64
	found := false
	visits: i64 = 0
	for len(search.stack) > 0 && visits < i64(tuning.pressure_visit_budget) {
		cell := pop(&search.stack)
		visits += 1
		cell_fill := i32(cell.chunk.water[cell.index])
		cell_span := field_water_span(cell.sample)
		cell_neighbours: [6]Field_Water_Neighbour
		if cell_fill == FIELD_WATER_FULL {
			cell_neighbours = field_water_neighbours(world, cell.chunk, cell.sample)
		}
		if cell_fill > 0 && !field_samples_are_face_neighbours(sample, cell.sample) && field_water_search_is_surface(cell_fill, cell_span, cell_neighbours) {
			level := field_water_level_exact(cell_span, cell_fill)
			if level > floor + cell_span.height && (!found || level > best_level) {
				best, best_span, best_level, found = cell, cell_span, level, true
			}
		}
		if cell_fill < FIELD_WATER_FULL {
			continue
		}
		for farther in ([2]bool{false, true}) {
			for neighbour in cell_neighbours {
				if (neighbour.span.middle > cell_span.middle) != farther || neighbour.chunk == nil || neighbour.chunk.density[neighbour.index] > 0 || neighbour.chunk.water[neighbour.index] == 0 {
					continue
				}
				if field_water_search_visit(search, neighbour.chunk, neighbour.index) {
					append(&search.stack, Field_Water_Search_Cell{neighbour.chunk, neighbour.index, neighbour.sample})
				}
			}
		}
	}
	world.water_pressure.visits += visits
	if found {
		receiver := Field_Water_Neighbour{chunk = chunk, index = index, sample = sample, span = span}
		amount := field_water_share(best.chunk, best.index, best_span, receiver, tuning, min(i32(best.chunk.water[best.index]), tuning.rate))
		if amount > 0 {
			move_field_water(world, best.chunk, best.index, best.sample, receiver, amount)
			world.water_pressure.teleports += 1
			return amount, false
		}
	}
	set_field_sample_bit(&chunk.water_pressure_failed, index)
	world.water_pressure.failures += 1
	return 0, false
}

// One awake sample's tick; start is its fill when the tick began.
step_field_water_sample :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, tuning: Field_Water_Tuning, tick: u64, start: u8, search: ^Field_Water_Search) {
	sample := field_chunk_sample(chunk, index)
	expire_field_water_moved(world, chunk, index, sample)
	if chunk.density[index] > 0 {
		chunk.water_flow[index] = 0
		sleep_field_water_sample(world, chunk, index)
		return
	}
	span := field_water_span(sample)
	neighbours := field_water_neighbours(world, chunk, sample)
	before := chunk.water[index]
	budget := i32(start)
	if source := field_water_source_fill(world, chunk, index, span, neighbours, i32(before), tuning.spring_rate); source > i32(before) {
		set_field_water(world, chunk, index, sample, source)
		budget = source
	}
	fill := i32(chunk.water[index])
	moved: i32 = 0
	film := fill > 0 && field_water_is_film(fill, span, neighbours, tuning)
	switch {
	case film:
		if tuning.dry_ticks > 0 && tick % tuning.dry_ticks == 0 {
			dry_field_water_film(world, chunk, index, sample)
			if chunk.water[index] == 0 {
				chunk.water_flow[index] = 0
				sleep_field_water_sample(world, chunk, index)
				return
			}
		}
	case fill > 0:
		moved = spread_field_water(world, chunk, index, sample, span, neighbours, tuning, budget)
	}
	// The flow counts the spread only; the teleports are counted on the
	// world.
	chunk.water_flow[index] = u8(min(moved, 255))
	if field_sample_bit(&chunk.water_source, index) {
		world.water_step_counts.spring_outflow += i64(moved)
	}
	postponed := false
	if !film && moved == 0 && tuning.pressure && i32(chunk.water[index]) < FIELD_WATER_FULL && field_water_rests_on_full(span, neighbours) {
		moved, postponed = pull_field_water_pressure(world, chunk, index, sample, span, neighbours, tuning, search)
	}
	// A film stays awake until it has dried; a postponed search keeps its
	// sample awake for the next tick's budget.
	if film || moved > 0 || postponed || chunk.water[index] != before {
		chunk.water_still[index] = 0
		return
	}
	chunk.water_still[index] = u8(min(int(chunk.water_still[index]) + 1, 255))
	if chunk.water_still[index] >= tuning.still_ticks {
		sleep_field_water_sample(world, chunk, index)
	}
}

// The bits above bit in a word.
field_bits_above :: proc(bit: u64) -> u64 {
	return bit == 63 ? 0 : ~u64(0) << (bit + 1)
}

// The samples awake when the tick began, in sample order.
step_field_water_pass :: proc(world: ^Field_World, pass: ^Field_Water_Pass, tuning: Field_Water_Tuning, tick: u64, search: ^Field_Water_Search) {
	for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
		bits := pass.awake[word]
		for bits != 0 {
			bit := u64(intrinsics.count_trailing_zeros(bits))
			index := word * 64 + int(bit)
			step_field_water_sample(world, pass.chunk, index, tuning, tick, pass.start[index], search)
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

// For a binary search over coordinates in that order.
field_chunk_coordinate_order :: proc(first, second: Field_Chunk_Coordinate) -> slice.Ordering {
	switch {
	case field_chunk_coordinate_before(first, second):
		return .Less
	case field_chunk_coordinate_before(second, first):
		return .Greater
	}
	return .Equal
}

// A map's chunk coordinates in that order, in the temp allocator.
sorted_field_chunk_coordinates :: proc(chunks: map[Field_Chunk_Coordinate]$T) -> []Field_Chunk_Coordinate {
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(chunks), context.temp_allocator)
	for coordinate in chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	return coordinates[:]
}

field_sample_before :: proc(first, second: Sample_Coordinate) -> bool {
	return field_chunk_coordinate_before(Field_Chunk_Coordinate(first), Field_Chunk_Coordinate(second))
}

// The water's tick, by the world's model: teleport (0292's rule) or
// bodies (0293, step_field_water_bodies). The last tick's events are
// dropped first.
step_field_water :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: u64) {
	clear(&world.water_events)
	step_field_water_keeping_events(world, tuning, tick)
}

// The step without dropping the events: finish_field_tick drops them at
// the top of the tick, before the edits, the buckets and the pumps push
// theirs (0295). The step's counts are its own, and its look marks (and,
// under teleport, a write's wakes) wait for its end (0367,
// finish_field_water_touches).
step_field_water_keeping_events :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: u64) {
	world.water_step_counts = {}
	spans_before := field_water_span_count
	begin_field_water_touches(world, world.water_model == .Teleport)
	switch world.water_model {
	case .Teleport:
		step_field_water_teleport(world, tuning, tick)
	case .Bodies:
		step_field_water_bodies(world, tuning, tick)
	}
	finish_field_water_touches(world)
	world.water_step_counts.spans = field_water_span_count - spans_before
}

// The teleport model's tick: the samples awake when it began, chunks in
// coordinate order, each moving at most the fill it held then. A sample
// woken during the step runs from the next tick. The pressure counts are
// the tick's.
step_field_water_teleport :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: u64) {
	world.water_pressure = {}
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
		// The pass counts the still ticks of its awake samples.
		note_field_chunk_change(chunk)
		append(&passes, pass)
	}
	search := make_field_water_search(tuning)
	for pass in passes {
		step_field_water_pass(world, pass, tuning, tick, search)
	}
	for pass in passes {
		if !field_sample_bits_any(&pass.chunk.water_awake) {
			delete_key(&world.water_awake_chunks, pass.chunk.coordinate)
		}
	}
}

// The bodies model's front (0293).

// One chunk's front in a tick: the samples awake when it began and their
// fills then, the fill each sample gains or loses (planned in pass one,
// applied in pass two), what moved out of it, its films and the samples a
// planned move fills (received, so the apply visits only the awake and
// received samples, 0367). A receiving chunk with no awake sample gets one
// too (field_water_front_pass_for).
Field_Water_Front_Pass :: struct {
	chunk:    ^Field_Chunk,
	awake:    Field_Sample_Bits,
	film:     Field_Sample_Bits,
	received: Field_Sample_Bits,
	start:   [FIELD_CHUNK_SAMPLE_COUNT]u8,
	delta:   [FIELD_CHUNK_SAMPLE_COUNT]i16,
	outflow: [FIELD_CHUNK_SAMPLE_COUNT]u8,
}

Field_Water_Front :: struct {
	passes:   [dynamic]^Field_Water_Front_Pass,
	by_chunk: map[Field_Chunk_Coordinate]^Field_Water_Front_Pass,
	// Inflow into each body's water this tick, by id.
	inflow:   []i64,
}

field_water_front_pass_for :: proc(front: ^Field_Water_Front, chunk: ^Field_Chunk) -> ^Field_Water_Front_Pass {
	if pass := front.by_chunk[chunk.coordinate] or_else nil; pass != nil {
		return pass
	}
	pass := new(Field_Water_Front_Pass, context.temp_allocator)
	pass.chunk, pass.start = chunk, chunk.water
	front.by_chunk[chunk.coordinate] = pass
	append(&front.passes, pass)
	return pass
}

// Before any planning, every awake spring of the front refills by its rate
// up to full (0367; its tick-start fill too), so no sender planned before
// it promises water against a fill the refill then overwrites. A spring the
// sea owns or under a body's level pours into it in pass one instead.
refill_field_water_front_springs :: proc(world: ^Field_World, front: ^Field_Water_Front, tuning: Field_Water_Tuning) {
	for pass in front.passes {
		chunk := pass.chunk
		for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
			bits := pass.awake[word] & chunk.water_source[word]
			for bits != 0 {
				bit := u64(intrinsics.count_trailing_zeros(bits))
				bits &= field_bits_above(bit)
				index := word * 64 + int(bit)
				refill := min(FIELD_WATER_FULL, i32(pass.start[index]) + tuning.spring_rate)
				if chunk.density[index] > 0 || chunk.water_owner[index] == WATER_OWNER_SEA || refill == i32(pass.start[index]) {
					continue
				}
				sample := field_chunk_sample(chunk, index)
				if _, credited := field_water_sample_credits(world, chunk, index, field_water_span(sample)); credited {
					continue
				}
				pass.start[index] = u8(refill)
				set_front_water(world, chunk, index, sample, refill)
			}
		}
	}
}

// Pass one for an awake sample: ground and the sea's samples sleep (a
// spring the sea owns pours into it); a spring under a body's level pours
// into the body (through the inflow, so its level follows); a spring was
// refilled before the planning; a film dries; else the sample
// plans its moves to its six neighbours, nearer the centre first, each the
// share of the two projected fills (the tick-start fill plus what this
// tick's plan brought and took so far), at most what it has left of its
// tick-start fill and the receiver's projected room. A move into a body's
// water or the sea's counts against the room and goes to the volume, and
// is an impact (from above) or a stream mouth (from the side) for the
// surface waves (0294). A move into a missing sample goes to the set's
// edge (0370), no event.
plan_field_water_front :: proc(world: ^Field_World, front: ^Field_Water_Front, pass: ^Field_Water_Front_Pass, index: int, tuning: Field_Water_Tuning, tick: u64) {
	chunk := pass.chunk
	sample := field_chunk_sample(chunk, index)
	expire_field_water_moved(world, chunk, index, sample)
	if chunk.density[index] > 0 {
		chunk.water_flow[index] = 0
		sleep_field_water_sample(world, chunk, index)
		return
	}
	source := field_sample_bit(&chunk.water_source, index)
	span := field_water_span(sample)
	if chunk.water_owner[index] == WATER_OWNER_SEA {
		chunk.water_flow[index] = 0
		if source {
			world.water_to_sea += i64(tuning.spring_rate)
			world.water_step_counts.spring_outflow += i64(tuning.spring_rate)
		} else {
			sleep_field_water_sample(world, chunk, index)
		}
		return
	}
	if source {
		if id, credited := field_water_sample_credits(world, chunk, index, span); credited {
			front.inflow[id] += i64(tuning.spring_rate)
			world.water_step_counts.spring_outflow += i64(tuning.spring_rate)
			chunk.water_flow[index] = 0
			return
		}
	}
	world.water_body_counts.front += 1
	neighbours := field_water_neighbours(world, chunk, sample)
	start := i32(pass.start[index])
	if start == 0 {
		return
	}
	if field_water_is_film(start, span, neighbours, tuning) {
		set_field_sample_bit(&pass.film, index)
		if tuning.dry_ticks > 0 && tick % tuning.dry_ticks == 0 {
			dry_field_water_film(world, chunk, index, sample)
			if chunk.water[index] == 0 {
				chunk.water_flow[index] = 0
				sleep_field_water_sample(world, chunk, index)
			}
		}
		return
	}
	left := start
	for nearer in ([2]bool{true, false}) {
		for neighbour in neighbours {
			if (neighbour.span.middle < span.middle) != nearer || left == 0 {
				continue
			}
			receiver := neighbour.chunk
			if receiver == nil {
				// The set's edge (0370): the share leaves the simulation.
				amount := field_water_edge_share(world, span, start + i32(pass.delta[index]), neighbour, tuning, left)
				if amount > 0 {
					pass.delta[index] -= i16(amount)
					pass.outflow[index] += u8(amount)
					left -= amount
					world.water_step_counts.moves += 1
					world.water_step_counts.moved_fill += i64(amount)
					if source {
						world.water_step_counts.spring_outflow += i64(amount)
					}
					world.water_to_edge += i64(amount)
				}
				continue
			}
			if receiver.density[neighbour.index] > 0 {
				continue
			}
			receiver_pass := front.by_chunk[receiver.coordinate] or_else nil
			body, credited := field_water_sample_credits(world, receiver, neighbour.index, neighbour.span)
			receiver_start := receiver_pass != nil ? i32(receiver_pass.start[neighbour.index]) : i32(receiver.water[neighbour.index])
			if !credited && receiver.water_owner[neighbour.index] != WATER_OWNER_NONE && !field_sample_bit(&receiver.water_awake, neighbour.index) {
				// A body's dry air holds no front water: its byte is stale.
				receiver_start = 0
			}
			promised := receiver_pass != nil ? i32(receiver_pass.delta[neighbour.index]) : 0
			sender_fill := start + i32(pass.delta[index])
			receiver_fill := receiver_start + promised
			amount := field_water_share_from(span, sender_fill, neighbour.span, receiver_fill, FIELD_WATER_FULL - receiver_fill, tuning, left)
			if amount <= 0 {
				continue
			}
			pass.delta[index] -= i16(amount)
			pass.outflow[index] += u8(amount)
			left -= amount
			world.water_step_counts.moves += 1
			world.water_step_counts.moved_fill += i64(amount)
			if source {
				world.water_step_counts.spring_outflow += i64(amount)
			}
			receiver_pass = field_water_front_pass_for(front, receiver)
			receiver_pass.delta[neighbour.index] += i16(amount)
			set_field_sample_bit(&receiver_pass.received, neighbour.index)
			if credited {
				if body == WATER_BODY_SEA {
					world.water_to_sea += i64(amount)
				} else {
					front.inflow[body] += i64(amount)
				}
				push_field_water_event(world, nearer ? .Impact : .Stream_Mouth, neighbour.sample, amount)
			}
		}
	}
}

// Pass two, chunks in coordinate order: every planned fill applies at
// once (the front sample and its neighbours wake, which is how the front
// spreads; a body's water took its share as volume), and an awake front
// sample counts a still tick when nothing moved through it (a steady drip
// is not still) and it held its fill. Only the awake and the received
// samples can be planned or carry a delta, so the apply visits their bits
// in index order (0367) in place of every sample of the chunk.
apply_field_water_front :: proc(world: ^Field_World, front: ^Field_Water_Front) {
	slice.sort_by(front.passes[:], proc(first, second: ^Field_Water_Front_Pass) -> bool {
		return field_chunk_coordinate_before(first.chunk.coordinate, second.chunk.coordinate)
	})
	for pass in front.passes {
		chunk := pass.chunk
		note_field_chunk_change(chunk)
		world.water_step_counts.apply_chunks += 1
		for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
			bits := pass.awake[word] | pass.received[word]
			world.water_step_counts.apply_visits += i64(intrinsics.count_ones(bits))
			for bits != 0 {
				bit := u64(intrinsics.count_trailing_zeros(bits))
				bits &= field_bits_above(bit)
				apply_field_water_front_sample(world, pass, word * 64 + int(bit))
			}
		}
	}
	for amount, id in front.inflow {
		if amount == 0 || !world.water_bodies[id].alive {
			continue
		}
		world.water_bodies[id].volume += amount
		world.water_body_counts.absorbed += amount
		relevel_water_body(world, Water_Body_Id(id))
	}
}

// One sample of pass two: its planned fill applied and its still tick
// counted (apply_field_water_front).
apply_field_water_front_sample :: proc(world: ^Field_World, pass: ^Field_Water_Front_Pass, index: int) {
	chunk := pass.chunk
	delta := i32(pass.delta[index])
	planned := field_sample_bit(&pass.awake, index)
	if delta == 0 && !planned {
		return
	}
	world.water_step_counts.apply_samples += 1
	sample := field_chunk_sample(chunk, index)
	span := field_water_span(sample)
	_, credited := field_water_sample_credits(world, chunk, index, span)
	if delta != 0 && !credited {
		set_front_water(world, chunk, index, sample, field_water_front_fill(chunk, index) + delta)
	}
	if !planned || credited || !field_sample_bit(&chunk.water_awake, index) || chunk.water_owner[index] == WATER_OWNER_SEA {
		return
	}
	chunk.water_flow[index] = pass.outflow[index]
	if field_sample_bit(&pass.film, index) || delta != 0 || pass.outflow[index] != 0 || chunk.water[index] != pass.start[index] {
		chunk.water_still[index] = 0
	} else {
		chunk.water_still[index] = u8(min(int(chunk.water_still[index]) + 1, 255))
	}
}

// A front sample into a body: its fill to the volume (the sea's discards
// it), its owner the body (the cell into the curve when it was another's
// or no one's), its byte the body's, asleep. A sample above the sea's
// level stays no one's.
absorb_front_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, span: Field_Water_Span, target: Water_Body_Id, changed: []bool) {
	fill := i64(chunk.water[index])
	level := water_body_level(world, target)
	if target == WATER_BODY_SEA {
		world.water_to_sea += fill
	} else {
		world.water_bodies[target].volume += fill
		changed[target] = true
	}
	world.water_body_counts.absorbed += fill
	owner := chunk.water_owner[index]
	new_owner := water_owner_of(target)
	if target == WATER_BODY_SEA && field_sea_fill(level, span) == 0 {
		new_owner = WATER_OWNER_NONE
	}
	if owner != new_owner {
		if previous, owned := water_owner_body(world, owner); owned && previous != WATER_BODY_SEA && owner != WATER_OWNER_RELEASED {
			remove_water_body_cell(&world.water_bodies[previous], &world.water_bodies[previous].loaded, span)
			changed[previous] = true
			// Its last cell taken: it dies, its volume to the target (the
			// relevel skips the dead slot).
			free_empty_water_body(world, previous, target)
		}
		if target != WATER_BODY_SEA {
			body := &world.water_bodies[target]
			add_water_body_cell(body, &body.loaded, span)
			insert_sorted_field_chunk(&body.chunks, chunk.coordinate)
		}
		chunk.water_owner[index] = new_owner
		note_field_chunk_change(chunk)
	}
	// Front water turns a body's still water: the mesher's plane from now
	// (0294), whether or not the owner changed.
	note_water_owner_change(world, chunk, sample)
	write_field_water_quiet(world, chunk, index, sample, field_sea_fill(level, span))
	chunk.water_moved[index] = 0
	if !field_sample_bit(&chunk.water_source, index) {
		sleep_field_water_sample(world, chunk, index)
	}
}

Field_Water_Seed_Candidate :: struct {
	bottom: i64,
	sample: Sample_Coordinate,
}

// Absorb and seed, over the front samples the passes ran: one whose
// nearer neighbour is a body's water (or the sea's) joins it; one a
// body's level rose over joins that body; one still for the still ticks
// joins the body whose dry air it rests in, or, in no body's, is a seed;
// a seed's sample its flood did not reach joins the new body
// (absorb_seed_candidate), so it never seeds again. Seeds flood in
// (bottom, sample order) while the budget lasts and no flood is pending;
// one left over stays awake and is tried next tick. An
// empty front sample still for the still ticks sleeps. A spring is neither
// absorbed nor a seed: it pours every tick (pass one).
settle_field_water_front :: proc(world: ^Field_World, front: ^Field_Water_Front, tuning: Field_Water_Tuning, budget: ^i64) {
	changed := make([]bool, len(world.water_bodies), context.temp_allocator)
	candidates := make([dynamic]Field_Water_Seed_Candidate, context.temp_allocator)
	for pass in front.passes {
		chunk := pass.chunk
		for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
			bits := pass.awake[word]
			for bits != 0 {
				bit := u64(intrinsics.count_trailing_zeros(bits))
				bits &= field_bits_above(bit)
				index := word * 64 + int(bit)
				if chunk.density[index] > 0 || !field_sample_bit(&chunk.water_awake, index) {
					continue
				}
				owner := chunk.water_owner[index]
				// A spring pours (pass one) and is never absorbed: its byte is
				// refilled every tick.
				if owner == WATER_OWNER_SEA || owner == WATER_OWNER_RELEASED || field_sample_bit(&chunk.water_source, index) {
					continue
				}
				own, owned := water_owner_body(world, owner)
				if owned && water_body_is_pending(world, own) {
					continue
				}
				fill := chunk.water[index]
				sample := field_chunk_sample(chunk, index)
				span := field_water_span(sample)
				target := -1
				if fill > 0 {
					for neighbour in field_water_neighbours(world, chunk, sample) {
						if neighbour.chunk == nil || neighbour.span.middle >= span.middle || neighbour.chunk.density[neighbour.index] > 0 {
							continue
						}
						if body, credited := field_water_sample_credits(world, neighbour.chunk, neighbour.index, neighbour.span); credited && !water_body_is_pending(world, body) {
							target = int(body)
							break
						}
					}
				}
				if target < 0 && owned && field_water_bottom(span) < world.water_bodies[own].level {
					target = int(own)
				}
				if target < 0 && fill > 0 && chunk.water_still[index] >= tuning.still_ticks {
					if owned {
						target = int(own)
					} else {
						append(&candidates, Field_Water_Seed_Candidate{field_water_bottom(span), sample})
					}
				}
				if target >= 0 {
					if len(changed) < len(world.water_bodies) {
						changed = make([]bool, len(world.water_bodies), context.temp_allocator)
					}
					absorb_front_water(world, chunk, index, sample, span, Water_Body_Id(target), changed)
				} else if fill == 0 && chunk.water_still[index] >= tuning.still_ticks {
					chunk.water_flow[index] = 0
					sleep_field_water_sample(world, chunk, index)
				}
			}
		}
	}
	for is_changed, id in changed {
		if is_changed {
			relevel_water_body(world, Water_Body_Id(id))
		}
	}
	slice.sort_by(candidates[:], proc(first, second: Field_Water_Seed_Candidate) -> bool {
		if first.bottom != second.bottom {
			return first.bottom < second.bottom
		}
		return field_sample_before(first.sample, second.sample)
	})
	for candidate in candidates {
		if budget^ <= 0 || world.water_flood.active {
			break
		}
		chunk, index := field_world_cell(world, candidate.sample)
		if chunk == nil || chunk.water_owner[index] != WATER_OWNER_NONE || !field_sample_bit(&chunk.water_awake, index) || chunk.water[index] == 0 {
			continue
		}
		if !seed_water_body(world, candidate.sample, tuning, budget) {
			break
		}
	}
}

// The bodies model's tick: the sea's claim, the dirty bodies' floods
// (the pending one first), the merge of bodies joined under water (0300),
// the weirs; then the front's two passes, the inflow into the bodies,
// absorption and seeding. The chunks whose front went to sleep leave the
// awake set. Nothing here reads the pressure pull.
step_field_water_bodies :: proc(world: ^Field_World, tuning: Field_Water_Tuning, tick: u64) {
	world.water_body_counts = {}
	world.water_pressure = {}
	make_sea_water_body(world)
	claim_sea(world)
	budget := tuning.flood_visit_budget
	reflood_dirty_water_bodies(world, tuning, &budget)
	merge_water_bodies_joined_under_water(world)
	emit_water_body_weirs(world, tuning)
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(world.water_awake_chunks), context.temp_allocator)
	for coordinate in world.water_awake_chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	front := Field_Water_Front {
		passes   = make([dynamic]^Field_Water_Front_Pass, 0, len(coordinates), context.temp_allocator),
		by_chunk = make(map[Field_Chunk_Coordinate]^Field_Water_Front_Pass, context.temp_allocator),
		inflow   = make([]i64, len(world.water_bodies), context.temp_allocator),
	}
	for coordinate in coordinates {
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			delete_key(&world.water_awake_chunks, coordinate)
			continue
		}
		pass := field_water_front_pass_for(&front, chunk)
		pass.awake = chunk.water_awake
	}
	refill_field_water_front_springs(world, &front, tuning)
	awake_passes := len(front.passes)
	for pass_index in 0 ..< awake_passes {
		pass := front.passes[pass_index]
		for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
			bits := pass.awake[word]
			for bits != 0 {
				bit := u64(intrinsics.count_trailing_zeros(bits))
				plan_field_water_front(world, &front, pass, word * 64 + int(bit), tuning, tick)
				bits &= field_bits_above(bit)
			}
		}
	}
	apply_field_water_front(world, &front)
	settle_field_water_front(world, &front, tuning, &budget)
	for pass in front.passes {
		if !field_sample_bits_any(&pass.chunk.water_awake) {
			delete_key(&world.water_awake_chunks, pass.chunk.coordinate)
		}
	}
	free_empty_water_bodies(world)
	for body in world.water_bodies {
		if body.alive {
			world.water_body_counts.bodies += 1
		}
	}
}

// After a terrain set under bodies: a body's still sample turned ground
// leaves the body, which keeps its volume and floods again (its level
// rises over the lost cell); the sea's leaves the sea; front water there
// goes to the neighbours, a body's water among them taking it as volume.
// The body of the sample and of its six neighbours floods again this tick
// (a hole beside or under a lake: the step runs after the edits), and an
// air sample below the sea level beside the sea seeds the sea's claim.
follow_field_terrain_with_bodies :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	span := field_water_span(sample)
	if chunk.density[index] > 0 {
		owner := chunk.water_owner[index]
		front_water := field_water_front_fill(chunk, index)
		if owner != WATER_OWNER_NONE {
			if id, owned := water_owner_body(world, owner); owned && id != WATER_BODY_SEA {
				if owner != WATER_OWNER_RELEASED {
					remove_water_body_cell(&world.water_bodies[id], &world.water_bodies[id].loaded, span)
				}
				mark_water_body_dirty(world, id)
				free_empty_water_body(world, id)
			}
			chunk.water_owner[index] = WATER_OWNER_NONE
			note_field_chunk_change(chunk)
			if front_water == 0 {
				write_field_water_quiet(world, chunk, index, sample, 0)
			}
		}
		if front_water > 0 {
			displace_front_water(world, chunk, index, sample, front_water)
		}
	}
	follow_cell :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
		owner := chunk.water_owner[index]
		if id, owned := water_owner_body(world, owner); owned {
			mark_water_body_dirty(world, id)
		}
		if chunk.density[index] <= 0 && owner != WATER_OWNER_SEA && owner != WATER_OWNER_RELEASED && field_sea_fill(world.water_planet.sea_level, field_water_span(sample)) > 0 && field_sample_beside_sea(world, chunk, sample) {
			append(&world.water_sea_seeds, sample)
		}
	}
	follow_cell(world, chunk, index, sample)
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		if neighbour, neighbour_index := field_water_cell(world, chunk, sample, offset); neighbour != nil {
			follow_cell(world, neighbour, neighbour_index, sample + Sample_Coordinate(offset))
		}
	}
	wake_field_water_around(world, chunk, index, sample)
}

// Front water a place displaced: to the neighbours with room in sample
// order, all of it into a body's water or the sea's when one is beside;
// what fits nowhere is dropped and counted.
displace_front_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	left := fill
	set_field_water(world, chunk, index, sample, 0)
	for neighbour in field_water_neighbours(world, chunk, sample) {
		if left == 0 {
			break
		}
		if neighbour.chunk == nil || neighbour.chunk.density[neighbour.index] > 0 {
			continue
		}
		if body, credited := field_water_sample_credits(world, neighbour.chunk, neighbour.index, neighbour.span); credited {
			if body == WATER_BODY_SEA {
				world.water_to_sea += i64(left)
			} else {
				world.water_bodies[body].volume += i64(left)
				relevel_water_body(world, body)
			}
			left = 0
			break
		}
		base := field_water_front_fill(neighbour.chunk, neighbour.index)
		amount := min(left, FIELD_WATER_FULL - base)
		if amount > 0 {
			set_front_water(world, neighbour.chunk, neighbour.index, neighbour.sample, base + amount)
			left -= amount
		}
	}
	world.water_dropped += i64(left)
}
