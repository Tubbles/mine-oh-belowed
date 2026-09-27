package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:slice"

// Machine prototypes from data/machines.sjson, resolved to a dense
// Machine_Id after the items. A machine names the item that places it,
// so the dependency runs one way like items on blocks: items.sjson knows
// nothing about machines, and machine_for_item is derived here.

MACHINES_FILE_NAME :: "machines.sjson"
MAXIMUM_FOOTPRINT_SIZE :: 8

// Dense index into Machine_Registry.machines.
Machine_Id :: distinct u16

NO_MACHINE :: Machine_Id(max(u16))

Machine_Kind :: enum u8 {
	Chest,
	Furnace,
}

@(rodata)
machine_kind_names := [Machine_Kind]string {
	.Chest   = "chest",
	.Furnace = "furnace",
}

Machine_Footprint_Definition :: struct {
	width:  int,
	depth:  int,
	height: int,
}

// As written in the file, before references are resolved.
Machine_Definition :: struct {
	id:                   string,
	name_key:             string,
	item:                 string,
	kind:                 string,
	footprint:            Machine_Footprint_Definition,
	slots:                int,
	fuel_slots:           int,
	input_slots:          int,
	output_slots:         int,
	speed:                f32,
	fuel_power_kilowatts: f32,
}

Machines_File :: struct {
	machines: []Machine_Definition,
}

// footprint is x (width), y (height), z (depth) before rotation. Speed is
// kept in percent and power in watts, so the tick works in integers.
Machine :: struct {
	id:               string,
	name_key:         string,
	item:             Item_Id,
	kind:             Machine_Kind,
	footprint:        [3]i32,
	slot_count:       int,
	speed_percent:    u32,
	fuel_power_watts: u32,
}

Machine_Registry :: struct {
	machines:         []Machine,
	// Indexed by Item_Id: the machine the item places, or NO_MACHINE.
	machine_for_item: []Machine_Id,
	// The furnace recipes, until work item 0012 brings recipes as data.
	smelting:         []Smelting_Recipe,
}

parse_machines_file :: proc(data: []byte, allocator := context.allocator) -> (file: Machines_File, error: json.Unmarshal_Error) {
	error = json.unmarshal(data, &file, .SJSON, allocator)
	return
}

parse_machine_kind :: proc(name: string) -> (kind: Machine_Kind, found: bool) {
	for candidate in Machine_Kind {
		if machine_kind_names[candidate] == name {
			return candidate, true
		}
	}
	return .Chest, false
}

find_machine_definition_index :: proc(definitions: []Machine_Definition, id: string) -> int {
	for definition, index in definitions {
		if definition.id == id {
			return index
		}
	}
	return -1
}

validate_footprint :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	for size in ([3]int{footprint.width, footprint.depth, footprint.height}) {
		if size < 1 || size > MAXIMUM_FOOTPRINT_SIZE {
			return fmt.tprintf("machine %q has a footprint side outside 1 to %d", definition.id, MAXIMUM_FOOTPRINT_SIZE)
		}
	}
	return ""
}

validate_machine_kind_fields :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	switch kind {
	case .Chest:
		if definition.slots < 1 || definition.slots > MAXIMUM_CHEST_SLOTS {
			return fmt.tprintf("chest %q has slots %d outside 1 to %d", definition.id, definition.slots, MAXIMUM_CHEST_SLOTS)
		}
	case .Furnace:
		if definition.fuel_slots != 1 || definition.input_slots != 1 || definition.output_slots != 1 {
			return fmt.tprintf("furnace %q must have one fuel, one input and one output slot", definition.id)
		}
		if definition.speed <= 0 || definition.fuel_power_kilowatts <= 0 {
			return fmt.tprintf("furnace %q needs a positive speed and fuel_power_kilowatts", definition.id)
		}
	}
	return ""
}

