package game

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

// The command protocol and socket (work item 0053): words, each command
// applied to a test simulation, blueprints, queries, the socket path and
// a round trip through a real socket.

Command_Test :: struct {
	simulation: Simulation_State,
	content:    Simulation_Content,
	generator:  Generator,
	control:    Command_Control,
}

// The developer test simulation (player at 0.5 11 0.5, pad at 0 10 0)
// with the test chunks loaded as a stone floor at y 0 and no veins.
// Heap allocated, since the context points into it.
make_command_test :: proc() -> ^Command_Test {
	test := new(Command_Test)
	test.simulation, test.content = make_developer_test_simulation()
	test.generator = make_test_generator(DEFAULT_WORLD_SEED)
	test.content.generator = &test.generator
	world := &test.simulation.world
	chunks := TEST_WORLD_CHUNKS
	for coordinate in chunks {
		chunk := new(Chunk)
		chunk.coordinate = coordinate
		world.chunks[coordinate] = chunk
		if chunk_column_of(coordinate) not_in world.column_veins {
			world.column_veins[chunk_column_of(coordinate)] = make([dynamic]Vein_Id)
		}
	}
	stone := test_block(test.content.blocks, "stone")
	for x in i32(-32) ..< 32 {
		for z in i32(-32) ..< 32 {
			world_set_block(world, {x, 0, z}, stone)
		}
	}
	return test
}

destroy_command_test :: proc(test: ^Command_Test) {
	destroy_simulation(&test.simulation)
	delete(test.control.screenshot_path)
	free(test)
}

command_test_context :: proc(test: ^Command_Test) -> Command_Context {
	return Command_Context{simulation = &test.simulation, content = test.content, control = &test.control}
}

run_test_command :: proc(test: ^Command_Test, line: string) -> Command_Response {
	response, _ := execute_command_line(command_test_context(test), line)
	return response
}

expect_command_ok :: proc(t: ^testing.T, test: ^Command_Test, line: string, location := #caller_location) -> Command_Response {
	response := run_test_command(test, line)
	testing.expectf(t, response.ok, "%q: %s", line, response.text, loc = location)
	return response
}

expect_command_error :: proc(t: ^testing.T, test: ^Command_Test, line: string, location := #caller_location) -> Command_Response {
	response := run_test_command(test, line)
	testing.expectf(t, !response.ok, "%q succeeded: %s", line, response.text, loc = location)
	return response
}

TEST_IRON_VEIN_INDEX :: 99

// An iron vein of radius 3 centred on 0 0 in the floor.
add_command_test_iron_vein :: proc(test: ^Command_Test) -> Vein_Id {
	remaining: [MAXIMUM_VEIN_OUTPUTS]i64
	remaining[0], remaining[1] = 1000, 250
	return add_test_vein(&test.simulation.world, test.content, "iron", {0, 0}, 3, remaining, TEST_IRON_VEIN_INDEX)
}

@(test)
test_command_words_split_quotes_and_comments :: proc(t: ^testing.T) {
	words, problem := split_command_words("  give \"iron plate\"\t5 # a comment \"x\"")
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(words), 3)
	if len(words) == 3 {
		testing.expect_value(t, words[0], "give")
		testing.expect_value(t, words[1], "iron plate")
		testing.expect_value(t, words[2], "5")
	}
	words, problem = split_command_words(`say "a \"b\" \\ c"`)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, words[1], `a "b" \ c`)
	words, _ = split_command_words("# only a comment")
	testing.expect_value(t, len(words), 0)
	words, _ = split_command_words("   \r")
	testing.expect_value(t, len(words), 0)
	words, _ = split_command_words("pause#now")
	testing.expect_value(t, len(words), 1)
	_, problem = split_command_words(`give "iron`)
	testing.expect(t, problem != "")
	_, problem = split_command_words(`give "iron"plate`)
	testing.expect(t, problem != "")

	value, ok := parse_integer_word("-42")
	testing.expect(t, ok && value == -42)
	for bad in ([?]string{"", "-", "4a", "+4", "1_0", "99999999999"}) {
		_, bad_ok := parse_integer_word(bad)
		testing.expectf(t, !bad_ok, "%q parsed", bad)
	}
}

@(test)
test_command_response_format :: proc(t: ^testing.T) {
	testing.expect_value(t, format_command_response(Command_Response{ok = true}), "ok\n.\n")
	testing.expect_value(t, format_command_response(command_ok("player\nposition 1")), "ok player\nposition 1\n.\n")
	testing.expect_value(t, format_command_response(command_error("unknown item %q", "x")), "error unknown item \"x\"\n.\n")
	response, empty := execute_command_line(Command_Context{}, "  # nothing")
	testing.expect(t, empty && response == {})
}

@(test)
test_command_socket_path_from_environment :: proc(t: ^testing.T) {
	path, ok := command_socket_path_from_environment("/run/user/1000", "/state", "/home/player", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, path, "/run/user/1000/mine-oh-belowed/command.sock")
	path, ok = command_socket_path_from_environment("", "/state", "/home/player", context.temp_allocator)
	testing.expect_value(t, path, "/state/mine-oh-belowed/command.sock")
	path, ok = command_socket_path_from_environment("relative", "", "/home/player", context.temp_allocator)
	testing.expect_value(t, path, "/home/player/.local/state/mine-oh-belowed/command.sock")
	_, ok = command_socket_path_from_environment("", "", "", context.temp_allocator)
	testing.expect(t, !ok)
	directory, directory_ok := screenshot_directory_from_environment("/state", "/home/player", context.temp_allocator)
	testing.expect(t, directory_ok)
	testing.expect_value(t, directory, "/state/mine-oh-belowed/screenshots")
}

@(test)
test_commands_without_a_world :: proc(t: ^testing.T) {
	control: Command_Control
	command_context := Command_Context{control = &control, content = make_test_content()}
	response, _ := execute_command_line(command_context, "help")
	testing.expect(t, response.ok)
	testing.expect(t, strings.contains(response.text, "blueprint <path>"), response.text)
	response, _ = execute_command_line(command_context, "give iron_plate 1")
	testing.expect_value(t, response.text, "no world is loaded")
	response, _ = execute_command_line(command_context, "reload")
	testing.expect_value(t, response, Command_Response{text = "reload runs only in the game"})
	response, _ = execute_command_line(command_context, "pause")
	testing.expect(t, response.ok && control.paused)
	response, _ = execute_command_line(command_context, "resume")
	testing.expect(t, response.ok && !control.paused)
}

