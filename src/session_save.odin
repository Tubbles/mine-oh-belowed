package game

import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:strings"
import "core:thread"
import "core:time"
import "platform"

// The save off the frame (work item 0345, doc/architecture.md, Save
// format). The main thread takes a snapshot between ticks
// (take_save_snapshot): the explored surfaces refreshed, world.sjson,
// entities.bin and the block regions encoded as the save on the frame
// encodes them, and field.bin's inputs copied (each kept chunk's bytes and
// each loaded chunk a tick changed, whole), every byte in the snapshot's
// own arena, so the save's thread reads nothing the simulation writes. The
// thread (run_save_job) encodes the field and writes the save through the
// staging and swap save_world uses (write_save_files_into_place), with the
// same encoders, so both write the same bytes.
//
// One save at a time: Session.save_job holds the save in flight, and only
// the main thread starts, polls, joins and frees it. A pause menu Save or
// a due autosave waits while one is in flight (begin_due_session_save).
// Every synchronous save (save_session) and end_session wait for it
// first, since all of them write the same <world>.saving.

// What the save's thread reads, every byte of it in arena.
Save_Snapshot :: struct {
	arena:         ^virtual.Arena,
	location:      Save_Location,
	world:         []byte,
	entities:      []byte,
	regions:       [dynamic]Region_File,
	field_enabled: bool,
	// field.bin's inputs: the kept chunks' codec bytes, and copies of the
	// loaded chunks a tick changed.
	field_kept:    map[Field_Chunk_Coordinate][]byte,
	field_changed: [dynamic]^Field_Chunk,
}

Save_Job :: struct {
	snapshot:  Save_Snapshot,
	thread:    ^thread.Thread,
	// The pause menu's Save asked for it, not the autosave.
	requested: bool,
	// Written by the thread before it ends, in the snapshot's arena, and
	// read once it is joined: empty when the save was written.
	problem:   string,
}

// A finished save: problem in the temp allocator, "" when written.
Save_Outcome :: struct {
	requested: bool,
	problem:   string,
}

// The snapshot of the state between ticks. ok is false when no arena can
// be reserved for it.
take_save_snapshot :: proc(state: ^Simulation_State, content: Simulation_Content, location: Save_Location, last_played_unix_seconds: i64) -> (snapshot: Save_Snapshot, ok: bool) {
	snapshot.arena = new_growing_arena()
	if snapshot.arena == nil {
		return {}, false
	}
	allocator := virtual.arena_allocator(snapshot.arena)
	refresh_loaded_surfaces(&state.world, &state.records.explored)
	files := encode_save_files_without_field(state, content, location.display_name, last_played_unix_seconds)
	snapshot.location = Save_Location {
		saves_directory = strings.clone(location.saves_directory, allocator),
		directory_name  = strings.clone(location.directory_name, allocator),
		display_name    = strings.clone(location.display_name, allocator),
	}
	snapshot.world = slice.clone(files.world, allocator)
	snapshot.entities = slice.clone(files.entities, allocator)
	snapshot.regions = make([dynamic]Region_File, 0, len(files.regions), allocator)
	for region in files.regions {
		append(&snapshot.regions, Region_File{name = strings.clone(region.name, allocator), bytes = slice.clone(region.bytes, allocator)})
	}
	snapshot.field_enabled = state.field.enabled
	if state.field.enabled {
		snapshot.field_kept, snapshot.field_changed = copy_field_save_inputs(&state.field, allocator)
	}
	return snapshot, true
}

// field.bin's inputs as they stand, in allocator: each kept chunk's bytes,
// and each loaded chunk a tick changed copied whole without its crater
// overlay (the live chunk owns it, and the codec does not read it).
copy_field_save_inputs :: proc(field: ^Field_Simulation, allocator: mem.Allocator) -> (kept: map[Field_Chunk_Coordinate][]byte, changed: [dynamic]^Field_Chunk) {
	kept = make(map[Field_Chunk_Coordinate][]byte, len(field.saved_chunks), allocator)
	for coordinate, saved in field.saved_chunks {
		kept[coordinate] = slice.clone(saved.bytes, allocator)
	}
	changed = make([dynamic]^Field_Chunk, allocator)
	for _, chunk in field.world.chunks {
		if chunk.modified {
			chunk_copy := new(Field_Chunk, allocator)
			chunk_copy^ = chunk^
			chunk_copy.crater_overlay = {}
			append(&changed, chunk_copy)
		}
	}
	return kept, changed
}

