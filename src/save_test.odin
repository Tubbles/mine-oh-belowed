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
	place_fuelled_inserter(world, content, World_Coordinate{4, 1, 0} + offset, 0)
	lay_belt_row(world, content, World_Coordinate{5, 1, 0} + offset, 3, 0)
	place_fuelled_inserter(world, content, World_Coordinate{8, 1, 0} + offset, 0)
	place_test_entity(world, content, "wooden_chest", World_Coordinate{9, 1, 0} + offset)
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
	add_test_power_plant(world, content, World_Coordinate{-1, 1, 0} + offset, World_Coordinate{-2, 1, 2} + offset)
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
	place_pending_crates(world, records.crate_sites[:], content)
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
	append(&records.core_samples, take_core_sample(world, len(content.blocks.definitions), {21, 1, -10}))
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
	place_test_entity(world, content, "power_switch", {12, 1, 6})
	lay_gear_line_at(world, content, {-20, 0, 0})
	lay_save_test_research(world, content, {-10, 0, -20})
	lay_save_test_smelting(world, content, {12, 0, 14})
	lay_save_test_splitter(world, content, {12, 0, 20})
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

pipes_holding_fluid :: proc(entities: ^Entities) -> int {
	count := 0
	for pipe in entities.pipes.entries {
		count += pipe.alive && pipe.buffer.level > 0 ? 1 : 0
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

expect_every_pool_used :: proc(t: ^testing.T, entities: ^Entities) {
	for kind in Entity_Kind {
		if kind != .None {
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
@(test)
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
	testing.expect(t, pipes_holding_fluid(&loaded.world.entities) > 0)
	testing.expect(t, deep_veins_and_bore_drill_loaded(&loaded.world))
	testing.expect(t, schematics_loaded(&loaded, content))
	testing.expect(t, prospecting_loaded(&loaded.world, &loaded.records, &original.records))
	testing.expect(t, launch_pad_loaded(&loaded.world, &loaded.records, &original.records))
	testing.expect(t, venture_loaded(&loaded.records, &original.records, content.technologies))
	testing.expect(t, len(loaded.world.entities.loose_items.items) > 0)
	testing.expect(t, slice.equal(loaded.world.entities.loose_items.items[:], original.world.entities.loose_items.items[:]))
	testing.expect_value(t, len(loaded.world.entities.fluid_networks.networks), len(original.world.entities.fluid_networks.networks))
	testing.expect_value(t, len(loaded.world.entities.electric_networks.networks), len(original.world.entities.electric_networks.networks))
	testing.expect_value(t, len(loaded.world.entities.belt_network.lines), len(original.world.entities.belt_network.lines))
	testing.expect_value(t, len(loaded.world.entities.cells), len(original.world.entities.cells))
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
	write_later_tables(&table, &original.world, &original.records)
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
