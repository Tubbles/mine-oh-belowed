package game

import "core:strings"
import "core:testing"

test_field_materials :: proc(items: Item_Registry) -> Field_Material_Table {
	table, problem := parse_field_material_table(#load("../data/materials.sjson"), FIELD_MATERIALS_FILE_NAME, items)
	assert(problem == "", problem)
	return table
}

test_field_simulation_content :: proc(items: Item_Registry, brush: Field_Brush) -> Simulation_Content {
	brushes := make([]Field_Brush, 1, context.temp_allocator)
	brushes[0] = brush
	content := Simulation_Content {
		items = items,
	}
	content.field = Field_Content {
		materials = test_field_materials(items),
		brushes   = brushes,
		tuning    = test_field_tuning(1000),
	}
	return content
}

// A field session's state with nothing but the field world and the tick
// rate; destroy_simulation frees it.
make_test_field_state :: proc(world: Field_World, spacing_millimetres: int) -> Simulation_State {
	return Simulation_State{field = Field_Simulation{enabled = true, world = world, spacing_millimetres = spacing_millimetres}, tick_rate = 60}
}

// The field's part of a tick on field inputs with the tools the test set
// (the hotbar is not read): each player moves and queues, then the queues
// drain, the water steps and the light spreads.
tick_field_simulation :: proc(state: ^Simulation_State, content: Simulation_Content, inputs: []Field_Player_Input) {
	state.tick += 1
	for index in 0 ..< len(state.players) {
		queue_field_player_edit(state, content, index, index < len(inputs) ? inputs[index] : Field_Player_Input{})
	}
	finish_field_tick(state, content)
}

// A player standing at feet carrying the stacks, looking straight down,
// placing stone.
add_test_miner :: proc(simulation: ^Simulation_State, items: Item_Registry, feet: World_Position, stacks: ..Starting_Item) {
	miner := make_player(Player_Start{})
	miner.field = make_field_player(feet, {UNIT_VECTOR_ONE, 0, 0})
	miner.field.pitch = -FIELD_PITCH_LIMIT
	miner.field.held_material = .Stone
	miner.field.tool = .Material
	for stack in stacks {
		inventory_add(miner.inventory, items, test_item(items, stack.item), stack.count)
	}
	append(&simulation.players, miner)
}

// The player holds the item as update_field_held_tool would set it from
// the hotbar (0265): the tool, and a shovel's, pickaxe's or axe's role and
// tier.
hold_test_item :: proc(player: ^Player, content: Simulation_Content, item_id: string) {
	item := test_item(content.items, item_id)
	tool, _, _ := field_tool_for_item(content, item)
	player.field.tool = tool
	player.field.held_tool_role, player.field.held_tool_tier = held_tool_role_and_tier(content.items, tool, item)
}

FAR_FEET :: World_Position{0, 100 * POSITION_UNITS_PER_METRE, 0}

// The volume a player holds of a material, in the credit's unit.
held_field_volume :: proc(simulation: ^Simulation_State, content: Simulation_Content, player: int, material: Field_Material) -> i64 {
	miner := simulation.players[player]
	return field_place_volume_available(miner.inventory, content.field.materials[material].item, miner.field_credit[material])
}

drain_one_field_edit :: proc(simulation: ^Simulation_State, content: Simulation_Content, player: int, edit: Field_Edit) {
	append(&simulation.field.edits, Queued_Field_Edit{player = player, edit = edit})
	drain_field_edits(simulation, content)
}

// 19 samples lie within 1.5 samples of a sample; a rate of 50 takes 950
// steps, 7.48 cubic metres at 1 m: seven stone and the rest carried, which
// the next dig completes.
@(test)
test_digging_stone_credits_stone_by_volume_and_carries_the_rest :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 50))
	simulation := make_test_field_state(make_uniform_test_field({MAXIMUM_DENSITY, .Stone, 0}), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, FAR_FEET, {"wooden_pickaxe", 1})
	hold_test_item(&simulation.players[0], content, "wooden_pickaxe")
	stone := test_item(items, "stone")
	step_volume := field_steps_to_volume(1, 1000)
	drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.field.brushes[0], centre = sample_to_world_position({0, 0, 0}, 1000)})
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, stone), 7)
	testing.expect_value(t, simulation.players[0].field_credit[.Stone], 950 * step_volume - 7 * FIELD_ITEM_VOLUME)
	drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.field.brushes[0], centre = sample_to_world_position({8, 8, 8}, 1000)})
	count := inventory_count(simulation.players[0].inventory, stone)
	testing.expect_value(t, count, 14)
	testing.expect_value(t, simulation.players[0].field_credit[.Stone], 1900 * step_volume - 14 * FIELD_ITEM_VOLUME)
	testing.expect(t, i64(count) * FIELD_ITEM_VOLUME <= 1900 * step_volume && 1900 * step_volume < i64(count + 1) * FIELD_ITEM_VOLUME, "within one item")
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.None)
}

