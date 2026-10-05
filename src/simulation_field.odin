package game

import "core:math"

// The field session's part of the tick (work item 0179, doc/architecture.md,
// The field session). A field session's players walk the terrain field
// (Player.field) instead of the block world: simulation_tick turns each
// player's input frame into the field's integer input (field_tick_input),
// the hotbar's selected stack decides the tool (field_tool_for_item), the
// players move and queue their brush edits and placements in player order,
// and the queues drain at the end of the field's part
// (finish_field_tick). After the players move and the queues drain, the
// pod's hatches follow the players (tick_pod_airlocks, 0222, 0231: a
// hatch is open exactly while a player is within reach of it). The
// entities (the frames' machines, the arms, the runs) tick on
// World.entities after it as in the block world.
//
// The torch: Place with the torch item held puts a torch at the air
// sample in front of the targeted ground (an emitter of data/
// lighting.sjson, kept in Field_Simulation.torches) and takes one torch;
// Dig aimed at a torch within the reach takes it back with its item. Both
// are placements, so they apply at the end of the tick in order.
//
// The home spawn: a new world stands the pod on the floor of the crater
// at the planet's home (data/planets.sjson, work item 0199) with its door
// towards the first spring; every new player, the first and a joining
// one, stands in the pod's cabin facing the door, with the starter kit
// (field_pod_spawn, make_field_session_player), or sits strapped into its
// chair while the world falls (0223). A new world's home is the
// nearest dry point to the record's (new_world_home, 0180), and a place
// that would raise ground into the spawn's capsule is refused with a
// refusal of its own (Would_Bury_Spawn, field_place_buries_a_player).

// A torch is aimed at while the reticle's ray passes this close to its
// sample.
FIELD_TORCH_AIM_RADIUS_MILLIMETRES :: 600
// A new player starts this far above the cabin's floor or the generated
// surface and drops.
FIELD_SPAWN_CLEARANCE_MILLIMETRES :: 250

