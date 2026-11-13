# 0385: The window carousel

Status: landed (2026-11-13, db53bf0)

Split from 0276 on 2026-11-13: 0276 lands the screens layer's input (the actions, the modifiers, the tab step, the triggers over the old inventory strip), this item turns the triggers' step into a carousel of every window, after Techtonica (user, 2026-10-05, [inspiration.md](../inspiration.md), Techtonica's controls and screens), with the user's answers of 2026-11-13 on B and on Power.

## Goal

The windows reached from the world step as one carousel on L2 and R2, each with a title row naming it between two arrows; the inventory tab strip goes. B pops one level of the screen stack towards the world, so a window opened from the world closes to it and one opened over a panel returns to the panel. Power is the carousel's seventh window.

## Controls

On the 0276 layer, which this item changes nowhere else.

- L2, R2: the previous and the next window of the carousel, wrapping: the crafting view (0277; until then the inventory and the recipes), the journal, research, the map, statistics (production, shipments), power (user, 2026-11-13). A step replaces the top window, so the stack never grows. Q and E on the keyboard; the title row's arrows on touch and for the pointer (main agent, 2026-11-13). No sound.
- B: pops one level of the screen stack towards the world, the lowest state (user, 2026-11-13). A window opened from the world closes to it; research opened from a lab's panel returns to the panel, also after a step; the info panel closes before its screen, the configure pop-up returns to the inventory, the recipe picker to its machine panel, Settings to Pause. Menu over a screen and a tap off a panel act as B; a window's own key closes it, one level.
- The picker, the station browser, the configure pop-up and the machine panels are outside the carousel: the triggers do nothing there.

## Change

- `src/ui_window_carousel.odin`: the order, the step, the title row drawn by all seven windows; the inventory tab strip goes.
- `handle_screen_keys`: a window's step before the closes, so the keyboard's E steps on a window; B, Menu, the tap off and the own keys pop one level as today, written down as the stack.
- Power becomes a window of the carousel, and Statistics' Power tab goes.
- The carousel's tests and audit cases.
- Docs: `doc/ui.md` (Screens, a Window carousel section in place of the strip's, Recipe browser, Other screens), `doc/input.md` (the triggers in menus, E), `doc/code_map.md`.

## Verify

- Tests: the carousel's order and wrap; L2 and R2 replace the top window without growing the stack, over a lab's panel too; B, Menu and a window's own key pop one level from every window and dialog; E steps on a window and closes a panel; the title row draws and its arrows step.
- The UI audit at every size.
- The couch.

## Specification (design, 2026-11-13)

Designed against 0276's specification, which lands first: `Ui_Input.window_previous` and `window_next`, `Glyph_Button.Tabs`, `.Window_Previous` and `.Window_Next`, and the interim `inventory_tabs` that this item removes.

### The stack

`Screen_Stack` (`UI_SCREEN_STACK_CAPACITY` 8) holds the screens over the world; the world is the empty stack. All of this is today's code (`handle_screen_keys`, `pause_screen_buttons`, the panels' buttons) but the replace; the item adds the step and puts it ahead of E's close.

- Push: from the world, Pause (Menu, Esc), the inventory binding (Inventory), C (Recipes), J (Journal), P (Power), N (Statistics), T (Research), M and View (Map); opening an aimed machine pushes its panel. Over a panel: an assembler's recipe choice pushes the picker, a crafting station's panel its browser, the lab's Open technologies Research. Over the inventory: X on a configurable item pushes the configure pop-up. Over Pause: Settings and Developer; over Settings the touch layout editor; over Developer Textures and Data files. The pause menu's Journal, Power and Statistics rows replace Pause (clear, then push), so their window lies on the world.
- Replace: L2 and R2 (Q and E, the title row's arrows) on a window put the previous or next window in its place; the depth and whatever lies under it stay.
- Pop one: B, Menu over any screen, a tap off the panel, a window's own key on it (C on Recipes, J, P, N, T, M and View), and the inventory binding on Inventory, Recipes, Research or a machine panel when the press is not the context action (the gamepad's X sorts) and not a window's step (the keyboard's E on a window steps). An open info panel takes the press first and closes alone; the on-screen keyboard takes B and Menu first. A station's browser pops and its panel follows the next frame (`open_station_recipes`), as today.
- Clear: the pause menu's Resume, Cancel placement and Skip arrival.
- So a window opened from the world (depth 1) closes to the world; research from a lab (depth 2) returns to the lab panel, also after stepping to the map; the configure pop-up returns to the inventory, the picker to its panel, Settings to Pause.

