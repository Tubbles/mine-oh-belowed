package game

import "base:runtime"
import "core:container/queue"
import "core:sync"
import "core:thread"

// Field streaming (work item 0169, doc/architecture.md, Threads and chunk
// streaming): the block streaming's pattern for the terrain field. Worker
// threads generate field chunks and mesh nodes; the main thread schedules.
// The chunks the workers generate are the simulated set's (0179,
// simulation_field_chunk_set.odin): the frame names them (requested), and
// the generated chunks go back to the caller (arrivals), which hands them
// to the tick as Field_Chunk_Ready_Command, so only the tick inserts and
// unloads chunks. Workers never touch the Field_World: a mesh job of the
// finest level whose chunk and shell are simulated carries a private copy
// of them (gather_field_grid); any other node, a finest one beyond the set
// included, generates its grid on the worker (generate_field_grid), from
// the samples of the loaded chunks it reads, copied on the main thread
// (gather_coarse_field_grid), and the seed for the rest. A finest node
// meshed so stays drawn when its chunks leave the set, and meshes again
// from its chunks once they and their shell are simulated. Each mesh job
// carries the node's revision; a result whose revision is no longer the
// node's latest is dropped, so an edited chunk (dirty again) remeshes on
// the next revision and an old result never overwrites a new one.

MAXIMUM_FIELD_PENDING_JOBS :: 32
MAXIMUM_FIELD_GENERATED_PER_FRAME :: 16
// A finest level mesh job copies a chunk and its shell on the main thread.
MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME :: 8
MAXIMUM_FIELD_MESH_RESULTS_PER_FRAME :: 8

Field_Job_Kind :: enum u8 {
	Generate,
	Mesh,
}

// Generate jobs name a chunk (a finest level node). A Mesh job of a finest
// node whose chunks are simulated carries its grid whole; any other
// (generate set) carries the samples of the loaded chunks it reads, or
// none, and generates the rest. skirt_faces are the node's faces that
// border a coarser node or none (field_node_skirt_faces).
Field_Job :: struct {
	kind:        Field_Job_Kind,
	node:        Field_Node,
	revision:    u64,
	grid:        ^Field_Grid,
	generate:    bool,
	skirt_faces: Field_Faces,
}

// Generate results carry chunk, Mesh results the terrain's mesh and the
// water's (0172), both from one grid in one job, so the water never lags
// the terrain it lies on and one revision covers both.
Field_Job_Result :: struct {
	kind:       Field_Job_Kind,
	node:       Field_Node,
	revision:   u64,
	chunk:      ^Field_Chunk,
	mesh:       Field_Mesh_Data,
	water_mesh: Field_Mesh_Data,
}

// Everything the workers read; only the queues are written after start.
// The planet's palette stays with the caller's content for the streaming's
// life.
Field_Worker_Shared :: struct {
	mutex:         sync.Mutex,
	job_available: sync.Cond,
	jobs:          queue.Queue(Field_Job),
	generated:     queue.Queue(Field_Job_Result),
	meshed:        queue.Queue(Field_Job_Result),
	stopping:      bool,
	seed:          u64,
	planet:        Planet,
	generation:    Planet_Generation,
	allocator:     runtime.Allocator,
}

Field_Streaming :: struct {
	shared:         ^Field_Worker_Shared,
	threads:        [dynamic]^thread.Thread,
	generating:     map[Field_Chunk_Coordinate]struct{},
	// The latest mesh revision submitted per node; a node leaves when it is
	// no longer selected, which drops its pending result.
	mesh_revisions: map[Field_Node]u64,
	// The skirt faces of each node's latest job; a node whose faces change
	// (a neighbour split or merged) meshes again, so no seam opens.
	skirt_faces:    map[Field_Node]Field_Faces,
	// The revision of each node's job still on the workers. A node is not
	// submitted again while one is, so an edit made every tick (a held
	// brush) cannot keep dropping each result as stale: the dirty chunk or
	// the remesh mark waits, and the next job goes out once the result
	// lands.
	in_flight:      map[Field_Node]u64,
	// Coarser nodes over an edited chunk, meshed again once nothing of
	// theirs is in flight (mark_edited_coarse_nodes).
	remesh:         map[Field_Node]struct{},
	// Finest nodes last meshed from a generated grid, since their chunks
	// were not all simulated (schedule_finest_field_mesh).
	finest_generated: map[Field_Node]struct{},
	next_revision:  u64,
	pending_jobs:   int,
	// Nodes no longer selected this frame, whose meshes the renderer drops.
	dropped:        [dynamic]Field_Node,
}

submit_field_job :: proc(shared: ^Field_Worker_Shared, job: Field_Job) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	queue.push_back(&shared.jobs, job)
	sync.cond_signal(&shared.job_available)
}

