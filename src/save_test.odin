package game

import "core:log"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"
import "platform"

// Save tests write only under a temporary directory they create and
// remove, never under the real saves directory.

make_save_test_directory :: proc() -> string {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-save-test-*", context.temp_allocator)
	assert(error == nil)
	return directory
}

remove_save_test_directory :: proc(directory: string) {
	os.remove_all(directory)
}

save_test_location :: proc(directory: string) -> Save_Location {
	return Save_Location{saves_directory = directory, directory_name = sanitize_world_name("Round trip!", context.temp_allocator), display_name = "Round trip!"}
}

SAVE_TEST_LANDING_PAD :: Landing_Pad_Site {
	present = true,
	centre  = {20, 0, -26},
}

SAVE_TEST_PLAYER_SURFACE :: World_Coordinate{-26, 0, 8}

make_save_test_content :: proc() -> Simulation_Content {
	content := make_test_content()
	content.quests = make_test_quests(make_test_quest_references())
	return content
}

make_save_test_simulation :: proc(generator: ^Generator, content: Simulation_Content) -> Simulation_State {
	simulation := make_simulation(test_game_config(), player_start_on(SAVE_TEST_PLAYER_SURFACE), content, content.technologies, false, SAVE_TEST_LANDING_PAD)
	simulation.world.settings = World_Settings{seed = generator.seed}
	return simulation
}

load_save_test_chunks :: proc(world: ^World, records: ^Game_Records, generator: ^Generator) {
	chunks := TEST_WORLD_CHUNKS
	for coordinate in chunks {
		load_chunk_now(world, records, generator, coordinate)
	}
}

// The upper test chunks become a stone floor at y 0 under air, the lower
// ones stay as generated.
carve_save_test_floor :: proc(world: ^World, stone: Block_Id) {
	for _, chunk in world.chunks {
		if chunk.coordinate.y != 0 {
			continue
		}
		for &block, index in chunk.blocks {
			block = index_to_local(index).y == 0 ? stone : AIR_BLOCK
		}
		chunk.modified = true
		chunk.dirty = true
	}
}

// A furnace fed by an inserter, with an inserter onto a belt into a chest.
lay_save_test_smelting :: proc(world: ^World, content: Simulation_Content, offset: World_Coordinate) {
	ore_chest := place_test_entity(world, content, "wooden_chest", World_Coordinate{0, 1, 0} + offset)
	entity_insert(&world.entities, content, ore_chest, Item_Stack{test_item(content.items, "hematite"), 200})
	place_fuelled_inserter(world, content, World_Coordinate{1, 1, 0} + offset, 0)
	furnace := place_test_entity(world, content, "stone_furnace", World_Coordinate{2, 1, 0} + offset)
	entity_slots(&world.entities, furnace)[FURNACE_FUEL_SLOT] = Item_Stack{test_item(content.items, "coal"), 10}
	place_fuelled_inserter(world, content, World_Coordinate{12, 1, 0} + offset, 0)
	lay_belt_row(world, content, World_Coordinate{13, 1, 0} + offset, 3, 0)
	place_fuelled_inserter(world, content, World_Coordinate{16, 1, 0} + offset, 0)
	place_test_entity(world, content, "wooden_chest", World_Coordinate{17, 1, 0} + offset)
}

// A chest feeding a belt into a splitter whose halves end in chests.
lay_save_test_splitter :: proc(world: ^World, content: Simulation_Content, offset: World_Coordinate) {
	source := place_test_entity(world, content, "wooden_chest", World_Coordinate{-2, 1, 0} + offset)
	entity_insert(&world.entities, content, source, Item_Stack{test_item(content.items, "iron_plate"), 100})
	place_fuelled_inserter(world, content, World_Coordinate{-1, 1, 0} + offset, 0)
	lay_belt_row(world, content, offset + {0, 1, 0}, 4, 0)
	place_test_splitter(world, content, World_Coordinate{4, 1, 0} + offset, 0)
	for side in Splitter_Side {
		z := i32(side)
		lay_belt_row(world, content, World_Coordinate{5, 1, z} + offset, 2, 0)
		place_fuelled_inserter(world, content, World_Coordinate{7, 1, z} + offset, 0)
		place_test_entity(world, content, "wooden_chest", World_Coordinate{8, 1, z} + offset)
	}
}

// Research on two labs with their own steam engine.
lay_save_test_research :: proc(world: ^World, content: Simulation_Content, offset: World_Coordinate) {
	first := place_test_entity(world, content, "lab", World_Coordinate{1, 1, -1} + offset)
	second := place_test_entity(world, content, "lab", World_Coordinate{-4, 1, -1} + offset)
	box, _ := add_test_power_plant(world, content, World_Coordinate{-1, 1, 0} + offset, World_Coordinate{-2, 1, 2} + offset)
	cable_test_machines(world, content, box, first, second)
	pack := test_item(content.items, "science_pack_1")
	entity_insert(&world.entities, content, first, {pack, 6})
	entity_insert(&world.entities, content, second, {pack, 6})
}

SAVE_TEST_CRATE :: World_Coordinate{-28, 1, -28}
SAVE_TEST_GOLD_QUARTZ :: World_Coordinate{-29, 0, -28}

// Cave schematics (work item 0036): a placed crate holding a schematic, a
// crate site whose chunk is not loaded, a gold quartz block and one
// schematic read.
lay_save_test_schematics :: proc(simulation: ^Simulation_State, content: Simulation_Content) {
	world := &simulation.world
	records := &simulation.records
	sites := [2]Crate_Site{{region = {40, 40}, position = SAVE_TEST_CRATE, choice = 1}, {region = {41, 40}, position = {10_000, -40, 10_000}, choice = 2}}
	register_crate_sites(&records.crate_sites, sites[:])
	place_pending_crates(world_tick_context(world, records, content, TEST_TICK_RATE))
	world_set_block(world, SAVE_TEST_GOLD_QUARTZ, test_block(content.blocks, "gold_quartz"))
	schematic := test_item(content.items, "schematic_slag_concrete")
	read_schematic(&simulation.unlocks, &simulation.quests, &records.statistics, content.recipes, schematic, 0)
}

// The crate, the pending site, the gold quartz and the found schematic
// came through a save.
schematics_loaded :: proc(simulation: ^Simulation_State, content: Simulation_Content) -> bool {
	world := &simulation.world
	records := &simulation.records
	crate := pool_get(&world.entities.schematic_crates, entity_at(&world.entities, SAVE_TEST_CRATE))
	found := simulation.unlocks.schematics_found[test_recipe(content.recipes, "slag_concrete")]
	sites_kept := len(records.crate_sites) == 2 && records.crate_sites[0].placed && !records.crate_sites[1].placed
	gold_quartz := world_get_block(world, SAVE_TEST_GOLD_QUARTZ) == test_block(content.blocks, "gold_quartz")
	return crate != nil && !stack_is_empty(crate.slots[0]) && found && sites_kept && gold_quartz && records.statistics.schematics_found == 1
}

SAVE_TEST_CORE_SAMPLE_DRILL :: World_Coordinate{-28, 1, 28}

// Prospecting (work item 0038): an assayed vein, a magnetometer reading, a
// core sample over the deep vein, a seismic shot imaging it, and a core
// sample drill part way through its sampling.
lay_save_test_prospecting :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content) {
	assayed := assay_vein(world, records, content.veins, {-19, 0, 21})
	assert(assayed)
	hematite := test_item(content.items, "hematite")
	append(&records.magnetometer_readings, magnetometer_reading(world.veins[:], content.veins, hematite, 30, {-10, 1, 18}))
	append(&records.core_samples, take_core_sample(world_tick_context(world, records, content, TEST_TICK_RATE), {21, 1, -10}))
	fire_seismic_shot(world, records, {10, 0, -10}, 32)
	drill := pool_get(&world.entities.core_sample_drills, place_test_entity(world, content, "core_sample_drill", SAVE_TEST_CORE_SAMPLE_DRILL))
	drill.work_ticks = 77
}

// The prospecting records, the drill and the explored set came through.
prospecting_loaded :: proc(loaded_world: ^World, loaded, original: ^Game_Records) -> bool {
	drill := pool_get(&loaded_world.entities.core_sample_drills, entity_at(&loaded_world.entities, SAVE_TEST_CORE_SAMPLE_DRILL))
	records := len(loaded.assayed_veins) == 1 && len(loaded.magnetometer_readings) == 1 && loaded.magnetometer_readings[0].found
	records &&= len(loaded.core_samples) == 1 && loaded.core_samples[0].vein_found && len(loaded.seismic_shots) == 1 && len(loaded.seismic_outlines) == 1
	counters := loaded.statistics.veins_assayed == 1 && loaded.statistics.seismic_shots == 1
	return drill != nil && drill.work_ticks == 77 && records && counters && len(loaded.explored) == len(original.explored) && len(loaded.explored) > 0
}

