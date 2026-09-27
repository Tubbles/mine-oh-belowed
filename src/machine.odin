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
	// The drop capsule on the landing pad: placed by the world, never by
	// an item, and never picked up.
	Capsule,
	// A belt block of one shape (belt.odin).
	Belt,
	// Moves one item at a time from the cell behind it to the cell in
	// front (inserter.odin).
	Inserter,
	// Taps the reservoir of the vein under it (drill.odin).
	Drill,
	// Stands across two belt cells and shares items between them
	// (splitter.odin).
	Splitter,
	// A 1 by 1 by 1 fluid segment connecting on all six faces
	// (fluid_network.odin).
	Pipe,
	// Fluid machines (fluid_machine.odin), all with fluid ports.
	Offshore_Pump,
	Boiler,
	Steam_Engine,
	Storage_Tank,
	Pump,
	// Draws crude oil from a tar pit block in front of it, with power.
	Tar_Pit_Pump,
	// Burns the gas in its input port, with power (the paid gas sink).
	Flare_Stack,
	// Power (power_network.odin): a pole carries wires to other poles
	// within reach and powers the machines in its supply volume, a power
	// switch is a pole without a supply volume that can be turned off,
	// and a lamp lights its surroundings while powered.
	Pole,
	Power_Switch,
	Lamp,
	// Crafting machines (assembler.odin): assemblers, crushers, washers,
	// alloy furnaces, recyclers, refineries and cracking units, told apart
	// by their recipe_maker.
	// Research (lab.odin).
	Crafting_Machine,
	Lab,
}

@(rodata)
machine_kind_names := [Machine_Kind]string {
	.Chest         = "chest",
	.Furnace       = "furnace",
	.Capsule       = "capsule",
	.Belt          = "belt",
	.Inserter      = "inserter",
	.Drill         = "drill",
	.Splitter      = "splitter",
	.Pipe          = "pipe",
	.Offshore_Pump = "offshore_pump",
	.Boiler        = "boiler",
	.Steam_Engine  = "steam_engine",
	.Storage_Tank  = "storage_tank",
	.Pump          = "pump",
	.Tar_Pit_Pump  = "tar_pit_pump",
	.Flare_Stack   = "flare_stack",
	.Pole          = "pole",
	.Power_Switch  = "power_switch",
	.Lamp          = "lamp",
	.Crafting_Machine = "crafting_machine",
	.Lab           = "lab",
}

// The shape family a belt item places. Ramps become up or down and lifts
// get their direction at placement (belt_placement.odin).
Belt_Item_Shape :: enum u8 {
	Flat,
	Ramp,
	Lift,
}

@(rodata)
belt_item_shape_names := [Belt_Item_Shape]string {
	.Flat = "flat",
	.Ramp = "ramp",
	.Lift = "lift",
}

// Line positions are in 1/256 block.
BELT_UNITS_PER_BLOCK :: 256

Machine_Footprint_Definition :: struct {
	width:  int,
	depth:  int,
	height: int,
}

// As written in the file, before references are resolved.
Machine_Definition :: struct {
	id:                           string,
	name_key:                     string,
	item:                         string,
	kind:                         string,
	footprint:                    Machine_Footprint_Definition,
	slots:                        int,
	fuel_slots:                   int,
	input_slots:                  int,
	output_slots:                 int,
	speed:                        f32,
	fuel_power_kilowatts:         f32,
	belt_shape:                   string,
	belt_speed_blocks_per_second: f32,
	items_per_minute:             int,
	electric_power_kilowatts:     f32,
	filter_slots:                 int,
	rate_reference_ore_percent:   int,
	fluid_ports:                  []Fluid_Port_Definition,
	buffer_litres:                int,
	flow_litres_per_second:       int,
	fluid_litres_per_second:      int,
	fluid_litres_per_minute:      int,
	supply_volume:                Machine_Footprint_Definition,
	wire_reach:                   int,
	electric_output_kilowatts:    f32,
	light_level:                  int,
	recipe_maker:                 string,
	recipe_choice:                string,
}

Machines_File :: struct {
	machines: []Machine_Definition,
}

