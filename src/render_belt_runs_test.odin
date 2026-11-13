package game

import "core:testing"
import rl "shared:raylib"

// Work item 0347: what a belt run's cull and its items' instances read.

@(test)
test_a_belt_run_box_holds_its_surface_and_items :: proc(t: ^testing.T) {
	machines := make_test_machines()
	entities: Entities
	defer destroy_entities(&entities)
	radius := 5 * TEST_RUN_METRE
	first := add_test_pole(&entities, machines, {0, 0, 0}, 0)
	second := add_test_pole(&entities, machines, {radius, 0, radius}, 1)
	handle, refusal := add_test_run(&entities, machines, first, second)
	testing.expect_value(t, refusal, Belt_Run_Refusal.None)
	run := pool_get(&entities.belt_runs, handle)
	if run == nil {
		return
	}
	ups, pitch, found := belt_run_frame_facts(&entities, run^)
	testing.expect(t, found, "the run's frames")
	minimum, maximum := belt_run_box(run.curve, pitch)
	half, lift, depth := pitch / 2, pitch * BELT_SURFACE_HEIGHT, pitch * BELT_RUN_SIDE_DEPTH_SHARE
	size := BELT_ITEM_SIZE * pitch
	for step in 0 ..= BELT_RUN_SUBDIVISIONS {
		section := belt_run_section(run.curve, ups, step)
		points := make([dynamic][3]f32, context.temp_allocator)
		for side in ([2]f32{-1, 1}) {
			surface := section.centre + section.right * (half * side) + section.up * lift
			append(&points, surface, surface - section.up * depth)
			item := section.centre + section.right * (side * BELT_LANE_OFFSET * pitch) + section.up * (lift + size / 2)
			for corner in 0 ..< 8 {
				offset := [3]f32{corner & 1 == 0 ? -1 : 1, corner & 2 == 0 ? -1 : 1, corner & 4 == 0 ? -1 : 1}
				append(&points, item + offset * (size / 2))
			}
		}
		for point in points {
			testing.expectf(t, point_in_posed_box(point, minimum, maximum), "step %d: %v in %v to %v", step, point, minimum, maximum)
		}
	}
}

@(test)
test_a_belt_item_instance_is_its_cube :: proc(t: ^testing.T) {
	color := rl.Color{30, 60, 90, 255}
	instance := belt_item_instance({1, 2, 3}, 0.1, color)
	testing.expect(t, instance[0, 3] == 1 && instance[1, 3] == 2 && instance[2, 3] == 3, "the translation is the centre")
	testing.expect(t, instance[0, 0] == 0.1 && instance[1, 1] == 0.1 && instance[2, 2] == 0.1, "the diagonal is the size")
	testing.expect(t, instance[0, 1] == 0 && instance[1, 2] == 0 && instance[2, 0] == 0, "no rotation")
	testing.expect(t, instance[3, 0] == 30.0 / 255 && instance[3, 1] == 60.0 / 255 && instance[3, 2] == 90.0 / 255 && instance[3, 3] == 1, "the bottom row the colour over 255, and 1")
}
