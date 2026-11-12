package game

import "core:container/queue"
import "core:fmt"
import "core:slice"
import "core:testing"

// Streaming without worker threads: the test runs the queued jobs itself,
// so the order is fixed.
run_queued_field_jobs :: proc(streaming: ^Field_Streaming) {
	shared := streaming.shared
	for queue.len(shared.jobs) > 0 {
		push_field_result(shared, run_field_job(shared, queue.pop_front(&shared.jobs)))
	}
}

// The chunks of the selection's finest nodes and their shells, in
// coordinate order, in the temp allocator: what a simulated set round
// them would request.
test_field_requests :: proc(selection: []Field_Node) -> []Field_Chunk_Coordinate {
	wanted := make(map[Field_Chunk_Coordinate]struct{}, context.temp_allocator)
	for node in selection {
		if node.level != 0 {
			continue
		}
		for z in i32(-1) ..= 1 {
			for y in i32(-1) ..= 1 {
				for x in i32(-1) ..= 1 {
					wanted[field_node_chunk(node) + {x, y, z}] = {}
				}
			}
		}
	}
	coordinates := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
	for coordinate in wanted {
		append(&coordinates, coordinate)
	}
	slice.sort_by(coordinates[:], field_chunk_coordinate_before)
	return coordinates[:]
}

// One frame of the streaming with the selection's chunks requested, and
// the arrivals inserted after it as the next tick would
// (insert_field_chunk_arrival). Returns the arrivals' count.
stream_test_field_frame :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node) -> int {
	arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
	update_field_streaming(streaming, world, Field_Stream_Frame{requested = test_field_requests(selection), selection = selection}, &arrivals)
	for chunk in arrivals {
		field_world_insert_chunk(world, chunk)
		mark_field_neighbours_dirty(world, chunk.coordinate)
	}
	return len(arrivals)
}

// Frames until no job is pending, the meshes taken and freed.
settle_test_field_stream :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node) {
	for _ in 0 ..< 16 {
		stream_test_field_frame(streaming, world, selection)
		run_queued_field_jobs(streaming)
		for result in take_current_field_meshes(streaming, context.temp_allocator) {
			destroy_field_mesh_data(result.mesh)
			destroy_field_mesh_data(result.water_mesh)
		}
		if streaming.pending_jobs == 0 && queue.len(streaming.shared.jobs) == 0 {
			return
		}
	}
}

// One finest node over the test planet's surface: its 27 chunks are
// generated and handed back as arrivals, MAXIMUM_FIELD_GENERATED_PER_FRAME
// a frame; the node meshes from a generated grid first and from its
// chunks once they are all in; an edit remeshes it with a new revision
// while the old revision's result is dropped; leaving the selection drops
// it and leaves the chunks, which are the simulation's.
@(test) // slow
test_an_edited_field_chunk_remeshes_on_the_next_revision :: proc(t: ^testing.T) {
	planet := make_test_planet()
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	node := field_chunk_node({0, 249, 0})
	selection := []Field_Node{node}
	testing.expect_value(t, stream_test_field_frame(&streaming, &world, selection), 0)
	testing.expect_value(t, streaming.pending_jobs, 27 + 1)
	testing.expect(t, node in streaming.finest_generated, "the node meshes from a generated grid while its chunks are missing")
	run_queued_field_jobs(&streaming)
	testing.expect_value(t, stream_test_field_frame(&streaming, &world, selection), MAXIMUM_FIELD_GENERATED_PER_FRAME)
	testing.expect_value(t, stream_test_field_frame(&streaming, &world, selection), 27 - MAXIMUM_FIELD_GENERATED_PER_FRAME)
	testing.expect_value(t, len(world.chunks), 27)
	settle_test_field_stream(&streaming, &world, selection)
	testing.expect(t, node not_in streaming.finest_generated, "the node meshed from its chunks")
	first_revision := streaming.mesh_revisions[node]

	// Nothing changed: no new job.
	stream_test_field_frame(&streaming, &world, selection)
	testing.expect_value(t, streaming.pending_jobs, 0)

	sample := field_chunk_origin(field_node_chunk(node)) + {5, 5, 5}
	testing.expect(t, field_world_set_sample(&world, sample, {MAXIMUM_DENSITY, .Stone, 0}))
	stream_test_field_frame(&streaming, &world, selection)
	second_revision := streaming.mesh_revisions[node]
	testing.expect(t, second_revision > first_revision)
	push_field_result(streaming.shared, Field_Job_Result{kind = .Mesh, node = node, revision = first_revision, mesh = make_field_mesh_data()})
	streaming.pending_jobs += 1
	run_queued_field_jobs(&streaming)
	meshes := take_current_field_meshes(&streaming, context.temp_allocator)
	testing.expect_value(t, len(meshes), 1)
	testing.expect_value(t, meshes[0].revision, second_revision)
	testing.expect(t, len(meshes[0].mesh.indices) > 0, "the node holds the surface")
	destroy_field_mesh_data(meshes[0].mesh)
	destroy_field_mesh_data(meshes[0].water_mesh)
	testing.expect_value(t, streaming.pending_jobs, 0)

	// The node leaves the selection: it is dropped, the chunks stay.
	stream_test_field_frame(&streaming, &world, {})
	testing.expect_value(t, len(world.chunks), 27)
	testing.expect_value(t, len(streaming.dropped), 1)
}

