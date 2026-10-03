package game

import "core:slice"
import "core:testing"

simulation_has_refusal :: proc(simulation: ^Simulation_State, player: int) -> bool {
	for event in simulation.events {
		if event.kind == .Action_Refused && event.player == player {
			return true
		}
	}
	return false
}

// A slot transfer queued in a frame changes nothing until the next tick
// applies it (0179).
@(test)
test_a_slot_transfer_applies_at_the_next_tick_and_not_before :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	// The focus is on the selected hotbar slot 0; the tap focuses slot 3.
	tap_widget(audit, &state, inventory_slot_id("hotbar", 3))
	screen_test_frame(audit, &state, {quick_move = true})
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, player.inventory.slots[3], coal)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], EMPTY_STACK)
	run_audit_tick(audit)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], coal)
}

// A chest removed between the frame and the tick: the quick move out of
// it is refused (a toast through Action_Refused) and changes nothing.
@(test)
test_a_slot_command_for_a_removed_machine_is_refused :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player, chest_slots := chest_test_panel(audit, &state)
	chest := player.open_machine
	coal := Item_Stack{test_item(audit.content.items, "coal"), 4}
	chest_slots[0] = coal
	tap_widget(audit, &state, machine_panel_slot_id("chest", 0))
	screen_test_frame(audit, &state, {quick_move = true})
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	inventory_before := make([]Item_Stack, len(player.inventory.slots), context.temp_allocator)
	copy(inventory_before, player.inventory.slots)
	testing.expect(t, remove_entity(&audit.simulation.world.entities, audit.content.machines, chest))
	apply_player_commands(&audit.simulation, audit.content)
	testing.expect(t, simulation_has_refusal(&audit.simulation, 0))
	for slot, index in player.inventory.slots {
		testing.expect_value(t, slot, inventory_before[index])
	}
	testing.expect_value(t, player.held, EMPTY_HELD_STACK)
}

// The screen's own check: a command naming a machine the player has not
// open toasts and never queues.
@(test)
test_a_stale_slot_command_toasts_and_never_queues :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	chest := audit_machine_of_kind(audit, .Chest)
	audit.simulation.players[0].open_machine = NO_ENTITY
	queue_slot_command(&state, audit_screen_context(audit), Transfer_Button_Command{machine = chest, button = .Take_All})
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, len(state.toasts), 1)
}

// The tick checks the hand as the screen saw it: a pick up queued on a
// frame that showed an empty hand is refused once a stack is held.
@(test)
test_a_slot_command_checks_the_hand :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	player := &simulation.players[0]
	coal := Item_Stack{test_item(audit.content.items, "coal"), 3}
	player.held = Held_Stack{stack = coal, origin_slot = 1}
	player.inventory.slots[2] = EMPTY_STACK
	queue_player_command(&simulation.player_commands, 0, Slot_Primary_Command{target = {NO_ENTITY, 2}, expects = {hand = NO_ITEM, slot = NO_ITEM}})
	apply_player_commands(simulation, audit.content)
	testing.expect(t, simulation_has_refusal(simulation, 0))
	testing.expect_value(t, player.held.stack, coal)
	testing.expect_value(t, player.inventory.slots[2], EMPTY_STACK)
	// The same drop with the hand it expects lands.
	queue_player_command(&simulation.player_commands, 0, Slot_Primary_Command{target = {NO_ENTITY, 2}, expects = {hand = coal.item, slot = NO_ITEM}})
	apply_player_commands(simulation, audit.content)
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[2], coal)
}

// A sort whose order no longer names the slots' stacks (one arrived
// since the screen took it) is refused instead of losing the stack.
@(test)
test_a_stale_sort_order_is_refused :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	player := &simulation.players[0]
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	coal := Item_Stack{test_item(audit.content.items, "coal"), 3}
	player.inventory.slots[HOTBAR_SLOT_COUNT + 4] = coal
	sort := slot_sort_command(NO_ENTITY, inventory_grid(player.inventory), audit.item_sort_ranks)
	player.inventory.slots[HOTBAR_SLOT_COUNT + 7] = coal
	queue_player_command(&simulation.player_commands, 0, sort)
	apply_player_commands(simulation, audit.content)
	testing.expect(t, simulation_has_refusal(simulation, 0))
	testing.expect_value(t, inventory_count(player.inventory, coal.item), 6)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT + 4], coal)
}

// Every slot command survives the network codec unchanged: decoded and
// encoded again, it gives the same bytes.
@(test)
test_slot_commands_cross_the_codec :: proc(t: ^testing.T) {
	chest := Entity_Handle{kind = .Chest, index = 7, generation = 2}
	sort := Slot_Sort_Command{machine = chest, count = 2}
	sort.order[0], sort.order[1] = 5, 1
	distribute := Distribute_Command{machine = chest, hand = 3, count = 3}
	distribute.slots[0], distribute.slots[1], distribute.slots[2] = 0, 4, 9
	commands := [?]Player_Command {
		Slot_Primary_Command{target = {chest, 3}, expects = {hand = ANY_ITEM, slot = ANY_ITEM}, keeps_origin = true},
		Slot_Split_Command{target = {NO_ENTITY, 12}, expects = {hand = NO_ITEM, slot = 4}},
		sort,
		distribute,
		Return_Held_Command{},
		Drop_Stack_Command{slot = 4, expects = {hand = NO_ITEM, slot = 5}},
		Quick_Move_Command{machine = chest, step = {kind = .All, target = {.Machine, -1}, item = 3}},
		Transfer_Button_Command{machine = chest, button = .Store_All},
		Grid_Transfer_Command{machine = NO_ENTITY, transfer = {source = .Hotbar, target = .Main, of_type = true, item = 2}},
		Inserter_Hand_Command{inserter = {kind = .Inserter, index = 1, generation = 1}, into_inventory = true},
	}
	for command in commands {
		bytes := make([dynamic]byte, context.temp_allocator)
		encode_player_command(&bytes, command)
		reader := Byte_Reader{data = bytes[:]}
		decoded, ok := decode_player_command(&reader)
		testing.expect(t, ok)
		testing.expect_value(t, reader.offset, len(bytes))
		again := make([dynamic]byte, context.temp_allocator)
		encode_player_command(&again, decoded)
		testing.expect(t, slice.equal(again[:], bytes[:]))
	}
}

