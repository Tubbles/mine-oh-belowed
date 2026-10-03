package game

import "core:math"

// The field session's part of the tick (work item 0179, doc/architecture.md,
// The field session). A field session's players walk the terrain field
// (Player.field) instead of the block world: simulation_tick turns each
// player's input frame into the field's integer input (field_tick_input),
// the hotbar's selected stack decides the tool (field_tool_for_item), the
// players move and queue their brush edits and placements in player order,
// and the queues drain at the end of the field's part
// (finish_field_tick). The entities (the frames' machines, the arms, the
// runs) tick on World.entities after it as in the block world.
//
// The torch: Place with the torch item held puts a torch at the air
// sample in front of the targeted ground (an emitter of data/
// lighting.sjson, kept in Field_Simulation.torches) and takes one torch;
// Dig aimed at a torch within the reach takes it back with its item. Both
// are placements, so they apply at the end of the tick in order.
//
// The home spawn: every new player, the first and a joining one, stands
// on the generated surface at the planet's home (data/planets.sjson),
// facing the first spring, with the starter kit (make_field_session_player).

// A torch is aimed at while the reticle's ray passes this close to its
// sample.
FIELD_TORCH_AIM_RADIUS_MILLIMETRES :: 600
// A new player starts this far above the generated surface and drops.
FIELD_SPAWN_CLEARANCE_MILLIMETRES :: 250

// The field's tables for a session (Simulation_Content.field): the
// tuning of the planet, the spacing and the tick rate; the brushes in
// allocator.
make_field_content :: proc(config: Game_Config, items: Item_Registry, machines: Machine_Registry, materials: Field_Material_Table, lighting: Lighting_File, planet: Planet, spacing_millimetres: int, allocator := context.allocator) -> Field_Content {
	torch_level, _ := find_lighting_emitter(lighting, config.field_simulation.torch_emitter)
	torch_item, torch_found := find_item_id(items, config.field_simulation.torch_item)
	return Field_Content {
		materials = materials,
		brushes = make_field_brushes(config.field_brushes, allocator),
		tuning = make_field_player_tuning(config.field_player, planet, spacing_millimetres, config.tick_rate),
		water = make_field_water_tuning(config.field_water),
		light = make_field_light_tuning(lighting, spacing_millimetres),
		foundation = find_foundation_machine(machines),
		foundation_pitch_millimetres = config.foundation_pitch_millimetres,
		belt_pole = find_machine_of_kind(machines, .Belt_Pole),
		run_belt = find_belt_machine(machines, .Flat),
		run_pipe = find_machine_of_kind(machines, .Pipe),
		belt_runs = make_belt_run_constraints(config.belt_runs),
		torch_item = torch_found ? torch_item : NO_ITEM,
		torch_level = u8(torch_level),
		starting_items = config.starting_items,
	}
}

// The torch's item and emitter name what the data has (load_game_tables).
field_torch_problem :: proc(field: Field_Simulation_Config, items: Item_Registry, lighting: Lighting_File) -> string {
	if _, found := find_item_id(items, field.torch_item); !found {
		return "field_simulation.torch_item is not an item"
	}
	if _, found := find_lighting_emitter(lighting, field.torch_emitter); !found {
		return "field_simulation.torch_emitter is not an emitter of lighting.sjson"
	}
	return ""
}

// The input.

// The turn a tick takes from its frame, in angle units before rounding.
field_frame_turn :: proc(frame: Input_Frame, tick_rate: int) -> [2]f32 {
	stick_degrees := frame.look * FLY_CAMERA_STICK_DEGREES_PER_SECOND / f32(max(tick_rate, 1))
	pointer_degrees := frame.look_delta * FLY_CAMERA_DEGREES_PER_LOOK_PIXEL
	return [2]f32{stick_degrees.x + pointer_degrees.x, stick_degrees.y - pointer_degrees.y} * ANGLE_UNITS_PER_TURN / 360
}

