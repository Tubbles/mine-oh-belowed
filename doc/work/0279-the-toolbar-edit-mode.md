# 0279: The toolbar edit mode

Status: implementing (2026-11-13)

## Goal

Y held in the crafting view opens the toolbar edit mode, Techtonica's way (user, 2026-10-05): the toolbars shown as a grid, the d-pad moving between the rows and along them, past the lowest row the rows shift as a carousel; A picks up a shortcut and drops it, on another the two swap and the new one is held; X clears the slot, X held clears the row; B backs out and a shortcut still held is dropped. On 0278.

## Controls

A mode over the crafting view (0277), entered by Y held for the UI's hold time, left by B. Inside it: D-pad Up and Down between the rows (the carousel past the lowest), Left and Right along the row, A pick up, drop or swap, X clear, X held clear the row, B done. The modifiers and the window carousel do nothing while it is open. Touch: a tap on a slot is the pick up and the drop, the button row shows Clear and Done. Open (design): whether the pointer drags shortcuts as it drags stacks.

## Change

- `ui_toolbar_edit.odin` (new): the grid, the held shortcut, the carousel; the changes as the assign command of 0278 (lockstep, as every player state).
- The UI audit case, the glyph bar's hints for the mode.
- Docs: `doc/ui.md` (Screens).

## Verify

- Tests: pick, drop, swap, clear, clear the row, backing out drops the held; the carousel shifts the rows and the HUD follows.
- The UI audit at every size.
- The couch.

## Specification (design, 2026-11-13)

Designed against 0278's tree (`.claude/worktrees/0278`, `item/0278`, verified, not on `main`): `Player.toolbars`, `active_toolbar`, `Toolbar_Assign_Command`, `toolbar_count`, `toolbar_at_row`, `draw_toolbar_slot` and Y's assign in `inventory_screen` are its; line numbers are that tree's. Lands after 0278.

### The mode is a screen

`Screen.Toolbar_Edit` (after `.Configure`, `ui_core.odin:264`), pushed over `.Inventory` as the configure pop-up is. "Open" is `top_screen(state.screens) == .Toolbar_Edit`. As a screen it gets most of the Controls without new input code: B, Pause and a tap off the panel pop it (`handle_screen_keys`, `screen_closes_on_outside_tap`); the triggers, the window keys and E do nothing (outside `window_carousel`, no title row); the crafting view under it does not run, so the only focus targets are the grid's cells; a stack in the hand goes back to the inventory as it opens (`close_slot_screens`).

- `run_screens` (`ui_screens.odin:260`): `case .Toolbar_Edit: toolbar_edit_screen(state, screen_context)`. `screen_pauses_simulation` (`ui_core.odin:1280`): the false row.
- `ui_begin`: the tooltip rule at 897 covers `.Toolbar_Edit` too (Y does nothing there); `state.confirm_modifier` is `.None` while the top screen is `.Toolbar_Edit` (882, before `advance_slot_drag`), so R1, L1, Left Control and Left Shift change neither A nor a click.

### Y short and Y held