SAVE_TEST_LAUNCH_PAD :: World_Coordinate{22, 1, 0}

// A launch pad (work item 0040) assembling without power, with its parts,
// fuel and cargo, and one shipment in the records.
lay_save_test_launch_pad :: proc(world: ^World, records: ^Game_Records, content: Simulation_Content) {
	handle := place_test_entity(world, content, "launch_pad", SAVE_TEST_LAUNCH_PAD)
	for id in ([?]string{"rocket_structure", "guidance_unit", "cargo_capsule", "steel"}) {
		entity_insert(&world.entities, content, handle, {test_item(content.items, id), 10})
	}
	pad := pool_get(&world.entities.launch_pads, handle)
	pad.buffers[LAUNCH_PAD_FUEL_PORT] = {fluid = test_fluid(content, "rocket_fuel"), level = 300}
	started := start_assembly(pad, content.machines.machines[pad.machine])
	assert(started)
	shipment := make_shipment([]Item_Stack{{test_item(content.items, "iron_plate"), 40}}, 77)
	append(&records.shipments, shipment)
	record_shipment(&records.statistics, shipment)
	// The venture (work item 0041): offers fill the slots on the first
	// tick, a catalogue order is served then, and two mining productivity
	// levels make every drill put out more.
	records.statistics.placed[pad.machine] += 1
	records.venture_credit = 2000
	ordered := order_from_catalogue(records, content.contracts, 0, launch_pad_centre(pad^))
	assert(ordered)
	records.research.levels[test_technology(content.technologies, "mining_productivity")] = 2
}

// A free foundation frame with a second foundation and a chest on it
// (work item 0174).
SAVE_TEST_FRAME_HIT :: World_Position{0, 8000 * POSITION_UNITS_PER_METRE, 0}