// footprint is x (width), y (height), z (depth) before rotation. Speed is
// kept in percent and power in watts, so the tick works in integers.
Machine :: struct {
	id:                          string,
	name_key:                    string,
	item:                        Item_Id,
	kind:                        Machine_Kind,
	footprint:                   [3]i32,
	slot_count:                  int,
	speed_percent:               u32,
	fuel_power_watts:            u32,
	belt_shape:                  Belt_Item_Shape,
	// Belts and splitters, in 1/256 block per second; the belt tick
	// divides by the tick rate.
	belt_speed_units_per_second: u32,
	// Inserters: the rate sets the cycle length (inserter_cycle_ticks).
	// Drills: the ore rate on a vein of rate_reference_ore_percent ore
	// (drill_cycle_ticks).
	items_per_minute:            u32,
	electric_power_watts:        u32,
	filter_slot_count:           int,
	rate_reference_ore_percent:  u32,
	fluid_ports:                 [MAXIMUM_FLUID_PORTS]Fluid_Port,
	fluid_port_count:            int,
	// Pipes: the litres one pipe block holds, and the most litres a
	// connection moves per second.
	buffer_litres:               i32,
	flow_litres_per_second:      u32,
	// Offshore pumps and pumps: litres moved per second. Boilers: litres
	// of steam made per second from as much water. Steam engines: litres
	// of steam used per second at full output.
	fluid_litres_per_second:     u32,
	// Tar pit pumps: litres per minute, a whole litre whenever enough
	// ticks have added up (accumulate_litres).
	fluid_litres_per_minute:     u32,
	// Poles: the box of cells powered, x y z like footprint, centred on
	// the pole across and starting at its bottom. Zero for a power switch.
	supply_volume:               [3]i32,
	// Poles and power switches: the longest wire, in blocks.
	wire_reach:                  i32,
	// Generators: the most power they give.
	electric_output_watts:       u32,
	// Lamps: the block light level while lit.
	light_level:                 u8,
	// Crafting machines: the recipes they make, whether the player picks
	// the recipe, and for a fixed choice the input and output slot counts.
	recipe_maker:                Recipe_Maker,
	recipe_choice:               Recipe_Choice,
	input_slot_count:            int,
	output_slot_count:           int,
}

Machine_Registry :: struct {
	machines:         []Machine,
	// Indexed by Item_Id: the machine the item places, or NO_MACHINE.
	machine_for_item: []Machine_Id,
	// The item each lab slot holds: Technology_Registry.science_packs, set
	// once the technologies are loaded, since the machines load first.
	lab_packs:        []Item_Id,
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
		if definition.fuel_slots != 1 || definition.input_slots != 1 || definition.output_slots != 2 {
			return fmt.tprintf("furnace %q must have one fuel, one input and two output slots (main and byproduct)", definition.id)
		}
		if definition.speed <= 0 || definition.fuel_power_kilowatts <= 0 {
			return fmt.tprintf("furnace %q needs a positive speed and fuel_power_kilowatts", definition.id)
		}
	case .Belt:
		return validate_belt_definition(definition)
	case .Inserter:
		return validate_inserter_definition(definition)
	case .Drill:
		return validate_drill_definition(definition)
	case .Splitter:
		return validate_splitter_definition(definition)
	case .Pipe, .Offshore_Pump, .Boiler, .Steam_Engine, .Storage_Tank, .Pump, .Tar_Pit_Pump, .Flare_Stack:
		return validate_fluid_machine_definition(definition, kind)
	case .Pole, .Power_Switch, .Lamp:
		return validate_power_machine_definition(definition, kind)
	case .Crafting_Machine:
		return validate_crafting_machine_definition(definition)
	case .Lab:
		return validate_lab_definition(definition)
	case .Capsule:
		if definition.slots != CAPSULE_SLOT_COUNT {
			return fmt.tprintf("capsule %q must have %d slots", definition.id, CAPSULE_SLOT_COUNT)
		}
		if definition.item != "" {
			return fmt.tprintf("capsule %q cannot be placed by an item", definition.id)
		}
	}
	return ""
}

parse_belt_item_shape :: proc(name: string) -> (shape: Belt_Item_Shape, found: bool) {
	for candidate in Belt_Item_Shape {
		if belt_item_shape_names[candidate] == name {
			return candidate, true
		}
	}
	return .Flat, false
}

validate_belt_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 {
		return fmt.tprintf("belt %q must have a 1 by 1 by 1 footprint", definition.id)
	}
	if _, found := parse_belt_item_shape(definition.belt_shape); !found {
		return fmt.tprintf("belt %q has unknown belt_shape %q", definition.id, definition.belt_shape)
	}
	if definition.belt_speed_blocks_per_second <= 0 {
		return fmt.tprintf("belt %q needs a positive belt_speed_blocks_per_second", definition.id)
	}
	return ""
}

