package game

import "core:slice"
import "core:testing"

// Every item obtained, in the temp allocator, for tests of lines that
// read the names of discovered ores.
test_all_obtained :: proc(items: Item_Registry) -> []bool {
	obtained := make([]bool, len(items.items), context.temp_allocator)
	fill_bools(obtained, true)
	return obtained
}

use_shipped_strings :: proc() -> ^String_Table {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	pointer := new_clone(table, context.temp_allocator)
	thread_string_table = pointer
	return pointer
}

@(test)
test_block_name_keys_are_validated :: proc(t: ^testing.T) {
	table := use_shipped_strings()
	defer thread_string_table = nil
	blocks := make_test_registry()
	testing.expect_value(t, validate_block_name_keys(blocks.definitions, table.entries), "")
	unnamed := [?]Block_Definition{{id = "air"}, {id = "stone"}}
	testing.expect_value(t, validate_block_name_keys(unnamed[:], table.entries), `block "stone" has no name_key`)
	unknown := [?]Block_Definition{{id = "air"}, {id = "stone", name_key = "block_no_such_key"}}
	testing.expect_value(t, validate_block_name_keys(unknown[:], table.entries), `block "stone": name_key "block_no_such_key" is not in the string table`)
	testing.expect_value(t, block_display_name(blocks, test_block(blocks, "grass")), "Grass")
	testing.expect_value(t, block_display_name(blocks, AIR_BLOCK), "")
}

@(test)
test_discoverable_block_needs_a_drop :: proc(t: ^testing.T) {
	blocks := make_test_registry()
	blocks.definitions = slice.clone(blocks.definitions, context.temp_allocator)
	blocks.definitions[test_block(blocks, "landing_pad")].discoverable = true
	file, error := parse_items_file(#load("../data/items.sjson"), context.temp_allocator)
	assert(error == nil)
	_, problem := resolve_item_registry(file, blocks, context.temp_allocator)
	testing.expect_value(t, problem, `block "landing_pad" is discoverable but yields no item`)
}

@(test)
test_target_lines_name_blocks_and_hide_unknown_ores :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	obtained := make([]bool, len(content.items.items), context.temp_allocator)
	tier := highest_tool_tier(content.items.items)
	target := Raycast_Hit{hit = true, block = {0, 0, 0}}
	name, tool, vein := target_status_lines(&world, &records, content.machines, content.fluids, content.veins, content.blocks, content.items, obtained, tier, target)
	testing.expect_value(t, name, "Stone")
	testing.expect_value(t, tool, "")
	testing.expect_value(t, vein, "")
	world_set_block(&world, {0, 0, 0}, test_block(content.blocks, "hematite_ore"))
	name, tool, _ = target_status_lines(&world, &records, content.machines, content.fluids, content.veins, content.blocks, content.items, obtained, 0, target)
	testing.expect_value(t, name, "Unknown ore")
	testing.expect_value(t, tool, "Needs a tool: Wooden pickaxe")
	obtained[test_item(content.items, "hematite")] = true
	name, _, _ = target_status_lines(&world, &records, content.machines, content.fluids, content.veins, content.blocks, content.items, obtained, tier, target)
	testing.expect_value(t, name, "Hematite ore")
	chest := place_test_entity(&world, content, "wooden_chest", {0, 1, 0})
	name, tool, vein = target_status_lines(&world, &records, content.machines, content.fluids, content.veins, content.blocks, content.items, obtained, tier, Raycast_Hit{hit = true, block = {0, 1, 0}, entity = chest})
	testing.expect_value(t, name, entity_status_text(&world, records.core_samples[:], content.machines, content.fluids, content.items, chest))
	testing.expect(t, name != "")
	testing.expect_value(t, tool, "")
	name, tool, vein = target_status_lines(&world, &records, content.machines, content.fluids, content.veins, content.blocks, content.items, obtained, tier, Raycast_Hit{})
	testing.expect_value(t, name, "")
	testing.expect_value(t, tool, "")
	testing.expect_value(t, vein, "")
}

@(test)
test_vein_line_hides_the_type_until_an_ore_is_discovered :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, {300, 50, 0, 0})
	obtained := make([]bool, len(content.items.items), context.temp_allocator)
	testing.expect_value(t, vein_status_text(&world, records.assayed_veins[:], content.veins, content.blocks, content.items, obtained, vein), "Unknown ore  350 remaining")
	// Gravel comes out of every vein, it names none of them.
	obtained[test_item(content.items, "gravel")] = true
	testing.expect_value(t, vein_status_text(&world, records.assayed_veins[:], content.veins, content.blocks, content.items, obtained, vein), "Unknown ore  350 remaining")
	obtained[test_item(content.items, "hematite")] = true
	testing.expect_value(t, vein_status_text(&world, records.assayed_veins[:], content.veins, content.blocks, content.items, obtained, vein), "Iron vein  350 remaining")
	// A quarry yields nothing a discoverable block drops, so it is named.
	quarry := content.veins.types[test_vein_type(content, "quarry")]
	testing.expect(t, vein_type_is_discovered(quarry, content.blocks, content.items, nil))
}

discovery_message_count :: proc(quests: Quest_State, item_name_key: string) -> int {
	count := 0
	for message in quests.messages {
		count += message.text_key == ITEM_DISCOVERED_KEY && message.argument_key == item_name_key ? 1 : 0
	}
	return count
}

@(test)
test_discovery_message_fires_once_and_not_for_starting_items :: proc(t: ^testing.T) {
	content := make_test_content()
	config := test_game_config()
	starting := [?]Starting_Item{{item = "coal", count = 5}}
	config.starting_items = starting[:]
	simulation := make_simulation(config, player_start_on({0, 10, 0}), content, content.technologies, false, {})
	defer destroy_simulation(&simulation)
	coal, hematite := test_item(content.items, "coal"), test_item(content.items, "hematite")
	testing.expect(t, simulation.unlocks.obtained[coal])
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, discovery_message_count(simulation.quests, content.items.items[coal].name_key), 0)
	inventory_add(simulation.players[0].inventory, content.items, hematite, 1)
	inventory_add(simulation.players[0].inventory, content.items, test_item(content.items, "gravel"), 1)
	simulation_tick(&simulation, content, {})
	simulation_tick(&simulation, content, {})
	testing.expect_value(t, discovery_message_count(simulation.quests, content.items.items[hematite].name_key), 1)
	testing.expect_value(t, discovery_message_count(simulation.quests, content.items.items[test_item(content.items, "gravel")].name_key), 0)
	notice_found := false
	for notice in simulation.quests.notices {
		notice_found ||= notice.text_key == ITEM_DISCOVERED_KEY
	}
	testing.expect(t, notice_found)
}