// A fresh stream spends its first jobs on the requested chunks in the
// order given, before any mesh.
@(test) // slow
test_a_fresh_stream_generates_the_requested_chunks_first :: proc(t: ^testing.T) {
	planet := make_test_planet()
	camera := World_Position{0, metres_to_position_units(i64(planet.radius_metres + 40)), 0}
	view := make_field_view(camera, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, TEST_LEVEL_DISTANCES_METRES)
	selection := select_field_nodes(view, context.temp_allocator)
	testing.expect_value(t, selection[0].level, 0)
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	requested := test_field_requests(selection[:1])
	arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
	update_field_streaming(&streaming, &world, Field_Stream_Frame{requested = requested, selection = selection}, &arrivals)
	jobs := &streaming.shared.jobs
	testing.expect_value(t, queue.len(jobs^), MAXIMUM_FIELD_PENDING_JOBS)
	for coordinate, index in requested {
		job := queue.get(jobs, index)
		testing.expectf(t, job.kind == .Generate && field_node_chunk(job.node) == coordinate, "job %d is %v of %v", index, job.kind, job.node)
	}
	testing.expect_value(t, queue.get(jobs, len(requested)).kind, Field_Job_Kind.Mesh)
	run_queued_field_jobs(&streaming)
	for result in take_field_results(streaming.shared, .Generate, MAXIMUM_FIELD_PENDING_JOBS, context.temp_allocator) {
		free_field_job_result(result)
	}
	for result in take_current_field_meshes(&streaming, context.temp_allocator) {
		destroy_field_mesh_data(result.mesh)
		destroy_field_mesh_data(result.water_mesh)
	}
}

// A chunk edited every frame (a held brush) still gets its mesh: the
// worker's result lands after the frame's scheduling, as an asynchronous
// worker's does, and the node is not submitted again while its job is in
// flight, so the result is current when it is taken.
@(test) // slow
test_a_chunk_edited_every_frame_still_meshes :: proc(t: ^testing.T) {
	planet := make_test_planet()
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	node := field_chunk_node({0, 249, 0})
	selection := []Field_Node{node}
	settle_test_field_stream(&streaming, &world, selection)
	testing.expect_value(t, len(world.chunks), 27)
	taken := 0
	sample := field_chunk_origin(field_node_chunk(node)) + {5, 5, 5}
	for frame in 0 ..< 6 {
		field_world_set_sample(&world, sample, {i8(frame * 10 + 1), .Stone, 0})
		stream_test_field_frame(&streaming, &world, selection)
		for result in take_current_field_meshes(&streaming, context.temp_allocator) {
			taken += 1
			destroy_field_mesh_data(result.mesh)
			destroy_field_mesh_data(result.water_mesh)
		}
		run_queued_field_jobs(&streaming)
	}
	for result in take_current_field_meshes(&streaming, context.temp_allocator) {
		destroy_field_mesh_data(result.mesh)
		destroy_field_mesh_data(result.water_mesh)
	}
	testing.expect(t, taken >= 2, "the edits land as results while the chunk stays dirty")
	testing.expect(t, world.chunks[field_node_chunk(node)].dirty, "the latest edit waits for the job in flight")
}

