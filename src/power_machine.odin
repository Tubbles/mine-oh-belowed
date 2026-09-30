package game

import "core:fmt"
import "core:slice"

// The entities of the power grid (doc/fluids.md, Power): poles (small,
// big, substations) and power switches in one pool (the machine kind
// tells them apart), lamps, and the power side of the machines that
// already exist: electric inserters, electric drills, pumps, steam
// engines, combustion generators and hydro turbines. Networks and the
// energy balance are in power_network.odin.
//
// A consumer's Power_State holds what its network gave it this tick. A
// brownout slows machines through power credit: every tick adds the
// satisfaction in per mille, and a machine takes one tick of work for
// every POWER_FULL collected, so at 50 percent it works every other tick.

// Satisfaction and power credit are in per mille.
POWER_FULL :: 1000
// A lamp shines only while its network gives more than half.
LAMP_ON_ABOVE :: 500

Power_State :: struct {
	satisfaction: u32,
	credit:       u32,
}

// on only matters for a power switch; a small pole is always on.
Pole :: struct {
	using common: Entity_Common,
	on:           bool,
}

Lamp :: struct {
	using common: Entity_Common,
	power:        Power_State,
	lit:          bool,
}

make_pole :: proc(common: Entity_Common) -> Pole {
	return Pole{common = common, on = true}
}

make_lamp :: proc(common: Entity_Common) -> Lamp {
	return Lamp{common = common}
}

// Poles: a square footprint across, a supply volume at least as wide
// whose width and depth differ from the footprint's by an even count so
// it centres on the pole, and a wire reach. Power switches: 1 by 1 by 1
// with a reach and no volume. Lamps: 1 by 1 by 1, electric power and a
// light level.
validate_power_machine_definition :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	footprint, volume := definition.footprint, definition.supply_volume
	#partial switch kind {
	case .Pole:
		if footprint.width != footprint.depth || definition.wire_reach <= 0 {
			return fmt.tprintf("pole %q must be square across with a positive wire_reach", definition.id)
		}
		if volume.width < footprint.width || volume.depth < footprint.depth || volume.height < 1 || (volume.width - footprint.width) % 2 != 0 || (volume.depth - footprint.depth) % 2 != 0 {
			return fmt.tprintf("pole %q needs a supply_volume centred on its footprint (as wide or wider, the difference even) and a positive height", definition.id)
		}
	case .Power_Switch:
		if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 || definition.wire_reach <= 0 {
			return fmt.tprintf("power switch %q must be 1 by 1 by 1 with a positive wire_reach", definition.id)
		}
	case .Lamp:
		if footprint.width != 1 || footprint.depth != 1 || footprint.height != 1 || definition.electric_power_kilowatts <= 0 {
			return fmt.tprintf("lamp %q must be 1 by 1 by 1 with a positive electric_power_kilowatts", definition.id)
		}
		if definition.light_level < 1 || definition.light_level > MAXIMUM_LIGHT {
			return fmt.tprintf("lamp %q needs a light_level from 1 to %d", definition.id, MAXIMUM_LIGHT)
		}
		if problem := validate_light_color(definition.light_color, definition.light_level); problem != "" {
			return fmt.tprintf("lamp %q %s", definition.id, problem)
		}
	}
	return ""
}

machine_is_electric_consumer :: proc(machine: Machine) -> bool {
	return machine.electric_power_watts > 0
}

machine_is_generator :: proc(machine: Machine) -> bool {
	return machine.electric_output_watts > 0
}

// Placing or removing it changes the networks or who belongs to them.
machine_touches_power :: proc(machine: Machine) -> bool {
	return machine.kind == .Pole || machine.kind == .Power_Switch || machine_is_electric_consumer(machine) || machine_is_generator(machine)
}

// Integer division like fuel: 13 kW at 60 ticks per second is 216 J.
electric_joules_per_tick :: proc(watts: u32, tick_rate: int) -> u64 {
	return u64(watts) / u64(max(tick_rate, 1))
}

power_is_on :: proc(power: Power_State) -> bool {
	return power.satisfaction > 0
}

// Adds the tick's satisfaction to the credit; true when a whole tick of
// work is paid for.
take_power_step :: proc(power: ^Power_State) -> bool {
	power.credit += power.satisfaction
	if power.credit < POWER_FULL {
		return false
	}
	power.credit -= POWER_FULL
	return true
}

// Steam engines.

steam_joules_per_litre :: proc(machine: Machine) -> u64 {
	return u64(machine.electric_output_watts) / u64(max(machine.fluid_litres_per_second, 1))
}

