package game

import "core:slice"

// The simulated chunk set (work item 0177): which chunks the tick reads is
// derived inside the tick from every player's position, so every machine
// of a lockstep session simulates the same chunks. At the start of each
// tick the set becomes every chunk within the radius (data/game.sjson,
// simulated_chunk_radius_horizontal and _vertical) of a player's chunk,
// plus the chunks it already held within one more chunk of one, so a
// player walking along a chunk border does not unload and reload a slab
// each step. Chunks that left the set unload, chunks that entered it are
// taken from the arrived chunks (Simulation_State.arrived_chunks) in
// coordinate order. A tick whose set holds a chunk this machine has not
// generated yet does not run (simulated_chunks_ready, checked by the
// lockstep driver). Off in tests, the benchmark and the debug terrain,
// whose chunks are placed by hand.

SIMULATED_CHUNK_UNLOAD_MARGIN :: 1
// The frame asks the workers for this many chunks more around every
// player, so a player crossing a chunk border finds the next slab
// generated and the tick does not stall for it.
SIMULATED_CHUNK_PREFETCH :: 1

Simulated_Chunk_Set :: struct {
	enabled:           bool,
	horizontal_radius: i32,
	vertical_radius:   i32,
	chunks:            map[Chunk_Coordinate]struct{},
	// The player chunks the set was last derived from: while they stay,
	// the set stays.
	centres:           [dynamic]Chunk_Coordinate,
}

make_simulated_chunk_set :: proc(horizontal_radius, vertical_radius: int) -> Simulated_Chunk_Set {
	return Simulated_Chunk_Set{enabled = true, horizontal_radius = i32(horizontal_radius), vertical_radius = i32(vertical_radius)}
}

destroy_simulated_chunk_set :: proc(state: ^Simulation_State) {
	delete(state.chunk_set.chunks)
	delete(state.chunk_set.centres)
	for _, result in state.arrived_chunks {
		free_job_result(result)
	}
	delete(state.arrived_chunks)
	delete(state.unloaded_chunks)
}

player_chunk :: proc(player: Player) -> Chunk_Coordinate {
	return world_to_chunk_coordinate(camera_world_coordinate(player.position))
}

// Each player's chunk once, in coordinate order. In the temp allocator.
player_chunk_centres :: proc(players: []Player) -> []Chunk_Coordinate {
	centres := make([dynamic]Chunk_Coordinate, 0, len(players), context.temp_allocator)
	for player in players {
		centre := player_chunk(player)
		if !slice.contains(centres[:], centre) {
			append(&centres, centre)
		}
	}
	slice.sort_by(centres[:], chunk_coordinate_before)
	return centres[:]
}

within_chunk_radius :: proc(centres: []Chunk_Coordinate, coordinate: Chunk_Coordinate, horizontal, vertical: i32) -> bool {
	for centre in centres {
		if within_radius(centre, coordinate, horizontal, vertical) {
			return true
		}
	}
	return false
}

// The set the next tick simulates, in coordinate order and the temp
// allocator. prefetch widens the radius for the frame's requests.
next_simulated_chunks :: proc(set: Simulated_Chunk_Set, centres: []Chunk_Coordinate, prefetch: i32 = 0) -> []Chunk_Coordinate {
	wanted := make(map[Chunk_Coordinate]struct{}, context.temp_allocator)
	horizontal, vertical := set.horizontal_radius + prefetch, set.vertical_radius + prefetch
	for centre in centres {
		for y in -vertical ..= vertical {
			for z in -horizontal ..= horizontal {
				for x in -horizontal ..= horizontal {
					wanted[centre + {x, y, z}] = {}
				}
			}
		}
	}
	for coordinate in set.chunks {
		if within_chunk_radius(centres, coordinate, set.horizontal_radius + SIMULATED_CHUNK_UNLOAD_MARGIN, set.vertical_radius + SIMULATED_CHUNK_UNLOAD_MARGIN) {
			wanted[coordinate] = {}
		}
	}
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(wanted), context.temp_allocator)
	for coordinate in wanted {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], chunk_coordinate_before)
	return coordinates[:]
}

// The set unchanged: the same player chunks and every chunk loaded.
simulated_set_settled :: proc(state: ^Simulation_State, centres: []Chunk_Coordinate) -> bool {
	return slice.equal(state.chunk_set.centres[:], centres) && len(state.chunk_set.chunks) == len(state.world.chunks)
}

