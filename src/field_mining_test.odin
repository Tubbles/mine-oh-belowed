package game

import "core:testing"

test_field_materials :: proc(items: Item_Registry) -> Field_Material_Table {
	table, problem := parse_field_material_table(#load("../data/materials.sjson"), FIELD_MATERIALS_FILE_NAME, items)
	assert(problem == "", problem)
	return table
}

test_field_simulation_content :: proc(items: Item_Registry, brush: Field_Brush) -> Field_Simulation_Content {
	brushes := make([]Field_Brush, 1, context.temp_allocator)
	brushes[0] = brush
	return Field_Simulation_Content{items = items, materials = test_field_materials(items), brushes = brushes, tuning = test_field_tuning(1000)}
}

// A player standing at feet carrying the stacks, looking straight down.
add_test_miner :: proc(simulation: ^Field_Simulation, items: Item_Registry, feet: World_Position, stacks: ..Starting_Item) {
	miner := Field_Miner {
		body      = make_field_player(feet, {UNIT_VECTOR_ONE, 0, 0}),
		inventory = make_inventory(PLAYER_INVENTORY_SLOT_COUNT),
	}
	miner.body.pitch = -FIELD_PITCH_LIMIT
	miner.body.held_material = .Stone
	for stack in stacks {
		inventory_add(miner.inventory, items, test_item(items, stack.item), stack.count)
	}
	append(&simulation.players, miner)
}

FAR_FEET :: World_Position{0, 100 * POSITION_UNITS_PER_METRE, 0}

// The volume a player holds of a material, in the credit's unit.
held_field_volume :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: int, material: Field_Material) -> i64 {
	miner := simulation.players[player]
	return field_place_volume_available(miner.inventory, content.materials[material].item, miner.credit[material])
}

drain_one_field_edit :: proc(simulation: ^Field_Simulation, content: Field_Simulation_Content, player: int, edit: Field_Edit) {
	append(&simulation.edits, Queued_Field_Edit{player = player, edit = edit})
	drain_field_edits(simulation, content)
}

// 19 samples lie within 1.5 samples of a sample; a rate of 50 takes 950
// steps, 7.48 cubic metres at 1 m: seven stone and the rest carried, which
// the next dig completes.
@(test)
test_digging_stone_credits_stone_by_volume_and_carries_the_rest :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 50))
	simulation := Field_Simulation {
		world               = make_uniform_test_field({MAXIMUM_DENSITY, .Stone, 0}),
		spacing_millimetres = 1000,
	}
	defer destroy_field_simulation(&simulation)
	add_test_miner(&simulation, items, FAR_FEET, {"wooden_pickaxe", 1})
	stone := test_item(items, "stone")
	step_volume := field_steps_to_volume(1, 1000)
	drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.brushes[0], centre = sample_to_world_position({0, 0, 0}, 1000)})
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, stone), 7)
	testing.expect_value(t, simulation.players[0].credit[.Stone], 950 * step_volume - 7 * FIELD_ITEM_VOLUME)
	drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.brushes[0], centre = sample_to_world_position({8, 8, 8}, 1000)})
	count := inventory_count(simulation.players[0].inventory, stone)
	testing.expect_value(t, count, 14)
	testing.expect_value(t, simulation.players[0].credit[.Stone], 1900 * step_volume - 14 * FIELD_ITEM_VOLUME)
	testing.expect(t, i64(count) * FIELD_ITEM_VOLUME <= 1900 * step_volume && 1900 * step_volume < i64(count + 1) * FIELD_ITEM_VOLUME, "within one item")
	testing.expect_value(t, simulation.players[0].refusal, Field_Edit_Refusal.None)
}

// One stone is a cubic metre: 127 steps of one sample at 1 m.
@(test)
test_placing_a_cubic_metre_of_stone_takes_one_item :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 254))
	simulation := Field_Simulation {
		world               = make_uniform_test_field(FIELD_AIR_SAMPLE),
		spacing_millimetres = 1000,
	}
	defer destroy_field_simulation(&simulation)
	add_test_miner(&simulation, items, FAR_FEET, {"stone", 1})
	place := Field_Edit {
		mode     = .Place,
		brush    = content.brushes[0],
		centre   = sample_to_world_position({0, 0, 0}, 1000),
		material = .Stone,
	}
	drain_one_field_edit(&simulation, content, 0, place)
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "stone")), 0)
	testing.expect_value(t, simulation.players[0].credit[.Stone], 0)
	testing.expect_value(t, field_steps_to_volume(field_ground_steps(&simulation.world), 1000), FIELD_ITEM_VOLUME)
	drain_one_field_edit(&simulation, content, 0, place)
	testing.expect_value(t, simulation.players[0].refusal, Field_Edit_Refusal.Nothing_Held)
	testing.expect_value(t, field_ground_steps(&simulation.world), MAXIMUM_DENSITY)
}