// One stone is a cubic metre: 127 steps of one sample at 1 m.
@(test)
test_placing_a_cubic_metre_of_stone_takes_one_item :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 254))
	simulation := make_test_field_state(make_uniform_test_field(FIELD_AIR_SAMPLE), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, FAR_FEET, {"stone", 1})
	place := Field_Edit {
		mode     = .Place,
		brush    = content.field.brushes[0],
		centre   = sample_to_world_position({0, 0, 0}, 1000),
		material = .Stone,
	}
	drain_one_field_edit(&simulation, content, 0, place)
	testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "stone")), 0)
	testing.expect_value(t, simulation.players[0].field_credit[.Stone], 0)
	testing.expect_value(t, field_steps_to_volume(field_ground_steps(&simulation.field.world), 1000), FIELD_ITEM_VOLUME)
	drain_one_field_edit(&simulation, content, 0, place)
	testing.expect_value(t, simulation.players[0].field_refusal, Field_Edit_Refusal.Nothing_Held)
	testing.expect_value(t, field_ground_steps(&simulation.field.world), MAXIMUM_DENSITY)
}

// Two players dig the same ground in one tick: the queue holds both edits
// and the field is untouched until the drain, which applies them in the
// order queued (the first takes up to the rate a sample, the second the
// rest).
@(test)
test_two_edits_of_one_tick_apply_in_order_at_its_end :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1500, 100))
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	for index in 0 ..< 2 {
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"wooden_pickaxe", 1})
		hold_test_item(&simulation.players[index], content, "wooden_pickaxe")
	}
	before := field_ground_steps(&simulation.field.world)
	inputs := [2]Field_Player_Input{{held = {.Dig}}, {held = {.Dig}}}
	for input, index in inputs {
		queue_field_player_edit(&simulation, content, index, input)
	}
	testing.expect_value(t, len(simulation.field.edits), 2)
	testing.expect_value(t, field_ground_steps(&simulation.field.world), before)
	expected := make_test_field(Test_Terrain{kind = .Flat}, 1000)
	defer destroy_field_world(&expected)
	results: [2]Field_Edit_Result
	for queued, index in simulation.field.edits {
		edit := queued.edit
		edit.diggable = {.Stone}
		results[index] = apply_field_edit(&expected, 1000, edit)
	}
	drain_field_edits(&simulation, content)
	testing.expect_value(t, len(simulation.field.edits), 0)
	testing.expect(t, results[0].steps[.Stone] > results[1].steps[.Stone] && results[1].steps[.Stone] > 0, "the second edit took what the first left")
	for index in 0 ..< 2 {
		testing.expect_value(t, held_field_volume(&simulation, content, index, .Stone), field_steps_to_volume(results[index].steps[.Stone], 1000))
	}
	testing.expect(t, field_worlds_equal(&simulation.field.world, &expected), "the field is the two edits in order")
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
		simulation := make_test_field_state(make_uniform_test_field({MAXIMUM_DENSITY, entry.material, 0}), 1000)
		defer destroy_simulation(&simulation)
		add_test_miner(&simulation, items, FAR_FEET, {entry.tool, 1})
		hold_test_item(&simulation.players[0], content, entry.tool)
		before := field_ground_steps(&simulation.field.world)
		drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.field.brushes[0], centre = sample_to_world_position({0, 0, 0}, 1000)})
		testing.expect_value(t, simulation.players[0].field_refusal, entry.refusal)
		dug := before - field_ground_steps(&simulation.field.world)
		if entry.refusal == .None {
			// Deep stone digs at its dig_rate_percent of 60 (0179).
			testing.expect_value(t, dug, 19 * 50 * 60 / 100)
			continue
		}
		testing.expect_value(t, dug, 0)
		testing.expect_value(t, simulation.players[0].field_refused_material, entry.material)
		testing.expect_value(t, simulation.players[0].field_credit[entry.material], 0)
	}
}

