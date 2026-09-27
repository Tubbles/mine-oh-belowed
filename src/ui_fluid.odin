package game

import "core:fmt"

// Panels and HUD text for pipes and fluid machines: per buffer the fluid,
// its level against the capacity and the flow in and out during the last
// tick, a note on ports closed to avoid mixing, the boiler's fuel slot
// and burn bar, and the machine state.

FLUID_AREA_WIDTH :: 480
// A level line and a flow line per buffer.
FLUID_ROWS_PER_BUFFER :: 2

// The pipe's buffer, or one per port.
fluid_buffer_count :: proc(machine: Machine) -> int {
	return machine.kind == .Pipe ? 1 : machine.fluid_port_count
}

// Whether the panel shows a state line.
fluid_machine_shows_state :: proc(kind: Machine_Kind) -> bool {
	return kind == .Offshore_Pump || kind == .Boiler || kind == .Pump || kind == .Steam_Engine
}

// Pumps and steam engines show their power network; steam engines their
// output too.
fluid_machine_power_rows :: proc(kind: Machine_Kind) -> int {
	#partial switch kind {
	case .Pump:
		return 1
	case .Steam_Engine:
		return 2
	}
	return 0
}

fluid_area_size :: proc(machine: Machine) -> [2]f32 {
	rows := 1 + FLUID_ROWS_PER_BUFFER * fluid_buffer_count(machine) + fluid_machine_power_rows(machine.kind)
	if fluid_machine_shows_state(machine.kind) {
		rows += 1
	}
	height := f32(rows) * UI_ROW_HEIGHT
	if machine.kind == .Boiler {
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

fluid_buffer_rows :: proc(state: ^Ui_State, content: ^Ui_Rectangle, fluids: Fluid_Registry, buffer: Fluid_Buffer, filter: Fluid_Id, capacity: i32, closed: bool, tick_rate: int) {
	ui_label(state, cut_top(content, UI_ROW_HEIGHT), fluid_level_line(fluids, buffer, filter, capacity, closed), UI_BODY_TEXT_SIZE, .Left)
	ui_label(state, cut_top(content, UI_ROW_HEIGHT), fluid_flow_line(buffer, tick_rate), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
}

pipe_panel_region :: proc(state: ^Ui_State, area: Ui_Rectangle, pipe: Pipe, screen_context: Screen_Context) {
	content := area
	capacity := screen_context.machines.machines[pipe.machine].buffer_litres
	fluid_buffer_rows(state, &content, screen_context.fluids, pipe.buffer, NO_FLUID, capacity, false, screen_context.tick_rate)
}

// The boiler's fuel slot and burn bar first, then a level and a flow line
// per port, then the state.
fluid_machine_slot_region :: proc(state: ^Ui_State, area: Ui_Rectangle, fluid_machine: Fluid_Machine, screen_context: Screen_Context) -> Slot_Grid_Result {
	result := Slot_Grid_Result{activated = -1, focused = -1}
	machine := screen_context.machines.machines[fluid_machine.machine]
	content := area
	if machine.kind == .Boiler {
		first := cut_top(&content, UI_SLOT_SIZE + UI_GAP)
		slots := fluid_machine.slots
		machine_slot(state, {first.x, first.y, UI_SLOT_SIZE, UI_SLOT_SIZE}, BOILER_FUEL_SLOT, slots[:], screen_context.items, &result)
		machine_bar(state, {first.x + UI_SLOT_SIZE + UI_GAP, first.y, MACHINE_BAR_WIDTH, UI_SLOT_SIZE}, boiler_burn_fraction(fluid_machine))
	}
	for port, index in fluid_ports_of(machine) {
		buffer, closed := fluid_machine.buffers[index], fluid_machine.closed[index]
		fluid_buffer_rows(state, &content, screen_context.fluids, buffer, port.filter, port.capacity, closed, screen_context.tick_rate)
	}
	if fluid_machine_shows_state(machine.kind) {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), text(fluid_machine_state_keys[fluid_machine.state]), UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
	}
	if machine.kind == .Steam_Engine {
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), generator_output_line(fluid_machine, screen_context.tick_rate), UI_BODY_TEXT_SIZE, .Left)
	}
	if fluid_machine_power_rows(machine.kind) > 0 {
		power_line := power_status_line(&screen_context.world.entities.electric_networks, fluid_machine.handle)
		ui_label(state, cut_top(&content, UI_ROW_HEIGHT), power_line, UI_BODY_TEXT_SIZE, .Left, UI_DIM_TEXT_COLOR)
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
