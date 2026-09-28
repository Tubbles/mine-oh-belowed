package game

import "core:math"
import rl "vendor:raylib"
import "vendor:raylib/rlgl"

// The default third person distance; settings.third_person_distance
// holds the player's.
THIRD_PERSON_DISTANCE :: 4.0
THIRD_PERSON_HEIGHT :: 0.75
// Kept between the pulled in camera and the block that blocked it, so the
// near plane does not clip into the block.
THIRD_PERSON_WALL_MARGIN :: 0.2
// The sprint field of view kick eases in or out over this long (work item
// 0073).
SPRINT_KICK_SECONDS :: 0.3
TARGET_OUTLINE_COLOR :: rl.Color{20, 20, 20, 255}
MINING_OUTLINE_COLOR :: rl.Color{240, 240, 240, 255}
GHOST_VALID_COLOR :: rl.Color{60, 220, 90, 90}
GHOST_INVALID_COLOR :: rl.Color{230, 60, 50, 90}
INSERTER_GHOST_PICKUP_COLOR :: rl.Color{150, 150, 150, 160}
PLAYER_BODY_COLOR :: rl.Color{60, 110, 200, 255}
// Outlines sit slightly outside the block so the block faces do not hide them.
OUTLINE_SCALE :: 1.004

Player_Pose :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
}

// Shortest signed turn from `from` to `to` in degrees, so that yaw
// interpolation across the 360 wrap does not spin the long way round.
angle_difference :: proc(from, to: f32) -> f32 {
	difference := math.mod(to - from, 360)
	switch {
	case difference > 180:
		difference -= 360
	case difference < -180:
		difference += 360
	}
	return difference
}

interpolate_player_pose :: proc(player: Player, alpha: f32) -> Player_Pose {
	return Player_Pose {
		position = player.previous_position + (player.position - player.previous_position) * alpha,
		yaw = player.previous_yaw + angle_difference(player.previous_yaw, player.yaw) * alpha,
		pitch = player.previous_pitch + (player.pitch - player.previous_pitch) * alpha,
	}
}

// Behind and above the eye along the reverse look direction, and shoulder
// blocks to the camera's right (from the yaw, so looking up or down does
// not tip it).
third_person_offset :: proc(forward: [3]f32, yaw, distance, shoulder: f32) -> [3]f32 {
	return -forward * distance + {0, THIRD_PERSON_HEIGHT, 0} + camera_right(yaw) * shoulder
}

// Yaw 0 looks along +x, so the right is +z (fly_camera_velocity).
camera_right :: proc(yaw: f32) -> [3]f32 {
	radians := yaw * math.RAD_PER_DEG
	return {-math.sin(radians), 0, math.cos(radians)}
}

// The eye moved by offset, pulled in when a solid block lies between the
// eye and that spot.
third_person_position :: proc(world: ^World, registry: Block_Registry, eye: [3]f32, offset: [3]f32) -> [3]f32 {
	length := math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
	direction := offset / length
	hit := raycast_blocks(world, registry, eye, direction, length)
	if !hit.hit {
		return eye + offset
	}
	return eye + direction * max(hit.distance - THIRD_PERSON_WALL_MARGIN, 0)
}

// bob is the head bob in blocks (work item 0066), which only the first
// person eye takes. The third person camera sits where the settings'
// distance and shoulder put it (work item 0073).
player_view_camera :: proc(world: ^World, registry: Block_Registry, player: Player, alpha: f32, bob: f32, settings: Settings) -> Fly_Camera {
	pose := interpolate_player_pose(player, alpha)
	view := Fly_Camera {
		position = player_eye(pose.position),
		yaw      = pose.yaw,
		pitch    = pose.pitch,
	}
	if player.camera_mode == .Third_Person {
		offset := third_person_offset(fly_camera_forward(view), view.yaw, settings.third_person_distance, settings.third_person_shoulder)
		view.position = third_person_position(world, registry, view.position, offset)
	} else {
		view.position.y += bob
	}
	return view
}