// The queue is filled and drained inside one tick, so between ticks, where
// a save runs, it is empty and every dug step is in the player's items or
// credit: a save loses nothing the drain had not applied.
@(test)
test_the_edit_queue_is_empty_between_ticks :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 20))
	simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, 1000), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"wooden_pickaxe", 1})
	hold_test_item(&simulation.players[0], content, "wooden_pickaxe")
	before := field_ground_steps(&simulation.field.world)
	inputs := [1]Field_Player_Input{{held = {.Dig}}}
	for _ in 0 ..< 40 {
		tick_field_simulation(&simulation, content, inputs[:])
		testing.expect_value(t, len(simulation.field.edits), 0)
	}
	dug := before - field_ground_steps(&simulation.field.world)
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
		content.field.tuning = test_field_tuning(spacing)
		simulation := make_test_field_state(make_test_field(Test_Terrain{kind = .Flat}, spacing), spacing)
		defer destroy_simulation(&simulation)
		add_test_miner(&simulation, items, test_site_point(0, 0, 0), {"stone", 10})
		before := field_ground_steps(&simulation.field.world)
		beside := Field_Edit{mode = .Place, brush = content.field.brushes[0], centre = test_site_point(metres_to_position_units(1), 0, 0), material = .Stone}
		drain_one_field_edit(&simulation, content, 0, beside)
		testing.expectf(t, simulation.players[0].field_refusal == .Would_Bury_Player, "beside the feet at %d mm", spacing)
		testing.expect_value(t, field_ground_steps(&simulation.field.world), before)
		testing.expect_value(t, inventory_count(simulation.players[0].inventory, test_item(items, "stone")), 10)

		level := Field_Edit{mode = .Place, brush = test_brush(.Level, 2000, 254), centre = test_site_point(metres_to_position_units(1), 0, 0), up = {0, UNIT_VECTOR_ONE, 0}, material = .Stone}
		drain_one_field_edit(&simulation, content, 0, level)
		testing.expectf(t, simulation.players[0].field_refusal == .None, "a level place at the feet at %d mm", spacing)
		testing.expect_value(t, field_ground_steps(&simulation.field.world), before)

		at_reach := beside
		at_reach.centre = test_site_point(metres_to_position_units(4), 0, 0)
		drain_one_field_edit(&simulation, content, 0, at_reach)
		testing.expectf(t, simulation.players[0].field_refusal == .None, "at the reach at %d mm", spacing)
		testing.expectf(t, field_ground_steps(&simulation.field.world) > before, "the place at the reach raised the field at %d mm", spacing)
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
	testing.expect_value(t, field_diggable_materials(table, .Pickaxe, 1), bit_set[Field_Material]{.Stone, .Coal_Ore})
	testing.expect_value(t, field_diggable_materials(table, .Shovel, 3), bit_set[Field_Material]{.Topsoil})
	testing.expect_value(t, field_diggable_materials(table, .Axe, 3), bit_set[Field_Material]{})
	testing.expect_value(t, field_diggable_materials(table, .None, 0), bit_set[Field_Material]{})
	// The dig rates (0179): soft topsoil faster, deep stone slower.
	testing.expect_value(t, table[.Topsoil].dig_rate_percent, 150)
	testing.expect_value(t, table[.Stone].dig_rate_percent, 100)
	testing.expect_value(t, table[.Deep_Stone].dig_rate_percent, 60)
	malformed := [?]string {
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 100}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 100}, {id = "stone", item = "pebble", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 100, hardness = 2}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", dig_rate_percent = 100}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 9, dig_rate_percent = 100}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 100}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 9}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
		`materials = [{id = "topsoil", item = "dirt", dug_with = "shovel", tool_tier = 1, dig_rate_percent = 401}, {id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 1, dig_rate_percent = 100}, {id = "deep_stone", item = "deep_stone", dug_with = "pickaxe", tool_tier = 3, dig_rate_percent = 100}, {id = "bedrock", item = "", dug_with = "", tool_tier = 0, dig_rate_percent = 100}]`,
	}
	for text in malformed {
		_, problem := parse_field_material_table(transmute([]byte)text, "test", items)
		testing.expect(t, problem != "", text)
	}
	_, problem := parse_field_material_table(transmute([]byte)malformed[len(malformed) - 2], "test", items)
	testing.expect(t, strings.contains(problem, "dig_rate_percent 9 is outside 10 to 400"), problem)
	_, problem = parse_field_material_table(transmute([]byte)malformed[len(malformed) - 3], "test", items)
	testing.expect(t, strings.contains(problem, "missing dig_rate_percent"), problem)
}

