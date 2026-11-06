package game

import "core:slice"

// The water bodies (work item 0293, doc/architecture.md, The water field:
// bodies), the tech demo's bodies model: a connected basin of still water
// is one record with an integer volume and a level, found by a priority
// flood over the water-capable samples with the radial potential, and the
// cellular rule runs only on the wet front (step_field_water_bodies in
// world_field_water.odin).
//
// A body owns the samples its flood claimed (Field_Chunk.water_owner):
// its water below the level and its dry air above it, up to the sill or
// the rise cap. The samples under the level are asleep and their bytes
// derived, field_sea_fill(level) as the sea's, rewritten a band at a time
// as the level moves (write_water_body_fills). Front water may lie in a
// body's dry air (awake: water falling through the basin), and is the
// front's until it is absorbed. Volume is in fill units, the level in fill
// units from the centre; the conserved quantity is the bodies' volumes
// plus the front's fills, never the bytes.
//
// The volume-level curve is a histogram of slopes per band of
// WATER_BODY_BAND fill units: a cell opens its slope at the band of its
// bottom and closes it at the band of its top, so the volume under a level
// is exact for the bucketed cells, integer and monotone, and
// body_level_of_volume is its inverse. The base (band 0's start) lowers
// when a cell below it is added, so no cell is ever folded and the bands
// are a function of the cells alone.
//
// The flood (run_water_body_flood) pops samples in (bottom, sample order)
// from the seed, claims each, and stops at the first sample beyond a
// saddle (a slab wholly under the running sill), at the sea, or past the
// rise cap; a sealed basin floods to its rim. It is bounded per tick by
// flood_visit_budget and resumes next tick; its heap and its pushed
// samples are saved as they stand (simulation_field_save.odin), so a
// loaded machine finishes it on the same tick. The sea is body 0: a fixed
// level, no volume, its samples the generation's and those its claim
// reaches (claim_sea), never flooded.

Water_Body_Id :: distinct u16
WATER_BODY_SEA :: Water_Body_Id(0)
// A sample's owner: none, a body's id plus one (the sea's is 1), or the
// pending flood's old samples, which stay the flood body's until it ends.
Water_Owner :: u16
WATER_OWNER_NONE :: Water_Owner(0)
WATER_OWNER_SEA :: Water_Owner(1)
WATER_OWNER_RELEASED :: Water_Owner(0xFFFF)
// The most bodies the owner plane can name.
MAXIMUM_WATER_BODIES :: int(WATER_OWNER_RELEASED) - 1
// Fill units a histogram band, 1/16 sample.
WATER_BODY_BAND :: 16
// A cell's slope: FIELD_WATER_FULL << WATER_BODY_WEIGHT_SHIFT / height.
WATER_BODY_WEIGHT_SHIFT :: 8
// The settling walk of a seed: rounds, and samples a round.
WATER_BODY_SETTLE_ROUNDS :: 8
WATER_BODY_SETTLE_VISITS :: 256
// The bands a flood spans at most: the rise cap plus a slab below the
// seed and above the cap (a diagonal cell is under two samples high).
WATER_BODY_FLOOD_BANDS :: (MAXIMUM_FIELD_WATER_FLOOD_RISE + 4) * FIELD_WATER_FULL / WATER_BODY_BAND
// A band index the save reader accepts at most: four floods' spans, for
// a body merged from others whose bases lie lower (lower_water_body_base).
MAXIMUM_WATER_BODY_BAND :: 4 * WATER_BODY_FLOOD_BANDS
// The band entries a save's curves allocate at most in all.
MAXIMUM_WATER_BODY_BAND_ENTRIES :: 1 << 22
// A level or a base the save reader accepts at most: the far limit at
// the finest spacing, in fill units from the centre.
MAXIMUM_WATER_BODY_LEVEL :: i64(FAR_LIMIT_METRES) * MILLIMETRES_PER_METRE / i64(SAMPLE_SPACING_CHOICES_MILLIMETRES[0]) * FIELD_WATER_FULL

// The weights of the cells whose bottom, whose top lies in the band.
Water_Body_Band :: struct {
	opens, closes: i64,
}

// A body's cells in a chunk outside the set: owner is the id the chunk's
// samples carry (a merge keeps the absorbed body's), so the thaw finds
// them.
Water_Body_Frozen :: struct {
	chunk: Field_Chunk_Coordinate,
	owner: Water_Owner,
	bands: [dynamic]Water_Body_Band,
}

Water_Body :: struct {
	alive, sea, dirty, spill_to_sea: bool,
	// Fill units; 0 and unused for the sea.
	volume:        i64,
	// Exact fill units from the centre; the sea's is the planet's.
	level:         i64,
	// The level the bytes were last written for (write_water_body_fills).
	written_level: i64,
	// The level the body's chunks were last marked to mesh at (0294,
	// write_water_body_fills, FIELD_WATER_LOOK_LEVEL_STEP); min(i64) on a
	// fresh or loaded body. Derived, not saved.
	meshed_level:  i64,
	seed, spill:   Sample_Coordinate,
	// The sill; max(i64) when sealed or capped (no spill).
	spill_level:   i64,
	// volume_of_water_body_level(spill_level); max(i64) with no spill.
	spill_volume:  i64,
	// A pending flood's spent visits, 0 when none.
	flood_visits:  i64,
	// Band 0's start, a multiple of WATER_BODY_BAND.
	base:          i64,
	// The cells in loaded chunks.
	loaded:        [dynamic]Water_Body_Band,
	// Per chunk outside the set, in (coordinate, owner) order.
	frozen:        [dynamic]Water_Body_Frozen,
	// Loaded chunks that may hold its samples, coordinate order; derived,
	// not saved (rebuild_water_body_chunks).
	chunks:        [dynamic]Field_Chunk_Coordinate,
}

// The last tick's (Field_World.water_body_counts), debug only.
Water_Body_Counts :: struct {
	bodies, front, flood_visits, absorbed, seeded, merged: i64,
}

Water_Flood_Entry :: struct {
	bottom: i64,
	sample: Sample_Coordinate,
}

// The one pending flood. heap is a binary min-heap by (bottom, sample
// order) of its own, so the order never depends on a library; pushed
// holds a bit per sample pushed once, so a sample is visited once.
// old_chunks are the chunks holding released samples. redirty is set
// when something marks the flood's body dirty while it runs, so it floods
// again after.
Water_Flood :: struct {
	active, seeding, redirty: bool,
	// The still front sample a seeding flood began from (seed_water_body,
	// absorb_seed_candidate); none for a reflood.
	has_candidate:            bool,
	candidate:                Sample_Coordinate,
	body:                     Water_Body_Id,
	// The rise cap in samples, kept for a flood begun again.
	rise_samples:             i32,
	sill, rise_limit:         i64,
	heap:                     [dynamic]Water_Flood_Entry,
	pushed:                   map[Field_Chunk_Coordinate]^Field_Sample_Bits,
	old_chunks:               [dynamic]Field_Chunk_Coordinate,
}