// The sprint kick's progress from 0 to 1: towards 1 while sprinting,
// towards 0 otherwise, a full swing in SPRINT_KICK_SECONDS of frame time.
advance_sprint_kick :: proc(progress: f32, sprinting: bool, frame_seconds: f32) -> f32 {
	step := frame_seconds / SPRINT_KICK_SECONDS
	return sprinting ? min(progress + step, 1) : max(progress - step, 0)
}

// The field of view with the kick eased in and out (smoothstep) by the
// progress from advance_sprint_kick.
sprint_field_of_view :: proc(field_of_view, kick, progress: f32) -> f32 {
	eased := progress * progress * (3 - 2 * progress)
	return field_of_view + kick * eased
}

block_centre :: proc(block: World_Coordinate) -> [3]f32 {
	return {f32(block.x), f32(block.y), f32(block.z)} + 0.5
}

// The outline of the targeted block's shape (block_bounds: a slab's half,
// a torch's post) or the whole footprint of the targeted entity, and
// inside it a second outline that shrinks as mining (or picking up)
// progresses.
draw_target_outline :: proc(world: ^World, registry: Block_Registry, player: Player) {
	bounds := block_bounds(registry, world_get_block(world, player.target.block))
	origin := [3]f32{f32(player.target.block.x), f32(player.target.block.y), f32(player.target.block.z)}
	centre := origin + (bounds.minimum + bounds.maximum) / 2
	extent := bounds.maximum - bounds.minimum
	if common := entity_common(&world.entities, player.target.entity); common != nil {
		centre = box_centre(common.origin, common.size)
		extent = {f32(common.size.x), f32(common.size.y), f32(common.size.z)}
	}
	rl.DrawCubeWiresV(centre, extent * OUTLINE_SCALE, TARGET_OUTLINE_COLOR)
	fraction := mining_fraction(player.mining)
	if fraction > 0 && mining_matches_target(player.mining, player.target) {
		rl.DrawCubeWiresV(centre, extent * (1 - fraction), MINING_OUTLINE_COLOR)
	}
}

mining_matches_target :: proc(mining: Mining_State, target: Raycast_Hit) -> bool {
	if target.entity != NO_ENTITY {
		return mining.entity == target.entity
	}
	return mining.entity == NO_ENTITY && mining.block == target.block
}

// The machine's model tinted translucent at the placement, or a
// translucent box for a machine without a model, with the machine's
// direction and cells over it. A block gets no preview cube: the target
// outline already says where it goes, and the couch found the cube
// distracting (2026-09-27).
draw_placement_preview :: proc(world: ^World, content: Simulation_Content, models: Model_Renderer, belts: ^Belt_Renderer, players: []Player, index: int) {
	placement := placement_for_player(world, content, players, index)
	if !placement.shown {
		return
	}
	color := placement.valid ? GHOST_VALID_COLOR : GHOST_INVALID_COLOR
	if placement.belt {
		draw_belt_ghost(belts, placement, color)
		return
	}
	if !draw_ghost_model(models, content.machines, placement, color) {
		extent := [3]f32{f32(placement.size.x), f32(placement.size.y), f32(placement.size.z)}
		rl.DrawCubeV(box_centre(placement.origin, placement.size), extent, color)
	}
	if placement.inserter {
		draw_inserter_ghost(placement, content.machines, models)
	}
	if placement.drill {
		top := f32(placement.origin.y + placement.size.y) + 0.02
		draw_drill_arrow(placement.origin, placement.size, placement.rotation, top, BELT_GHOST_ARROW_COLOR)
		draw_drill_drop_cell(placement, content.machines)
	}
	if placement.splitter {
		draw_splitter_arrow(placement.origin, placement.size, placement.rotation, BELT_GHOST_ARROW_COLOR)
	}
	draw_fluid_machine_ghost(placement, content.machines, content.fluids)
	draw_supply_volume_ghost(placement, content.machines)
}