// The tick's frame as the field player's integers: the stick in
// thousandths, the turn in angle units at the fly camera's rates for one
// tick (the stick's degrees a second over the tick rate, the pointer's
// degrees a pixel), each rounded towards zero. Every machine converts the
// same record the same way, so the result is the same everywhere. The
// fraction the rounding drops is carried by the frame side
// (carry_field_turn).
field_tick_input :: proc(frame: Input_Frame, tick_rate: int) -> Field_Player_Input {
	turn := field_frame_turn(frame, tick_rate)
	input := Field_Player_Input {
		move          = {i32(clamp(frame.move.x, -1, 1) * FIELD_MOVE_ONE), i32(clamp(frame.move.y, -1, 1) * FIELD_MOVE_ONE)},
		turn          = {i32(math.clamp(turn.x, -ANGLE_UNITS_PER_TURN, ANGLE_UNITS_PER_TURN)), i32(math.clamp(turn.y, -ANGLE_UNITS_PER_TURN, ANGLE_UNITS_PER_TURN))},
		developer     = frame.developer,
		world_blocked = frame.world_blocked,
	}
	buttons := [?]struct {
		action: Action,
		button: Field_Player_Button,
	}{{.Jump, .Jump}, {.Sneak, .Sneak}, {.Sprint, .Sprint}, {.Sprint_Hold, .Sprint}, {.Toggle_Fly_Mode, .Toggle_Fly_Mode}, {.Toggle_No_Clip, .Toggle_No_Clip}, {.Toggle_Camera_Mode, .Toggle_Camera_Mode}, {.Mine, .Dig}, {.Place, .Place}, {.Rotate_Building, .Next_Brush}, {.Back, .Back}}
	for entry in buttons {
		if entry.action in frame.pressed {
			input.held += {entry.button}
		}
		if entry.action in frame.just_pressed {
			input.just_pressed += {entry.button}
		}
	}
	return input
}

// The tool.

// What an item held in the hotbar lets Place do (Field_Held_Tool), with
// the material or the machine it names.
field_tool_for_item :: proc(content: Simulation_Content, item: Item_Id) -> (tool: Field_Held_Tool, material: Field_Material, machine: Machine_Id) {
	if item == NO_ITEM {
		return .Hand, .Air, NO_MACHINE
	}
	for record, candidate in content.field.materials {
		if candidate != .Air && record.item == item {
			return .Material, candidate, NO_MACHINE
		}
	}
	if item == content.field.torch_item {
		return .Torch, .Air, NO_MACHINE
	}
	machine = item_places_machine(content.machines, item)
	if machine == NO_MACHINE {
		return .Hand, .Air, NO_MACHINE
	}
	#partial switch content.machines.machines[machine].kind {
	case .Foundation:
		return .Foundation, .Air, machine
	case .Belt, .Belt_Pole:
		return .Belt_Run, .Air, machine
	case .Pipe:
		return .Pipe_Run, .Air, machine
	}
	return .Machine, .Air, machine
}

// The tool follows the selected hotbar stack; a change of tool forgets a
// run's first endpoint. Next_Brush turns a held machine a quarter, and
// cycles the brushes otherwise.
update_field_held_tool :: proc(player: ^Player, content: Simulation_Content, input: Field_Player_Input) {
	stack := selected_hotbar_stack(player^)
	item := stack_is_empty(stack) ? NO_ITEM : stack.item
	tool, material, machine := field_tool_for_item(content, item)
	body := &player.field
	if tool != body.tool || machine != body.held_machine {
		body.run_started = false
	}
	body.tool, body.held_machine = tool, machine
	if tool == .Material {
		body.held_material = material
	}
	if .Next_Brush not_in input.just_pressed {
		return
	}
	if tool == .Machine {
		body.placement_rotation = (body.placement_rotation + 1) % 4
	} else if len(content.field.brushes) > 0 {
		body.brush = u8((int(body.brush) + 1) % len(content.field.brushes))
	}
}

// The torch.

// The air sample in front of the hit: the first along its normal, in
// half samples up to two samples out.
field_torch_sample :: proc(world: ^Field_World, spacing_millimetres: int, hit: Field_Raycast_Hit) -> (sample: Sample_Coordinate, found: bool) {
	half := sample_axis_to_position(1, spacing_millimetres) / 2
	for step in i64(1) ..= 4 {
		sample = nearest_field_sample(hit.position + World_Position(fixed_scale(hit.normal, step * half)), spacing_millimetres)
		if field_world_get_sample(world, sample).density <= 0 {
			return sample, true
		}
	}
	return {}, false
}

