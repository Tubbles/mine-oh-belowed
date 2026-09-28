package game

import "core:slice"
import "core:testing"

// Prospecting worlds stand on the stone floor of make_floor_world (top at
// y 1), with test veins in region (0, 0) like the drill tests.

@(test)
test_prospecting_data_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	hammer := content.items.items[test_item(content.items, "geologists_hammer")]
	testing.expect(t, hammer.usable && hammer.use == .Assay)
	magnetometer := content.items.items[test_item(content.items, "magnetometer")]
	testing.expect_value(t, magnetometer.use, Item_Use.Magnetometer)
	testing.expect_value(t, magnetometer.detects, test_item(content.items, "hematite"))
	testing.expect_value(t, magnetometer.use_range, 30)
	charge := content.items.items[test_item(content.items, "thumper_charge")]
	testing.expect_value(t, charge.use, Item_Use.Seismic_Shot)
	testing.expect_value(t, charge.use_range, 32)
	recipe := content.recipes.recipes[test_recipe(content.recipes, "thumper_charge")]
	testing.expect_value(t, recipe.outputs[0], Item_Stack{test_item(content.items, "thumper_charge"), 4})
	seismic := content.technologies.technologies[test_technology(content.technologies, "seismic_survey")]
	testing.expect_value(t, seismic.pack_count, 100)
	testing.expect_value(t, seismic.prerequisites[0], test_technology(content.technologies, "prospecting"))
	testing.expect_value(t, len(seismic.science_packs), 2)
	drill := content.machines.machines[test_machine(content.machines, "core_sample_drill")]
	testing.expect_value(t, drill.kind, Machine_Kind.Core_Sample_Drill)
	testing.expect_value(t, drill.footprint, [3]i32{1, 2, 1})
	testing.expect_value(t, drill.electric_power_watts, 40_000)
	testing.expect_value(t, core_sample_ticks(drill, TEST_TICK_RATE), 3600)
	// A use needs a usable item, and a magnetometer what it detects.
	definitions := []Item_Definition{{id = "tool", name_key = "k", category = "tool", stack_size = 1, use = "assay", price = 1}}
	testing.expect(t, validate_item_definition(definitions, 0) != "")
	definitions[0] = {id = "tool", name_key = "k", category = "tool", stack_size = 1, usable = true, use = "magnetometer", use_range = 5, price = 1}
	testing.expect(t, validate_item_definition(definitions, 0) != "")
	definitions[0].detects = "hematite"
	testing.expect_value(t, validate_item_definition(definitions, 0), "")
}

@(test)
test_hammer_assays_the_vein_of_an_outcrop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 2, IRON_TEST_VEIN)
	registered_vein(&world, vein).size_class = 1
	testing.expect(t, !vein_is_assayed(&world, vein))
	// Stone is no outcrop.
	testing.expect(t, !assay_vein(&world, content.veins, {12, 0, 12}))
	testing.expect(t, assay_vein(&world, content.veins, {6, 0, 5}))
	testing.expect_value(t, len(world.assayed_veins), 1)
	assayed := world.assayed_veins[0]
	testing.expect_value(t, assayed.vein, vein)
	testing.expect_value(t, assayed.type, test_vein_type(content, "iron"))
	testing.expect_value(t, assayed.size_class, 1)
	testing.expect_value(t, assayed.centre, World_Coordinate{5, 0, 5})
	testing.expect_value(t, assayed.radius, 2)
	testing.expect_value(t, world.statistics.veins_assayed, 1)
	// Once per vein.
	testing.expect(t, !assay_vein(&world, content.veins, {5, 0, 5}))
	testing.expect_value(t, world.statistics.veins_assayed, 1)
	testing.expect(t, vein_is_assayed(&world, vein))
	testing.expect_value(t, content.veins.size_class_ids[assayed.size_class], "deposit")
}

// A vein known only from its spent outcrop (work item 0096) is not
// assayed; the hammer turns its record into an assayed one.
@(test)
test_hammer_assays_a_vein_known_from_its_spent_outcrop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 2, IRON_TEST_VEIN)
	testing.expect(t, record_spent_outcrop(&world, vein))
	testing.expect(t, !vein_is_assayed(&world, vein))
	testing.expect_value(t, world.statistics.veins_assayed, 0)
	testing.expect(t, assay_vein(&world, content.veins, {6, 0, 5}))
	testing.expect(t, vein_is_assayed(&world, vein))
	testing.expect_value(t, len(world.assayed_veins), 1)
	testing.expect(t, world.assayed_veins[0].outcrop_spent)
	testing.expect_value(t, world.statistics.veins_assayed, 1)
}

