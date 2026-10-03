package game

import "platform"

// The player command list (work items 0166 and 0177): every write into the
// simulation from outside the tick is a command on
// Simulation_State.player_commands, applied in order at the start of the
// next tick (apply_player_commands, from simulation_tick). The screens
// queue instead of writing, after the same pure refusal check the tick
// makes, so a refused action toasts in the frame and never queues; the
// lockstep driver (lockstep.odin) carries the local player's commands to
// every machine in its input record. A chunk the streaming workers
// generated arrives as a Chunk_Ready_Command and waits in
// Simulation_State.arrived_chunks until the simulated chunk set takes it
// (simulation_chunk_set.odin). The slot transfers of the inventory screen
// and the machine panel are commands too (player_command_slots.odin). The
// list is not saved.

Research_Command :: struct {
	technology: int,
}

Craft_Command :: struct {
	recipe: int,
	count:  int,
}

// Cancels the newest hand craft.
Cancel_Craft_Command :: struct {
	unused: u8,
}

Assembler_Recipe_Command :: struct {
	assembler: Entity_Handle,
	recipe:    int,
}

Power_Switch_Command :: struct {
	switch_handle: Entity_Handle,
}

// The launch pad panel's Assemble button: a refusal is counted in the
// statistics like a press today, so the press queues even when the screen
// toasts it.
Assembly_Command :: struct {
	pad: Entity_Handle,
}

Launch_Command :: struct {
	pad: Entity_Handle,
}

Catalogue_Order_Command :: struct {
	entry:         int,
	survey_centre: World_Coordinate,
}

// The filter of a filter inserter or a splitter, NO_ITEM to clear it.
Machine_Filter_Command :: struct {
	machine: Entity_Handle,
	filter:  Item_Id,
}

Splitter_Priorities_Command :: struct {
	splitter: Entity_Handle,
	input:    Splitter_Priority,
	output:   Splitter_Priority,
}

Splitter_Side_Command :: struct {
	splitter: Entity_Handle,
	side:     Splitter_Side,
}

Hotbar_Slot_Command :: struct {
	slot: int,
}

// A machine panel closed: the player's open_machine forgets the machine,
// unless another one was opened since.
Close_Machine_Command :: struct {
	machine: Entity_Handle,
}

// The F-key debug edits (apply_debug_actions in loop.odin).
Debug_Remove_Block_Command :: struct {
	counter: u64,
}

Debug_Drop_Item_Command :: struct {
	unused: u8,
}

// A player joining the session gets a new entry at the start position
// (lockstep.odin). The command's player is the new entry's index, which
// must be the array's length.
Add_Player_Command :: struct {
	start: Player_Start,
}

// A generated chunk from the streaming workers, owned by the command
// until the simulated chunk set takes it.
Chunk_Ready_Command :: struct {
	result: Chunk_Job_Result,
}

Player_Command :: union {
	Research_Command,
	Craft_Command,
	Cancel_Craft_Command,
	Assembler_Recipe_Command,
	Power_Switch_Command,
	Assembly_Command,
	Launch_Command,
	Catalogue_Order_Command,
	Machine_Filter_Command,
	Splitter_Priorities_Command,
	Splitter_Side_Command,
	Hotbar_Slot_Command,
	Close_Machine_Command,
	Debug_Remove_Block_Command,
	Debug_Drop_Item_Command,
	Developer_Request,
	Add_Player_Command,
	Chunk_Ready_Command,
	// The slot commands (player_command_slots.odin).
	Slot_Primary_Command,
	Slot_Split_Command,
	Slot_Sort_Command,
	Distribute_Command,
	Return_Held_Command,
	Drop_Stack_Command,
	Quick_Move_Command,
	Transfer_Button_Command,
	Grid_Transfer_Command,
	Inserter_Hand_Command,
}

// player indexes the simulation's players; a chunk arrival has no player
// (NO_PLAYER).
Queued_Player_Command :: struct {
	player:  int,
	command: Player_Command,
}

NO_PLAYER :: -1

queue_player_command :: proc(list: ^[dynamic]Queued_Player_Command, player: int, command: Player_Command) {
	if list != nil {
		append(list, Queued_Player_Command{player = player, command = command})
	}
}

