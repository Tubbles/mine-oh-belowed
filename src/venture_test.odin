package game

import "core:slice"
import "core:strings"
import "core:testing"

// Venture tests run a simulation made like a new world on the save test
// landing pad (so the capsule stands), without chunks. The venture starts
// when a launch pad counts as placed.

make_test_contracts :: proc(items: Item_Registry) -> Contract_Registry {
	table, error := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	assert(error == nil)
	file, parse_error := parse_contracts_file(#load("../data/contracts.sjson"), context.temp_allocator)
	assert(parse_error == nil)
	registry, problem := resolve_contract_registry(file, items, table.entries, context.temp_allocator)
	assert(problem == "", problem)
	return registry
}

test_contract :: proc(registry: Contract_Registry, id: string) -> int {
	for contract, index in registry.contracts {
		if contract.id == id {
			return index
		}
	}
	panic(id)
}

Venture_Test :: struct {
	content: Simulation_Content,
	state:   Simulation_State,
}

// In the temp allocator, like the other entity tests.
make_venture_test :: proc() -> Venture_Test {
	content := make_test_content()
	state := make_simulation(test_game_config(), player_start_on({}), content, content.technologies, false, SAVE_TEST_LANDING_PAD)
	state.world.settings.seed = 7
	return Venture_Test{content = content, state = state}
}

start_test_venture :: proc(test: ^Venture_Test) {
	test.state.records.statistics.placed[find_machine_of_kind(test.content.machines, .Launch_Pad)] = 1
}

// A shipment of the stacks at the current tick, served like a launch.
launch_test_cargo :: proc(test: ^Venture_Test, stacks: []Item_Stack) {
	records := &test.state.records
	shipment := make_shipment(stacks, test.state.tick)
	append(&records.shipments, shipment)
	record_shipment(&records.statistics, shipment)
	tick_venture(&test.state, test.content, len(records.shipments) - 1)
}

test_stack :: proc(test: ^Venture_Test, id: string, count: u16) -> Item_Stack {
	return Item_Stack{item = test_item(test.content.items, id), count = count}
}

message_logged :: proc(quests: Quest_State, key: string) -> (message: Quest_Message, found: bool) {
	for candidate in quests.messages {
		if candidate.text_key == key {
			return candidate, true
		}
	}
	return {}, false
}

@(test)
test_contract_data_loads :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	items := make_test_items()
	registry := make_test_contracts(items)
	testing.expect(t, len(registry.contracts) >= 8 && len(registry.contracts) <= 12)
	testing.expect_value(t, registry.tier_shipments, [CONTRACT_TIER_COUNT]u64{0, 3, 10})
	for tier in 1 ..= CONTRACT_TIER_COUNT {
		count := 0
		for contract in registry.contracts {
			count += contract.tier == tier ? 1 : 0
		}
		testing.expectf(t, count >= 3, "tier %d has %d contracts", tier, count)
	}
	boards := registry.contracts[test_contract(registry, "control_boards")]
	testing.expect_value(t, boards.requests[0], Item_Stack{test_item(items, "electronic_circuit"), 300})
	testing.expect_value(t, boards.late_percent, 50)
	testing.expect(t, registry.contracts[test_contract(registry, "survey_fee")].orbital_survey)
	testing.expect_value(t, len(registry.catalogue), 5)
	testing.expect(t, registry.catalogue[4].orbital_survey)
	// Every item has a price.
	for item in items.items {
		testing.expectf(t, item.price > 0, "%s has no price", item.id)
	}
	// A reward and a survey together, and an unknown item, are refused.
	table, _ := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	both := Contract_Definition{id = "x", name_key = "contract_survey_fee", message_key = "mc_contract_survey_fee", tier = 1, deadline_minutes = 1, late_percent = 50, requests = {{item = "steel", count = 1}}, rewards = {{item = "steel", count = 1}}, orbital_survey = true}
	_, problem := resolve_contract_registry(Contracts_File{tier_shipments = {0, 3, 10}, contracts = {both}}, items, table.entries)
	testing.expect(t, problem != "")
	unknown := both
	unknown.orbital_survey = false
	unknown.requests = {{item = "no_such_item", count = 1}}
	_, problem = resolve_contract_registry(Contracts_File{tier_shipments = {0, 3, 10}, contracts = {unknown}}, items, table.entries)
	testing.expect(t, problem != "")
}

