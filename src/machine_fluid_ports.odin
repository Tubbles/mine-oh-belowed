package game

import "core:fmt"

// Fluid ports of machines (data/machines.sjson, doc/fluids.md). A port is
// a face of one footprint cell, or with face "all" every outward face of
// the footprint, with its own litre buffer. Ports rotate with the
// footprint. Each port is one segment of the fluid network it touches.

MAXIMUM_FLUID_PORTS :: 4

// Input only takes from the network, output only gives, both does either.
Fluid_Port_Direction :: enum u8 {
	Input,
	Output,
	Both,
}

@(rodata)
fluid_port_direction_names := [Fluid_Port_Direction]string {
	.Input  = "input",
	.Output = "output",
	.Both   = "both",
}

@(rodata)
direction_names := [Direction]string {
	.Negative_X = "negative_x",
	.Positive_X = "positive_x",
	.Negative_Y = "negative_y",
	.Positive_Y = "positive_y",
	.Negative_Z = "negative_z",
	.Positive_Z = "positive_z",
}

EVERY_FACE_NAME :: "all"

Fluid_Port_Cell_Definition :: struct {
	x: int,
	y: int,
	z: int,
}

// cell is x along the width, y up, z along the depth of the unrotated
// footprint. fluid is optional: a port with one only ever holds it.
// phase is optional too: liquid, gas or burnable_gas (a gas with a fuel
// value), what the port admits.
Fluid_Port_Definition :: struct {
	cell:          Fluid_Port_Cell_Definition,
	face:          string,
	direction:     string,
	fluid:         string,
	phase:         string,
	buffer_litres: int,
}

// every_face ports ignore cell and face.
Fluid_Port :: struct {
	cell:         [3]i32,
	face:         Direction,
	every_face:   bool,
	direction:    Fluid_Port_Direction,
	filter:       Fluid_Id,
	phase_filter: Fluid_Phase_Filter,
	capacity:     i32,
}

parse_direction_name :: proc(name: string) -> (direction: Direction, found: bool) {
	for candidate in Direction {
		if direction_names[candidate] == name {
			return candidate, true
		}
	}
	return .Positive_X, false
}

parse_fluid_port_direction :: proc(name: string) -> (direction: Fluid_Port_Direction, found: bool) {
	for candidate in Fluid_Port_Direction {
		if fluid_port_direction_names[candidate] == name {
			return candidate, true
		}
	}
	return .Both, false
}

// Inside the footprint, and with the face pointing out of it.
port_cell_is_on_the_surface :: proc(cell: [3]i32, face: Direction, footprint: [3]i32) -> bool {
	for axis in 0 ..< 3 {
		if cell[axis] < 0 || cell[axis] >= footprint[axis] {
			return false
		}
	}
	outside := cell + direction_offsets[face]
	for axis in 0 ..< 3 {
		if outside[axis] < 0 || outside[axis] >= footprint[axis] {
			return true
		}
	}
	return false
}

resolve_fluid_port :: proc(definition: Fluid_Port_Definition, footprint: [3]i32, fluids: Fluid_Registry) -> (port: Fluid_Port, problem: string) {
	direction, direction_found := parse_fluid_port_direction(definition.direction)
	if !direction_found {
		return {}, fmt.tprintf("unknown port direction %q", definition.direction)
	}
	if definition.buffer_litres <= 0 {
		return {}, "a port needs a positive buffer_litres"
	}
	port = Fluid_Port{direction = direction, filter = NO_FLUID, capacity = i32(definition.buffer_litres)}
	phase_found: bool
	if port.phase_filter, phase_found = parse_named_enum(fluid_phase_filter_names, definition.phase); !phase_found {
		return {}, fmt.tprintf("unknown port phase %q", definition.phase)
	}
	if definition.fluid != "" {
		found: bool
		if port.filter, found = find_fluid_id(fluids, definition.fluid); !found {
			return {}, fmt.tprintf("unknown port fluid %q", definition.fluid)
		}
	}
	if definition.face == EVERY_FACE_NAME {
		port.every_face = true
		return port, ""
	}
	face_found: bool
	if port.face, face_found = parse_direction_name(definition.face); !face_found {
		return {}, fmt.tprintf("unknown port face %q", definition.face)
	}
	port.cell = {i32(definition.cell.x), i32(definition.cell.y), i32(definition.cell.z)}
	if !port_cell_is_on_the_surface(port.cell, port.face, footprint) {
		return {}, "a port must sit on a footprint cell and face out of the footprint"
	}
	return port, ""
}

resolve_fluid_ports :: proc(machine: ^Machine, definition: Machine_Definition, fluids: Fluid_Registry) -> string {
	if len(definition.fluid_ports) > MAXIMUM_FLUID_PORTS {
		return fmt.tprintf("machine %q has more than %d fluid ports", definition.id, MAXIMUM_FLUID_PORTS)
	}
	for port_definition, index in definition.fluid_ports {
		port, problem := resolve_fluid_port(port_definition, machine.footprint, fluids)
		if problem != "" {
			return fmt.tprintf("machine %q port %d: %s", definition.id, index, problem)
		}
		machine.fluid_ports[index] = port
	}
	machine.fluid_port_count = len(definition.fluid_ports)
	return validate_fluid_port_layout(machine^)
}

