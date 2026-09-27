package game

import "base:runtime"
import "core:container/queue"
import "core:os"
import "core:slice"
import "core:sync"
import "core:thread"

// Chunk streaming: worker threads generate and mesh chunks, the main thread
// inserts, unloads and schedules. Workers never touch the World. A mesh job
// carries a private copy of the chunk and of the cells around it (blocks
// and light), so edits and unloads on the main thread cannot race with it.

LOAD_RADIUS_HORIZONTAL :: 6
LOAD_RADIUS_VERTICAL :: 3
// Chunks unload once they are this many chunks beyond the load radius, so
// that moving back and forth across a border does not reload them.
UNLOAD_MARGIN :: 1
// Jobs submitted and not yet received. Keeps the queue short, so that jobs
// for far chunks do not pile up ahead of near ones when the camera moves.
MAXIMUM_PENDING_JOBS :: 48
MAXIMUM_GENERATED_PER_FRAME :: 16
// A mesh job copies a chunk and its border shell on the main thread, so
// the copies per frame stay bounded.
MAXIMUM_MESH_SUBMISSIONS_PER_FRAME :: 8
// Uploads of non empty meshes per frame, against hitches.
MAXIMUM_MESH_UPLOADS_PER_FRAME :: 6
MAXIMUM_WORKER_COUNT :: 6

Chunk_Job_Kind :: enum u8 {
	Generate,
	Mesh,
}

// For Mesh jobs, chunk and border are copies owned by the job. For
// Generate jobs of a saved chunk, saved is a copy of its bytes.
Chunk_Job :: struct {
	kind:       Chunk_Job_Kind,
	coordinate: Chunk_Coordinate,
	revision:   u64,
	chunk:      ^Chunk,
	border:     ^Chunk_Border,
	saved:      []byte,
}

// Generate results carry chunk and veins, Mesh results carry mesh.
// restored marks a chunk that holds saved blocks.
Chunk_Job_Result :: struct {
	kind:       Chunk_Job_Kind,
	coordinate: Chunk_Coordinate,
	revision:   u64,
	restored:   bool,
	chunk:      ^Chunk,
	veins:      [dynamic]Vein,
	outcrops:   [dynamic]Outcrop_Cell,
	crates:     [dynamic]Crate_Site,
	mesh:       Chunk_Mesh_Data,
}

Chunk_Job_Queue :: struct {
	mutex:         sync.Mutex,
	job_available: sync.Cond,
	jobs:          queue.Queue(Chunk_Job),
	generated:     queue.Queue(Chunk_Job_Result),
	meshed:        queue.Queue(Chunk_Job_Result),
	stopping:      bool,
}

// Everything the workers read. Only the queue is written after start.
// Workers allocate chunks, veins and meshes with the allocator of the
// thread that started streaming, which frees them after receiving.
Worker_Shared :: struct {
	jobs:      Chunk_Job_Queue,
	generator: ^Generator,
	registry:  Block_Registry,
	atlas:     Atlas_Layout,
	allocator: runtime.Allocator,
}

Chunk_Streaming :: struct {
	shared:             ^Worker_Shared,
	threads:            [dynamic]^thread.Thread,
	// Off for the debug terrain: nothing is generated or unloaded, and
	// only dirty chunks are meshed.
	load_around_camera: bool,
	// The load volume around the camera chunk, nearest first.
	offsets:            []Chunk_Coordinate,
	generating:         map[Chunk_Coordinate]struct{},
	// Latest mesh revision submitted per chunk. Results of older revisions
	// are dropped, since workers may finish out of order.
	mesh_revisions:     map[Chunk_Coordinate]u64,
	next_revision:      u64,
	pending_jobs:       int,
	// Chunks unloaded this frame, so the renderer can drop their meshes.
	unloaded:           [dynamic]Chunk_Coordinate,
}

