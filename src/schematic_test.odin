package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Caves, schematic crates and the schematic channel (work item 0036).

// The per block cave lookup the crate sites use agrees with chunk
// generation: an open cell is air, and air below the surface is open.
@(test)
test_cave_lookup_matches_generated_chunks :: proc(t: ^testing.T) {
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	cache := make(Cave_Noise_Cache, context.temp_allocator)
	for coordinate in ([?]Chunk_Coordinate{{0, -2, 0}, {3, 0, -2}, {-5, -1, 4}}) {
		chunk := generate_chunk(&generator, coordinate, context.temp_allocator).chunk
		origin := chunk_origin(coordinate)
		mismatches := 0
		for block, index in chunk.blocks {
			position := origin + World_Coordinate(index_to_local(index))
			below_surface := position.y < terrain_height(generator.seeds, position.x, position.z)
			open := cell_is_open_cave(&generator, &cache, position)
			if open != (below_surface && block == AIR_BLOCK) {
				mismatches += 1
			}
		}
		testing.expectf(t, mismatches == 0, "chunk %v: %d cells disagree", coordinate, mismatches)
	}
}

expect_valid_crate_site :: proc(t: ^testing.T, generator: ^Generator, site: Crate_Site, region: Region_Coordinate) {
	cache := make(Cave_Noise_Cache, context.temp_allocator)
	testing.expect_value(t, site.region, region)
	testing.expect_value(t, block_to_region(site.position.x, site.position.z), region)
	surface := terrain_height(generator.seeds, site.position.x, site.position.z)
	testing.expect(t, surface - site.position.y >= CRATE_MINIMUM_DEPTH)
	testing.expect(t, cell_is_open_cave(generator, &cache, site.position))
	testing.expect(t, !cell_is_open_cave(generator, &cache, site.position - {0, 1, 0}))
	testing.expect(t, site.wall_count >= MINIMUM_GOLD_QUARTZ_WALLS && site.wall_count <= MAXIMUM_GOLD_QUARTZ_WALLS)
	walls := site.walls
	for wall in walls[:site.wall_count] {
		testing.expect(t, cell_is_cave_rock(generator, &cache, wall))
		testing.expect_value(t, block_to_region(wall.x, wall.z), region)
		offset := wall - site.position
		testing.expect(t, abs(offset.x) + abs(offset.z) <= CRATE_WALL_REACH + 1 && offset.y >= 0 && offset.y <= 1)
	}
}

// About one crate per four regions, each in a real pocket deep enough,
// and the same from a second generator of the seed.
@(test)
test_crate_sites_are_deterministic_and_sparse :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		other_instance := make_test_generator(seed)
		count := 0
		for region_z in i32(-6) ..< 6 {
			for region_x in i32(-6) ..< 6 {
				region := Region_Coordinate{region_x, region_z}
				site, found := region_crate_site(&generator, region)
				again, found_again := region_crate_site(&other_instance, region)
				testing.expect_value(t, found_again, found)
				testing.expect_value(t, again, site)
				if found {
					count += 1
					expect_valid_crate_site(t, &generator, site, region)
				}
			}
		}
		// 144 regions at a quarter each: 36 expected.
		testing.expectf(t, count >= 20 && count <= 55, "seed %d: %d crates in 144 regions", seed, count)
	}
}

