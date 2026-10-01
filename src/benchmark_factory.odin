package game

import "core:encoding/json"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "platform"

// The headless factory benchmark (work item 0050, doc/architecture.md):
// a flat world built in code, a factory laid out from module blueprints
// in data scaled by a size, and the wall time of every simulation system
// over a run of ticks (tick_profile.odin). The layout is content: the
// manifest data/blueprints/benchmark.sjson lists the modules, each a
// blueprint under data/blueprints/benchmark/ with its footprint, its copies
// per size and the veins it stands on. Odin only tiles the grid, lays the
// floor, adds the veins, runs the blueprints and measures. The test
// (benchmark_test.odin) and --benchmark=<size> (main.odin) share the
// runner and the table.

BENCHMARK_MANIFEST_FILE :: "blueprints/benchmark.sjson"
BENCHMARK_MODULE_DIRECTORY :: "blueprints/benchmark"
// Blocks between two module footprints, across and along the columns.
BENCHMARK_MODULE_GAP :: 4
// World y of relative y 0: the air above the grass of chunk y 0.
BENCHMARK_SURFACE_Y :: CHUNK_SIZE
// Chunks of floor around the grid, and the chunk rows the floor fills.
BENCHMARK_FLOOR_MARGIN_CHUNKS :: 1
BENCHMARK_LOWEST_CHUNK_Y :: -1
BENCHMARK_HIGHEST_CHUNK_Y :: 2
// Every technology costs this percent of its packs (the world setting
// research cost multiplier), so the one technology the builder queues
// outlasts every run at every size.
BENCHMARK_RESEARCH_COST_PERCENT :: 100_000
// Larger factories are read off size 16 (user, 2026-09-28): the cost per
// tick is close to linear in the size, and a size 64 build took minutes,
// nearly all of it network rebuilds.
BENCHMARK_LARGEST_SIZE :: 16
// The window over which a machine must show progress at the end of the
// warm up.
BENCHMARK_IDLE_WINDOW_SECONDS :: 60

Benchmark_Vein_Definition :: struct {
	vein_type:  string `json:"type"`,
	size_class: string,
	x:          i32,
	z:          i32,
}

// extent is the footprint [width, depth] the layout tiles by; veins are
// relative to the module origin and added before its commands run.
Benchmark_Module_Definition :: struct {
	file:            string,
	extent:          [2]i32,
	copies_per_size: int,
	veins:           []Benchmark_Vein_Definition,
}

Benchmark_Manifest :: struct {
	modules: []Benchmark_Module_Definition,
}

// The manifest and every module's blueprint text, in arena.
Benchmark_Plan :: struct {
	manifest:   Benchmark_Manifest,
	blueprints: [][]byte,
	arena:      ^virtual.Arena,
}

// One copy of a module: its minimum corner on the surface and its
// footprint.
Module_Placement :: struct {
	module: int,
	copy:   int,
	origin: World_Coordinate,
	extent: [2]i32,
}

// The chunk columns the floor covers, both corners included.
Benchmark_Floor :: struct {
	first: Chunk_Column,
	last:  Chunk_Column,
}

Idle_Machine :: struct {
	machine: Machine_Id,
	cell:    World_Coordinate,
}

// problem is set when the factory could not be built; the timings are
// then empty. Owned: idle and problem (context.allocator).
Benchmark_Report :: struct {
	size:                 int,
	problem:              string,
	entity_counts:        [Entity_Kind]int,
	belt_items:           int,
	warm_up_ticks:        int,
	measured_ticks:       int,
	tick_rate:            int,
	profile:              Tick_Profile,
	average_milliseconds: f64,
	worst_milliseconds:   f64,
	idle:                 []Idle_Machine,
}

destroy_benchmark_report :: proc(report: Benchmark_Report) {
	delete(report.idle)
	delete(report.problem)
}

// Plan.

