package game

// The toolbar edit mode (0279, after Techtonica): a screen over the
// crafting view, opened by Y held there (or a long press on the touch
// row's Assign), that shows the toolbars as a grid, row 0 the lowest and
// the active toolbar as on the HUD. The d-pad moves the cursor, Left and
// Right wrapping along the row, Down past row 0 rolling the rows up as a
// carousel, which makes the toolbar coming down the active one
// (Active_Toolbar_Command). A picks a shortcut up and drops it: on an
// empty cell it moves, on another kind the two swap and the new one is
// held, on its own kind they merge. X clears the held shortcut or the
// cursor's slot, X held QUICK_MOVE_REPEAT_SECONDS the cursor's row. B,
// Pause and a tap off the panel close it (the screen stack).
//
// The simulation always holds what the grid would show with the held
// shortcut back on its origin: a pick up queues nothing, so the held
// kind is the shown toolbars' at the origin, and closing the screen by
// any path while one is held sends nothing. Every change is a
// Toolbar_Assign_Command; a move's and a swap's two are queued in one
// frame, so one tick applies both, and a merge is one.

Button_Press :: struct {
	// The edge, the button held, and a press that left the slop (touch).
	pressed, down, cancelled: bool,
}

// A button's press as a tap or a hold (advance_button_hold): seconds
// held, whether the hold fired (spent), and the frame it was last
// advanced in.
Button_Hold :: struct {
	down:    bool,
	seconds: f32,
	spent:   bool,
	frame:   u64,
}

Button_Hold_Event :: enum u8 {
	None,
	Tap,
	Hold,
}

// A toolbar index and a slot, not a grid row.
Toolbar_Cell :: struct {
	toolbar, slot: int,
}

// The mode's state for the open screen. row and slot are the cursor, row
// 0 the lowest; first_toolbar is the lowest row's toolbar
// (toolbar_at_row). origin is the held shortcut's cell while holding.
// clear_hold tracks X; return_focus is the crafting view's slot widget
// that held the focus when the mode opened.
Toolbar_Edit :: struct {
	row, slot:     int,
	first_toolbar: int,
	holding:       bool,
	origin:        Toolbar_Cell,
	clear_hold:    Button_Hold,
	return_focus:  Ui_Id,
}

TOOLBAR_EDIT_PANEL_LABEL :: "toolbar_edit"
TOOLBAR_EDIT_PANEL_WIDTH :: HOTBAR_SLOT_COUNT * (UI_SLOT_SIZE + UI_GAP) - UI_GAP + 2 * UI_PADDING
TOOLBAR_EDIT_TOUCH_BUTTONS :: Touch_Buttons{.Clear_Toolbar_Slot, .Done}

Toolbar_Edit_Layout :: struct {
	title: Ui_Rectangle,
	cells: [MAXIMUM_TOOLBAR_COUNT][HOTBAR_SLOT_COUNT]Ui_Rectangle,
}

// One frame of a button: a hold not advanced on the previous frame starts
// afresh, so a press left behind by a closed screen never fires later. A
// press and its release are a Tap on the release (in one frame, at once),
// unless the press was held hold_seconds, which is a Hold once, on the
// frame that reaches it. A cancelled press is forgotten.
advance_button_hold :: proc(hold: Button_Hold, press: Button_Press, frame: u64, seconds, hold_seconds: f32) -> (Button_Hold, Button_Hold_Event) {
	tracked := hold.frame + 1 == frame ? hold : Button_Hold{}
	switch {
	case press.cancelled:
		return {frame = frame}, .None
	case press.pressed && press.down:
		return {down = true, frame = frame}, .None
	case press.pressed:
		return {frame = frame}, .Tap
	case !tracked.down:
		return {frame = frame}, .None
	case !press.down:
		return {frame = frame}, tracked.spent ? .None : .Tap
	}
	tracked.frame = frame
	tracked.seconds += seconds
	if tracked.spent || tracked.seconds < hold_seconds {
		return tracked, .None
	}
	tracked.spent = true
	return tracked, .Hold
}