// The chunks the next tick needs, for the frame's streaming: the set it
// would derive now and one ring more (SIMULATED_CHUNK_PREFETCH). In the
// temp allocator; empty while the set is off.
simulated_chunk_requests :: proc(state: ^Simulation_State) -> []Chunk_Coordinate {
	if !state.chunk_set.enabled {
		return nil
	}
	return next_simulated_chunks(state.chunk_set, player_chunk_centres(state.players[:]), SIMULATED_CHUNK_PREFETCH)
}

// Whether the next tick can run: every chunk of its set, and of the
// field's set (field_chunks_ready, 0179), loaded or arrived. Stages the
// arrivals first, which the tick does not read.
simulated_chunks_ready :: proc(state: ^Simulation_State) -> bool {
	stage_chunk_arrivals(state)
	if !field_chunks_ready(state) {
		return false
	}
	if !state.chunk_set.enabled {
		return true
	}
	centres := player_chunk_centres(state.players[:])
	if simulated_set_settled(state, centres) {
		return true
	}
	for coordinate in next_simulated_chunks(state.chunk_set, centres) {
		if coordinate not_in state.world.chunks && coordinate not_in state.arrived_chunks {
			return false
		}
	}
	return true
}

// At the start of a tick: unloads what left the set, inserts what
// entered it, both in coordinate order. A chunk of the set that has not
// arrived stays missing (the driver checks simulated_chunks_ready first).
// The field's set first (update_simulated_field_chunks, 0179).
update_simulated_chunks :: proc(state: ^Simulation_State, content: Simulation_Content) {
	update_simulated_field_chunks(state, content)
	set := &state.chunk_set
	centres := player_chunk_centres(state.players[:])
	if !set.enabled || simulated_set_settled(state, centres) {
		return
	}
	next := next_simulated_chunks(set^, centres)
	unload_left_chunks(state, next)
	clear(&set.chunks)
	for coordinate in next {
		set.chunks[coordinate] = {}
		if coordinate in state.world.chunks {
			continue
		}
		if result, arrived := state.arrived_chunks[coordinate]; arrived {
			delete_key(&state.arrived_chunks, coordinate)
			insert_chunk_arrival(&state.world, &state.records, content.blocks, content.generator, result)
		}
	}
	clear(&set.centres)
	append(&set.centres, ..centres)
	drop_unwanted_arrivals(state, centres)
}

// next is sorted, so the left chunks are found in coordinate order.
unload_left_chunks :: proc(state: ^Simulation_State, next: []Chunk_Coordinate) {
	world := &state.world
	leaving := make([dynamic]Chunk_Coordinate, context.temp_allocator)
	for coordinate in world.chunks {
		if _, kept := slice.binary_search_by(next, coordinate, chunk_coordinate_order); !kept {
			append(&leaving, coordinate)
		}
	}
	slice.sort_by(leaving[:], chunk_coordinate_before)
	refresh_unloading_surfaces(world, &state.records.explored, leaving[:])
	for coordinate in leaving {
		store_modified_chunk(world, world.chunks[coordinate])
		free(world.chunks[coordinate])
		delete_key(&world.chunks, coordinate)
		append(&state.unloaded_chunks, coordinate)
	}
}

// Arrivals the prefetch ring and the margin no longer cover are freed.
drop_unwanted_arrivals :: proc(state: ^Simulation_State, centres: []Chunk_Coordinate) {
	set := state.chunk_set
	reach := i32(SIMULATED_CHUNK_PREFETCH + SIMULATED_CHUNK_UNLOAD_MARGIN)
	dropped := make([dynamic]Chunk_Coordinate, context.temp_allocator)
	for coordinate in state.arrived_chunks {
		if coordinate in state.world.chunks || !within_chunk_radius(centres, coordinate, set.horizontal_radius + reach, set.vertical_radius + reach) {
			append(&dropped, coordinate)
		}
	}
	for coordinate in dropped {
		free_job_result(state.arrived_chunks[coordinate])
		delete_key(&state.arrived_chunks, coordinate)
	}
}

// The chunks generated and not yet in the world: arrived, or queued as a
// chunk ready command. In the temp allocator.
held_chunk_arrivals :: proc(state: ^Simulation_State) -> map[Chunk_Coordinate]struct{} {
	held := make(map[Chunk_Coordinate]struct{}, context.temp_allocator)
	for coordinate in state.arrived_chunks {
		held[coordinate] = {}
	}
	for queued in state.player_commands {
		if ready, is_chunk := queued.command.(Chunk_Ready_Command); is_chunk {
			held[ready.result.coordinate] = {}
		}
	}
	return held
}
