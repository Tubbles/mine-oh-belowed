package game

import "core:encoding/json"
import "core:fmt"
import "platform"

// Contracts and the catalogue from data/contracts.sjson (work item 0041,
// DESIGN.md Research, quests and rockets). A contract asks for items, pays
// a reward (items that land in the drop capsule, or an orbital survey)
// and has a soft deadline in game minutes from the moment it is offered:
// late, it pays late_percent of the reward. Its tier gates when it may be
// offered: tier 1 once a launch pad was placed, tier n once
// tier_shipments[n - 1] rockets were launched. The catalogue lists what
// venture credit buys. The runtime is in venture.odin.

CONTRACTS_FILE_NAME :: "contracts.sjson"
MAXIMUM_CONTRACTS :: 32
MAXIMUM_CONTRACT_REQUESTS :: 4
MAXIMUM_CONTRACT_REWARDS :: 4
CONTRACT_TIER_COUNT :: 3

Contract_Stack_Definition :: struct {
	item:  string,
	count: int,
}

Contract_Definition :: struct {
	id:               string,
	name_key:         string,
	message_key:      string,
	tier:             int,
	deadline_minutes: int,
	late_percent:     int,
	requests:         []Contract_Stack_Definition,
	rewards:          []Contract_Stack_Definition,
	orbital_survey:   bool,
}

Catalogue_Definition :: struct {
	item:           string,
	count:          int,
	orbital_survey: bool,
	price:          int,
}

Contracts_File :: struct {
	tier_shipments: []int,
	contracts:      []Contract_Definition,
	catalogue:      []Catalogue_Definition,
}

// message_key is Mission Control's line when the contract is offered.
Contract :: struct {
	id:               string,
	name_key:         string,
	message_key:      string,
	tier:             int,
	deadline_minutes: u32,
	late_percent:     u32,
	request_count:    int,
	requests:         [MAXIMUM_CONTRACT_REQUESTS]Item_Stack,
	reward_count:     int,
	rewards:          [MAXIMUM_CONTRACT_REWARDS]Item_Stack,
	orbital_survey:   bool,
}

// item is NO_ITEM for an orbital survey.
Catalogue_Entry :: struct {
	item:           Item_Id,
	count:          u16,
	orbital_survey: bool,
	price:          u64,
}

Contract_Registry :: struct {
	tier_shipments: [CONTRACT_TIER_COUNT]u64,
	contracts:      []Contract,
	catalogue:      []Catalogue_Entry,
}