// Sites prefer pockets 20 to 40 blocks down and go deeper only when no
// candidate column of the region has a shallow pocket.
@(test)
test_crate_sites_prefer_shallow_pockets :: proc(t: ^testing.T) {
	for seed in TEST_SEEDS {
		generator := make_test_generator(seed)
		cache := make(Cave_Noise_Cache, context.temp_allocator)
		shallow, total := 0, 0
		for region_z in i32(-6) ..< 6 {
			for region_x in i32(-6) ..< 6 {
				region := Region_Coordinate{region_x, region_z}
				site, found := region_crate_site(&generator, region)
				if !found {
					continue
				}
				total += 1
				depth := terrain_height(generator.seeds, site.position.x, site.position.z) - site.position.y
				if depth <= CRATE_SHALLOW_MAXIMUM_DEPTH {
					shallow += 1
					continue
				}
				region_hash := region_crate_hash(&generator, region)
				for candidate in 0 ..< CRATE_CANDIDATE_COLUMNS {
					column := crate_candidate_column(region_hash, region, candidate)
					_, has_shallow := column_crate_site(&generator, &cache, column, region_hash, CRATE_SHALLOW_MAXIMUM_DEPTH)
					testing.expectf(t, !has_shallow, "seed %d region %v: deep site although candidate %d is shallow", seed, region, candidate)
				}
			}
		}
		testing.expectf(t, shallow * 2 > total, "seed %d: only %d of %d crates shallow", seed, shallow, total)
	}
}

first_crate_site :: proc(generator: ^Generator) -> Crate_Site {
	for region_z in i32(0) ..< 8 {
		for region_x in i32(0) ..< 8 {
			if site, found := region_crate_site(generator, {region_x, region_z}); found {
				return site
			}
		}
	}
	panic("no crate site in 64 regions")
}

// The chunks around a site, in a fixed order.
crate_site_chunks :: proc(site: Crate_Site) -> []Chunk_Coordinate {
	centre := world_to_chunk_coordinate(site.position)
	chunks := make([dynamic]Chunk_Coordinate, context.temp_allocator)
	for y in i32(-1) ..= 1 {
		for z in i32(-1) ..= 1 {
			for x in i32(-1) ..= 1 {
				append(&chunks, centre + {x, y, z})
			}
		}
	}
	return chunks[:]
}

load_crate_world :: proc(world: ^World, records: ^Game_Records, generator: ^Generator, content: Simulation_Content, chunks: []Chunk_Coordinate) {
	for coordinate in chunks {
		load_chunk_now(world, records, generator, coordinate)
	}
	place_pending_crates(world_tick_context(world, records, content, TEST_TICK_RATE))
}

@(test)
test_crate_placement_does_not_depend_on_load_order :: proc(t: ^testing.T) {
	content := make_test_content()
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	site := first_crate_site(&generator)
	chunks := crate_site_chunks(site)
	// Only the chunk holding the crate cell lists the site.
	for coordinate in chunks {
		generated := generate_chunk(&generator, coordinate, context.temp_allocator)
		testing.expect_value(t, len(generated.crates), coordinate == world_to_chunk_coordinate(site.position) ? 1 : 0)
	}
	forward, backward: World
	forward_records, backward_records: Game_Records
	defer destroy_world(&forward)
	defer destroy_world(&backward)
	defer destroy_game_records(&forward_records)
	defer destroy_game_records(&backward_records)
	load_crate_world(&forward, &forward_records, &generator, content, chunks)
	reversed := slice.clone(chunks, context.temp_allocator)
	slice.reverse(reversed)
	load_crate_world(&backward, &backward_records, &generator, content, reversed)
	for world, index in ([2]^World{&forward, &backward}) {
		records := ([2]^Game_Records{&forward_records, &backward_records})[index]
		testing.expect_value(t, len(records.crate_sites), 1)
		testing.expect_value(t, len(world.entities.schematic_crates.entries), 1)
		crate := pool_get(&world.entities.schematic_crates, entity_at(&world.entities, site.position))
		testing.expect(t, crate != nil)
		testing.expect_value(t, crate.slots[0], Item_Stack{item = schematic_for_choice(content.recipes, site.choice), count = 1})
		testing.expect_value(t, world_get_block(world, site.position), AIR_BLOCK)
		testing.expect(t, block_is_solid(content.blocks, world_get_block(world, site.position - {0, 1, 0})))
		for wall in site.walls[:site.wall_count] {
			testing.expect_value(t, world_get_block(world, wall), test_block(content.blocks, "gold_quartz"))
		}
	}
	for coordinate in chunks {
		testing.expect(t, slice.equal(forward.chunks[coordinate].blocks[:], backward.chunks[coordinate].blocks[:]))
	}
	// An emptied crate stays empty when its chunk loads again.
	crate := pool_get(&forward.entities.schematic_crates, entity_at(&forward.entities, site.position))
	crate.slots[0] = EMPTY_STACK
	coordinate := world_to_chunk_coordinate(site.position)
	free(forward.chunks[coordinate])
	delete_key(&forward.chunks, coordinate)
	load_crate_world(&forward, &forward_records, &generator, content, {coordinate})
	testing.expect_value(t, len(forward_records.crate_sites), 1)
	testing.expect_value(t, len(forward.entities.schematic_crates.entries), 1)
	testing.expect(t, stack_is_empty(forward.entities.schematic_crates.entries[0].slots[0]))
}

