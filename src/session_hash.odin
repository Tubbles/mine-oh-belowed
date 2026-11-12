package game

import "core:slice"
import "core:thread"
import "platform"

// The state hash off the frame (work item 0382, doc/architecture.md,
// Threads and chunk streaming). On a due tick the main thread takes a
// snapshot of every byte lockstep_state_hash reads
// (take_state_hash_snapshot): the explored surfaces refreshed, the state
// encoded as the save encodes it, the block chunks' bytes, each loaded
// field chunk's cached hash or, while it is stale, its hashed planes, and
// the kept field chunks' hashes. A thread folds them in
// lockstep_state_hash's order (hash_state_snapshot), so it computes the
// same value and reads nothing the simulation writes.
//
// One job per session (Session.hash_job), started, polled, joined and
// written back only by the main thread; a due tick while one is in flight
// waits for it. A field chunk copied while stale is marked hash_pending,
// and after the join the thread's hash of it is kept on the chunk unless
// a tick wrote it since (keep_hashed_field_chunks), so a chunk is copied
// once per change. The frame finishes the job between frames
// (poll_state_hash) and reports the result by role (report_state_hash);
// end_session drops a job in flight, a content reload finishes it first.

// A block chunk's bytes, block_bytes[start:end].
State_Hash_Block_Bytes :: struct {
	coordinate: Chunk_Coordinate,
	start, end: int,
}

// A loaded field chunk: planes is the offset of its copied planes in
// field_planes, -1 when hash is its cached hash; the thread writes hash
// of a copied chunk.
State_Hash_Field_Chunk :: struct {
	coordinate: Field_Chunk_Coordinate,
	hash:       u64,
	planes:     int,
}

// What the hash's thread reads, in heap buffers kept across jobs.
State_Hash_Snapshot :: struct {
	tick:                                     u64,
	cheat_speed, free_crafting, field_enabled: bool,
	state_bytes:                              [dynamic]byte,
	loaded_blocks, unloaded_blocks:           [dynamic]State_Hash_Block_Bytes,
	block_bytes:                              [dynamic]byte,
	field_chunks:                             [dynamic]State_Hash_Field_Chunk,
	field_planes:                             [dynamic]byte,
	kept_hashes:                              [dynamic]u64,
}

// pending holds from the start to the report; result is written by the
// thread before it ends and read after the join.
State_Hash_Job :: struct {
	snapshot:        State_Hash_Snapshot,
	thread:          ^thread.Thread,
	pending:         bool,
	result:          u64,
	fallback_logged: bool,
}

// The snapshot of the state between ticks, its buffers cleared with their
// capacity kept. The two large buffers are reserved to their exact sizes
// before anything is copied or flagged; false when either cannot be. Main
// thread, with no job reading the snapshot.
take_state_hash_snapshot :: proc(snapshot: ^State_Hash_Snapshot, simulation: ^Simulation_State) -> (ok: bool) {
	world, field := &simulation.world, &simulation.field
	loaded := sorted_loaded_chunk_coordinates(world)
	unloaded := sorted_unloaded_saved_chunk_coordinates(world)
	clear_state_hash_snapshot(snapshot)
	if reserve(&snapshot.block_bytes, block_snapshot_size(world, loaded, unloaded)) != nil || reserve(&snapshot.field_planes, stale_field_chunk_count(field) * FIELD_CHUNK_HASHED_BYTES) != nil {
		return false
	}
	refresh_loaded_surfaces(world, &simulation.records.explored)
	snapshot.tick = simulation.tick
	snapshot.cheat_speed, snapshot.free_crafting, snapshot.field_enabled = simulation.cheat_speed, simulation.free_crafting, field.enabled
	write_simulation_state(&snapshot.state_bytes, simulation)
	for coordinate in loaded {
		append_state_hash_block_bytes(snapshot, &snapshot.loaded_blocks, coordinate, slice.to_bytes(world.chunks[coordinate].blocks[:]))
	}
	for coordinate in unloaded {
		append_state_hash_block_bytes(snapshot, &snapshot.unloaded_blocks, coordinate, world.saved_chunks[coordinate])
	}
	if field.enabled {
		copy_field_chunks_for_hash(snapshot, field)
	}
	return true
}

clear_state_hash_snapshot :: proc(snapshot: ^State_Hash_Snapshot) {
	clear(&snapshot.state_bytes)
	clear(&snapshot.loaded_blocks)
	clear(&snapshot.unloaded_blocks)
	clear(&snapshot.block_bytes)
	clear(&snapshot.field_chunks)
	clear(&snapshot.field_planes)
	clear(&snapshot.kept_hashes)
}