// The map draws a spent vein's footprint like an assayed one.
@(test)
test_map_draws_the_footprint_of_a_spent_vein :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	vein := add_test_vein(&world, content, "iron", {5, 5}, 2, IRON_TEST_VEIN)
	frame := Map_Frame{origin = {0, 0}, blocks_per_pixel = 1, size = 12}
	colors := DEFAULT_UI_THEME.palettes[.Default]
	background := Ui_Color{0, 0, 0, 255}
	pixels := make([]Ui_Color, frame.size * frame.size)
	paint_map_records(pixels, frame, &world, colors)
	testing.expect_value(t, pixels[5 * frame.size + 5], Ui_Color{})
	testing.expect(t, record_spent_outcrop(&world, vein))
	slice.fill(pixels, background)
	paint_map_records(pixels, frame, &world, colors)
	footprint := blend_color(background, colors[.Map_Assayed], MAP_ASSAYED_BLEND)
	testing.expect_value(t, pixels[5 * frame.size + 5], footprint)
	testing.expect_value(t, pixels[5 * frame.size + 7], footprint)
	testing.expect_value(t, pixels[5 * frame.size + 8], background)
}

// The tools stay in the hotbar, a charge goes only when fired at a block.
@(test)
test_use_item_consumes_only_schematics_and_fired_charges :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	player := make_test_player(content.blocks, {10, 1, 10})
	for id in ([?]string{"geologists_hammer", "magnetometer"}) {
		clear_inventory(player.inventory)
		tool := test_item(content.items, id)
		inventory_add(player.inventory, content.items, tool, 1)
		player.target = Raycast_Hit{hit = true, block = {10, 0, 10}}
		input, used := resolve_use_item(&player, &world.entities, content.items, press({.Place, .Use_Item}))
		testing.expect_value(t, used, tool)
		testing.expect_value(t, input.just_pressed, Action_Set{.Use_Item})
		testing.expect_value(t, inventory_count(player.inventory, tool), 1)
	}
	clear_inventory(player.inventory)
	charge := test_item(content.items, "thumper_charge")
	inventory_add(player.inventory, content.items, charge, 2)
	player.target = {}
	_, used := resolve_use_item(&player, &world.entities, content.items, press({.Use_Item}))
	testing.expect_value(t, used, charge)
	testing.expect_value(t, inventory_count(player.inventory, charge), 2)
	player.target = Raycast_Hit{hit = true, block = {10, 0, 10}}
	resolve_use_item(&player, &world.entities, content.items, press({.Use_Item}))
	testing.expect_value(t, inventory_count(player.inventory, charge), 1)
}

test_magnetometer_vein :: proc(content: Simulation_Content, type_id: string, centre: [2]i32, radius: i32, layer: Vein_Layer, index: i32) -> Vein {
	depth := layer == .Deep ? i32(-80) : 0
	return Vein{id = {index = index, layer = layer}, type = test_vein_type(content, type_id), centre = {centre.x, depth, centre.y}, radius = radius}
}

@(test)
test_magnetometer_finds_the_nearest_iron_vein :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	hematite := test_item(content.items, "hematite")
	player := [3]f32{0.5, 40, 0.5}
	// Copper is nearer but has no hematite; the buried iron vein counts
	// across, whatever its depth.
	veins := []Vein {
		test_magnetometer_vein(content, "copper", {3, 0}, 1, .Surface, 0),
		test_magnetometer_vein(content, "iron", {21, 0}, 5, .Surface, 1),
		test_magnetometer_vein(content, "deep_iron", {0, -18}, 3, .Deep, 2),
	}
	reading := magnetometer_reading(veins, content.veins, hematite, 30, player)
	testing.expect(t, reading.found)
	testing.expect_value(t, reading.origin, [2]i32{0, 0})
	testing.expect_value(t, reading.offset, [2]i32{0, -18})
	// 15 blocks from the disc's edge: half strength.
	testing.expect_value(t, reading.strength, 500)
	// Inside a disc: full strength.
	inside := magnetometer_reading(veins, content.veins, hematite, 30, {20.5, 40, 1.5})
	testing.expect_value(t, inside.strength, MAGNETOMETER_FULL)
	testing.expect_value(t, inside.offset, [2]i32{1, -1})
	// Beyond the range nothing is found.
	far := magnetometer_reading(veins, content.veins, hematite, 30, {-60.5, 40, 0.5})
	testing.expect(t, !far.found)
	testing.expect_value(t, far.strength, 0)
	testing.expect_value(t, magnetometer_strength(29.9, 30), 3)
	testing.expect_value(t, magnetometer_strength(30, 30), 0)
	// The needle points straight up when the player looks at the vein.
	testing.expect(t, abs(magnetometer_needle_angle({offset = {0, -18}}, -90)) < 0.001)
	// The rumble follows the strength while the world is shown.
	player_state := make_test_player(content.blocks, {})
	player_state.magnetometer = reading
	testing.expect_value(t, haptic_request_for(player_state, true).strength, 0.5)
	testing.expect_value(t, haptic_request_for(player_state, false).strength, 0)
	testing.expect_value(t, rumble_level(1), max(u16))
}

