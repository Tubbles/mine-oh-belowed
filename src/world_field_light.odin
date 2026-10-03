package game

import "core:container/queue"
import "core:slice"

// The field light (work item 0173, doc/architecture.md, The field light):
// two bytes per sample beside the terrain, block light and sky light, 0 to
// FIELD_LIGHT_FULL, carried by a flood fill on the pattern of the block
// light (world_light.odin). Light spreads to the six face neighbours in
// air (terrain density at or below zero; water does not block it) and
// loses per step the falloff of data/lighting.sjson for the level it
// leaves, scaled by the spacing (Field_Light_Tuning.spread), so a room is
// the same size in metres at every spacing.
//
// Everything runs inside the tick through bounded queues, removals before
// additions: a removal queue that darkens what a removed source or a
// sample turned to ground used to light, and an addition queue that
// spreads light from its nodes. The spread never makes a brighter level
// dimmer (falloff_problem), so the final values do not depend on the
// order the nodes are visited in, and the per tick budget only spreads
// them over more ticks.
//
// Emitters (a torch, a lamp) are samples with a source level in
// Field_Lighting.sources, kept while their chunk is away and lit again
// when it arrives. Sky light is FIELD_LIGHT_FULL in a sample whose radial
// march outward meets no ground before it leaves the relief's shell
// (field_sky_is_open); the fill carries it from there into cave mouths.
// The generation gives every air sample full sky light
// (light_generated_field_chunk): the generated terrain is a height field
// along the radial, so no generated air lies under ground. Under an edit
// the samples in the edit's shadow march again at the end of the edit
// drain (update_field_sky_after_edits).

FIELD_LIGHT_FULL :: MAXIMUM_FIELD_LIGHT
FIELD_LIGHT_LEVELS :: FIELD_LIGHT_FULL + 1
// The six face neighbours, in sample order.
FIELD_LIGHT_NEIGHBOUR_OFFSETS :: FIELD_WATER_NEIGHBOUR_OFFSETS

Field_Light_Channel :: enum u8 {
	Block,
	Sky,
}

// data/lighting.sjson in one spacing's steps: spread[level] is the level a
// neighbour gets from a sample at level.
Field_Light_Tuning :: struct {
	spread:               [FIELD_LIGHT_LEVELS]u8,
	dark_level:           u8,
	steps_per_tick:       int,
	chunk_seeds_per_tick: int,
}

// value is the level a removal's sample had before it was cleared.
Field_Light_Node :: struct {
	sample: Sample_Coordinate,
	value:  u8,
}

// The queues per channel, the chunks whose borders wait to be compared (a
// set, taken in coordinate order), the samples whose ground changed in
// this tick's edits (their shadow marches at the end of the drain) and
// the emitters by sample. Every walk over a map goes in sorted order: a
// map's iteration order differs between machines.
Field_Lighting :: struct {
	removals:       [Field_Light_Channel]queue.Queue(Field_Light_Node),
	additions:      [Field_Light_Channel]queue.Queue(Sample_Coordinate),
	arrived_chunks: map[Field_Chunk_Coordinate]struct{},
	sky_edits:      map[Sample_Coordinate]struct{},
	sources:        map[Sample_Coordinate]u8,
}

// A loaded sample, found once.
Field_Light_Cell :: struct {
	chunk: ^Field_Chunk,
	index: int,
}

destroy_field_lighting :: proc(lighting: ^Field_Lighting) {
	for channel in Field_Light_Channel {
		queue.destroy(&lighting.removals[channel])
		queue.destroy(&lighting.additions[channel])
	}
	delete(lighting.arrived_chunks)
	delete(lighting.sky_edits)
	delete(lighting.sources)
}

// The level's band: its top bits, the darkest band 0.
field_light_band :: proc(level: int, band_count: int) -> int {
	return level * band_count / FIELD_LIGHT_LEVELS
}

// The loss of one step of the band's falloff per metre at the spacing,
// rounded to the nearest and at least 1.
field_light_step_loss :: proc(falloff_per_metre: int, spacing_millimetres: int) -> int {
	return max(1, (falloff_per_metre * spacing_millimetres + MILLIMETRES_PER_METRE / 2) / MILLIMETRES_PER_METRE)
}

