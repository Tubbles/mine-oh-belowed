package game

// The slot commands (work item 0179): every edit the inventory screen and
// the machine panel make to the player's slots, the hand (Player.held),
// the open machine's slots or an inserter's hand is a Player_Command
// applied at the start of the next tick, as the other screen actions are
// (player_command.odin). The screens show the state after the tick: no
// frame side prediction. The tick checks each command against the state
// it meets (slot_command_stale): the machine is still the player's open
// machine, the slots are in range and the hand and the target slot hold
// the items the screen showed; a stale command changes nothing and raises
// Action_Refused.

#assert(PLAYER_GRID_SLOT_COUNT <= MAXIMUM_CHEST_SLOTS && MAXIMUM_CHEST_SLOTS <= 255)

// What the screen showed when it queued the command: the hand's item and
// the target slot's, NO_ITEM for empty. A press made on a frame older than
// a transfer still on its way (online, the latency window) would
// otherwise act on a stack the screen never showed: pick up where it
// meant to drop, or drop the stack a swap just put in the hand.
// ANY_ITEM is what the screen cannot know: a hand whose pick up is on its
// way (any stack), a slot a drag's drop does not check.
Held_Expectation :: struct {
	hand: Item_Id,
	slot: Item_Id,
}

ANY_ITEM :: Item_Id(NO_ITEM - 1)

// The stack's item, NO_ITEM for an empty one.
shown_item :: proc(stack: Item_Stack) -> Item_Id {
	return stack_is_empty(stack) ? NO_ITEM : stack.item
}

// ANY_ITEM matches any stack in the hand and anything in a slot.
hand_matches :: proc(expected: Item_Id, held: Held_Stack) -> bool {
	if expected == ANY_ITEM {
		return !stack_is_empty(held.stack)
	}
	return shown_item(held.stack) == expected
}

slot_matches :: proc(expected: Item_Id, slot: Item_Stack) -> bool {
	return expected == ANY_ITEM || shown_item(slot) == expected
}

expected_item_valid :: proc(item: Item_Id, items: Item_Registry) -> bool {
	return item == ANY_ITEM || item_valid(item, items, true)
}

expectation_valid :: proc(expects: Held_Expectation, items: Item_Registry) -> bool {
	return expected_item_valid(expects.hand, items) && expected_item_valid(expects.slot, items)
}

// A slot of the player's inventory (machine NO_ENTITY, slot an inventory
// index) or of the player's open machine.
Slot_Command_Target :: struct {
	machine: Entity_Handle,
	slot:    int,
}

// A on a slot, or a pointer drag's drop on it: pick up, drop, merge or
// swap (apply_slot_primary, apply_machine_slot_primary). keeps_origin is
// the drag's drop: what the hand holds afterwards keeps the dragged
// stack's origin, so the Return_Held_Command after it puts a swapped
// stack where the dragged one came from.
Slot_Primary_Command :: struct {
	target:       Slot_Command_Target,
	expects:      Held_Expectation,
	keeps_origin: bool,
}

// L2: half the slot's stack onto the empty hand.
Slot_Split_Command :: struct {
	target:  Slot_Command_Target,
	expects: Held_Expectation,
}

// X with an empty hand: the player's main grid (NO_ENTITY) or a chest's
// slots into the order the screen took (sorted_slot_order), since the
// order follows the display language.
Slot_Sort_Command :: struct {
	machine: Entity_Handle,
	order:   [MAXIMUM_CHEST_SLOTS]u8,
	count:   u8,
}

// The end of the distribute gesture: the hand's stack (of the item hand)
// over the visited machine slots that still take it (distribute_targets,
// finish_distribute).
Distribute_Command :: struct {
	machine: Entity_Handle,
	hand:    Item_Id,
	slots:   [DISTRIBUTE_MAXIMUM_SLOTS]u8,
	count:   u8,
}

// The hand back to its origin slot (return_held_stack): a drag released,
// a slot screen closed.
Return_Held_Command :: struct {
	unused: u8,
}

// Menu_Drop: the hand's stack, or with an empty hand the slot's, onto the
// ground in front of the player (drop_player_stack).
Drop_Stack_Command :: struct {
	slot:    int,
	expects: Held_Expectation,
}

// One step of the quick move (advance_quick_move): into or out of the
// machine, or with NO_ENTITY between the hotbar and the backpack.
Quick_Move_Command :: struct {
	machine: Entity_Handle,
	step:    Quick_Move_Step,
}

