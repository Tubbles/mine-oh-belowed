package game

// The water tech demo's buckets (work item 0295, doc/input.md, the
// buckets; doc/architecture.md, The water field: tools and pumps). Place
// with the water bucket held pours bucket_fill_per_press fill into the
// room round the aimed sample, the brush's size; with the drain bucket it
// takes up to as much from the water there. A press fires at once and a
// held Place again every bucket_repeat_ticks. The player's tick queues the
// edit (queue_field_water_edit); the queue drains after the placements and
// before the pumps and the water step (finish_field_tick), so a pour
// moves on the next tick as a dug hole floods. What a press poured or took
// is counted on the player for the HUD (poured_fill, drained_fill).

Field_Water_Edit_Mode :: enum u8 {
	Pour,
	Drain,
}

// One press: the aimed sample, the brush's radius in position units and
// the fill to pour or take.
Field_Water_Edit :: struct {
	mode:   Field_Water_Edit_Mode,
	centre: Sample_Coordinate,
	radius: i64,
	amount: i32,
}

Queued_Field_Water_Edit :: struct {
	player: int,
	edit:   Field_Water_Edit,
}

// Where a bucket pours or drains: with a ground hit the first sample that
// is not ground along its normal (field_torch_sample: a lake bed's hit
// gives the water above it); without one the sample at the end of the aim
// (the reach, or a nearer frame or trunk), when it is loaded and not
// ground, so a bucket works on deep water beyond the bed's reach.
field_water_tool_sample :: proc(world: ^Field_World, spacing_millimetres: int, player: Field_Player, tuning: Field_Player_Tuning) -> (sample: Sample_Coordinate, found: bool) {
	if player.target.hit {
		return field_torch_sample(world, spacing_millimetres, player.target)
	}
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	end := field_player_eye(player, tuning) + World_Position(fixed_scale(look, field_aim_limit(player, tuning)))
	sample = nearest_field_sample(end, spacing_millimetres)
	chunk, index := field_world_cell(world, sample)
	if chunk == nil || chunk.density[index] > 0 {
		return {}, false
	}
	return sample, true
}

// A bucket's press or hold this tick queues its edit; any other tool
// resets the hold. No refusal is told where nothing is aimed (a resting
// thumb).
queue_field_water_edit :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) {
	body := &state.players[index].field
	if body.tool != .Water && body.tool != .Drain {
		body.water_tool_ticks = 0
		return
	}
	tuning := content.field.water
	fire := false
	switch {
	case .Place in input.just_pressed:
		fire = true
	case .Place in input.held:
		body.water_tool_ticks = u8(min(int(body.water_tool_ticks) + 1, 255))
		fire = body.water_tool_ticks >= tuning.bucket_repeat_ticks
	case:
		body.water_tool_ticks = 0
	}
	if !fire {
		return
	}
	body.water_tool_ticks = 0
	brushes := content.field.brushes
	if len(brushes) == 0 {
		return
	}
	sample, found := field_water_tool_sample(&state.field.world, state.field.spacing_millimetres, body^, content.field.tuning)
	if !found {
		return
	}
	edit := Field_Water_Edit {
		mode   = body.tool == .Water ? .Pour : .Drain,
		centre = sample,
		radius = brushes[int(body.brush) % len(brushes)].radius,
		amount = tuning.bucket_fill_per_press,
	}
	append(&state.field.water_edits, Queued_Field_Water_Edit{player = index, edit = edit})
}

// Every queued bucket edit in order, counted on its player; then the
// queue is empty.
drain_field_water_edits :: proc(state: ^Simulation_State, content: Simulation_Content) {
	field := &state.field
	for queued in field.water_edits {
		body := &state.players[queued.player].field
		edit := queued.edit
		switch edit.mode {
		case .Pour:
			body.poured_fill += pour_field_water(&field.world, field.spacing_millimetres, edit.centre, edit.radius, edit.amount)
		case .Drain:
			body.drained_fill += drain_field_water(&field.world, field.spacing_millimetres, edit.centre, edit.radius, edit.amount)
		}
	}
	clear(&field.water_edits)
}
