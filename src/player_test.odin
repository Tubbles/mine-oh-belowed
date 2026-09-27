package game

import "core:log"
import "core:slice"
import "core:testing"

TEST_TICK_RATE :: 60

test_game_config :: proc() -> Game_Config {
	return Game_Config{name = "test", tick_rate = TEST_TICK_RATE, day_length_seconds = 1200}
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

tick_test_player :: proc(world: ^World, registry: Block_Registry, player: ^Player, input: Input_Frame, ticks: int) -> (events: Player_Events) {
	content := make_test_content()
	content.blocks = registry
	for _ in 0 ..< ticks {
		events += tick_player(world, content, slice.from_ptr(player, 1), 0, input, TEST_TICK_RATE)
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
	set_blocks(&world, test_block(registry, "stone"), {3, 1, 0}, {3, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &player, WALK_FORWARD, 120)
	testing.expectf(t, abs(player.position.x - (3 - PLAYER_WIDTH / 2)) < 1e-3, "x %v", player.position.x)
	testing.expect_value(t, player.velocity.x, 0)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
}

@(test)
test_player_falls_onto_floor_and_lands_on_top :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	player := make_test_player(registry, {0.5, 20, 0.5})
	tick_test_player(&world, registry, &player, {}, 180)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
	testing.expect_value(t, player.velocity.y, 0)
}

@(test)
test_player_jump_reaches_one_block_not_two :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &player, {}, 1)
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Jump}}, 1)
	apex := player.position.y
	for _ in 0 ..< 60 {
		tick_test_player(&world, registry, &player, {}, 1)
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
	set_blocks(&world, stone, {3, 1, 0}, {3, 1, 2}, {3, 2, 2})
	input := Input_Frame {
		move    = {0, 1},
		pressed = {.Jump},
	}
	low := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &low, input, 90)
	testing.expectf(t, low.position.x > 3.3, "x %v", low.position.x)
	high := make_test_player(registry, {0.5, 1, 2.5})
	tick_test_player(&world, registry, &high, input, 90)
	testing.expectf(t, high.position.x < 3, "x %v", high.position.x)
}

@(test)
test_sneaking_stops_at_edge :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 3)
	sneaking := Input_Frame {
		move    = {0, 1},
		pressed = {.Sneak},
	}
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &player, {}, 1)
	tick_test_player(&world, registry, &player, sneaking, 240)
	testing.expectf(t, player.position.x > 3 && player.position.x < 3 + PLAYER_WIDTH / 2, "x %v", player.position.x)
	testing.expect(t, player.on_ground)
	testing.expectf(t, abs(player.position.y - 1) < 1e-3, "y %v", player.position.y)
	walking := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &walking, WALK_FORWARD, 120)
	testing.expect(t, walking.position.y < 0)
}

@(test)
test_player_waits_for_missing_ground_chunk :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_test_world({})
	player := make_test_player(registry, {0.5, 20, 0.5})
	tick_test_player(&world, registry, &player, {}, 60)
	testing.expect_value(t, player.position.y, 20)
	testing.expect_value(t, player.velocity.y, 0)
}

@(test)
test_player_inside_blocks_rises_out :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, test_block(registry, "log"), {0, 1, 0}, {0, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &player, {}, 30)
	testing.expectf(t, abs(player.position.y - 3) < 1e-3, "y %v", player.position.y)
	testing.expect(t, player.on_ground)
}

@(test)
test_fly_mode_ignores_gravity_and_blocks :: proc(t: ^testing.T) {
	registry := make_test_registry()
	world := make_floor_world(registry, 32)
	set_blocks(&world, test_block(registry, "stone"), {3, 1, 0}, {3, 2, 0})
	player := make_test_player(registry, {0.5, 1, 0.5})
	tick_test_player(&world, registry, &player, Input_Frame{just_pressed = {.Toggle_Fly_Mode}}, 1)
	testing.expect(t, player.flying)
	tick_test_player(&world, registry, &player, WALK_FORWARD, 60)
	testing.expectf(t, abs(player.position.x - (0.5 + FLY_CAMERA_SPEED)) < 1e-2, "x %v", player.position.x)
	testing.expect_value(t, player.position.y, 1)
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
	free := third_person_position(&world, registry, eye, {1, 0, 0})
	testing.expectf(t, abs(free.x - (0.5 - THIRD_PERSON_DISTANCE)) < 1e-3, "x %v", free.x)
	for y in i32(1) ..= 6 {
		set_blocks(&world, test_block(registry, "stone"), {-2, y, 0})
	}
	blocked := third_person_position(&world, registry, eye, {1, 0, 0})
	testing.expectf(t, blocked.x > -1 && blocked.x < 0.5, "x %v", blocked.x)
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
	random := hash_u64(u64(tick) / 20)
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
		input.pressed += {.Sprint}
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
			}
		}
	}
	return world
}

make_generated_simulation :: proc(generator: ^Generator, content: Simulation_Content) -> Simulation_State {
	surface := World_Coordinate{8, terrain_height(generator.seeds, 8, 8), 8}
	_, technologies := make_test_recipes(content.items)
	simulation := make_simulation(test_game_config(), player_start_on(surface), content, technologies, false)
	simulation.world = make_generated_world(generator, world_to_chunk_coordinate(surface))
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
	water := test_block(registry, "water")
	for y in i32(1) ..= 8 {
		for z in i32(-4) ..= 4 {
			for x in i32(0) ..< 16 {
				world_set_block(&world, {x, y, z}, water)
			}
		}
	}
	player := make_test_player(registry, {2.5, 5, 0.5})
	tick_test_player(&world, registry, &player, {}, 30)
	testing.expectf(t, player.velocity.y >= -PLAYER_SINK_SPEED && player.velocity.y < 0, "sinking at %v", player.velocity.y)
	testing.expect(t, player.position.y > 4)

	start_x := player.position.x
	tick_test_player(&world, registry, &player, WALK_FORWARD, 60)
	walked := player.position.x - start_x
	testing.expectf(t, abs(walked - PLAYER_WALK_SPEED * PLAYER_WATER_SPEED_FACTOR) < 0.05, "walked %v in one second", walked)

	start_y := player.position.y
	tick_test_player(&world, registry, &player, Input_Frame{pressed = {.Jump}}, 30)
	testing.expectf(t, player.position.y - start_y > 1, "rose %v", player.position.y - start_y)
}
