package game

@(require) import "base:intrinsics"
@(require) import "core:fmt"
@(require) import "core:log"
@(require) import "core:mem/virtual"
@(require) import "core:testing"
@(require) import "core:time"

// The water at a flowing spring (work item 0367's probe), measured, not
// asserted: what the water step and the streaming do at 0342's spring
// view, a new world of the default settings with player 0 put at the
// view's stand, under teleport (S1) and under bodies (S2), and the tech
// demo's start under bodies (S3) when its spring lies outside S1's set.
// Each runs SPRING_REPORT_TICKS ticks of an empty input frame and logs,
// per window of SPRING_REPORT_WINDOW_TICKS ticks, the means a tick of the
// awake samples, the step's counts (Field_Water_Step_Counts), the pull's,
// the samples written and those the tick undid, the samples whose fill
// changed, the films and the standing water, the fill and what the set's
// edge took (0370), the chunks marked and the events; from
// SPRING_REPORT_STREAM_TICK the streaming of a
// viewport at the stand, a frame every SPRING_REPORT_TICKS_PER_FRAME ticks
// as at the spring's frame rate, started with nothing meshed, with the
// shipped surface waves; and per scenario the digest of field_state_hash
// over every tick against the one recorded (SPRING_REPORT_RECORDED_DIGESTS).
// The counts do not depend on the optimisation, so it runs unoptimised; its
// times are indicative only (0342's profile holds the timed figures):
// ./build.sh test quick test_report_the_water_at_a_flowing_spring -define:WATER_SPRING_REPORT=true
// or in ./build.sh nightly.
WATER_SPRING_REPORT :: #config(WATER_SPRING_REPORT, false)