parse_benchmark_manifest :: proc(data: []byte, allocator := context.allocator) -> (manifest: Benchmark_Manifest, problem: string) {
	if error := json.unmarshal(data, &manifest, .SJSON, allocator); error != nil {
		return {}, fmt.tprintf("not a benchmark manifest: %v", error)
	}
	if len(manifest.modules) == 0 {
		return {}, "the manifest lists no modules"
	}
	for module in manifest.modules {
		if module.extent.x < 1 || module.extent.y < 1 || module.copies_per_size < 1 {
			return {}, fmt.tprintf("module %s needs a positive extent and copies_per_size", module.file)
		}
	}
	return manifest, ""
}

read_benchmark_file :: proc(data_directory: string, parts: []string, allocator := context.allocator) -> (data: []byte, problem: string) {
	path, _ := os.join_path(parts, context.temp_allocator)
	full, _ := os.join_path({data_directory, path}, context.temp_allocator)
	error: os.Error
	if data, error = os.read_entire_file(full, allocator); error != nil {
		return nil, fmt.tprintf("cannot read %s: %v", full, error)
	}
	return data, ""
}

// The manifest and the module blueprints under the data directory.
load_benchmark_plan :: proc(data_directory: string) -> (plan: Benchmark_Plan, problem: string) {
	plan.arena = new_growing_arena()
	allocator := virtual.arena_allocator(plan.arena)
	manifest_data: []byte
	if manifest_data, problem = read_benchmark_file(data_directory, {BENCHMARK_MANIFEST_FILE}, allocator); problem == "" {
		plan.manifest, problem = parse_benchmark_manifest(manifest_data, allocator)
	}
	if problem == "" {
		plan.blueprints = make([][]byte, len(plan.manifest.modules), allocator)
		for module, index in plan.manifest.modules {
			if plan.blueprints[index], problem = read_benchmark_file(data_directory, {BENCHMARK_MODULE_DIRECTORY, module.file}, allocator); problem != "" {
				break
			}
		}
	}
	if problem != "" {
		destroy_benchmark_plan(&plan)
	}
	return
}

destroy_benchmark_plan :: proc(plan: ^Benchmark_Plan) {
	destroy_arena(plan.arena)
	plan^ = {}
}

// What an id word of a blueprint command names, or the problem.
benchmark_command_problem :: proc(words: []string, content: Simulation_Content) -> string {
	if len(words) < 2 {
		return "no id"
	}
	found := true
	switch words[0] {
	case "place":
		_, found = find_machine_id(content.machines, words[1])
	case "block":
		_, found = find_block_id(content.blocks, words[1])
	case "insert", "filter":
		_, found = find_item_id(content.items, words[1])
	case "recipe":
		found = find_recipe(content.recipes, words[1]) != NO_RECIPE
	case "remove":
	case:
		return fmt.tprintf("%s is not a blueprint command", words[0])
	}
	return found ? "" : fmt.tprintf("unknown %s id %q", words[0], words[1])
}

// Every module parses with origin [0, 0, 0], names shipped machines,
// blocks, items, recipes, vein types and size classes, and keeps its
// veins inside its extent.
validate_benchmark_plan :: proc(plan: Benchmark_Plan, content: Simulation_Content) -> string {
	for module, index in plan.manifest.modules {
		blueprint, problem := parse_blueprint(plan.blueprints[index])
		if problem == "" && (blueprint.origin_kind != .Cell || blueprint.cell != {}) {
			problem = "origin must be [0, 0, 0]"
		}
		for command, number in blueprint.commands {
			if problem != "" {
				break
			}
			words, split_problem := expand_blueprint_command(command, {})
			if problem = split_problem; problem == "" {
				problem = benchmark_command_problem(words, content)
			}
			if problem != "" {
				problem = fmt.tprintf("command %d (%s): %s", number + 1, command, problem)
			}
		}
		for vein in module.veins {
			if problem == "" {
				problem = benchmark_vein_problem(vein, module.extent, content.veins)
			}
		}
		if problem != "" {
			return fmt.tprintf("%s: %s", module.file, problem)
		}
	}
	return ""
}

benchmark_vein_problem :: proc(vein: Benchmark_Vein_Definition, extent: [2]i32, veins: Vein_Content) -> string {
	switch {
	case find_vein_type(veins, vein.vein_type) < 0:
		return fmt.tprintf("unknown vein type %q", vein.vein_type)
	case find_size_class(veins, vein.size_class) < 0:
		return fmt.tprintf("unknown size class %q", vein.size_class)
	case vein.x < 0 || vein.z < 0 || vein.x >= extent.x || vein.z >= extent.y:
		return fmt.tprintf("the %s vein at %d %d lies outside the extent", vein.vein_type, vein.x, vein.z)
	}
	return ""
}

