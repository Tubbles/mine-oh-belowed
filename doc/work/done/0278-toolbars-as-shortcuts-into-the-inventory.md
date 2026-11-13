# 0278: Toolbars as shortcuts into the inventory

Status: landed (2026-11-13, ac76d591)

## Goal

The hotbar stops being a row of the inventory and becomes toolbars of shortcuts into it, Techtonica's way (user, 2026-10-05): a toolbar slot names an item kind and shows the inventory's count of it, selecting it holds that item, placing draws from the inventory by kind. Two toolbars at the start (a data number, more later), stacked on the HUD, the lower one active; the d-pad swaps the rows as a carousel and steps along the active one (0280). Y on a slot or a schematic assigns it to the selected toolbar slot (0276). The left trackpad's radial shows the active toolbar.

## Controls

Main agent, 2026-11-13. No new binding.

- Y in the crafting view (0277), on an inventory slot or a schematic: assigns its item kind to the selected slot of the active toolbar, with a toast naming both. The info panel leaves Y in that view only (the schematic's detail panel and the slot's name line carry what it showed) and stays on Y on every other screen. On a machine or chest panel Y stays the info panel: shortcuts are assigned from the crafting view.
- The world's controls do not change in this item: the d-pad's Left and Right and the bumpers step along the active toolbar as they step the hotbar today, the trackpad's radial and the touch slot taps select from it.
- Swapping the active row is 0280's (the d-pad's Up and Down, the user's to approve), so this item ships `toolbars = 1` in `game.sjson`, with the rows, the carousel order and the HUD's stack built and tested at 2. 0280 raises the number. Nothing here invents a row swap control.
- The toolbar edit mode is 0279.

## Change

- The simulation: the player's hotbar grid becomes `toolbars` of item kinds in the save, with a remap for old saves (the hotbar's stacks move into the main grid, their kinds become the first toolbar, one log line). The main grid grows by one row to 45 slots (five rows of nine, the row the hotbar leaves in the panel), so nothing spills (main agent, 2026-11-13).
- Place, Use_Item, the tools and Drop_Stack take the first stack of the selected kind; a kind the inventory lacks greys the slot and does nothing. The quick move between the backpack and the hotbar goes.
- The HUD's two rows, the radial, the touch overlay's slot taps (0119), the glyph bar's held hints, the UI audit's HUD cases.
- Data: the toolbar count in `game.sjson` (1 to 4).
- Docs: `DESIGN.md` (The player, the inventory line), `doc/ui.md` (Item slots, Active grid), `doc/hud.md`, `doc/architecture.md` (the save), `doc/content.md` (the key), `doc/touch_overlay.md`.

## Verify

- Tests: assign, select, place consumes by kind, an empty kind places nothing, the carousel's order, the remap of an old save (the dev kits).
- The UI audit's HUD cases at every size.
- The couch.

## Specification (design, 2026-11-13)

Designed against 0277's specification, which is being implemented on `item/0277` and is not on `main`: `Screen.Inventory` is the crafting view, its inventory half runs `player_slot_region` in the panel `"inventory"`, and Y there is still the info panel. This item lands after 0277. No split: the hotbar leaves the slot array, the save and every slot screen at once, and a half step (toolbars beside a live hotbar row) would need a second save remap.

### State and data

