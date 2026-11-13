package game

import rl "shared:raylib"

// Placeholder fluid models: a pipe is a small core cube with a stub
// towards every neighbour it connects to and a band in the colour of the
// fluid its netlist carries, since a pipe holds nothing (0356, the block
// world's draw_pipes). Fluid
// machines are coloured boxes, drawn by draw_entities with the other
// machines on both worlds (0362); their single face ports are squares on
// the footprint faces, in the colour of the fluid held or taken (every
// face ports, the tank's, get none), drawn with the other machines' ports
// by draw_ports_and_arrows (render_entities.odin). Offshore pumps, pumps
// and tar pit pumps show their direction with an arrow there. A flare
// stack's top glows while it burns gas, a combustion generator's top is
// brighter while it generates. A fluid machine with a model
// (render_models.odin) is drawn with it, animated while its bottleneck
// marker would be green; the ports and arrows stay. Pipes keep their
// stubs: a model per connection shape is left for later.

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
	.Water_Pump    = {70, 120, 160, 255},
	.Junction_Box  = {},
	.Power_Switch  = {},
	.Lamp          = {},
	.Crafting_Machine = {},
	.Lab           = {},
	.Schematic_Crate = {},
	.Core_Sample_Drill = {},
	.Launch_Pad    = {},
	.Foundation    = {},
	.Belt_Pole     = {},
	.Pod           = {},
	.Crafting_Station = {},
	.Tree          = {},
	.Hatch         = {},
	.Locker        = {},
	.Crafting_Bench = {},
	.Charge_Controller = {},
	.Vessel_Part   = {},
	.Vessel_Control_Unit = {},
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

// Steady while the pipe's netlist carries a fluid, not only on the ticks
// litres pass, so a slow line does not blink.
pipe_shows_band :: proc(pipe: Pipe) -> bool {
	return pipe.buffer.fluid != NO_FLUID
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
	if !pipe_shows_band(pipe) {
		return
	}
	band := f32(PIPE_CORE_SIZE + 2 * PIPE_BAND_MARGIN)
	rl.DrawCubeV(centre, {band, PIPE_CORE_SIZE, band}, fluid_color(fluids, pipe.buffer.fluid))
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

// The body: the model, or the boxes under the frame's matrix
// (draw_entity_cells).
draw_fluid_machine :: proc(fluid_machine: Fluid_Machine, machines: Machine_Registry, models: Model_Renderer, frame: Model_Frame) {
	machine := machines.machines[fluid_machine.machine]
	color := fluid_machine_colors[machine.kind]
	top_color := color
	if machine.kind == .Flare_Stack && fluid_machine.state == .Flaring {
		top_color = FLARE_BURNING_TOP_COLOR
	}
	if (machine.kind == .Combustion_Generator || machine.kind == .Hydro_Turbine) && fluid_machine.state == .Generating {
		top_color = GENERATING_TOP_COLOR
	}
	draw_entity_cells(fluid_machine.common, machines, models, frame, fluid_machine_model_working(fluid_machine), color, top_color)
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

// Between BeginMode3D and EndMode3D, after the chunks: the block world's
// cell pipes (a field world's pipes are runs, draw_belt_runs).
draw_pipes :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry) {
	for pipe in world.entities.pipes.entries {
		if pipe.alive {
			draw_pipe(world, pipe, machines, fluids)
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
