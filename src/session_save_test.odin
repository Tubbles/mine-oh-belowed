package game

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import "platform"

// Work item 0345: the save off the frame. Every save goes under a
// temporary directory (make_save_test_directory).

SAVE_OFF_FRAME_TEST_NAME :: "Off the frame"
SAVING_TEST_DIRECTORY_NAME :: "Saved world"

// A snapshot written through the save's thread holds the bytes a save on
// the frame writes of the same state, though the live state changed after
// the snapshot: for a field world with a kept chunk and for a block world.
@(test) // slow
test_a_save_off_the_frame_writes_the_bytes_of_one_on_it :: proc(t: ^testing.T) {
	{
		game := make_field_test_game_content()
		session := start_field_test_session(test_field_game_config(), game)
		defer end_session(session)
		content := field_test_content(session, game)
		state := &session.simulation
		sample, kept := make_field_save_test_state(state, content)
		directory := make_save_test_directory()
		defer remove_save_test_directory(directory)
		on_frame, off_frame := save_test_locations_on_and_off_frame(directory)
		testing.expect_value(t, save_world(state, content, on_frame, 7), "")
		snapshot, ok := take_save_snapshot(state, content, off_frame, 7)
		if !testing.expect(t, ok) {
			return
		}
		field_world_set_sample(&state.field.world, sample, Field_Sample{MAXIMUM_DENSITY, .Stone, 2})
		slice.fill(state.field.saved_chunks[kept].bytes, 0)
		state.players[0].held.stack.count += 1
		expect_snapshot_written_as_on_frame(t, snapshot, on_frame, off_frame)
		testing.expect(t, os.exists(save_test_file_path(off_frame, FIELD_FILE_NAME)), "a field world writes field.bin")
		live := encode_save_files(state, content, SAVE_OFF_FRAME_TEST_NAME, 7)
		testing.expect(t, !slice.equal(live.entities, read_save_test_file(on_frame, ENTITIES_FILE_NAME)), "the change after the snapshot is in the entities")
		testing.expect(t, !slice.equal(live.field, read_save_test_file(on_frame, FIELD_FILE_NAME)), "the change after the snapshot is in the field")
	}
	{
		content := make_save_test_content()
		session := make_loopback_test_session(content)
		defer end_session(session)
		state := &session.simulation
		directory := make_save_test_directory()
		defer remove_save_test_directory(directory)
		on_frame, off_frame := save_test_locations_on_and_off_frame(directory)
		testing.expect_value(t, save_world(state, content, on_frame, 7), "")
		snapshot, ok := take_save_snapshot(state, content, off_frame, 7)
		if !testing.expect(t, ok) {
			return
		}
		state.players[0].held.stack.count += 1
		regions := expect_snapshot_written_as_on_frame(t, snapshot, on_frame, off_frame)
		testing.expect(t, regions > 0, "the block world writes regions")
		live := encode_save_files(state, content, SAVE_OFF_FRAME_TEST_NAME, 7)
		testing.expect(t, !slice.equal(live.entities, read_save_test_file(on_frame, ENTITIES_FILE_NAME)), "the change after the snapshot is in the entities")
	}
}

// A save in flight is written before a synchronous save, and before the
// session ends. Neither leaves a staging or previous directory.
@(test)
test_a_save_in_flight_finishes_before_a_save_on_the_frame_and_the_session_end :: proc(t: ^testing.T) {
	content := make_save_test_content()
	game := Game_Content {
		simulation_content = content,
	}
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	session := make_saving_test_session(content, directory)
	first_tick := session.simulation.tick
	testing.expect_value(t, start_session_save(session, game, false), "")
	session.simulation.tick += 1
	testing.expect_value(t, save_session(session, game), "")
	testing.expect(t, session.save_job == nil)
	expect_one_save_at_tick(t, directory, first_tick + 1)
	testing.expect_value(t, start_session_save(session, game, false), "")
	session.simulation.tick += 1
	end_session(session)
	expect_one_save_at_tick(t, directory, first_tick + 1)
}