// One by one by one, a positive rate, and either a fuel slot with fuel
// power or electric power. At most one filter slot.
validate_inserter_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 {
		return fmt.tprintf("inserter %q must have a 1 by 1 by 1 footprint", definition.id)
	}
	if definition.items_per_minute <= 0 {
		return fmt.tprintf("inserter %q needs a positive items_per_minute", definition.id)
	}
	if definition.filter_slots < 0 || definition.filter_slots > 1 || definition.input_slots != 0 || definition.output_slots != 0 {
		return fmt.tprintf("inserter %q may only have one fuel slot and one filter slot", definition.id)
	}
	switch definition.fuel_slots {
	case 0:
		if definition.electric_power_kilowatts <= 0 {
			return fmt.tprintf("inserter %q without a fuel slot needs a positive electric_power_kilowatts", definition.id)
		}
	case 1:
		if definition.fuel_power_kilowatts <= 0 {
			return fmt.tprintf("inserter %q with a fuel slot needs a positive fuel_power_kilowatts", definition.id)
		}
	case:
		return fmt.tprintf("inserter %q may have at most one fuel slot", definition.id)
	}
	return ""
}

// Square, so turning a placed drill moves no cell, with a rate and
// either one fuel slot with fuel power or electric power.
validate_drill_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != footprint.depth {
		return fmt.tprintf("drill %q must have a square footprint", definition.id)
	}
	if definition.items_per_minute <= 0 || definition.rate_reference_ore_percent < 1 || definition.rate_reference_ore_percent > 100 {
		return fmt.tprintf("drill %q needs a positive items_per_minute and rate_reference_ore_percent from 1 to 100", definition.id)
	}
	burner := definition.fuel_slots == 1 && definition.fuel_power_kilowatts > 0 && definition.electric_power_kilowatts == 0
	electric := definition.fuel_slots == 0 && definition.fuel_power_kilowatts == 0 && definition.electric_power_kilowatts > 0
	if !burner && !electric {
		return fmt.tprintf("drill %q needs either one fuel slot and fuel_power_kilowatts or electric_power_kilowatts", definition.id)
	}
	if definition.slots != 0 || definition.input_slots != 0 || definition.output_slots != 0 || definition.filter_slots != 0 {
		return fmt.tprintf("drill %q may only have a fuel slot", definition.id)
	}
	return ""
}

// One along its flow and two across it, so each half stands where a belt
// block would, and a positive item speed.
validate_splitter_definition :: proc(definition: Machine_Definition) -> string {
	footprint := definition.footprint
	if footprint.width != 1 || footprint.depth != 2 || footprint.height != 1 {
		return fmt.tprintf("splitter %q must have a footprint of width 1, depth 2 and height 1", definition.id)
	}
	if definition.belt_speed_blocks_per_second <= 0 {
		return fmt.tprintf("splitter %q needs a positive belt_speed_blocks_per_second", definition.id)
	}
	return ""
}