// Layout.

module_copies :: proc(module: Benchmark_Module_Definition, size: int) -> int {
	return module.copies_per_size * size
}

// Each module kind in its own column along x (pitch its width plus the
// gap), its copies along z (pitch its depth plus the gap), each column
// centred on z 0 and the columns together centred on x 0. In the temp
// allocator.
benchmark_layout :: proc(manifest: Benchmark_Manifest, size: int) -> []Module_Placement {
	placements := make([dynamic]Module_Placement, context.temp_allocator)
	total_width := i32(-BENCHMARK_MODULE_GAP)
	for module in manifest.modules {
		total_width += module.extent.x + BENCHMARK_MODULE_GAP
	}
	x := -total_width / 2
	for module, index in manifest.modules {
		copies := module_copies(module, size)
		pitch := module.extent.y + BENCHMARK_MODULE_GAP
		z := -(i32(copies) * pitch - BENCHMARK_MODULE_GAP) / 2
		for copy in 0 ..< copies {
			origin := World_Coordinate{x, BENCHMARK_SURFACE_Y, z + i32(copy) * pitch}
			append(&placements, Module_Placement{module = index, copy = copy, origin = origin, extent = module.extent})
		}
		x += module.extent.x + BENCHMARK_MODULE_GAP
	}
	return placements[:]
}

// The smallest and largest column any placement covers.
layout_bounds :: proc(placements: []Module_Placement) -> (minimum, maximum: [2]i32) {
	minimum, maximum = {max(i32), max(i32)}, {min(i32), min(i32)}
	for placement in placements {
		corner := placement.origin.xz
		minimum = {min(minimum.x, corner.x), min(minimum.y, corner.y)}
		maximum = {max(maximum.x, corner.x + placement.extent.x - 1), max(maximum.y, corner.y + placement.extent.y - 1)}
	}
	return
}

// The chunk columns under the layout with a margin, so the pad and the
// player stand on floor beyond the grid's corners.
benchmark_floor :: proc(placements: []Module_Placement) -> Benchmark_Floor {
	minimum, maximum := layout_bounds(placements)
	first := chunk_column_of(world_to_chunk_coordinate({minimum.x, 0, minimum.y}))
	last := chunk_column_of(world_to_chunk_coordinate({maximum.x, 0, maximum.y}))
	margin := Chunk_Column{BENCHMARK_FLOOR_MARGIN_CHUNKS, BENCHMARK_FLOOR_MARGIN_CHUNKS}
	return Benchmark_Floor{first = first - margin, last = last + margin}
}

// The surface block (world y 31) of the floor's first and last corner
// columns: the landing pad in one, the player in the other.
benchmark_pad_surface :: proc(floor: Benchmark_Floor) -> World_Coordinate {
	return {floor.first.x * CHUNK_SIZE + CHUNK_SIZE / 2, BENCHMARK_SURFACE_Y - 1, floor.first.y * CHUNK_SIZE + CHUNK_SIZE / 2}
}

benchmark_player_surface :: proc(floor: Benchmark_Floor) -> World_Coordinate {
	return {floor.last.x * CHUNK_SIZE + CHUNK_SIZE / 2, BENCHMARK_SURFACE_Y - 1, floor.last.y * CHUNK_SIZE + CHUNK_SIZE / 2}
}

// World.

// Stone in chunk y -1 and 0 with grass on top (world y 31), air above up
// to chunk y 2, every block under full sky light, so no light has to
// propagate. Chunks are marked loaded like streamed ones, with empty vein
// lists: the benchmark adds its own veins.
build_benchmark_world :: proc(world: ^World, blocks: Block_Registry, floor: Benchmark_Floor) {
	stone, _ := find_block_id(blocks, "stone")
	grass, _ := find_block_id(blocks, "grass")
	for z in floor.first.y ..= floor.last.y {
		for x in floor.first.x ..= floor.last.x {
			for y in i32(BENCHMARK_LOWEST_CHUNK_Y) ..= BENCHMARK_HIGHEST_CHUNK_Y {
				world.chunks[{x, y, z}] = make_floor_chunk({x, y, z}, stone, grass)
			}
			if Chunk_Column({x, z}) not_in world.column_veins {
				world.column_veins[{x, z}] = make([dynamic]Vein_Id)
			}
		}
	}
}