make_schematic_simulation :: proc(content: Simulation_Content) -> Simulation_State {
	return make_simulation(test_game_config(), player_start_on({0, 40, 0}), content, content.technologies, false, {})
}

press :: proc(actions: Action_Set) -> Input_Frame {
	return Input_Frame{pressed = actions, just_pressed = actions}
}

// Use_Item (L2, with Place) on a selected schematic consumes it and finds
// exactly its recipe, with a log line, a toast and the statistic.
@(test)
test_use_action_reads_exactly_its_recipe :: proc(t: ^testing.T) {
	content := make_test_content()
	simulation := make_schematic_simulation(content)
	defer destroy_simulation(&simulation)
	player := &simulation.players[0]
	clear_inventory(player.inventory)
	schematic := test_item(content.items, "schematic_charcoal_steel")
	inventory_add(player.inventory, content.items, schematic, 1)
	before := slice.clone(simulation.unlocks.available, context.temp_allocator)
	recipe := test_recipe(content.recipes, "charcoal_steel")
	testing.expect(t, !before[recipe])
	simulation_tick(&simulation, content, {press({.Place, .Use_Item})})
	testing.expect_value(t, inventory_count(player.inventory, schematic), 0)
	for available, index in simulation.unlocks.available {
		testing.expectf(t, available == (before[index] || index == recipe), "recipe %s", content.recipes.recipes[index].id)
	}
	testing.expect_value(t, count_true(simulation.unlocks.schematics_found), 1)
	testing.expect(t, simulation.unlocks.schematics_found[recipe])
	testing.expect_value(t, simulation.records.statistics.schematics_found, 1)
	testing.expect_value(t, hint_counter_value(simulation.records.statistics, Hint{counter = .Schematics_Found}), 1)
	message := simulation.quests.messages[len(simulation.quests.messages) - 1]
	testing.expect_value(t, message, Quest_Message{tick = 1, text_key = SCHEMATIC_READ_KEY, argument_key = "recipe_charcoal_steel"})
	testing.expect(t, slice.contains(simulation.quests.notices[:], message))
	// Without a schematic selected, the same press does nothing more.
	simulation_tick(&simulation, content, {press({.Place, .Use_Item})})
	testing.expect_value(t, simulation.records.statistics.schematics_found, 1)
}

clear_inventory :: proc(inventory: Inventory) {
	for &slot in inventory.slots {
		slot = EMPTY_STACK
	}
}

