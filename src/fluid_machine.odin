package game

// Pipes and the fluid machines of doc/fluids.md: offshore pump, boiler,
// steam engine, storage tank and pump. They share one pool; the machine's
// kind decides what the tick does. Each fluid port has its own litre
// buffer, which is a segment of the fluid network on its side
// (fluid_network.odin). Picking a machine up loses the fluid in it.

FLUID_MACHINE_SLOT_COUNT :: 1
BOILER_FUEL_SLOT :: 0

// Litres of one fluid. flow_in and flow_out are what the network moved
// in and out during the last tick, for the panels.
Fluid_Buffer :: struct {
	fluid:    Fluid_Id,
	level:    i32,
	flow_in:  i32,
	flow_out: i32,
}

EMPTY_FLUID_BUFFER :: Fluid_Buffer {
	fluid = NO_FLUID,
}

Pipe :: struct {
	using common: Entity_Common,
	buffer:       Fluid_Buffer,
}

Fluid_Machine_State :: enum u8 {
	Idle,
	No_Water,
	No_Fuel,
	Output_Full,
	Producing,
	Unpowered,
	Pumping,
	No_Steam,
}

@(rodata)
fluid_machine_state_keys := [Fluid_Machine_State]string {
	.Idle        = "machine_state_idle",
	.No_Water    = "machine_state_no_water",
	.No_Fuel     = "machine_state_no_fuel",
	.Output_Full = "machine_state_output_full",
	.Producing   = "machine_state_producing",
	.Unpowered   = "machine_state_unpowered",
	.Pumping     = "machine_state_pumping",
	.No_Steam    = "machine_state_no_steam",
}

// buffers and closed are per fluid port. closed marks a port the network
// shut because it would mix two fluids. power is a pump's share of its
// network (power_machine.odin). A steam engine keeps the energy of steam
// already drawn from its buffers in fuel_joules, and generated_joules is
// what it gave its network in the last tick.
Fluid_Machine :: struct {
	using common:     Entity_Common,
	buffers:          [MAXIMUM_FLUID_PORTS]Fluid_Buffer,
	closed:           [MAXIMUM_FLUID_PORTS]bool,
	slot_count:       int,
	slots:            [FLUID_MACHINE_SLOT_COUNT]Item_Stack,
	fuel_joules:      u32,
	fuel_item_joules: u32,
	power:            Power_State,
	generated_joules: u32,
	state:            Fluid_Machine_State,
}

make_pipe :: proc(common: Entity_Common) -> Pipe {
	return Pipe{common = common, buffer = EMPTY_FLUID_BUFFER}
}

make_fluid_machine :: proc(common: Entity_Common, machine: Machine) -> Fluid_Machine {
	result := Fluid_Machine {
		common     = common,
		slot_count = min(machine.slot_count, FLUID_MACHINE_SLOT_COUNT),
		slots      = {EMPTY_STACK},
	}
	for &buffer in result.buffers {
		buffer = EMPTY_FLUID_BUFFER
	}
	if machine.kind == .Pump {
		result.state = .Unpowered
	}
	return result
}

// Rates are whole litres per tick, at least one.
litres_per_tick :: proc(litres_per_second: u32, tick_rate: int) -> i32 {
	return i32(max(litres_per_second / u32(tick_rate), 1))
}

buffer_room :: proc(buffer: Fluid_Buffer, capacity: i32) -> i32 {
	return capacity - buffer.level
}

// Whether a buffer can take fluid: empty, or holding the same fluid.
buffer_takes_fluid :: proc(buffer: Fluid_Buffer, fluid: Fluid_Id) -> bool {
	return buffer.level == 0 || buffer.fluid == fluid
}

add_to_buffer :: proc(buffer: ^Fluid_Buffer, fluid: Fluid_Id, litres: i32) {
	buffer.fluid = fluid
	buffer.level += litres
}

// Drawing water: 1200 litres per second into its port while there is room.
advance_offshore_pump :: proc(pump: ^Fluid_Machine, machine: Machine, tick_rate: int) {
	port := machine.fluid_ports[0]
	buffer := &pump.buffers[0]
	amount := min(litres_per_tick(machine.fluid_litres_per_second, tick_rate), buffer_room(buffer^, port.capacity))
	if amount <= 0 || !buffer_takes_fluid(buffer^, port.filter) {
		pump.state = .Output_Full
		return
	}
	add_to_buffer(buffer, port.filter, amount)
	pump.state = .Producing
}

port_index_of_direction :: proc(machine: Machine, direction: Fluid_Port_Direction) -> int {
	for port, index in fluid_ports_of(machine) {
		if port.direction == direction {
			return index
		}
	}
	return -1
}

boiler_has_fuel :: proc(boiler: Fluid_Machine, needed: u32, items: Item_Registry) -> bool {
	fuel := boiler.slots[BOILER_FUEL_SLOT]
	return boiler.fuel_joules >= needed || !stack_is_empty(fuel) && item_is_fuel(items, fuel.item)
}