// The crafting view's way in: Y (with no text field open), or a finger's
// press on the touch row's Assign, which leaving the slop cancels.
toolbar_edit_entry_press :: proc(state: Ui_State, assign_button: Ui_Id) -> Button_Press {
	typing := state.keyboard.field != 0
	press := state.pointer_press
	on_assign := press.widget == assign_button
	return Button_Press {
		pressed = (state.input.info && !typing) || (on_assign && state.click),
		down = (state.input.info_down && !typing) || (on_assign && press.down && !press.moved),
		cancelled = on_assign && press.down && press.moved,
	}
}

// The player's toolbars with the Toolbar_Assign_Commands on their way
// applied in order, the unconfirmed first, then the frame queue's of the
// player (as shown_foundation_block), so presses inside the latency window
// act on what the grid shows. One outside the arrays is skipped.
shown_toolbars :: proc(player: Player, queued: []Queued_Player_Command, unconfirmed: []Player_Command, player_index: int) -> [MAXIMUM_TOOLBAR_COUNT]Toolbar {
	shown := player.toolbars
	for command in unconfirmed {
		if assign, is_assign := command.(Toolbar_Assign_Command); is_assign {
			apply_shown_toolbar_assign(&shown, assign)
		}
	}
	for entry in queued {
		if assign, is_assign := entry.command.(Toolbar_Assign_Command); is_assign && entry.player == player_index {
			apply_shown_toolbar_assign(&shown, assign)
		}
	}
	return shown
}

apply_shown_toolbar_assign :: proc(shown: ^[MAXIMUM_TOOLBAR_COUNT]Toolbar, assign: Toolbar_Assign_Command) {
	if index_in_range(assign.toolbar, MAXIMUM_TOOLBAR_COUNT) && index_in_range(assign.slot, HOTBAR_SLOT_COUNT) {
		shown[assign.toolbar][assign.slot] = assign.item
	}
}

// Left and Right wrap along the row; Up goes to the row above, nothing on
// the top row; Down to the row below, and on row 0 shifts the carousel
// (the cursor stays) while there is more than one toolbar.
step_toolbar_edit_cursor :: proc(row, slot: int, step: Ui_Direction, count: int) -> (row_after, slot_after: int, shift: bool) {
	row_after, slot_after = row, slot
	switch step {
	case .None:
	case .Left:
		slot_after = (slot + HOTBAR_SLOT_COUNT - 1) % HOTBAR_SLOT_COUNT
	case .Right:
		slot_after = (slot + 1) % HOTBAR_SLOT_COUNT
	case .Up:
		row_after = min(row + 1, count - 1)
	case .Down:
		if row > 0 {
			row_after = row - 1
		} else {
			shift = count > 1
		}
	}
	return
}

// A or a drop on a cell. Nothing held: a named cell is picked up. Held,
// on the origin: put back. On a cell naming the held kind: they merge,
// the origin cleared. On any other cell: the held kind goes there and
// what was there to the origin, held on while it names a kind, so a swap
// holds the new one and a move ends the hold.
toolbar_edit_act :: proc(edit: Toolbar_Edit, shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, cell: Toolbar_Cell) -> (after: Toolbar_Edit, commands: [2]Toolbar_Assign_Command, count: int) {
	after = edit
	under := shown[cell.toolbar][cell.slot]
	if !edit.holding {
		if under != NO_ITEM {
			after.holding, after.origin = true, cell
		}
		return
	}
	if cell == edit.origin {
		after.holding = false
		return
	}
	origin := edit.origin
	held := shown[origin.toolbar][origin.slot]
	if under == held {
		commands[0] = {origin.toolbar, origin.slot, NO_ITEM}
		after.holding = false
		return after, commands, 1
	}
	commands[0] = {cell.toolbar, cell.slot, held}
	commands[1] = {origin.toolbar, origin.slot, under}
	after.holding = under != NO_ITEM
	return after, commands, 2
}

// X or the touch row's Clear: with one held, its origin cleared (the held
// shortcut discarded); else the cursor's slot while it names a kind.
toolbar_edit_clear :: proc(edit: Toolbar_Edit, shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, cursor: Toolbar_Cell) -> (command: Toolbar_Assign_Command, queues, discards_held: bool) {
	if edit.holding {
		return {edit.origin.toolbar, edit.origin.slot, NO_ITEM}, true, true
	}
	return {cursor.toolbar, cursor.slot, NO_ITEM}, shown[cursor.toolbar][cursor.slot] != NO_ITEM, false
}