// Use_Item replaces Place only for a usable item; Interact on a crate
// takes its schematic in one press and never jumps.
@(test)
test_use_item_resolution :: proc(t: ^testing.T) {
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	player := make_test_player(content.blocks, {10, 1, 10})
	inventory_add(player.inventory, content.items, test_item(content.items, "iron_plate"), 1)
	input, used := resolve_use_item(&player, &world.entities, content.items, press({.Place, .Use_Item}))
	testing.expect_value(t, used, NO_ITEM)
	testing.expect_value(t, input.just_pressed, Action_Set{.Place})
	clear_inventory(player.inventory)
	schematic := test_item(content.items, "schematic_slag_concrete")
	inventory_add(player.inventory, content.items, schematic, 1)
	input, used = resolve_use_item(&player, &world.entities, content.items, press({.Place, .Use_Item}))
	testing.expect_value(t, used, schematic)
	testing.expect_value(t, input.just_pressed, Action_Set{.Use_Item})
	testing.expect_value(t, inventory_count(player.inventory, schematic), 0)

	sites := [1]Crate_Site{{region = {0, 0}, position = {4, 1, 4}, choice = 3}}
	register_crate_sites(&records.crate_sites, sites[:])
	place_pending_crates(world_tick_context(&world, &records, content, TEST_TICK_RATE))
	crate := entity_at(&world.entities, {4, 1, 4})
	testing.expect_value(t, crate.kind, Entity_Kind.Schematic_Crate)
	testing.expect(t, !entity_has_panel(&world.entities, content.machines, crate))
	testing.expect(t, !entity_can_be_picked_up(&world, content.machines, crate))
	player.target = Raycast_Hit{hit = true, block = {4, 1, 4}, entity = crate}
	// Interact on a crate takes its schematic in one press; A jumps there.
	// X routed at the full crate is Interact's alone, so the inventory
	// stays shut (0233).
	takes_interact, has_panel := aimed_target_calls_for(&world.entities, content.machines, crate, {})
	testing.expect(t, takes_interact && !has_panel)
	x := route_open_inventory_press(shipped_gamepad_press(t, .WEST), false, has_panel, takes_interact)
	testing.expect_value(t, x.just_pressed & {.Interact, .Open_Inventory, .Open_Aimed}, Action_Set{.Interact})
	input, used = resolve_use_item(&player, &world.entities, content.items, x)
	testing.expect_value(t, used, schematic_for_choice(content.recipes, 3))
	testing.expect(t, .Interact not_in input.pressed && .Interact not_in input.just_pressed)
	testing.expect(t, stack_is_empty(entity_slots(&world.entities, crate)[0]))
	crate_slot := &pool_get(&world.entities.schematic_crates, crate).slots[0]
	crate_slot^ = Item_Stack{item = schematic_for_choice(content.recipes, 3), count = 1}
	input, used = resolve_use_item(&player, &world.entities, content.items, press({.Interact}))
	testing.expect_value(t, used, schematic_for_choice(content.recipes, 3))
	testing.expect_value(t, input.pressed, Action_Set{})
	input, used = resolve_use_item(&player, &world.entities, content.items, press({.Jump}))
	testing.expect_value(t, input.pressed, Action_Set{.Jump})
	// An empty crate takes no Interact (0233): it gives nothing, the press
	// passes on, and X there keeps Open_Inventory, so the inventory opens.
	input, used = resolve_use_item(&player, &world.entities, content.items, press({.Jump, .Interact}))
	testing.expect_value(t, used, NO_ITEM)
	testing.expect_value(t, input.pressed, Action_Set{.Jump, .Interact})
	takes_interact, has_panel = aimed_target_calls_for(&world.entities, content.machines, crate, {})
	testing.expect(t, !takes_interact && !has_panel)
	x = route_open_inventory_press(shipped_gamepad_press(t, .WEST), false, has_panel, takes_interact)
	testing.expect(t, .Open_Inventory in x.just_pressed)
	// Inserters neither feed nor empty a crate.
	_, accepted := entity_accepts(&world.entities, content, crate, test_item(content.items, "coal"))
	testing.expect(t, !accepted)
	testing.expect_value(t, len(entity_offered_items(&world.entities, crate, NO_ITEM)), 0)
}

