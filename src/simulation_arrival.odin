package game

import "platform"

// The arrival (work item 0200, doc/architecture.md, The field session,
// The arrival): a new world's first ticks are the pod's fall. While it
// falls every player's input frame is empty (arrival_input), in the tick
// and in the prediction; at the end of its last tick, or when the pause
// menu's Skip applies (Skip_Arrival_Command), it lands
// (land_field_arrival) and the pod's hatches open through toggle_hatch.
// Its table follows the felled trees in entities.bin, so it is hashed,
// travels in the join snapshot, and a world loaded or joined past the
// fall never falls again. The presentation (render_arrival.odin) reads it
// and never writes it.

// start_tick is the tick the fall began (the new world's), fall_ticks its
// length (0 for no fall), landed_tick the tick it landed (0 while falling
// or without a fall; ticks start at 1, so 0 is never a landing).
Field_Arrival :: struct {
	start_tick:  u64,
	fall_ticks:  u64,
	landed_tick: u64,
}

// A new world's fall, from start_field_world (not the benchmark's).
begin_field_arrival :: proc(field: ^Field_Simulation, tick: u64, fall_ticks: int) {
	field.arrival = {start_tick = tick, fall_ticks = u64(fall_ticks)}
}

field_arrival_falling :: proc(arrival: Field_Arrival) -> bool {
	return arrival.fall_ticks > 0 && arrival.landed_tick == 0
}

// Before the hit, which comes settle_ticks before the planned landing:
// the pause menu offers Skip arrival only then, so a Skip never cuts the
// hit's shake and dust short (a Skip arriving later still lands).
field_arrival_skippable :: proc(arrival: Field_Arrival, tick: u64, settle_ticks: int) -> bool {
	return field_arrival_falling(arrival) && tick + u64(settle_ticks) < arrival.start_tick + arrival.fall_ticks
}

// The fall's last tick has run (or is running).
field_arrival_due :: proc(arrival: Field_Arrival, tick: u64) -> bool {
	return field_arrival_falling(arrival) && tick >= arrival.start_tick + arrival.fall_ticks
}

// The frame a player's tick reads: nothing while the world falls.
arrival_input :: proc(arrival: Field_Arrival, frame: Input_Frame) -> Input_Frame {
	if field_arrival_falling(arrival) {
		return Input_Frame{}
	}
	return frame
}

// Lands the fall at the state's tick and opens every closed hatch in the
// foundations' pool order (opening never checks capsules).
land_field_arrival :: proc(state: ^Simulation_State, content: Simulation_Content) {
	state.field.arrival.landed_tick = state.tick
	open_closed_hatches(state, content.machines)
}

// Every alive closed hatch opened at the state's tick, in pool order.
open_closed_hatches :: proc(state: ^Simulation_State, machines: Machine_Registry) {
	for entry in state.world.entities.foundations.entries {
		if entry.alive && int(entry.machine) < len(machines.machines) && machines.machines[entry.machine].kind == .Hatch && !entry.hatch_open {
			toggle_hatch(&state.world.entities, machines, entry.handle, state.tick, nil)
		}
	}
}

// The save table.

// Always in a field world, after the felled trees (write_simulation_state),
// so a save without it is one from before 0200.
write_field_arrival_table :: proc(bytes: ^[dynamic]byte, field: ^Field_Simulation) {
	append_u64(bytes, field.arrival.start_tick)
	append_u64(bytes, field.arrival.fall_ticks)
	append_u64(bytes, field.arrival.landed_tick)
}

// A save from before 0200 ends before the table and loads with no fall,
// its hatches as saved, with one log line. False for a fall longer than
// MAXIMUM_ARRIVAL_TICKS or a landing before its start.
read_field_arrival_table :: proc(reader: ^Byte_Reader, field: ^Field_Simulation) -> bool {
	field.arrival = {}
	if bytes_left(reader^) == 0 {
		platform.log_printf("save: written before the arrival (0200), the world starts landed")
		return true
	}
	arrival: Field_Arrival
	arrival.start_tick = read_u64(reader) or_return
	arrival.fall_ticks = read_u64(reader) or_return
	arrival.landed_tick = read_u64(reader) or_return
	if arrival.fall_ticks > MAXIMUM_ARRIVAL_TICKS || (arrival.landed_tick != 0 && arrival.landed_tick < arrival.start_tick) {
		return false
	}
	field.arrival = arrival
	return true
}