@(test)
test_command_give_take_kit_chapter :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	items := test.content.items
	player := &test.simulation.players[0]
	plate := test_item(items, "iron_plate")
	expect_command_ok(t, test, "give iron_plate 50")
	testing.expect_value(t, inventory_count(player.inventory, plate), 50)
	response := expect_command_ok(t, test, "take iron_plate 80")
	testing.expect_value(t, response.text, "took 50 iron_plate")
	testing.expect_value(t, inventory_count(player.inventory, plate), 0)
	expect_command_error(t, test, "give no_such_item 5")
	expect_command_error(t, test, "give iron_plate 0")
	expect_command_error(t, test, "give iron_plate")

	expect_command_ok(t, test, "kit 4")
	testing.expect_value(t, inventory_count(player.inventory, test_item(items, "iron_pickaxe")), 1)
	expect_command_error(t, test, "kit 0")
	expect_command_error(t, test, "kit 99")

	response = expect_command_ok(t, test, "chapter 4")
	testing.expect_value(t, test.simulation.quests.active, test.content.quests.chapters[3].first_quest)
	testing.expect(t, strings.contains(response.text, "chapter 4"), response.text)
	expect_command_error(t, test, "chapter 0")

	first := test.simulation.quests.active
	response = expect_command_ok(t, test, "quest finish")
	testing.expect_value(t, test.simulation.quests.progress[first].status, Quest_Status.Done)
	testing.expect_value(t, test.simulation.quests.active, first + 1)
	testing.expect(t, strings.contains(response.text, "active quest"), response.text)
	expect_command_error(t, test, "quest")
	expect_command_error(t, test, "quest done")
	expect_command_ok(t, test, fmt.tprintf("chapter %d", len(test.content.quests.chapters) + 1))
	expect_command_error(t, test, "quest finish")
}

@(test)
test_command_research_and_unlock_all :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	technologies := test.content.technologies.technologies
	finite, infinite := -1, -1
	for technology, index in technologies {
		if technology.infinite && infinite < 0 {
			infinite = index
		} else if !technology.infinite && !technology.placeholder && !test.simulation.unlocks.researched[index] && finite < 0 {
			finite = index
		}
	}
	testing.expect(t, finite >= 0 && infinite >= 0)
	expect_command_ok(t, test, strings.concatenate({"research ", technologies[finite].id}, context.temp_allocator))
	testing.expect(t, test.simulation.unlocks.researched[finite])
	response := expect_command_ok(t, test, strings.concatenate({"research ", technologies[finite].id}, context.temp_allocator))
	testing.expect(t, strings.contains(response.text, "already"), response.text)
	for level in u32(1) ..= 2 {
		expect_command_ok(t, test, strings.concatenate({"research ", technologies[infinite].id}, context.temp_allocator))
		testing.expect_value(t, test.simulation.records.research.levels[infinite], level)
	}
	expect_command_error(t, test, "research no_such_technology")

	expect_command_ok(t, test, "unlock_all")
	for researched in test.simulation.unlocks.researched {
		testing.expect(t, researched)
	}
}

@(test)
test_command_teleport_time_and_toggles :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	simulation := &test.simulation
	expect_command_ok(t, test, "teleport 3 20 -4")
	testing.expect_value(t, simulation.players[0].position, [3]f32{3.5, 20, -3.5})
	expect_command_ok(t, test, "teleport pad")
	testing.expect_value(t, simulation.players[0].position, landing_pad_standing_position(simulation.landing_pad))
	expect_command_error(t, test, "teleport 1 2")

	expect_command_ok(t, test, "time noon")
	testing.expect_value(t, simulation_day_ticks(simulation^) % simulation.day_length_ticks, time_of_day_day_ticks(.Noon, simulation.day_length_ticks))
	expect_command_error(t, test, "time teatime")

	flying := simulation.players[0].flying
	expect_command_ok(t, test, flying ? "fly off" : "fly on")
	testing.expect_value(t, simulation.players[0].flying, !flying)
	expect_command_ok(t, test, flying ? "fly off" : "fly on")
	testing.expect_value(t, simulation.players[0].flying, !flying)
	expect_command_ok(t, test, "cheat_speed on")
	expect_command_ok(t, test, "cheat_speed on")
	testing.expect(t, simulation.cheat_speed)
	expect_command_ok(t, test, "cheat_speed off")
	testing.expect(t, !simulation.cheat_speed)
	expect_command_ok(t, test, "free_crafting on")
	expect_command_ok(t, test, "free_crafting on")
	testing.expect(t, simulation.free_crafting)
	expect_command_ok(t, test, "free_crafting off")
	testing.expect(t, !simulation.free_crafting)
	expect_command_error(t, test, "fly maybe")

	expect_command_ok(t, test, "noclip on")
	testing.expect(t, simulation.players[0].no_clip)
	query := expect_command_ok(t, test, "query player")
	testing.expect(t, strings.contains(query.text, "\nno_clip true\n"), query.text)
	expect_command_ok(t, test, "noclip off")
	testing.expect(t, !simulation.players[0].no_clip)
	expect_command_error(t, test, "noclip maybe")
}

// The first column, walking chunk column centres east from start, where
// a vein of the type fits.
find_clear_vein_column :: proc(test: ^Command_Test, type_index: int, start_x: i32) -> [2]i32 {
	for chunk_x in i32(0) ..< 64 {
		for chunk_z in i32(0) ..< 8 {
			column := [2]i32{start_x + chunk_x * CHUNK_SIZE + CHUNK_SIZE / 2, chunk_z * CHUNK_SIZE + CHUNK_SIZE / 2}
			vein := make_added_vein(&test.generator, type_index, 0, column)
			if !added_vein_overlaps(&test.simulation.world, &test.generator, vein.centre, vein.radius) {
				return column
			}
		}
	}
	panic("no clear column")
}

load_vein_chunks :: proc(test: ^Command_Test, vein: Vein) {
	for cell in added_vein_cells(&test.generator, vein) {
		if coordinate := world_to_chunk_coordinate(cell); coordinate not_in test.simulation.world.chunks {
			load_chunk_now(&test.simulation.world, &test.simulation.records, &test.generator, coordinate)
		}
	}
}

// Every footprint cell registered for the vein, and most of them (the
// solid ones) turned into its outcrop block.
expect_vein_outcrop :: proc(t: ^testing.T, test: ^Command_Test, vein: Vein, location := #caller_location) {
	world := &test.simulation.world
	cells := added_vein_cells(&test.generator, vein)
	stamped := 0
	for cell in cells {
		testing.expect_value(t, world.outcrop_cells[cell] or_else {}, vein.id, loc = location)
		stamped += vein_block_is_outcrop(test.content.veins, vein, world_get_block(world, cell)) ? 1 : 0
	}
	testing.expectf(t, stamped * 2 > len(cells), "%d of %d cells stamped", stamped, len(cells), loc = location)
	found, found_ok := vein_at_column(world, vein.centre.x, vein.centre.z)
	testing.expect(t, found_ok && found == vein.id, loc = location)
}

