package game

import "core:container/queue"
import "core:os"
import "core:strings"
import "core:testing"
import "platform"

// The field session (work item 0179): the presets, the determinism of the
// field's tick, the save, the spawn, the refused block save and the
// simulated set.

// The test content with the shipped planets, field materials and light.
make_field_test_game_content :: proc() -> Game_Content {
	content := Game_Content {
		simulation_content = make_save_test_content(),
		planets            = shipped_test_planets(),
	}
	content.field_materials = test_field_materials(content.items)
	lighting, problem := parse_lighting_file(#load("../data/lighting.sjson"), LIGHTING_FILE_NAME)
	assert(problem == "", problem)
	content.lighting = lighting
	return content
}

// A new field world of the default seed at the radius (0 for the
// planet's default), without a save.
start_field_test_session :: proc(config: Game_Config, content: Game_Content, radius_metres := 0) -> ^Session {
	settings := default_world_file_settings(config)
	settings.planet_radius_metres = radius_metres
	plan := Session_Plan{seed = DEFAULT_WORLD_SEED, settings = settings}
	session, problem := start_session(plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	assert(problem == "", problem)
	return session
}

field_test_content :: proc(session: ^Session, content: Game_Content) -> Simulation_Content {
	simulation_content := session_simulation_content(content, session.technologies, session.field_content)
	simulation_content.generator = &session.generator
	return simulation_content
}

// One tick with the set's chunks generated on the test's thread first,
// as the streaming would hand them over.
tick_field_test_simulation :: proc(state: ^Simulation_State, content: Simulation_Content, frame: Input_Frame) {
	if !simulated_chunks_ready(state) {
		stage_generated_field_set(state)
	}
	inputs := [1]Input_Frame{frame}
	simulation_tick(state, content, inputs[:])
}

// The scripted input of tick index, through the hotbar: a look down, a
// walk, a torch on the ground ahead, a foundation, a turn away from it, a
// short dig with the pickaxe and the dug material placed back.
field_test_script_frame :: proc(tick: int) -> Input_Frame {
	frame: Input_Frame
	press :: proc(frame: ^Input_Frame, action: Action) {
		frame.pressed += {action}
		frame.just_pressed += {action}
	}
	switch {
	case tick == 0:
		frame.look_delta = {0, 300}
	case tick < 240:
		frame.move = {0, 1}
		frame.pressed = {.Move}
	case tick == 260:
		press(&frame, .Hotbar_Slot_3)
	case tick == 280, tick == 320:
		press(&frame, .Place)
	case tick >= 520 && tick < 560:
		frame.pressed = {.Place}
		frame.just_pressed = tick == 520 ? {.Place} : {}
	case tick == 300:
		press(&frame, .Hotbar_Slot_2)
	case tick == 340:
		frame.look_delta = {900, 0}
	case tick == 380:
		press(&frame, .Hotbar_Slot_1)
	case tick >= 400 && tick < 480:
		frame.pressed = {.Mine}
		frame.just_pressed = tick == 400 ? {.Mine} : {}
	case tick == 490:
		frame.look_delta = {-1800, -100}
	case tick == 500:
		press(&frame, .Hotbar_Slot_4)
	}
	return frame
}

// Each preset radius generates a planet of that radius: the session's
// planet and the world file's record, and the home's ground lies within
// the relief of it.
@(test)
test_new_worlds_generate_each_preset_radius :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	for radius in content.planets[0].radius_presets_metres {
		session := start_field_test_session(config, content, radius)
		defer end_session(session)
		testing.expect(t, session.simulation.field.enabled)
		testing.expect_value(t, session.planet.radius_metres, radius)
		file := make_world_file(&session.simulation, "preset", 0)
		testing.expect_value(t, file.planet_generation.radius_metres, radius)
		testing.expect(t, file.field_world)
		feet := session.simulation.players[0].field.position
		distance := vector_length(cast([3]i64)feet)
		relief := metres_to_position_units(MAXIMUM_RELIEF_METRES) + millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)
		testing.expectf(t, abs(distance - metres_to_position_units(i64(radius))) <= relief, "radius %d: the feet are %d units from the centre", radius, distance)
	}
}

