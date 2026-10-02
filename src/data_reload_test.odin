package game

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"
import "model_vox"
import "platform"

// Hot reload (work item 0054): the strings swap, the content loader, and
// the running world taken through the save codec under new content. The
// data directories are temporary copies of the shipped files, written and
// removed by the tests.

@(test)
test_a_bad_strings_file_is_refused_and_the_old_table_kept :: proc(t: ^testing.T) {
	table, error := parse_string_table(transmute([]byte)string(`hello = "Hi"`))
	defer destroy_string_table(&table)
	testing.expect_value(t, error, nil)
	lookup_text(&table, "missing")
	_, error = replace_string_entries(&table, transmute([]byte)string(`hello = "Hi`))
	testing.expect(t, error != nil)
	testing.expect_value(t, lookup_text(&table, "hello"), "Hi")
	testing.expect_value(t, len(table.reported_missing), 1)

	old_entries: map[string]string
	old_entries, error = replace_string_entries(&table, transmute([]byte)string(`hello = "Hello"`))
	testing.expect_value(t, error, nil)
	testing.expect_value(t, lookup_text(&table, "hello"), "Hello")
	testing.expect_value(t, old_entries["hello"], "Hi")
	testing.expect_value(t, len(table.reported_missing), 0)
	destroy_string_entries(old_entries)
}

