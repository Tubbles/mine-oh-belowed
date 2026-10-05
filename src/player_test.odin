package game

import "core:log"
import "core:slice"
import "core:testing"
import "generation_seed"

TEST_TICK_RATE :: 60

test_game_config :: proc() -> Game_Config {
	return Game_Config{name = "test", tick_rate = TEST_TICK_RATE, day_length_seconds = 1200, field_simulation = {chunk_radius = 2, chunk_margin = 1, torch_item = "torch", torch_emitter = "torch", pad_foundation = "wooden_foundation"}}
}

// The test config with the shipped field blocks of data/game.sjson (the
// view, the player, the brushes, the water, the foundations, the runs and
// the simulated set), for the field sessions (0179).
test_field_game_config :: proc() -> Game_Config {
	shipped, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	config := test_game_config()
	config.field_view = shipped.field_view
	config.field_player = shipped.field_player
	config.field_brushes = shipped.field_brushes
	config.field_water = shipped.field_water
	config.foundation_pitch_millimetres = shipped.foundation_pitch_millimetres
	config.belt_runs = shipped.belt_runs
	config.field_simulation = shipped.field_simulation
	config.starting_items = shipped.starting_items
	config.bare_ground_flatness_millimetres = shipped.bare_ground_flatness_millimetres
	config.bare_ground_life_minutes = shipped.bare_ground_life_minutes
	config.salvage_percent = shipped.salvage_percent
	config.pod_airlock = shipped.pod_airlock
	return config
}

// Test worlds span chunks -1 and 0 on every axis, so blocks -32 to 31.
TEST_WORLD_CHUNKS :: [8]Chunk_Coordinate{{-1, -1, -1}, {0, -1, -1}, {-1, 0, -1}, {0, 0, -1}, {-1, -1, 0}, {0, -1, 0}, {-1, 0, 0}, {0, 0, 0}}

test_block :: proc(registry: Block_Registry, name: string) -> Block_Id {
	block, found := find_block_id(registry, name)
	assert(found, name)
	return block
}

// Stone at y 0 for every x below floor_end_x, so the floor top is at y 1.
make_floor_world :: proc(registry: Block_Registry, floor_end_x: i32) -> World {
	chunks := TEST_WORLD_CHUNKS
	world := make_test_world(chunks[:])
	stone := test_block(registry, "stone")
	for x in i32(-32) ..< floor_end_x {
		for z in i32(-32) ..< 32 {
			world_set_block(&world, {x, 0, z}, stone)
		}
	}
	return world
}

set_blocks :: proc(world: ^World, block: Block_Id, positions: ..World_Coordinate) {
	for position in positions {
		world_set_block(world, position, block)
	}
}

make_test_player :: proc(registry: Block_Registry, position: [3]f32) -> Player {
	return make_player(Player_Start{position = position}, context.temp_allocator)
}

tick_test_player :: proc(world: ^World, records: ^Game_Records, registry: Block_Registry, player: ^Player, input: Input_Frame, ticks: int) -> (events: Player_Events) {
	content := make_test_content()
	content.blocks = registry
	for _ in 0 ..< ticks {
		events += tick_player(world, records, content, slice.from_ptr(player, 1), 0, input, TEST_TICK_RATE, 0)
	}
	return events
}

WALK_FORWARD :: Input_Frame {
	move = {0, 1},
}

@(test)
test_player_walks_into_wall_and_stops_flush :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, test_block(registry, "stone"), {3, 1, 0}, {3, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, WALK_FORWARD, 120)
	testing.expectf(t, abs(player.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", player.position.x)
	testing.expect_value(t, player.velocity.x, 0)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
}

@(test)
test_player_falls_onto_floor_and_lands_on_top :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 20, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 180)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
	testing.expect_value(t, player.velocity.y, 0)
}

@(test)
test_player_jump_reaches_one_block_not_two :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	tick_test_player(&world, &records, registry, &player, Input_Frame{pressed = {.Jump}}, 1)
	apex := player.position.y
	for _ in 0 ..< 60 {
		tick_test_player(&world, &records, registry, &player, {}, 1)
		apex = max(apex, player.position.y)
	}
	testing.expectf(t, apex - 1 > 1 && apex - 1 < 1.5, "apex %v", apex - 1)
	testing.expect(t, player.on_ground)
}