make_field_light_tuning :: proc(lighting: Lighting_File, spacing_millimetres: int) -> Field_Light_Tuning {
	tuning := Field_Light_Tuning {
		dark_level           = u8(lighting.dark_level),
		steps_per_tick       = lighting.steps_per_tick,
		chunk_seeds_per_tick = lighting.chunk_seeds_per_tick,
	}
	for level in 0 ..< FIELD_LIGHT_LEVELS {
		loss := field_light_step_loss(lighting.falloff[field_light_band(level, len(lighting.falloff))], spacing_millimetres)
		tuning.spread[level] = u8(max(level - loss, 0))
	}
	return tuning
}

field_light_bytes :: proc(chunk: ^Field_Chunk, channel: Field_Light_Channel) -> ^[FIELD_CHUNK_SAMPLE_COUNT]u8 {
	return channel == .Block ? &chunk.block_light : &chunk.sky_light
}

field_light_cell :: proc(world: ^Field_World, sample: Sample_Coordinate) -> (cell: Field_Light_Cell, loaded: bool) {
	chunk := world.chunks[sample_to_field_chunk_coordinate(sample)] or_else nil
	if chunk == nil {
		return {}, false
	}
	return {chunk, sample_to_field_index(sample)}, true
}

field_cell_light :: proc(cell: Field_Light_Cell, channel: Field_Light_Channel) -> u8 {
	return field_light_bytes(cell.chunk, channel)[cell.index]
}

field_cell_is_ground :: proc(cell: Field_Light_Cell) -> bool {
	return cell.chunk.density[cell.index] > 0
}

// The chunks that mesh the sample remesh, at every level of detail.
set_field_cell_light :: proc(world: ^Field_World, cell: Field_Light_Cell, sample: Sample_Coordinate, channel: Field_Light_Channel, level: u8) {
	field_light_bytes(cell.chunk, channel)[cell.index] = level
	note_field_chunk_change(cell.chunk)
	mark_field_chunks_around_sample_dirty(world, cell.chunk.coordinate, sample)
	world.edited_chunks[cell.chunk.coordinate] = {}
}

push_field_light_addition :: proc(world: ^Field_World, channel: Field_Light_Channel, sample: Sample_Coordinate) {
	queue.push_back(&world.light.additions[channel], sample)
}

push_field_light_removal :: proc(world: ^Field_World, channel: Field_Light_Channel, sample: Sample_Coordinate, value: u8) {
	queue.push_back(&world.light.removals[channel], Field_Light_Node{sample, value})
}

// Clears the cell's light on the channel and queues the removal of what
// it lit.
clear_field_cell_light :: proc(world: ^Field_World, cell: Field_Light_Cell, sample: Sample_Coordinate, channel: Field_Light_Channel) {
	level := field_cell_light(cell, channel)
	if level == 0 {
		return
	}
	set_field_cell_light(world, cell, sample, channel, 0)
	push_field_light_removal(world, channel, sample, level)
}

// Raises the cell to level and spreads it, when level is brighter and the
// cell is air.
raise_field_cell_light :: proc(world: ^Field_World, cell: Field_Light_Cell, sample: Sample_Coordinate, channel: Field_Light_Channel, level: u8) {
	if field_cell_is_ground(cell) || level <= field_cell_light(cell, channel) {
		return
	}
	set_field_cell_light(world, cell, sample, channel, level)
	push_field_light_addition(world, channel, sample)
}

// An emitter's own level back in its sample (a cleared one, or one that
// arrived or became air).
restore_field_light_source :: proc(world: ^Field_World, cell: Field_Light_Cell, sample: Sample_Coordinate) {
	if level, found := world.light.sources[sample]; found {
		raise_field_cell_light(world, cell, sample, .Block, level)
	}
}

