package game

import "core:testing"

// The bumpers step the inventory tab strip from each of its screens,
// wrapping, by replacing the top screen (work item 0094).
@(test)
test_bumpers_step_the_inventory_tab_strip :: proc(t: ^testing.T) {
	strip := Ui_Rectangle{0, 0, 600, 56}
	Step :: struct {
		from, next, previous: Screen,
	}
	steps := [?]Step {
		{.Inventory, .Recipes, .Technologies},
		{.Recipes, .Technologies, .Inventory},
		{.Technologies, .Inventory, .Recipes},
	}
	for step in steps {
		for input in ([2]Ui_Input{{tab_next = true}, {tab_previous = true}}) {
			state: Ui_State
			// Opened from a lab's panel: Back returns there.
			push_screen(&state.screens, .Machine)
			push_screen(&state.screens, step.from)
			test_ui_frame(&state, input)
			inventory_tabs(&state, strip)
			testing.expect_value(t, top_screen(state.screens), input.tab_next ? step.next : step.previous)
			testing.expect_value(t, state.screens.count, 2)
			testing.expect_value(t, state.screens.screens[0], Screen.Machine)
			// A frame without a bumper keeps the tab.
			test_ui_frame(&state, {})
			inventory_tabs(&state, strip)
			testing.expect_value(t, top_screen(state.screens), input.tab_next ? step.next : step.previous)
			destroy_ui_state(&state)
		}
	}
}

// On the keyboard E is Open_Inventory and Tab_Next: it closes the strip
// from any of its screens instead of stepping.
@(test)
test_open_inventory_closes_the_strip :: proc(t: ^testing.T) {
	strip := Ui_Rectangle{0, 0, 600, 56}
	for screen in inventory_tab_screens {
		state: Ui_State
		push_screen(&state.screens, screen)
		test_ui_frame(&state, {open_inventory = true, tab_next = true})
		inventory_tabs(&state, strip)
		testing.expect_value(t, top_screen(state.screens), screen)
		handle_screen_keys(&state)
		testing.expect_value(t, state.screens.count, 0)
		destroy_ui_state(&state)
	}
}

// A frame in the world forgets the focus of the last screen; a screen
// open keeps it.
@(test)
test_a_frame_without_a_screen_clears_the_focus :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	state.focus = 7
	push_screen(&state.screens, .None)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.focus, 7)
	pop_screen(&state.screens)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.focus, 0)
}

// Work item 0124: the pointer moves stacks by drag and drop. The screen
// frames run at 1920 by 1080 pixels and UI scale 1, so a UI unit is a
// pixel and a mouse position is a pointer position.

pointer_input :: proc(position: [2]f32, down: bool, pressed := false, moved := true) -> Ui_Input {
	return Ui_Input{mouse_position = position, mouse_moved = moved, mouse_pressed = pressed, mouse_down = down}
}

inventory_slot_id :: proc(grid: string, index: int) -> Ui_Id {
	return ui_hash(ui_hash(ui_hash(0, "inventory", -1), grid, -1), "slot", index)
}

// The centre of a widget of the last frame.
widget_centre :: proc(state: Ui_State, id: Ui_Id) -> [2]f32 {
	index := widget_index(state.widgets[:], id)
	assert(index >= 0, "no such widget")
	return rectangle_centre(state.widgets[index].rectangle)
}

// An empty inventory but five coal in hotbar slot 3, the inventory
// screen open and drawn once.
drag_test_inventory :: proc(audit: ^Ui_Audit, state: ^Ui_State, count: u16 = 5) -> ^Player {
	player := &audit.simulation.players[0]
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	player.selected_hotbar_slot = 0
	player.inventory.slots[3] = {test_item(audit.content.items, "coal"), count}
	push_screen(&state.screens, .Inventory)
	screen_test_frame(audit, state, {})
	return player
}

@(test)
test_a_drag_moves_a_stack :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	to := widget_centre(state, inventory_slot_id("grid", 0))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	screen_test_frame(audit, &state, pointer_input(to, true))
	testing.expect_value(t, player.held.stack, coal)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], coal)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

// A drag onto another item swaps the two slots.
@(test)
test_a_drag_onto_another_item_swaps_the_slots :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	stone := Item_Stack{test_item(audit.content.items, "stone"), 2}
	player.inventory.slots[HOTBAR_SLOT_COUNT] = stone
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	to := widget_centre(state, inventory_slot_id("grid", 0))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], coal)
	testing.expect_value(t, player.inventory.slots[3], stone)
}