@(test)
test_player_climbs_one_block_step_but_not_two :: proc(t: ^testing.T) {
	registry := make_test_registry()
	stone := test_block(registry, "stone")
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, stone, {3, 1, 0}, {3, 1, 2}, {3, 2, 2})
	input := Input_Frame {
		move    = {0, 1},
		pressed = {.Jump},
	}
	low := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &low, input, 90)
	testing.expectf(t, low.position.x > 3.3, "x %v", low.position.x)
	high := make_test_player(registry, {0.5, 1, 2.5})
	tick_test_player(&world, &records, registry, &high, input, 90)
	testing.expectf(t, high.position.x < 3, "x %v", high.position.x)
}

@(test)
test_sneaking_stops_at_edge :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 3)
	records: Game_Records
	sneaking := Input_Frame {
		move    = {0, 1},
		pressed = {.Sneak},
	}
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	tick_test_player(&world, &records, registry, &player, sneaking, 240)
	testing.expectf(t, player.position.x > 3 && player.position.x < 3 + PLAYER_WIDTH / 2, "x %v", player.position.x)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
	walking := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &walking, WALK_FORWARD, 120)
	testing.expect(t, walking.position.y < 0)
}

@(test)
test_player_waits_for_missing_ground_chunk :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({})
	records: Game_Records
	player := make_test_player(registry, {0.5, 20, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 60)
	testing.expect_value(t, player.position.y, 20)
	testing.expect_value(t, player.velocity.y, 0)
}

@(test)
test_player_inside_blocks_rises_out :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, test_block(registry, "log"), {0, 1, 0}, {0, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 30)
	testing.expectf(t, abs(player.position.y - 3) < 1e-3, "y %v", player.position.y)
	testing.expect(t, player.on_ground)
}

@(test)
test_fly_mode_ignores_gravity_and_blocks :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, test_block(registry, "stone"), {3, 1, 0}, {3, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, Input_Frame{just_pressed = {.Toggle_Fly_Mode, .Toggle_No_Clip}}, 1)
	testing.expect(t, player.flying)
	testing.expect(t, player.no_clip)
	tick_test_player(&world, &records, registry, &player, WALK_FORWARD, 60)
	testing.expectf(t, abs(player.position.x - (0.5 + FLY_CAMERA_SPEED)) < 1e-2, "x %v", player.position.x)
	testing.expect_value(t, player.position.y, 1)
}

// 0112: without no clip, flight stops at blocks on every axis.
@(test)
test_flying_without_no_clip_stops_at_blocks :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, test_block(registry, "stone"), {3, 1, 0}, {3, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, Input_Frame{just_pressed = {.Toggle_Fly_Mode}}, 1)
	testing.expect(t, player.flying)
	testing.expect(t, !player.no_clip)
	tick_test_player(&world, &records, registry, &player, WALK_FORWARD, 60)
	testing.expectf(t, abs(player.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", player.position.x)
	testing.expect_value(t, player.velocity.x, 0)
	testing.expect_value(t, player.position.y, 1)
	player.position = {0.5, 3, 0.5}
	tick_test_player(&world, &records, registry, &player, Input_Frame{pressed = {.Sneak}}, 60)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
	testing.expect(t, player.flying)
}

JUMP_TAP :: Input_Frame {
	pressed      = {.Jump},
	just_pressed = {.Jump},
	developer    = true,
}

// Two Jump presses gap_ticks apart, the frames between them empty.
double_tap_jump :: proc(world: ^World, records: ^Game_Records, registry: Block_Registry, player: ^Player, tap: Input_Frame, gap_ticks: int) {
	tick_test_player(world, records, registry, player, tap, 1)
	tick_test_player(world, records, registry, player, Input_Frame{developer = tap.developer}, gap_ticks - 1)
	tick_test_player(world, records, registry, player, tap, 1)
}

// 0112: a Jump double tap toggles flying in developer mode only.
@(test)
test_double_tap_jump_toggles_flying :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	double_tap_jump(&world, &records, registry, &player, JUMP_TAP, JUMP_DOUBLE_TAP_TICKS)
	testing.expect(t, player.flying)
	testing.expect_value(t, player.jump_tap_ticks, 0)
	double_tap_jump(&world, &records, registry, &player, JUMP_TAP, 5)
	testing.expect(t, !player.flying)
}

@(test)
test_slow_double_tap_jump_does_not_fly :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	double_tap_jump(&world, &records, registry, &player, JUMP_TAP, JUMP_DOUBLE_TAP_TICKS + 1)
	testing.expect(t, !player.flying)
}

@(test)
test_double_tap_jump_without_developer_does_not_fly :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	tap := JUMP_TAP
	tap.developer = false
	double_tap_jump(&world, &records, registry, &player, tap, 5)
	testing.expect(t, !player.flying)
}

