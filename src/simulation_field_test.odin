package game

import "core:container/queue"
import "core:os"
import "core:slice"
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
	lighting, problem := parse_lighting_file(#load("../data/lighting.sjson"), LIGHTING_FILE_NAME, context.temp_allocator)
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

// Stands every player on the floor two cells outside the pod's front,
// centred on the outer hatch, facing away from the pod (0221: the airlock
// is crawled through crouched, so a standing walk no longer leaves the
// cabin). The hatches stay as they are: the airlock opens them for a
// player who comes to them (0222).
move_test_players_out_of_the_pod :: proc(state: ^Simulation_State, machines: Machine_Registry) {
	pod, frame, found := find_test_pod(&state.world.entities, machines)
	if !found {
		return
	}
	machine := machines.machines[pod.machine]
	outer := machine.fixture_boxes[0]
	outside := Cell_Box{from = {machine.footprint.x + 1, 0, outer.from.z}, to = {machine.footprint.x + 1, 0, outer.to.z}}
	feet := pod_box_floor_centre(frame, pod.origin, machine, pod.rotation, outside)
	for &player in state.players {
		move_field_player_body(&player.field, make_field_player(feet, frame.axes[FRAME_FORWARD]))
	}
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
// walk out of the pod and up the crater's bowl (0199), a torch on the
// ground ahead, a foundation, a turn away from it, a short dig with the
// pickaxe and the dug material placed back, aimed far enough up the slope
// that the placement does not reach the player.
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
		frame.look_delta = {-1800, -200}
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
	move_test_players_out_of_the_pod(&first.simulation, first_content.machines)
	move_test_players_out_of_the_pod(&second.simulation, second_content.machines)
	// The dug topsoil held, its items and the credit (a place turns an
	// item into credit first, so the credit alone may rise).
	held_topsoil :: proc(session: ^Session, content: Simulation_Content) -> i64 {
		player := session.simulation.players[0]
		return field_place_volume_available(player.inventory, content.field.materials[.Topsoil].item, player.field_credit[.Topsoil])
	}
	held_before_place: i64
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
			held_before_place = held_topsoil(first, first_content)
		}
	}
	testing.expect_value(t, first.simulation.tick, 1000)
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
	testing.expect(t, len(first.simulation.world.entities.frames.frames) > 0, "the script laid a foundation")
	testing.expect_value(t, len(first.simulation.field.torches), 1)
	testing.expect(t, held_before_place > 0, "the script dug topsoil")
	testing.expect(t, held_topsoil(first, first_content) < held_before_place, "the script placed it back")
	tick_field_test_simulation(&first.simulation, first_content, Input_Frame{move = {1, 0}, pressed = {.Move}})
	tick_field_test_simulation(&second.simulation, second_content, {})
	testing.expect(t, simulation_state_hash(&first.simulation) != simulation_state_hash(&second.simulation), "one extra input parts the hashes")
}

// After the script's dig two sessions walk on across the ground (0203:
// the footprint probes and the step a step height higher run on both)
// and hash alike.
@(test)
test_two_field_simulations_hash_alike_after_a_walk_over_dug_ground :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	first_content, second_content := field_test_content(first, content), field_test_content(second, content)
	move_test_players_out_of_the_pod(&first.simulation, first_content.machines)
	move_test_players_out_of_the_pod(&second.simulation, second_content.machines)
	walk := Input_Frame{move = {0, 1}, pressed = {.Move}}
	dig: Field_Raycast_Hit
	dig_radius: i64
	walk_start: World_Position
	heading: [3]i64
	for tick in 0 ..< 630 {
		frame := tick < 480 ? field_test_script_frame(tick) : walk
		tick_field_test_simulation(&first.simulation, first_content, frame)
		tick_field_test_simulation(&second.simulation, second_content, frame)
		player := first.simulation.players[0].field
		switch tick {
		case 400:
			brushes := first_content.field.brushes
			dig, dig_radius = player.target, brushes[int(player.brush) % len(brushes)].radius
		case 479:
			testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
			walk_start, heading = player.position, field_player_heading(player)
		}
	}
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
	testing.expect_value(t, first.simulation.players[0].field.position, second.simulation.players[0].field.position)
	// The dig's first target (the hole soon deepens past the reach); the
	// walk keeps the dig's heading (the script turns only at 490), so the
	// dig lies ahead and the walk ends past its far rim.
	testing.expect(t, dig.hit, "the script dug the ground")
	rim := fixed_dot(cast([3]i64)(dig.position - walk_start), heading) + dig_radius
	walked := fixed_dot(cast([3]i64)(first.simulation.players[0].field.position - walk_start), heading)
	testing.expectf(t, walked > rim, "the walk went %d along its heading, the dig's far rim lies at %d", walked, rim)
}

// A field world's save round trips an edited chunk, a torch, a frame
// with a foundation, the pod on its own frame, the light's queues and the
// players' field state; a planet vein keeps its drawn reservoir and gets
// its disc back, which the save leaves out.
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
	foundation := field_pad_foundation(simulation_content)
	testing.expect(t, foundation != NO_MACHINE)
	place_free_foundation(&state.world.entities, simulation_content.machines, foundation, feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, {UNIT_VECTOR_ONE, 0, 0}, simulation_content.field.foundation_pitch_millimetres)
	state.players[0].field.yaw = 1234
	removals := queue.len(field.world.light.removals[.Block]) + queue.len(field.world.light.additions[.Block])
	testing.expect(t, removals > 0, "the torch waits in the light's queue")
	iron := &state.world.veins[state.world.vein_indices[planet_vein_id(0)]]
	iron.remaining[0] -= 3
	drawn, disc := iron.remaining, iron.sphere_radius
	testing.expect(t, disc > 0)
	hash := simulation_state_hash(state)
	frame_count, foundation_count := len(state.world.entities.frames.frames), len(state.world.entities.foundations.entries)
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
	stage_generated_field_set(restored)
	testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
	testing.expect_value(t, simulation_state_hash(restored), hash)
	testing.expect_value(t, field_world_get_sample(&restored.field.world, sample), edited)
	testing.expect_value(t, len(restored.field.torches), 1)
	testing.expect_value(t, restored.field.world.light.sources[torch], 12)
	testing.expect_value(t, queue.len(restored.field.world.light.removals[.Block]) + queue.len(restored.field.world.light.additions[.Block]), removals)
	testing.expect_value(t, len(restored.world.entities.frames.frames), frame_count)
	testing.expect_value(t, len(restored.world.entities.foundations.entries), foundation_count)
	loaded_iron := restored.world.veins[restored.world.vein_indices[planet_vein_id(0)]]
	testing.expect_value(t, loaded_iron.remaining, drawn)
	testing.expect_value(t, loaded_iron.sphere_radius, disc)
	_, _, pod_found := find_test_pod(&restored.world.entities, content.machines)
	testing.expect(t, pod_found, "the pod is saved with its frame")
	testing.expect_value(t, restored.players[0].field, original_player)
}

// A field world after two ticks with an edited sample beside the player,
// awake water in its chunk and a torch, saved: its files (temp
// allocator), its state hash, the count of the light's arrived chunks the
// save holds and the chunk with the awake water.
make_test_field_save :: proc(config: Game_Config, content: Game_Content) -> (files: Save_Files, hash: u64, light_arrived: int, awake: Field_Chunk_Coordinate) {
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	tick_field_test_simulation(state, simulation_content, {})
	field := &state.field
	sample := nearest_field_sample(state.players[0].field.position, field.spacing_millimetres)
	field_world_set_sample(&field.world, sample, Field_Sample{MAXIMUM_DENSITY, .Stone, 1})
	add_field_light_source(&field.world, sample + {0, 3, 0}, 12)
	append(&field.torches, Field_Torch{sample = sample + {0, 3, 0}})
	awake = sample_to_field_chunk_coordinate(sample)
	chunk := field.world.chunks[awake]
	set_field_sample_bit(&chunk.water_awake, 0)
	note_field_chunk_change(chunk)
	field.world.water_awake_chunks[awake] = {}
	return encode_save_files(state, simulation_content, "restore", 0), simulation_state_hash(state), len(field.world.light.arrived_chunks), awake
}

