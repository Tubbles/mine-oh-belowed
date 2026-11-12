package game

import "base:runtime"
import "core:container/queue"
import "core:slice"
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
// of them (gather_field_grid) and of the water's look's reach
// (gather_field_look_samples, 0344), from which the worker writes the
// water; any other node, a finest one beyond the set included, generates
// its grid on the worker (generate_field_grid), from the samples of the
// loaded chunks it reads and their water, copied on the main thread
// (gather_coarse_field_grid), and the seed for the rest. A finest node
// meshed so stays drawn when its chunks leave the set, and meshes again
// from its chunks once they and their shell are simulated. Each mesh job
// carries the node's revision; a result whose revision is no longer the
// node's latest is dropped, so an edited chunk (dirty again) remeshes on
// the next revision and an old result never overwrites a new one. The
// workers also generate the trees' draw tiles (0310,
// render_field_trees.odin) when no chunk or mesh job waits: a tree job
// carries its tile, and its result the tile's keys and packed instances.
// A finest level mesh job with the ground cover on (0311,
// world_field_cover.odin) carries copies of the frames over its node and
// returns the cover placed on its triangles; a change of the frames
// (Frame_Table.revision) marks the finest nodes under the changed frames
// to mesh again.

MAXIMUM_FIELD_PENDING_JOBS :: 32
MAXIMUM_FIELD_GENERATED_PER_FRAME :: 16
// A finest level mesh job copies a chunk and its shell on the main thread.
MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME :: 8
MAXIMUM_FIELD_MESH_RESULTS_PER_FRAME :: 8
// Finest meshes a frame for the surface waves alone (0294), after every
// unmeshed or edited node, within the frame's cap (schedule_field_jobs).
MAXIMUM_FIELD_WAVE_REMESHES_PER_FRAME :: 2

Field_Job_Kind :: enum u8 {
	Generate,
	Mesh,
	Trees,
}

// The trees' draw tile (0310): a cube of field_tree_tile_cells tree cubes
// an edge, about FIELD_TREE_TILE_METRES.
Field_Tree_Tile :: [3]i32
FIELD_TREE_TILE_METRES :: 128

// The tree cubes along a tile's edge at the tree spacing (position
// units), at least one.
field_tree_tile_cells :: proc(spacing: i64) -> i64 {
	return max(1, metres_to_position_units(FIELD_TREE_TILE_METRES) / max(spacing, 1))
}

// The tile's box in position units.
field_tree_tile_box :: proc(tile: Field_Tree_Tile, edge: i64) -> (minimum, maximum: [3]i64) {
	minimum = [3]i64{i64(tile.x), i64(tile.y), i64(tile.z)} * edge
	return minimum, minimum + edge - 1
}

// Generate jobs name a chunk (a finest level node). A Mesh job of a finest
// node whose chunks are simulated carries its grid whole; any other
// (generate set) carries the samples of the loaded chunks it reads, or
// none, and generates the rest. skirt_faces are the node's faces that
// hang a flap (a coarser node or none beyond) and those that cut and hang
// a curtain (finer nodes beyond, 0321; field_node_skirt_faces). A Trees
// job (0310) carries its tile, the tile's edge in tree cubes and the
// pitch the instances scale the models by. A finest Mesh job with the
// cover on carries copies of the frames over its node (cover_frames,
// 0311), freed by the worker after the job. The water's look (0344): a
// finest job meshed from its chunks carries the copy of the look's reach
// (look), one whose grid holds loaded samples to generate around carries
// their water (coarse_water); the worker writes the water from them and
// frees them with the grid (free_field_job_copies).
Field_Job :: struct {
	kind:        Field_Job_Kind,
	node:        Field_Node,
	revision:    u64,
	grid:        ^Field_Grid,
	generate:    bool,
	skirt_faces: Field_Seam_Faces,
	tree_tile:   Field_Tree_Tile,
	tree_cells:  i64,
	tree_pitch_millimetres: int,
	cover_frames: []Cover_Frame,
	look:         ^Field_Look_Samples,
	coarse_water: ^Field_Coarse_Water,
}