// A coarse node whose neighbour of its level merges into a coarser node
// meshes again with a skirt on that face, so no seam opens; an unchanged
// selection submits nothing.
@(test)
test_a_node_whose_neighbour_changes_level_meshes_again :: proc(t: ^testing.T) {
	planet := make_test_planet()
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	node := Field_Node{1, {1, 124, 0}}
	same_level := []Field_Node{node, {1, {2, 124, 0}}}
	settle_test_field_stream(&streaming, &world, same_level)
	first := streaming.mesh_revisions[node]
	testing.expect(t, .Positive_X not_in streaming.skirt_faces[node].flaps)
	settle_test_field_stream(&streaming, &world, same_level)
	testing.expect_value(t, streaming.mesh_revisions[node], first)
	merged := []Field_Node{node, {2, {1, 62, 0}}}
	settle_test_field_stream(&streaming, &world, merged)
	testing.expect(t, streaming.mesh_revisions[node] > first, "the node meshes again")
	testing.expect(t, .Positive_X in streaming.skirt_faces[node].flaps)
}

// A coarse node whose neighbour of its level splits into finer nodes
// meshes again with a curtain on that face (0321).
@(test)
test_a_node_whose_neighbour_splits_meshes_again :: proc(t: ^testing.T) {
	planet := make_test_planet()
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	node := Field_Node{2, {0, 62, 0}}
	same_level := []Field_Node{node, {2, {1, 62, 0}}}
	settle_test_field_stream(&streaming, &world, same_level)
	first := streaming.mesh_revisions[node]
	testing.expect(t, .Positive_X not_in streaming.skirt_faces[node].curtains)
	split := []Field_Node{node, {1, {2, 124, 0}}}
	settle_test_field_stream(&streaming, &world, split)
	testing.expect(t, streaming.mesh_revisions[node] > first, "the node meshes again")
	testing.expect(t, .Positive_X in streaming.skirt_faces[node].curtains)
}

// Two eyes far apart: one selection holds the finest nodes under both,
// and no two of its nodes overlap (0179, Field_View.more_cameras).
@(test)
test_one_selection_serves_two_viewports :: proc(t: ^testing.T) {
	planet := make_test_planet()
	radius := metres_to_position_units(i64(planet.radius_metres + 2))
	first := World_Position{0, radius, 0}
	second := World_Position{0, 0, radius}
	view := make_field_view(first, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, TEST_LEVEL_DISTANCES_METRES)
	others := []World_Position{second}
	view.more_cameras = others
	selection := select_field_nodes(view, context.temp_allocator)
	finest_near :: proc(selection: []Field_Node, eye: World_Position) -> bool {
		for node in selection {
			if node.level == 0 && box_distance_squared(field_node_box(node, DEFAULT_SAMPLE_SPACING_MILLIMETRES), eye) == 0 {
				return true
			}
		}
		return false
	}
	testing.expect(t, finest_near(selection, first), "a finest node holds the first eye")
	testing.expect(t, finest_near(selection, second), "a finest node holds the second eye")
	for node, index in selection {
		for other in selection[index + 1:] {
			fine, coarse := node, other
			if fine.level > coarse.level {
				fine, coarse = coarse, fine
			}
			shift := uint(coarse.level - fine.level)
			inside := Field_Node{coarse.level, {fine.coordinate.x >> shift, fine.coordinate.y >> shift, fine.coordinate.z >> shift}} == coarse
			testing.expectf(t, !inside, "%v overlaps %v", node, other)
		}
	}
}