lay_save_test_frame :: proc(world: ^World, content: Simulation_Content) {
	foundation := test_machine(content.machines, "wooden_foundation")
	_, frame := place_free_foundation(&world.entities, content.machines, foundation, SAVE_TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
	place_on_frame(&world.entities, content.machines, foundation, frame, {1, 0, 0}, 0)
	place_on_frame(&world.entities, content.machines, test_machine(content.machines, "wooden_chest"), frame, {0, 1, 0}, 0)
}

frame_loaded :: proc(loaded_world, original_world: ^World) -> bool {
	frames := loaded_world.entities.frames.frames[:]
	if !slice.equal(frames, original_world.entities.frames.frames[:]) || len(frames) == 0 {
		return false
	}
	frame := frames[0].id
	chest := entity_at(&loaded_world.entities, {0, 1, 0}, frame)
	return frame_cell_count(&loaded_world.entities.frames, frame) == 3 && chest.kind == .Chest && entity_at(&loaded_world.entities, {1, 0, 0}, frame).kind == .Foundation && loaded_world.entities.frames.last_id == original_world.entities.frames.last_id
}

// Three free poles in a row with a belt run carrying plates from the
// first to the second (work item 0176); the third waited for a pipe run,
// which 0374 removed. Returns the poles' endpoints.
lay_save_test_runs :: proc(world: ^World, content: Simulation_Content) -> (endpoints: [3]Belt_Run_Endpoint) {
	entities := &world.entities
	machines := content.machines
	metre := i64(POSITION_UNITS_PER_METRE)
	hits := [3]World_Position{SAVE_TEST_FRAME_HIT + {0, 0, 3 * metre}, SAVE_TEST_FRAME_HIT + {8 * metre, 0, 3 * metre}, SAVE_TEST_FRAME_HIT + {16 * metre, 0, 3 * metre}}
	chord := [3]i64{metre, 0, 0}
	for hit, index in hits {
		pole, _ := place_free_belt_pole(entities, machines, test_machine(machines, "belt_pole"), hit, chord, 500)
		endpoints[index], _ = belt_pole_endpoint(entities, pole, chord, BELT_RUN_START)
	}
	constraints := data_belt_run_constraints()
	belt_run, belt_refusal := add_belt_run(entities, machines, constraints, find_belt_machine(machines, .Flat), {endpoints[0], endpoints[1]})
	assert(belt_refusal == .None)
	run := pool_get(&entities.belt_runs, belt_run)
	line := &entities.belt_network.lines[run.line]
	start := belt_line_segment_start(line^, run.line_index)
	for index in i32(0) ..< 3 {
		lane_insert(&line.lanes[.Right], test_item(content.items, "iron_plate"), start + BELT_INSERT_OFFSET + index * BELT_ITEM_SPACING)
	}
	return
}

// The belt run's plates stand on it: its line's right lane holds three on
// its segment.
belt_run_items_loaded :: proc(entities: ^Entities) -> bool {
	for run in entities.belt_runs.entries {
		if !run.alive {
			continue
		}
		line := entities.belt_network.lines[run.line]
		on_run := 0
		for entry in line.lanes[.Right] {
			on_run += belt_line_segment_at(line, entry.position) == run.line_index ? 1 : 0
		}
		return on_run == 3
	}
	return false
}

// The poles with their frames and the runs with their control points
// came through, the curves derived again alike, and the belt run's items
// stand on it.
belt_runs_loaded :: proc(loaded_world, original_world: ^World) -> bool {
	loaded, original := &loaded_world.entities, &original_world.entities
	if len(loaded.belt_poles.entries) != 3 || len(loaded.belt_runs.entries) != 1 {
		return false
	}
	for pole, index in loaded.belt_poles.entries {
		if pole.frame != original.belt_poles.entries[index].frame || pole.frame == BLOCK_FRAME {
			return false
		}
	}
	for run, index in loaded.belt_runs.entries {
		before := original.belt_runs.entries[index]
		if run.endpoints != before.endpoints || run.control_points != before.control_points || run.curve != before.curve {
			return false
		}
	}
	return belt_run_items_loaded(loaded)
}

// The pad kept its assembly and cargo, the shipment and its statistics
// came through.
launch_pad_loaded :: proc(loaded_world: ^World, loaded, original: ^Game_Records) -> bool {
	pad := pool_get(&loaded_world.entities.launch_pads, entity_at(&loaded_world.entities, SAVE_TEST_LAUNCH_PAD))
	if pad == nil || len(loaded.shipments) != 1 {
		return false
	}
	assembling := pad.state == .Assembling && pad.stages_taken == 1 && !stack_is_empty(pad.slots[pad.part_count])
	return assembling && loaded.shipments[0] == original.shipments[0] && loaded.statistics.rockets_launched == 1
}

// Open contracts, the credit left after the order and the levels came
// through.
venture_loaded :: proc(loaded, original: ^Game_Records, technologies: Technology_Registry) -> bool {
	contracts := loaded.contracts.open_count == MAXIMUM_OPEN_CONTRACTS && loaded.contracts == original.contracts
	credit := loaded.venture_credit == original.venture_credit && loaded.venture_credit < 2000
	return contracts && credit && loaded.research.levels[test_technology(technologies, "mining_productivity")] == 2
}

// Every entity kind with contents: the power plant (offshore pump, pipes,
// boiler, steam engine, poles, electric drill, lamp, electric inserter), a
// power switch, an assembler line, labs, a furnace line with belts, a
// splitter, a burner drill on a finite vein, a bore drill part way down
// to a deep vein, mining fluid in the electric drill's revival port, a
// schematic crate, a core sample drill with the prospecting records, a
// launch pad assembling with a shipment, and the capsule of the pad.
// One stack resting on the floor, one high up that falls while the test
// runs.
lay_save_test_loose_items :: proc(world: ^World, content: Simulation_Content) {
	spill_stack(world, content.blocks, {2, 1, 28}, {test_item(content.items, "iron_plate"), 12})
	spill_stack(world, content.blocks, {3, 30, 28}, {test_item(content.items, "coal"), 3}, {1, -1})
	// A dropper no ticking player clears, so the field survives to the save.
	world.entities.loose_items.items[0].dropping_player = dropping_player_value(1)
}

build_save_test_site :: proc(simulation: ^Simulation_State, content: Simulation_Content) {
	world := &simulation.world
	records := &simulation.records
	carve_save_test_floor(world, test_block(content.blocks, "stone"))
	build_power_plant(world, content)
	// On the box build_power_plant chains above its third (0368).
	cable_test_machines(world, content, entity_at(&world.entities, {6, 2, 9}), place_test_entity(world, content, "power_switch", {12, 1, 6}))
	lay_gear_line_at(world, content, {-20, 0, 0})
	lay_save_test_research(world, content, {-10, 0, -20})
	lay_save_test_smelting(world, content, {12, 0, 14})
	lay_save_test_splitter(world, content, {12, 0, 26})
	vein := add_test_vein(world, content, "iron", {-19, 21}, 1, IRON_TEST_VEIN, 1000)
	place_test_drill(world, content, {-20, 1, 20}, 0, vein)
	lay_belt_row(world, content, {-18, 1, 20}, 4, 0)
	world.entities.drills.entries[0].buffers[REVIVAL_PORT] = {fluid = test_fluid(content, "mining_fluid"), level = 120}
	deep := add_test_deep_vein(world, content, "gold_quartz", {21, -10}, 3, {20_000, 70_000, 10_000, 0}, 1000)
	bore := test_drill(world, place_test_entity(world, content, "bore_drill", {20, 1, -12}))
	bore.vein, bore.bored_ticks = deep, 1234
	lay_save_test_schematics(simulation, content)
	lay_save_test_prospecting(world, records, content)
	lay_save_test_launch_pad(world, records, content)
	lay_save_test_frame(world, content)
	lay_save_test_runs(world, content)
	lay_save_test_loose_items(world, content)
	technology := test_technology(content.technologies, "automation")
	testing_refusal := queue_research(&records.research, content.technologies, simulation.unlocks, technology)
	assert(testing_refusal == .None)
}

run_save_test_ticks :: proc(simulation: ^Simulation_State, content: Simulation_Content, first, last: int) {
	for tick in first ..< last {
		simulation_tick(simulation, content, {recorded_input(tick)})
	}
}

// The way main loads a world, with the test generator.
load_save_test_simulation :: proc(t: ^testing.T, location: Save_Location, content: Simulation_Content) -> Simulation_State {
	directory, found := existing_save_directory(location)
	testing.expect(t, found)
	file, problem := read_world_file(directory, context.temp_allocator)
	testing.expect_value(t, problem, "")
	loaded: Simulation_State
	loaded, problem = make_simulation_from_save(test_game_config(), player_start_on({}), content, SAVE_TEST_LANDING_PAD, directory, file)
	testing.expect_value(t, problem, "")
	return loaded
}

modified_chunk_count :: proc(world: ^World) -> int {
	count := 0
	for _, chunk in world.chunks {
		count += chunk.modified ? 1 : 0
	}
	return count
}

// Pipes hold nothing since 0356: the fluid machines' ports hold it.
fluid_ports_holding_fluid :: proc(entities: ^Entities) -> int {
	count := 0
	for machine in entities.fluid_machines.entries {
		for buffer in machine.buffers {
			count += machine.alive && buffer.level > 0 ? 1 : 0
		}
	}
	return count
}

// A registered deep vein, a bore drill bored part way and a revival port
// holding fluid (work item 0035).
deep_veins_and_bore_drill_loaded :: proc(world: ^World) -> bool {
	bored, holding := false, false
	for drill in world.entities.drills.entries {
		vein := registered_vein(world, drill.vein)
		bored ||= drill.alive && drill.bored_ticks > 0 && vein != nil && vein_is_deep(vein^)
		holding ||= drill.alive && drill.buffers[REVIVAL_PORT].level > 0
	}
	return bored && holding
}

labs_in_progress :: proc(entities: ^Entities) -> int {
	count := 0
	for lab in entities.labs.entries {
		count += lab.alive && lab.progress_ticks > 0 ? 1 : 0
	}
	return count
}

// Vessel parts stand in a field world only (0361), whose round trip
// covers them (test_a_vessel_round_trips_a_save_and_an_older_save_loads_without_vessels).
expect_every_pool_used :: proc(t: ^testing.T, entities: ^Entities) {
	for kind in Entity_Kind {
		if kind != .None && kind != .Vessel_Part {
			testing.expectf(t, entity_pool_length(entities, kind) > 0, "no %v in the test site", kind)
		}
	}
}

save_file_size :: proc(path: string) -> i64 {
	info, error := os.stat(path, context.temp_allocator)
	return error == nil ? info.size : -1
}

log_save_sizes :: proc(location: Save_Location) {
	directory := platform.join_path(location.saves_directory, location.directory_name)
	regions, _ := os.read_all_directory_by_path(platform.join_path(directory, REGIONS_DIRECTORY_NAME), context.temp_allocator)
	region_bytes: i64
	for region in regions {
		region_bytes += region.size
	}
	log.infof(
		"save sizes: world.sjson %d bytes, entities.bin %d bytes, %d region files with %d bytes",
		save_file_size(platform.join_path(directory, WORLD_FILE_NAME)),
		save_file_size(platform.join_path(directory, ENTITIES_FILE_NAME)),
		len(regions),
		region_bytes,
	)
}

// The strongest test: build a base, run it, save, load into a fresh
// simulation, and run both for 600 ticks with the same input. The state
// hashes must match right after loading and after every 100 ticks.
@(test) // slow
test_save_load_run_matches_the_original :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	load_save_test_chunks(&original.world, &original.records, &generator)
	build_save_test_site(&original, content)
	expect_every_pool_used(t, &original.world.entities)
	run_save_test_ticks(&original, content, 0, 300)

	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	location := save_test_location(directory)
	testing.expect_value(t, save_world(&original, content, location, 1_700_000_000), "")
	log_save_sizes(location)

	loaded := load_save_test_simulation(t, location, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, loaded.tick, original.tick)
	testing.expect_value(t, len(loaded.world.saved_chunks), modified_chunk_count(&original.world))
	load_save_test_chunks(&loaded.world, &loaded.records, &generator)
	testing.expect_value(t, len(loaded.world.saved_chunks), 0)
	loaded_hash := simulation_state_hash(&loaded)
	testing.expect_value(t, loaded_hash, simulation_state_hash(&original))
	// The hash sees a one item difference.
	loaded.players[0].held.stack.count += 1
	testing.expect(t, simulation_state_hash(&loaded) != loaded_hash)
	loaded.players[0].held.stack.count -= 1

	// What the save carried is really there.
	testing.expect(t, len(belt_cell_items(&loaded.world.entities)) > 0)
	testing.expect(t, loaded.records.research.queued && labs_in_progress(&loaded.world.entities) > 0)
	testing.expect(t, len(loaded.quests.messages) > 0)
	testing.expect(t, fluid_ports_holding_fluid(&loaded.world.entities) > 0)
	testing.expect(t, deep_veins_and_bore_drill_loaded(&loaded.world))
	testing.expect(t, schematics_loaded(&loaded, content))
	testing.expect(t, prospecting_loaded(&loaded.world, &loaded.records, &original.records))
	testing.expect(t, launch_pad_loaded(&loaded.world, &loaded.records, &original.records))
	testing.expect(t, frame_loaded(&loaded.world, &original.world))
	testing.expect(t, belt_runs_loaded(&loaded.world, &original.world))
	testing.expect(t, venture_loaded(&loaded.records, &original.records, content.technologies))
	testing.expect(t, len(loaded.world.entities.loose_items.items) > 0)
	testing.expect(t, slice.equal(loaded.world.entities.loose_items.items[:], original.world.entities.loose_items.items[:]))
	testing.expect_value(t, fluid_netlist_count(&loaded.world.entities.fluid_networks), fluid_netlist_count(&original.world.entities.fluid_networks))
	testing.expect_value(t, len(loaded.world.entities.electric_networks.networks), len(original.world.entities.electric_networks.networks))
	testing.expect_value(t, len(loaded.world.entities.belt_network.lines), len(original.world.entities.belt_network.lines))
	testing.expect_value(t, len(loaded.world.entities.frames.occupants), len(original.world.entities.frames.occupants))
	testing.expect_value(t, len(loaded.world.entity_lights), len(original.world.entity_lights))

	before_running := loaded_hash
	for block in 0 ..< 6 {
		first := 300 + block * 100
		run_save_test_ticks(&original, content, first, first + 100)
		run_save_test_ticks(&loaded, content, first, first + 100)
		testing.expectf(t, simulation_state_hash(&loaded) == simulation_state_hash(&original), "state differs after tick %d", first + 100)
	}
	testing.expect(t, simulation_state_hash(&loaded) != before_running, "the simulation moved on")
	// The rate rings (work item 0028) came through and closed a ten
	// second span after loading, the same in both.
	statistics, original_statistics := loaded.records.statistics, original.records.statistics
	testing.expect(t, slice.any_of_proc(statistics.produced_rates.per_ten_seconds, proc(count: u32) -> bool {return count > 0}))
	testing.expect(t, slice.equal(statistics.produced_rates.per_ten_seconds, original_statistics.produced_rates.per_ten_seconds))
	testing.expect(t, slice.equal(statistics.consumed_rates.per_second, original_statistics.consumed_rates.per_second))
	testing.expect(t, slice.any_of_proc(statistics.consumed, proc(count: u64) -> bool {return count > 0}))
}

