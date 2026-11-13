package game

import "core:fmt"
import "core:math"

// A machine's ports for cables and pipes (work items 0361 and 0368,
// doc/vessels.md, doc/content.md): a named face of one footprint cell
// where a power cable or a fluid pipe ends, with the most it carries. The
// vessel kinds list both kinds; outside them every electric machine and
// generator lists one power port, first, and the junction boxes and the
// power switch list theirs (cable.odin); the pipes (0356) extend the
// fluid kind to the other machines. A save names a port by its index, so
// a record's ports are appended to and never reordered. Separate from
// fluid_ports (machine_fluid_ports.odin), the fluid network's buffers.

MAXIMUM_MACHINE_PORTS :: 8
// Watts or litres a second; keeps a sum of every port far inside an i64.
MAXIMUM_PORT_CAPACITY :: 1_000_000_000

Machine_Port_Kind :: enum u8 {
	Power,
	Fluid,
}

@(rodata)
machine_port_kind_names := [Machine_Port_Kind]string {
	.Power = "power",
	.Fluid = "fluid",
}

// As written in data/machines.sjson: a power port has capacity_watts, a
// fluid port capacity_litres_per_second, the other key 0.
Machine_Port_Definition :: struct {
	id:                         string,
	kind:                       string,
	cell:                       Machine_Cell_Definition,
	face:                       string,
	capacity_watts:             int,
	capacity_litres_per_second: int,
}

// cell is of the unrotated footprint, face out of it; capacity in watts
// for power, litres a second for fluid.
Machine_Port :: struct {
	id:       string,
	kind:     Machine_Port_Kind,
	cell:     [3]i32,
	face:     Direction,
	capacity: i64,
}

// A machine's ports: the kind's (validate_power_ports_of_kind), at most
// MAXIMUM_MACHINE_PORTS, each with an id unique on the machine, a known
// kind and face, its cell on the footprint's surface with the face out of
// it (port_cell_is_on_the_surface), no two on one cell and face, and the
// capacity of its kind 1 to MAXIMUM_PORT_CAPACITY with the other 0.
validate_machine_ports :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if problem := validate_power_ports_of_kind(definition, kind); problem != "" {
		return problem
	}
	if len(definition.ports) == 0 {
		return ""
	}
	if len(definition.ports) > MAXIMUM_MACHINE_PORTS {
		return fmt.tprintf("machine %q has more than %d ports", definition.id, MAXIMUM_MACHINE_PORTS)
	}
	footprint := [3]int{definition.footprint.width, definition.footprint.height, definition.footprint.depth}
	for port, index in definition.ports {
		if problem := validate_machine_port(definition, port, footprint); problem != "" {
			return problem
		}
		for earlier in definition.ports[:index] {
			if earlier.id == port.id {
				return fmt.tprintf("machine %q has two ports %q", definition.id, port.id)
			}
			if earlier.cell == port.cell && earlier.face == port.face {
				return fmt.tprintf("machine %q ports %q and %q share a cell and face", definition.id, earlier.id, port.id)
			}
		}
	}
	return ""
}

// The rating of an electric machine or generator in watts, 0 for none.
definition_electric_watts :: proc(definition: Machine_Definition) -> int {
	kilowatts := max(definition.electric_power_kilowatts, definition.electric_output_kilowatts)
	return int(math.round(kilowatts * 1000))
}

// Which ports a kind lists (0368): any for the vessel kinds; outside
// them power ports only (the fluid kind waits for the pipes, 0356), one
// at index 0 of at least the rating on an electric machine or generator,
// 2 to MAXIMUM_MACHINE_PORTS on a junction box, 2 on a power switch, and
// none on any other kind.
validate_power_ports_of_kind :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if machine_kind_is_vessel(kind) {
		return ""
	}
	for port in definition.ports {
		if port.kind != machine_port_kind_names[.Power] {
			return fmt.tprintf("machine %q port %q is not a power port, which only a vessel part may list", definition.id, port.id)
		}
	}
	watts, count := definition_electric_watts(definition), len(definition.ports)
	switch {
	case watts > 0:
		if count != 1 || definition.ports[0].capacity_watts < watts {
			return fmt.tprintf("electric machine %q needs one power port, first, with capacity_watts of at least %d", definition.id, watts)
		}
	case kind == .Junction_Box:
		if count < 2 || count > MAXIMUM_MACHINE_PORTS {
			return fmt.tprintf("junction box %q needs 2 to %d power ports", definition.id, MAXIMUM_MACHINE_PORTS)
		}
	case kind == .Power_Switch:
		if count != 2 {
			return fmt.tprintf("power switch %q needs exactly 2 power ports", definition.id)
		}
	case count > 0:
		return fmt.tprintf("machine %q lists ports, which only an electric machine, a generator, a junction box, a power switch or a vessel part may", definition.id)
	}
	return ""
}

