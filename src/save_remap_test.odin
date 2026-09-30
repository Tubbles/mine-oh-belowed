package game

import "core:fmt"
import "core:strings"
import "core:testing"

// Content remapping (work item 0047): the save test's world is saved with
// the shipped game data and loaded with a changed copy. Only the loaded
// state is checked; the changed copies keep the ids other registries
// hold, so they are not run.

// Two runs of hand crafts queued, the save test's world otherwise.
queue_save_test_crafts :: proc(simulation: ^Simulation_State, content: Simulation_Content) {
	crafting := &simulation.players[0].crafting
	crafting.runs[0] = {test_recipe(content.recipes, "stick"), 3}
	crafting.runs[1] = {test_recipe(content.recipes, "plank"), 2}
	crafting.count = 2
}

// The save test's site after 300 ticks, saved under directory.
save_remap_test_original :: proc(t: ^testing.T, content: Simulation_Content, directory: string) -> Simulation_State {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	original := make_save_test_simulation(&generator, content)
	load_save_test_chunks(&original.world, &generator)
	build_save_test_site(&original, content)
	run_save_test_ticks(&original, content, 0, 300)
	queue_save_test_crafts(&original, content)
	testing.expect_value(t, save_world(&original, content, save_test_location(directory), 1_700_000_000), "")
	return original
}

with_inserted :: proc(values: []$T, index: int, value: T) -> []T {
	result := make([]T, len(values) + 1, context.temp_allocator)
	copy(result, values[:index])
	result[index] = value
	copy(result[index + 1:], values[index:])
	return result
}

without :: proc(values: []$T, index: int) -> []T {
	result := make([]T, len(values) - 1, context.temp_allocator)
	copy(result, values[:index])
	copy(result[index:], values[index + 1:])
	return result
}

// The problem loading the save with content reports.
save_test_load_problem :: proc(location: Save_Location, content: Simulation_Content) -> string {
	directory, _ := existing_save_directory(location)
	file, _ := read_world_file(directory, context.temp_allocator)
	loaded, problem := make_simulation_from_save(test_game_config(), player_start_on({}), content, SAVE_TEST_LANDING_PAD, directory, file)
	destroy_simulation(&loaded)
	return problem
}

saved_stack_text :: proc(items: Item_Registry, stack: Item_Stack) -> string {
	if stack_is_empty(stack) {
		return ""
	}
	if int(stack.item) >= len(items.items) {
		return "unknown item"
	}
	return fmt.tprintf("%s x%d", items.items[stack.item].id, stack.count)
}

// Every stack of every entity and player, in pool order.
world_stacks :: proc(state: ^Simulation_State) -> []Item_Stack {
	stacks := make([dynamic]Item_Stack, context.temp_allocator)
	entities := &state.world.entities
	for &entry in entities.chests.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.furnaces.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.capsules.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.inserters.entries {
		append(&stacks, ..entry.slots[:])
		append(&stacks, entry.held)
	}
	for &entry in entities.drills.entries {
		append(&stacks, ..entry.slots[:])
		append(&stacks, entry.held)
	}
	for &entry in entities.fluid_machines.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.assemblers.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.labs.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.schematic_crates.entries {
		append(&stacks, ..entry.slots[:])
	}
	for &entry in entities.launch_pads.entries {
		append(&stacks, ..entry.slots[:])
	}
	for player in state.players {
		append(&stacks, ..player.inventory.slots)
		append(&stacks, player.held.stack)
	}
	return stacks[:]
}

belt_item_ids :: proc(state: ^Simulation_State, items: Item_Registry) -> []string {
	ids := make([dynamic]string, context.temp_allocator)
	for record in belt_cell_items(&state.world.entities) {
		append(&ids, items.items[record.item].id)
	}
	return ids[:]
}

// Every stack of original holds in loaded the same item and count, except
// stacks of removed_item, which are empty.
expect_stacks_kept :: proc(t: ^testing.T, original, loaded: ^Simulation_State, original_items, loaded_items: Item_Registry, removed_item := "") {
	original_stacks, loaded_stacks := world_stacks(original), world_stacks(loaded)
	testing.expect_value(t, len(loaded_stacks), len(original_stacks))
	held, removed := 0, 0
	for stack, index in original_stacks {
		expected := saved_stack_text(original_items, stack)
		if removed_item != "" && strings.has_prefix(expected, fmt.tprintf("%s x", removed_item)) {
			expected = ""
			removed += 1
		}
		held += expected == "" ? 0 : 1
		if index < len(loaded_stacks) {
			testing.expect_value(t, saved_stack_text(loaded_items, loaded_stacks[index]), expected)
		}
	}
	testing.expect(t, held > 10, "the site holds stacks")
	testing.expect(t, removed_item == "" || removed > 0, "the site holds the removed item")
}