// The cell the drill's ore goes to, outlined: whatever stands there
// receives it, an empty cell leaves the drill without output.
draw_drill_drop_cell :: proc(placement: Placement, machines: Machine_Registry) {
	cell := drill_drop_cell_at(placement.origin, placement.rotation, machines.machines[placement.machine])
	rl.DrawCubeWiresV(block_centre(cell), {0.9, 0.9, 0.9}, BELT_GHOST_ARROW_COLOR)
}

// The cells the inserter a placement would build takes from and drops
// into, at its machine's reach.
inserter_ghost_cells :: proc(placement: Placement, machine: Machine) -> (pickup, drop: World_Coordinate) {
	inserter := make_inserter(Entity_Common{machine = placement.machine, origin = placement.origin, rotation = placement.rotation, size = placement.size}, machine)
	return inserter_pickup_cell(inserter), inserter_drop_cell(inserter)
}

// Across the top of the post, from the pickup side to the drop side.
inserter_ghost_chevron :: proc(placement: Placement, top: f32) -> Ghost_Chevron {
	forward := belt_direction_vector(placement.rotation)
	centre := block_centre(placement.origin)
	centre.y = f32(placement.origin.y) + top + GHOST_CHEVRON_LIFT
	return ghost_chevron_triangles(centre - forward * 0.5, centre + forward * 0.5, belt_direction_vector(turn_right(placement.rotation)))
}

// The pickup cell dim, the drop cell bright like the drill's, and the
// chevron between them over the model or the box.
draw_inserter_ghost :: proc(placement: Placement, machines: Machine_Registry, models: Model_Renderer) {
	pickup, drop := inserter_ghost_cells(placement, machines.machines[placement.machine])
	rl.DrawCubeWiresV(block_centre(pickup), {0.9, 0.9, 0.9}, INSERTER_GHOST_PICKUP_COLOR)
	rl.DrawCubeWiresV(block_centre(drop), {0.9, 0.9, 0.9}, BELT_GHOST_ARROW_COLOR)
	top := machine_model_top(models, Entity_Common{machine = placement.machine, size = placement.size})
	draw_ghost_chevron(inserter_ghost_chevron(placement, top), BELT_GHOST_ARROW_COLOR)
}

// The capsule over the collision box, while the player model did not
// load.
draw_player_body :: proc(position: [3]f32) {
	radius := f32(PLAYER_WIDTH / 2)
	bottom := position + {0, radius, 0}
	top := position + {0, PLAYER_HEIGHT - radius, 0}
	rl.DrawCapsule(bottom, top, radius, 12, 6, PLAYER_BODY_COLOR)
}

// What the body and the first person arm are drawn with this frame
// (work item 0066). light is the world light at the eye.
Player_Body_Draw :: struct {
	renderer:  Model_Renderer,
	model:     Player_Model,
	animation: Player_Animation_State,
	light:     rl.Color,
}

// The world light at the eye, like a machine model's.
player_body_light :: proc(frame: Model_Frame, eye: [3]f32) -> rl.Color {
	light := world_get_light(frame.world, camera_world_coordinate(eye))
	return brightness_color(model_light_tint(light, frame.day_factor, frame.sky_tint))
}

// The six limbs posed by the animation, or the capsule.
draw_player_third_person :: proc(body: Player_Body_Draw, pose: Player_Pose) {
	if !body.model.loaded {
		draw_player_body(pose.position)
		return
	}
	draw_player_model(body.renderer, body.model, pose, player_limb_angles(body.animation), body.light)
}