// One port's own rules (validate_machine_ports).
validate_machine_port :: proc(definition: Machine_Definition, port: Machine_Port_Definition, footprint: [3]int) -> string {
	if port.id == "" {
		return fmt.tprintf("machine %q has a port without an id", definition.id)
	}
	port_kind, kind_found := parse_named_enum(machine_port_kind_names, port.kind)
	if !kind_found {
		return fmt.tprintf("machine %q port %q has unknown kind %q, not power or fluid", definition.id, port.id, port.kind)
	}
	face, face_found := parse_direction_name(port.face)
	if !face_found {
		return fmt.tprintf("machine %q port %q has unknown face %q", definition.id, port.id, port.face)
	}
	// Checked as ints before the cast, so an oversized value cannot wrap
	// into the footprint.
	cell := [3]int{port.cell.x, port.cell.y, port.cell.z}
	for axis in 0 ..< 3 {
		if cell[axis] < 0 || cell[axis] >= footprint[axis] {
			return fmt.tprintf("machine %q port %q is not on a footprint cell", definition.id, port.id)
		}
	}
	if !port_cell_is_on_the_surface({i32(cell.x), i32(cell.y), i32(cell.z)}, face, {i32(footprint.x), i32(footprint.y), i32(footprint.z)}) {
		return fmt.tprintf("machine %q port %q does not face out of the footprint", definition.id, port.id)
	}
	capacity, other := port.capacity_watts, port.capacity_litres_per_second
	key, other_key := "capacity_watts", "capacity_litres_per_second"
	if port_kind == .Fluid {
		capacity, other = other, capacity
		key, other_key = other_key, key
	}
	if capacity < 1 || capacity > MAXIMUM_PORT_CAPACITY {
		return fmt.tprintf("machine %q port %q has %s %d outside 1 to %d", definition.id, port.id, key, capacity, MAXIMUM_PORT_CAPACITY)
	}
	if other != 0 {
		return fmt.tprintf("machine %q port %q is a %s port and cannot have %s", definition.id, port.id, port.kind, other_key)
	}
	return ""
}

// The world cell and face of a port on a placed machine, as
// placed_port_face of a fluid port.
placed_machine_port_face :: proc(common: Entity_Common, machine: Machine, port: Machine_Port) -> Cell_Face {
	offset := rotate_footprint_cell(port.cell.xz, machine.footprint.x, machine.footprint.z, common.rotation)
	return {cell = common.origin + {offset.x, port.cell.y, offset.y}, face = rotate_direction(port.face, common.rotation)}
}

// Validated before (validate_machine_ports).
resolve_machine_ports :: proc(definitions: []Machine_Port_Definition) -> (ports: [MAXIMUM_MACHINE_PORTS]Machine_Port, count: int) {
	for definition in definitions[:min(len(definitions), MAXIMUM_MACHINE_PORTS)] {
		kind, _ := parse_named_enum(machine_port_kind_names, definition.kind)
		face, _ := parse_direction_name(definition.face)
		capacity := kind == .Power ? definition.capacity_watts : definition.capacity_litres_per_second
		cell := definition.cell
		ports[count] = Machine_Port {
			id       = definition.id,
			kind     = kind,
			cell     = {i32(cell.x), i32(cell.y), i32(cell.z)},
			face     = face,
			capacity = i64(capacity),
		}
		count += 1
	}
	return ports, count
}