// Generate results carry chunk, Mesh results the terrain's mesh and the
// water's (0172), both from one grid in one job, so the water never lags
// the terrain it lies on and one revision covers both. Trees results
// (0310) carry the tile's standing and felled trees' keys and instances
// (tree_instance), in the workers' allocator. A finest Mesh result with
// the cover on carries the node's cover (0311). A Mesh result carries its
// terrain mesh's depth hash (field_mesh_depth_hash, 0348).
Field_Job_Result :: struct {
	kind:       Field_Job_Kind,
	node:       Field_Node,
	revision:   u64,
	chunk:      ^Field_Chunk,
	mesh:       Field_Mesh_Data,
	terrain_hash: u64,
	water_mesh: Field_Mesh_Data,
	tree_tile:  Field_Tree_Tile,
	tree_keys:  []Tree_Key,
	tree_instances: []matrix[4, 4]f32,
	cover:      Field_Cover_Data,
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
	// The trees' tile jobs (0310), taken only when jobs is empty, and
	// their results.
	tree_jobs:     queue.Queue(Field_Job),
	trees_done:    queue.Queue(Field_Job_Result),
	stopping:      bool,
	seed:          u64,
	planet:        Planet,
	generation:    Planet_Generation,
	// The ground's look the meshes take (0307, make_field_ground_look).
	look:          Field_Ground_Look,
	// The ground cover the finest meshes place (0311,
	// make_field_cover_table); off in a stream started without a row.
	cover:         Field_Cover_Table,
	allocator:     runtime.Allocator,
}

Field_Streaming :: struct {
	shared:         ^Field_Worker_Shared,
	threads:        [dynamic]^thread.Thread,
	generating:     map[Field_Chunk_Coordinate]struct{},
	// The latest mesh revision submitted per node; a node leaves when it is
	// no longer selected, which drops its pending result.
	mesh_revisions: map[Field_Node]u64,
	// The flap and curtain faces of each node's latest job; a node whose
	// faces change (a neighbour split or merged) meshes again, so no seam
	// opens.
	skirt_faces:    map[Field_Node]Field_Seam_Faces,
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
	// The frames with occupied cells as the cover last saw them, and the
	// frame table's revision then (0311, update_cover_frames).
	cover_frames:          [dynamic]Cover_Frame,
	cover_frames_revision: u64,
}

submit_field_job :: proc(shared: ^Field_Worker_Shared, job: Field_Job) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	queue.push_back(&shared.jobs, job)
	sync.cond_signal(&shared.job_available)
}

// A chunk or mesh job first; a tree tile only when none waits (0310), so
// the trees never hold back the ground.
wait_for_field_job :: proc(shared: ^Field_Worker_Shared) -> (job: Field_Job, ok: bool) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	for queue.len(shared.jobs) == 0 && queue.len(shared.tree_jobs) == 0 && !shared.stopping {
		sync.cond_wait(&shared.job_available, &shared.mutex)
	}
	if shared.stopping {
		return {}, false
	}
	if queue.len(shared.jobs) > 0 {
		return queue.pop_front(&shared.jobs), true
	}
	return queue.pop_front(&shared.tree_jobs), true
}

push_field_result :: proc(shared: ^Field_Worker_Shared, result: Field_Job_Result) {
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	switch result.kind {
	case .Generate:
		queue.push_back(&shared.generated, result)
	case .Mesh:
		queue.push_back(&shared.meshed, result)
	case .Trees:
		queue.push_back(&shared.trees_done, result)
	}
}

// A tree tile for the workers (0310), behind every chunk and mesh job.
submit_field_tree_tile :: proc(streaming: ^Field_Streaming, tile: Field_Tree_Tile, cells: i64, pitch_millimetres: int) {
	shared := streaming.shared
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	queue.push_back(&shared.tree_jobs, Field_Job{kind = .Trees, tree_tile = tile, tree_cells = cells, tree_pitch_millimetres = pitch_millimetres})
	sync.cond_signal(&shared.job_available)
}

// Up to maximum finished tree tiles; the caller takes their slices
// (free_field_job_result).
take_field_tree_tiles :: proc(streaming: ^Field_Streaming, maximum: int, allocator := context.temp_allocator) -> [dynamic]Field_Job_Result {
	shared := streaming.shared
	sync.mutex_lock(&shared.mutex)
	defer sync.mutex_unlock(&shared.mutex)
	results := make([dynamic]Field_Job_Result, 0, maximum, allocator)
	for len(results) < maximum && queue.len(shared.trees_done) > 0 {
		append(&results, queue.pop_front(&shared.trees_done))
	}
	return results
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
	destroy_field_chunk(result.chunk)
	destroy_field_mesh_data(result.mesh)
	destroy_field_mesh_data(result.water_mesh)
	delete(result.tree_keys)
	delete(result.tree_instances)
	destroy_field_cover_data(result.cover)
}

