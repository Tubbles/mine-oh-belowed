package game

import "core:testing"

make_test_items :: proc() -> Item_Registry {
	file, error := parse_items_file(#load("../data/items.sjson"), context.temp_allocator)
	assert(error == nil)
	registry, problem := resolve_item_registry(file, make_test_registry(), context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

test_item :: proc(items: Item_Registry, id: string) -> Item_Id {
	item, found := find_item_id(items, id)
	assert(found, id)
	return item
}

@(test)
test_shipped_items_resolve :: proc(t: ^testing.T) {
	items := make_test_items()
	blocks := make_test_registry()
	testing.expect_value(t, len(items.items), 128)
	iron_plate := items.items[test_item(items, "iron_plate")]
	testing.expect_value(t, iron_plate.category, Item_Category.Intermediate)
	testing.expect_value(t, iron_plate.stack_size, 50)
	testing.expect_value(t, items.items[test_item(items, "iron_gear")].stack_size, 100)
	testing.expect_value(t, items.items[test_item(items, "stone_furnace")].stack_size, 10)
	testing.expect_value(t, items.items[test_item(items, "stick")].fuel_kilojoules, 500)
	testing.expect_value(t, items.items[test_item(items, "coal")].fuel_kilojoules, 4000)
	testing.expect_value(t, item_places_block(items, test_item(items, "torch")), test_block(blocks, "torch"))
	// Every block that can be mined yields an item.
	for definition, block in blocks.definitions {
		if block_is_minable(blocks, Block_Id(block)) {
			testing.expectf(t, block_drop(items, Block_Id(block)) != NO_ITEM, "%s yields nothing", definition.id)
		}
	}
}

@(test)
test_shipped_item_names_are_in_the_string_table :: proc(t: ^testing.T) {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	for item in make_test_items().items {
		testing.expectf(t, item.name_key in table.entries, "missing string %q", item.name_key)
	}
	for category in Item_Category {
		testing.expect(t, item_category_key(category) in table.entries)
	}
}

resolve_test_items :: proc(definitions: []Item_Definition) -> string {
	registry, problem := resolve_item_registry(Items_File{items = definitions}, make_test_registry(), context.temp_allocator)
	if problem == "" {
		destroy_item_registry(registry, context.temp_allocator)
	}
	return problem
}

@(test)
test_item_loading_rejects_bad_tables :: proc(t: ^testing.T) {
	items_file, _ := parse_items_file(#load("../data/items.sjson"), context.temp_allocator)
	valid := items_file.items
	testing.expect_value(t, resolve_test_items(valid), "")
	cases := [?]Item_Definition {
		{id = "x", name_key = "k", category = "gadget", stack_size = 1, price = 1},
		{id = "x", name_key = "k", category = "raw", stack_size = 0, price = 1},
		{id = "x", name_key = "", category = "raw", stack_size = 1, price = 1},
		{id = "x", name_key = "k", category = "raw", stack_size = 1, places_block = "no_such_block", price = 1},
		{id = "x", name_key = "k", category = "raw", stack_size = 1, places_block = "air", price = 1},
		{id = "x", name_key = "k", category = "raw", stack_size = 1, mined_from = {"water"}, price = 1},
		// Stone already yields the stone item.
		{id = "x", name_key = "k", category = "raw", stack_size = 1, mined_from = {"stone"}, price = 1},
		{id = "stone", name_key = "k", category = "raw", stack_size = 1, price = 1},
		// Every item needs a price (work item 0041).
		{id = "x", name_key = "k", category = "raw", stack_size = 1, price = 0},
	}
	for bad in cases {
		definitions := make([dynamic]Item_Definition, context.temp_allocator)
		append(&definitions, ..valid)
		append(&definitions, bad)
		testing.expectf(t, resolve_test_items(definitions[:]) != "", "accepted %v", bad)
	}
	// A block that can be mined but yields nothing.
	without_torch := make([dynamic]Item_Definition, context.temp_allocator)
	for definition in valid {
		if definition.id != "torch" {
			append(&without_torch, definition)
		}
	}
	testing.expect(t, resolve_test_items(without_torch[:]) != "")
}

@(test)
test_item_sort_ranks_by_category_then_name :: proc(t: ^testing.T) {
	items := Item_Registry {
		items = []Item {
			{id = "zinc", category = .Raw},
			{id = "belt", category = .Machine},
			{id = "anvil", category = .Machine},
			{id = "gear", category = .Intermediate},
			{id = "ash", category = .Raw},
		},
	}
	names := []string{"Zinc", "Belt", "Anvil", "Gear", "Ash"}
	ranks := item_sort_ranks(items, names, context.temp_allocator)
	testing.expect_value(t, len(ranks), 5)
	expected := []u16{1, 4, 3, 2, 0}
	for rank, index in ranks {
		testing.expect_value(t, rank, expected[index])
	}
}

@(test)
test_item_icons :: proc(t: ^testing.T) {
	items := make_test_items()
	blocks := make_test_registry()
	stone := item_icon(items, test_item(items, "stone"))
	testing.expect_value(t, stone.kind, Item_Icon_Kind.Block_Tile)
	testing.expect_value(t, stone.tile, atlas_tile_index(test_block(blocks, "stone"), .Side))
	plate := item_icon(items, test_item(items, "iron_plate"))
	testing.expect_value(t, plate.kind, Item_Icon_Kind.Lettered)
	testing.expect_value(t, plate.letters, [2]u8{'I', 'P'})
	testing.expect_value(t, item_letters("coal"), [2]u8{'C', 'O'})
	testing.expect_value(t, item_letters("x"), [2]u8{'X', ' '})
}