// In the temp allocator, as simulation_state_hash orders them.
sorted_loaded_chunk_coordinates :: proc(world: ^World) -> []Chunk_Coordinate {
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(world.chunks), context.temp_allocator)
	for coordinate in world.chunks {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], chunk_coordinate_before)
	return coordinates[:]
}

// The saved chunks not loaded, in the temp allocator, as
// lockstep_state_hash orders them.
sorted_unloaded_saved_chunk_coordinates :: proc(world: ^World) -> []Chunk_Coordinate {
	coordinates := make([dynamic]Chunk_Coordinate, 0, len(world.saved_chunks), context.temp_allocator)
	for coordinate in world.saved_chunks {
		if coordinate not_in world.chunks {
			append(&coordinates, coordinate)
		}
	}
	slice.sort_by(coordinates[:], chunk_coordinate_before)
	return coordinates[:]
}

block_snapshot_size :: proc(world: ^World, loaded, unloaded: []Chunk_Coordinate) -> int {
	size := len(loaded) * CHUNK_BLOCK_COUNT * size_of(Block_Id)
	for coordinate in unloaded {
		size += len(world.saved_chunks[coordinate])
	}
	return size
}

// The loaded field chunks whose cached hash is stale; none in a block
// world.
stale_field_chunk_count :: proc(field: ^Field_Simulation) -> int {
	if !field.enabled {
		return 0
	}
	count := 0
	for _, chunk in field.world.chunks {
		count += chunk.hash_current ? 0 : 1
	}
	return count
}

append_state_hash_block_bytes :: proc(snapshot: ^State_Hash_Snapshot, entries: ^[dynamic]State_Hash_Block_Bytes, coordinate: Chunk_Coordinate, bytes: []byte) {
	start := len(snapshot.block_bytes)
	append(&snapshot.block_bytes, ..bytes)
	append(entries, State_Hash_Block_Bytes{coordinate = coordinate, start = start, end = len(snapshot.block_bytes)})
}

// Each loaded field chunk in coordinate order, by its cached hash or, when
// stale, its hashed planes copied and the live chunk marked hash_pending;
// then the kept chunks' hashes in coordinate order.
copy_field_chunks_for_hash :: proc(snapshot: ^State_Hash_Snapshot, field: ^Field_Simulation) {
	for coordinate in sorted_field_chunk_coordinates(field.world.chunks) {
		chunk := field.world.chunks[coordinate]
		entry := State_Hash_Field_Chunk{coordinate = coordinate, hash = chunk.state_hash, planes = -1}
		if !chunk.hash_current {
			entry.planes = len(snapshot.field_planes)
			for plane in field_chunk_hashed_planes(chunk) {
				append(&snapshot.field_planes, ..plane)
			}
			chunk.hash_pending = true
		}
		append(&snapshot.field_chunks, entry)
	}
	for coordinate in sorted_field_chunk_coordinates(field.saved_chunks) {
		if coordinate not_in field.world.chunks {
			append(&snapshot.kept_hashes, field.saved_chunks[coordinate].state_hash)
		}
	}
}

// lockstep_state_hash's parts in its order, from the snapshot: the tick
// and the state's bytes, the loaded block chunks, the field chunks and the
// kept hashes, cheat speed, free crafting, the saved block chunks not
// loaded. A copied field chunk's hash is stored in its entry. Allocates
// nothing.
hash_state_snapshot :: proc(snapshot: ^State_Hash_Snapshot) -> u64 {
	result := fingerprint_bytes(fingerprint_u64(FINGERPRINT_START, snapshot.tick), snapshot.state_bytes[:])
	result = fingerprint_block_bytes(result, snapshot, snapshot.loaded_blocks[:])
	if snapshot.field_enabled {
		for &entry in snapshot.field_chunks {
			if entry.planes >= 0 {
				entry.hash = fingerprint_bytes(field_chunk_hash_start(entry.coordinate), snapshot.field_planes[entry.planes:][:FIELD_CHUNK_HASHED_BYTES])
			}
			result = fingerprint_u64(result, entry.hash)
		}
		for kept in snapshot.kept_hashes {
			result = fingerprint_u64(result, kept)
		}
	}
	result = fingerprint_u64(result, snapshot.cheat_speed ? 1 : 0)
	result = fingerprint_u64(result, snapshot.free_crafting ? 1 : 0)
	return fingerprint_block_bytes(result, snapshot, snapshot.unloaded_blocks[:])
}