// X held: every slot of the toolbar that names a kind cleared.
toolbar_row_clear_commands :: proc(shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, toolbar: int) -> (commands: [HOTBAR_SLOT_COUNT]Toolbar_Assign_Command, count: int) {
	for item, slot in shown[toolbar] {
		if item != NO_ITEM {
			commands[count] = {toolbar, slot, NO_ITEM}
			count += 1
		}
	}
	return
}

// The id the screen registers for a cell (its panel opens at depth 0),
// by row, so a shift of the carousel keeps the focus on row 0.
toolbar_edit_cell_id :: proc(row, slot: int) -> Ui_Id {
	return ui_hash(ui_hash(0, TOOLBAR_EDIT_PANEL_LABEL, -1), "cell", row * HOTBAR_SLOT_COUNT + slot)
}

toolbar_edit_cursor_of_focus :: proc(focus: Ui_Id, count: int) -> (row, slot: int, found: bool) {
	for candidate_row in 0 ..< count {
		for candidate_slot in 0 ..< HOTBAR_SLOT_COUNT {
			if toolbar_edit_cell_id(candidate_row, candidate_slot) == focus {
				return candidate_row, candidate_slot, true
			}
		}
	}
	return 0, 0, false
}

// The cursor and the carousel within the count; a data reload that
// lowered the count past the origin's toolbar ends the hold.
clamp_toolbar_edit :: proc(edit: ^Toolbar_Edit, count: int) {
	edit.row = clamp(edit.row, 0, count - 1)
	edit.slot = clamp(edit.slot, 0, HOTBAR_SLOT_COUNT - 1)
	edit.first_toolbar = clamp(edit.first_toolbar, 0, count - 1)
	if edit.origin.toolbar >= count {
		edit.holding = false
	}
}

// The title row, a gap and a row of slots per toolbar.
toolbar_edit_panel_height :: proc(count: int) -> f32 {
	return UI_ROW_HEIGHT + UI_GAP + slot_grid_height(count) + 2 * UI_PADDING
}

// Inset by the padding: the title row, a gap, then row r on grid line
// count - 1 - r, so the lowest row is the active toolbar as on the HUD.
toolbar_edit_layout :: proc(panel: Ui_Rectangle, count: int) -> Toolbar_Edit_Layout {
	content := inset(panel, UI_PADDING)
	layout: Toolbar_Edit_Layout
	layout.title = cut_top(&content, UI_ROW_HEIGHT)
	cut_top(&content, UI_GAP)
	for row in 0 ..< count {
		for slot in 0 ..< HOTBAR_SLOT_COUNT {
			layout.cells[row][slot] = slot_grid_rectangle({content.x, content.y}, HOTBAR_SLOT_COUNT, (count - 1 - row) * HOTBAR_SLOT_COUNT + slot)
		}
	}
	return layout
}

// From the crafting view: the cursor on the selected slot of row 0, the
// active toolbar lowest, and the inventory half's focused slot to return
// to.
open_toolbar_edit :: proc(state: ^Ui_State, player: Player) {
	state.toolbar_edit = Toolbar_Edit {
		slot          = player.selected_hotbar_slot,
		first_toolbar = player.active_toolbar,
		return_focus  = state.crafting_half == .Inventory ? state.focus : 0,
	}
	push_screen(&state.screens, .Toolbar_Edit)
}

// A cell as an item slot to the pointer (Slot_Drag): a drag past the slop
// picks it up and its release drops on the cell under it. On touch a tap
// acts as A, with its Confirm sound (an item slot's tap has none). The
// tooltip names the kind and shows by itself.
toolbar_edit_cell :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, entry: Toolbar_Entry, items: Item_Registry) -> Ui_Interaction {
	named := entry.item != NO_ITEM
	interaction := ui_interact(state, id, rectangle, {.Tooltip_Shows_Itself, .Item_Slot}, named ? item_name(items, entry.item) : "")
	if interaction.hovered && state.click {
		state.slot_drag.slot, state.slot_drag.count = id, named ? 1 : 0
	}
	tapped := interaction.hovered && state.pointer_source == .Touch && pointer_tapped(state^, id)
	if tapped {
		state.sound_events += {.Confirm}
	}
	interaction.activated = (interaction.focused && state.confirm) || (interaction.hovered && state.slot_drag.released) || tapped
	widget_background(state, rectangle, id, interaction)
	draw_outline(state, rectangle, theme_color(state, .Panel_Edge), ui_theme(state).border)
	draw_toolbar_slot(state, rectangle, entry, items)
	return interaction
}