@(test)
test_toggle_camera_mode :: proc(t: ^testing.T) {
	player: Player
	apply_player_toggles(&player, {.Toggle_Camera_Mode})
	testing.expect_value(t, player.camera_mode, Camera_Mode.Third_Person)
	apply_player_toggles(&player, {.Toggle_Camera_Mode})
	testing.expect_value(t, player.camera_mode, Camera_Mode.First_Person)
}

@(test)
test_interpolated_pose :: proc(t: ^testing.T) {
	testing.expect_value(t, angle_difference(350, 10), 20)
	testing.expect_value(t, angle_difference(10, 350), -20)
	player := Player {
		previous_position = {0, 0, 0},
		position          = {2, 4, 0},
		previous_yaw      = 350,
		yaw               = 10,
		previous_pitch    = -10,
		pitch             = 10,
	}
	pose := interpolate_player_pose(player, 0.5)
	testing.expect_value(t, pose.position, [3]f32{1, 2, 0})
	testing.expect_value(t, pose.yaw, 360)
	testing.expect_value(t, pose.pitch, 0)
}

@(test)
test_third_person_camera_pulls_in_before_a_wall :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	eye := [3]f32{0.5, 2.6, 0.5}
	free := third_person_position(&world, registry, eye, third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE, 0))
	testing.expectf(t, abs(free.x - (0.5 - THIRD_PERSON_DISTANCE)) < 1e-3, "x %v", free.x)
	for y in i32(1) ..= 6 {
		set_blocks(&world, test_block(registry, "stone"), {-2, y, 0})
	}
	blocked := third_person_position(&world, registry, eye, third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE, 0))
	testing.expectf(t, blocked.x > -1 && blocked.x < 0.5, "x %v", blocked.x)
}

// Stone half a metre behind the eye pulls the camera in to about 0.31 m,
// within VIEWER_BODY_HIDDEN_WITHIN_METRES, and the body is hidden; stone
// 1.5 m behind leaves it about 1.33 m out, and the body is shown (0261).
@(test)
test_the_block_viewers_body_is_hidden_when_the_camera_reaches_the_eye :: proc(t: ^testing.T) {
	registry := make_test_registry()
	eye := [3]f32{0.5, 2.6, 0.5}
	near_world := make_floor_world(registry, 32)
	for y in i32(1) ..= 6 {
		set_blocks(&near_world, test_block(registry, "stone"), {-1, y, 0})
	}
	near := third_person_position(&near_world, registry, eye, third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE, 0))
	testing.expectf(t, !viewer_body_shown(.Third_Person, near, eye), "the body is shown with the camera at %v", near)
	far_world := make_floor_world(registry, 32)
	for y in i32(1) ..= 6 {
		set_blocks(&far_world, test_block(registry, "stone"), {-2, y, 0})
	}
	far := third_person_position(&far_world, registry, eye, third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE, 0))
	testing.expectf(t, viewer_body_shown(.Third_Person, far, eye), "the body is hidden with the camera at %v", far)
}

// Fixed input: look down and dig for five seconds, climb back out by
// jumping and placing under the feet, look up, then a pseudo random mix of
// walking, turning, jumping, mining, placing and cycling the selection.
recorded_input :: proc(tick: int) -> Input_Frame {
	switch {
	case tick < 15:
		return Input_Frame{look_delta = {0, 40}}
	case tick < 300:
		return Input_Frame{pressed = {.Mine}}
	case tick < 600:
		return Input_Frame{pressed = {.Jump}, just_pressed = {.Place}}
	case tick < 615:
		return Input_Frame{look_delta = {0, -30}}
	}
	random := generation_seed.hash_u64(u64(tick) / 20)
	input := Input_Frame {
		move       = {f32(random % 3) - 1, 1},
		look_delta = {f32(random / 3 % 41) - 20, f32(random / 123 % 21) - 10},
	}
	if random / 2583 % 4 == 0 {
		input.pressed += {.Jump}
	}
	if random / 10332 % 3 == 0 {
		input.pressed += {.Mine}
	}
	if random / 30996 % 2 == 0 {
		input.pressed += {.Sprint_Hold}
	}
	if tick % 20 == 0 && random / 61992 % 2 == 0 {
		input.just_pressed += {.Place, .Hotbar_Next}
	}
	return input
}

make_generated_world :: proc(generator: ^Generator, centre: Chunk_Coordinate) -> World {
	world: World
	for y in i32(-1) ..= 1 {
		for z in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				generated := generate_chunk(generator, centre + {x, y, z})
				world.chunks[generated.chunk.coordinate] = generated.chunk
				delete(generated.veins)
				delete(generated.outcrops)
				delete(generated.crates)
			}
		}
	}
	return world
}

