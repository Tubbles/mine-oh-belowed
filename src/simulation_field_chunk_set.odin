package game

import "core:slice"
import "platform"

// The terrain field's simulated chunk set (work item 0179): the field's
// form of the block world's set (simulation_chunk_set.odin). Which field
// chunks the tick reads is derived inside the tick from every player's
// feet, so every machine of a lockstep session holds the same chunks
// round an edit and the water's sea edge and missing chunk rule agree.
// At the start of each tick the set becomes every chunk within the radius
// (data/game.sjson, field_simulation.chunk_radius) of a player's chunk,
// plus the chunks it already held within the margin more; chunks that left
// unload (a changed one keeps its bytes in Field_Simulation.saved_chunks),
// chunks that entered are taken from the arrived chunks in coordinate
// order, with their saved bytes when they have some. The streaming workers
// generate the chunks off the tick (world_field_streaming.odin) and hand
// them over as Field_Chunk_Ready_Command, so a chunk enters the world only
// inside a tick; a tick whose set holds a chunk this machine has not
// generated yet does not run (field_chunks_ready, through
// simulated_chunks_ready). A loaded world's set enters the same way
// (0185): its chunks generate on the workers and the first tick waits for
// all of them (Field_Chunk_Set.restoring, restore_arrived_field_set).

// The frame asks the workers for this many chunks more round every
// player, so a player crossing a chunk border finds the next slab
// generated.
FIELD_CHUNK_PREFETCH :: 1

Field_Chunk_Set :: struct {
	radius: i32,
	margin: i32,
	chunks: map[Field_Chunk_Coordinate]struct{},
	// The player chunks the set was last derived from: while they stay,
	// the set stays.
	centres: [dynamic]Field_Chunk_Coordinate,
	// A loaded world's set not in the world yet: the next tick waits until
	// every chunk of it has arrived, then inserts them as they were saved
	// (restore_arrived_field_set). Not saved.
	restoring: bool,
}

make_field_chunk_set :: proc(radius, margin: int) -> Field_Chunk_Set {
	return Field_Chunk_Set{radius = i32(radius), margin = i32(margin)}
}

destroy_field_chunk_set :: proc(set: ^Field_Chunk_Set) {
	delete(set.chunks)
	delete(set.centres)
}

field_feet_chunk :: proc(feet: World_Position, spacing_millimetres: int) -> Field_Chunk_Coordinate {
	return sample_to_field_chunk_coordinate(world_position_to_sample(feet, spacing_millimetres))
}

// Each player's chunk once, in coordinate order. In the temp allocator.
field_player_chunk_centres :: proc(players: []Player, spacing_millimetres: int) -> []Field_Chunk_Coordinate {
	centres := make([dynamic]Field_Chunk_Coordinate, 0, len(players), context.temp_allocator)
	for player in players {
		centre := field_feet_chunk(player.field.position, spacing_millimetres)
		if !slice.contains(centres[:], centre) {
			append(&centres, centre)
		}
	}
	slice.sort_by(centres[:], field_chunk_coordinate_before)
	return centres[:]
}

within_field_chunk_radius :: proc(centres: []Field_Chunk_Coordinate, coordinate: Field_Chunk_Coordinate, radius: i32) -> bool {
	for centre in centres {
		offset := coordinate - centre
		if abs(offset.x) <= radius && abs(offset.y) <= radius && abs(offset.z) <= radius {
			return true
		}
	}
	return false
}