@(test)
test_command_vein_stamps_loaded_stored_and_later_chunks :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	world := &test.simulation.world
	iron := find_vein_type(test.content.veins, "iron")

	// Loaded: stamped at once, next to the region's generated veins.
	loaded := find_clear_vein_column(test, iron, 64)
	load_vein_chunks(test, make_added_vein(&test.generator, iron, 0, loaded))
	expect_command_ok(t, test, strings.concatenate({"vein iron ", fmt_column(loaded)}, context.temp_allocator))
	first := world.veins[len(world.veins) - 1]
	testing.expect(t, first.added)
	testing.expect_value(t, first.id.index, i32(len(layer_veins(&test.generator, first.id.region, .Surface, context.temp_allocator))))
	expect_vein_outcrop(t, test, first)
	expect_command_error(t, test, strings.concatenate({"vein iron ", fmt_column(loaded)}, context.temp_allocator))

	// Stored: a modified chunk that went out of range gets the outcrop
	// in its stored blocks.
	stored := find_clear_vein_column(test, iron, loaded.x + 64)
	stored_vein := make_added_vein(&test.generator, iron, 0, stored)
	load_vein_chunks(test, stored_vein)
	for cell in added_vein_cells(&test.generator, stored_vein) {
		coordinate := world_to_chunk_coordinate(cell)
		if chunk, found := world.chunks[coordinate]; found {
			chunk.modified = true
			store_modified_chunk(world, chunk)
			free(chunk)
			delete_key(&world.chunks, coordinate)
		}
	}
	expect_command_ok(t, test, strings.concatenate({"vein iron ", fmt_column(stored)}, context.temp_allocator))
	load_vein_chunks(test, stored_vein)
	expect_vein_outcrop(t, test, world.veins[len(world.veins) - 1])

	// Later: a chunk generated after the command.
	later := find_clear_vein_column(test, iron, stored.x + 64)
	expect_command_ok(t, test, strings.concatenate({"vein iron ", fmt_column(later), " deposit"}, context.temp_allocator))
	later_vein := world.veins[len(world.veins) - 1]
	testing.expect_value(t, later_vein.size_class, find_size_class(test.content.veins, "deposit"))
	load_vein_chunks(test, later_vein)
	expect_vein_outcrop(t, test, later_vein)

	expect_command_error(t, test, "vein deep_iron 500 500")
	expect_command_error(t, test, "vein no_such_type 500 500")
	expect_command_error(t, test, "vein iron 500 500 enormous")
}

fmt_column :: proc(column: [2]i32) -> string {
	return fmt.tprintf("%d %d", column.x, column.y)
}

@(test)
test_command_place_remove_block_insert :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	world := &test.simulation.world
	vein := add_command_test_iron_vein(test)
	expect_command_ok(t, test, "place burner_mining_drill -2 1 -2 1")
	drill := entity_at(&world.entities, {-2, 1, -2})
	testing.expect_value(t, drill.kind, Entity_Kind.Drill)
	testing.expect_value(t, pool_get(&world.entities.drills, drill).vein, vein)
	expect_command_error(t, test, "place burner_mining_drill -2 1 -2 1")
	expect_command_error(t, test, "place burner_mining_drill 20 1 20 0")
	expect_command_error(t, test, "place wooden_chest 5 4 5 0")
	expect_command_error(t, test, "place drop_capsule 5 1 5 0")
	expect_command_error(t, test, "place wooden_chest 5 1 5 4")
	expect_command_error(t, test, "place no_such_machine 5 1 5 0")
	// The player's body blocks a machine.
	expect_command_error(t, test, "place wooden_chest 0 11 0 0")

	expect_command_ok(t, test, "place belt 5 1 0 1")
	belt := pool_get(&world.entities.belts, entity_at(&world.entities, {5, 1, 0}))
	testing.expect(t, belt != nil && belt.rotation == 1)
	expect_command_ok(t, test, "remove 5 1 0")
	testing.expect_value(t, entity_at(&world.entities, {5, 1, 0}), NO_ENTITY)
	expect_command_error(t, test, "remove 5 1 0")
	expect_command_ok(t, test, "remove 5 0 0")
	testing.expect_value(t, world_get_block(world, {5, 0, 0}), AIR_BLOCK)
	expect_command_ok(t, test, "block stone 5 0 0")
	testing.expect_value(t, world_get_block(world, {5, 0, 0}), test_block(test.content.blocks, "stone"))
	expect_command_error(t, test, "block stone -2 1 -2")
	expect_command_error(t, test, "block stone 500 0 0")

	expect_command_ok(t, test, "insert coal 20 -1 2 -1")
	fuel := pool_get(&world.entities.drills, drill).slots[DRILL_FUEL_SLOT]
	testing.expect_value(t, fuel, Item_Stack{test_item(test.content.items, "coal"), 20})
	expect_command_error(t, test, "insert iron_plate 5 -2 1 -2")
	expect_command_error(t, test, "insert coal 5 9 1 9")
	// The capsule stays.
	capsule := entity_common(&world.entities, test.simulation.quests.capsule)
	testing.expect(t, capsule != nil)
	origin := capsule.origin
	expect_command_error(t, test, fmt.tprintf("remove %d %d %d", origin.x, origin.y, origin.z))
}

// Work item 0050: the recipe and filter commands, as the panels set them.
@(test)
test_command_recipe_and_filter :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	world := &test.simulation.world
	recipes := test.content.recipes
	expect_command_ok(t, test, "place assembler_1 4 1 4 0")
	expect_command_ok(t, test, "recipe iron_gear 5 2 5")
	assembler := pool_get(&world.entities.assemblers, entity_at(&world.entities, {4, 1, 4}))
	testing.expect_value(t, assembler.recipe, test_recipe(recipes, "iron_gear"))
	// A furnace recipe, a missing machine, an unknown recipe, bad words.
	expect_command_error(t, test, "recipe iron_plate 4 1 4")
	testing.expect_value(t, assembler.recipe, test_recipe(recipes, "iron_gear"))
	expect_command_error(t, test, "recipe iron_gear 9 1 9")
	expect_command_error(t, test, "recipe no_such_recipe 4 1 4")
	expect_command_error(t, test, "recipe iron_gear 4 1")
	// The old contents go to the player's inventory, as from the panel.
	plate := test_item(test.content.items, "iron_plate")
	expect_command_ok(t, test, "insert iron_plate 2 4 1 4")
	held := inventory_count(test.simulation.players[0].inventory, plate)
	expect_command_ok(t, test, "recipe copper_wire 4 1 4")
	testing.expect_value(t, assembler.recipe, test_recipe(recipes, "copper_wire"))
	testing.expect_value(t, inventory_count(test.simulation.players[0].inventory, plate), held + 2)
	// A fixed recipe machine takes none.
	expect_command_ok(t, test, "place crusher 9 1 4 0")
	expect_command_error(t, test, "recipe iron_gear 9 1 4")

	coal := test_item(test.content.items, "coal")
	expect_command_ok(t, test, "place filter_inserter 2 1 8 0")
	expect_command_ok(t, test, "filter coal 2 1 8")
	testing.expect_value(t, pool_get(&world.entities.inserters, entity_at(&world.entities, {2, 1, 8})).filter, coal)
	expect_command_ok(t, test, "place splitter 5 1 8 0")
	expect_command_ok(t, test, "filter coal 5 1 9")
	testing.expect_value(t, pool_get(&world.entities.splitters, entity_at(&world.entities, {5, 1, 8})).filter, coal)
	expect_command_ok(t, test, "place inserter 8 1 8 0")
	expect_command_error(t, test, "filter coal 8 1 8")
	expect_command_error(t, test, "filter no_such_item 2 1 8")
	words, _ := expand_blueprint_command("recipe iron_gear 1 0 1", {10, 20, 30})
	testing.expect_value(t, strings.join(words, " ", context.temp_allocator), "recipe iron_gear 11 20 31")
	words, _ = expand_blueprint_command("filter coal 1 0 1", {10, 20, 30})
	testing.expect_value(t, strings.join(words, " ", context.temp_allocator), "filter coal 11 20 31")
}

