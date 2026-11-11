package game

import "core:encoding/json"
import "core:fmt"
import "core:slice"
import "platform"

// The vessel parts' table (work item 0361, data/vessel_parts.sjson,
// doc/vessels.md): the slot sizes and, per vessel machine, its role (the
// structure that brings slots, or the equipment that goes into them), its
// line and tier (the swap in place goes up a line, 0365) and its figures.
// The geometry stays on the machine record (part_slots, ports,
// machine.odin); this table is keyed by machine id and loaded after the
// machines, strictly: an unknown key or a wrong type refuses the file.

VESSEL_PARTS_FILE_NAME :: "vessel_parts.sjson"
MAXIMUM_SLOT_SIZES :: 4
MAXIMUM_VESSEL_PART_TIER :: 15
MAXIMUM_VESSEL_PART_MASS_KILOGRAMS :: 1_000_000
MAXIMUM_VESSEL_PART_FIGURE :: 1_000_000_000

Vessel_Part_Role :: enum u8 {
	Structure,
	Equipment,
}

@(rodata)
vessel_part_role_names := [Vessel_Part_Role]string {
	.Structure = "structure",
	.Equipment = "equipment",
}

// A slot size as written: width = depth by height, in cells.
Vessel_Slot_Size_Definition :: struct {
	id:       string,
	name_key: string,
	width:    int,
	height:   int,
	depth:    int,
}

// machine, role, line, tier and mass_kilograms are required; the figures
// and connector are optional (VESSEL_PART_OPTIONAL_KEYS).
Vessel_Part_Definition :: struct {
	machine:           string,
	role:              Vessel_Part_Role,
	line:              string,
	tier:              int,
	mass_kilograms:    int,
	supplies_watts:    int,
	draws_watts:       int,
	stores_watt_hours: int,
	stores_litres:     int,
	connector:         bool,
}

VESSEL_PART_OPTIONAL_KEYS :: [?]string{"supplies_watts", "draws_watts", "stores_watt_hours", "stores_litres", "connector"}

Vessel_Parts_File :: struct {
	slot_sizes: []Vessel_Slot_Size_Definition,
	parts:      []Vessel_Part_Definition,
}

// cells is width, height, depth, as a footprint.
Vessel_Slot_Size :: struct {
	id:       string,
	name_key: string,
	cells:    [3]i32,
}

// line indexes Vessel_Part_Registry.lines; size is the equipment's slot
// size, -1 for structure.
Vessel_Part_Record :: struct {
	machine:           Machine_Id,
	role:              Vessel_Part_Role,
	line:              int,
	tier:              u8,
	size:              int,
	mass_kilograms:    i64,
	supplies_watts:    i64,
	draws_watts:       i64,
	stores_watt_hours: i64,
	stores_litres:     i64,
	connector:         bool,
}

// part_of_machine is indexed by Machine_Id: the record's index in parts,
// -1 for a machine that is no vessel part.
Vessel_Part_Registry :: struct {
	slot_sizes:      []Vessel_Slot_Size,
	lines:           []string,
	parts:           []Vessel_Part_Record,
	part_of_machine: []i32,
}

// Held to the configuration's strict keys (parse_configuration_layer,
// assign_configuration_value), every key required but the optional
// figures.
parse_vessel_parts_file :: proc(data: []byte, source: string, allocator := context.allocator) -> (file: Vessel_Parts_File, problem: string) {
	tree, parse_problem := parse_configuration_layer(data, source, context.temp_allocator)
	if parse_problem != "" {
		return {}, parse_problem
	}
	provenance := make(Configuration_Provenance, context.temp_allocator)
	provenance[""] = source
	if problem = assign_configuration_value(any{&file, typeid_of(Vessel_Parts_File)}, json.Value(tree), "", provenance, allocator); problem != "" {
		return {}, problem
	}
	if key, missing := missing_struct_key(Vessel_Parts_File, tree); missing {
		return {}, fmt.tprintf("%s: missing key %s", source, key)
	}
	for record, index in tree["slot_sizes"].(json.Array) {
		if key, missing := missing_struct_key(Vessel_Slot_Size_Definition, record.(json.Object)); missing {
			return {}, fmt.tprintf("%s: slot_sizes[%d] is missing %s", source, index, key)
		}
	}
	optional := VESSEL_PART_OPTIONAL_KEYS
	for record, index in tree["parts"].(json.Array) {
		if key, missing := missing_struct_key(Vessel_Part_Definition, record.(json.Object), optional[:]); missing {
			return {}, fmt.tprintf("%s: parts[%d] is missing %s", source, index, key)
		}
	}
	return file, ""
}