submit_job :: proc(jobs: ^Chunk_Job_Queue, job: Chunk_Job) {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	queue.push_back(&jobs.jobs, job)
	sync.cond_signal(&jobs.job_available)
}

// Blocks until a job is available. Returns false once the queue stops.
wait_for_job :: proc(jobs: ^Chunk_Job_Queue) -> (job: Chunk_Job, ok: bool) {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	for queue.len(jobs.jobs) == 0 && !jobs.stopping {
		sync.cond_wait(&jobs.job_available, &jobs.mutex)
	}
	if jobs.stopping {
		return {}, false
	}
	return queue.pop_front(&jobs.jobs), true
}

push_result :: proc(jobs: ^Chunk_Job_Queue, result: Chunk_Job_Result) {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	queue.push_back(result.kind == .Generate ? &jobs.generated : &jobs.meshed, result)
}

take_generated_results :: proc(jobs: ^Chunk_Job_Queue, maximum: int, allocator := context.allocator) -> [dynamic]Chunk_Job_Result {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	results := make([dynamic]Chunk_Job_Result, 0, maximum, allocator)
	for len(results) < maximum && queue.len(jobs.generated) > 0 {
		append(&results, queue.pop_front(&jobs.generated))
	}
	return results
}

// Empty meshes cost no upload, so they do not count against the maximum.
take_mesh_results :: proc(jobs: ^Chunk_Job_Queue, maximum_uploads: int, allocator := context.allocator) -> [dynamic]Chunk_Job_Result {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	results := make([dynamic]Chunk_Job_Result, allocator)
	uploads := 0
	for uploads < maximum_uploads && queue.len(jobs.meshed) > 0 {
		result := queue.pop_front(&jobs.meshed)
		if len(result.mesh.parts) > 0 {
			uploads += 1
		}
		append(&results, result)
	}
	return results
}

stop_job_queue :: proc(jobs: ^Chunk_Job_Queue) {
	sync.mutex_lock(&jobs.mutex)
	defer sync.mutex_unlock(&jobs.mutex)
	jobs.stopping = true
	sync.cond_broadcast(&jobs.job_available)
}

free_job_chunks :: proc(job: Chunk_Job) {
	free(job.chunk)
	free(job.border)
	delete(job.saved)
}

free_job_result :: proc(result: Chunk_Job_Result) {
	free(result.chunk)
	delete(result.veins)
	delete(result.outcrops)
	delete(result.crates)
	destroy_chunk_mesh_data(result.mesh)
}

run_chunk_job :: proc(shared: ^Worker_Shared, job: Chunk_Job) -> Chunk_Job_Result {
	result := Chunk_Job_Result {
		kind       = job.kind,
		coordinate = job.coordinate,
		revision   = job.revision,
	}
	switch job.kind {
	case .Generate:
		generated: Generated_Chunk
		if job.saved != nil {
			generated, result.restored = generate_saved_chunk(shared.generator, job.coordinate, job.saved)
			delete(job.saved)
		} else {
			generated = generate_chunk(shared.generator, job.coordinate)
		}
		result.chunk, result.veins, result.outcrops, result.crates = generated.chunk, generated.veins, generated.outcrops, generated.crates
	case .Mesh:
		input := Mesh_Input {
			chunk    = job.chunk,
			border   = job.border,
			registry = shared.registry,
			atlas    = shared.atlas,
		}
		result.mesh = mesh_chunk(input)
		free_job_chunks(job)
	}
	return result
}

chunk_worker :: proc(shared: ^Worker_Shared) {
	context.allocator = shared.allocator
	for {
		job, ok := wait_for_job(&shared.jobs)
		if !ok {
			return
		}
		push_result(&shared.jobs, run_chunk_job(shared, job))
		free_all(context.temp_allocator)
	}
}

default_worker_count :: proc() -> int {
	return clamp(os.get_processor_core_count() - 1, 1, MAXIMUM_WORKER_COUNT)
}

