package game

// The surface waves (work item 0294, doc/presentation.md, The water's
// look): a presentation-only height field over the water's surface
// samples, a height offset and a velocity per sample in floats on the
// frame side, never in the simulation, the save or the hash. The water
// step's events of a tick (Field_World.water_events: water arriving from
// a fall or a stream's mouth, a dig, a pump's intake) excite it; routine
// levelling never does, so a settled lake stays still. The wave equation
// runs on the active samples only, damped, with the height and the
// velocity clamped, and a sample whose height and velocity both fall
// under FIELD_WAVE_REST is set to exactly zero and leaves the set, so
// every wave dies out and the mesh is the water's bytes' again. The step
// follows the simulation's ticks (at most MAXIMUM_FIELD_WAVE_STEPS_PER_FRAME
// a frame), never the frame time or the cheat speed. The gather adds the
// heights, rounded to density steps (field_wave_offset), to the water
// grid, so a mesh job carries them baked in; a chunk meshes again only
// when the rounded heights it reads changed, at most
// MAXIMUM_FIELD_WAVE_REMESHES_PER_FRAME a frame after every other mesh
// (Field_Chunk.wave_dirty, schedule_field_jobs).

// Integrations a frame at most, whatever the ticks since the last.
MAXIMUM_FIELD_WAVE_STEPS_PER_FRAME :: 4
// Chunks with waves at most (288 KiB each); an excitation or a spread
// into a further one is dropped.
MAXIMUM_FIELD_WAVE_CHUNKS :: 64
// Under this in height and velocity, in samples, a sample is at rest.
FIELD_WAVE_REST :: 0.003

// data/game.sjson's water_look in the wave equation's units: c²dt²/dx²,
// the damping a step, the height clamp and the velocity clamp (four times
// the height's) in samples, and the velocity a full sample of arriving
// water gives, in samples a tick.
Field_Wave_Tuning :: struct {
	on:                                                     bool,
	speed_squared, damping, clamp, velocity_clamp, kick: f32,
}

make_field_wave_tuning :: proc(config: Water_Look_Config) -> Field_Wave_Tuning {
	clamp := f32(config.wave_clamp_percent) / 100
	return Field_Wave_Tuning {
		on = config.waves,
		speed_squared = f32(config.wave_speed_percent) / 100,
		damping = f32(config.wave_damping_percent) / 100,
		clamp = clamp,
		velocity_clamp = 4 * clamp,
		kick = f32(config.wave_kick_percent) / 100,
	}
}

Field_Wave_Cell :: struct {
	coordinate: Field_Chunk_Coordinate,
	index:      int,
}

// A session's waves (Session.field_waves): the tuning, the chunks'
// heights, the active samples and the tick last stepped.
Field_Waves :: struct {
	tuning:    Field_Wave_Tuning,
	heights:   Field_Wave_Heights,
	active:    [dynamic]Field_Wave_Cell,
	last_tick: u64,
}

destroy_field_waves :: proc(waves: ^Field_Waves) {
	for _, entry in waves.heights {
		free(entry)
	}
	delete(waves.heights)
	delete(waves.active)
	waves^ = {}
}

// A sample on the water's surface: loaded, not ground, holding water, its
// radial up neighbour loaded and not full.
field_wave_surface_sample :: proc(world: ^Field_World, sample: Sample_Coordinate) -> bool {
	chunk, index := field_world_cell(world, sample)
	if chunk == nil || chunk.density[index] > 0 || chunk.water[index] == 0 {
		return false
	}
	axis, sign := field_radial_axis(sample)
	up := sample
	up[axis] += sign
	up_chunk, up_index := field_world_cell(world, up)
	return up_chunk != nil && up_chunk.water[up_index] < FIELD_WATER_FULL
}

