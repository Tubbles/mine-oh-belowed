package game

import "core:slice"
import "core:testing"

// Work item 0279: the toolbar edit mode. The screen frames run at 1920 by
// 1080 pixels and UI scale 1 (screen_test_frame), so a UI unit is a pixel.

TEST_FRAME_SECONDS :: f32(1.0 / 60)

// The events of a press held down for down_frames frames (the press frame
// first) and released on the next, at 60 frames a second.
button_hold_events :: proc(down_frames: int, hold_seconds: f32) -> []Button_Hold_Event {
	events := make([]Button_Hold_Event, down_frames + 1, context.temp_allocator)
	hold: Button_Hold
	for frame in 0 ..= down_frames {
		press := Button_Press{pressed = frame == 0, down = frame < down_frames}
		hold, events[frame] = advance_button_hold(hold, press, u64(frame + 1), TEST_FRAME_SECONDS, hold_seconds)
	}
	return events
}

// The frames after the press frame whose seconds reach hold_seconds.
frames_to_hold :: proc(hold_seconds: f32) -> int {
	frames, seconds := 0, f32(0)
	for seconds < hold_seconds {
		seconds += TEST_FRAME_SECONDS
		frames += 1
	}
	return frames
}

@(test)
test_a_button_hold_tells_a_tap_from_a_hold :: proc(t: ^testing.T) {
	tap := button_hold_events(10, TOUCH_HOLD_SECONDS)
	for event, frame in tap {
		testing.expectf(t, event == (frame == 10 ? .Tap : .None), "a tap's frame %d: %v", frame, event)
	}
	reached := frames_to_hold(TOUCH_HOLD_SECONDS)
	held := button_hold_events(20, TOUCH_HOLD_SECONDS)
	for event, frame in held {
		testing.expectf(t, event == (frame == reached ? .Hold : .None), "a hold's frame %d: %v", frame, event)
	}
	_, at_once := advance_button_hold({}, {pressed = true}, 1, TEST_FRAME_SECONDS, TOUCH_HOLD_SECONDS)
	testing.expect_value(t, at_once, Button_Hold_Event.Tap)
	// A frame without the tracker's advance forgets the press.
	pressed, _ := advance_button_hold({}, {pressed = true, down = true}, 1, TEST_FRAME_SECONDS, TOUCH_HOLD_SECONDS)
	_, skipped := advance_button_hold(pressed, {}, 3, TEST_FRAME_SECONDS, TOUCH_HOLD_SECONDS)
	testing.expect_value(t, skipped, Button_Hold_Event.None)
	cancelled, cancel_event := advance_button_hold(pressed, {down = true, cancelled = true}, 2, TEST_FRAME_SECONDS, TOUCH_HOLD_SECONDS)
	testing.expect_value(t, cancel_event, Button_Hold_Event.None)
	_, released := advance_button_hold(cancelled, {}, 3, TEST_FRAME_SECONDS, TOUCH_HOLD_SECONDS)
	testing.expect_value(t, released, Button_Hold_Event.None)
}

@(test)
test_the_edit_cursor_steps_and_shifts_the_carousel :: proc(t: ^testing.T) {
	Step_Case :: struct {
		row, slot:       int,
		step:            Ui_Direction,
		count:           int,
		row_after:       int,
		slot_after:      int,
		shift:           bool,
	}
	cases := [?]Step_Case {
		{0, 0, .Left, 4, 0, 7, false},
		{0, 7, .Right, 4, 0, 0, false},
		{3, 2, .Up, 4, 3, 2, false},
		{2, 2, .Down, 4, 1, 2, false},
		{0, 2, .Down, 4, 0, 2, true},
		{0, 2, .Down, 2, 0, 2, true},
		{0, 2, .Down, 1, 0, 2, false},
		{0, 2, .Up, 1, 0, 2, false},
	}
	for step_case in cases {
		row, slot, shift := step_toolbar_edit_cursor(step_case.row, step_case.slot, step_case.step, step_case.count)
		testing.expectf(t, row == step_case.row_after && slot == step_case.slot_after && shift == step_case.shift, "%v: %d %d %v", step_case, row, slot, shift)
	}
}