// A chunk arrival stays on this machine; every other command is the
// player's and crosses the network in its input record.
command_is_relayed :: proc(command: Player_Command) -> bool {
	_, chunk := command.(Chunk_Ready_Command)
	return !chunk
}

destroy_player_command :: proc(command: Player_Command) {
	if ready, is_chunk := command.(Chunk_Ready_Command); is_chunk {
		free_job_result(ready.result)
	}
}

destroy_player_commands :: proc(list: ^[dynamic]Queued_Player_Command) {
	for queued in list {
		destroy_player_command(queued.command)
	}
	delete(list^)
}

// Moves the chunk arrivals into arrived_chunks and leaves the rest of the
// list in order. A second arrival of one coordinate replaces the first.
stage_chunk_arrivals :: proc(state: ^Simulation_State) {
	kept := 0
	for queued in state.player_commands {
		ready, is_chunk := queued.command.(Chunk_Ready_Command)
		if !is_chunk {
			state.player_commands[kept] = queued
			kept += 1
			continue
		}
		if previous, found := state.arrived_chunks[ready.result.coordinate]; found {
			free_job_result(previous)
		}
		state.arrived_chunks[ready.result.coordinate] = ready.result
	}
	resize(&state.player_commands, kept)
}

// At the start of a tick, oldest first. A command of a player the
// simulation does not have is dropped.
apply_player_commands :: proc(state: ^Simulation_State, content: Simulation_Content) {
	stage_chunk_arrivals(state)
	for queued in state.player_commands {
		if _, adds := queued.command.(Add_Player_Command); !adds && (queued.player < 0 || queued.player >= len(state.players)) {
			continue
		}
		apply_player_command(state, content, queued)
	}
	clear(&state.player_commands)
}

apply_player_command :: proc(state: ^Simulation_State, content: Simulation_Content, queued: Queued_Player_Command) {
	if !player_command_valid(queued.command, content) {
		platform.log_printf("error: a command of player %d names an index this build does not have, refused: %v", queued.player, queued.command)
		append(&state.events, Simulation_Event{player = queued.player, kind = .Action_Refused})
		return
	}
	refused := false
	switch command in queued.command {
	case Developer_Request:
		apply_developer_command(state, content, queued.player, command)
	case Add_Player_Command:
		add_player_entry(state, content, queued.player, command.start)
	case Chunk_Ready_Command:
	case Research_Command:
		refused = queue_research(&state.records.research, content.technologies, state.unlocks, command.technology) != .None
	case Craft_Command:
		player := &state.players[queued.player]
		refusal, _ := queue_crafts(&player.crafting, player.inventory, content.recipes, state.unlocks, command.recipe, command.count)
		refused = refusal != .None
	case Cancel_Craft_Command:
		player := &state.players[queued.player]
		if player.crafting.count > 0 && !cancel_last_craft(&player.crafting, player.inventory, content.recipes, content.items) {
			append(&state.events, Simulation_Event{player = queued.player, kind = .Inventory_Full})
		}
	case Assembler_Recipe_Command:
		refused = apply_assembler_recipe_command(state, content, queued.player, command)
	case Power_Switch_Command:
		toggle_power_switch(&state.world.entities, content.machines, command.switch_handle)
	case Assembly_Command:
		apply_assembly_command(state, content, command.pad)
	case Launch_Command:
		apply_launch_command(state, content, command.pad)
	case Catalogue_Order_Command:
		refused = !order_from_catalogue(&state.records, content.contracts, command.entry, command.survey_centre)
	case Machine_Filter_Command:
		apply_machine_filter(&state.world.entities, content.machines, command.machine, command.filter)
	case Splitter_Priorities_Command:
		if splitter := pool_get(&state.world.entities.splitters, command.splitter); splitter != nil {
			splitter.input_priority, splitter.output_priority = command.input, command.output
		}
	case Splitter_Side_Command:
		if splitter := pool_get(&state.world.entities.splitters, command.splitter); splitter != nil {
			splitter.filter_side = command.side
		}
	case Hotbar_Slot_Command:
		state.players[queued.player].selected_hotbar_slot = clamp(command.slot, 0, HOTBAR_SLOT_COUNT - 1)
	case Close_Machine_Command:
		player := &state.players[queued.player]
		if player.open_machine == command.machine {
			player.open_machine = NO_ENTITY
		}
	case Debug_Remove_Block_Command:
		eye := player_eye(state.players[queued.player].position)
		debug_remove_block(&state.world, content.blocks, eye, command.counter)
	case Debug_Drop_Item_Command:
		debug_drop_item_on_belt(&state.world, content, state.players[queued.player])
	case Slot_Primary_Command, Slot_Split_Command, Slot_Sort_Command, Distribute_Command, Return_Held_Command, Drop_Stack_Command, Quick_Move_Command, Transfer_Button_Command, Grid_Transfer_Command, Inserter_Hand_Command:
		refused = apply_slot_command(state, content, queued.player, queued.command)
	}
	if refused {
		append(&state.events, Simulation_Event{player = queued.player, kind = .Action_Refused})
	}
}