steam_engine_litres :: proc(engine: Fluid_Machine, machine: Machine) -> u64 {
	total: u64
	for port, index in fluid_ports_of(machine) {
		if engine.buffers[index].level > 0 && engine.buffers[index].fluid == port.filter {
			total += u64(engine.buffers[index].level)
		}
	}
	return total
}

// Up to its output over the tick, and no more than the steam it holds
// (drawn already or still in its buffers) is worth.
steam_engine_available_joules :: proc(engine: Fluid_Machine, machine: Machine, tick_rate: int) -> u64 {
	stored := u64(engine.fuel_joules) + steam_engine_litres(engine, machine) * steam_joules_per_litre(machine)
	return min(electric_joules_per_tick(machine.electric_output_watts, tick_rate), stored)
}

// Takes whole litres from the input buffers in port order.
draw_steam_litres :: proc(engine: ^Fluid_Machine, machine: Machine, litres: u64) {
	remaining := litres
	for port, index in fluid_ports_of(machine) {
		buffer := &engine.buffers[index]
		if remaining == 0 || buffer.level <= 0 || buffer.fluid != port.filter {
			continue
		}
		taken := min(u64(buffer.level), remaining)
		buffer.level -= i32(taken)
		remaining -= taken
	}
}

// Steam turns into joules a whole litre at a time, only as the delivered
// energy needs it; the rest waits in fuel_joules for the next tick.
deliver_steam_engine_energy :: proc(engine: ^Fluid_Machine, machine: Machine, joules: u64) {
	per_litre := steam_joules_per_litre(machine)
	if u64(engine.fuel_joules) < joules && per_litre > 0 {
		litres := (joules - u64(engine.fuel_joules) + per_litre - 1) / per_litre
		draw_steam_litres(engine, machine, litres)
		engine.fuel_joules += u32(litres * per_litre)
	}
	engine.fuel_joules -= u32(min(joules, u64(engine.fuel_joules)))
	engine.generated_joules = u32(joules)
}

steam_engine_state :: proc(delivered, available: u64, network_demand: u64) -> Fluid_Machine_State {
	switch {
	case delivered > 0:
		return .Producing
	case available == 0 && network_demand > 0:
		return .No_Steam
	}
	return .Idle
}

// Combustion generators: like a steam engine, but the energy comes from
// the gas in its one port (whole litres at the gas's
// fuel_kilojoules_per_litre) and, with no burnable gas left, from fuel
// items in its slot, lit whole like a furnace's at the machine's
// fuel_efficiency_percent. What was drawn and not yet delivered waits in
// fuel_joules. The fuel generator (0140) is one without a port.

COMBUSTION_FUEL_SLOT :: 0

// Zero for an empty port or a gas that does not burn.
combustion_gas_joules_per_litre :: proc(generator: Fluid_Machine, fluids: Fluid_Registry) -> u64 {
	buffer := generator.buffers[0]
	if buffer.level <= 0 || int(buffer.fluid) >= len(fluids.fluids) {
		return 0
	}
	return u64(fluids.fluids[buffer.fluid].fuel_kilojoules_per_litre) * 1000
}

combustion_gas_joules :: proc(generator: Fluid_Machine, fluids: Fluid_Registry) -> u64 {
	return u64(max(generator.buffers[0].level, 0)) * combustion_gas_joules_per_litre(generator, fluids)
}

combustion_slot_joules :: proc(generator: Fluid_Machine, machine: Machine, items: Item_Registry) -> u64 {
	fuel := generator.slots[COMBUSTION_FUEL_SLOT]
	if stack_is_empty(fuel) || !item_is_fuel(items, fuel.item) {
		return 0
	}
	return u64(fuel.count) * u64(fuel_joules_at_efficiency(items.items[fuel.item].fuel_kilojoules, machine.fuel_efficiency_percent))
}

// What its gas, its fuel items and what it drew already are worth.
combustion_generator_stored_joules :: proc(generator: Fluid_Machine, machine: Machine, fluids: Fluid_Registry, items: Item_Registry) -> u64 {
	return u64(generator.fuel_joules) + combustion_gas_joules(generator, fluids) + combustion_slot_joules(generator, machine, items)
}

// Up to its output over the tick, and no more than it has stored.
combustion_generator_available_joules :: proc(generator: Fluid_Machine, machine: Machine, fluids: Fluid_Registry, items: Item_Registry, tick_rate: int) -> u64 {
	return min(electric_joules_per_tick(machine.electric_output_watts, tick_rate), combustion_generator_stored_joules(generator, machine, fluids, items))
}