@(test)
test_schematic_channel_in_recipe_unlocks :: proc(t: ^testing.T) {
	test := make_crafting_test()
	schematics := schematic_items(test.recipes)
	testing.expect_value(t, len(schematics), 5)
	for item in schematics {
		recipe := schematic_recipe_for(test.recipes, item)
		definition := test.recipes.recipes[recipe]
		testing.expect_value(t, definition.channel, Recipe_Channel.Schematic)
		testing.expect_value(t, test.items.items[item].id, fmt.tprintf("schematic_%s", definition.id))
		testing.expect(t, item_is_usable(test.items, item))
		testing.expect_value(t, test.items.items[item].category, Item_Category.Tool)
		testing.expect_value(t, test.items.items[item].stack_size, 50)
		testing.expect(t, test.items.items[item].cannot_recycle)
		testing.expect(t, !recipe_is_available(test.unlocks, recipe))
		testing.expect(t, record_found_schematic(&test.unlocks, test.recipes, recipe))
		testing.expect(t, recipe_is_available(test.unlocks, recipe))
		testing.expect(t, !record_found_schematic(&test.unlocks, test.recipes, recipe))
	}
	testing.expect_value(t, schematic_recipe_for(test.recipes, test_item(test.items, "iron_plate")), NO_RECIPE)
	// Unlocking everything finds every schematic, for machines too.
	all := make_crafting_test(unlock_all = true)
	for item in schematics {
		recipe := schematic_recipe_for(all.recipes, item)
		testing.expect(t, recipe_is_available(all.unlocks, recipe) && all.unlocks.schematics_found[recipe])
	}
}

// Machines pick recipes by their inputs, so an alternate runs only once
// found: the furnace and the fixed chemical plant and washer.
@(test)
test_machines_make_alternates_only_once_found :: proc(t: ^testing.T) {
	content := make_test_content()
	items, recipes := content.items, content.recipes
	low_grade := test_item(items, "hematite_low_grade")
	slag := test_item(items, "slag")
	wood_gas := test_fluid(content, "wood_gas")
	testing.expect_value(t, furnace_recipe_for(recipes, low_grade), NO_RECIPE)
	testing.expect(t, !item_is_smeltable(recipes, low_grade))
	// Nothing loaded and wood gas in a port: not the alternate yet (the
	// plant settles on sulfur and waits for its gases, as before).
	testing.expect(t, fixed_recipe_for_inputs(recipes, .Chemistry, nil, {wood_gas}) != test_recipe(recipes, "wood_gas_plastic"))
	testing.expect_value(t, category_input_count(recipes, .Washer, slag), 0)
	unlocks := make_recipe_unlocks(len(items.items), recipes, content.technologies, false, context.temp_allocator)
	for id in ([?]string{"low_grade_iron_plate", "wood_gas_plastic", "slag_concrete", "charcoal_steel"}) {
		record_found_schematic(&unlocks, recipes, test_recipe(recipes, id))
	}
	found := with_schematics_found(recipes, unlocks.schematics_found)
	testing.expect_value(t, furnace_recipe_for(found, low_grade), test_recipe(recipes, "low_grade_iron_plate"))
	testing.expect_value(t, fixed_recipe_for_inputs(found, .Chemistry, nil, {wood_gas}), test_recipe(recipes, "wood_gas_plastic"))
	charcoal := [1]Item_Stack{{test_item(items, "charcoal"), 1}}
	testing.expect_value(t, fixed_recipe_for_inputs(found, .Chemistry, charcoal[:], {wood_gas}), test_recipe(recipes, "syngas_plastic"))
	testing.expect_value(t, category_input_count(found, .Washer, slag), 2)
	steel_inputs := [2]Item_Stack{{test_item(items, "iron_plate"), 5}, {test_item(items, "charcoal"), 2}}
	testing.expect_value(t, fixed_recipe_for_inputs(found, .Alloy_Furnace, steel_inputs[:]), test_recipe(recipes, "charcoal_steel"))
	// Half yield in the stone furnace: 2 low grade ore, 1 plate and 1 slag.
	furnace := make_furnace({})
	furnace.slots[FURNACE_INPUT_SLOT] = {low_grade, 4}
	furnace.slots[FURNACE_FUEL_SLOT] = {test_item(items, "coal"), 5}
	machine := content.machines.machines[test_machine(content.machines, "stone_furnace")]
	for _ in 0 ..< 2 * 192 + 10 {
		furnace = advance_furnace(furnace, machine, items, found, TEST_TICK_RATE)
	}
	testing.expect(t, stack_is_empty(furnace.slots[FURNACE_INPUT_SLOT]))
	testing.expect_value(t, furnace.slots[FURNACE_OUTPUT_SLOT], Item_Stack{test_item(items, "iron_plate"), 2})
	testing.expect_value(t, furnace.slots[FURNACE_BYPRODUCT_SLOT], Item_Stack{slag, 2})
}