No existing tracker fits a button (`advance_hotbar_touch` is a touch slot's, `tools_radial` the radial's, `advance_quick_move` the quick move's). A small pure one takes their rules: the hotbar's long press fires once at `TOUCH_HOLD_SECONDS` (0.25 s, the UI's hold time) and spends the press, a lift before it is the tap; Pipette's tap fires on the release; and `Knob_Position`'s frame check, a tracker not advanced last frame starts afresh, so a press left behind by a window step or a closed view never fires later.

- The assign fires on Y's release, not on the press: on the press it would also fire for every hold, overwriting the selected slot each time the mode opens. Nothing waits for the hold time: a release before 0.25 s assigns on that frame. The hold opens the mode at 0.25 s and its release fires nothing.
- A press and its release in one frame (pressed without down) is a tap at once, so 0278's one frame tests (`{info = true}`) pass unchanged.
- `Ui_Input` gains `info_down` and `context_action_down` (held, not edges); `make_ui_input`: `.Info_Panel in current.pressed`, `.Context_Action in current.pressed`.

### State

`Ui_State`, after `configure`: `toolbar_entry: Button_Hold` (the crafting view's Y and touch Assign press) and `toolbar_edit: Toolbar_Edit`.

The rule the mode rests on: the simulation always holds what the grid would show with the held shortcut back on its origin. A pick up queues nothing (the origin still names the kind), so the held kind is the shown toolbars' at the origin and is not stored, and backing out, closing by any path, a save or a crash while one is held send nothing.

### `src/ui_toolbar_edit.odin` (new, ui cluster)

Types and constants:

- `Button_Press :: struct {pressed, down, cancelled: bool}`: the edge, held, and a press that left the slop (touch).
- `Button_Hold :: struct {down: bool, seconds: f32, spent: bool, frame: u64}`, `Button_Hold_Event :: enum u8 {None, Tap, Hold}`.
- `Toolbar_Cell :: struct {toolbar, slot: int}`: a toolbar index, not a row.
- `Toolbar_Edit :: struct`: `row, slot: int` (the cursor, row 0 the lowest), `first_toolbar: int` (the lowest row's toolbar, `toolbar_at_row(first_toolbar, count, row)`), `holding: bool`, `origin: Toolbar_Cell`, `clear_hold: Button_Hold` (X), `return_focus: Ui_Id`.
- `TOOLBAR_EDIT_PANEL_LABEL :: "toolbar_edit"`, `TOOLBAR_EDIT_PANEL_WIDTH :: HOTBAR_SLOT_COUNT * (UI_SLOT_SIZE + UI_GAP) - UI_GAP + 2 * UI_PADDING` (728), `TOOLBAR_EDIT_TOUCH_BUTTONS :: Touch_Buttons{.Clear_Toolbar_Slot, .Done}`.
- `Toolbar_Edit_Layout :: struct {title: Ui_Rectangle, cells: [MAXIMUM_TOOLBAR_COUNT][HOTBAR_SLOT_COUNT]Ui_Rectangle}`.

Pure procedures:

- `advance_button_hold :: proc(hold: Button_Hold, press: Button_Press, frame: u64, seconds, hold_seconds: f32) -> (Button_Hold, Button_Hold_Event)`: a hold not advanced on the previous frame (`hold.frame + 1 != frame`) starts as `{}`; cancelled forgets the press; pressed with down starts it, pressed without down is Tap; a tracked press released is Tap unless spent; tracked and down, seconds add up and on reaching hold_seconds it is spent and gives Hold once. Callers pass `state.frame_count`.
- `toolbar_edit_entry_press :: proc(state: Ui_State, assign_button: Ui_Id) -> Button_Press`: Y (`input.info`, `input.info_down`, with no text field open), or a pointer press on the touch row's Assign (`pointer_press.widget == assign_button`): pressed `state.click` on it, down `press.down && !press.moved`, cancelled `press.down && press.moved` (P2).
- `shown_toolbars :: proc(player: Player, queued: []Queued_Player_Command, unconfirmed: []Player_Command, player_index: int) -> [MAXIMUM_TOOLBAR_COUNT]Toolbar`: `player.toolbars` with the `Toolbar_Assign_Command`s on their way applied in order, the unconfirmed first, then the queue's of `player_index` (as `shown_foundation_block`), one outside the arrays skipped. Every edit reads it, so presses inside the latency window act on what the grid shows.
- `step_toolbar_edit_cursor :: proc(row, slot: int, step: Ui_Direction, count: int) -> (row_after, slot_after: int, shift: bool)`: Left and Right wrap along the row; Up to the row above, nothing on the top row; Down to the row below, on row 0 shift (the cursor stays) while count > 1. At count 1 Up and Down change nothing.
- `toolbar_edit_act :: proc(edit: Toolbar_Edit, shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, cell: Toolbar_Cell) -> (after: Toolbar_Edit, commands: [2]Toolbar_Assign_Command, count: int)`, A or a drop on a cell:
  - nothing held: a cell naming a kind is picked up (holding, origin the cell), an empty one does nothing; no command;
  - held, on the origin: the hold ends; no command;
  - held, on a cell naming the held kind: they merge, `{origin, NO_ITEM}`, the hold ends;
  - held, on any other cell: `{cell, held}` then `{origin, under}` (the cell's kind, NO_ITEM when empty); the hold goes on while under names a kind, with the same origin. A swap holds the new one and the origin stays the hole; a move ends the hold.
- `toolbar_edit_clear :: proc(edit: Toolbar_Edit, shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, cursor: Toolbar_Cell) -> (command: Toolbar_Assign_Command, queues, discards_held: bool)`: held, `{origin, NO_ITEM}` and discards_held; else `{cursor, NO_ITEM}` while the cursor names a kind.
- `toolbar_row_clear_commands :: proc(shown: [MAXIMUM_TOOLBAR_COUNT]Toolbar, toolbar: int) -> (commands: [HOTBAR_SLOT_COUNT]Toolbar_Assign_Command, count: int)`: `{toolbar, slot, NO_ITEM}` per slot naming a kind.
- `toolbar_edit_cell_id :: proc(row, slot: int) -> Ui_Id`: `ui_hash(ui_hash(0, TOOLBAR_EDIT_PANEL_LABEL, -1), "cell", row * HOTBAR_SLOT_COUNT + slot)`, the id the screen registers (its panel opens at depth 0). By row, so a shift keeps the focus on row 0.
- `toolbar_edit_cursor_of_focus :: proc(focus: Ui_Id, count: int) -> (row, slot: int, found: bool)`.
- `clamp_toolbar_edit :: proc(edit: ^Toolbar_Edit, count: int)`: row, slot and first_toolbar into range; the hold ends when `origin.toolbar >= count` (a data reload lowered the count).
- `toolbar_edit_panel_height :: proc(count: int) -> f32`: `UI_ROW_HEIGHT + UI_GAP + slot_grid_height(count) + 2 * UI_PADDING` (176 at one toolbar, 440 at four).
- `toolbar_edit_layout :: proc(panel: Ui_Rectangle, count: int) -> Toolbar_Edit_Layout`: inset by `UI_PADDING`, the title row, a gap, row r at grid line `count - 1 - r` (`slot_grid_rectangle`), so the lowest row is the active toolbar as on the HUD.

Screen procedures:

- `open_toolbar_edit :: proc(state: ^Ui_State, player: Player)`: `toolbar_edit = {slot = selected_hotbar_slot, first_toolbar = active_toolbar, return_focus = crafting_half == .Inventory ? focus : 0}`, push `.Toolbar_Edit`.
- `toolbar_edit_cell :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, id: Ui_Id, entry: Toolbar_Entry, items: Item_Registry) -> Ui_Interaction`, as `ui_item_slot`: `ui_interact` with `{.Tooltip_Shows_Itself, .Item_Slot}` and the kind's name as the tooltip; on `hovered && click` it sets `slot_drag.slot` and `slot_drag.count` (1 naming a kind, 0 empty), so `Slot_Drag` picks up and drops for it; activated `(focused && confirm) || (hovered && slot_drag.released) || (hovered && pointer_source == .Touch && pointer_tapped(state^, id))`, the last adding a Confirm sound (an item slot's tap has none); `widget_background`, the panel edge outline, `draw_toolbar_slot`.
- `toolbar_edit_screen :: proc(state: ^Ui_State, screen_context: Screen_Context)`, in order:
  1. Without a player, pop and return. `count := toolbar_count(content)`; `clamp_toolbar_edit`; the cursor from the focus (the pointer's hover moved it last frame); `shown := shown_toolbars(...)`.
  2. A navigation step: `step_toolbar_edit_cursor`; a shift sets `first_toolbar = (first_toolbar + count - 1) % count` (the top row's toolbar comes down to row 0, the others move up) and queues P1's command; then `requested_focus = toolbar_edit_cell_id(row, slot)` and `navigation_step = .None` (`crafting_seam_target`'s pattern), so `ui_resolve` never steps the focus off the grid. `ui_prefer_focus` the cursor's cell for the opening frame.
  3. `ui_backdrop`; the panel `fitted_panel(ui_panel_area(state), TOOLBAR_EDIT_PANEL_WIDTH, toolbar_edit_panel_height(count))`; `toolbar_edit_title` fitted and centred at the heading size; the cells row by row with `toolbar_entries_of(shown[toolbar_at_row(first_toolbar, count, row)], inventory)`, the origin's cell drawn empty while holding; the activated cell kept.
  4. On touch the row (`ui_touch_row(state, TOOLBAR_EDIT_TOUCH_BUTTONS)`).
  5. An activated cell: `toolbar_edit_act`, its commands queued.
  6. X: `advance_button_hold(clear_hold, {context_action, context_action_down, false}, frame_count, frame_seconds, QUICK_MOVE_REPEAT_SECONDS)`. On the press, or the row's Clear: `toolbar_edit_clear` against `shown_toolbars` read again (this frame's A included); discards_held ends the hold and sets `clear_hold.spent`. On Hold: `toolbar_row_clear_commands` for the cursor's toolbar, queued, and the hold ends (a held one from that row is cleared with it, one from another row stays on its origin).
  7. A drag's end: `slot_drag.released && slot_drag.moved && holding` ends the hold (the swapped kind, or one released off the cells, stays on the origin). A release that did not move keeps it, so a touch tap or an unmoved click on a named cell swaps and holds the new one, as A does.
  8. `slot_drag.holding = holding`; a `.Dragging` phase with nothing held goes to `.None` (as `finish_slot_drag`).
  9. The held kind at `held_stack_rectangle` through `draw_toolbar_slot`.
  10. Off touch `toolbar_edit_glyph_bar`.
- `toolbar_edit_glyph_bar :: proc(state: ^Ui_State, held, cursor_kind: Item_Id)` (held NO_ITEM with nothing held; cursor_kind as drawn, NO_ITEM on the hole): Confirm `hint_swap` when held and the cursor names another kind, `hint_place_stack` when held, `hint_pick_up` on a named cell; Context_Action `hint_clear_shortcut` when held, else `hint_clear_toolbar`; Back `hint_done`.
- `queue_toolbar_assigns :: proc(screen_context: Screen_Context, commands: []Toolbar_Assign_Command)`: each through `queue_player_command`; nothing without a command list.

On touch the cursor is the last focused cell: a tap focuses its cell, and the row's buttons take the focus without moving the cursor, so Clear acts on the tapped cell.

### Changes elsewhere

- `toolbar.odin`: `toolbar_entries_of :: proc(toolbar: Toolbar, inventory: Inventory) -> [HOTBAR_SLOT_COUNT]Toolbar_Entry`; `toolbar_entries` calls it.
- `inventory_screen` (`ui_inventory.odin:268`): after the touch row, `entry_event` from `advance_button_hold(state.toolbar_entry, toolbar_edit_entry_press(state^, touch_row_button_id(state, .Assign_Toolbar)), state.frame_count, state.frame_seconds, TOUCH_HOLD_SECONDS)`; the assign at 342 runs on `assignment != NO_ITEM && entry_event == .Tap` (the row's `.Assign_Toolbar` result is no longer read); after the configure pop-up's open, `else if entry_event == .Hold { open_toolbar_edit(state, player^) }`. `slot_preferred` takes `toolbar_edit.return_focus` after `configure.return_focus`, cleared once the focus lands on it as that one is. The schematics half needs nothing: `settle_recipe_focus` focuses the focused recipe's cell again.
- `inventory_glyph_bar` (with `assign`) and `crafting_view_glyph_bar`: the Info hint is `hint_assign_or_edit_toolbars` where Y assigns, else `hint_edit_toolbars` (in the view, always). `hint_assign` goes.
- `ui_widgets.odin`: `Touch_Button` gains `Clear_Toolbar_Slot` and `Done` after `Zoom_Out`, with their keys; `ui_touch_row` treats `.Done` as `.Back`; `touch_row_button_id :: proc(state: ^Ui_State, button: Touch_Button) -> Ui_Id` (`ui_id(state, text(touch_button_keys[button]))`, at the depth the row was drawn). `.Assign_Toolbar`'s comment: a long press opens the toolbar edit mode.

### Commands and lockstep

- Every change is a `Toolbar_Assign_Command` (0278's, unchanged); a move, a swap and a merge are two, queued in one frame. The frame's commands reach the local member together (`hold_local_commands`) and its next record takes all of them (`stamp_local_record`); offline the next tick takes the whole list. So every machine applies both at the start of one tick, in order, before anything reads the toolbars, and no machine runs a tick between them; the state between them (one kind on two slots) is valid anyway (0278, Settled 3). No swap command.
- P1: `Active_Toolbar_Command :: struct {toolbar: int}` after `Toolbar_Assign_Command` in the union, valid when `index_in_range(toolbar, toolbar_count(content))`, applied as `players[p].active_toolbar = toolbar`; `Player_Command_Tag.Active_Toolbar` after `.Toolbar_Assign` (`session_network.odin:129`) with its encode and decode cases, no tag renumbering. No save change: `active_toolbar` is saved since 0278.

### Sizes

The panel is 728 wide, 176 tall at one toolbar and 440 at four. The panel area is 1037 by 588 units at 1280x800 and UI scale 1.5 and 1414 by 824 on the Deck, so it fits at every audited size; the title at text size 1.6 takes about 250 of 696. Centred, it ends above the HUD's lowest row (550 against 584 at the smallest with four rows); the HUD's higher rows lie under it at four toolbars. The HUD draws under the backdrop and shows each edit once it applies. Clear and Done stand right of the hotbar.

### Strings

`toolbar_edit_title = "Edit toolbars"`, `hint_swap = "Swap"`, `hint_clear_shortcut = "Clear"`, `hint_clear_toolbar = "Clear, hold for the row"`, `hint_done = "Done"`, `hint_assign_or_edit_toolbars = "Assign, hold to edit toolbars"`, `hint_edit_toolbars = "Hold to edit toolbars"`, `touch_button_clear_toolbar_slot = "Clear"`, `touch_button_done = "Done"`. `hint_assign` goes.

### Tests

`ui_toolbar_edit_test.odin` (new). The screen tests give each kind its own inventory count, so a cell's drawn count tells its kind (as `test_two_toolbars_stack_with_the_active_one_lowest`), and restore `audit.content.toolbar_count` after changing it.

- `test_a_button_hold_tells_a_tap_from_a_hold`: down 10 frames then up, Tap on the release frame only; down 20 frames, Hold once on the frame that reaches 0.25 s and None on the release; pressed without down, Tap at once; a tracked press whose next frame number skips one, then released, None; cancelled while down, then released, None.
- `test_the_edit_cursor_steps_and_shifts_the_carousel`: Left at slot 0 gives 7, Right at 7 gives 0; Up on row 3 of 4 stays; Down from row 2 gives 1; Down on row 0 shifts at counts 2 and 4, not at 1; at count 1 Up and Down leave the cursor.
- `test_toolbar_edit_act_picks_drops_swaps_and_merges`: each case of `toolbar_edit_act` with its commands in order, one across toolbars (origin `{1, 3}`, cell `{0, 5}`).
- `test_clear_takes_the_held_shortcut_first_and_the_row_clears_its_named_slots`.
- `test_y_held_opens_the_edit_mode_and_a_short_y_still_assigns` (focus on a log slot, selected slot 2): Y down 10 frames then up queues one `{0, 2, log}` on the release frame and leaves `.Inventory` on top; Y down 20 frames opens `.Toolbar_Edit` with nothing queued, the cursor `(0, 2)`, `first_toolbar` the active toolbar; Y's release in the mode queues nothing.
- `test_the_edit_mode_moves_and_swaps_shortcuts_through_assign_commands` (toolbar 0: log, plank, then empty): A on slot 0, Right twice, A: the frame queues exactly `{0, 2, log}`, `{0, 0, NO_ITEM}`; applied, slot 2's cell draws log's count. A on slot 1 (plank), Right, A on slot 2 (log): that frame queues `{0, 2, plank}`, `{0, 1, log}`, the hold goes on with log drawn at the held rectangle and slot 1's cell empty; applied, `draw_hud_toolbars` draws plank on row 0's slot 2 and log on slot 1 (the HUD follows); B pops the screen and queues nothing.
- `test_backing_out_puts_the_held_shortcut_back`: picked up at slot 3 and moved away, each of B, Pause, the row's Done (on touch) and a tap off the panel pops to `.Inventory` with nothing queued and the toolbars unchanged; after B the focus is the inventory slot Y was held on.
- `test_x_clears_the_slot_and_x_held_clears_the_row`: X pressed on a named slot queues `{cursor, NO_ITEM}` on the press frame and nothing more within 0.5 s; held 40 frames, the row's other named slots clear, once; X pressed with one held queues `{origin, NO_ITEM}`, ends the hold, and that press held 40 frames clears no row; the touch row's Clear acts as the press.
- `test_the_pointer_drags_a_shortcut` (mouse): a click without moving picks up nothing; a press on slot 0 dragged past the slop picks up, released over slot 4 queues the move; dragged onto a named cell, the swap's two commands and the hold ends with the swapped kind on the origin; released off the panel, nothing queued and the hold ends.
- `test_touch_taps_pick_up_and_drop`: a tap on a named cell holds it; a tap on another named cell swaps and still holds; a tap on an empty cell moves and ends the hold; the row draws Clear and Done and no glyph bar draws.
- `test_the_assign_buttons_long_press_opens_the_edit_mode` (P2): a touch press on Assign held 20 frames opens `.Toolbar_Edit` and queues nothing, also on its release; a press that leaves the slop and is released assigns nothing.
- `test_the_focus_never_leaves_the_grid`: at counts 1 and 4, from every cell each of the four steps leaves `state.focus` on `toolbar_edit_cell_id` of the cursor.
- `test_the_modifiers_and_the_window_step_do_nothing_in_the_edit_mode`: A with `modifier_five` and with `modifier_most` held picks up as A; a Left Control click on a named cell dragged past the slop picks up as a plain drag; `window_next`, `window_previous`, `open_inventory` and `open_recipes` leave `.Toolbar_Edit` on top.
- `test_the_carousel_shifts_the_rows_and_the_hud_follows` (count 3, one kind per toolbar): Down on row 0 makes `first_toolbar` 2, row 0 draws toolbar 2's kind and row 1 toolbar 0's, the focus stays on row 0's cell; P1: `Active_Toolbar_Command{2}` queued and, applied, `draw_hud_toolbars` draws toolbar 2's kind on row 0.

Elsewhere:

- `ui_crafting_view_test`: `test_the_crafting_view_bars_offer_assign` expects `hint_assign_or_edit_toolbars` where Y names something and `hint_edit_toolbars` elsewhere. `test_y_assigns_the_focused_slot_or_schematic_to_the_selected_slot` and `test_the_touch_assign_button_assigns` stay as they are.
- P1: `player_command_test`'s `test_the_active_toolbar_command_round_trips_and_applies` (encode and decode equal, toolbar 1 refused at a count of 1 and applied at 2); `lockstep_test`'s `slot_test_commands` also queues `Active_Toolbar_Command{0}` at frame 64.

### UI audit

`Ui_Audit_Case.toolbar_edit: Toolbar_Edit`, copied into `state.toolbar_edit` in `audit_case_at_size` beside `configure.item`. After the configure cases (`ui_audit_test.odin:1355`):

- "toolbar edit": `{.Inventory, .Toolbar_Edit}`, the shipped one toolbar, walk_focus.
- "toolbar edit, four toolbars, one held": `toolbar_count` 4 (restored), every slot named, one kind the inventory lacks (the shade), `{row = 3, slot = 7, holding = true, origin = {1, 3}}`, walk_focus.
- "toolbar edit touch row": touch, hud.

None is obsolete; the crafting view's cases draw the new Y hint.

### Docs

- `doc/ui.md`: the Screens table (Toolbar edit keeps the simulation running); the stack bullet's pushes (the crafting view its configure pop-up and the toolbar edit mode); Architecture's list of what queues commands (the edit mode's moves and carousel); Crafting view's Y bullet (the tap on the release, held `TOUCH_HOLD_SECONDS` the edit mode, Assign's long press on touch); a new "Toolbar edit" section after Configure pop-up (the grid and its rows, the cursor and the carousel, A and the hole, X and X held after 0.5 s, B, the pointer, touch, two commands in one tick); the touch row table (Assign's long press; a Toolbar edit row, Clear and Done).
- `doc/hud.md`, Toolbars: Y held edits the toolbars; P1, the carousel sets the active toolbar.
- `doc/input.md`: the Gamepad table's Y, X, L5 and D-pad rows, menu column; the keyboard paragraph (R held, F held).
- `doc/touch_overlay.md`: the `TOUCH_HOLD_SECONDS` row adds Assign's long press.
- `doc/architecture.md` (the rule of writes, line 167): the edit's commands, two in one record; P1's command.
- `doc/code_map.md`: `ui_toolbar_edit.odin` in the ui list and the counts `code_graph.py --check` reports.

### Hand-back lines that apply

- A number from outside: P1's command is range checked in `player_command_valid`, as the assign is.
- A long string: the title fitted, the hints dropped from the end with Done kept, the tooltip wrapped, the counts fitted; the four toolbar case at the smallest size and at text size 1.6.
- An obsolete audit case: none.
- Tests in memory only. Frame memory, file writes, start-up loads, the save layout (the edit state is the UI's), shared budgets and unbounded lists (at most eight commands a press) do not apply.

### Settled

1. A screen rather than a flag in `Ui_State`: Back, Pause, the tap off the panel, the inert carousel and the focus confined to the grid come from the screen stack, as for the configure pop-up.
2. The assign moves from Y's press to its release, the one change to 0278's behaviour; 0278's tests hold.
3. The simulation keeps the held one on its origin: nothing goes out on a pick up or a back out, a swap is two commands in one tick.
4. Left and Right wrap along the row; Up on the top row does nothing; Down on row 0 rolls the rows up, the top row's toolbar coming down.
5. A held one dropped on a cell naming its kind merges, the origin cleared, as stacks merge.
6. X with one held clears the held one first, as Menu_Drop drops the held stack before the focused one, and that press's hold clears no row.
7. X held waits `QUICK_MOVE_REPEAT_SECONDS` (0.5 s), the hold that extends one action to all (R1 with A held moves every stack), not Y's 0.25 s: it clears up to eight shortcuts and nothing undoes it.
8. The pointer (main agent): the cells are item slots to `Slot_Drag`, so a drag past the slop picks up and its release on a cell moves, swaps or merges, elsewhere puts back; a mouse click without moving only focuses, as on stacks; on touch a tap acts as A.
9. A cell's tooltip names its kind and shows by itself, as an item slot's; the grid draws icons and counts.
10. The crafting view's focus comes back on the slot Y was held on, as after the configure pop-up.
11. The Y hint names the hold, as `hint_place_or_spread` does.

### Provisional, for the main agent

- P1: the carousel is the HUD's. The lowest row is always the active toolbar, Down past it queues `Active_Toolbar_Command`, and the HUD follows on return, which is how the Verify line reads; with all rows shown, a carousel that only reorders the grid would do nothing. It is a way to change the active toolbar before 0280's world control, inert while `toolbars = 1` ships. If declined: `first_toolbar` shifts alone, nothing is queued, the active toolbar's selected slot keeps the HUD's accent outline wherever its row stands, and the HUD follows the edits only.
- P2: touch enters by a long press (`TOUCH_HOLD_SECONDS`) on the crafting view's Assign, Y's touch form, which a tap still is. If declined, touch has no way into the mode and its taps, Clear and Done wait for one.

### Decisions (main agent, 2026-11-13)

1. Approved: the mode as a screen over the crafting view, the pick up sending nothing, every change as `Toolbar_Assign_Command`s in one record.
2. Y short assigns on release, since a hold must not assign first. Accepted as the one change to 0278's behaviour.
3. X held clears the row after 0.5 s, twice the hold that opens the mode: it wipes eight shortcuts with no undo.
4. P1, yes: the carousel past the lowest row makes that row the active toolbar through `Active_Toolbar_Command`, which is the item's "the rows shift as a carousel" and "the HUD follows". No world control switches toolbars; that stays 0280's.
5. P2, yes: on touch a long press on the crafting view's Assign button opens the mode, the button's own hold as Y's.
6. The pointer drags a shortcut as it drags a stack (the Controls section's open point).