// Whole litres, as few as cover what fuel_joules lacks.
draw_combustion_gas :: proc(generator: ^Fluid_Machine, fluids: Fluid_Registry, joules: u64) {
	per_litre := combustion_gas_joules_per_litre(generator^, fluids)
	if u64(generator.fuel_joules) >= joules || per_litre == 0 {
		return
	}
	buffer := &generator.buffers[0]
	litres := min((joules - u64(generator.fuel_joules) + per_litre - 1) / per_litre, u64(buffer.level))
	buffer.level -= i32(litres)
	generator.fuel_joules += u32(litres * per_litre)
}

// Gas first, then fuel items one at a time, only as the delivered energy
// needs them.
deliver_combustion_generator_energy :: proc(generator: ^Fluid_Machine, machine: Machine, fluids: Fluid_Registry, items: Item_Registry, joules: u64) {
	draw_combustion_gas(generator, fluids, joules)
	needed := u32(joules)
	fuel := &generator.slots[COMBUSTION_FUEL_SLOT]
	for generator.fuel_joules < needed && refuel_from_slot(&generator.fuel_joules, &generator.fuel_item_joules, fuel, items, needed, machine.fuel_efficiency_percent) {
	}
	generator.fuel_joules -= min(needed, generator.fuel_joules)
	generator.generated_joules = needed
}

combustion_generator_state :: proc(delivered, available: u64, network_demand: u64) -> Fluid_Machine_State {
	switch {
	case delivered > 0:
		return .Generating
	case available == 0 && network_demand > 0:
		return .No_Fuel
	}
	return .Idle
}

// Combustion generators turn 1 to 100 percent of a fuel item's energy
// into electricity (0140); no other kind burns items for power.
validate_fuel_efficiency :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	if kind == .Combustion_Generator && (definition.fuel_efficiency_percent < 1 || definition.fuel_efficiency_percent > 100) {
		return fmt.tprintf("combustion generator %q needs a fuel_efficiency_percent from 1 to 100", definition.id)
	}
	if kind != .Combustion_Generator && definition.fuel_efficiency_percent != 0 {
		return fmt.tprintf("machine %q is not a combustion generator and cannot have fuel_efficiency_percent", definition.id)
	}
	return ""
}

// Dispatch orders run from 0 (serves first) to this.
MAXIMUM_DISPATCH_ORDER :: 9

machine_kind_is_generator :: proc(kind: Machine_Kind) -> bool {
	return kind == .Steam_Engine || kind == .Combustion_Generator || kind == .Hydro_Turbine
}

// Every generator kind names its dispatch_order (0140); no other kind
// has one.
validate_dispatch_order :: proc(definition: Machine_Definition, kind: Machine_Kind) -> string {
	order, found := definition.dispatch_order.?
	if machine_kind_is_generator(kind) && (!found || order < 0 || order > MAXIMUM_DISPATCH_ORDER) {
		return fmt.tprintf("generator %q needs a dispatch_order from 0 to %d", definition.id, MAXIMUM_DISPATCH_ORDER)
	}
	if !machine_kind_is_generator(kind) && found {
		return fmt.tprintf("machine %q is not a generator and cannot have dispatch_order", definition.id)
	}
	return ""
}

// Hydro turbines: no fuel and no ports. The power comes from the flowing
// water standing in the turbine's own cells, read from the blocks every
// tick, so a dam upstream or a drained channel changes it at once. Source
// water is still and counts nothing.

validate_hydro_turbine_definition :: proc(definition: Machine_Definition) -> string {
	if definition.electric_output_kilowatts <= 0 || definition.hydro_kilowatts_per_water_level <= 0 {
		return fmt.tprintf("hydro turbine %q needs a positive electric_output_kilowatts and hydro_kilowatts_per_water_level", definition.id)
	}
	if definition.hydro_minimum_water_level < 1 || definition.hydro_minimum_water_level > WATER_FALLING_LEVEL {
		return fmt.tprintf("hydro turbine %q needs a hydro_minimum_water_level from 1 to %d", definition.id, WATER_FALLING_LEVEL)
	}
	if definition.fuel_slots != 0 || definition.slots != 0 {
		return fmt.tprintf("hydro turbine %q cannot have slots", definition.id)
	}
	return ""
}

// The level of flowing water in the cell, 0 for a source or no water.
flowing_water_level :: proc(world: ^World, registry: Block_Registry, cell: World_Coordinate) -> int {
	level := world_water_level(world, registry, cell)
	return level == WATER_SOURCE_LEVEL ? 0 : level
}

flowing_water_level_sum :: proc(world: ^World, registry: Block_Registry, cells: []World_Coordinate) -> int {
	sum := 0
	for cell in cells {
		sum += flowing_water_level(world, registry, cell)
	}
	return sum
}