load_test_field_save :: proc(config: Game_Config, content: Game_Content, files: ^Save_Files) -> ^Session {
	file, problem := parse_world_file(files.world, context.temp_allocator)
	assert(problem == "", problem)
	plan := Session_Plan{loading = true, seed = file.seed, settings = file.settings, file = file, files = files}
	session: ^Session
	session, problem = start_session(plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	assert(problem == "", problem)
	return session
}

// The load generates nothing on its thread (0185): the world and the
// arrivals stay empty until the streaming hands chunks over, the tick
// waits, and a part of the set does not enter on its own.
@(test)
test_a_field_load_leaves_the_set_to_the_workers :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	files, _, _, _ := make_test_field_save(config, content)
	session := load_test_field_save(config, content, &files)
	defer end_session(session)
	field := &session.simulation.field
	testing.expect(t, field.chunk_set.restoring)
	testing.expect(t, len(field.chunk_set.chunks) > 0)
	testing.expect(t, len(field.saved_chunks) > 0, "field.bin holds the edited chunk")
	testing.expect_value(t, len(field.world.chunks), 0)
	testing.expect_value(t, len(field.arrived_chunks), 0)
	testing.expect(t, !field_chunks_ready(&session.simulation))
	first := sorted_field_chunk_coordinates(field.chunk_set.chunks)[0]
	chunk := new(Field_Chunk)
	generate_field_chunk(session.simulation.world.settings.seed, session.simulation.world.planet, field.spacing_millimetres, first, chunk)
	stage_field_chunk_arrival(field, chunk)
	update_simulated_field_chunks(&session.simulation)
	testing.expect(t, field.chunk_set.restoring)
	testing.expect_value(t, len(field.world.chunks), 0)
	requested := field_chunk_requests(&session.simulation)
	for coordinate in field.chunk_set.chunks {
		_, found := slice.linear_search(requested, coordinate)
		testing.expect(t, found, "the streaming is asked for every chunk of the set")
	}
}

// The restored set (0185) holds every chunk as its generation with the
// saved bytes over it, seeds no light, and hashes as the saved world
// whichever order the chunks arrive in.
@(test)
test_a_restored_field_set_matches_the_save_in_either_arrival_order :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	files, hash, light_arrived, awake := make_test_field_save(config, content)
	sessions := [2]^Session{load_test_field_save(config, content, &files), load_test_field_save(config, content, &files)}
	defer end_session(sessions[0])
	defer end_session(sessions[1])
	state := &sessions[0].simulation
	coordinates := sorted_field_chunk_coordinates(state.field.chunk_set.chunks)
	expected := make(map[Field_Chunk_Coordinate]u64, context.temp_allocator)
	for coordinate in coordinates {
		chunk := new(Field_Chunk, context.temp_allocator)
		generate_field_chunk(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres, coordinate, chunk)
		if saved, found := state.field.saved_chunks[coordinate]; found {
			testing.expect_value(t, decode_field_chunk_delta(saved.bytes, chunk), "")
		}
		expected[coordinate] = field_chunk_state_hash(chunk)
	}
	for session, order in sessions {
		simulation := &session.simulation
		for index in 0 ..< len(coordinates) {
			coordinate := coordinates[order == 0 ? index : len(coordinates) - 1 - index]
			chunk := new(Field_Chunk)
			generate_field_chunk(simulation.world.settings.seed, simulation.world.planet, simulation.field.spacing_millimetres, coordinate, chunk)
			stage_field_chunk_arrival(&simulation.field, chunk)
		}
		testing.expect(t, field_chunks_ready(simulation))
		update_simulated_field_chunks(simulation)
		field := &simulation.field
		testing.expect(t, !field.chunk_set.restoring)
		testing.expect_value(t, len(field.world.chunks), len(coordinates))
		for coordinate in coordinates {
			testing.expect_value(t, field_chunk_state_hash(field.world.chunks[coordinate]), expected[coordinate])
		}
		testing.expect_value(t, len(field.world.light.arrived_chunks), light_arrived)
		testing.expect(t, awake in field.world.water_awake_chunks, "the saved awake water is awake again")
		testing.expect(t, field_sample_bit(&field.world.chunks[awake].water_awake, 0))
		testing.expect_value(t, simulation_state_hash(simulation), hash)
	}
}

// A tick command waits for a loaded world's set as a lockstep tick does
// (0185): no tick runs on the empty world, and the ticks left run once
// the set is in.
@(test)
test_a_tick_command_waits_for_a_restoring_field_set :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	files, _, _, _ := make_test_field_save(config, content)
	session := load_test_field_save(config, content, &files)
	defer end_session(session)
	state := new(Frame_State)
	defer free(state)
	state.session = session
	state.developer.command_control.pending_ticks = 3
	simulation_content := field_test_content(session, content)
	start := session.simulation.tick
	testing.expect_value(t, run_command_ticks(state, simulation_content), 0)
	testing.expect_value(t, session.simulation.tick, start)
	testing.expect_value(t, state.developer.command_control.pending_ticks, 3)
	stage_generated_field_set(&session.simulation)
	testing.expect_value(t, run_command_ticks(state, simulation_content), 3)
	testing.expect_value(t, session.simulation.tick, start + 3)
	testing.expect(t, !session.simulation.field.chunk_set.restoring)
}

// The pod of a field world: its handle and its frame.
find_test_pod :: proc(entities: ^Entities, machines: Machine_Registry) -> (pod: Foundation, frame: Frame, found: bool) {
	for foundation in entities.foundations.entries {
		if foundation.alive && machines.machines[foundation.machine].kind == .Pod {
			frame, found = find_frame(&entities.frames, foundation.frame)
			return foundation, frame, found
		}
	}
	return {}, {}, false
}

// The feet's cell, a quarter pitch over them, is a cell of the pod's
// first open box (the cabin) on its floor row.
feet_in_test_cabin :: proc(frame: Frame, pod: Foundation, machine: Machine, player: Field_Player) -> bool {
	lift := World_Position(fixed_scale(player.up, frame_pitch_units(frame) / 4))
	cell := world_to_frame_cell(frame, player.position + lift)
	cabin := machine
	cabin.open_cell_box_count = 1
	return cell.y == pod.origin.y && slice.contains(machine_open_cells(pod.origin, cabin, pod.rotation), cell)
}