water_owner_of :: proc(id: Water_Body_Id) -> Water_Owner {
	return Water_Owner(id) + 1
}

// The body an owner names: the released samples are the pending flood's;
// false for none or an id with no live body.
water_owner_body :: proc(world: ^Field_World, owner: Water_Owner) -> (id: Water_Body_Id, ok: bool) {
	switch owner {
	case WATER_OWNER_NONE:
		return 0, false
	case WATER_OWNER_RELEASED:
		return world.water_flood.body, world.water_flood.active
	}
	index := int(owner) - 1
	if index >= len(world.water_bodies) || !world.water_bodies[index].alive {
		return 0, false
	}
	return Water_Body_Id(index), true
}

water_body_is_pending :: proc(world: ^Field_World, id: Water_Body_Id) -> bool {
	return world.water_flood.active && world.water_flood.body == id
}

// The sea's level is the planet's.
water_body_level :: proc(world: ^Field_World, id: Water_Body_Id) -> i64 {
	if id == WATER_BODY_SEA {
		return world.water_planet.sea_level
	}
	return world.water_bodies[id].level
}

// Under the bodies model a world's table starts with the sea.
make_sea_water_body :: proc(world: ^Field_World) {
	if world.water_model != .Bodies || len(world.water_bodies) > 0 {
		return
	}
	append(&world.water_bodies, Water_Body{alive = true, sea = true, level = world.water_planet.sea_level, meshed_level = world.water_planet.sea_level, spill_level = max(i64), spill_volume = max(i64)})
}

// The lowest dead slot above the sea, else a new one; false when the
// owner plane can name no more.
allocate_water_body_id :: proc(world: ^Field_World) -> (id: Water_Body_Id, ok: bool) {
	for index in 1 ..< len(world.water_bodies) {
		if !world.water_bodies[index].alive {
			return Water_Body_Id(index), true
		}
	}
	if len(world.water_bodies) >= MAXIMUM_WATER_BODIES {
		return 0, false
	}
	append(&world.water_bodies, Water_Body{})
	return Water_Body_Id(len(world.water_bodies) - 1), true
}

destroy_water_body :: proc(body: ^Water_Body) {
	delete(body.loaded)
	for &part in body.frozen {
		delete(part.bands)
	}
	delete(body.frozen)
	delete(body.chunks)
	body^ = {}
}

// A body dies: its arrays freed, its slot free for the next.
kill_water_body :: proc(world: ^Field_World, id: Water_Body_Id) {
	destroy_water_body(&world.water_bodies[id])
}

// A body left with no cell (no loaded band, no frozen part), alive, not
// the sea and not pending, dies where its last cell left it (0299): its
// volume to the heir that took the cell (the sea's to water_to_sea, a
// body's to its volume, relevelled by the caller or at the pending
// flood's finish), with no heir as finish_water_body_flood sends its own.
// False, and nothing done, when the body is not empty.
free_empty_water_body :: proc(world: ^Field_World, id: Water_Body_Id, heir: Maybe(Water_Body_Id) = nil) -> bool {
	body := &world.water_bodies[id]
	if !body.alive || body.sea || water_body_is_pending(world, id) || len(body.loaded) > 0 || len(body.frozen) > 0 {
		return false
	}
	if target, has_heir := heir.?; has_heir {
		if target == WATER_BODY_SEA {
			world.water_to_sea += body.volume
		} else {
			world.water_bodies[target].volume += body.volume
		}
	} else if body.spill_to_sea {
		world.water_to_sea += body.volume
	} else {
		world.water_dropped += body.volume
	}
	kill_water_body(world, id)
	return true
}

// The sweep at the end of a bodies tick: any empty body left (a table
// saved before 0299) dies, in id order.
free_empty_water_bodies :: proc(world: ^Field_World) {
	for index in 1 ..< len(world.water_bodies) {
		free_empty_water_body(world, Water_Body_Id(index))
	}
}

clear_water_flood :: proc(flood: ^Water_Flood) {
	clear(&flood.heap)
	for _, bits in flood.pushed {
		free(bits)
	}
	clear(&flood.pushed)
	clear(&flood.old_chunks)
}

destroy_water_bodies :: proc(world: ^Field_World) {
	for &body in world.water_bodies {
		destroy_water_body(&body)
	}
	delete(world.water_bodies)
	clear_water_flood(&world.water_flood)
	delete(world.water_flood.heap)
	delete(world.water_flood.pushed)
	delete(world.water_flood.old_chunks)
	delete(world.water_sea_seeds)
}

// Marks a body to flood again; one pending floods again after it ends.
mark_water_body_dirty :: proc(world: ^Field_World, id: Water_Body_Id) {
	if id == WATER_BODY_SEA {
		return
	}
	world.water_bodies[id].dirty = true
	if water_body_is_pending(world, id) {
		world.water_flood.redirty = true
	}
}

// The chunk and index of a sample; nil when its chunk is not loaded.
field_world_cell :: proc(world: ^Field_World, sample: Sample_Coordinate) -> (chunk: ^Field_Chunk, index: int) {
	return world.chunks[sample_to_field_chunk_coordinate(sample)] or_else nil, sample_to_field_index(sample)
}

insert_sorted_field_chunk :: proc(chunks: ^[dynamic]Field_Chunk_Coordinate, coordinate: Field_Chunk_Coordinate) {
	position, found := slice.binary_search_by(chunks[:], coordinate, field_chunk_coordinate_order)
	if !found {
		inject_at(chunks, position, coordinate)
	}
}

// The curve.

water_body_band_index :: proc(base, level: i64) -> int {
	return int(floor_divide_i64(level - base, WATER_BODY_BAND))
}

water_body_cell_weight :: proc(span: Field_Water_Span) -> i64 {
	return (FIELD_WATER_FULL << WATER_BODY_WEIGHT_SHIFT) / span.height
}

// Shifts every band array of the body so band 0 starts at base, when base
// lies below the body's.
lower_water_body_base :: proc(body: ^Water_Body, base: i64) {
	if base >= body.base {
		return
	}
	shift := int((body.base - base) / WATER_BODY_BAND)
	shift_bands :: proc(bands: ^[dynamic]Water_Body_Band, shift: int) {
		if len(bands) == 0 {
			return
		}
		old := len(bands)
		resize(bands, old + shift)
		copy(bands[shift:], bands[:old])
		for index in 0 ..< shift {
			bands[index] = {}
		}
	}
	shift_bands(&body.loaded, shift)
	for &part in body.frozen {
		shift_bands(&part.bands, shift)
	}
	body.base = base
}

// The cell's slope into bands (the body's loaded bands or a frozen
// part's), the base lowered first when the cell lies below it.
add_water_body_cell :: proc(body: ^Water_Body, bands: ^[dynamic]Water_Body_Band, span: Field_Water_Span) {
	bottom := field_water_bottom(span)
	lower_water_body_base(body, floor_divide_i64(bottom, WATER_BODY_BAND) * WATER_BODY_BAND)
	weight := water_body_cell_weight(span)
	open := water_body_band_index(body.base, bottom)
	close := water_body_band_index(body.base, bottom + span.height)
	if len(bands) <= close {
		resize(bands, close + 1)
	}
	bands[open].opens += weight
	bands[close].closes += weight
}

