package game

import "core:slice"
import "core:strings"
import "core:testing"

SHIPPED_VESSEL_PARTS :: #load("../data/vessel_parts.sjson", string)

// Work item 0361: every vessel machine has its record, the first set's
// ids resolve with their roles, sizes and figures, the ring's line has
// tiers 1 and 2, and the sizes' names are in the string table.
@(test)
test_shipped_vessel_parts_resolve :: proc(t: ^testing.T) {
	machines := make_test_machines()
	registry := make_test_vessel_parts(machines)
	vessel_machines := 0
	for machine, index in machines.machines {
		if !machine_kind_is_vessel(machine.kind) {
			continue
		}
		vessel_machines += 1
		record, found := vessel_part_record(registry, Machine_Id(index))
		testing.expectf(t, found && record.machine == Machine_Id(index), "%s has its record", machine.id)
	}
	testing.expect_value(t, vessel_machines, 9)
	testing.expect_value(t, len(registry.parts), 9)
	testing.expect_value(t, len(registry.slot_sizes), 3)
	small, medium := vessel_slot_size_of(registry, {1, 1, 1}), vessel_slot_size_of(registry, {2, 2, 2})
	testing.expect_value(t, vessel_slot_size_of(registry, {4, 4, 4}), 2)
	testing.expect_value(t, vessel_slot_size_of(registry, {2, 1, 2}), -1)
	expected := [?]struct {
		id:   string,
		role: Vessel_Part_Role,
		size: int,
	} {
		{"iron_truss", .Structure, -1},
		{"iron_deck_plate", .Structure, -1},
		{"iron_fuselage_ring", .Structure, -1},
		{"steel_fuselage_ring", .Structure, -1},
		{"lead_battery", .Equipment, small},
		{"nickel_battery", .Equipment, small},
		{"iron_tank", .Equipment, medium},
		{"control_unit", .Equipment, small},
		{"docking_connector", .Equipment, small},
	}
	for part in expected {
		record, found := vessel_part_record(registry, test_machine(machines, part.id))
		testing.expectf(t, found && record.role == part.role && record.size == part.size, "%s: %v", part.id, record)
	}
	iron, _ := vessel_part_record(registry, test_machine(machines, "iron_fuselage_ring"))
	steel, _ := vessel_part_record(registry, test_machine(machines, "steel_fuselage_ring"))
	testing.expect_value(t, registry.lines[iron.line], "fuselage_ring")
	testing.expect_value(t, steel.line, iron.line)
	testing.expect_value(t, iron.tier, 1)
	testing.expect_value(t, steel.tier, 2)
	battery, _ := vessel_part_record(registry, test_machine(machines, "lead_battery"))
	testing.expect_value(t, battery.supplies_watts, 2000)
	testing.expect_value(t, battery.stores_watt_hours, 2000)
	control, _ := vessel_part_record(registry, test_machine(machines, "control_unit"))
	testing.expect_value(t, control.draws_watts, 60)
	connector, _ := vessel_part_record(registry, test_machine(machines, "docking_connector"))
	testing.expect(t, connector.connector)
	_, furnace_found := vessel_part_record(registry, test_machine(machines, "stone_furnace"))
	testing.expect(t, !furnace_found)
	table := use_shipped_strings()
	defer thread_string_table = nil
	for size in registry.slot_sizes {
		testing.expectf(t, size.name_key in table.entries, "missing string %q", size.name_key)
	}
}

// The shipped file and machines with one change, parsed and resolved:
// the problem either step gives, "" for none.
vessel_parts_problem :: proc(text: string, machines: Machine_Registry) -> string {
	file, problem := parse_vessel_parts_file(transmute([]byte)text, VESSEL_PARTS_FILE_NAME, context.temp_allocator)
	if problem != "" {
		return problem
	}
	_, problem = resolve_vessel_part_registry(file, machines, context.temp_allocator)
	return problem
}