// Two simulations of one plan fed the same script hash alike at tick
// 1000, and part after one extra input on one side.
@(test)
test_two_field_simulations_hash_alike_and_part_on_one_input :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	first_content, second_content := field_test_content(first, content), field_test_content(second, content)
	credit_before_place: [Field_Material]i64
	for tick in 0 ..< 1000 {
		tick_field_test_simulation(&first.simulation, first_content, field_test_script_frame(tick))
		tick_field_test_simulation(&second.simulation, second_content, field_test_script_frame(tick))
		if tick == 495 {
			// The dug dirt into the hotbar, as a drag would put it.
			for session in ([2]^Session{first, second}) {
				slots := session.simulation.players[0].inventory.slots
				slots[3], slots[HOTBAR_SLOT_COUNT] = slots[HOTBAR_SLOT_COUNT], slots[3]
			}
		}
		if tick == 519 {
			credit_before_place = first.simulation.players[0].field_credit
		}
	}
	testing.expect_value(t, first.simulation.tick, 1000)
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
	testing.expect(t, len(first.simulation.world.entities.frames.frames) > 0, "the script laid a foundation")
	testing.expect_value(t, len(first.simulation.field.torches), 1)
	testing.expect(t, credit_before_place[.Topsoil] > 0, "the script dug topsoil")
	testing.expect(t, first.simulation.players[0].field_credit[.Topsoil] < credit_before_place[.Topsoil], "the script placed it back")
	tick_field_test_simulation(&first.simulation, first_content, Input_Frame{move = {1, 0}, pressed = {.Move}})
	tick_field_test_simulation(&second.simulation, second_content, {})
	testing.expect(t, simulation_state_hash(&first.simulation) != simulation_state_hash(&second.simulation), "one extra input parts the hashes")
}

// A field world's save round trips an edited chunk, a torch, a frame
// with a foundation, the light's queues and the players' field state.
@(test)
test_a_field_world_save_round_trips :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	tick_field_test_simulation(state, simulation_content, {})
	field := &state.field
	feet := state.players[0].field.position
	sample := nearest_field_sample(feet, field.spacing_millimetres)
	edited := Field_Sample{MAXIMUM_DENSITY, .Stone, 1}
	testing.expect(t, field_world_set_sample(&field.world, sample, edited))
	torch := sample + {0, 3, 0}
	add_field_light_source(&field.world, torch, 12)
	append(&field.torches, Field_Torch{sample = torch})
	foundation := field_foundation(simulation_content)
	testing.expect(t, foundation != NO_MACHINE)
	place_free_foundation(&state.world.entities, simulation_content.machines, foundation, feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, {UNIT_VECTOR_ONE, 0, 0}, simulation_content.field.foundation_pitch_millimetres)
	state.players[0].field.yaw = 1234
	removals := queue.len(field.world.light.removals[.Block]) + queue.len(field.world.light.additions[.Block])
	testing.expect(t, removals > 0, "the torch waits in the light's queue")
	hash := simulation_state_hash(state)
	files := encode_save_files(state, simulation_content, "round trip", 0)
	original_player := state.players[0].field
	end_session(session)
	file, problem := parse_world_file(files.world, context.temp_allocator)
	testing.expect_value(t, problem, "")
	plan := Session_Plan{loading = true, seed = file.seed, settings = file.settings, file = file, files = &files}
	loaded: ^Session
	loaded, problem = start_session(plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	testing.expect_value(t, problem, "")
	if loaded == nil {
		return
	}
	defer end_session(loaded)
	restored := &loaded.simulation
	testing.expect(t, restored.field.enabled)
	testing.expect_value(t, simulation_state_hash(restored), hash)
	testing.expect_value(t, field_world_get_sample(&restored.field.world, sample), edited)
	testing.expect_value(t, len(restored.field.torches), 1)
	testing.expect_value(t, restored.field.world.light.sources[torch], 12)
	testing.expect_value(t, queue.len(restored.field.world.light.removals[.Block]) + queue.len(restored.field.world.light.additions[.Block]), removals)
	testing.expect_value(t, len(restored.world.entities.frames.frames), 1)
	testing.expect_value(t, len(restored.world.entities.foundations.entries), 1)
	testing.expect_value(t, restored.players[0].field, original_player)
}

