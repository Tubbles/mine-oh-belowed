package game

import "core:math"
import "core:math/linalg"
import "core:testing"

// The model preview's pure parts (work item 0207); the drawing needs a
// window and is run by tools/model_preview.sh.

@(test)
test_the_preview_writes_sixteen_names :: proc(t: ^testing.T) {
	names := make(map[string]bool, context.temp_allocator)
	for phase in Model_Preview_Phase {
		for view in Model_Preview_View {
			names[model_preview_file_name("burner_mining_drill", view, phase)] = true
		}
	}
	testing.expect_value(t, len(names), 16)
	testing.expect(t, "burner_mining_drill_front_0.5.png" in names)
	testing.expect(t, "burner_mining_drill_top_rest.png" in names)
}

@(test)
test_the_preview_poses :: proc(t: ^testing.T) {
	pump := Machine{motion = {kind = .Pump}}
	expected := [Model_Preview_Phase]Model_Preview_Pose{.Rest = {0, false}, .Quarter = {0.25, true}, .Half = {0.5, true}, .Three_Quarters = {0.75, true}}
	for phase in Model_Preview_Phase {
		testing.expect_value(t, model_preview_pose(pump, phase), expected[phase])
	}
	arm := Machine{motion = {kind = .Arm}}
	expected = {.Rest = {0, false}, .Quarter = {ARM_GRAB_END, true}, .Half = {ARM_SWING_MIDDLE, true}, .Three_Quarters = {ARM_DROP_FRACTION, true}}
	for phase in Model_Preview_Phase {
		testing.expect_value(t, model_preview_pose(arm, phase), expected[phase])
	}
}

@(test)
test_the_preview_cameras_frame_the_scene :: proc(t: ^testing.T) {
	machine := Machine{footprint = {2, 2, 2}, motion = {kind = .Pump}}
	bounds := model_preview_bounds(machine, 2.35, 500)
	centre := (bounds.scene_minimum + bounds.scene_maximum) / 2
	radius := linalg.length(bounds.scene_maximum - bounds.scene_minimum) / 2
	least := radius / math.sin(f32(20) * math.RAD_PER_DEG)
	front := model_preview_camera(.Front, bounds)
	testing.expect(t, front.position.x > bounds.model_maximum.x && front.position.z < centre.z)
	testing.expect(t, linalg.length(front.position - centre) >= least)
	back := model_preview_camera(.Back, bounds)
	testing.expect(t, back.position.x < bounds.model_minimum.x && back.position.z > centre.z)
	testing.expect(t, linalg.length(back.position - centre) >= least)
	top := model_preview_camera(.Top, bounds)
	testing.expect(t, top.position.x == centre.x && top.position.z == centre.z && top.position.y > centre.y)
	testing.expect_value(t, top.up, [3]f32{1, 0, 0})
	close := model_preview_camera(.Close, bounds)
	face := [3]f32{bounds.model_maximum.x, bounds.model_maximum.y / 2, (bounds.model_minimum.z + bounds.model_maximum.z) / 2}
	testing.expect_value(t, close.target, face)
	testing.expect_value(t, close.position - face, [3]f32{2, 0, 0})
	feet := model_preview_capsule_feet(0.5)
	for point in ([2][3]f32{feet - {0.3, 0, 0.3}, feet + {0.3, 1.8, 0.3}}) {
		testing.expect(t, point == linalg.clamp(point, bounds.scene_minimum, bounds.scene_maximum), "the capsule inside the scene")
	}
}