// The inverse of add_water_body_cell; trailing empty bands are cut, so
// the arrays are a function of their cells.
remove_water_body_cell :: proc(body: ^Water_Body, bands: ^[dynamic]Water_Body_Band, span: Field_Water_Span) {
	bottom := field_water_bottom(span)
	weight := water_body_cell_weight(span)
	open := water_body_band_index(body.base, bottom)
	close := water_body_band_index(body.base, bottom + span.height)
	if open < 0 || close >= len(bands) {
		return
	}
	bands[open].opens -= weight
	bands[close].closes -= weight
	for len(bands) > 0 && bands[len(bands) - 1] == {} {
		pop(bands)
	}
}

// The scaled slopes integrated up to level, in fill units.
volume_of_water_body_bands :: proc(bands: []Water_Body_Band, base, level: i64) -> i64 {
	slope, scaled: i64
	for band, index in bands {
		start := base + i64(index) * WATER_BODY_BAND
		if level <= start {
			break
		}
		slope += band.opens - band.closes
		scaled += slope * min(WATER_BODY_BAND, level - start)
	}
	return scaled >> WATER_BODY_WEIGHT_SHIFT
}

// The loaded part and every frozen part, one base.
volume_of_water_body_level :: proc(body: ^Water_Body, level: i64) -> i64 {
	volume := volume_of_water_body_bands(body.loaded[:], body.base, level)
	for part in body.frozen {
		volume += volume_of_water_body_bands(part.bands[:], body.base, level)
	}
	return volume
}

// The top of the curve: the end of the longest array.
water_body_top :: proc(body: ^Water_Body) -> i64 {
	longest := len(body.loaded)
	for part in body.frozen {
		longest = max(longest, len(part.bands))
	}
	return body.base + WATER_BODY_BAND * i64(longest)
}

water_body_capacity :: proc(body: ^Water_Body) -> i64 {
	return volume_of_water_body_level(body, water_body_top(body))
}

// The largest level in [base, top] whose volume is at most volume, by a
// binary search; the top when the body is over full (a sealed basin holds
// the excess as volume), the base for no volume.
body_level_of_volume :: proc(body: ^Water_Body, volume: i64) -> i64 {
	low, high := body.base, water_body_top(body)
	if volume_of_water_body_level(body, high) <= volume {
		return high
	}
	if volume < 0 {
		return low
	}
	// volume_of(low) is 0 <= volume < volume_of(high).
	for high - low > 1 {
		middle := low + (high - low) / 2
		if volume_of_water_body_level(body, middle) <= volume {
			low = middle
		} else {
			high = middle
		}
	}
	return low
}

// The level follows the volume; the bytes follow it a band at a time. A
// pending body keeps its old level until its flood ends.
relevel_water_body :: proc(world: ^Field_World, id: Water_Body_Id) {
	body := &world.water_bodies[id]
	if body.sea || !body.alive || water_body_is_pending(world, id) {
		return
	}
	body.level = body_level_of_volume(body, body.volume)
	write_water_body_fills(world, id, false)
}

// The bytes of the body's still samples (asleep, or a spring) to the fill
// under its level, the sea's expression, when the level crossed a band or
// with force. Front water in its air (awake) is left alone. The mesher
// draws the body's plane from the level itself (0294), so its chunks are
// marked to mesh again whenever the level moved a look step since they
// last were, whatever the bands do.
write_water_body_fills :: proc(world: ^Field_World, id: Water_Body_Id, force: bool) {
	body := &world.water_bodies[id]
	if body.sea {
		return
	}
	owner := water_owner_of(id)
	if body.meshed_level == min(i64) || abs(body.level - body.meshed_level) >= FIELD_WATER_LOOK_LEVEL_STEP {
		for coordinate in body.chunks {
			bits := FIELD_LOOK_REACH_SELF
			if chunk := world.chunks[coordinate] or_else nil; chunk != nil {
				bits |= field_look_owned_reach(chunk, owner)
			}
			mark_field_look_reach(world, coordinate, bits)
		}
		body.meshed_level = body.level
	}
	if !force && floor_divide_i64(body.level, WATER_BODY_BAND) == floor_divide_i64(body.written_level, WATER_BODY_BAND) {
		return
	}
	for coordinate in body.chunks {
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			continue
		}
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] != owner || (field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index)) {
				continue
			}
			sample := field_chunk_sample(chunk, index)
			write_field_water_quiet(world, chunk, index, sample, field_sea_fill(body.level, field_water_span(sample)))
		}
	}
	body.written_level = body.level
}

// The flood.

water_flood_entry_before :: proc(first, second: Water_Flood_Entry) -> bool {
	if first.bottom != second.bottom {
		return first.bottom < second.bottom
	}
	return field_sample_before(first.sample, second.sample)
}

push_water_flood :: proc(flood: ^Water_Flood, entry: Water_Flood_Entry) {
	append(&flood.heap, entry)
	child := len(flood.heap) - 1
	for child > 0 {
		parent := (child - 1) / 2
		if !water_flood_entry_before(flood.heap[child], flood.heap[parent]) {
			break
		}
		flood.heap[child], flood.heap[parent] = flood.heap[parent], flood.heap[child]
		child = parent
	}
}

pop_water_flood :: proc(flood: ^Water_Flood) -> Water_Flood_Entry {
	top := flood.heap[0]
	last := pop(&flood.heap)
	if len(flood.heap) == 0 {
		return top
	}
	flood.heap[0] = last
	parent := 0
	for {
		smallest := parent
		for child in ([2]int{2 * parent + 1, 2 * parent + 2}) {
			if child < len(flood.heap) && water_flood_entry_before(flood.heap[child], flood.heap[smallest]) {
				smallest = child
			}
		}
		if smallest == parent {
			break
		}
		flood.heap[smallest], flood.heap[parent] = flood.heap[parent], flood.heap[smallest]
		parent = smallest
	}
	return top
}

// Marks the sample pushed; false when it was already.
mark_water_flood_pushed :: proc(flood: ^Water_Flood, sample: Sample_Coordinate) -> bool {
	coordinate := sample_to_field_chunk_coordinate(sample)
	bits := flood.pushed[coordinate] or_else nil
	if bits == nil {
		bits = new(Field_Sample_Bits)
		flood.pushed[coordinate] = bits
	}
	index := sample_to_field_index(sample)
	if field_sample_bit(bits, index) {
		return false
	}
	set_field_sample_bit(bits, index)
	return true
}

push_water_flood_sample :: proc(flood: ^Water_Flood, sample: Sample_Coordinate) {
	if mark_water_flood_pushed(flood, sample) {
		push_water_flood(flood, {bottom = field_water_bottom(field_water_span(sample)), sample = sample})
	}
}