// Work item 0343: the selection at a 256 m view holds no eighth level node
// and nothing past 256 m, and the streaming drops exactly the meshed nodes
// of the 1024 m selection the shorter one left out, keeping the shared.
@(test)
test_a_shorter_view_drops_the_far_nodes :: proc(t: ^testing.T) {
	planet := make_test_planet()
	eye := World_Position{0, metres_to_position_units(i64(planet.radius_metres + 2)), 0}
	config, _ := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	field_view := config.field_view
	selection_at :: proc(eye: World_Position, planet: Planet, field_view: Field_View_Config, view_distance_metres: int) -> []Field_Node {
		view := make_field_view(eye, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, field_view_level_distances(field_view, view_distance_metres))
		return select_field_nodes(view, context.temp_allocator)
	}
	far := selection_at(eye, planet, field_view, 1024)
	near := selection_at(eye, planet, field_view, 256)
	testing.expectf(t, len(near) < len(far), "%d nodes at 256 m against %d at 1024 m", len(near), len(far))
	reach := metres_to_position_units(256)
	near_set := make(map[Field_Node]struct{}, context.temp_allocator)
	for node in near {
		near_set[node] = {}
		testing.expectf(t, node.level < FIELD_COARSEST_LEVEL, "%v is an eighth level node at 256 m", node)
		testing.expectf(t, box_distance_squared(field_node_box(node, DEFAULT_SAMPLE_SPACING_MILLIMETRES), eye) <= reach * reach, "%v lies past 256 m", node)
	}
	far_has_coarsest := false
	for node in far {
		far_has_coarsest ||= node.level == FIELD_COARSEST_LEVEL
	}
	testing.expect(t, far_has_coarsest, "the 1024 m selection holds eighth level nodes")
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	for node in far {
		streaming.mesh_revisions[node] = 1
	}
	drop_unselected_field_nodes(&streaming, near)
	dropped := make(map[Field_Node]struct{}, context.temp_allocator)
	for node in streaming.dropped {
		dropped[node] = {}
	}
	testing.expect_value(t, len(dropped), len(streaming.dropped))
	missing := 0
	for node in far {
		if node in near_set {
			testing.expectf(t, node in streaming.mesh_revisions, "the shared %v keeps its revision", node)
			testing.expectf(t, node not_in dropped, "the shared %v is dropped", node)
		} else {
			missing += 1
			testing.expectf(t, node in dropped, "%v left the selection but is not dropped", node)
		}
	}
	testing.expect_value(t, len(dropped), missing)
	free_all(context.temp_allocator)
}