// The four face neighbours of a sample across its radial axis.
field_wave_tangential_neighbours :: proc(sample: Sample_Coordinate) -> [4]Sample_Coordinate {
	axis, _ := field_radial_axis(sample)
	neighbours: [4]Sample_Coordinate
	count := 0
	for other in 0 ..< 3 {
		if other == axis {
			continue
		}
		for sign in ([2]i32{-1, 1}) {
			neighbour := sample
			neighbour[other] += sign
			neighbours[count] = neighbour
			count += 1
		}
	}
	return neighbours
}

// The sample's entry and index once it is active (made under the cap,
// appended to the active set); nil when the cap refuses its chunk.
activate_field_wave_cell :: proc(waves: ^Field_Waves, sample: Sample_Coordinate) -> (entry: ^Field_Wave_Chunk, index: int) {
	coordinate := sample_to_field_chunk_coordinate(sample)
	index = sample_to_field_index(sample)
	entry = waves.heights[coordinate] or_else nil
	if entry == nil {
		if len(waves.heights) >= MAXIMUM_FIELD_WAVE_CHUNKS {
			return nil, index
		}
		entry = new(Field_Wave_Chunk)
		waves.heights[coordinate] = entry
	}
	if !field_sample_bit(&entry.active, index) {
		set_field_sample_bit(&entry.active, index)
		entry.active_count += 1
		append(&waves.active, Field_Wave_Cell{coordinate, index})
	}
	return entry, index
}

// The wave height at a sample and whether it is a wave sample.
field_wave_height_at :: proc(waves: Field_Wave_Heights, sample: Sample_Coordinate) -> (height: f32, active: bool) {
	entry := waves[sample_to_field_chunk_coordinate(sample)] or_else nil
	if entry == nil {
		return 0, false
	}
	index := sample_to_field_index(sample)
	if !field_sample_bit(&entry.active, index) {
		return 0, false
	}
	return entry.height[index], true
}

field_wave_cell_sample :: proc(cell: Field_Wave_Cell) -> Sample_Coordinate {
	return field_chunk_origin(cell.coordinate) + Sample_Coordinate(field_index_to_local(cell.index))
}

add_field_wave_velocity :: proc(waves: ^Field_Waves, sample: Sample_Coordinate, velocity: f32) {
	if entry, index := activate_field_wave_cell(waves, sample); entry != nil {
		limit := waves.tuning.velocity_clamp
		entry.velocity[index] = clamp(entry.velocity[index] + velocity, -limit, limit)
	}
}

// The surface sample along the radial through the sample: itself, then up
// to three steps up, then three down; false for none.
field_wave_event_surface :: proc(world: ^Field_World, sample: Sample_Coordinate) -> (surface: Sample_Coordinate, found: bool) {
	if field_wave_surface_sample(world, sample) {
		return sample, true
	}
	for direction in ([2]i32{1, -1}) {
		current := sample
		for _ in 0 ..< 3 {
			axis, sign := field_radial_axis(current)
			current[axis] += direction * sign
			if field_wave_surface_sample(world, current) {
				return current, true
			}
		}
	}
	return {}, false
}

// One event into the waves: an impact pushes the surface sample down and
// its tangential surface neighbours up by a quarter each (zero mean), a
// stream's mouth half as hard, a dig lowers the height at once, a pump's
// intake pulls a steady dimple.
excite_field_waves :: proc(waves: ^Field_Waves, world: ^Field_World, event: Field_Water_Event) {
	surface, found := field_wave_event_surface(world, event.sample)
	if !found {
		return
	}
	tuning := waves.tuning
	kick := min(tuning.velocity_clamp, tuning.kick * f32(event.amount) / FIELD_WATER_FULL)
	switch event.kind {
	case .Impact, .Stream_Mouth:
		if event.kind == .Stream_Mouth {
			kick /= 2
		}
		add_field_wave_velocity(waves, surface, -kick)
		for neighbour in field_wave_tangential_neighbours(surface) {
			if field_wave_surface_sample(world, neighbour) {
				add_field_wave_velocity(waves, neighbour, kick / 4)
			}
		}
	case .Dig:
		if entry, index := activate_field_wave_cell(waves, surface); entry != nil {
			entry.height[index] = clamp(entry.height[index] - min(tuning.clamp, tuning.kick), -tuning.clamp, tuning.clamp)
		}
	case .Pump:
		add_field_wave_velocity(waves, surface, -kick / 8)
	}
}