// A torch in a cave dug into an underground chunk lights the cave the
// same after the chunk is saved and loaded again, although light is not
// saved.
@(test)
test_saved_torch_lit_cave_is_lit_after_load :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	torch := test_block(registry, "torch")
	coordinate := Chunk_Coordinate{0, -2, 0}
	origin := chunk_origin(coordinate)
	centre := origin + {16, 16, 16}
	dug: World
	dug_records: Game_Records
	defer destroy_world(&dug)
	defer destroy_game_records(&dug_records)
	load_chunk_now(&dug, &dug_records, &generator, coordinate)
	for y in i32(-1) ..= 1 {
		for z in i32(-3) ..= 3 {
			for x in i32(-3) ..= 3 {
				world_set_block(&dug, centre + {x, y, z}, AIR_BLOCK)
			}
		}
	}
	world_set_block(&dug, centre, torch)
	settle_world(t, &dug, registry, 0)
	testing.expect_value(t, block_light_at(&dug, centre), 15)
	testing.expect_value(t, block_light_at(&dug, centre + {3, 0, 0}), 12)

	loaded: World
	loaded_records: Game_Records
	defer destroy_world(&loaded)
	defer destroy_game_records(&loaded_records)
	loaded.saved_chunks[coordinate] = serialize_chunk(dug.chunks[coordinate])
	load_chunk_now(&loaded, &loaded_records, &generator, coordinate)
	chunk := loaded.chunks[coordinate]
	testing.expect(t, chunk.modified)
	testing.expect_value(t, world_get_block(&loaded, centre), torch)
	settle_world(t, &loaded, registry, 0)
	testing.expect_value(t, block_light_at(&loaded, centre), 15)
	testing.expect_value(t, block_light_at(&loaded, centre + {3, 0, 0}), 12)
	testing.expect(t, slice.equal(chunk.light[:], dug.chunks[coordinate].light[:]), "the relit chunk has the light of the dug one")
}

// An edited chunk that streams out keeps its edits and comes back with
// them; its lamp light returns with it.
@(test)
test_modified_chunk_survives_unloading :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	registry := make_test_registry()
	coordinate := Chunk_Coordinate{1, 3, 1}
	cell := chunk_origin(coordinate) + {4, 4, 4}
	world: World
	records: Game_Records
	defer destroy_world(&world)
	defer destroy_game_records(&records)
	load_chunk_now(&world, &records, &generator, coordinate)
	testing.expect(t, !world.chunks[coordinate].modified)
	world_set_block(&world, cell, test_block(registry, "stone"))
	testing.expect(t, world.chunks[coordinate].modified)
	world.entity_lights[cell + {0, 1, 0}] = 9
	store_modified_chunk(&world, world.chunks[coordinate])
	free(world.chunks[coordinate])
	delete_key(&world.chunks, coordinate)
	load_chunk_now(&world, &records, &generator, coordinate)
	testing.expect_value(t, world_get_block(&world, cell), test_block(registry, "stone"))
	testing.expect_value(t, block_light_at(&world, cell + {0, 1, 0}), 9)
}

@(test)
test_world_names_are_sanitised :: proc(t: ^testing.T) {
	cases := [?][2]string {
		{"My World!", "My World_"},
		{"../etc/passwd", "___etc_passwd"},
		{"  spaced  ", "spaced"},
		{"", DEFAULT_WORLD_NAME},
		{"   ", DEFAULT_WORLD_NAME},
		{"under_score-dash 7", "under_score-dash 7"},
		{"Welt ü", "Welt _"},
		{".", "_"},
	}
	for entry in cases {
		testing.expect_value(t, sanitize_world_name(entry[0], context.temp_allocator), entry[1])
	}
	long := strings.repeat("a", 200, context.temp_allocator)
	testing.expect_value(t, len(sanitize_world_name(long, context.temp_allocator)), MAXIMUM_WORLD_DIRECTORY_NAME_LENGTH)
}

@(test)
test_saves_directory_follows_xdg :: proc(t: ^testing.T) {
	directory, ok := saves_directory_from_environment("/custom/saves", "/data", "/home/player", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, directory, "/custom/saves")
	directory, ok = saves_directory_from_environment("", "/data", "/home/player", context.temp_allocator)
	testing.expect_value(t, directory, "/data/mine-oh-belowed/saves")
	directory, ok = saves_directory_from_environment("", "relative", "/home/player", context.temp_allocator)
	testing.expect_value(t, directory, "/home/player/.local/share/mine-oh-belowed/saves")
	_, ok = saves_directory_from_environment("", "", "", context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_region_grouping :: proc(t: ^testing.T) {
	testing.expect_value(t, chunk_region({0, 5, 0}), Region_Coordinate{0, 0})
	testing.expect_value(t, chunk_region({7, -3, 7}), Region_Coordinate{0, 0})
	testing.expect_value(t, chunk_region({8, 0, -1}), Region_Coordinate{1, -1})
	testing.expect_value(t, chunk_region({-8, 0, -9}), Region_Coordinate{-1, -2})

	chunk := new(Chunk, context.temp_allocator)
	chunk_set_block(chunk, {1, 2, 3}, Block_Id(4))
	bytes := serialize_chunk(chunk, context.temp_allocator)
	chunks := make(map[Chunk_Coordinate][]byte, context.temp_allocator)
	for coordinate in ([?]Chunk_Coordinate{{0, 0, 0}, {7, 2, 7}, {0, -1, 0}, {-1, 0, 0}, {8, 0, 0}}) {
		chunks[coordinate] = bytes
	}
	regions := group_chunks_by_region(chunks)
	testing.expect_value(t, len(regions), 3)
	origin := regions[{0, 0}]
	testing.expect_value(t, len(origin), 3)
	testing.expect_value(t, origin[0].coordinate, Chunk_Coordinate{0, -1, 0})
	testing.expect_value(t, len(regions[{-1, 0}]), 1)
	testing.expect_value(t, len(regions[{1, 0}]), 1)

	header := make_save_header()
	encoded := encode_region(header, {0, 0}, origin[:], context.temp_allocator)
	decoded := make(map[Chunk_Coordinate][]byte, context.temp_allocator)
	read_header, ok := decode_region(encoded, {0, 0}, &decoded, nil)
	testing.expect(t, ok)
	testing.expect_value(t, read_header, header)
	testing.expect_value(t, len(decoded), 3)
	testing.expect(t, slice.equal(decoded[{7, 2, 7}], bytes))
	for _, copied in decoded {
		delete(copied)
	}

	wrong := make(map[Chunk_Coordinate][]byte, context.temp_allocator)
	_, ok = decode_region(encoded, {1, 0}, &wrong, nil)
	testing.expect(t, !ok, "region coordinate mismatch")
	_, ok = decode_region(encoded[:len(encoded) - 1], {0, 0}, &wrong, nil)
	testing.expect(t, !ok, "truncated")
	for _, copied in wrong {
		delete(copied)
	}

	testing.expect_value(t, region_file_name({-1, -2}), "-1_-2.bin")
	region, named := parse_region_file_name("-1_-2.bin")
	testing.expect(t, named)
	testing.expect_value(t, region, Region_Coordinate{-1, -2})
	for bad in ([?]string{"a_b.bin", "1_2.txt", "12.bin", "1_99999999999.bin"}) {
		_, named = parse_region_file_name(bad)
		testing.expectf(t, !named, "%q accepted", bad)
	}
}

Save_Test_Value :: struct {
	count:    u16,
	signed:   i32,
	flag:     bool,
	lane:     Belt_Lane,
	position: [3]f32,
	stacks:   [2]Item_Stack,
	per_lane: [Belt_Lane]i64,
	hints:    Quest_Hint_Set,
	events:   Player_Events,
	slots:    []Item_Stack,
}

Save_Test_Flag :: struct {
	flag: bool,
}

@(test)
test_value_codec_round_trip_and_refusals :: proc(t: ^testing.T) {
	slots := [3]Item_Stack{{1, 2}, {3, 4}, {5, 6}}
	value := Save_Test_Value {
		count    = 513,
		signed   = -7,
		flag     = true,
		lane     = .Right,
		position = {1.5, -2, 1e9},
		stacks   = {{7, 8}, {9, 10}},
		per_lane = {.Left = -1, .Right = max(i64)},
		hints    = {0, 3},
		events   = {.Inventory_Full, .Seismic_Shot_Fired},
		slots    = slots[:],
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&bytes, &value)

	read_slots: [3]Item_Stack
	restored := Save_Test_Value {
		slots = read_slots[:],
	}
	reader := Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, read_value_of(&reader, &restored))
	testing.expect_value(t, bytes_left(reader), 0)
	testing.expect_value(t, restored.count, value.count)
	testing.expect_value(t, restored.signed, value.signed)
	testing.expect_value(t, restored.lane, value.lane)
	testing.expect_value(t, restored.position, value.position)
	testing.expect_value(t, restored.stacks, value.stacks)
	testing.expect_value(t, restored.per_lane, value.per_lane)
	testing.expect_value(t, restored.hints, value.hints)
	testing.expect_value(t, restored.events, value.events)
	testing.expect(t, slice.equal(read_slots[:], slots[:]))

	flag := Save_Test_Flag {
		flag = true,
	}
	flag_bytes := make([dynamic]byte, context.temp_allocator)
	write_value_of(&flag_bytes, &flag)
	flag_bytes[len(flag_bytes) - 1] = 2
	reader = Byte_Reader {
		data = flag_bytes[:],
	}
	testing.expect(t, !read_value_of(&reader, &flag), "boolean out of range")
	short_slots: [2]Item_Stack
	restored.slots = short_slots[:]
	reader = Byte_Reader {
		data = bytes[:],
	}
	testing.expect(t, !read_value_of(&reader, &restored), "slice length mismatch")
	restored.slots = read_slots[:]
	reader = Byte_Reader {
		data = bytes[:len(bytes) - 1],
	}
	testing.expect(t, !read_value_of(&reader, &restored), "truncated")

	list := make([dynamic]u32, context.temp_allocator)
	huge := make([dynamic]byte, context.temp_allocator)
	append_u32(&huge, 1_000_000)
	reader = Byte_Reader {
		data = huge[:],
	}
	testing.expect(t, !read_list(&reader, &list), "a count beyond the data is refused before allocating")
}

@(test)
test_newer_and_older_formats_are_refused :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION + 1,
		name = "future",
		settings = {day_length_seconds = 1200},
	}
	_, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, strings.contains(problem, "newer"), problem)
	file.format_version = SAVE_FORMAT_VERSION - 1
	_, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect(t, strings.contains(problem, "older"), problem)
	file.format_version = SAVE_FORMAT_VERSION
	file.seed = max(u64)
	parsed: World_File
	parsed, problem = parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.seed, max(u64))
	testing.expect_value(t, parsed.name, "future")

	expected := make_save_header()
	newer := expected
	newer.version += 1
	testing.expect(t, header_problem(newer, expected, "entities.bin") != "")
	testing.expect(t, strings.contains(header_problem(Save_Header{version = 1}, expected, "entities.bin"), "format version 1"))
	testing.expect_value(t, header_problem(expected, expected, "entities.bin"), "")
}