Transfer_Button_Command :: struct {
	machine: Entity_Handle,
	button:  Transfer_Button,
}

// The touch row's Transfer all and Transfer all of type, NO_ENTITY in the
// inventory screen.
Grid_Transfer_Command :: struct {
	machine:  Entity_Handle,
	transfer: Grid_Transfer,
}

// An inserter's hand onto the empty cursor (A on the hand slot) or into
// the inventory (the quick move on it).
Inserter_Hand_Command :: struct {
	inserter:       Entity_Handle,
	into_inventory: bool,
}

// The hand and the slot as the frame shows them.
shown_expectation :: proc(held: Held_Stack, slot: Item_Stack) -> Held_Expectation {
	return {hand = shown_item(held.stack), slot = shown_item(slot)}
}

is_slot_command :: proc(command: Player_Command) -> bool {
	#partial switch _ in command {
	case Slot_Primary_Command, Slot_Split_Command, Slot_Sort_Command, Distribute_Command, Return_Held_Command, Drop_Stack_Command, Quick_Move_Command, Transfer_Button_Command, Grid_Transfer_Command, Inserter_Hand_Command:
		return true
	}
	return false
}

// A command of the player not applied yet that matches: any slot command
// (the screens' check is left to the tick), one that may fill the hand (a
// pointer drag whose pick up is on its way keeps dragging) or a return
// of the hand (a closed screen queues it once).
slot_command_pending :: proc(queued: []Queued_Player_Command, unconfirmed: []Player_Command, player: int, matches: proc(command: Player_Command) -> bool) -> bool {
	for entry in queued {
		if entry.player == player && matches(entry.command) {
			return true
		}
	}
	for command in unconfirmed {
		if matches(command) {
			return true
		}
	}
	return false
}

fills_hand :: proc(command: Player_Command) -> bool {
	#partial switch value in command {
	case Slot_Primary_Command:
		return value.expects.hand == NO_ITEM
	case Slot_Split_Command:
		return true
	case Inserter_Hand_Command:
		return !value.into_inventory
	}
	return false
}

// The item a pending pick up puts in the hand, the newest one's;
// ANY_ITEM when none is pending or its item is unknown (an inserter's
// hand). The unconfirmed commands are older than the queued ones.
pending_hand_item :: proc(queued: []Queued_Player_Command, unconfirmed: []Player_Command, player: int) -> Item_Id {
	item := ANY_ITEM
	for command in unconfirmed {
		item = fills_hand(command) ? filled_item(command) : item
	}
	for entry in queued {
		item = entry.player == player && fills_hand(entry.command) ? filled_item(entry.command) : item
	}
	return item
}

filled_item :: proc(command: Player_Command) -> Item_Id {
	#partial switch value in command {
	case Slot_Primary_Command:
		return value.expects.slot
	case Slot_Split_Command:
		return value.expects.slot
	}
	return ANY_ITEM
}

returns_hand :: proc(command: Player_Command) -> bool {
	_, returns := command.(Return_Held_Command)
	return returns
}

// The content side of a slot command (player_command_valid): the enums
// and items it carries.
slot_command_valid :: proc(command: Player_Command, content: Simulation_Content) -> bool {
	#partial switch value in command {
	case Slot_Primary_Command:
		return enum_in_range(value.target.machine.kind) && expectation_valid(value.expects, content.items)
	case Slot_Split_Command:
		return enum_in_range(value.target.machine.kind) && expectation_valid(value.expects, content.items)
	case Slot_Sort_Command:
		return enum_in_range(value.machine.kind) && int(value.count) <= len(value.order)
	case Distribute_Command:
		return enum_in_range(value.machine.kind) && expected_item_valid(value.hand, content.items) && value.count >= 1 && int(value.count) <= len(value.slots)
	case Drop_Stack_Command:
		return expectation_valid(value.expects, content.items)
	case Quick_Move_Command:
		step := value.step
		return enum_in_range(value.machine.kind) && enum_in_range(step.kind) && enum_in_range(step.target.side) && item_valid(step.item, content.items, true)
	case Transfer_Button_Command:
		return enum_in_range(value.machine.kind) && enum_in_range(value.button)
	case Grid_Transfer_Command:
		transfer := value.transfer
		return enum_in_range(value.machine.kind) && enum_in_range(transfer.source) && enum_in_range(transfer.target) && item_valid(transfer.item, content.items, true)
	case Inserter_Hand_Command:
		return enum_in_range(value.inserter.kind)
	}
	return true
}