offset_distance_squared :: proc(offset: Chunk_Coordinate) -> i32 {
	return offset.x * offset.x + offset.y * offset.y + offset.z * offset.z
}

offset_before :: proc(first, second: Chunk_Coordinate) -> bool {
	first_distance, second_distance := offset_distance_squared(first), offset_distance_squared(second)
	if first_distance != second_distance {
		return first_distance < second_distance
	}
	for axis in 0 ..< 3 {
		if first[axis] != second[axis] {
			return first[axis] < second[axis]
		}
	}
	return false
}

load_volume_offsets :: proc(allocator := context.allocator) -> []Chunk_Coordinate {
	offsets := make([dynamic]Chunk_Coordinate, allocator)
	for y in i32(-LOAD_RADIUS_VERTICAL) ..= LOAD_RADIUS_VERTICAL {
		for z in i32(-LOAD_RADIUS_HORIZONTAL) ..= LOAD_RADIUS_HORIZONTAL {
			for x in i32(-LOAD_RADIUS_HORIZONTAL) ..= LOAD_RADIUS_HORIZONTAL {
				append(&offsets, Chunk_Coordinate{x, y, z})
			}
		}
	}
	slice.sort_by(offsets[:], offset_before)
	return offsets[:]
}

within_radius :: proc(centre, coordinate: Chunk_Coordinate, horizontal, vertical: i32) -> bool {
	offset := coordinate - centre
	return abs(offset.x) <= horizontal && abs(offset.z) <= horizontal && abs(offset.y) <= vertical
}

in_load_volume :: proc(centre, coordinate: Chunk_Coordinate) -> bool {
	return within_radius(centre, coordinate, LOAD_RADIUS_HORIZONTAL, LOAD_RADIUS_VERTICAL)
}

in_keep_volume :: proc(centre, coordinate: Chunk_Coordinate) -> bool {
	return within_radius(centre, coordinate, LOAD_RADIUS_HORIZONTAL + UNLOAD_MARGIN, LOAD_RADIUS_VERTICAL + UNLOAD_MARGIN)
}

start_chunk_streaming :: proc(generator: ^Generator, registry: Block_Registry, load_around_camera: bool, worker_count: int) -> Chunk_Streaming {
	shared := new(Worker_Shared)
	shared.generator = generator
	shared.registry = registry
	shared.atlas = atlas_layout_for_block_count(len(registry.definitions))
	shared.allocator = context.allocator
	queue.init(&shared.jobs.jobs)
	queue.init(&shared.jobs.generated)
	queue.init(&shared.jobs.meshed)
	streaming := Chunk_Streaming {
		shared             = shared,
		load_around_camera = load_around_camera,
		offsets            = load_volume_offsets(),
	}
	for _ in 0 ..< worker_count {
		append(&streaming.threads, thread.create_and_start_with_poly_data(shared, chunk_worker))
	}
	return streaming
}

drain_job_queue :: proc(jobs: ^Chunk_Job_Queue) {
	for queue.len(jobs.jobs) > 0 {
		free_job_chunks(queue.pop_front(&jobs.jobs))
	}
	for queue.len(jobs.generated) > 0 {
		free_job_result(queue.pop_front(&jobs.generated))
	}
	for queue.len(jobs.meshed) > 0 {
		free_job_result(queue.pop_front(&jobs.meshed))
	}
}

stop_chunk_streaming :: proc(streaming: ^Chunk_Streaming) {
	stop_job_queue(&streaming.shared.jobs)
	for worker in streaming.threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	drain_job_queue(&streaming.shared.jobs)
	queue.destroy(&streaming.shared.jobs.jobs)
	queue.destroy(&streaming.shared.jobs.generated)
	queue.destroy(&streaming.shared.jobs.meshed)
	free(streaming.shared)
	delete(streaming.threads)
	delete(streaming.offsets)
	delete(streaming.generating)
	delete(streaming.mesh_revisions)
	delete(streaming.unloaded)
}