make_generated_simulation :: proc(generator: ^Generator, content: Simulation_Content) -> Simulation_State {
	surface := World_Coordinate{8, terrain_height(generator.seeds, 8, 8), 8}
	_, technologies := make_test_recipes(content.items)
	simulation := make_simulation(test_game_config(), player_start_on(surface), content, technologies, false, {})
	generated := make_generated_world(generator, world_to_chunk_coordinate(surface))
	simulation.world = generated
	return simulation
}

owned_total :: proc(player: Player) -> int {
	total := 0
	for slot in player.inventory.slots {
		total += int(slot.count)
	}
	return total
}

@(test)
test_player_ticks_are_deterministic :: proc(t: ^testing.T) {
	content := make_test_content()
	first_generator := make_test_generator(DEFAULT_WORLD_SEED)
	second_generator := make_test_generator(DEFAULT_WORLD_SEED)
	first := make_generated_simulation(&first_generator, content)
	defer destroy_simulation(&first)
	second := make_generated_simulation(&second_generator, content)
	defer destroy_simulation(&second)
	// Mined blocks reach the hotbar only onto a partial stack there
	// (inventory_add_picked_up), so both start with one dirt to pillar with.
	dirt := test_item(content.items, "dirt")
	first.players[0].inventory.slots[0] = Item_Stack{dirt, 1}
	second.players[0].inventory.slots[0] = Item_Stack{dirt, 1}
	start := first.players[0].position
	placed_count := 0
	for tick in 0 ..< 1200 {
		input := recorded_input(tick)
		owned_before := owned_total(first.players[0])
		simulation_tick(&first, content, {input})
		simulation_tick(&second, content, {input})
		placed_count += owned_total(first.players[0]) < owned_before ? 1 : 0
	}
	a, b := first.players[0], second.players[0]
	testing.expect_value(t, transmute([3]u32)a.position, transmute([3]u32)b.position)
	testing.expect_value(t, transmute([3]u32)a.velocity, transmute([3]u32)b.velocity)
	testing.expect_value(t, transmute(u32)a.yaw, transmute(u32)b.yaw)
	testing.expect_value(t, transmute(u32)a.pitch, transmute(u32)b.pitch)
	testing.expect_value(t, a.selected_hotbar_slot, b.selected_hotbar_slot)
	for slot, index in a.inventory.slots {
		testing.expect_value(t, slot, b.inventory.slots[index])
	}
	moved := a.position - start
	log.infof("after 1200 ticks: moved %v, placed %d, hotbar %v, selected %v", moved, placed_count, inventory_hotbar(a.inventory), a.selected_hotbar_slot)
	testing.expectf(t, moved.x * moved.x + moved.z * moved.z > 1, "moved %v", moved)
	testing.expectf(t, placed_count > 0, "nothing placed")
}

// Water above the floor from y 1 to 8 for x 0 to 15: the player sinks
// slowly, walks at half speed and swims up while Jump is held.
@(test)
test_player_swims_in_water :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	water := test_block(registry, "water")
	for y in i32(1) ..= 8 {
		for z in i32(-4) ..= 4 {
			for x in i32(0) ..< 16 {
				world_set_block(&world, {x, y, z}, water)
			}
		}
	}
	player := make_test_player(registry, {2.5, 5, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 30)
	testing.expectf(t, player.velocity.y >= -PLAYER_SINK_SPEED && player.velocity.y < 0, "sinking at %v", player.velocity.y)
	testing.expect(t, player.position.y > 4)

	start_x := player.position.x
	tick_test_player(&world, &records, registry, &player, WALK_FORWARD, 60)
	walked := player.position.x - start_x
	testing.expectf(t, abs(walked - PLAYER_WALK_SPEED * PLAYER_WATER_SPEED_FACTOR) < 0.05, "walked %v in one second", walked)

	start_y := player.position.y
	tick_test_player(&world, &records, registry, &player, Input_Frame{pressed = {.Jump}}, 30)
	testing.expectf(t, player.position.y - start_y > 1, "rose %v", player.position.y - start_y)
}