// A new field world stands the pod on the floor of its crater at the
// home, with no pad and its door to the spring, and a player joining it
// spawns as the first did, in the cabin facing the door, with the
// starter kit, through the entry every join takes (add_player_entry);
// after a second with no input both stand on the cabin's floor.
@(test)
test_a_new_world_sinks_the_pod_in_its_crater_and_players_spawn_in_the_cabin :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	state := &session.simulation
	pod, frame, found := find_test_pod(&state.world.entities, content.machines)
	testing.expect(t, found, "the new world has the pod")
	if !found {
		return
	}
	machine := content.machines.machines[pod.machine]
	testing.expect_value(t, pod.origin, pod_origin(machine))
	testing.expect_value(t, frame_cell_count(&state.world.entities.frames, frame.id), int(pod.size.x * pod.size.y * pod.size.z))
	hatches := 0
	for foundation in state.world.entities.foundations.entries {
		testing.expect(t, !foundation.alive || content.machines.machines[foundation.machine].kind != .Foundation, "a foundation was laid")
		if foundation.alive && content.machines.machines[foundation.machine].kind == .Hatch {
			hatches += 1
			testing.expect(t, !foundation.hatch_open, "a new world's hatch starts closed")
		}
	}
	testing.expect_value(t, hatches, 2)
	testing.expect_value(t, len(state.world.entities.sealed_rooms), 1)
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	site, heading := field_home_site(generation, state.world.planet)
	// Cell (0, 0, 0)'s base stands on the site (free_frame_at).
	base := frame_cell_centre(frame, {}) - World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	testing.expectf(t, vector_length(cast([3]i64)(base - site)) <= 4, "the pod's frame stands %v off the site", base - site)
	home := fixed_scale(planet_home_direction(state.world.planet.home), generation.radius)
	sunk := uncratered_relief(generation, home) - (vector_length(cast([3]i64)site) - generation.radius)
	depth := metres_to_position_units(i64(state.world.planet.crater.depth_metres))
	testing.expectf(t, abs(sunk - depth) <= generation.spacing / 8, "the floor lies %d units below the uncratered ground, not %d", sunk, depth)
	testing.expectf(t, fixed_dot(frame.axes[FRAME_FORWARD], heading) > UNIT_VECTOR_ONE * 990 / 1000, "the door faces %v against the spring's heading %v", frame.axes[FRAME_FORWARD], heading)
	simulation_content := field_test_content(session, content)
	add_player_entry(state, simulation_content, 1, Player_Start{})
	testing.expect_value(t, len(state.players), 2)
	spawn, spawn_found := field_pod_spawn(&state.world.entities, content.machines)
	testing.expect(t, spawn_found)
	for player in state.players {
		testing.expect_value(t, player.field.position, spawn.position)
		testing.expect_value(t, player.field.forward, spawn.forward)
		testing.expectf(t, fixed_dot(player.field.forward, frame.axes[FRAME_FORWARD]) > UNIT_VECTOR_ONE * 999 / 1000, "the player faces %v, not the door", player.field.forward)
		testing.expectf(t, feet_in_test_cabin(frame, pod, machine, player.field), "the player stands in cell %v", world_to_frame_cell(frame, player.field.position))
		for starting in config.starting_items {
			testing.expectf(t, inventory_count(player.inventory, test_item(content.items, starting.item)) == starting.count, "%s", starting.item)
		}
	}
	stage_generated_field_set(state)
	for _ in 0 ..< 60 {
		tick_field_test_simulation(state, simulation_content, {})
	}
	floor := pod_cabin_floor_centre(frame, pod.origin, machine, pod.rotation)
	for player in state.players {
		testing.expect(t, player.field.on_ground, "the player stands on the cabin's floor")
		testing.expectf(t, feet_in_test_cabin(frame, pod, machine, player.field), "the player left the cabin for %v", world_to_frame_cell(frame, player.field.position))
		above := fixed_dot(cast([3]i64)(player.field.position - floor), frame.axes[FRAME_UP])
		testing.expectf(t, above >= -tenth_sample(state.field.spacing_millimetres) && above <= frame_pitch_units(frame) / 4, "the feet stand %d units over the floor", above)
	}
}

// Two new worlds from one seed hash alike at the start and after a second
// with no input: the crater and the pod come from the seed and the record.
@(test)
test_two_new_worlds_from_one_seed_agree :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	first := start_field_test_session(config, content)
	defer end_session(first)
	second := start_field_test_session(config, content)
	defer end_session(second)
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
	for session in ([2]^Session{first, second}) {
		simulation_content := field_test_content(session, content)
		for _ in 0 ..< 60 {
			tick_field_test_simulation(&session.simulation, simulation_content, {})
		}
	}
	testing.expect_value(t, simulation_state_hash(&first.simulation), simulation_state_hash(&second.simulation))
}

// A world saved before 0199, its pod on a pad of a hundred foundations
// and its record without the crater, loads: the record takes the data's
// crater, the pad stays, the old pod (6 by 8 by 6) is replaced by the
// record's on a frame of its own standing on the pad's top (0198), the
// spawn stands in its cabin, and a pad foundation beside the old pod
// picks up and returns a foundation.
@(test)
test_an_old_save_with_a_pad_still_loads :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	entities := &state.world.entities
	machines := simulation_content.machines
	new_pod, _, _ := find_test_pod(entities, machines)
	pod_machine := new_pod.machine
	for &entry in entities.foundations.entries {
		if entry.alive && entry.frame == new_pod.frame {
			testing.expect(t, remove_entity(entities, machines, entry.handle))
		}
	}
	for entry in entities.chests.entries {
		if entry.alive && entry.frame == new_pod.frame {
			testing.expect(t, remove_entity(entities, machines, entry.handle))
		}
	}
	_, pod_frame_left := find_frame(&entities.frames, new_pod.frame)
	testing.expect(t, !pod_frame_left, "the new pod's frame goes with it and its fixtures")
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	site, heading := field_home_site(generation, state.world.planet)
	foundation := field_pad_foundation(simulation_content)
	pitch := simulation_content.field.foundation_pitch_millimetres
	_, frame_id := place_free_foundation(entities, machines, foundation, site, heading, pitch)
	for z in i32(-4) ..= 5 {
		for x in i32(-4) ..= 5 {
			if x != 0 || z != 0 {
				place_on_frame(entities, machines, foundation, frame_id, {x, 0, z}, 0)
			}
		}
	}
	old_origin := World_Coordinate{-4 + (10 - 6) / 2, 1, -4 + (10 - 6) / 2}
	old_size := [3]i32{6, 8, 6}
	old_pod := add_entity(entities, machines, pod_machine, old_origin, POD_ROTATION, frame_id)
	// The bytes an older build wrote: the pod of 6 by 8 by 6 cells.
	pool_get(&entities.foundations, old_pod).size = old_size
	pad_frame, _ := find_frame(&entities.frames, frame_id)
	old_floor := pod_floor_centre(pad_frame, old_origin, old_size)
	files := encode_save_files(state, simulation_content, "old pad", 0)
	end_session(session)
	file, problem := parse_world_file(files.world, context.temp_allocator)
	testing.expect_value(t, problem, "")
	file.planet_generation.crater, file.planet_generation.crater_recorded = {}, false
	plan := Session_Plan{loading = true, seed = file.seed, settings = file.settings, file = file, files = &files}
	loaded: ^Session
	loaded, problem = start_session(plan, config, content, make_test_generator(DEFAULT_WORLD_SEED))
	testing.expect_value(t, problem, "")
	if loaded == nil {
		return
	}
	defer end_session(loaded)
	restored := &loaded.simulation
	testing.expect_value(t, restored.world.planet.crater, default_planet(content.planets).crater)
	pod, frame, found := find_test_pod(&restored.world.entities, machines)
	testing.expect(t, found, "the old pod is replaced")
	if !found {
		return
	}
	testing.expect(t, pod.frame != frame_id, "the new pod stands on a frame of its own")
	expected_origin, expected_axes := free_frame_at(old_floor, pad_frame.axes[FRAME_FORWARD], pad_frame.pitch_millimetres)
	testing.expect_value(t, frame.origin, expected_origin)
	testing.expect_value(t, frame.axes, expected_axes)
	testing.expect_value(t, pod.size, rotated_footprint_size(machines.machines[pod.machine].footprint, POD_ROTATION))
	laid := 0
	for entry in restored.world.entities.foundations.entries {
		if entry.alive && machines.machines[entry.machine].kind == .Foundation {
			laid += 1
		}
	}
	testing.expect_value(t, laid, 100)
	machine := machines.machines[pod.machine]
	spawn, spawn_found := field_pod_spawn(&restored.world.entities, machines)
	testing.expect(t, spawn_found)
	testing.expectf(t, feet_in_test_cabin(frame, pod, machine, spawn), "the spawn stands in cell %v", world_to_frame_cell(frame, spawn.position))
	above := fixed_dot(cast([3]i64)(spawn.position - frame_cell_centre(frame, {0, 0, 0})), frame.axes[FRAME_UP]) + frame_pitch_units(frame) / 2
	testing.expectf(t, abs(above - millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)) <= 4, "the spawn stands %d units over the pad's top", above)
	restored_content := field_test_content(loaded, content)
	player := &restored.players[0]
	before := inventory_count(player.inventory, machines.machines[foundation].item)
	drain_field_pick_up(restored, restored_content, player, frame_id, {-4, 0, -4})
	testing.expect_value(t, inventory_count(player.inventory, machines.machines[foundation].item), before + 1)
	testing.expect_value(t, entity_at(&restored.world.entities, {-4, 0, -4}, frame_id), NO_ENTITY)
}