// Toolbar 0 names kinds 10 and 11 on its first two slots and 10 again on
// slot 4, toolbar 1 kind 12 on slot 3.
edit_test_toolbars :: proc() -> [MAXIMUM_TOOLBAR_COUNT]Toolbar {
	toolbars := empty_toolbars()
	toolbars[0][0], toolbars[0][1], toolbars[0][4] = 10, 11, 10
	toolbars[1][3] = 12
	return toolbars
}

@(test)
test_toolbar_edit_act_picks_drops_swaps_and_merges :: proc(t: ^testing.T) {
	shown := edit_test_toolbars()
	Act_Case :: struct {
		name:     string,
		edit:     Toolbar_Edit,
		cell:     Toolbar_Cell,
		holding:  bool,
		origin:   Toolbar_Cell,
		commands: []Toolbar_Assign_Command,
	}
	cases := [?]Act_Case {
		{name = "pick up", cell = {0, 0}, holding = true, origin = {0, 0}},
		{name = "an empty cell holds nothing", cell = {0, 2}},
		{name = "put back", edit = {holding = true, origin = {0, 0}}, cell = {0, 0}, origin = {0, 0}},
		{name = "move", edit = {holding = true, origin = {0, 0}}, cell = {0, 2}, origin = {0, 0}, commands = {{0, 2, 10}, {0, 0, NO_ITEM}}},
		{name = "swap", edit = {holding = true, origin = {0, 0}}, cell = {0, 1}, holding = true, origin = {0, 0}, commands = {{0, 1, 10}, {0, 0, 11}}},
		{name = "merge", edit = {holding = true, origin = {0, 0}}, cell = {0, 4}, origin = {0, 0}, commands = {{0, 0, NO_ITEM}}},
		{name = "across toolbars", edit = {holding = true, origin = {1, 3}}, cell = {0, 5}, origin = {1, 3}, commands = {{0, 5, 12}, {1, 3, NO_ITEM}}},
	}
	for act_case in cases {
		after, commands, count := toolbar_edit_act(act_case.edit, shown, act_case.cell)
		testing.expectf(t, after.holding == act_case.holding, "%s: holding %v", act_case.name, after.holding)
		testing.expectf(t, !after.holding || after.origin == act_case.origin, "%s: origin %v", act_case.name, after.origin)
		testing.expectf(t, slice.equal(commands[:count], act_case.commands), "%s: %v", act_case.name, commands[:count])
	}
}

@(test)
test_clear_takes_the_held_shortcut_first_and_the_row_clears_its_named_slots :: proc(t: ^testing.T) {
	shown := edit_test_toolbars()
	held := Toolbar_Edit{holding = true, origin = {1, 3}}
	command, queues, discards := toolbar_edit_clear(held, shown, {0, 0})
	testing.expect_value(t, command, Toolbar_Assign_Command{1, 3, NO_ITEM})
	testing.expect(t, queues && discards)
	command, queues, discards = toolbar_edit_clear({}, shown, {0, 1})
	testing.expect_value(t, command, Toolbar_Assign_Command{0, 1, NO_ITEM})
	testing.expect(t, queues && !discards)
	_, queues, discards = toolbar_edit_clear({}, shown, {0, 2})
	testing.expect(t, !queues && !discards)
	commands, count := toolbar_row_clear_commands(shown, 0)
	testing.expect(t, slice.equal(commands[:count], []Toolbar_Assign_Command{{0, 0, NO_ITEM}, {0, 1, NO_ITEM}, {0, 4, NO_ITEM}}))
	_, count = toolbar_row_clear_commands(shown, 2)
	testing.expect_value(t, count, 0)
}

// The kinds of the screen tests, each with its own count in the
// inventory, so a cell's drawn count names its kind.
Edit_Test_Kinds :: struct {
	log, plank, coal, stone: Item_Id,
}

EDIT_TEST_LOG_COUNT :: "7"
EDIT_TEST_PLANK_COUNT :: "3"
EDIT_TEST_COAL_COUNT :: "5"