// Logged like the requests the Developer screen queued before 0166.
apply_developer_command :: proc(state: ^Simulation_State, content: Simulation_Content, player: int, request: Developer_Request) {
	before := movement_toggles(state.players[player])
	if problem := serve_developer_request(state, content, request, player); problem != "" {
		platform.log_printf("developer: %v refused: %s", request.action, problem)
	}
	log_movement_toggles(before, state.players[player], "a developer request", state.tick)
}

// Only at the end of the array, so every machine numbers the players
// alike.
add_player_entry :: proc(state: ^Simulation_State, content: Simulation_Content, index: int, start: Player_Start) {
	if index != len(state.players) {
		platform.log_printf("error: player %d cannot join as entry %d of %d", index, index, len(state.players))
		return
	}
	append(&state.players, make_player(start))
	platform.log_printf("simulation: player %d joined at tick %d", index, state.tick)
}

apply_assembler_recipe_command :: proc(state: ^Simulation_State, content: Simulation_Content, player: int, command: Assembler_Recipe_Command) -> (refused: bool) {
	assembler := pool_get(&state.world.entities.assemblers, command.assembler)
	if assembler == nil {
		return true
	}
	machine := content.machines.machines[assembler.machine]
	return change_assembler_recipe(assembler, machine, state.players[player].inventory, content.items, content.recipes, command.recipe) != .None
}

// The refusal is counted as the panel's press always was.
apply_assembly_command :: proc(state: ^Simulation_State, content: Simulation_Content, handle: Entity_Handle) {
	pad := pool_get(&state.world.entities.launch_pads, handle)
	if pad == nil {
		return
	}
	machine := content.machines.machines[pad.machine]
	record_launch_refusal(&state.records.statistics, assembly_refusal(pad^, machine))
	start_assembly(pad, machine)
}

apply_launch_command :: proc(state: ^Simulation_State, content: Simulation_Content, handle: Entity_Handle) {
	pad := pool_get(&state.world.entities.launch_pads, handle)
	if pad == nil {
		return
	}
	record_launch_refusal(&state.records.statistics, launch_refusal(pad, content.machines.machines[pad.machine]))
	request_launch(&state.world.entities, handle)
}

// A filter inserter's or a splitter's filter, as set_filter_for_developer
// sets it by cell.
apply_machine_filter :: proc(entities: ^Entities, machines: Machine_Registry, handle: Entity_Handle, filter: Item_Id) {
	if inserter := pool_get(&entities.inserters, handle); inserter != nil && machines.machines[inserter.machine].filter_slot_count > 0 {
		inserter.filter = filter
	} else if splitter := pool_get(&entities.splitters, handle); splitter != nil {
		splitter.filter = filter
	}
}

// A screen's pending state: the player's commands in the frame's queue
// (queued) and the local player's not applied yet (unconfirmed: held for
// the next record or in records not run, lockstep_unconfirmed_commands).

pending_developer_toggles :: proc(queued: []Queued_Player_Command, unconfirmed: []Player_Command, player: int, action: Developer_Action) -> int {
	count := 0
	for entry in queued {
		if entry.player == player && is_developer_toggle(entry.command, action) {
			count += 1
		}
	}
	for command in unconfirmed {
		count += is_developer_toggle(command, action) ? 1 : 0
	}
	return count
}

is_developer_toggle :: proc(command: Player_Command, action: Developer_Action) -> bool {
	request, is_request := command.(Developer_Request)
	return is_request && request.action == action
}