make_floor_chunk :: proc(coordinate: Chunk_Coordinate, stone, grass: Block_Id) -> ^Chunk {
	chunk := new(Chunk)
	chunk.coordinate = coordinate
	if coordinate.y <= 0 {
		for &block, index in chunk.blocks {
			block = coordinate.y == 0 && index_to_local(index).y == CHUNK_SIZE - 1 ? grass : stone
		}
	}
	for &light in chunk.light {
		light = pack_light(MAXIMUM_LIGHT, {})
	}
	chunk.modified = true
	return chunk
}

// Factory.

// A surface vein centred on the column like the developer command's
// (make_added_vein, add_vein), checked only against the veins already in
// the world: the floor replaces the generated terrain, so the generator's
// own veins are not there.
add_benchmark_vein :: proc(world: ^World, content: Simulation_Content, definition: Benchmark_Vein_Definition, column: [2]i32) -> string {
	generator := content.generator
	vein := make_added_vein(generator, find_vein_type(content.veins, definition.vein_type), find_size_class(content.veins, definition.size_class), column)
	for other in world.veins {
		if discs_overlap(other.centre, other.radius, vein.centre, vein.radius) {
			return fmt.tprintf("the %s vein of radius %d at %d %d overlaps another vein", definition.vein_type, vein.radius, column.x, column.y)
		}
	}
	add_vein(world, generator, vein)
	return ""
}

// The module's veins, then its blueprint from the copy's origin.
build_module_copy :: proc(command_context: Command_Context, plan: Benchmark_Plan, placement: Module_Placement) -> string {
	module := plan.manifest.modules[placement.module]
	world := &command_context.simulation.world
	for vein in module.veins {
		if problem := add_benchmark_vein(world, command_context.content, vein, placement.origin.xz + {vein.x, vein.z}); problem != "" {
			return problem
		}
	}
	blueprint, problem := parse_blueprint(plan.blueprints[placement.module])
	if problem != "" {
		return problem
	}
	blueprint.origin_kind, blueprint.cell = .Cell, placement.origin
	if response := run_blueprint(command_context, blueprint); !response.ok {
		return response.text
	}
	return ""
}

// Every copy of the layout, each with the scratch arena as the temp
// allocator emptied after it, since every placement rebuilds networks in
// temp memory and a whole factory's worth would pile up. The first
// failure names the module, the copy and the command; owned.
build_benchmark_factory :: proc(simulation: ^Simulation_State, content: Simulation_Content, plan: Benchmark_Plan, placements: []Module_Placement, scratch: ^virtual.Arena) -> string {
	command_context := Command_Context{simulation = simulation, content = content}
	for placement in placements {
		problem: string
		{
			context.temp_allocator = virtual.arena_allocator(scratch)
			if problem = build_module_copy(command_context, plan, placement); problem != "" {
				module := plan.manifest.modules[placement.module].file
				problem = fmt.aprintf("module %s copy %d at %d %d %d: %s", module, placement.copy + 1, placement.origin.x, placement.origin.y, placement.origin.z, problem)
			}
		}
		virtual.arena_free_all(scratch)
		if problem != "" {
			return problem
		}
	}
	return ""
}

// The labs' technology: the first one research may start, as a player
// would pick it in the technology screen.
queue_first_available_research :: proc(simulation: ^Simulation_State, technologies: Technology_Registry) -> bool {
	for _, technology in technologies.technologies {
		if queue_research(&simulation.records.research, technologies, simulation.unlocks, technology) == .None {
			return true
		}
	}
	return false
}

// Machine activity.

// Machines whose progress shows in their state rather than in an output
// rate, seen working on some tick of the idle window.
Machine_Activity :: map[Entity_Handle]bool