// The waves' budget (0294 fix round, 2026-11-06): 64 meshed nodes whose
// chunks only the waves marked and ten nodes never meshed, farther in the
// selection. The unmeshed take the frame's cap first; the waves' remeshes
// take at most two a frame of what is left, and every chunk marked meshes
// in time.
@(test) // slow
test_the_waves_remesh_after_unmeshed_nodes_two_a_frame :: proc(t: ^testing.T) {
	streaming := start_field_streaming(TEST_PLANET_SEED, make_test_planet(), DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	selection := make([dynamic]Field_Node, context.temp_allocator)
	for z in i32(0) ..< 6 {
		for y in i32(0) ..< 6 {
			for x in i32(0) ..< 6 {
				chunk := new(Field_Chunk)
				chunk.coordinate = {x, y, z}
				field_world_insert_chunk(&world, chunk)
				chunk.dirty = false
				if x >= 1 && x <= 4 && y >= 1 && y <= 4 && z >= 1 && z <= 4 {
					chunk.wave_dirty = true
					node := field_chunk_node(chunk.coordinate)
					streaming.mesh_revisions[node] = 1
					append(&selection, node)
				}
			}
		}
	}
	testing.expect_value(t, len(selection), 64)
	unmeshed := make([dynamic]Field_Node, context.temp_allocator)
	for index in i32(0) ..< 10 {
		node := field_chunk_node({100 + 2 * index, 0, 0})
		append(&selection, node)
		append(&unmeshed, node)
	}
	waiting :: proc(world: ^Field_World) -> int {
		count := 0
		for _, chunk in world.chunks {
			count += chunk.wave_dirty ? 1 : 0
		}
		return count
	}
	submitted :: proc(streaming: ^Field_Streaming, nodes: []Field_Node) -> int {
		count := 0
		for node in nodes {
			count += node in streaming.in_flight ? 1 : 0
		}
		return count
	}
	expected := [?][2]int{{8, 0}, {10, 2}, {10, 4}}
	for counts, frame in expected {
		schedule_field_jobs(&streaming, &world, selection[:])
		testing.expectf(t, submitted(&streaming, unmeshed[:]) == counts[0], "frame %d: %d unmeshed nodes out", frame, submitted(&streaming, unmeshed[:]))
		testing.expectf(t, 64 - waiting(&world) == counts[1], "frame %d: %d wave remeshes out", frame, 64 - waiting(&world))
	}
	for _ in 0 ..< 64 {
		schedule_field_jobs(&streaming, &world, selection[:])
		run_queued_field_jobs(&streaming)
		for result in take_current_field_meshes(&streaming, context.temp_allocator) {
			destroy_field_mesh_data(result.mesh)
			destroy_field_mesh_data(result.water_mesh)
		}
		if waiting(&world) == 0 {
			break
		}
	}
	testing.expect_value(t, waiting(&world), 0)
	free_all(context.temp_allocator)
}

// Oldest mark first (0294's second fix round): six meshed nodes in a row,
// the five nearest marked by the waves every frame (as a stream's mouth
// keeps them), the sixth once. With the jobs run every frame, two wave
// remeshes a frame and six nodes marked, no mark waits more than three
// frames (six over two), the sixth's included.
@(test) // slow
test_the_waves_remesh_the_oldest_mark_first :: proc(t: ^testing.T) {
	streaming := start_field_streaming(TEST_PLANET_SEED, make_test_planet(), DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	for z in i32(0) ..< 3 {
		for y in i32(0) ..< 3 {
			for x in i32(0) ..< 8 {
				chunk := new(Field_Chunk)
				chunk.coordinate = {x, y, z}
				field_world_insert_chunk(&world, chunk)
				chunk.dirty = false
			}
		}
	}
	selection: [6]Field_Node
	chunks: [6]^Field_Chunk
	for slot in 0 ..< 6 {
		coordinate := Field_Chunk_Coordinate{i32(slot) + 1, 1, 1}
		selection[slot] = field_chunk_node(coordinate)
		chunks[slot] = world.chunks[coordinate]
		streaming.mesh_revisions[selection[slot]] = 1
	}
	BOUND :: 3
	marked_at: [6]int
	longest: [6]int
	sixth_meshed := -1
	for frame in 1 ..= 200 {
		for slot in 0 ..< 6 {
			if (slot < 5 || frame == 1) && !chunks[slot].wave_dirty {
				chunks[slot].wave_dirty, chunks[slot].wave_dirty_tick = true, u64(frame)
				marked_at[slot] = frame
			}
		}
		schedule_field_jobs(&streaming, &world, selection[:])
		run_queued_field_jobs(&streaming)
		for result in take_current_field_meshes(&streaming, context.temp_allocator) {
			destroy_field_mesh_data(result.mesh)
			destroy_field_mesh_data(result.water_mesh)
		}
		for slot in 0 ..< 6 {
			if chunks[slot].wave_dirty {
				testing.expectf(t, frame - marked_at[slot] < BOUND, "frame %d: node %d waits since frame %d", frame, slot, marked_at[slot])
			} else if marked_at[slot] > 0 {
				longest[slot] = max(longest[slot], frame - marked_at[slot] + 1)
				if slot == 5 && sixth_meshed < 0 {
					sixth_meshed = frame
				}
				marked_at[slot] = 0
			}
		}
		free_all(context.temp_allocator)
	}
	fmt.printfln("0294: the longest wave waits in frames, nearest first: %v; the sixth meshed in frame %d", longest, sixth_meshed)
	testing.expect(t, sixth_meshed >= 1 && sixth_meshed <= BOUND, "the node marked once is meshed in time")
	for slot in 0 ..< 6 {
		testing.expect(t, longest[slot] >= 1 && longest[slot] <= BOUND)
	}
}

// Frames over the selection with the frame table and no chunk requested,
// so the finest nodes mesh from generated grids, until no job is pending;
// the meshes and their cover taken and freed (0311).
settle_test_cover_stream :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node, frames: ^Frame_Table) {
	for _ in 0 ..< 16 {
		arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
		update_field_streaming(streaming, world, Field_Stream_Frame{selection = selection, frames = frames}, &arrivals)
		run_queued_field_jobs(streaming)
		for result in take_current_field_meshes(streaming, context.temp_allocator) {
			free_field_job_result(result)
		}
		if streaming.pending_jobs == 0 && queue.len(streaming.shared.jobs) == 0 {
			return
		}
	}
}

// 0311: a frame added over a meshed finest node marks it, and its next
// job carries the frame; a node 200 m away is not marked; a revision
// without a change marks none.
@(test) // slow
test_a_frame_change_remeshes_the_nodes_under_it :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	direction := cover_test_direction(spots[0].latitude, spots[0].longitude)
	node := cover_test_surface_node(generation, direction, 0, 0)
	far := cover_test_surface_node(generation, direction, 200, 0)
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, planet, 1000, 0, COVER_TEST_ROW)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	table: Frame_Table
	defer destroy_frame_table(&table)
	selection := []Field_Node{node, far}
	settle_test_cover_stream(&streaming, &world, selection, &table)
	testing.expect(t, node in streaming.mesh_revisions && far in streaming.mesh_revisions, "both nodes meshed")
	testing.expect_value(t, len(streaming.remesh), 0)

	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	_, _, mesh := cover_test_grid_cover(generation, planet, grid)
	frame := cover_test_add_block(&table, grid, mesh)
	update_cover_frames(&streaming, &table)
	testing.expect(t, node in streaming.remesh, "the node under the frame is marked")
	testing.expect(t, far not_in streaming.remesh, "the node 200 m away is not")

	arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
	update_field_streaming(&streaming, &world, Field_Stream_Frame{selection = selection, frames = &table}, &arrivals)
	jobs := &streaming.shared.jobs
	testing.expect_value(t, queue.len(jobs^), 1)
	if queue.len(jobs^) == 1 {
		job := queue.get(jobs, 0)
		testing.expect_value(t, job.node, node)
		testing.expect_value(t, len(job.cover_frames), 1)
		if len(job.cover_frames) == 1 {
			testing.expect_value(t, job.cover_frames[0].frame.id, frame)
			testing.expect_value(t, len(job.cover_frames[0].cells), 64)
		}
	}
	settle_test_cover_stream(&streaming, &world, selection, &table)
	testing.expect_value(t, len(streaming.remesh), 0)

	// The cell occupied again by the same occupant: the revision moves,
	// the frames do not.
	revision := table.revision
	occupy_frame_cell(&table, frame, {0, 0, 0}, {handle = 1})
	testing.expect(t, table.revision > revision, "the revision moved")
	update_cover_frames(&streaming, &table)
	testing.expect_value(t, len(streaming.remesh), 0)
}

