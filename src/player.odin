package game

import "core:math"

// The player body, ticked by the simulation at the fixed rate. Physics runs
// in plain f32: the fixed point rule for accumulating simulation state has
// this one exception until the world scale is settled. Determinism still
// holds for the same binary, the same input and the same world, since every
// step is the same sequence of f32 operations.

// Blocks and seconds.
PLAYER_WIDTH :: 0.6
PLAYER_HEIGHT :: 1.8
PLAYER_EYE_HEIGHT :: 1.6
PLAYER_REACH :: 5.0
// Blocks per second squared. With the jump speed the apex is about 1.19
// blocks at 60 Hz (1.26 in continuous time): one block and a margin, never two.
PLAYER_GRAVITY :: 28.0
PLAYER_JUMP_SPEED :: 8.4
PLAYER_TERMINAL_SPEED :: 50.0
PLAYER_WALK_SPEED :: 4.3
PLAYER_SPRINT_SPEED :: 5.6
PLAYER_SNEAK_SPEED :: 1.3

Camera_Mode :: enum u8 {
	First_Person,
	Third_Person,
}

// Yaw and pitch follow Fly_Camera: degrees, yaw 0 along +x, positive yaw
// turns towards +z, positive pitch looks up. The previous_ fields hold the
// state before the latest tick, for render interpolation.
Player :: struct {
	position:          [3]f32,
	velocity:          [3]f32,
	yaw:               f32,
	pitch:             f32,
	previous_position: [3]f32,
	previous_yaw:      f32,
	previous_pitch:    f32,
	on_ground:         bool,
	flying:            bool,
	camera_mode:       Camera_Mode,
	target:            Raycast_Hit,
	mining:            Mining_State,
	selected_block:    Block_Id,
	// Blocks owned, indexed by block id. The real inventory is M2.
	owned_blocks:      []u32,
}

Player_Start :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	flying:   bool,
}

make_player :: proc(start: Player_Start, block_count: int, allocator := context.allocator) -> Player {
	return Player {
		position = start.position,
		previous_position = start.position,
		yaw = start.yaw,
		previous_yaw = start.yaw,
		pitch = start.pitch,
		previous_pitch = start.pitch,
		flying = start.flying,
		owned_blocks = make([]u32, block_count, allocator),
	}
}

destroy_player :: proc(player: Player) {
	delete(player.owned_blocks)
}

// Standing on top of the given surface block.
player_start_on :: proc(surface: World_Coordinate) -> Player_Start {
	return Player_Start{position = {f32(surface.x) + 0.5, f32(surface.y + 1), f32(surface.z) + 0.5}, yaw = 45}
}

player_eye :: proc(position: [3]f32) -> [3]f32 {
	return position + {0, PLAYER_EYE_HEIGHT, 0}
}

player_look_direction :: proc(player: Player) -> [3]f32 {
	return fly_camera_forward(Fly_Camera{yaw = player.yaw, pitch = player.pitch})
}

turn_player :: proc(player: ^Player, input: Input_Frame, seconds: f32) {
	view := turn_fly_camera(Fly_Camera{yaw = player.yaw, pitch = player.pitch}, input, seconds)
	player.yaw, player.pitch = view.yaw, view.pitch
}

player_walk_speed :: proc(pressed: Action_Set) -> f32 {
	switch {
	case .Sneak in pressed:
		return PLAYER_SNEAK_SPEED
	case .Sprint in pressed:
		return PLAYER_SPRINT_SPEED
	}
	return PLAYER_WALK_SPEED
}

// Horizontal velocity follows the input directly, without acceleration.
walk_velocity :: proc(yaw: f32, input: Input_Frame) -> [2]f32 {
	radians := yaw * math.RAD_PER_DEG
	forward := [2]f32{math.cos(radians), math.sin(radians)}
	right := [2]f32{-math.sin(radians), math.cos(radians)}
	return (forward * input.move.y + right * input.move.x) * player_walk_speed(input.pressed)
}

fall_velocity :: proc(vertical_velocity: f32, seconds: f32) -> f32 {
	return max(vertical_velocity - PLAYER_GRAVITY * seconds, -PLAYER_TERMINAL_SPEED)
}