fluid_machine_is_working :: proc(state: Fluid_Machine_State) -> bool {
	return state == .Producing || state == .Pumping || state == .Flaring || state == .Generating
}

// Per tick over the idle window: crafting machines (assemblers, refineries, cracking units, chemical
// plants) by a craft running, labs by researching, fluid machines by
// producing, pumping, flaring or generating, launch pads by assembling or
// launching.
observe_machine_activity :: proc(world: ^World, activity: ^Machine_Activity) {
	for assembler in world.entities.assemblers.entries {
		if assembler.alive && assembler.state == .Working {
			activity[assembler.handle] = true
		}
	}
	for lab in world.entities.labs.entries {
		if lab.alive && lab.state == .Researching {
			activity[lab.handle] = true
		}
	}
	for machine in world.entities.fluid_machines.entries {
		if machine.alive && fluid_machine_is_working(machine.state) {
			activity[machine.handle] = true
		}
	}
	for pad in world.entities.launch_pads.entries {
		if pad.alive && (pad.state == .Assembling || pad.state == .Launching) {
			activity[pad.handle] = true
		}
	}
}

// A generator in the Idle state delivered nothing while it could have
// (or nothing was asked): a reserve behind generators of a lower dispatch
// order (0140), like the fuel generator beside running engines. Not idle;
// No_Fuel, No_Steam and No_Water still are.
generator_is_standing_by :: proc(kind: Machine_Kind, state: Fluid_Machine_State) -> bool {
	return machine_kind_is_generator(kind) && state == .Idle
}

idle_machine_of :: proc(common: Entity_Common) -> Idle_Machine {
	return Idle_Machine{machine = common.machine, cell = common.origin}
}

// After the idle window: drills and furnaces by their output over the
// last minute (the rate their panels show), inserters by an idle streak
// (nothing to pick) as long as the window, every other machine by the
// observed activity, except a generator standing by. An inserter holding an item for a full target is not
// idle: its supply runs, the target is just stocked. Storage tanks hold
// fluid and do no work, so they are left out. In the temp allocator, by
// cell.
benchmark_idle_machines :: proc(world: ^World, second: u64, content: Simulation_Content, activity: Machine_Activity, tick_rate: int) -> []Idle_Machine {
	idle := make([dynamic]Idle_Machine, context.temp_allocator)
	for inserter in world.entities.inserters.entries {
		if inserter.alive && int(inserter.idle_streak) >= BENCHMARK_IDLE_WINDOW_SECONDS * tick_rate {
			append(&idle, idle_machine_of(inserter.common))
		}
	}
	for drill in world.entities.drills.entries {
		if drill.alive && machine_output_per_minute(drill.output_rate, second) == 0 {
			append(&idle, idle_machine_of(drill.common))
		}
	}
	for furnace in world.entities.furnaces.entries {
		if furnace.alive && machine_output_per_minute(furnace.output_rate, second) == 0 {
			append(&idle, idle_machine_of(furnace.common))
		}
	}
	append_unobserved(&idle, world.entities.assemblers.entries[:], activity)
	append_unobserved(&idle, world.entities.labs.entries[:], activity)
	append_unobserved(&idle, world.entities.launch_pads.entries[:], activity)
	for machine in world.entities.fluid_machines.entries {
		kind := content.machines.machines[machine.machine].kind
		if machine.alive && kind != .Storage_Tank && !activity[machine.handle] && !generator_is_standing_by(kind, machine.state) {
			append(&idle, idle_machine_of(machine.common))
		}
	}
	slice.sort_by(idle[:], proc(first, second: Idle_Machine) -> bool {
		return coordinate_before(first.cell, second.cell)
	})
	return idle[:]
}

append_unobserved :: proc(idle: ^[dynamic]Idle_Machine, entries: []$T, activity: Machine_Activity) {
	for entry in entries {
		if entry.alive && !activity[entry.handle] {
			append(idle, idle_machine_of(entry.common))
		}
	}
}

// Runner.