// 0311: a worker's finest mesh job places the cover place_field_cover
// places on the same grid; a level 1 job carries none.
@(test) // slow
test_a_worker_job_carries_the_cover :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	spots := COVER_TEST_SPOTS
	node := cover_test_surface_node(generation, cover_test_direction(spots[0].latitude, spots[0].longitude), 0, 0)
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, planet, 1000, 0, COVER_TEST_ROW)
	defer stop_field_streaming(&streaming)
	finest := run_field_job(streaming.shared, Field_Job{kind = .Mesh, node = node, grid = new(Field_Grid), generate = true})
	defer free_field_job_result(finest)
	expected, _ := cover_test_node_cover(generation, planet, node)
	total := 0
	for kind, index in finest.cover.kinds {
		testing.expect(t, slice.equal(kind.instances[:], expected.kinds[index].instances[:]), "the worker's cover differs")
		testing.expect_value(t, kind.rank_counts, expected.kinds[index].rank_counts)
		total += len(kind.instances)
	}
	testing.expect(t, total > 1000, "the meadow node holds a cover")
	coarse := Field_Node{1, {node.coordinate.x >> 1, node.coordinate.y >> 1, node.coordinate.z >> 1}}
	coarse_result := run_field_job(streaming.shared, Field_Job{kind = .Mesh, node = coarse, grid = new(Field_Grid), generate = true})
	defer free_field_job_result(coarse_result)
	testing.expect(t, len(coarse_result.mesh.indices) > 0, "the level 1 node holds the surface")
	testing.expect_value(t, cover_test_count(coarse_result.cover), 0)
}

