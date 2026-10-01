package game

import "generation_seed"

// The venture's side of shipments (work item 0041, DESIGN.md Research,
// quests and rockets): contracts, free trade, venture credit, the
// catalogue and the orbital survey. Served in simulation_tick after the
// launches (tick_venture), before the quests land rewards in the capsule.
//
// - Offering: once a launch pad was ever placed, the venture keeps up to
//   MAXIMUM_OPEN_CONTRACTS open. A free slot takes a contract of the
//   eligible pool (tier reached, not open) among those offered least
//   often, so the pool cycles, picked by a hash of the world seed, the
//   tick and the slot.
// - A launch's cargo goes to the open contracts oldest first; deliveries
//   accumulate per contract across launches. A contract whose requests
//   are covered completes: its reward is queued for the capsule (or the
//   orbital survey runs), cut to late_percent (rounded down, at least one
//   of each item) past its deadline. Contracts never fail.
// - Cargo no contract took is sold at the items' prices into
//   Game_Records.venture_credit.
// - Catalogue orders from the pad panel wait in the records until the next
//   tick, which deducts the credit and queues the items for the capsule
//   or runs the survey.
// - The orbital survey adds every surface vein whose centre lies within
//   ORBITAL_SURVEY_RADIUS blocks of the pad to the assayed records, so the
//   map draws them. It asks the generator for the veins when the content
//   has one, and otherwise knows only the registered veins.

MAXIMUM_OPEN_CONTRACTS :: 3
ORBITAL_SURVEY_RADIUS :: 256
// Keeps the offer stream apart from the other uses of the seed.
CONTRACT_OFFER_SALT :: u64(0x636f_6e74_7261_6374)

SHIPMENT_LAUNCHED_KEY :: "shipment_launched"
CONTRACT_FULFILLED_KEY :: "contract_fulfilled"
CONTRACT_FULFILLED_LATE_KEY :: "contract_fulfilled_late"
FREE_TRADE_KEY :: "free_trade_sold"
ORBITAL_SURVEY_KEY :: "orbital_survey_charted"
CATALOGUE_ORDERED_KEY :: "catalogue_ordered"
CATALOGUE_SURVEY_NAME_KEY :: "catalogue_orbital_survey"

// delivered is indexed like the contract's requests.
Open_Contract :: struct {
	contract:     i32,
	offered_tick: u64,
	delivered:    [MAXIMUM_CONTRACT_REQUESTS]u32,
}

// open[:open_count] oldest first. offer_counts is indexed by contract.
Contract_State :: struct {
	open:         [MAXIMUM_OPEN_CONTRACTS]Open_Contract,
	open_count:   i32,
	offer_counts: [MAXIMUM_CONTRACTS]u32,
}

// entry indexes Contract_Registry.catalogue; survey_centre is where a
// bought orbital survey looks (the ordering pad's centre).
Catalogue_Order :: struct {
	entry:         i32,
	survey_centre: World_Coordinate,
}

open_contracts :: proc(state: ^Contract_State) -> []Open_Contract {
	return state.open[:state.open_count]
}

// Offering.

// From the first launch pad placed.
venture_started :: proc(statistics: Statistics, machines: Machine_Registry) -> bool {
	pad := find_machine_of_kind(machines, .Launch_Pad)
	return pad != NO_MACHINE && int(pad) < len(statistics.placed) && statistics.placed[pad] > 0
}

// The highest tier whose shipment threshold the launches reached.
contract_tier :: proc(registry: Contract_Registry, rockets_launched: u64) -> int {
	tier := 1
	for threshold, index in registry.tier_shipments {
		if rockets_launched >= threshold {
			tier = index + 1
		}
	}
	return tier
}

contract_is_open :: proc(state: Contract_State, contract: int) -> bool {
	for index in 0 ..< int(state.open_count) {
		if int(state.open[index].contract) == contract {
			return true
		}
	}
	return false
}

contract_is_eligible :: proc(registry: Contract_Registry, state: Contract_State, contract, tier: int) -> bool {
	return registry.contracts[contract].tier <= tier && !contract_is_open(state, contract)
}