// A bool byte other than 0 or 1 is malformed and refused by the decoder.
@(test)
test_a_slot_command_with_a_malformed_bool_is_refused :: proc(t: ^testing.T) {
	commands := [?]Player_Command {
		Slot_Primary_Command{target = {NO_ENTITY, 3}, expects = {hand = NO_ITEM, slot = NO_ITEM}, keeps_origin = true},
		Inserter_Hand_Command{inserter = {kind = .Inserter, index = 1, generation = 1}, into_inventory = true},
	}
	for command in commands {
		bytes := make([dynamic]byte, context.temp_allocator)
		encode_player_command(&bytes, command)
		// The bool is the command's last field.
		bytes[len(bytes) - 1] = 2
		reader := Byte_Reader{data = bytes[:]}
		_, ok := decode_player_command(&reader)
		testing.expect(t, !ok)
	}
}

// Hand X over slot Y: A queues the swap, and Drop pressed before the tick
// (the frame still shows X) is refused, so Y stays in the hand instead of
// going to the ground.
@(test)
test_a_drop_after_a_swap_in_the_same_tick_is_refused :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	player := &simulation.players[0]
	coal := Item_Stack{test_item(audit.content.items, "coal"), 3}
	stone := Item_Stack{test_item(audit.content.items, "stone"), 2}
	player.held = Held_Stack{stack = coal, origin_slot = 1}
	player.inventory.slots[2] = stone
	loose_before := len(simulation.world.entities.loose_items.items)
	commands := inventory_slot_commands(player.inventory, player.held, {activated = 2, focused = 2}, audit.item_sort_ranks)
	queue_player_command(&simulation.player_commands, 0, commands[0])
	drop, drops := drop_stack_command(player^, 2)
	testing.expect(t, drops)
	queue_player_command(&simulation.player_commands, 0, drop)
	apply_player_commands(simulation, audit.content)
	testing.expect(t, simulation_has_refusal(simulation, 0))
	testing.expect_value(t, player.held.stack, stone)
	testing.expect_value(t, player.inventory.slots[2], coal)
	testing.expect_value(t, len(simulation.world.entities.loose_items.items), loose_before)
}

// A distribute over slots whose filters refuse the hand's item (a
// furnace's output slots) is refused; with one slot that takes it, only
// that one gets the stack.
@(test)
test_a_distribute_skips_slots_that_refuse_the_item :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	furnace := audit_machine_of_kind(audit, .Furnace)
	if !testing.expect(t, furnace != NO_ENTITY) {
		return
	}
	player := &simulation.players[0]
	player.open_machine = furnace
	slots := entity_slots(&simulation.world.entities, furnace)
	for &slot in slots {
		slot = EMPTY_STACK
	}
	coal := Item_Stack{test_item(audit.content.items, "coal"), 6}
	player.held = Held_Stack{stack = coal, origin_slot = 0}
	outputs := Distribute_Command{machine = furnace, hand = coal.item, count = 2}
	outputs.slots[0], outputs.slots[1] = FURNACE_OUTPUT_SLOT, FURNACE_BYPRODUCT_SLOT
	queue_player_command(&simulation.player_commands, 0, outputs)
	apply_player_commands(simulation, audit.content)
	testing.expect(t, simulation_has_refusal(simulation, 0))
	testing.expect_value(t, player.held.stack, coal)
	testing.expect(t, slots_empty(slots))
	mixed := Distribute_Command{machine = furnace, hand = coal.item, count = 2}
	mixed.slots[0], mixed.slots[1] = FURNACE_FUEL_SLOT, FURNACE_OUTPUT_SLOT
	queue_player_command(&simulation.player_commands, 0, mixed)
	apply_player_commands(simulation, audit.content)
	testing.expect_value(t, slots[FURNACE_FUEL_SLOT], coal)
	testing.expect_value(t, slots[FURNACE_OUTPUT_SLOT], EMPTY_STACK)
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
}

return_commands_queued :: proc(commands: []Queued_Player_Command) -> int {
	count := 0
	for entry in commands {
		count += returns_hand(entry.command) ? 1 : 0
	}
	return count
}

// A held stack with no room anywhere in the inventory queues no return
// when the screen is closed; with room, one.
@(test)
test_a_full_inventory_queues_no_return :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := &audit.simulation.players[0]
	stone := test_item(audit.content.items, "stone")
	for &slot in player.inventory.slots {
		slot = {stone, u16(item_stack_size(audit.content.items, stone))}
	}
	player.held = Held_Stack{stack = {test_item(audit.content.items, "coal"), 3}, origin_slot = 4}
	player.open_machine = NO_ENTITY
	for _ in 0 ..< 3 {
		screen_test_frame(audit, &state, {})
	}
	testing.expect_value(t, return_commands_queued(audit.simulation.player_commands[:]), 0)
	player.inventory.slots[4] = EMPTY_STACK
	screen_test_frame(audit, &state, {})
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, return_commands_queued(audit.simulation.player_commands[:]), 1)
}