// Turns water from the input port into as much steam in the output port,
// burning fuel only on the ticks it produces. The fluids are the port
// filters.
advance_boiler :: proc(boiler: ^Fluid_Machine, machine: Machine, items: Item_Registry, tick_rate: int) {
	input_index := port_index_of_direction(machine, .Input)
	output_index := port_index_of_direction(machine, .Output)
	input, output := &boiler.buffers[input_index], &boiler.buffers[output_index]
	steam := machine.fluid_ports[output_index].filter
	litres := litres_per_tick(machine.fluid_litres_per_second, tick_rate)
	per_tick := fuel_joules_per_tick(machine, tick_rate)
	has_water := input.level >= litres
	switch {
	case !has_water && !boiler_has_fuel(boiler^, per_tick, items):
		boiler.state = .Idle
	case !has_water:
		boiler.state = .No_Water
	case buffer_room(output^, machine.fluid_ports[output_index].capacity) < litres || !buffer_takes_fluid(output^, steam):
		boiler.state = .Output_Full
	case !refuel_from_slot(&boiler.fuel_joules, &boiler.fuel_item_joules, &boiler.slots[BOILER_FUEL_SLOT], items, per_tick):
		boiler.state = .No_Fuel
	case:
		boiler.fuel_joules -= per_tick
		input.level -= litres
		add_to_buffer(output, steam, litres)
		boiler.state = .Producing
	}
}

// Moves its rate times its network's satisfaction from the input port to
// the output port whatever the heights, and only with power. Its output
// network ignores gravity while it runs (fluid_network.odin).
advance_pump :: proc(pump: ^Fluid_Machine, machine: Machine, tick_rate: int) {
	if !power_is_on(pump.power) {
		pump.state = .Unpowered
		return
	}
	input := &pump.buffers[port_index_of_direction(machine, .Input)]
	output_index := port_index_of_direction(machine, .Output)
	output := &pump.buffers[output_index]
	rate := litres_per_tick(machine.fluid_litres_per_second, tick_rate) * i32(pump.power.satisfaction) / POWER_FULL
	amount := min(rate, input.level, buffer_room(output^, machine.fluid_ports[output_index].capacity))
	if amount <= 0 || !buffer_takes_fluid(output^, input.fluid) {
		pump.state = .Idle
		return
	}
	input.level -= amount
	add_to_buffer(output, input.fluid, amount)
	pump.state = .Pumping
}

advance_fluid_machine :: proc(fluid_machine: ^Fluid_Machine, machine: Machine, items: Item_Registry, tick_rate: int) {
	#partial switch machine.kind {
	case .Offshore_Pump:
		advance_offshore_pump(fluid_machine, machine, tick_rate)
	case .Boiler:
		advance_boiler(fluid_machine, machine, items, tick_rate)
	case .Pump:
		advance_pump(fluid_machine, machine, tick_rate)
	}
}

// Machines first, so what they make this tick flows on in the same tick.
tick_fluids :: proc(entities: ^Entities, content: Simulation_Content, tick_rate: int) {
	for &fluid_machine in entities.fluid_machines.entries {
		if fluid_machine.alive {
			advance_fluid_machine(&fluid_machine, content.machines.machines[fluid_machine.machine], content.items, tick_rate)
		}
	}
	tick_fluid_networks(entities, content.fluids, pipe_flow_per_tick(content.machines, tick_rate))
}

// The per connection flow limit comes from the pipe prototype.
pipe_flow_per_tick :: proc(machines: Machine_Registry, tick_rate: int) -> i32 {
	pipe := find_machine_of_kind(machines, .Pipe)
	if pipe == NO_MACHINE {
		return 0
	}
	return litres_per_tick(machines.machines[pipe].flow_litres_per_second, tick_rate)
}

boiler_burn_fraction :: proc(boiler: Fluid_Machine) -> f32 {
	if boiler.fuel_item_joules == 0 {
		return 0
	}
	return f32(boiler.fuel_joules) / f32(boiler.fuel_item_joules)
}

// Free, clear of the players, and on a solid block or on another pipe, so
// pipes climb in columns like belt lifts.
pipe_cell_is_placeable :: proc(world: ^World, registry: Block_Registry, players: []Player, cell: World_Coordinate) -> bool {
	cells := [1]World_Coordinate{cell}
	if !cell_is_free(world, cell) || footprint_hits_player(players, cells[:]) {
		return false
	}
	below := cell - {0, 1, 0}
	return block_is_solid(registry, world_get_block(world, below)) || entity_at(&world.entities, below).kind == .Pipe
}

// An offshore pump stands on the shore with the cell in front of its
// intake end, at its own height or one below, a water source block. Its
// intake is the end its output port is not on: rotation 0 faces +x.
offshore_pump_intake_cell :: proc(origin: World_Coordinate, machine: Machine, rotation: u8) -> World_Coordinate {
	offset := rotate_footprint_cell({machine.footprint.x, 0}, machine.footprint.x, machine.footprint.z, rotation)
	return origin + {offset.x, 0, offset.y}
}

offshore_pump_has_water :: proc(world: ^World, registry: Block_Registry, origin: World_Coordinate, machine: Machine, rotation: u8) -> bool {
	intake := offshore_pump_intake_cell(origin, machine, rotation)
	for below in i32(0) ..= 1 {
		if world_water_level(world, registry, intake - {0, below, 0}) == WATER_SOURCE_LEVEL {
			return true
		}
	}
	return false
}