// A press and release without moving picks nothing up and focuses the slot.
@(test)
test_a_tap_on_a_slot_only_focuses_it :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	slot := inventory_slot_id("hotbar", 3)
	testing.expect(t, state.focus != slot)
	at := widget_centre(state, slot)
	screen_test_frame(audit, &state, pointer_input(at, true, pressed = true, moved = false))
	screen_test_frame(audit, &state, pointer_input(at, false, moved = false))
	testing.expect_value(t, state.focus, slot)
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[3], coal)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

// Resting on a stack for the hold delay splits it and drags the half.
@(test)
test_a_hold_splits_and_drags_the_half :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state, 6)
	coal := player.inventory.slots[3].item
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	to := widget_centre(state, inventory_slot_id("grid", 0))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	for _ in 0 ..< int(TOUCH_HOLD_SECONDS * 60) + 1 {
		screen_test_frame(audit, &state, pointer_input(from, true, moved = false))
	}
	testing.expect_value(t, player.held.stack, Item_Stack{coal, 3})
	testing.expect_value(t, player.inventory.slots[3], Item_Stack{coal, 3})
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], Item_Stack{coal, 3})
	testing.expect_value(t, player.inventory.slots[3], Item_Stack{coal, 3})
}

// A drag released off the slots returns the stack and keeps the screen.
@(test)
test_a_drag_released_off_the_slots_returns_the_stack :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	outside := [2]f32{100, 400}
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(outside, true))
	testing.expect_value(t, player.held.stack, coal)
	screen_test_frame(audit, &state, pointer_input(outside, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[3], coal)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

// A tap off the panel closes the screen as Back does; a tap on the
// panel or a press dragged off it does not.
@(test)
test_a_tap_outside_the_panel_closes_the_screen :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	drag_test_inventory(audit, &state)
	outside := [2]f32{100, 400}
	inside := widget_centre(state, inventory_slot_id("grid", 0))
	screen_test_frame(audit, &state, pointer_input(inside, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(outside, true))
	screen_test_frame(audit, &state, pointer_input(outside, false, moved = false))
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	state.sound_events = {}
	screen_test_frame(audit, &state, pointer_input(outside, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(outside, false, moved = false))
	testing.expect_value(t, state.screens.count, 0)
	// With B's sound.
	testing.expect(t, .Back in state.sound_events)
}

// The machine panels share the slot code: a drag from the hotbar into a
// chest.
@(test)
test_a_drag_moves_a_stack_into_a_chest :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	simulation := &audit.simulation
	chest := audit_machine_of_kind(audit, .Chest)
	testing.expect(t, chest != NO_ENTITY)
	player := &simulation.players[0]
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	coal := Item_Stack{test_item(audit.content.items, "coal"), 5}
	player.inventory.slots[3] = coal
	slots := entity_slots(&simulation.world.entities, chest)
	for &slot in slots {
		slot = EMPTY_STACK
	}
	player.open_machine = chest
	push_screen(&state.screens, .Machine)
	screen_test_frame(audit, &state, {})
	machine_panel := ui_hash(0, "machine", -1)
	from := widget_centre(state, ui_hash(ui_hash(machine_panel, "hotbar", -1), "slot", 3))
	to := widget_centre(state, ui_hash(ui_hash(ui_hash(machine_panel, "machine_slots", -1), "chest", -1), "slot", 0))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, slots[0], coal)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
}

// A finger's dragged stack sits a slot height above it, a mouse's under it.
@(test)
test_held_stack_sits_above_a_finger :: proc(t: ^testing.T) {
	state := Ui_State{pointer = {500, 400}, pointer_source = .Mouse}
	defer destroy_ui_state(&state)
	half := f32(UI_SLOT_SIZE / 2)
	under, found := held_stack_rectangle(&state)
	testing.expect(t, found)
	testing.expect_value(t, under, Ui_Rectangle{500 - half, 400 - half, UI_SLOT_SIZE, UI_SLOT_SIZE})
	state.pointer_source = .Touch
	above, _ := held_stack_rectangle(&state)
	testing.expect_value(t, above, Ui_Rectangle{500 - half, 400 - half - UI_SLOT_SIZE, UI_SLOT_SIZE, UI_SLOT_SIZE})
}