// Neighbours dimmer than the removed level got their light from it and
// are cleared in turn; an emitter among them gets its own level back.
// Brighter ones have another source and spread it back.
field_light_removal_step :: proc(world: ^Field_World, channel: Field_Light_Channel, node: Field_Light_Node) {
	for offset in FIELD_LIGHT_NEIGHBOUR_OFFSETS {
		neighbour := node.sample + Sample_Coordinate(offset)
		cell := field_light_cell(world, neighbour) or_continue
		level := field_cell_light(cell, channel)
		switch {
		case level == 0:
		case level < node.value:
			set_field_cell_light(world, cell, neighbour, channel, 0)
			push_field_light_removal(world, channel, neighbour, level)
			if channel == .Block {
				restore_field_light_source(world, cell, neighbour)
			}
		case:
			push_field_light_addition(world, channel, neighbour)
		}
	}
}

field_light_addition_step :: proc(world: ^Field_World, tuning: Field_Light_Tuning, channel: Field_Light_Channel, sample: Sample_Coordinate) {
	cell, loaded := field_light_cell(world, sample)
	if !loaded {
		return
	}
	spread := tuning.spread[field_cell_light(cell, channel)]
	if spread == 0 {
		return
	}
	for offset in FIELD_LIGHT_NEIGHBOUR_OFFSETS {
		neighbour := sample + Sample_Coordinate(offset)
		target := field_light_cell(world, neighbour) or_continue
		raise_field_cell_light(world, target, neighbour, channel, spread)
	}
}

// Runs at most maximum_steps queue nodes, every removal before any
// addition, the block channel's before the sky's. Returns the number run.
propagate_field_light :: proc(world: ^Field_World, tuning: Field_Light_Tuning, maximum_steps: int) -> int {
	light := &world.light
	steps := 0
	for ; steps < maximum_steps; steps += 1 {
		removal_channel, has_removal := field_light_queue_with_nodes(light.removals)
		addition_channel, has_addition := field_light_queue_with_nodes(light.additions)
		switch {
		case has_removal:
			field_light_removal_step(world, removal_channel, queue.pop_front(&light.removals[removal_channel]))
		case has_addition:
			field_light_addition_step(world, tuning, addition_channel, queue.pop_front(&light.additions[addition_channel]))
		case:
			return steps
		}
	}
	return steps
}

field_light_queue_with_nodes :: proc(queues: [Field_Light_Channel]queue.Queue($T)) -> (channel: Field_Light_Channel, found: bool) {
	for pending, candidate in queues {
		if queue.len(pending) > 0 {
			return candidate, true
		}
	}
	return .Block, false
}

pending_field_light_nodes :: proc(world: ^Field_World) -> int {
	total := 0
	for channel in Field_Light_Channel {
		total += queue.len(world.light.removals[channel]) + queue.len(world.light.additions[channel])
	}
	return total
}

// Emitters.

// Makes sample an emitter of level (or changes its level): what an old
// level lit goes through the removal queue first.
add_field_light_source :: proc(world: ^Field_World, sample: Sample_Coordinate, level: u8) {
	remove_field_light_source(world, sample)
	world.light.sources[sample] = level
	if cell, loaded := field_light_cell(world, sample); loaded {
		raise_field_cell_light(world, cell, sample, .Block, level)
	}
}

remove_field_light_source :: proc(world: ^Field_World, sample: Sample_Coordinate) {
	if sample not_in world.light.sources {
		return
	}
	delete_key(&world.light.sources, sample)
	if cell, loaded := field_light_cell(world, sample); loaded {
		clear_field_cell_light(world, cell, sample, .Block)
		queue_lit_field_neighbours(world, sample, {.Block})
	}
}

// Neighbours holding light on the channels spread it into the sample
// again.
queue_lit_field_neighbours :: proc(world: ^Field_World, sample: Sample_Coordinate, channels: bit_set[Field_Light_Channel]) {
	for offset in FIELD_LIGHT_NEIGHBOUR_OFFSETS {
		neighbour := sample + Sample_Coordinate(offset)
		cell := field_light_cell(world, neighbour) or_continue
		for channel in channels {
			if field_cell_light(cell, channel) > 0 {
				push_field_light_addition(world, channel, neighbour)
			}
		}
	}
}

// Terrain edits.

