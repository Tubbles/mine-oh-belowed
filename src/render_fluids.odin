package game

import rl "shared:raylib"

// Placeholder fluid models: a pipe is a small core cube with a stub
// towards every neighbour it connects to and a band in the fluid's colour
// whose height follows the level. Fluid machines are coloured boxes with
// their single face ports drawn as squares on the footprint faces, in the
// colour of the fluid held or taken (every face ports, the tank's, get
// none). Offshore pumps, pumps and tar pit pumps show their direction with
// an arrow. A flare stack's top glows while it burns gas, a combustion
// generator's top is brighter while it generates. A fluid machine with a
// model (render_models.odin) is drawn with it, animated while its
// bottleneck marker would be green; the ports and arrows stay. Pipes keep
// their stubs: a model per connection shape is left for later.

PIPE_COLOR :: rl.Color{110, 112, 118, 255}
FLARE_BURNING_TOP_COLOR :: rl.Color{255, 170, 60, 255}
GENERATING_TOP_COLOR :: rl.Color{200, 185, 140, 255}
PIPE_CORE_SIZE :: 0.3
PIPE_STUB_SIZE :: 0.22
PIPE_BAND_MARGIN :: 0.02
PORT_EMPTY_COLOR :: rl.Color{90, 90, 90, 255}
PORT_SQUARE_SIZE :: 0.5
PORT_SQUARE_THICKNESS :: 0.03
FLUID_MACHINE_ARROW_COLOR :: rl.Color{240, 220, 80, 255}

@(rodata)
fluid_machine_colors := [Machine_Kind]rl.Color {
	.Chest         = {},
	.Furnace       = {},
	.Capsule       = {},
	.Belt          = {},
	.Inserter      = {},
	.Drill         = {},
	.Splitter      = {},
	.Pipe          = PIPE_COLOR,
	.Offshore_Pump = {70, 120, 160, 255},
	.Boiler        = {150, 80, 60, 255},
	.Steam_Engine  = {90, 110, 90, 255},
	.Storage_Tank  = {140, 140, 150, 255},
	.Pump          = {80, 130, 170, 255},
	.Tar_Pit_Pump  = {70, 64, 60, 255},
	.Flare_Stack   = {120, 110, 100, 255},
	.Combustion_Generator = {110, 100, 80, 255},
	.Hydro_Turbine = {90, 120, 140, 255},
	.Pole          = {},
	.Power_Switch  = {},
	.Lamp          = {},
	.Crafting_Machine = {},
	.Lab           = {},
	.Schematic_Crate = {},
	.Core_Sample_Drill = {},
	.Launch_Pad    = {},
	.Foundation    = {},
}

fluid_color :: proc(fluids: Fluid_Registry, fluid: Fluid_Id) -> rl.Color {
	if int(fluid) >= len(fluids.fluids) {
		return PORT_EMPTY_COLOR
	}
	color := fluids.fluids[fluid].color
	return {color.r, color.g, color.b, 255}
}

// Whether the pipe at cell connects through face: another pipe, or a
// machine port facing back.
pipe_connects_through :: proc(entities: ^Entities, machines: Machine_Registry, cell: World_Coordinate, face: Direction) -> bool {
	neighbour := cell + World_Coordinate(direction_offsets[face])
	handle := entity_at(entities, neighbour)
	#partial switch handle.kind {
	case .Pipe:
		return true
	case .Fluid_Machine, .Assembler, .Drill, .Launch_Pad:
		common := entity_common(entities, handle)
		return port_at_face(common^, machines.machines[common.machine], neighbour, opposite_directions[face]) >= 0
	}
	return false
}

vector_of :: proc(offset: [3]i32) -> [3]f32 {
	return {f32(offset.x), f32(offset.y), f32(offset.z)}
}

// A box from the core's face to the cell's face along the offset.
pipe_stub :: proc(centre: [3]f32, face: Direction) -> (stub_centre, size: [3]f32) {
	direction := vector_of(direction_offsets[face])
	length := f32(0.5 - PIPE_CORE_SIZE / 2)
	stub_centre = centre + direction * (PIPE_CORE_SIZE / 2 + length / 2)
	for axis in 0 ..< 3 {
		size[axis] = direction[axis] != 0 ? length : PIPE_STUB_SIZE
	}
	return
}

draw_pipe :: proc(world: ^World, pipe: Pipe, machines: Machine_Registry, fluids: Fluid_Registry) {
	centre := block_centre(pipe.origin)
	rl.DrawCube(centre, PIPE_CORE_SIZE, PIPE_CORE_SIZE, PIPE_CORE_SIZE, PIPE_COLOR)
	for face in Direction {
		if pipe_connects_through(&world.entities, machines, pipe.origin, face) {
			stub_centre, size := pipe_stub(centre, face)
			rl.DrawCubeV(stub_centre, size, PIPE_COLOR)
		}
	}
	capacity := machines.machines[pipe.machine].buffer_litres
	if pipe.buffer.level <= 0 || capacity <= 0 {
		return
	}
	height := PIPE_CORE_SIZE * f32(pipe.buffer.level) / f32(capacity)
	bottom := centre.y - PIPE_CORE_SIZE / 2
	band := f32(PIPE_CORE_SIZE + 2 * PIPE_BAND_MARGIN)
	rl.DrawCubeV({centre.x, bottom + height / 2, centre.z}, {band, height, band}, fluid_color(fluids, pipe.buffer.fluid))
}

