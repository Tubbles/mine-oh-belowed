package game

import "core:log"
import "core:slice"
import "core:testing"
import "core:time"

TEST_WORKER_COUNT :: 4
// Upper bound for waiting on workers, so that a lost job fails the test
// instead of hanging it.
TEST_STREAMING_TIMEOUT :: 120 * time.Second

// Chunks this high are all air, so the jobs are cheap and only the queue
// is under test.
@(test)
test_job_queue_hands_back_every_job_once :: proc(t: ^testing.T) {
	JOB_COUNT :: 400
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	streaming := start_chunk_streaming(&generator, make_test_registry(), false, TEST_WORKER_COUNT)
	defer stop_chunk_streaming(&streaming)
	for index in i32(0) ..< JOB_COUNT {
		submit_job(&streaming.shared.jobs, Chunk_Job{kind = .Generate, coordinate = {index % 20, 10, index / 20}})
	}
	seen: map[Chunk_Coordinate]int
	defer delete(seen)
	received := 0
	start := time.tick_now()
	for received < JOB_COUNT && time.tick_since(start) < TEST_STREAMING_TIMEOUT {
		for result in take_generated_results(&streaming.shared.jobs, 64, context.temp_allocator) {
			seen[result.coordinate] += 1
			received += 1
			free_job_result(result)
		}
		time.sleep(time.Millisecond)
	}
	testing.expect_value(t, received, JOB_COUNT)
	testing.expect_value(t, len(seen), JOB_COUNT)
	for coordinate, count in seen {
		testing.expectf(t, count == 1, "chunk %v came back %d times", coordinate, count)
	}
	time.sleep(10 * time.Millisecond)
	testing.expect_value(t, len(take_generated_results(&streaming.shared.jobs, 64, context.temp_allocator)), 0)
}

Stream_Counts :: struct {
	meshes:           int,
	non_empty_meshes: int,
}

// The load volume around the camera in coordinate order, as the simulated
// chunk set requests it for one player. In the temp allocator.
test_requested_volume :: proc(camera_chunk: Chunk_Coordinate) -> []Chunk_Coordinate {
	requested := load_volume_offsets(context.temp_allocator)
	for &coordinate in requested {
		coordinate += camera_chunk
	}
	slice.sort_by(requested, chunk_coordinate_before)
	return requested
}

// What the simulated chunk set's tick does to the chunks outside the
// requested volume. Returns them, in the temp allocator.
unload_test_chunks_outside :: proc(world: ^World, requested: []Chunk_Coordinate) -> []Chunk_Coordinate {
	leaving := make([dynamic]Chunk_Coordinate, context.temp_allocator)
	for coordinate in world.chunks {
		if _, found := slice.binary_search_by(requested, coordinate, chunk_coordinate_order); !found {
			append(&leaving, coordinate)
		}
	}
	for coordinate in leaving {
		store_modified_chunk(world, world.chunks[coordinate])
		free(world.chunks[coordinate])
		delete_key(&world.chunks, coordinate)
	}
	return leaving[:]
}

// Runs the main thread side of streaming until nothing is pending and every
// chunk of the load volume is loaded and meshed. The arrivals go into the
// world as the tick takes them (insert_chunk_arrival).
stream_until_settled :: proc(t: ^testing.T, streaming: ^Chunk_Streaming, world: ^World, records: ^Game_Records, camera_chunk: Chunk_Coordinate) -> Stream_Counts {
	counts: Stream_Counts
	start := time.tick_now()
	requested := test_requested_volume(camera_chunk)
	unloaded := unload_test_chunks_outside(world, requested)
	for time.tick_since(start) < TEST_STREAMING_TIMEOUT {
		arrivals := make([dynamic]Chunk_Job_Result, context.temp_allocator)
		update_chunk_streaming(streaming, world, Chunk_Stream_Frame{requested = requested, unloaded = unloaded, camera_chunk = camera_chunk}, &arrivals)
		unloaded = nil
		for result in arrivals {
			insert_chunk_arrival(world, records, streaming.shared.registry, streaming.shared.generator, result)
		}
		for result in take_current_meshes(streaming, MAXIMUM_MESH_UPLOADS_PER_FRAME, context.temp_allocator) {
			counts.meshes += 1
			counts.non_empty_meshes += len(result.mesh.parts) > 0 ? 1 : 0
			destroy_chunk_mesh_data(result.mesh)
		}
		if streaming.pending_jobs == 0 && volume_settled(streaming, world, camera_chunk) {
			return counts
		}
		time.sleep(time.Millisecond)
	}
	testing.fail_now(t, "streaming did not settle")
}