// The ports in use, in the temp allocator.
fluid_ports_of :: proc(machine: Machine) -> []Fluid_Port {
	ports := new_clone(machine.fluid_ports, context.temp_allocator)
	return ports[:machine.fluid_port_count]
}

count_ports_of_direction :: proc(machine: Machine, direction: Fluid_Port_Direction) -> int {
	count := 0
	for port in fluid_ports_of(machine) {
		if port.direction == direction {
			count += 1
		}
	}
	return count
}

// The number and direction of ports each fluid machine works with. The
// boiler reads its fluids from its port filters, so both need one.
validate_fluid_port_layout :: proc(machine: Machine) -> string {
	ports := fluid_ports_of(machine)
	inputs := count_ports_of_direction(machine, .Input)
	outputs := count_ports_of_direction(machine, .Output)
	#partial switch machine.kind {
	case .Pipe:
		if len(ports) != 0 {
			return fmt.tprintf("pipe %q connects on every face and takes no fluid_ports", machine.id)
		}
	case .Offshore_Pump:
		if len(ports) != 1 || outputs != 1 || ports[0].filter == NO_FLUID {
			return fmt.tprintf("offshore pump %q needs one output port with a fluid", machine.id)
		}
	case .Boiler:
		if len(ports) != 2 || inputs != 1 || outputs != 1 || ports[0].filter == NO_FLUID || ports[1].filter == NO_FLUID {
			return fmt.tprintf("boiler %q needs one input and one output port, each with a fluid", machine.id)
		}
	case .Steam_Engine:
		if len(ports) == 0 || inputs != len(ports) {
			return fmt.tprintf("steam engine %q needs input ports only", machine.id)
		}
	case .Storage_Tank:
		if len(ports) != 1 {
			return fmt.tprintf("storage tank %q needs one port", machine.id)
		}
	case .Pump:
		if len(ports) != 2 || inputs != 1 || outputs != 1 {
			return fmt.tprintf("pump %q needs one input and one output port", machine.id)
		}
	case .Tar_Pit_Pump:
		if len(ports) != 1 || outputs != 1 || ports[0].filter == NO_FLUID {
			return fmt.tprintf("tar pit pump %q needs one output port with a fluid", machine.id)
		}
	case .Flare_Stack:
		if len(ports) != 1 || inputs != 1 || ports[0].phase_filter != .Gas {
			return fmt.tprintf("flare stack %q needs one input port admitting gases only", machine.id)
		}
	case .Combustion_Generator:
		// No port makes a fuel generator (0140), which burns items only.
		gas_port := len(ports) == 1 && inputs == 1 && ports[0].phase_filter == .Burnable_Gas
		if len(ports) != 0 && !gas_port {
			return fmt.tprintf("combustion generator %q needs one input port admitting burnable gases only, or none", machine.id)
		}
	case .Drill:
		// A revival port: one input port holding one fluid (drill.odin).
		revival := len(ports) == 1 && inputs == 1 && ports[0].filter != NO_FLUID && !ports[0].every_face
		if machine.revival_port != revival {
			return fmt.tprintf("drill %q needs revival_port with exactly one single face input port with a fluid, or neither", machine.id)
		}
	case .Launch_Pad:
		// The fuel port: one input port holding one fluid, room for a
		// rocket's fuel (launch_pad.odin).
		fuel_port := len(ports) == 1 && inputs == 1 && ports[0].filter != NO_FLUID && !ports[0].every_face
		if !fuel_port || ports[0].capacity < machine.launch_fuel_litres {
			return fmt.tprintf("launch pad %q needs one single face input port with a fluid, holding at least launch_fuel_litres", machine.id)
		}
	case .Crafting_Machine:
		// Recipes take from input ports and give into output ports.
		if inputs + outputs != len(ports) {
			return fmt.tprintf("crafting machine %q may only have input and output ports", machine.id)
		}
	case:
		if len(ports) != 0 {
			return fmt.tprintf("machine %q cannot have fluid ports", machine.id)
		}
	}
	return ""
}

machine_kind_is_pump :: proc(kind: Machine_Kind) -> bool {
	return kind == .Offshore_Pump || kind == .Pump || kind == .Tar_Pit_Pump
}

// Keeps a port height plus the head far inside i32.
MAXIMUM_HEAD_METRES :: 1000

// Every pump kind lifts liquid up to a head of 1 to MAXIMUM_HEAD_METRES
// metres (0139); no other kind has one.
validate_pump_head :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if machine_kind_is_pump(kind) && (definition.head_metres < 1 || definition.head_metres > MAXIMUM_HEAD_METRES) {
		return fmt.tprintf("pump %q needs a head_metres from 1 to %d", definition.id, MAXIMUM_HEAD_METRES)
	}
	if !machine_kind_is_pump(kind) && definition.head_metres != 0 {
		return fmt.tprintf("machine %q is not a pump and cannot have head_metres", definition.id)
	}
	return ""
}