field_torch_index :: proc(torches: []Field_Torch, sample: Sample_Coordinate) -> int {
	for torch, index in torches {
		if torch.sample == sample {
			return index
		}
	}
	return -1
}

// How far along the ray the reticle's terrain or frame hit lies, or the
// reach without one: a torch behind it is out of sight.
field_aim_limit :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> i64 {
	limit := tuning.reach
	if player.target.hit {
		limit = min(limit, player.target.distance)
	}
	if player.frame_target.hit {
		limit = min(limit, player.frame_target.distance)
	}
	return limit
}

// The torch the player's reticle is on: within the reach and the aim
// radius of the ray and nearer along it than the terrain or frame hit,
// the nearest the ray first; -1 for none.
field_aimed_torch :: proc(torches: []Field_Torch, player: Field_Player, tuning: Field_Player_Tuning) -> int {
	eye := field_player_eye(player, tuning)
	look := field_look_direction(player.forward, player.up, player.yaw, player.pitch)
	radius := millimetres_to_position_units(FIELD_TORCH_AIM_RADIUS_MILLIMETRES)
	limit := field_aim_limit(player, tuning)
	best, best_across := -1, i64(max(i64))
	for torch, index in torches {
		offset := cast([3]i64)(sample_to_world_position(torch.sample, tuning.spacing_millimetres) - eye)
		along := fixed_dot(offset, look)
		if along <= 0 || along >= limit || vector_length(offset) > tuning.reach {
			continue
		}
		across := vector_length(offset - fixed_scale(look, along))
		if across <= radius && across < best_across {
			best, best_across = index, across
		}
	}
	return best
}

// Place with the torch held queues a torch at the air before the target;
// Dig pressed (not held) on an aimed torch queues its removal. Returns
// whether the Dig went to a torch, so the brush does not dig behind it in
// that tick; a held Dig digs.
queue_field_torch :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, input: Field_Player_Input) -> (took_dig: bool) {
	field := &state.field
	body := state.players[index].field
	if .Dig in input.just_pressed {
		if aimed := field_aimed_torch(field.torches[:], body, content.field.tuning); aimed >= 0 {
			append(&field.placements, Queued_Field_Placement{player = index, placement = Field_Placement{kind = .Torch_Removal, sample = field.torches[aimed].sample}})
			return true
		}
	}
	if body.tool != .Torch || .Place not_in input.just_pressed || !body.target.hit {
		return false
	}
	if sample, found := field_torch_sample(&field.world, field.spacing_millimetres, body.target); found {
		append(&field.placements, Queued_Field_Placement{player = index, placement = Field_Placement{kind = .Torch, sample = sample}})
	}
	return false
}

// At the drain: a torch where none is, taking one torch item.
drain_field_torch :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, sample: Sample_Coordinate) {
	field := &state.field
	switch {
	case inventory_count(player.inventory, content.field.torch_item) == 0:
		player.field_refusal = .Nothing_Held
		return
	case field_torch_index(field.torches[:], sample) >= 0 || field_world_get_sample(&field.world, sample).density > 0:
		player.field_refusal = .Torch_Blocked
		return
	}
	add_field_light_source(&field.world, sample, content.field.torch_level)
	append(&field.torches, Field_Torch{sample = sample})
	inventory_remove(player.inventory, content.field.torch_item, 1)
}

// At the drain: the torch taken back, its item into the inventory; with
// no room it stays.
drain_field_torch_removal :: proc(state: ^Simulation_State, content: Simulation_Content, player: ^Player, sample: Sample_Coordinate) {
	field := &state.field
	index := field_torch_index(field.torches[:], sample)
	if index < 0 {
		return
	}
	if inventory_add_picked_up(player.inventory, content.items, content.field.torch_item, 1) > 0 {
		player.field_refusal = .Inventory_Full
		return
	}
	remove_field_light_source(&field.world, sample)
	ordered_remove(&field.torches, index)
}

