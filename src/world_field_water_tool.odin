package game

import "core:slice"

// Writes of the water tech demo's tools and pumps into the water field
// (work item 0295, doc/architecture.md, The water field: tools and
// pumps), under both models. A bucket pours into the room of the samples
// round the aimed one, nearest first, and drains what they hold; a pump
// takes from the water column over its intake and adds into the room of
// the column over its outlet. Each write goes by the sample's owner: front
// water (every sample under teleport, an unowned one or front water in a
// body's air under bodies) through set_field_water, which wakes the
// samples round it; a body's still water or dry air to the body's volume,
// its level and bytes following; the sea is infinite both ways (a take
// counts and changes nothing, an addition goes to water_to_sea). Integer
// only and in one order, so every machine writes alike.

// The samples a pump's column walks at most, up from its intake or its
// outlet.
WATER_PUMP_COLUMN_REACH :: 32

// The owner a write into a sample goes to.
Field_Water_Owner_Kind :: enum u8 {
	Unowned,
	Sea,
	Body,
}

// A sample of a bucket's brush: its chunk, index and coordinate, and its
// squared distance to the brush's centre in position units.
Field_Water_Brush_Sample :: struct {
	chunk:            ^Field_Chunk,
	index:            int,
	sample:           Sample_Coordinate,
	distance_squared: i64,
}

// A full sample's volume in millilitres at the spacing (1000 L at 1 m,
// 36 926 mL at 333 mm): a display and rate conversion, not a conserved
// sum.
field_sample_millilitres :: proc(spacing_millimetres: int) -> i64 {
	spacing := i64(spacing_millimetres)
	return spacing * spacing * spacing / 1000
}

// A fill sum in whole litres.
field_water_fill_litres :: proc(fill, sample_millilitres: i64) -> i64 {
	return fill * sample_millilitres / (FIELD_WATER_FULL * 1000)
}

// Front water under teleport and for every unowned sample; under bodies a
// body's still sample or dry air is the body's, front water in its air
// (awake, not a spring) the front's (field_water_front_fill), and the
// sea's samples the sea's. An owner naming no live body is front.
field_water_owner_kind :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int) -> (kind: Field_Water_Owner_Kind, id: Water_Body_Id) {
	owner := chunk.water_owner[index]
	if world.water_model == .Teleport || owner == WATER_OWNER_NONE {
		return .Unowned, 0
	}
	if owner == WATER_OWNER_SEA {
		return .Sea, WATER_BODY_SEA
	}
	if field_sample_bit(&chunk.water_awake, index) && !field_sample_bit(&chunk.water_source, index) {
		return .Unowned, 0
	}
	body, owned := water_owner_body(world, owner)
	switch {
	case !owned:
		return .Unowned, 0
	case body == WATER_BODY_SEA:
		return .Sea, WATER_BODY_SEA
	}
	return .Body, body
}

// Front water's byte: as set_field_water under teleport, awake whoever
// owns the sample under bodies (set_front_water).
write_field_tool_water :: proc(world: ^Field_World, chunk: ^Field_Chunk, index: int, sample: Sample_Coordinate, fill: i32) {
	if world.water_model == .Bodies {
		set_front_water(world, chunk, index, sample, fill)
	} else {
		set_field_water(world, chunk, index, sample, fill)
	}
}

field_water_brush_sample_before :: proc(first, second: Field_Water_Brush_Sample) -> bool {
	if first.distance_squared != second.distance_squared {
		return first.distance_squared < second.distance_squared
	}
	return field_sample_before(first.sample, second.sample)
}

