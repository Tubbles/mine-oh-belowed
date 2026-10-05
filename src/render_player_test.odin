package game

import "core:math/linalg"
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

// The held block (work item 0092): six faces of the given edge around
// the centre, each wound counter clockwise seen from outside so culling
// keeps the near faces with the depth test off, and the whole cube turned
// and moved with the arm's transform.
@(test)
test_held_block_cube_faces_wind_outwards :: proc(t: ^testing.T) {
	centre := [3]f32{1, 2, 3}
	size: f32 = 0.35
	identity := matrix[4, 4]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
	faces := held_block_cube_corners(identity, centre, size)
	for corners, direction in faces {
		offset := direction_offsets[direction]
		normal := [3]f32{f32(offset.x), f32(offset.y), f32(offset.z)}
		for corner in corners {
			testing.expectf(t, abs(linalg.dot(corner - centre, normal) - size / 2) < 1e-5, "%v corner %v off its face", direction, corner)
			for axis in 0 ..< 3 {
				testing.expectf(t, abs(abs(corner[axis] - centre[axis]) - size / 2) < 1e-5, "%v corner %v not on the cube", direction, corner)
			}
		}
		winding := linalg.cross(corners[1] - corners[0], corners[2] - corners[1])
		testing.expectf(t, linalg.dot(winding, normal) > 0, "%v wound inwards", direction)
	}
	turned := camera_frame_transform({5, 6, 7}, 90, 0)
	moved := held_block_cube_corners(turned, {}, size)
	top := (moved[.Positive_Y][0] + moved[.Positive_Y][2]) / 2
	expect_near_point(t, top, [3]f32{5, 6, 7} + {0, size / 2, 0}, "top face middle")
	front := (moved[.Positive_X][0] + moved[.Positive_X][2]) / 2
	expect_near_point(t, front, [3]f32{5, 6, 7} + fly_camera_forward(Fly_Camera{yaw = 90}) * size / 2, "front face middle")
}

// The viewer's body is hidden within VIEWER_BODY_HIDDEN_WITHIN_METRES of
// the eye, shown past it and at the settings' shortest distance, never in
// first person; the value is the body's radius plus the field's near
// plane (0261).
@(test)
test_the_viewers_body_is_shown_only_past_the_hidden_distance :: proc(t: ^testing.T) {
	eye := [3]f32{1, 2, 3}
	testing.expect(t, !viewer_body_shown(.Third_Person, eye, eye), "shown at the eye")
	testing.expect(t, !viewer_body_shown(.Third_Person, eye + {0, 0, VIEWER_BODY_HIDDEN_WITHIN_METRES - 0.01}, eye), "shown just inside the distance")
	testing.expect(t, viewer_body_shown(.Third_Person, eye + {VIEWER_BODY_HIDDEN_WITHIN_METRES + 0.01, 0, 0}, eye), "hidden just past the distance")
	shortest := eye + third_person_offset({1, 0, 0}, 0, THIRD_PERSON_DISTANCE_RANGE.minimum, 0)
	testing.expect(t, viewer_body_shown(.Third_Person, shortest, eye), "hidden at the settings' shortest distance")
	testing.expect(t, !viewer_body_shown(.First_Person, shortest, eye), "shown in first person")
	testing.expectf(t, abs(VIEWER_BODY_HIDDEN_WITHIN_METRES - (PLAYER_WIDTH / 2 + FIELD_NEAR_METRES)) < 1e-6, "%v is not the body's radius plus the near plane", VIEWER_BODY_HIDDEN_WITHIN_METRES)
}