toolbar_edit_screen :: proc(state: ^Ui_State, screen_context: Screen_Context) {
	if screen_context.player == nil {
		pop_screen(&state.screens)
		return
	}
	player, items := screen_context.player, screen_context.items
	edit := &state.toolbar_edit
	count := toolbar_count(screen_context.content)
	clamp_toolbar_edit(edit, count)
	// The pointer's hover moved the focus last frame.
	if row, slot, found := toolbar_edit_cursor_of_focus(state.focus, count); found {
		edit.row, edit.slot = row, slot
	}
	shown := shown_toolbars(player^, queued_commands(screen_context), screen_context.unconfirmed_commands, screen_context.player_index)
	// The screen takes the step, so ui_resolve never steps the focus off
	// the grid.
	if state.navigation_step != .None {
		shift: bool
		edit.row, edit.slot, shift = step_toolbar_edit_cursor(edit.row, edit.slot, state.navigation_step, count)
		if shift {
			edit.first_toolbar = (edit.first_toolbar + count - 1) % count
			queue_player_command(screen_context.player_commands, screen_context.player_index, Active_Toolbar_Command{edit.first_toolbar})
		}
		state.requested_focus, state.navigation_step = toolbar_edit_cell_id(edit.row, edit.slot), .None
	}
	ui_prefer_focus(state, toolbar_edit_cell_id(edit.row, edit.slot))
	ui_backdrop(state)
	panel := fitted_panel(ui_panel_area(state), TOOLBAR_EDIT_PANEL_WIDTH, toolbar_edit_panel_height(count))
	layout := toolbar_edit_layout(panel, count)
	ui_panel_begin(state, TOOLBAR_EDIT_PANEL_LABEL, panel)
	draw_text_fitted(state, layout.title, text("toolbar_edit_title"), UI_HEADING_TEXT_SIZE, .Centre)
	activated, activates := Toolbar_Cell{}, false
	for row in 0 ..< count {
		toolbar := toolbar_at_row(edit.first_toolbar, count, row)
		entries := toolbar_entries_of(shown[toolbar], player.inventory)
		for slot in 0 ..< HOTBAR_SLOT_COUNT {
			cell := Toolbar_Cell{toolbar, slot}
			entry := edit.holding && cell == edit.origin ? Toolbar_Entry{NO_ITEM, 0} : entries[slot]
			if toolbar_edit_cell(state, layout.cells[row][slot], ui_id(state, "cell", row * HOTBAR_SLOT_COUNT + slot), entry, items).activated {
				activated, activates = cell, true
			}
		}
	}
	ui_panel_end(state)
	touch := touch_row_shows(state)
	button := touch ? ui_touch_row(state, TOOLBAR_EDIT_TOUCH_BUTTONS) : .None
	if activates {
		acted, commands, command_count := toolbar_edit_act(edit^, shown, activated)
		edit^ = acted
		queue_toolbar_assigns(screen_context, commands[:command_count])
	}
	toolbar_edit_clear_input(state, screen_context, edit, count, button == .Clear_Toolbar_Slot)
	// A drag's end puts what is still held back on its origin (the swapped
	// kind, or one released off the cells); a release that did not move
	// keeps it, as A does, but off the screen's content it backs out, as
	// such a tap does with nothing held (end_slot_drag).
	if state.slot_drag.released && edit.holding {
		switch {
		case state.slot_drag.moved:
			edit.holding = false
		case state.slot_drag.outside && pointer_outside_screen(state^):
			state.input.back = true
			state.sound_events += {.Back}
		}
	}
	state.slot_drag.holding = edit.holding
	if state.slot_drag.phase == .Dragging && !edit.holding {
		state.slot_drag.phase = .None
	}
	shown_after := shown_toolbars(player^, queued_commands(screen_context), screen_context.unconfirmed_commands, screen_context.player_index)
	held := edit.holding ? shown_after[edit.origin.toolbar][edit.origin.slot] : NO_ITEM
	if held != NO_ITEM {
		if rectangle, found := held_stack_rectangle(state); found {
			draw_toolbar_slot(state, rectangle, {held, inventory_count(player.inventory, held)}, items)
		}
	}
	if !touch {
		cursor := toolbar_edit_cursor(edit^, count)
		on_hole := edit.holding && cursor == edit.origin
		toolbar_edit_glyph_bar(state, held, on_hole ? NO_ITEM : shown_after[cursor.toolbar][cursor.slot])
	}
}