when WATER_SPRING_REPORT {
	SPRING_REPORT_TICKS :: 7200
	SPRING_REPORT_WINDOW_TICKS :: 600
	SPRING_REPORT_STREAM_TICK :: 6600
	SPRING_REPORT_TICKS_PER_FRAME :: 10
	// A remesh of a node sent at most this many frames before (a second at
	// SPRING_REPORT_TICKS_PER_FRAME ticks a frame) is a repeat.
	SPRING_REPORT_REPEAT_FRAMES :: 6
	SPRING_REPORT_VIEW_METRES :: 512
	// The digests of S1, S2 and S3 recorded after 0367's C1 and C2 with the
	// shipped spring rate of 64, 0 for a scenario that did not run (S3: the
	// tech demo's spring lies in S1's set): 0367's landed digests, kept as
	// the base 0370 is read against. 0370's set's edge changes S1 and S2
	// (a behaviour change), so their verdict reads "differs". At 0367's base
	// (3f5f66e), which its pure steps B1 to B4 kept, they were
	// 0x8d19a40a04c848d5 and 0xd7e020eeefaf81de.
	SPRING_REPORT_RECORDED_DIGESTS :: [3]u64{0x24567da7e42ce7f2, 0x12079851b4b7077c, 0}

	SPRING_STEP_COUNT_FIELDS :: size_of(Field_Water_Step_Counts) / size_of(i64)
	SPRING_BODY_COUNT_FIELDS :: size_of(Water_Body_Counts) / size_of(i64)

	@(test)
	test_report_the_water_at_a_flowing_spring :: proc(t: ^testing.T) {
		config := test_field_game_config()
		content := make_field_test_game_content()
		shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
		testing.expect(t, error == nil, "the shipped game.sjson parses")
		labels := [3]string{"S1 teleport", "S2 bodies", "S3 tech demo bodies"}
		digests: [3]u64
		ran: [3]bool
		run_tech_demo := false
		for model, index in ([2]Water_Model{.Teleport, .Bodies}) {
			// The waters kept, as in the game (start_session_at_the_test_spring).
			session := start_session_at_the_test_spring(config, &content, model)
			digests[index] = run_spring_report_scenario(session, content, config, shipped.water_look, labels[index], true)
			ran[index] = true
			if index == 0 {
				run_tech_demo = !log_spring_report_tech_demo_spring(session)
			}
			end_session(session)
		}
		if run_tech_demo {
			session, problem := start_tech_demo_session(config, content, make_test_generator(DEFAULT_WORLD_SEED), DEFAULT_WORLD_SEED, {water_model = .Bodies, start = .Spring})
			testing.expect_value(t, problem, "")
			if session != nil {
				digests[2] = run_spring_report_scenario(session, content, config, shipped.water_look, labels[2], false)
				ran[2] = true
				end_session(session)
			}
		}
		recorded := SPRING_REPORT_RECORDED_DIGESTS
		for label, index in labels {
			if !ran[index] {
				log.infof("spring %s: not run", label)
				continue
			}
			verdict := recorded[index] == 0 ? "none recorded" : (recorded[index] == digests[index] ? "equal to the recorded" : "differs from the recorded")
			log.infof("spring %s: the state digest over %d ticks %016x, %s (%016x)", label, SPRING_REPORT_TICKS, digests[index], verdict, recorded[index])
		}
	}

	// The tech demo's spring (planet_spring_start) against S1's loaded
	// chunks, and the springs S1's set holds; true when the tech demo's
	// lies inside the set.
	log_spring_report_tech_demo_spring :: proc(session: ^Session) -> (inside: bool) {
		simulation := &session.simulation
		world := &simulation.field.world
		spacing := simulation.field.spacing_millimetres
		sources := 0
		for coordinate in sorted_field_chunk_coordinates(world.chunks) {
			chunk := world.chunks[coordinate]
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				if !field_sample_bit(&chunk.water_source, index) {
					continue
				}
				sources += 1
				if sources <= 8 {
					sample := field_chunk_sample(chunk, index)
					log.infof("spring S1: a spring sample of the set at %s, fill %d", field_place_text(session.planet, sample_to_world_position(sample, spacing)), chunk.water[index])
				}
			}
		}
		log.infof("spring S1: %d spring samples in the %d loaded chunks", sources, len(world.chunks))
		direction, found := planet_spring_start(simulation.world.settings.seed, session.planet)
		if !found {
			log.infof("spring S1: the planet has no tech demo spring")
			return true
		}
		sample, air := planet_spring_sample_at(world.water_planet.generation, direction)
		inside = sample_to_field_chunk_coordinate(sample) in world.chunks
		log.infof("spring S1: the tech demo's spring at %s (air above its surface %v), %s S1's set", field_place_text(session.planet, sample_to_world_position(sample, spacing)), air, inside ? "inside" : "outside")
		return inside
	}

	// One chunk's fills a tick and two ticks before, at the window's start,
	// and the samples changed in the window.
	Spring_Report_Snapshot :: struct {
		previous, before_previous, window_start: [FIELD_CHUNK_SAMPLE_COUNT]u8,
		window_changed:                          Field_Sample_Bits,
	}

	// The awake set at a tick's start: wet, dry and spring samples, the
	// chunks, the films (fill 1 to the minimum) and the standing water
	// (over the minimum, flow 0 the last tick).
	Spring_Report_Awake :: struct {
		wet, dry, springs, chunks, films, standing: i64,
	}

	// A window's sums over its ticks, and its most.
	Spring_Report_Window :: struct {
		ticks:                                      i64,
		awake:                                      Spring_Report_Awake,
		awake_most:                                 i64,
		counts:                                     [SPRING_STEP_COUNT_FIELDS]i64,
		writes_most, outflow_most:                  i64,
		pressure:                                   Field_Water_Pressure_Counts,
		visits_most:                                i64,
		written, undone:                            i64,
		changed, changed_two:                       i64,
		changed_chunks, reached_chunks:             i64,
		marked_ticks, marked_dirty, marked_edited: i64,
		events:                                     i64,
		to_edge:                                    i64,
		bodies:                                     [SPRING_BODY_COUNT_FIELDS]i64,
		wall, wall_most:                            time.Duration,
		wall_most_tick:                             int,
	}

	// The streaming of the probe's viewport (from SPRING_REPORT_STREAM_TICK):
	// its own workers' queue run on the test's thread, the waves, the
	// frame, and the frame each node was last sent; the totals.
	Spring_Report_Stream :: struct {
		on:                                          bool,
		streaming:                                   Field_Streaming,
		waves:                                       Field_Waves,
		frame:                                       int,
		last_sent:                                   map[Field_Node]int,
		first, remeshes, repeats, wave_remeshes:     int,
		stale_dirty, stale_wave_dirty, stale_edited: int,
		jobs_time:                                   time.Duration,
	}

	// Runs the scenario's ticks with its windows and streaming, logged
	// under the label; returns the digest of its states.
	run_spring_report_scenario :: proc(session: ^Session, content: Game_Content, config: Game_Config, water_look: Water_Look_Config, label: string, stream: bool) -> u64 {
		simulation := &session.simulation
		world := &simulation.field.world
		simulation_content := field_test_content(session, content)
		tuning := simulation_content.field.water
		log.infof("spring %s: water model %v, the player at %s", label, world.water_model, field_place_text(session.planet, simulation.players[0].field.position))
		// The set generated before the first tick, so its wall time is the
		// tick's.
		if !simulated_chunks_ready(simulation) {
			stage_cached_field_set(simulation)
		}
		snapshots: map[Field_Chunk_Coordinate]^Spring_Report_Snapshot
		defer {
			for _, snapshot in snapshots {
				free(snapshot)
			}
			delete(snapshots)
		}
		writes: [dynamic]Field_Water_Write
		defer delete(writes)
		world.water_write_log = &writes
		defer world.water_write_log = nil
		// The ticks' scratch, freed after each tick and frame; the content
		// and the config stay in the test's. The streaming stops before the
		// scratch goes.
		scratch: virtual.Arena
		_ = virtual.arena_init_growing(&scratch)
		defer virtual.arena_destroy(&scratch)
		context.temp_allocator = virtual.arena_allocator(&scratch)
		probe: Spring_Report_Stream
		defer if probe.on {
			stop_field_streaming(&probe.streaming)
			destroy_field_waves(&probe.waves)
			delete(probe.last_sent)
		}
		window: Spring_Report_Window
		window_fill: i64 = -1
		digest := FINGERPRINT_START
		for tick in 0 ..< SPRING_REPORT_TICKS {
			if stream && tick == SPRING_REPORT_STREAM_TICK {
				probe.on = true
				probe.streaming = start_field_streaming(simulation.world.settings.seed, session.planet, simulation.field.spacing_millimetres, 0)
				probe.waves = Field_Waves{tuning = make_field_wave_tuning(water_look), last_tick = simulation.tick}
			}
			if probe.on && (tick - SPRING_REPORT_STREAM_TICK) % SPRING_REPORT_TICKS_PER_FRAME == 0 {
				run_spring_report_frame(&probe, session, config, label)
			}
			awake := spring_report_awake(world, tuning)
			counting_marks := !probe.on
			if counting_marks {
				for _, chunk in world.chunks {
					chunk.dirty = false
				}
				clear(&world.edited_chunks)
			}
			clear(&writes)
			edge_before := world.water_to_edge
			begin := time.tick_now()
			tick_field_test_simulation(simulation, simulation_content, {})
			wall := time.tick_since(begin)
			window.to_edge += world.water_to_edge - edge_before
			digest = fingerprint_u64(digest, field_state_hash(&simulation.field, 0))

			window.ticks += 1
			window.awake.wet += awake.wet
			window.awake.dry += awake.dry
			window.awake.springs += awake.springs
			window.awake.chunks += awake.chunks
			window.awake.films += awake.films
			window.awake.standing += awake.standing
			window.awake_most = max(window.awake_most, awake.wet + awake.dry + awake.springs)
			counts := world.water_step_counts
			window.counts += transmute([SPRING_STEP_COUNT_FIELDS]i64)counts
			window.writes_most = max(window.writes_most, counts.writes)
			window.outflow_most = max(window.outflow_most, counts.spring_outflow)
			window.pressure.teleports += world.water_pressure.teleports
			window.pressure.visits += world.water_pressure.visits
			window.pressure.failures += world.water_pressure.failures
			window.visits_most = max(window.visits_most, world.water_pressure.visits)
			written, undone := spring_report_writes(writes[:])
			window.written += i64(written)
			window.undone += i64(undone)
			changed, changed_two, changed_chunks, reached_chunks := spring_report_changes(&snapshots, world)
			window.changed += i64(changed)
			window.changed_two += i64(changed_two)
			window.changed_chunks += i64(changed_chunks)
			window.reached_chunks += i64(reached_chunks)
			if counting_marks {
				window.marked_ticks += 1
				for _, chunk in world.chunks {
					window.marked_dirty += chunk.dirty ? 1 : 0
				}
				window.marked_edited += i64(len(world.edited_chunks))
			}
			window.events += i64(len(world.water_events))
			window.bodies += transmute([SPRING_BODY_COUNT_FIELDS]i64)world.water_body_counts
			window.wall += wall
			if wall > window.wall_most {
				window.wall_most, window.wall_most_tick = wall, tick
			}
			if window_fill < 0 {
				window_fill, _ = spring_report_fill(world)
			}
			if (tick + 1) % SPRING_REPORT_WINDOW_TICKS == 0 {
				window_fill = log_spring_report_window(label, tick + 1 - SPRING_REPORT_WINDOW_TICKS, tick, window, window_fill, &snapshots, world)
				window = {}
			}
			free_all(context.temp_allocator)
		}
		if probe.on {
			log.infof("spring %s streaming, %d frames: sent %d first meshes, %d remeshes (%d of a node sent within %d frames, %d for the waves alone); stale at the frames' starts %d dirty, %d wave dirty, %d edited in all; the jobs %.0f ms on the test's thread (unoptimised)", label, probe.frame, probe.first, probe.remeshes, probe.repeats, SPRING_REPORT_REPEAT_FRAMES, probe.wave_remeshes, probe.stale_dirty, probe.stale_wave_dirty, probe.stale_edited, time.duration_milliseconds(probe.jobs_time))
		}
		log.infof("spring %s: the player at %s after %d ticks", label, field_place_text(session.planet, simulation.players[0].field.position), SPRING_REPORT_TICKS)
		return digest
	}

	spring_report_awake :: proc(world: ^Field_World, tuning: Field_Water_Tuning) -> Spring_Report_Awake {
		awake := Spring_Report_Awake{chunks = i64(len(world.water_awake_chunks))}
		for coordinate in world.water_awake_chunks {
			chunk := world.chunks[coordinate] or_else nil
			if chunk == nil {
				continue
			}
			for word in 0 ..< FIELD_SAMPLE_BIT_WORDS {
				bits := chunk.water_awake[word]
				for bits != 0 {
					bit := u64(intrinsics.count_trailing_zeros(bits))
					bits &= field_bits_above(bit)
					index := word * 64 + int(bit)
					fill := i32(chunk.water[index])
					switch {
					case field_sample_bit(&chunk.water_source, index):
						awake.springs += 1
					case fill == 0:
						awake.dry += 1
					case:
						awake.wet += 1
					}
					if fill > 0 && fill <= tuning.minimum_fill {
						awake.films += 1
					} else if fill > tuning.minimum_fill && chunk.water_flow[index] == 0 {
						awake.standing += 1
					}
				}
			}
		}
		return awake
	}

	// The samples the tick wrote (set_field_water), and those whose fill at
	// the tick's end is the fill before their first write.
	spring_report_writes :: proc(writes: []Field_Water_Write) -> (written, undone: int) {
		seen := make(map[^Field_Chunk]^Field_Sample_Bits, context.temp_allocator)
		for write in writes {
			bits := seen[write.chunk] or_else nil
			if bits == nil {
				bits = new(Field_Sample_Bits, context.temp_allocator)
				seen[write.chunk] = bits
			}
			if field_sample_bit(bits, write.index) {
				continue
			}
			set_field_sample_bit(bits, write.index)
			written += 1
			if write.chunk.water[write.index] == write.before {
				undone += 1
			}
		}
		return written, undone
	}

	// The samples whose fill differs from the tick before and from two
	// ticks before, the chunks holding such a sample and the loaded chunks
	// their reach marks (mark_field_look_dirty's, what a mark by the
	// changed fill alone would dirty); a chunk seen first starts its
	// snapshots, one that left drops them.
	spring_report_changes :: proc(snapshots: ^map[Field_Chunk_Coordinate]^Spring_Report_Snapshot, world: ^Field_World) -> (changed, changed_two, changed_chunks, reached_chunks: int) {
		reached := make(map[Field_Chunk_Coordinate]struct{}, context.temp_allocator)
		for coordinate, chunk in world.chunks {
			snapshot := snapshots^[coordinate] or_else nil
			if snapshot == nil {
				snapshot = new(Spring_Report_Snapshot)
				snapshot.previous, snapshot.before_previous, snapshot.window_start = chunk.water, chunk.water, chunk.water
				snapshots^[coordinate] = snapshot
				continue
			}
			if chunk.water != snapshot.previous {
				changed_chunks += 1
				for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
					if chunk.water[index] != snapshot.previous[index] {
						changed += 1
						set_field_sample_bit(&snapshot.window_changed, index)
						bits := field_look_reach_bits(field_index_to_local(index))
						for slot in 0 ..< 27 {
							offset := Field_Chunk_Coordinate{i32(slot % 3) - 1, i32(slot / 3 % 3) - 1, i32(slot / 9) - 1}
							if bits & (u32(1) << uint(slot)) != 0 && coordinate + offset in world.chunks {
								reached[coordinate + offset] = {}
							}
						}
					}
				}
			}
			if chunk.water != snapshot.before_previous {
				for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
					changed_two += chunk.water[index] != snapshot.before_previous[index] ? 1 : 0
				}
			}
			snapshot.before_previous = snapshot.previous
			snapshot.previous = chunk.water
		}
		left := make([dynamic]Field_Chunk_Coordinate, context.temp_allocator)
		for coordinate in snapshots^ {
			if coordinate not_in world.chunks {
				append(&left, coordinate)
			}
		}
		for coordinate in left {
			free(snapshots^[coordinate])
			delete_key(snapshots, coordinate)
		}
		return changed, changed_two, changed_chunks, len(reached)
	}

	// The loaded chunks' fill, and their wet samples with a face neighbour
	// in a chunk not loaded.
	spring_report_fill :: proc(world: ^Field_World) -> (fill: i64, beside_missing: int) {
		for coordinate, chunk in world.chunks {
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				water := chunk.water[index]
				fill += i64(water)
				if water == 0 || chunk.density[index] > 0 {
					continue
				}
				local := field_index_to_local(index)
				for axis in 0 ..< 3 {
					step: Field_Chunk_Coordinate
					switch local[axis] {
					case 0:
						step[axis] = -1
					case FIELD_CHUNK_SIZE - 1:
						step[axis] = 1
					case:
						continue
					}
					if coordinate + step not_in world.chunks {
						beside_missing += 1
						break
					}
				}
			}
		}
		return fill, beside_missing
	}

	// The window's three lines; returns the fill at its end, the next
	// window's start.
	log_spring_report_window :: proc(label: string, first, last: int, window: Spring_Report_Window, start_fill: i64, snapshots: ^map[Field_Chunk_Coordinate]^Spring_Report_Snapshot, world: ^Field_World) -> i64 {
		ticks := f64(window.ticks)
		mean :: proc(sum: i64, ticks: f64) -> f64 {
			return f64(sum) / ticks
		}
		in_window, end_against_start := 0, 0
		for coordinate, chunk in world.chunks {
			snapshot := snapshots^[coordinate] or_else nil
			if snapshot == nil {
				continue
			}
			in_window +=field_sample_bits_count(&snapshot.window_changed)
			for index in 0 ..< FIELD_CHUNK_SAMPLE_COUNT {
				end_against_start += chunk.water[index] != snapshot.window_start[index] ? 1 : 0
			}
			snapshot.window_start = chunk.water
			snapshot.window_changed = {}
		}
		fill, beside_missing := spring_report_fill(world)
		awake := window.awake
		log.infof("spring %s, ticks %d to %d: %d chunks loaded; awake at the tick's start %.0f (wet %.0f, dry %.0f, springs %.2f, most %d) in %.1f chunks; films %.0f, standing %.0f; wet beside a chunk not loaded %d at the end; fill %d, %+d over the window; to the edge %.1f a tick", label, first, last, len(world.chunks), mean(awake.wet + awake.dry + awake.springs, ticks), mean(awake.wet, ticks), mean(awake.dry, ticks), mean(awake.springs, ticks), window.awake_most, mean(awake.chunks, ticks), mean(awake.films, ticks), mean(awake.standing, ticks), beside_missing, fill, fill - start_fill, mean(window.to_edge, ticks))
		counts := transmute(Field_Water_Step_Counts)window.counts
		log.infof("spring %s, ticks %d to %d: writes %.0f (most %d), samples written %.0f, %.0f of them undone by the tick's end; moves %.0f (fill %.0f); wake checks %.0f, wakes %.0f; neighbour sets %.0f; spans %.0f (wake checks %.0f, searches %.0f); searches %.1f (postponed %.1f), visits %.0f (most %d), teleports %.2f, failures %.1f; spring pours %.1f (most %d); apply over %.2f chunks visits %.0f samples, %.0f planned or given a delta",label, first, last, mean(counts.writes, ticks), window.writes_most, mean(window.written, ticks), mean(window.undone, ticks), mean(counts.moves, ticks), mean(counts.moved_fill, ticks), mean(counts.wake_checks, ticks), mean(counts.wakes, ticks), mean(counts.neighbour_sets, ticks), mean(counts.spans, ticks), mean(counts.wake_spans, ticks), mean(counts.search_spans, ticks), mean(counts.searches, ticks), mean(counts.postponed, ticks), mean(window.pressure.visits, ticks), window.visits_most, mean(window.pressure.teleports, ticks), mean(window.pressure.failures, ticks), mean(counts.spring_outflow, ticks), window.outflow_most, mean(counts.apply_chunks, ticks), mean(counts.apply_visits, ticks), mean(counts.apply_samples, ticks))
		marks := "not counted (the streaming takes them)"
		if window.marked_ticks > 0 {
			marked := f64(window.marked_ticks)
			marks = fmt.tprintf("%.1f dirty, %.1f edited", mean(window.marked_dirty, marked), mean(window.marked_edited, marked))
		}
		bodies := transmute(Water_Body_Counts)window.bodies
		log.infof("spring %s, ticks %d to %d: samples changed from the tick before %.0f (in %.1f chunks, their reach %.1f chunks), from two ticks before %.0f, in the window %d, at its end against its start %d; chunks marked a tick %s; events %.1f; bodies' front %.0f, flood visits %.0f, absorbed %.1f, seeded %.3f; a tick %.1f ms (most %.1f at tick %d, unoptimised)", label, first, last, mean(window.changed, ticks), mean(window.changed_chunks, ticks), mean(window.reached_chunks, ticks), mean(window.changed_two, ticks), in_window, end_against_start, marks, mean(window.events, ticks), mean(bodies.front, ticks), mean(bodies.flood_visits, ticks), mean(bodies.absorbed, ticks), mean(bodies.seeded, ticks), time.duration_milliseconds(window.wall) / ticks, time.duration_milliseconds(window.wall_most), window.wall_most_tick)
		return fill
	}

	// One frame of the viewport at the player's eye: the waves, the
	// streaming's update with no chunk requested, the jobs run here and the
	// meshes taken and freed. Logs the stale chunks before the update, the
	// jobs sent (first meshes, remeshes, those of a node sent within
	// SPRING_REPORT_REPEAT_FRAMES frames, those for the waves alone) and the
	// selected nodes never sent.
	run_spring_report_frame :: proc(probe: ^Spring_Report_Stream, session: ^Session, config: Game_Config, label: string) {
		simulation := &session.simulation
		world := &simulation.field.world
		eye := field_player_eye(simulation.players[0].field, session.field_content.tuning)
		view := make_field_view(eye, session.planet, simulation.field.spacing_millimetres, field_view_level_distances(config.field_view, SPRING_REPORT_VIEW_METRES))
		selection := select_field_nodes(view, context.temp_allocator)
		advance_field_waves(&probe.waves, world, simulation.tick)
		dirty, wave_dirty := 0, 0
		for _, chunk in world.chunks {
			dirty += chunk.dirty ? 1 : 0
			wave_dirty += chunk.wave_dirty ? 1 : 0
		}
		edited := len(world.edited_chunks)
		probe.stale_dirty += dirty
		probe.stale_wave_dirty += wave_dirty
		probe.stale_edited += edited
		revisions := make([]u64, len(selection), context.temp_allocator)
		waves_alone := make([]bool, len(selection), context.temp_allocator)
		for node, position in selection {
			revisions[position] = probe.streaming.mesh_revisions[node] or_else 0
			if node.level == 0 {
				chunk := world.chunks[field_node_chunk(node)] or_else nil
				waves_alone[position] = chunk != nil && chunk.wave_dirty && !chunk.dirty
			}
		}
		arrivals := make([dynamic]^Field_Chunk, context.temp_allocator)
		update_field_streaming(&probe.streaming, world, Field_Stream_Frame{selection = selection}, &arrivals, field_waves_drawn(&probe.waves))
		first, remeshes, repeats, wave_remeshes := 0, 0, 0, 0
		for node, position in selection {
			revision := probe.streaming.mesh_revisions[node] or_else 0
			if revision == revisions[position] {
				continue
			}
			if revisions[position] == 0 {
				first += 1
			} else {
				remeshes += 1
				if last, found := probe.last_sent[node]; found && probe.frame - last <= SPRING_REPORT_REPEAT_FRAMES {
					repeats += 1
				}
				wave_remeshes += waves_alone[position] ? 1 : 0
			}
			probe.last_sent[node] = probe.frame
		}
		begin := time.tick_now()
		run_queued_field_jobs(&probe.streaming)
		for result in take_current_field_meshes(&probe.streaming, context.temp_allocator) {
			free_field_job_result(result)
		}
		probe.jobs_time += time.tick_since(begin)
		never := 0
		for node in selection {
			never += node in probe.streaming.mesh_revisions ? 0 : 1
		}
		probe.first += first
		probe.remeshes += remeshes
		probe.repeats += repeats
		probe.wave_remeshes += wave_remeshes
		log.infof("spring %s frame %d (tick %d): stale %d dirty, %d wave dirty, %d edited; sent %d first meshes, %d remeshes (%d of a node sent within %d frames, %d for the waves alone); %d of %d selected nodes never sent", label, probe.frame, simulation.tick, dirty, wave_dirty, edited, first, remeshes, repeats, SPRING_REPORT_REPEAT_FRAMES, wave_remeshes, never, len(selection))
		probe.frame += 1
	}
}