// The fields that need no fluid registry.
validate_fluid_machine_definition :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	footprint := definition.footprint
	#partial switch kind {
	case .Pipe:
		if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 {
			return fmt.tprintf("pipe %q must have a 1 by 1 by 1 footprint", definition.id)
		}
		if definition.buffer_litres <= 0 || definition.flow_litres_per_second <= 0 {
			return fmt.tprintf("pipe %q needs a positive buffer_litres and flow_litres_per_second", definition.id)
		}
	case .Offshore_Pump:
		if definition.fluid_litres_per_second <= 0 {
			return fmt.tprintf("offshore pump %q needs a positive fluid_litres_per_second", definition.id)
		}
	case .Boiler:
		if definition.fuel_slots != 1 || definition.fuel_power_kilowatts <= 0 || definition.fluid_litres_per_second <= 0 {
			return fmt.tprintf("boiler %q needs one fuel slot, fuel_power_kilowatts and fluid_litres_per_second", definition.id)
		}
	case .Steam_Engine:
		if definition.fluid_litres_per_second <= 0 || definition.electric_output_kilowatts <= 0 {
			return fmt.tprintf("steam engine %q needs a positive fluid_litres_per_second and electric_output_kilowatts", definition.id)
		}
	case .Pump, .Flare_Stack:
		if definition.fluid_litres_per_second <= 0 || definition.electric_power_kilowatts <= 0 {
			return fmt.tprintf("machine %q needs a positive fluid_litres_per_second and electric_power_kilowatts", definition.id)
		}
	case .Combustion_Generator:
		if definition.fuel_slots != 1 || definition.electric_output_kilowatts <= 0 {
			return fmt.tprintf("combustion generator %q needs one fuel slot and a positive electric_output_kilowatts", definition.id)
		}
	case .Hydro_Turbine:
		return validate_hydro_turbine_definition(definition)
	case .Tar_Pit_Pump:
		if definition.fluid_litres_per_minute <= 0 || definition.electric_power_kilowatts <= 0 {
			return fmt.tprintf("tar pit pump %q needs a positive fluid_litres_per_minute and electric_power_kilowatts", definition.id)
		}
	}
	return ""
}

@(rodata)
opposite_directions := [Direction]Direction {
	.Negative_X = .Positive_X,
	.Positive_X = .Negative_X,
	.Negative_Y = .Positive_Y,
	.Positive_Y = .Negative_Y,
	.Negative_Z = .Positive_Z,
	.Positive_Z = .Negative_Z,
}

// A face of one placed cell.
Cell_Face :: struct {
	cell: World_Coordinate,
	face: Direction,
}

// The world cell and face of a single face port on a placed machine.
placed_port_face :: proc(common: Entity_Common, machine: Machine, port: Fluid_Port) -> Cell_Face {
	offset := rotate_footprint_cell(port.cell.xz, machine.footprint.x, machine.footprint.z, common.rotation)
	return {cell = common.origin + {offset.x, port.cell.y, offset.y}, face = rotate_direction(port.face, common.rotation)}
}

cell_in_box :: proc(cell, origin: World_Coordinate, size: [3]i32) -> bool {
	for axis in 0 ..< 3 {
		if cell[axis] < origin[axis] || cell[axis] >= origin[axis] + size[axis] {
			return false
		}
	}
	return true
}

// Every face a port connects through, in the temp allocator: one for a
// single face port, every outward face of the footprint for the others.
placed_port_faces :: proc(common: Entity_Common, machine: Machine, port: Fluid_Port) -> []Cell_Face {
	if !port.every_face {
		faces := make([]Cell_Face, 1, context.temp_allocator)
		faces[0] = placed_port_face(common, machine, port)
		return faces
	}
	faces := make([dynamic]Cell_Face, context.temp_allocator)
	for cell in footprint_cells(common.origin, machine.footprint, common.rotation) {
		for face in Direction {
			if !cell_in_box(cell + World_Coordinate(direction_offsets[face]), common.origin, common.size) {
				append(&faces, Cell_Face{cell, face})
			}
		}
	}
	return faces[:]
}

// The port of a placed machine that connects through face of cell, or -1.
port_at_face :: proc(common: Entity_Common, machine: Machine, cell: World_Coordinate, face: Direction) -> int {
	if cell_in_box(cell + World_Coordinate(direction_offsets[face]), common.origin, common.size) {
		return -1
	}
	for port, index in fluid_ports_of(machine) {
		if port.every_face {
			return index
		}
		if placed_port_face(common, machine, port) == (Cell_Face{cell, face}) {
			return index
		}
	}
	return -1
}

// The height a port's buffer counts at for gravity: its cell, or the
// bottom of the machine for an every face port.
placed_port_height :: proc(common: Entity_Common, machine: Machine, port: Fluid_Port) -> i32 {
	if port.every_face {
		return common.origin.y
	}
	return placed_port_face(common, machine, port).cell.y
}