// The loaded samples that are not ground within radius (position units)
// of the centre sample, the centre first, then outwards, ties in sample
// order. A level brush is the sphere of its radius: the plane means
// nothing to water.
field_water_brush_samples :: proc(world: ^Field_World, spacing_millimetres: int, centre: Sample_Coordinate, radius: i64, allocator := context.temp_allocator) -> []Field_Water_Brush_Sample {
	reach := i32(ceiling_divide_i64(radius, sample_axis_to_position(1, spacing_millimetres)))
	centre_position := sample_to_world_position(centre, spacing_millimetres)
	samples := make([dynamic]Field_Water_Brush_Sample, allocator)
	for z in -reach ..= reach {
		for y in -reach ..= reach {
			for x in -reach ..= reach {
				sample := centre + Sample_Coordinate{x, y, z}
				offset := cast([3]i64)(sample_to_world_position(sample, spacing_millimetres) - centre_position)
				distance_squared := offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
				if distance_squared > radius * radius {
					continue
				}
				chunk, index := field_world_cell(world, sample)
				if chunk == nil || chunk.density[index] > 0 {
					continue
				}
				append(&samples, Field_Water_Brush_Sample{chunk = chunk, index = index, sample = sample, distance_squared = distance_squared})
			}
		}
	}
	slice.sort_by(samples[:], field_water_brush_sample_before)
	return samples[:]
}

// A pour of amount fill into the room of the brush's samples, nearest
// first; returns what was poured. What finds no room is not poured, but a
// brush with no room at all in deep water goes to the aimed sample's owner
// (pour_into_deep_water).
pour_field_water :: proc(world: ^Field_World, spacing_millimetres: int, centre: Sample_Coordinate, radius: i64, amount: i32) -> (poured: i64) {
	left := i64(amount)
	for entry in field_water_brush_samples(world, spacing_millimetres, centre, radius) {
		if left <= 0 {
			break
		}
		byte := i64(entry.chunk.water[entry.index])
		take := min(left, FIELD_WATER_FULL - byte)
		if take <= 0 {
			continue
		}
		kind, id := field_water_owner_kind(world, entry.chunk, entry.index)
		switch kind {
		case .Unowned:
			write_field_tool_water(world, entry.chunk, entry.index, entry.sample, i32(byte + take))
		case .Body:
			take = credit_water_body_volume(world, id, entry.sample, take)
		case .Sea:
			world.water_to_sea += take
		}
		left -= take
	}
	if left == i64(amount) {
		left -= pour_into_deep_water(world, centre, left)
	}
	return i64(amount) - left
}

// A bucket in water deeper than its brush, where no sample has room: a
// body's still water takes the press as volume (its level rises), the
// sea as water_to_sea; front water stays as it is (the flux spreads it).
// Returns what was taken.
pour_into_deep_water :: proc(world: ^Field_World, centre: Sample_Coordinate, amount: i64) -> i64 {
	chunk, index := field_world_cell(world, centre)
	if chunk == nil || chunk.density[index] > 0 || chunk.water[index] == 0 {
		return 0
	}
	kind, id := field_water_owner_kind(world, chunk, index)
	switch kind {
	case .Body:
		return credit_water_body_volume(world, id, centre, amount)
	case .Sea:
		world.water_to_sea += amount
		return amount
	case .Unowned:
	}
	return 0
}

// A drain of up to amount fill from the wet samples of the brush, nearest
// first; returns what was taken. A body is drained once through its
// volume (at most eight bodies a drain), the sea gives what is asked.
drain_field_water :: proc(world: ^Field_World, spacing_millimetres: int, centre: Sample_Coordinate, radius: i64, amount: i32) -> (drained: i64) {
	left := i64(amount)
	drained_bodies: [8]Water_Body_Id
	drained_count := 0
	for entry in field_water_brush_samples(world, spacing_millimetres, centre, radius) {
		if left <= 0 {
			break
		}
		byte := i64(entry.chunk.water[entry.index])
		if byte == 0 {
			continue
		}
		take: i64
		kind, id := field_water_owner_kind(world, entry.chunk, entry.index)
		switch kind {
		case .Unowned:
			take = min(left, byte)
			write_field_tool_water(world, entry.chunk, entry.index, entry.sample, i32(byte - take))
		case .Body:
			if drained_count == len(drained_bodies) || slice.contains(drained_bodies[:drained_count], id) {
				continue
			}
			drained_bodies[drained_count] = id
			drained_count += 1
			take = displace_water_body_volume(world, id, entry.sample, left)
		case .Sea:
			take = left
		}
		left -= take
	}
	return i64(amount) - left
}