close_machine_pending :: proc(queued: []Queued_Player_Command, unconfirmed: []Player_Command, player: int) -> bool {
	for entry in queued {
		if _, closes := entry.command.(Close_Machine_Command); closes && entry.player == player {
			return true
		}
	}
	for command in unconfirmed {
		if _, closes := command.(Close_Machine_Command); closes {
			return true
		}
	}
	return false
}

// Every index and enum a command carries is one this build's content has:
// a record from a machine with other data (or a malformed one) is
// refused instead of indexing past a table. Entity handles are checked
// where they are used (pool_get).
player_command_valid :: proc(command: Player_Command, content: Simulation_Content) -> bool {
	switch value in command {
	case Research_Command:
		return index_in_range(value.technology, len(content.technologies.technologies))
	case Craft_Command:
		return index_in_range(value.recipe, len(content.recipes.recipes)) && value.count >= 1 && value.count <= MAXIMUM_CRAFT_COMMAND_COUNT
	case Assembler_Recipe_Command:
		return value.recipe == NO_RECIPE || index_in_range(value.recipe, len(content.recipes.recipes))
	case Catalogue_Order_Command:
		return index_in_range(value.entry, len(content.contracts.catalogue))
	case Machine_Filter_Command:
		return item_valid(value.filter, content.items, true)
	case Splitter_Priorities_Command:
		return enum_in_range(value.input) && enum_in_range(value.output)
	case Splitter_Side_Command:
		return enum_in_range(value.side)
	case Developer_Request:
		return developer_request_valid(value, content)
	case Slot_Primary_Command, Slot_Split_Command, Slot_Sort_Command, Distribute_Command, Return_Held_Command, Drop_Stack_Command, Quick_Move_Command, Transfer_Button_Command, Grid_Transfer_Command, Inserter_Hand_Command:
		return slot_command_valid(value, content)
	case Cancel_Craft_Command, Power_Switch_Command, Assembly_Command, Launch_Command, Hotbar_Slot_Command, Close_Machine_Command, Debug_Remove_Block_Command, Debug_Drop_Item_Command, Add_Player_Command, Chunk_Ready_Command:
		return true
	}
	return false
}

// A craft command's count: far above what an inventory can feed.
MAXIMUM_CRAFT_COMMAND_COUNT :: 100_000

index_in_range :: proc(index, count: int) -> bool {
	return index >= 0 && index < count
}

enum_in_range :: proc(value: $T) -> bool {
	return value >= min(T) && value <= max(T)
}

item_valid :: proc(item: Item_Id, items: Item_Registry, none_allowed: bool) -> bool {
	return (none_allowed && item == NO_ITEM) || int(item) < len(items.items)
}

grant_valid :: proc(grant: Developer_Grant, items: Item_Registry) -> bool {
	return item_valid(grant.item, items, false) && grant.count >= 1 && grant.count <= MAXIMUM_DEVELOPER_GRANT_COUNT
}

developer_request_valid :: proc(request: Developer_Request, content: Simulation_Content) -> bool {
	if !enum_in_range(request.action) {
		return false
	}
	switch request.action {
	case .Give_Kit:
		return request.chapter >= 1 && request.chapter <= len(content.developer_kits.kits)
	case .Give_Item, .Take_Item, .Insert_Items:
		return grant_valid(request.grant, content.items)
	case .Complete_Quests_To_Chapter:
		return request.chapter >= 1 && request.chapter <= len(content.quests.chapters) + 1
	case .Set_Time_Of_Day:
		return enum_in_range(request.time_of_day)
	case .Research_Technology:
		return index_in_range(request.technology, len(content.technologies.technologies))
	case .Place_Machine:
		return index_in_range(int(request.machine), len(content.machines.machines)) && request.rotation < 8
	case .Set_Block:
		return index_in_range(int(request.block), len(content.blocks.definitions))
	case .Set_Recipe:
		return request.recipe == NO_RECIPE || index_in_range(request.recipe, len(content.recipes.recipes))
	case .Set_Filter:
		return item_valid(request.filter, content.items, true)
	case .Toggle_Fly_Mode, .Toggle_No_Clip, .Unlock_All, .Teleport, .Toggle_Cheat_Speed, .Add_Vein, .Remove_At, .Finish_Active_Quest:
		return true
	}
	return false
}