### The carousel

- `@(rodata) window_carousel := [?]Screen{.Inventory, .Recipes, .Journal, .Technologies, .Map, .Statistics, .Power}`; 0277 folds the first two into the crafting view.
- Opening: each key opens its own window as today, never the last one seen; the inventory binding the Inventory (0277's crafting view). The gamepad reaches the others with the triggers from the inventory or the map.
- Remembered: what each window keeps today and nothing more: the browsers' filters, categories and focused rows (`Session_Views`), the journal's, statistics' and settings' selected tab (`Ui_State.selections`); the map re-centres at every opening (`Map_View.active`).
- A step takes the new window's preferred or first focus as the strip's step does today (each panel's label scopes its ids). An open info panel stays open.
- Outside: machine panels, the station browser, the picker, the configure pop-up and the menus; the triggers do nothing there. A window over a panel (research from the lab) steps as any window, the panel staying under it.

### Power and Statistics

Power is the seventh window: `power_overview_screen` draws the title row in place of its label, its panel (`POWER_OVERVIEW_WIDTH`) unchanged; P and the pause menu's Power row open it as today; its title is `power_overview_title` ("Power networks").

Statistics' Power tab goes (recommended): the Power window sits one R2 step after Statistics, and the same `power_overview_body` in two neighbouring windows is two places for one view. Statistics keeps Production and Shipments, in that order. Alternative: the tab stays (no code, the body drawn twice). `statistics_title` becomes "Statistics": the title row names the window in a word, and it holds shipments too.

### Files and procedures

`src/ui_window_carousel.odin` (new, ui cluster)

- `window_carousel` above.
- `step_window_carousel :: proc(screen: Screen, steps: int) -> Screen`: `steps` along the carousel, wrapping both ways; a screen outside it returns unchanged.
- `window_in_carousel :: proc(screen: Screen, views: ^Session_Views) -> bool`: in `window_carousel`; `.Recipes` only with `views` nil or neither `recipe_browser.selecting_for` nor `recipe_browser.station` set.
- `window_title_key :: proc(screen: Screen) -> string`: `inventory_title`, `recipes_title`, `journal_title`, `technologies_title`, `map_title`, `statistics_title`, `power_overview_title`; "" outside.
- `ui_window_title_row :: proc(state: ^Ui_State, rectangle: Ui_Rectangle)`: off touch (`touch_row_shows`) the `Window_Previous` glyph box at the left end and the `Window_Next` box at the right (`glyph_box_width` by `UI_GLYPH_BAR_HEIGHT`, centred in the row, drawn as `ui_glyph_rows` draws a box), `UI_GAP` inside each; a `UI_ROW_HEIGHT` square arrow on each side (`Arrow_Left`, `Arrow_Right`, the tab's hover fill), a press on one (`state.click && ui_pointer_over`) setting `state.input.window_previous` or `window_next`; the top screen's title between, `draw_text_fitted` at `UI_HEADING_TEXT_SIZE`, centred. No `ui_interact`: no focus target, as a stepped tab strip.

`src/ui_screens.odin`

- `handle_screen_keys :: proc(state: ^Ui_State, only_pause := false, in_carousel := false)`: after the `.Title` return, before the closes:

```odin
steps := int(input.window_next) - int(input.window_previous)
if in_carousel && steps != 0 {
	replace_top_screen(&state.screens, step_window_carousel(top, steps))
	return
}
```

  The rest as today. Its comment states the stack in short.
- `run_screens`: `handle_screen_keys(state, screen_context.arrival_falling, window_in_carousel(top_screen(state.screens), screen_context.views))`.

Windows:

- `src/ui_inventory.odin`: `inventory_screen`'s panel is `inventory_panel_height() + UI_GAP` high (the heading row in `inventory_panel_height` is now the title row's) and `shows_heading` goes; `ui_window_title_row` and `UI_GAP` replace the strip and the heading. `inventory_tabs`, `inventory_tab_screens`, `inventory_tab_index` go.
- `src/ui_recipes.odin`: `recipe_screen`, outside the picker and station modes, draws `ui_window_title_row` and `UI_GAP` in place of the strip and the "Recipes" label; the two modes keep their title label. `recipe_glyph_bar` loses `strip`: `{.Tabs, "hint_tabs"}` in every mode.
- `src/ui_technologies.odin`: the title row and `UI_GAP` replace the strip, its gap and the label; the hints lose the window pair.
- `src/ui_journal.odin`, `src/ui_map.odin`: the title row replaces the label.
- `src/ui_statistics.odin`: the title row replaces the label; the tabs are Production and Shipments (`statistics_tab_power` out, the switch's Power case out).
- `src/ui_power.odin`: `power_overview_screen` draws the title row in place of its label; `power_overview_body`'s comment loses the statistics tab.

Also: `replace_top_screen`'s comment (`ui_core.odin`) names the carousel; `data/bindings.sjson`'s header says E on a window steps.

### Strings

Removed: `inventory_tab_inventory`, `inventory_tab_recipes`, `inventory_tab_technologies`, `statistics_tab_power`. Changed: `statistics_title = "Statistics"`.

### Hints

Off touch every window's title row shows LT and RT (Q and E) beside its arrows, so no glyph bar names the windows. Changed from 0276: Recipes with the strip shows RS Tabs (the categories) in place of LT RT Tabs; Technologies is A Research, B Close. Touch rows unchanged.

### Tests

New, `src/ui_window_carousel_test.odin`:

- `test_the_window_carousel_steps_in_order_and_wraps`: +1 and -1 from each window by the order, Power +1 is Inventory, Inventory -1 is Power, +8 is +1; `.Pause` and `.Machine` unchanged; `window_in_carousel` false for `.Recipes` with `selecting_for` set and with `station` set, for `.Machine`, `.Configure`, `.Settings`, true for the seven.
- `test_the_triggers_step_every_window_and_wrap` (audit harness): each window alone and over a lab's panel, `window_next` gives the next and `window_previous` the previous; the count stays 1 or 2 and the panel stays at the bottom.
- `test_the_picker_station_and_panels_ignore_the_window_step`: the picker over an assembler's panel, the crafting station's browser, a chest's panel, `.Inventory` with `.Configure`, `.Pause` with `.Settings`: a `window_next` frame leaves the stack as it was.
- `test_back_pops_one_level_of_the_stack`: each window alone with `back`, with `pause` and with its own key ends at count 0; research over a lab's panel returns to `.Machine`, also after a step to `.Map`; with `tooltip_open` the first `back` closes only the info panel; the picker returns to its panel, the configure pop-up to the inventory, Settings to Pause.
- `test_the_keyboard_window_step_wins_over_open_inventory`: `.Inventory` with `window_next` and `open_inventory` becomes `.Recipes`; research over a lab's panel with both becomes `.Map` over it; a chest's panel with both closes; the picker with both returns to its panel.
- `test_the_title_row_names_the_window_and_its_arrows_step`: each window on the gamepad draws its title and the `Arrow_Left`, `Arrow_Right`, `Trigger_Left`, `Trigger_Right` icons; with `pointer_is_touch` no trigger icon; a `mouse_pressed` frame on the `Arrow_Right` icon's centre gives the next window.

Changed:

- `ui_inventory_test.odin`: `test_the_triggers_step_the_inventory_tab_strip` and `test_open_inventory_closes_the_strip` go; the carousel's tests hold what they held.
- `ui_audit_test.odin`: `test_inventory_strip_pause_menu_and_initial_focus` becomes `test_pause_menu_and_initial_focus` without the strip loop and the picker's strip check; the "statistics tab" loop runs over two tabs.

### UI audit

- Every window's case draws the title row, both devices (Q and E key caps on the keyboard), and its touch row case the arrows alone: inventory, recipes, technologies, the journal's tabs, the statistics' tabs, power, map.
- "statistics tab 2" goes with the Power tab (the loop runs 0 and 1); the power body stays audited by "power" (walk focus) and "power touch row".
- At every audit size and text scale; at the smallest sizes the fitted title and the arrows within the panel.

### Docs

- `doc/ui.md`: Architecture, Screens (the Back bullet as the stack in short; E steps on a window); "Inventory tab strip" becomes "Window carousel" (the order, the opening, what is remembered, the step, the title row, the windows over a panel, what is outside); Recipe browser (the categories under the title row, station mode outside the carousel); Other screens (Statistics with Production and Shipments, the Power window).
- `doc/input.md`: the menus column's L2 and R2 (the carousel's windows), the shared controls bullet's E (steps on a window, closes a panel), the keyboard paragraph ("the inventory tab strip reach them" becomes the carousel).
- `doc/code_map.md`, ui: `ui_window_carousel.odin` after `ui_screens.odin` (the carousel's order, step and title row); a reach record lowered if `code_graph.py --check` reports one below.
- `doc/touch_overlay.md` and `doc/hud.md`: no change (Start still steps back one screen).

### Hand-back check

- Memory, files, start-up loads, parsed numbers, rates, budgets, saves: do not apply.
- Long strings: the title is fitted at the smallest audit sizes.
- An audit case made obsolete: "statistics tab 2", with the Power body still drawn by "power".
- Tests and the state directory: no file is touched.

### Decisions (2026-11-13)

User: B pops one level; Power is the seventh window. Main agent: the title row's tap arrows; no sound on a step. Design, approved: the inventory binding always opens the inventory; `statistics_title`. Main agent, at the approval: Statistics' Power tab goes (one place for the view; "Statistics keeps its tabs as they are" in the design's brief was the main agent's sentence, not the user's). The keyboard's E steps on a window and no longer closes the inventory, Esc and Backspace do; named to the user.

### Deviations (implementation, 2026-11-13)

- 0276 landed as its specification named everything this item uses (`Ui_Input.window_previous` and `window_next`, `Glyph_Button.Window_Previous` and `Window_Next`, `inventory_tabs`); its fix round's changes (`make_ui_input`'s flick arming, the modifier cleared off the slots) touch nothing here.
- `window_carousel_index` (the screen's place, -1 outside) serves `step_window_carousel` and `window_in_carousel`; the title row draws through `draw_window_step_glyph` and `window_title_arrow`, the arrow icon inset by `UI_GAP` in its square.
- Research keeps one `UI_GAP` under the title row (the strip, its gap, the label and its gap became the row and a gap).
- `test_pause_menu_and_initial_focus` checks the pause menu against `recipes_title` and `technologies_title` (the same texts) in place of the removed strip keys.
- The carousel's tests share helpers in `ui_window_carousel_test.odin` (`carousel_test_state`, `expect_screens`, `audit_panel_of_kind`, `draw_list_icon` and two finders); the title row test presses the right arrow with the mouse and on touch.
- `doc/audit/ui.md`, refactor 3: its guard `test_open_inventory_closes_the_strip` became `test_the_keyboard_window_step_wins_over_open_inventory` (`tools/check_docs.py` names removed tests).