// Work item 0358: world.sjson keeps the day clock whole, so an offset of
// days the wait moved round trips; a file written before it holds the
// clock within the day and loads the offset the older build loaded, past
// the first day and in it.
@(test)
test_the_day_offset_round_trips_whole_through_world_sjson :: proc(t: ^testing.T) {
	simulation, _ := make_developer_test_simulation()
	defer destroy_simulation(&simulation)
	day_length := simulation.day_length_ticks
	testing.expect(t, day_length > 0, "the test's day has a length")
	simulation.tick = 100_000
	simulation.day_offset_ticks = 2 * day_length + day_length / 3
	file := make_world_file(&simulation, "waited", 0)
	parsed, problem := parse_world_file(encode_world_file(file, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, saved_day_offset(parsed, day_length), simulation.day_offset_ticks)
	older := World_File{tick = 5 * day_length + 7, day_time_ticks = day_length / 2}
	testing.expect_value(t, saved_day_offset(older, day_length), day_offset_for(older.tick, older.day_time_ticks, day_length))
	testing.expect_value(t, (older.tick + saved_day_offset(older, day_length)) % day_length, day_length / 2)
	first_day := World_File{tick = 7, day_time_ticks = day_length / 2}
	testing.expect_value(t, saved_day_offset(first_day, day_length), day_offset_for(first_day.tick, first_day.day_time_ticks, day_length))
}

// 0057: world.sjson carries the generator version; a file written before
// it existed reads as version 1, and the load list marks a save of an
// older generator but still loads it.
@(test)
test_generator_version_round_trips_and_marks_older_terrain :: proc(t: ^testing.T) {
	file := World_File {
		format_version = SAVE_FORMAT_VERSION,
		generator_version = GENERATOR_VERSION,
		name = "terrain",
		settings = {day_length_seconds = 1200},
	}
	encoded := string(encode_world_file(file, context.temp_allocator))
	parsed, problem := parse_world_file(transmute([]byte)encoded, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.generator_version, GENERATOR_VERSION)
	without_version := strings.join(remove_lines_containing(encoded, "generator_version"), "\n", context.temp_allocator)
	testing.expect(t, len(without_version) < len(encoded))
	parsed, problem = parse_world_file(transmute([]byte)without_version, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, parsed.generator_version, 1)

	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	expected := Save_Header {
		version = SAVE_FORMAT_VERSION,
	}
	write_test_world_file(directory, "current", "Current", 2000)
	write_test_entities_header(directory, "current", expected)
	os.make_directory_all(platform.join_path(directory, "older"))
	older_path := platform.join_path(directory, "older", WORLD_FILE_NAME)
	testing.expect(t, os.write_entire_file(older_path, transmute([]byte)without_version) == nil)
	write_test_entities_header(directory, "older", expected)
	saves: [dynamic]Save_Summary
	defer delete(saves)
	defer destroy_save_summaries(&saves)
	list_saves(&saves, directory, expected)
	testing.expect_value(t, len(saves), 2)
	if len(saves) != 2 {
		return
	}
	testing.expect_value(t, saves[0].directory_name, "current")
	testing.expect(t, saves[0].loadable && !saves[0].terrain_changed)
	testing.expect(t, saves[1].loadable && saves[1].terrain_changed)
	testing.expect_value(t, save_row_cells(saves[0], {}, 60).marker, "")
	testing.expect_value(t, save_row_cells(saves[1], {}, 60).marker, text("save_terrain_changed"))
}

remove_lines_containing :: proc(contents, needle: string) -> []string {
	kept := make([dynamic]string, context.temp_allocator)
	for line in strings.split_lines(contents, context.temp_allocator) {
		if !strings.contains(line, needle) {
			append(&kept, line)
		}
	}
	return kept[:]
}

// A save written before the loose item table existed ends after the
// players; it loads with no loose items, and one with the table loads
// them back.
@(test)
test_a_save_without_the_loose_item_table_loads :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	header := make_save_header()
	without_table := encode_entities(&original, content, header)
	// The empty table (a count and the schema) ends the file.
	table := make([dynamic]byte, context.temp_allocator)
	write_later_tables(&table, &original.world, &original.records, false)
	without_table = without_table[:len(without_table) - len(table)]
	spill_stack(&original.world, content.blocks, {2, 1, 2}, {test_item(content.items, "coal"), 5}, {-1, 1})
	with_table := encode_entities(&original, content, header)

	remap: Content_Remap
	older := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&older)
	testing.expect_value(t, decode_entities(&older, content, without_table, "entities.bin", header, &remap), "")
	testing.expect_value(t, len(older.world.entities.loose_items.items), 0)
	testing.expect_value(t, older.world.entities.loose_items.despawn_ticks, original.world.entities.loose_items.despawn_ticks)

	newer := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&newer)
	testing.expect_value(t, decode_entities(&newer, content, with_table, "entities.bin", header, &remap), "")
	testing.expect(t, slice.equal(newer.world.entities.loose_items.items[:], original.world.entities.loose_items.items[:]))
	// Bytes after the tables this build knows are still malformed.
	extra := make([dynamic]byte, context.temp_allocator)
	append(&extra, ..with_table)
	append(&extra, 0)
	testing.expect(t, decode_entities(&newer, content, extra[:], "entities.bin", header, &remap) != "")
}

// Saving writes into a staging directory and swaps it in; nothing is left
// beside the save, and after a crash between the renames loading finds
// the previous save.
@(test)
test_save_swaps_a_staged_directory_into_place :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	simulation := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&simulation)
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	location := save_test_location(directory)
	testing.expect_value(t, save_world(&simulation, content, location, 1), "")
	simulation.tick = 42
	testing.expect_value(t, save_world(&simulation, content, location, 2), "")

	entries, error := os.read_all_directory_by_path(directory, context.temp_allocator)
	testing.expect(t, error == nil)
	testing.expect_value(t, len(entries), 1)
	testing.expect_value(t, entries[0].name, location.directory_name)
	saved, found := existing_save_directory(location)
	testing.expect(t, found)
	file, problem := read_world_file(saved, context.temp_allocator)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, file.tick, 42)
	testing.expect_value(t, file.last_played_unix_seconds, 2)
	testing.expect_value(t, file.name, "Round trip!")

	target := platform.join_path(directory, location.directory_name)
	previous := strings.concatenate({target, PREVIOUS_DIRECTORY_SUFFIX}, context.temp_allocator)
	testing.expect(t, os.rename(target, previous) == nil)
	saved, found = existing_save_directory(location)
	testing.expect(t, found)
	testing.expect_value(t, saved, previous)
	testing.expect(t, world_directory_taken(directory, location.directory_name))
	testing.expect_value(t, unused_world_directory_name(directory, location.directory_name, context.temp_allocator), "Round trip_ 2")
	testing.expect_value(t, save_world(&simulation, content, location, 3), "")
	testing.expect(t, !os.exists(previous))
	testing.expect(t, os.exists(platform.join_path(target, WORLD_FILE_NAME)))
}