// Labs: a speed and electric power. Their slots come from the
// technologies, never from the file.
validate_lab_definition :: proc(definition: Machine_Definition) -> string {
	if definition.speed <= 0 || definition.electric_power_kilowatts <= 0 {
		return fmt.tprintf("machine %q needs a positive speed and electric_power_kilowatts", definition.id)
	}
	if definition.slots != 0 || definition.fuel_slots != 0 || definition.input_slots != 0 || definition.output_slots != 0 {
		return fmt.tprintf("machine %q may not list slots", definition.id)
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
	belt_shape, _ := parse_belt_item_shape(definition.belt_shape)
	footprint := definition.footprint
	slot_count := kind == .Inserter || kind == .Drill || kind == .Boiler || kind == .Crafting_Machine ? definition.fuel_slots : definition.slots
	recipe_maker, _ := parse_named_enum(recipe_maker_names, definition.recipe_maker)
	recipe_choice, _ := parse_named_enum(recipe_choice_names, definition.recipe_choice)
	return Machine {
		id = definition.id,
		name_key = definition.name_key,
		item = item,
		kind = kind,
		footprint = {i32(footprint.width), i32(footprint.height), i32(footprint.depth)},
		slot_count = slot_count,
		speed_percent = u32(math.round(definition.speed * 100)),
		fuel_power_watts = u32(math.round(definition.fuel_power_kilowatts * 1000)),
		belt_shape = belt_shape,
		belt_speed_units_per_second = u32(math.round(definition.belt_speed_blocks_per_second * BELT_UNITS_PER_BLOCK)),
		items_per_minute = u32(max(definition.items_per_minute, 0)),
		electric_power_watts = u32(math.round(definition.electric_power_kilowatts * 1000)),
		filter_slot_count = definition.filter_slots,
		rate_reference_ore_percent = u32(max(definition.rate_reference_ore_percent, 0)),
		buffer_litres = i32(max(definition.buffer_litres, 0)),
		flow_litres_per_second = u32(max(definition.flow_litres_per_second, 0)),
		fluid_litres_per_second = u32(max(definition.fluid_litres_per_second, 0)),
		fluid_litres_per_minute = u32(max(definition.fluid_litres_per_minute, 0)),
		supply_volume = {i32(definition.supply_volume.width), i32(definition.supply_volume.height), i32(definition.supply_volume.depth)},
		wire_reach = i32(max(definition.wire_reach, 0)),
		electric_output_watts = u32(math.round(definition.electric_output_kilowatts * 1000)),
		light_level = u8(clamp(definition.light_level, 0, MAXIMUM_LIGHT)),
		recipe_maker = recipe_maker,
		recipe_choice = recipe_choice,
		input_slot_count = definition.input_slots,
		output_slot_count = definition.output_slots,
	}
}

// Validates the file against the item registry and resolves every
// reference.
resolve_machine_registry :: proc(file: Machines_File, items: Item_Registry, fluids: Fluid_Registry, allocator := context.allocator) -> (registry: Machine_Registry, problem: string) {
	if len(file.machines) >= int(NO_MACHINE) {
		return {}, fmt.tprintf("%d machines exceed the limit of %d", len(file.machines), int(NO_MACHINE) - 1)
	}
	registry.machines = make([]Machine, len(file.machines), allocator)
	registry.machine_for_item = make([]Machine_Id, len(items.items), allocator)
	slice.fill(registry.machine_for_item, NO_MACHINE)
	for definition, index in file.machines {
		problem = validate_machine_definition(file.machines, index)
		item := NO_ITEM
		if problem == "" && definition.kind != machine_kind_names[.Capsule] {
			item, problem = resolve_machine_item(definition, items, registry.machine_for_item, Machine_Id(index))
		}
		machine: Machine
		if problem == "" {
			machine = resolve_machine(definition, item)
			problem = resolve_fluid_ports(&machine, definition, fluids)
		}
		if problem != "" {
			destroy_machine_registry(registry, allocator)
			return {}, problem
		}
		registry.machines[index] = machine
	}
	return registry, ""
}

destroy_machine_registry :: proc(registry: Machine_Registry, allocator := context.allocator) {
	delete(registry.machines, allocator)
	delete(registry.machine_for_item, allocator)
}

// Ids outside the table (NO_ITEM included) place nothing.
item_places_machine :: proc(registry: Machine_Registry, item: Item_Id) -> Machine_Id {
	if int(item) >= len(registry.machine_for_item) {
		return NO_MACHINE
	}
	return registry.machine_for_item[item]
}

// The first machine of a kind, or NO_MACHINE.
find_machine_of_kind :: proc(registry: Machine_Registry, kind: Machine_Kind) -> Machine_Id {
	for machine, index in registry.machines {
		if machine.kind == kind {
			return Machine_Id(index)
		}
	}
	return NO_MACHINE
}

find_machine_id :: proc(registry: Machine_Registry, id: string) -> (machine: Machine_Id, found: bool) {
	for candidate, index in registry.machines {
		if candidate.id == id {
			return Machine_Id(index), true
		}
	}
	return NO_MACHINE, false
}

machine_name :: proc(registry: Machine_Registry, machine: Machine_Id) -> string {
	if int(machine) >= len(registry.machines) {
		return ""
	}
	return text(registry.machines[machine].name_key)
}

load_machine_registry :: proc(data_directory: string, items: Item_Registry, fluids: Fluid_Registry, allocator := context.allocator) -> (registry: Machine_Registry, ok: bool) {
	path, join_error := os.join_path({data_directory, MACHINES_FILE_NAME}, context.temp_allocator)
	if join_error != nil {
		return {}, false
	}
	data, read_error := os.read_entire_file(path, context.temp_allocator)
	if read_error != nil {
		log_printf("error: cannot read %s: %v", path, read_error)
		return {}, false
	}
	file, parse_error := parse_machines_file(data, allocator)
	if parse_error != nil {
		log_printf("error: cannot parse %s: %v", path, parse_error)
		return {}, false
	}
	problem: string
	registry, problem = resolve_machine_registry(file, items, fluids, allocator)
	if problem != "" {
		log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}