// The slot sizes: at most MAXIMUM_SLOT_SIZES, ids unique and not empty,
// each side 1 to MAXIMUM_FOOTPRINT_SIZE, width = depth, no two alike.
resolve_vessel_slot_sizes :: proc(definitions: []Vessel_Slot_Size_Definition, allocator := context.allocator) -> (sizes: []Vessel_Slot_Size, problem: string) {
	if len(definitions) > MAXIMUM_SLOT_SIZES {
		return nil, fmt.tprintf("more than %d slot_sizes", MAXIMUM_SLOT_SIZES)
	}
	resolved := make([]Vessel_Slot_Size, len(definitions), allocator)
	for definition, index in definitions {
		sides := [3]int{definition.width, definition.height, definition.depth}
		switch {
		case definition.id == "":
			problem = fmt.tprintf("slot_sizes[%d] has no id", index)
		case !(sides.x >= 1 && sides.x <= MAXIMUM_FOOTPRINT_SIZE && sides.y >= 1 && sides.y <= MAXIMUM_FOOTPRINT_SIZE && sides.z >= 1 && sides.z <= MAXIMUM_FOOTPRINT_SIZE):
			problem = fmt.tprintf("slot size %q has a side outside 1 to %d", definition.id, MAXIMUM_FOOTPRINT_SIZE)
		case sides.x != sides.z:
			problem = fmt.tprintf("slot size %q is not square: width %d, depth %d", definition.id, sides.x, sides.z)
		}
		resolved[index] = {id = definition.id, name_key = definition.name_key, cells = {i32(sides.x), i32(sides.y), i32(sides.z)}}
		for earlier in resolved[:index] {
			if problem == "" && earlier.id == definition.id {
				problem = fmt.tprintf("slot size %q is defined twice", definition.id)
			}
			if problem == "" && earlier.cells == resolved[index].cells {
				problem = fmt.tprintf("slot sizes %q and %q are alike", earlier.id, definition.id)
			}
		}
		if problem != "" {
			delete(resolved, allocator)
			return nil, problem
		}
	}
	return resolved, ""
}

// The index of the size whose cells are these, -1 for none.
vessel_slot_size_of :: proc(registry: Vessel_Part_Registry, cells: [3]i32) -> int {
	for size, index in registry.slot_sizes {
		if size.cells == cells {
			return index
		}
	}
	return -1
}

// The cells of a slot's box, as a size's.
part_slot_box_cells :: proc(box: Cell_Box) -> [3]i32 {
	return box.to - box.from + 1
}

// A figure key 0 to MAXIMUM_VESSEL_PART_FIGURE.
vessel_part_figure_problem :: proc(definition: Vessel_Part_Definition) -> string {
	figures := [4]struct {
		key:   string,
		value: int,
	}{{"supplies_watts", definition.supplies_watts}, {"draws_watts", definition.draws_watts}, {"stores_watt_hours", definition.stores_watt_hours}, {"stores_litres", definition.stores_litres}}
	for figure in figures {
		if figure.value < 0 || figure.value > MAXIMUM_VESSEL_PART_FIGURE {
			return fmt.tprintf("vessel part %q has %s %d outside 0 to %d", definition.machine, figure.key, figure.value, MAXIMUM_VESSEL_PART_FIGURE)
		}
	}
	return ""
}