@(test)
test_blueprint_parsing_and_expansion :: proc(t: ^testing.T) {
	blueprint, problem := parse_blueprint(transmute([]byte)string(`origin = [1, 2, 3]
commands = ["place belt 0 0 0 0" "remove -1 0 2"]`))
	testing.expect_value(t, problem, "")
	testing.expect_value(t, blueprint.origin_kind, Blueprint_Origin_Kind.Cell)
	testing.expect_value(t, blueprint.cell, World_Coordinate{1, 2, 3})
	testing.expect_value(t, len(blueprint.commands), 2)
	blueprint, problem = parse_blueprint(transmute([]byte)string(`origin = "pad", commands = []`))
	testing.expect(t, problem == "" && blueprint.origin_kind == .Pad)
	blueprint, problem = parse_blueprint(transmute([]byte)string(`origin = {vein = "iron"}, commands = []`))
	testing.expect(t, problem == "" && blueprint.origin_kind == .Vein && blueprint.vein_type == "iron")
	for bad in ([?]string{`origin = "moon", commands = []`, `origin = [1, 2], commands = []`, `origin = "pad", commands = [1]`, `origin = "pad", commands = [], extra = 1`, `origin = {vein = "iron", size = 2}, commands = []`}) {
		_, bad_problem := parse_blueprint(transmute([]byte)bad)
		testing.expectf(t, bad_problem != "", "%s parsed", bad)
	}

	words, expand_problem := expand_blueprint_command("place belt 1 2 3 0", {10, 20, 30})
	testing.expect_value(t, expand_problem, "")
	testing.expect_value(t, strings.join(words, " ", context.temp_allocator), "place belt 11 22 33 0")
	words, _ = expand_blueprint_command("insert coal 5 -1 0 1", {10, 20, 30})
	testing.expect_value(t, strings.join(words, " ", context.temp_allocator), "insert coal 5 9 20 31")
	words, _ = expand_blueprint_command("remove 0 -1 0", {10, 20, 30})
	testing.expect_value(t, strings.join(words, " ", context.temp_allocator), "remove 10 19 30")
	_, expand_problem = expand_blueprint_command("give coal 5", {})
	testing.expect(t, expand_problem != "")
	_, expand_problem = expand_blueprint_command("place belt 1 2", {})
	testing.expect(t, expand_problem != "")
}

@(test)
test_blueprint_runs_relative_and_stops_at_the_first_error :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	world := &test.simulation.world
	blueprint := Blueprint {
		origin_kind = .Cell,
		cell        = {4, 1, 4},
		commands    = {"place wooden_chest 0 0 0 0", "place wooden_chest 0 0 0 0", "place wooden_chest 1 0 0 0"},
	}
	response := run_blueprint(command_test_context(test), blueprint)
	testing.expect(t, !response.ok)
	testing.expect(t, strings.has_prefix(response.text, "blueprint command 2 "), response.text)
	testing.expect_value(t, entity_at(&world.entities, {4, 1, 4}).kind, Entity_Kind.Chest)
	testing.expect_value(t, entity_at(&world.entities, {5, 1, 4}), NO_ENTITY)

	// Relative to the cell above the pad's centre.
	blueprint = Blueprint{origin_kind = .Pad, commands = {"block stone 3 0 3"}}
	testing.expect(t, run_blueprint(command_test_context(test), blueprint).ok)
	pad := test.simulation.landing_pad.centre
	testing.expect_value(t, world_get_block(world, pad + {3, 1, 3}), test_block(test.content.blocks, "stone"))
	blueprint = Blueprint{origin_kind = .Vein, vein_type = "copper", commands = {"block stone 0 0 0"}}
	testing.expect(t, !run_blueprint(command_test_context(test), blueprint).ok)
}

// The shipped blueprint places on a flat floor with an iron vein and
// makes plates.
@(test)
test_tier1_factory_blueprint_places_and_smelts :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	add_command_test_iron_vein(test)
	blueprint, problem := parse_blueprint(#load("../data/blueprints/tier1_factory.sjson"))
	testing.expect_value(t, problem, "")
	response := run_blueprint(command_test_context(test), blueprint)
	testing.expect(t, response.ok, response.text)
	entities := &test.simulation.world.entities
	testing.expect_value(t, pool_live_count(&entities.drills), 2)
	testing.expect_value(t, pool_live_count(&entities.furnaces), 2)
	testing.expect_value(t, pool_live_count(&entities.belts), 9)
	testing.expect_value(t, pool_live_count(&entities.inserters), 7)
	testing.expect_value(t, pool_live_count(&entities.chests), 5)

	expect_command_ok(t, test, "tick 3600")
	for test.control.pending_ticks > 0 {
		run_command_tick(&test.simulation, test.content, &test.control)
	}
	_, finished := finish_command_ticks(&test.control, test.simulation.tick)
	testing.expect(t, finished)
	plates := test_item(test.content.items, "iron_plate")
	produced := item_counter(test.simulation.records.statistics.produced, plates)
	testing.expectf(t, produced > 0, "no plates after a minute")
	stored: u64
	for &chest in entities.chests.entries {
		stored += slots_item_count(chest.slots[:chest.slot_count], plates)
	}
	testing.expectf(t, stored > 0, "no plates in the chests (%d produced)", produced)
}

pool_live_count :: proc(pool: ^Entity_Pool($T)) -> int {
	return len(pool.entries) - len(pool.free)
}

@(test)
test_command_tick_pause_and_screenshot :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	start := test.simulation.tick
	response := expect_command_ok(t, test, "tick 5")
	testing.expect(t, response.deferred)
	testing.expect_value(t, test.control.pending_ticks, 5)
	_, finished := finish_command_ticks(&test.control, test.simulation.tick)
	testing.expect(t, !finished)
	for test.control.pending_ticks > 0 {
		run_command_tick(&test.simulation, test.content, &test.control)
	}
	testing.expect_value(t, test.simulation.tick, start + 5)
	response, finished = finish_command_ticks(&test.control, test.simulation.tick)
	testing.expect(t, finished && response.ok)
	testing.expect(t, strings.has_prefix(response.text, "ran 5 ticks"), response.text)
	expect_command_error(t, test, "tick 0")
	expect_command_error(t, test, "tick many")

	expect_command_ok(t, test, "pause")
	testing.expect(t, test.control.paused)
	expect_command_ok(t, test, "resume")
	testing.expect(t, !test.control.paused)
	expect_command_error(t, test, "save")

	directory, error := os.make_directory_temp("", "mine-oh-belowed-screenshot-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(directory)
	command_context := command_test_context(test)
	command_context.screenshot_directory = directory
	command_context.now = time.unix(1790000000, 0)
	response, _ = execute_command_line(command_context, "screenshot base")
	testing.expect(t, response.ok && strings.has_suffix(response.text, "/base.png"), response.text)
	testing.expect_value(t, test.control.screenshot_path, response.text)
	response, _ = execute_command_line(command_context, "screenshot")
	testing.expect(t, strings.has_suffix(response.text, "/2026-09-21T14-13-20Z.png"), response.text)
	for bad in ([?]string{"screenshot ../up", "screenshot .hidden", "screenshot a b"}) {
		response, _ = execute_command_line(command_context, bad)
		testing.expectf(t, !response.ok, "%q succeeded", bad)
	}
	command_context.screenshot_directory = ""
	response, _ = execute_command_line(command_context, "screenshot")
	testing.expect(t, !response.ok)
}

