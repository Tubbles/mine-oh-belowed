package game

import "core:log"
import "core:testing"

// The factory benchmark (work item 0050): the plan, the layout and the
// floor as pure pieces, and the run of sizes 1 and 4 that logs the table.
// ./build.sh bench runs the last one optimised, where the size 4 budget
// holds; the plain test build only logs the numbers.

// Half the 60 Hz budget, so CI runners have room.
BENCHMARK_SIZE_4_BUDGET_MILLISECONDS :: 8.0
// Two minutes like the command line: machines at the end of a chain
// (the flare stack behind two cracking units, the lab behind two
// assemblers) first work well into the first minute.
BENCHMARK_TEST_WARM_UP_MINUTES :: 2
BENCHMARK_TEST_MEASURED_MINUTES :: 1

load_test_benchmark_plan :: proc(t: ^testing.T) -> Benchmark_Plan {
	plan, problem := load_benchmark_plan(test_data_directory())
	testing.expect_value(t, problem, "")
	return plan
}

@(test)
test_benchmark_plan_names_shipped_content :: proc(t: ^testing.T) {
	plan := load_test_benchmark_plan(t)
	defer destroy_benchmark_plan(&plan)
	content := make_test_content()
	testing.expect(t, len(plan.manifest.modules) > 0)
	testing.expect_value(t, validate_benchmark_plan(plan, content), "")
	broken := plan
	broken.blueprints = make([][]byte, len(plan.blueprints), context.temp_allocator)
	copy(broken.blueprints, plan.blueprints)
	broken.blueprints[0] = transmute([]byte)string(`origin = [0, 0, 0], commands = ["place no_such_machine 0 0 0 0"]`)
	testing.expect(t, validate_benchmark_plan(broken, content) != "")
	broken.blueprints[0] = transmute([]byte)string(`origin = [1, 0, 0], commands = []`)
	testing.expect(t, validate_benchmark_plan(broken, content) != "")
	_, problem := parse_benchmark_manifest(transmute([]byte)string(`modules = [{file = "a.sjson", extent = [0, 4], copies_per_size = 1}]`), context.temp_allocator)
	testing.expect(t, problem != "")
}

placements_overlap :: proc(first, second: Module_Placement) -> bool {
	first_end := first.origin.xz + first.extent
	second_end := second.origin.xz + second.extent
	return first.origin.x < second_end.x && second.origin.x < first_end.x && first.origin.z < second_end.y && second.origin.z < first_end.y
}

@(test)
test_benchmark_layout_tiles_without_overlap :: proc(t: ^testing.T) {
	plan := load_test_benchmark_plan(t)
	defer destroy_benchmark_plan(&plan)
	for size in ([?]int{1, 4, 16}) {
		placements := benchmark_layout(plan.manifest, size)
		expected := 0
		for module in plan.manifest.modules {
			expected += module_copies(module, size)
		}
		testing.expect_value(t, len(placements), expected)
		for first, index in placements {
			testing.expect_value(t, first.origin.y, BENCHMARK_SURFACE_Y)
			for second in placements[index + 1:] {
				testing.expectf(t, !placements_overlap(first, second), "size %d: %v overlaps %v", size, first, second)
			}
		}
		minimum, maximum := layout_bounds(placements)
		testing.expect(t, minimum.x < 0 && maximum.x > 0 && minimum.y < 0 && maximum.y > 0)
	}
}

@(test)
test_benchmark_world_is_a_flat_lit_floor :: proc(t: ^testing.T) {
	blocks := make_test_registry()
	world: World
	defer destroy_world(&world)
	floor := Benchmark_Floor{first = {-1, -1}, last = {0, 1}}
	build_benchmark_world(&world, blocks, floor)
	testing.expect_value(t, len(world.chunks), 2 * 3 * 4)
	testing.expect_value(t, len(world.column_veins), 2 * 3)
	stone, grass := test_block(blocks, "stone"), test_block(blocks, "grass")
	for column in ([?][2]i32{{-32, -32}, {0, 0}, {31, 63}}) {
		testing.expect_value(t, world_get_block(&world, {column.x, -32, column.y}), stone)
		testing.expect_value(t, world_get_block(&world, {column.x, 30, column.y}), stone)
		testing.expect_value(t, world_get_block(&world, {column.x, BENCHMARK_SURFACE_Y - 1, column.y}), grass)
		testing.expect_value(t, world_get_block(&world, {column.x, BENCHMARK_SURFACE_Y, column.y}), AIR_BLOCK)
		testing.expect_value(t, world_get_block(&world, {column.x, 95, column.y}), AIR_BLOCK)
	}
	testing.expect(t, world_to_chunk_coordinate({32, 0, 0}) not_in world.chunks)
	testing.expect(t, world_to_chunk_coordinate({0, 96, 0}) not_in world.chunks)
}

// Builds and runs sizes 1 and 4 and logs their tables. Every machine
// must work at the end of the warm up; the size 4 budget holds only in
// the optimised build (./build.sh bench), the plain build logs.
@(test)
test_factory_benchmark :: proc(t: ^testing.T) {
	plan := load_test_benchmark_plan(t)
	defer destroy_benchmark_plan(&plan)
	content := make_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	config := test_game_config()
	ticks_per_minute := 60 * config.tick_rate
	for size in ([?]int{1, 4}) {
		report := run_factory_benchmark(size, &generator, content, config, plan, BENCHMARK_TEST_WARM_UP_MINUTES * ticks_per_minute, BENCHMARK_TEST_MEASURED_MINUTES * ticks_per_minute)
		defer destroy_benchmark_report(report)
		log.infof("\n%s", format_benchmark_report(report, content.machines))
		testing.expect_value(t, report.problem, "")
		testing.expect_value(t, len(report.idle), 0)
		testing.expect_value(t, report.profile.ticks, report.measured_ticks)
		when ODIN_OPTIMIZATION_MODE == .Speed {
			if size == 4 {
				testing.expectf(t, report.average_milliseconds < BENCHMARK_SIZE_4_BUDGET_MILLISECONDS, "size 4 averages %.3f ms per tick, over the %.1f ms budget", report.average_milliseconds, BENCHMARK_SIZE_4_BUDGET_MILLISECONDS)
			}
		}
	}
}