@(test)
test_an_inserted_item_keeps_every_stack_and_statistic :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	changed := content
	changed.items.items = with_inserted(content.items.items, 0, Item{id = "inserted_item"})
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	expect_stacks_kept(t, &original, &loaded, content.items, changed.items)
	original_belt := belt_item_ids(&original, content.items)
	testing.expect(t, len(original_belt) > 0)
	loaded_belt := belt_item_ids(&loaded, changed.items)
	testing.expect_value(t, len(loaded_belt), len(original_belt))
	for id, index in original_belt {
		if index < len(loaded_belt) {
			testing.expect_value(t, loaded_belt[index], id)
		}
	}
	statistics, original_statistics := loaded.world.statistics, original.world.statistics
	testing.expect_value(t, statistics.produced[0], 0)
	testing.expect_value(t, statistics.obtained[0], 0)
	for count, item in original_statistics.produced {
		testing.expect_value(t, statistics.produced[item + 1], count)
		testing.expect_value(t, statistics.consumed[item + 1], original_statistics.consumed[item])
		testing.expect_value(t, loaded.unlocks.obtained[item + 1], original.unlocks.obtained[item])
	}
	ring := original_statistics.produced_rates.per_second
	for bucket in 0 ..< len(ring) {
		testing.expect_value(t, statistics.produced_rates.per_second[bucket + RATE_BUCKET_COUNT], ring[bucket])
	}
}

@(test)
test_a_removed_item_empties_its_stacks :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	hematite := test_item(content.items, "hematite")
	changed := content
	changed.items.items = without(content.items.items, int(hematite))
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	expect_stacks_kept(t, &original, &loaded, content.items, changed.items, "hematite")
	coal := test_item(content.items, "coal")
	testing.expect_value(t, loaded.world.statistics.consumed[test_item(changed.items, "coal")], original.world.statistics.consumed[coal])
}

recipe_id :: proc(recipes: Recipe_Registry, recipe: int) -> string {
	return recipe == NO_RECIPE ? "" : recipes.recipes[recipe].id
}

@(test)
test_an_inserted_recipe_keeps_queues_and_machine_recipes :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	changed := content
	changed.recipes.recipes = with_inserted(content.recipes.recipes, 0, Recipe{id = "inserted_recipe"})
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	original_queue, loaded_queue := original.players[0].crafting, loaded.players[0].crafting
	testing.expect_value(t, loaded_queue.count, original_queue.count)
	for run, position in original_queue.runs[:original_queue.count] {
		testing.expect_value(t, recipe_id(changed.recipes, loaded_queue.runs[position].recipe), recipe_id(content.recipes, run.recipe))
		testing.expect_value(t, loaded_queue.runs[position].count, run.count)
	}
	set := 0
	for assembler, index in original.world.entities.assemblers.entries {
		set += assembler.recipe == NO_RECIPE ? 0 : 1
		testing.expect_value(t, recipe_id(changed.recipes, loaded.world.entities.assemblers.entries[index].recipe), recipe_id(content.recipes, assembler.recipe))
	}
	testing.expect(t, set > 0, "an assembler has a recipe")
	for furnace, index in original.world.entities.furnaces.entries {
		testing.expect_value(t, recipe_id(changed.recipes, loaded.world.entities.furnaces.entries[index].recipe), recipe_id(content.recipes, furnace.recipe))
	}
	testing.expect(t, loaded.unlocks.schematics_found[test_recipe(changed.recipes, "slag_concrete")])
}

@(test)
test_an_inserted_technology_keeps_research :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	changed := content
	changed.technologies.technologies = with_inserted(content.technologies.technologies, 0, Technology{id = "inserted_technology"})
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	research := loaded.world.research
	testing.expect(t, research.queued)
	testing.expect_value(t, changed.technologies.technologies[research.technology].id, "automation")
	testing.expect_value(t, research.units_done, original.world.research.units_done)
	testing.expect_value(t, research.levels[test_technology(changed.technologies, "mining_productivity")], 2)
	testing.expect_value(t, research.levels[0], 0)
	for researched, technology in original.unlocks.researched {
		testing.expect_value(t, loaded.unlocks.researched[technology + 1], researched)
	}
}

