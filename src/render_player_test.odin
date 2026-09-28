package game

import "core:testing"

// The kick eases in over SPRINT_KICK_SECONDS of frame time, holds while
// sprinting and eases out the same way, whatever the frame rate.
@(test)
test_sprint_kick_blends_over_time :: proc(t: ^testing.T) {
	progress: f32
	for _ in 0 ..< 9 {
		progress = advance_sprint_kick(progress, true, SPRINT_KICK_SECONDS / 10)
	}
	testing.expectf(t, progress > 0.85 && progress < 0.95, "nine tenths in: %v", progress)
	progress = advance_sprint_kick(progress, true, SPRINT_KICK_SECONDS)
	testing.expect_value(t, progress, 1)
	testing.expect_value(t, advance_sprint_kick(0, true, SPRINT_KICK_SECONDS * 2), 1)
	testing.expect_value(t, advance_sprint_kick(1, false, SPRINT_KICK_SECONDS * 2), 0)
	testing.expect_value(t, advance_sprint_kick(0, false, 1.0 / 60), 0)
	halfway := advance_sprint_kick(1, false, SPRINT_KICK_SECONDS / 2)
	testing.expectf(t, abs(halfway - 0.5) < 1e-5, "halfway out: %v", halfway)

	testing.expect_value(t, sprint_field_of_view(70, 6, 0), 70)
	testing.expect_value(t, sprint_field_of_view(70, 6, 1), 76)
	testing.expectf(t, abs(sprint_field_of_view(70, 6, 0.5) - 73) < 1e-4, "halfway kick")
	// Eased: slower than linear at the start.
	testing.expectf(t, sprint_field_of_view(70, 6, 0.1) - 70 < 0.6, "eased in: %v", sprint_field_of_view(70, 6, 0.1))
	testing.expect_value(t, sprint_field_of_view(70, 0, 1), 70)
}

// A positive shoulder moves the camera to the right of the look
// direction, so the player stands left of centre.
@(test)
test_third_person_shoulder_follows_the_yaw :: proc(t: ^testing.T) {
	Case :: struct {
		yaw:   f32,
		right: [3]f32,
	}
	// Yaw 0 looks along +x and positive yaw turns towards +z.
	cases := [?]Case{{0, {0, 0, 1}}, {90, {-1, 0, 0}}, {180, {0, 0, -1}}, {270, {1, 0, 0}}}
	for case_value in cases {
		forward := fly_camera_forward(Fly_Camera{yaw = case_value.yaw})
		behind := third_person_offset(forward, case_value.yaw, 4, 0)
		shouldered := third_person_offset(forward, case_value.yaw, 4, 0.6)
		sideways := shouldered - behind
		expected := case_value.right * 0.6
		for axis in 0 ..< 3 {
			testing.expectf(t, abs(sideways[axis] - expected[axis]) < 1e-4, "yaw %v: %v, want %v", case_value.yaw, sideways, expected)
		}
		mirrored := third_person_offset(forward, case_value.yaw, 4, -0.6) - behind
		testing.expectf(t, abs(mirrored.x + expected.x) < 1e-4 && abs(mirrored.z + expected.z) < 1e-4, "yaw %v: negative is left", case_value.yaw)
	}
	// Looking down leaves the shoulder level.
	down := Fly_Camera{yaw = 0, pitch = -60}
	sideways := third_person_offset(fly_camera_forward(down), 0, 4, 1) - third_person_offset(fly_camera_forward(down), 0, 4, 0)
	testing.expectf(t, abs(sideways.y) < 1e-6 && abs(sideways.z - 1) < 1e-4, "pitched: %v", sideways)
}