wait_for_field_job :: proc(shared: ^Field_Worker_Shared) -> (job: Field_Job, ok: bool) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	for queue.len(shared.jobs) == 0 && !shared.stopping {
		sync.cond_wait(&shared.job_available, &shared.mutex)
	}
	if shared.stopping {
		return {}, false
	}
	return queue.pop_front(&shared.jobs), true
}

push_field_result :: proc(shared: ^Field_Worker_Shared, result: Field_Job_Result) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	queue.push_back(result.kind == .Generate ? &shared.generated : &shared.meshed, result)
}

take_field_results :: proc(shared: ^Field_Worker_Shared, kind: Field_Job_Kind, maximum: int, allocator := context.allocator) -> [dynamic]Field_Job_Result {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	source := kind == .Generate ? &shared.generated : &shared.meshed
	results := make([dynamic]Field_Job_Result, 0, maximum, allocator)
	for len(results) < maximum && queue.len(source^) > 0 {
		append(&results, queue.pop_front(source))
	}
	return results
}

free_field_job_result :: proc(result: Field_Job_Result) {
	free(result.chunk)
	destroy_field_mesh_data(result.mesh)
	destroy_field_mesh_data(result.water_mesh)
}

run_field_job :: proc(shared: ^Field_Worker_Shared, job: Field_Job) -> Field_Job_Result {
	result := Field_Job_Result {
		kind     = job.kind,
		node     = job.node,
		revision = job.revision,
	}
	switch job.kind {
	case .Generate:
		result.chunk = new(Field_Chunk)
		generate_field_chunk(shared.seed, shared.planet, shared.generation.spacing_millimetres, field_node_chunk(job.node), result.chunk)
	case .Mesh:
		grid := job.grid
		if grid == nil {
			grid = new(Field_Grid, context.temp_allocator)
		}
		if job.generate {
			generate_field_grid(shared.generation, job.node, grid)
		}
		result.mesh = mesh_field_grid(grid, shared.planet.palette, shared.generation.spacing_millimetres, job.skirt_faces)
		result.water_mesh = mesh_field_water_grid(grid, shared.planet.palette, shared.generation.spacing_millimetres)
		free(job.grid)
	}
	return result
}

field_worker :: proc(shared: ^Field_Worker_Shared) {
	context.allocator = shared.allocator
	for {
		job, ok := wait_for_field_job(shared)
		if !ok {
			return
		}
		push_field_result(shared, run_field_job(shared, job))
		free_all(context.temp_allocator)
	}
}

start_field_streaming :: proc(seed: u64, planet: Planet, spacing_millimetres: int, worker_count: int) -> Field_Streaming {
	shared := new(Field_Worker_Shared)
	shared.seed = seed
	shared.planet = planet
	shared.generation = make_planet_generation(seed, planet, spacing_millimetres)
	shared.allocator = context.allocator
	queue.init(&shared.jobs)
	queue.init(&shared.generated)
	queue.init(&shared.meshed)
	streaming := Field_Streaming {
		shared = shared,
	}
	for _ in 0 ..< worker_count {
		append(&streaming.threads, thread.create_and_start_with_poly_data(shared, field_worker))
	}
	return streaming
}

stop_field_streaming :: proc(streaming: ^Field_Streaming) {
	shared := streaming.shared
	sync.mutex_lock(&shared.mutex)
	shared.stopping = true
	sync.cond_broadcast(&shared.job_available)
	sync.mutex_unlock(&shared.mutex)
	for worker in streaming.threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	for queue.len(shared.jobs) > 0 {
		free(queue.pop_front(&shared.jobs).grid)
	}
	for queue.len(shared.generated) > 0 {
		free_field_job_result(queue.pop_front(&shared.generated))
	}
	for queue.len(shared.meshed) > 0 {
		free_field_job_result(queue.pop_front(&shared.meshed))
	}
	queue.destroy(&shared.jobs)
	queue.destroy(&shared.generated)
	queue.destroy(&shared.meshed)
	free(shared)
	delete(streaming.threads)
	delete(streaming.generating)
	delete(streaming.mesh_revisions)
	delete(streaming.skirt_faces)
	delete(streaming.in_flight)
	delete(streaming.remesh)
	delete(streaming.finest_generated)
	delete(streaming.dropped)
	streaming^ = {}
}

// A chunk changes the shell of its 26 neighbours.
mark_field_neighbours_dirty :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate) {
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				if neighbour := world.chunks[coordinate + {x, y, z}] or_else nil; neighbour != nil {
					neighbour.dirty = true
				}
			}
		}
	}
}