@(test)
test_command_queries :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	add_command_test_iron_vein(test)
	expect_command_ok(t, test, "give iron_plate 7")
	expect_command_ok(t, test, "place burner_mining_drill -2 1 -2 1")
	expect_command_ok(t, test, "place belt 0 1 0 0")
	expected := [?][2]string {
		{"query player", "position 0.50 11.00 0.50"},
		{"query player", "item iron_plate 7"},
		{"query player", "\nno_clip false\n"},
		{"query world", "pad 0 10 0"},
		{"query world", "loaded_chunks 8"},
		{"query world", "tick 0"},
		{"query veins", "vein iron size scattering layer surface centre 0 0 0 radius 3 remaining 1250"},
		{"query veins 5", "vein iron"},
		{"query entities", "entity burner_mining_drill -2 1 -2 rotation 1"},
		{"query entities belt", "entities 1\nentity belt 0 1 0 rotation 0"},
		{"query entities drill 20", "entities 1"},
		{"query quests", "active arrival chapter 1"},
		{"query quests", "done 0 of "},
		{"query contracts", "credit 0"},
		{"query stats iron_plate", "produced 0"},
		{"query stats iron_plate", "inventory 7"},
	}
	for entry in expected {
		response := expect_command_ok(t, test, entry[0])
		testing.expectf(t, strings.contains(response.text, entry[1]), "%q lacks %q:\n%s", entry[0], entry[1], response.text)
	}
	expect_command_ok(t, test, "chapter 2")
	response := expect_command_ok(t, test, "query quests")
	testing.expect(t, strings.contains(response.text, "chapter 2\nobjective 1 "), response.text)
	expect_command_error(t, test, "query")
	expect_command_error(t, test, "query moon")
	expect_command_error(t, test, "query stats no_such_item")
	expect_command_error(t, test, "query veins 0")
}

// The field world's forms (work item 0183).

// A new field world of the default seed with its content and the socket's
// control. Heap allocated, since the context points into it.
Field_Command_Test :: struct {
	session: ^Session,
	game:    Game_Content,
	content: Simulation_Content,
	control: Command_Control,
}

make_field_command_test :: proc() -> ^Field_Command_Test {
	test := new(Field_Command_Test)
	test.game = make_field_test_game_content()
	test.session = start_field_test_session(test_field_game_config(), test.game)
	test.content = field_test_content(test.session, test.game)
	tick_field_command_test(test, 1)
	return test
}

destroy_field_command_test :: proc(test: ^Field_Command_Test) {
	end_session(test.session)
	delete(test.control.screenshot_path)
	free(test)
}

tick_field_command_test :: proc(test: ^Field_Command_Test, ticks: int) {
	for _ in 0 ..< ticks {
		tick_field_test_simulation(&test.session.simulation, test.content, {})
	}
}

run_field_command :: proc(test: ^Field_Command_Test, line: string) -> Command_Response {
	response, _ := execute_command_line(Command_Context{simulation = &test.session.simulation, content = test.content, control = &test.control}, line)
	return response
}

expect_field_command_ok :: proc(t: ^testing.T, test: ^Field_Command_Test, line: string, location := #caller_location) -> Command_Response {
	response := run_field_command(test, line)
	testing.expectf(t, response.ok, "%q: %s", line, response.text, loc = location)
	return response
}

// The line fails and its text holds wanted.
expect_field_command_error :: proc(t: ^testing.T, test: ^Field_Command_Test, line, wanted: string, location := #caller_location) {
	response := run_field_command(test, line)
	testing.expectf(t, !response.ok && strings.contains(response.text, wanted), "%q answered %v %q, wanted an error with %q", line, response.ok, response.text, wanted, loc = location)
}

field_command_body :: proc(test: ^Field_Command_Test) -> ^Field_Player {
	return &test.session.simulation.players[0].field
}

// The value after "<key> " on its line of a query answer.
answer_value :: proc(text, key: string) -> string {
	for line in strings.split_lines(text, context.temp_allocator) {
		if strings.has_prefix(line, key) && len(line) > len(key) && line[len(key)] == ' ' {
			return line[len(key) + 1:]
		}
	}
	return ""
}

f32_dot :: proc(first, second: [3]f32) -> f32 {
	return first.x * second.x + first.y * second.y + first.z * second.z
}

@(test)
test_decimal_words_parse_and_range_check :: proc(t: ^testing.T) {
	cases := [?]struct {
		word:  string,
		value: i64,
	}{{"1.5", 1500}, {"-0.001", -1}, {"83", 83000}, {"0.25", 250}, {"-12.34", -12340}}
	for entry in cases {
		value, ok := parse_decimal_word(entry.word)
		testing.expectf(t, ok && value == entry.value, "%q gave %d %v", entry.word, value, ok)
	}
	for bad in ([?]string{"1.2345", "abc", "", "-", ".5", "5.", "1e3", "+1", "1234567890123", "1.-5", "--1"}) {
		_, ok := parse_decimal_word(bad)
		testing.expectf(t, !ok, "%q parsed", bad)
	}
	_, problem := parse_ranged_decimal_word("90.001", -90000, 90000, "the latitude")
	testing.expect_value(t, problem, "the latitude must be a number from -90 to 90 with up to three decimals")
	value, within := parse_ranged_decimal_word("-90", -90000, 90000, "the latitude")
	testing.expect(t, within == "" && value == -90000)
	testing.expect_value(t, millidegrees_to_angle_units(90_000), i32(ANGLE_UNITS_PER_QUARTER))
	testing.expect_value(t, millidegrees_to_angle_units(-30_000), i32(-5461))
}

@(test)
test_angle_of_sine_inverts_the_fixed_sine :: proc(t: ^testing.T) {
	for angle := i32(-ANGLE_UNITS_PER_QUARTER); angle <= ANGLE_UNITS_PER_QUARTER; angle += 97 {
		found := angle_of_sine(fixed_sine(angle))
		testing.expectf(t, abs(found - angle) <= 1, "angle %d gave %d", angle, found)
	}
	testing.expect_value(t, angle_of_sine(UNIT_VECTOR_ONE), i32(ANGLE_UNITS_PER_QUARTER))
	testing.expect_value(t, angle_of_sine(-UNIT_VECTOR_ONE), i32(-ANGLE_UNITS_PER_QUARTER))
	testing.expect_value(t, angle_of_sine(2 * UNIT_VECTOR_ONE), i32(ANGLE_UNITS_PER_QUARTER))
	testing.expect_value(t, angle_of_sine(0), i32(0))
}

