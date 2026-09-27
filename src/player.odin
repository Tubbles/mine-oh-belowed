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
// In water: half the walking speed, a slow sink under weak gravity and a
// small upward speed while Jump is held. No drowning.
PLAYER_WATER_SPEED_FACTOR :: 0.5
PLAYER_WATER_GRAVITY :: 4.0
PLAYER_SINK_SPEED :: 1.5
PLAYER_SWIM_SPEED :: 2.5

Camera_Mode :: enum u8 {
	First_Person,
	Third_Person,
}

// Yaw and pitch follow Fly_Camera: degrees, yaw 0 along +x, positive yaw
// turns towards +z, positive pitch looks up. The previous_ fields hold the
// state before the latest tick, for render interpolation.
Player :: struct {
	position:             [3]f32,
	velocity:             [3]f32,
	yaw:                  f32,
	pitch:                f32,
	previous_position:    [3]f32,
	previous_yaw:         f32,
	previous_pitch:       f32,
	on_ground:            bool,
	flying:               bool,
	camera_mode:          Camera_Mode,
	target:               Raycast_Hit,
	mining:               Mining_State,
	// The hotbar is the first HOTBAR_SLOT_COUNT slots.
	inventory:            Inventory,
	selected_hotbar_slot: int,
	// The stack on the cursor of the inventory screen.
	held:                 Held_Stack,
	// Quarter turns of the machine ghost, changed with Rotate_Building.
	placement_rotation:   u8,
	// The belt run being dragged while Place is held.
	belt_drag:            Belt_Drag,
	// The entity whose panel Interact opened; the UI clears it on close.
	open_machine:         Entity_Handle,
	// Hand crafting. The UI queues and cancels between ticks.
	crafting:             Craft_Queue,
	// The selected magnetometer's reading this tick, empty while none is
	// selected (prospecting.odin).
	magnetometer:         Magnetometer_Reading,
}

// What a player tick reports to the UI, which turns it into toasts.
Player_Event :: enum u8 {
	Inventory_Full,
	// Interact on an entity: the UI opens player.open_machine's panel.
	Open_Machine,
	// Interact turned a power switch.
	Toggled_Switch,
	// Use_Item with a prospecting tool (prospecting.odin).
	Vein_Assayed,
	Magnetometer_Recorded,
	Seismic_Shot_Fired,
}

Player_Events :: bit_set[Player_Event]

Player_Start :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
	flying:   bool,
}

make_player :: proc(start: Player_Start, allocator := context.allocator) -> Player {
	return Player {
		position = start.position,
		previous_position = start.position,
		yaw = start.yaw,
		previous_yaw = start.yaw,
		pitch = start.pitch,
		previous_pitch = start.pitch,
		flying = start.flying,
		inventory = make_inventory(PLAYER_INVENTORY_SLOT_COUNT, allocator),
		held = EMPTY_HELD_STACK,
	}
}

// Unknown names are skipped: validate_starting_items reports them at load.
give_starting_items :: proc(player: ^Player, items: Item_Registry, starting_items: []Starting_Item) {
	for starting in starting_items {
		if item, found := find_item_id(items, starting.item); found {
			inventory_add(player.inventory, items, item, starting.count)
		}
	}
}