- `inventory.odin`: `PLAYER_INVENTORY_SLOT_COUNT :: 45`, five rows of `INVENTORY_COLUMNS`. `PLAYER_GRID_SLOT_COUNT`, `inventory_hotbar` and `inventory_grid` go. `HOTBAR_SLOT_COUNT` (8) stays: the slots of one toolbar. `player_command_slots.odin` asserts `PLAYER_INVENTORY_SLOT_COUNT <= MAXIMUM_CHEST_SLOTS`. The comments of `inventory_add` (slot order) and `inventory_remove` (the first stack in slot order empties last) follow.
- `Player`: `toolbars: [MAXIMUM_TOOLBAR_COUNT]Toolbar` and `active_toolbar: int` after `selected_hotbar_slot`, which keeps its name (old saves keep the value) and is the selected slot of the active toolbar. `make_player` sets `toolbars = empty_toolbars()`. The field's comment: Item_Id 0 is an item and the codec zeroes a fixed array's missing tail, so raising `MAXIMUM_TOOLBAR_COUNT` needs `read_players` to fill new rows with NO_ITEM. Both fields reach the save and the state hash through `write_value_of`.
- `Simulation_Content.toolbar_count: int`, set from `Game_Config.toolbars` in `load_game_tables`, read only through `toolbar_count`.
- `data/game.sjson`: `toolbars = 1` after `tech_demo_items`, comment "The toolbars stacked on the HUD (work item 0278, doc/content.md): 1 to 4." `validate_game_config` refuses `toolbars %d is outside 1 to 4`, required like its neighbours.

New `src/toolbar.odin` (simulation cluster):

- `MAXIMUM_TOOLBAR_COUNT :: 4`, `Toolbar :: [HOTBAR_SLOT_COUNT]Item_Id`.
- `empty_toolbars :: proc() -> [MAXIMUM_TOOLBAR_COUNT]Toolbar`: every slot NO_ITEM.
- `toolbar_count :: proc(content: Simulation_Content) -> int`: `content.toolbar_count` clamped to 1..4, so a test's zero content has one.
- `selected_kind :: proc(player: Player) -> Item_Id`: `toolbars[active_toolbar][selected_hotbar_slot]`.
- `selected_stack_index :: proc(player: Player) -> int`: the lowest slot index whose stack is not empty and holds the selected kind; -1 for NO_ITEM or none.
- `take_toolbar_slot :: proc(player: ^Player, item: Item_Id) -> bool`: when no row names the item, the active toolbar's first NO_ITEM slot names it; true when it is named.
- `clamp_toolbar_selection :: proc(player: ^Player, count: int)`: `active_toolbar` to 0..count-1, `selected_hotbar_slot` to 0..7.
- `Toolbar_Entry :: struct {item: Item_Id, count: int}`; `toolbar_entries :: proc(player: Player, toolbar: int) -> [HOTBAR_SLOT_COUNT]Toolbar_Entry`: each slot's kind and its `inventory_count`.
- `toolbar_at_row :: proc(active, count, row: int) -> int`: `(active + row) % count`; row 0 is the lowest. The carousel's order: the active toolbar lowest, the next ones above it (at 2 with the second active 1, 0; at 4 with the third 2, 3, 0, 1).
- P1's procedures below.

### The selected kind

- "The first stack of the selected kind" is `selected_stack_index`: slot order, the grid's reading order. `selected_hotbar_stack` returns that slot's stack, EMPTY_STACK at -1.
- Every reader through `selected_hotbar_stack` keeps its code and follows the rule: the ghost (`selected_placed_machine`, `selected_placed_block`, `selected_placement_rotates`), the field tool (`field_tool_for_item` gives Hand), `update_magnetometer`, the cable run (`queue_field_cable`; the run bound to `cable_slot` ends when the held item stops being a cable, as when the stack ran out), the placement editor (cancels when the held machine goes), the hands (`loop.odin`), the held hints (`world_glyph_hints`), `command_field.odin`'s `held`, `diagnostics.odin`. `player_tool_tier` counts every slot, unchanged.
- The last item of the kind placed, used or dropped: the index is -1 from the next read, so the slot greys, the hand holds nothing, the ghost goes. The kind stays named.
- `place_block_with_player` (player_interaction.odin:324), `place_entity_with_player` (entity_placement.odin:265) and `resolve_use_item` (schematic.odin:79) take from `&player.inventory.slots[selected_stack_index(player^)]` where they took from the hotbar slot; `resolve_use_item` checks the index first, the two places are reached only with a non-empty selected stack. The field's drains (`inventory_remove`) are unchanged.
- `player.odin`'s Drop_Stack drops `selected_stack_index(player^)`; -1 drops nothing (`drop_player_stack` already refuses it).

### Kits name their kinds

