package game

import "core:fmt"

// The water tech demo's pump (work item 0295, doc/content.md, Water pumps;
// doc/architecture.md, The water field: tools and pumps). A Water_Pump
// machine rides in the fluid machines' pool with no ports, no slots and no
// power, standing on the ground or a lake bed (stands_on_ground). Its
// intake is the lowest sample that is not ground from the centre of its
// bottom row down to two samples below it (the water it stands in, or the
// bed's first air sample), or, where that centre lies in the ground (a
// slope rising under the footprint), the first open sample up from it
// within WATER_PUMP_INTAKE_CLIMB samples; its outlet the sample half a sample over its
// top, both set when it is placed (settle_water_pump). Interact cycles it
// Off, Sink, Source (cycle_water_pump_mode). Each tick after the buckets
// and before the water step (tick_water_pumps) a running pump earns its
// rate in millilitre-fill, the take_power_step pattern, and moves the
// whole fill the credit holds: a sink from the water at its intake (the
// body under it, or the column of front water over it), a source into the
// room over its outlet. What it moved is counted for the HUD's line; a
// pump that moved nothing says intake dry or output full and keeps no
// credit.

// The samples the intake climbs at most from the bottom row's centre
// when that lies in the ground (a slope under the footprint).
WATER_PUMP_INTAKE_CLIMB :: 4

Water_Pump_Mode :: enum u8 {
	Off,
	Sink,
	Source,
}

// A water pump's own state, nested in Fluid_Machine (zero for every other
// kind): the mode, the intake and outlet samples and the frame's up (a
// unit vector) the columns walk along, a full sample's millilitres at
// placement (so the tick and the HUD need no spacing), the rate's credit
// in millilitre-fill and the fill moved in all.
Water_Pump :: struct {
	mode:               Water_Pump_Mode,
	intake:             Sample_Coordinate,
	outlet:             Sample_Coordinate,
	up:                 [3]i64,
	sample_millilitres: i64,
	credit:             i64,
	moved_fill:         i64,
}

// A loaded sample that is not ground.
field_sample_is_open :: proc(world: ^Field_World, sample: Sample_Coordinate) -> bool {
	chunk, index := field_world_cell(world, sample)
	return chunk != nil && chunk.density[index] <= 0
}

// The pump just placed (apply_field_placement): its intake, outlet, up and
// sample volume from its frame, Off and Idle. Nothing for another kind.
settle_water_pump :: proc(state: ^Simulation_State, content: Simulation_Content, handle: Entity_Handle) {
	entities := &state.world.entities
	pump := pool_get(&entities.fluid_machines, handle)
	if pump == nil || content.machines.machines[pump.machine].kind != .Water_Pump {
		return
	}
	frame, found := find_frame(&entities.frames, pump.frame)
	if !found {
		return
	}
	world := &state.field.world
	spacing := state.field.spacing_millimetres
	up := frame.axes[FRAME_UP]
	step := sample_axis_to_position(1, spacing)
	pitch := frame_pitch_units(frame)
	first := frame_cell_centre(frame, pump.origin)
	last := frame_cell_centre(frame, pump.origin + {pump.size.x - 1, 0, pump.size.z - 1})
	centre := first + (last - first) / 2
	intake := nearest_field_sample(centre, spacing)
	if field_sample_is_open(world, intake) {
		for k in i64(1) ..= 4 {
			candidate := nearest_field_sample(centre - World_Position(fixed_scale(up, k * step / 2)), spacing)
			if !field_sample_is_open(world, candidate) {
				break
			}
			intake = candidate
		}
	} else {
		// On a slope rising towards the second cell the centre lies in the
		// ground: the first open sample up from it; none leaves the intake
		// in the ground, and the pump says dry.
		for k in i64(1) ..= 2 * WATER_PUMP_INTAKE_CLIMB {
			candidate := nearest_field_sample(centre + World_Position(fixed_scale(up, k * step / 2)), spacing)
			if field_sample_is_open(world, candidate) {
				intake = candidate
				break
			}
		}
	}
	outlet := nearest_field_sample(centre + World_Position(fixed_scale(up, pitch * i64(pump.size.y) - pitch / 2 + step / 2)), spacing)
	pump.water_pump = Water_Pump {
		mode               = .Off,
		intake             = intake,
		outlet             = outlet,
		up                 = up,
		sample_millilitres = field_sample_millilitres(spacing),
	}
	pump.state = .Idle
}

// Every running pump in the pool's order: its rate's credit, then the
// whole fill the credit holds from its intake or into its outlet. The rest
// of a fill the water could not give or take is dropped, and a pump that
// moved nothing keeps no credit, so no debt builds while it idles.
tick_water_pumps :: proc(state: ^Simulation_State, content: Simulation_Content) {
	world := &state.field.world
	spacing := state.field.spacing_millimetres
	for &pump in state.world.entities.fluid_machines.entries {
		if !pump.alive || pump.broken || content.machines.machines[pump.machine].kind != .Water_Pump {
			continue
		}
		machine := content.machines.machines[pump.machine]
		water := &pump.water_pump
		if water.mode == .Off {
			pump.state = .Idle
			water.credit = 0
			continue
		}
		step := i64(state.tick_rate) * water.sample_millilitres
		if step <= 0 {
			continue
		}
		water.credit += i64(machine.fluid_litres_per_second) * 1000 * FIELD_WATER_FULL
		fill := water.credit / step
		water.credit -= fill * step
		if fill == 0 {
			continue
		}
		moved: i64
		switch water.mode {
		case .Sink:
			moved = sink_field_water(world, water.intake, water.up, spacing, fill)
		case .Source:
			moved = source_field_water(world, water.outlet, water.up, spacing, fill)
		case .Off:
		}
		if moved == 0 {
			pump.state = water.mode == .Sink ? .No_Water : .Output_Full
			water.credit = 0
			continue
		}
		pump.state = .Pumping
		water.moved_fill += moved
	}
}

// A live water pump.
entity_is_water_pump :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	pump := pool_get(&entities.fluid_machines, handle)
	return pump != nil && machines.machines[pump.machine].kind == .Water_Pump
}

// Interact on a water pump: Off, Sink, Source, Off again, the credit
// dropped. False for anything else.
cycle_water_pump_mode :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) -> bool {
	if !entity_is_water_pump(entities, machines, handle) {
		return false
	}
	pump := pool_get(&entities.fluid_machines, handle)
	water := &pump.water_pump
	switch water.mode {
	case .Off:
		water.mode = .Sink
	case .Sink:
		water.mode = .Source
	case .Source:
		water.mode = .Off
		pump.state = .Idle
	}
	water.credit = 0
	return true
}

@(rodata)
water_pump_mode_keys := [Water_Pump_Mode]string {
	.Off    = "water_pump_mode_off",
	.Sink   = "water_pump_mode_sink",
	.Source = "water_pump_mode_source",
}

// The crosshair's line on a water pump: "Water pump  Off", or the name,
// the mode, the state and the litres moved. In the temp allocator.
water_pump_status_text :: proc(pump: Fluid_Machine, name: string) -> string {
	water := pump.water_pump
	if water.mode == .Off {
		return fmt.tprintf("%s  %s", name, text(water_pump_mode_keys[.Off]))
	}
	litres := replace_message_mark(text("water_pump_litres"), "{litres}", fmt.tprint(field_water_fill_litres(water.moved_fill, water.sample_millilitres)))
	return fmt.tprintf("%s  %s  %s  %s", name, text(water_pump_mode_keys[water.mode]), text(fluid_machine_state_keys[pump.state]), litres)
}
