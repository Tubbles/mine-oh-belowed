package game

import "core:fmt"
import "core:math"

// A machine's ports for cables and pipes (work items 0361, 0368 and 0374,
// doc/vessels.md, doc/content.md): a named face of one footprint cell
// where a power cable or a fluid pipe ends, with the most it carries. The
// vessel kinds list both kinds; outside them every electric machine and
// generator lists one power port, first, and the junction boxes and the
// power switch list theirs (cable.odin); a machine with fluid_ports lists
// a fluid port on each buffer a hand run pipe meets, and a fluid junction
// its fluid ports. A save names a port by its index, so a record's ports
// are appended to and never reordered. Separate from fluid_ports
// (machine_fluid_ports.odin), the fluid network's buffers, which a fluid
// port meets by fluid_buffer.

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
// for power, litres a second for fluid. fluid_buffer is derived
// (link_fluid_ports_to_buffers): for a fluid port the index into the
// machine's fluid_ports of the buffer it meets; -1 for a power port, a
// vessel part's fluid port and a fluid junction's port.
Machine_Port :: struct {
	id:           string,
	kind:         Machine_Port_Kind,
	cell:         [3]i32,
	face:         Direction,
	capacity:     i64,
	fluid_buffer: i8,
}

// A machine's ports: the kind's (validate_ports_of_kind), at most
// MAXIMUM_MACHINE_PORTS, each with an id unique on the machine, a known
// kind and face, its cell on the footprint's surface with the face out of
// it (port_cell_is_on_the_surface), no two on one cell and face, and the
// capacity of its kind up to MAXIMUM_PORT_CAPACITY, from 1 watt or from
// MINIMUM_PIPE_LITRES_PER_SECOND, with the other 0.
validate_machine_ports :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if problem := validate_ports_of_kind(definition, kind); problem != "" {
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

// Which ports a kind lists (0368, 0374): any for the vessel kinds.
// Outside them a fluid port only on a record with fluid_ports, which the
// port meets (link_fluid_ports_to_buffers), or on a fluid junction; and
// counting power ports only, one at index 0 of at least the rating on an
// electric machine or generator, 2 to MAXIMUM_MACHINE_PORTS and no fluid
// port on a junction box, 2 and no fluid port on a power switch, none on
// any other kind. A fluid junction lists 2 to MAXIMUM_MACHINE_PORTS fluid
// ports and no power port.
validate_ports_of_kind :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if machine_kind_is_vessel(kind) {
		return ""
	}
	fluid_count := 0
	for port in definition.ports {
		if port.kind != machine_port_kind_names[.Fluid] {
			continue
		}
		if len(definition.fluid_ports) == 0 && kind != .Fluid_Junction {
			return fmt.tprintf("machine %q port %q is a fluid port, which only a machine with fluid_ports, a fluid junction or a vessel part may list", definition.id, port.id)
		}
		fluid_count += 1
	}
	watts, count := definition_electric_watts(definition), len(definition.ports) - fluid_count
	switch {
	case kind == .Fluid_Junction:
		if fluid_count < 2 || fluid_count > MAXIMUM_MACHINE_PORTS || count > 0 {
			return fmt.tprintf("fluid junction %q needs 2 to %d fluid ports and no power port", definition.id, MAXIMUM_MACHINE_PORTS)
		}
	case watts > 0:
		if count != 1 || definition.ports[0].kind != machine_port_kind_names[.Power] || definition.ports[0].capacity_watts < watts {
			return fmt.tprintf("electric machine %q needs one power port, first, with capacity_watts of at least %d", definition.id, watts)
		}
	case kind == .Junction_Box:
		if count < 2 || count > MAXIMUM_MACHINE_PORTS || fluid_count > 0 {
			return fmt.tprintf("junction box %q needs 2 to %d power ports", definition.id, MAXIMUM_MACHINE_PORTS)
		}
	case kind == .Power_Switch:
		if count != 2 || fluid_count > 0 {
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
	// A fluid port takes the pipe's minimum, a litre a tick at 60 Hz: below
	// it a pipe on the port would carry nothing (scale_fluid_capacities).
	minimum := port_kind == .Fluid ? MINIMUM_PIPE_LITRES_PER_SECOND : 1
	if capacity < minimum || capacity > MAXIMUM_PORT_CAPACITY {
		return fmt.tprintf("machine %q port %q has %s %d outside %d to %d", definition.id, port.id, key, capacity, minimum, MAXIMUM_PORT_CAPACITY)
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
			id           = definition.id,
			kind         = kind,
			cell         = {i32(cell.x), i32(cell.y), i32(cell.z)},
			face         = face,
			capacity     = i64(capacity),
			fluid_buffer = -1,
		}
		count += 1
	}
	return ports, count
}

// After resolve_fluid_ports (0374): each fluid port meets the buffer of its
// cell and face, else the first every_face one. Outside the vessel kinds
// and the fluid junction, whose fluid ports keep -1, a fluid port that
// meets none is refused. A buffer without a port stays allowed: the block
// world joins it by face.
link_fluid_ports_to_buffers :: proc(machine: ^Machine, id: string) -> string {
	if machine_kind_is_vessel(machine.kind) || machine.kind == .Fluid_Junction {
		return ""
	}
	for &port in machine.ports[:machine.port_count] {
		if port.kind != .Fluid {
			continue
		}
		port.fluid_buffer = i8(fluid_buffer_met_by(machine^, port))
		if port.fluid_buffer < 0 {
			return fmt.tprintf("machine %q fluid port %q meets none of its fluid_ports", id, port.id)
		}
	}
	return ""
}

// The index of the buffer on the port's cell and face, else of the first
// every_face buffer, else -1.
fluid_buffer_met_by :: proc(machine: Machine, port: Machine_Port) -> int {
	every_face := -1
	for buffer, index in fluid_ports_of(machine) {
		if buffer.every_face {
			every_face = every_face < 0 ? index : every_face
		} else if buffer.cell == port.cell && buffer.face == port.face {
			return index
		}
	}
	return every_face
}