// Whether the seed's walk may pass the sample: water-capable, and the
// body's own, released, or no one's.
water_body_walk_allows :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, id: Water_Body_Id) -> bool {
	if chunk.density[index] > 0 {
		return false
	}
	owner := chunk.water_owner[index]
	return owner == WATER_OWNER_NONE || owner == WATER_OWNER_RELEASED || owner == water_owner_of(id)
}

// Up to WATER_BODY_SETTLE_ROUNDS rounds of a breadth first walk through
// the samples one slab above the seed at most, WATER_BODY_SETTLE_VISITS a
// round, moving to the lowest by (bottom, sample order) while it is lower:
// the sphere's bottoms have one-cell dimples, and a flood from a dimple
// above the floor would spill after one cell.
settle_water_body_seed :: proc(world: ^Field_World, id: Water_Body_Id, seed: Sample_Coordinate) -> Sample_Coordinate {
	current := seed
	for _ in 0 ..< WATER_BODY_SETTLE_ROUNDS {
		span := field_water_span(current)
		current_bottom := field_water_bottom(span)
		limit := current_bottom + span.height
		best, best_bottom := current, current_bottom
		visited := make(map[Sample_Coordinate]struct{}, context.temp_allocator)
		queue := make([dynamic]Sample_Coordinate, context.temp_allocator)
		append(&queue, current)
		visited[current] = {}
		for head := 0; head < len(queue) && head < WATER_BODY_SETTLE_VISITS; head += 1 {
			from := queue[head]
			for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
				next := from + Sample_Coordinate(offset)
				if next in visited {
					continue
				}
				chunk, index := field_world_cell(world, next)
				if chunk == nil || !water_body_walk_allows(world, chunk, index, id) {
					continue
				}
				bottom := field_water_bottom(field_water_span(next))
				if bottom >= limit {
					continue
				}
				visited[next] = {}
				append(&queue, next)
				if bottom < best_bottom || (bottom == best_bottom && field_sample_before(next, best)) {
					best, best_bottom = next, bottom
				}
			}
		}
		if best_bottom >= current_bottom {
			break
		}
		current = best
	}
	return current
}

// The lowest (bottom, sample order) non-ground sample of the chunks whose
// owner is one of the two given; false for none.
lowest_owned_water_sample :: proc(world: ^Field_World, chunks: []Field_Chunk_Coordinate, first, second: Water_Owner) -> (lowest: Sample_Coordinate, found: bool) {
	lowest_bottom: i64
	for coordinate in chunks {
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			continue
		}
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			owner := chunk.water_owner[index]
			if (owner != first && owner != second) || chunk.density[index] > 0 {
				continue
			}
			sample := field_chunk_sample(chunk, index)
			bottom := field_water_bottom(field_water_span(sample))
			if !found || bottom < lowest_bottom || (bottom == lowest_bottom && field_sample_before(sample, lowest)) {
				lowest, lowest_bottom, found = sample, bottom, true
			}
		}
	}
	return
}

// The body's samples in its chunks to released, its chunks to the flood's
// old chunks, its loaded bands and chunks cleared.
release_water_body_samples :: proc(world: ^Field_World, id: Water_Body_Id) {
	body := &world.water_bodies[id]
	flood := &world.water_flood
	owner := water_owner_of(id)
	for coordinate in body.chunks {
		insert_sorted_field_chunk(&flood.old_chunks, coordinate)
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			continue
		}
		// The released samples draw the flood's plane (0294).
		mark_field_look_reach(world, coordinate, FIELD_LOOK_REACH_SELF | field_look_owned_reach(chunk, owner))
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] == owner {
				chunk.water_owner[index] = WATER_OWNER_RELEASED
				note_field_chunk_change(chunk)
			}
		}
	}
	clear(&body.chunks)
	clear(&body.loaded)
}

// A flood of the body begins (fresh) or begins again (after a chunk of
// it left the set): its samples released, the seed checked (a ground or
// missing seed moves to the lowest released sample; with none the flood
// ends, and a body with nothing left dies with its volume dropped), and
// the heap holding the seed. A fresh start settles the seed and sets the
// base from it. False when no flood runs.
start_water_body_flood :: proc(world: ^Field_World, id: Water_Body_Id, tuning: Field_Water_Tuning, fresh: bool) -> bool {
	flood := &world.water_flood
	if fresh {
		clear_water_flood(flood)
		body := &world.water_bodies[id]
		flood.seeding = body.volume == 0 && len(body.frozen) == 0
		flood.redirty = false
		flood.has_candidate = false
		flood.rise_samples = tuning.flood_rise_samples
	} else {
		for _, bits in flood.pushed {
			free(bits)
		}
		clear(&flood.pushed)
		clear(&flood.heap)
	}
	flood.active, flood.body = true, id
	release_water_body_samples(world, id)
	body := &world.water_bodies[id]
	body.flood_visits = 0
	seed_chunk, seed_index := field_world_cell(world, body.seed)
	seed_lost := seed_chunk == nil || seed_chunk.density[seed_index] > 0
	if seed_lost {
		lowest, found := lowest_owned_water_sample(world, flood.old_chunks[:], WATER_OWNER_RELEASED, WATER_OWNER_RELEASED)
		if !found {
			// A lake walled solid: nothing is left to flood.
			end_water_body_flood(world)
			if len(body.frozen) == 0 {
				world.water_dropped += body.volume
				kill_water_body(world, id)
			} else {
				body.dirty = false
			}
			return false
		}
		body.seed = lowest
	} else if fresh {
		body.seed = settle_water_body_seed(world, id, body.seed)
	}
	seed_bottom := field_water_bottom(field_water_span(body.seed))
	if fresh {
		base := floor_divide_i64(seed_bottom, WATER_BODY_BAND) * WATER_BODY_BAND
		if len(body.frozen) == 0 {
			body.base = base
		} else {
			lower_water_body_base(body, base)
		}
	}
	flood.sill = seed_bottom
	flood.rise_limit = seed_bottom + i64(flood.rise_samples) * FIELD_WATER_FULL
	body.spill_level, body.spill_volume, body.spill_to_sea, body.spill = max(i64), max(i64), false, {}
	push_water_flood_sample(flood, body.seed)
	return true
}

// The pending flood ends: its state cleared, nothing pending.
end_water_body_flood :: proc(world: ^Field_World) {
	flood := &world.water_flood
	clear_water_flood(flood)
	flood.active, flood.seeding, flood.redirty = false, false, false
	flood.has_candidate = false
}

// Merges body other into the flood's body, connected under its water:
// the volume and frozen parts taken, the bases made one, other's samples
// released (the flood claims them again through connectivity), other
// dead.
merge_into_water_flood :: proc(world: ^Field_World, id, other: Water_Body_Id) {
	body := &world.water_bodies[id]
	absorbed := &world.water_bodies[other]
	body.volume += absorbed.volume
	lower_water_body_base(body, absorbed.base)
	lower_water_body_base(absorbed, body.base)
	for part in absorbed.frozen {
		append(&body.frozen, part)
	}
	clear(&absorbed.frozen)
	sort_water_body_frozen(body)
	release_water_body_samples(world, other)
	kill_water_body(world, other)
	world.water_body_counts.merged += 1
}