// The field's tables for a session (Simulation_Content.field): the
// tuning of the planet, the spacing and the tick rate; the brushes and the
// tree species in allocator (destroy_field_content).
make_field_content :: proc(config: Game_Config, items: Item_Registry, machines: Machine_Registry, materials: Field_Material_Table, lighting: Lighting_File, planet: Planet, spacing_millimetres: int, allocator := context.allocator) -> Field_Content {
	torch_level, _ := find_lighting_emitter(lighting, config.field_simulation.torch_emitter)
	torch_item, torch_found := find_item_id(items, config.field_simulation.torch_item)
	return Field_Content {
		materials = materials,
		brushes = make_field_brushes(config.field_brushes, allocator),
		tuning = make_field_player_tuning(config.field_player, planet, spacing_millimetres, config.tick_rate),
		water = make_field_water_tuning(config.field_water),
		light = make_field_light_tuning(lighting, spacing_millimetres),
		pad_foundation = find_pad_foundation(machines, config.field_simulation.pad_foundation),
		foundation_pitch_millimetres = config.foundation_pitch_millimetres,
		foundation_sizes = config.foundation_sizes,
		foundation_heights = config.foundation_heights,
		direct_placement_limit = {i32(config.direct_placement_limit.width), i32(config.direct_placement_limit.height), i32(config.direct_placement_limit.depth)},
		belt_pole = find_machine_of_kind(machines, .Belt_Pole),
		run_belt = find_belt_machine(machines, .Flat),
		run_pipe = find_machine_of_kind(machines, .Pipe),
		belt_runs = make_belt_run_constraints(config.belt_runs),
		torch_item = torch_found ? torch_item : NO_ITEM,
		torch_level = u8(torch_level),
		starting_items = config.starting_items,
		bare_ground = make_bare_ground_tuning(config),
		pod_airlock = make_pod_airlock_tuning(config.pod_airlock),
		pod_rest = Pod_Rest_Tuning{tilt_degrees = config.arrival_rest_tilt_degrees, settle_ticks = config.arrival_settle_ticks},
		tree_species = make_field_tree_species(planet.trees, items, machines, config.tick_rate, allocator),
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

// The pad foundation names a machine of kind foundation (load_game_tables).
field_pad_foundation_problem :: proc(field: Field_Simulation_Config, machines: Machine_Registry) -> string {
	machine, found := find_machine_id(machines, field.pad_foundation)
	if !found || machines.machines[machine].kind != .Foundation {
		return "field_simulation.pad_foundation is not a machine of kind foundation"
	}
	return ""
}

// NO_MACHINE when the machines have no such id.
find_pad_foundation :: proc(machines: Machine_Registry, id: string) -> Machine_Id {
	machine, _ := find_machine_id(machines, id)
	return machine
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
// the material or the machine it names. An item with a tool_role is the
// Tool (0265); a role-less tool (the hammer) is the hand.
field_tool_for_item :: proc(content: Simulation_Content, item: Item_Id) -> (tool: Field_Held_Tool, material: Field_Material, machine: Machine_Id) {
	if item == NO_ITEM {
		return .Hand, .Air, NO_MACHINE
	}
	if content.items.items[item].tool_role != .None {
		return .Tool, .Air, NO_MACHINE
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

// The tool follows the selected hotbar stack, a Tool's role and tier
// with it (0265); a change of tool forgets a run's first endpoint.
// Next_Brush turns a held machine a quarter, and cycles the brushes
// otherwise.
update_field_held_tool :: proc(player: ^Player, content: Simulation_Content, input: Field_Player_Input) {
	stack := selected_hotbar_stack(player^)
	item := stack_is_empty(stack) ? NO_ITEM : stack.item
	tool, material, machine := field_tool_for_item(content, item)
	role, tier := held_tool_role_and_tier(content.items, tool, item)
	body := &player.field
	if tool != body.tool || machine != body.held_machine || role != body.held_tool_role {
		body.run_started = false
	}
	body.tool, body.held_machine = tool, machine
	body.held_tool_role, body.held_tool_tier = role, tier
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

// The Tool's role and tier, None and 0 for any other tool. The tier is
// at most MAXIMUM_TOOL_TIER, so it fits a byte.
held_tool_role_and_tier :: proc(items: Item_Registry, tool: Field_Held_Tool, item: Item_Id) -> (role: Item_Tool_Role, tier: u8) {
	if tool != .Tool {
		return .None, 0
	}
	return items.items[item].tool_role, u8(items.items[item].tool_tier)
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

// How far along the ray the reticle's terrain, frame or trunk hit (0197)
// lies, or the reach without one: a torch behind it is out of sight.
field_aim_limit :: proc(player: Field_Player, tuning: Field_Player_Tuning) -> i64 {
	limit := tuning.reach
	if player.target.hit {
		limit = min(limit, player.target.distance)
	}
	if player.frame_target.hit {
		limit = min(limit, player.frame_target.distance)
	}
	if player.tree_target.hit {
		limit = min(limit, player.tree_target.distance)
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

// Open_Aimed on a frame cell whose machine has a panel opens it, as the
// block world's does (resolve_interact, 0194); Interact turns a power
// switch there (a hatch takes no Interact since 0231, a launch pad
// launches from its panel since 0233).
interact_on_field :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> Player_Events {
	player := &state.players[index]
	entities, machines := &state.world.entities, content.machines
	handle := aimed_entity(NO_ENTITY, player.field.frame_target)
	if .Open_Aimed in frame.just_pressed && entity_has_panel(entities, machines, handle) {
		player.open_machine = handle
		return {.Open_Machine}
	}
	if .Interact in frame.just_pressed && toggle_power_switch(entities, machines, handle) {
		return {.Toggled_Switch}
	}
	return {}
}

// The chair (0223).

// What a seated player's frame keeps of the actions: the inventory
// binding at the bench opens its panel from the chair, as the HUD's Open
// promises.
SEATED_FIELD_ACTIONS :: Action_Set{.Open_Aimed}

// A seated player's frame: no walk and no action but
// SEATED_FIELD_ACTIONS; the look, the pointer delta and the flags stay.
seated_field_frame :: proc(frame: Input_Frame) -> Input_Frame {
	seated := frame
	seated.move = {}
	seated.pressed &= SEATED_FIELD_ACTIONS
	seated.just_pressed &= SEATED_FIELD_ACTIONS
	return seated
}

// Interact on the chair, never while the world falls: a strapped or
// seated player stands whatever the aim (the chair is under them), a
// standing one aimed at the chair sits. True when it acted.
interact_on_field_chair :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> bool {
	if field_arrival_falling(state.field.arrival) || .Interact not_in frame.just_pressed {
		return false
	}
	player := &state.players[index]
	entities := &state.world.entities
	switch player.field.seat {
	case .Strapped, .Seated:
		stand_field_player_from_seat(entities, content.machines, &player.field)
		return true
	case .Standing:
		if field_aimed_chair(entities, content.machines, player.field.frame_target) && seat_field_player(entities, content.machines, content.field.tuning, &player.field, .Seated) {
			player.sneaking = false
			return true
		}
	}
	return false
}

// One field player's part of the tick, before the drain: the chair, the
// hotbar, the tool, the move and the queued edits and placements, the
// hand crafting. A seated player keeps the look and Open_Aimed alone
// (seated_field_frame); the hand crafting runs on.
tick_field_session_player :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, frame: Input_Frame) -> Player_Events {
	player := &state.players[index]
	frame := frame
	if interact_on_field_chair(state, content, index, frame) {
		frame.just_pressed -= {.Interact}
		frame.pressed -= {.Interact}
	}
	if player.field.seat != .Standing {
		frame = seated_field_frame(frame)
	}
	// The hold or toggle setting applies on the field as in the block
	// world (0218).
	player.sneaking = update_sneaking(player.sneaking, frame)
	resolved := with_sneaking(frame, player.sneaking)
	events := interact_on_field(state, content, index, resolved)
	// Counted as tick_player counts the block world's.
	if events & {.Open_Machine, .Toggled_Switch} != {} {
		record_world_action(&state.records.statistics)
	}
	player.selected_hotbar_slot = cycle_hotbar_slot(player.selected_hotbar_slot, resolved.just_pressed)
	input := field_tick_input(resolved, state.tick_rate)
	update_field_held_tool(player, content, input)
	if queue_field_torch(state, content, index, input) {
		input.held -= {.Dig}
		input.just_pressed -= {.Dig}
	}
	queue_field_player_edit(state, content, index, input)
	if finished, finished_free := advance_crafting(&player.crafting, player.inventory, content.recipes, content.items, state.tick_rate, state.free_crafting); finished != NO_RECIPE {
		record_produced_stacks(&state.records.statistics, content.recipes.recipes[finished].outputs)
		if !finished_free {
			record_consumed_stacks(&state.records.statistics, content.recipes.recipes[finished].inputs)
		}
	}
	return events
}

// A player's field refusal after the drain is told (a Field_Refused
// event the HUD toasts) when it is new against the last tick's, or the
// player pressed Dig or Place this tick: a held Dig refused tick after
// tick tells it once, a press refused again tells it again.
field_refusal_is_news :: proc(refusal, previous: Field_Edit_Refusal, pressed: bool) -> bool {
	return refusal != .None && (refusal != previous || pressed)
}

// Every field player in player order, then the queues drain, then the
// refusals the drain left are told (field_refusal_is_news). inputs[index]
// is players[index]'s; a missing one is no input.
tick_field_session_players :: proc(state: ^Simulation_State, content: Simulation_Content, inputs: []Input_Frame) {
	previous := make([]Field_Edit_Refusal, len(state.players), context.temp_allocator)
	pressed := make([]bool, len(state.players), context.temp_allocator)
	for index in 0 ..< len(state.players) {
		// Only the look turns a player while the world falls (0200, 0223).
		frame := arrival_input(state.field.arrival, index < len(inputs) ? inputs[index] : Input_Frame{})
		previous[index] = state.players[index].field_refusal
		pressed[index] = frame.just_pressed & {.Mine, .Place} != {}
		events := tick_field_session_player(state, content, index, frame)
		for kind in events {
			append(&state.events, Simulation_Event{player = index, kind = kind})
		}
	}
	finish_field_tick(state, content)
	// The pod's doors after every player moved (0222, 0231); never while the
	// world falls, the landing tick included (the arrival lands below,
	// after this step, so the fall still counts here).
	if !field_arrival_falling(state.field.arrival) {
		tick_pod_airlocks(&state.world.entities, content.machines, field_player_capsules(state.players[:], content.field.tuning), content.field.pod_airlock, state.tick)
	}
	for index in 0 ..< len(previous) {
		if refusal := state.players[index].field_refusal; field_refusal_is_news(refusal, previous[index], pressed[index]) {
			counts := index < len(state.field.refused_foundation_counts) ? state.field.refused_foundation_counts[index] : {}
			append(&state.events, Simulation_Event{player = index, kind = .Field_Refused, field_refusal = refusal, needed = counts[0], held = counts[1]})
		}
	}
	// The hit: the pod rests as it hit (0270); a landing in the same tick
	// rests it itself.
	if field_arrival_rests_now(state.field.arrival, state.tick, content.field.pod_rest.settle_ticks) {
		rest_field_pod(state, content)
	}
	// The fall's last tick: it lands, the hatches closed (0200, 0222).
	if field_arrival_due(state.field.arrival, state.tick) {
		land_field_arrival(state, content)
	}
}

// The home spawn.

// The heading at the home towards the first spring (towards +x on a
// planet without one, or with the spring on the home), a unit tangent:
// the chord from the home to the spring normalised before tangent_of,
// whose threshold of a sixteenth of a unit a chord of under 256 m in
// position units fell below (0260), so the heading is the same at every
// radius.
field_home_heading :: proc(planet: Planet, home: [3]i64) -> [3]i64 {
	look := [3]i64{UNIT_VECTOR_ONE, 0, 0}
	if len(planet.springs) > 0 {
		if chord, ok := normalize_fixed(planet_spring_direction(planet.springs[0]) - home); ok {
			look = chord
		}
	}
	return tangent_of(home, look)
}

// The pod's place: the generated surface at the planet's home, which is
// the crater's floor (0199), and the heading its frame takes the yaw step
// of.
field_home_site :: proc(generation: Planet_Generation, planet: Planet) -> (surface: World_Position, heading: [3]i64) {
	home := planet_home_direction(planet.home)
	return field_surface_under(generation, World_Position(fixed_scale(home, generation.radius)), 0), field_home_heading(planet, home)
}

// Without a pod (content that has none): the clearance above the
// generated surface at the home, facing the spring.
field_home_player :: proc(seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player {
	generation := make_planet_generation(seed, planet, spacing_millimetres)
	site, heading := field_home_site(generation, planet)
	feet := field_surface_under(generation, site, millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES))
	return make_field_player(feet, heading)
}

// The centre of the cabin's floor: the record's first open_cells box
// (validate_pod_cabin, the floor before the chair since 0221).
pod_cabin_floor_centre :: proc(frame: Frame, origin: World_Coordinate, pod: Machine, rotation: u8) -> World_Position {
	return pod_box_floor_centre(frame, origin, pod, rotation, pod.open_cells[0])
}

// The centre of the floor of a box of the pod's unrotated footprint: the
// mean of its bottom layer's two corner cells lowered half a pitch along
// the frame's up.
pod_box_floor_centre :: proc(frame: Frame, origin: World_Coordinate, pod: Machine, rotation: u8, box: Cell_Box) -> World_Position {
	first := rotate_footprint_cell({box.from.x, box.from.z}, pod.footprint.x, pod.footprint.z, rotation)
	last := rotate_footprint_cell({box.to.x, box.to.z}, pod.footprint.x, pod.footprint.z, rotation)
	first_centre := frame_cell_centre(frame, origin + {first.x, box.from.y, first.y})
	last_centre := frame_cell_centre(frame, origin + {last.x, box.from.y, last.y})
	half := World_Position(fixed_scale(frame.axes[FRAME_UP], frame_pitch_units(frame) / 2))
	return first_centre + (last_centre - first_centre) / 2 - half
}

// In the cabin of the world's pod, the first alive in pool order: the
// clearance above its floor, facing the door. It reads the saved frame,
// so it holds for a loaded world, a joiner and an old save's pod on its
// pad. found is false without a pod.
field_pod_spawn :: proc(entities: ^Entities, machines: Machine_Registry) -> (player: Field_Player, found: bool) {
	for foundation in entities.foundations.entries {
		if !foundation.alive || machines.machines[foundation.machine].kind != .Pod {
			continue
		}
		frame, frame_found := find_frame(&entities.frames, foundation.frame)
		pod := machines.machines[foundation.machine]
		if !frame_found || pod.open_cell_box_count == 0 {
			return {}, false
		}
		floor := pod_cabin_floor_centre(frame, foundation.origin, pod, foundation.rotation)
		feet := floor + World_Position(fixed_scale(frame.axes[FRAME_UP], millimetres_to_position_units(FIELD_SPAWN_CLEARANCE_MILLIMETRES)))
		return make_field_player(feet, frame.axes[FRAME_FORWARD]), true
	}
	return {}, false
}

// A new player's body: in the pod's cabin, or at the home without a pod.
field_spawn_player :: proc(entities: ^Entities, machines: Machine_Registry, seed: u64, planet: Planet, spacing_millimetres: int) -> Field_Player {
	if player, found := field_pod_spawn(entities, machines); found {
		return player
	}
	return field_home_player(seed, planet, spacing_millimetres)
}

// A new world's field (a session's, the benchmark's): the spacing, the
// simulated set of data/game.sjson, the planet, the pod on the crater's
// floor at the home (place_pod, when the machines have one), the quests'
// reward target (the pod's locker, settle_quest_reward_target), every
// player in its cabin and the water's planet. The world's seed is set
// before.
enable_new_field_world :: proc(state: ^Simulation_State, config: Game_Config, machines: Machine_Registry, field_content: Field_Content, planet: Planet, spacing_millimetres: int) {
	field := &state.field
	field.enabled = true
	field.spacing_millimetres = spacing_millimetres
	field.chunk_set = make_field_chunk_set(config.field_simulation.chunk_radius, config.field_simulation.chunk_margin)
	state.world.planet = planet
	seed := state.world.settings.seed
	site, heading := field_home_site(make_planet_generation(seed, planet, spacing_millimetres), planet)
	place_pod(&state.world.entities, machines, site, heading, field_content.foundation_pitch_millimetres)
	settle_quest_reward_target(&state.quests, &state.records.statistics, &state.world.entities, machines, true)
	for &player in state.players {
		player.field = field_spawn_player(&state.world.entities, machines, seed, planet, spacing_millimetres)
	}
	field.world.water_planet = make_field_water_planet(seed, planet, spacing_millimetres)
	field.felled_trees_recorded = true
}

// The spawn of a field session's new player: the pod's cabin, or its
// chair strapped in while the world falls (0223), the starter kit
// (data/game.sjson, starting_items). The first player of a new world
// and every joining one come through here.
make_field_session_player :: proc(state: ^Simulation_State, content: Simulation_Content, start: Player_Start) -> Player {
	player := make_player(start)
	player.field = field_spawn_player(&state.world.entities, content.machines, state.world.settings.seed, state.world.planet, state.field.spacing_millimetres)
	// The first player of a new world joins inside the fall (0223).
	if field_arrival_falling(state.field.arrival) {
		seat_field_player(&state.world.entities, content.machines, content.field.tuning, &player.field, .Strapped)
	}
	give_starting_items(&player, content.items, content.field.starting_items)
	return player
}