// A player joining a field world spawns at the home with the starter kit,
// through the entry every join takes (add_player_entry).
@(test)
test_a_joining_player_spawns_at_the_home_with_the_kit :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	state := &session.simulation
	add_player_entry(state, field_test_content(session, content), 1, Player_Start{})
	testing.expect_value(t, len(state.players), 2)
	home := field_home_player(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	for player in state.players {
		testing.expect_value(t, player.field.position, home.position)
		testing.expect_value(t, player.field.forward, home.forward)
		for starting in config.starting_items {
			testing.expectf(t, inventory_count(player.inventory, test_item(content.items, starting.item)) == starting.count, "%s", starting.item)
		}
	}
}

// A world saved by a block build (no field) is refused by the title's
// load, naming M14.
@(test)
test_a_block_world_save_is_refused_naming_m14 :: proc(t: ^testing.T) {
	saves, error := os.make_directory_temp("", "mine-oh-belowed-block-save-test-*", context.temp_allocator)
	testing.expect_value(t, error, nil)
	defer os.remove_all(saves)
	directory := platform.join_path(saves, "old")
	testing.expect_value(t, os.make_directory(directory), nil)
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		name           = "old",
		settings       = {day_length_seconds = 1200, planet_id = "home"},
	}
	testing.expect_value(t, os.write_entire_file(platform.join_path(directory, WORLD_FILE_NAME), encode_world_file(file, context.temp_allocator)), nil)
	_, problem := saved_world_plan(saves, "old")
	testing.expect(t, strings.contains(problem, "M14"), problem)
}

// The set follows a player who walks a chunk: the chunks behind leave,
// the ones ahead arrive, alike on two machines.
@(test)
test_the_field_set_follows_a_walking_player :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	sessions := [2]^Session{first, second}
	for session in sessions {
		tick_field_test_simulation(&session.simulation, field_test_content(session, content), {})
	}
	spacing := first.simulation.field.spacing_millimetres
	start := field_feet_chunk(first.simulation.players[0].field.position, spacing)
	reach := first.simulation.field.chunk_set.radius + first.simulation.field.chunk_set.margin
	radius := first.simulation.field.chunk_set.radius
	testing.expect(t, reach > radius)
	behind := start - {radius, 0, 0}
	ahead := start + {radius + 2, 0, 0}
	testing.expect(t, behind in first.simulation.field.world.chunks)
	testing.expect(t, ahead not_in first.simulation.field.world.chunks)
	step := World_Position{2 * i64(FIELD_CHUNK_SIZE) * sample_axis_to_position(1, spacing), 0, 0}
	for session in sessions {
		session.simulation.players[0].field.position += step
		session.simulation.players[0].field.previous_position += step
		tick_field_test_simulation(&session.simulation, field_test_content(session, content), {})
	}
	for session in sessions {
		world := &session.simulation.field.world
		testing.expect(t, behind not_in world.chunks, "the chunk behind left")
		testing.expect(t, ahead in world.chunks, "the chunk ahead arrived")
		testing.expect_value(t, len(world.chunks), len(session.simulation.field.chunk_set.chunks))
	}
	testing.expect_value(t, len(first.simulation.field.world.chunks), len(second.simulation.field.world.chunks))
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
}

