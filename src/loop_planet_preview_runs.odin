package game

import "platform"

// The planet preview's run (work item 0176): after the first pad and its
// arms, the walk screenshot lays a second pad
// PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES from the first along the
// diagonal between its forward and its right (a yaw step, so the poles
// face along the run) and a belt run between two poles placed free on the
// ground off the pads' facing corners, with items along it, so one level
// shot (--planet-preview-pitch=-10) shows two islands joined by a swept
// belt. The preview does not tick the entities, so the items stand still.

PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES :: 12000
// How far past a pad's corner its pole stands.
PLANET_PREVIEW_POLE_CLEARANCE_MILLIMETRES :: 750
// The items laid on the run, one every this many line units per lane.
PLANET_PREVIEW_RUN_ITEM :: "iron_plate"
PLANET_PREVIEW_RUN_ITEM_GAP :: 4 * BELT_ITEM_SPACING

// The poles the player carries, 0 when the data has no pole.
planet_preview_pole_count :: proc(miner: Field_Miner, content: Field_Simulation_Content) -> int {
	pole := field_content_machine(content, content.belt_pole, .Belt_Pole)
	if pole == NO_MACHINE {
		return 0
	}
	return inventory_count(miner.inventory, content.machines.machines[pole].item)
}

// The diagonal between the frame's forward and its right.
planet_preview_run_direction :: proc(frame: Frame) -> [3]i64 {
	direction, _ := normalize_fixed(frame.axes[FRAME_FORWARD] + frame.axes[FRAME_RIGHT])
	return direction
}

// The ground under a point along the run's direction from the frame's
// cell (0, 0, 0) bottom.
planet_preview_ground_along :: proc(preview: ^Planet_Preview, frame: Frame, millimetres: int) -> World_Position {
	generation := make_planet_generation(preview.seed, preview.planet, DEFAULT_SAMPLE_SPACING_MILLIMETRES)
	along := frame_cell_bottom(frame, {}) + World_Position(fixed_scale(planet_preview_run_direction(frame), millimetres_to_position_units(millimetres)))
	return field_surface_under(generation, along, 0)
}

lay_planet_preview_second_pad :: proc(preview: ^Planet_Preview, first: Frame) {
	content := preview.field_content
	entities := &preview.field.entities
	hit := planet_preview_ground_along(preview, first, PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES)
	_, frame := place_free_foundation(entities, content.machines, content.foundation, hit, first.axes[FRAME_FORWARD], content.foundation_pitch_millimetres)
	for x in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
		for z in -PLANET_PREVIEW_PAD_HALF_WIDTH ..= PLANET_PREVIEW_PAD_HALF_WIDTH {
			place_on_frame(entities, content.machines, content.foundation, frame, {i32(x), 0, i32(z)}, 0)
		}
	}
}

// Items every PLANET_PREVIEW_RUN_ITEM_GAP along both lanes of the run.
lay_planet_preview_run_items :: proc(preview: ^Planet_Preview, run: Entity_Handle) {
	item, found := find_item_id(preview.items, PLANET_PREVIEW_RUN_ITEM)
	entry := pool_get(&preview.field.entities.belt_runs, run)
	if !found || entry == nil {
		return
	}
	line := &preview.field.entities.belt_network.lines[entry.line]
	start := belt_line_segment_start(line^, entry.line_index)
	for distance := i32(BELT_INSERT_OFFSET); distance < entry.curve.length_units; distance += PLANET_PREVIEW_RUN_ITEM_GAP {
		for lane in Belt_Lane {
			lane_insert(&line.lanes[lane], item, start + distance)
		}
	}
}

// The second pad, the two poles and the run between them.
lay_planet_preview_run :: proc(preview: ^Planet_Preview, first_frame: Frame_Id) {
	content := preview.field_content
	entities := &preview.field.entities
	first, found := find_frame(&entities.frames, first_frame)
	kind, machine, tool_found := field_run_tool(content, .Belt_Run)
	if !found || !tool_found || kind != .Belt {
		return
	}
	lay_planet_preview_second_pad(preview, first)
	// The pad's half diagonal, a little over the half width times 1.414.
	edge := (2 * PLANET_PREVIEW_PAD_HALF_WIDTH + 1) * content.foundation_pitch_millimetres * 3 / 4 + PLANET_PREVIEW_POLE_CLEARANCE_MILLIMETRES
	start_hit := planet_preview_ground_along(preview, first, edge)
	end_hit := planet_preview_ground_along(preview, first, PLANET_PREVIEW_SECOND_PAD_DISTANCE_MILLIMETRES - edge)
	chord := cast([3]i64)(end_hit - start_hit)
	start, _ := place_free_belt_pole(entities, content.machines, content.belt_pole, start_hit, chord, content.foundation_pitch_millimetres)
	end, _ := place_free_belt_pole(entities, content.machines, content.belt_pole, end_hit, chord, content.foundation_pitch_millimetres)
	start_endpoint, _ := belt_pole_endpoint(entities, start, chord, kind, BELT_RUN_START)
	end_endpoint, _ := belt_pole_endpoint(entities, end, chord, kind, BELT_RUN_END)
	run, refusal := add_belt_run(entities, content.machines, content.belt_runs, kind, machine, {start_endpoint, end_endpoint})
	if refusal != .None {
		platform.log_printf("planet preview: the run between the pads is refused: %v", refusal)
		return
	}
	lay_planet_preview_run_items(preview, run)
	entry := pool_get(&entities.belt_runs, run)
	platform.log_printf("planet preview: a run of %d mm between the pads", entry.curve.arc_length * MILLIMETRES_PER_METRE / POSITION_UNITS_PER_METRE)
}
