package game

import "core:math"
import "core:math/linalg"

// The view (position, yaw, pitch) and the fly mode speeds. The player tick
// turns and flies through these procedures, the renderer draws from a
// Fly_Camera interpolated between ticks.

FLY_CAMERA_SPEED :: 12.0
FLY_CAMERA_SPRINT_FACTOR :: 3.0
FLY_CAMERA_STICK_DEGREES_PER_SECOND :: 150.0
FLY_CAMERA_DEGREES_PER_LOOK_PIXEL :: 0.15
FLY_CAMERA_PITCH_LIMIT_DEGREES :: 89.0

// Yaw 0 looks along +x, positive yaw turns right (towards +z). Pitch
// positive looks up. Both in degrees.
Fly_Camera :: struct {
	position: [3]f32,
	yaw:      f32,
	pitch:    f32,
}

fly_camera_forward :: proc(camera: Fly_Camera) -> [3]f32 {
	yaw := camera.yaw * math.RAD_PER_DEG
	pitch := camera.pitch * math.RAD_PER_DEG
	return {math.cos(pitch) * math.cos(yaw), math.sin(pitch), math.cos(pitch) * math.sin(yaw)}
}

// Look_delta uses mouse conventions (y down), look uses stick conventions (y up).
turn_fly_camera :: proc(camera: Fly_Camera, input: Input_Frame, frame_seconds: f32) -> Fly_Camera {
	result := camera
	stick_degrees := input.look * FLY_CAMERA_STICK_DEGREES_PER_SECOND * frame_seconds
	pointer_degrees := input.look_delta * FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	result.yaw = math.mod(camera.yaw + stick_degrees.x + pointer_degrees.x, 360)
	pitch := camera.pitch + stick_degrees.y - pointer_degrees.y
	result.pitch = clamp(pitch, -FLY_CAMERA_PITCH_LIMIT_DEGREES, FLY_CAMERA_PITCH_LIMIT_DEGREES)
	return result
}

// Horizontal movement follows the yaw only, so looking down does not slow
// the camera. Jump rises, Sneak descends, sprinting (player_sprints) is
// faster.
fly_camera_velocity :: proc(camera: Fly_Camera, input: Input_Frame, sprinting: bool) -> [3]f32 {
	yaw := camera.yaw * math.RAD_PER_DEG
	forward := [3]f32{math.cos(yaw), 0, math.sin(yaw)}
	right := [3]f32{-math.sin(yaw), 0, math.cos(yaw)}
	velocity := forward * input.move.y + right * input.move.x
	if .Jump in input.pressed {
		velocity.y += 1
	}
	if .Sneak in input.pressed {
		velocity.y -= 1
	}
	speed := f32(FLY_CAMERA_SPEED)
	if sprinting {
		speed *= FLY_CAMERA_SPRINT_FACTOR
	}
	return velocity * speed
}

fly_camera_target :: proc(camera: Fly_Camera) -> [3]f32 {
	return camera.position + linalg.normalize(fly_camera_forward(camera))
}
