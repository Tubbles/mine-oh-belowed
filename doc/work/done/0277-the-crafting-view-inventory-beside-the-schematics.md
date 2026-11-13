# 0277: The crafting view, the inventory beside the schematics

Status: landed (2026-11-13, 5138746f)

## Goal

The inventory binding opens one view with the inventory on the left half and the schematics on the right half, Techtonica's way (user, 2026-10-05: with a chest or a machine open one shuffles items, with the own inventory open one crafts). The schematics are a grid of icons under category tabs with the detail panel for the focused one, in place of the Recipes tab's list. The machine and chest panels keep the transfer view and gain no schematics. The list with the letter wheel stays as the browser of the picker and station modes. On the 0276 layer and 0385's carousel.

## Controls

- D-pad or left stick: the focus across both halves, Left and Right crossing the seam.
- A: craft one. R1 with A: craft five. L1 with A: craft the most the inventory affords (the planner's N).
- X on the schematics half: clears the whole crafting queue (the user's Techtonica note), and so does the keyboard's F, the same action; on the inventory half: sort or configure as now. A control's meaning never depends on the device that pressed it. Cancel last, which X and F do in the recipe browser since 0276, has no gamepad or keyboard control in this view: it is the touch row's button here (main agent, 2026-11-13). The station browser keeps X and F as Cancel last.
- Right stick: a flick steps the category tabs (0276), from either half. The tabs come from the data's categories, mapped by a key on the category, never by name in code. "Unlocked only" is a toggle in the schematics half's header that the focus reaches, not a tab and not a cycled control (main agent, 2026-11-13).
- Y: the info panel as now, until 0278 gives it the toolbar assignment.
- L2, R2: the carousel (0385), where this view takes the place of its first two windows, Inventory and Recipes, so six windows remain. C opens this view with the focus on the schematics half, the inventory binding with the focus on the inventory half (main agent, 2026-11-13).
- Touch: the recipe row's buttons (Craft, Craft 5, Craft max, Cancel last, Back) while a schematic is focused, the inventory's while a slot is; a Clear queue button joins the recipe row.
- B: pops one level of the screen stack (0385), so from the world's view to the world.

## Change

- `ui_inventory.odin`: the schematics half with a grid widget, the recipe browser's detail panel and plans (`Recipe_Plans`) reused; the Recipes window leaves 0385's carousel.
- The crafting queue's clear as a `Player_Command` (lockstep as the crafts are).
- Docs: `doc/ui.md` (Screens: the crafting view, the recipe browser's remaining modes). `doc/hud.md` needs no change: it names no screen control.

## Verify

- Tests: the focus crosses the seam and wraps inside each half; the craft counts through the modifiers; the clear queue command; the categories come from the data.
- The UI audit at every size, the grid at 1080 and at the smallest size.
- The couch.

## Specification (design, 2026-11-13)

Designed against 0385's worktree (`item/0385`, verified, not on `main` yet): its carousel, stack and title row are the base, and every file and procedure named here is as it stands there. The implementer's worktree starts from 0385's tip.

### The screens after this item

- `Screen.Inventory` is the crafting view: one panel, the inventory half left, the schematics half right. `inventory_screen` stays its entry, so `run_screens` is unchanged.
- `Screen.Recipes` keeps only the picker and the station mode, both outside the carousel as today. `recipe_screen` with neither mode pops itself and returns (the vanished station's precedent); its title row branch goes, so it always draws the station's name or "Choose a recipe".
- The carousel: Inventory, Journal, Research, Map, Statistics, Power (six). The view's title stays `inventory_title` ("Inventory", decision 6).
- From the world the inventory binding pushes `.Inventory` on the inventory half, C pushes `.Inventory` on the schematics half. On the view C pops it as a window's own key, as the inventory binding does (except as the context action or the keyboard's window step, as today).
- The machine panels, the chest, the picker and the station browser keep their screens, lists and letter wheel. The station browser's X and F stay Cancel last.

### Layout

The panel is `fitted_panel(area, CRAFTING_VIEW_WIDTH, area.height)` with `area := ui_panel_area(state)`, full height, `CRAFTING_VIEW_WIDTH` 1712 = 784 + 2 × 16 seam + 864 + 2 × 16 padding. Inside the padding: the title row (56) and a gap across the whole width; the inventory half 784 wide (`slot_grid_width(INVENTORY_COLUMNS)`, its slots at its top as today); the seam, 2 × `UI_PADDING`, with a vertical line of the theme's border width in the panel edge colour at its centre; the schematics half, W wide, the rest. The schematics half from the top: the tabs (56), a gap, the header (56: the "Unlocked only" toggle and the queue summary as the two halves of `column_rectangle`), a gap, the body.

- Side by side when W ≥ `CRAFTING_SIDE_BY_SIDE_WIDTH` (500 = `slot_grid_width(2)` + 2 × 16 + `CRAFTING_DETAIL_MINIMUM_WIDTH` 300): columns = min(`CRAFTING_GRID_COLUMNS` 5, `slot_columns(W - 2 × 16 - 300)`), the grid `slot_grid_width(columns)` wide at the left, 2 × 16, the detail the rest.
- Stacked below that: columns = min(5, `slot_columns(W)`), the grid `slot_grid_height(CRAFTING_STACKED_GRID_ROWS` 2) tall on top, 16, the detail the rest.

| Size (UI scale) | W | Layout | Columns | Detail |
| --- | --- | --- | --- | --- |
| 1920x1080 (1.0), 960x540, 1920x540 (capped at 1712) | 864 | side by side | 5 | 400 by 688 |
| 1920x1080 (1.2) | 592 | side by side | 3 | 304 by 526 |
| 1920x1080 (1.5) | 304 | stacked | 3 | 304 by 180 |
| 1280x800 (1.0) | 707.2 | side by side | 4 | 331.2 by 688 |
| Deck preset, 1280x800 (1.1) | 565.8 | side by side | 2 | 365.8 by 599.6 |
| 1280x800 (1.2) | 448 | stacked | 5 | 448 by 342 |
| 1280x800 (1.5), the smallest | 188.8 | stacked | 2 | 188.8 by 180 |
| 2880x1920 (1.0) | 610 | side by side | 3 | 322 by 688 |

The inventory half needs 488 and gets at least 492. What gives way: under 500 the detail moves under a two row grid and its tail is cut where it ends (the graph lists need 112 and drop first, `recipe_detail_panel`'s check); under 40 units of tab content (W 304 and 188.8, tabs of 54.4 and 31.4) the icons drop and the labels fit, to an ellipsis at the smallest (`draw_tab_label`); the toggle and the queue summary fit their text. The text scale changes only text, fitted as everywhere.

### The schematics half

- Tabs: `ui_tabs(state, layout.tabs, "crafting_tabs", labels, icons, .Stepped)`, `state.selections[ui_id(state, "crafting_tabs")] = view.tab` written first, the label `text(recipe_category_key(tab))` and the icon `recipe_category_icons[tab]` of each tab category. No focus target: the right stick's flick and `[` `]` step them from either half, the pointer and a tap pick. A changed tab sets the grid's scroll offset to 0 and `recipe_browser.focused_recipe` to the new grid's first recipe (`NO_RECIPE` when empty), so the detail follows the tab wherever the focus is.
- Header: `ui_toggle(..., text("recipes_unlocked_only"), &view.available_only)` and the queue summary (`queue_summary_text`, the accent while the queue waits, as `recipe_filter_column` draws it).
- Grid: the tab's recipes (`crafting_view_recipes`) in data order, non-hand ones included (it is the reference and the graph, as the list was), in a `scroll_region_begin(state, "schematics_grid", area, slot_rows_height(count, columns) - UI_GAP)` with `ui_push_id(state, "schematics_grid")` around the cells, so a cell's id is `recipe_row_id(grid_id, recipe)` with `grid_id = ui_id(state, "schematics_grid")` in the half, the region's id too. A cell is `UI_SLOT_SIZE` square at `slot_grid_rectangle`: `ui_interact(state, id, cell, {}, recipe_names[recipe])`, `widget_background`, the craftable mark (accent, `RECIPE_CRAFTABLE_MARK_WIDTH`, the cell's left edge), `recipe_icon` inset by `UI_SLOT_ICON_INSET`; no count. A focused cell sets `focused_recipe`. An empty grid draws `recipes_none` at its top.
- Detail: `recipe_detail_panel` unchanged, its graph lists included (DESIGN.md: the browser is a graph). A recipe reached there calls `navigate_crafting_view`.
- `Recipe_Plans` and the craftable marks: `refresh_craftable_recipes` with `screen_craft_makers`, as `recipe_screen` calls it.

### Focus

- The halves are two panels without art, `"inventory"` (the slot ids keep their path, `inventory_slot_id`) and `"schematics"`, after the outer `"crafting_view"` panel with art, which holds the title row and the seam line. Each half's navigation stays inside it and wraps, as every panel's does.
- The seam: Right on an inventory widget and Left on a schematics widget, when `find_focus_in_line` finds nothing ahead in its own panel and `focus_step_allowed` holds, move to the other half's widget ahead with the least `along + UI_FOCUS_PERPENDICULAR_PENALTY × perpendicular` (`focus_score`). The view sets `requested_focus` to it and `navigation_step` to `.None`. Every other step is the default one.
- `Ui_State.crafting_half`: set by `handle_screen_keys` when it pushes the view from the world (the inventory binding `.Inventory`, C `.Schematics`), and each frame by the view from the focused widget's panel; kept while the focus is on neither half (the touch row, an id from the last screen). A carousel step onto the view and the return from the configure pop-up keep it.
- Preferred focus: on the inventory half as today (the configure pop-up's slot once, else the selected hotbar slot); on the schematics half `ui_prefer_focus(toggle_id)`, and `settle_recipe_focus(state, browser, grid_id, visible)` runs, on that half only, after the tap selection, so a fresh opening, a stale focus and a graph step land on the focused recipe's cell, else the first cell, else the toggle.
- A tab step with the focus on a cell: the cell is gone, so the settle takes the new tab's first cell. On the toggle or in the inventory the focus stays.

### Controls by half

Only the context action is gated by the half; everything else acts on what is focused or under the pointer, which is already one half's.

| Control | Inventory half | Schematics half |
| --- | --- | --- |
| A, R1 A, L1 A | the slot as today | a cell: 1, 5, the most (`apply_recipe_craft_input`); the toggle: flips; a graph row: the step |
| X, F (`Context_Action`) | sort, configure | clear the queue |
| RS flick, `[` `]` | the tabs | the tabs |
| RS click | drops the hand's stack, else the focused slot's | drops the hand's stack (no slot is focused, `drop_stack_command`) |
| Touch row | `inventory_touch_buttons` with `INVENTORY_TOUCH_LAYOUT` | `CRAFTING_VIEW_TOUCH_BUTTONS`: Craft, Craft 5, Craft max, Cancel last, Clear queue, Back |
| Glyph bar | `inventory_glyph_bar` as today | `crafting_view_glyph_bar` |

The meaning never depends on the device. Cancel last has no gamepad or keyboard control in the view; it is the touch row's button. A tap on a cell selects it (`tap_selects_only`); the row's craft buttons act on the selected recipe while the grid shows it.

`crafting_view_glyph_bar`: on a cell A Craft, R1 A Craft 5, L1 A Craft max; on the toggle and the graph rows A Select (`hint_select`); then the context action `hint_clear_craft_queue` (X on the gamepad, F on the keyboard); RS Tabs; B Close. The pairs drop together as 0276's do.

### Data: the categories table

`data/recipes.sjson` gains a top level `categories` list, `{id, crafting_tab}` per entry: `id` a recipe category, `crafting_tab` the category whose tab shows it, which must be its own tab (`crafting_tab` equal to its `id`). The tabs are the entries that are their own tab, in the table's order. Bounds: absent, or each of the 7 categories exactly once. Shipped, in this order:

| id | crafting_tab |
| --- | --- |
| machines | machines |
| logistics | logistics |
| power | power |
| materials | materials |
| components | materials |
| science | materials |
| tools | tools |

Five tabs: Machines, Logistics, Power, Materials, Tools. Without the table every category is its own tab in `Recipe_Category` order (the tests' hand built files). Refusals, each refusing the file as any recipe error does: `categories: 6 entries, need each of the 7 categories once`; `categories[2].id: unknown category "x"`; `categories[4].id: "tools" is listed twice`; `categories[1].crafting_tab: unknown category "x"`; `categories[5].crafting_tab: "components" is not a tab (it shows in "materials")`. The header comment's category sentence says the categories are the station browser's tabs and the table maps them to the crafting view's.

### The clear command

- `Clear_Craft_Queue_Command :: struct {unused: u8}` after `Cancel_Craft_Command` in the `Player_Command` union; in `player_command_valid`'s always valid list; `apply_player_command`: `if player.crafting.count > 0 && !clear_craft_queue(...)` appends `Inventory_Full`, as the cancel does.
- `Player_Command_Tag.Clear_Craft_Queue` appended after `Machine_Placement`, with its `encode_player_command` and `decode_player_command` cases (`read_command_value`). No tag renumbers.
- All or nothing: only a started front craft holds ingredients, so the clear gives back that craft's inputs (not under `started_free`, a waiting front included) and is refused when they do not fit, like the cancel. Queued runs took nothing and go.
- The UI queues it only with a run queued; refused at the UI, it toasts `inventory_full` as the cancel does.

### Files and procedures

`src/ui_crafting_view.odin` (new, ui cluster):

- `Crafting_Half :: enum u8 {Inventory, Schematics}`, Inventory first so a test that pushes `.Inventory` gets the inventory half.
- `Crafting_View :: struct {tab: int, available_only: bool}`, the session's: the tab's position in the tab list, clamped each frame. `make_crafting_view :: proc() -> Crafting_View`: Unlocked only on.
- Constants: `CRAFTING_VIEW_WIDTH` 1712, `CRAFTING_GRID_COLUMNS` 5, `CRAFTING_DETAIL_MINIMUM_WIDTH` 300, `CRAFTING_SIDE_BY_SIDE_WIDTH` 500, `CRAFTING_STACKED_GRID_ROWS` 2.
- `Crafting_View_Layout :: struct {title, inventory, seam, schematics, tabs, header, grid, detail: Ui_Rectangle, columns: int}`; `crafting_view_layout :: proc(content: Ui_Rectangle) -> Crafting_View_Layout`: the cuts above, pure, from the panel inset by `UI_PADDING`.
- `crafting_view_recipes :: proc(recipes: Recipe_Registry, tab: Recipe_Category, available_only: bool, available: []bool, allocator := context.allocator) -> []int`: the recipes whose category's `crafting_tabs` entry is `tab`, unlocked only when asked, in index order.
- `Schematics_Half :: struct {panel, grid, toggle: Ui_Id, visible: []int, activated, reached: int}`; `schematics_half :: proc(state: ^Ui_State, screen_context: Screen_Context, layout: Crafting_View_Layout) -> Schematics_Half`: the half's panel as above, from `inventory_screen`.
- `schematic_grid :: proc(state: ^Ui_State, area: Ui_Rectangle, columns: int, screen_context: Screen_Context, visible: []int, craftable: []bool) -> (activated: int)`: the grid's region and cells, from `schematics_half`.
- `navigate_crafting_view :: proc(view: ^Crafting_View, browser: ^Recipe_Browser, recipes: Recipe_Registry, unlocks: Recipe_Unlocks, recipe: int)`: the tab of the recipe's category, Unlocked only off for a locked recipe, `pending_focus` and `focused_recipe` set; from `inventory_screen` on a reached recipe.
- `crafting_half_of_focus :: proc(widgets: []Ui_Widget, focus: Ui_Id, inventory_panel, schematics_panel: Ui_Id, current: Crafting_Half) -> Crafting_Half`: the focused widget's half, `current` for any other.
- `crafting_seam_target :: proc(widgets: []Ui_Widget, focus: Ui_Id, step: Ui_Direction, inventory_panel, schematics_panel: Ui_Id) -> Ui_Id`: the seam's target, 0 when the step is the default one.
- `crafting_view_queue_act :: proc(context_action: bool, button: Touch_Button) -> Craft_Queue_Act`: Clear for the context action and for `.Clear_Craft_Queue`, Cancel_Last for `.Cancel_Craft`, else None.
- `CRAFTING_VIEW_TOUCH_BUTTONS :: Touch_Buttons{.Craft, .Craft_Five, .Craft_Most, .Cancel_Craft, .Clear_Craft_Queue, .Back}`.
- `crafting_view_glyph_bar :: proc(state: ^Ui_State, on_cell: bool)`.

`src/ui_inventory.odin`, `inventory_screen`, in this order: backdrop; the layout; the outer panel with the title row and the seam line; the inventory panel (`ui_panel_begin(state, "inventory", layout.inventory, art = false)`, `player_slot_region` in it); `schematics_half`; `state.crafting_half = crafting_half_of_focus(...)`; the touch row of the half; the tap selection, `settle_recipe_focus` and the preferred focus by half; `navigate_crafting_view` on `reached`; `crafting_seam_target`, applied when not 0; the slot input as today with `context_action` and `configures` also needing the inventory half; `apply_recipe_craft_input(..., activated, selected_shown, button, crafting_view_queue_act(state.input.context_action && state.crafting_half == .Schematics, button))` with `selected_shown` whether the grid shows `focused_recipe`; the drop, `finish_slot_drag`, `draw_held_stack` as today; the glyph bar by half; the configure pop-up. The panel width constant and `inventory_panel_height` stay for `machine_screen`.

`src/ui_recipes.odin`:

- `Craft_Queue_Act :: enum u8 {None, Cancel_Last, Clear}`.
- `apply_recipe_craft_input(state, screen_context, activated, selected_shown, button, queue_act: Craft_Queue_Act)`: its cancel lines become `apply_craft_queue_act(state, screen_context, queue_act)`.
- `apply_craft_queue_act :: proc(state: ^Ui_State, screen_context: Screen_Context, act: Craft_Queue_Act)`: with a run queued, Cancel_Last queues `Cancel_Craft_Command` when `last_craft_cancels`, Clear queues `Clear_Craft_Queue_Command` when `craft_queue_clears`, else the toast `inventory_full`.
- `recipe_screen`: the neither mode pop; the title label always; `queue_act` Cancel_Last on the context action or `.Cancel_Craft`, so the station browser's X and F stay Cancel last.
- `recipe_filter_column`: the "Unlocked only" branch goes (no mode shows it any more).

`src/ui_window_carousel.odin`: `window_carousel` the six; `window_in_carousel :: proc(screen: Screen) -> bool` (the views and the `.Recipes` case go); `window_title_key` loses `.Recipes`.

`src/ui_screens.odin`: `handle_screen_keys` sets `state.crafting_half` with the two pushes, C pushes `.Inventory`, `closes_recipes := (top == .Recipes || top == .Inventory) && input.open_recipes`; `run_screens` passes `window_in_carousel(top_screen(state.screens))`.

`src/ui_core.odin`: `Ui_State.crafting_half: Crafting_Half` beside `active_slot`.

`src/ui_widgets.odin`: `ui_panel_begin(state, label, rectangle, art := true)` draws the art only with `art`; `Touch_Button.Clear_Craft_Queue` after `Cancel_Craft`, key `touch_button_clear_craft_queue`.

`src/ui_session_views.odin`: `Session_Views.crafting_view: Crafting_View`, made by `make_session_views`, `make_crafting_view()` again in `reset_session_views`.

`src/recipe.odin`:

- `Recipe_Category_Definition :: struct {id, crafting_tab: string}`; `Recipes_File.categories: []Recipe_Category_Definition`.
- `Recipe_Registry`: `crafting_tabs: [Recipe_Category]Recipe_Category` (each category's tab) and `category_order: [len(Recipe_Category)]Recipe_Category` (the table's order), fixed, no allocation.
- `resolve_recipe_categories :: proc(definitions: []Recipe_Category_Definition) -> (tabs: [Recipe_Category]Recipe_Category, order: [len(Recipe_Category)]Recipe_Category, problem: string)`: the default without a table, the refusals above; first in `resolve_recipe_registry`, before anything is allocated.
- `crafting_tab_list :: proc(recipes: Recipe_Registry) -> (tabs: [len(Recipe_Category)]Recipe_Category, count: int)`: the categories that are their own tab, in `category_order`; a zero registry gives one tab, Materials.

`src/crafting.odin`: `craft_queue_clears :: proc(queue: Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry) -> bool` (a run queued, and the started front's inputs fit unless it started free or did not start); `clear_craft_queue :: proc(queue: ^Craft_Queue, inventory: Inventory, recipes: Recipe_Registry, items: Item_Registry) -> bool`: refunds those inputs, `count = 0`, `reset_front_craft`.

`src/player_command.odin`, `src/session_network.odin`: the clear command above.

### Strings

`data/strings/en.sjson`, new: `hint_clear_craft_queue = "Clear queue"`, `touch_button_clear_craft_queue = "Clear queue"`. Removed: `recipes_title` (its readers go). Kept: `inventory_title` (the view and the machine panels), `recipes_unlocked_only`, `crafting_queue`, `recipes_none`, `hint_select`, `hint_tabs`, the craft hints and buttons, `recipe_category_*`.

### Tests

New, `src/ui_crafting_view_test.odin` unless named otherwise:

- `test_the_crafting_view_layout_at_the_audit_sizes`: content 1680 by 880 gives W 864, five columns, detail 400; 1523.2 four and 331.2; 1381.8 two and 365.8; 1004.8 by 556 stacked, two columns, grid 168 tall, detail 188.8 wide; the inventory rectangle 784 wide in all.
- `src/recipe_test.odin`, `test_the_crafting_tabs_come_from_the_categories_table`: the shipped registry's `crafting_tab_list` is Machines, Logistics, Power, Materials, Tools and maps components and science to Materials; a file without the table gives the seven in enum order; a table that maps tools to machines drops the Tools tab; each of the five refusals gives its problem; `Recipe_Registry{}` gives one tab.
- `test_crafting_view_recipes_follow_the_tab_and_unlocked_only` (`make_browser_test`): with Unlocked only off the Materials tab holds plank, iron_gear, electronic_circuit and science_pack_1 in index order (plank before stick) and no recipe of another tab; on, it drops electronic_circuit.
- `test_the_focus_crosses_the_seam_and_wraps_inside_each_half`: on hand built widgets of two panels, Right from the left panel's right column gives the right panel's left column in the same row, Left the reverse, Right from the left column gives 0, Up gives 0, a widget with `.Adjusts_Horizontally` gives 0. In the view at 1080p (`screen_test_frame`): Right on `inventory_slot_id("grid", 8)` and on `inventory_slot_id("hotbar", 7)` lands on a schematics widget and the next frame's half is Schematics; Left from the first column's cell lands on an inventory widget; Down from the hotbar and Up from the toggle keep the focus in their panel.
- `test_c_and_the_inventory_binding_open_the_crafting_view_on_their_half`: from the world `open_recipes` pushes `.Inventory` with the half Schematics and the focus, two frames later, on a cell; `open_inventory` the half Inventory and the selected hotbar slot; `open_recipes` on the view pops it; a step to the journal and back keeps the half.
- `test_a_tab_step_moves_the_schematics_focus_to_the_new_tab`: focus on a cell of tab 0, `tab_next`: tab 1, the focus on its first cell, `focused_recipe` that recipe, the grid's offset 0; on the toggle the focus stays and `focused_recipe` follows; on a slot the focus stays; `tab_previous` from 0 wraps to the last tab.
- `test_modifiers_with_a_on_a_schematic`: 20 logs, the plank cell focused: `confirm` queues `Craft_Command{plank, 1}`, with `modifier_five` 5, with `modifier_most` the planner's count; with a run queued `context_action` queues `Clear_Craft_Queue_Command` with `active_device = .Gamepad` and with `.Keyboard_Mouse` alike, and the glyph bar reads `hint_clear_craft_queue` on both; the focus on a backpack stack (`inventory_slot_id("grid", 0)`) and the gamepad, `context_action` queues `Slot_Sort_Command`; an empty inventory and `modifier_most` queues nothing and toasts.
- `test_crafting_view_queue_act_follows_the_context_action_and_the_button`: the table of `crafting_view_queue_act`.
- `test_a_drag_scrolls_the_schematics_grid`: the Materials tab with Unlocked only off on the schematics half, a finger dragged 100 up on a cell moves the grid's offset by 100 and keeps the focus and the screen.
- `test_a_graph_step_in_the_crafting_view_opens_the_recipes_tab`: `navigate_crafting_view` from the Machines tab to electronic_circuit (locked in `make_browser_test`) gives the Materials tab and Unlocked only off, to plank keeps it on; in the view, after a step to burner_mining_drill from the Materials tab the second frame's focus is the drill's cell.
- `src/crafting_test.odin`, `test_clear_returns_only_the_craft_in_progress`: three runs, the front started: the clear gives back the front craft's inputs only and empties the queue with the front state reset; under `started_free` it gives back nothing.
- `src/crafting_test.odin`, `test_clear_refused_when_ingredients_do_not_fit`: a full inventory and a started front: `craft_queue_clears` and `clear_craft_queue` are false and the queue is unchanged; not started, it clears.
- `src/player_command_test.odin`, `test_the_clear_craft_queue_command_round_trips_and_applies`: it encodes and decodes to itself, is valid, empties a player's queue at the tick, and with the refund not fitting appends `Inventory_Full` and keeps the queue.

Changed:

- `ui_window_carousel_test.odin`: `CAROUSEL_TEST_ORDER` the six; the step by 8 becomes 7; `window_in_carousel` one argument, the views block goes and `.Recipes` joins the screens outside; `own_keys` the six, and `open_recipes` also pops `.Inventory`; the keyboard case `{.Inventory}` steps to `{.Journal}`.
- `ui_audit_test.odin`: `test_pause_menu_and_initial_focus` checks `inventory_title` not drawn on the pause menu in place of `recipes_title`; `test_the_configure_popup_picks_the_foundation_block` steps to `.Journal`; `set_recipe_ingredient_states` and its restore also save and set `crafting_view` (the Machines tab), and with `test_recipe_detail_shows_how_the_queue_gets_each_ingredient` and `test_recipe_screen_shows_have_and_need` (plank's tab) push `.Inventory` with the half Schematics.
- `ui_recipe_browser_test.odin`: `test_modifiers_with_a_on_a_recipe` and `open_recipe_browser_on_plank` run on the bench only; `test_recipe_categories_follow_the_tab_step` loses its strip part and sets `.Materials` before the picker's.
- `ui_pointer_test.odin`: `test_a_drag_scrolls_the_recipe_list` keeps its name (doc/audit/ui.md's Scroll_List guard) on the crafting bench's browser, Machines, every recipe made available and restored; `test_every_screen_has_a_back_button_on_touch` drops `{.Recipes}`; `test_a_tap_on_a_recipe_selects_it_and_the_row_crafts` runs in the view: the inventory row before the tap (Sort, no Craft), the crafting row after it, and Clear queue empties the queue at the tick; `test_touch_row_buttons_by_screen` checks `CRAFTING_VIEW_TOUCH_BUTTONS`; `test_the_row_ignores_a_hidden_selection` selects plank on the Machines tab, the half Schematics.
- `ui_inventory_test.odin`: the three taps outside at (100, 400) move to (40, 400), past the wider panel; `test_a_modified_click_off_the_slots_is_a_plain_click` takes the empty corner of the `"crafting_view"` panel.
- Each new test that `build/test_times.tsv` shows at 1 s or more is marked `// slow`.

### UI audit

`Ui_Audit_Case.schematics: bool` sets `crafting_half`; `audit_case_at_size` also sets `audit.views.crafting_view.tab = 0` before the first frame, so the tab cases step from the first tab at every size.

- Renamed: "inventory" becomes "crafting view" (walk_focus, which reaches every widget of both halves, each half's bar and touch row with it); "inventory touch row" becomes "crafting view touch row".
- New: "crafting view schematics" (the settled cell); "crafting view schematics touch row" (the six buttons, checked whole at the smallest touch size; Clear queue becomes "Clear all" if the check cuts it, named as a deviation); "crafting view tab N" for N in 1 ..< the tab count; "crafting view, every recipe" (Unlocked only off on the Materials tab, saved and restored, silhouettes and the scrolled grid).
- Moved: "recipes, ingredients held, craftable and missing" becomes "crafting view, ingredients held, craftable and missing".
- Obsolete: "recipes" and "recipes touch row". The list, its letter wheel, its category row, "Can craft now" and the tags stay drawn by "crafting station", "crafting bench", "recipe selection" and their touch rows; the toggle, the queue summary, the detail and the craft row by the crafting view's cases.

### Docs

- `doc/ui.md`: Screens (the table's Inventory as the crafting view; the stack bullet: C opens the view and pops it); Focus and navigation (X and F on the schematics clear the queue, Cancel last is the touch row's there; the crafting view's tabs are no focus target); Touch button row (a crafting view row); Window carousel (the six, C, what the view keeps: the tab, Unlocked only, the half); a new `### Crafting view` after it with the layout rule, the halves, the seam, the half's touch row and bar; Recipe browser (the picker and the station only; Unlocked only and the window mode leave it); Crafting queue (Clear queue: all or nothing, refunds only the craft in progress); Configure pop-up ("the inventory view" is the view's inventory half).
- `doc/input.md`: line 148's context action (clear the queue on the crafting view's schematics, cancel the last craft in the station browser), line 161's C (the crafting view on its schematics).
- `doc/content.md`: Recipes (the categories table); Hand crafting (the clear).
- `doc/developer_tools.md` line 26: the crafting view and the station browser mark.
- `doc/code_map.md`: `ui_crafting_view.odin` in the ui cluster; `Ui_State` one field more.
- `doc/hud.md`: none. It names no screen control (as 0276 found).

### Hand-back check

- Memory a frame draws from, file writes, parsed numbers, per tick rates, budgets and growing lists: none apply (temporary lists only; the grid scrolls).
- A start-up load the game can make fail: a malformed `categories` table refuses `recipes.sjson` like any recipe error, a live reload keeps the old content and a failed start load turns the data overlay off (developer_tools.md, Editing).
- Save layout: none. `Craft_Queue` is unchanged; the command tag is appended, and a peer of another build is refused already.
- Long strings: the tabs, the toggle, the summary and the title fit; the six button row is checked whole at the smallest sizes.
- Obsolete audit cases: replaced as listed.
- Tests: in memory and the audit's temporary state only.

### Settled

- The grid holds non-hand recipes too: the Recipes tab it replaces did, and the graph steps land on them.
- Data order, not name order: the cells show no names, and the data groups a family (planks, sticks, slabs).
- The categories table lives in `recipes.sjson` beside the recipes that name the categories; `Recipe_Category` stays the code's enum, which the station browser's tabs (`station_categories`) keep reading.
- "Can craft now" and the tags stay in the station browser only: the Controls name only Unlocked only for the view.
- The halves are art-less panels inside one panel: navigation scoping needs the two ids, the player sees one window.

### Decisions (main agent, 2026-11-13)

1. Not by device: a control's meaning never depends on which device pressed it. `Context_Action` on the schematics half clears the queue on every device (X, F). Cancel last has no gamepad or keyboard control in the view; it is the touch row's button, and stays X and F in the station browser.
2. The station browser's touch row gets no Clear queue button.
3. Five tabs from our own categories: Machines, Logistics, Power, Materials, Tools. No base building category in this item.
4. The narrow layout at UI scale 1.5 as designed.
5. C on the open view closes it, as every window's own key pops one level.
6. The title stays "Inventory".

### Deviations (implementation, 2026-11-13)

- Procedures beyond the list, split out to keep each small: `crafting_body_layout` (the body's two layouts), `crafting_view_frame` (the outer panel, the title row, the seam line), `crafting_view_tabs`, `crafting_view_header`, `nearest_widget_ahead` (the seam's score), `crafting_tab_index` (a category's place in the tab list, for `navigate_crafting_view` and the tests), `resolve_recipe_category` (one table entry), and `crafting_view_touch_row` in `ui_inventory.odin`.
- `inventory_screen` takes the slot modifiers, the quick move and the active slot before the touch row, not with the later slot input: the row's Configure in Sort's place reads the active slot of the frame, as the inventory screen did before.
- The queue summary is right aligned in the header's second column, inset by `UI_GAP`. An empty grid's `recipes_none` is drawn fitted, since the half is 188.8 wide at the smallest size.
- Tests: `test_the_row_ignores_a_hidden_selection` parks the focus on the toggle before it selects plank, since `settle_recipe_focus` moves a focus on a cell to the cell shown. The audit case "crafting view, every recipe" reaches Materials by `tab_next` presses, as the audit resets the tab at every size. `set_recipe_ingredient_states` saves the crafting view too, and `push_crafting_view_on_schematics` (`ui_audit_test.odin`) opens the view for the two detail tests. `test_modifiers_with_a_on_a_schematic` sets the device through `Ui_Input.device`, which `ui_begin` copies to `active_device`.
- "Clear queue" stays: the audit finds the six button row whole at the smallest touch size.
- Review fix 1: a widget registered inside a scroll region or list carries its clip (`Ui_Widget.clip`, `Ui_State.scroll_clip`), and `ui_pointer_over` and `widget_under` ignore a point outside it, so the hover, the press and the pointer's focus miss the part scrolled out. Focus navigation still reaches it. Tests: `test_a_tap_on_the_toggle_over_the_scrolled_grid_flips_it`, `test_a_click_on_the_toggle_over_the_scrolled_grid_queues_nothing` (offset 88), `test_a_click_above_a_scrolled_list_misses_its_rows` (the crafting bench's list a row down, a click on the category row above it).
- Review fix 2, the stacked layout (the half under 500): the tabs, then the toggle across the half's width, then the summary on its own row (right aligned, not inset), then the grid of two rows and the detail, each with a gap of 8. At 1280x800 and UI scale 1.5: W 188.8, tabs of 31.4, toggle label room 92.8, summary 188.8, grid 168 tall, detail 116 (180 before). At 1920x1080 and UI scale 1.5: W 304, tabs of 54.4, label room 208, detail 116. At 1280x800 and UI scale 1.2: W 448, tabs of 83.2, label room 352, detail 278. Side by side the header is unchanged.
- Review fix 2, tabs: `ui_tabs` takes `icons_alone_when_cut`, which only the crafting view sets. At the smallest size the tab (31.4) is narrower than the icon (32), so the icon shrinks to the tab rather than being dropped: a dropped icon would leave a blank tab or a cut label. At 1920x1080 with the largest text the labels do not fit either ("Logistics" needs 167.9 of 150.4), so those tabs show icons too.
- Review fix 2, the toggle's label: `crafting_view_unlocked_short` ("Unlocked") is used only in the stacked layout, where "Unlocked only" is wider than the room left beside the knob. At 1280x800, UI scale 1.5 and text 1.6 even "Unlocked" (113.7) does not fit its 92.8 and draws fitted with an ellipsis. There the audit does not check the toggle's label, which is open for the main agent. The audit's `audit_crafting_view_texts` checks every crafting view frame for a blank tab, the toggle's label (either key) and the summary drawn whole (`Crafting_Tab_Blank`, `Crafting_Text_Cut`).
- Review fix 3: a panel without art is `inner` (`Ui_Panel.inner`), and its tooltips dock beside the panel around it (`tooltip_dock_rectangle`). At 1080p the view is 1712 wide in a 1728 wide safe area, which leaves no room for the 420 wide box on either side, so `tooltip_rectangle` puts it under the slot, inside the inventory half. A box that intersects neither half fits only where the view leaves room beside it. `test_a_slot_tooltip_docks_beside_the_crafting_view` therefore asserts at 1080p that the box stays off the schematics half, and at 1920x540 (3840 units wide) that it stays off both halves.
- Review fix 4: turning Unlocked only on moves `focused_recipe` off a recipe the grid now hides, to the first cell shown or to `NO_RECIPE` (`test_unlocked_only_moves_the_detail_off_a_hidden_recipe`).
- Review fix 1, an existing test: `test_panel_presses_land_at_the_next_tick` tapped the launch pad's Assemble (y 945) and Launch (y 1009), which lie below the machine side's view at 1080p (it ends at y 950), so fix 1 made the taps miss. The test now scrolls `machine_area` to its end before the taps and back to 0 before the next machine.