// 0044: Sprint toggles while moving, a tick without movement ends it, and
// Sprint_Hold (Left Shift) sprints while held regardless of the toggle.
@(test)
test_sprint_toggles_and_stops_with_movement :: proc(t: ^testing.T) {
	moving_press := Input_Frame{move = {0, 1}, just_pressed = {.Sprint}}
	moving := Input_Frame{move = {0, 1}}
	testing.expect(t, update_sprinting(false, moving_press))
	testing.expect(t, update_sprinting(true, moving))
	testing.expect(t, !update_sprinting(true, moving_press))
	testing.expect(t, !update_sprinting(true, Input_Frame{}))
	testing.expect(t, !update_sprinting(false, Input_Frame{just_pressed = {.Sprint}}))
	testing.expect(t, !update_sprinting(false, Input_Frame{move = {0, 1}, pressed = {.Sprint}}))
	testing.expect(t, player_sprints(Player{}, {.Sprint_Hold}))
	testing.expect(t, player_sprints(Player{sprinting = true}, {}))
	testing.expect(t, !player_sprints(Player{}, {.Sprint}))
	testing.expect_value(t, player_walk_speed({}, true), PLAYER_SPRINT_SPEED)
	testing.expect_value(t, player_walk_speed({.Sneak}, true), PLAYER_SNEAK_SPEED)
	testing.expect_value(t, player_walk_speed({}, false), PLAYER_WALK_SPEED)
}

@(test)
test_sprint_press_keeps_the_player_sprinting :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, Input_Frame{move = {0, 1}, just_pressed = {.Sprint}}, 1)
	testing.expect(t, player.sprinting)
	tick_test_player(&world, &records, registry, &player, WALK_FORWARD, 1)
	testing.expect(t, player.sprinting)
	testing.expect(t, abs(player.velocity.x - PLAYER_SPRINT_SPEED) < TEST_TOLERANCE)
	tick_test_player(&world, &records, registry, &player, Input_Frame{}, 1)
	testing.expect(t, !player.sprinting)
}

// 0044: cheat speed triples walking, sprinting and flying.
@(test)
test_cheat_speed_multiplies_movement :: proc(t: ^testing.T) {
	testing.expect_value(t, cheat_speed_factor(false), 1)
	testing.expect_value(t, cheat_speed_factor(true), CHEAT_SPEED_FACTOR)
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	content := make_test_content()
	content.blocks = registry
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_player(&world, &records, content, slice.from_ptr(&player, 1), 0, WALK_FORWARD, TEST_TICK_RATE, 0, true)
	testing.expect(t, abs(player.velocity.x - PLAYER_WALK_SPEED * CHEAT_SPEED_FACTOR) < TEST_TOLERANCE)
	player.flying = true
	tick_player(&world, &records, content, slice.from_ptr(&player, 1), 0, Input_Frame{move = {0, 1}, pressed = {.Sprint_Hold}}, TEST_TICK_RATE, 0, true)
	testing.expect(t, abs(player.velocity.x - FLY_CAMERA_SPEED * FLY_CAMERA_SPRINT_FACTOR * CHEAT_SPEED_FACTOR) < TEST_TOLERANCE)
}

// A bottom slab stops a fall half way up its cell and is ground to stand
// on; an upper slab stops a rising head at its underside.
@(test)
test_sweep_stops_on_a_slab_at_half_height :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, SHAPE_TEST_SLAB, {0, 1, 0})
	set_blocks(&world, SHAPE_TEST_UPPER_SLAB, {0, 4, 0})
	moved, blocked := sweep_box_axis(&world, registry, player_box({0.5, 3, 0.5}), 1, -5)
	testing.expect(t, blocked)
	testing.expectf(t, abs(moved + 1.5) < 1e-4, "moved %v", moved)
	testing.expect(t, box_has_ground(&world, registry, player_box({0.5, 1.5, 0.5})))
	testing.expect(t, !box_has_ground(&world, registry, player_box({0.5, 1.6, 0.5})))
	testing.expect(t, !box_intersects_solid(&world, registry, player_box({0.5, 1.5, 0.5})))
	testing.expect(t, box_intersects_solid(&world, registry, player_box({0.5, 1.4, 0.5})))
	// The head at 1.5 + 1.8 rises to the upper slab's underside at 4.5.
	up, stopped := sweep_box_axis(&world, registry, player_box({0.5, 1.5, 0.5}), 1, 3)
	testing.expect(t, stopped)
	testing.expectf(t, abs(up - (4.5 - 3.3)) < 1e-4, "up %v", up)
	// Walking into the slab from the floor stops at its side; above its
	// top the way is free.
	side, side_blocked := sweep_box_axis(&world, registry, player_box({-1.5, 1, 0.5}), 0, 2)
	testing.expect(t, side_blocked)
	testing.expectf(t, abs(side - 1.2) < 1e-4, "side %v", side)
	_, over_blocked := sweep_box_axis(&world, registry, player_box({-1.5, 1.5, 0.5}), 0, 2)
	testing.expect(t, !over_blocked)
}

@(test)
test_player_falls_onto_a_slab_and_stands_on_it :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, SHAPE_TEST_SLAB, {0, 1, 0})
	player := make_test_player(registry, {0.5, 6, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 120)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1.5) < 1e-3, "y %v", player.position.y)
}