// The generated chunks the tick may take: those still requested and not
// in the world or held already go to arrivals, the rest are freed.
receive_field_chunks :: proc(streaming: ^Field_Streaming, world: ^Field_World, frame: Field_Stream_Frame, arrivals: ^[dynamic]^Field_Chunk) {
	requested := make(map[Field_Chunk_Coordinate]struct{}, len(frame.requested), context.temp_allocator)
	for coordinate in frame.requested {
		requested[coordinate] = {}
	}
	for result in take_field_results(streaming.shared, .Generate, MAXIMUM_FIELD_GENERATED_PER_FRAME, context.temp_allocator) {
		streaming.pending_jobs -= 1
		coordinate := field_node_chunk(result.node)
		delete_key(&streaming.generating, coordinate)
		if coordinate in world.chunks || coordinate in frame.held || coordinate not_in requested {
			free_field_job_result(result)
			continue
		}
		append(arrivals, result.chunk)
	}
}

// The requested chunks not in the world, held or on the workers, in the
// order given, while the pending budget lasts.
schedule_field_chunk_generation :: proc(streaming: ^Field_Streaming, world: ^Field_World, frame: Field_Stream_Frame) {
	for coordinate in frame.requested {
		if streaming.pending_jobs >= MAXIMUM_FIELD_PENDING_JOBS {
			return
		}
		if coordinate in world.chunks || coordinate in frame.held || coordinate in streaming.generating {
			continue
		}
		streaming.generating[coordinate] = {}
		submit_field_job(streaming.shared, Field_Job{kind = .Generate, node = field_chunk_node(coordinate)})
		streaming.pending_jobs += 1
	}
}

// Nodes that left the selection forget their revision, so their pending
// results are dropped and they mesh again when they come back.
drop_unselected_field_nodes :: proc(streaming: ^Field_Streaming, selection: []Field_Node) {
	selected := make(map[Field_Node]struct{}, context.temp_allocator)
	for node in selection {
		selected[node] = {}
	}
	clear(&streaming.dropped)
	for node in streaming.mesh_revisions {
		if node not_in selected {
			append(&streaming.dropped, node)
		}
	}
	for node in streaming.dropped {
		delete_key(&streaming.mesh_revisions, node)
		delete_key(&streaming.skirt_faces, node)
		delete_key(&streaming.remesh, node)
		delete_key(&streaming.finest_generated, node)
	}
}

field_chunk_neighbours_loaded :: proc(world: ^Field_World, coordinate: Field_Chunk_Coordinate) -> bool {
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				if coordinate + {x, y, z} not_in world.chunks {
					return false
				}
			}
		}
	}
	return true
}

submit_field_mesh_job :: proc(streaming: ^Field_Streaming, node: Field_Node, grid: ^Field_Grid, generate: bool, skirt_faces: Field_Faces) {
	streaming.next_revision += 1
	streaming.mesh_revisions[node] = streaming.next_revision
	streaming.in_flight[node] = streaming.next_revision
	streaming.skirt_faces[node] = skirt_faces
	submit_field_job(streaming.shared, Field_Job{kind = .Mesh, node = node, revision = streaming.next_revision, grid = grid, generate = generate, skirt_faces = skirt_faces})
	streaming.pending_jobs += 1
}

// Whether a meshed node's latest job had other skirt faces.
field_skirt_faces_changed :: proc(streaming: ^Field_Streaming, node: Field_Node, faces: Field_Faces) -> bool {
	previous, found := streaming.skirt_faces[node]
	return found && previous != faces
}

// A finest node whose chunk and every neighbour are simulated meshes from
// them, and again whenever the chunk is dirty or its skirt faces changed.
// Any other meshes once from a generated grid with the loaded samples it
// reads (finest_generated), again when an edit beside it marks it or its
// skirt faces change, and from its chunks once they are all simulated; a
// node meshed from its chunks keeps that mesh when they leave the set.
// Returns whether a job went out.
schedule_finest_field_mesh :: proc(streaming: ^Field_Streaming, world: ^Field_World, node: Field_Node, faces: Field_Faces) -> bool {
	if node in streaming.in_flight {
		return false
	}
	coordinate := field_node_chunk(node)
	chunk := world.chunks[coordinate] or_else nil
	faces_changed := field_skirt_faces_changed(streaming, node, faces)
	meshed := node in streaming.mesh_revisions
	if chunk != nil && field_chunk_neighbours_loaded(world, coordinate) {
		if !chunk.dirty && meshed && node not_in streaming.finest_generated && !faces_changed {
			return false
		}
		submit_field_mesh_job(streaming, node, gather_field_grid(world, coordinate), false, faces)
		chunk.dirty = false
		delete_key(&streaming.finest_generated, node)
		delete_key(&streaming.remesh, node)
		return true
	}
	if meshed && !faces_changed && node not_in streaming.remesh {
		return false
	}
	delete_key(&streaming.remesh, node)
	streaming.finest_generated[node] = {}
	submit_field_mesh_job(streaming, node, gather_coarse_field_grid(world, node), true, faces)
	// The generated grid read the loaded chunk's samples, so its changes
	// are in this mesh; a later edit marks the node again (remesh).
	if chunk != nil {
		chunk.dirty = false
	}
	return true
}

