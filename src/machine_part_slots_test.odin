package game

import "core:strings"
import "core:testing"

// The shipped definition of a machine, as parsed.
shipped_machine_definition :: proc(id: string) -> Machine_Definition {
	file, error := parse_machines_file(#load("../data/machines.sjson"), context.temp_allocator)
	assert(error == nil)
	for definition in file.machines {
		if definition.id == id {
			return definition
		}
	}
	panic(id)
}

// Work item 0361: validate_machine_definition refuses each malformed slot
// layout (on the shipped ring) and port list (on the shipped tank), a
// truss whose inside slot takes its one cell, slots or ports on a furnace,
// and a vessel part without its item or colour.
@(test)
test_malformed_part_slots_and_ports_are_refused :: proc(t: ^testing.T) {
	ring := shipped_machine_definition("iron_fuselage_ring")
	tank := shipped_machine_definition("iron_tank")
	furnace := shipped_machine_definition("stone_furnace")
	testing.expect_value(t, validate_machine_definition({ring}, 0), "")
	testing.expect_value(t, validate_machine_definition({tank}, 0), "")
	cell :: proc(x, y, z: int) -> Machine_Cell_Definition {
		return {x = x, y = y, z = z}
	}
	outside := Part_Slot_Definition{side = "outside", from = cell(-1, 0, 1), to = cell(-1, 0, 1)}
	nine_slots := make([]Part_Slot_Definition, MAXIMUM_PART_SLOTS + 1, context.temp_allocator)
	for &slot, index in nine_slots {
		slot = {side = "outside", from = cell(-1, 0, index % 4), to = cell(-1, 0, index % 4)}
		if index >= 4 {
			slot.from.x, slot.to.x = 4, 4
		}
	}
	slot_cases := [?]struct {
		slots: []Part_Slot_Definition,
		words: string,
	} {
		{{{side = "inside", from = cell(1, 0, 1), to = cell(2, 2, 2)}}, `machine "iron_fuselage_ring" part_slots 0 does not lie inside the footprint`},
		{{{side = "outside", from = cell(-2, 0, 1), to = cell(-2, 0, 1)}}, `part_slots 0 does not lie outside beside a face of the footprint`},
		{{{side = "outside", from = cell(-1, -1, 1), to = cell(-1, -1, 1)}}, `part_slots 0 does not lie outside beside a face of the footprint`},
		{{{side = "underneath", from = cell(0, -1, 0), to = cell(1, 0, 1)}}, `part_slots 0 does not lie underneath the footprint`},
		{{{side = "underneath", from = cell(5, -1, 0), to = cell(5, -1, 0)}}, `part_slots 0 does not lie underneath the footprint`},
		{{outside, {side = "outside", from = cell(-1, 0, 0), to = cell(-1, 1, 1)}}, `part_slots 0 and 1 overlap`},
		{nine_slots, `machine "iron_fuselage_ring" has more than 8 part_slots`},
		{{{side = "above", from = cell(0, 2, 0), to = cell(0, 2, 0)}}, `part_slots 0 has unknown side "above"`},
		{{{side = "outside", from = cell(-13, 0, 1), to = cell(-1, 0, 1)}}, `part_slots 0 is not a box within -12 to 23`},
		{{{side = "outside", from = cell(-1, 0, 2), to = cell(-1, 0, 1)}}, `part_slots 0 is not a box within -12 to 23`},
	}
	for refusal in slot_cases {
		changed := ring
		changed.part_slots = refusal.slots
		problem := validate_machine_definition({changed}, 0)
		testing.expectf(t, strings.contains(problem, refusal.words), "%q lacks %q", problem, refusal.words)
	}
	// A piece holds at least one cell, so it can be aimed at and taken off.
	hollow_truss := shipped_machine_definition("iron_truss")
	hollow_truss.part_slots = {{side = "inside", from = cell(0, 0, 0), to = cell(0, 0, 0)}}
	testing.expect_value(t, validate_machine_definition({hollow_truss}, 0), `machine "iron_truss" part_slots leave none of its footprint's cells held`)
	slotted_furnace := furnace
	slotted_furnace.part_slots = {outside}
	testing.expect_value(t, validate_machine_definition({slotted_furnace}, 0), `machine "stone_furnace" lists part_slots, which only a vessel_part may`)

	fluid := Machine_Port_Definition{id = "fluid", kind = "fluid", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 60}
	// Four on the tank's -z face, four on its +z face, the ninth on -x.
	nine_ports := make([]Machine_Port_Definition, MAXIMUM_MACHINE_PORTS + 1, context.temp_allocator)
	for &port, index in nine_ports {
		port = {id = strings.repeat("p", index + 1, context.temp_allocator), kind = "power", cell = cell(index % 2, index % 4 / 2, 0), face = "negative_z", capacity_watts = 1}
		switch {
		case index == MAXIMUM_MACHINE_PORTS:
			port.cell, port.face = cell(0, 0, 0), "negative_x"
		case index >= 4:
			port.cell.z, port.face = 1, "positive_z"
		}
	}
	port_cases := [?]struct {
		ports: []Machine_Port_Definition,
		words: string,
	} {
		{{{id = "fluid", kind = "fluid", cell = cell(0, 0, 0), face = "positive_x", capacity_litres_per_second = 60}}, `machine "iron_tank" port "fluid" does not face out of the footprint`},
		{{{id = "fluid", kind = "fluid", cell = cell(2, 0, 0), face = "positive_x", capacity_litres_per_second = 60}}, `port "fluid" is not on a footprint cell`},
		{{fluid, {id = "fluid", kind = "fluid", cell = cell(0, 0, 0), face = "negative_x", capacity_litres_per_second = 60}}, `machine "iron_tank" has two ports "fluid"`},
		{{fluid, {id = "other", kind = "fluid", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 60}}, `ports "fluid" and "other" share a cell and face`},
		{{{id = "fluid", kind = "steam", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 60}}, `port "fluid" has unknown kind "steam", not power or fluid`},
		{{{id = "fluid", kind = "fluid", cell = cell(0, 0, 1), face = "outward", capacity_litres_per_second = 60}}, `port "fluid" has unknown face "outward"`},
		{{{id = "", kind = "fluid", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 60}}, `machine "iron_tank" has a port without an id`},
		{{{id = "power", kind = "power", cell = cell(0, 0, 1), face = "positive_z", capacity_watts = 10, capacity_litres_per_second = 5}}, `port "power" is a power port and cannot have capacity_litres_per_second`},
		{{{id = "power", kind = "power", cell = cell(0, 0, 1), face = "positive_z"}}, `port "power" has capacity_watts 0 outside 1 to 1000000000`},
		{{{id = "fluid", kind = "fluid", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 1_000_000_001}}, `port "fluid" has capacity_litres_per_second 1000000001 outside 60 to 1000000000`},
		{{{id = "fluid", kind = "fluid", cell = cell(0, 0, 1), face = "positive_z", capacity_litres_per_second = 59}}, `port "fluid" has capacity_litres_per_second 59 outside 60 to 1000000000`},
		{nine_ports, `machine "iron_tank" has more than 8 ports`},
	}
	for refusal in port_cases {
		changed := tank
		changed.ports = refusal.ports
		problem := validate_machine_definition({changed}, 0)
		testing.expectf(t, strings.contains(problem, refusal.words), "%q lacks %q", problem, refusal.words)
	}
	eight_ports := tank
	eight_ports.ports = nine_ports[:MAXIMUM_MACHINE_PORTS]
	testing.expect_value(t, validate_machine_definition({eight_ports}, 0), "")
	ported_furnace := furnace
	ported_furnace.ports = {fluid}
	testing.expect_value(t, validate_machine_definition({ported_furnace}, 0), `machine "stone_furnace" port "fluid" is a fluid port, which only a machine with fluid_ports, a fluid junction or a vessel part may list`)

	no_item := tank
	no_item.item = ""
	testing.expect_value(t, validate_machine_definition({no_item}, 0), `vessel part "iron_tank" needs an item`)
	no_colour := tank
	no_colour.color = {300, 0, 0}
	testing.expect_value(t, validate_machine_definition({no_colour}, 0), `vessel part "iron_tank" needs a color of three channels from 0 to 255`)
	with_slots := tank
	with_slots.slots = 4
	testing.expect_value(t, validate_machine_definition({with_slots}, 0), `vessel part "iron_tank" may not list item slots, power or fluid_ports`)
}

// The ring holds its 24 wall cells at every quarter turn, its hollow
// empty, and its slots turn with it: turned once, the -x outside box lands
// where the -z one was, and the four outside boxes are the same set.
@(test)
test_a_ring_holds_its_walls_and_its_slots_turn_with_it :: proc(t: ^testing.T) {
	machines := make_test_machines()
	ring := machines.machines[test_machine(machines, "iron_fuselage_ring")]
	testing.expect_value(t, ring.part_slot_count, 5)
	testing.expect_value(t, ring.part_slots[0].side, Part_Slot_Side.Inside)
	for rotation in u8(0) ..< 4 {
		cells := machine_held_cells({}, ring, rotation)
		testing.expectf(t, len(cells) == 24, "rotation %d holds %d cells", rotation, len(cells))
		for cell in cells {
			testing.expectf(t, !(cell.x >= 1 && cell.x <= 2 && cell.z >= 1 && cell.z <= 2), "rotation %d holds the interior cell %v", rotation, cell)
		}
		low, high := placed_part_slot_box(Entity_Common{rotation = rotation}, ring, ring.part_slots[0])
		testing.expect_value(t, low, World_Coordinate{1, 0, 1})
		testing.expect_value(t, high, World_Coordinate{2, 1, 2})
	}
	origin := World_Coordinate{-1, 0, -1}
	turned := Entity_Common{origin = origin, rotation = 1}
	straight := Entity_Common{origin = origin}
	turned_low, turned_high := placed_part_slot_box(turned, ring, ring.part_slots[1])
	straight_low, straight_high := placed_part_slot_box(straight, ring, ring.part_slots[2])
	testing.expect_value(t, turned_low, straight_low)
	testing.expect_value(t, turned_high, straight_high)
	testing.expect_value(t, straight_low, World_Coordinate{1, 0, -2})
	for slot in ring.part_slots[1:5] {
		low, _ := placed_part_slot_box(turned, ring, slot)
		found := false
		for other in ring.part_slots[1:5] {
			other_low, _ := placed_part_slot_box(straight, ring, other)
			found ||= other_low == low
		}
		testing.expectf(t, found, "the turned box at %v is a straight one", low)
	}
	// The truss's top slot and the deck plate's underneath one keep their
	// height and turn about the footprint.
	deck := machines.machines[test_machine(machines, "iron_deck_plate")]
	low, high := placed_part_slot_box(Entity_Common{origin = {5, 3, 5}, rotation = 3}, deck, deck.part_slots[1])
	testing.expect_value(t, low, World_Coordinate{5, 1, 5})
	testing.expect_value(t, high, World_Coordinate{6, 2, 6})
}