// A launch posts the launch line with its cargo to the message log and
// as a toast (0040).
@(test)
test_launch_posts_a_message_and_a_toast :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	test.state.tick = 600
	launch_test_cargo(&test, {test_stack(&test, "iron_plate", 50), test_stack(&test, "steel", 20)})
	expected := Quest_Message{tick = 600, text_key = SHIPMENT_LAUNCHED_KEY, shipment = 1}
	testing.expect_value(t, test.state.quests.messages[0], expected)
	testing.expect(t, slice.contains(test.state.quests.notices[:], expected))
	// The string table's line names the cargo; no table is loaded in
	// tests, so a key that is its own template shows the substitution.
	table, _ := parse_string_table(#load("../data/strings/en.sjson"), context.temp_allocator)
	testing.expect(t, strings.contains(table.entries[SHIPMENT_LAUNCHED_KEY], MESSAGE_CARGO_MARK))
	rendered := quest_message_text(Quest_Message{text_key = "Shipped {cargo} for {value}", value = 5, shipment = 1}, test.state.records.shipments[:], test.content.items, NO_ENTITY, false)
	testing.expect_value(t, rendered, "Shipped item_iron_plate 50, item_steel 20 for 5")
}

@(test)
test_contract_offers_are_gated_and_deterministic :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tests := [2]Venture_Test{make_venture_test(), make_venture_test()}
	registry := tests[0].content.contracts
	// No launch pad placed yet: no offers.
	offer_contracts(&tests[0].state.records, tests[0].state.world.settings.seed, &tests[0].state.quests, tests[0].content, 100)
	testing.expect_value(t, tests[0].state.records.contracts.open_count, 0)
	for &test in tests {
		start_test_venture(&test)
		offer_contracts(&test.state.records, test.state.world.settings.seed, &test.state.quests, test.content, 100)
	}
	first, second := tests[0].state.records.contracts, tests[1].state.records.contracts
	testing.expect_value(t, first, second)
	testing.expect_value(t, first.open_count, MAXIMUM_OPEN_CONTRACTS)
	for open in first.open {
		testing.expect_value(t, registry.contracts[open.contract].tier, 1)
		testing.expect_value(t, open.offered_tick, 100)
	}
	testing.expect_value(t, len(tests[0].state.quests.messages), MAXIMUM_OPEN_CONTRACTS)
	testing.expect_value(t, tests[0].state.quests.messages[0].text_key, registry.contracts[first.open[0].contract].message_key)
	// The tiers open with the rockets launched.
	testing.expect_value(t, contract_tier(registry, 0), 1)
	testing.expect_value(t, contract_tier(registry, 2), 1)
	testing.expect_value(t, contract_tier(registry, 3), 2)
	testing.expect_value(t, contract_tier(registry, 10), 3)
	// Tier 2 adds its contracts to the candidates, which are those never
	// offered yet: the fourth tier 1 contract and the tier 2 ones.
	tier_two := offer_candidates(registry, first, 2)
	testing.expect_value(t, len(tier_two), 5)
	for candidate in tier_two {
		testing.expect(t, registry.contracts[candidate].tier <= 2 && first.offer_counts[candidate] == 0)
	}
	for candidate in offer_candidates(registry, first, 1) {
		testing.expect(t, !contract_is_open(first, candidate))
	}
	// The same seed and tick choose the same, another seed may not.
	candidates := offer_candidates(registry, {}, 3)
	testing.expect_value(t, choose_contract(candidates, 7, 500, 0), choose_contract(candidates, 7, 500, 0))
	differs := false
	for seed in u64(1) ..< 20 {
		differs ||= choose_contract(candidates, seed, 500, 0) != choose_contract(candidates, 7, 500, 0)
	}
	testing.expect(t, differs)
}