// The eligible contracts offered least often, in data order. In the temp
// allocator.
offer_candidates :: proc(registry: Contract_Registry, state: Contract_State, tier: int) -> []int {
	fewest := max(u32)
	for _, contract in registry.contracts {
		if contract_is_eligible(registry, state, contract, tier) {
			fewest = min(fewest, state.offer_counts[contract])
		}
	}
	candidates := make([dynamic]int, context.temp_allocator)
	for _, contract in registry.contracts {
		if contract_is_eligible(registry, state, contract, tier) && state.offer_counts[contract] == fewest {
			append(&candidates, contract)
		}
	}
	return candidates[:]
}

// -1 without candidates.
choose_contract :: proc(candidates: []int, seed, tick: u64, slot: int) -> int {
	if len(candidates) == 0 {
		return -1
	}
	hash := generation_seed.hash_combine(generation_seed.hash_combine(generation_seed.hash_combine(seed, CONTRACT_OFFER_SALT), tick), u64(slot))
	return candidates[generation_seed.hash_to_range(hash, 0, i64(len(candidates) - 1))]
}

offer_contract :: proc(state: ^Contract_State, contract: int, tick: u64) {
	state.open[state.open_count] = Open_Contract{contract = i32(contract), offered_tick = tick}
	state.open_count += 1
	state.offer_counts[contract] += 1
}

// Fills every free slot it can, each with Mission Control's line.
offer_contracts :: proc(records: ^Game_Records, seed: u64, quests: ^Quest_State, content: Simulation_Content, tick: u64) {
	if !venture_started(records.statistics, content.machines) {
		return
	}
	tier := contract_tier(content.contracts, records.statistics.rockets_launched)
	for records.contracts.open_count < MAXIMUM_OPEN_CONTRACTS {
		candidates := offer_candidates(content.contracts, records.contracts, tier)
		chosen := choose_contract(candidates, seed, tick, int(records.contracts.open_count))
		if chosen < 0 {
			return
		}
		offer_contract(&records.contracts, chosen, tick)
		log_quest_message(quests, tick, content.contracts.contracts[chosen].message_key)
	}
}

// Deliveries.

contract_deadline_tick :: proc(open: Open_Contract, contract: Contract, tick_rate: int) -> u64 {
	return open.offered_tick + u64(contract.deadline_minutes) * 60 * u64(tick_rate)
}

contract_is_late :: proc(open: Open_Contract, contract: Contract, tick: u64, tick_rate: int) -> bool {
	return tick > contract_deadline_tick(open, contract, tick_rate)
}

// Takes up to wanted of the item out of the cargo; returns what it took.
take_from_cargo :: proc(cargo: []Shipped_Item, item: Item_Id, wanted: u32) -> u32 {
	taken: u32
	for &shipped in cargo {
		if shipped.item == item {
			amount := min(shipped.count, wanted - taken)
			shipped.count -= amount
			taken += amount
		}
	}
	return taken
}

// The cargo fills the open contracts' requests oldest first; what they
// take leaves the cargo.
deliver_cargo :: proc(state: ^Contract_State, registry: Contract_Registry, cargo: []Shipped_Item) {
	for &open in open_contracts(state) {
		contract := registry.contracts[open.contract]
		for request, index in contract.requests[:contract.request_count] {
			open.delivered[index] += take_from_cargo(cargo, request.item, u32(request.count) - open.delivered[index])
		}
	}
}

contract_is_covered :: proc(open: Open_Contract, contract: Contract) -> bool {
	requests := contract.requests
	for request, index in requests[:contract.request_count] {
		if open.delivered[index] < u32(request.count) {
			return false
		}
	}
	return true
}

// The late share of a count, rounded down and at least one.
late_share :: proc(count: u16, percent: u32) -> u16 {
	return max(u16(u32(count) * percent / 100), 1)
}

// In the temp allocator.
contract_reward_stacks :: proc(contract: Contract, late: bool) -> []Item_Stack {
	stacks := make([]Item_Stack, contract.reward_count, context.temp_allocator)
	for &stack, index in stacks {
		stack = contract.rewards[index]
		if late {
			stack.count = late_share(stack.count, contract.late_percent)
		}
	}
	return stacks
}

remove_open_contract :: proc(state: ^Contract_State, index: int) {
	copy(state.open[index:state.open_count], state.open[index + 1:state.open_count])
	state.open_count -= 1
	state.open[state.open_count] = {}
}