// The frame's command list as a slice, nil without one.
queued_commands :: proc(screen_context: Screen_Context) -> []Queued_Player_Command {
	return screen_context.player_commands != nil ? screen_context.player_commands[:] : nil
}

// The cursor's cell: the toolbar its row shows.
toolbar_edit_cursor :: proc(edit: Toolbar_Edit, count: int) -> Toolbar_Cell {
	return {toolbar_at_row(edit.first_toolbar, count, edit.row), edit.slot}
}

// X: its press (or the touch row's Clear) clears against the toolbars
// shown after this frame's A; discarding the held one spends the press,
// so it clears no row. Held QUICK_MOVE_REPEAT_SECONDS it clears the
// cursor's row and ends the hold (a held one from another row stays on
// its origin).
toolbar_edit_clear_input :: proc(state: ^Ui_State, screen_context: Screen_Context, edit: ^Toolbar_Edit, count: int, clear_button: bool) {
	press := Button_Press{state.input.context_action, state.input.context_action_down, false}
	event: Button_Hold_Event
	edit.clear_hold, event = advance_button_hold(edit.clear_hold, press, state.frame_count, state.frame_seconds, QUICK_MOVE_REPEAT_SECONDS)
	cursor := toolbar_edit_cursor(edit^, count)
	if state.input.context_action || clear_button {
		shown := shown_toolbars(screen_context.player^, queued_commands(screen_context), screen_context.unconfirmed_commands, screen_context.player_index)
		command, queues, discards_held := toolbar_edit_clear(edit^, shown, cursor)
		if queues {
			queue_toolbar_assigns(screen_context, {command})
		}
		if discards_held {
			edit.holding, edit.clear_hold.spent = false, true
		}
	}
	if event == .Hold {
		shown := shown_toolbars(screen_context.player^, queued_commands(screen_context), screen_context.unconfirmed_commands, screen_context.player_index)
		commands, command_count := toolbar_row_clear_commands(shown, cursor.toolbar)
		queue_toolbar_assigns(screen_context, commands[:command_count])
		edit.holding = false
	}
}

// held is NO_ITEM with nothing held; cursor_kind the cursor's cell as
// drawn, NO_ITEM on the hole. The bar drops hints from the end, Done kept.
toolbar_edit_glyph_bar :: proc(state: ^Ui_State, held, cursor_kind: Item_Id) {
	hints := make([dynamic]Glyph_Hint, context.temp_allocator)
	switch {
	case held != NO_ITEM && cursor_kind != NO_ITEM && cursor_kind != held:
		append(&hints, Glyph_Hint{.Confirm, text("hint_swap")})
	case held != NO_ITEM:
		append(&hints, Glyph_Hint{.Confirm, text("hint_place_stack")})
	case cursor_kind != NO_ITEM:
		append(&hints, Glyph_Hint{.Confirm, text("hint_pick_up")})
	}
	append(&hints, Glyph_Hint{.Context_Action, text(held != NO_ITEM ? "hint_clear_shortcut" : "hint_clear_toolbar")})
	append(&hints, Glyph_Hint{.Back, text("hint_done")})
	ui_glyph_bar(state, hints[:])
}

// Each through queue_player_command; nothing without a command list.
queue_toolbar_assigns :: proc(screen_context: Screen_Context, commands: []Toolbar_Assign_Command) {
	for command in commands {
		queue_player_command(screen_context.player_commands, screen_context.player_index, command)
	}
}
