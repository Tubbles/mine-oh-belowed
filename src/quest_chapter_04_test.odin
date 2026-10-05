package game

import "core:fmt"
import "core:slice"
import "core:testing"

// Chapter 4 (data/quests/chapter_04.sjson), the power hint counters
// brownout_ticks and unpowered_machine_ticks, and the research
// completion notice.

chapter_04_registry :: proc(references: Quest_References) -> Quest_Registry {
	files := shipped_chapter_files()
	registry, problem := resolve_quest_registry(files[3:4], references, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

make_chapter_04_test :: proc() -> Quest_Test {
	references := make_test_quest_references()
	registry := chapter_04_registry(references)
	test := make_quest_test(registry.quests, registry.chapters)
	test.statistics = make_statistics(len(test.items.items), len(test.machines.machines), 4, context.temp_allocator)
	return test
}

@(test)
test_chapter_04_loads :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := chapter_04_registry(references)
	ids := [?]string{"steam", "first_pole", "first_research", "assembly", "electric_drill", "second_engine", "first_contract"}
	testing.expect_value(t, len(registry.quests), len(ids))
	for id, index in ids {
		testing.expect_value(t, registry.quests[index].id, id)
	}
	first_research := registry.quests[2]
	testing.expect_value(t, first_research.objectives[1].technology, test_technology(references.technologies, "automation"))
	testing.expect_value(t, first_research.hints[0], Hint{counter = .Brownout_Ticks, threshold = 600, text_key = "mc_hint_brownout"})
	testing.expect_value(t, first_research.hints[1], Hint{counter = .Unpowered_Machine_Ticks, threshold = 1800, text_key = "mc_hint_unpowered"})
	testing.expect(t, registry.quests[3].objectives[1].produced_since_active)
	contract := registry.quests[6]
	testing.expect(t, contract.main)
	testing.expect_value(t, contract.objectives[0].type, Objective_Type.Deliver)
	testing.expect_value(t, contract.objectives[0].count, 100)
	crusher, washer := test_item(references.items, "crusher"), test_item(references.items, "washer")
	testing.expect_value(t, len(contract.reward_items), 2)
	testing.expect_value(t, contract.reward_items[0], Item_Stack{crusher, 1})
	testing.expect_value(t, contract.reward_items[1], Item_Stack{washer, 1})
}

// What the quests so far have opened: technologies researched by research
// objectives and recipes unlocked by rewards.
Quest_Gates :: struct {
	researched:     []bool,
	quest_unlocked: []bool,
}

recipe_reachable :: proc(recipe: Recipe, index: int, gates: Quest_Gates) -> bool {
	switch recipe.channel {
	case .Start, .Discovery:
		return true
	case .Research:
		return gates.researched[recipe.technology]
	case .Quest:
		return gates.quest_unlocked[index]
	case .Schematic:
		// Found in caves, never a quest's path.
		return false
	}
	return false
}

// An item mined from a block (ore, logs), or that no recipe makes, is
// reachable by mining; ore is also made by the washer (work item 0026).
item_reachable :: proc(items: Item_Registry, recipes: Recipe_Registry, item: Item_Id, gates: Quest_Gates) -> bool {
	if slice.contains(items.drop_for_block, item) {
		return true
	}
	made := false
	for recipe, index in recipes.recipes {
		for output in recipe.outputs {
			if output.item == item {
				made = true
				if recipe_reachable(recipe, index, gates) {
					return true
				}
			}
		}
	}
	return !made
}

objective_item :: proc(objective: Objective, machines: Machine_Registry) -> Item_Id {
	#partial switch objective.type {
	case .Place:
		return objective.machine == NO_MACHINE ? objective.item : machines.machines[objective.machine].item
	case .Obtain, .Craft, .Deliver, .Sustain:
		return objective.item
	}
	return NO_ITEM
}

// A research objective opens its technology for the quest's other
// objectives; its prerequisites must be open already.
open_quest_research :: proc(t: ^testing.T, quest: Quest, technologies: Technology_Registry, gates: Quest_Gates) {
	for objective in quest.objectives {
		if objective.type != .Research {
			continue
		}
		for prerequisite in technologies.technologies[objective.technology].prerequisites {
			testing.expectf(t, gates.researched[prerequisite], "quest %s researches %d before its prerequisite %d", quest.id, objective.technology, prerequisite)
		}
		gates.researched[objective.technology] = true
	}
}