// The crafting view over the audit's site with only log 7, plank 3, coal 5
// and stone 2 in the inventory, the hand empty, toolbar 0 naming log and
// plank on its first two slots, slot 0 selected; drawn twice.
make_edit_test :: proc(audit: ^Ui_Audit, state: ^Ui_State) -> Edit_Test_Kinds {
	items := audit.content.items
	kinds := Edit_Test_Kinds{test_item(items, "log"), test_item(items, "plank"), test_item(items, "coal"), test_item(items, "stone")}
	player := &audit.simulation.players[0]
	slice.fill(player.inventory.slots, EMPTY_STACK)
	player.inventory.slots[0] = {kinds.log, 7}
	player.inventory.slots[1] = {kinds.plank, 3}
	player.inventory.slots[2] = {kinds.coal, 5}
	player.inventory.slots[3] = {kinds.stone, 2}
	player.held = EMPTY_HELD_STACK
	player.toolbars = empty_toolbars()
	player.toolbars[0][0], player.toolbars[0][1] = kinds.log, kinds.plank
	player.selected_hotbar_slot, player.active_toolbar = 0, 0
	clear(&audit.simulation.player_commands)
	open_crafting_view(audit, state, .Inventory)
	return kinds
}

// Y pressed, held down_frames frames in all and released.
press_y :: proc(audit: ^Ui_Audit, state: ^Ui_State, down_frames: int) {
	screen_test_frame(audit, state, {info = true, info_down = true})
	for _ in 1 ..< down_frames {
		screen_test_frame(audit, state, {info_down = true})
	}
	screen_test_frame(audit, state, {})
}

// Y held from the crafting view opens the edit mode, drawn once more.
open_edit_by_y :: proc(audit: ^Ui_Audit, state: ^Ui_State) {
	press_y(audit, state, 20)
	screen_test_frame(audit, state, {})
}

// A d-pad step and a frame without, so the next step is a new press.
step_edit_cursor :: proc(audit: ^Ui_Audit, state: ^Ui_State, step: Ui_Direction) {
	screen_test_frame(audit, state, {navigation = step})
	screen_test_frame(audit, state, {})
}

edit_cell_rectangle :: proc(state: Ui_State, row, slot: int) -> Ui_Rectangle {
	index := widget_index(state.widgets[:], toolbar_edit_cell_id(row, slot))
	assert(index >= 0, "no such cell")
	return state.widgets[index].rectangle
}

// The cell of the last frame draws the count's text.
edit_cell_draws :: proc(state: Ui_State, row, slot: int, count: string) -> bool {
	return draw_list_has_text(draw_commands_in(state.draw_list[:], edit_cell_rectangle(state, row, slot))[:], count)
}

// An icon or a text drawn in the cell of the last frame.
edit_cell_draws_a_kind :: proc(state: Ui_State, row, slot: int) -> bool {
	for command in draw_commands_in(state.draw_list[:], edit_cell_rectangle(state, row, slot)) {
		if command.kind == .Item_Tile || command.kind == .Atlas_Tile || command.kind == .Text {
			return true
		}
	}
	return false
}

edit_test_commands :: proc(audit: ^Ui_Audit) -> []Toolbar_Assign_Command {
	commands := make([dynamic]Toolbar_Assign_Command, context.temp_allocator)
	for queued in audit.simulation.player_commands {
		if assign, is_assign := queued.command.(Toolbar_Assign_Command); is_assign {
			append(&commands, assign)
		}
	}
	return commands[:]
}

@(test)
test_y_held_opens_the_edit_mode_and_a_short_y_still_assigns :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	player := &audit.simulation.players[0]
	player.selected_hotbar_slot = 2
	state.focus = inventory_slot_id("grid", 0)
	screen_test_frame(audit, &state, {})
	commands := &audit.simulation.player_commands
	screen_test_frame(audit, &state, {info = true, info_down = true})
	for _ in 1 ..< 10 {
		screen_test_frame(audit, &state, {info_down = true})
	}
	testing.expect_value(t, len(commands), 0)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, len(commands), 1)
	testing.expect_value(t, last_queued_command(audit).(Toolbar_Assign_Command), Toolbar_Assign_Command{0, 2, kinds.log})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	clear(commands)
	screen_test_frame(audit, &state, {info = true, info_down = true})
	for _ in 1 ..< 20 {
		screen_test_frame(audit, &state, {info_down = true})
	}
	testing.expect_value(t, top_screen(state.screens), Screen.Toolbar_Edit)
	testing.expect_value(t, len(commands), 0)
	testing.expect_value(t, state.toolbar_edit.row, 0)
	testing.expect_value(t, state.toolbar_edit.slot, 2)
	testing.expect_value(t, state.toolbar_edit.first_toolbar, player.active_toolbar)
	screen_test_frame(audit, &state, {})
	testing.expect_value(t, len(commands), 0)
	testing.expect_value(t, top_screen(state.screens), Screen.Toolbar_Edit)
	testing.expect_value(t, state.focus, toolbar_edit_cell_id(0, 2))
}

