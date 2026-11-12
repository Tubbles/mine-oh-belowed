package game

import "core:slice"
import "core:testing"

// Work item 0382: the state hash off the frame. No test writes a file.

// The thread's hash of a snapshot is the direct hash of the same state:
// for a field world with a kept chunk, stale and cached chunks mixed, and
// for a block world with a saved chunk not loaded. The thread's hashes of
// the copied chunks are kept on them.
@(test)
test_a_snapshot_hashes_to_the_direct_state_hash :: proc(t: ^testing.T) {
	{
		game := make_field_test_game_content()
		session := start_field_test_session(test_field_game_config(), game)
		defer end_session(session)
		content := field_test_content(session, game)
		state := &session.simulation
		make_field_save_test_state(state, content)
		state.cheat_speed, state.free_crafting = true, true
		// The direct hash warms every loaded chunk's cache.
		direct := lockstep_state_hash(state)
		noted := make(map[Field_Chunk_Coordinate]u64, context.temp_allocator)
		for coordinate, chunk in state.field.world.chunks {
			noted[coordinate] = chunk.state_hash
		}
		stale := 0
		for coordinate, index in sorted_field_chunk_coordinates(state.field.world.chunks) {
			if index % 2 == 0 {
				note_field_chunk_change(state.field.world.chunks[coordinate])
				stale += 1
			}
		}
		job := &session.hash_job
		if !testing.expect(t, take_state_hash_snapshot(&job.snapshot, state)) {
			return
		}
		testing.expect_value(t, len(job.snapshot.field_planes), stale * FIELD_CHUNK_HASHED_BYTES)
		testing.expect_value(t, len(job.snapshot.kept_hashes), 1)
		start_state_hash_job(job)
		tick, hash, finished := finish_state_hash_job(job, &state.field)
		testing.expect(t, finished)
		testing.expect_value(t, tick, state.tick)
		testing.expect_value(t, hash, direct)
		plane_bytes := 0
		for coordinate, chunk in state.field.world.chunks {
			testing.expectf(t, chunk.hash_current && !chunk.hash_pending, "chunk %v kept the thread's hash", coordinate)
			testing.expect_value(t, chunk.state_hash, noted[coordinate])
			plane_bytes = 0
			for plane in field_chunk_hashed_planes(chunk) {
				plane_bytes += len(plane)
			}
		}
		testing.expect_value(t, plane_bytes, FIELD_CHUNK_HASHED_BYTES)
	}
	{
		content := make_save_test_content()
		generator := make_test_generator(DEFAULT_WORLD_SEED)
		simulation := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&simulation)
		load_save_test_chunks(&simulation.world, &simulation.records, &generator)
		loaded := sorted_loaded_chunk_coordinates(&simulation.world)
		if !testing.expect(t, len(loaded) > 0) {
			return
		}
		saved := loaded[0] + {0, 40, 0}
		simulation.world.saved_chunks[saved] = slice.clone(slice.to_bytes(simulation.world.chunks[loaded[0]].blocks[:]))
		simulation.cheat_speed, simulation.free_crafting = true, true
		job: State_Hash_Job
		defer destroy_state_hash_job(&job)
		if !testing.expect(t, take_state_hash_snapshot(&job.snapshot, &simulation)) {
			return
		}
		testing.expect_value(t, len(job.snapshot.loaded_blocks), len(simulation.world.chunks))
		testing.expect_value(t, len(job.snapshot.unloaded_blocks), 1)
		start_state_hash_job(&job)
		_, hash, finished := finish_state_hash_job(&job, &simulation.field)
		testing.expect(t, finished)
		testing.expect_value(t, hash, lockstep_state_hash(&simulation))
	}
}

// Ticks that write chunks while the thread hashes leave the hash of the
// snapshot's tick, and keep no thread's hash on a chunk written since:
// every chunk whose hash is current holds its recomputed hash. The thread
// sanitizer's probe.
@(test)
test_ticks_while_the_hash_runs_leave_the_snapshots_hash :: proc(t: ^testing.T) {
	game := make_field_test_game_content()
	session := start_field_test_session(test_field_game_config(), game)
	defer end_session(session)
	session.network.role = .Host
	content := field_test_content(session, game)
	state := &session.simulation
	sample, _ := make_field_save_test_state(state, content)
	// Spares the ticks up to the due one.
	state.tick = STATE_HASH_INTERVAL_TICKS - 1
	tick_field_test_simulation(state, content, {})
	due := state.tick
	if !testing.expect_value(t, due, STATE_HASH_INTERVAL_TICKS) {
		return
	}
	reference := lockstep_state_hash(state)
	for _, chunk in state.field.world.chunks {
		note_field_chunk_change(chunk)
	}
	testing.expect(t, start_state_hash_when_due(session))
	field_world_set_sample(&state.field.world, sample, Field_Sample{MAXIMUM_DENSITY, .Stone, 2})
	for _ in 0 ..< 30 {
		tick_field_test_simulation(state, content, {})
	}
	testing.expect(t, finish_state_hash(session))
	testing.expect_value(t, session.network.hashes[due], reference)
	written := state.field.world.chunks[sample_to_field_chunk_coordinate(sample)]
	testing.expect(t, !written.hash_current, "the chunk written after the snapshot keeps no hash")
	for coordinate, chunk in state.field.world.chunks {
		if !chunk.hash_current {
			continue
		}
		kept := chunk.state_hash
		chunk.hash_current = false
		testing.expectf(t, field_chunk_state_hash(chunk) == kept, "chunk %v holds its own hash", coordinate)
	}
}