// The set the next tick simulates, in coordinate order and the temp
// allocator. prefetch widens the radius for the frame's requests.
next_field_chunks :: proc(set: Field_Chunk_Set, centres: []Field_Chunk_Coordinate, prefetch: i32 = 0) -> []Field_Chunk_Coordinate {
	wanted := make(map[Field_Chunk_Coordinate]struct{}, context.temp_allocator)
	radius := set.radius + prefetch
	for centre in centres {
		for z in -radius ..= radius {
			for y in -radius ..= radius {
				for x in -radius ..= radius {
					wanted[centre + {x, y, z}] = {}
				}
			}
		}
	}
	for coordinate in set.chunks {
		if within_field_chunk_radius(centres, coordinate, set.radius + set.margin) {
			wanted[coordinate] = {}
		}
	}
	coordinates := make([dynamic]Field_Chunk_Coordinate, 0, len(wanted), context.temp_allocator)
	for coordinate in wanted {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	return coordinates[:]
}

field_chunk_coordinate_order :: proc(first, second: Field_Chunk_Coordinate) -> slice.Ordering {
	switch {
	case field_chunk_coordinate_before(first, second):
		return .Less
	case field_chunk_coordinate_before(second, first):
		return .Greater
	}
	return .Equal
}

// The set unchanged: the same player chunks and every chunk loaded.
field_set_settled :: proc(field: ^Field_Simulation, centres: []Field_Chunk_Coordinate) -> bool {
	return slice.equal(field.chunk_set.centres[:], centres) && len(field.chunk_set.chunks) == len(field.world.chunks)
}

// The chunks the next tick needs, for the frame's streaming: the set it
// would derive now and one ring more. In the temp allocator; empty
// outside a field session.
field_chunk_requests :: proc(state: ^Simulation_State) -> []Field_Chunk_Coordinate {
	if !state.field.enabled {
		return nil
	}
	return needed_field_chunks(state, FIELD_CHUNK_PREFETCH)
}

// The set the next tick derives (next_field_chunks), and while a loaded
// world's set is restoring the chunks of that set it lacks, since the
// restore inserts them before the tick derives its own. In the temp
// allocator.
needed_field_chunks :: proc(state: ^Simulation_State, prefetch: i32 = 0) -> []Field_Chunk_Coordinate {
	field := &state.field
	next := next_field_chunks(field.chunk_set, field_player_chunk_centres(state.players[:], field.spacing_millimetres), prefetch)
	if !field.chunk_set.restoring {
		return next
	}
	needed := make([dynamic]Field_Chunk_Coordinate, 0, len(next) + len(field.chunk_set.chunks), context.temp_allocator)
	append(&needed, ..next)
	for coordinate in field.chunk_set.chunks {
		if _, found := slice.binary_search_by(next, coordinate, field_chunk_coordinate_order); !found {
			append(&needed, coordinate)
		}
	}
	return needed[:]
}

// A generated chunk waiting for the set; a second arrival of one
// coordinate replaces the first.
stage_field_chunk_arrival :: proc(field: ^Field_Simulation, chunk: ^Field_Chunk) {
	if previous := field.arrived_chunks[chunk.coordinate] or_else nil; previous != nil {
		destroy_field_chunk(previous)
	}
	field.arrived_chunks[chunk.coordinate] = chunk
}

// Whether the next tick's field chunks are all loaded or arrived; true
// outside a field session. The arrivals are staged by the caller
// (simulated_chunks_ready).
field_chunks_ready :: proc(state: ^Simulation_State) -> bool {
	field := &state.field
	if !field.enabled {
		return true
	}
	centres := field_player_chunk_centres(state.players[:], field.spacing_millimetres)
	if !field.chunk_set.restoring && field_set_settled(field, centres) {
		return true
	}
	for coordinate in needed_field_chunks(state) {
		if coordinate not_in field.world.chunks && coordinate not_in field.arrived_chunks {
			return false
		}
	}
	return true
}

// Its saved bytes over a generated chunk that has some, which then stays
// marked changed, so the next save writes it again. field.bin decoded
// every saved chunk once already (decode_saved_field_chunk), so a refusal
// here only logs and the chunk regenerates.
apply_saved_field_chunk :: proc(field: ^Field_Simulation, chunk: ^Field_Chunk) {
	saved, found := field.saved_chunks[chunk.coordinate]
	if !found {
		return
	}
	if problem := decode_field_chunk_delta(saved.bytes, chunk); problem != "" {
		platform.log_printf("error: the saved field chunk %v does not load, it regenerates: %s", chunk.coordinate, problem)
	} else {
		chunk.modified = true
	}
	delete(saved.bytes)
	delete_key(&field.saved_chunks, chunk.coordinate)
}

// A chunk entering the set: its saved bytes over the generated chunk when
// a tick changed it before (apply_saved_field_chunk), then into the world
// with the arrival's wake and light seeding. With dig (the crater stands
// dug), its crater overlay (0271) is applied when it had no saved bytes
// and dropped when it had, since those were written after the dig;
// before the hit the overlay waits for it (dig_impact_crater). Returns
// whether the overlay wrote a sample.
insert_field_chunk_arrival :: proc(field: ^Field_Simulation, chunk: ^Field_Chunk, dig: bool) -> bool {
	saved := chunk.coordinate in field.saved_chunks
	apply_saved_field_chunk(field, chunk)
	field_world_insert_chunk(&field.world, chunk)
	mark_field_neighbours_dirty(&field.world, chunk.coordinate)
	if !dig {
		return false
	}
	// A chunk saved before the hit (its water changed) that unloaded and
	// enters again after it stays whole there: its saved bytes say nothing
	// of the crater. Alike on every machine, and the descent unloads no
	// chunk near the crater.
	if saved {
		drop_field_crater_overlay(chunk)
		return false
	}
	return apply_field_crater_overlay(&field.world, chunk) > 0
}

// A loaded world restored after its crater was dug keeps it in its saved
// chunks, so no restored chunk's overlay is applied (0271).
drop_field_crater_overlays :: proc(world: ^Field_World) {
	for _, chunk in world.chunks {
		drop_field_crater_overlay(chunk)
	}
}

// At the start of a tick: a loaded world's set restored first, once all
// of it arrived (until then nothing changes, so a world alone does not
// take part of it); then unloads what left the set, inserts what entered
// it, both in coordinate order. A chunk of the set that has not arrived
// stays missing (the driver checks field_chunks_ready first). Once the
// impact's crater stands dug (impact_crater_dug), an entering chunk takes
// it and the sky follows.
update_simulated_field_chunks :: proc(state: ^Simulation_State, content: Simulation_Content) {
	field := &state.field
	if !field.enabled {
		return
	}
	dig := impact_crater_dug(state.world.planet, field.arrival, state.tick, content.field.pod_rest.settle_ticks)
	if field.chunk_set.restoring {
		if !restore_arrived_field_set(field) {
			return
		}
		// Dropped only when the hit ran in a tick before this one: a set
		// saved at the hit's tick less one restores in the hit's own tick
		// (the tick is counted before the chunks), whose hit_field_arrival
		// still applies the overlays.
		settle_ticks := content.field.pod_rest.settle_ticks
		if impact_crater_dug(state.world.planet, field.arrival, max(state.tick, 1) - 1, settle_ticks) {
			drop_field_crater_overlays(&field.world)
		}
	}
	centres := field_player_chunk_centres(state.players[:], field.spacing_millimetres)
	if field_set_settled(field, centres) {
		return
	}
	next := next_field_chunks(field.chunk_set, centres)
	unload_left_field_chunks(field, next, state.world.settings.seed, state.world.planet)
	clear(&field.chunk_set.chunks)
	dug := false
	for coordinate in next {
		field.chunk_set.chunks[coordinate] = {}
		if coordinate in field.world.chunks {
			continue
		}
		if chunk, arrived := field.arrived_chunks[coordinate]; arrived {
			delete_key(&field.arrived_chunks, coordinate)
			dug = insert_field_chunk_arrival(field, chunk, dig) || dug
		}
	}
	if dug {
		update_field_sky_after_edits(&field.world)
	}
	clear(&field.chunk_set.centres)
	append(&field.chunk_set.centres, ..centres)
	drop_unwanted_field_arrivals(field, centres)
}

// next is sorted, so the left chunks are found in coordinate order. A
// leaving chunk a tick changed is kept when its terrain or water still
// differs from a fresh generation (field_saved_chunk); one the sea woke
// and that slept back to its generation leaves nothing behind. The water
// beside a leaving chunk below sea level wakes, so it can become a sea
// edge (wake_field_water_beside_missing).
unload_left_field_chunks :: proc(field: ^Field_Simulation, next: []Field_Chunk_Coordinate, seed: u64, planet: Planet) {
	world := &field.world
	leaving := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate in world.chunks {
		if _, kept := slice.binary_search_by(next, coordinate, field_chunk_coordinate_order); !kept {
			append(&leaving, coordinate)
		}
	}
	slice.sort_by(leaving[:], field_chunk_coordinate_before)
	for coordinate in leaving {
		chunk := world.chunks[coordinate]
		if saved, kept := field_saved_chunk(chunk, seed, planet, field.spacing_millimetres); kept {
			field.saved_chunks[coordinate] = saved
		}
		destroy_field_chunk(chunk)
		delete_key(&world.chunks, coordinate)
	}
	for coordinate in leaving {
		wake_field_water_beside_missing(world, coordinate)
	}
}

// A leaving chunk worth keeping: changed by a tick, and its terrain or
// water unlike a fresh generation of it. The comparison runs on unload
// only, the same on every machine. The hash is the chunk's, computed once.
field_saved_chunk :: proc(chunk: ^Field_Chunk, seed: u64, planet: Planet, spacing_millimetres: int) -> (saved: Field_Saved_Chunk, kept: bool) {
	if !chunk.modified {
		return {}, false
	}
	generated := new(Field_Chunk)
	defer free(generated)
	generate_field_chunk(seed, planet, spacing_millimetres, chunk.coordinate, generated)
	if field_chunk_terrain_and_water_equal(chunk, generated) {
		return {}, false
	}
	return Field_Saved_Chunk{bytes = encode_field_chunk(chunk), state_hash = field_chunk_state_hash(chunk)}, true
}

// Arrivals the prefetch ring and the margin no longer cover are freed.
drop_unwanted_field_arrivals :: proc(field: ^Field_Simulation, centres: []Field_Chunk_Coordinate) {
	reach := field.chunk_set.radius + FIELD_CHUNK_PREFETCH + field.chunk_set.margin
	dropped := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate in field.arrived_chunks {
		if coordinate in field.world.chunks || !within_field_chunk_radius(centres, coordinate, reach) {
			append(&dropped, coordinate)
		}
	}
	for coordinate in dropped {
		destroy_field_chunk(field.arrived_chunks[coordinate])
		delete_key(&field.arrived_chunks, coordinate)
	}
}

// The chunks the next tick needs (needed_field_chunks), generated on the
// calling thread and staged as arrivals, for a world without the workers
// (the benchmark, the tests).
stage_generated_field_set :: proc(state: ^Simulation_State) {
	field := &state.field
	for coordinate in needed_field_chunks(state) {
		if coordinate in field.world.chunks || coordinate in field.arrived_chunks {
			continue
		}
		chunk := new(Field_Chunk)
		generate_field_chunk(state.world.settings.seed, state.world.planet, field.spacing_millimetres, coordinate, chunk, crater_overlay = true)
		stage_field_chunk_arrival(field, chunk)
	}
}

// The field chunks generated and not yet in the world: arrived, or queued
// as a chunk ready command. In the temp allocator.
held_field_chunk_arrivals :: proc(state: ^Simulation_State) -> map[Field_Chunk_Coordinate]struct{} {
	held := make(map[Field_Chunk_Coordinate]struct{}, context.temp_allocator)
	for coordinate in state.field.arrived_chunks {
		held[coordinate] = {}
	}
	for queued in state.player_commands {
		if ready, is_chunk := queued.command.(Field_Chunk_Ready_Command); is_chunk {
			held[ready.chunk.coordinate] = {}
		}
	}
	return held
}