// One dig of a uniform field of the material by a player holding the
// tool: what the dig took and the refusal it left.
dig_uniform_test_field :: proc(content: Simulation_Content, material: Field_Material, tool: string) -> (dug: i64, credited: int, refusal: Field_Edit_Refusal) {
	simulation := make_test_field_state(make_uniform_test_field({MAXIMUM_DENSITY, material, 0}), 1000)
	defer destroy_simulation(&simulation)
	add_test_miner(&simulation, content.items, FAR_FEET, {tool, 1})
	hold_test_item(&simulation.players[0], content, tool)
	before := field_ground_steps(&simulation.field.world)
	drain_one_field_edit(&simulation, content, 0, Field_Edit{mode = .Dig, brush = content.field.brushes[0], centre = sample_to_world_position({0, 0, 0}, 1000)})
	item := content.field.materials[material].item
	return before - field_ground_steps(&simulation.field.world), inventory_count(simulation.players[0].inventory, item), simulation.players[0].field_refusal
}

// A shovel digs topsoil into dirt and leaves stone, telling the pickaxe
// it needs (0265).
@(test)
test_the_shovel_digs_topsoil_and_not_stone :: proc(t: ^testing.T) {
	content := test_field_simulation_content(make_test_items(), test_brush(.Sphere, 1500, 254))
	dug, credited, refusal := dig_uniform_test_field(content, .Topsoil, "wooden_shovel")
	testing.expect(t, dug > 0 && credited > 0, "the shovel dug topsoil into dirt")
	testing.expect_value(t, refusal, Field_Edit_Refusal.None)
	dug, credited, refusal = dig_uniform_test_field(content, .Stone, "wooden_shovel")
	testing.expect_value(t, dug, 0)
	testing.expect_value(t, credited, 0)
	testing.expect_value(t, refusal, Field_Edit_Refusal.Needs_Pickaxe)
}

// A pickaxe digs stone and leaves topsoil, telling the shovel it needs
// (0265); deep stone still wants a better pickaxe.
@(test)
test_the_pickaxe_digs_stone_and_not_topsoil :: proc(t: ^testing.T) {
	content := test_field_simulation_content(make_test_items(), test_brush(.Sphere, 1500, 254))
	dug, credited, refusal := dig_uniform_test_field(content, .Stone, "wooden_pickaxe")
	testing.expect(t, dug > 0 && credited > 0, "the pickaxe dug stone")
	testing.expect_value(t, refusal, Field_Edit_Refusal.None)
	dug, credited, refusal = dig_uniform_test_field(content, .Topsoil, "wooden_pickaxe")
	testing.expect_value(t, dug, 0)
	testing.expect_value(t, credited, 0)
	testing.expect_value(t, refusal, Field_Edit_Refusal.Needs_Shovel)
	_, _, refusal = dig_uniform_test_field(content, .Deep_Stone, "wooden_pickaxe")
	testing.expect_value(t, refusal, Field_Edit_Refusal.Tool_Tier)
}