// Placement: one cell holds flowing water of the machine's minimum level.
cells_hold_flowing_water :: proc(world: ^World, registry: Block_Registry, cells: []World_Coordinate, minimum_level: int) -> bool {
	for cell in cells {
		if flowing_water_level(world, registry, cell) >= minimum_level {
			return true
		}
	}
	return false
}

hydro_turbine_watts :: proc(machine: Machine, level_sum: int) -> u32 {
	return u32(min(u64(level_sum) * u64(machine.hydro_watts_per_water_level), u64(machine.electric_output_watts)))
}

hydro_turbine_available_joules :: proc(world: ^World, content: Simulation_Content, turbine: Fluid_Machine, tick_rate: int) -> u64 {
	machine := content.machines.machines[turbine.machine]
	level_sum := flowing_water_level_sum(world, content.blocks, common_cells(turbine.common, content.machines))
	return electric_joules_per_tick(hydro_turbine_watts(machine, level_sum), tick_rate)
}

hydro_turbine_state :: proc(delivered, available: u64) -> Fluid_Machine_State {
	switch {
	case delivered > 0:
		return .Generating
	case available == 0:
		return .No_Water
	}
	return .Idle
}

// Generators of every kind.

generator_available_joules :: proc(world: ^World, generator: Fluid_Machine, machine: Machine, content: Simulation_Content, tick_rate: int) -> u64 {
	#partial switch machine.kind {
	case .Combustion_Generator:
		return combustion_generator_available_joules(generator, machine, content.fluids, content.items, tick_rate)
	case .Hydro_Turbine:
		return hydro_turbine_available_joules(world, content, generator, tick_rate)
	}
	return steam_engine_available_joules(generator, machine, tick_rate)
}

deliver_generator_energy :: proc(generator: ^Fluid_Machine, machine: Machine, content: Simulation_Content, joules: u64) {
	#partial switch machine.kind {
	case .Combustion_Generator:
		deliver_combustion_generator_energy(generator, machine, content.fluids, content.items, joules)
	case .Hydro_Turbine:
		generator.generated_joules = u32(joules)
	case:
		deliver_steam_engine_energy(generator, machine, joules)
	}
}

generator_state :: proc(kind: Machine_Kind, delivered, available: u64, network_demand: u64) -> Fluid_Machine_State {
	#partial switch kind {
	case .Combustion_Generator:
		return combustion_generator_state(delivered, available, network_demand)
	case .Hydro_Turbine:
		return hydro_turbine_state(delivered, available)
	}
	return steam_engine_state(delivered, available, network_demand)
}

// Lamps: an entity light source (World.entity_lights) in the lamp's cell
// while lit, through the block light queues of world_light.odin.

tick_lamps :: proc(world: ^World, machines: Machine_Registry) {
	for &lamp in world.entities.lamps.entries {
		if lamp.alive {
			lamp.lit = lamp.power.satisfaction > LAMP_ON_ABOVE
		}
	}
	sync_entity_lights(world, lit_lamp_lights(&world.entities, machines))
}

// Cell and light colour of every lit lamp, in the temp allocator.
lit_lamp_lights :: proc(entities: ^Entities, machines: Machine_Registry) -> map[World_Coordinate]Light_Color {
	lights := make(map[World_Coordinate]Light_Color, context.temp_allocator)
	for lamp in entities.lamps.entries {
		if lamp.alive && lamp.lit {
			lights[lamp.origin] = machines.machines[lamp.machine].light_color
		}
	}
	return lights
}

// Makes World.entity_lights match wanted: sources that went out or were
// picked up go through the removal queue, new ones through the addition
// queue. Cells are visited in coordinate order.
sync_entity_lights :: proc(world: ^World, wanted: map[World_Coordinate]Light_Color) {
	changed := make([dynamic]World_Coordinate, context.temp_allocator)
	for cell, color in world.entity_lights {
		if wanted[cell] != color {
			append(&changed, cell)
		}
	}
	for cell in wanted {
		if cell not_in world.entity_lights {
			append(&changed, cell)
		}
	}
	slice.sort_by(changed[:], coordinate_before)
	for cell in changed {
		set_entity_light(world, cell, wanted[cell])
	}
}

// Power switches.

// Interact on a power switch turns it (the panel has a button too).
toggle_power_switch :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	pole := pool_get(&entities.poles, handle)
	if pole == nil || machines.machines[pole.machine].kind != .Power_Switch {
		return false
	}
	pole.on = !pole.on
	rebuild_electric_networks(entities, machines)
	return true
}

entity_is_power_switch :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	pole := pool_get(&entities.poles, handle)
	return pole != nil && machines.machines[pole.machine].kind == .Power_Switch
}