// The simulation of the benchmark world: the pad in the floor's first
// corner, the player standing in the last, research costs scaled.
make_benchmark_simulation :: proc(config: Game_Config, content: Simulation_Content, floor: Benchmark_Floor) -> Simulation_State {
	pad := Landing_Pad_Site{present = true, centre = benchmark_pad_surface(floor)}
	simulation := make_simulation(config, player_start_on(benchmark_player_surface(floor)), content, content.technologies, false, pad)
	generator := content.generator
	simulation.world.settings = World_Settings {
		seed                  = generator.seed,
		vein_richness_percent = generator.vein_richness_percent,
		research_cost_percent = BENCHMARK_RESEARCH_COST_PERCENT,
	}
	return simulation
}

// Builds the world and the factory of the size, ticks the warm up (the
// last BENCHMARK_IDLE_WINDOW_SECONDS of it watching for idle machines),
// then the measured ticks with the profile the report keeps. content's
// technologies are scaled here; its generator serves the vein tables.
// The build and the ticks run with a temp allocator of their own,
// emptied after every module copy and every tick as a frame does, so the
// caller's temp allocations (the test content lives there) survive.
run_factory_benchmark :: proc(size: int, generator: ^Generator, base_content: Simulation_Content, config: Game_Config, plan: Benchmark_Plan, warm_up_ticks, measured_ticks: int) -> (report: Benchmark_Report) {
	report.size, report.warm_up_ticks, report.measured_ticks, report.tick_rate = size, warm_up_ticks, measured_ticks, config.tick_rate
	content := base_content
	content.generator = generator
	content.technologies = scaled_technology_registry(base_content.technologies, BENCHMARK_RESEARCH_COST_PERCENT)
	defer delete(content.technologies.technologies)
	if problem := validate_benchmark_plan(plan, content); problem != "" {
		report.problem = strings.clone(problem)
		return
	}
	placements := benchmark_layout(plan.manifest, size)
	simulation := make_benchmark_simulation(config, content, benchmark_floor(placements))
	defer destroy_simulation(&simulation)
	build_benchmark_world(&simulation.world, content.blocks, benchmark_floor(placements))
	queue_first_available_research(&simulation, content.technologies)
	tick_arena: virtual.Arena
	if virtual.arena_init_growing(&tick_arena) != nil {
		report.problem = strings.clone("cannot reserve the tick memory")
		return
	}
	defer virtual.arena_destroy(&tick_arena)
	if report.problem = build_benchmark_factory(&simulation, content, plan, placements, &tick_arena); report.problem != "" {
		return
	}
	report.idle = warm_up_benchmark(&simulation, content, warm_up_ticks, &tick_arena)
	report.entity_counts = entity_counts(&simulation.world.entities)
	measure_benchmark(&simulation, content, &report, &tick_arena)
	report.belt_items = belt_item_count(simulation.world.entities.belt_network)
	return
}

// The idle machines at the end of the warm up, owned.
warm_up_benchmark :: proc(simulation: ^Simulation_State, content: Simulation_Content, ticks: int, tick_arena: ^virtual.Arena) -> []Idle_Machine {
	activity := make(Machine_Activity)
	defer delete(activity)
	window_start := ticks - BENCHMARK_IDLE_WINDOW_SECONDS * simulation.tick_rate
	{
		context.temp_allocator = virtual.arena_allocator(tick_arena)
		for tick in 0 ..< ticks {
			simulation_tick(simulation, content, {})
			if tick >= window_start {
				observe_machine_activity(&simulation.world, &activity)
			}
			virtual.arena_free_all(tick_arena)
		}
	}
	return slice.clone(benchmark_idle_machines(&simulation.world, simulation.records.statistics.current_second, content, activity, simulation.tick_rate))
}

measure_benchmark :: proc(simulation: ^Simulation_State, content: Simulation_Content, report: ^Benchmark_Report, tick_arena: ^virtual.Arena) {
	context.temp_allocator = virtual.arena_allocator(tick_arena)
	total, worst: time.Duration
	for _ in 0 ..< report.measured_ticks {
		start := time.tick_now()
		simulation_tick(simulation, content, {}, &report.profile)
		elapsed := time.tick_since(start)
		total += elapsed
		worst = max(worst, elapsed)
		virtual.arena_free_all(tick_arena)
	}
	report.average_milliseconds = time.duration_milliseconds(total) / f64(max(report.measured_ticks, 1))
	report.worst_milliseconds = time.duration_milliseconds(worst)
}