@(test)
test_field_query_player_answers_the_field_body :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	text := expect_field_command_ok(t, test, "query player").text
	body := field_command_body(test)
	testing.expectf(t, strings.contains(text, fmt.tprintf("\nposition %s\n", metres_text(body.position))), "%s", text)
	// The cabin lies within a few metres of the default seed's home, 83
	// 132, which 0180 does not move.
	latitude, latitude_ok := parse_decimal_word(answer_value(text, "latitude")[:len(answer_value(text, "latitude")) - 1])
	longitude, longitude_ok := parse_decimal_word(answer_value(text, "longitude")[:len(answer_value(text, "longitude")) - 1])
	testing.expectf(t, latitude_ok && abs(latitude - 83_000) < 100 && longitude_ok && abs(longitude - 132_000) < 100, "%s", text)
	height, height_ok := parse_decimal_word(answer_value(text, "height"))
	testing.expectf(t, height_ok && height > 0 && height < 20_000, "height %q", answer_value(text, "height"))
	for line in ([?]string{"\ncamera first", "\ncrouch_held false", "\nflying false", "\nhotbar_slot 1", "\ntool "}) {
		testing.expectf(t, strings.contains(text, line), "%q missing from %s", line, text)
	}
	testing.expectf(t, !strings.contains(text, "\nblock "), "%s", text)
}

@(test)
test_field_query_world_veins_entities_and_frames :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	pod, frame, found := find_test_pod(&test.session.simulation.world.entities, test.content.machines)
	testing.expect(t, found)
	world := expect_field_command_ok(t, test, "query world").text
	for line in ([?]string{"\nhome 83 132", fmt.tprintf("\npod frame %d ", frame.id), "\nfield_chunks "}) {
		testing.expectf(t, strings.contains(world, line), "%q missing from %s", line, world)
	}
	testing.expectf(t, !strings.contains(world, "\npad "), "%s", world)
	veins := expect_field_command_ok(t, test, "query veins").text
	lines := strings.split_lines(veins, context.temp_allocator)
	testing.expectf(t, len(lines) == 4 && lines[0] == "veins", "%s", veins)
	for type_id in ([?]string{"iron", "copper", "coal"}) {
		listed := false
		for line in lines[1:] {
			if strings.has_prefix(line, fmt.tprintf("vein %s ", type_id)) && strings.contains(line, " layer surface ") {
				listed = true
				words := strings.fields(line, context.temp_allocator)
				for word, index in words {
					if word == "distance" {
						distance, ok := parse_decimal_word(words[index + 1])
						testing.expectf(t, ok && distance < 100_000, "%s", line)
					}
				}
			}
		}
		testing.expectf(t, listed, "no %s vein in %s", type_id, veins)
	}
	entities := expect_field_command_ok(t, test, "query entities pod").text
	testing.expectf(t, strings.has_prefix(entities, "entities 1\n"), "%s", entities)
	testing.expectf(t, strings.contains(entities, fmt.tprintf("entity pod frame %d cell %d %d %d ", frame.id, pod.origin.x, pod.origin.y, pod.origin.z)), "%s", entities)
	everything := expect_field_command_ok(t, test, "query entities").text
	testing.expectf(t, !strings.contains(everything, "drop_capsule"), "%s", everything)
	frames := expect_field_command_ok(t, test, "query frames").text
	testing.expectf(t, strings.contains(frames, fmt.tprintf("\nframe %d origin ", frame.id)) && strings.contains(frames, " pitch 500 "), "%s", frames)
}

// Work item 0262: a new field world holds no drop capsule, so the listing
// holds the pod's frame only.
@(test)
test_field_query_entities_lists_only_the_pod_frame :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	_, frame, found := find_test_pod(&test.session.simulation.world.entities, test.content.machines)
	testing.expect(t, found)
	everything := expect_field_command_ok(t, test, "query entities").text
	lines := strings.split_lines(everything, context.temp_allocator)
	for line in lines[1:] {
		testing.expectf(t, strings.contains(line, fmt.tprintf(" frame %d ", frame.id)), "%s", line)
		testing.expectf(t, !strings.contains(line, "drop_capsule"), "%s", line)
	}
	capsules := expect_field_command_ok(t, test, "query entities capsule").text
	testing.expect_value(t, capsules, "entities 0")
	testing.expect_value(t, pool_alive_count(test.session.simulation.world.entities.capsules), 0)
}

@(test)
test_field_teleport_to_a_surface_point_lands_on_the_ground :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	home := test.session.simulation.world.planet.home
	response := expect_field_command_ok(t, test, fmt.tprintf("teleport %d %d.5", home.latitude_degrees, home.longitude_degrees + 1))
	latitude, _, _ := field_feet_coordinates(field_command_body(test).position)
	testing.expectf(t, abs(latitude - f64(home.latitude_degrees)) < 0.006, "latitude %f: %s", latitude, response.text)
	generation := test.session.simulation.field.world.water_planet.generation
	direction := planet_direction_at(millidegrees_to_angle_units(i64(home.latitude_degrees) * 1000), millidegrees_to_angle_units(i64(home.longitude_degrees) * 1000 + 1500))
	surface := field_surface_under(generation, World_Position(fixed_scale(direction, generation.radius)), 0)
	clearance := metres_between(surface, field_command_body(test).position)
	testing.expectf(t, abs(clearance - 0.25) < 0.001, "the feet are %f m over the surface", clearance)
	landed := false
	for _ in 0 ..< 60 {
		tick_field_command_test(test, 1)
		if field_command_body(test).on_ground {
			landed = true
			break
		}
	}
	body := field_command_body(test)
	along_up := f64(fixed_dot(cast([3]i64)(body.position - surface), body.up)) / POSITION_UNITS_PER_METRE
	testing.expectf(t, landed && abs(along_up) < 0.3, "landed %v, %f m over the surface", landed, along_up)
}

@(test)
test_field_teleport_to_metres_and_to_the_pod :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	body := field_command_body(test)
	words := strings.fields(metres_text(body.position + {2 * POSITION_UNITS_PER_METRE, 0, 0}), context.temp_allocator)
	expected, problem := parse_metres_words(words, "a position")
	testing.expect_value(t, problem, "")
	expect_field_command_ok(t, test, fmt.tprintf("teleport %s %s %s", words[0], words[1], words[2]))
	testing.expect_value(t, body.position, expected)
	testing.expect_value(t, body.previous_position, expected)
	expect_field_command_ok(t, test, "teleport pod")
	pod, frame, _ := find_test_pod(&test.session.simulation.world.entities, test.content.machines)
	testing.expect(t, feet_in_test_cabin(frame, pod, test.content.machines.machines[pod.machine], body^), "teleport pod stands the feet in the cabin")
	expect_field_command_error(t, test, "teleport pad", NO_BLOCK_WORLD_PROBLEM)
	expect_field_command_error(t, test, "teleport 91 0", "the latitude must be a number from -90 to 90")
	expect_field_command_error(t, test, "teleport 0 0 99999999", "a position must be a number")
}