// A job's frame copies (0311).
free_field_job_frames :: proc(job: Field_Job) {
	destroy_cover_frames(job.cover_frames)
	delete(job.cover_frames)
}

// Everything a mesh job carries: the grid, the water's copies (0344) and
// the frames.
free_field_job_copies :: proc(job: Field_Job) {
	free(job.grid)
	destroy_field_look_samples(job.look)
	destroy_field_coarse_water(job.coarse_water)
	free_field_job_frames(job)
}

// The tile's trees (planet_trees_in_box, with the tile's sea boxes, 0337),
// their keys and instances in the allocator.
generate_field_tree_tile :: proc(generation: ^Planet_Generation, tile: Field_Tree_Tile, cells: i64, pitch_millimetres: int, allocator := context.allocator) -> (keys: []Tree_Key, instances: []matrix[4, 4]f32) {
	minimum, maximum := field_tree_tile_box(tile, cells * generation.trees.spacing)
	sea := make_tree_sea_boxes(generation.trees, minimum, maximum)
	trees := planet_trees_in_box(generation, minimum, maximum, sea = &sea)
	keys = make([]Tree_Key, len(trees), allocator)
	instances = make([]matrix[4, 4]f32, len(trees), allocator)
	for tree, index in trees {
		keys[index] = tree.key
		instances[index] = tree_instance(tree, pitch_millimetres)
	}
	return keys, instances
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
		generate_field_chunk(shared.seed, shared.planet, shared.generation.spacing_millimetres, field_node_chunk(job.node), result.chunk, crater_overlay = true)
	case .Mesh:
		grid := job.grid
		if grid == nil {
			grid = new(Field_Grid, context.temp_allocator)
		}
		if job.generate {
			generate_field_grid(shared.generation, job.node, grid, job.coarse_water)
		}
		if job.look != nil {
			write_field_water_look(grid, job.look)
		}
		// A job's own grid holds loaded samples, which an edit can have
		// moved off the generated surface (field_natural_share). The
		// finest level places the cover (0311) and measures its cuts with
		// or without loaded samples, since the generation carves below the
		// height map (an arch, a grotto, a cave, a notch): its cover is
		// then the same from a generated grid as from the loaded chunks.
		cover: ^Field_Cover_Data = nil
		if job.node.level == 0 && shared.cover.on {
			cover = &result.cover
		}
		measure_cuts := job.grid != nil || job.node.level == 0
		result.mesh = mesh_field_grid(grid, shared.planet.palette, shared.generation.spacing_millimetres, job.skirt_faces, look = shared.look, measure_cuts = measure_cuts, cover = cover, cover_table = shared.cover, cover_frames = job.cover_frames)
		result.terrain_hash = field_mesh_depth_hash(result.mesh)
		result.water_mesh = mesh_field_water_grid(grid, shared.planet.palette, shared.generation.spacing_millimetres)
		free_field_job_copies(job)
	case .Trees:
		result.tree_tile = job.tree_tile
		result.tree_keys, result.tree_instances = generate_field_tree_tile(&shared.generation, job.tree_tile, job.tree_cells, job.tree_pitch_millimetres)
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

// cover_row is the build target's row of field_cover (0311); the zero row
// places no cover.
start_field_streaming :: proc(seed: u64, planet: Planet, spacing_millimetres: int, worker_count: int, cover_row: Field_Cover_Row = {}) -> Field_Streaming {
	shared := new(Field_Worker_Shared)
	shared.seed = seed
	shared.planet = planet
	shared.generation = make_planet_generation(seed, planet, spacing_millimetres)
	shared.look = make_field_ground_look(shared.generation, planet)
	shared.cover = make_field_cover_table(shared.generation, planet, cover_row)
	shared.allocator = context.allocator
	queue.init(&shared.jobs)
	queue.init(&shared.generated)
	queue.init(&shared.meshed)
	queue.init(&shared.tree_jobs)
	queue.init(&shared.trees_done)
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
		free_field_job_copies(queue.pop_front(&shared.jobs))
	}
	for queue.len(shared.generated) > 0 {
		free_field_job_result(queue.pop_front(&shared.generated))
	}
	for queue.len(shared.meshed) > 0 {
		free_field_job_result(queue.pop_front(&shared.meshed))
	}
	for queue.len(shared.trees_done) > 0 {
		free_field_job_result(queue.pop_front(&shared.trees_done))
	}
	queue.destroy(&shared.jobs)
	queue.destroy(&shared.generated)
	queue.destroy(&shared.meshed)
	queue.destroy(&shared.tree_jobs)
	queue.destroy(&shared.trees_done)
	free(shared)
	delete(streaming.threads)
	delete(streaming.generating)
	delete(streaming.mesh_revisions)
	delete(streaming.skirt_faces)
	delete(streaming.in_flight)
	delete(streaming.remesh)
	delete(streaming.finest_generated)
	delete(streaming.dropped)
	destroy_cover_frames(streaming.cover_frames[:])
	delete(streaming.cover_frames)
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

// A finest node's job with the cover on carries the frames over the node
// (0311). look and coarse_water are the water's copies (0344), handed to
// the job with the grid.
submit_field_mesh_job :: proc(streaming: ^Field_Streaming, node: Field_Node, grid: ^Field_Grid, generate: bool, skirt_faces: Field_Seam_Faces, look: ^Field_Look_Samples = nil, coarse_water: ^Field_Coarse_Water = nil) {
	streaming.next_revision += 1
	streaming.mesh_revisions[node] = streaming.next_revision
	streaming.in_flight[node] = streaming.next_revision
	streaming.skirt_faces[node] = skirt_faces
	cover_frames: []Cover_Frame
	if node.level == 0 && streaming.shared.cover.on {
		minimum, maximum := field_cover_node_box(node, streaming.shared.generation.spacing_millimetres, COVER_FRAME_MARGIN_METRES)
		cover_frames = cover_frames_meeting(streaming.cover_frames[:], minimum, maximum)
	}
	submit_field_job(streaming.shared, Field_Job{kind = .Mesh, node = node, revision = streaming.next_revision, grid = grid, generate = generate, skirt_faces = skirt_faces, cover_frames = cover_frames, look = look, coarse_water = coarse_water})
	streaming.pending_jobs += 1
}

// Whether a meshed node's latest job had other flap or curtain faces.
field_skirt_faces_changed :: proc(streaming: ^Field_Streaming, node: Field_Node, faces: Field_Seam_Faces) -> bool {
	previous, found := streaming.skirt_faces[node]
	return found && previous != faces
}

// A finest node whose chunk and every neighbour are simulated meshes from
// them, and again whenever the chunk is dirty, its skirt faces changed or
// a frame over it changed (remesh, 0311).
// Any other meshes once from a generated grid with the loaded samples it
// reads (finest_generated), again when an edit beside it marks it or its
// skirt faces change, and from its chunks once they are all simulated; a
// node meshed from its chunks keeps that mesh when they leave the set.
// The surface waves' baked offsets go into the look's copy at the gather
// (0294, 0344); a chunk the waves alone marked (wave_dirty) waits for
// schedule_field_wave_remeshes. Returns whether a job went out.
schedule_finest_field_mesh :: proc(streaming: ^Field_Streaming, world: ^Field_World, node: Field_Node, faces: Field_Seam_Faces, waves: Field_Wave_Heights = nil) -> bool {
	if node in streaming.in_flight {
		return false
	}
	coordinate := field_node_chunk(node)
	chunk := world.chunks[coordinate] or_else nil
	faces_changed := field_skirt_faces_changed(streaming, node, faces)
	meshed := node in streaming.mesh_revisions
	if chunk != nil && field_chunk_neighbours_loaded(world, coordinate) {
		if !chunk.dirty && meshed && node not_in streaming.finest_generated && !faces_changed && node not_in streaming.remesh {
			return false
		}
		submit_field_mesh_job(streaming, node, gather_field_grid(world, coordinate), false, faces, look = gather_field_look_samples(world, coordinate, waves))
		chunk.dirty, chunk.wave_dirty = false, false
		delete_key(&streaming.finest_generated, node)
		delete_key(&streaming.remesh, node)
		return true
	}
	if meshed && !faces_changed && node not_in streaming.remesh {
		return false
	}
	delete_key(&streaming.remesh, node)
	streaming.finest_generated[node] = {}
	grid, coarse_water := gather_coarse_field_grid(world, node)
	submit_field_mesh_job(streaming, node, grid, true, faces, coarse_water = coarse_water)
	// The generated grid read the loaded chunk's samples, so its changes
	// are in this mesh; a later edit marks the node again (remesh).
	if chunk != nil {
		chunk.dirty = false
	}
	return true
}

// A finest node meshed from its chunks whose chunk the waves alone marked
// (wave_dirty) and that can mesh again now; nil when it cannot.
field_wave_remesh_chunk :: proc(streaming: ^Field_Streaming, world: ^Field_World, node: Field_Node) -> ^Field_Chunk {
	if node.level != 0 {
		return nil
	}
	coordinate := field_node_chunk(node)
	chunk := world.chunks[coordinate] or_else nil
	if chunk == nil || !chunk.wave_dirty || node in streaming.in_flight || node not_in streaming.mesh_revisions || node in streaming.finest_generated || !field_chunk_neighbours_loaded(world, coordinate) {
		return nil
	}
	return chunk
}

Field_Wave_Remesh :: struct {
	tick:     u64,
	position: int,
}

// The waves' pass: of the selection's chunks the waves alone marked, the
// oldest marks first (wave_dirty_tick), nearest first among marks of one
// tick, at most `limit`, each meshed again with the current heights.
// Oldest first, a node marked every frame can never hold the budget from
// one marked once: a mark waits at most the marked nodes over the budget
// in frames, while nothing else takes the frame's cap. Returns the jobs
// sent.
schedule_field_wave_remeshes :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node, index: Field_Selection_Index, waves: Field_Wave_Heights, limit: int) -> int {
	if limit <= 0 {
		return 0
	}
	waiting := make([dynamic]Field_Wave_Remesh, context.temp_allocator)
	for node, position in selection {
		if chunk := field_wave_remesh_chunk(streaming, world, node); chunk != nil {
			append(&waiting, Field_Wave_Remesh{chunk.wave_dirty_tick, position})
		}
	}
	slice.sort_by(waiting[:], proc(first, second: Field_Wave_Remesh) -> bool {
		return first.tick != second.tick ? first.tick < second.tick : first.position < second.position
	})
	sent := 0
	for remesh in waiting {
		if sent >= limit {
			break
		}
		node := selection[remesh.position]
		chunk := world.chunks[field_node_chunk(node)]
		submit_field_mesh_job(streaming, node, gather_field_grid(world, chunk.coordinate), false, field_node_skirt_faces(index, node), look = gather_field_look_samples(world, chunk.coordinate, waves))
		chunk.dirty, chunk.wave_dirty = false, false
		sent += 1
	}
	return sent
}