@(test) // slow
test_the_edit_mode_moves_and_swaps_shortcuts_through_assign_commands :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	player := &audit.simulation.players[0]
	open_edit_by_y(audit, &state)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, state.toolbar_edit.holding)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	step_edit_cursor(audit, &state, .Right)
	step_edit_cursor(audit, &state, .Right)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 2, kinds.log}, {0, 0, NO_ITEM}}))
	testing.expect_value(t, len(audit.simulation.player_commands), 2)
	testing.expect(t, !state.toolbar_edit.holding)
	apply_player_commands(&audit.simulation, audit.content)
	screen_test_frame(audit, &state, {})
	testing.expect(t, edit_cell_draws(state, 0, 2, EDIT_TEST_LOG_COUNT))
	// Plank picked up and dropped on log: they swap, log held.
	step_edit_cursor(audit, &state, .Left)
	screen_test_frame(audit, &state, {confirm = true})
	step_edit_cursor(audit, &state, .Right)
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 2, kinds.plank}, {0, 1, kinds.log}}))
	testing.expect(t, state.toolbar_edit.holding)
	apply_player_commands(&audit.simulation, audit.content)
	screen_test_frame(audit, &state, {})
	held, found := held_stack_rectangle(&state)
	testing.expect(t, found)
	testing.expect(t, draw_list_has_text(draw_commands_in(state.draw_list[:], held)[:], EDIT_TEST_LOG_COUNT), "log drawn held")
	testing.expect(t, !edit_cell_draws_a_kind(state, 0, 1), "the origin drawn empty")
	testing.expect(t, edit_cell_draws(state, 0, 2, EDIT_TEST_PLANK_COUNT))
	hud: Ui_State
	defer destroy_ui_state(&hud)
	test_ui_frame(&hud, {})
	draw_hud_toolbars(&hud, player^, audit.content.items, 1)
	row := hud_toolbar_row_rectangles(ui_safe_area(&hud), player.selected_hotbar_slot, 0)
	testing.expect(t, draw_list_has_text(draw_commands_in(hud.draw_list[:], row[2])[:], EDIT_TEST_PLANK_COUNT), "the HUD's slot 3 names plank")
	testing.expect(t, draw_list_has_text(draw_commands_in(hud.draw_list[:], row[1])[:], EDIT_TEST_LOG_COUNT), "the HUD's slot 2 names log")
	toolbars := player.toolbars
	screen_test_frame(audit, &state, {back = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, player.toolbars, toolbars)
}

// Coal named on slot 3 and selected, the focus on the inventory's coal
// stack (grid slot 2) when Y is held; the coal picked up and the cursor
// moved right.
open_edit_holding_coal :: proc(audit: ^Ui_Audit, state: ^Ui_State, kinds: Edit_Test_Kinds) {
	player := &audit.simulation.players[0]
	player.toolbars[0][3], player.selected_hotbar_slot = kinds.coal, 3
	screen_test_frame(audit, state, {})
	state.focus = inventory_slot_id("grid", 2)
	screen_test_frame(audit, state, {})
	open_edit_by_y(audit, state)
	screen_test_frame(audit, state, {confirm = true})
	step_edit_cursor(audit, state, .Right)
}