// Two players dig the same ground in one tick: the queue holds both edits
// and the field is untouched until the drain, which applies them in the
// order queued (the first takes up to the rate a sample, the second the
// rest).
@(test)
test_two_edits_of_one_tick_apply_in_order_at_its_end :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 100))
	simulation := Field_Simulation {
		world               = make_test_field(Test_Terrain{kind = .Flat}, 1000),
		spacing_millimetres = 1000,
	}
	defer destroy_field_simulation(&simulation)
	for _ in 0 ..< 2 {
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"wooden_pickaxe", 1})
	}
	before := field_ground_steps(&simulation.world)
	inputs := [2]Field_Player_Input{{held = {.Dig}}, {held = {.Dig}}}
	queue_field_player_edits(&simulation, content, inputs[:])
	testing.expect_value(t, len(simulation.edits), 2)
	testing.expect_value(t, field_ground_steps(&simulation.world), before)
	expected := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&expected)
	results: [2]Field_Edit_Result
	for queued, index in simulation.edits {
		edit := queued.edit
		edit.diggable = {.Stone}
		results[index] = apply_field_edit(&expected, 1000, edit)
	}
	drain_field_edits(&simulation, content)
	testing.expect_value(t, len(simulation.edits), 0)
	testing.expect(t, results[0].steps[.Stone] > results[1].steps[.Stone] && results[1].steps[.Stone] > 0, "the second edit took what the first left")
	for index in 0 ..< 2 {
		testing.expect_value(t, held_field_volume(&simulation, content, index, .Stone), field_steps_to_volume(results[index].steps[.Stone], 1000))
	}
	testing.expect(t, field_worlds_equal(&simulation.world, &expected), "the field is the two edits in order")
}

// A brush over ground above the carried tool's tier digs nothing and says
// why; a material without an item cannot be dug at all.
@(test)
test_a_brush_over_a_harder_material_digs_nothing :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 50))
	cases := [?]struct {
		material: Field_Material,
		tool:     string,
		refusal:  Field_Edit_Refusal,
	}{{.Deep_Stone, "wooden_pickaxe", .Tool_Tier}, {.Bedrock, "iron_pickaxe", .Undiggable}, {.Deep_Stone, "iron_pickaxe", .None}}
	for entry in cases {
		simulation := Field_Simulation {
			world               = make_uniform_test_field({MAXIMUM_DENSITY, entry.material, 0}),
			spacing_millimetres = 1000,
		}
		defer destroy_field_simulation(&simulation)
		add_test_miner(&simulation, items, FAR_FEET, {entry.tool, 1})
		before := field_ground_steps(&simulation.world)
		drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.brushes[0], centre = sample_to_world_position({0, 0, 0}, 1000)})
		testing.expect_value(t, simulation.players[0].refusal, entry.refusal)
		dug := before - field_ground_steps(&simulation.world)
		if entry.refusal == .None {
			testing.expect_value(t, dug, 19 * 50)
			continue
		}
		testing.expect_value(t, dug, 0)
		testing.expect_value(t, simulation.players[0].refused_material, entry.material)
		testing.expect_value(t, simulation.players[0].credit[entry.material], 0)
	}
}

// The queue is filled and drained inside one tick, so between ticks, where
// a save runs, it is empty and every dug step is in the player's items or
// credit: a save loses nothing the drain had not applied.
@(test)
test_the_edit_queue_is_empty_between_ticks :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 20))
	simulation := Field_Simulation {
		world               = make_test_field(Test_Terrain{kind = .Flat}, 1000),
		spacing_millimetres = 1000,
	}
	defer destroy_field_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"wooden_pickaxe", 1})
	before := field_ground_steps(&simulation.world)
	inputs := [1]Field_Player_Input{{held = {.Dig}}}
	for _ in 0 ..< 40 {
		tick_field_simulation(&simulation, content, inputs[:])
		testing.expect_value(t, len(simulation.edits), 0)
	}
	dug := before - field_ground_steps(&simulation.world)
	testing.expect(t, dug > 0, "the player dug")
	testing.expect_value(t, held_field_volume(&simulation, content, 0, .Stone), field_steps_to_volume(dug, 1000))
	testing.expect_value(t, simulation.tick, 40)
}