destroy_save_snapshot :: proc(snapshot: ^Save_Snapshot) {
	destroy_arena(snapshot.arena)
	snapshot^ = {}
}

// The snapshot's files with field.bin encoded in the calling thread's
// temp allocator. The other files' bytes are the snapshot's own.
save_snapshot_files :: proc(snapshot: ^Save_Snapshot) -> Save_Files {
	files := Save_Files {
		world    = snapshot.world,
		entities = snapshot.entities,
		regions  = snapshot.regions,
	}
	if snapshot.field_enabled {
		files.field = assemble_field_file(snapshot.field_kept, snapshot.field_changed[:], make_save_header())
	}
	return files
}

// Returns the problem, "" when written.
write_save_snapshot :: proc(snapshot: ^Save_Snapshot) -> string {
	return write_save_files_into_place(snapshot.location, save_snapshot_files(snapshot))
}

// The save's thread: reads only the snapshot, writes only job.problem.
run_save_job :: proc(job: ^Save_Job) {
	context.allocator = virtual.arena_allocator(job.snapshot.arena)
	job.problem = strings.clone(write_save_snapshot(&job.snapshot))
}

// The job owns the snapshot from here. When no thread can be made the
// save is written on the calling thread at once, so it is still written.
start_save_job :: proc(snapshot: Save_Snapshot, requested: bool) -> ^Save_Job {
	job := new(Save_Job)
	job^ = Save_Job {
		snapshot  = snapshot,
		requested = requested,
	}
	job.thread = thread.create_and_start_with_poly_data(job, run_save_job)
	if job.thread == nil {
		run_save_job(job)
	}
	return job
}

save_job_done :: proc(job: ^Save_Job) -> bool {
	return job.thread == nil || thread.is_done(job.thread)
}

// Joins the job's thread, logs a failed write with save_session's line,
// and frees the snapshot and the job.
finish_save_job :: proc(job: ^Save_Job) -> Save_Outcome {
	if job.thread != nil {
		thread.destroy(job.thread)
	}
	outcome := Save_Outcome {
		requested = job.requested,
		problem   = strings.clone(job.problem, context.temp_allocator),
	}
	if outcome.problem != "" {
		platform.log_printf("error: saving %q failed: %s", job.snapshot.location.display_name, outcome.problem)
	}
	destroy_save_snapshot(&job.snapshot)
	free(job)
	return outcome
}

// The snapshot now and the write on the save's thread. The interval
// counts from the snapshot's tick. Returns the problem when no save
// started, "" otherwise (the write's own comes with its outcome,
// poll_session_save).
start_session_save :: proc(session: ^Session, content: Game_Content, requested: bool) -> (problem: string) {
	assert(session.save_job == nil)
	if !session.save.enabled {
		return "saving is off for this world"
	}
	session.ticks_since_save = 0
	simulation_content := session_simulation_content(content, session.technologies, session.field_content)
	snapshot, ok := take_save_snapshot(&session.simulation, simulation_content, session.save.location, time.to_unix_seconds(time.now()))
	if !ok {
		problem = "cannot reserve memory for the save"
		platform.log_printf("error: saving %q failed: %s", session.save.location.display_name, problem)
		return problem
	}
	session.save_job = start_save_job(snapshot, requested)
	return ""
}

// The pause menu's Save or a due autosave, started off the frame. While a
// save is in flight nothing starts: the request stays set and the
// autosave stays due, for the first frame after it finished. started: a
// snapshot was taken.
begin_due_session_save :: proc(session: ^Session, content: Game_Content, autosave_minutes: int) -> (started: bool, problem: string) {
	requested := session.save_requested
	autosave := session.save.enabled && autosave_due(session.ticks_since_save, autosave_minutes, session.simulation.tick_rate)
	if (!requested && !autosave) || session.save_job != nil {
		return false, ""
	}
	session.save_requested = false
	problem = start_session_save(session, content, requested)
	return problem == "", problem
}

// The save in flight, once its thread is done. Nothing while it runs or
// when none is.
poll_session_save :: proc(session: ^Session) -> (outcome: Save_Outcome, finished: bool) {
	if session.save_job == nil || !save_job_done(session.save_job) {
		return {}, false
	}
	return finish_session_save(session)
}

// The save in flight, waited for. finished is false when none was.
finish_session_save :: proc(session: ^Session) -> (outcome: Save_Outcome, finished: bool) {
	if session.save_job == nil {
		return {}, false
	}
	outcome = finish_save_job(session.save_job)
	session.save_job = nil
	return outcome, true
}