// Nearest first within each pass: the finest nodes' chunks and meshes take
// the budget before any coarser node, since the ground under the camera
// waits on 27 chunks a node and a coarse node on one job. A node whose
// skirt faces changed meshes again.
schedule_field_jobs :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node) {
	index := make_field_selection_index(selection, context.temp_allocator)
	submissions := 0
	for node in selection {
		if node.level != 0 {
			continue
		}
		if streaming.pending_jobs < MAXIMUM_FIELD_PENDING_JOBS && submissions < MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME {
			submissions += schedule_finest_field_mesh(streaming, world, node, field_node_skirt_faces(index, node)) ? 1 : 0
		}
	}
	for node in selection {
		if streaming.pending_jobs >= MAXIMUM_FIELD_PENDING_JOBS || submissions >= MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME {
			return
		}
		if node.level == 0 || node in streaming.in_flight {
			continue
		}
		faces := field_node_skirt_faces(index, node)
		if node not_in streaming.mesh_revisions || node in streaming.remesh || field_skirt_faces_changed(streaming, node, faces) {
			delete_key(&streaming.remesh, node)
			submit_field_mesh_job(streaming, node, gather_coarse_field_grid(world, node), true, faces)
			submissions += 1
		}
	}
}

// The meshed coarser nodes whose grid reads a chunk an edit changed (the
// chunk or one beside it, since a grid reads a step beyond its node) are
// marked to mesh again from the edited samples; the old mesh stays drawn
// until the new one arrives. The finest nodes meshed from their chunks
// follow the chunks' dirty flags; one meshed from a generated grid
// (finest_generated) is marked as the coarser ones. The edited chunks are
// taken every frame, and on a server, which meshes nothing, dropped.
mark_edited_coarse_nodes :: proc(streaming: ^Field_Streaming, world: ^Field_World) {
	for coordinate in world.edited_chunks {
		for z in i32(-1) ..= 1 {
			for y in i32(-1) ..= 1 {
				for x in i32(-1) ..= 1 {
					chunk := coordinate + {x, y, z}
					if finest := field_chunk_node(chunk); finest in streaming.finest_generated {
						streaming.remesh[finest] = {}
					}
					for level in i32(1) ..= FIELD_COARSEST_LEVEL {
						width := i32(1) << uint(level)
						node := Field_Node{level, {floor_divide(chunk.x, width), floor_divide(chunk.y, width), floor_divide(chunk.z, width)}}
						if node in streaming.mesh_revisions {
							streaming.remesh[node] = {}
						}
					}
				}
			}
		}
	}
	clear(&world.edited_chunks)
}

// What one frame asks of the streaming: the chunks the next ticks need
// (field_chunk_requests), the ones generated already and not in the world
// (held_field_chunk_arrivals), and the nodes the viewports' cameras chose
// (empty on a server).
Field_Stream_Frame :: struct {
	requested: []Field_Chunk_Coordinate,
	held:      map[Field_Chunk_Coordinate]struct{},
	selection: []Field_Node,
}

// Main thread, once per frame, before take_current_field_meshes. The
// generated chunks the tick may take go to arrivals; the generation goes
// out before the meshing, so the tick waits on as little as it can.
update_field_streaming :: proc(streaming: ^Field_Streaming, world: ^Field_World, frame: Field_Stream_Frame, arrivals: ^[dynamic]^Field_Chunk) {
	mark_edited_coarse_nodes(streaming, world)
	receive_field_chunks(streaming, world, frame, arrivals)
	drop_unselected_field_nodes(streaming, frame.selection)
	schedule_field_chunk_generation(streaming, world, frame)
	schedule_field_jobs(streaming, world, frame.selection)
}

// Mesh results still current for a selected node. Stale ones are freed
// here; the caller uploads and frees the rest.
take_current_field_meshes :: proc(streaming: ^Field_Streaming, allocator := context.allocator) -> [dynamic]Field_Job_Result {
	results := take_field_results(streaming.shared, .Mesh, MAXIMUM_FIELD_MESH_RESULTS_PER_FRAME, allocator)
	current := make([dynamic]Field_Job_Result, 0, len(results), allocator)
	for result in results {
		streaming.pending_jobs -= 1
		if streaming.in_flight[result.node] == result.revision {
			delete_key(&streaming.in_flight, result.node)
		}
		if latest, found := streaming.mesh_revisions[result.node]; found && latest == result.revision {
			append(&current, result)
		} else {
			free_field_job_result(result)
		}
	}
	return current
}