sort_water_body_frozen :: proc(body: ^Water_Body) {
	slice.sort_by(body.frozen[:], proc(first, second: Water_Body_Frozen) -> bool {
		if first.chunk != second.chunk {
			return field_chunk_coordinate_before(first.chunk, second.chunk)
		}
		return first.owner < second.owner
	})
}

// A front sample: awake water not yet a body's (the awake bit marks it in
// a body's dry air too).
field_water_is_front :: proc(chunk: ^Field_Chunk, index: int) -> bool {
	return chunk.water_owner[index] == WATER_OWNER_NONE || (field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index))
}

// The flood claims a sample: the running sill rises to it, the owner and
// the curve take it. Another body's dry sample leaves that body; front
// water there stays front (awake), and old water no one moves wakes as
// front.
claim_water_flood_sample :: proc(world: ^Field_World, id: Water_Body_Id, chunk: ^Field_Chunk, index: int, span: Field_Water_Span, bottom: i64) {
	flood := &world.water_flood
	flood.sill = max(flood.sill, bottom)
	previous := chunk.water_owner[index]
	if previous != WATER_OWNER_NONE && previous != WATER_OWNER_RELEASED {
		if other, ok := water_owner_body(world, previous); ok && other != id && other != WATER_BODY_SEA {
			remove_water_body_cell(&world.water_bodies[other], &world.water_bodies[other].loaded, span)
			relevel_water_body(world, other)
			// Its last cell taken: it dies, its volume to the flood's body.
			free_empty_water_body(world, other, id)
		}
	}
	if previous == WATER_OWNER_NONE && chunk.water[index] > 0 && !field_sample_bit(&chunk.water_awake, index) {
		force_wake_field_water_sample(world, chunk, index)
	}
	chunk.water_owner[index] = water_owner_of(id)
	note_field_chunk_change(chunk)
	note_water_owner_change(world, chunk, field_chunk_sample(chunk, index))
	body := &world.water_bodies[id]
	add_water_body_cell(body, &body.loaded, span)
	insert_sorted_field_chunk(&body.chunks, chunk.coordinate)
}

// One visit a pop while the heap holds samples and the budget lasts;
// true when the flood is done (a spill found, the rise cap passed, or the
// heap empty: sealed). The budget is checked per pop, so a tick never
// overruns it.
run_water_body_flood :: proc(world: ^Field_World, tuning: Field_Water_Tuning, budget: ^i64) -> (done: bool) {
	flood := &world.water_flood
	id := flood.body
	own := water_owner_of(id)
	for len(flood.heap) > 0 {
		if budget^ <= 0 {
			return false
		}
		budget^ -= 1
		world.water_bodies[id].flood_visits += 1
		world.water_body_counts.flood_visits += 1
		entry := pop_water_flood(flood)
		chunk, index := field_world_cell(world, entry.sample)
		if chunk == nil || chunk.density[index] > 0 {
			continue
		}
		owner := chunk.water_owner[index]
		span := field_water_span(entry.sample)
		bottom := entry.bottom
		body := &world.water_bodies[id]
		if owner == own {
			continue
		}
		if bottom > flood.rise_limit {
			return true
		}
		if owner == WATER_OWNER_SEA {
			body.spill, body.spill_level, body.spill_to_sea = entry.sample, max(flood.sill, bottom), true
			return true
		}
		if bottom + span.height <= flood.sill {
			body.spill, body.spill_level = entry.sample, flood.sill
			return true
		}
		if owner != WATER_OWNER_RELEASED {
			if other, ok := water_owner_body(world, owner); ok && other != id && bottom < world.water_bodies[other].level {
				// Connected under water: our sill at or under our level, or,
				// for a seeding flood (no level yet), under the other's. Else
				// the other's water stands above ours and spills to us.
				if flood.sill > (flood.seeding ? world.water_bodies[other].level : body.level) {
					continue
				}
				merge_into_water_flood(world, id, other)
			}
		}
		claim_water_flood_sample(world, id, chunk, index, span, bottom)
		for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
			next := entry.sample + Sample_Coordinate(offset)
			next_chunk, next_index := field_water_cell(world, chunk, entry.sample, offset)
			if next_chunk == nil {
				next_span := field_water_span(next)
				if field_missing_sample_sea(world.water_planet, next, next_span) > 0 {
					body = &world.water_bodies[id]
					body.spill, body.spill_level, body.spill_to_sea = entry.sample, max(flood.sill, field_water_bottom(next_span)), true
					return true
				}
				continue
			}
			if next_chunk.density[next_index] > 0 || next_chunk.water_owner[next_index] == own {
				continue
			}
			push_water_flood_sample(flood, next)
		}
	}
	return true
}

// The flood ends: the released samples it did not reach leave the body
// (their water to the front: a split, exact in one call), the spill's
// volume, the level (a seeding flood takes its front first,
// absorb_seeded_front, then its seed's sample when the flood did not
// claim it, absorb_seed_candidate), the bytes written, and a body with no
// cells left dies.
finish_water_body_flood :: proc(world: ^Field_World, tuning: Field_Water_Tuning) {
	flood := &world.water_flood
	id := flood.body
	for coordinate in flood.old_chunks {
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			continue
		}
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] != WATER_OWNER_RELEASED {
				continue
			}
			chunk.water_owner[index] = WATER_OWNER_NONE
			note_field_chunk_change(chunk)
			note_water_owner_change(world, chunk, field_chunk_sample(chunk, index))
			if chunk.water[index] > 0 && !field_sample_bit(&chunk.water_awake, index) {
				world.water_bodies[id].volume -= i64(chunk.water[index])
				force_wake_field_water_sample(world, chunk, index)
			}
		}
	}
	body := &world.water_bodies[id]
	body.spill_volume = body.spill_level == max(i64) ? max(i64) : volume_of_water_body_level(body, body.spill_level)
	if flood.seeding {
		absorb_seeded_front(world, id)
		absorb_seed_candidate(world, id)
	}
	body.level = body_level_of_volume(body, body.volume)
	body.dirty = flood.redirty
	body.flood_visits = 0
	spill_to_sea := body.spill_to_sea
	end_water_body_flood(world)
	write_water_body_fills(world, id, true)
	if len(body.loaded) == 0 && len(body.frozen) == 0 {
		if spill_to_sea {
			world.water_to_sea += body.volume
		} else {
			world.water_dropped += body.volume
		}
		kill_water_body(world, id)
	}
}