// The leaf decay queue is the second later table: it round trips, and a
// save that ends after the loose items loads with an empty queue.
@(test)
test_leaf_decay_queue_round_trips :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	schedule_leaf_decay(&original.records.leaf_decay, {4, 12, -3}, 130)
	schedule_leaf_decay(&original.records.leaf_decay, {5, 12, -3}, 95)
	header := make_save_header()
	with_table := encode_entities(&original, content, header)
	table := make([dynamic]byte, context.temp_allocator)
	write_list(&table, original.records.leaf_decay.updates[:])
	without_table := with_table[:len(with_table) - len(table)]

	remap: Content_Remap
	newer := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&newer)
	testing.expect_value(t, decode_entities(&newer, content, with_table, "entities.bin", header, &remap), "")
	testing.expect(t, slice.equal(newer.records.leaf_decay.updates[:], original.records.leaf_decay.updates[:]))
	testing.expect(t, World_Coordinate{5, 12, -3} in newer.records.leaf_decay.scheduled)

	older := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&older)
	schedule_leaf_decay(&older.records.leaf_decay, {1, 1, 1}, 1)
	testing.expect_value(t, decode_entities(&older, content, without_table, "entities.bin", header, &remap), "")
	testing.expect_value(t, len(older.records.leaf_decay.updates), 0)
	testing.expect_value(t, len(older.records.leaf_decay.scheduled), 0)
}

// A world that never had a frame writes no frame tables, so its file is
// the layout of a save from before frames (work item 0174); it loads with
// every entity on frame 0 and the occupant index rebuilt from the pools.
@(test)
test_a_save_without_frame_tables_loads_on_frame_0 :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	chest := place_test_entity(&original.world, content, "wooden_chest", {3, 1, 3})
	tables := make([dynamic]byte, context.temp_allocator)
	write_frame_tables(&tables, &original.world.entities)
	testing.expect_value(t, len(tables), 0)
	header := make_save_header()
	bytes := encode_entities(&original, content, header)

	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, decode_entities(&loaded, content, bytes, "entities.bin", header, &remap), "")
	testing.expect_value(t, len(loaded.world.entities.frames.frames), 0)
	testing.expect_value(t, entity_at(&loaded.world.entities, {3, 1, 3}), chest)
	testing.expect_value(t, entity_common(&loaded.world.entities, chest).frame, BLOCK_FRAME)
	testing.expect_value(t, len(loaded.world.entities.frames.occupants), len(original.world.entities.frames.occupants))
}

// Work item 0356: a block world saved while its pipes held litres, as a
// save from before 0356 does, loads with the pipes empty of litres and
// fluid, so they show no band before the first tick, and the ports'
// litres kept; the line names the litres dropped, not those a removed
// pipe's dead entry still holds, and the world saves and loads again to
// its hash.
@(test)
test_an_old_save_drops_its_pipe_litres :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	pipes := lay_pipes(&original.world, content, {-1, 1, 1}, {-2, 1, 1})
	tank := place_test_tank(&original.world, content, {-5, 1, 0}, "water", 1000)
	for pipe in pipes {
		test_pipe(&original.world, pipe).buffer = {fluid = test_fluid(content, "water"), level = 60}
	}
	removed := lay_pipes(&original.world, content, {-1, 1, 6})[0]
	test_pipe(&original.world, removed).buffer = {fluid = test_fluid(content, "water"), level = 50}
	testing.expect(t, remove_entity(&original.world.entities, content.machines, removed))
	bytes := encode_entities(&original, content, header)

	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, decode_entities(&loaded, content, bytes, "entities.bin", header, &remap), "")
	for pipe in pipes {
		testing.expect_value(t, test_pipe(&loaded.world, pipe).buffer, EMPTY_FLUID_BUFFER)
		testing.expect(t, !pipe_shows_band(test_pipe(&loaded.world, pipe)^))
	}
	testing.expect_value(t, test_fluid_machine(&loaded.world, tank).buffers[0], test_fluid_machine(&original.world, tank).buffers[0])
	testing.expect_value(t, drop_pipe_litres(&original.world.entities), 120)
	testing.expect_value(t, pipe_litres_line(120), "save: dropped 120 litres held in pipes, which hold no fluid since 0356")

	hash := simulation_state_hash(&loaded)
	again_remap: Content_Remap
	again := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&again)
	testing.expect_value(t, decode_entities(&again, content, encode_entities(&loaded, content, header), "entities.bin", header, &again_remap), "")
	testing.expect_value(t, simulation_state_hash(&again), hash)
}

// The save tests' world writing and reading a field world's tables
// (0368): a spacing and a chunk radius, no field generated.
enable_test_field_tables :: proc(simulation: ^Simulation_State) {
	simulation.field.enabled = true
	simulation.field.spacing_millimetres = 1000
	simulation.field.chunk_set.radius = 1
}

// The shipped content as a build before 0368 had it: the small pole, the
// big pole and the substation as junction boxes of two ports, with their
// items and recipes, and no deleted_ids.
content_with_the_poles :: proc(content: Simulation_Content) -> Simulation_Content {
	old := content
	items := make([dynamic]Item, context.temp_allocator)
	machines := make([dynamic]Machine, context.temp_allocator)
	recipes := make([dynamic]Recipe, context.temp_allocator)
	append(&items, ..content.items.items)
	append(&machines, ..content.machines.machines)
	append(&recipes, ..content.recipes.recipes)
	box_item := content.items.items[test_item(content.items, "junction_box")]
	box := content.machines.machines[test_machine(content.machines, "junction_box")]
	box_recipe := content.recipes.recipes[test_recipe(content.recipes, "junction_box")]
	poles := [?]struct {
		id:        string,
		footprint: [3]i32,
	}{{"small_pole", {1, 3, 1}}, {"big_pole", {1, 6, 1}}, {"substation", {2, 3, 2}}}
	for pole in poles {
		item, machine, recipe := box_item, box, box_recipe
		item.id, recipe.id = pole.id, pole.id
		append(&items, item)
		machine.id, machine.item, machine.footprint, machine.port_count = pole.id, Item_Id(len(items) - 1), pole.footprint, 2
		append(&machines, machine)
		append(&recipes, recipe)
	}
	old.items.items, old.machines.machines, old.recipes.recipes = items[:], machines[:], recipes[:]
	old.machines.deleted_ids = nil
	return old
}

// Work item 0368, decision 7: a block world and a field world saved with
// the poles load with them deleted: one line names the three, the switch
// and the assembler stay with no cable, a pole's frame of its own is
// released, the world saves and loads again to its hash, and a box placed
// afterwards takes a freed slot. A cable from a pole to the switch goes
// with the pole. Beside a gone machine that is not deleted, the load
// refuses as before.
@(test)
test_old_saves_lose_their_poles :: proc(t: ^testing.T) {
	content := make_save_test_content()
	old := content_with_the_poles(content)
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	ids := [5]string{"small_pole", "big_pole", "substation", "power_switch", "assembler_1"}
	cells := [5]World_Coordinate{{0, 1, 0}, {3, 1, 0}, {6, 1, 0}, {10, 1, 0}, {13, 1, 0}}
	for field_world in ([?]bool{false, true}) {
		original := make_save_test_simulation(&generator, old)
		defer destroy_simulation(&original)
		entities := &original.world.entities
		frame, bare := BLOCK_FRAME, BLOCK_FRAME
		if field_world {
			enable_test_field_tables(&original)
			foundation := find_foundation_machine(old.machines)
			_, frame = place_free_foundation(entities, old.machines, foundation, SAVE_TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
			for x in i32(0) ..< 16 {
				for z in i32(0) ..< 3 {
					place_on_frame(entities, old.machines, foundation, frame, {x, 0, z}, 0)
				}
			}
			origin, axes := free_frame_at(SAVE_TEST_FRAME_HIT + {20 * POSITION_UNITS_PER_METRE, 0, 0}, {UNIT_VECTOR_ONE, 0, 0}, 500)
			bare = add_frame(&entities.frames, origin, axes, 500)
		}
		placed: [5]Entity_Handle
		for id, index in ids {
			on, cell := frame, cells[index]
			if field_world && id == "big_pole" {
				on, cell = bare, {}
			}
			placed[index] = add_entity(entities, old.machines, test_machine(old.machines, id), cell, 0, on)
		}
		// A worn pole: the field's wear table skips it with the pole.
		entity_common(entities, placed[1]).wear_ticks = 600
		// A cable from the small pole to the switch: dropped with its pole.
		lay_test_cable(&original.world, old, "light_cable", {placed[0], 1}, {placed[3], 0})
		bytes := encode_entities(&original, old, header)

		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&loaded)
		testing.expect_value(t, decode_entities(&loaded, content, bytes, "entities.bin", header, &remap), "")
		testing.expect_value(t, deleted_machines_line(remap), "save: removed 3 placed machines of deleted kinds (small_pole, big_pole, substation)")
		loaded_entities := &loaded.world.entities
		for index in 0 ..< 3 {
			testing.expectf(t, entity_common(loaded_entities, placed[index]) == nil, "the %s is gone", ids[index])
		}
		for index in 3 ..< 5 {
			common := entity_common(loaded_entities, entity_at(loaded_entities, cells[index], frame))
			testing.expectf(t, common != nil && content.machines.machines[common.machine].id == ids[index], "the %s stays", ids[index])
		}
		testing.expect_value(t, len(loaded_entities.cables.cables), 0)
		testing.expect_value(t, len(loaded_entities.electric_networks.networks), 0)
		if field_world {
			_, kept := find_frame(&loaded_entities.frames, frame)
			_, released := find_frame(&loaded_entities.frames, bare)
			testing.expect(t, kept && !released, "the bare ground pole's frame is released, the foundations' kept")
		}

		hash := simulation_state_hash(&loaded)
		again_remap: Content_Remap
		again := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&again)
		testing.expect_value(t, decode_entities(&again, content, encode_entities(&loaded, content, header), "entities.bin", header, &again_remap), "")
		testing.expect_value(t, deleted_machines_line(again_remap), "")
		testing.expect_value(t, simulation_state_hash(&again), hash)

		box := add_entity(loaded_entities, content.machines, test_machine(content.machines, "junction_box"), {20, 1, 1}, 0, frame)
		freed := false
		for handle in remap.deleted_handles {
			freed ||= handle.kind == box.kind && handle.index == box.index
		}
		testing.expect(t, freed, "the box takes a deleted pole's slot")
	}

	retired := old
	machines := make([dynamic]Machine, context.temp_allocator)
	append(&machines, ..old.machines.machines)
	chest := old.machines.machines[test_machine(old.machines, "wooden_chest")]
	chest.id = "retired_chest"
	append(&machines, chest)
	retired.machines.machines = machines[:]
	original := make_save_test_simulation(&generator, retired)
	defer destroy_simulation(&original)
	add_entity(&original.world.entities, retired.machines, test_machine(retired.machines, "small_pole"), {0, 1, 0}, 0)
	add_entity(&original.world.entities, retired.machines, test_machine(retired.machines, "retired_chest"), {3, 1, 0}, 0)
	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	problem := decode_entities(&loaded, content, encode_entities(&original, retired, header), "entities.bin", header, &remap)
	testing.expectf(t, strings.contains(problem, "placed retired_chest machines"), "%q", problem)
}