// 0311 fix round: a finest node over the arch nearest the home, 16 m
// before its centre, meshed from a generated grid (no chunk loaded, as
// gather_coarse_field_grid leaves it) gives the same cover as meshed from
// its 27 gathered chunks: both measure the cuts, so the carved ground
// under the arch carries none either way.
@(test) // slow
test_a_carved_node_gives_the_same_cover_from_either_grid :: proc(t: ^testing.T) {
	planet, generation := cover_test_setup()
	site := test_nearest_carving_site(generation, .Arch)
	direction, _ := normalize_fixed(site.centre)
	forward := tangent_of(direction, {UNIT_VECTOR_ONE, 0, 0})
	point := test_sphere_point(generation, direction, forward, fixed_cross(forward, direction), -16, 0)
	node := test_surface_node(test_radial_position(generation, point, uncratered_column(generation, point).relief), 1000, 0)
	streaming := start_field_streaming(DEFAULT_WORLD_SEED, planet, 1000, 0, COVER_TEST_ROW)
	defer stop_field_streaming(&streaming)
	generated := run_field_job(streaming.shared, Field_Job{kind = .Mesh, node = node, generate = true})
	defer free_field_job_result(generated)
	world: Field_World
	defer destroy_field_world(&world)
	world.water_planet = make_field_water_planet(DEFAULT_WORLD_SEED, planet, 1000)
	coordinate := field_node_chunk(node)
	for z in i32(-1) ..= 1 {
		for y in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				chunk := new(Field_Chunk)
				generate_field_chunk(DEFAULT_WORLD_SEED, planet, 1000, coordinate + {x, y, z}, chunk, crater_overlay = true)
				field_world_insert_chunk(&world, chunk)
			}
		}
	}
	gathered := run_field_job(streaming.shared, Field_Job{kind = .Mesh, node = node, grid = gather_field_grid(&world, coordinate), look = gather_field_look_samples(&world, coordinate)})
	defer free_field_job_result(gathered)
	for kind, index in planet.cover.kinds {
		from_grid, from_chunks := generated.cover.kinds[index].instances[:], gathered.cover.kinds[index].instances[:]
		testing.expectf(t, slice.equal(from_grid, from_chunks), "%s: %d instances from the generated grid, %d from the chunks", kind.id, len(from_grid), len(from_chunks))
	}
	// The carving cuts cover here: unmeasured, the generated grid would
	// carry more.
	grid := new(Field_Grid, context.temp_allocator)
	generate_field_grid(generation, node, grid)
	unmeasured: Field_Cover_Data
	mesh_field_grid(grid, planet.palette, 1000, {}, context.temp_allocator, make_field_ground_look(generation, planet), false, &unmeasured, streaming.shared.cover)
	testing.expectf(t, cover_test_count(unmeasured) > cover_test_count(gathered.cover) && cover_test_count(gathered.cover) > 1000, "%d instances unmeasured against %d measured", cover_test_count(unmeasured), cover_test_count(gathered.cover))
}

// The nodes of the mesh jobs waiting on the workers, in order.
queued_field_mesh_nodes :: proc(streaming: ^Field_Streaming) -> []Field_Node {
	nodes := make([dynamic]Field_Node, context.temp_allocator)
	for position in 0 ..< queue.len(streaming.shared.jobs) {
		if job := queue.get(&streaming.shared.jobs, position); job.kind == .Mesh {
			append(&nodes, job.node)
		}
	}
	return nodes[:]
}