// Freeing the oldest slot again and again cycles through the pool: no
// contract is open twice, and none is offered twice before every other
// eligible one was offered once.
@(test)
test_contract_pool_cycles_without_repeats :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	start_test_venture(&test)
	registry := test.content.contracts
	contracts := &test.state.records.contracts
	for round in 0 ..< 40 {
		offer_contracts(&test.state.records, test.state.world.settings.seed, &test.state.quests, test.content, u64(round) * 997)
		open := open_contracts(contracts)
		testing.expect_value(t, len(open), MAXIMUM_OPEN_CONTRACTS)
		for entry, index in open {
			for other in open[index + 1:] {
				testing.expect(t, entry.contract != other.contract)
			}
		}
		fewest, most := max(u32), u32(0)
		for contract, index in registry.contracts {
			if contract.tier == 1 {
				fewest, most = min(fewest, contracts.offer_counts[index]), max(most, contracts.offer_counts[index])
			} else {
				testing.expect_value(t, contracts.offer_counts[index], 0)
			}
		}
		testing.expect(t, most - fewest <= 1)
		remove_open_contract(contracts, 0)
	}
}

// Circuits cover the control boards contract on time: the reward waits
// for the capsule, the iron plates are sold.
@(test)
test_contract_completes_on_time :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	boards := test_contract(test.content.contracts, "control_boards")
	offer_contract(&test.state.records.contracts, boards, 0)
	test.state.tick = 60 * TEST_TICK_RATE
	launch_test_cargo(&test, {test_stack(&test, "electronic_circuit", 300), test_stack(&test, "iron_plate", 10)})
	world := &test.state.world
	records := &test.state.records
	testing.expect_value(t, records.contracts.open_count, 0)
	testing.expect_value(t, records.statistics.contracts_completed, 1)
	testing.expect_value(t, records.statistics.contracts_late, 0)
	testing.expect(t, slice.equal(test.state.quests.pending_rewards[:], []Item_Stack{test_stack(&test, "silicon", 60), test_stack(&test, "aluminium_plate", 40)}))
	testing.expect_value(t, records.venture_credit, 20)
	testing.expect_value(t, records.statistics.credit_earned, 20)
	fulfilled, found := message_logged(test.state.quests, CONTRACT_FULFILLED_KEY)
	testing.expect(t, found)
	testing.expect_value(t, fulfilled.argument_key, "contract_control_boards")
	keys := [?]string{SHIPMENT_LAUNCHED_KEY, CONTRACT_FULFILLED_KEY, FREE_TRADE_KEY}
	for key, index in keys {
		testing.expect_value(t, test.state.quests.messages[index].text_key, key)
	}
	// The rewards land in the capsule with the quest tick.
	tick_quests(&test.state.quests, simulation_quest_context(&test.state, test.content), &world.entities)
	capsule := entity_slots(&world.entities, test.state.quests.capsule)
	testing.expect_value(t, slots_count_of(capsule, test_item(test.content.items, "silicon")), 60)
}

// Past the deadline the same delivery pays the late share, rounded down
// and at least one of each item; the contract never fails.
@(test)
test_contract_completes_late_with_the_late_share :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	registry := test.content.contracts
	boards := test_contract(registry, "control_boards")
	offer_contract(&test.state.records.contracts, boards, 0)
	test.state.tick = contract_deadline_tick(test.state.records.contracts.open[0], registry.contracts[boards], TEST_TICK_RATE) + 1
	testing.expect_value(t, test.state.tick, 30 * 60 * TEST_TICK_RATE + 1)
	launch_test_cargo(&test, {test_stack(&test, "electronic_circuit", 300)})
	statistics := test.state.records.statistics
	testing.expect_value(t, statistics.contracts_completed, 1)
	testing.expect_value(t, statistics.contracts_late, 1)
	testing.expect(t, slice.equal(test.state.quests.pending_rewards[:], []Item_Stack{test_stack(&test, "silicon", 30), test_stack(&test, "aluminium_plate", 20)}))
	late, found := message_logged(test.state.quests, CONTRACT_FULFILLED_LATE_KEY)
	testing.expect(t, found)
	testing.expect_value(t, late.value, 50)
	testing.expect_value(t, late_share(1, 50), 1)
	testing.expect_value(t, late_share(3, 50), 1)
	testing.expect_value(t, late_share(10, 30), 3)
}