parse_contracts_file :: proc(data: []byte, allocator := context.allocator) -> (file: Contracts_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

check_contract_key :: proc(strings: map[string]string, owner, field, key: string) -> string {
	if key == "" || key not_in strings {
		return fmt.tprintf("contract %q: %s %q is not in the string table", owner, field, key)
	}
	return ""
}

// At most maximum stacks of known items, each 1 to 65535.
resolve_contract_stacks :: proc(owner: string, definitions: []Contract_Stack_Definition, maximum: int, items: Item_Registry, stacks: []Item_Stack) -> (count: int, problem: string) {
	if len(definitions) > maximum {
		return 0, fmt.tprintf("contract %q lists more than %d stacks", owner, maximum)
	}
	for definition, index in definitions {
		item, found := find_item_id(items, definition.item)
		switch {
		case !found:
			return 0, fmt.tprintf("contract %q names unknown item %q", owner, definition.item)
		case definition.count < 1 || definition.count > int(max(u16)):
			return 0, fmt.tprintf("contract %q needs a count from 1 to %d for %q", owner, max(u16), definition.item)
		}
		stacks[index] = Item_Stack{item = item, count = u16(definition.count)}
	}
	return len(definitions), ""
}

validate_contract_definition :: proc(definitions: []Contract_Definition, index: int, strings: map[string]string) -> string {
	definition := definitions[index]
	for other in definitions[:index] {
		if other.id == definition.id {
			return fmt.tprintf("contract id %q is defined twice", definition.id)
		}
	}
	switch {
	case definition.id == "":
		return fmt.tprintf("contract %d has no id", index)
	case definition.tier < 1 || definition.tier > CONTRACT_TIER_COUNT:
		return fmt.tprintf("contract %q needs a tier from 1 to %d", definition.id, CONTRACT_TIER_COUNT)
	case definition.deadline_minutes < 1:
		return fmt.tprintf("contract %q needs a positive deadline_minutes", definition.id)
	case definition.late_percent < 1 || definition.late_percent > 100:
		return fmt.tprintf("contract %q needs a late_percent from 1 to 100", definition.id)
	case len(definition.requests) == 0:
		return fmt.tprintf("contract %q requests nothing", definition.id)
	case definition.orbital_survey == (len(definition.rewards) > 0):
		return fmt.tprintf("contract %q needs exactly one of rewards and orbital_survey", definition.id)
	}
	if problem := check_contract_key(strings, definition.id, "name_key", definition.name_key); problem != "" {
		return problem
	}
	return check_contract_key(strings, definition.id, "message_key", definition.message_key)
}

resolve_contract :: proc(definitions: []Contract_Definition, index: int, items: Item_Registry, strings: map[string]string) -> (contract: Contract, problem: string) {
	if problem = validate_contract_definition(definitions, index, strings); problem != "" {
		return {}, problem
	}
	definition := definitions[index]
	contract = Contract {
		id               = definition.id,
		name_key         = definition.name_key,
		message_key      = definition.message_key,
		tier             = definition.tier,
		deadline_minutes = u32(definition.deadline_minutes),
		late_percent     = u32(definition.late_percent),
		orbital_survey   = definition.orbital_survey,
	}
	if contract.request_count, problem = resolve_contract_stacks(definition.id, definition.requests, MAXIMUM_CONTRACT_REQUESTS, items, contract.requests[:]); problem != "" {
		return {}, problem
	}
	contract.reward_count, problem = resolve_contract_stacks(definition.id, definition.rewards, MAXIMUM_CONTRACT_REWARDS, items, contract.rewards[:])
	return contract, problem
}

// Either an item with a count or the orbital survey, and a price.
resolve_catalogue_entry :: proc(definition: Catalogue_Definition, index: int, items: Item_Registry) -> (entry: Catalogue_Entry, problem: string) {
	if definition.price < 1 {
		return {}, fmt.tprintf("catalogue entry %d needs a positive price", index)
	}
	if definition.orbital_survey {
		if definition.item != "" || definition.count != 0 {
			return {}, fmt.tprintf("catalogue entry %d is an orbital survey and may not name an item", index)
		}
		return Catalogue_Entry{item = NO_ITEM, orbital_survey = true, price = u64(definition.price)}, ""
	}
	item, found := find_item_id(items, definition.item)
	if !found || definition.count < 1 || definition.count > int(max(u16)) {
		return {}, fmt.tprintf("catalogue entry %d needs a known item and a count from 1 to %d", index, max(u16))
	}
	return Catalogue_Entry{item = item, count = u16(definition.count), price = u64(definition.price)}, ""
}

// Three tiers whose shipment thresholds never fall.
resolve_tier_shipments :: proc(values: []int) -> (tiers: [CONTRACT_TIER_COUNT]u64, problem: string) {
	if len(values) != CONTRACT_TIER_COUNT {
		return {}, fmt.tprintf("tier_shipments needs %d values", CONTRACT_TIER_COUNT)
	}
	for value, index in values {
		if value < 0 || (index > 0 && value < values[index - 1]) {
			return {}, "tier_shipments must be non negative and never fall"
		}
		tiers[index] = u64(value)
	}
	return tiers, ""
}

resolve_contract_registry :: proc(file: Contracts_File, items: Item_Registry, strings: map[string]string, allocator := context.allocator) -> (registry: Contract_Registry, problem: string) {
	if len(file.contracts) > MAXIMUM_CONTRACTS {
		return {}, fmt.tprintf("%d contracts, at most %d are supported", len(file.contracts), MAXIMUM_CONTRACTS)
	}
	if registry.tier_shipments, problem = resolve_tier_shipments(file.tier_shipments); problem != "" {
		return {}, problem
	}
	registry.contracts = make([]Contract, len(file.contracts), allocator)
	registry.catalogue = make([]Catalogue_Entry, len(file.catalogue), allocator)
	for _, index in file.contracts {
		if registry.contracts[index], problem = resolve_contract(file.contracts, index, items, strings); problem != "" {
			destroy_contract_registry(registry, allocator)
			return {}, problem
		}
	}
	for definition, index in file.catalogue {
		if registry.catalogue[index], problem = resolve_catalogue_entry(definition, index, items); problem != "" {
			destroy_contract_registry(registry, allocator)
			return {}, problem
		}
	}
	return registry, ""
}

destroy_contract_registry :: proc(registry: Contract_Registry, allocator := context.allocator) {
	delete(registry.contracts, allocator)
	delete(registry.catalogue, allocator)
}

load_contract_registry :: proc(data_directory: string, items: Item_Registry, strings: map[string]string, allocator := context.allocator) -> (registry: Contract_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, CONTRACTS_FILE_NAME) or_return
	file, parse_error := parse_contracts_file(data, allocator)
	if parse_error != nil {
		platform.log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_contract_registry(file, items, strings, allocator)
	if problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