// The lowest tool_tier among the blocks mining yields the item from.
item_block_tool_tier :: proc(items: Item_Registry, blocks: Block_Registry, item: Item_Id) -> (tier: int, from_block: bool) {
	for block in 0 ..< len(items.drop_for_block) {
		if items.drop_for_block[block] == item || items.extra_drop_for_block[block] == item {
			block_tier := block_tool_tier(blocks, Block_Id(block))
			tier = from_block ? min(tier, block_tier) : block_tier
			from_block = true
		}
	}
	return
}

// Work item 0051: an obtain or place objective whose item comes from a
// block, or a mining_ticks hint, must not need a pickaxe above tool_tier.
quest_tool_tier_problem :: proc(quest: Quest, references: Quest_References, tool_tier: int) -> string {
	for objective in quest.objectives {
		if objective.type != .Obtain && objective.type != .Place {
			continue
		}
		item := objective_item(objective, references.machines)
		if tier, from_block := item_block_tool_tier(references.items, references.blocks, item); from_block && tier > tool_tier {
			return fmt.tprintf("quest %s needs %s, mined with tool_tier %d, the quests so far reach %d", quest.id, references.items.items[item].id, tier, tool_tier)
		}
	}
	for hint in quest.hints {
		if hint.counter == .Mining_Ticks && block_tool_tier(references.blocks, hint.block) > tool_tier {
			return fmt.tprintf("quest %s hints at mining %s above tool_tier %d", quest.id, references.blocks.definitions[hint.block].id, tool_tier)
		}
	}
	return ""
}

// Every pickaxe recipe is a start recipe, so recipe availability alone
// would allow the iron pickaxe from the first quest. The tier that counts
// is the best pickaxe an earlier quest had the player craft or obtain, or
// gave as a reward; a shovel or an axe does not count (0265).
quest_granted_tool_tier :: proc(quest: Quest, items: Item_Registry, tool_tier: int) -> int {
	tier := tool_tier
	for objective in quest.objectives {
		if (objective.type == .Craft || objective.type == .Obtain) && int(objective.item) < len(items.items) {
			tier = max(tier, pickaxe_tool_tier(items.items[objective.item]))
		}
	}
	for reward in quest.reward_items {
		tier = max(tier, pickaxe_tool_tier(items.items[reward.item]))
	}
	return tier
}

pickaxe_tool_tier :: proc(item: Item) -> int {
	return item.tool_role == .Pickaxe ? item.tool_tier : 0
}

// Played in order, no quest asks for an item whose every recipe is still
// locked, and research objectives come after their prerequisites. Reward
// technologies count as researched from the next quest on. No quest asks
// for a block above the pickaxe the starter kit and the earlier quests put
// in hand.
@(test)
test_shipped_quests_never_need_a_locked_recipe :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := make_test_quests(references)
	gates := Quest_Gates {
		researched     = make([]bool, len(references.technologies.technologies), context.temp_allocator),
		quest_unlocked = make([]bool, len(references.recipes.recipes), context.temp_allocator),
	}
	tool_tier := starter_kit_tool_tier(references.items)
	for quest in registry.quests {
		testing.expect_value(t, quest_tool_tier_problem(quest, references, tool_tier), "")
		tool_tier = quest_granted_tool_tier(quest, references.items, tool_tier)
		open_quest_research(t, quest, references.technologies, gates)
		for objective in quest.objectives {
			item := objective_item(objective, references.machines)
			if item != NO_ITEM {
				testing.expectf(t, item_reachable(references.items, references.recipes, item, gates), "quest %s needs %s", quest.id, references.items.items[item].id)
			}
		}
		for recipe in quest.reward_recipes {
			gates.quest_unlocked[recipe] = true
		}
		for technology in quest.reward_technologies {
			gates.researched[technology] = true
		}
	}
}