// Interact on the inner hatch from the cabin, crouched so the eye's ray
// meets the low door (0221), opens it on two sessions of one seed alike:
// the toggle tick, the event and the hash after a second agree, a session
// without the press hashes otherwise, and the opened world round trips
// its save.
@(test)
test_toggling_a_hatch_is_lockstep_state :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	sessions := [3]^Session{start_field_test_session(config, content), start_field_test_session(config, content), start_field_test_session(config, content)}
	defer for session, index in sessions {
		if index < 2 {
			end_session(session)
		}
	}
	interact := Input_Frame{pressed = {.Interact, .Sneak}, just_pressed = {.Interact}}
	sneak := Input_Frame{pressed = {.Sneak}}
	toggle_ticks: [2]u64
	for session, index in sessions {
		simulation_content := field_test_content(session, content)
		state := &session.simulation
		stage_generated_field_set(state)
		pod, frame, found := find_test_pod(&state.world.entities, content.machines)
		testing.expect(t, found)
		if !found {
			return
		}
		machine := content.machines.machines[pod.machine]
		inner_box := machine.fixture_boxes[1]
		lane := Cell_Box{from = {inner_box.from.x - 2, 0, inner_box.from.z}, to = {inner_box.from.x - 2, 0, inner_box.to.z}}
		state.players[0].field = make_field_player(pod_box_floor_centre(frame, pod.origin, machine, pod.rotation, lane), frame.axes[FRAME_FORWARD])
		tick_field_test_simulation(state, simulation_content, sneak)
		clear(&state.events)
		tick_field_test_simulation(state, simulation_content, index < 2 ? interact : sneak)
		inner_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 1)
		inner := pool_get(&state.world.entities.foundations, entity_at(&state.world.entities, inner_origin, frame.id))
		testing.expect(t, inner != nil)
		if index < 2 && inner != nil {
			testing.expectf(t, inner.hatch_open, "session %d: the inner hatch opens", index)
			toggle_ticks[index] = inner.hatch_toggle_tick
			raised := false
			for event in state.events {
				raised ||= event.kind == .Toggled_Switch
			}
			testing.expect(t, raised, "the toggle raises its event")
		}
		for _ in 0 ..< 60 {
			tick_field_test_simulation(state, simulation_content, {})
		}
	}
	testing.expect(t, toggle_ticks[0] != 0)
	testing.expect_value(t, toggle_ticks[0], toggle_ticks[1])
	hash := simulation_state_hash(&sessions[0].simulation)
	testing.expect_value(t, simulation_state_hash(&sessions[1].simulation), hash)
	testing.expect(t, simulation_state_hash(&sessions[2].simulation) != hash, "no press, another hash")
	end_session(sessions[2])

	files := encode_save_files(&sessions[0].simulation, field_test_content(sessions[0], content), "hatch", 0)
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
	stage_generated_field_set(restored)
	testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
	testing.expect_value(t, simulation_state_hash(restored), hash)
	pod, frame, _ := find_test_pod(&restored.world.entities, content.machines)
	machine := content.machines.machines[pod.machine]
	inner_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 1)
	handle := entity_at(&restored.world.entities, inner_origin, frame.id)
	inner := pool_get(&restored.world.entities.foundations, handle)
	testing.expect(t, inner != nil && inner.hatch_open && inner.hatch_toggle_tick == toggle_ticks[0], "the hatch loads open with its tick")
	cells := common_cells(entity_common(&restored.world.entities, handle)^, content.machines)
	for cell in cells {
		testing.expect(t, !frame_cell_is_solid(&restored.world.entities.frames, frame.id, cell))
	}
	room := make([dynamic]World_Coordinate, context.temp_allocator)
	append(&room, ..test_pod_inside_cells(machine))
	append(&room, ..cells)
	testing.expect_value(t, len(restored.world.entities.sealed_rooms), 1)
	if len(restored.world.entities.sealed_rooms) == 1 {
		testing.expect(t, slice.equal(sorted_cells(restored.world.entities.sealed_rooms[0].cells[:]), sorted_cells(room[:])), "the room is the cabin, the airlock and the inner hatch")
	}
}

// The session pod's hatch of the fixture index (0 the outer, 1 the
// inner), nil without a pod.
test_session_hatch :: proc(state: ^Simulation_State, machines: Machine_Registry, index: int) -> ^Foundation {
	pod, frame, found := find_test_pod(&state.world.entities, machines)
	if !found {
		return nil
	}
	origin, _ := pod_fixture_placement(machines.machines[pod.machine], pod.origin, pod.rotation, index)
	return pool_get(&state.world.entities.foundations, entity_at(&state.world.entities, origin, frame.id))
}

// Work item 0222: a crouched crawl from the lane out through the airlock
// on two sessions of one seed: the doors open and close alike, a save
// taken in the inner door's hold and loaded into a third session closes
// it on the same tick, the hashes agree at tick 600, and a session with
// no input hashes otherwise.
@(test)
test_the_airlock_is_lockstep_state_and_survives_a_save :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	sessions := [3]^Session{start_field_test_session(config, content), start_field_test_session(config, content), start_field_test_session(config, content)}
	defer for session in sessions {
		end_session(session)
	}
	contents: [3]Simulation_Content
	for session, index in sessions {
		contents[index] = field_test_content(session, content)
		state := &session.simulation
		stage_generated_field_set(state)
		pod, frame, found := find_test_pod(&state.world.entities, content.machines)
		testing.expect(t, found)
		if !found {
			return
		}
		machine := content.machines.machines[pod.machine]
		inner := machine.fixture_boxes[1]
		start := Cell_Box{from = {inner.from.x - 2, 0, inner.from.z}, to = {inner.from.x - 1, 0, inner.to.z}}
		move_field_player_body(&state.players[0].field, make_field_player(pod_box_floor_centre(frame, pod.origin, machine, pod.rotation, start), frame.axes[FRAME_FORWARD]))
	}
	crawl := Input_Frame{move = {0, 1}, pressed = {.Move, .Sneak}}
	loaded: ^Session
	loaded_content: Simulation_Content
	defer if loaded != nil {
		end_session(loaded)
	}
	for _ in 1 ..= 600 {
		tick_field_test_simulation(&sessions[0].simulation, contents[0], crawl)
		tick_field_test_simulation(&sessions[1].simulation, contents[1], crawl)
		tick_field_test_simulation(&sessions[2].simulation, contents[2], {})
		if loaded != nil {
			tick_field_test_simulation(&loaded.simulation, loaded_content, crawl)
			continue
		}
		if inner := test_session_hatch(&sessions[0].simulation, content.machines, 1); inner != nil && inner.hatch_close_tick != 0 {
			files := encode_save_files(&sessions[0].simulation, contents[0], "airlock", 0)
			loaded = load_test_field_save(config, content, &files)
			stage_generated_field_set(&loaded.simulation)
			testing.expect(t, restore_arrived_field_set(&loaded.simulation.field), "the staged set restores")
			loaded_content = field_test_content(loaded, content)
			testing.expect_value(t, simulation_state_hash(&loaded.simulation), simulation_state_hash(&sessions[0].simulation))
			restored := test_session_hatch(&loaded.simulation, content.machines, 1)
			testing.expect(t, restored != nil && restored.hatch_close_tick == inner.hatch_close_tick, "the close tick loads")
		}
	}
	testing.expect(t, loaded != nil, "the inner door's hold was saved")
	if loaded == nil {
		return
	}
	outer := test_session_hatch(&sessions[0].simulation, content.machines, 0)
	testing.expect(t, outer != nil && outer.hatch_toggle_tick != 0, "the outer door opened")
	for state in ([2]^Simulation_State{&sessions[1].simulation, &loaded.simulation}) {
		other := test_session_hatch(state, content.machines, 0)
		testing.expect(t, other != nil && outer != nil && other.hatch_toggle_tick == outer.hatch_toggle_tick, "the outer door toggles on the same tick")
	}
	testing.expect_value(t, loaded.simulation.tick, sessions[0].simulation.tick)
	hash := simulation_state_hash(&sessions[0].simulation)
	testing.expect_value(t, simulation_state_hash(&sessions[1].simulation), hash)
	testing.expect_value(t, simulation_state_hash(&loaded.simulation), hash)
	testing.expect(t, simulation_state_hash(&sessions[2].simulation) != hash, "no input, another hash")
}