// A thin square on the outside of the port's face.
draw_port_square :: proc(face: Cell_Face, color: rl.Color) {
	normal := vector_of(direction_offsets[face.face])
	centre := block_centre(face.cell) + normal * (0.5 + PORT_SQUARE_THICKNESS / 2)
	size: [3]f32
	for axis in 0 ..< 3 {
		size[axis] = normal[axis] != 0 ? PORT_SQUARE_THICKNESS : PORT_SQUARE_SIZE
	}
	rl.DrawCubeV(centre, size, color)
}

// buffers may be nil for a ghost, which shows the ports' filter colours.
draw_fluid_ports :: proc(common: Entity_Common, machine: Machine, buffers: []Fluid_Buffer, fluids: Fluid_Registry) {
	for port, index in fluid_ports_of(machine) {
		if port.every_face {
			continue
		}
		fluid := port.filter
		if buffers != nil && buffers[index].level > 0 {
			fluid = buffers[index].fluid
		}
		draw_port_square(placed_port_face(common, machine, port), fluid_color(fluids, fluid))
	}
}

fluid_machine_has_arrow :: proc(kind: Machine_Kind) -> bool {
	return kind == .Offshore_Pump || kind == .Pump || kind == .Tar_Pit_Pump
}

draw_fluid_machine :: proc(fluid_machine: Fluid_Machine, machines: Machine_Registry, models: Model_Renderer, fluids: Fluid_Registry, frame: Model_Frame) {
	machine := machines.machines[fluid_machine.machine]
	color := fluid_machine_colors[machine.kind]
	top_color := color
	if machine.kind == .Flare_Stack && fluid_machine.state == .Flaring {
		top_color = FLARE_BURNING_TOP_COLOR
	}
	if (machine.kind == .Combustion_Generator || machine.kind == .Hydro_Turbine) && fluid_machine.state == .Generating {
		top_color = GENERATING_TOP_COLOR
	}
	working := marker_means_working(machine_marker_colour(fluid_machine.state, true))
	draw_entity_cells(fluid_machine.common, machines, models, frame, working, color, top_color)
	buffers := fluid_machine.buffers
	draw_fluid_ports(fluid_machine.common, machine, buffers[:], fluids)
	if fluid_machine_has_arrow(machine.kind) {
		draw_direction_arrow(fluid_machine.origin, fluid_machine.size, fluid_machine.rotation, FLUID_MACHINE_ARROW_COLOR)
	}
}

// On the top face, from the centre to the end the rotation points at.
draw_direction_arrow :: proc(origin: World_Coordinate, size: [3]i32, rotation: u8, color: rl.Color) {
	centre := box_centre(origin, size)
	centre.y = f32(origin.y + size.y) + 0.02
	forward := belt_direction_vector(rotation)
	half_length := (abs(forward.x) * f32(size.x) + abs(forward.z) * f32(size.z)) / 2
	tip := centre + forward * half_length
	rl.DrawLine3D(centre, tip, color)
	rl.DrawCubeV(tip, {0.12, 0.12, 0.12}, color)
}

// Between BeginMode3D and EndMode3D, after the chunks.
draw_fluid_entities :: proc(world: ^World, machines: Machine_Registry, models: Model_Renderer, fluids: Fluid_Registry, frame: Model_Frame) {
	for pipe in world.entities.pipes.entries {
		if pipe.alive {
			draw_pipe(world, pipe, machines, fluids)
		}
	}
	for fluid_machine in world.entities.fluid_machines.entries {
		if fluid_machine.alive {
			draw_fluid_machine(fluid_machine, machines, models, fluids, frame)
		}
	}
	for assembler in world.entities.assemblers.entries {
		if assembler.alive {
			buffers := assembler.buffers
			draw_fluid_ports(assembler.common, machines.machines[assembler.machine], buffers[:], fluids)
		}
	}
	for drill in world.entities.drills.entries {
		if drill.alive {
			buffers := drill.buffers
			draw_fluid_ports(drill.common, machines.machines[drill.machine], buffers[:], fluids)
		}
	}
	for pad in world.entities.launch_pads.entries {
		if pad.alive {
			buffers := pad.buffers
			draw_fluid_ports(pad.common, machines.machines[pad.machine], buffers[:], fluids)
		}
	}
}

// The ports and the direction arrow on a fluid machine's ghost.
draw_fluid_machine_ghost :: proc(placement: Placement, machines: Machine_Registry, fluids: Fluid_Registry) {
	machine := machines.machines[placement.machine]
	if machine.fluid_port_count == 0 {
		return
	}
	common := Entity_Common{machine = placement.machine, origin = placement.origin, rotation = placement.rotation, size = placement.size}
	draw_fluid_ports(common, machine, nil, fluids)
	if fluid_machine_has_arrow(machine.kind) {
		draw_direction_arrow(placement.origin, placement.size, placement.rotation, BELT_GHOST_ARROW_COLOR)
	}
}