// The tool tier the quests start from: the best pickaxe of the shipped
// starter kit, which has none (work item 0265), so 0.
starter_kit_tool_tier :: proc(items: Item_Registry) -> int {
	config, error := parse_game_config(#load("../data/game.sjson"), context.temp_allocator)
	assert(error == nil)
	tier := 0
	for stack in config.starting_items {
		tier = max(tier, pickaxe_tool_tier(items.items[test_item(items, stack.item)]))
	}
	return tier
}

// Chapter 1 crafts its pickaxes before it digs (0265): the stone quest
// asks too much without a pickaxe and passes with the wooden one the
// tools quest crafts, the rocks quest crafts the stone one. A deep stone
// hint asks more than the stone pickaxe gives.
@(test)
test_chapter_one_crafts_its_pickaxes_before_it_digs :: proc(t: ^testing.T) {
	references := make_test_quest_references()
	registry := make_test_quests(references)
	stone := registry.quests[test_quest_index(registry, "stone")]
	rocks := registry.quests[test_quest_index(registry, "rocks")]
	tools := registry.quests[test_quest_index(registry, "tools")]
	testing.expect_value(t, starter_kit_tool_tier(references.items), 0)
	testing.expect(t, quest_tool_tier_problem(stone, references, 0) != "")
	testing.expect_value(t, quest_tool_tier_problem(stone, references, 1), "")
	testing.expect_value(t, quest_tool_tier_problem(rocks, references, 2), "")
	hints := []Hint{{counter = .Mining_Ticks, block = test_block(references.blocks, "deep_stone"), threshold = 1}}
	testing.expect(t, quest_tool_tier_problem(Quest{id = "deep", hints = hints}, references, 2) != "")
	testing.expect_value(t, quest_granted_tool_tier(tools, references.items, 0), 1)
	testing.expect_value(t, quest_granted_tool_tier(rocks, references.items, 0), 2)
}

@(test)
test_power_counters_count_brownouts_and_unpowered_machines :: proc(t: ^testing.T) {
	statistics: Statistics
	networks: Electric_Networks
	networks.networks = make([dynamic]Electric_Network, context.temp_allocator)
	networks.participants = make([dynamic]Electric_Participant, context.temp_allocator)
	append(&networks.networks, Electric_Network{supply = 50, demand = 100, delivered = 50, satisfaction = POWER_FULL / 2})
	append(&networks.participants, Electric_Participant{network = 0, offered = 100, delivered = 50})
	append(&networks.participants, Electric_Participant{network = -1})
	append(&networks.participants, Electric_Participant{network = -1, generator = true})
	record_electric_tick(&statistics, &networks)
	record_electric_tick(&statistics, &networks)
	testing.expect_value(t, statistics.brownout_ticks, 2)
	testing.expect_value(t, statistics.unpowered_machine_ticks, 2)
	// Full satisfaction is no brownout.
	networks.networks[0].satisfaction = POWER_FULL
	record_electric_tick(&statistics, &networks)
	testing.expect_value(t, statistics.brownout_ticks, 2)
	// A lamp in the world with no pole near it counts every tick.
	content := make_test_content()
	world := make_floor_world(content.blocks, 32)
	records: Game_Records
	place_test_entity(&world, content, "lamp", {3, 1, 3})
	tick_test_entities(&world, &records, content, 10)
	testing.expect_value(t, records.statistics.unpowered_machine_ticks, 10)
	testing.expect_value(t, records.statistics.unpowered_machines, 1)
	testing.expect_value(t, records.statistics.brownout_ticks, 0)
}

// Completes steam and first_pole, so first_research is active.
reach_first_research :: proc(test: ^Quest_Test) {
	set_placed(test, "fuel_generator", 1)
	set_placed(test, "offshore_pump", 1)
	set_placed(test, "boiler", 1)
	set_placed(test, "steam_engine", 1)
	set_placed(test, "small_pole", 2)
	test.statistics.obtained[test_item(test.items, "glass")] = 5
	run_quest_tick(test)
}

@(test)
test_chapter_04_power_hints_fire_once :: proc(t: ^testing.T) {
	test := make_chapter_04_test()
	defer destroy_quest_test(&test)
	test.statistics.brownout_ticks = 5000
	test.statistics.unpowered_machine_ticks = 9000
	reach_first_research(&test)
	testing.expect_value(t, active_quest_id(&test), "first_research")
	test.statistics.brownout_ticks += 599
	test.statistics.unpowered_machine_ticks += 1799
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 0)
	test.statistics.brownout_ticks += 1
	run_quest_tick(&test)
	testing.expect_value(t, message_count(&test, "mc_hint_brownout"), 1)
	test.statistics.unpowered_machine_ticks += 1
	run_quest_tick(&test)
	test.statistics.brownout_ticks += 5000
	test.statistics.unpowered_machine_ticks += 5000
	run_quest_tick(&test)
	testing.expect_value(t, test.state.hints_fired, 2)
	testing.expect_value(t, message_count(&test, "mc_hint_brownout"), 1)
	testing.expect_value(t, message_count(&test, "mc_hint_unpowered"), 1)
}