// One step of the height-field wave equation, order independent: every
// active sample's velocity from its tangential neighbours' heights as the
// step began (a neighbour off the surface reflects; one on the surface
// not yet active joins with height 0 when the sample's height is not
// zero, or reflects when the cap refuses it), then every height from its velocity, damped and clamped; a sample
// at rest is zeroed and leaves the set. The samples that joined this step
// keep their zeros until the next.
step_field_waves :: proc(waves: ^Field_Waves, world: ^Field_World) {
	tuning := waves.tuning
	stepped := len(waves.active)
	for position in 0 ..< stepped {
		cell := waves.active[position]
		entry := waves.heights[cell.coordinate]
		height := entry.height[cell.index]
		pull: f32 = 0
		for neighbour in field_wave_tangential_neighbours(field_wave_cell_sample(cell)) {
			if !field_wave_surface_sample(world, neighbour) {
				continue
			}
			if neighbour_height, active := field_wave_height_at(waves.heights, neighbour); active {
				pull += neighbour_height - height
			} else if height != 0 {
				if joined, _ := activate_field_wave_cell(waves, neighbour); joined != nil {
					pull -= height
				}
			}
		}
		velocity := (entry.velocity[cell.index] + tuning.speed_squared * pull) * tuning.damping
		entry.velocity[cell.index] = clamp(velocity, -tuning.velocity_clamp, tuning.velocity_clamp)
	}
	kept := 0
	for position in 0 ..< len(waves.active) {
		cell := waves.active[position]
		if position < stepped {
			entry := waves.heights[cell.coordinate]
			height := clamp((entry.height[cell.index] + entry.velocity[cell.index]) * tuning.damping, -tuning.clamp, tuning.clamp)
			if abs(height) < FIELD_WAVE_REST && abs(entry.velocity[cell.index]) < FIELD_WAVE_REST {
				entry.height[cell.index], entry.velocity[cell.index] = 0, 0
				clear_field_sample_bit(&entry.active, cell.index)
				entry.active_count -= 1
				// Its last mark drew an offset: the chunks it reaches draw
				// none now (mark_field_wave_changes).
				if entry.baked[cell.index] != 0 {
					entry.baked[cell.index] = 0
					entry.changed_reach |= field_look_reach_bits(field_index_to_local(cell.index))
				}
				continue
			}
			entry.height[cell.index] = height
		}
		waves.active[kept] = cell
		kept += 1
	}
	resize(&waves.active, kept)
}

// The heights the gather adds: nil while the waves are off (a server,
// which meshes nothing, and the planet preview).
field_waves_drawn :: proc(waves: ^Field_Waves) -> Field_Wave_Heights {
	return waves.tuning.on ? waves.heights : nil
}

// Frees every chunk entry and empties the lists.
clear_field_waves :: proc(waves: ^Field_Waves) {
	for _, entry in waves.heights {
		free(entry)
	}
	clear(&waves.heights)
	clear(&waves.active)
}