// Checks the fields that need no item registry.
validate_machine_definition :: proc(definitions: []Machine_Definition, index: int) -> string {
	definition := definitions[index]
	if definition.id == "" {
		return fmt.tprintf("machine %d has no id", index)
	}
	if find_machine_definition_index(definitions, definition.id) != index {
		return fmt.tprintf("machine id %q is defined twice", definition.id)
	}
	if definition.name_key == "" {
		return fmt.tprintf("machine %q has no name_key", definition.id)
	}
	kind, found := parse_machine_kind(definition.kind)
	if !found {
		return fmt.tprintf("machine %q has unknown kind %q", definition.id, definition.kind)
	}
	if problem := validate_footprint(definition); problem != "" {
		return problem
	}
	return validate_machine_kind_fields(definition, kind)
}

// The placing item must exist, place no block and place only this machine.
resolve_machine_item :: proc(definition: Machine_Definition, items: Item_Registry, machine_for_item: []Machine_Id, machine: Machine_Id) -> (item: Item_Id, problem: string) {
	found: bool
	if item, found = find_item_id(items, definition.item); !found {
		return NO_ITEM, fmt.tprintf("machine %q is placed by unknown item %q", definition.id, definition.item)
	}
	if item_places_block(items, item) != AIR_BLOCK {
		return NO_ITEM, fmt.tprintf("machine %q is placed by %q, which already places a block", definition.id, definition.item)
	}
	if machine_for_item[item] != NO_MACHINE {
		return NO_ITEM, fmt.tprintf("item %q places more than one machine", definition.item)
	}
	machine_for_item[item] = machine
	return item, ""
}

resolve_machine :: proc(definition: Machine_Definition, item: Item_Id) -> Machine {
	kind, _ := parse_machine_kind(definition.kind)
	footprint := definition.footprint
	return Machine {
		id = definition.id,
		name_key = definition.name_key,
		item = item,
		kind = kind,
		footprint = {i32(footprint.width), i32(footprint.height), i32(footprint.depth)},
		slot_count = definition.slots,
		speed_percent = u32(math.round(definition.speed * 100)),
		fuel_power_watts = u32(math.round(definition.fuel_power_kilowatts * 1000)),
	}
}

// Validates the file against the item registry and resolves every
// reference, including the hardcoded smelting table.
resolve_machine_registry :: proc(file: Machines_File, items: Item_Registry, allocator := context.allocator) -> (registry: Machine_Registry, problem: string) {
	if len(file.machines) >= int(NO_MACHINE) {
		return {}, fmt.tprintf("%d machines exceed the limit of %d", len(file.machines), int(NO_MACHINE) - 1)
	}
	registry.machines = make([]Machine, len(file.machines), allocator)
	registry.machine_for_item = make([]Machine_Id, len(items.items), allocator)
	slice.fill(registry.machine_for_item, NO_MACHINE)
	for definition, index in file.machines {
		problem = validate_machine_definition(file.machines, index)
		item: Item_Id
		if problem == "" {
			item, problem = resolve_machine_item(definition, items, registry.machine_for_item, Machine_Id(index))
		}
		if problem != "" {
			destroy_machine_registry(registry, allocator)
			return {}, problem
		}
		registry.machines[index] = resolve_machine(definition, item)
	}
	if registry.smelting, problem = resolve_smelting_table(items, allocator); problem != "" {
		destroy_machine_registry(registry, allocator)
		return {}, problem
	}
	return registry, ""
}

destroy_machine_registry :: proc(registry: Machine_Registry, allocator := context.allocator) {
	delete(registry.machines, allocator)
	delete(registry.machine_for_item, allocator)
	delete(registry.smelting, allocator)
}

// Ids outside the table (NO_ITEM included) place nothing.
item_places_machine :: proc(registry: Machine_Registry, item: Item_Id) -> Machine_Id {
	if int(item) >= len(registry.machine_for_item) {
		return NO_MACHINE
	}
	return registry.machine_for_item[item]
}

machine_name :: proc(registry: Machine_Registry, machine: Machine_Id) -> string {
	if int(machine) >= len(registry.machines) {
		return ""
	}
	return text(registry.machines[machine].name_key)
}

load_machine_registry :: proc(data_directory: string, items: Item_Registry, allocator := context.allocator) -> (registry: Machine_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, MACHINES_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		fmt.eprintfln("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_machines_file(data, allocator)
	if parse_error != nil {
		fmt.eprintfln("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_machine_registry(file, items, allocator)
	if problem != "" {
		fmt.eprintfln("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