// A part's own rules against its machine: the tier and the mass in their
// bounds, the figures (vessel_part_figure_problem); structure with no
// figure, connector or port and every slot box of a size; equipment with
// no part_slots and its footprint a size; the control unit equipment; a
// connector with a port. Returns the equipment's size, -1 for structure.
vessel_part_definition_problem :: proc(definition: Vessel_Part_Definition, machine: Machine, sizes: []Vessel_Slot_Size) -> (size: int, problem: string) {
	registry := Vessel_Part_Registry{slot_sizes = sizes}
	switch {
	case definition.tier < 1 || definition.tier > MAXIMUM_VESSEL_PART_TIER:
		return -1, fmt.tprintf("vessel part %q has tier %d outside 1 to %d", definition.machine, definition.tier, MAXIMUM_VESSEL_PART_TIER)
	case definition.mass_kilograms < 1 || definition.mass_kilograms > MAXIMUM_VESSEL_PART_MASS_KILOGRAMS:
		return -1, fmt.tprintf("vessel part %q has mass_kilograms %d outside 1 to %d", definition.machine, definition.mass_kilograms, MAXIMUM_VESSEL_PART_MASS_KILOGRAMS)
	case definition.line == "":
		return -1, fmt.tprintf("vessel part %q has no line", definition.machine)
	}
	if problem = vessel_part_figure_problem(definition); problem != "" {
		return -1, problem
	}
	if definition.connector && machine.port_count == 0 {
		return -1, fmt.tprintf("vessel part %q is a connector without a port", definition.machine)
	}
	if definition.role == .Structure {
		functions := definition.supplies_watts != 0 || definition.draws_watts != 0 || definition.stores_watt_hours != 0 || definition.stores_litres != 0 || definition.connector
		switch {
		case machine.kind == .Vessel_Control_Unit:
			return -1, fmt.tprintf("vessel part %q is a control unit and must be equipment", definition.machine)
		case functions:
			return -1, fmt.tprintf("vessel part %q is structure and cannot supply, draw, store or connect", definition.machine)
		case machine.port_count > 0:
			return -1, fmt.tprintf("vessel part %q is structure and cannot have ports", definition.machine)
		}
		slots := machine.part_slots
		for slot, index in slots[:machine.part_slot_count] {
			if vessel_slot_size_of(registry, part_slot_box_cells(slot.box)) < 0 {
				return -1, fmt.tprintf("vessel part %q part_slots %d is of no slot size", definition.machine, index)
			}
		}
		return -1, ""
	}
	if machine.part_slot_count > 0 {
		return -1, fmt.tprintf("vessel part %q is equipment and cannot bring part_slots", definition.machine)
	}
	if size = vessel_slot_size_of(registry, machine.footprint); size < 0 {
		return -1, fmt.tprintf("vessel part %q is equipment whose footprint is of no slot size", definition.machine)
	}
	return size, ""
}

// One line has one role and one machine kind; a structure line one
// footprint and the same part_slots, an equipment line one footprint, so
// a swap along a line never moves a cell (0365).
vessel_line_problem :: proc(first, second: Vessel_Part_Definition, first_machine, second_machine: Machine) -> string {
	switch {
	case first.role != second.role:
		return fmt.tprintf("line %q mixes structure and equipment (%q, %q)", first.line, first.machine, second.machine)
	case first_machine.kind != second_machine.kind:
		return fmt.tprintf("line %q mixes machine kinds (%q, %q)", first.line, first.machine, second.machine)
	case first_machine.footprint != second_machine.footprint:
		return fmt.tprintf("line %q mixes footprints (%q, %q)", first.line, first.machine, second.machine)
	case first_machine.part_slot_count != second_machine.part_slot_count || first_machine.part_slots != second_machine.part_slots:
		return fmt.tprintf("line %q mixes part_slots (%q, %q)", first.line, first.machine, second.machine)
	}
	return ""
}