// Deliveries add up over launches, and cargo goes to the oldest open
// contract first.
@(test)
test_partial_deliveries_accumulate_oldest_first :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	registry := test.content.contracts
	records := &test.state.records
	offer_contract(&records.contracts, test_contract(registry, "survey_fee"), 0)
	launch_test_cargo(&test, {test_stack(&test, "concrete", 150), test_stack(&test, "iron_plate", 100)})
	testing.expect_value(t, records.contracts.open_count, 1)
	testing.expect_value(t, records.contracts.open[0].delivered, [MAXIMUM_CONTRACT_REQUESTS]u32{150, 100, 0, 0})
	testing.expect_value(t, records.venture_credit, 0)
	launch_test_cargo(&test, {test_stack(&test, "concrete", 60)})
	testing.expect_value(t, records.contracts.open_count, 0)
	testing.expect_value(t, records.statistics.contracts_completed, 1)
	testing.expect_value(t, records.statistics.surveys_bought, 1)
	testing.expect_value(t, records.venture_credit, 10 * 3)
	_, surveyed := message_logged(test.state.quests, ORBITAL_SURVEY_KEY)
	testing.expect(t, surveyed)
	// Two contracts want steel: the older one is served first.
	girders, expansion := test_contract(registry, "station_girders"), test_contract(registry, "station_expansion")
	offer_contract(&records.contracts, girders, 10)
	offer_contract(&records.contracts, expansion, 20)
	launch_test_cargo(&test, {test_stack(&test, "steel", 250)})
	testing.expect_value(t, records.contracts.open_count, 1)
	testing.expect_value(t, int(records.contracts.open[0].contract), expansion)
	testing.expect_value(t, records.contracts.open[0].delivered[0], 50)
}

@(test)
test_venture_credit_arithmetic :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	items := test.content.items
	plate, steel := test_item(items, "iron_plate"), test_item(items, "steel")
	cargo := []Shipped_Item{{plate, 50}, {steel, 20}}
	testing.expect_value(t, cargo_value(cargo, items), 50 * 2 + 20 * 12)
	testing.expect_value(t, take_from_cargo(cargo, steel, 30), 20)
	testing.expect_value(t, cargo_value(cargo, items), 100)
	launch_test_cargo(&test, {test_stack(&test, "iron_plate", 50), test_stack(&test, "steel", 20)})
	launch_test_cargo(&test, {test_stack(&test, "gold_plate", 3)})
	testing.expect_value(t, test.state.records.venture_credit, 340 + 60)
	testing.expect_value(t, test.state.records.statistics.credit_earned, 400)
	sold, found := message_logged(test.state.quests, FREE_TRADE_KEY)
	testing.expect(t, found)
	testing.expect_value(t, sold.value, 340)
}