// After a terrain set (field_world_set_sample) that turned the sample to
// ground or to air: ground holds no light, so what the sample held is
// removed; air takes the neighbours' light and its emitter's. Either way
// the sample's shadow marches again at the end of the drain.
follow_field_terrain_with_light :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, was_ground: bool) {
	cell := Field_Light_Cell{chunk, index}
	if field_cell_is_ground(cell) == was_ground {
		return
	}
	world.light.sky_edits[sample] = {}
	if field_cell_is_ground(cell) {
		for channel in Field_Light_Channel {
			clear_field_cell_light(world, cell, sample, channel)
		}
		return
	}
	queue_lit_field_neighbours(world, sample, {.Block, .Sky})
	restore_field_light_source(world, cell, sample)
}

// The generation's sky: full in every air sample (the generated terrain
// is a height field along the radial). Safe on any thread.
light_generated_field_chunk :: proc(chunk: ^Field_Chunk) {
	for density, index in chunk.density {
		chunk.sky_light[index] = density > 0 ? 0 : FIELD_LIGHT_FULL
	}
}

// The sky march.

// The top of the relief's shell: no ground lies farther from the centre.
field_relief_top :: proc(generation: Planet_Generation) -> i64 {
	return generation.radius + metres_to_position_units(MAXIMUM_RELIEF_METRES) + generation.spacing
}

// Whether an air sample sees the sky: the samples nearest the points
// along its radial outward, a quarter spacing apart (as the spring's
// climb), are air until the radial leaves the loaded chunks above the
// relief's shell. Within the shell a missing chunk reads the generation,
// so an unloaded overhang shades; above it the generation is air, so the
// march ends at the first missing chunk there, and ground placed above
// the shell (a roof on a tall build) still shades.
field_sky_is_open :: proc(world: ^Field_World, generation: Planet_Generation, sample: Sample_Coordinate) -> bool {
	position := sample_to_world_position(sample, generation.spacing_millimetres)
	up, ok := normalize_fixed(([3]i64)(position))
	if !ok {
		return false
	}
	start := vector_length(([3]i64)(position))
	top := field_relief_top(generation)
	quarter := max(generation.spacing / 4, 1)
	previous := sample
	for along := quarter;; along += quarter {
		next := nearest_field_sample(position + World_Position(fixed_scale(up, along)), generation.spacing_millimetres)
		if next == previous {
			continue
		}
		previous = next
		cell, loaded := field_light_cell(world, next)
		switch {
		case loaded:
			if field_cell_is_ground(cell) {
				return false
			}
		case start + along > top:
			return true
		case planet_sample(generation, sample_to_world_position(next, generation.spacing_millimetres)).density > 0:
			return false
		}
	}
}

// The edit's shadow: the sample if it is air, and the loaded air samples
// nearest the points along its radial inward, a quarter spacing apart,
// until the first ground sample.
append_field_sky_shadow :: proc(world: ^Field_World, generation: Planet_Generation, sample: Sample_Coordinate, shadow: ^map[Sample_Coordinate]struct{}) {
	position := sample_to_world_position(sample, generation.spacing_millimetres)
	up, ok := normalize_fixed(([3]i64)(position))
	if !ok {
		return
	}
	if cell, loaded := field_light_cell(world, sample); loaded && !field_cell_is_ground(cell) {
		shadow[sample] = {}
	}
	start := vector_length(([3]i64)(position))
	quarter := max(generation.spacing / 4, 1)
	previous := sample
	for along := quarter; along < start - generation.spacing; along += quarter {
		next := nearest_field_sample(position - World_Position(fixed_scale(up, along)), generation.spacing_millimetres)
		if next == previous {
			continue
		}
		previous = next
		cell, loaded := field_light_cell(world, next)
		if !loaded || field_cell_is_ground(cell) {
			return
		}
		shadow[next] = {}
	}
}

z_y_x_before :: proc(first, second: Sample_Coordinate) -> bool {
	return field_chunk_coordinate_before(Field_Chunk_Coordinate(first), Field_Chunk_Coordinate(second))
}

// Full sky light where the march is open, none from the sky directly
// where it is not (the fill may bring some back).
apply_field_sky :: proc(world: ^Field_World, cell: Field_Light_Cell, sample: Sample_Coordinate, open: bool) {
	level := field_cell_light(cell, .Sky)
	switch {
	case open && level != FIELD_LIGHT_FULL:
		set_field_cell_light(world, cell, sample, .Sky, FIELD_LIGHT_FULL)
		push_field_light_addition(world, .Sky, sample)
	case !open && level == FIELD_LIGHT_FULL:
		clear_field_cell_light(world, cell, sample, .Sky)
	}
}