// While a save is in flight a request and a due autosave wait, unchanged,
// and the first call after it finished starts the next.
@(test)
test_a_second_save_waits_while_one_is_in_flight :: proc(t: ^testing.T) {
	content := make_save_test_content()
	game := Game_Content {
		simulation_content = content,
	}
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	session := make_saving_test_session(content, directory)
	defer end_session(session)
	session.save_requested = true
	session.ticks_since_save = 5
	started, problem := begin_due_session_save(session, game, 0)
	testing.expect(t, started)
	testing.expect_value(t, problem, "")
	testing.expect(t, !session.save_requested)
	testing.expect_value(t, session.ticks_since_save, 0)
	first := session.save_job
	testing.expect(t, first != nil)

	minute := u64(60 * session.simulation.tick_rate)
	session.ticks_since_save = minute
	session.save_requested = true
	started, problem = begin_due_session_save(session, game, 1)
	testing.expect(t, !started)
	testing.expect_value(t, problem, "")
	testing.expect(t, session.save_job == first)
	testing.expect(t, session.save_requested)
	testing.expect_value(t, session.ticks_since_save, minute)

	outcome, finished := finish_session_save(session)
	testing.expect(t, finished)
	testing.expect(t, outcome.requested)
	testing.expect_value(t, outcome.problem, "")
	started, problem = begin_due_session_save(session, game, 1)
	testing.expect(t, started)
	testing.expect_value(t, problem, "")
	testing.expect(t, !session.save_requested)
	finish_session_save(session)
}

// A write that fails on the save's thread comes back as the outcome's
// problem and writes nothing. Then the toasts of the outcomes.
@(test)
test_a_failed_save_off_the_frame_reports_its_problem :: proc(t: ^testing.T) {
	content := make_save_test_content()
	game := Game_Content {
		simulation_content = content,
	}
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	blocker := platform.join_path(directory, "blocker")
	testing.expect(t, os.write_entire_file(blocker, transmute([]byte)string("a file, not a directory")) == nil)
	saves := platform.join_path(blocker, "saves")
	session := make_saving_test_session(content, saves)
	defer end_session(session)
	testing.expect_value(t, start_session_save(session, game, true), "")
	outcome, finished := finish_session_save(session)
	testing.expect(t, finished)
	testing.expect(t, outcome.problem != "")
	testing.expect(t, outcome.requested)
	testing.expect(t, !os.exists(saves))
	testing.expect(t, os.is_file(blocker))
	testing.expect_value(t, save_outcome_text_key(outcome), "save_failed")
	testing.expect_value(t, save_outcome_text_key(Save_Outcome{requested = true}), "save_done")
	testing.expect_value(t, save_outcome_text_key(Save_Outcome{}), "autosave_done")
}

// make_test_field_save's state (two ticks, an edited sample, a torch,
// awake water) plus a kept chunk: a copy of the awake chunk 40 chunks up,
// its bytes and hash in Field_Simulation.saved_chunks. Returns the edited
// sample and the kept chunk's coordinate.
make_field_save_test_state :: proc(state: ^Simulation_State, content: Simulation_Content) -> (sample: Sample_Coordinate, kept: Field_Chunk_Coordinate) {
	tick_field_test_simulation(state, content, {})
	tick_field_test_simulation(state, content, {})
	field := &state.field
	sample = nearest_field_sample(state.players[0].field.position, field.spacing_millimetres)
	field_world_set_sample(&field.world, sample, Field_Sample{MAXIMUM_DENSITY, .Stone, 1})
	add_field_light_source(&field.world, sample + {0, 3, 0}, 12)
	append(&field.torches, Field_Torch{sample = sample + {0, 3, 0}})
	awake := sample_to_field_chunk_coordinate(sample)
	chunk := field.world.chunks[awake]
	set_field_sample_bit(&chunk.water_awake, 0)
	note_field_chunk_change(chunk)
	field.world.water_awake_chunks[awake] = {}
	kept_chunk := new(Field_Chunk)
	defer free(kept_chunk)
	kept_chunk^ = chunk^
	kept_chunk.crater_overlay = {}
	kept_chunk.coordinate += {0, 40, 0}
	kept_chunk.hash_current = false
	field.saved_chunks[kept_chunk.coordinate] = Field_Saved_Chunk {
		bytes      = encode_field_chunk(kept_chunk),
		state_hash = field_chunk_state_hash(kept_chunk),
	}
	return sample, kept_chunk.coordinate
}