@(test) // slow
test_backing_out_puts_the_held_shortcut_back :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	player := &audit.simulation.players[0]
	Way_Out :: enum {
		Back,
		Pause,
		Done,
		Tap_Off_The_Panel,
	}
	for way in Way_Out {
		open_edit_holding_coal(audit, &state, kinds)
		toolbars := player.toolbars
		testing.expectf(t, state.toolbar_edit.holding && state.toolbar_edit.origin == {0, 3} && state.toolbar_edit.slot == 4, "%v: %v", way, state.toolbar_edit)
		switch way {
		case .Back:
			screen_test_frame(audit, &state, {back = true})
		case .Pause:
			screen_test_frame(audit, &state, {pause = true})
		case .Done:
			screen_test_frame(audit, &state, {pointer_is_touch = true})
			tap_widget(audit, &state, slot_button_id("touch_button_done"))
		case .Tap_Off_The_Panel:
			screen_test_frame(audit, &state, {pointer_is_touch = true})
			off := [2]f32{200, 200}
			screen_test_frame(audit, &state, touch_input(off, true, pressed = true))
			screen_test_frame(audit, &state, touch_input(off, false, moved = false))
		}
		testing.expectf(t, top_screen(state.screens) == .Inventory, "%v: %v on top", way, top_screen(state.screens))
		testing.expectf(t, len(audit.simulation.player_commands) == 0, "%v: %d queued", way, len(audit.simulation.player_commands))
		testing.expectf(t, player.toolbars == toolbars, "%v: the toolbars changed", way)
		screen_test_frame(audit, &state, {})
		screen_test_frame(audit, &state, {})
		if way == .Back {
			testing.expect_value(t, state.focus, inventory_slot_id("grid", 2))
		}
	}
}

@(test)
test_x_clears_the_slot_and_x_held_clears_the_row :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	player := &audit.simulation.players[0]
	player.toolbars[0][2] = kinds.coal
	open_edit_by_y(audit, &state)
	screen_test_frame(audit, &state, {context_action = true, context_action_down = true})
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 0, NO_ITEM}}))
	for _ in 1 ..< 25 {
		screen_test_frame(audit, &state, {context_action_down = true})
	}
	testing.expect_value(t, len(audit.simulation.player_commands), 1)
	for _ in 25 ..< 40 {
		screen_test_frame(audit, &state, {context_action_down = true})
	}
	screen_test_frame(audit, &state, {})
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 0, NO_ITEM}, {0, 1, NO_ITEM}, {0, 2, NO_ITEM}}))
	apply_player_commands(&audit.simulation, audit.content)
	testing.expect_value(t, player.toolbars[0], empty_toolbars()[0])
	// With one held X discards it, and that press held clears no row.
	player.toolbars[0][0], player.toolbars[0][1] = kinds.log, kinds.plank
	screen_test_frame(audit, &state, {confirm = true})
	testing.expect(t, state.toolbar_edit.holding)
	screen_test_frame(audit, &state, {context_action = true, context_action_down = true})
	testing.expect(t, !state.toolbar_edit.holding)
	for _ in 1 ..< 40 {
		screen_test_frame(audit, &state, {context_action_down = true})
	}
	screen_test_frame(audit, &state, {})
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 0, NO_ITEM}}))
	apply_player_commands(&audit.simulation, audit.content)
	// The touch row's Clear acts as the press, on the cursor's slot.
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	tap_widget(audit, &state, slot_button_id("touch_button_clear_toolbar_slot"))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{}))
	step_edit_cursor(audit, &state, .Right)
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	tap_widget(audit, &state, slot_button_id("touch_button_clear_toolbar_slot"))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 1, NO_ITEM}}))
}

@(test) // slow
test_the_pointer_drags_a_shortcut :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	open_edit_by_y(audit, &state)
	slot_0 := rectangle_centre(edit_cell_rectangle(state, 0, 0))
	slot_1 := rectangle_centre(edit_cell_rectangle(state, 0, 1))
	slot_4 := rectangle_centre(edit_cell_rectangle(state, 0, 4))
	screen_test_frame(audit, &state, pointer_input(slot_0, true, pressed = true, moved = false))
	screen_test_frame(audit, &state, pointer_input(slot_0, false, moved = false))
	testing.expect(t, !state.toolbar_edit.holding)
	testing.expect_value(t, state.focus, toolbar_edit_cell_id(0, 0))
	// Dragged onto an empty cell: the move.
	screen_test_frame(audit, &state, pointer_input(slot_0, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(slot_4, true))
	testing.expect(t, state.toolbar_edit.holding)
	screen_test_frame(audit, &state, pointer_input(slot_4, false, moved = false))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 4, kinds.log}, {0, 0, NO_ITEM}}))
	testing.expect(t, !state.toolbar_edit.holding)
	apply_player_commands(&audit.simulation, audit.content)
	// Plank dragged onto log: the swap, and the log stays on the origin.
	screen_test_frame(audit, &state, pointer_input(slot_1, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(slot_4, true))
	screen_test_frame(audit, &state, pointer_input(slot_4, false, moved = false))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 4, kinds.plank}, {0, 1, kinds.log}}))
	testing.expect(t, !state.toolbar_edit.holding)
	apply_player_commands(&audit.simulation, audit.content)
	// Released off the panel: put back, nothing queued.
	off := [2]f32{200, 200}
	screen_test_frame(audit, &state, pointer_input(slot_1, true, pressed = true))
	screen_test_frame(audit, &state, pointer_input(off, true))
	testing.expect(t, state.toolbar_edit.holding)
	screen_test_frame(audit, &state, pointer_input(off, false, moved = false))
	testing.expect(t, !state.toolbar_edit.holding)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, top_screen(state.screens), Screen.Toolbar_Edit)
}

