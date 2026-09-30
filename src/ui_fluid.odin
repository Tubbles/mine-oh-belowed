package game

import "core:fmt"

// Panels and HUD text for pipes and fluid machines: per buffer the fluid,
// its level against the capacity and the flow in and out during the last
// tick (or that it stands above its network's head line), a note on
// ports closed to avoid mixing, a pump's head, the fuel slot of the
// boiler (with its burn bar) and of the combustion generator with its Fill
// button, the machine state, a generator's output, and a combustion
// generator's efficiency and burn time left.

FLUID_AREA_WIDTH :: 480
// A level line and a flow line per buffer.
FLUID_ROWS_PER_BUFFER :: 2

// The pipe's buffer, or one per port.
fluid_buffer_count :: proc(machine: Machine) -> int {
	return machine.kind == .Pipe ? 1 : machine.fluid_port_count
}

// Whether the panel shows a state line.
fluid_machine_shows_state :: proc(kind: Machine_Kind) -> bool {
	return kind == .Offshore_Pump || kind == .Boiler || kind == .Pump || kind == .Steam_Engine || kind == .Tar_Pit_Pump || kind == .Flare_Stack || kind == .Combustion_Generator || kind == .Hydro_Turbine
}

fluid_machine_has_fuel_slot :: proc(kind: Machine_Kind) -> bool {
	return kind == .Boiler || kind == .Combustion_Generator
}

// Offshore, tar pit and electric pumps show their head.
fluid_machine_head_rows :: proc(kind: Machine_Kind) -> int {
	return machine_kind_is_pump(kind) ? 1 : 0
}

// Pumps (offshore, tar pit, electric), flare stacks and generators show
// their power network; generators their output too, and combustion
// generators their efficiency and burn time.
fluid_machine_power_rows :: proc(kind: Machine_Kind) -> int {
	#partial switch kind {
	case .Offshore_Pump, .Pump, .Tar_Pit_Pump, .Flare_Stack:
		return 1
	case .Steam_Engine, .Hydro_Turbine:
		return 2
	case .Combustion_Generator:
		return 3
	}
	return 0
}

// "Efficiency 25 %  Burn time 0:40": how long what it holds lasts at
// full output (0140).
combustion_fuel_line :: proc(machine: Machine, stored_joules: u64, tick_rate: int) -> string {
	ticks := stored_joules / max(electric_joules_per_tick(machine.electric_output_watts, tick_rate), 1)
	return fmt.tprintf("%s %d %%  %s %s", text("fuel_efficiency"), machine.fuel_efficiency_percent, text("fuel_burn_time"), format_game_time(ticks, tick_rate))
}

fluid_area_size :: proc(machine: Machine) -> [2]f32 {
	rows := 1 + FLUID_ROWS_PER_BUFFER * fluid_buffer_count(machine) + fluid_machine_head_rows(machine.kind) + fluid_machine_power_rows(machine.kind)
	if fluid_machine_shows_state(machine.kind) {
		rows += 1
	}
	height := f32(rows) * UI_ROW_HEIGHT
	if fluid_machine_has_fuel_slot(machine.kind) {
		height += UI_SLOT_SIZE + UI_GAP
	}
	return {FLUID_AREA_WIDTH, height}
}

// "Water: 150 L of 200 L", naming the fluid held, or else the one the
// port takes, or none.
fluid_level_line :: proc(fluids: Fluid_Registry, buffer: Fluid_Buffer, filter: Fluid_Id, capacity: i32, closed: bool) -> string {
	fluid := buffer.level > 0 ? buffer.fluid : filter
	line := fmt.tprintf("%s: %s %s %s", fluid_name(fluids, fluid), format_volume(f32(buffer.level)), text("fluid_of"), format_volume(f32(capacity)))
	if closed {
		return fmt.tprintf("%s  %s", line, text("fluid_mixing_refused"))
	}
	return line
}

fluid_flow_line :: proc(buffer: Fluid_Buffer, tick_rate: int) -> string {
	return fmt.tprintf("%s %s  %s %s", text("fluid_flow_in"), format_litres_per_minute(buffer.flow_in, tick_rate), text("fluid_flow_out"), format_litres_per_minute(buffer.flow_out, tick_rate))
}