// Orders wait for the next tick, which deducts the credit and sends the
// items down with the capsule; the survey runs at once.
@(test)
test_catalogue_purchase_lands_in_the_capsule :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	registry := test.content.contracts
	world := &test.state.world
	records := &test.state.records
	records.venture_credit = 1000
	silicon, aluminium := -1, -1
	for entry, index in registry.catalogue {
		if !entry.orbital_survey && entry.item == test_item(test.content.items, "silicon") {
			silicon = index
		}
		if !entry.orbital_survey && entry.item == test_item(test.content.items, "aluminium_plate") {
			aluminium = index
		}
	}
	testing.expect(t, order_from_catalogue(records, registry, silicon, {}))
	// 600 is promised already, 750 more is not covered.
	testing.expect(t, !order_from_catalogue(records, registry, aluminium, {}))
	testing.expect_value(t, records.venture_credit, 1000)
	tick_venture(&test.state, test.content, len(records.shipments))
	testing.expect_value(t, records.venture_credit, 400)
	testing.expect_value(t, len(records.catalogue_orders), 0)
	tick_quests(&test.state.quests, simulation_quest_context(&test.state, test.content), &world.entities)
	capsule := entity_slots(&world.entities, test.state.quests.capsule)
	testing.expect_value(t, slots_count_of(capsule, test_item(test.content.items, "silicon")), 50)
	ordered, found := message_logged(test.state.quests, CATALOGUE_ORDERED_KEY)
	testing.expect(t, found)
	testing.expect_value(t, ordered.argument_key, "item_silicon")
	testing.expect_value(t, ordered.value, 600)
	// The survey from the catalogue.
	records.venture_credit = 3000
	testing.expect(t, order_from_catalogue(records, registry, len(registry.catalogue) - 1, {}))
	tick_venture(&test.state, test.content, len(records.shipments))
	testing.expect_value(t, records.venture_credit, 0)
	testing.expect_value(t, records.statistics.surveys_bought, 1)
}

// Surface veins whose centre is within the radius join the assayed
// records once; deep veins and those further out do not. With the
// generator the survey sees veins no chunk registered.
@(test)
test_orbital_survey_reveals_surface_veins :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_venture_test()
	records := &test.state.records
	veins := []Vein {
		{id = {region = {0, 0}, index = 0}, centre = {100, 40, 100}, radius = 5},
		{id = {region = {2, 0}, index = 0}, centre = {300, 40, 0}, radius = 5},
		{id = {region = {0, 0}, index = 1, layer = .Deep}, centre = {10, -40, 10}, radius = 5},
		{id = {region = {0, -2}, index = 0}, centre = {0, 40, -256}, radius = 3},
	}
	testing.expect_value(t, reveal_surface_veins(&records.assayed_veins, veins, {0, 0, 0}, ORBITAL_SURVEY_RADIUS), 2)
	testing.expect_value(t, reveal_surface_veins(&records.assayed_veins, veins, {0, 0, 0}, ORBITAL_SURVEY_RADIUS), 0)
	testing.expect_value(t, len(records.assayed_veins), 2)
	testing.expect_value(t, records.assayed_veins[0].centre, World_Coordinate{100, 40, 100})
	generator := make_test_generator(DEFAULT_WORLD_SEED)
	content := test.content
	content.generator = &generator
	clear(&records.assayed_veins)
	run_orbital_survey(&test.state, content, {0, 60, 0})
	charted, _ := message_logged(test.state.quests, ORBITAL_SURVEY_KEY)
	testing.expect(t, charted.value > 0)
	testing.expect_value(t, u64(len(records.assayed_veins)), charted.value)
	for assayed in records.assayed_veins {
		testing.expect(t, assayed.vein.layer == .Surface)
		testing.expect(t, i64(assayed.centre.x) * i64(assayed.centre.x) + i64(assayed.centre.z) * i64(assayed.centre.z) <= ORBITAL_SURVEY_RADIUS * ORBITAL_SURVEY_RADIUS)
	}
}

