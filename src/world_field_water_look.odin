package game

import "core:math"
import "core:slice"

// The water's look (work item 0294, doc/presentation.md, The water's
// look): what the mesher's water grid holds. A sample a body or the sea
// owns as still water draws its owner's level as a plane, a signed
// distance in the grid's spacing at every level of detail (field_look_base,
// field_coarse_water_base); the front (awake water no body owns yet) draws
// its slab level as before (field_water_density). Over that, at full
// resolution, every wet sample stamps a sheet onto itself and its 26
// neighbours reached through open space (stamp_field_water_sheet): the
// terrain's density plus the water's thickness, its true share at rest, at
// least FIELD_WATER_SHEET_FLOOR_STEPS while it moves, the full column
// while it falls, clipped at the level (or the column) and against a thin
// wall, so thin or fast water hugs the ground, a resting film draws as
// thin as it is and no water shows through a one-sample wall. Moving is
// derived from the simulation: a fill changed within the last
// FIELD_WATER_MOVED_TICKS awake ticks (Field_Chunk.water_moved). The
// main thread copies the arrays the look reads, the surface waves' baked
// offsets (Field_Wave_Heights, render_field_waves.odin) and the levels of
// the owners they name into the mesh job (gather_field_look_samples,
// gather_coarse_field_grid, 0344), and the worker writes the look from
// those copies, so it reads no Field_World and no table. Nothing here is
// saved or hashed.

// The ticks a changed sample counts as moving (set_field_water).
FIELD_WATER_MOVED_TICKS :: 6
// A sample falls when the water under it lies at least this far below
// its bottom, in fill units (0.2 sample): a settled staircase on the
// sphere is no fall.
FIELD_WATER_FALL_GAP :: 51
// The moving sheet's least thickness in density steps (0.2 sample).
FIELD_WATER_SHEET_FLOOR_STEPS :: 26
// A falling column's clip stands this far over its cell's top, in
// density steps (half a sample), so a column is drawn whole.
FIELD_WATER_SHEET_FALL_LIFT_STEPS :: 64
// A body's chunks mesh again when its level moved this far, in fill
// units (a thirty-second of a sample), since they last did.
FIELD_WATER_LOOK_LEVEL_STEP :: 8

Field_Water_Sheet_Mode :: enum u8 {
	Resting,
	Moving,
	Falling,
}

// What the surface waves take from a tick of the water step
// (Field_World.water_events): water arriving from above onto standing
// water, arriving from the side (a stream's mouth), a dig beside or into
// water, a pump's intake. amount is in fill units.
Field_Water_Event_Kind :: enum u8 {
	Impact,
	Stream_Mouth,
	Dig,
	Pump,
}

Field_Water_Event :: struct {
	kind:   Field_Water_Event_Kind,
	sample: Sample_Coordinate,
	amount: i32,
}

// The events a tick keeps at most; the rest are dropped.
MAXIMUM_FIELD_WATER_EVENTS :: 1024

// One chunk's surface waves: a height offset and a velocity per sample
// in samples (frame side floats, never in the simulation), the samples
// the wave equation runs on and their count. The presentation owns them
// (Field_Waves); the gather copies the baked offsets
// (gather_field_look_samples), which the worker adds (field_look_wave_offset).
// baked holds each sample's baked offset as the chunks it reaches were
// last marked (zero off the active set), changed_reach the reach bits
// (field_look_reach_bits) of the samples whose baked offset changed since
// (mark_field_wave_changes).
Field_Wave_Chunk :: struct {
	height, velocity: [FIELD_CHUNK_SAMPLE_COUNT]f32,
	baked:            [FIELD_CHUNK_SAMPLE_COUNT]i8,
	active:           Field_Sample_Bits,
	active_count:     int,
	changed_reach:    u32,
}

// nil or empty: no waves.
Field_Wave_Heights :: map[Field_Chunk_Coordinate]^Field_Wave_Chunk

push_field_water_event :: proc(world: ^Field_World, kind: Field_Water_Event_Kind, sample: Sample_Coordinate, amount: i32) {
	if len(world.water_events) < MAXIMUM_FIELD_WATER_EVENTS {
		append(&world.water_events, Field_Water_Event{kind = kind, sample = sample, amount = amount})
	}
}