// Stairs rising towards +x: the low half is a slab, the back quarter
// stands a full block high. A torch stops nothing.
@(test)
test_stairs_collide_with_both_boxes_and_torches_not_at_all :: proc(t: ^testing.T) {
	registry := make_shape_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, SHAPE_TEST_STAIRS, {0, 1, 0})
	set_blocks(&world, SHAPE_TEST_TORCH, {0, 1, 3})
	low, low_blocked := sweep_box_axis(&world, registry, player_box({0.2, 3, 0.5}), 1, -5)
	testing.expect(t, low_blocked)
	testing.expectf(t, abs(low + 1.5) < 1e-4, "low %v", low)
	high, high_blocked := sweep_box_axis(&world, registry, player_box({0.8, 3, 0.5}), 1, -5)
	testing.expect(t, high_blocked)
	testing.expectf(t, abs(high + 1) < 1e-4, "high %v", high)
	// Standing on the low step, the back quarter stops the way forward.
	forward, forward_blocked := sweep_box_axis(&world, registry, player_box({0.2, 1.5, 0.5}), 0, 1)
	testing.expect(t, forward_blocked)
	testing.expectf(t, abs(forward) < 1e-4, "forward %v", forward)
	_, torch_blocked := sweep_box_axis(&world, registry, player_box({-1.5, 1, 3.5}), 0, 4)
	testing.expect(t, !torch_blocked)
}

// 0074: the sneak_hold and sprint_hold settings ride in the frame.
@(test)
test_hold_settings_reach_the_frame :: proc(t: ^testing.T) {
	defaults := world_input(Input_Frame{pressed = {.Sneak}}, false, {}, DEFAULT_SETTINGS, false)
	testing.expect(t, !defaults.sneak_toggles)
	testing.expect(t, !defaults.sprint_holds)
	testing.expect_value(t, defaults.pressed, Action_Set{.Sneak})
	settings := DEFAULT_SETTINGS
	settings.sneak_hold = .Toggle
	settings.sprint_hold = .Hold
	open := world_input(Input_Frame{}, false, {}, settings, false)
	testing.expect(t, open.sneak_toggles)
	testing.expect(t, open.sprint_holds)
	// Also while a screen is open, so a toggled sneak outlasts it.
	blocked := world_input(Input_Frame{}, true, {}, settings, false)
	testing.expect(t, blocked.sneak_toggles)
	testing.expect(t, blocked.sprint_holds)
}

// 0112: developer mode rides in the frame in both branches.
@(test)
test_developer_mode_reaches_the_frame :: proc(t: ^testing.T) {
	testing.expect(t, world_input(Input_Frame{}, false, {}, DEFAULT_SETTINGS, true).developer)
	testing.expect(t, world_input(Input_Frame{}, true, {}, DEFAULT_SETTINGS, true).developer)
	testing.expect(t, !world_input(Input_Frame{}, false, {}, DEFAULT_SETTINGS, false).developer)
}

@(test)
test_sneak_hold_and_toggle :: proc(t: ^testing.T) {
	// Hold: sneaking follows the button.
	testing.expect(t, update_sneaking(false, Input_Frame{pressed = {.Sneak}}))
	testing.expect(t, !update_sneaking(true, Input_Frame{}))
	// Toggle: a press flips it, holding or releasing does not.
	toggle := Input_Frame{sneak_toggles = true}
	pressed := toggle
	pressed.pressed, pressed.just_pressed = {.Sneak}, {.Sneak}
	held := toggle
	held.pressed = {.Sneak}
	testing.expect(t, update_sneaking(false, pressed))
	testing.expect(t, update_sneaking(true, held))
	testing.expect(t, update_sneaking(true, toggle))
	testing.expect(t, !update_sneaking(true, pressed))
	testing.expect(t, !update_sneaking(false, held))
	testing.expect_value(t, with_sneaking(Input_Frame{pressed = {.Jump}}, true).pressed, Action_Set{.Jump, .Sneak})
	testing.expect_value(t, with_sneaking(Input_Frame{pressed = {.Jump, .Sneak}}, false).pressed, Action_Set{.Jump})
}