// The chunk holding the block under the feet. While it is missing the
// ground reads as air, so the player would fall through it.
ground_chunk_loaded :: proc(world: ^World, position: [3]f32) -> bool {
	under := camera_world_coordinate(position - {0, COLLISION_EPSILON, 0})
	return world_to_chunk_coordinate(under) in world.chunks
}

// Sneaking on the ground rejects a horizontal step that would leave no
// solid block under the box.
step_keeps_ground :: proc(world: ^World, registry: Block_Registry, player: Player, sneaking: bool, position: [3]f32) -> bool {
	if !sneaking || !player.on_ground {
		return true
	}
	return box_has_ground(world, registry, player_box(position))
}

move_player_vertically :: proc(world: ^World, registry: Block_Registry, player: ^Player, seconds: f32) {
	if !ground_chunk_loaded(world, player.position) {
		player.velocity.y = 0
		return
	}
	player.velocity.y = fall_velocity(player.velocity.y, seconds)
	moved, blocked := sweep_box_axis(world, registry, player_box(player.position), 1, player.velocity.y * seconds)
	player.position.y += moved
	player.on_ground = blocked && player.velocity.y < 0
	if blocked {
		player.velocity.y = 0
	}
}

move_player_horizontally :: proc(world: ^World, registry: Block_Registry, player: ^Player, sneaking: bool, seconds: f32) {
	for axis in ([2]int{0, 2}) {
		moved, blocked := sweep_box_axis(world, registry, player_box(player.position), axis, player.velocity[axis] * seconds)
		candidate := player.position
		candidate[axis] += moved
		if !step_keeps_ground(world, registry, player^, sneaking, candidate) {
			blocked = true
			candidate = player.position
		}
		player.position = candidate
		if blocked {
			player.velocity[axis] = 0
		}
	}
}

// A body inside solid blocks (a spawn inside a boulder, fly mode turned off
// underground) rises one block per tick until it is free.
lift_out_of_blocks :: proc(world: ^World, registry: Block_Registry, player: ^Player) -> bool {
	if !box_intersects_solid(world, registry, player_box(player.position)) {
		return false
	}
	player.position.y = math.floor(player.position.y) + 1
	player.velocity = {}
	return true
}

walk_player :: proc(world: ^World, registry: Block_Registry, player: ^Player, input: Input_Frame, seconds: f32) {
	if lift_out_of_blocks(world, registry, player) {
		return
	}
	if player.on_ground && .Jump in input.pressed {
		player.velocity.y = PLAYER_JUMP_SPEED
	}
	horizontal := walk_velocity(player.yaw, input)
	player.velocity.x, player.velocity.z = horizontal.x, horizontal.y
	move_player_vertically(world, registry, player, seconds)
	move_player_horizontally(world, registry, player, .Sneak in input.pressed, seconds)
}

// The developer fly mode: fly camera speeds, no gravity and no collision.
fly_player :: proc(player: ^Player, input: Input_Frame, seconds: f32) {
	player.velocity = fly_camera_velocity(Fly_Camera{yaw = player.yaw}, input)
	player.position += player.velocity * seconds
	player.on_ground = false
}

apply_player_toggles :: proc(player: ^Player, just_pressed: Action_Set) {
	if .Toggle_Camera_Mode in just_pressed {
		player.camera_mode = player.camera_mode == .First_Person ? .Third_Person : .First_Person
	}
	if .Toggle_Fly_Mode in just_pressed {
		player.flying = !player.flying
		player.velocity = {}
	}
}

tick_player :: proc(world: ^World, registry: Block_Registry, players: []Player, index: int, input: Input_Frame, tick_rate: int) {
	player := &players[index]
	seconds := 1 / f32(tick_rate)
	player.previous_position, player.previous_yaw, player.previous_pitch = player.position, player.yaw, player.pitch
	apply_player_toggles(player, input.just_pressed)
	turn_player(player, input, seconds)
	if player.flying {
		fly_player(player, input, seconds)
	} else {
		walk_player(world, registry, player, input, seconds)
	}
	player.target = raycast_blocks(world, registry, player_eye(player.position), player_look_direction(player^), PLAYER_REACH)
	mine_with_player(world, registry, player, .Mine in input.pressed, tick_rate)
	place_with_player(world, registry, players, index, input.just_pressed)
	cycle_selected_block(player, input.just_pressed)
}