// The chunks whose full resolution grid reads a sample at a local
// coordinate (its water's look reads FIELD_LOOK_REACH samples beyond the
// node, write_field_water_look), as bits of the 27 offsets, bit
// (x + 1) + 3 * ((y + 1) + 3 * (z + 1)): the sample's own chunk, and a
// neighbour on every axis where the sample lies within FIELD_LOOK_REACH
// of that border, with the edges and corners between.
field_look_reach_bits :: proc(local: [3]i32) -> u32 {
	low, high: [3]i32
	for axis in 0 ..< 3 {
		low[axis] = local[axis] < FIELD_LOOK_REACH ? -1 : 0
		high[axis] = local[axis] >= FIELD_CHUNK_SIZE - FIELD_LOOK_REACH ? 1 : 0
	}
	bits: u32
	for z in low.z ..= high.z {
		for y in low.y ..= high.y {
			for x in low.x ..= high.x {
				bits |= u32(1) << uint((x + 1) + 3 * ((y + 1) + 3 * (z + 1)))
			}
		}
	}
	return bits
}

// The chunk's own bit (offset 0, 0, 0).
FIELD_LOOK_REACH_SELF :: u32(1) << 13

// Marks the loaded chunks of the reach bits around a chunk to mesh again,
// and the chunk edited for the coarse levels.
mark_field_look_reach :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, bits: u32) {
	for slot in 0 ..< 27 {
		if bits & (u32(1) << uint(slot)) == 0 {
			continue
		}
		offset := Field_Chunk_Coordinate{i32(slot % 3) - 1, i32(slot / 3 % 3) - 1, i32(slot / 9) - 1}
		if neighbour := world.chunks[coordinate + offset] or_else nil; neighbour != nil {
			neighbour.dirty = true
		}
	}
	world.edited_chunks[coordinate] = {}
}

// A change to a sample's water, its owner or its terrain: every chunk
// whose full resolution water reads it meshes again.
mark_field_look_dirty :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, sample: Sample_Coordinate) {
	local := [3]i32{sample.x %% FIELD_CHUNK_SIZE, sample.y %% FIELD_CHUNK_SIZE, sample.z %% FIELD_CHUNK_SIZE}
	mark_field_look_reach(world, coordinate, field_look_reach_bits(local))
}

// The neighbours' reach bits of the samples of a chunk an owner holds:
// only the samples within FIELD_LOOK_REACH of a border reach a neighbour,
// so a row inside on y and z is read at its two ends only. The chunk's own
// bit is set only when such a sample is found; the callers add it.
field_look_owned_reach :: proc(chunk: ^Field_Chunk, owner: Water_Owner) -> u32 {
	bits: u32
	inside :: proc(local: i32) -> bool {
		return local >= FIELD_LOOK_REACH && local < FIELD_CHUNK_SIZE - FIELD_LOOK_REACH
	}
	for z in i32(0) ..< FIELD_CHUNK_SIZE {
		for y in i32(0) ..< FIELD_CHUNK_SIZE {
			row := FIELD_CHUNK_SIZE * (int(y) + FIELD_CHUNK_SIZE * int(z))
			ends := inside(y) && inside(z)
			for x in i32(0) ..< FIELD_CHUNK_SIZE {
				if ends && inside(x) {
					continue
				}
				if chunk.water_owner[row + int(x)] == owner {
					bits |= field_look_reach_bits({x, y, z})
				}
			}
		}
	}
	return bits
}

// One awake tick of the moving stamp; the chunks that mesh the sample
// draw it at rest again once it reaches zero (at the step's end inside the
// step, note_field_water_change).
expire_field_water_moved :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate) {
	if chunk.water_moved[index] == 0 {
		return
	}
	if chunk.water_moved[index] == 1 {
		note_field_water_change(world, chunk, index, sample, true)
	}
	chunk.water_moved[index] -= 1
}

// A sample's owner changed, or its water turned a body's still water: the
// chunks that mesh it draw the other plane.
note_water_owner_change :: proc(world: ^Field_World, chunk: ^Field_Chunk, sample: Sample_Coordinate) {
	mark_field_look_dirty(world, chunk.coordinate, sample)
}

// Whether a loaded face neighbour of the sample holds water.
field_sample_has_wet_face_neighbour :: proc(world: ^Field_World, chunk: ^Field_Chunk, sample: Sample_Coordinate) -> bool {
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		if neighbour, index := field_water_cell(world, chunk, sample, offset); neighbour != nil && neighbour.density[index] <= 0 && neighbour.water[index] > 0 {
			return true
		}
	}
	return false
}

// The axis along which the sample lies farthest from the centre (the
// lowest on a tie) and the sign of its coordinate there: the face
// neighbour along it away from the centre is the sample's radial up.
field_radial_axis :: proc(sample: Sample_Coordinate) -> (axis: int, sign: i32) {
	for candidate in 1 ..< 3 {
		if abs(sample[candidate]) > abs(sample[axis]) {
			axis = candidate
		}
	}
	return axis, sample[axis] < 0 ? -1 : 1
}