// The shipped data files and models, with items.sjson and recipes.sjson
// as given.
write_test_data_directory :: proc(directory, items, recipes: string) {
	files := [?]struct {
		name: string,
		text: string,
	} {
		{BLOCKS_FILE_NAME, #load("../data/blocks.sjson", string)},
		{ITEMS_FILE_NAME, items},
		{FLUIDS_FILE_NAME, #load("../data/fluids.sjson", string)},
		{MACHINES_FILE_NAME, #load("../data/machines.sjson", string)},
		{RECIPES_FILE_NAME, recipes},
		{TECHNOLOGIES_FILE_NAME, #load("../data/technologies.sjson", string)},
		{CONTRACTS_FILE_NAME, #load("../data/contracts.sjson", string)},
		{NOTES_FILE_NAME, #load("../data/notes.sjson", string)},
		{DEVELOPER_KITS_FILE_NAME, #load("../data/dev_kits.sjson", string)},
		{TOUCH_OVERLAY_FILE_NAME, #load("../data/touch_overlay.sjson", string)},
		{BIOMES_FILE_NAME, #load("../data/biomes.sjson", string)},
		{TREES_FILE_NAME, #load("../data/trees.sjson", string)},
		{VEINS_FILE_NAME, #load("../data/veins.sjson", string)},
		{PLANETS_FILE_NAME, #load("../data/planets.sjson", string)},
		{"quests/chapter_01.sjson", #load("../data/quests/chapter_01.sjson", string)},
		{"quests/chapter_02.sjson", #load("../data/quests/chapter_02.sjson", string)},
		{"quests/chapter_03.sjson", #load("../data/quests/chapter_03.sjson", string)},
		{"quests/chapter_04.sjson", #load("../data/quests/chapter_04.sjson", string)},
		{"quests/chapter_05.sjson", #load("../data/quests/chapter_05.sjson", string)},
		{"quests/chapter_06.sjson", #load("../data/quests/chapter_06.sjson", string)},
		{"quests/chapter_07.sjson", #load("../data/quests/chapter_07.sjson", string)},
		{"quests/chapter_08.sjson", #load("../data/quests/chapter_08.sjson", string)},
	}
	for file in files {
		write_test_file(platform.join_path(directory, file.name), file.text)
	}
	copy_test_models(directory)
}

// The machines name the shipped model files, which must load.
copy_test_models :: proc(directory: string) {
	models_directory := platform.join_path(test_data_directory(), model_vox.MODELS_DIRECTORY)
	entries, error := os.read_all_directory_by_path(models_directory, context.temp_allocator)
	assert(error == nil)
	for entry in entries {
		data, read_error := os.read_entire_file(entry.fullpath, context.temp_allocator)
		assert(read_error == nil)
		write_test_file(platform.join_path(directory, model_vox.MODELS_DIRECTORY, entry.name), string(data))
	}
}

make_reload_test_directory :: proc() -> string {
	directory, error := os.make_directory_temp("", "mine-oh-belowed-reload-test-*", context.temp_allocator)
	assert(error == nil)
	return directory
}

// The save test's site after 300 ticks.
make_reload_test_world :: proc(content: Simulation_Content) -> Simulation_State {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	simulation := make_save_test_simulation(&generator, content)
	load_save_test_chunks(&simulation.world, &simulation.records, &generator)
	build_save_test_site(&simulation, content)
	run_save_test_ticks(&simulation, content, 0, 300)
	return simulation
}

@(test)
test_reloading_the_same_content_keeps_the_world :: proc(t: ^testing.T) {
	content := make_save_test_content()
	original := make_reload_test_world(content)
	defer destroy_simulation(&original)
	twin := make_reload_test_world(content)
	defer destroy_simulation(&twin)
	hash := simulation_state_hash(&original)
	testing.expect_value(t, simulation_state_hash(&twin), hash)
	chunk_count := len(original.world.chunks)

	reloaded, problem := reload_simulation(&original, content, content, test_game_config())
	defer destroy_simulation(&reloaded)
	testing.expect_value(t, problem, "")
	testing.expect_value(t, simulation_state_hash(&reloaded), hash)
	testing.expect_value(t, len(reloaded.world.chunks), chunk_count)
	testing.expect_value(t, len(original.world.chunks), 0)
	for _, chunk in reloaded.world.chunks {
		testing.expect(t, chunk.dirty, "a moved chunk is remeshed")
	}
	// The reloaded world runs on like the one that was never reloaded.
	run_save_test_ticks(&reloaded, content, 300, 500)
	run_save_test_ticks(&twin, content, 300, 500)
	testing.expect_value(t, simulation_state_hash(&reloaded), simulation_state_hash(&twin))
}

RELOAD_TEST_ITEM :: `	{id = "reload_test_item", name_key = "item_log", category = "raw", stack_size = 50, cannot_recycle = true, price = 1}`
RELOAD_TEST_RECIPE :: `	{id = "reload_test_recipe", inputs = [{item = "log", count = 1}], outputs = [{item = "reload_test_item", count = 1}], seconds = 0.5, made_in = ["hand"], category = "materials", tags = ["wood"], channel = "start"}`

// The shipped items with one inserted first, the shipped recipes with one
// making it.
changed_items_text :: proc() -> string {
	items, _ := strings.replace(#load("../data/items.sjson", string), "items = [\n", "items = [\n" + RELOAD_TEST_ITEM + "\n", 1, context.temp_allocator)
	return items
}

changed_recipes_text :: proc() -> string {
	recipes, _ := strings.replace(#load("../data/recipes.sjson", string), "recipes = [\n", "recipes = [\n" + RELOAD_TEST_RECIPE + "\n", 1, context.temp_allocator)
	return recipes
}

// The shipped strings as this thread's table, as main loads them.
@(deferred_out = end_reload_test_strings)
begin_reload_test_strings :: proc() -> ^String_Table {
	table := new(String_Table)
	error: json.Unmarshal_Error
	table^, error = parse_string_table(#load("../data/strings/en.sjson"))
	assert(error == nil)
	thread_string_table = table
	return table
}

end_reload_test_strings :: proc(table: ^String_Table) {
	thread_string_table = nil
	destroy_string_table(table)
	free(table)
}

@(test)
test_a_reload_with_an_inserted_item_keeps_stacks_and_makes_it_usable :: proc(t: ^testing.T) {
	table := begin_reload_test_strings()
	directory := make_reload_test_directory()
	defer os.remove_all(directory)
	write_test_data_directory(directory, changed_items_text(), changed_recipes_text())
	data, problem := load_game_data(directory, test_game_config(), table.entries)
	defer destroy_game_data(&data)
	testing.expect_value(t, problem, "")
	if problem != "" {
		return
	}
	new_content := data.content.simulation_content
	testing.expect_value(t, new_content.items.items[0].id, "reload_test_item")

	old_content := make_save_test_content()
	original := make_reload_test_world(old_content)
	defer destroy_simulation(&original)
	changes := content_table_changes(content_tables(old_content), content_tables(new_content))
	testing.expect_value(t, changes[.Items], Content_Table_Change{added = 1})
	testing.expect_value(t, changes[.Recipes], Content_Table_Change{added = 1})
	testing.expect_value(t, content_changes_text(changes), "items +1, recipes +1")

	reloaded: Simulation_State
	reloaded, problem = reload_simulation(&original, old_content, new_content, test_game_config())
	defer destroy_simulation(&reloaded)
	testing.expect_value(t, problem, "")
	expect_stacks_kept(t, &original, &reloaded, old_content.items, new_content.items)

	// The new item is crafted by hand from a log and lands in the inventory.
	player := &reloaded.players[0]
	item := test_item(new_content.items, "reload_test_item")
	log_item := test_item(new_content.items, "log")
	testing.expect_value(t, inventory_add(player.inventory, new_content.items, log_item, 1), 0)
	player.crafting = {}
	refusal, _ := queue_crafts(&player.crafting, player.inventory, new_content.recipes, reloaded.unlocks, test_recipe(new_content.recipes, "reload_test_recipe"), 1)
	testing.expect_value(t, refusal, Craft_Refusal.None)
	for _ in 0 ..< 60 {
		simulation_tick(&reloaded, new_content, {})
	}
	testing.expect_value(t, inventory_count(player.inventory, item), 1)
}

@(test)
test_a_failing_recipe_file_keeps_the_old_content :: proc(t: ^testing.T) {
	table := begin_reload_test_strings()
	directory := make_reload_test_directory()
	defer os.remove_all(directory)
	write_test_data_directory(directory, #load("../data/items.sjson", string), "recipes = [{id = ")
	data, problem := load_game_data(directory, test_game_config(), table.entries)
	testing.expect(t, strings.contains(problem, RECIPES_FILE_NAME), problem)
	testing.expect(t, data.arena == nil)
}

// A reload the running world cannot take (a placed machine or a loaded
// block gone) is refused and leaves the world as it was.
@(test)
test_a_refused_reload_leaves_the_world :: proc(t: ^testing.T) {
	content := make_save_test_content()
	original := make_reload_test_world(content)
	defer destroy_simulation(&original)
	hash := simulation_state_hash(&original)
	chunk_count := len(original.world.chunks)

	without_lab := content
	without_lab.machines.machines = without(content.machines.machines, int(test_machine(content.machines, "lab")))
	_, problem := reload_simulation(&original, content, without_lab, test_game_config())
	testing.expect(t, strings.contains(problem, "placed lab machines"), problem)

	without_stone := content
	without_stone.blocks.definitions = without(content.blocks.definitions, int(test_block(content.blocks, "stone")))
	_, problem = reload_simulation(&original, content, without_stone, test_game_config())
	testing.expect_value(t, problem, "a loaded chunk holds the block stone, which the new game data no longer has")

	testing.expect_value(t, len(original.world.chunks), chunk_count)
	testing.expect_value(t, simulation_state_hash(&original), hash)
}