// Work item 0222: from the middle of the bore, Interact on the closed
// outer door is refused while the inner one is open (no event), and opens
// it once the inner one is closed and has finished its slide.
@(test)
test_interact_on_the_far_door_is_refused_while_the_near_one_is_open :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	stage_generated_field_set(state)
	pod, frame, found := find_test_pod(&state.world.entities, content.machines)
	testing.expect(t, found)
	if !found {
		return
	}
	machine := content.machines.machines[pod.machine]
	state.players[0].field = test_airlock_player(frame, machine)
	inner_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 1)
	inner := entity_at(&state.world.entities, inner_origin, frame.id)
	outer_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 0)
	outer := entity_at(&state.world.entities, outer_origin, frame.id)
	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	sneak := Input_Frame{pressed = {.Sneak}}
	interact := Input_Frame{pressed = {.Interact, .Sneak}, just_pressed = {.Interact}}
	toggled :: proc(state: ^Simulation_State) -> bool {
		for event in state.events {
			if event.kind == .Toggled_Switch {
				return true
			}
		}
		return false
	}
	tick_field_test_simulation(state, simulation_content, sneak)
	clear(&state.events)
	tick_field_test_simulation(state, simulation_content, interact)
	testing.expect(t, !hatch_is_open(&state.world.entities, outer), "the outer door opened with the inner one open")
	testing.expect(t, hatch_is_open(&state.world.entities, inner), "the inner door closed")
	testing.expect(t, !toggled(state), "a refused press raised a toggle")

	testing.expect(t, toggle_hatch(&state.world.entities, content.machines, inner, state.tick, nil))
	for _ in 0 ..< simulation_content.field.pod_airlock.door_travel_ticks {
		tick_field_test_simulation(state, simulation_content, sneak)
		testing.expect(t, !hatch_is_open(&state.world.entities, inner), "the inner door opened for the player in the middle")
	}
	clear(&state.events)
	tick_field_test_simulation(state, simulation_content, interact)
	testing.expect(t, hatch_is_open(&state.world.entities, outer), "the outer door stays closed after the inner one's slide")
	testing.expect(t, toggled(state), "the press raises its toggle")
}

// A pad of foundations on a free frame at the surface position, eleven
// cells along +x and two across: room for a drill at (0, 1, 0) facing
// +x, its drop cell (2, 1, 0), and an arm whose reach spans four cells
// at the data's pitch (inserter_reach_on_frame) at (6, 1, 0), dropping at
// (10, 1, 0).
TEST_FIELD_PAD_LENGTH :: 11

lay_test_field_pad :: proc(state: ^Simulation_State, content: Simulation_Content, surface: World_Position) -> Frame_Id {
	entities := &state.world.entities
	foundation := field_pad_foundation(content)
	_, frame := place_free_foundation(entities, content.machines, foundation, surface, {UNIT_VECTOR_ONE, 0, 0}, content.field.foundation_pitch_millimetres)
	for x in i32(0) ..< TEST_FIELD_PAD_LENGTH {
		for z in i32(0) ..< 2 {
			if x != 0 || z != 0 {
				place_on_frame(entities, content.machines, foundation, frame, {x, 0, z}, 0)
			}
		}
	}
	return frame
}

// The belt line of chapter 1 on the field: a pad over the iron outcrop
// (the planet's veins, registered by the session), a drill placed through
// place_drill_on_frame, a flat belt under its drop cell, a burner arm and
// an iron chest; the session's tick runs it, and the chest fills with the
// vein's ore.
@(test)
test_a_belt_line_on_a_frame_over_an_outcrop_fills_the_chest :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	machines := simulation_content.machines
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	iron := generation.veins.veins[0]
	testing.expect_value(t, iron.material, Field_Material.Hematite_Ore)
	vein_index, registered := state.world.vein_indices[planet_vein_id(0)]
	testing.expect(t, registered, "the session registered the planet's veins")
	if !registered {
		return
	}
	entities := &state.world.entities
	frame := lay_test_field_pad(state, simulation_content, field_surface_under(generation, World_Position(iron.centre), 0))
	drill_machine := test_machine(machines, "burner_mining_drill")
	drill, drill_refusal := place_drill_on_frame(entities, machines, state.world.veins[:], drill_machine, frame, {0, 1, 0}, 0)
	testing.expect_value(t, drill_refusal, Frame_Placement_Refusal.None)
	if drill == NO_ENTITY {
		return
	}
	testing.expect_value(t, pool_get(&entities.drills, drill).vein, planet_vein_id(0))
	testing.expect_value(t, drill_drop_cell(pool_get(&entities.drills, drill)^, machines.machines[drill_machine]), World_Coordinate{2, 1, 0})
	_, belt_refusal := place_on_frame(entities, machines, test_machine(machines, "belt"), frame, {2, 1, 0}, 0)
	inserter, inserter_refusal := place_on_frame(entities, machines, test_machine(machines, "burner_inserter"), frame, {6, 1, 0}, 0)
	testing.expect_value(t, inserter_pickup_cell(pool_get(&entities.inserters, inserter)^), World_Coordinate{2, 1, 0})
	chest, chest_refusal := place_on_frame(entities, machines, test_machine(machines, "iron_chest"), frame, inserter_drop_cell(pool_get(&entities.inserters, inserter)^), 0)
	testing.expect(t, belt_refusal == .None && inserter_refusal == .None && chest_refusal == .None)
	coal := test_item(content.items, "coal")
	pool_get(&entities.drills, drill).slots[DRILL_FUEL_SLOT] = Item_Stack{coal, 5}
	pool_get(&entities.inserters, inserter).slots[INSERTER_FUEL_SLOT] = Item_Stack{coal, 5}
	cycle := int(drill_cycle_ticks(machines.machines[drill_machine], config.tick_rate))
	for _ in 0 ..< 3 * cycle {
		tick_field_test_simulation(state, simulation_content, {})
	}
	vein_type := content.veins.types[state.world.veins[vein_index].type]
	total := 0
	for output in vein_type.outputs[:vein_type.output_count] {
		total += chest_count_of(&state.world, chest, output)
	}
	testing.expectf(t, total >= 1, "the chest holds %d of the vein's ore after %d ticks", total, 3 * cycle)
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

// Place on a frame through the player's queue: a drill off every vein is
// refused with No_Vein and keeps its item, one over the iron outcrop takes
// the vein, and a placed machine counts for the quests (record_placed).
@(test)
test_queued_frame_placements_take_their_vein_and_count_for_the_quests :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	machines := simulation_content.machines
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	home := planet_home_direction(state.world.planet.home)
	off_vein := lay_test_field_pad(state, simulation_content, field_surface_under(generation, World_Position(fixed_scale(-home, generation.radius)), 0))
	on_vein := lay_test_field_pad(state, simulation_content, field_surface_under(generation, World_Position(generation.veins.veins[0].centre), 0))
	drill_machine := test_machine(machines, "burner_mining_drill")
	chest_machine := test_machine(machines, "iron_chest")
	player := &state.players[0]
	inventory_add(player.inventory, content.items, machines.machines[drill_machine].item, 2)
	inventory_add(player.inventory, content.items, machines.machines[chest_machine].item, 1)
	queue_placement :: proc(state: ^Simulation_State, machine: Machine_Id, frame: Frame_Id, cell: World_Coordinate) {
		append(&state.field.placements, Queued_Field_Placement{player = 0, placement = {kind = .Machine, machine = machine, frame = frame, cell = cell}})
	}
	queue_placement(state, drill_machine, off_vein, {0, 1, 0})
	drain_field_placements(state, simulation_content)
	testing.expect_value(t, player.field_refusal, Field_Edit_Refusal.No_Vein)
	testing.expect_value(t, inventory_count(player.inventory, machines.machines[drill_machine].item), 2)
	testing.expect_value(t, state.records.statistics.placed[drill_machine], 0)
	queue_placement(state, drill_machine, on_vein, {0, 1, 0})
	queue_placement(state, chest_machine, on_vein, {2, 1, 0})
	drain_field_placements(state, simulation_content)
	drill := entity_at(&state.world.entities, {0, 1, 0}, on_vein)
	testing.expect_value(t, drill.kind, Entity_Kind.Drill)
	if drill.kind == .Drill {
		testing.expect_value(t, pool_get(&state.world.entities.drills, drill).vein, planet_vein_id(0))
	}
	testing.expect_value(t, state.records.statistics.placed[drill_machine], 1)
	testing.expect_value(t, state.records.statistics.placed[chest_machine], 1)
	testing.expect_value(t, inventory_count(player.inventory, machines.machines[drill_machine].item), 1)
}