@(test) // slow
test_touch_taps_pick_up_and_drop :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	open_edit_by_y(audit, &state)
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	tap_widget(audit, &state, toolbar_edit_cell_id(0, 0))
	testing.expect(t, state.toolbar_edit.holding && state.toolbar_edit.origin == {0, 0})
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	tap_widget(audit, &state, toolbar_edit_cell_id(0, 1))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 1, kinds.log}, {0, 0, kinds.plank}}))
	testing.expect(t, state.toolbar_edit.holding && state.toolbar_edit.origin == {0, 0})
	apply_player_commands(&audit.simulation, audit.content)
	tap_widget(audit, &state, toolbar_edit_cell_id(0, 5))
	testing.expect(t, slice.equal(edit_test_commands(audit), []Toolbar_Assign_Command{{0, 5, kinds.plank}, {0, 0, NO_ITEM}}))
	testing.expect(t, !state.toolbar_edit.holding)
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("touch_button_clear_toolbar_slot")))
	testing.expect(t, draw_list_has_text(state.draw_list[:], text("touch_button_done")))
	testing.expect(t, !glyph_bar_draws_glyphs(state.draw_list[:]))
}

@(test)
test_the_assign_buttons_long_press_opens_the_edit_mode :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	make_edit_test(audit, &state)
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	tap_widget(audit, &state, inventory_slot_id("grid", 0))
	assign := widget_centre(state, slot_button_id("touch_button_assign_toolbar"))
	screen_test_frame(audit, &state, touch_input(assign, true, pressed = true))
	for _ in 1 ..< 20 {
		screen_test_frame(audit, &state, touch_input(assign, true, moved = false))
	}
	testing.expect_value(t, top_screen(state.screens), Screen.Toolbar_Edit)
	screen_test_frame(audit, &state, touch_input(assign, false, moved = false))
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, top_screen(state.screens), Screen.Toolbar_Edit)
	// A press that leaves the slop assigns nothing on its release.
	screen_test_frame(audit, &state, {back = true})
	screen_test_frame(audit, &state, {pointer_is_touch = true})
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
	screen_test_frame(audit, &state, touch_input(assign, true, pressed = true))
	away := assign + {0, -3 * UI_SLOT_DRAG_SLOP}
	screen_test_frame(audit, &state, touch_input(away, true))
	screen_test_frame(audit, &state, touch_input(away, false, moved = false))
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	testing.expect_value(t, top_screen(state.screens), Screen.Inventory)
}

@(test) // slow
test_the_focus_never_leaves_the_grid :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	count_before := audit.content.toolbar_count
	defer audit.content.toolbar_count = count_before
	for count in ([?]int{1, MAXIMUM_TOOLBAR_COUNT}) {
		audit.content.toolbar_count = count
		state: Ui_State
		make_edit_test(audit, &state)
		open_edit_by_y(audit, &state)
		for step in ([?]Ui_Direction{.Up, .Down, .Left, .Right}) {
			for row in 0 ..< count {
				for slot in 0 ..< HOTBAR_SLOT_COUNT {
					state.focus = toolbar_edit_cell_id(row, slot)
					screen_test_frame(audit, &state, {navigation = step})
					edit := state.toolbar_edit
					testing.expectf(t, state.focus == toolbar_edit_cell_id(edit.row, edit.slot), "count %d, (%d, %d) %v: the focus left the cursor %v", count, row, slot, step, edit)
					screen_test_frame(audit, &state, {})
					clear(&audit.simulation.player_commands)
				}
			}
		}
		destroy_ui_state(&state)
	}
}

