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

// Work item 0125: the touch row of the slot screens.

touch_input :: proc(position: [2]f32, down: bool, pressed := false, moved := true) -> Ui_Input {
	input := pointer_input(position, down, pressed, moved)
	input.pointer_is_touch = true
	return input
}

// A finger's press and release on a widget of the last frame.
tap_widget :: proc(audit: ^Ui_Audit, state: ^Ui_State, id: Ui_Id) {
	at := widget_centre(state^, id)
	screen_test_frame(audit, state, touch_input(at, true, pressed = true))
	screen_test_frame(audit, state, touch_input(at, false, moved = false))
}

slot_button_id :: proc(key: string) -> Ui_Id {
	return ui_hash(0, text(key), -1)
}

glyph_bar_draws_glyphs :: proc(commands: []Draw_Command) -> bool {
	for command in commands {
		if command.panel == UI_GLYPH_BAR_PANEL && command.kind == .Ui_Icon {
			return true
		}
	}
	return false
}

// The chest panel open over an empty inventory and an empty chest.
chest_test_panel :: proc(audit: ^Ui_Audit, state: ^Ui_State) -> (player: ^Player, chest_slots: []Item_Stack) {
	simulation := &audit.simulation
	chest := audit_machine_of_kind(audit, .Chest)
	assert(chest != NO_ENTITY, "no chest")
	player = &simulation.players[0]
	for &slot in player.inventory.slots {
		slot = EMPTY_STACK
	}
	player.held = EMPTY_HELD_STACK
	player.selected_hotbar_slot = 0
	chest_slots = entity_slots(&simulation.world.entities, chest)
	for &slot in chest_slots {
		slot = EMPTY_STACK
	}
	player.open_machine = chest
	push_screen(&state.screens, .Machine)
	screen_test_frame(audit, state, {})
	return player, chest_slots
}

machine_panel_slot_id :: proc(grid: string, index: int) -> Ui_Id {
	machine_panel := ui_hash(0, "machine", -1)
	if grid == "chest" {
		return ui_hash(ui_hash(ui_hash(machine_panel, "machine_slots", -1), "chest", -1), "slot", index)
	}
	return ui_hash(ui_hash(machine_panel, grid, -1), "slot", index)
}

@(test)
test_the_touch_row_replaces_the_glyph_bar :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	for screen in ([2]Screen{.Inventory, .Machine}) {
		state := Ui_State{theme = audit.theme}
		if screen == .Inventory {
			drag_test_inventory(audit, &state)
		} else {
			chest_test_panel(audit, &state)
		}
		screen_test_frame(audit, &state, {pointer_is_touch = true})
		testing.expect(t, widget_index(state.widgets[:], slot_button_id("slot_button_transfer_all_of_type")) >= 0)
		testing.expect(t, !glyph_bar_draws_glyphs(state.draw_list[:]))
		screen_test_frame(audit, &state, {device = .Gamepad, device_seen = true})
		testing.expect(t, widget_index(state.widgets[:], slot_button_id("slot_button_transfer_all_of_type")) < 0)
		testing.expect(t, glyph_bar_draws_glyphs(state.draw_list[:]))
		destroy_ui_state(&state)
	}
}

// In the inventory screen: Split halves the active stack onto the
// cursor, Sort sorts the main grid from the main grid and from the
// hotbar, which keeps its order, and the transfers move between the
// hotbar and the main grid.
@(test)
test_the_touch_row_in_the_inventory :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := test_item(audit.content.items, "coal")
	stone := test_item(audit.content.items, "stone")
	slots := player.inventory.slots
	slots[HOTBAR_SLOT_COUNT + 4] = {stone, 2}
	slots[HOTBAR_SLOT_COUNT + 6] = {coal, 1}
	tap_widget(audit, &state, inventory_slot_id("hotbar", 3))
	tap_widget(audit, &state, slot_button_id("slot_button_split"))
	testing.expect_value(t, player.held.stack, Item_Stack{coal, 3})
	testing.expect_value(t, slots[3], Item_Stack{coal, 2})
	player.held = EMPTY_HELD_STACK
	slots[3] = {coal, 5}
	// The hotbar is active: Sort sorts the main grid, the hotbar keeps
	// its order.
	slots[5] = {stone, 1}
	tap_widget(audit, &state, slot_button_id("slot_button_sort"))
	testing.expect(t, !stack_is_empty(slots[HOTBAR_SLOT_COUNT]))
	testing.expect(t, !stack_is_empty(slots[HOTBAR_SLOT_COUNT + 1]))
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 4], EMPTY_STACK)
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 6], EMPTY_STACK)
	testing.expect_value(t, slots[3], Item_Stack{coal, 5})
	testing.expect_value(t, slots[5], Item_Stack{stone, 1})
	// Of type: the hotbar's coal onto the main grid's coal, the stone stays.
	tap_widget(audit, &state, slot_button_id("slot_button_transfer_all_of_type"))
	testing.expect_value(t, slots[3], EMPTY_STACK)
	testing.expect_value(t, slots[5], Item_Stack{stone, 1})
	testing.expect_value(t, inventory_count({slots = slots[HOTBAR_SLOT_COUNT:]}, coal), 6)
	// The main grid is active: Sort sorts it.
	slots[HOTBAR_SLOT_COUNT + 9] = slots[HOTBAR_SLOT_COUNT]
	slots[HOTBAR_SLOT_COUNT] = EMPTY_STACK
	tap_widget(audit, &state, inventory_slot_id("grid", 4))
	tap_widget(audit, &state, slot_button_id("slot_button_sort"))
	testing.expect(t, !stack_is_empty(slots[HOTBAR_SLOT_COUNT]))
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 9], EMPTY_STACK)
	testing.expect_value(t, slots[5], Item_Stack{stone, 1})
	// Transfer all: the main grid into the hotbar.
	tap_widget(audit, &state, slot_button_id("slot_button_transfer_all"))
	testing.expect(t, slots_empty(inventory_grid(player.inventory)))
	testing.expect_value(t, inventory_count(player.inventory, coal), 6)
	testing.expect_value(t, inventory_count(player.inventory, stone), 3)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