// A seeding flood's body takes the front it owns: the resting samples
// (still for a tick at least) set the level, then the samples under that
// level add theirs too; each absorbed sample sleeps with its byte derived.
// Water falling through the basin's air above the level keeps falling.
absorb_seeded_front :: proc(world: ^Field_World, id: Water_Body_Id) {
	body := &world.water_bodies[id]
	owner := water_owner_of(id)
	taken := make([dynamic][2]int, context.temp_allocator)
	chunk_list := make([dynamic]^Field_Chunk, context.temp_allocator)
	for coordinate, chunk_slot in body.chunks {
		chunk := world.chunks[coordinate] or_else nil
		append(&chunk_list, chunk)
		if chunk == nil {
			continue
		}
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] == owner && field_sample_bit(&chunk.water_awake, index) && chunk.water[index] > 0 && chunk.water_still[index] > 0 {
				body.volume += i64(chunk.water[index])
				append(&taken, [2]int{chunk_slot, index})
			}
		}
	}
	level := body_level_of_volume(body, body.volume)
	for chunk, chunk_slot in chunk_list {
		if chunk == nil {
			continue
		}
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] != owner || !field_sample_bit(&chunk.water_awake, index) || chunk.water[index] == 0 || chunk.water_still[index] > 0 {
				continue
			}
			if field_water_bottom(field_water_span(field_chunk_sample(chunk, index))) < level {
				body.volume += i64(chunk.water[index])
				append(&taken, [2]int{chunk_slot, index})
			}
		}
	}
	for entry in taken {
		chunk := chunk_list[entry[0]]
		world.water_body_counts.absorbed += i64(chunk.water[entry[1]])
		if !field_sample_bit(&chunk.water_source, entry[1]) {
			sleep_field_water_sample(chunk, entry[1])
		}
	}
}

// A seeding flood's seed sample it did not claim (the walk moved the
// seed, and the flood stopped at a saddle first) joins the new body
// (0299): when it is still front water no one owns (loaded, not ground,
// awake, not a spring, fill > 0), its fill goes to the volume and it
// sleeps empty, no one's, so it never seeds again. A candidate the flood
// claimed is the body's already.
absorb_seed_candidate :: proc(world: ^Field_World, id: Water_Body_Id) {
	flood := &world.water_flood
	if !flood.has_candidate {
		return
	}
	chunk, index := field_world_cell(world, flood.candidate)
	if chunk == nil || chunk.density[index] > 0 || chunk.water_owner[index] != WATER_OWNER_NONE || !field_sample_bit(&chunk.water_awake, index) || field_sample_bit(&chunk.water_source, index) || chunk.water[index] == 0 {
		return
	}
	fill := i64(chunk.water[index])
	world.water_bodies[id].volume += fill
	world.water_body_counts.absorbed += fill
	write_field_water_quiet(world, chunk, index, flood.candidate, 0)
	sleep_field_water_sample(chunk, index)
}

// The pending flood first, then every live dirty body in id order whose
// seed is loaded, while the budget lasts; one flood at most is left
// pending, resumed next tick.
reflood_dirty_water_bodies :: proc(world: ^Field_World, tuning: Field_Water_Tuning, budget: ^i64) {
	flood := &world.water_flood
	if flood.active {
		if !run_water_body_flood(world, tuning, budget) {
			return
		}
		finish_water_body_flood(world, tuning)
	}
	for index in 1 ..< len(world.water_bodies) {
		id := Water_Body_Id(index)
		body := &world.water_bodies[index]
		if !body.alive || body.sea || !body.dirty {
			continue
		}
		if seed_chunk, _ := field_world_cell(world, body.seed); seed_chunk == nil {
			continue
		}
		if budget^ <= 0 {
			return
		}
		if !start_water_body_flood(world, id, tuning, true) {
			continue
		}
		if !run_water_body_flood(world, tuning, budget) {
			return
		}
		finish_water_body_flood(world, tuning)
	}
}

// A new body from a still front sample: flooded at once, or left
// pending. The sample is kept on the flood for its finish
// (absorb_seed_candidate). False when no id is free.
seed_water_body :: proc(world: ^Field_World, sample: Sample_Coordinate, tuning: Field_Water_Tuning, budget: ^i64) -> bool {
	id, ok := allocate_water_body_id(world)
	if !ok {
		return false
	}
	world.water_bodies[id] = Water_Body {
		alive        = true,
		dirty        = true,
		seed         = sample,
		spill_level  = max(i64),
		spill_volume = max(i64),
		meshed_level = min(i64),
	}
	world.water_body_counts.seeded += 1
	if !start_water_body_flood(world, id, tuning, true) {
		return true
	}
	world.water_flood.has_candidate, world.water_flood.candidate = true, sample
	if run_water_body_flood(world, tuning, budget) {
		finish_water_body_flood(world, tuning)
	}
	return true
}

// The weir: a body over its sill hands water to its spill sample, at
// weir_rate_per_head a sample of head, between weir_floor and weir_cap, at
// most the excess, nothing while the excess is within weir_dead_band (the
// static friction is on the head). Into the sea, into another body's
// water (the two merge, the lower id surviving, once the lower's water
// reached the sill and the upper sits at it), or as front water at the
// spill sample, which lies beyond the saddle, so it is never re-absorbed
// into its own body: the stream starts. A body pending, dirty, without a
// spill or whose spill chunk is missing waits.
emit_water_body_weirs :: proc(world: ^Field_World, tuning: Field_Water_Tuning) {
	for index in 1 ..< len(world.water_bodies) {
		id := Water_Body_Id(index)
		body := &world.water_bodies[index]
		if !body.alive || body.sea || body.dirty || water_body_is_pending(world, id) || body.spill_level == max(i64) {
			continue
		}
		excess := body.volume - body.spill_volume
		if excess <= i64(tuning.weir_dead_band) {
			continue
		}
		head := body.level - body.spill_level
		flow := min(excess, max(i64(tuning.weir_floor), min(i64(tuning.weir_cap), i64(tuning.weir_rate_per_head) * head / FIELD_WATER_FULL)))
		chunk, sample_index := field_world_cell(world, body.spill)
		if body.spill_to_sea || (chunk != nil && chunk.water_owner[sample_index] == WATER_OWNER_SEA) {
			world.water_to_sea += flow
			body.volume -= flow
			relevel_water_body(world, id)
			continue
		}
		if chunk == nil || chunk.density[sample_index] > 0 {
			continue
		}
		span := field_water_span(body.spill)
		if other, credited := field_water_sample_credits(world, chunk, sample_index, span); credited && other != id {
			target := &world.water_bodies[other]
			target.volume += flow
			body.volume -= flow
			relevel_water_body(world, other)
			relevel_water_body(world, id)
			if !water_body_is_pending(world, other) && target.level >= body.spill_level && excess - flow <= i64(tuning.weir_dead_band) {
				merge_water_bodies(world, min(id, other), max(id, other))
			}
			continue
		}
		base := field_water_front_fill(chunk, sample_index)
		flow = min(flow, i64(FIELD_WATER_FULL - base))
		if flow <= 0 {
			continue
		}
		set_front_water(world, chunk, sample_index, body.spill, base + i32(flow))
		body.volume -= i64(flow)
		relevel_water_body(world, id)
	}
}