// An all air chunk under open sky looks like a missing one to the mesher,
// so its arrival changes no neighbour's mesh.
insert_generated_chunk :: proc(world: ^World, result: Chunk_Job_Result) {
	world.chunks[result.coordinate] = result.chunk
	mark_column_explored(world, chunk_column_of(result.coordinate))
	register_column_veins(world, chunk_column_of(result.coordinate), result.veins[:])
	register_outcrop_cells(world, result.outcrops[:])
	register_crate_sites(world, result.crates[:])
	queue.push_back(&world.lighting.arrived_chunks, result.coordinate)
	seed_entity_lights_in_chunk(world, result.chunk)
	if chunk_is_all_air(result.chunk) && chunk_is_open_sky(result.chunk) {
		return
	}
	for direction in Direction {
		mark_chunk_dirty(world, result.coordinate + Chunk_Coordinate(direction_offsets[direction]))
	}
}

// A chunk with saved blocks leaves World.saved_chunks while it is loaded,
// stays modified, and its light emitting blocks light up again.
insert_saved_chunk :: proc(world: ^World, registry: Block_Registry, result: Chunk_Job_Result) {
	insert_generated_chunk(world, result)
	if saved, found := world.saved_chunks[result.coordinate]; found {
		delete(saved)
		delete_key(&world.saved_chunks, result.coordinate)
	}
	seed_block_emitters_in_chunk(world, registry, result.chunk)
}

// Generation and insertion of one chunk on the calling thread, the way
// streaming does it on a worker and the main thread. For tests and tools.
load_chunk_now :: proc(world: ^World, generator: ^Generator, coordinate: Chunk_Coordinate) {
	result := Chunk_Job_Result {
		kind       = .Generate,
		coordinate = coordinate,
	}
	generated: Generated_Chunk
	if saved, found := world.saved_chunks[coordinate]; found {
		generated, result.restored = generate_saved_chunk(generator, coordinate, saved)
	} else {
		generated = generate_chunk(generator, coordinate)
	}
	result.chunk, result.veins, result.outcrops, result.crates = generated.chunk, generated.veins, generated.outcrops, generated.crates
	if result.restored {
		insert_saved_chunk(world, generator.registry, result)
	} else {
		insert_generated_chunk(world, result)
	}
	delete(result.veins)
	delete(result.outcrops)
	delete(result.crates)
}

// A modified chunk going out of range keeps its blocks in
// World.saved_chunks, so the edits come back with it and reach the save.
store_modified_chunk :: proc(world: ^World, chunk: ^Chunk) {
	if !chunk.modified {
		return
	}
	if previous, found := world.saved_chunks[chunk.coordinate]; found {
		delete(previous)
	}
	world.saved_chunks[chunk.coordinate] = serialize_chunk(chunk)
}

receive_generated_chunks :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk: Chunk_Coordinate) {
	results := take_generated_results(&streaming.shared.jobs, MAXIMUM_GENERATED_PER_FRAME, context.temp_allocator)
	for result in results {
		streaming.pending_jobs -= 1
		delete_key(&streaming.generating, result.coordinate)
		if result.coordinate in world.chunks || !in_keep_volume(camera_chunk, result.coordinate) {
			free_job_result(result)
			continue
		}
		if result.restored {
			insert_saved_chunk(world, streaming.shared.registry, result)
		} else {
			insert_generated_chunk(world, result)
		}
		delete(result.veins)
		delete(result.outcrops)
		delete(result.crates)
	}
}

unload_distant_chunks :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk: Chunk_Coordinate) {
	for coordinate in world.chunks {
		if !in_keep_volume(camera_chunk, coordinate) {
			append(&streaming.unloaded, coordinate)
		}
	}
	refresh_unloading_surfaces(world, streaming.unloaded[:])
	for coordinate in streaming.unloaded {
		store_modified_chunk(world, world.chunks[coordinate])
		free(world.chunks[coordinate])
		delete_key(&world.chunks, coordinate)
		delete_key(&streaming.mesh_revisions, coordinate)
	}
}