// The flow, or why no pump lifts anything this high.
fluid_second_line :: proc(buffer: Fluid_Buffer, above_head_line: bool, tick_rate: int) -> string {
	return above_head_line ? text("fluid_above_pump_head") : fluid_flow_line(buffer, tick_rate)
}

// "Head: 6 m".
pump_head_line :: proc(machine: Machine) -> string {
	return fmt.tprintf("%s: %d m", text("fluid_pump_head"), machine.head_metres)
}

fluid_buffer_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, fluids: Fluid_Registry, buffer: Fluid_Buffer, filter: Fluid_Id, capacity: i32, closed: bool, tick_rate: int, above_head_line := false) {
	detail_line(state, content, fluid_level_line(fluids, buffer, filter, capacity, closed))
	detail_line(state, content, fluid_second_line(buffer, above_head_line, tick_rate), UI_DIM_TEXT_COLOR)
}

pipe_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, pipe: Pipe, screen_context: Screen_Context) {
	content := area
	capacity := screen_context.machines.machines[pipe.machine].buffer_litres
	above := segment_is_above_head_line(&screen_context.world.entities, screen_context.fluids, pipe.handle, -1)
	fluid_buffer_rows(state, &content, screen_context.fluids, pipe.buffer, NO_FLUID, capacity, false, screen_context.tick_rate, above)
}

// The fuel slot first (with the boiler's burn bar) and its Fill button,
// then a level and a flow line per port, then the state and a generator's
// output.
fluid_machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, fluid_machine: Fluid_Machine, screen_context: Screen_Context) -> Machine_Slot_Result {
	result := Machine_Slot_Result {
		grid = {activated = -1, focused = -1},
	}
	machine := screen_context.machines.machines[fluid_machine.machine]
	content := area
	if fluid_machine_has_fuel_slot(machine.kind) {
		first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
		slots := fluid_machine.slots
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, BOILER_FUEL_SLOT, slots[:], screen_context.items, &result.grid)
		if machine.kind == .Boiler {
			machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, boiler_burn_fraction(fluid_machine))
		}
		result.transfer = transfer_button_rows(state, &content, machine)
	}
	for port, index in fluid_ports_of(machine) {
		buffer, closed := fluid_machine.buffers[index], fluid_machine.closed[index]
		above := segment_is_above_head_line(&screen_context.world.entities, screen_context.fluids, fluid_machine.handle, index)
		fluid_buffer_rows(state, &content, screen_context.fluids, buffer, port.filter, port.capacity, closed, screen_context.tick_rate, above)
	}
	if fluid_machine_head_rows(machine.kind) > 0 {
		detail_line(state, &content, pump_head_line(machine), UI_DIM_TEXT_COLOR)
	}
	if fluid_machine_shows_state(machine.kind) {
		detail_line(state, &content, text(fluid_machine_state_keys[fluid_machine.state]), UI_DIM_TEXT_COLOR)
	}
	if machine_is_generator(machine) {
		detail_line(state, &content, generator_output_line(fluid_machine, screen_context.tick_rate))
	}
	if machine.kind == .Combustion_Generator {
		stored := combustion_generator_stored_joules(fluid_machine, machine, screen_context.fluids, screen_context.items)
		detail_line(state, &content, combustion_fuel_line(machine, stored, screen_context.tick_rate), UI_DIM_TEXT_COLOR)
	}
	if fluid_machine_power_rows(machine.kind) > 0 {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, fluid_machine.handle)
		detail_line(state, &content, power_line, UI_DIM_TEXT_COLOR)
	}
	return result
}

// The HUD line: the machine's state, or a pipe's fluid and level.
fluid_status_text :: proc(world: ^World, machines: Machine_Registry, fluids: Fluid_Registry, handle: Entity_Handle, name: string) -> string {
	if pipe := pool_get(&world.entities.pipes, handle); pipe != nil {
		return fmt.tprintf("%s  %s %s", name, fluid_name(fluids, pipe.buffer.level > 0 ? pipe.buffer.fluid : NO_FLUID), format_volume(f32(pipe.buffer.level)))
	}
	fluid_machine := pool_get(&world.entities.fluid_machines, handle)
	if fluid_machine == nil || !fluid_machine_shows_state(machines.machines[fluid_machine.machine].kind) {
		return name
	}
	return fmt.tprintf("%s  %s", name, text(fluid_machine_state_keys[fluid_machine.state]))
}