@(test)
test_toggled_sneak_keeps_the_player_slow :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	press := Input_Frame{move = {0, 1}, pressed = {.Sneak}, just_pressed = {.Sneak}, sneak_toggles = true}
	tick_test_player(&world, &records, registry, &player, press, 1)
	testing.expect(t, player.sneaking)
	released := Input_Frame{move = {0, 1}, sneak_toggles = true}
	tick_test_player(&world, &records, registry, &player, released, 1)
	testing.expect(t, player.sneaking)
	testing.expect(t, abs(player.velocity.x - PLAYER_SNEAK_SPEED) < TEST_TOLERANCE)
	tick_test_player(&world, &records, registry, &player, press, 1)
	testing.expect(t, !player.sneaking)
	tick_test_player(&world, &records, registry, &player, released, 1)
	testing.expect(t, abs(player.velocity.x - PLAYER_WALK_SPEED) < TEST_TOLERANCE)
}

@(test)
test_sprint_hold_and_toggle :: proc(t: ^testing.T) {
	// Hold: sprinting while Sprint is held and the player moves.
	holding := Input_Frame{move = {0, 1}, pressed = {.Sprint}, sprint_holds = true}
	testing.expect(t, update_sprinting(false, holding))
	testing.expect(t, !update_sprinting(true, Input_Frame{move = {0, 1}, sprint_holds = true}))
	testing.expect(t, !update_sprinting(true, Input_Frame{pressed = {.Sprint}, sprint_holds = true}))
	// Toggle, the default: a press starts it, releasing keeps it.
	testing.expect(t, update_sprinting(false, Input_Frame{move = {0, 1}, pressed = {.Sprint}, just_pressed = {.Sprint}}))
	testing.expect(t, update_sprinting(true, Input_Frame{move = {0, 1}}))

	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, holding, 1)
	testing.expect(t, player.sprinting)
	testing.expect(t, abs(player.velocity.x - PLAYER_SPRINT_SPEED) < TEST_TOLERANCE)
	tick_test_player(&world, &records, registry, &player, Input_Frame{move = {0, 1}, sprint_holds = true}, 1)
	testing.expect(t, !player.sprinting)
	testing.expect(t, abs(player.velocity.x - PLAYER_WALK_SPEED) < TEST_TOLERANCE)
}

tick_cheat_test_player :: proc(world: ^World, records: ^Game_Records, registry: Block_Registry, player: ^Player, input: Input_Frame, ticks: int) {
	content := make_test_content()
	content.blocks = registry
	for _ in 0 ..< ticks {
		tick_player(world, records, content, slice.from_ptr(player, 1), 0, input, TEST_TICK_RATE, 0, true)
	}
}

// Stone from x 3 to 9 on row z, height blocks high, a ledge to walk onto.
set_ledge :: proc(world: ^World, stone: Block_Id, z, height: i32) {
	for x in i32(3) ..< 10 {
		for y in i32(1) ..= height {
			world_set_block(world, {x, y, z}, stone)
		}
	}
}

