package game

import "core:math"
import rl "vendor:raylib"

THIRD_PERSON_DISTANCE :: 4.0
THIRD_PERSON_HEIGHT :: 0.75
// Kept between the pulled in camera and the block that blocked it, so the
// near plane does not clip into the block.
THIRD_PERSON_WALL_MARGIN :: 0.2
TARGET_OUTLINE_COLOR :: rl.Color{20, 20, 20, 255}
MINING_OUTLINE_COLOR :: rl.Color{240, 240, 240, 255}
PLACEMENT_PREVIEW_COLOR :: rl.Color{255, 255, 255, 70}
PLAYER_BODY_COLOR :: rl.Color{60, 110, 200, 255}
CROSSHAIR_COLOR :: rl.Color{255, 255, 255, 200}
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

// Behind and above the eye along the reverse look direction, pulled in
// when a solid block lies between the eye and that spot.
third_person_position :: proc(world: ^World, registry: Block_Registry, eye: [3]f32, forward: [3]f32) -> [3]f32 {
	offset := -forward * THIRD_PERSON_DISTANCE + {0, THIRD_PERSON_HEIGHT, 0}
	length := math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
	direction := offset / length
	hit := raycast_blocks(world, registry, eye, direction, length)
	if !hit.hit {
		return eye + offset
	}
	return eye + direction * max(hit.distance - THIRD_PERSON_WALL_MARGIN, 0)
}

player_view_camera :: proc(world: ^World, registry: Block_Registry, player: Player, alpha: f32) -> Fly_Camera {
	pose := interpolate_player_pose(player, alpha)
	view := Fly_Camera {
		position = player_eye(pose.position),
		yaw      = pose.yaw,
		pitch    = pose.pitch,
	}
	if player.camera_mode == .Third_Person {
		view.position = third_person_position(world, registry, view.position, fly_camera_forward(view))
	}
	return view
}

block_centre :: proc(block: World_Coordinate) -> [3]f32 {
	return {f32(block.x), f32(block.y), f32(block.z)} + 0.5
}

// The outline of the targeted block, and inside it a second outline that
// shrinks as mining progresses.
draw_target_outline :: proc(player: Player) {
	centre := block_centre(player.target.block)
	rl.DrawCubeWires(centre, OUTLINE_SCALE, OUTLINE_SCALE, OUTLINE_SCALE, TARGET_OUTLINE_COLOR)
	fraction := mining_fraction(player.mining)
	if fraction > 0 && player.mining.block == player.target.block {
		size := 1 - fraction
		rl.DrawCubeWires(centre, size, size, size, MINING_OUTLINE_COLOR)
	}
}

draw_placement_preview :: proc(player: Player) {
	if !player_owns(player, player.selected_block) {
		return
	}
	rl.DrawCube(block_centre(player.target.adjacent), 1, 1, 1, PLACEMENT_PREVIEW_COLOR)
}

// Placeholder body, a capsule over the collision box.
draw_player_body :: proc(position: [3]f32) {
	radius := f32(PLAYER_WIDTH / 2)
	bottom := position + {0, radius, 0}
	top := position + {0, PLAYER_HEIGHT - radius, 0}
	rl.DrawCapsule(bottom, top, radius, 12, 6, PLAYER_BODY_COLOR)
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_player_world_overlay :: proc(player: Player, alpha: f32) {
	if player.camera_mode == .Third_Person {
		draw_player_body(interpolate_player_pose(player, alpha).position)
	}
	if !player.target.hit {
		return
	}
	draw_target_outline(player)
	draw_placement_preview(player)
}

draw_crosshair :: proc() {
	centre_x, centre_y := rl.GetScreenWidth() / 2, rl.GetScreenHeight() / 2
	size := max(rl.GetScreenHeight() / 60, 8)
	thickness := max(size / 6, 2)
	rl.DrawRectangle(centre_x - size, centre_y - thickness / 2, 2 * size, thickness, CROSSHAIR_COLOR)
	rl.DrawRectangle(centre_x - thickness / 2, centre_y - size, thickness, 2 * size, CROSSHAIR_COLOR)
}