@(test)
test_the_modifiers_and_the_window_step_do_nothing_in_the_edit_mode :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	state: Ui_State
	defer destroy_ui_state(&state)
	make_edit_test(audit, &state)
	open_edit_by_y(audit, &state)
	for modifier in ([?]Confirm_Modifier{.Five, .Most}) {
		screen_test_frame(audit, &state, with_confirm_modifier({confirm = true}, modifier))
		testing.expectf(t, state.toolbar_edit.holding && state.toolbar_edit.origin == {0, 0}, "%v: %v", modifier, state.toolbar_edit)
		screen_test_frame(audit, &state, {confirm = true})
		testing.expect(t, !state.toolbar_edit.holding)
	}
	slot_0 := rectangle_centre(edit_cell_rectangle(state, 0, 0))
	slot_1 := rectangle_centre(edit_cell_rectangle(state, 0, 1))
	screen_test_frame(audit, &state, with_confirm_modifier(pointer_input(slot_0, true, pressed = true), .Five))
	screen_test_frame(audit, &state, with_confirm_modifier(pointer_input(slot_1, true), .Five))
	testing.expect(t, state.toolbar_edit.holding && state.toolbar_edit.origin == {0, 0})
	screen_test_frame(audit, &state, with_confirm_modifier(pointer_input(slot_0, false), .Five))
	testing.expect(t, !state.toolbar_edit.holding)
	testing.expect_value(t, len(audit.simulation.player_commands), 0)
	steps := [?]Ui_Input{{window_next = true}, {window_previous = true}, {open_inventory = true}, {open_recipes = true}}
	for input in steps {
		screen_test_frame(audit, &state, input)
		testing.expectf(t, top_screen(state.screens) == .Toolbar_Edit, "%v: %v on top", input, top_screen(state.screens))
	}
}

@(test)
test_the_carousel_shifts_the_rows_and_the_hud_follows :: proc(t: ^testing.T) {
	audit := make_ui_audit()
	defer destroy_ui_audit(audit)
	count_before := audit.content.toolbar_count
	defer audit.content.toolbar_count = count_before
	audit.content.toolbar_count = 3
	state: Ui_State
	defer destroy_ui_state(&state)
	kinds := make_edit_test(audit, &state)
	player := &audit.simulation.players[0]
	player.toolbars[0] = empty_toolbars()[0]
	player.toolbars[0][0], player.toolbars[1][0], player.toolbars[2][0] = kinds.log, kinds.plank, kinds.coal
	open_edit_by_y(audit, &state)
	testing.expect(t, edit_cell_draws(state, 0, 0, EDIT_TEST_LOG_COUNT))
	step_edit_cursor(audit, &state, .Down)
	testing.expect_value(t, state.toolbar_edit.first_toolbar, 2)
	testing.expect(t, edit_cell_draws(state, 0, 0, EDIT_TEST_COAL_COUNT), "row 0 shows toolbar 2")
	testing.expect(t, edit_cell_draws(state, 1, 0, EDIT_TEST_LOG_COUNT), "row 1 shows toolbar 0")
	testing.expect(t, edit_cell_draws(state, 2, 0, EDIT_TEST_PLANK_COUNT), "row 2 shows toolbar 1")
	testing.expect_value(t, state.focus, toolbar_edit_cell_id(0, 0))
	testing.expect_value(t, last_queued_command(audit).(Active_Toolbar_Command), Active_Toolbar_Command{2})
	apply_player_commands(&audit.simulation, audit.content)
	hud: Ui_State
	defer destroy_ui_state(&hud)
	test_ui_frame(&hud, {})
	draw_hud_toolbars(&hud, player^, audit.content.items, 3)
	row := hud_toolbar_row_rectangles(ui_safe_area(&hud), player.selected_hotbar_slot, 0)
	testing.expect(t, draw_list_has_text(draw_commands_in(hud.draw_list[:], row[0])[:], EDIT_TEST_COAL_COUNT), "the HUD's lowest row shows toolbar 2")
}