// Work item 0368: the hand run factory and a cable on a frame round trip
// in a block world and a field world to the hash and the cable table; a
// block world without a cable writes no cable table; a cable whose item
// this build lacks is dropped; one longer than any span is cut to the
// longest; a dead end and two cables on one port each refuse the file.
@(test)
test_cables_save_and_load :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	box := test_machine(content.machines, "junction_box")
	for field_world in ([?]bool{false, true}) {
		original := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&original)
		if field_world {
			enable_test_field_tables(&original)
		}
		entities := &original.world.entities
		lay_hand_run_factory(&original.world, content, true)
		origin, axes := free_frame_at(SAVE_TEST_FRAME_HIT, {UNIT_VECTOR_ONE, 0, 0}, 500)
		frame := add_frame(&entities.frames, origin, axes, 500)
		near := add_entity(entities, content.machines, box, {0, 0, 0}, 0, frame)
		far := add_entity(entities, content.machines, box, {4, 0, 0}, 0, frame)
		lay_test_cable(&original.world, content, "light_cable", {near, 1}, {far, 0})
		tick_test_entities(&original.world, &original.records, content, 3)

		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&loaded)
		testing.expect_value(t, decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap), "")
		testing.expect_value(t, loaded.field.enabled, field_world)
		original_table, loaded_table := &original.world.entities.cables, &loaded.world.entities.cables
		testing.expect(t, len(original_table.cables) > 10 && slice.equal(loaded_table.cables[:], original_table.cables[:]), "the cables come back")
		testing.expect(t, slice.equal(loaded_table.capacity[:], original_table.capacity[:]) && slice.equal(loaded_table.kinds[:], original_table.kinds[:]), "their capacities and kinds come back")
		testing.expect_value(t, port_end_cable(loaded_table, {far, 0}), port_end_cable(original_table, {far, 0}))
		testing.expect_value(t, len(loaded.world.entities.electric_networks.networks), len(entities.electric_networks.networks))
		testing.expect_value(t, simulation_state_hash(&loaded), simulation_state_hash(&original))
	}

	// Without a cable a block world ends with the later tables, and a cable
	// laid and taken up leaves its bytes as they were.
	{
		plain := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&plain)
		first := place_test_entity(&plain.world, content, "junction_box", {0, 1, 0})
		second := place_test_entity(&plain.world, content, "junction_box", {5, 1, 0})
		before := encode_entities(&plain, content, header)
		later := make([dynamic]byte, context.temp_allocator)
		write_later_tables(&later, &plain.world, &plain.records, false)
		testing.expect(t, slice.has_suffix(before, later[:]), "the file ends with the later tables")
		lay_test_cable(&plain.world, content, "light_cable", {first, 1}, {second, 0})
		testing.expect(t, !slice.equal(encode_entities(&plain, content, header), before), "a cable is written")
		remove_cable(&plain.world.entities, content.machines, 0)
		testing.expect(t, slice.equal(encode_entities(&plain, content, header), before), "a cable taken up leaves the bytes")
	}

	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	entities := &original.world.entities
	first := place_test_entity(&original.world, content, "junction_box", {0, 1, 0})
	second := place_test_entity(&original.world, content, "junction_box", {5, 1, 0})
	third := place_test_entity(&original.world, content, "junction_box", {10, 1, 0})
	lay_test_cable(&original.world, content, "light_cable", {first, 1}, {second, 0})
	lay_test_cable(&original.world, content, "heavy_cable", {first, 2}, {second, 2})
	{
		changed := content
		changed.items.items = without(content.items.items, int(test_item(content.items, "light_cable")))
		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, changed)
		defer destroy_simulation(&loaded)
		testing.expect_value(t, decode_entities(&loaded, changed, encode_entities(&original, content, header), "entities.bin", header, &remap), "")
		cables := loaded.world.entities.cables.cables[:]
		testing.expect_value(t, len(cables), 1)
		testing.expect(t, len(cables) == 1 && changed.items.items[cables[0].item].id == "heavy_cable", "the heavy cable stays")
	}
	// A cable longer than any span is cut to the longest.
	heavy_metres := entities.cables.cables[1].metres
	entities.cables.cables[1].metres = 5000
	{
		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&loaded)
		testing.expect_value(t, decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap), "")
		cables := loaded.world.entities.cables.cables[:]
		testing.expect_value(t, len(cables), 2)
		testing.expect(t, len(cables) == 2 && cables[1].metres == MAXIMUM_CABLE_SPAN_METRES && cables[0].metres == entities.cables.cables[0].metres, "the long cable is cut, the other kept")
	}
	entities.cables.cables[1].metres = heavy_metres
	// Two cables on the first box's port b.
	append(&entities.cables.cables, Cable{ends = {{first, 1}, {third, 0}}, item = test_item(content.items, "light_cable"), metres = 9})
	{
		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&loaded)
		problem := decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap)
		testing.expectf(t, strings.contains(problem, "the save has two cables on one port"), "%q", problem)
	}
	// A cable whose end is a box gone.
	pop(&entities.cables.cables)
	testing.expect(t, remove_entity(entities, content.machines, third))
	append(&entities.cables.cables, Cable{ends = {{second, 1}, {third, 0}}, item = test_item(content.items, "light_cable"), metres = 4})
	{
		remap: Content_Remap
		loaded := make_save_test_simulation(&generator, content)
		defer destroy_simulation(&loaded)
		problem := decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap)
		testing.expectf(t, strings.contains(problem, "the save has a cable whose end is gone"), "%q", problem)
	}
}