// The machine a command names is the player's open machine and exists
// (the same generation); NO_ENTITY names the player's own slots.
command_machine_open :: proc(player: Player, entities: ^Entities, machine: Entity_Handle) -> bool {
	return machine == NO_ENTITY || (player.open_machine == machine && entity_common(entities, machine) != nil)
}

// The slots a target indexes: the inventory's or the machine's.
target_slots :: proc(player: Player, entities: ^Entities, machine: Entity_Handle) -> []Item_Stack {
	return machine == NO_ENTITY ? player.inventory.slots : entity_slots(entities, machine)
}

slot_target_valid :: proc(player: Player, entities: ^Entities, target: Slot_Command_Target) -> bool {
	return command_machine_open(player, entities, target.machine) && index_in_range(target.slot, len(target_slots(player, entities, target.machine)))
}

// The slots X sorts: the main grid, or a chest's.
sort_target_slots :: proc(player: Player, entities: ^Entities, machine: Entity_Handle) -> []Item_Stack {
	if machine == NO_ENTITY {
		return inventory_grid(player.inventory)
	}
	return machine.kind == .Chest ? entity_slots(entities, machine) : nil
}

sort_command_order :: proc(command: Slot_Sort_Command) -> []int {
	order := command.order
	return widened_indices(order[:command.count])
}

distribute_command_slots :: proc(command: Distribute_Command) -> []int {
	slots := command.slots
	return widened_indices(slots[:command.count])
}

widened_indices :: proc(indices: []u8) -> []int {
	result := make([]int, len(indices), context.temp_allocator)
	for index, position in indices {
		result[position] = int(index)
	}
	return result
}

// A quick move's side belongs to its screen (the panel's Inventory and
// Machine, the inventory screen's Hotbar and Backpack) and a single
// stack's slot is in range.
quick_move_command_fits :: proc(player: Player, entities: ^Entities, command: Quick_Move_Command) -> bool {
	side := command.step.target.side
	if (command.machine == NO_ENTITY) != (side == .Hotbar || side == .Backpack) {
		return false
	}
	if command.step.kind != .Stack {
		return true
	}
	slots := side == .Machine ? entity_slots(entities, command.machine) : player.inventory.slots
	return index_in_range(command.step.target.slot, len(slots))
}

// The pure check the screens make before queuing and the tick repeats.
slot_command_stale :: proc(player: Player, entities: ^Entities, content: Simulation_Content, command: Player_Command) -> bool {
	empty_hand := stack_is_empty(player.held.stack)
	#partial switch value in command {
	case Slot_Primary_Command:
		return !slot_target_valid(player, entities, value.target) || !shown_as_expected(player, entities, value.target, value.expects)
	case Slot_Split_Command:
		return !slot_target_valid(player, entities, value.target) || !empty_hand || !shown_as_expected(player, entities, value.target, value.expects)
	case Slot_Sort_Command:
		slots := sort_target_slots(player, entities, value.machine)
		return !command_machine_open(player, entities, value.machine) || !empty_hand || slots == nil || !sort_order_matches(slots, sort_command_order(value))
	case Distribute_Command:
		if value.machine == NO_ENTITY || !command_machine_open(player, entities, value.machine) || empty_hand || !hand_matches(value.hand, player.held) {
			return true
		}
		return len(distribute_targets(player.held, entities, content, value)) == 0
	case Drop_Stack_Command:
		if !hand_matches(value.expects.hand, player.held) {
			return true
		}
		return empty_hand && (!index_in_range(value.slot, len(player.inventory.slots)) || !slot_matches(value.expects.slot, player.inventory.slots[value.slot]))
	case Quick_Move_Command:
		return !command_machine_open(player, entities, value.machine) || !quick_move_command_fits(player, entities, value)
	case Transfer_Button_Command:
		return value.machine == NO_ENTITY || !command_machine_open(player, entities, value.machine)
	case Grid_Transfer_Command:
		return !command_machine_open(player, entities, value.machine)
	case Inserter_Hand_Command:
		inserter := value.inserter
		return inserter.kind != .Inserter || !command_machine_open(player, entities, inserter) || (!value.into_inventory && !empty_hand)
	}
	return false
}