// The Field_Refused events of a player in the tick's events.
count_field_refused_events :: proc(events: []Simulation_Event, refusal: Field_Edit_Refusal) -> int {
	count := 0
	for event in events {
		if event.kind == .Field_Refused && event.field_refusal == refusal {
			count += 1
		}
	}
	return count
}

// A drill queued off every vein in a session's tick raises one
// Field_Refused event with No_Vein, which the HUD toasts; the ghost of
// that placement takes the refused colour.
@(test)
test_a_refused_field_placement_raises_one_event :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	machines := simulation_content.machines
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	home := planet_home_direction(state.world.planet.home)
	off_vein := lay_test_field_pad(state, simulation_content, field_surface_under(generation, World_Position(fixed_scale(-home, generation.radius)), 0))
	drill_machine := test_machine(machines, "burner_mining_drill")
	inventory_add(state.players[0].inventory, content.items, machines.machines[drill_machine].item, 1)
	placement := Field_Placement{kind = .Machine, machine = drill_machine, frame = off_vein, cell = {0, 1, 0}}
	testing.expect_value(t, frame_ghost_color(field_placement_refusal(state, simulation_content, state.players[0], placement)), GHOST_INVALID_COLOR)
	tick_field_test_simulation(state, simulation_content, {})
	clear(&state.events)
	append(&state.field.placements, Queued_Field_Placement{player = 0, placement = placement})
	tick_field_test_simulation(state, simulation_content, {})
	testing.expect_value(t, count_field_refused_events(state.events[:], .No_Vein), 1)
	tick_field_test_simulation(state, simulation_content, {})
	testing.expect_value(t, count_field_refused_events(state.events[:], .No_Vein), 1)
}

// A 5 by 5 foundation block queued with 16 foundations held (0193) is
// refused whole: nothing is placed or taken, one Field_Refused event is
// raised, and its ghost takes the refused colour.
@(test)
test_a_foundation_block_short_of_foundations_places_nothing :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	home := planet_home_direction(state.world.planet.home)
	pad := lay_test_field_pad(state, simulation_content, field_surface_under(generation, World_Position(fixed_scale(-home, generation.radius)), 0))
	foundation := field_pad_foundation(simulation_content)
	item := simulation_content.machines.machines[foundation].item
	inventory := state.players[0].inventory
	inventory_remove(inventory, item, inventory_count(inventory, item))
	inventory_add(inventory, content.items, item, 16)
	cells_before := frame_cell_count(&state.world.entities.frames, pad)
	block := Field_Placement{kind = .Machine, machine = foundation, frame = pad, cell = {0, 1, 0}, normal = UP, size = 5, height = 1}
	refusal := field_placement_refusal(state, simulation_content, state.players[0], block)
	testing.expect_value(t, refusal, Field_Edit_Refusal.Too_Few_Foundations)
	testing.expect_value(t, frame_ghost_color(refusal), GHOST_INVALID_COLOR)
	tick_field_test_simulation(state, simulation_content, {})
	clear(&state.events)
	append(&state.field.placements, Queued_Field_Placement{player = 0, placement = block})
	tick_field_test_simulation(state, simulation_content, {})
	tick_field_test_simulation(state, simulation_content, {})
	testing.expect_value(t, count_field_refused_events(state.events[:], refusal), 1)
	for event in state.events {
		if event.field_refusal == .Too_Few_Foundations {
			testing.expect_value(t, [2]int{event.needed, event.held}, [2]int{25, 16})
		}
	}
	testing.expect_value(t, frame_cell_count(&state.world.entities.frames, pad), cells_before)
	testing.expect_value(t, inventory_count(inventory, item), 16)
}

// A Dig held on ground the player's tools cannot dig is refused every
// tick for ten ticks and raises one event; a new press raises another.
@(test)
test_a_held_refused_dig_raises_one_event :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	for &record in simulation_content.field.materials {
		record.tool_tier = 99
	}
	state := &session.simulation
	move_test_players_out_of_the_pod(state, simulation_content.machines)
	tick_field_test_simulation(state, simulation_content, Input_Frame{look_delta = {0, 300}})
	clear(&state.events)
	for tick in 0 ..< 10 {
		frame := Input_Frame{pressed = {.Mine}, just_pressed = tick == 0 ? {.Mine} : {}}
		tick_field_test_simulation(state, simulation_content, frame)
		testing.expectf(t, state.players[0].field_refusal == .Tool_Tier, "tick %d: %v", tick, state.players[0].field_refusal)
	}
	testing.expect_value(t, count_field_refused_events(state.events[:], .Tool_Tier), 1)
	tick_field_test_simulation(state, simulation_content, {})
	tick_field_test_simulation(state, simulation_content, Input_Frame{pressed = {.Mine}, just_pressed = {.Mine}})
	testing.expect_value(t, count_field_refused_events(state.events[:], .Tool_Tier), 2)
}

// The field session's walk counter (0187): a walk on the ground counts,
// a flight counts none.
@(test)
test_a_field_walk_counts_and_a_flight_does_not :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	move_test_players_out_of_the_pod(state, simulation_content.machines)
	tick_field_test_simulation(state, simulation_content, {})
	walk := Input_Frame{move = {0, 1}, pressed = {.Move}}
	state.players[0].field.flying = true
	start := state.players[0].field.position
	for _ in 0 ..< 60 {
		tick_field_test_simulation(state, simulation_content, walk)
	}
	testing.expect(t, state.players[0].field.position != start, "the flight moves")
	testing.expect_value(t, state.records.statistics.distance_walked_millimetres, 0)
	state.players[0].field.flying = false
	for _ in 0 ..< 120 {
		tick_field_test_simulation(state, simulation_content, walk)
	}
	testing.expectf(t, state.records.statistics.distance_walked_millimetres > 1000, "walked %d mm", state.records.statistics.distance_walked_millimetres)
}