// Only while selected, read every tick.
@(test)
test_selected_magnetometer_reads_every_tick :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	add_test_vein(&world, content, "iron", {10, 0}, 2, IRON_TEST_VEIN)
	player := make_test_player(content.blocks, {0.5, 1, 0.5})
	update_magnetometer(&world, content, &player)
	testing.expect(t, !player.magnetometer.found)
	inventory_add(player.inventory, content.items, test_item(content.items, "magnetometer"), 1)
	update_magnetometer(&world, content, &player)
	testing.expect(t, player.magnetometer.found)
	testing.expect_value(t, player.magnetometer.offset, [2]i32{10, 0})
}

// Stone floor, dirt below it, sand below that; the chunks under y -32 are
// not loaded, so the report stops after two bands. The deep vein under the
// column comes with its type and depth.
@(test)
test_core_sample_reports_strata_and_deep_vein :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	dirt, sand := test_block(content.blocks, "dirt"), test_block(content.blocks, "sand")
	for y in i32(-15) ..= -1 {
		world_set_block(&world, {3, y, 3}, dirt)
	}
	for y in i32(-31) ..= -16 {
		world_set_block(&world, {3, y, 3}, sand)
	}
	vein := add_test_deep_vein(&world, content, "deep_iron", {4, 4}, 3, {50_000, 5_000, 0, 0})
	sample := take_core_sample(&world, len(content.blocks.definitions), {3, 1, 3})
	testing.expect_value(t, sample.band_count, 2)
	testing.expect_value(t, sample.bands[0], dirt)
	testing.expect_value(t, sample.bands[1], sand)
	testing.expect(t, sample.vein_found)
	testing.expect_value(t, sample.vein, vein)
	testing.expect_value(t, sample.vein_type, test_vein_type(content, "deep_iron"))
	testing.expect_value(t, sample.vein_depth, 61)
	outside := take_core_sample(&world, len(content.blocks.definitions), {-20, 1, -20})
	testing.expect(t, !outside.vein_found)
}

// Powered, the drill reports after its sampling time and not before;
// picked up and placed again it samples anew.
@(test)
test_core_sample_drill_reports_after_sampling_time :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	add_test_power_plant(&world, content, {2, 1, 2}, {0, 1, 3})
	handle := place_test_entity(&world, content, "core_sample_drill", {4, 1, 0})
	testing.expect(t, entity_network(&world.entities.electric_networks, handle) >= 0)
	sampling := int(core_sample_ticks(content.machines.machines[test_machine(content.machines, "core_sample_drill")], TEST_TICK_RATE))
	for _ in 0 ..< sampling - 1 {
		tick_entities(&world, content, TEST_TICK_RATE)
	}
	testing.expect_value(t, len(world.core_samples), 0)
	tick_entities(&world, content, TEST_TICK_RATE)
	drill := pool_get(&world.entities.core_sample_drills, handle)
	testing.expect_value(t, drill.sample, 0)
	testing.expect_value(t, len(world.core_samples), 1)
	testing.expect_value(t, world.core_samples[0].position, World_Coordinate{4, 1, 0})
	testing.expect_value(t, world.statistics.core_samples_taken, 1)
	// Done, it asks for no more power and reports no more.
	tick_entities(&world, content, TEST_TICK_RATE)
	testing.expect_value(t, len(world.core_samples), 1)
	testing.expect(t, remove_entity(&world.entities, content.machines, handle))
	again := pool_get(&world.entities.core_sample_drills, place_test_entity(&world, content, "core_sample_drill", {4, 1, 1}))
	testing.expect_value(t, again.sample, -1)
	testing.expect_value(t, again.work_ticks, 0)
}