@(test)
test_an_inserted_quest_keeps_the_active_quest_and_progress :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	changed := content
	changed.quests.quests = with_inserted(content.quests.quests, 0, Quest{id = "inserted_quest"})
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	testing.expect(t, original.quests.active != NO_QUEST)
	testing.expect_value(t, changed.quests.quests[loaded.quests.active].id, content.quests.quests[original.quests.active].id)
	testing.expect_value(t, loaded.quests.progress[0], Quest_Progress{})
	for progress, quest in original.quests.progress {
		testing.expect_value(t, loaded.quests.progress[quest + 1], progress)
	}
	testing.expect_value(t, len(loaded.quests.messages), len(original.quests.messages))
}

@(test)
test_a_removed_contract_frees_its_open_slot :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	open := open_contracts(&original.world.contracts)
	testing.expect_value(t, len(open), MAXIMUM_OPEN_CONTRACTS)
	removed := int(open[0].contract)
	changed := content
	changed.contracts.contracts = without(content.contracts.contracts, removed)
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	loaded_open := open_contracts(&loaded.world.contracts)
	testing.expect_value(t, len(loaded_open), len(open) - 1)
	for entry, index in loaded_open {
		kept := open[index + 1]
		testing.expect_value(t, changed.contracts.contracts[entry.contract].id, content.contracts.contracts[kept.contract].id)
		testing.expect_value(t, entry.delivered, kept.delivered)
	}
	for count, contract in original.world.contracts.offer_counts[:len(content.contracts.contracts)] {
		if contract != removed {
			testing.expect_value(t, loaded.world.contracts.offer_counts[contract > removed ? contract - 1 : contract], count)
		}
	}
}

@(test)
test_an_inserted_block_keeps_every_saved_chunk :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)

	changed := content
	changed.blocks.definitions = with_inserted(content.blocks.definitions, 1, Block_Definition{id = "inserted_block"})
	loaded := load_save_test_simulation(t, save_test_location(directory), changed)
	defer destroy_simulation(&loaded)
	testing.expect_value(t, len(loaded.world.saved_chunks), modified_chunk_count(&original.world))
	blocks := new([CHUNK_BLOCK_COUNT]Block_Id, context.temp_allocator)
	for coordinate, bytes in loaded.world.saved_chunks {
		testing.expect(t, deserialize_chunk_blocks(bytes, blocks))
		differing := 0
		for block, index in original.world.chunks[coordinate].blocks {
			differing += changed.blocks.definitions[blocks[index]].id == content.blocks.definitions[block].id ? 0 : 1
		}
		testing.expectf(t, differing == 0, "chunk %v has %d blocks changed", coordinate, differing)
	}
	gold_quartz := test_block(content.blocks, "gold_quartz")
	testing.expect_value(t, gold_quartz + 1, test_block(changed.blocks, "gold_quartz"))
}

// What cannot be dropped refuses the file, naming the id.
@(test)
test_vanished_machines_blocks_and_vein_types_refuse :: proc(t: ^testing.T) {
	content := make_save_test_content()
	directory := make_save_test_directory()
	defer remove_save_test_directory(directory)
	original := save_remap_test_original(t, content, directory)
	defer destroy_simulation(&original)
	location := save_test_location(directory)

	changed := content
	changed.machines.machines = without(content.machines.machines, int(test_machine(content.machines, "lab")))
	problem := save_test_load_problem(location, changed)
	testing.expect(t, strings.contains(problem, "placed lab machines"), problem)

	changed = content
	changed.blocks.definitions = without(content.blocks.definitions, int(test_block(content.blocks, "gold_quartz")))
	problem = save_test_load_problem(location, changed)
	testing.expect(t, strings.contains(problem, "block gold_quartz"), problem)

	vein_type := original.world.veins[0].type
	changed = content
	changed.veins.types = without(content.veins.types, vein_type)
	problem = save_test_load_problem(location, changed)
	testing.expect(t, strings.contains(problem, fmt.tprintf("veins of type %s,", content.veins.types[vein_type].id)), problem)
}