// A neighbour counts as settled when it is loaded or will not be loaded
// soon, so that a chunk is meshed once instead of once per arriving neighbour.
neighbours_settled :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk, coordinate: Chunk_Coordinate) -> bool {
	for direction in Direction {
		neighbour := coordinate + Chunk_Coordinate(direction_offsets[direction])
		if neighbour in world.chunks {
			continue
		}
		if streaming.load_around_camera && in_load_volume(camera_chunk, neighbour) {
			return false
		}
	}
	return true
}

copy_chunk_contents :: proc(chunk: ^Chunk) -> ^Chunk {
	copied := new(Chunk)
	copied.coordinate = chunk.coordinate
	copied.blocks = chunk.blocks
	copied.light = chunk.light
	return copied
}

submit_mesh_job :: proc(streaming: ^Chunk_Streaming, world: ^World, chunk: ^Chunk) {
	streaming.next_revision += 1
	streaming.mesh_revisions[chunk.coordinate] = streaming.next_revision
	job := Chunk_Job {
		kind       = .Mesh,
		coordinate = chunk.coordinate,
		revision   = streaming.next_revision,
		chunk      = copy_chunk_contents(chunk),
		border     = gather_chunk_border(world, chunk.coordinate),
	}
	chunk.dirty = false
	submit_job(&streaming.shared.jobs, job)
	streaming.pending_jobs += 1
}

submit_generate_job :: proc(streaming: ^Chunk_Streaming, world: ^World, coordinate: Chunk_Coordinate) {
	streaming.generating[coordinate] = {}
	saved: []byte
	if bytes, found := world.saved_chunks[coordinate]; found {
		saved = slice.clone(bytes)
	}
	submit_job(&streaming.shared.jobs, Chunk_Job{kind = .Generate, coordinate = coordinate, saved = saved})
	streaming.pending_jobs += 1
}

// Nearest first, so the chunks around the camera appear before far ones.
schedule_chunk_jobs :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk: Chunk_Coordinate) {
	mesh_submissions := 0
	for offset in streaming.offsets {
		if streaming.pending_jobs >= MAXIMUM_PENDING_JOBS {
			return
		}
		coordinate := camera_chunk + offset
		chunk := world.chunks[coordinate] or_else nil
		switch {
		case chunk == nil:
			if streaming.load_around_camera && coordinate not_in streaming.generating {
				submit_generate_job(streaming, world, coordinate)
			}
		case chunk.dirty && mesh_submissions < MAXIMUM_MESH_SUBMISSIONS_PER_FRAME && neighbours_settled(streaming, world, camera_chunk, coordinate):
			submit_mesh_job(streaming, world, chunk)
			mesh_submissions += 1
		}
	}
}

// Main thread, once per frame, before take_current_meshes.
update_chunk_streaming :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk: Chunk_Coordinate) {
	clear(&streaming.unloaded)
	if streaming.load_around_camera {
		receive_generated_chunks(streaming, world, camera_chunk)
		unload_distant_chunks(streaming, world, camera_chunk)
	}
	schedule_chunk_jobs(streaming, world, camera_chunk)
}

// Mesh results still current for a loaded chunk. Stale ones are freed here,
// the caller uploads and frees the rest.
take_current_meshes :: proc(streaming: ^Chunk_Streaming, maximum_uploads: int, allocator := context.allocator) -> [dynamic]Chunk_Job_Result {
	results := take_mesh_results(&streaming.shared.jobs, maximum_uploads, allocator)
	current := make([dynamic]Chunk_Job_Result, 0, len(results), allocator)
	for result in results {
		streaming.pending_jobs -= 1
		latest, found := streaming.mesh_revisions[result.coordinate]
		if found && latest == result.revision {
			append(&current, result)
		} else {
			free_job_result(result)
		}
	}
	return current
}