// Shots record every deep vein within reach once as an outline, count
// the shots covering it, and resolve it at the third.
@(test)
test_seismic_outlines_union_over_shots :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	near := add_test_deep_vein(&world, content, "deep_iron", {0, 0}, 4, {1000, 0, 0, 0}, 0)
	east := add_test_deep_vein(&world, content, "deep_copper", {60, 0}, 4, {1000, 0, 0, 0}, 1)
	add_test_vein(&world, content, "iron", {10, 10}, 2, IRON_TEST_VEIN, 2)
	// 36 blocks from the near vein's centre, the disc reaches within 32.
	fire_seismic_shot(&world, {36, 1, 0}, 32)
	testing.expect_value(t, len(world.seismic_outlines), 2)
	fire_seismic_shot(&world, {-10, 1, 0}, 32)
	testing.expect_value(t, len(world.seismic_outlines), 2)
	testing.expect_value(t, world.seismic_outlines[0].vein, near)
	testing.expect_value(t, world.seismic_outlines[0].shot_count, 2)
	testing.expect_value(t, world.seismic_outlines[1].vein, east)
	testing.expect_value(t, world.seismic_outlines[1].shot_count, 1)
	testing.expect(t, !world.seismic_outlines[0].resolved)
	testing.expect_value(t, world.seismic_outlines[0].centre, World_Coordinate{0, -60, 0})
	testing.expect_value(t, world.seismic_outlines[0].radius, 4)
	// The third shot covering the near vein resolves it; the east vein is
	// 67 blocks away and stays at one shot.
	fire_seismic_shot(&world, {0, 1, 30}, 32)
	testing.expect(t, world.seismic_outlines[0].resolved)
	testing.expect_value(t, world.seismic_outlines[1].shot_count, 1)
	testing.expect_value(t, world.statistics.seismic_shots, 3)
	testing.expect_value(t, world.statistics.veins_resolved, 1)
	testing.expect_value(t, len(world.seismic_shots), 3)
	// A fourth shot counts but does not resolve twice.
	fire_seismic_shot(&world, {0, 1, 0}, 32)
	testing.expect_value(t, world.seismic_outlines[0].shot_count, 4)
	testing.expect_value(t, world.statistics.veins_resolved, 1)
}

@(test)
test_surface_merge_keeps_what_a_lower_scan_cannot_see :: proc(t: ^testing.T) {
	unknown := Surface_Cell{height = UNKNOWN_SURFACE_HEIGHT}
	grass := Surface_Cell{block = 3, height = 40}
	cave_floor := Surface_Cell{block = 1, height = -10}
	testing.expect_value(t, merge_surface_cell(unknown, grass, true, 63), grass)
	testing.expect_value(t, merge_surface_cell(grass, {}, false, 63), grass)
	// Scanning from y 31 cannot see the surface at 40.
	testing.expect_value(t, merge_surface_cell(grass, cave_floor, true, 31), grass)
	// Dug down while the surface chunk was loaded.
	testing.expect_value(t, merge_surface_cell(grass, cave_floor, true, 63), cave_floor)
}

// A column is explored once a chunk of it loads; its surface is recorded
// when its chunks unload and stays when they are gone, and a later scan
// from below does not replace it.
@(test)
test_explored_surface_is_recorded_for_unloaded_chunks :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	world: World
	coordinates := [?]Chunk_Coordinate{{0, 3, 0}, {0, 2, 0}, {0, 1, 0}, {0, 0, 0}, {0, -1, 0}}
	for coordinate in coordinates {
		load_chunk_now(&world, &generator, coordinate)
	}
	testing.expect_value(t, len(world.explored), 1)
	testing.expect(t, !surface_cell_is_known(world.explored[{0, 0}][0]))
	live := make(map[Chunk_Column]Column_Surface)
	collect_explored_surfaces(&world, &live)
	expected := surface_at(live, 5, 7)
	testing.expect(t, surface_cell_is_known(expected))
	testing.expect(t, world_get_block(&world, {5, i32(expected.height), 7}) == expected.block && expected.block != AIR_BLOCK)
	testing.expect_value(t, world_get_block(&world, {5, i32(expected.height) + 1, 7}), AIR_BLOCK)
	refresh_unloading_surfaces(&world, coordinates[:])
	for coordinate in coordinates {
		free(world.chunks[coordinate])
		delete_key(&world.chunks, coordinate)
	}
	testing.expect_value(t, surface_at(world.explored, 5, 7), expected)
	testing.expect_value(t, surface_at(world.explored, 40, 7).height, UNKNOWN_SURFACE_HEIGHT)
	load_chunk_now(&world, &generator, {0, -1, 0})
	refresh_loaded_surfaces(&world)
	testing.expect_value(t, surface_at(world.explored, 5, 7), expected)
	free(world.chunks[{0, -1, 0}])
}