// Two rounds, the selected nodes never meshed (not in mesh_revisions,
// read before the node's own submission) first and the rest after
// (0367), so a node edited every frame (a stream's chunk) can never keep
// a hole in the view open. Nearest first within each pass of a round: the
// finest nodes' chunks and meshes take the budget before any coarser
// node, since the ground under the camera waits on 27 chunks a node and a
// coarse node on one job. A node whose skirt faces changed meshes again.
// The waves' remeshes come last, at most
// MAXIMUM_FIELD_WAVE_REMESHES_PER_FRAME of what the frame's cap leaves, so
// a moving surface never holds back a node still unmeshed or edited.
schedule_field_jobs :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node, waves: Field_Wave_Heights = nil) {
	index := make_field_selection_index(selection, context.temp_allocator)
	submissions := 0
	full :: proc(streaming: ^Field_Streaming, submissions: int) -> bool {
		return streaming.pending_jobs >= MAXIMUM_FIELD_PENDING_JOBS || submissions >= MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME
	}
	for never_meshed in ([2]bool{true, false}) {
		for node in selection {
			if node.level != 0 || (node not_in streaming.mesh_revisions) != never_meshed {
				continue
			}
			if !full(streaming, submissions) {
				submissions += schedule_finest_field_mesh(streaming, world, node, field_node_skirt_faces(index, node), waves) ? 1 : 0
			}
		}
		for node in selection {
			if full(streaming, submissions) {
				return
			}
			if node.level == 0 || node in streaming.in_flight || (node not_in streaming.mesh_revisions) != never_meshed {
				continue
			}
			faces := field_node_skirt_faces(index, node)
			if node not_in streaming.mesh_revisions || node in streaming.remesh || field_skirt_faces_changed(streaming, node, faces) {
				delete_key(&streaming.remesh, node)
				grid, coarse_water := gather_coarse_field_grid(world, node)
				submit_field_mesh_job(streaming, node, grid, true, faces, coarse_water = coarse_water)
				submissions += 1
			}
		}
	}
	room := min(MAXIMUM_FIELD_WAVE_REMESHES_PER_FRAME, MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME - submissions, MAXIMUM_FIELD_PENDING_JOBS - streaming.pending_jobs)
	schedule_field_wave_remeshes(streaming, world, selection, index, waves, room)
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
// (held_field_chunk_arrivals), the nodes the viewports' cameras chose
// (empty on a server) and the frame table the cover clears its instances
// by (0311, nil on a server).
Field_Stream_Frame :: struct {
	requested: []Field_Chunk_Coordinate,
	held:      map[Field_Chunk_Coordinate]struct{},
	selection: []Field_Node,
	frames:    ^Frame_Table,
}

// When the frame table's revision moved (0311): a new snapshot of its
// frames, the finest nodes under the changed ones marked
// (mark_cover_frame_changes), the old snapshot freed.
update_cover_frames :: proc(streaming: ^Field_Streaming, frames: ^Frame_Table) {
	if frames.revision == streaming.cover_frames_revision {
		return
	}
	streaming.cover_frames_revision = frames.revision
	snapshot := snapshot_cover_frames(frames)
	mark_cover_frame_changes(streaming, streaming.cover_frames[:], snapshot[:])
	destroy_cover_frames(streaming.cover_frames[:])
	delete(streaming.cover_frames)
	streaming.cover_frames = snapshot
}

// Each frame only in one snapshot, or in both with another pose or other
// cells, marks every meshed finest node whose box, widened by
// COVER_FRAME_MARGIN_METRES, meets its old or its new box.
mark_cover_frame_changes :: proc(streaming: ^Field_Streaming, old, new: []Cover_Frame) {
	Box :: struct {
		minimum, maximum: [3]f64,
	}
	changed := make([dynamic]Box, context.temp_allocator)
	old_index, new_index := 0, 0
	for old_index < len(old) || new_index < len(new) {
		switch {
		case new_index >= len(new) || (old_index < len(old) && old[old_index].frame.id < new[new_index].frame.id):
			append(&changed, Box{old[old_index].minimum, old[old_index].maximum})
			old_index += 1
		case old_index >= len(old) || new[new_index].frame.id < old[old_index].frame.id:
			append(&changed, Box{new[new_index].minimum, new[new_index].maximum})
			new_index += 1
		case:
			before, after := old[old_index], new[new_index]
			if before.frame != after.frame || !slice.equal(before.cells[:], after.cells[:]) {
				append(&changed, Box{before.minimum, before.maximum}, Box{after.minimum, after.maximum})
			}
			old_index += 1
			new_index += 1
		}
	}
	if len(changed) == 0 {
		return
	}
	spacing := streaming.shared.generation.spacing_millimetres
	for node in streaming.mesh_revisions {
		if node.level != 0 {
			continue
		}
		minimum, maximum := field_cover_node_box(node, spacing, COVER_FRAME_MARGIN_METRES)
		for box in changed {
			if cover_boxes_meet(minimum, maximum, box.minimum, box.maximum) {
				streaming.remesh[node] = {}
				break
			}
		}
	}
}

// Main thread, once per frame, before take_current_field_meshes. The
// generated chunks the tick may take go to arrivals; the generation goes
// out before the meshing, so the tick waits on as little as it can. waves
// are the surface waves' heights the finest meshes take (0294), nil for
// none.
update_field_streaming :: proc(streaming: ^Field_Streaming, world: ^Field_World, frame: Field_Stream_Frame, arrivals: ^[dynamic]^Field_Chunk, waves: Field_Wave_Heights = nil) {
	if streaming.shared.cover.on && frame.frames != nil {
		update_cover_frames(streaming, frame.frames)
	}
	mark_edited_coarse_nodes(streaming, world)
	receive_field_chunks(streaming, world, frame, arrivals)
	drop_unselected_field_nodes(streaming, frame.selection)
	schedule_field_chunk_generation(streaming, world, frame)
	schedule_field_jobs(streaming, world, frame.selection, waves)
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