// Silhouettes until found, with "Found in caves" as what unlocks them.
@(test)
test_schematic_recipes_are_silhouettes_found_in_caves :: proc(t: ^testing.T) {
	test := make_crafting_test()
	recipe := test_recipe(test.recipes, "slag_concrete")
	testing.expect(t, !recipe_detail(test.recipes, test.unlocks, recipe, context.temp_allocator).revealed)
	strings_table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, lookup_text(&strings_table, "recipes_locked_schematic"), "Found in caves")
	defer clear_missing_reports(&global_string_table)
	testing.expect_value(t, locked_recipe_text(test.recipes.recipes[recipe], test.technologies), text("recipes_locked_schematic"))
	record_found_schematic(&test.unlocks, test.recipes, recipe)
	detail := recipe_detail(test.recipes, test.unlocks, recipe, context.temp_allocator)
	testing.expect(t, detail.revealed)
	testing.expect_value(t, detail.inputs[0], Item_Stack{test_item(test.items, "slag"), 2})
}

@(test)
test_gold_quartz_yields_quartz_and_gold_ore :: proc(t: ^testing.T) {
	content := make_test_content()
	block := test_block(content.blocks, "gold_quartz")
	testing.expect(t, block_is_solid(content.blocks, block) && block_is_minable(content.blocks, block))
	drops := block_drop_stacks(content.items, block)
	testing.expect(t, slice.equal(drops, []Item_Stack{{test_item(content.items, "quartz"), 1}, {test_item(content.items, "gold_ore"), 1}}))
	testing.expect_value(t, len(block_drop_stacks(content.items, test_block(content.blocks, "stone"))), 1)
}

@(test)
test_schematic_data_is_validated :: proc(t: ^testing.T) {
	items := make_test_items()
	channel_without_item := Recipe_Definition{id = "a", inputs = {{item = "log", count = 1}}, outputs = {{item = "plank", count = 1}}, seconds = 1, made_in = {"hand"}, category = "materials", channel = "schematic"}
	_, problem := resolve_recipe_registry(Recipes_File{recipes = {channel_without_item}}, items, make_test_fluids(), context.temp_allocator)
	testing.expect(t, problem != "")
	not_usable := channel_without_item
	not_usable.schematic = "iron_plate"
	_, problem = resolve_recipe_registry(Recipes_File{recipes = {not_usable}}, items, make_test_fluids(), context.temp_allocator)
	testing.expect(t, problem != "")
	usable := channel_without_item
	usable.schematic = "schematic_slag_concrete"
	_, problem = resolve_recipe_registry(Recipes_File{recipes = {usable}}, items, make_test_fluids(), context.temp_allocator)
	testing.expect_value(t, problem, "")
	twice := usable
	twice.id = "b"
	_, problem = resolve_recipe_registry(Recipes_File{recipes = {usable, twice}}, items, make_test_fluids(), context.temp_allocator)
	testing.expect(t, problem != "")
	placing := Item_Definition{id = "x", name_key = "x", category = "tool", stack_size = 1, usable = true, places_block = "stone", price = 1}
	_, problem = resolve_item_registry(Items_File{items = {placing}}, make_test_registry(), context.temp_allocator)
	testing.expect(t, problem != "")
	crate := Machine_Definition{id = "crate", name_key = "crate", kind = "schematic_crate", footprint = {1, 1, 1}, slots = 2}
	_, problem = resolve_machine_registry(Machines_File{machines = {crate}}, items, make_test_fluids(), context.temp_allocator)
	testing.expect(t, problem != "")
}