// One display name, two directories.
save_test_locations_on_and_off_frame :: proc(directory: string) -> (on_frame, off_frame: Save_Location) {
	on_frame = Save_Location {
		saves_directory = directory,
		directory_name  = "on frame",
		display_name    = SAVE_OFF_FRAME_TEST_NAME,
	}
	off_frame = on_frame
	off_frame.directory_name = "off frame"
	return on_frame, off_frame
}

save_test_file_path :: proc(location: Save_Location, name: string) -> string {
	return platform.join_path(location.saves_directory, location.directory_name, name)
}

// The file's bytes, nil when it does not exist.
read_save_test_file :: proc(location: Save_Location, name: string) -> []byte {
	data, error := os.read_entire_file(save_test_file_path(location, name), context.temp_allocator)
	return error == nil ? data : nil
}

// The snapshot written through the save's thread, then every file of the
// two saves compared byte for byte. Returns the count of region files.
expect_snapshot_written_as_on_frame :: proc(t: ^testing.T, snapshot: Save_Snapshot, on_frame, off_frame: Save_Location) -> (regions: int) {
	outcome := finish_save_job(start_save_job(snapshot, false))
	testing.expect_value(t, outcome.problem, "")
	testing.expect(t, !outcome.requested)
	names := make([dynamic]string, context.temp_allocator)
	append(&names, WORLD_FILE_NAME, ENTITIES_FILE_NAME, FIELD_FILE_NAME)
	entries, error := os.read_all_directory_by_path(save_test_file_path(on_frame, REGIONS_DIRECTORY_NAME), context.temp_allocator)
	testing.expect(t, error == nil)
	for entry in entries {
		append(&names, platform.join_path(REGIONS_DIRECTORY_NAME, entry.name))
	}
	written, written_error := os.read_all_directory_by_path(save_test_file_path(off_frame, REGIONS_DIRECTORY_NAME), context.temp_allocator)
	testing.expect(t, written_error == nil)
	testing.expect_value(t, len(written), len(entries))
	for name in names {
		testing.expectf(t, os.exists(save_test_file_path(on_frame, name)) == os.exists(save_test_file_path(off_frame, name)), "%s is in one save only", name)
		testing.expectf(t, slice.equal(read_save_test_file(on_frame, name), read_save_test_file(off_frame, name)), "%s differs", name)
	}
	return len(entries)
}

// make_loopback_test_session saving under saves_directory, its names heap
// clones as end_session expects (the old ones deleted).
make_saving_test_session :: proc(content: Simulation_Content, saves_directory: string) -> ^Session {
	session := make_loopback_test_session(content)
	delete(session.save.location.directory_name)
	delete(session.save.location.display_name)
	session.save = Save_Setup {
		location = Save_Location {
			saves_directory = saves_directory,
			directory_name = strings.clone(SAVING_TEST_DIRECTORY_NAME),
			display_name = strings.clone(LOOPBACK_TEST_WORLD_NAME),
		},
		enabled = true,
	}
	return session
}

// The saves directory holds the save alone (no staging or previous
// directory beside it), at the tick.
expect_one_save_at_tick :: proc(t: ^testing.T, saves_directory: string, tick: u64) {
	entries, error := os.read_all_directory_by_path(saves_directory, context.temp_allocator)
	testing.expect(t, error == nil)
	testing.expect_value(t, len(entries), 1)
	file, problem := read_world_file(platform.join_path(saves_directory, SAVING_TEST_DIRECTORY_NAME), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, file.tick, tick)
}