// Table.

// A row per section with milliseconds per tick and the share of the
// sections' sum, the total, the counts and the idle machines. In the temp
// allocator.
format_benchmark_report :: proc(report: Benchmark_Report, machines: Machine_Registry) -> string {
	builder := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&builder, "factory benchmark size %d", report.size)
	if report.problem != "" {
		fmt.sbprintf(&builder, "\nbuild failed: %s", report.problem)
		return strings.to_string(builder)
	}
	seconds_per_minute := f64(report.tick_rate * 60)
	fmt.sbprintf(&builder, ", %.1f minutes warm up, %.1f minutes measured", f64(report.warm_up_ticks) / seconds_per_minute, f64(report.measured_ticks) / seconds_per_minute)
	write_benchmark_sections(&builder, report)
	write_benchmark_counts(&builder, report)
	fmt.sbprintf(&builder, "\nidle machines after the warm up: %d", len(report.idle))
	for machine in report.idle {
		fmt.sbprintf(&builder, "\n  %s at %d %d %d", machines.machines[machine.machine].id, machine.cell.x, machine.cell.y, machine.cell.z)
	}
	return strings.to_string(builder)
}

write_benchmark_sections :: proc(builder: ^strings.Builder, report: Benchmark_Report) {
	ticks := f64(max(report.profile.ticks, 1))
	sum := profile_total_seconds(report.profile)
	fmt.sbprintf(builder, "\n%-20s %10s %7s", "section", "ms/tick", "share")
	for seconds, section in report.profile.seconds {
		share := sum > 0 ? 100 * seconds / sum : 0
		write_benchmark_row(builder, fmt.tprint(section), 1000 * seconds / ticks, fmt.tprintf("%.1f%%", share))
	}
	write_benchmark_row(builder, "sections", 1000 * sum / ticks, "100.0%")
	write_benchmark_row(builder, "tick average", report.average_milliseconds, "")
	write_benchmark_row(builder, "tick worst", report.worst_milliseconds, "")
}

// Numbers are formatted first, since a width on a float pads with zeros.
write_benchmark_row :: proc(builder: ^strings.Builder, name: string, milliseconds: f64, share: string) {
	fmt.sbprintf(builder, "\n%-20s %10s", name, fmt.tprintf("%.4f", milliseconds))
	if share != "" {
		fmt.sbprintf(builder, " %7s", share)
	}
}

write_benchmark_counts :: proc(builder: ^strings.Builder, report: Benchmark_Report) {
	total := 0
	strings.write_string(builder, "\nentities:")
	for count, kind in report.entity_counts {
		if count > 0 && kind != .None {
			fmt.sbprintf(builder, " %v %d,", kind, count)
			total += count
		}
	}
	fmt.sbprintf(builder, " total %d; items on belts %d", total, report.belt_items)
}

// --benchmark=<size> (main.odin): the shipped data and the default seed's
// vein tables, two minutes of warm up and ten measured, the table on
// stdout. Exit status 1 when the factory cannot be built or a machine
// idles.
BENCHMARK_COMMAND_WARM_UP_MINUTES :: 2
BENCHMARK_COMMAND_MEASURED_MINUTES :: 10

run_command_line_benchmark :: proc(size: int, data_directory: string, config: Game_Config, game_data: Game_Data) -> int {
	plan, problem := load_benchmark_plan(data_directory)
	if problem != "" {
		platform.log_printf("error: %s", problem)
		return 1
	}
	defer destroy_benchmark_plan(&plan)
	generator := session_generator(game_data.base_generator, DEFAULT_WORLD_SEED, 100)
	content := game_data.content.simulation_content
	ticks_per_minute := 60 * config.tick_rate
	report := run_factory_benchmark(size, &generator, content, config, plan, BENCHMARK_COMMAND_WARM_UP_MINUTES * ticks_per_minute, BENCHMARK_COMMAND_MEASURED_MINUTES * ticks_per_minute)
	defer destroy_benchmark_report(report)
	fmt.println(format_benchmark_report(report, content.machines))
	return report.problem == "" && len(report.idle) == 0 ? 0 : 1
}