// Work item 0374: a field world's tank piped to a fluid junction piped to
// a boiler round trips to the table, its capacities and kinds, the fluid
// netlist and the state hash.
@(test)
test_pipes_save_and_load :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	enable_test_field_tables(&original)
	world := &original.world
	frame := lay_pipe_test_pad(world, content)
	tank := place_on_pipe_pad(world, content, frame, "storage_tank", {-4, 1, -1})
	test_fluid_machine(world, tank).buffers[0] = {fluid = test_fluid(content, "water"), level = 5000}
	junction := place_on_pipe_pad(world, content, frame, "fluid_junction", {3, 1, 0})
	boiler := place_on_pipe_pad(world, content, frame, "boiler", {7, 1, -1})
	lay_test_cable(world, content, "pipe", test_port_end(world, content, tank, "b"), test_port_end(world, content, junction, "a"))
	lay_test_cable(world, content, "pipe", test_port_end(world, content, junction, "b"), test_port_end(world, content, boiler, "in"))
	tick_test_entities(world, &original.records, content, 3)

	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap), "")
	original_table, loaded_table := &world.entities.cables, &loaded.world.entities.cables
	testing.expect(t, len(original_table.cables) == 2 && slice.equal(loaded_table.cables[:], original_table.cables[:]), "the pipes come back")
	testing.expect(t, slice.equal(loaded_table.capacity[:], original_table.capacity[:]) && slice.equal(loaded_table.kinds[:], original_table.kinds[:]), "their capacities and kinds come back")
	testing.expect(t, slice.equal(loaded_table.kinds[:], []Machine_Port_Kind{.Fluid, .Fluid}), "both are pipes")
	networks := &loaded.world.entities.fluid_networks
	testing.expect_value(t, len(networks.nodes), len(world.entities.fluid_networks.nodes))
	testing.expect(t, fluid_netlist_of(networks, junction, -1) == fluid_netlist_of(networks, tank, 0) && fluid_netlist_of(networks, junction, -1) == fluid_netlist_of(networks, boiler, 0), "the pipes join the tank, the junction and the inlet")
	testing.expect_value(t, simulation_state_hash(&loaded), simulation_state_hash(&original))
}

// Work item 0374: an old save's pipe run between belt poles, a run of the
// pipe machine as a build before 0374 laid it, is dropped on load; the
// three poles and the belt run with its plates stay.
@(test)
test_old_saves_lose_their_pipe_runs :: proc(t: ^testing.T) {
	content := make_save_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	header := make_save_header()
	original := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&original)
	entities := &original.world.entities
	endpoints := lay_save_test_runs(&original.world, content)
	pool_add(&entities.belt_runs, .Belt_Run, Belt_Run{machine = test_machine(content.machines, "pipe"), endpoints = {endpoints[1], endpoints[2]}})

	remap: Content_Remap
	loaded := make_save_test_simulation(&generator, content)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, decode_entities(&loaded, content, encode_entities(&original, content, header), "entities.bin", header, &remap), "")
	testing.expect_value(t, pool_live_count(&loaded.world.entities.belt_runs), 1)
	testing.expect_value(t, pool_live_count(&loaded.world.entities.belt_poles), 3)
	testing.expect(t, belt_run_items_loaded(&loaded.world.entities), "the belt run's plates stand on it")
	testing.expect_value(t, drop_pipe_runs(entities, content.machines), 1)
}

// A run as a build before 0374 wrote it, with the kind field the codec
// now skips (from the 0374 review's probe).
Old_Belt_Run_Kind :: enum u8 {
	Belt,
	Pipe,
}

Old_Belt_Run :: struct {
	handle:         Entity_Handle,
	alive:          bool,
	kind:           Old_Belt_Run_Kind,
	machine:        Machine_Id,
	endpoints:      [2]Belt_Run_Endpoint,
	control_points: [4]World_Position,
}

// Work item 0374: an old run pool written with the kind field reads into
// this build's Belt_Run with every field after the kind intact and the
// bytes after the pool read right; drop_pipe_runs then removes the pipe
// run and keeps the belt run.
@(test)
test_an_old_run_pools_kind_is_skipped :: proc(t: ^testing.T) {
	content := make_test_content()
	pipe, belt := test_machine(content.machines, "pipe"), test_machine(content.machines, "belt")
	old := [3]Old_Belt_Run {
		{handle = {kind = .Belt_Run, index = 0}, alive = true, kind = .Belt, machine = belt, endpoints = {{frame = 3, cell = {1, 2, 3}, facing = 1}, {frame = 4, cell = {4, 5, 6}, facing = 2}}, control_points = {{1, 2, 3}, {4, 5, 6}, {7, 8, 9}, {10, 11, 12}}},
		{handle = {kind = .Belt_Run, index = 1}, alive = true, kind = .Pipe, machine = pipe, endpoints = {{frame = 5, cell = {7, 8, 9}, facing = 3}, {frame = 6, cell = {1, 1, 1}, facing = 0}}, control_points = {{13, 14, 15}, {16, 17, 18}, {19, 20, 21}, {22, 23, 24}}},
		{handle = {kind = .Belt_Run, index = 2}, alive = false, kind = .Pipe, machine = pipe},
	}
	free := [1]u32{2}
	bytes := make([dynamic]byte, context.temp_allocator)
	write_list(&bytes, old[:])
	write_list(&bytes, free[:])
	append_u32(&bytes, 0xfeed_0374)
	reader := Byte_Reader{data = bytes[:]}
	pool: Entity_Pool(Belt_Run)
	defer destroy_pool(&pool)
	if !testing.expect(t, read_pool(&reader, &pool, .Belt_Run, content.machines), "the old pool reads") {
		return
	}
	sentinel, ok := read_u32(&reader)
	testing.expect(t, ok && sentinel == 0xfeed_0374, "the bytes after the pool read right")
	testing.expect_value(t, len(pool.entries), 3)
	for entry, index in pool.entries {
		testing.expectf(t, entry.handle == old[index].handle && entry.alive == old[index].alive && entry.machine == old[index].machine && entry.endpoints == old[index].endpoints && entry.control_points == old[index].control_points, "run %d reads as written", index)
	}
	entities: Entities
	defer destroy_entities(&entities)
	for entry in pool.entries {
		append(&entities.belt_runs.entries, entry)
	}
	testing.expect_value(t, drop_pipe_runs(&entities, content.machines), 1)
	testing.expect(t, entities.belt_runs.entries[0].alive && !entities.belt_runs.entries[1].alive, "the belt run stays, the pipe run goes")
}

// A player as a build before the toolbars (0278) wrote one: 44 slots,
// the hotbar's 8 first.
Hotbar_Era_Test_Player :: struct {
	inventory:            Inventory,
	selected_hotbar_slot: int,
	held:                 Held_Stack,
}

// Work item 0278: an old save's hotbar moves into the fifth row and its
// kinds onto the first toolbar; the main grid takes slots 0 to 35, the
// held stack's origin follows its slot and the selection is kept.
@(test)
test_an_old_save_moves_the_hotbar_into_the_fifth_row :: proc(t: ^testing.T) {
	old := Hotbar_Era_Test_Player {
		inventory            = make_inventory(HOTBAR_ERA_INVENTORY_SLOT_COUNT, context.temp_allocator),
		selected_hotbar_slot = 5,
		held                 = {stack = {Item_Id(9), 2}, origin_slot = 2},
	}
	for &slot, index in old.inventory.slots {
		if index != 4 {
			slot = Item_Stack{Item_Id(index + 1), u16(index + 1)}
		}
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	append_u32(&bytes, 1)
	write_value_of(&bytes, &old)
	players: [dynamic]Player
	defer {
		for entry in players {
			destroy_player(entry)
		}
		delete(players)
	}
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_players(&reader, &players))
	testing.expect_value(t, len(players), 1)
	if len(players) != 1 {
		return
	}
	player := players[0]
	testing.expect_value(t, len(player.inventory.slots), PLAYER_INVENTORY_SLOT_COUNT)
	for index in 0 ..< 36 {
		testing.expectf(t, player.inventory.slots[index] == old.inventory.slots[HOTBAR_SLOT_COUNT + index], "grid slot %d", index)
	}
	for slot in 0 ..< HOTBAR_SLOT_COUNT {
		testing.expectf(t, player.inventory.slots[36 + slot] == old.inventory.slots[slot], "hotbar slot %d at %d", slot, 36 + slot)
		expected := slot == 4 ? NO_ITEM : old.inventory.slots[slot].item
		testing.expectf(t, player.toolbars[0][slot] == expected, "the first toolbar's slot %d", slot)
	}
	testing.expect_value(t, player.inventory.slots[44], EMPTY_STACK)
	for row in 1 ..< MAXIMUM_TOOLBAR_COUNT {
		for item, slot in player.toolbars[row] {
			testing.expectf(t, item == NO_ITEM, "toolbar %d slot %d", row, slot)
		}
	}
	testing.expect_value(t, player.held.origin_slot, 38)
	testing.expect_value(t, player.selected_hotbar_slot, 5)
	testing.expect_value(t, moved_hotbar_era_slot(10), 2)
	testing.expect_value(t, moved_hotbar_era_slot(MACHINE_SLOT_ORIGIN), MACHINE_SLOT_ORIGIN)
}

// Work item 0278: a selection past the loaded config's toolbars is
// clamped to the last toolbar and the last slot.
@(test)
test_a_loaded_toolbar_selection_is_clamped :: proc(t: ^testing.T) {
	player := Player{active_toolbar = 3, selected_hotbar_slot = 12}
	clamp_toolbar_selection(&player, 1)
	testing.expect_value(t, player.active_toolbar, 0)
	testing.expect_value(t, player.selected_hotbar_slot, 7)
	player.active_toolbar = 3
	clamp_toolbar_selection(&player, 2)
	testing.expect_value(t, player.active_toolbar, 1)
}