// X in a chest panel sorts the grid holding the focus, not the other.
@(test)
test_sort_touches_only_the_active_grid :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player, chest_slots := chest_test_panel(audit, &state)
	coal := test_item(audit.content.items, "coal")
	slots := player.inventory.slots
	slots[HOTBAR_SLOT_COUNT + 5] = {coal, 1}
	chest_slots[4] = {coal, 2}
	tap_widget(audit, &state, machine_panel_slot_id("grid", 0))
	screen_test_frame(audit, &state, {context_action = true})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT], Item_Stack{coal, 1})
	testing.expect_value(t, chest_slots[4], Item_Stack{coal, 2})
	slots[HOTBAR_SLOT_COUNT + 5] = {coal, 3}
	tap_widget(audit, &state, machine_panel_slot_id("chest", 0))
	screen_test_frame(audit, &state, {context_action = true})
	testing.expect_value(t, chest_slots[0], Item_Stack{coal, 2})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 5], Item_Stack{coal, 3})
	// From the hotbar X sorts the main grid, not the chest.
	chest_slots[0], chest_slots[4] = EMPTY_STACK, {coal, 2}
	tap_widget(audit, &state, machine_panel_slot_id("hotbar", 0))
	screen_test_frame(audit, &state, {context_action = true})
	// The coal of the first sort and this one merge.
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT], Item_Stack{coal, 4})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 5], EMPTY_STACK)
	testing.expect_value(t, chest_slots[4], Item_Stack{coal, 2})
}

// In a chest panel the hotbar and the main grid transfer into the chest,
// the chest into the main grid; Split and Sort act on the chest's slot.
@(test)
test_the_touch_row_in_a_chest_panel :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player, chest_slots := chest_test_panel(audit, &state)
	coal := test_item(audit.content.items, "coal")
	stone := test_item(audit.content.items, "stone")
	slots := player.inventory.slots
	slots[2] = {coal, 4}
	slots[HOTBAR_SLOT_COUNT + 1] = {stone, 3}
	slots[HOTBAR_SLOT_COUNT + 2] = {coal, 1}
	tap_widget(audit, &state, machine_panel_slot_id("hotbar", 2))
	tap_widget(audit, &state, slot_button_id("slot_button_transfer_all"))
	testing.expect(t, slots_empty(inventory_hotbar(player.inventory)))
	testing.expect_value(t, chest_slots[0], Item_Stack{coal, 4})
	tap_widget(audit, &state, machine_panel_slot_id("grid", 2))
	tap_widget(audit, &state, slot_button_id("slot_button_transfer_all_of_type"))
	testing.expect_value(t, chest_slots[0], Item_Stack{coal, 5})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 1], Item_Stack{stone, 3})
	tap_widget(audit, &state, machine_panel_slot_id("chest", 0))
	tap_widget(audit, &state, slot_button_id("slot_button_split"))
	testing.expect_value(t, player.held.stack, Item_Stack{coal, 3})
	testing.expect_value(t, chest_slots[0], Item_Stack{coal, 2})
	player.held = EMPTY_HELD_STACK
	chest_slots[0] = EMPTY_STACK
	chest_slots[3] = {coal, 5}
	tap_widget(audit, &state, slot_button_id("slot_button_sort"))
	testing.expect_value(t, chest_slots[0], Item_Stack{coal, 5})
	// The chest into the main grid, never the hotbar.
	tap_widget(audit, &state, slot_button_id("slot_button_transfer_all"))
	testing.expect(t, slots_empty(chest_slots))
	testing.expect(t, slots_empty(inventory_hotbar(player.inventory)))
	testing.expect_value(t, inventory_count(player.inventory, coal), 5)
}