// Each block chunk's coordinate words and bytes, as simulation_state_hash
// folds them.
fingerprint_block_bytes :: proc(start: u64, snapshot: ^State_Hash_Snapshot, entries: []State_Hash_Block_Bytes) -> u64 {
	result := start
	for entry in entries {
		result = fingerprint_u64(result, u64(u32(entry.coordinate.x)) | u64(u32(entry.coordinate.z)) << 32)
		result = fingerprint_u64(result, u64(u32(entry.coordinate.y)))
		result = fingerprint_bytes(result, snapshot.block_bytes[entry.start:entry.end])
	}
	return result
}

// The hash's thread: reads only the snapshot, writes only its field
// chunks' hashes and job.result.
run_state_hash_job :: proc(job: ^State_Hash_Job) {
	job.result = hash_state_snapshot(&job.snapshot)
}

// The job owns the snapshot from here. Without a thread (none could be
// made, or threaded false, which only a test passes) the hash runs on the
// calling thread at once and the next poll reports it.
start_state_hash_job :: proc(job: ^State_Hash_Job, threaded := true) {
	job.pending = true
	job.thread = nil
	if threaded {
		job.thread = thread.create_and_start_with_poly_data(job, run_state_hash_job)
	}
	if job.thread == nil {
		run_state_hash_job(job)
		log_state_hash_on_frame(job, "no thread")
	}
}

// The fallback's line, once per session.
log_state_hash_on_frame :: proc(job: ^State_Hash_Job, reason: string) {
	if !job.fallback_logged {
		job.fallback_logged = true
		platform.log_printf("network: the state hash runs on the frame (%s)", reason)
	}
}

state_hash_job_done :: proc(job: ^State_Hash_Job) -> bool {
	return job.thread == nil || thread.is_done(job.thread)
}

// The write-back, on the main thread after the join: a copied chunk still
// at its coordinate and not written since the snapshot (hash_pending)
// keeps the thread's hash.
keep_hashed_field_chunks :: proc(snapshot: ^State_Hash_Snapshot, field: ^Field_Simulation) {
	for entry in snapshot.field_chunks {
		if entry.planes < 0 {
			continue
		}
		chunk := field.world.chunks[entry.coordinate] or_else nil
		if chunk != nil && chunk.hash_pending {
			chunk.state_hash, chunk.hash_current, chunk.hash_pending = entry.hash, true, false
		}
	}
}

// The job in flight, waited for and written back: the snapshot's tick and
// its hash. finished is false when none was.
finish_state_hash_job :: proc(job: ^State_Hash_Job, field: ^Field_Simulation) -> (tick, hash: u64, finished: bool) {
	if !job.pending {
		return 0, 0, false
	}
	if job.thread != nil {
		thread.destroy(job.thread)
		job.thread = nil
	}
	if job.snapshot.field_enabled && field.enabled {
		keep_hashed_field_chunks(&job.snapshot, field)
	}
	job.pending = false
	return job.snapshot.tick, job.result, true
}

// Joins a thread still running and frees the buffers, with no write-back
// and no report.
destroy_state_hash_job :: proc(job: ^State_Hash_Job) {
	if job.thread != nil {
		thread.destroy(job.thread)
	}
	snapshot := &job.snapshot
	delete(snapshot.state_bytes)
	delete(snapshot.loaded_blocks)
	delete(snapshot.unloaded_blocks)
	delete(snapshot.block_bytes)
	delete(snapshot.field_chunks)
	delete(snapshot.field_planes)
	delete(snapshot.kept_hashes)
	job^ = {}
}

// On a due tick, after the job in flight finished: the snapshot and its
// thread, or when the snapshot's buffers cannot be reserved the hash on
// the frame, reported at once. started is true on every due tick.
start_state_hash_when_due :: proc(session: ^Session) -> (started: bool) {
	if !state_hash_due(session.simulation.tick) {
		return false
	}
	finish_state_hash(session)
	job := &session.hash_job
	if !take_state_hash_snapshot(&job.snapshot, &session.simulation) {
		log_state_hash_on_frame(job, "cannot reserve memory for the snapshot")
		report_state_hash(&session.network, session.simulation.tick, lockstep_state_hash(&session.simulation))
		return true
	}
	start_state_hash_job(job)
	return true
}

// Between frames: the job whose thread is done, finished and reported.
poll_state_hash :: proc(session: ^Session) {
	if session.hash_job.pending && state_hash_job_done(&session.hash_job) {
		finish_state_hash(session)
	}
}

// The job in flight, waited for, written back and reported.
finish_state_hash :: proc(session: ^Session) -> (finished: bool) {
	tick, hash: u64
	tick, hash, finished = finish_state_hash_job(&session.hash_job, &session.simulation.field)
	if finished {
		report_state_hash(&session.network, tick, hash)
	}
	return finished
}