complete_contract :: proc(state: ^Simulation_State, content: Simulation_Content, open: Open_Contract, survey_centre: World_Coordinate) {
	contract := content.contracts.contracts[open.contract]
	late := contract_is_late(open, contract, state.tick, state.tick_rate)
	statistics := &state.records.statistics
	statistics.contracts_completed += 1
	statistics.contracts_late += late ? 1 : 0
	key := late ? CONTRACT_FULFILLED_LATE_KEY : CONTRACT_FULFILLED_KEY
	log_message(&state.quests, Quest_Message{tick = state.tick, text_key = key, argument_key = contract.name_key, value = u64(contract.late_percent)})
	append(&state.quests.pending_rewards, ..contract_reward_stacks(contract, late))
	if contract.orbital_survey {
		run_orbital_survey(state, content, survey_centre)
	}
}

complete_covered_contracts :: proc(state: ^Simulation_State, content: Simulation_Content, survey_centre: World_Coordinate) {
	contracts := &state.records.contracts
	index := 0
	for index < int(contracts.open_count) {
		open := contracts.open[index]
		if !contract_is_covered(open, content.contracts.contracts[open.contract]) {
			index += 1
			continue
		}
		remove_open_contract(contracts, index)
		complete_contract(state, content, open, survey_centre)
	}
}

// Free trade.

cargo_value :: proc(cargo: []Shipped_Item, items: Item_Registry) -> u64 {
	value: u64
	for shipped in cargo {
		value += u64(shipped.count) * item_price(items, shipped.item)
	}
	return value
}

sell_cargo :: proc(state: ^Simulation_State, content: Simulation_Content, cargo: []Shipped_Item) {
	value := cargo_value(cargo, content.items)
	if value == 0 {
		return
	}
	state.records.venture_credit += value
	state.records.statistics.credit_earned += value
	log_message(&state.quests, Quest_Message{tick = state.tick, text_key = FREE_TRADE_KEY, value = value})
}

// A launched shipment: the launch line, the contracts, then free trade.
serve_shipment :: proc(state: ^Simulation_State, content: Simulation_Content, index: int) {
	shipment := state.records.shipments[index]
	log_message(&state.quests, Quest_Message{tick = state.tick, text_key = SHIPMENT_LAUNCHED_KEY, shipment = u32(index + 1)})
	cargo := shipment.cargo
	deliver_cargo(&state.records.contracts, content.contracts, cargo[:shipment.cargo_count])
	complete_covered_contracts(state, content, shipment.pad_centre)
	sell_cargo(state, content, cargo[:shipment.cargo_count])
}

// The orbital survey.

centre_within :: proc(vein: Vein, centre: World_Coordinate, radius: i32) -> bool {
	dx, dz := i64(vein.centre.x - centre.x), i64(vein.centre.z - centre.z)
	return dx * dx + dz * dz <= i64(radius) * i64(radius)
}

// Every surface vein of the regions the square around the centre touches,
// from the generator when there is one, else the registered veins. In the
// temp allocator.
survey_candidate_veins :: proc(world: ^World, generator: ^Generator, centre: World_Coordinate, radius: i32) -> []Vein {
	if generator != nil {
		veins := veins_near_box(generator, {centre.x - radius, centre.z - radius}, {centre.x + radius, centre.z + radius}, context.temp_allocator)
		return veins[:]
	}
	return world.veins[:]
}

// Adds the surface veins within the radius that are not assayed yet;
// returns how many.
reveal_surface_veins :: proc(assayed_veins: ^[dynamic]Assayed_Vein, veins: []Vein, centre: World_Coordinate, radius: i32) -> int {
	revealed := 0
	for vein in veins {
		if vein_is_deep(vein) || !centre_within(vein, centre, radius) || vein_is_assayed(assayed_veins[:], vein.id) {
			continue
		}
		append(assayed_veins, Assayed_Vein{vein = vein.id, type = vein.type, size_class = vein.size_class, centre = vein.centre, radius = vein.radius})
		revealed += 1
	}
	return revealed
}

run_orbital_survey :: proc(state: ^Simulation_State, content: Simulation_Content, centre: World_Coordinate) {
	veins := survey_candidate_veins(&state.world, content.generator, centre, ORBITAL_SURVEY_RADIUS)
	revealed := reveal_surface_veins(&state.records.assayed_veins, veins, centre, ORBITAL_SURVEY_RADIUS)
	state.records.statistics.surveys_bought += 1
	log_message(&state.quests, Quest_Message{tick = state.tick, text_key = ORBITAL_SURVEY_KEY, value = u64(revealed)})
}