// Place with a stone furnace held over the bare ground in front of the
// pod (0201): the tool line says what bare_ground_line reads there, and
// Place either stands the furnace on a new frame of its own with no
// foundation, its footprint centred on cell (0, 0, 0) (0215), or raises
// one Too_Steep event and places nothing, as the ghost's refusal says.
@(test)
test_a_machine_on_bare_ground_stands_centred_on_its_frame :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	player := &state.players[0]
	// Out of the pod first (0221: the airlock is crawled through).
	move_test_players_out_of_the_pod(state, simulation_content.machines)
	for _ in 0 ..< 90 {
		tick_field_test_simulation(state, simulation_content, Input_Frame{move = {0, 1}, pressed = {.Move}})
	}
	furnace := test_machine(simulation_content.machines, "stone_furnace")
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{simulation_content.machines.machines[furnace].item, 1}
	tick_field_test_simulation(state, simulation_content, Input_Frame{look_delta = {0, 300}})
	testing.expect_value(t, player.field.tool, Field_Held_Tool.Machine)
	testing.expect(t, player.field.target.hit && !player.field.frame_target.hit, "the ground is aimed at")
	placement, bare := field_bare_ground_placement(player.field, furnace, simulation_content.machines)
	testing.expect(t, bare)
	testing.expect_value(t, placement.cell, World_Coordinate{-4, 0, -4})
	reading := bare_ground_line(state, simulation_content, player.field)
	testing.expect(t, reading != .None, "a furnace does not stand on the ground for good")
	refusal := field_placement_refusal(state, simulation_content, player^, placement)
	testing.expect_value(t, refusal == .Too_Steep, reading == .Too_Steep)
	frame, cell, _ := field_placement_frame(&state.world.entities.frames, placement, simulation_content.field.foundation_pitch_millimetres)
	size := rotated_footprint_size(simulation_content.machines.machines[furnace].footprint, placement.rotation)
	flat := bare_ground_is_flat(&state.field.world, state.field.spacing_millimetres, frame, size, simulation_content.field.bare_ground.flatness_millimetres, cell)
	testing.expect_value(t, flat, refusal != .Too_Steep)
	line, shown := field_tool_line(player.field, simulation_content, reading)
	testing.expect(t, shown)
	expected := reading == .Too_Steep ? text("field_refused_too_steep") : bare_ground_wear_line(config.bare_ground_life_minutes)
	testing.expect_value(t, line, expected)
	clear(&state.events)
	frames_before := len(state.world.entities.frames.frames)
	tick_field_test_simulation(state, simulation_content, Input_Frame{pressed = {.Place}, just_pressed = {.Place}})
	tick_field_test_simulation(state, simulation_content, {})
	if reading == .Too_Steep {
		testing.expect_value(t, count_field_refused_events(state.events[:], .Too_Steep), 1)
		testing.expect_value(t, len(state.world.entities.frames.frames), frames_before)
		return
	}
	testing.expect_value(t, len(state.world.entities.frames.frames), frames_before + 1)
	testing.expect_value(t, inventory_count(player.inventory, simulation_content.machines.machines[furnace].item), 0)
	placed := state.world.entities.frames.frames[frames_before]
	common := entity_common(&state.world.entities, entity_at(&state.world.entities, {}, placed.id))
	testing.expect(t, common != nil && common.machine == furnace && !common.founded, "the furnace stands unfounded on its own frame")
	testing.expect_value(t, common.origin, World_Coordinate{-4, 0, -4})
}

// The pure rule: told when new against the last tick or on a press.
@(test)
test_a_field_refusal_is_news_when_new_or_pressed :: proc(t: ^testing.T) {
	testing.expect(t, !field_refusal_is_news(.None, .Tool_Tier, true))
	testing.expect(t, field_refusal_is_news(.Tool_Tier, .None, false))
	testing.expect(t, !field_refusal_is_news(.Tool_Tier, .Tool_Tier, false))
	testing.expect(t, field_refusal_is_news(.Tool_Tier, .Tool_Tier, true))
	testing.expect(t, field_refusal_is_news(.No_Vein, .Tool_Tier, false))
}

// Work item 0194 on the field: Open_Aimed (the inventory binding routed
// on the press) at a furnace's frame cell opens it; A's Interact there
// opens nothing and keeps its Jump; at a power switch Interact turns it
// and takes the Jump.
@(test)
test_the_field_opens_a_panel_on_open_aimed_and_turns_a_switch_on_interact :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	feet := state.players[0].field.position
	frame := add_frame(&state.world.entities.frames, feet + {0, 0, 5 * POSITION_UNITS_PER_METRE}, frame_axes({0, UNIT_VECTOR_ONE, 0}, 0), 500)
	entities := &state.world.entities
	furnace := add_entity(entities, simulation_content.machines, test_machine(simulation_content.machines, "steel_furnace"), {}, 0, frame)
	power_switch := add_entity(entities, simulation_content.machines, test_machine(simulation_content.machines, "power_switch"), {3, 0, 0}, 0, frame)
	aim := proc(state: ^Simulation_State, frame: Frame_Id, handle: Entity_Handle) {
		state.players[0].field.frame_target = Frame_Raycast_Hit{hit = true, frame = frame, occupant = {handle = entity_occupant_handle(handle)}}
	}
	events_of := proc(state: ^Simulation_State) -> (events: Player_Events) {
		for event in state.events {
			events += {event.kind}
		}
		return events
	}
	interact := Input_Frame{pressed = {.Jump, .Interact}, just_pressed = {.Jump, .Interact}}

	aim(state, frame, furnace)
	clear(&state.events)
	actions_before := state.records.statistics.world_actions
	tick_field_test_simulation(state, simulation_content, Input_Frame{just_pressed = {.Open_Aimed}})
	testing.expect(t, .Open_Machine in events_of(state))
	testing.expect_value(t, state.records.statistics.world_actions, actions_before + 1)
	testing.expect_value(t, state.players[0].open_machine, furnace)

	state.players[0].open_machine = NO_ENTITY
	aim(state, frame, furnace)
	testing.expect(t, .Jump in without_field_interact_jump(state.players[0], entities, simulation_content.machines, interact).just_pressed)
	clear(&state.events)
	tick_field_test_simulation(state, simulation_content, interact)
	testing.expect_value(t, events_of(state) & {.Open_Machine, .Toggled_Switch}, Player_Events{})
	testing.expect_value(t, state.players[0].open_machine, NO_ENTITY)

	aim(state, frame, power_switch)
	testing.expect(t, .Jump not_in without_field_interact_jump(state.players[0], entities, simulation_content.machines, interact).just_pressed)
	was_on := pool_get(&entities.poles, power_switch).on
	clear(&state.events)
	tick_field_test_simulation(state, simulation_content, interact)
	testing.expect(t, .Toggled_Switch in events_of(state))
	testing.expect_value(t, pool_get(&entities.poles, power_switch).on, !was_on)
	testing.expect_value(t, state.records.statistics.world_actions, actions_before + 2)
	testing.expect_value(t, state.players[0].open_machine, NO_ENTITY)
}

// Work item 0196: field_simulation.pad_foundation names a machine of kind
// foundation; the shipped one is the wooden foundation.
@(test)
test_the_pad_foundation_must_be_a_foundation :: proc(t: ^testing.T) {
	machines := make_test_machines()
	testing.expect(t, field_pad_foundation_problem({pad_foundation = "no_such_machine"}, machines) != "")
	testing.expect(t, field_pad_foundation_problem({pad_foundation = "stone_furnace"}, machines) != "")
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect(t, error == nil)
	testing.expect_value(t, shipped.field_simulation.pad_foundation, "wooden_foundation")
	testing.expect_value(t, field_pad_foundation_problem(shipped.field_simulation, machines), "")
}

// Work item 0210: a field world's quest reward target is the pod's
// locker, and a save round trips it. The load derives it again from the
// pools; an equal hash shows the load's settle moved no baseline.
@(test)
test_a_field_world_save_round_trips_the_reward_target :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	simulation_content := field_test_content(session, content)
	state := &session.simulation
	tick_field_test_simulation(state, simulation_content, {})
	tick_field_test_simulation(state, simulation_content, {})
	locker, locker_found := pod_locker(&state.world.entities, simulation_content.machines)
	testing.expect(t, locker_found, "the pod has a locker")
	testing.expect_value(t, state.quests.reward_target, locker)
	testing.expect(t, state.quests.reward_target != state.quests.capsule, "the target is the capsule")
	capsule := state.quests.capsule
	add_to_slots(entity_slots(&state.world.entities, locker), test_item(simulation_content.items, "coal"), 3, item_stack_size(simulation_content.items, test_item(simulation_content.items, "coal")))
	tick_field_test_simulation(state, simulation_content, {})
	hash := simulation_state_hash(state)
	files := encode_save_files(state, simulation_content, "round trip", 0)
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
	stage_generated_field_set(restored)
	testing.expect(t, restore_arrived_field_set(&restored.field), "the staged set restores")
	testing.expect_value(t, restored.quests.reward_target, locker)
	testing.expect_value(t, restored.quests.capsule, capsule)
	testing.expect_value(t, simulation_state_hash(restored), hash)
}