// An item with a tool_role is the Tool with its role and tier (0265); a
// role-less item, the geologist's hammer included, is the hand.
@(test)
test_field_tool_for_item_reads_the_role :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.torch_item = test_item(items, "torch")
	cases := [?]struct {
		item: string,
		tool: Field_Held_Tool,
		role: Item_Tool_Role,
		tier: u8,
	}{
		{"wooden_pickaxe", .Tool, .Pickaxe, 1},
		{"iron_pickaxe", .Tool, .Pickaxe, 3},
		{"wooden_shovel", .Tool, .Shovel, 1},
		{"stone_shovel", .Tool, .Shovel, 2},
		{"wooden_axe", .Tool, .Axe, 1},
		{"iron_axe", .Tool, .Axe, 3},
		{"plank", .Hand, .None, 0},
		{"geologists_hammer", .Hand, .None, 0},
		{"stone", .Material, .None, 0},
		{"torch", .Torch, .None, 0},
		{"wooden_chest", .Machine, .None, 0},
	}
	for entry in cases {
		item := test_item(items, entry.item)
		tool, _, _ := field_tool_for_item(content, item)
		role, tier := held_tool_role_and_tier(items, tool, item)
		testing.expectf(t, tool == entry.tool && role == entry.role && tier == entry.tier, "%s: %v %v %d", entry.item, tool, role, tier)
	}
}

// The shipped table names the role and tier of each material (0265); a
// material dug with an axe, an item without a role, bedrock with a role
// and a role at tier 0 are refused.
@(test)
test_the_material_table_needs_a_digging_role :: proc(t: ^testing.T) {
	items := make_test_items()
	table := test_field_materials(items)
	expected := [Field_Material]struct {
		role: Item_Tool_Role,
		tier: int,
	} {
		.Air              = {.None, 0},
		.Topsoil          = {.Shovel, 1},
		.Stone            = {.Pickaxe, 1},
		.Deep_Stone       = {.Pickaxe, 3},
		.Bedrock          = {.None, 0},
		.Hematite_Ore     = {.Pickaxe, 2},
		.Chalcopyrite_Ore = {.Pickaxe, 2},
		.Coal_Ore         = {.Pickaxe, 1},
	}
	for record, material in table {
		testing.expectf(t, record.dug_with == expected[material].role && record.tool_tier == expected[material].tier, "%v: %v %d", material, record.dug_with, record.tool_tier)
	}
	refused := [?]struct {
		definition: Field_Material_Definition,
		problem:    string,
	}{
		{{id = "stone", item = "stone", dug_with = "axe", tool_tier = 1, dig_rate_percent = 100}, "dug_with \"axe\" is not shovel, pickaxe or empty"},
		{{id = "stone", item = "stone", dug_with = "", tool_tier = 1, dig_rate_percent = 100}, "dug_with \"\" needs an item"},
		{{id = "bedrock", item = "", dug_with = "shovel", tool_tier = 0, dig_rate_percent = 100}, "dug_with \"shovel\" needs an item"},
		{{id = "stone", item = "stone", dug_with = "pickaxe", tool_tier = 0, dig_rate_percent = 100}, "tool_tier 0 is outside 1 to 3"},
	}
	for entry in refused {
		_, problem := field_material_record(entry.definition, items)
		testing.expectf(t, strings.contains(problem, entry.problem), "%s: %s", entry.definition.id, problem)
	}
}

// The hotbar's stack decides the tool (0179): stone places stone, a
// foundation the foundation, the torch the torch, a pickaxe the Tool (0265);
// the brush key cycles the brushes, and turns a held machine instead.
@(test)
test_the_hotbar_decides_the_field_tool :: proc(t: ^testing.T) {
	items := make_test_items()
	content := test_field_simulation_content(items, test_brush(.Sphere, 1000, 10))
	content.machines = make_test_machines()
	content.field.pad_foundation = find_foundation_machine(content.machines)
	content.field.torch_item = test_item(items, "torch")
	brushes := [2]Field_Brush{test_brush(.Sphere, 1000, 10), test_brush(.Level, 2000, 5)}
	content.field.brushes = brushes[:]
	player := make_player(Player_Start{})
	defer destroy_player(player)
	cases := [?]struct {
		item: string,
		tool: Field_Held_Tool,
	}{{"stone", .Material}, {"wooden_foundation", .Foundation}, {"torch", .Torch}, {"wooden_pickaxe", .Tool}, {"wooden_chest", .Machine}}
	for entry, slot in cases {
		inventory_add(player.inventory, items, test_item(items, entry.item), 1)
		player.selected_hotbar_slot = slot
		update_field_held_tool(&player, content, {})
		testing.expectf(t, player.field.tool == entry.tool, "%s: %v", entry.item, player.field.tool)
	}
	update_field_held_tool(&player, content, {just_pressed = {.Next_Brush}})
	testing.expect_value(t, player.field.placement_rotation, 1)
	testing.expect_value(t, player.field.brush, 0)
	player.selected_hotbar_slot = 0
	update_field_held_tool(&player, content, {just_pressed = {.Next_Brush}})
	testing.expect_value(t, player.field.held_material, Field_Material.Stone)
	testing.expect_value(t, player.field.brush, 1)
}