// Level costs grow by 150 percent, a finished level stays queued for the
// next, and the effects add up per level.
@(test)
test_infinite_research_levels :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	test := make_crafting_test()
	technologies, recipes := test.technologies, test.recipes
	mining := test_technology(technologies, "mining_productivity")
	speed := test_technology(technologies, "research_speed")
	technology := technologies.technologies[mining]
	testing.expect(t, technology.infinite)
	testing.expect_value(t, technology.effect, Technology_Effect.Mining_Productivity)
	costs := [?]int{100, 150, 225, 337, 506}
	for cost, index in costs {
		testing.expect_value(t, technology_level_cost(technology, u32(index + 1)), cost)
	}
	testing.expect_value(t, technology_level_cost(technology, 200), MAXIMUM_LEVEL_COST)
	automation := technologies.technologies[test_technology(technologies, "automation")]
	testing.expect_value(t, technology_level_cost(automation, 3), automation.pack_count)
	research: Research_State
	testing.expect(t, queue_research(&research, technologies, test.unlocks, mining) != .None)
	mark_technology_researched(&test.unlocks, recipes, test_technology(technologies, "rocket_program"))
	testing.expect_value(t, queue_research(&research, technologies, test.unlocks, mining), Research_Refusal.None)
	research.units_done = 99
	finish_research_unit(&research, technologies)
	// The queue empties after a level like after any research (user
	// decision 2026-09-27); the next level costs more.
	testing.expect(t, research.finished && !research.queued)
	testing.expect_value(t, research.levels[mining], 1)
	testing.expect_value(t, research.units_done, 0)
	testing.expect_value(t, queued_research_cost(research, technologies), 150)
	finished, done := apply_finished_research(&research, &test.unlocks, recipes)
	testing.expect(t, done && finished == mining)
	testing.expect_value(t, technology_status(technologies, test.unlocks, mining), Technology_Status.Available)
	testing.expect_value(t, research_refusal(technologies, test.unlocks, mining), Research_Refusal.None)
	testing.expect_value(t, technology_effect_per_mille(technologies, research.levels, .Mining_Productivity), 100)
	testing.expect_value(t, technology_effect_per_mille(technologies, research.levels, .Research_Speed), 0)
	// Research speed makes labs faster.
	research.levels[speed] = 3
	testing.expect_value(t, boosted_speed_percent(100, 300), 130)
	lab := Machine{speed_percent = 100}
	testing.expect_value(t, lab_speed_percent(lab, research, technologies), 130)
	testing.expect_value(t, technology_unit_ticks(automation, 130, TEST_TICK_RATE), 461)
	// An infinite technology needs an effect; any other may not name one.
	definitions := []Technology_Definition{{id = "x", name_key = "k", packs = 1, seconds = 1, science_packs = {"science_pack_1"}, infinite = true, level_cost_growth_percent = 150}}
	testing.expect(t, validate_technology_definition(definitions, 0) != "")
	definitions[0].effect, definitions[0].effect_percent = "research_speed", 10
	testing.expect_value(t, validate_technology_definition(definitions, 0), "")
	definitions[0].infinite = false
	testing.expect(t, validate_technology_definition(definitions, 0) != "")
}

// Five mining productivity levels add a unit for every second one drawn,
// at no cost to the vein.
@(test)
test_mining_productivity_multiplies_drill_output :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	content := make_test_content()
	world := make_drill_world(content)
	records := make_test_records(content)
	records.research.levels[test_technology(content.technologies, "mining_productivity")] = 5
	vein := add_test_vein(&world, content, "iron", {1, 1}, 2, IRON_TEST_VEIN)
	place_test_drill(&world, content, {0, 1, 0}, 0, vein)
	chest := place_test_entity(&world, content, "wooden_chest", {2, 1, 0})
	hematite, gravel := test_item(content.items, "hematite"), test_item(content.items, "gravel")
	tick_test_entities(&world, &records, content, 3600)
	testing.expect_value(t, vein_remaining_total(registered_vein(&world, vein)^), 10_000 - 18)
	testing.expect_value(t, chest_count_of(&world, chest, hematite) + chest_count_of(&world, chest, gravel), 27)
	// Past 100 percent a draw can bring two bonus units.
	drill := Drill{}
	for _ in 0 ..< 5 {
		add_productivity(&drill, 1200)
	}
	testing.expect_value(t, drill.bonus_units, 6)
	testing.expect_value(t, drill.productivity_credit, 0)
}