- After the add, `take_toolbar_slot` for each kind: `give_starting_items` (foundations on slot 1, the torch on slot 2, as game.sjson's comment says), `give_to_player` when anything went in (the `give` command, `give_kit`, `--chapter`), `give_planet_preview_items`. The tech demo (`session.odin`) sets `player.toolbars = empty_toolbars()` where it clears the inventory, so its six kinds stand in order. A kit of more than 8 kinds leaves the rest unnamed.

### P1, provisional: arrivals take a slot

0128 sent a picked up tool or machine to an empty hotbar slot, and crafted outputs filled the hotbar first. Carried over: a Tool or Machine item arriving by a pick up or as a hand craft's output takes `take_toolbar_slot` while the inventory holds it.

- `item_takes_toolbar_slot` (renamed `item_takes_empty_hotbar_slot`).
- `offer_toolbar_slot :: proc(player: ^Player, items: Item_Registry, item: Item_Id)`: when `item_takes_toolbar_slot` and `inventory_count > 0`, `take_toolbar_slot`.
- `add_picked_up :: proc(player: ^Player, items: Item_Registry, item: Item_Id, count: int) -> (leftover: int)`: `inventory_add`, then the offer when anything went in. Replaces `inventory_add_picked_up` at player_interaction.odin:157, loose_item.odin:260, field_trees.odin:345, cable_field.odin:162, simulation_field.odin:343 and in `take_entity_into_inventory`, which takes `player: ^Player` instead of `inventory` (both callers have it). `credit_field_volume` (terrain materials) calls `inventory_add`.
- `offer_crafted_outputs :: proc(player: ^Player, items: Item_Registry, outputs: []Item_Stack)` after `advance_crafting` finishes (player.odin:638, simulation_field.odin:462) with `content.recipes.recipes[finished].outputs`.
- `inventory_add_picked_up` and `inventory_fits_all_picked_up` go; the fit checks call `inventory_fits_all`.
- If declined: the sites call `inventory_add`, the offers and their test go.

### The assign command

- `Toolbar_Assign_Command :: struct {toolbar: int, slot: int, item: Item_Id}` after `Hotbar_Slot_Command` in the union. Valid when `index_in_range(toolbar, toolbar_count(content))`, `index_in_range(slot, HOTBAR_SLOT_COUNT)` and `item_valid(item, content.items, true)`. Applied in the tick: `toolbars[toolbar][slot] = item`. NO_ITEM clears a slot (0279's). One kind may stand on several slots.
- `Player_Command_Tag.Toolbar_Assign` appended after 0277's `Clear_Craft_Queue`, with its encode and decode cases. No tag renumbers.

### Y in the crafting view

- `ui_begin` (ui_core.odin:877) skips the info toggle and forces `tooltip_open` false while the top screen is `.Inventory`, as in the world. Item slots keep their delayed tooltip (`Tooltip_Shows_Itself`), the slot's name line; the schematic's detail panel stays. The configure pop-up is its own screen, so Y there is the info panel.
- `toolbar_assignment :: proc(half: Crafting_Half, slot_stack: Item_Stack, on_cell: bool, recipe: int, recipes: Recipe_Registry, available: []bool) -> Item_Id` (pure, `ui_crafting_view.odin`): the inventory half gives the focused slot's item (with touch the active slot's), whatever the hand holds; the schematics half on a cell gives `focused_recipe`'s first item output when it is available. NO_ITEM for an empty slot, the toggle, a graph row, a locked recipe, a recipe without an item output.
- `queue_toolbar_assign :: proc(state: ^Ui_State, screen_context: Screen_Context, item: Item_Id)`: nothing without a command list; queues `Toolbar_Assign_Command{player.active_toolbar, player.selected_hotbar_slot, item}` with `queue_player_command` and toasts `toast_toolbar_assigned`, `{name}` the item's name, `{value}` the slot 1 to 8 (`replace_message_mark`).
- `inventory_screen` after the slot input: on `state.input.info && state.keyboard.field == 0` (or P2's button) with a `toolbar_assignment` other than NO_ITEM, `queue_toolbar_assign`.
- Machine and chest panels: Y stays the info panel and their bars offer no assign.

### The inventory without the hotbar

- `player_slot_region`: one `ui_slot_grid(state, origin, "grid", INVENTORY_COLUMNS, player.inventory.slots, items)`, its results slot indices. The label, the hotbar grid, its outline, `grid_result_to_inventory` and `merge_grid_results` go. `INVENTORY_ROWS :: PLAYER_INVENTORY_SLOT_COUNT / INVENTORY_COLUMNS` (5).
- `inventory_panel_height` = `UI_ROW_HEIGHT + slot_grid_height(INVENTORY_ROWS) + 2 * UI_PADDING` = 520 (was 576). The region needs 432 where 0277 counts 488.
- `selected_kind_slot_id :: proc(state: ^Ui_State, player: ^Player) -> Ui_Id` replaces `selected_hotbar_slot_id`: the grid slot `max(selected_stack_index, 0)`, the preferred focus of the inventory half and the machine panels.
- The inventory's own quick move goes: `Quick_Move_Side.Hotbar` and `.Backpack`, `inventory_quick_move_target`, `apply_inventory_quick_move`, `inventory_quick_move_destination`, `inventory_quick_move_origin`, `move_slot_to_section`, `apply_slot_command`'s NO_ENTITY branch. `quick_move_command_fits` refuses NO_ENTITY. `apply_inventory_quick_move_input` goes; `inventory_screen` keeps its last line inline (a press with R1 or L1 activates nothing). R1 A, L1 A and Left Control with a click do nothing on the inventory half; the machine panels' quick move is unchanged.
- `Slot_Grid_Kind.Hotbar` and `sort_target_grid` go: a player slot is `.Main` (`active_slot_after_focus`, `player_slot_index`), `grid_slots(.Main)` is every slot, `transfer_target_grid(.Inventory, _)` is `.None`, the sort gates compare `active.grid` directly. `inventory_order_hotbar_last` goes; `store_item`, `store_all_order` and `fill_from_inventory` run in slot order.
- Sort sorts the 45 slots (`slot_sort_command` and `sort_target_slots` take `inventory.slots`). No slot verb touches the toolbars. Even Distribution is unchanged, over the one grid.
- `INVENTORY_TOUCH_BUTTONS :: Touch_Buttons{.Sort, .Split, .Drop, .Back}` (P2 adds one): the transfers have no pair in the inventory.
- `inventory_glyph_bar` gains `assign := false`: `{.Info, text("hint_assign")}` when the focused slot holds a stack. The view passes `quick_move = false, assign = true`, the machine panels as today. `crafting_view_glyph_bar(state, on_cell, assigns: bool)` shows the same hint when `toolbar_assignment` is not NO_ITEM.

### The HUD

- `hud_toolbar_row_rectangles :: proc(area: Ui_Rectangle, selected, row: int) -> [HOTBAR_SLOT_COUNT]Ui_Rectangle`: row 0 is `hud_hotbar_rectangles(area, selected)`; a higher row's slots are `UI_SLOT_SIZE` square from the same left edge at a step of `UI_SLOT_SIZE + UI_GAP`, top at `bottom - UI_SLOT_SIZE * HUD_SELECTED_SLOT_SCALE - row * (UI_SLOT_SIZE + UI_GAP)`, a gap above the enlarged slot.
- `hud_toolbar_stack_top :: proc(area: Ui_Rectangle, rows: int) -> f32`: `bottom - UI_SLOT_SIZE * HUD_SELECTED_SLOT_SCALE - (rows - 1) * (UI_SLOT_SIZE + UI_GAP)`.
- `draw_toolbar_slot :: proc(state: ^Ui_State, rectangle: Ui_Rectangle, entry: Toolbar_Entry, items: Item_Registry)`: nothing for NO_ITEM; the icon as `draw_item_stack` insets it; above 1 the count with `draw_text_fitted` in `draw_item_stack`'s count area (up to 9000, 45 stacks of 200); at 0 `HUD_EMPTY_KIND_SHADE :: Ui_Color{24, 26, 34, 170}` over the icon.
- `draw_hud_toolbars :: proc(state: ^Ui_State, player: Player, items: Item_Registry, count: int)` replaces `draw_hud_hotbar`, called with `toolbar_count(screen_context.content)`: row r draws `toolbar_at_row(active_toolbar, count, r)` at `hud_toolbar_row_rectangles` as the hotbar drew (fill, outline, the selected outline on row 0 only) with `draw_toolbar_slot`; a higher row gets `HUD_INACTIVE_ROW_SHADE :: Ui_Color{24, 26, 34, 110}` over each slot. The name line stands a gap above `hud_toolbar_stack_top` whenever the selected slot names a kind, in `UI_DIM_TEXT_COLOR` when the inventory lacks it.
- `hud_glyph_bar_above_bottom(safe, rows: int)`: `hud_toolbar_stack_top(safe, rows) - UI_GAP - UI_ROW_HEIGHT - UI_GAP`. `hud_glyph_bar_layout` and `ui_hud_glyph_bar` gain `rows: int`, the callers pass `toolbar_count`. The bar beside row 0, the craft queue left of it and the touch row strip right of it are unchanged; a higher row is narrower than row 0 from the same left edge, so neither meets it.
- The radial: `draw_hotbar_radial(state, entries: []Toolbar_Entry, items)` draws with `draw_toolbar_slot`, the highlighted slot's name whenever it names a kind; `hotbar_radial` passes `toolbar_entries(player^, player.active_toolbar)[:]`.
- Touch: the slot taps, the long press drop and `hud_hotbar_pixel_rectangles` stay row 0's. A higher row is no touch target (0280).

Layout in UI units (safe bottom B, the target lines' band ends at H/2 + 194):

| Size | Row 0 left, selected top | Row 1 (two toolbars) | Name line top (one, two) | Bar above, bottom (one, two) | Band end |
| --- | --- | --- | --- | --- | --- |
| 1920x1080 (1.0), B 1026 | 602, 926 | 838 to 918 | 862, 774 | 854, 766 | 734 |
| 1280x800 (1.5), the smallest, B 684 | 218, 584 | 496 to 576 | 520, 432 | 512, 424 | 554 |

At 1080 two rows and their name clear the band; the bar above (used only when it does not fit beside) keeps one row whose top, 722, lies 12 into the band, as at UI scale 1.2 today. Row 1 clears the band only for H ≥ 849 units, so at UI scale 1.5 it overlaps the target lines. Shipped at 1 nothing moves; 0280 inherits the overlap when it raises the count.

### The save

- `saved_struct_has_field :: proc(reader: Byte_Reader, name: string) -> bool` (save_binary.odin): the schema peek of `saved_list_has_field`, which calls it after its u32.
- `read_players`: per player, `legacy := !saved_struct_has_field(reader^, "toolbars")`; a legacy player is read into an inventory of `HOTBAR_ERA_INVENTORY_SLOT_COUNT :: 44` slots, then `move_hotbar_into_inventory`.
- `move_hotbar_into_inventory :: proc(player: ^Player)` (save_state.odin): a new 45 slot inventory with new[i] = old[8 + i] for i < 36, new[36 + j] = old[j] for j < 8, new[44] empty; `toolbars = empty_toolbars()`, `toolbars[0][j]` the item of a non-empty old[j]; `held.origin_slot` j < 8 becomes 36 + j, 8 + i becomes i, -1 stays; the old inventory freed.
- It always fits: the map takes 44 slots one to one into 45 (36 + 8 = 44), nothing merges, nothing is left, so no overflow rule exists. `#assert(HOTBAR_ERA_INVENTORY_SLOT_COUNT < PLAYER_INVENTORY_SLOT_COUNT)`. A gone item is NO_ITEM after the content remap, so its toolbar slot is NO_ITEM.
- `read_simulation_state` runs `clamp_toolbar_selection(&player, toolbar_count(content))` on every player after `read_players`.
- One line when any moved: `save: written before the toolbars (0278), %d hotbars moved into the inventory's fifth row and onto the first toolbar` (`platform.log_printf`). An older build refuses a new save (the inventory's slice length), as any inventory change does.

### Strings

- `hint_assign = "Assign"`, `toast_toolbar_assigned = "{name} on slot {value}"`; P2's `touch_button_assign_toolbar = "Assign"`.
- `inventory_hotbar` goes. The three schematic descriptions say "Read it from the toolbar."

### Tests

`toolbar_test.odin` (new):

- Helper `hold_test_stack :: proc(player: ^Player, stack: Item_Stack)`: slot `selected_hotbar_slot` holds the stack and the active toolbar's selected slot names its item (NO_ITEM for an empty stack). Every test writing `inventory_hotbar(...)[i]` moves to it, or names each kind on its slot.
- `test_the_selected_kind_holds_the_first_stack_in_slot_order`: dirt at slots 30 and 7 gives 7; NO_ITEM and an absent kind give -1 and EMPTY_STACK; a named absent furnace gives NO_MACHINE.
- `test_take_toolbar_slot_names_a_kind_once`: the first empty slot; a kind named on toolbar 1 is not named again; a full active toolbar returns false.
- `test_toolbar_rows_stack_the_active_one_lowest`: `toolbar_at_row` at (0, 1), (1, 2) and (2, 4) for every row.
- `test_the_kits_name_their_kinds`: the shipped starter kit names foundations then torch and selects foundations; the tech demo kit its six kinds in order; `give` of a stone furnace names it on the first empty slot.
- `test_arrivals_offer_tools_and_machines_a_toolbar_slot` (P1): a picked up furnace and a crafted shovel get a slot, a picked up log and a crafted plate do not, a named kind is not named twice.

Elsewhere:

- `player_interaction_test`: `test_place_draws_from_the_first_stack_of_the_kind` (dirt at 3 and 20, two places take slot 3 down by 2); `test_an_absent_kind_places_and_uses_nothing` (a named dirt and a named schematic, none held: no block, no use, the field tool Hand); `test_the_last_item_placed_leaves_the_kind_named_and_the_hand_empty`.
- `loose_item_test`: `test_drop_stack_drops_the_selected_hotbar_stack_in_the_world` becomes `test_drop_stack_drops_the_first_stack_of_the_kind`.
- `player_command_test`: `test_the_toolbar_assign_command_round_trips_and_applies`: encode and decode equal; applied at the next tick; toolbar 1 refused at a count of 1 and applied at 2; slot 8 and an unknown item refused; NO_ITEM clears.
- `save_test`: `test_an_old_save_moves_the_hotbar_into_the_fifth_row`: a test struct with the old player's `inventory` (44 slots), `selected_hotbar_slot` and `held` (origin 2), written as `player_field_test`'s round trip writes one, read by `read_players`: the grid at 0 to 35, the hotbar at 36 to 43, 44 empty, `toolbars[0]` the old kinds with NO_ITEM for an empty hotbar slot, the other rows NO_ITEM, origin 38, the selection kept. `test_a_loaded_toolbar_selection_is_clamped`: 3 and 12 at a count of 1 give 0 and 7.
- `hud_test`: `test_the_toolbar_shows_counts_and_greys_an_absent_kind` (dirt 250 in two stacks draws "250", an absent kind its shade and a dim name, NO_ITEM no icon); `test_two_toolbars_stack_with_the_active_one_lowest` (count 2, the second active: row 0 draws its icons, row 1 the first's with the shade, the name above row 1, the bar above at 766 at 1080p).
- `ui_crafting_view_test`: `test_y_assigns_the_focused_slot_or_schematic_to_the_selected_slot` (selected slot 2: Y on logs queues `{0, 2, log}` and toasts "Log on slot 3"; on an available cell its first output; an empty slot and a locked recipe queue nothing; `tooltip_open` stays false; on a chest panel Y toggles it and queues nothing); `test_the_crafting_view_bars_offer_assign`.
- `data_load_test`: `test_toolbars_outside_one_to_four_refuse_game_config` (0 and 5 refused with the message, 1 and 4 load).

Changed or removed:

- `inventory_test`: `test_hotbar_is_a_window_onto_the_slots`, `test_picked_up_items_fill_a_partial_hotbar_stack_first`, `test_picked_up_raw_items_take_an_empty_hotbar_slot_only_with_the_grid_full` go; `test_picked_up_tools_and_machines_go_to_the_hotbar` becomes P1's test.
- `quick_transfer_test`: `test_inventory_quick_move_target`, `test_inventory_quick_move_between_hotbar_and_backpack`, `test_inventory_quick_move_all_of_one_item`, `test_inventory_quick_move_into_a_full_section_leaves_the_stack`, `test_grid_transfer_between_hotbar_and_main_grid` go; `test_transfer_target_grid_per_screen` expects `.None` for the inventory.
- `ui_inventory_test`: `test_x_on_the_hotbar_sorts_the_main_grid` becomes `test_x_sorts_the_whole_inventory`; `test_the_touch_row_in_the_inventory` the new row; `test_sort_touches_only_the_active_grid`, `test_a_left_control_click_quick_moves_the_pressed_slot` and `test_modifiers_with_a_on_a_slot` keep their machine panel cases and expect nothing queued in the inventory.
- `inventory_interaction_test`: `test_active_slot_follows_the_focused_grid` drops `sort_target_grid`; `test_radial_selects_hotbar_slot` names its kinds.
- `player_interaction_test`: `test_player_mines_block_onto_its_hotbar_stack` checks the partial stack in slot order.
- `ui_audit_test`: `test_pause_menu_and_initial_focus` (1201, 1208) expects the `"grid"` slot of the first stack of the selected kind; `test_inventory_screen_quick_move_and_drop` becomes `test_inventory_screen_drop`; line 1527 checks `inventory_title` absent; `inventory_hotbar_slot_test_id` becomes `inventory_grid_slot_test_id` (`"grid"`).
- 0277's tests: `inventory_slot_id("hotbar", 7)` becomes `inventory_slot_id("grid", 44)`, "Down from the hotbar" becomes Down from the last row, `open_inventory` focuses `selected_kind_slot_id`.

### UI audit

- "hud magnetometer", "hud field furnace held", "hud field nothing held", the configure cases and `set_glyph_bar_test_player` go through `hold_test_stack`.
- Added: "hud field kind missing" (a furnace named, none held: the shade, the dim name, no held hints); "hud two toolbars" (`toolbar_count` 2, both rows named, the furnace held, the count restored); "hud radial" runs with one kind missing.
- `audit_glyph_bar_clear_of_hotbar` and `expect_glyph_bar_clear_of_hotbar` check every drawn row.
- None obsolete: the panel's hotbar row goes with its state; the toolbar draws on the HUD.

### Docs

- `DESIGN.md`, The player: line 36 (45 slots, toolbars of kinds over them, the radial shows the active one); line 53 "the radial toolbar".
- `doc/ui.md`: Item slots and Active grid (one grid of 45, no hotbar row, no quick move in the inventory, the touch row); Y in the crafting view; the preferred focus.
- `doc/hud.md`: the toolbars, the counts, the grey slot, the rows and their order, the name line, the bar above, the band note above.
- `doc/input.md`: the Y and L5 rows' menu column, Left Control's quick move only in machine panels, the left trackpad row (the active toolbar).
- `doc/touch_overlay.md`: the taps on row 0, the inventory row.
- `doc/architecture.md`: the player's state (the toolbars, the first stack rule, the assign command); Save format (the remap beside the slice length rule).
- `doc/content.md`: the `toolbars` key; the starting items name their kinds.
- `doc/logistics.md`, Routing: slot order and P1's offer.
- `doc/commands.md`: `hotbar_slot` is the active toolbar's slot, `held` the first stack's item.
- `doc/build.md` 172 and 209: named on the toolbar, one entry per toolbar slot.
- `doc/code_map.md`: `toolbar.odin` in the simulation cluster.

### Hand-back lines that apply

- A number from text: `toolbars` bounded at load; a save's `active_toolbar` and `selected_hotbar_slot` clamped.
- A changed save layout: the remap and its line; the kits and `give` name their kinds, so a chapter start plays (`test_the_kits_name_their_kinds`).
- A long string: the count fitted at 9000; the toast's name as every item toast.
- An obsolete audit case: none, the added ones above.
- Tests in memory only. Frame memory, file writes, start-up fallbacks and shared budgets do not apply.

### Settled

1. "Hotbar" stays the name of the active toolbar's selection (`selected_hotbar_slot`, the `Hotbar_*` actions, `Hotbar_Slot_Command`, the radial): old saves keep the field and the bindings file does not change.
2. Place and Use_Item take from the first stack, as the item says, so the hand, Drop and the place agree on one stack.
3. One kind may stand on several slots: a refusal would need a rule nobody asked for, and 0279 moves shortcuts.
4. The new row is the bottom one, where the hotbar sat in the panel, so stacks keep their place on screen.
5. Y assigns the slot's kind whatever the hand holds; the hand is a cursor.
6. A locked recipe assigns nothing: its slot would stay grey until research.
7. The preferred focus is the first stack of the selected kind, the hotbar slot's successor.

### Provisional, for the main agent

- P1: arrivals take a slot (above).
- P2: touch has no Y, so without a button touch cannot assign. `Touch_Button.Assign_Toolbar` after `.Drop`, in `INVENTORY_TOUCH_BUTTONS` and `CRAFTING_VIEW_TOUCH_BUTTONS` (then 7), acting on the active slot or the selected recipe while shown, through `toolbar_assignment`. The audit's touch label check decides whether 7 fit at the smallest touch size; a test `test_the_touch_assign_button_assigns` and the touch row cases follow.
- Q1: 0277's view is full height, so it covers the HUD's toolbar and the toast is the only sign of the slot assigned to. A row of the active toolbar under the grid needs 520 units of the half, which 1280x800 at 1.5 (492) lacks. Not designed here.

### Decisions (main agent, 2026-11-13)

1. Approved, unsplit, to land after 0277.
2. P1: yes. A tool or a machine that arrives by a pick up or as a hand craft's output names itself on the first empty toolbar slot, as the hotbar took it first before.
3. P2: yes. The crafting view's touch row gets an Assign button, the touch form of Y, as every touch row button is a screen control. If seven buttons do not fit whole at the smallest audit size, Cancel last gives way on the inventory half and Assign on neither.
4. Q1: the toast is the sign of which slot was assigned. A toolbar row inside the view is 0279's (the edit mode shows the toolbars as a grid).
5. Correction to the specification: on the inventory half L1 with A still splits a stack, as on every slot. Only R1 with A (the quick move between the backpack and the hotbar) has nothing left to do there, and it stays the quick move on machine and chest panels. The implementer follows this where the specification says both do nothing, and the tests assert the split.
6. 0216 (the pipette) is designed after this item: it selects the toolbar slot naming the kind, or assigns the kind to the selected slot.

### Deviations (implementation, 2026-11-13)

- `inventory_test`'s `test_picked_up_raw_items_go_to_the_main_grid` and `test_picked_up_fits_check_follows_the_routing` go too: they tested the removed routing.
- `test_item_tooltip_shows_itself_after_the_delay` runs on a machine panel: on the inventory the Info toggle no longer opens the panel, which its last step needs.
- `test_a_left_control_click_quick_moves_the_pressed_slot` had no machine panel case, so it gained a chest's slot quick moved by a Ctrl click.
- `test_slot_commands_keep_two_machines_in_step` (lockstep): the inventory's quick move became a `Toolbar_Assign_Command`, the inventory's grid transfer one into the inserter, and the sort is queued before Fill, since Fill now draws from the slots the sort's order covers and made it stale.
- The test helpers that gave a player items to hold (`add_test_miner`, `give_test_items`) name each kind on the toolbar (`give_test_kind`), as the old slot order selected the first stack given.
- `moved_hotbar_era_slot` holds the held stack's origin map as its own pure procedure; `read_players` prints the remap's line.