destroy_player :: proc(player: Player, allocator := context.allocator) {
	destroy_inventory(player.inventory, allocator)
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

swim_velocity :: proc(vertical_velocity: f32, swimming_up: bool, seconds: f32) -> f32 {
	if swimming_up {
		return PLAYER_SWIM_SPEED
	}
	return max(vertical_velocity - PLAYER_WATER_GRAVITY * seconds, -PLAYER_SINK_SPEED)
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

move_player_vertically :: proc(world: ^World, registry: Block_Registry, player: ^Player, in_water, swimming_up: bool, seconds: f32) {
	if !ground_chunk_loaded(world, player.position) {
		player.velocity.y = 0
		return
	}
	if in_water {
		player.velocity.y = swim_velocity(player.velocity.y, swimming_up, seconds)
	} else {
		player.velocity.y = fall_velocity(player.velocity.y, seconds)
	}
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
	in_water := box_touches_water(world, registry, player_box(player.position))
	if player.on_ground && !in_water && .Jump in input.pressed {
		player.velocity.y = PLAYER_JUMP_SPEED
	}
	horizontal := walk_velocity(player.yaw, input)
	if in_water {
		horizontal *= PLAYER_WATER_SPEED_FACTOR
	}
	player.velocity.x, player.velocity.z = horizontal.x, horizontal.y
	move_player_vertically(world, registry, player, in_water, .Jump in input.pressed, seconds)
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

// A gamepad's A is both Jump and Interact. Looking at an entity it opens
// the entity instead of jumping; keyboard Space never interacts. On a
// power switch Interact turns the switch like a lever, and Sneak with
// Interact opens its panel.
resolve_interact :: proc(player: ^Player, entities: ^Entities, machines: Machine_Registry, input: Input_Frame) -> (Input_Frame, Player_Events) {
	result := input
	if .Interact not_in input.pressed || !entity_has_panel(entities, player.target.entity) {
		return result, {}
	}
	result.pressed -= {.Jump}
	result.just_pressed -= {.Jump}
	if .Interact not_in input.just_pressed {
		return result, {}
	}
	if .Sneak not_in input.pressed && toggle_power_switch(entities, machines, player.target.entity) {
		return result, {.Toggled_Switch}
	}
	player.open_machine = player.target.entity
	return result, {.Open_Machine}
}

// Standing on a flat belt or a ramp moves the body with the belt before
// its own movement, swept like any other move so walls still stop it.
carry_player_on_belt :: proc(world: ^World, content: Simulation_Content, player: ^Player, tick_rate: int) {
	if player.flying || !player.on_ground {
		return
	}
	belt := belt_at(&world.entities, camera_world_coordinate(player.position + {0, COLLISION_EPSILON, 0}))
	if belt == nil {
		return
	}
	offset := belt_carry_offset(belt^, content.machines, tick_rate)
	for axis in ([2]int{0, 2}) {
		moved, _ := sweep_box_axis(world, content.blocks, player_box(player.position), axis, offset[axis])
		player.position[axis] += moved
	}
}

tick_player :: proc(world: ^World, content: Simulation_Content, players: []Player, index: int, frame: Input_Frame, tick_rate: int) -> Player_Events {
	player := &players[index]
	seconds := 1 / f32(tick_rate)
	input, events := resolve_interact(player, &world.entities, content.machines, frame)
	player.previous_position, player.previous_yaw, player.previous_pitch = player.position, player.yaw, player.pitch
	apply_player_toggles(player, input.just_pressed)
	turn_player(player, input, seconds)
	carry_player_on_belt(world, content, player, tick_rate)
	walk_start := player.position
	if player.flying {
		fly_player(player, input, seconds)
	} else {
		walk_player(world, content.blocks, player, input, seconds)
	}
	if !player.flying {
		record_walked(&world.statistics, walk_start, player.position)
	}
	if .Open_Machine in events || .Toggled_Switch in events {
		record_world_action(&world.statistics)
	}
	player.target = raycast_blocks(world, content.blocks, player_eye(player.position), player_look_direction(player^), PLAYER_REACH)
	events += mine_with_player(world, content, player, .Mine in input.pressed, tick_rate)
	place_with_player(world, content, players, index, input.just_pressed, input.pressed)
	player.selected_hotbar_slot = cycle_hotbar_slot(player.selected_hotbar_slot, input.just_pressed)
	if finished := advance_crafting(&player.crafting, player.inventory, content.recipes, content.items, tick_rate); finished != NO_RECIPE {
		record_produced_stacks(&world.statistics, content.recipes.recipes[finished].outputs)
		record_consumed_stacks(&world.statistics, content.recipes.recipes[finished].inputs)
	}
	return events
}