// Work item 0382: every machine takes the hash on a due tick, alone or
// not, and only there; a host keeps the result, a lone one too, a client
// sends it and offline drops it.
@(test)
test_every_machine_takes_the_hash_and_keeps_it_by_role :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	Hash_Case :: struct {
		role:             Network_Role,
		peer:             bool,
		receives_records: bool,
		kept:             int,
	}
	cases := [?]Hash_Case {
		{role = .Offline},
		{role = .Host, kept = 1},
		{role = .Host, peer = true, kept = 1},
		{role = .Host, peer = true, receives_records = true, kept = 1},
		{role = .Client},
	}
	for test_case in cases {
		session := new(Session)
		session.simulation = make_save_test_simulation(&generator, content)
		// A peer's zero connection sends nothing.
		session.network.role = test_case.role
		if test_case.peer {
			append(&session.network.peers, Network_Peer{receives_records = test_case.receives_records})
		}
		session.simulation.tick = STATE_HASH_INTERVAL_TICKS
		testing.expectf(t, start_state_hash_when_due(session), "%v took the hash", test_case)
		testing.expectf(t, session.hash_job.pending, "%v has the job in flight", test_case)
		finish_state_hash(session)
		testing.expectf(t, len(session.network.hashes) == test_case.kept, "%v kept %d hashes", test_case, len(session.network.hashes))
		if test_case.kept > 0 {
			testing.expect(t, STATE_HASH_INTERVAL_TICKS in session.network.hashes)
		}
		session.simulation.tick = STATE_HASH_INTERVAL_TICKS + 1
		testing.expect(t, !start_state_hash_when_due(session), "a tick that is not due is not hashed")
		destroy_state_hash_job(&session.hash_job)
		destroy_session_network(&session.network)
		destroy_simulation(&session.simulation)
		free(session)
	}
}

// Without a thread the job runs on the calling thread at once, logs the
// fallback, and the finish reports the direct hash.
@(test)
test_the_hash_runs_on_the_frame_without_a_thread :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	session := new(Session)
	defer free(session)
	session.simulation = make_save_test_simulation(&generator, content)
	defer destroy_simulation(&session.simulation)
	load_save_test_chunks(&session.simulation.world, &session.simulation.records, &generator)
	defer destroy_session_network(&session.network)
	defer destroy_state_hash_job(&session.hash_job)
	session.network.role = .Host
	session.simulation.tick = STATE_HASH_INTERVAL_TICKS
	job := &session.hash_job
	if !testing.expect(t, take_state_hash_snapshot(&job.snapshot, &session.simulation)) {
		return
	}
	start_state_hash_job(job, threaded = false)
	testing.expect(t, job.thread == nil)
	testing.expect(t, job.fallback_logged)
	testing.expect(t, state_hash_job_done(job))
	testing.expect(t, finish_state_hash(session))
	testing.expect_value(t, session.network.hashes[STATE_HASH_INTERVAL_TICKS], lockstep_state_hash(&session.simulation))
}

// A session that ends with every loaded chunk being hashed on the thread
// joins it and frees the snapshot.
@(test) // slow
test_a_session_ends_with_its_hash_in_flight :: proc(t: ^testing.T) {
	game := make_field_test_game_content()
	session := start_field_test_session(test_field_game_config(), game)
	content := field_test_content(session, game)
	tick_field_test_simulation(&session.simulation, content, {})
	tick_field_test_simulation(&session.simulation, content, {})
	for _, chunk in session.simulation.field.world.chunks {
		note_field_chunk_change(chunk)
	}
	session.simulation.tick = STATE_HASH_INTERVAL_TICKS
	testing.expect(t, start_state_hash_when_due(session))
	end_session(session)
}
