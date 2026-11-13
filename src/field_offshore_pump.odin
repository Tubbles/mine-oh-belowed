package game

import "platform"

// The field's offshore pumps and their water (work item 0376,
// doc/fluids.md, Fluid machines). An offshore pump on a field frame
// draws only with water in front of its intake: from the centre of the
// cell in front of its intake end (offshore_pump_intake_cell, as in the
// block world) the reading walks down along the frame's up a sample at a
// time, at most FIELD_OFFSHORE_INTAKE_REACH_MILLIMETRES, adding each
// sample's water byte until the first ground sample. Any field water
// counts (the sea's, a lake's, a body's, front water); a stream's sheet
// falls short. Placement asks for the start depth
// (field_offshore_pump_refusal). Each tick after the water step
// (finish_field_tick) every pump reads again
// (refresh_offshore_pump_sources): one with water against the keep depth,
// one without against the start depth, so a surface waving at either
// does not switch it every tick. A walk that meets a chunk outside the
// simulated set before it decides keeps the pump's answer, which is the
// answer of that frozen water. Drawing takes nothing from the water. A
// pump on the block frame keeps the block rule, checked at placement
// only, and is never read here.

Offshore_Intake_Reading :: enum u8 {
	Unloaded,
	Dry,
	Wet,
}

// The intake's walk against a depth in millimetres: Wet as soon as the
// water adds up to it, so no sample past that is read. A sample whose
// chunk is not loaded reads the generation's water when generation is
// set (field_water_outside, its ground and a world without a planet
// ending the walk), else the reading is Unloaded.
read_offshore_pump_intake :: proc(world: ^Field_World, spacing_millimetres: int, frame: Frame, intake_cell: World_Coordinate, depth_millimetres: i64, generation: bool) -> Offshore_Intake_Reading {
	spacing := i64(spacing_millimetres)
	centre := frame_cell_centre(frame, intake_cell)
	up := frame.axes[FRAME_UP]
	step := sample_axis_to_position(1, spacing_millimetres)
	needed := depth_millimetres * FIELD_WATER_FULL
	water: i64 = 0
	previous: Sample_Coordinate
	for k in i64(0) ..= (FIELD_OFFSHORE_INTAKE_REACH_MILLIMETRES + spacing - 1) / spacing {
		sample := nearest_field_sample(centre - World_Position(fixed_scale(up, k * step)), spacing_millimetres)
		if k > 0 && sample == previous {
			continue
		}
		previous = sample
		fill, open, loaded := offshore_intake_sample(world, sample, generation)
		if !loaded {
			return .Unloaded
		}
		if !open {
			break
		}
		water += i64(fill)
		if water * spacing >= needed {
			return .Wet
		}
	}
	return water * spacing >= needed ? .Wet : .Dry
}

// One sample of the walk: its water, whether it is open (not ground) and
// whether it could be read.
offshore_intake_sample :: proc(world: ^Field_World, sample: Sample_Coordinate, generation: bool) -> (fill: i32, open: bool, loaded: bool) {
	chunk, index := field_world_cell(world, sample)
	if chunk != nil {
		return i32(chunk.water[index]), chunk.density[index] <= 0, true
	}
	if !generation {
		return 0, false, false
	}
	outside := field_water_outside(world, sample, field_water_span(sample))
	return max(outside, 0), outside >= 0, true
}

// The refusal of a placement on a field frame (field_placement_refusal,
// the developer's place): an offshore pump needs the start depth at its
// intake in the loaded water; any other machine passes.
field_offshore_pump_refusal :: proc(state: ^Simulation_State, content: Simulation_Content, machine: Machine_Id, frame: Frame, cell: World_Coordinate, rotation: u8) -> Field_Edit_Refusal {
	definition := content.machines.machines[machine]
	if definition.kind != .Offshore_Pump {
		return .None
	}
	intake := offshore_pump_intake_cell(cell, definition, rotation)
	reading := read_offshore_pump_intake(&state.field.world, state.field.spacing_millimetres, frame, intake, content.field.water.offshore_pump_start_depth_millimetres, false)
	return reading == .Wet ? .None : .No_Water_At_Intake
}

// A pump just placed passed the refusal, so it has water. Nothing for a
// handle that is no live offshore pump off the block frame.
mark_offshore_pump_source_present :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle) {
	pump := pool_get(&entities.fluid_machines, handle)
	if pump != nil && pump.frame != BLOCK_FRAME && machines.machines[pump.machine].kind == .Offshore_Pump {
		pump.source = .Present
	}
}

// The depth a pump's intake must hold: the start depth for a pump without
// water, the keep depth for one with water and for an old save's pump not
// read yet, which ran before the load.
offshore_pump_depth :: proc(tuning: Field_Water_Tuning, source: Pump_Source) -> i64 {
	return source == .Missing ? tuning.offshore_pump_start_depth_millimetres : tuning.offshore_pump_keep_depth_millimetres
}

// Every live offshore pump off the block frame in pool order, after the
// water step: Wet is Present, Dry Missing, Unloaded keeps the answer. An
// old save's pump (Unread) reads the generation where its column is
// outside the set, once. Returns the old saves' pumps found without
// water and logs one line when there are any; each pump is Unread once,
// so the line comes once a load.
refresh_offshore_pump_sources :: proc(state: ^Simulation_State, content: Simulation_Content) -> (old_missing: int) {
	entities := &state.world.entities
	for &pump in entities.fluid_machines.entries {
		if !pump.alive || pump.frame == BLOCK_FRAME || content.machines.machines[pump.machine].kind != .Offshore_Pump {
			continue
		}
		frame, found := find_frame(&entities.frames, pump.frame)
		if !found {
			continue
		}
		intake := offshore_pump_intake_cell(pump.origin, content.machines.machines[pump.machine], pump.rotation)
		depth := offshore_pump_depth(content.field.water, pump.source)
		switch read_offshore_pump_intake(&state.field.world, state.field.spacing_millimetres, frame, intake, depth, pump.source == .Unread) {
		case .Unloaded:
		case .Wet:
			pump.source = .Present
		case .Dry:
			if pump.source == .Unread {
				old_missing += 1
			}
			pump.source = .Missing
		}
	}
	if old_missing > 0 {
		platform.log_printf("save: %d offshore pumps on the field found no water at their intake and stand idle (0376)", old_missing)
	}
	return
}