// The player.

// Interact on a frame cell whose machine has a panel opens it, as the
// block world's Interact does (resolve_interact); the gamepad's A then
// does not jump.
interact_on_field :: proc(player: ^Player, entities: ^Entities, frame: Input_Frame) -> (input: Input_Frame, events: Player_Events) {
	input = frame
	target := player.field.frame_target
	if !target.hit {
		return input, {}
	}
	handle := entity_from_occupant(target.occupant.handle)
	if !entity_has_panel(entities, handle) {
		return input, {}
	}
	if .Interact in frame.pressed {
		input.pressed -= {.Jump}
		input.just_pressed -= {.Jump}
	}
	if .Interact not_in frame.just_pressed {
		return input, {}
	}
	player.open_machine = handle
	return input, {.Open_Machine}
}

// One field player's part of the tick, before the drain: the hotbar, the
// tool, the move and the queued edits and placements, the hand crafting.
tick_field_session_player :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> Player_Events {
	player := &state.players[index]
	resolved, events := interact_on_field(player, &state.world.entities, frame)
	player.selected_hotbar_slot = cycle_hotbar_slot(player.selected_hotbar_slot, resolved.just_pressed)
	input := field_tick_input(resolved, state.tick_rate)
	update_field_held_tool(player, content, input)
	if queue_field_torch(state, content, index, input) {
		input.held -= {.Dig}
		input.just_pressed -= {.Dig}
	}
	queue_field_player_edit(state, content, index, input)
	if finished := advance_crafting(&player.crafting, player.inventory, content.recipes, content.items, state.tick_rate); finished != NO_RECIPE {
		record_produced_stacks(&state.records.statistics, content.recipes.recipes[finished].outputs)
		record_consumed_stacks(&state.records.statistics, content.recipes.recipes[finished].inputs)
	}
	return events
}

// Every field player in player order, then the queues drain. inputs[index]
// is players[index]'s; a missing one is no input.
tick_field_session_players :: proc(state: ^Simulation_State, content: Simulation_Content, inputs: []Input_Frame) {
	for index in 0 ..< len(state.players) {
		events := tick_field_session_player(state, content, index, index < len(inputs) ? inputs[index] : Input_Frame{})
		for kind in events {
			append(&state.events, Simulation_Event{player = index, kind = kind})
		}
	}
	finish_field_tick(state, content)
}

// The home spawn.

// The surface at the planet's home, the feet the clearance above it,
// heading towards the first spring (towards +x on a planet without one).
field_home_player :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player {
	generation := make_planet_generation(seed, planet, spacing_millimetres)
	home := planet_home_direction(planet.home)
	clearance := millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)
	feet := field_surface_under(generation, World_Position(fixed_scale(home, generation.radius)), clearance)
	look := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	if len(planet.springs) > 0 {
		look = planet_spring_direction(planet.springs[0]) - home
	}
	return make_field_player(feet, look)
}

// A new world's field (a session's, the benchmark's): the spacing, the
// simulated set of data/game.sjson, the planet, every player at the home
// and the water's planet. The world's seed is set before.
enable_new_field_world :: proc(state: ^Simulation_State, config: Game_Config, planet: Planet, spacing_millimetres: int) {
	field := &state.field
	field.enabled = true
	field.spacing_millimetres = spacing_millimetres
	field.chunk_set = make_field_chunk_set(config.field_simulation.chunk_radius, config.field_simulation.chunk_margin)
	state.world.planet = planet
	seed := state.world.settings.seed
	for &player in state.players {
		player.field = field_home_player(seed, planet, spacing_millimetres)
	}
	field.world.water_planet = make_field_water_planet(seed, planet, spacing_millimetres)
}

// The spawn of a field session's new player: the home, the starter kit
// (data/game.sjson, starting_items). The first player of a new world and
// every joining one come through here.
make_field_session_player :: proc(state: Simulation_State, content: Simulation_Content, start: Player_Start) -> Player {
	player := make_player(start)
	player.field = field_home_player(state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	give_starting_items(&player, content.items, content.field.starting_items)
	return player
}