// A level over a sample's middle as the mesher's value in a grid of step
// samples: a signed distance, clamped.
field_water_plane_value :: proc(level, middle: i64, step: i32) -> i8 {
	return i8(clamp(floor_divide_i64((level - middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL * i64(step)), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
}

// One owner's level in fill units from the centre and whether it names
// the sea or a live body.
Field_Look_Owner :: struct {
	owner: Water_Owner,
	owned: bool,
	level: i64,
}

// Every owner a job's copies name, each once with its level as the gather
// found it (note_field_look_owner), and the last one looked up on the
// worker (field_look_owner_level). The zero cached entry names no owner,
// which the lookup answers before the cache.
Field_Look_Owners :: struct {
	list:   [dynamic]Field_Look_Owner,
	cached: Field_Look_Owner,
}

// The level of the still water an owner names: the sea's, or a live
// body's (water_owner_body, which reads the pending flood for the
// released samples); false for none and an owner with no live body. Main
// thread.
field_water_owner_level :: proc(world: ^Field_World, owner: Water_Owner) -> (level: i64, owned: bool) {
	if owner == WATER_OWNER_SEA {
		return world.water_planet.sea_level, true
	}
	id, ok := water_owner_body(world, owner)
	if !ok {
		return 0, false
	}
	return world.water_bodies[id].level, true
}

// Lists an owner with its level unless it is none or listed already. Main
// thread.
note_field_look_owner :: proc(owners: ^Field_Look_Owners, world: ^Field_World, owner: Water_Owner) {
	if owner == WATER_OWNER_NONE {
		return
	}
	for entry in owners.list {
		if entry.owner == owner {
			return
		}
	}
	level, owned := field_water_owner_level(world, owner)
	append(&owners.list, Field_Look_Owner{owner = owner, owned = owned, level = level})
}

// The level of an owner's still water from the list, the last one kept,
// since a grid holds few owners; an owner the list lacks reads as not
// owned. Worker.
field_look_owner_level :: proc(owners: ^Field_Look_Owners, owner: Water_Owner) -> (level: i64, owned: bool) {
	if owner == WATER_OWNER_NONE {
		return 0, false
	}
	if owner != owners.cached.owner {
		owners.cached = {owner = owner}
		for entry in owners.list {
			if entry.owner == owner {
				owners.cached = entry
				break
			}
		}
	}
	return owners.cached.level, owners.cached.owned
}

// How a wet sample's sheet is drawn, from simulation facts only: at rest
// when it has not moved for FIELD_WATER_MOVED_TICKS; falling when the
// loaded water under it lies a fall gap below its bottom; at rest when it
// stands on water or touches no ground (the top of a body, free water);
// else moving. Only a sample no owner holds as still water is asked, so
// a body's sample never reaches here.
field_look_sheet_mode :: proc(samples: ^Field_Look_Samples, look: int, sample: Sample_Coordinate, span: Field_Water_Span) -> Field_Water_Sheet_Mode {
	if samples.moved[look] == 0 {
		return .Resting
	}
	axis, sign := field_radial_axis(sample)
	offset: [3]i32
	offset[axis] = -sign
	down := look + field_look_step(offset)
	if samples.loaded[down] && samples.density[down] <= 0 {
		down_fill := i32(samples.water[down])
		if down_fill < FIELD_WATER_FULL && field_water_level(field_water_span(sample + Sample_Coordinate(offset)), down_fill) + FIELD_WATER_FALL_GAP <= field_water_bottom(span) {
			return .Falling
		}
		if down_fill > 0 {
			return .Resting
		}
	}
	// A sample not loaded reads -MAXIMUM_DENSITY, no ground.
	for neighbour in FIELD_WATER_NEIGHBOUR_OFFSETS {
		if samples.density[look + field_look_step(neighbour)] > 0 {
			return .Moving
		}
	}
	return .Resting
}

// The full resolution water is made from the samples from three beyond
// the grid to three beyond its far side (FIELD_LOOK_SIZE a side), copied
// once from the node's chunk and its 26 neighbours into flat arrays; a
// missing chunk reads as air holding nothing (loaded false). A water or
// terrain change within FIELD_LOOK_REACH of a chunk's border therefore
// changes the neighbour's grid too (mark_field_look_dirty).
FIELD_LOOK_REACH :: 3
FIELD_LOOK_SIZE :: FIELD_GRID_CELLS + 2 * FIELD_LOOK_REACH
FIELD_LOOK_SAMPLE_COUNT :: FIELD_LOOK_SIZE * FIELD_LOOK_SIZE * FIELD_LOOK_SIZE

// A finest mesh job's copy of the look's reach (gather_field_look_samples,
// main thread), finished and read by the worker. density, water,
// still_owner and moved (Field_Chunk.water_moved) are the chunks' arrays
// as copied, a missing chunk's samples -MAXIMUM_DENSITY, nothing and
// unloaded. wave holds the waves' baked offsets of every sample whose
// chunk has waves, loaded or not, zero elsewhere, and wavy is set when any
// of the 27 chunks has. awake_front holds a bit a row (bit x of row
// y + FIELD_LOOK_SIZE * z) for awake water that is no spring, the front in
// a body's air. finish_field_look_samples then clears still_owner to
// WATER_OWNER_NONE for the front and an owner with no live body, so it
// names the owner of still water a body or the sea owns, and fills
// interior, a bit a row like awake_front, for still water whose 26
// neighbours are all its owner's still water: it stamps nothing, so the
// sheet pass skips it without visiting them.
Field_Look_Samples :: struct {
	loaded:      [FIELD_LOOK_SAMPLE_COUNT]bool,
	density:     [FIELD_LOOK_SAMPLE_COUNT]i8,
	water:       [FIELD_LOOK_SAMPLE_COUNT]u8,
	still_owner: [FIELD_LOOK_SAMPLE_COUNT]Water_Owner,
	moved:       [FIELD_LOOK_SAMPLE_COUNT]u8,
	wave:        [FIELD_LOOK_SAMPLE_COUNT]i8,
	awake_front: [FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64,
	interior:    [FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64,
	wavy:        bool,
	owners:      Field_Look_Owners,
}

// A coarse mesh job's water of the loaded samples it read
// (gather_coarse_field_grid, main thread), by grid index: the fill, and
// the owner unless the sample is front water (field_water_is_front).
// generate_field_grid writes the base from it on the worker
// (field_coarse_water_base).
Field_Coarse_Water :: struct {
	fill:        [FIELD_GRID_SAMPLE_COUNT]u8,
	still_owner: [FIELD_GRID_SAMPLE_COUNT]Water_Owner,
	owners:      Field_Look_Owners,
}

// Local -FIELD_LOOK_REACH to FIELD_GRID_CELLS - 1 + FIELD_LOOK_REACH on
// every axis.
field_look_index :: proc(local: [3]i32) -> int {
	return int(local.x + FIELD_LOOK_REACH) + FIELD_LOOK_SIZE * (int(local.y + FIELD_LOOK_REACH) + FIELD_LOOK_SIZE * int(local.z + FIELD_LOOK_REACH))
}

// The look's copy of a node's reach, for the worker. The arrays are filled
// a run at a time: each row crosses three chunks (FIELD_LOOK_REACH samples
// of the one before, the node's, FIELD_LOOK_REACH of the one after), whose
// arrays and baked wave offsets are copied whole; then every owner the
// copy names is listed with its level (note_field_look_owner). Main
// thread; nothing is derived per sample here.
gather_field_look_samples :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, waves: Field_Wave_Heights = nil, allocator := context.allocator) -> ^Field_Look_Samples {
	samples := new(Field_Look_Samples, allocator)
	samples.owners.list = make([dynamic]Field_Look_Owner, 0, 8, allocator)
	chunks: [27]^Field_Chunk
	wave_chunks: [27]^Field_Wave_Chunk
	for slot in 0 ..< 27 {
		neighbour := coordinate + Field_Chunk_Coordinate{i32(slot % 3) - 1, i32(slot / 3 % 3) - 1, i32(slot / 9) - 1}
		chunks[slot] = world.chunks[neighbour] or_else nil
		if len(waves) > 0 {
			wave_chunks[slot] = waves[neighbour] or_else nil
			samples.wavy ||= wave_chunks[slot] != nil
		}
	}
	// The chunk slot and the coordinate inside it of each local value.
	slots, inners: [FIELD_LOOK_SIZE]int
	for position in 0 ..< FIELD_LOOK_SIZE {
		local := i32(position) - FIELD_LOOK_REACH
		slots[position] = int(floor_divide(local, FIELD_CHUNK_SIZE) + 1)
		inners[position] = int(local %% FIELD_CHUNK_SIZE)
	}
	RUNS :: [3][2]int{{0, FIELD_LOOK_REACH}, {FIELD_LOOK_REACH, FIELD_LOOK_REACH + FIELD_CHUNK_SIZE}, {FIELD_LOOK_REACH + FIELD_CHUNK_SIZE, FIELD_LOOK_SIZE}}
	for z in 0 ..< FIELD_LOOK_SIZE {
		for y in 0 ..< FIELD_LOOK_SIZE {
			row := y + FIELD_LOOK_SIZE * z
			row_slot := 3 * (slots[y] + 3 * slots[z])
			row_index := FIELD_CHUNK_SIZE * (inners[y] + FIELD_CHUNK_SIZE * inners[z])
			for run, slot in RUNS {
				look := run[0] + FIELD_LOOK_SIZE * row
				count := run[1] - run[0]
				first := inners[run[0]] + row_index
				if entry := wave_chunks[slot + row_slot]; entry != nil {
					copy(samples.wave[look:look + count], entry.baked[first:first + count])
				}
				chunk := chunks[slot + row_slot]
				if chunk == nil {
					slice.fill(samples.density[look:look + count], -MAXIMUM_DENSITY)
					continue
				}
				copy(samples.density[look:look + count], chunk.density[first:first + count])
				copy(samples.water[look:look + count], chunk.water[first:first + count])
				copy(samples.still_owner[look:look + count], chunk.water_owner[first:first + count])
				copy(samples.moved[look:look + count], chunk.water_moved[first:first + count])
				slice.fill(samples.loaded[look:look + count], true)
				// A chunk row is 32 samples, half of one bit word.
				word := first >> 6
				front := (chunk.water_awake[word] & ~chunk.water_source[word]) >> uint(first & 63)
				samples.awake_front[row] |= (front & (u64(1) << uint(count) - 1)) << uint(run[0])
			}
		}
	}
	last := WATER_OWNER_NONE
	for owner in samples.still_owner {
		if owner != last {
			note_field_look_owner(&samples.owners, world, owner)
			last = owner
		}
	}
	return samples
}

// The worker's part of the copy: a sample of the front (its awake_front
// bit) or of an owner with no live body draws no owner's plane, so its
// still_owner becomes WATER_OWNER_NONE; the still water of each row's
// first owner is collected, a bit a sample, for the interior
// (mark_field_look_interior). Idempotent.
finish_field_look_samples :: proc(samples: ^Field_Look_Samples) {
	still_rows := new([FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64, context.temp_allocator)
	row_owners := new([FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]Water_Owner, context.temp_allocator)
	for row in 0 ..< FIELD_LOOK_SIZE * FIELD_LOOK_SIZE {
		front := samples.awake_front[row]
		look := FIELD_LOOK_SIZE * row
		for x in 0 ..< FIELD_LOOK_SIZE {
			owner := samples.still_owner[look + x]
			if owner == WATER_OWNER_NONE {
				continue
			}
			if (front >> uint(x)) & 1 != 0 {
				samples.still_owner[look + x] = WATER_OWNER_NONE
				continue
			}
			if _, owned := field_look_owner_level(&samples.owners, owner); !owned {
				samples.still_owner[look + x] = WATER_OWNER_NONE
				continue
			}
			if row_owners[row] == WATER_OWNER_NONE {
				row_owners[row] = owner
			}
			if owner == row_owners[row] && samples.density[look + x] <= 0 {
				still_rows[row] |= u64(1) << uint(x)
			}
		}
	}
	mark_field_look_interior(samples, still_rows, row_owners)
}

// The full resolution base of a sample of the arrays: ground and a
// missing sample -MAXIMUM_DENSITY, still water its owner's plane (plane
// true), the front its slab; and a dry sample no one owns beside still
// water takes the lower of its slab and the owner's plane, so the air just
// above the sea's surface (which the sea does not own) is a signed
// distance too and every crossing edge has both ends on the plane.
field_look_base :: proc(samples: ^Field_Look_Samples, look: int, span: Field_Water_Span) -> (value: i8, plane: bool) {
	if !samples.loaded[look] || samples.density[look] > 0 {
		return -MAXIMUM_DENSITY, false
	}
	if level, owned := field_look_owner_level(&samples.owners, samples.still_owner[look]); owned {
		return field_water_plane_value(level, span.middle, 1), true
	}
	fill := samples.water[look]
	value = i8(clamp(floor_divide_i64((field_water_level(span, i32(fill)) - span.middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
	if fill > 0 {
		return value, false
	}
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		beside := look + field_look_step(offset)
		if samples.density[beside] > 0 {
			continue
		}
		if level, owned := field_look_owner_level(&samples.owners, samples.still_owner[beside]); owned {
			return min(value, field_water_plane_value(level, span.middle, 1)), false
		}
	}
	return value, false
}

// A separable test on the row bits: a sample is interior along x when it
// and its two x neighbours are still water of the row's owner, along x
// and y when that holds for the rows beside it in y of the same owner, and
// so on; a row of another owner or on the arrays' faces breaks it. A
// sample of a row's second owner is never interior, which only costs the
// sheet pass a visit.
mark_field_look_interior :: proc(samples: ^Field_Look_Samples, still_rows: ^[FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64, row_owners: ^[FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]Water_Owner) {
	along_x := new([FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64, context.temp_allocator)
	for bits, row in still_rows {
		along_x[row] = bits & (bits << 1) & (bits >> 1)
	}
	along_y := new([FIELD_LOOK_SIZE * FIELD_LOOK_SIZE]u64, context.temp_allocator)
	for z in 0 ..< FIELD_LOOK_SIZE {
		for y in 1 ..< FIELD_LOOK_SIZE - 1 {
			row := y + FIELD_LOOK_SIZE * z
			owner := row_owners[row]
			if row_owners[row - 1] == owner && row_owners[row + 1] == owner {
				along_y[row] = along_x[row - 1] & along_x[row] & along_x[row + 1]
			}
		}
	}
	for z in 1 ..< FIELD_LOOK_SIZE - 1 {
		for y in 0 ..< FIELD_LOOK_SIZE {
			row := y + FIELD_LOOK_SIZE * z
			owner := row_owners[row]
			if row_owners[row - FIELD_LOOK_SIZE] == owner && row_owners[row + FIELD_LOOK_SIZE] == owner {
				samples.interior[row] = along_y[row - FIELD_LOOK_SIZE] & along_y[row] & along_y[row + FIELD_LOOK_SIZE]
			}
		}
	}
}

// The offset of a local step in the flat arrays.
field_look_step :: proc(offset: [3]i32) -> int {
	return int(offset.x) + FIELD_LOOK_SIZE * (int(offset.y) + FIELD_LOOK_SIZE * int(offset.z))
}

// Whether an air target at offset (each component -1 to 1) is reached
// from the wet sample at look index wet through face-connected open space:
// a face neighbour always, an edge neighbour through either of its two
// intermediates, a corner through one of its six two-step paths.
field_look_reaches :: proc(samples: ^Field_Look_Samples, wet: int, offset: [3]i32) -> bool {
	steps: [3]int
	count := 0
	for axis in 0 ..< 3 {
		if offset[axis] != 0 {
			step: [3]i32
			step[axis] = offset[axis]
			steps[count] = field_look_step(step)
			count += 1
		}
	}
	open :: proc(samples: ^Field_Look_Samples, look: int) -> bool {
		return samples.density[look] <= 0
	}
	switch count {
	case 2:
		return open(samples, wet + steps[0]) || open(samples, wet + steps[1])
	case 3:
		orders := [6][2]int{{0, 1}, {0, 2}, {1, 0}, {1, 2}, {2, 0}, {2, 1}}
		for order in orders {
			first := wet + steps[order[0]]
			if open(samples, first) && open(samples, first + steps[order[1]]) {
				return true
			}
		}
		return false
	}
	return true
}

field_look_in_grid :: proc(local: [3]i32) -> bool {
	for axis in 0 ..< 3 {
		if local[axis] < -1 || local[axis] > FIELD_GRID_CELLS {
			return false
		}
	}
	return true
}

// The water of a full resolution grid (the worker, after the terrain the
// gather copied, run_field_job): the copy finished
// (finish_field_look_samples), every sample's base (field_look_base) with
// the surface waves' offset added where it is not ground
// (field_look_wave_shifted_value), then the sheet
// (stamp_field_water_sheet). The spans of the grid's samples are taken
// once and shared by both. Its temporaries go on the temp allocator.
write_field_water_look :: proc(grid: ^Field_Grid, samples: ^Field_Look_Samples) {
	finish_field_look_samples(samples)
	spans := new([FIELD_GRID_SAMPLE_COUNT]Field_Water_Span, context.temp_allocator)
	index := 0
	for z in i32(-1) ..= FIELD_GRID_CELLS {
		for y in i32(-1) ..= FIELD_GRID_CELLS {
			look := field_look_index({-1, y, z})
			for x in i32(-1) ..= FIELD_GRID_CELLS {
				sample := grid.origin + Sample_Coordinate([3]i32{x, y, z})
				span := field_water_span(sample)
				spans[index] = span
				value, plane := field_look_base(samples, look, span)
				if samples.wavy && samples.loaded[look] && samples.density[look] <= 0 {
					value = i8(field_look_wave_shifted_value(samples, value, look, sample))
				}
				grid.water[index], grid.water_exact[index] = value, plane
				index += 1
				look += 1
			}
		}
	}
	stamp_field_water_sheet(grid, samples, spans)
}

// The wall guard of a ground target: over its face neighbours that are
// not ground, lie outside the wet sample's 3×3×3 and hold no water of
// their own (base value at or below zero), the value that keeps the
// water's crossing on the edge to them at 60 percent of the way to the
// terrain's crossing, inside the wall. The base values beyond the grid
// are taken from the arrays on the fly.
field_water_wall_limit :: proc(samples: ^Field_Look_Samples, base: ^[FIELD_GRID_SAMPLE_COUNT]i8, origin: Sample_Coordinate, target, wet: [3]i32, target_density: i32) -> i32 {
	limit := i32(MAXIMUM_DENSITY)
	for offset in FIELD_WATER_NEIGHBOUR_OFFSETS {
		beside := target + offset
		if abs(beside.x - wet.x) <= 1 && abs(beside.y - wet.y) <= 1 && abs(beside.z - wet.z) <= 1 {
			continue
		}
		look := field_look_index(beside)
		beside_density := i32(samples.density[look])
		if beside_density > 0 {
			continue
		}
		value: i32
		if field_look_in_grid(beside) {
			value = i32(base[field_grid_index(beside)])
		} else {
			sample := origin + Sample_Coordinate(beside)
			fine, _ := field_look_base(samples, look, field_water_span(sample))
			value = samples.loaded[look] ? field_look_wave_shifted_value(samples, fine, look, sample) : i32(fine)
		}
		if value > 0 {
			continue
		}
		limit = min(limit, (-value) * 3 * target_density / (2 * target_density - 5 * beside_density))
	}
	return limit
}

// The sheet pass: every wet sample from two beyond the grid to two beyond
// its far side stamps its sheet onto itself and its 26 neighbours inside
// the grid, each value the maximum of what it held and the stamps. The
// guard reads the base values as they stood before the first stamp, so
// the order never matters, and two neighbouring nodes compute their
// shared samples from the same values.
stamp_field_water_sheet :: proc(grid: ^Field_Grid, samples: ^Field_Look_Samples, spans: ^[FIELD_GRID_SAMPLE_COUNT]Field_Water_Span) {
	base := new([FIELD_GRID_SAMPLE_COUNT]i8, context.temp_allocator)
	base^ = grid.water
	for z in i32(-2) ..= FIELD_GRID_CELLS + 1 {
		for y in i32(-2) ..= FIELD_GRID_CELLS + 1 {
			look := field_look_index({-2, y, z})
			interior := samples.interior[int(y + FIELD_LOOK_REACH) + FIELD_LOOK_SIZE * int(z + FIELD_LOOK_REACH)] >> uint(FIELD_LOOK_REACH - 2)
			for x in i32(-2) ..= FIELD_GRID_CELLS + 1 {
				if samples.density[look] <= 0 && samples.water[look] > 0 && interior & 1 == 0 {
					stamp_field_water_sheet_sample(grid, samples, spans, base, {x, y, z}, look)
				}
				look += 1
				interior >>= 1
			}
		}
	}
}

// One wet sample's sheet: the thickness (its fill's share, at least the
// floor while it moves or falls) over each target's terrain, clipped at
// the sample's level (plus the floor while it moves) or its column's
// top (falling), the wall guard on a ground target. Still water a body
// owns skips the samples its body owns, whose plane is its own already.
stamp_field_water_sheet_sample :: proc(grid: ^Field_Grid, samples: ^Field_Look_Samples, spans: ^[FIELD_GRID_SAMPLE_COUNT]Field_Water_Span, base: ^[FIELD_GRID_SAMPLE_COUNT]i8, wet: [3]i32, look: int) {
	fill := i32(samples.water[look])
	owner := samples.still_owner[look]
	level, owned := field_look_owner_level(&samples.owners, owner)
	mode := Field_Water_Sheet_Mode.Resting
	column_top: i64
	if !owned {
		sample := grid.origin + Sample_Coordinate(wet)
		span := field_water_span(sample)
		level = field_water_level(span, fill)
		mode = field_look_sheet_mode(samples, look, sample, span)
		column_top = field_water_bottom(span) + span.height
	}
	thickness := fill * DENSITY_STEPS_PER_SAMPLE / FIELD_WATER_FULL
	if mode != .Resting {
		thickness = max(thickness, FIELD_WATER_SHEET_FLOOR_STEPS)
	}
	wet_density := i32(samples.density[look])
	for dz in i32(-1) ..= 1 {
		for dy in i32(-1) ..= 1 {
			for dx in i32(-1) ..= 1 {
				offset := [3]i32{dx, dy, dz}
				target := wet + offset
				if !field_look_in_grid(target) {
					continue
				}
				target_look := look + field_look_step(offset)
				target_density := i32(samples.density[target_look])
				ground := target_density > 0
				if !ground {
					if owned && samples.still_owner[target_look] == owner {
						continue
					}
					if !field_look_reaches(samples, look, offset) {
						continue
					}
				}
				target_grid_index := field_grid_index(target)
				middle := spans[target_grid_index].middle
				clip: i64
				switch mode {
				case .Resting:
					clip = floor_divide_i64((level - middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL)
				case .Moving:
					clip = floor_divide_i64((level - middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL) + FIELD_WATER_SHEET_FLOOR_STEPS
				case .Falling:
					clip = floor_divide_i64((column_top - middle) * DENSITY_STEPS_PER_SAMPLE, FIELD_WATER_FULL) + FIELD_WATER_SHEET_FLOOR_STEPS + FIELD_WATER_SHEET_FALL_LIFT_STEPS
				}
				stamp := i32(clamp(min(i64(target_density + thickness), clip), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
				if ground {
					guarded := field_water_wall_limit(samples, base, grid.origin, target, wet, target_density)
					if guarded < stamp {
						if mode != .Resting && field_look_in_grid(wet) {
							// The crossing on the edge from the wet sample to the
							// target stays where the unguarded sheet put it.
							difference := target_density - wet_density
							numerator := -DENSITY_STEPS_PER_SAMPLE * wet_density - thickness * difference
							denominator := DENSITY_STEPS_PER_SAMPLE * difference - numerator
							if numerator > 0 {
								raised := i8(clamp(-guarded * numerator / denominator, -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
								wet_index := field_grid_index(wet)
								grid.water[wet_index] = max(grid.water[wet_index], raised)
							}
						}
						stamp = guarded
					}
				}
				grid.water[target_grid_index] = max(grid.water[target_grid_index], i8(stamp))
			}
		}
	}
}

// A wave height in density steps, as Field_Wave_Chunk.baked keeps it
// (mark_field_wave_changes).
field_wave_baked :: proc(height: f32) -> i32 {
	return i32(math.round(height * DENSITY_STEPS_PER_SAMPLE))
}

// The wave offset the worker adds to a non-ground sample, in density
// steps: the sample's own baked offset when it is not zero, else its
// radial up neighbour's (the water under a surface sample), else its
// radial down neighbour's (the air over it), so the band shifts together;
// 0 when no chunk of the node has waves. It reads the copied baked
// offsets only, so a chunk whose baked offsets did not change draws the
// same (advance_field_waves). The callers' samples lie from two beyond the
// grid to two beyond its far side, so both neighbours are in the copy.
field_look_wave_offset :: proc(samples: ^Field_Look_Samples, look: int, sample: Sample_Coordinate) -> i32 {
	if !samples.wavy {
		return 0
	}
	if own := samples.wave[look]; own != 0 {
		return i32(own)
	}
	axis, sign := field_radial_axis(sample)
	step: [3]i32
	step[axis] = sign
	up := look + field_look_step(step)
	if baked := samples.wave[up]; baked != 0 {
		return i32(baked)
	}
	return i32(samples.wave[look - field_look_step(step)])
}

// A non-ground water value with the wave offset added, in density steps.
field_look_wave_shifted_value :: proc(samples: ^Field_Look_Samples, value: i8, look: int, sample: Sample_Coordinate) -> i32 {
	return clamp(i32(value) + field_look_wave_offset(samples, look, sample), -MAXIMUM_DENSITY, MAXIMUM_DENSITY)
}

// A coarse grid's water base of a loaded sample (gather_coarse_field_grid
// copied its fill and still owner): ground -MAXIMUM_DENSITY, still water
// a body or the sea owns (its dry air above the level too) the owner's
// plane in the grid's spacing (plane true), the front the slab level
// (field_water_density, which generate_field_grid then scales,
// coarse_field_water_density). density is the loaded sample's own.
// Worker.
field_coarse_water_base :: proc(water: ^Field_Coarse_Water, index: int, density: i8, sample: Sample_Coordinate, step: i32) -> (value: i8, plane: bool) {
	if density > 0 {
		return -MAXIMUM_DENSITY, false
	}
	if level, owned := field_look_owner_level(&water.owners, water.still_owner[index]); owned {
		return field_water_plane_value(level, field_water_span(sample).middle, step), true
	}
	return field_water_density(density, water.fill[index], sample), false
}

// A job's copies freed (nil safe) with the context's allocator, which on a
// worker is the one the main thread made them in (field_worker).
destroy_field_look_samples :: proc(samples: ^Field_Look_Samples) {
	if samples == nil {
		return
	}
	delete(samples.owners.list)
	free(samples)
}

destroy_field_coarse_water :: proc(water: ^Field_Coarse_Water) {
	if water == nil {
		return
	}
	delete(water.owners.list)
	free(water)
}