volume_settled :: proc(streaming: ^Chunk_Streaming, world: ^World, camera_chunk: Chunk_Coordinate) -> bool {
	for offset in streaming.offsets {
		chunk := world.chunks[camera_chunk + offset] or_else nil
		if chunk == nil || chunk.dirty {
			return false
		}
	}
	return true
}

@(test)
test_streaming_loads_meshes_and_unloads :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	world: World
	records: Game_Records
	defer destroy_world(&world)
	defer destroy_game_records(&records)
	streaming := start_chunk_streaming(&generator, make_test_registry(), true, TEST_WORKER_COUNT)
	defer stop_chunk_streaming(&streaming)
	start := time.tick_now()
	counts := stream_until_settled(t, &streaming, &world, &records, {0, 1, 0})
	elapsed := time.tick_since(start)
	testing.expect_value(t, len(world.chunks), len(streaming.offsets))
	testing.expect(t, counts.meshes >= len(streaming.offsets))
	testing.expect(t, len(world.veins) > 0)
	log.infof("streamed %d chunks (%d meshes, %d non empty) with %d workers in %v, %d veins", len(world.chunks), counts.meshes, counts.non_empty_meshes, TEST_WORKER_COUNT, elapsed, len(world.veins))
	moved := Chunk_Coordinate{3, 1, 0}
	stream_until_settled(t, &streaming, &world, &records, moved)
	for coordinate in world.chunks {
		testing.expect(t, within_radius(moved, coordinate, LOAD_RADIUS_HORIZONTAL, LOAD_RADIUS_VERTICAL))
	}
	testing.expect(t, Chunk_Coordinate{-LOAD_RADIUS_HORIZONTAL, 1, 0} not_in world.chunks)
}

// A chunk arriving next to an already meshed one marks it for a remesh, so
// the seam between them closes.
@(test)
test_arriving_neighbour_marks_border_chunk_dirty :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	world := make_test_world({{0, 0, 0}})
	records: Game_Records
	world.chunks[{0, 0, 0}].dirty = false
	neighbour := new(Chunk)
	neighbour.coordinate = {1, 0, 0}
	chunk_set_block(neighbour, {0, 0, 0}, TEST_STONE)
	insert_generated_chunk(&world, &records, Chunk_Job_Result{kind = .Generate, coordinate = {1, 0, 0}, chunk = neighbour})
	testing.expect(t, world.chunks[{0, 0, 0}].dirty)
}

@(test)
test_load_volume_offsets_nearest_first :: proc(t: ^testing.T) {
	offsets := load_volume_offsets(context.temp_allocator)
	testing.expect_value(t, len(offsets), (2 * LOAD_RADIUS_HORIZONTAL + 1) * (2 * LOAD_RADIUS_HORIZONTAL + 1) * (2 * LOAD_RADIUS_VERTICAL + 1))
	testing.expect_value(t, offsets[0], Chunk_Coordinate{0, 0, 0})
	for index in 1 ..< len(offsets) {
		testing.expect(t, offset_distance_squared(offsets[index - 1]) <= offset_distance_squared(offsets[index]))
	}
}

// Generation and meshing cost per chunk on this machine, for the notes.
@(test)
test_report_generation_and_meshing_time :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	world: World
	defer destroy_world(&world)
	generation_start := time.tick_now()
	for z in i32(-2) ..= 2 {
		for x in i32(-2) ..= 2 {
			for y in i32(-1) ..= 2 {
				generated := generate_chunk(&generator, {x, y, z})
				world.chunks[{x, y, z}] = generated.chunk
				delete(generated.veins)
				delete(generated.outcrops)
				delete(generated.crates)
			}
		}
	}
	generation_time := time.tick_since(generation_start)
	mesh_start := time.tick_now()
	quads := 0
	for _, chunk in world.chunks {
		input := Mesh_Input {
			chunk    = chunk,
			border   = gather_chunk_border(&world, chunk.coordinate),
			registry = registry,
			atlas    = atlas_layout_for_block_count(len(registry.definitions)),
		}
		data := mesh_chunk(input)
		quads += data.quad_count
		destroy_chunk_mesh_data(data)
		free(input.border)
	}
	mesh_time := time.tick_since(mesh_start)
	count := len(world.chunks)
	log.infof("generation %v per chunk, meshing %v per chunk, over %d chunks (y -1 to 2), %d quads", generation_time / time.Duration(count), mesh_time / time.Duration(count), count, quads)
	testing.expect(t, quads > 0)
}