// Work item 0367 (B2): a node never meshed goes before any remesh. Eight
// meshed finest nodes marked to mesh again, ahead of a coarse node never
// meshed in the selection: the frame's jobs hold the coarse node and
// seven of the finest, and the eighth waits for the next frame. No job
// runs.
@(test)
test_a_never_meshed_node_goes_before_a_remesh :: proc(t: ^testing.T) {
	streaming := start_field_streaming(TEST_PLANET_SEED, make_test_planet(), DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	selection := make([dynamic]Field_Node, context.temp_allocator)
	for x in i32(0) ..< MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME {
		node := field_chunk_node({x, 249, 0})
		append(&selection, node)
		streaming.next_revision += 1
		streaming.mesh_revisions[node] = streaming.next_revision
		streaming.finest_generated[node] = {}
		streaming.remesh[node] = {}
	}
	coarse := Field_Node{level = 1, coordinate = {10, 124, 10}}
	append(&selection, coarse)
	schedule_field_jobs(&streaming, &world, selection[:])
	sent := queued_field_mesh_nodes(&streaming)
	testing.expect_value(t, len(sent), MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME)
	testing.expect(t, slice.contains(sent, coarse), "the never meshed coarse node is sent")
	waiting := selection[MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME - 1]
	testing.expect(t, !slice.contains(sent, waiting) && waiting in streaming.remesh, "the last finest remesh waits")
	schedule_field_jobs(&streaming, &world, selection[:])
	sent = queued_field_mesh_nodes(&streaming)
	testing.expect_value(t, len(sent), MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME + 1)
	if len(sent) == MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME + 1 {
		testing.expect_value(t, sent[MAXIMUM_FIELD_MESH_SUBMISSIONS_PER_FRAME], waiting)
	}
}

// Work item 0344, the shore world: a finest node meshed from its chunks
// sends the look's copy with a grid whose water is left zero, and the
// worker's water mesh is the one the look gives on the main thread; a
// finest node whose +x neighbour is not loaded sends the coarse water
// instead; a job left queued is freed with its copies when the streaming
// stops.
@(test)
test_a_finest_mesh_job_carries_the_look_to_the_worker :: proc(t: ^testing.T) {
	world, planet, _, finest := make_shore_look_test_world()
	defer destroy_field_world(&world)
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, 1000, 0)
	defer stop_field_streaming(&streaming)
	shared := streaming.shared
	testing.expect(t, schedule_finest_field_mesh(&streaming, &world, field_chunk_node(finest), {}), "the shore node is sent")
	testing.expect_value(t, queue.len(shared.jobs), 1)
	if queue.len(shared.jobs) == 1 {
		job := queue.pop_front(&shared.jobs)
		testing.expect(t, job.look != nil && job.coarse_water == nil, "the job carries the look's copy")
		testing.expect(t, slice.all_of(job.grid.water[:], 0), "the gather leaves the water zero")
		result := run_field_job(shared, job)
		defer free_field_job_result(result)
		testing.expect(t, mesh_data_equal(result.water_mesh, mesh_field_water_grid(look_test_grid(&world, finest), planet.palette, 1000, context.temp_allocator)), "the worker's water mesh is the look's")
	}
	testing.expect(t, schedule_finest_field_mesh(&streaming, &world, field_chunk_node(finest + {1, 0, 0}), {}), "the node beside the set's edge is sent")
	testing.expect_value(t, queue.len(shared.jobs), 1)
	if queue.len(shared.jobs) == 1 {
		job := queue.pop_front(&shared.jobs)
		testing.expect(t, job.coarse_water != nil && job.look == nil, "the job carries the coarse water")
		free_field_job_copies(job)
	}
	testing.expect(t, schedule_finest_field_mesh(&streaming, &world, field_chunk_node(finest - {1, 0, 0}), {}), "the node left queued is sent")
	testing.expect_value(t, queue.len(shared.jobs), 1)
}