// The mouse's pointer is a finger when the frame says so.
@(test)
test_a_touch_pointer_is_the_touch_source :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	test_ui_frame(&state, {mouse_position = {10, 10}, mouse_moved = true, pointer_is_touch = true})
	testing.expect_value(t, state.pointer_source, Pointer_Source.Touch)
	test_ui_frame(&state, {mouse_position = {20, 10}, mouse_moved = true})
	testing.expect_value(t, state.pointer_source, Pointer_Source.Mouse)
}

// The first machine panel of a kind in the audit's world.
audit_machine_of_kind :: proc(audit: ^Ui_Audit, kind: Machine_Kind) -> Entity_Handle {
	world := &audit.simulation.world
	for handle in machines_with_panels(world, audit.content) {
		common := entity_common(&world.entities, handle)
		if audit.content.machines.machines[common.machine].kind == kind {
			return handle
		}
	}
	return NO_ENTITY
}

// A drag out of a set filter slot lifts nothing, so its release over
// another stack moves nothing.
@(test)
test_a_drag_from_a_filter_slot_moves_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	simulation := &audit.simulation
	handle := audit_machine_of_kind(audit, .Splitter)
	testing.expect(t, handle != NO_ENTITY)
	splitter := pool_get(&simulation.world.entities.splitters, handle)
	coal := test_item(audit.content.items, "coal")
	splitter.filter = coal
	player := &simulation.players[0]
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	stone := Item_Stack{test_item(audit.content.items, "stone"), 2}
	player.inventory.slots[3] = stone
	player.open_machine = handle
	push_screen(&state.screens, .Machine)
	screen_test_frame(audit, &state, {})
	machine_panel := ui_hash(0, "machine", -1)
	from := widget_centre(state, ui_hash(ui_hash(machine_panel, "machine_slots", -1), "filter", 0))
	to := widget_centre(state, ui_hash(ui_hash(machine_panel, "hotbar", -1), "slot", 3))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[3], stone)
	testing.expect_value(t, splitter.filter, coal)
}

// A slot emptied between the press and the drag's start (a machine used
// it up) lifts nothing, so the release moves nothing.
@(test)
test_a_slot_emptied_before_the_drag_moves_nothing :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	stone := Item_Stack{test_item(audit.content.items, "stone"), 2}
	player.inventory.slots[HOTBAR_SLOT_COUNT] = stone
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	to := widget_centre(state, inventory_slot_id("grid", 0))
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	player.inventory.slots[3] = EMPTY_STACK
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], stone)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
}

// Left Control with a click quick moves the pressed slot, also when the
// focus is elsewhere, and starts no drag.
@(test)
test_a_left_control_click_quick_moves_the_pressed_slot :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := player.inventory.slots[3]
	slot := inventory_slot_id("hotbar", 3)
	testing.expect(t, state.focus != slot)
	at := widget_centre(state, slot)
	to := widget_centre(state, inventory_slot_id("grid", 4))
	click := pointer_input(at, true, pressed = true, moved = false)
	click.quick_move_modifier = true
	screen_test_frame(audit, &state, click)
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], coal)
	screen_test_frame(audit, &state, pointer_input(to, true))
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect_value(t, player.held.stack, EMPTY_STACK)
	testing.expect_value(t, player.inventory.slots[HOTBAR_SLOT_COUNT], coal)
}

// Confirm sounds on the pick up and on the drop, not on a tap.
@(test)
test_a_drag_sounds_on_the_pick_up_and_the_drop :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	drag_test_inventory(audit, &state)
	from := widget_centre(state, inventory_slot_id("hotbar", 3))
	to := widget_centre(state, inventory_slot_id("grid", 0))
	state.sound_events = {}
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true, moved = false))
	screen_test_frame(audit, &state, pointer_input(from, false, moved = false))
	testing.expect(t, .Confirm not_in state.sound_events)
	screen_test_frame(audit, &state, pointer_input(from, true, pressed = true))
	testing.expect(t, .Confirm not_in state.sound_events)
	screen_test_frame(audit, &state, pointer_input(to, true))
	testing.expect(t, .Confirm in state.sound_events)
	state.sound_events = {}
	screen_test_frame(audit, &state, pointer_input(to, true))
	testing.expect(t, .Confirm not_in state.sound_events)
	screen_test_frame(audit, &state, pointer_input(to, false, moved = false))
	testing.expect(t, .Confirm in state.sound_events)
}