// The held stack's icon, or its coloured cube for an item without one.
draw_player_held_item :: proc(billboards: Item_Billboards, items: Item_Registry, item: Item_Id, centre: [3]f32) {
	if item_has_icon(billboards.atlas, item) {
		rl.DrawBillboardRec(billboards.camera, billboards.atlas.texture, item_atlas_source(billboards.atlas, item), centre, {HELD_ITEM_SIZE, HELD_ITEM_SIZE}, rl.WHITE)
		return
	}
	rl.DrawCubeV(centre, HELD_ITEM_SIZE / 2, item_cube_color(items, item))
}

// After the world's 3D pass and before the UI, in a pass of its own with
// the depth test off so the arm draws over the world: the right arm held
// forward from the lower right of the view, chopping while mining and
// swinging on a place, and the selected hotbar stack at the hand. It
// rides the bobbed camera. Nothing without the player model.
draw_first_person_hands :: proc(view: Fly_Camera, body: Player_Body_Draw, billboards: Item_Billboards, items: Item_Registry, held: Item_Stack) {
	if !body.model.loaded {
		return
	}
	rl.BeginMode3D(billboards.camera)
	defer rl.EndMode3D()
	rlgl.DrawRenderBatchActive()
	rlgl.DisableDepthTest()
	defer rlgl.EnableDepthTest()
	defer rlgl.DrawRenderBatchActive()
	arm := camera_frame_transform(view.position, view.yaw, view.pitch) * first_person_arm_transform(body.model.pivots[.Arm_Right], right_arm_action_angle(body.animation))
	draw_player_limb(body.renderer, body.model, .Arm_Right, arm * player_model_scale(), body.light)
	if !stack_is_empty(held) {
		draw_player_held_item(billboards, items, held.item, transform_point(arm, body.model.hand - {0, HELD_ITEM_REACH, 0}))
	}
}

// Dust kicked up under the feet on a step (work item 0066): on the ground
// and out of water, in the colour of the block stood on.
FOOTSTEP_DUST_COUNT :: 6
FOOTSTEP_DUST_SPREAD :: 0.15

footstep_dust_due :: proc(footstep, on_ground, in_water: bool) -> bool {
	return footstep && on_ground && !in_water
}

spawn_footstep_dust :: proc(particles: ^Particle_System, particle_memory: Particle_Memory, world: ^World, blocks: Block_Registry, position: [3]f32) {
	under := world_get_block(world, camera_world_coordinate(position - {0, COLLISION_EPSILON, 0}))
	emitter := Emitter{position = position + {0, 0.05, 0}, kind = .Puff, color = block_debris_color(blocks, under), spread = FOOTSTEP_DUST_SPREAD}
	spawn_particle_count(particles, emitter, FOOTSTEP_DUST_COUNT, emitter_random_key(particle_memory.frame_count, emitter))
}

// Once a frame, before the camera: the animation memory learns the
// frame, and a step puts dust into the particle pool.
update_player_presence :: proc(memory: ^Player_Animation_Memory, particles: ^Particle_System, particle_memory: Particle_Memory, world: ^World, blocks: Block_Registry, player: Player, tick: u64, render_seconds: f64) {
	footstep: bool
	memory^, footstep = advance_player_animation_memory(memory^, world.statistics.distance_walked_millimetres, placed_total(world.statistics), tick, render_seconds)
	in_water := footstep && box_touches_water(world, blocks, player_box(player.position))
	if footstep_dust_due(footstep, player.on_ground, in_water) {
		spawn_footstep_dust(particles, particle_memory, world, blocks, player.position)
	}
}

// Between BeginMode3D and EndMode3D, after the chunks. The body shows in
// third person only.
draw_player_world_overlay :: proc(world: ^World, content: Simulation_Content, models: Model_Renderer, belts: ^Belt_Renderer, players: []Player, index: int, alpha: f32, body: Player_Body_Draw) {
	player := players[index]
	if player.camera_mode == .Third_Person {
		draw_player_third_person(body, interpolate_player_pose(player, alpha))
	}
	if !player.target.hit {
		return
	}
	draw_target_outline(world, content.blocks, player)
	draw_placement_preview(world, content, models, belts, players, index)
}
