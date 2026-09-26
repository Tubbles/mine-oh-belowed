package game

import "core:testing"

@(test)
test_fly_camera_pitch_is_clamped :: proc(t: ^testing.T) {
	input := Input_Frame {
		look_delta = {0, -10_000},
	}
	camera := update_fly_camera({}, input, 1.0 / 60)
	testing.expect_value(t, camera.pitch, FLY_CAMERA_PITCH_LIMIT_DEGREES)
}

@(test)
test_fly_camera_mouse_right_turns_right :: proc(t: ^testing.T) {
	input := Input_Frame {
		look_delta = {10, 0},
	}
	camera := update_fly_camera({}, input, 1.0 / 60)
	testing.expect(t, camera.yaw > 0)
	// Yaw 0 looks along +x, turning right swings the view towards +z.
	testing.expect(t, fly_camera_forward(camera).z > 0)
}

@(test)
test_fly_camera_moves_and_sprints :: proc(t: ^testing.T) {
	forward := Input_Frame {
		move = {0, 1},
	}
	walked := update_fly_camera({}, forward, 1)
	testing.expect(t, abs(walked.position.x - FLY_CAMERA_SPEED) < TEST_TOLERANCE)
	sprinting := forward
	sprinting.pressed = {.Sprint, .Jump}
	sprinted := update_fly_camera({}, sprinting, 1)
	testing.expect(t, abs(sprinted.position.x - FLY_CAMERA_SPEED * FLY_CAMERA_SPRINT_FACTOR) < TEST_TOLERANCE)
	testing.expect(t, sprinted.position.y > 0)
}