// The inventory view's Foundation_Block_Command (0193) sets the field
// player's two indices as they are, wrapping nothing; an index past
// either list is refused with Action_Refused and changes nothing; the
// command crosses the network unchanged. Rotate_Building with a
// foundation held still cycles the brush and leaves the block alone. The
// tool line names the block, and the shipped lists pass their bounds.
@(test)
test_the_foundation_block_command_sets_the_indices :: proc(t: ^testing.T) {
	use_shipped_strings()
	defer thread_string_table = nil
	simulation, content, items, _ := make_field_placement_test()
	defer destroy_simulation(&simulation)
	with_test_foundation_blocks(&content)
	brushes := [2]Field_Brush{test_brush(.Sphere, 1000, 10), test_brush(.Level, 2000, 5)}
	content.field.brushes = brushes[:]
	queue_player_command(&simulation.player_commands, 0, Foundation_Block_Command{size_index = 2, height_index = 1})
	apply_player_commands(&simulation, content)
	field := &simulation.players[0].field
	testing.expect_value(t, [2]u8{field.foundation_size_index, field.foundation_height_index}, [2]u8{2, 1})
	size, height := field_foundation_block(field^, content.field)
	testing.expect_value(t, foundation_block_line(size, height), "Foundation 5x5, 2 high")
	refused := [?]Foundation_Block_Command{{size_index = len(TEST_FOUNDATION_SIZES), height_index = 0}, {size_index = 0, height_index = len(TEST_FOUNDATION_HEIGHTS)}, {size_index = -1, height_index = 0}}
	for command in refused {
		clear(&simulation.events)
		queue_player_command(&simulation.player_commands, 0, command)
		apply_player_commands(&simulation, content)
		testing.expect_value(t, [2]u8{field.foundation_size_index, field.foundation_height_index}, [2]u8{2, 1})
		testing.expect_value(t, len(simulation.events), 1)
		testing.expect_value(t, simulation.events[0].kind, Player_Event.Action_Refused)
	}
	bytes := make([dynamic]byte, context.temp_allocator)
	encode_player_command(&bytes, Foundation_Block_Command{size_index = 3, height_index = 2})
	reader := Byte_Reader{data = bytes[:]}
	decoded, ok := decode_player_command(&reader)
	testing.expect(t, ok)
	testing.expect_value(t, decoded.(Foundation_Block_Command), Foundation_Block_Command{size_index = 3, height_index = 2})
	player := &simulation.players[0]
	inventory_hotbar(player.inventory)[player.selected_hotbar_slot] = Item_Stack{test_item(items, "wooden_foundation"), 1}
	update_field_held_tool(player, content, {held = {.Sneak}, just_pressed = {.Next_Brush}})
	testing.expect_value(t, field.tool, Field_Held_Tool.Foundation)
	testing.expect_value(t, field.brush, 1)
	testing.expect_value(t, [2]u8{field.foundation_size_index, field.foundation_height_index}, [2]u8{2, 1})
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	testing.expect_value(t, error, nil)
	testing.expect_value(t, foundation_block_list_problem("foundation_sizes", config.foundation_sizes), "")
	testing.expect_value(t, foundation_block_list_problem("foundation_heights", config.foundation_heights), "")
	too_wide := [?]int{1, MAXIMUM_FOUNDATION_BLOCK_CELLS + 1}
	testing.expect(t, foundation_block_list_problem("foundation_sizes", too_wide[:]) != "")
	testing.expect(t, foundation_block_list_problem("foundation_sizes", {}) != "")
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