// The frame's waves (stream_field_session, before the gather): nothing
// when off or when no tick ran since the last call, else the last tick's
// events, then one step per tick since (at most
// MAXIMUM_FIELD_WAVE_STEPS_PER_FRAME), then the marks
// (mark_field_wave_changes); an entry whose chunk left the world is
// dropped. Main thread only, so no job ever reads a freed entry.
advance_field_waves :: proc(waves: ^Field_Waves, world: ^Field_World, tick: u64) {
	if !waves.tuning.on {
		clear_field_waves(waves)
		return
	}
	if tick <= waves.last_tick {
		waves.last_tick = tick
		return
	}
	steps := min(tick - waves.last_tick, MAXIMUM_FIELD_WAVE_STEPS_PER_FRAME)
	waves.last_tick = tick
	for event in world.water_events {
		excite_field_waves(waves, world, event)
	}
	for _ in 0 ..< steps {
		step_field_waves(waves, world)
	}
	mark_field_wave_changes(waves, world)
	drop_field_waves_of_left_chunks(waves, world)
}

// Marks to mesh again (wave_dirty) the chunks whose grids read a wave
// sample whose baked offset changed: each active sample's baked offset
// against the one kept from its last mark, and the samples that came to
// rest since (step_field_waves); only the chunks a changed sample reaches
// are marked (a wave at a border moves the neighbour's grid too,
// field_look_reach_bits), so a ripple deep inside a chunk marks that chunk
// alone, and a sample whose offset rounds alike marks nothing however its
// height moved. An entry whose waves came to rest is freed after its last
// mark. The per sample compare replaces 0294's first hash sum: it finds
// the changed samples, which a sum could not.
mark_field_wave_changes :: proc(waves: ^Field_Waves, world: ^Field_World) {
	for cell in waves.active {
		entry := waves.heights[cell.coordinate]
		baked := i8(clamp(field_wave_baked(entry.height[cell.index]), -MAXIMUM_DENSITY, MAXIMUM_DENSITY))
		if baked != entry.baked[cell.index] {
			entry.baked[cell.index] = baked
			entry.changed_reach |= field_look_reach_bits(field_index_to_local(cell.index))
		}
	}
	rested := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate, entry in waves.heights {
		if entry.changed_reach != 0 {
			mark_field_wave_reach(world, coordinate, entry.changed_reach, waves.last_tick)
			entry.changed_reach = 0
		}
		if entry.active_count == 0 {
			append(&rested, coordinate)
		}
	}
	for coordinate in rested {
		free(waves.heights[coordinate])
		delete_key(&waves.heights, coordinate)
	}
}

// The loaded chunks of the reach bits around a chunk mesh again for the
// waves (no coarse level draws them). A chunk's wave_dirty_tick is the
// tick of its oldest mark not yet meshed, kept while it waits, so the
// waves' remeshes go oldest first (schedule_field_jobs).
mark_field_wave_reach :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate, bits: u32, tick: u64) {
	for slot in 0 ..< 27 {
		if bits & (u32(1) << uint(slot)) == 0 {
			continue
		}
		offset := Field_Chunk_Coordinate{i32(slot % 3) - 1, i32(slot / 3 % 3) - 1, i32(slot / 9) - 1}
		if neighbour := world.chunks[coordinate + offset] or_else nil; neighbour != nil && !neighbour.wave_dirty {
			neighbour.wave_dirty, neighbour.wave_dirty_tick = true, tick
		}
	}
}

// The entries whose chunk is no longer in the world, with their samples.
drop_field_waves_of_left_chunks :: proc(waves: ^Field_Waves, world: ^Field_World) {
	left := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate in waves.heights {
		if coordinate not_in world.chunks {
			append(&left, coordinate)
		}
	}
	if len(left) == 0 {
		return
	}
	for coordinate in left {
		entry := waves.heights[coordinate]
		bits := entry.changed_reach
		for baked, index in entry.baked {
			if baked != 0 {
				bits |= field_look_reach_bits(field_index_to_local(index))
			}
		}
		mark_field_wave_reach(world, coordinate, bits, waves.last_tick)
		free(entry)
		delete_key(&waves.heights, coordinate)
	}
	kept := 0
	for cell in waves.active {
		if cell.coordinate in waves.heights {
			waves.active[kept] = cell
			kept += 1
		}
	}
	resize(&waves.active, kept)
}