// 0087: under cheat speed a walk climbs a one block ledge without jumping
// and stops at a two block wall; without it the ledge stops the walk.
@(test)
test_cheat_speed_steps_up_one_block_not_two :: proc(t: ^testing.T) {
	registry := make_test_registry()
	stone := test_block(registry, "stone")
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_ledge(&world, stone, 0, 1)
	set_ledge(&world, stone, 2, 2)
	low := make_test_player(registry, {0.5, 1, 0.5})
	tick_cheat_test_player(&world, &records, registry, &low, WALK_FORWARD, 20)
	testing.expectf(t, low.position.x > 3.3, "x %v", low.position.x)
	testing.expectf(t, abs(low.position.y - 2) < 1e-3, "y %v", low.position.y)
	testing.expect(t, low.on_ground)
	high := make_test_player(registry, {0.5, 1, 2.5})
	tick_cheat_test_player(&world, &records, registry, &high, WALK_FORWARD, 20)
	testing.expectf(t, abs(high.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", high.position.x)
	testing.expectf(t, abs(high.position.y - 1) < 1e-3, "y %v", high.position.y)
	normal := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &normal, WALK_FORWARD, 60)
	testing.expectf(t, abs(normal.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", normal.position.x)
	testing.expectf(t, abs(normal.position.y - 1) < 1e-3, "y %v", normal.position.y)
}

// 0087: a ceiling right above the ledge leaves no room to stand there, so
// the walk does not step up.
@(test)
test_cheat_step_up_needs_room_above_the_ledge :: proc(t: ^testing.T) {
	registry := make_test_registry()
	stone := test_block(registry, "stone")
	world := make_floor_world(registry, 32)
	records: Game_Records
	set_blocks(&world, stone, {3, 1, 0}, {3, 3, 0}, {4, 3, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_cheat_test_player(&world, &records, registry, &player, WALK_FORWARD, 60)
	testing.expectf(t, abs(player.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", player.position.x)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
}

// 0087: the cheat jump's apex is about 2.2 blocks, so a jump clears a two
// block wall.
@(test)
test_cheat_jump_reaches_two_blocks :: proc(t: ^testing.T) {
	registry := make_test_registry()
	stone := test_block(registry, "stone")
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_cheat_test_player(&world, &records, registry, &player, {}, 1)
	tick_cheat_test_player(&world, &records, registry, &player, Input_Frame{pressed = {.Jump}}, 1)
	apex := player.position.y
	for _ in 0 ..< 90 {
		tick_cheat_test_player(&world, &records, registry, &player, {}, 1)
		apex = max(apex, player.position.y)
	}
	testing.expectf(t, abs(apex - 1 - 2.2) < 0.02, "apex %v", apex - 1)
	testing.expect(t, player.on_ground)

	set_ledge(&world, stone, 2, 2)
	climber := make_test_player(registry, {0.5, 1, 2.5})
	input := Input_Frame {
		move    = {0, 1},
		pressed = {.Jump},
	}
	tick_cheat_test_player(&world, &records, registry, &climber, input, 40)
	testing.expectf(t, climber.position.x > 3.3, "x %v", climber.position.x)
	testing.expectf(t, climber.position.y > 3 - 1e-3, "y %v", climber.position.y)
}

// 0132: a Jump before a screen blocked the world and one after it are no
// double tap, however few ticks ran between them; without the block two
// Jumps 10 ticks apart still toggle.
@(test)
test_a_blocked_world_closes_the_double_tap_window :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	records: Game_Records
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, &records, registry, &player, {}, 1)
	tick_test_player(&world, &records, registry, &player, JUMP_TAP, 1)
	tick_test_player(&world, &records, registry, &player, Input_Frame{developer = true, world_blocked = true}, 1)
	tick_test_player(&world, &records, registry, &player, JUMP_TAP, 1)
	testing.expect(t, !player.flying)
	tick_test_player(&world, &records, registry, &player, {}, JUMP_DOUBLE_TAP_TICKS + 1)
	double_tap_jump(&world, &records, registry, &player, JUMP_TAP, 10)
	testing.expect(t, player.flying)
}

// Work item 0223: the pod's chair takes Interact like a switch: never
// while the world falls, always for a strapped or seated body, for a
// standing one aimed at it and not aimed at the bench; the X press is
// then Interact's alone.
@(test)
test_the_chair_takes_interact_like_a_switch :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	place_test_pod(&entities, machines)
	pod, frame, found := find_pod(&entities, machines)
	testing.expect(t, found)
	machine := machines.machines[pod.machine]
	chair_corner := rotate_footprint_cell({machine.seat.cells.from.x, machine.seat.cells.from.z}, machine.footprint.x, machine.footprint.z, pod.rotation)
	chair_cell := pod.origin + {chair_corner.x, 1, chair_corner.y}
	chair := Frame_Raycast_Hit{hit = true, frame = frame.id, cell = chair_cell, occupant = {handle = entity_occupant_handle(pod.handle)}}
	bench_origin, _ := pod_fixture_placement(machine, pod.origin, pod.rotation, 3)
	bench_handle := entity_at(&entities, bench_origin, frame.id)
	testing.expect_value(t, machines.machines[entity_common(&entities, bench_handle).machine].kind, Machine_Kind.Crafting_Bench)
	bench := Frame_Raycast_Hit{hit = true, frame = frame.id, cell = bench_origin, occupant = {handle = entity_occupant_handle(bench_handle)}}
	strapped := Field_Player{seat = .Strapped}
	testing.expect(t, !field_chair_takes_interact(&entities, machines, strapped, true), "strapped while falling")
	testing.expect(t, field_chair_takes_interact(&entities, machines, strapped, false), "strapped after the landing")
	testing.expect(t, field_chair_takes_interact(&entities, machines, Field_Player{seat = .Seated}, false), "seated")
	testing.expect(t, field_chair_takes_interact(&entities, machines, Field_Player{frame_target = chair}, false), "standing at the chair")
	testing.expect(t, !field_chair_takes_interact(&entities, machines, Field_Player{frame_target = bench}, false), "standing at the bench")
	takes_interact, has_panel := aimed_target_calls_for(&entities, machines, NO_ENTITY, Field_Player{frame_target = chair}, false)
	press := Input_Frame{pressed = {.Interact, .Open_Inventory}, just_pressed = {.Interact, .Open_Inventory}}
	routed := route_open_inventory_press(press, false, has_panel, takes_interact)
	testing.expect_value(t, routed.just_pressed & {.Interact, .Open_Inventory, .Open_Aimed}, Action_Set{.Interact})
}
