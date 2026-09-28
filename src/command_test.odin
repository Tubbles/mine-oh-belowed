package game

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"
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
	_, address_ok := unix_socket_address(strings.repeat("x", 200, context.temp_allocator))
	testing.expect(t, !address_ok)
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
		testing.expect_value(t, test.simulation.world.research.levels[infinite], level)
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
	expect_command_error(t, test, "fly maybe")
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
			load_chunk_now(&test.simulation.world, &test.generator, coordinate)
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
	produced := item_counter(test.simulation.world.statistics.produced, plates)
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

// A real socket: bind a temporary path, connect, send help, read the
// answer up to its terminating line.
@(test)
test_command_socket_round_trip :: proc(t: ^testing.T) {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-socket-test-*", context.temp_allocator)
	testing.expect(t, error == nil)
	defer os.remove_all(directory)
	path, _ := os.join_path({directory, "run", COMMAND_SOCKET_FILE_NAME}, context.temp_allocator)
	server := make_command_server()
	defer destroy_command_server(&server)
	testing.expect_value(t, open_command_server(&server, path), "")
	testing.expect(t, os.exists(path))

	address, _ := unix_socket_address(path)
	client := posix.socket(.UNIX, .STREAM)
	defer posix.close(client)
	testing.expect_value(t, posix.connect(client, (^posix.sockaddr)(&address), size_of(address)), posix.result.OK)
	message := "help\n# comment\n"
	testing.expect_value(t, int(posix.send(client, raw_data(message), len(message), {})), len(message))

	control: Command_Control
	command_context := Command_Context{control = &control}
	answered := 0
	for attempt := 0; attempt < 100 && answered < 2; attempt += 1 {
		poll_command_server(&server)
		for {
			queued := take_command_line(&server) or_break
			if response, empty := execute_command_line(command_context, queued.line); !empty {
				send_command_response(&server, queued.client, format_command_response(response))
			}
			answered += 1
			delete(queued.line)
		}
		flush_command_server(&server)
	}
	testing.expect_value(t, answered, 2)

	received := make([dynamic]byte, context.temp_allocator)
	buffer: [4096]byte
	for !strings.has_suffix(string(received[:]), "\n.\n") {
		count := posix.recv(client, &buffer[0], len(buffer), {})
		if count <= 0 {
			break
		}
		append(&received, ..buffer[:count])
	}
	text := string(received[:])
	testing.expect(t, strings.has_prefix(text, "ok commands\nhelp: "), text)
	testing.expect(t, strings.has_suffix(text, "\n.\n"), text)

	// A second server on the same path refuses while the first listens.
	second := make_command_server()
	defer destroy_command_server(&second)
	testing.expect(t, open_command_server(&second, path) != "")
	close_command_server(&server)
	testing.expect(t, !os.exists(path))
}