// The sample k samples along up (a unit vector) from from.
field_column_sample :: proc(from: Sample_Coordinate, up: [3]i64, k: int, spacing_millimetres: int) -> Sample_Coordinate {
	step := sample_axis_to_position(1, spacing_millimetres)
	return nearest_field_sample(sample_to_world_position(from, spacing_millimetres) + World_Position(fixed_scale(up, i64(k) * step)), spacing_millimetres)
}

// A pump's intake: up to amount from what the intake stands in, by its
// owner; nothing when it is dry or not loaded.
sink_field_water :: proc(world: ^Field_World, intake: Sample_Coordinate, up: [3]i64, spacing_millimetres: int, amount: i64) -> (taken: i64) {
	chunk, index := field_world_cell(world, intake)
	if chunk == nil || amount <= 0 || chunk.density[index] > 0 || chunk.water[index] == 0 {
		return 0
	}
	kind, id := field_water_owner_kind(world, chunk, index)
	switch kind {
	case .Body:
		return displace_water_body_volume(world, id, intake, amount)
	case .Sea:
		return amount
	case .Unowned:
	}
	return take_field_water_column(world, intake, up, spacing_millimetres, amount)
}

// Front water at the intake: from the top of the wet run over it (at most
// WATER_PUMP_COLUMN_REACH samples) down to the intake, so the surface
// falls; a body's water or the sea's met on the way gives the rest.
take_field_water_column :: proc(world: ^Field_World, intake: Sample_Coordinate, up: [3]i64, spacing_millimetres: int, amount: i64) -> (taken: i64) {
	top := -1
	for k in 0 ..< WATER_PUMP_COLUMN_REACH {
		chunk, index := field_world_cell(world, field_column_sample(intake, up, k, spacing_millimetres))
		if chunk == nil || chunk.density[index] > 0 || chunk.water[index] == 0 {
			break
		}
		top = k
	}
	if top < 0 {
		return 0
	}
	left := amount
	front: i64 = 0
	column: for k := top; k >= 0 && left > 0; k -= 1 {
		sample := field_column_sample(intake, up, k, spacing_millimetres)
		chunk, index := field_world_cell(world, sample)
		kind, id := field_water_owner_kind(world, chunk, index)
		switch kind {
		case .Unowned:
			byte := i64(chunk.water[index])
			take := min(left, byte)
			if take > 0 {
				write_field_tool_water(world, chunk, index, sample, i32(byte - take))
				left -= take
				front += take
			}
		case .Body:
			left -= displace_water_body_volume(world, id, sample, left)
			break column
		case .Sea:
			left = 0
			break column
		}
	}
	if front > 0 {
		push_field_water_event(world, .Pump, field_column_sample(intake, up, top, spacing_millimetres), i32(min(front, FIELD_WATER_FULL)))
	}
	return amount - left
}

// A pump's outlet: amount into the room of the column over the outlet
// (at most WATER_PUMP_COLUMN_REACH samples, ground or an unloaded chunk
// stops it, a roof), a body's or the sea's sample taking all of the rest;
// returns what was added. Under teleport a submerged outlet climbs to the
// surface's room.
source_field_water :: proc(world: ^Field_World, outlet: Sample_Coordinate, up: [3]i64, spacing_millimetres: int, amount: i64) -> (added: i64) {
	left := amount
	for k in 0 ..< WATER_PUMP_COLUMN_REACH {
		if left <= 0 {
			break
		}
		sample := field_column_sample(outlet, up, k, spacing_millimetres)
		chunk, index := field_world_cell(world, sample)
		if chunk == nil || chunk.density[index] > 0 {
			break
		}
		kind, id := field_water_owner_kind(world, chunk, index)
		switch kind {
		case .Body:
			left -= credit_water_body_volume(world, id, sample, left)
		case .Sea:
			world.water_to_sea += left
			left = 0
		case .Unowned:
			byte := i64(chunk.water[index])
			take := min(left, FIELD_WATER_FULL - byte)
			if take > 0 {
				write_field_tool_water(world, chunk, index, sample, i32(byte + take))
				left -= take
			}
		}
		if kind != .Unowned {
			break
		}
	}
	return amount - left
}