// Every rule of doc/vessels.md (Data): the sizes, each part naming a
// machine of a vessel kind once, every vessel machine named, each part's
// own rules and its line's.
resolve_vessel_part_registry :: proc(file: Vessel_Parts_File, machines: Machine_Registry, allocator := context.allocator) -> (registry: Vessel_Part_Registry, problem: string) {
	sizes, size_problem := resolve_vessel_slot_sizes(file.slot_sizes, allocator)
	if size_problem != "" {
		return {}, size_problem
	}
	registry.slot_sizes = sizes
	registry.parts = make([]Vessel_Part_Record, len(file.parts), allocator)
	registry.part_of_machine = make([]i32, len(machines.machines), allocator)
	slice.fill(registry.part_of_machine, -1)
	lines := make([dynamic]string, allocator)
	defer if problem != "" {
		destroy_vessel_part_registry(registry, allocator)
		delete(lines)
		registry = {}
	}
	line_definitions := make([dynamic]int, context.temp_allocator)
	for definition, index in file.parts {
		machine, found := find_machine_id(machines, definition.machine)
		switch {
		case !found:
			problem = fmt.tprintf("parts[%d] names unknown machine %q", index, definition.machine)
		case !machine_kind_is_vessel(machines.machines[machine].kind):
			problem = fmt.tprintf("parts[%d] names %q, which is no vessel_part or vessel_control_unit", index, definition.machine)
		case registry.part_of_machine[machine] >= 0:
			problem = fmt.tprintf("vessel part %q is listed twice", definition.machine)
		}
		if problem != "" {
			return
		}
		size: int
		if size, problem = vessel_part_definition_problem(definition, machines.machines[machine], sizes); problem != "" {
			return
		}
		line := -1
		for name, line_index in lines {
			if name == definition.line {
				line = line_index
			}
		}
		if line < 0 {
			append(&lines, definition.line)
			append(&line_definitions, index)
			line = len(lines) - 1
		} else {
			first := file.parts[line_definitions[line]]
			first_machine, _ := find_machine_id(machines, first.machine)
			if problem = vessel_line_problem(first, definition, machines.machines[first_machine], machines.machines[machine]); problem != "" {
				return
			}
		}
		registry.part_of_machine[machine] = i32(index)
		registry.parts[index] = Vessel_Part_Record {
			machine           = machine,
			role              = definition.role,
			line              = line,
			tier              = u8(definition.tier),
			size              = size,
			mass_kilograms    = i64(definition.mass_kilograms),
			supplies_watts    = i64(definition.supplies_watts),
			draws_watts       = i64(definition.draws_watts),
			stores_watt_hours = i64(definition.stores_watt_hours),
			stores_litres     = i64(definition.stores_litres),
			connector         = definition.connector,
		}
	}
	for machine, index in machines.machines {
		if machine_kind_is_vessel(machine.kind) && registry.part_of_machine[index] < 0 {
			problem = fmt.tprintf("vessel machine %q has no record in parts", machine.id)
			return
		}
	}
	registry.lines = lines[:]
	return registry, ""
}

destroy_vessel_part_registry :: proc(registry: Vessel_Part_Registry, allocator := context.allocator) {
	delete(registry.slot_sizes, allocator)
	delete(registry.lines, allocator)
	delete(registry.parts, allocator)
	delete(registry.part_of_machine, allocator)
}

// Through read_logged_data_file, so the edits overlay and its fallback
// apply as for every table.
load_vessel_part_registry :: proc(data_directory: string, machines: Machine_Registry, allocator := context.allocator) -> (registry: Vessel_Part_Registry, ok: bool) {
	data, path := read_logged_data_file(data_directory, VESSEL_PARTS_FILE_NAME) or_return
	file, problem := parse_vessel_parts_file(data, path, allocator)
	if problem != "" {
		platform.log_printf("error: invalid %s", problem)
		return {}, false
	}
	if registry, problem = resolve_vessel_part_registry(file, machines, allocator); problem != "" {
		platform.log_printf("error: invalid %s: %s", path, problem)
		return {}, false
	}
	return registry, true
}

// The record of a vessel machine; found is false for any other machine.
vessel_part_record :: proc(registry: Vessel_Part_Registry, machine: Machine_Id) -> (record: Vessel_Part_Record, found: bool) {
	if int(machine) >= len(registry.part_of_machine) || registry.part_of_machine[machine] < 0 {
		return {}, false
	}
	return registry.parts[registry.part_of_machine[machine]], true
}