@(test)
test_field_look_sets_the_bearing_and_the_camera_follows :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	response := expect_field_command_ok(t, test, "look 90 -30")
	testing.expect_value(t, response.text, "yaw 90.0 pitch -30.0")
	body := field_command_body(test)
	for pass in 0 ..< 2 {
		testing.expectf(t, abs(field_player_bearing_degrees(body^) - 90) < 0.1, "pass %d: bearing %f", pass, field_player_bearing_degrees(body^))
		testing.expect_value(t, body.pitch, millidegrees_to_angle_units(-30_000))
		tick_field_command_test(test, 1)
	}
	view := field_player_view(body^, test.session.field_content.tuning, 1, 0)
	camera := field_camera(view, .First_Person, THIRD_PERSON_DISTANCE, 0.6, 70)
	look := camera.target - camera.position
	north := unit_vector_to_f32(frame_north_tangent(body.up))
	east := unit_vector_to_f32(fixed_cross(frame_north_tangent(body.up), body.up))
	up := unit_vector_to_f32(body.up)
	testing.expectf(t, abs(f32_dot(look, north)) < 0.01, "north %f", f32_dot(look, north))
	testing.expectf(t, abs(f32_dot(look, east) - math.cos(f32(math.PI) / 6)) < 0.01, "east %f", f32_dot(look, east))
	testing.expectf(t, abs(f32_dot(look, up) + 0.5) < 0.01, "up %f", f32_dot(look, up))
	// A heading a hair west of north reads 0.0, never 360.0.
	set_field_look(body, -1, 0)
	testing.expect_value(t, fmt.tprintf("%.1f", field_player_bearing_degrees(body^)), "0.0")
	query := expect_field_command_ok(t, test, "query player").text
	testing.expectf(t, strings.contains(query, "\nyaw 0.0\n"), "%s", query)
	expect_field_command_error(t, test, "look 0 95", "the pitch must be a number from -89 to 89")
	expect_field_command_error(t, test, "look 0 x", "the pitch must be a number")
}

@(test)
test_field_look_at_a_point_faces_it :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	move_test_players_out_of_the_pod(&test.session.simulation, test.content.machines)
	tick_field_command_test(test, 1)
	entities := expect_field_command_ok(t, test, "query entities pod").text
	centre := strings.fields(entities[max(strings.index(entities, " centre "), 0):], context.temp_allocator)
	testing.expectf(t, len(centre) == 4 && centre[0] == "centre", "%s", entities)
	expect_field_command_ok(t, test, fmt.tprintf("look at %s %s %s", centre[1], centre[2], centre[3]))
	target, _ := parse_metres_words(centre[1:], "a position")
	body := field_command_body(test)
	tuning := test.session.field_content.tuning
	towards, _ := normalize_fixed(cast([3]i64)(target - field_player_eye(body^, tuning)))
	look := field_look_direction(body.forward, body.up, body.yaw, body.pitch)
	cosine := f64(fixed_dot(towards, look)) / UNIT_VECTOR_ONE
	testing.expectf(t, cosine > math.cos(math.to_radians(f64(1))), "the look is %f degrees off the pod's centre", math.to_degrees(math.acos(min(cosine, 1))))
	eye := strings.fields(metres_text(field_player_eye(body^, tuning)), context.temp_allocator)
	expect_field_command_error(t, test, fmt.tprintf("look at %s %s %s", eye[0], eye[1], eye[2]), "the point is at the eye")
}

@(test)
test_field_camera_third_is_pulled_in_in_the_cabin :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	tick_field_command_test(test, 3)
	body := field_command_body(test)
	testing.expect_value(t, expect_field_command_ok(t, test, "camera third").text, "camera third")
	testing.expect_value(t, body.camera_mode, Camera_Mode.Third_Person)
	view := field_player_view(body^, test.session.field_content.tuning, 1, 0)
	eye := world_position_to_metres(view.eye)
	pulled := pulled_in_field_camera(&test.session.simulation, test.session.field_content, view, .Third_Person, THIRD_PERSON_DISTANCE, 0.6, 70)
	free := field_camera(view, .Third_Person, THIRD_PERSON_DISTANCE, 0.6, 70)
	pulled_distance, free_distance := math.sqrt(f32_dot(pulled.position - eye, pulled.position - eye)), math.sqrt(f32_dot(free.position - eye, free.position - eye))
	testing.expectf(t, pulled_distance <= free_distance - 0.5, "pulled %f m from the eye, free %f m", pulled_distance, free_distance)
	expect_field_command_ok(t, test, "camera first")
	testing.expect_value(t, body.camera_mode, Camera_Mode.First_Person)
	testing.expect(t, pulled_in_field_camera(&test.session.simulation, test.session.field_content, view, .First_Person, THIRD_PERSON_DISTANCE, 0.6, 70) == field_camera(view, .First_Person, THIRD_PERSON_DISTANCE, 0.6, 70))
	expect_field_command_error(t, test, "camera side", "usage: camera <first|third>")
}

@(test)
test_field_crouch_holds_and_releases :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	move_test_players_out_of_the_pod(&test.session.simulation, test.content.machines)
	tick_field_command_test(test, 1)
	body := field_command_body(test)
	tuning := test.session.field_content.tuning
	testing.expect_value(t, expect_field_command_ok(t, test, "crouch on").text, "crouch on")
	tick_field_command_test(test, 1)
	testing.expect(t, body.crouching, "crouch on crouches")
	testing.expect_value(t, field_player_eye(body^, tuning), body.position + World_Position(fixed_scale(body.up, tuning.crouch_eye_height)))
	tick_field_command_test(test, 10)
	testing.expect(t, body.crouching, "the crouch holds with no input")
	expect_field_command_ok(t, test, "crouch off")
	tick_field_command_test(test, 1)
	testing.expect(t, !body.crouching, "crouch off stands")
	expect_field_command_ok(t, test, "fly on")
	expect_field_command_ok(t, test, "crouch on")
	tick_field_command_test(test, 1)
	testing.expect(t, !body.crouching, "no crouch while flying")
	expect_field_command_error(t, test, "crouch maybe", "usage: crouch <on|off>")
}

@(test)
test_field_fly_and_noclip_act_on_the_field_body :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	player := &test.session.simulation.players[0]
	expect_field_command_ok(t, test, "fly on")
	testing.expect(t, player.field.flying)
	testing.expect(t, !player.flying, "the block body stays as it is")
	expect_field_command_ok(t, test, "fly on")
	testing.expect(t, player.field.flying, "fly on again changes nothing")
	expect_field_command_ok(t, test, "noclip on")
	testing.expect(t, player.field.no_clip)
	text := expect_field_command_ok(t, test, "query player").text
	testing.expectf(t, strings.contains(text, "\nflying true\n") && strings.contains(text, "\nno_clip true\n"), "%s", text)
	expect_field_command_ok(t, test, "fly off")
	testing.expect(t, !player.field.flying)
}