// Two bodies become one, the lower id surviving: the volumes and the
// curves added (one base), the absorbed one's samples its own, the
// survivor flooded again (dirty).
merge_water_bodies :: proc(world: ^Field_World, survivor, absorbed: Water_Body_Id) {
	kept := &world.water_bodies[survivor]
	gone := &world.water_bodies[absorbed]
	kept.volume += gone.volume
	lower_water_body_base(kept, gone.base)
	lower_water_body_base(gone, kept.base)
	if len(kept.loaded) < len(gone.loaded) {
		resize(&kept.loaded, len(gone.loaded))
	}
	for band, band_index in gone.loaded {
		kept.loaded[band_index].opens += band.opens
		kept.loaded[band_index].closes += band.closes
	}
	for part in gone.frozen {
		append(&kept.frozen, part)
	}
	clear(&gone.frozen)
	sort_water_body_frozen(kept)
	from, to := water_owner_of(absorbed), water_owner_of(survivor)
	for coordinate in gone.chunks {
		insert_sorted_field_chunk(&kept.chunks, coordinate)
		// The absorbed samples take the survivor's plane (0294).
		chunk := world.chunks[coordinate] or_else nil
		if chunk == nil {
			world.edited_chunks[coordinate] = {}
			continue
		}
		mark_field_look_reach(world, coordinate, FIELD_LOOK_REACH_SELF | field_look_owned_reach(chunk, from))
		for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			if chunk.water_owner[index] == from {
				chunk.water_owner[index] = to
				note_field_chunk_change(chunk)
			}
		}
	}
	kill_water_body(world, absorbed)
	kept = &world.water_bodies[survivor]
	kept.level = body_level_of_volume(kept, kept.volume)
	mark_water_body_dirty(world, survivor)
	world.water_body_counts.merged += 1
}

// 0295's intake: takes up to amount from the body (the level and the
// bytes follow); returns what was taken. intake is the sample the pump
// draws at: the surface waves' pump event (0294) and 0295 read it. The
// demo's pump and drain bucket call it (world_field_water_tool.odin), and
// credit_water_body_volume is its counterpart for a pour and an outlet.
displace_water_body_volume :: proc(world: ^Field_World, id: Water_Body_Id, intake: Sample_Coordinate, amount: i64) -> i64 {
	body := &world.water_bodies[id]
	if body.sea || !body.alive || amount <= 0 {
		return 0
	}
	taken := min(amount, max(body.volume, 0))
	body.volume -= taken
	relevel_water_body(world, id)
	if taken > 0 {
		push_field_water_event(world, .Pump, intake, i32(min(taken, i64(max(i32)))))
	}
	return taken
}

// 0295's pour and outlet: amount added to the body's volume (the level
// and the bytes follow; a sealed basin over full holds the excess as
// volume), the splash an impact event at sample for the surface waves
// (0294); returns what was added. Never the sea's: the caller sends that
// to water_to_sea.
credit_water_body_volume :: proc(world: ^Field_World, id: Water_Body_Id, sample: Sample_Coordinate, amount: i64) -> i64 {
	body := &world.water_bodies[id]
	if body.sea || !body.alive || amount <= 0 {
		return 0
	}
	body.volume += amount
	relevel_water_body(world, id)
	push_field_water_event(world, .Impact, sample, i32(min(amount, FIELD_WATER_FULL)))
	return amount
}

// The sea.

// Whether the sample is beside the sea: a loaded sea sample or a missing
// sample the generation makes sea.
field_sample_beside_sea :: proc(world: ^Field_World, chunk: ^Field_Chunk, sample: Sample_Coordinate) -> bool {
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		next_chunk, next_index := field_water_cell(world, chunk, sample, offset)
		if next_chunk == nil {
			next := sample + Sample_Coordinate(offset)
			if field_missing_sample_sea(world.water_planet, next, field_water_span(next)) > 0 {
				return true
			}
		} else if next_chunk.water_owner[next_index] == WATER_OWNER_SEA {
			return true
		}
	}
	return false
}

// A sample the sea's claim may take: water-capable, below the sea level,
// and no one's or a body's (never the pending flood's).
field_sample_sea_claimable :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) -> bool {
	owner := chunk.water_owner[index]
	if chunk.density[index] > 0 || owner == WATER_OWNER_SEA || owner == WATER_OWNER_RELEASED {
		return false
	}
	return field_sea_fill(world.water_planet.sea_level, field_water_span(sample)) > 0
}

// The sea claims what this tick's edits and arrivals joined to it: a
// breadth first walk from the seeds beside the sea through the claimable
// samples. A body loses the cells (and floods again), front water there
// goes to the sea, and each claimed sample holds the sea's fill, asleep.
claim_sea :: proc(world: ^Field_World) {
	if len(world.water_sea_seeds) == 0 {
		return
	}
	queue := make([dynamic]Sample_Coordinate, context.temp_allocator)
	for seed in world.water_sea_seeds {
		chunk, index := field_world_cell(world, seed)
		if chunk != nil && field_sample_sea_claimable(world, chunk, index, seed) && field_sample_beside_sea(world, chunk, seed) {
			append(&queue, seed)
		}
	}
	clear(&world.water_sea_seeds)
	for head := 0; head < len(queue); head += 1 {
		sample := queue[head]
		chunk, index := field_world_cell(world, sample)
		if chunk == nil || !field_sample_sea_claimable(world, chunk, index, sample) {
			continue
		}
		span := field_water_span(sample)
		owner := chunk.water_owner[index]
		if id, owned := water_owner_body(world, owner); owned && id != WATER_BODY_SEA {
			remove_water_body_cell(&world.water_bodies[id], &world.water_bodies[id].loaded, span)
			mark_water_body_dirty(world, id)
			free_empty_water_body(world, id, WATER_BODY_SEA)
		}
		if field_water_is_front(chunk, index) {
			world.water_to_sea += i64(chunk.water[index])
		}
		chunk.water_owner[index] = WATER_OWNER_SEA
		note_field_chunk_change(chunk)
		note_water_owner_change(world, chunk, sample)
		write_field_water_quiet(world, chunk, index, sample, field_sea_fill(world.water_planet.sea_level, span))
		if !field_sample_bit(&chunk.water_source, index) && field_sample_bit(&chunk.water_awake, index) {
			sleep_field_water_sample(chunk, index)
		}
		for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
			if next_chunk, next_index := field_water_cell(world, chunk, sample, offset); next_chunk != nil {
				next := sample + Sample_Coordinate(offset)
				if field_sample_sea_claimable(world, next_chunk, next_index, next) {
					append(&queue, next)
				}
			}
		}
	}
}

// An arriving chunk's face samples beside a loaded sea sample or a
// missing sea sample seed the sea's claim, so a chunk saved before 0293
// (no owners) is claimed as it enters.
seed_water_sea_facing :: proc(world: ^Field_World, chunk: ^Field_Chunk) {
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		neighbour := world.chunks[chunk.coordinate + Field_Chunk_Coordinate(offset)] or_else nil
		// pair[0] is the neighbour's face sample, pair[1] this chunk's
		// across it.
		for pair in field_face_pairs(offset) {
			index := pair[1]
			sample := field_chunk_sample(chunk, index)
			if !field_sample_sea_claimable(world, chunk, index, sample) {
				continue
			}
			beside: bool
			if neighbour == nil {
				next := sample + Sample_Coordinate(offset)
				beside = field_missing_sample_sea(world.water_planet, next, field_water_span(next)) > 0
			} else {
				beside = neighbour.water_owner[pair[0]] == WATER_OWNER_SEA
			}
			if beside {
				append(&world.water_sea_seeds, sample)
			}
		}
	}
}