// Every prospecting record and the explored set come back from the save
// bytes as they were.
@(test)
test_prospecting_records_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	world: World
	surface := unknown_column_surface()
	surface[33] = {block = 4, height = 37}
	world.explored[{2, -3}] = surface
	world.explored[{-1, 0}] = unknown_column_surface()
	append(&world.assayed_veins, Assayed_Vein{vein = {region = {1, 2}, index = 3}, type = 2, size_class = 1, centre = {4, 40, 5}, radius = 6})
	append(&world.assayed_veins, Assayed_Vein{vein = {index = 4}, centre = {9, 40, 9}, radius = 2, from_spent_outcrop = true, outcrop_spent = true})
	append(&world.magnetometer_readings, Magnetometer_Reading{origin = {7, 8}, offset = {-3, 9}, strength = 420, found = true})
	append(&world.core_samples, Core_Sample{position = {1, 2, 3}, bands = {5, 6, 0, 0, 0, 0, 0, 0}, band_count = 2, vein_found = true, vein_type = 4, vein_depth = 77})
	append(&world.seismic_shots, Seismic_Shot{position = {9, 1, 9}})
	append(&world.seismic_outlines, Seismic_Outline{vein = {index = 1, layer = .Deep}, centre = {0, -60, 0}, radius = 4, shot_count = 3, resolved = true})
	bytes := make([dynamic]byte)
	write_prospecting_records(&bytes, &world)
	loaded: World
	reader := Byte_Reader{data = bytes[:]}
	testing.expect(t, read_prospecting_records(&reader, &loaded))
	testing.expect_value(t, bytes_left(reader), 0)
	testing.expect_value(t, len(loaded.explored), 2)
	testing.expect_value(t, loaded.explored[{2, -3}][33], Surface_Cell{block = 4, height = 37})
	testing.expect(t, !surface_cell_is_known(loaded.explored[{-1, 0}][0]))
	testing.expect_value(t, loaded.assayed_veins[0], world.assayed_veins[0])
	testing.expect_value(t, loaded.assayed_veins[1], world.assayed_veins[1])
	testing.expect_value(t, loaded.magnetometer_readings[0], world.magnetometer_readings[0])
	testing.expect_value(t, loaded.core_samples[0], world.core_samples[0])
	testing.expect_value(t, loaded.seismic_shots[0], world.seismic_shots[0])
	testing.expect_value(t, loaded.seismic_outlines[0], world.seismic_outlines[0])
}

@(test)
test_map_frame_places_blocks_on_pixels :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	frame := map_frame_for({0.5, 0.5}, 1)
	testing.expect_value(t, frame.blocks_per_pixel, 2)
	testing.expect_value(t, frame.origin, [2]i32{-256, -256})
	pixel, inside := map_pixel_of(frame, 0, 1)
	testing.expect(t, inside)
	testing.expect_value(t, pixel, [2]i32{128, 128})
	_, inside = map_pixel_of(frame, 256, 0)
	testing.expect(t, !inside)
	testing.expect_value(t, map_block_of(frame, {128, 128}), [2]i32{1, 1})
	// An assayed footprint tints the pixels inside its disc only.
	pixels := make([]Ui_Color, MAP_IMAGE_SIZE * MAP_IMAGE_SIZE)
	paint_map_disc(pixels, frame, {0, 40, 0}, 4, MAP_ASSAYED_COLOR, 1)
	testing.expect_value(t, pixels[128 * MAP_IMAGE_SIZE + 128], MAP_ASSAYED_COLOR)
	testing.expect_value(t, pixels[128 * MAP_IMAGE_SIZE + 131], Ui_Color{})
	// Unexplored ground is dark, known ground shaded by its height.
	colors := []Ui_Color{{}, {100, 100, 100, 255}}
	testing.expect_value(t, surface_color({height = UNKNOWN_SURFACE_HEIGHT}, colors), MAP_UNEXPLORED_COLOR)
	low := surface_color({block = 1, height = TERRAIN_MINIMUM_HEIGHT}, colors)
	high := surface_color({block = 1, height = TERRAIN_MAXIMUM_HEIGHT}, colors)
	testing.expect(t, low.r < high.r)
}