// The active grid is forgotten with the focus on a frame without a screen.
@(test)
test_a_frame_without_a_screen_clears_the_active_slot :: proc(t: ^testing.T) {
	state: Ui_State
	defer destroy_ui_state(&state)
	state.active_slot = {.Main, HOTBAR_SLOT_COUNT + 2}
	push_screen(&state.screens, .None)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.active_slot, Active_Slot{.Main, HOTBAR_SLOT_COUNT + 2})
	pop_screen(&state.screens)
	test_ui_frame(&state, {})
	run_screens(&state, {})
	testing.expect_value(t, state.active_slot, Active_Slot{})
}

// X with a hotbar slot focused (where the screen opens) sorts the main
// grid and leaves the hotbar's order.
@(test)
test_x_on_the_hotbar_sorts_the_main_grid :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	coal := test_item(audit.content.items, "coal")
	stone := test_item(audit.content.items, "stone")
	slots := player.inventory.slots
	slots[6] = {stone, 1}
	slots[HOTBAR_SLOT_COUNT + 7] = {stone, 2}
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, state.active_slot.grid, Slot_Grid_Kind.Hotbar)
	screen_test_frame(audit, &state, {context_action = true})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT], Item_Stack{stone, 2})
	testing.expect_value(t, slots[HOTBAR_SLOT_COUNT + 7], EMPTY_STACK)
	testing.expect_value(t, slots[3], Item_Stack{coal, 5})
	testing.expect_value(t, slots[6], Item_Stack{stone, 1})
}

// Buttons keep their widths while they fit; else the widest shrink
// first to one common width.
@(test)
test_fit_button_widths_caps_the_widest :: proc(t: ^testing.T) {
	natural := [?]f32{50, 60, 150, 250}
	fitted := fit_button_widths(natural[:], 1000)
	testing.expect_value(t, fitted[3], 250)
	fitted = fit_button_widths(natural[:], 400)
	testing.expect_value(t, fitted[0], 50)
	testing.expect_value(t, fitted[1], 60)
	testing.expect_value(t, fitted[2], 145)
	testing.expect_value(t, fitted[3], 145)
	fitted = fit_button_widths(natural[:], 100)
	for width in fitted {
		testing.expect_value(t, width, 25)
	}
}

// Work item 0137: Drop in the inventory's row drops the active slot's
// stack, Clear filter in a filter panel's row clears the filter.
@(test)
test_the_touch_row_drops_the_active_stack :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state := Ui_State{theme = audit.theme}
	defer destroy_ui_state(&state)
	player := drag_test_inventory(audit, &state)
	loose_before := len(audit.simulation.world.entities.loose_items.items)
	tap_widget(audit, &state, inventory_slot_id("hotbar", 3))
	tap_widget(audit, &state, slot_button_id("touch_button_drop"))
	testing.expect_value(t, player.inventory.slots[3], EMPTY_STACK)
	testing.expect_value(t, len(audit.simulation.world.entities.loose_items.items), loose_before + 1)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

@(test)
test_the_touch_row_clears_a_filter :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	simulation := &audit.simulation
	coal := test_item(audit.content.items, "coal")
	filtered := 0
	for handle in machines_with_panels(&simulation.world, audit.content) {
		machine := audit.content.machines.machines[entity_common(&simulation.world.entities, handle).machine]
		filter: ^Item_Id
		if inserter := pool_get(&simulation.world.entities.inserters, handle); inserter != nil && inserter_has_filter(machine) && inserter.slot_count == 0 {
			filter = &inserter.filter
		}
		if splitter := pool_get(&simulation.world.entities.splitters, handle); splitter != nil {
			filter = &splitter.filter
		}
		if filter == nil {
			continue
		}
		filtered += 1
		filter^ = coal
		state := Ui_State{theme = audit.theme}
		simulation.players[0].open_machine = handle
		push_screen(&state.screens, .Machine)
		screen_test_frame(audit, &state, {pointer_is_touch = true})
		tap_widget(audit, &state, slot_button_id("touch_button_clear_filter"))
		testing.expectf(t, filter^ == NO_ITEM, "%s keeps its filter", machine.id)
		testing.expect_value(t, top_screen(state.screens), Screen.Machine)
		destroy_ui_state(&state)
	}
	testing.expect(t, filtered >= 2)
	simulation.players[0].open_machine = NO_ENTITY
}