// A torch on the ray behind the targeted ground is out of sight, one in
// front of it is aimed at; Dig takes a torch on its press only, so a held
// Dig digs.
@(test)
test_a_torch_behind_the_ground_is_not_aimed_at :: proc(t: ^testing.T) {
	tuning := test_field_tuning(1000)
	player := make_field_player(FAR_FEET, {UNIT_VECTOR_ONE, 0, 0})
	eye := field_player_eye(player, tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	metre := i64(POSITION_UNITS_PER_METRE)
	near := Field_Torch{sample = nearest_field_sample(eye + World_Position(fixed_scale(look, metre)), 1000)}
	far := Field_Torch{sample = nearest_field_sample(eye + World_Position(fixed_scale(look, 3 * metre)), 1000)}
	testing.expect_value(t, field_aimed_torch({far}, player, tuning), 0)
	player.target = Field_Raycast_Hit{hit = true, distance = 2 * metre}
	testing.expect_value(t, field_aimed_torch({far}, player, tuning), -1)
	testing.expect_value(t, field_aimed_torch({near}, player, tuning), 0)
	player.target = {}
	player.frame_target = Frame_Raycast_Hit{hit = true, distance = metre / 2}
	testing.expect_value(t, field_aimed_torch({near}, player, tuning), -1)

	state := make_test_field_state({}, 1000)
	defer delete(state.field.placements)
	defer delete(state.field.torches)
	content := Simulation_Content{}
	content.field.tuning = tuning
	miner := make_player(Player_Start{})
	defer destroy_player(miner)
	miner.field = make_field_player(FAR_FEET, {UNIT_VECTOR_ONE, 0, 0})
	append(&state.players, miner)
	defer delete(state.players)
	append(&state.field.torches, near)
	held := Field_Player_Input{held = {.Dig}}
	testing.expect(t, !queue_field_torch(&state, content, 0, held), "a held Dig digs")
	testing.expect_value(t, len(state.field.placements), 0)
	pressed := Field_Player_Input{held = {.Dig}, just_pressed = {.Dig}}
	testing.expect(t, queue_field_torch(&state, content, 0, pressed), "a Dig press takes the torch")
	testing.expect_value(t, len(state.field.placements), 1)
}

// A chunk leaving the set is kept only when its terrain or water differs
// from its generation: one the sea woke and that slept back leaves
// nothing behind, a dug one keeps its bytes and the hash it had.
@(test)
test_only_chunks_unlike_their_generation_are_kept_on_unload :: proc(t: ^testing.T) {
	planet := make_test_planet()
	seed := u64(7)
	field := Field_Simulation{enabled = true, spacing_millimetres = 1000}
	defer destroy_field_simulation(&field)
	slept := new(Field_Chunk)
	generate_field_chunk(seed, planet, 1000, {0, 0, 0}, slept)
	testing.expect(t, !field_sample_bit(&slept.water_awake, 0), "the sample starts asleep")
	set_field_sample_bit(&slept.water_awake, 0)
	note_field_chunk_change(slept)
	sleep_field_water_sample(slept, 0)
	dug := new(Field_Chunk)
	generate_field_chunk(seed, planet, 1000, {1, 0, 0}, dug)
	dug.density[0] = dug.density[0] > 0 ? 0 : 1
	note_field_chunk_change(dug)
	dug_hash := field_chunk_state_hash(dug)
	field.world.chunks[slept.coordinate] = slept
	field.world.chunks[dug.coordinate] = dug
	testing.expect(t, slept.modified && dug.modified, "both chunks were written")

	unload_left_field_chunks(&field, {}, seed, planet)

	testing.expect_value(t, len(field.world.chunks), 0)
	testing.expect_value(t, len(field.saved_chunks), 1)
	kept, found := field.saved_chunks[{1, 0, 0}]
	testing.expect(t, found, "the dug chunk is kept")
	testing.expect_value(t, kept.state_hash, dug_hash)
	testing.expect_value(t, field_state_hash(&field, 0), fingerprint_u64(0, dug_hash))
}

// Ten ticks of a third of an angle unit turn three units, not none: the
// frame side carries the fraction the tick's rounding drops.
@(test)
test_the_field_turn_fraction_carries_across_ticks :: proc(t: ^testing.T) {
	pixels := f32(0.34) * 360 / ANGLE_UNITS_PER_TURN / FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	frame := Input_Frame{look_delta = {pixels, pixels}}
	remainder: [2]f32
	total: [2]i32
	for _ in 0 ..< 10 {
		carried: Input_Frame
		carried, remainder = carry_field_turn(frame, remainder, 60)
		total += field_tick_input(carried, 60).turn
	}
	testing.expect_value(t, total, [2]i32{3, -3})
	testing.expect_value(t, field_tick_input(frame, 60).turn, [2]i32{0, 0})
}