// The simulated set's edges.

// A chunk leaves: every body with samples in it moves them to a frozen
// part (the same cells, so the volume and the level hold exactly); a
// pending body's released samples there are its again first. A body whose
// seed lay there moves it to its lowest loaded sample, or keeps it and
// sleeps wholly frozen. A pending flood touching the chunk begins again.
// The chunk is out of the world's map already (field_world_detach_chunk).
freeze_water_body_chunk :: proc(world: ^Field_World, chunk: ^Field_Chunk) {
	flood := &world.water_flood
	restart := false
	for index in 1 ..< len(world.water_bodies) {
		id := Water_Body_Id(index)
		body := &world.water_bodies[index]
		if !body.alive || body.sea {
			continue
		}
		pending := water_body_is_pending(world, id)
		_, in_chunks := slice.binary_search_by(body.chunks[:], chunk.coordinate, field_chunk_coordinate_order)
		_, in_old := slice.binary_search_by(flood.old_chunks[:], chunk.coordinate, field_chunk_coordinate_order)
		if !in_chunks && !(pending && in_old) {
			continue
		}
		owner := water_owner_of(id)
		part := Water_Body_Frozen {
			chunk = chunk.coordinate,
			owner = owner,
		}
		// What the chunk holds decides, never the lists: they may name
		// chunks the body has left, which a load's rebuild drops.
		holds := false
		for sample_index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
			current := chunk.water_owner[sample_index]
			if current != owner && !(pending && current == WATER_OWNER_RELEASED) {
				continue
			}
			holds = true
			span := field_water_span(field_chunk_sample(chunk, sample_index))
			if current == owner {
				remove_water_body_cell(body, &body.loaded, span)
			} else {
				chunk.water_owner[sample_index] = owner
				note_field_chunk_change(chunk)
			}
			add_water_body_cell(body, &part.bands, span)
		}
		if position, found := slice.binary_search_by(body.chunks[:], chunk.coordinate, field_chunk_coordinate_order); found {
			ordered_remove(&body.chunks, position)
		}
		if len(part.bands) > 0 {
			append(&body.frozen, part)
			sort_water_body_frozen(body)
		}
		if sample_to_field_chunk_coordinate(body.seed) == chunk.coordinate {
			searched := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
			append(&searched, ..body.chunks[:])
			if pending {
				for coordinate in flood.old_chunks {
					insert_sorted_field_chunk(&searched, coordinate)
				}
			}
			if lowest, found := lowest_owned_water_sample(world, searched[:], owner, pending ? WATER_OWNER_RELEASED : owner); found {
				body.seed = lowest
			}
		}
		if pending && holds {
			restart = true
		}
	}
	if position, found := slice.binary_search_by(flood.old_chunks[:], chunk.coordinate, field_chunk_coordinate_order); found {
		ordered_remove(&flood.old_chunks, position)
	}
	if restart {
		id := flood.body
		mark_water_body_dirty(world, id)
		if seed_chunk, _ := field_world_cell(world, world.water_bodies[id].seed); seed_chunk == nil {
			// Wholly frozen: no loaded sample is left to flood from; the body
			// floods once its chunks return.
			end_water_body_flood(world)
			world.water_bodies[id].dirty = true
			world.water_bodies[id].flood_visits = 0
			return
		}
		start_water_body_flood(world, id, {}, false)
	}
}

// A chunk arrives: every body with a frozen part for it takes the chunk's
// samples back (the inverse of the freeze; the bytes carry the
// ownership) and floods again, since the wall is gone; a body whose seed
// lay in a missing chunk moves it to its lowest loaded sample. Owners that
// name no live body are cleared, their still water counted dropped.
thaw_water_body_chunk :: proc(world: ^Field_World, chunk: ^Field_Chunk) {
	changed := false
	for index in 1 ..< len(world.water_bodies) {
		id := Water_Body_Id(index)
		body := &world.water_bodies[index]
		if !body.alive || body.sea {
			continue
		}
		for part_index := 0; part_index < len(body.frozen); {
			part := body.frozen[part_index]
			if part.chunk != chunk.coordinate {
				part_index += 1
				continue
			}
			delete(part.bands)
			ordered_remove(&body.frozen, part_index)
			owner := water_owner_of(id)
			for sample_index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				if chunk.water_owner[sample_index] != part.owner {
					continue
				}
				if part.owner != owner {
					chunk.water_owner[sample_index] = owner
					changed = true
				}
				add_water_body_cell(body, &body.loaded, field_water_span(field_chunk_sample(chunk, sample_index)))
			}
			insert_sorted_field_chunk(&body.chunks, chunk.coordinate)
			mark_water_body_dirty(world, id)
		}
		// A body that slept wholly frozen keeps its seed in a missing chunk;
		// it moves to the lowest loaded sample, so the body floods again.
		if seed_chunk, _ := field_world_cell(world, body.seed); seed_chunk == nil {
			owner := water_owner_of(id)
			if lowest, found := lowest_owned_water_sample(world, body.chunks[:], owner, owner); found {
				body.seed = lowest
			}
		}
	}
	for sample_index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
		owner := chunk.water_owner[sample_index]
		if owner == WATER_OWNER_NONE || owner == WATER_OWNER_SEA {
			continue
		}
		if id, ok := water_owner_body(world, owner); ok && owner != WATER_OWNER_RELEASED {
			if _, listed := slice.binary_search_by(world.water_bodies[id].chunks[:], chunk.coordinate, field_chunk_coordinate_order); listed {
				continue
			}
		}
		chunk.water_owner[sample_index] = WATER_OWNER_NONE
		if !field_sample_bit(&chunk.water_awake, sample_index) {
			// A still byte of no live body: its volume is in no body, so it
			// leaves the world counted, as a place's drop does.
			world.water_dropped += i64(chunk.water[sample_index])
			chunk.water[sample_index] = 0
		}
		changed = true
	}
	if changed {
		note_field_chunk_change(chunk)
	}
}

// After a load restored the set: each body's loaded chunks from the owner
// planes, the pending flood's old chunks from its released samples.
rebuild_water_body_chunks :: proc(world: ^Field_World) {
	for &body in world.water_bodies {
		clear(&body.chunks)
	}
	clear(&world.water_flood.old_chunks)
	for coordinate in sorted_field_chunk_coordinates(world.chunks) {
		chunk := world.chunks[coordinate]
		for owner in chunk.water_owner {
			if owner == WATER_OWNER_NONE || owner == WATER_OWNER_SEA {
				continue
			}
			if owner == WATER_OWNER_RELEASED {
				if world.water_flood.active {
					insert_sorted_field_chunk(&world.water_flood.old_chunks, coordinate)
				}
				continue
			}
			if id, ok := water_owner_body(world, owner); ok {
				insert_sorted_field_chunk(&world.water_bodies[id].chunks, coordinate)
			}
		}
	}
}