// The catalogue.

// Credit already promised to orders not served yet.
ordered_credit :: proc(orders: []Catalogue_Order, catalogue: []Catalogue_Entry) -> u64 {
	total: u64
	for order in orders {
		total += catalogue[order.entry].price
	}
	return total
}

catalogue_entry_affordable :: proc(records: ^Game_Records, registry: Contract_Registry, entry: int) -> bool {
	return records.venture_credit >= ordered_credit(records.catalogue_orders[:], registry.catalogue) + registry.catalogue[entry].price
}

// The pad panel's order: false when the credit does not cover it.
order_from_catalogue :: proc(records: ^Game_Records, registry: Contract_Registry, entry: int, survey_centre: World_Coordinate) -> bool {
	if entry < 0 || entry >= len(registry.catalogue) || !catalogue_entry_affordable(records, registry, entry) {
		return false
	}
	append(&records.catalogue_orders, Catalogue_Order{entry = i32(entry), survey_centre = survey_centre})
	return true
}

catalogue_entry_name_key :: proc(entry: Catalogue_Entry, items: Item_Registry) -> string {
	return entry.orbital_survey ? CATALOGUE_SURVEY_NAME_KEY : items.items[entry.item].name_key
}

serve_catalogue_order :: proc(state: ^Simulation_State, content: Simulation_Content, order: Catalogue_Order) {
	entry := content.contracts.catalogue[order.entry]
	if state.records.venture_credit < entry.price {
		return
	}
	state.records.venture_credit -= entry.price
	log_message(&state.quests, Quest_Message{tick = state.tick, text_key = CATALOGUE_ORDERED_KEY, argument_key = catalogue_entry_name_key(entry, content.items), value = entry.price})
	if entry.orbital_survey {
		run_orbital_survey(state, content, order.survey_centre)
		return
	}
	append(&state.quests.pending_rewards, Item_Stack{item = entry.item, count = entry.count})
}

serve_catalogue_orders :: proc(state: ^Simulation_State, content: Simulation_Content) {
	for order in state.records.catalogue_orders {
		serve_catalogue_order(state, content, order)
	}
	clear(&state.records.catalogue_orders)
}

// Every shipment launched this tick (from first_new_shipment on), the
// catalogue orders, then new offers for the freed slots.
tick_venture :: proc(state: ^Simulation_State, content: Simulation_Content, first_new_shipment: int) {
	for index in first_new_shipment ..< len(state.records.shipments) {
		serve_shipment(state, content, index)
	}
	serve_catalogue_orders(state, content)
	offer_contracts(&state.records, state.world.settings.seed, &state.quests, content, state.tick)
}

// A loaded state names only contracts and catalogue entries the data has.
venture_state_is_consistent :: proc(records: ^Game_Records, registry: Contract_Registry) -> bool {
	if records.contracts.open_count < 0 || records.contracts.open_count > MAXIMUM_OPEN_CONTRACTS {
		return false
	}
	for open in open_contracts(&records.contracts) {
		if open.contract < 0 || int(open.contract) >= len(registry.contracts) {
			return false
		}
	}
	for order in records.catalogue_orders {
		if order.entry < 0 || int(order.entry) >= len(registry.catalogue) {
			return false
		}
	}
	return true
}

@(rodata)
venture_message_keys := [?]string {
	SHIPMENT_LAUNCHED_KEY,
	CONTRACT_FULFILLED_KEY,
	CONTRACT_FULFILLED_LATE_KEY,
	FREE_TRADE_KEY,
	ORBITAL_SURVEY_KEY,
	CATALOGUE_ORDERED_KEY,
	CATALOGUE_SURVEY_NAME_KEY,
}

// The message log's keys of this file, of the contracts and of the items
// (a catalogue order names its item), as the game data's own strings.
known_venture_message_key :: proc(content: Simulation_Content, key: string) -> (known: string, found: bool) {
	for candidate in venture_message_keys {
		if candidate == key {
			return candidate, true
		}
	}
	for contract in content.contracts.contracts {
		for candidate in ([2]string{contract.name_key, contract.message_key}) {
			if candidate == key {
				return candidate, true
			}
		}
	}
	for item in content.items.items {
		if item.name_key == key {
			return item.name_key, true
		}
	}
	return "", false
}