@(test)
test_field_place_on_a_frame_cell :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	state := &test.session.simulation
	move_test_players_out_of_the_pod(state, test.content.machines)
	tick_field_command_test(test, 1)
	_, frame, _ := find_test_pod(&state.world.entities, test.content.machines)
	// Two cells outside the pod's +x side, or its -x side when the moved
	// player stands there.
	x, beyond := i32(8), i32(9)
	if field_placement_buries_a_player(state, test.session.field_content.tuning, frame, {8, 0, 0}) {
		x, beyond = -7, -8
	}
	items := test.content.items
	chest_item, foundation_item := test_item(items, "wooden_chest"), test_item(items, "wooden_foundation")
	chests, foundations := inventory_count(state.players[0].inventory, chest_item), inventory_count(state.players[0].inventory, foundation_item)
	expect_field_command_ok(t, test, fmt.tprintf("place wooden_foundation %d %d -1 0 0", frame.id, x))
	response := expect_field_command_ok(t, test, fmt.tprintf("place wooden_chest %d %d 0 0 0", frame.id, x))
	testing.expect_value(t, response.text, fmt.tprintf("placed wooden_chest on frame %d at %d 0 0", frame.id, x))
	handle, _ := frame_occupant(&state.world.entities.frames, frame.id, {x, 0, 0})
	testing.expect_value(t, entity_from_occupant(handle.handle).kind, Entity_Kind.Chest)
	testing.expect_value(t, inventory_count(state.players[0].inventory, chest_item), chests)
	testing.expect_value(t, inventory_count(state.players[0].inventory, foundation_item), foundations)
	expect_field_command_error(t, test, fmt.tprintf("place wooden_chest %d %d 0 0 0", frame.id, x), "a cell of the footprint is taken")
	expect_field_command_error(t, test, fmt.tprintf("place wooden_chest %d %d 0 0 0", frame.id, beyond), "a bottom cell has no solid cell under it")
	expect_field_command_error(t, test, fmt.tprintf("place wooden_chest %d 0 0 0 0", frame.id), "a cell of the footprint is taken")
	expect_field_command_error(t, test, "place wooden_chest 0 8 0 0 0", NO_BLOCK_WORLD_PROBLEM)
	expect_field_command_error(t, test, "place wooden_chest 999 8 0 0 0", "no frame 999")
	expect_field_command_error(t, test, fmt.tprintf("place belt %d %d 1 0 0", frame.id, x), "belt is not placed on a frame")
	expect_field_command_error(t, test, fmt.tprintf("place wooden_chest %d %d 1 0 4", frame.id, x), "the rotation must be a number from 0 to 3")
	expect_field_command_error(t, test, fmt.tprintf("place wooden_chest %d %d 0 0", frame.id, x), "usage: place <machine> <frame>")
	listed := expect_field_command_ok(t, test, "query entities chest").text
	testing.expectf(t, strings.contains(listed, fmt.tprintf("entity wooden_chest frame %d cell %d 0 0 ", frame.id, x)), "%s", listed)
}

// Work item 0274: insert with a frame fills the machine at a frame's
// cell; an empty cell and frame 0 are refused.
@(test)
test_field_insert_into_a_frame_machine :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	state := &test.session.simulation
	move_test_players_out_of_the_pod(state, test.content.machines)
	tick_field_command_test(test, 1)
	_, frame, _ := find_test_pod(&state.world.entities, test.content.machines)
	x := i32(8)
	if field_placement_buries_a_player(state, test.session.field_content.tuning, frame, {8, 0, 0}) {
		x = -7
	}
	expect_field_command_ok(t, test, fmt.tprintf("place wooden_foundation %d %d -1 0 0", frame.id, x))
	expect_field_command_ok(t, test, fmt.tprintf("place wooden_chest %d %d 0 0 0", frame.id, x))
	response := expect_field_command_ok(t, test, fmt.tprintf("insert coal 5 %d %d 0 0", frame.id, x))
	testing.expect_value(t, response.text, fmt.tprintf("frame %d at %d 0 0", frame.id, x))
	handle, _ := frame_occupant(&state.world.entities.frames, frame.id, {x, 0, 0})
	chest := pool_get(&state.world.entities.chests, entity_from_occupant(handle.handle))
	testing.expect(t, chest != nil, "the chest stands there")
	if chest != nil {
		testing.expect_value(t, chest.slots[0], Item_Stack{test_item(test.content.items, "coal"), 5})
	}
	expect_field_command_error(t, test, fmt.tprintf("insert coal 5 %d %d 1 0", frame.id, x), "no entity there")
	expect_field_command_error(t, test, fmt.tprintf("insert coal 5 0 %d 0 0", x), NO_BLOCK_WORLD_PROBLEM)
	expect_field_command_error(t, test, fmt.tprintf("insert coal 0 %d %d 0 0", frame.id, x), "needs a count from 1")
}

@(test)
test_field_refuses_the_block_world_commands :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	for line in ([?]string{"teleport pad", "vein iron 0 0", "remove 0 0 0", "block stone 0 0 0", "insert coal 1 0 0 0", "recipe nothing 0 0 0", "filter coal 0 0 0", "blueprint /nonexistent"}) {
		response := run_field_command(test, line)
		testing.expectf(t, !response.ok && response.text == NO_BLOCK_WORLD_PROBLEM, "%q answered %v %q", line, response.ok, response.text)
	}
}

@(test)
test_block_world_refuses_the_field_commands :: proc(t: ^testing.T) {
	test := make_command_test()
	defer destroy_command_test(test)
	for line in ([?]string{"look 0 0", "look at 0 0 0", "crouch on", "teleport pod", "teleport 10 20", "query frames"}) {
		response := expect_command_error(t, test, line)
		testing.expectf(t, response.text == NO_FIELD_WORLD_PROBLEM, "%q answered %q", line, response.text)
	}
	expect_command_ok(t, test, "camera third")
	testing.expect_value(t, test.simulation.players[0].camera_mode, Camera_Mode.Third_Person)
	testing.expect_value(t, expect_command_ok(t, test, "teleport 3 20 -4").text, "at 3.50 20.00 -3.50")
	text := expect_command_ok(t, test, "query player").text
	testing.expectf(t, strings.contains(text, "\nblock "), "%s", text)
}

// Work item 0223: seat sit puts the body in the pod's chair, its eye on
// the seat's, and query player says so; seat stand stands it; both are
// refused while the world falls.
@(test)
test_the_seat_command_sits_and_stands :: proc(t: ^testing.T) {
	test := make_field_command_test()
	defer destroy_field_command_test(test)
	testing.expectf(t, strings.contains(expect_field_command_ok(t, test, "query player").text, "\nseat standing"), "standing at the start")
	testing.expect_value(t, expect_field_command_ok(t, test, "seat sit").text, "seat seated")
	testing.expectf(t, strings.contains(expect_field_command_ok(t, test, "query player").text, "\nseat seated"), "seated after seat sit")
	pod, frame, found := find_pod(&test.session.simulation.world.entities, test.content.machines)
	testing.expect(t, found)
	body := field_command_body(test)
	testing.expect_value(t, field_player_eye(body^, test.content.field.tuning), pod_seat_eye(frame, pod, test.content.machines.machines[pod.machine]))
	testing.expect_value(t, expect_field_command_ok(t, test, "seat stand").text, "seat standing")
	testing.expect_value(t, body.seat, Field_Seat.Standing)
	expect_field_command_error(t, test, "seat lie", "usage: seat <stand|sit>")
	test.session.simulation.field.arrival = {start_tick = test.session.simulation.tick, fall_ticks = 600}
	expect_field_command_error(t, test, "seat sit", "the world is falling")
	testing.expect_value(t, body.seat, Field_Seat.Standing)
}