// The end of the edit drain: every air sample in the shadow of a sample
// whose ground changed marches again on the final field of the tick, in
// sample order. Each march reads only the field, so the result does not
// depend on the order of the edits. A world with no planet (tests) has no
// sky to march.
update_field_sky_after_edits :: proc(world: ^Field_World) {
	if len(world.light.sky_edits) == 0 {
		return
	}
	defer clear(&world.light.sky_edits)
	generation := world.water_planet.generation
	if generation.spacing_millimetres == 0 {
		return
	}
	shadow := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
	for sample in world.light.sky_edits {
		append_field_sky_shadow(world, generation, sample, &shadow)
	}
	samples := make([dynamic]Sample_Coordinate, 0, len(shadow), context.temp_allocator)
	for sample in shadow {
		append(&samples, sample)
	}
	slice.sort_by(samples[:], z_y_x_before)
	for sample in samples {
		cell, _ := field_light_cell(world, sample)
		apply_field_sky(world, cell, sample, field_sky_is_open(world, generation, sample))
	}
}

// Arriving chunks.

// A chunk arrived (field_world_insert_chunk): its generation never lit it
// from its neighbours, nor them from it, so each face sample whose light
// would raise the sample across the face spreads, both ways; its emitters
// shine.
seed_field_chunk_light :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate) {
	chunk := world.chunks[coordinate] or_else nil
	if chunk == nil {
		return
	}
	for offset in FIELD_LIGHT_NEIGHBOUR_OFFSETS {
		neighbour := world.chunks[coordinate + Field_Chunk_Coordinate(offset)] or_else nil
		if neighbour == nil {
			continue
		}
		for pair in field_face_pairs(offset) {
			seed_field_light_across(world, {neighbour, pair[0]}, {chunk, pair[1]})
			seed_field_light_across(world, {chunk, pair[1]}, {neighbour, pair[0]})
		}
	}
	emitters := make([dynamic]Sample_Coordinate, context.temp_allocator)
	for sample in world.light.sources {
		if sample_to_field_chunk_coordinate(sample) == coordinate {
			append(&emitters, sample)
		}
	}
	slice.sort_by(emitters[:], z_y_x_before)
	for sample in emitters {
		restore_field_light_source(world, {chunk, sample_to_field_index(sample)}, sample)
	}
}

// Queues from on every channel where it is brighter than to; the
// addition step finds whether its spread raises to.
seed_field_light_across :: proc(world: ^Field_World, from, to: Field_Light_Cell) {
	if field_cell_is_ground(to) {
		return
	}
	for channel in Field_Light_Channel {
		level := field_cell_light(from, channel)
		if level > 0 && level > field_cell_light(to, channel) {
			push_field_light_addition(world, channel, field_chunk_sample(from.chunk, from.index))
		}
	}
}

// The arrived chunks' borders, the first in coordinate order up to the
// budget; a chunk that has left since is dropped without spending it.
seed_arrived_field_chunks :: proc(world: ^Field_World, maximum_chunks: int) {
	arrived := &world.light.arrived_chunks
	if len(arrived) == 0 {
		return
	}
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(arrived), context.temp_allocator)
	for coordinate in arrived {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	seeded := 0
	for coordinate in coordinates {
		if seeded == maximum_chunks {
			return
		}
		delete_key(arrived, coordinate)
		if coordinate in world.chunks {
			seed_field_chunk_light(world, coordinate)
			seeded += 1
		}
	}
}

// The light's tick (in tick_field_simulation, after the water): the
// arrived chunks' borders, then the queues, both within the budget of
// data/lighting.sjson.
tick_field_light :: proc(world: ^Field_World, tuning: Field_Light_Tuning) {
	seed_arrived_field_chunks(world, tuning.chunk_seeds_per_tick)
	propagate_field_light(world, tuning, tuning.steps_per_tick)
}