// Every quest of the chapter in order on synthetic counters, ending with
// the delivery and the plates landing in the capsule.
@(test)
test_chapter_04_completes_in_order :: proc(t: ^testing.T) {
	test := make_chapter_04_test()
	defer destroy_quest_test(&test)
	testing.expect_value(t, active_quest_id(&test), "steam")
	set_placed(&test, "fuel_generator", 1)
	set_placed(&test, "offshore_pump", 1)
	set_placed(&test, "boiler", 1)
	run_quest_tick(&test)
	// Waits for the steam engine.
	testing.expect_value(t, active_quest_id(&test), "steam")
	set_placed(&test, "fuel_generator", 0)
	set_placed(&test, "steam_engine", 1)
	run_quest_tick(&test)
	// And for the fuel generator, since the offshore pump needs power (0140).
	testing.expect_value(t, active_quest_id(&test), "steam")
	set_placed(&test, "fuel_generator", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_pole")
	set_placed(&test, "small_pole", 2)
	test.statistics.obtained[test_item(test.items, "glass")] = 4
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_pole")
	test.statistics.obtained[test_item(test.items, "glass")] = 5
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_research")
	set_placed(&test, "lab", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_research")
	gear := test_item(test.items, "iron_gear")
	test.statistics.produced[gear] = 30
	technologies := make_test_quest_references().technologies
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, "automation"))
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "assembly")
	set_placed(&test, "assembler_1", 1)
	run_quest_tick(&test)
	// Gears made before the quest do not count.
	testing.expect_value(t, active_quest_id(&test), "assembly")
	test.statistics.produced[gear] = 50
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "electric_drill")
	set_placed(&test, "electric_mining_drill", 1)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "electric_drill")
	mark_technology_researched(&test.unlocks, test.recipes, test_technology(technologies, "electric_mining"))
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "second_engine")
	set_placed(&test, "steam_engine", 2)
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_contract")
	circuit := test_item(test.items, "electronic_circuit")
	slots := capsule_slots(&test)
	slots[0] = {circuit, 99}
	run_quest_tick(&test)
	testing.expect_value(t, active_quest_id(&test), "first_contract")
	slots[0] = {circuit, 100}
	run_quest_tick(&test)
	testing.expect_value(t, test.state.active, NO_QUEST)
	testing.expect(t, chapter_done(test.state, test.registry.chapters[0]))
	testing.expect(t, has_message(&test, "mc_first_contract_done"))
	testing.expect_value(t, slots_item_count(slots, circuit), 0)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "crusher")), 1)
	testing.expect_value(t, slots_item_count(slots, test_item(test.items, "washer")), 1)
	testing.expect_value(t, test.state.notices[len(test.state.notices) - 1].text_key, CAPSULE_LANDED_KEY)
}

@(test)
test_finished_research_is_announced :: proc(t: ^testing.T) {
	content := make_test_content()
	state := Simulation_State {
		tick    = 42,
		unlocks = make_recipe_unlocks(len(content.items.items), content.recipes, content.technologies, false, context.temp_allocator),
	}
	defer delete(state.quests.messages)
	defer delete(state.quests.notices)
	apply_research_result(&state, content)
	testing.expect_value(t, len(state.quests.messages), 0)
	automation := test_technology(content.technologies, "automation")
	state.records.research.finished, state.records.research.finished_technology = true, automation
	apply_research_result(&state, content)
	testing.expect(t, state.unlocks.researched[automation])
	expected := Quest_Message{tick = 42, text_key = RESEARCH_COMPLETE_KEY, argument_key = "technology_automation"}
	testing.expect_value(t, len(state.quests.messages), 1)
	testing.expect_value(t, state.quests.messages[0], expected)
	testing.expect_value(t, state.quests.notices[0], expected)
	testing.expect_value(t, format_message_text("Research complete: {name}", "Automation"), "Research complete: Automation")
}