// The hand and the target slot hold what the screen showed (a valid
// target).
shown_as_expected :: proc(player: Player, entities: ^Entities, target: Slot_Command_Target, expects: Held_Expectation) -> bool {
	slot := target_slots(player, entities, target.machine)[target.slot]
	return hand_matches(expects.hand, player.held) && slot_matches(expects.slot, slot)
}

// The visited slots that still take the hand's stack: a slot whose filter
// refuses the item (an output, a fuel slot, a recipe changed since the
// gesture) or that holds another item is left out, as the gesture leaves
// it out (slot_takes_distribution). Out of range slots are left out too.
// In the temp allocator.
distribute_targets :: proc(held: Held_Stack, entities: ^Entities, content: Simulation_Content, command: Distribute_Command) -> []int {
	slots := entity_slots(entities, command.machine)
	filters := entity_slot_filters(entities, content, command.machine)
	targets := make([dynamic]int, 0, command.count, context.temp_allocator)
	for slot in distribute_command_slots(command) {
		if slot < len(slots) && slot_takes_distribution(slots[slot], filters[slot], held, content.items, content.recipes) {
			append(&targets, slot)
		}
	}
	return targets[:]
}

// At the start of the tick, in order; a stale command is refused.
apply_slot_command :: proc(state: ^Simulation_State, content: Simulation_Content, player_index: int, command: Player_Command) -> (refused: bool) {
	player := &state.players[player_index]
	entities := &state.world.entities
	if slot_command_stale(player^, entities, content, command) {
		return true
	}
	#partial switch value in command {
	case Slot_Primary_Command:
		player.held = slot_primary_result(player^, entities, content, value)
	case Slot_Split_Command:
		player.held = slot_split_result(player^, entities, value.target)
	case Slot_Sort_Command:
		arrange_slots(sort_target_slots(player^, entities, value.machine), content.items, sort_command_order(value))
	case Distribute_Command:
		targets := distribute_targets(player.held, entities, content, value)
		gesture := Distribute_Gesture{active = true, count = len(targets)}
		copy(gesture.visited[:], targets)
		player.held = finish_distribute(gesture, entity_slots(entities, value.machine), entity_slot_filters(entities, content, value.machine), player.held, content.items, content.recipes)
	case Return_Held_Command:
		player.held = return_held_stack(player.inventory, player.held, content.items)
	case Drop_Stack_Command:
		drop_player_stack(&state.world, &state.records.statistics, content.blocks, player, player_index, value.slot)
	case Quick_Move_Command:
		if value.machine == NO_ENTITY {
			apply_inventory_quick_move(player.inventory, content.items, value.step)
		} else {
			apply_quick_move(entities, content, value.machine, player.inventory, value.step)
		}
	case Transfer_Button_Command:
		apply_transfer_button(entities, content, value.machine, player.inventory, value.button)
	case Grid_Transfer_Command:
		apply_grid_transfer(entities, content, value.machine, player.inventory, value.transfer)
	case Inserter_Hand_Command:
		if value.into_inventory {
			take_inserter_hand(entities, content.items, value.inserter, player.inventory)
		} else if inserter := pool_get(&entities.inserters, value.inserter); inserter != nil {
			inserter.held, player.held = inserter_hand_after_input(inserter.held, player.held, true)
		}
	}
	return false
}

slot_primary_result :: proc(player: Player, entities: ^Entities, content: Simulation_Content, command: Slot_Primary_Command) -> Held_Stack {
	target := command.target
	result: Held_Stack
	if target.machine == NO_ENTITY {
		result = apply_slot_primary(player.inventory, player.held, target.slot, content.items)
	} else {
		filters := entity_slot_filters(entities, content, target.machine)
		result = apply_machine_slot_primary(entity_slots(entities, target.machine), target.slot, filters[target.slot], player.held, content.items, content.recipes)
	}
	if command.keeps_origin && !stack_is_empty(result.stack) {
		result.origin_slot = player.held.origin_slot
	}
	return result
}

// A stack split off a machine slot has no player slot to return to.
slot_split_result :: proc(player: Player, entities: ^Entities, target: Slot_Command_Target) -> Held_Stack {
	if target.machine == NO_ENTITY {
		return apply_slot_split(player.inventory, player.held, target.slot)
	}
	result := apply_slot_split(Inventory{slots = entity_slots(entities, target.machine)}, player.held, target.slot)
	if !stack_is_empty(result.stack) {
		result.origin_slot = MACHINE_SLOT_ORIGIN
	}
	return result
}