// Each malformed table is refused with its message: the strict keys, the
// machines named, the roles' rules, the lines, the bounds and the sizes.
// A change to the text replaces its first occurrence; a change to the
// machines edits a copy of the shipped records.
@(test)
test_malformed_vessel_parts_are_refused :: proc(t: ^testing.T) {
	machines := make_test_machines()
	testing.expect_value(t, vessel_parts_problem(SHIPPED_VESSEL_PARTS, machines), "")
	FUSELAGE_SIZES :: `{id = "large", name_key = "vessel_slot_large", width = 4, height = 4, depth = 4}`
	cases := [?]struct {
		old, new: string,
		change:   proc(machines: []Machine, registry: Machine_Registry),
		words:    string,
	} {
		{`mass_kilograms = 40}`, `mass_kilograms = 40, colour = 1}`, nil, "unknown key parts[0].colour"},
		{`tier = 1, mass_kilograms = 40}`, `tier = "one", mass_kilograms = 40}`, nil, "parts[0].tier must be"},
		{`line = "truss", tier = 1, mass_kilograms = 40}`, `line = "truss", tier = 1}`, nil, "parts[0] is missing mass_kilograms"},
		{`width = 1, height = 1, depth = 1}`, `width = 1, height = 1}`, nil, "slot_sizes[0] is missing depth"},
		{`role = "structure", line = "truss"`, `role = "frame", line = "truss"`, nil, "parts[0].role is \"frame\""},
		{`machine = "iron_truss"`, `machine = "iron_trusss"`, nil, `parts[0] names unknown machine "iron_trusss"`},
		{`machine = "iron_truss"`, `machine = "stone_furnace"`, nil, `parts[0] names "stone_furnace", which is no vessel_part or vessel_control_unit`},
		{`machine = "iron_deck_plate"`, `machine = "iron_truss"`, nil, `vessel part "iron_truss" is listed twice`},
		{`{machine = "docking_connector"`, `// {machine = "docking_connector"`, nil, `vessel machine "docking_connector" has no record in parts`},
		{"", "", proc(machines: []Machine, registry: Machine_Registry) {
				machines[test_machine(registry, "lead_battery")].footprint = {3, 3, 3}
			}, `vessel part "lead_battery" is equipment whose footprint is of no slot size`},
		{`line = "truss", tier = 1, mass_kilograms = 40}`, `line = "truss", tier = 1, mass_kilograms = 40, stores_litres = 5}`, nil, `vessel part "iron_truss" is structure and cannot supply, draw, store or connect`},
		{"", "", proc(machines: []Machine, registry: Machine_Registry) {
				machines[test_machine(registry, "iron_truss")].port_count = 1
			}, `vessel part "iron_truss" is structure and cannot have ports`},
		{"", "", proc(machines: []Machine, registry: Machine_Registry) {
				machines[test_machine(registry, "iron_deck_plate")].part_slots[0].box.to = {1, 1, 1}
			}, `vessel part "iron_deck_plate" part_slots 0 is of no slot size`},
		{`role = "structure", line = "truss"`, `role = "equipment", line = "truss"`, nil, `vessel part "iron_truss" is equipment and cannot bring part_slots`},
		{`role = "equipment", line = "control_unit"`, `role = "structure", line = "control_unit"`, nil, `vessel part "control_unit" is a control unit and must be equipment`},
		{"", "", proc(machines: []Machine, registry: Machine_Registry) {
				machines[test_machine(registry, "docking_connector")].port_count = 0
			}, `vessel part "docking_connector" is a connector without a port`},
		{`role = "equipment", line = "battery", tier = 1`, `role = "equipment", line = "truss", tier = 1`, nil, `line "truss" mixes structure and equipment ("iron_truss", "lead_battery")`},
		{`line = "control_unit"`, `line = "battery"`, nil, `line "battery" mixes machine kinds ("lead_battery", "control_unit")`},
		{`line = "tank"`, `line = "battery"`, nil, `line "battery" mixes footprints ("lead_battery", "iron_tank")`},
		{"", "", proc(machines: []Machine, registry: Machine_Registry) {
				machines[test_machine(registry, "steel_fuselage_ring")].part_slots[1].box = {from = {-1, 1, 1}, to = {-1, 1, 1}}
			}, `line "fuselage_ring" mixes part_slots ("iron_fuselage_ring", "steel_fuselage_ring")`},
		{`tier = 1, mass_kilograms = 60`, `tier = 0, mass_kilograms = 60`, nil, `vessel part "lead_battery" has tier 0 outside 1 to 15`},
		{`tier = 1, mass_kilograms = 60`, `tier = 16, mass_kilograms = 60`, nil, `vessel part "lead_battery" has tier 16 outside 1 to 15`},
		{`mass_kilograms = 40}`, `mass_kilograms = 0}`, nil, `vessel part "iron_truss" has mass_kilograms 0 outside 1 to 1000000`},
		{`mass_kilograms = 40}`, `mass_kilograms = 1000001}`, nil, `vessel part "iron_truss" has mass_kilograms 1000001 outside 1 to 1000000`},
		{`draws_watts = 60`, `draws_watts = 1000000001`, nil, `vessel part "control_unit" has draws_watts 1000000001 outside 0 to 1000000000`},
		{`width = 2, height = 2, depth = 2}`, `width = 2, height = 2, depth = 3}`, nil, `slot size "medium" is not square: width 2, depth 3`},
		{`width = 2, height = 2, depth = 2}`, `width = 1, height = 1, depth = 1}`, nil, `slot sizes "small" and "medium" are alike`},
		{`id = "medium"`, `id = "small"`, nil, `slot size "small" is defined twice`},
		{`width = 4, height = 4, depth = 4}`, `width = 13, height = 4, depth = 13}`, nil, `slot size "large" has a side outside 1 to 12`},
		{FUSELAGE_SIZES, FUSELAGE_SIZES + ` {id = "huge", name_key = "a", width = 6, height = 6, depth = 6} {id = "giant", name_key = "b", width = 8, height = 8, depth = 8}`, nil, "more than 4 slot_sizes"},
	}
	for refusal in cases {
		text := SHIPPED_VESSEL_PARTS
		if refusal.old != "" {
			testing.expectf(t, strings.contains(text, refusal.old), "the shipped file holds %q", refusal.old)
			text, _ = strings.replace(text, refusal.old, refusal.new, 1, context.temp_allocator)
		}
		changed := machines
		if refusal.change != nil {
			changed.machines = slice.clone(machines.machines, context.temp_allocator)
			refusal.change(changed.machines, changed)
		}
		problem := vessel_parts_problem(text, changed)
		testing.expectf(t, strings.contains(problem, refusal.words), "%q lacks %q", problem, refusal.words)
	}
}