// The bury check reads the samples a place would raise, each widened by
// its trilinear support, at every spacing: a place on the ground beside a
// standing player is refused and takes nothing; a place at the reach is
// allowed; a level place round the player with its plane at the feet
// raises nothing on flat ground and is allowed.
@(test)
test_a_place_that_would_bury_a_player_is_refused :: proc(t: ^testing.T) {
	items := make_test_items()
	for spacing in TEST_FIELD_SPACINGS {
		content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 254))
		content.tuning = test_field_tuning(spacing)
		simulation := Field_Simulation {
			world               = make_test_field(Test_Terrain{kind = .Flat}, spacing),
			spacing_millimetres = spacing,
		}
		defer destroy_field_simulation(&simulation)
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"stone", 10})
		before := field_ground_steps(&simulation.world)
		beside := Field_Edit{mode = .Place, brush = content.brushes[0], centre = test_site_point(metres_to_position_units(1), 0, 0), material = .Stone}
		drain_one_field_edit(&simulation, content, 0, beside)
		testing.expectf(t, simulation.players[0].refusal == .Would_Bury_Player, "beside the feet at %d mm", spacing)
		testing.expect_value(t, field_ground_steps(&simulation.world), before)
		testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "stone")), 10)

		level := Field_Edit{mode = .Place, brush = test_brush(.Level, 2000, 254), centre = test_site_point(metres_to_position_units(1), 0, 0), up = {0, UNIT_VECTOR_ONE, 0}, material = .Stone}
		drain_one_field_edit(&simulation, content, 0, level)
		testing.expectf(t, simulation.players[0].refusal == .None, "a level place at the feet at %d mm", spacing)
		testing.expect_value(t, field_ground_steps(&simulation.world), before)

		at_reach := beside
		at_reach.centre = test_site_point(metres_to_position_units(4), 0, 0)
		drain_one_field_edit(&simulation, content, 0, at_reach)
		testing.expectf(t, simulation.players[0].refusal == .None, "at the reach at %d mm", spacing)
		testing.expectf(t, field_ground_steps(&simulation.world) > before, "the place at the reach raised the field at %d mm", spacing)
	}
}

// The shipped table names an item for every diggable material; a file
// missing a material, naming an unknown item or carrying an unknown key is
// refused.
@(test)
test_the_field_material_table :: proc(t: ^testing.T) {
	items := make_test_items()
	table := test_field_materials(items)
	testing.expect_value(t, table[.Stone].item, test_item(items, "stone"))
	testing.expect_value(t, table[.Topsoil].item, test_item(items, "dirt"))
	testing.expect_value(t, table[.Bedrock].item, NO_ITEM)
	testing.expect_value(t, table[.Air].item, NO_ITEM)
	testing.expect_value(t, field_diggable_materials(table, 1), bit_set[Field_Material]{.Topsoil, .Stone})
	malformed := [?]string {
		`materials = [{id = "topsoil", item = "dirt", tool_tier = 0}, {id = "stone", item = "stone", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}]`,
		`materials = [{id = "topsoil", item = "dirt", tool_tier = 0}, {id = "stone", item = "pebble", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}, {id = "bedrock", item = "", tool_tier = 0}]`,
		`materials = [{id = "topsoil", item = "dirt", tool_tier = 0, hardness = 2}, {id = "stone", item = "stone", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}, {id = "bedrock", item = "", tool_tier = 0}]`,
		`materials = [{id = "topsoil", item = "dirt"}, {id = "stone", item = "stone", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}, {id = "bedrock", item = "", tool_tier = 0}]`,
		`materials = [{id = "topsoil", item = "dirt", tool_tier = 9}, {id = "stone", item = "stone", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}, {id = "bedrock", item = "", tool_tier = 0}]`,
		`materials = [{id = "topsoil", item = "dirt", tool_tier = 0}, {id = "stone", item = "stone", tool_tier = 1}, {id = "stone", item = "stone", tool_tier = 1}, {id = "deep_stone", item = "deep_stone", tool_tier = 3}, {id = "bedrock", item = "", tool_tier = 0}]`,
	}
	for text in malformed {
		_, problem := parse_field_material_table(transmute([]byte)text, "test", items)
		testing.expect(t, problem != "", text)
	}
}

// The brush key cycles the brushes, the material key the materials with
// an item.
@(test)
test_the_tool_keys_cycle_brushes_and_materials :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	brushes := [2]Field_Brush{test_brush(.Sphere, 1000, 10), test_brush(.Level, 2000, 5)}
	content.brushes = brushes[:]
	player := Field_Player {
		held_material = .Stone,
	}
	update_field_tool(&player, Field_Player_Input{just_pressed = {.Next_Brush, .Next_Material}}, content)
	testing.expect_value(t, player.brush, 1)
	testing.expect_value(t, player.held_material, Field_Material.Deep_Stone)
	update_field_tool(&player, Field_Player_Input{just_pressed = {.Next_Brush, .Next_Material}}, content)
	testing.expect_value(t, player.brush, 0)
	testing.expect_value(t, player.held_material, Field_Material.Topsoil)
}

// The shipped brushes pass; an empty list, an unknown shape, a twice used
// id and a rate out of bounds are refused.
@(test)
test_the_field_brushes_are_bounded :: proc(t: ^testing.T) {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, field_brushes_problem(config.field_brushes), "")
	testing.expect_value(t, len(config.field_brushes), 3)
	good := Field_Brush_Config{id = "a", shape = "sphere", radius_millimetres = 1000, rate_density_steps_per_tick = 5}
	bad_shape, bad_rate := good, good
	bad_shape.shape = "cube"
	bad_rate.rate_density_steps_per_tick = MAXIMUM_FIELD_BRUSH_RATE + 1
	cases := [?][]Field_Brush_Config{{}, {bad_shape}, {good, good}, {bad_rate}}
	for brushes in cases {
		testing.expect(t, field_brushes_problem(brushes) != "")
	}
}