// The sneak toggle's frames (0218): a press, 20 frames without, a press,
// 10 frames without.
sneak_toggle_test_frame :: proc(tick: int) -> Input_Frame {
	frame := Input_Frame{sneak_toggles = true}
	if tick == 0 || tick == 21 {
		frame.pressed, frame.just_pressed = {.Sneak}, {.Sneak}
	}
	return frame
}

SNEAK_TOGGLE_TEST_TICKS :: 32

@(test)
test_the_sneak_toggle_crouches_the_field_player :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	for tick in 0 ..< SNEAK_TOGGLE_TEST_TICKS {
		tick_field_test_simulation(&session.simulation, simulation_content, sneak_toggle_test_frame(tick))
		player := session.simulation.players[0]
		toggled_on := tick <= 20
		testing.expectf(t, player.sneaking == toggled_on, "tick %d: sneaking %v", tick, player.sneaking)
		testing.expectf(t, player.field.crouching == toggled_on, "tick %d: crouching %v", tick, player.field.crouching)
	}
}

@(test)
test_the_field_prediction_crouches_as_the_tick :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	simulation_content := field_test_content(session, content)
	// Settled first: the first ticks of a new world drop the player onto
	// the cabin's floor, which the motion alone does not predict.
	for _ in 0 ..< 30 {
		tick_field_test_simulation(&session.simulation, simulation_content, {})
	}
	for tick in 0 ..< SNEAK_TOGGLE_TEST_TICKS {
		frame := sneak_toggle_test_frame(tick)
		predicted := session.simulation.players[0]
		predict_field_player_motion(&session.simulation, simulation_content, &predicted, frame)
		tick_field_test_simulation(&session.simulation, simulation_content, frame)
		ticked := session.simulation.players[0]
		testing.expectf(t, predicted.sneaking == ticked.sneaking, "tick %d: sneaking %v predicted, %v ticked", tick, predicted.sneaking, ticked.sneaking)
		testing.expectf(t, predicted.field.crouching == ticked.field.crouching, "tick %d: crouching %v predicted, %v ticked", tick, predicted.field.crouching, ticked.field.crouching)
		testing.expectf(t, predicted.field.position == ticked.field.position, "tick %d: feet %v predicted, %v ticked", tick, predicted.field.position, ticked.field.position)
	}
}

@(test)
test_the_crouch_changes_the_state_hash :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	session := start_field_test_session(config, content)
	defer end_session(session)
	before := simulation_state_hash(&session.simulation)
	session.simulation.players[0].field.crouching = true
	testing.expect(t, simulation_state_hash(&session.simulation) != before, "the crouch is hashed")
}

// Lines 1, 2, 3, 6, 7, 8, 9, 11, 12, 13 and 20 of 0230's table of the
// pod's volumes in the file's frame: the hull's lower wall with the door
// gap, the cone, the plug, the floor plate, the drum housing, the fairing
// round the outer door and the chair.
test_pod_volume_definitions :: proc() -> []Collision_Volume_Definition {
	definitions := make([]Collision_Volume_Definition, 11, context.temp_allocator)
	definitions[0] = {kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 2.2, 0}, radius_from = 5, radius_to = 5, shell = 0.4, sector = []f64{102.6, 77.4}}
	definitions[1] = {kind = "round", axis = "y", from = {0, 2.2, 0}, to = {0, 6.8, 0}, radius_from = 5, radius_to = 2.4125, shell = 0.2875}
	definitions[2] = {kind = "round", axis = "y", from = {0, 6.2, 0}, to = {0, 6.8, 0}, radius_from = 2.75, radius_to = 2.4125}
	definitions[3] = {kind = "round", axis = "y", from = {0, 0, 0}, to = {0, 0.006, 0}, radius_from = 4.6, radius_to = 4.6}
	definitions[4] = {kind = "box", from = {1.12, 0, -1.75}, to = {4.6, 2.75, -1}}
	definitions[5] = {kind = "box", from = {1.12, 0, 1}, to = {4.6, 2.75, 1.75}}
	definitions[6] = {kind = "box", from = {1.12, 2, -1}, to = {4.6, 2.75, 1}}
	definitions[7] = {kind = "box", from = {3.9, 0, -1.8}, to = {5, 4, -1}}
	definitions[8] = {kind = "box", from = {3.9, 0, 1}, to = {5, 4, 1.8}}
	definitions[9] = {kind = "box", from = {3.9, 2, -1}, to = {5, 4, 1}}
	definitions[10] = {kind = "box", from = {-2.97, 0, 0.06}, to = {-1.03, 1.1, 1.82}}
	return definitions
}

// Two sessions whose pod collides by its volumes (work item 0230) walk
// round the hull and crawl into the airlock on the same input and hash
// alike; a third, standing still, hashes otherwise.
@(test)
test_two_sessions_hash_alike_walking_round_and_into_a_pod_with_volumes :: proc(t: ^testing.T) {
	config := test_field_game_config()
	content := make_field_test_game_content()
	pod_id := find_machine_of_kind(content.machines, .Pod)
	content.machines.machines[pod_id].collision = resolve_collision_volumes(test_pod_volume_definitions(), context.temp_allocator)
	sessions: [3]^Session
	contents: [3]Simulation_Content
	for &session, index in sessions {
		session = start_field_test_session(config, content)
		contents[index] = field_test_content(session, content)
		stage_generated_field_set(&session.simulation)
		move_test_players_out_of_the_pod(&session.simulation, contents[index].machines)
	}
	defer for session in sessions {
		end_session(session)
	}
	state := &sessions[0].simulation
	pod, frame, found := find_test_pod(&state.world.entities, contents[0].machines)
	testing.expect(t, found && len(state.world.entities.frames.bodies) == 1)
	if !found || len(state.world.entities.frames.bodies) != 1 {
		return
	}
	body := state.world.entities.frames.bodies[0]
	doorstep := state.players[0].field.position
	tick_all :: proc(sessions: [3]^Session, contents: [3]Simulation_Content, frame: Input_Frame, still_third: bool) {
		for session, index in sessions {
			tick_field_test_simulation(&session.simulation, contents[index], still_third && index == 2 ? Input_Frame{} : frame)
		}
	}
	expect_alike :: proc(t: ^testing.T, sessions: [3]^Session, label: string, tick: int) {
		testing.expectf(t, simulation_state_hash(&sessions[0].simulation) == simulation_state_hash(&sessions[1].simulation), "%s tick %d: the hashes part", label, tick)
	}
	for _ in 0 ..< 30 {
		tick_all(sessions, contents, {}, true)
	}
	hull := body.volumes[0].radius_from
	met_hull := false
	walk := Input_Frame{move = {0, 1}, look_delta = {60, 0}, pressed = {.Move}}
	for tick in 0 ..< 360 {
		tick_all(sessions, contents, walk, true)
		radius := test_body_radius(body, state.players[0].field.position)
		met_hull = met_hull || abs(radius - hull) <= metres_to_position_units(1)
		if tick % 60 == 59 {
			expect_alike(t, sessions, "walk", tick)
		}
	}
	testing.expect(t, met_hull, "the walk round never came within 1 m of the hull")
	for session in sessions[:2] {
		for &player in session.simulation.players {
			move_field_player_body(&player.field, make_field_player(doorstep, -frame.axes[FRAME_FORWARD]))
		}
	}
	machine := contents[0].machines.machines[pod.machine]
	entered := false
	crawl := Input_Frame{move = {0, 1}, pressed = {.Move, .Sneak}}
	for tick in 0 ..< 900 {
		tick_all(sessions, contents, crawl, true)
		cell := frame_cell_of_feet(frame, state.players[0].field)
		for box in 0 ..< machine.open_cell_box_count {
			for candidate in test_pod_box_cells(machine, box) {
				entered = entered || candidate == cell
			}
		}
		if tick % 60 == 59 {
			expect_alike(t, sessions, "crawl", tick)
		}
	}
	testing.expect(t, entered, "the crawl never entered the airlock, the lane or the cabin")
	expect_alike(t, sessions, "end", 1290)
	testing.expect(t, simulation_state_hash(&sessions[0].simulation) != simulation_state_hash(&sessions[2].simulation), "the still session hashes alike")
}
