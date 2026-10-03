package game

import "core:log"
import "core:strings"
import "core:testing"

// The factory benchmark (work item 0050): the plan, the layout and the
// floor as pure pieces, and the run of size 1 on the field world (0179)
// that logs the table. ./build.sh bench runs the last one optimised,
// where the budget holds; the plain test build only logs the numbers.
// Size 4 comes back with the factories on frames (M14).

// Half the 60 Hz budget, so CI runners have room.
BENCHMARK_SIZE_1_BUDGET_MILLISECONDS :: 8.0
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

// The field of the benchmark from the shipped planet and tables.
test_benchmark_field :: proc(items: Item_Registry) -> Benchmark_Field {
	lighting, problem := parse_lighting_file(#load("../data/lighting.sjson"), LIGHTING_FILE_NAME, context.temp_allocator)
	assert(problem == "", problem)
	return Benchmark_Field{planet = shipped_test_planets()[0], materials = test_field_materials(items), lighting = lighting}
}

// Builds and runs size 1 on the field world and logs its table. Every
// machine must work at the end of the warm up, and the player stands in
// the pod's cabin at the home, with the pad 24 m ahead of it; the
// budget holds only in the optimised build (./build.sh bench), the plain
// build logs. Size 2 is refused with the M14 message.
@(test)
test_factory_benchmark :: proc(t: ^testing.T) {
	plan := load_test_benchmark_plan(t)
	defer destroy_benchmark_plan(&plan)
	content := make_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	config := test_field_game_config()
	config.starting_items = nil
	field := test_benchmark_field(content.items)
	ticks_per_minute := 60 * config.tick_rate
	report := run_factory_benchmark(1, &generator, content, field, config, plan, BENCHMARK_TEST_WARM_UP_MINUTES * ticks_per_minute, BENCHMARK_TEST_MEASURED_MINUTES * ticks_per_minute)
	defer destroy_benchmark_report(report)
	log.infof("\n%s", format_benchmark_report(report, content.machines))
	testing.expect_value(t, report.problem, "")
	testing.expect_value(t, len(report.idle), 0)
	testing.expect_value(t, report.profile.ticks, report.measured_ticks)
	// The benchmark's pad and the pod, which rides in the foundations'
	// pool; the player starts in the pod.
	pad := (2 * BENCHMARK_PAD_HALF_WIDTH + 1) * (2 * BENCHMARK_PAD_HALF_WIDTH + 1)
	testing.expect_value(t, report.entity_counts[.Foundation], pad + 1)
	when ODIN_OPTIMIZATION_MODE == .Speed {
		testing.expectf(t, report.average_milliseconds < BENCHMARK_SIZE_1_BUDGET_MILLISECONDS, "size 1 averages %.3f ms per tick, over the %.1f ms budget", report.average_milliseconds, BENCHMARK_SIZE_1_BUDGET_MILLISECONDS)
	}
	larger := run_factory_benchmark(2, &generator, content, field, config, plan, 0, 0)
	defer destroy_benchmark_report(larger)
	testing.expect(t, strings.contains(larger.problem, "M14"), larger.problem)
}

// Work item 0196: the benchmark's pad is laid in the content's pad
// foundation, the wooden one; the pod has no pad (0199).
@(test)
test_the_benchmark_pad_is_the_contents_pad_foundation :: proc(t: ^testing.T) {
	content := make_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content.generator = &generator
	config := test_field_game_config()
	config.starting_items = nil
	field := test_benchmark_field(content.items)
	content.field = make_field_content(config, content.items, content.machines, field.materials, field.lighting, field.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	defer destroy_field_content(&content.field)
	testing.expect_value(t, content.machines.machines[field_pad_foundation(content)].id, "wooden_foundation")
	simulation := make_benchmark_simulation(config, content, Benchmark_Floor{})
	defer destroy_simulation(&simulation)
	start_benchmark_field(&simulation, content, config, field.planet)
	laid := 0
	for foundation in simulation.world.entities.foundations.entries {
		if foundation.alive && content.machines.machines[foundation.machine].kind == .Foundation {
			testing.expect_value(t, foundation.machine, content.field.pad_foundation)
			laid += 1
		}
	}
	pad := (2 * BENCHMARK_PAD_HALF_WIDTH + 1) * (2 * BENCHMARK_PAD_HALF_WIDTH + 1)
	testing.expect_value(t, laid, pad)
}
