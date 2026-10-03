package game

import "core:container/queue"
import "core:testing"

// Streaming without worker threads: the test runs the queued jobs itself,
// so the order is fixed.
run_queued_field_jobs :: proc(streaming: ^Field_Streaming) {
	shared := streaming.shared
	for queue.len(shared.jobs) > 0 {
		push_field_result(shared, run_field_job(shared, queue.pop_front(&shared.jobs)))
	}
}

// One finest node over the test planet's surface: its 27 chunks are
// generated, it meshes once they are in, and an edit remeshes it with a
// new revision while the old revision's result is dropped.
@(test)
test_an_edited_field_chunk_remeshes_on_the_next_revision :: proc(t: ^testing.T) {
	planet := make_test_planet()
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	node := field_chunk_node({0, 249, 0})
	selection := []Field_Node{node}
	update_field_streaming(&streaming, &world, selection)
	testing.expect_value(t, streaming.pending_jobs, 27)
	run_queued_field_jobs(&streaming)
	// MAXIMUM_FIELD_GENERATED_PER_FRAME arrive per frame.
	update_field_streaming(&streaming, &world, selection)
	testing.expect_value(t, len(world.chunks), MAXIMUM_FIELD_GENERATED_PER_FRAME)
	testing.expect(t, node not_in streaming.mesh_revisions, "a node waits for its neighbours")
	update_field_streaming(&streaming, &world, selection)
	testing.expect_value(t, len(world.chunks), 27)
	first_revision, meshing := streaming.mesh_revisions[node]
	testing.expect(t, meshing)
	run_queued_field_jobs(&streaming)
	meshes := take_current_field_meshes(&streaming, context.temp_allocator)
	testing.expect_value(t, len(meshes), 1)
	testing.expect(t, len(meshes[0].mesh.indices) > 0, "the node holds the surface")
	destroy_field_mesh_data(meshes[0].mesh)

	// Nothing changed: no new job.
	update_field_streaming(&streaming, &world, selection)
	testing.expect_value(t, streaming.pending_jobs, 0)

	sample := field_chunk_origin(field_node_chunk(node)) + {5, 5, 5}
	testing.expect(t, field_world_set_sample(&world, sample, {MAXIMUM_DENSITY, .Stone, 0}))
	update_field_streaming(&streaming, &world, selection)
	second_revision := streaming.mesh_revisions[node]
	testing.expect(t, second_revision > first_revision)
	push_field_result(streaming.shared, Field_Job_Result{kind = .Mesh, node = node, revision = first_revision, mesh = make_field_mesh_data()})
	streaming.pending_jobs += 1
	run_queued_field_jobs(&streaming)
	meshes = take_current_field_meshes(&streaming, context.temp_allocator)
	testing.expect_value(t, len(meshes), 1)
	testing.expect_value(t, meshes[0].revision, second_revision)
	destroy_field_mesh_data(meshes[0].mesh)
	testing.expect_value(t, streaming.pending_jobs, 0)

	// The node leaves the selection: its chunks unload and it is dropped.
	update_field_streaming(&streaming, &world, {})
	testing.expect_value(t, len(world.chunks), 0)
	testing.expect_value(t, len(streaming.dropped), 1)
}

// A fresh stream spends its first jobs on the chunks of the finest nodes
// under the camera, the nearest node's own chunk first, before any
// coarser node.
@(test)
test_a_fresh_stream_generates_the_finest_chunks_first :: proc(t: ^testing.T) {
	planet := make_test_planet()
	camera := World_Position{0, metres_to_position_units(i64(planet.radius_metres + 40)), 0}
	view := make_field_view(camera, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, TEST_LEVEL_DISTANCES_METRES)
	selection := select_field_nodes(view, context.temp_allocator)
	testing.expect_value(t, selection[0].level, 0)
	streaming := start_field_streaming(TEST_PLANET_SEED, planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES, 0)
	defer stop_field_streaming(&streaming)
	world: Field_World
	defer destroy_field_world(&world)
	update_field_streaming(&streaming, &world, selection)
	jobs := &streaming.shared.jobs
	testing.expect_value(t, queue.len(jobs^), MAXIMUM_FIELD_PENDING_JOBS)
	testing.expect_value(t, queue.get(jobs, 0).node, selection[0])
	wanted := wanted_field_chunks(selection, context.temp_allocator)
	for index in 0 ..< queue.len(jobs^) {
		job := queue.get(jobs, index)
		testing.expectf(t, job.kind == .Generate && field_node_chunk(job.node) in wanted, "job %d is %v of %v", index, job.kind, job.node)
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
	for _ in 0 ..< 3 {
		update_field_streaming(&streaming, &world, selection)
		run_queued_field_jobs(&streaming)
	}
	for result in take_current_field_meshes(&streaming, context.temp_allocator) {
		destroy_field_mesh_data(result.mesh)
	}
	testing.expect_value(t, len(world.chunks), 27)
	taken := 0
	sample := field_chunk_origin(field_node_chunk(node)) + {5, 5, 5}
	for frame in 0 ..< 6 {
		field_world_set_sample(&world, sample, {i8(frame * 10 + 1), .Stone, 0})
		update_field_streaming(&streaming, &world, selection)
		for result in take_current_field_meshes(&streaming, context.temp_allocator) {
			taken += 1
			destroy_field_mesh_data(result.mesh)
		}
		run_queued_field_jobs(&streaming)
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
	settle :: proc(streaming: ^Field_Streaming, world: ^Field_World, selection: []Field_Node) {
		update_field_streaming(streaming, world, selection)
		run_queued_field_jobs(streaming)
		for result in take_current_field_meshes(streaming, context.temp_allocator) {
			destroy_field_mesh_data(result.mesh)
			destroy_field_mesh_data(result.water_mesh)
		}
	}
	same_level := []Field_Node{node, {1, {2, 124, 0}}}
	settle(&streaming, &world, same_level)
	first := streaming.mesh_revisions[node]
	testing.expect(t, .Positive_X not_in streaming.skirt_faces[node])
	settle(&streaming, &world, same_level)
	testing.expect_value(t, streaming.mesh_revisions[node], first)
	merged := []Field_Node{node, {2, {1, 62, 0}}}
	settle(&streaming, &world, merged)
	testing.expect(t, streaming.mesh_revisions[node] > first, "the node meshes again")
	testing.expect(t, .Positive_X in streaming.skirt_faces[node])
}
