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

// A field world's save round trips an edited chunk, a torch, a frame
// with a foundation, the pod with its pad, the light's queues and the
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
	foundation := field_foundation(simulation_content)
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

// A new field world lays the pod at the home with its door to the spring,
// and a player joining it spawns as the first did, in front of the door
// (past the pad's front edge, off every pad cell), facing the spring,
// with the starter kit, through the entry every join takes
// (add_player_entry).
@(test)
test_a_new_world_places_the_pod_and_players_spawn_at_its_door :: proc(t: ^testing.T) {
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
	testing.expect_value(t, pod.origin, pod_origin(content.machines.machines[pod.machine]))
	testing.expect_value(t, frame_cell_count(&state.world.entities.frames, frame.id), POD_PAD_SIZE * POD_PAD_SIZE + int(pod.size.x * pod.size.y * pod.size.z))
	generation := make_planet_generation(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	site, heading := field_home_site(generation, state.world.planet)
	// Cell (0, 0, 0) stands on the site (free_frame_at), within rounding.
	standing := World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	testing.expectf(t, vector_length(cast([3]i64)(frame_cell_centre(frame, {}) - site - standing)) <= 4, "the pod's frame stands %v off the site", frame_cell_centre(frame, {}) - site)
	testing.expectf(t, fixed_dot(frame.axes[FRAME_FORWARD], heading) > UNIT_VECTOR_ONE * 990 / 1000, "the door faces %v against the spring's heading %v", frame.axes[FRAME_FORWARD], heading)
	add_player_entry(state, field_test_content(session, content), 1, Player_Start{})
	testing.expect_value(t, len(state.players), 2)
	home := field_home_player(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres, config.foundation_pitch_millimetres)
	for player in state.players {
		testing.expect_value(t, player.field.position, home.position)
		testing.expect_value(t, player.field.forward, home.forward)
		cell := world_to_frame_cell(frame, player.field.position)
		testing.expectf(t, cell.z >= POD_PAD_FIRST_CELL + POD_PAD_SIZE, "the player stands in pad row %d", cell.z)
		testing.expectf(t, cell.x >= POD_PAD_FIRST_CELL && cell.x < POD_PAD_FIRST_CELL + POD_PAD_SIZE, "the player stands beside the pad, column %d", cell.x)
		testing.expectf(t, fixed_dot(player.field.forward, frame.axes[FRAME_FORWARD]) > UNIT_VECTOR_ONE * 990 / 1000, "the player faces %v, not the spring", player.field.forward)
		for starting in config.starting_items {
			testing.expectf(t, inventory_count(player.inventory, test_item(content.items, starting.item)) == starting.count, "%s", starting.item)
		}
	}
}

// A pad of foundations on a free frame at the surface position, eleven
// cells along +x and two across: room for a drill at (0, 1, 0) facing
// +x, its drop cell (2, 1, 0), and an arm whose reach spans four cells
// at the data's pitch (inserter_reach_on_frame) at (6, 1, 0), dropping at
// (10, 1, 0).
TEST_FIELD_PAD_LENGTH :: 11

lay_test_field_pad :: proc(state: ^Simulation_State, content: Simulation_Content, surface: World_Position) -> Frame_Id {
	entities := &state.world.entities
	foundation := field_foundation(content)
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

// The pure rule: told when new against the last tick or on a press.
@(test)
test_a_field_refusal_is_news_when_new_or_pressed :: proc(t: ^testing.T) {
	testing.expect(t, !field_refusal_is_news(.None, .Tool_Tier, true))
	testing.expect(t, field_refusal_is_news(.Tool_Tier, .None, false))
	testing.expect(t, !field_refusal_is_news(.Tool_Tier, .Tool_Tier, false))
	testing.expect(t, field_refusal_is_news(.Tool_Tier, .Tool_Tier, true))
	testing.expect(t, field_refusal_is_news(.No_Vein, .Tool_Tier, false))
}
