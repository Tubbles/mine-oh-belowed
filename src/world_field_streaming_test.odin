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
@(test)
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
@(test)
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
@(test)
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
	testing.expect(t, .Positive_X not_in streaming.skirt_faces[node])
	settle_test_field_stream(&streaming, &world, same_level)
	testing.expect_value(t, streaming.mesh_revisions[node], first)
	merged := []Field_Node{node, {2, {1, 62, 0}}}
	settle_test_field_stream(&streaming, &world, merged)
	testing.expect(t, streaming.mesh_revisions[node] > first, "the node meshes again")
	testing.expect(t, .Positive_X in streaming.skirt_faces[node])
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

// The waves' budget (0294 fix round, 2026-11-06): 64 meshed nodes whose
// chunks only the waves marked and ten nodes never meshed, farther in the
// selection. The unmeshed take the frame's cap first; the waves' remeshes
// take at most two a frame of what is left, and every chunk marked meshes
// in time.
@(test)
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
@(test)
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
