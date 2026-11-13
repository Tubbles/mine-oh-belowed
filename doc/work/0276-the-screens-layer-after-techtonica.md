# 0276: The screens layer after Techtonica

Status: verified (2026-11-13)

## Goal

One button layer for every screen, after Techtonica's (user, 2026-10-05, [inspiration.md](../inspiration.md), Techtonica's controls and screens): A is the primary act on the focused thing and the bumpers held are its modifiers, the triggers step between the windows, the right stick steps the window's tabs. This item is the input layer: the actions, the modifiers, the tab step, and the triggers stepping today's inventory strip. The window carousel, its title row on every window and the stack B pops are 0385 (split 2026-11-13). 0277 to 0279 build on both.

## Controls

The screens layer, gamepad. The keyboard and the pointer keep their ways where nothing below replaces them.

- A: the primary act (pick up or drop a stack, craft one, queue a research, pick a row).
- R1 held with A: five (craft five; on a slot the quick move). L1 held with A: the most (craft as many as the inventory affords; on a slot the split). The bumpers alone do nothing, the tab step goes.
- B: pops one level of the screen stack towards the world, no modifier, as today (user, 2026-11-13: "B pops the window stack towards the world, the lowest state"; the earlier "B closes every screen to the world" was the main agent's wording). The tap off a panel stays. This item changes nothing about B; 0385 states the stack.
- X: the context action as now (sort the active grid, configure); in the recipe browser it cancels the last craft, which L2 did (main agent, 2026-11-13); on a schematic it clears the crafting queue (0277).
- Y: assigns the focused slot or schematic to the toolbar (0278), held it opens the toolbar edit mode (0279); elsewhere the info panel as now, list rows included (user, 2026-11-13).
- L2, R2: the previous and the next window, wrapping: until 0385 the inventory's strip (Inventory, Recipes, Research), then the carousel. The split and the quick move leave the triggers for the modifiers above, R2 as Confirm goes. Q and E step on the keyboard.
- Right stick: a flick left or right steps the window's tabs (the recipe categories, the journal's chapters, the statistics', settings' and launch pad's tabs), `[` and `]` on the keyboard (main agent, 2026-11-13); up and down keep scrolling lists; its click stays Menu_Drop.
- D-pad, left stick: the focus, in grids too. View and Menu stay.
- Touch (0134): the recipe browser's touch row gains Craft max beside Craft and Craft 5, no held fan (user, 2026-11-13). The carousel's arrows are 0385's.

## Change

- `data/bindings.sjson`: `Window_Previous` and `Window_Next` on the triggers, Q and E; `Modifier_Five` (R1) and `Modifier_Most` (L1) replace `Menu_Quick_Move` and `Menu_Secondary`; `Tab_Previous` and `Tab_Next` leave the bumpers and Q, E for `[`, `]` and the right stick's flick; an old configuration naming a removed action still loads. Every screen's handling of Confirm with a modifier held.
- The inventory strip steps on the triggers until 0385 replaces it.
- The settings' Bindings tab, the glyph bar per screen, the recipe touch row, the UI audit cases.
- Docs: `doc/input.md` (Bindings, Gamepad, Keyboard and mouse), `doc/ui.md` (Focus and navigation, Pointer, Item slots, Touch button row, Inventory tab strip, Recipe browser, Other screens, Touch layout editor).

## Verify

- Tests: A alone, R1 with A and L1 with A on a slot and on a schematic resolve to the acts above; the triggers step the strip; a flick steps the tabs once; no control carries two meanings in one context; an old configuration naming a removed action loads.
- The UI audit at every size.
- The couch.

## Specification (design, 2026-11-13)

Designed against `main` of 2026-11-13, revised the same day for the user's answers and the main agent's decisions. 0385 builds on it and changes none of it but the strip and its hints.

### The layer after this item

On every screen A is Confirm. R1 or L1 held changes A only on an item slot with an empty hand and on a recipe row outside the picker; anywhere else, with a stack in hand and with both held, A acts alone. L2 and R2 step the inventory's strip and resize in the touch layout editor, and do nothing elsewhere. A flick of the right stick steps the screen's tab strip where it has one (the recipe categories in every mode, the journal, statistics, settings, launch pad) and the map's zoom; up and down scroll lists and zoom the map as today; the click stays `Menu_Drop`. The bumpers alone never act on a screen.

B, Menu, a tap off a panel, Y, the d-pad, the left stick and View are unchanged on every screen: B pops one screen, the info panel first, exactly as today.

### Every screen, now → after

"Mods" is R1 or L1 held with A (Modifiers held with A).

| Screen | L1, R1 | L2, R2 | Right stick moved | X |
| --- | --- | --- | --- | --- |
| Inventory | strip step → mods on slots | L2 split, R2 Confirm or quick move → strip step | same | same (sort, configure) |
| Recipes (with the strip) | strip step → mods on rows | L2 cancel last, R2 Confirm → strip step | scroll → flick: categories; scroll | craft five → cancel last |
| Technologies | strip step → nothing | R2 Confirm → strip step | same (scroll) | same (nothing) |
| Journal | chapters → nothing | R2 Confirm → nothing | scroll → flick: chapters; scroll | same |
| Statistics | tabs → nothing | R2 Confirm → nothing | scroll → flick: tabs; scroll | same |
| Power | same (nothing) | R2 Confirm → nothing | same | same |
| Map | zoom step → nothing | R2 Confirm → nothing | up and down zoom → same, and a flick steps the zoom | same |
| Machine panels (chest, furnace, drill, inserter, splitter, assembler, lab, charge controller) | nothing → mods on slots | L2 split, R2 Confirm or quick move → nothing | same | same (sort, clear filter) |
| Launch pad panel | tabs → mods on slots | as a machine panel | scroll → flick: tabs; scroll | same |
| Station browser | nothing → mods on rows | L2 cancel last, R2 Confirm → nothing | scroll → flick: categories; scroll | craft five → cancel last |
| Picker | same (nothing) | R2 Confirm → nothing | scroll → flick: categories; scroll | same |
| Configure pop-up | same | R2 Confirm → nothing | same | same |
| Settings | tabs → nothing | R2 Confirm → nothing | scroll → flick: tabs; scroll | same |
| Touch layout editor | resize → nothing | R2 Confirm → resize | same | same |
| Pause, Developer, Textures, Data files, the title's screens | same | R2 Confirm → nothing | same | same |

Keyboard on the same screens: Q and E (the tabs, Q also the quick move in the inventory and the panels, E closing the strip) step the strip and resize in the touch layout editor; E on the strip still closes it, since the strip drops the step on an Open_Inventory press as today, so Q steps the strip back from all three screens and E closes. `[` and `]` (world only today) step the tabs and the map's zoom. Left Shift (a split press) and Left Control (held with a click, the quick move) become L1 and R1: held with Enter or a click. F cancels the last craft in the recipe browser.

### Actions

| Action | Gamepad | Keyboard | Touch |
| --- | --- | --- | --- |
| `Window_Previous` (new, menu) | LEFT_TRIGGER | Q | a tap on the strip's tab (0385: the title row's left arrow) |
| `Window_Next` (new, menu) | RIGHT_TRIGGER | E | as above (0385: the right arrow) |
| `Modifier_Five` (new, menu, held) | RIGHT_SHOULDER | LEFT_CONTROL | Craft 5 on the recipe row |
| `Modifier_Most` (new, menu, held) | LEFT_SHOULDER | LEFT_SHIFT | Craft max on the recipe row; slots keep Split and the 0.25 s rest |
| `Tab_Previous`, `Tab_Next` (kept) | none: the right stick's flick, no binding | LEFT_BRACKET, RIGHT_BRACKET (were Q, E) | a tap on a tab |
| `Confirm` | loses RIGHT_TRIGGER | same | same |
| `Menu_Secondary`, `Menu_Quick_Move`, `Menu_Quick_Move_Modifier` | removed | removed | |

In `Action` the three removed give their place to the four new ones, after `Context_Action`: 64 members, so `Action_Set` stays 64 bits and `Record_Input` its size. The renumbering reaches no save; a peer of another build is refused already.

A configuration from an older build: an entry naming a removed action is skipped with one log line, `<source>: bindings[<n>].action: Menu_Quick_Move is no longer used and is ignored (Modifier_Five took its place)`, the retired settings keys' wording (`configuration.odin`), where today the start exits. No remap: a press became a held modifier, and its old trigger now steps windows. `Tab_Previous` and `Tab_Next` stay actions, so overrides naming them load as before. Settings files, touch layouts (they name gamepad controls) and saves name no action.

### Modifiers held with A

| Focused thing | A | R1 + A (Left Control) | L1 + A (Left Shift) |
| --- | --- | --- | --- |
| Item slot, empty hand | pick up | quick move: a second press within 0.5 s or a hold moves every stack of the item (`advance_quick_move`, R2 today) | split, the larger half (L2 today) |
| Item slot, a stack in hand | place, merge, swap; held across machine slots, Even Distribution | as A | as A |
| An inserter's In hand slot | lift | into the inventory (R2 today) | L2 today |
| A filter slot | set the filter | nothing (R2 today) | L2 today |
| Recipe row (with the strip, station) | 1 craft | 5 (`RECIPE_CRAFT_MANY_COUNT`) | `planned_craft_count` for the recipe and the screen's makers, at most 999 (free crafting gives 999); at 0 one craft, so the refusal toasts |
| Picker row, technology row, button, toggle, stepper, list row | as today | as A | as A |

Both bumpers held: A alone. The modifier is read with the press of A (a click, or a tap's release on a recipe row).

### Keyboard, pointer, string fields

- Keyboard: Enter is A, Left Control and Left Shift held are R1 and L1 (Ctrl+Enter quick moves or crafts five, Shift+Enter splits or crafts the most). Q and E step the strip, `[` and `]` the tabs and the map's zoom. Esc, Backspace and E close as today. Lost: Q's one key quick move and Shift's one key split.
- Pointer: Ctrl+click quick moves a slot as today and Shift+click splits it (new), both on the press, focusing the pressed slot and starting no drag. Ctrl or Shift with a click on a recipe row crafts five or the most. The 0.25 s rest on a stack still splits (`Ui_State.pointer_split`). A click on a tab, the strip's included, picks it as today.
- String fields: the screens with fields (New world, Multiplayer, the touch layout's name) give the modifiers and the triggers no meaning, so Shift held for a capital changes nothing, and while a field is typed the touch layout editor shows only the entry, so typed Q and E resize nothing.

### Touch

The recipe browser's touch row gains Craft max (`Touch_Button.Craft_Most`): Craft, Craft 5, Craft max, Cancel last, Back, in the station mode too. Slots keep Split, the transfers and the rest split. The strip stays tappable until 0385.

Y stays the info panel on list rows (user, 2026-11-13): no tooltip change.

### Files and procedures

`data/bindings.sjson`

- Gamepad, in menus: out go Confirm on RIGHT_TRIGGER, Tab_Previous on LEFT_SHOULDER, Tab_Next on RIGHT_SHOULDER, Menu_Secondary on LEFT_TRIGGER, Menu_Quick_Move on RIGHT_TRIGGER and its comment. In come `Window_Previous` LEFT_TRIGGER, `Window_Next` RIGHT_TRIGGER, `Modifier_Most` LEFT_SHOULDER, `Modifier_Five` RIGHT_SHOULDER, all `context = "menu"`, under `// The triggers step the windows; the bumpers held with Confirm are R1 five and L1 the most (0276).`
- Keyboard, in menus: Menu_Secondary LEFT_SHIFT becomes `Modifier_Most`; Tab_Previous Q and Tab_Next E become `Window_Previous` and `Window_Next`; new `Tab_Previous` LEFT_BRACKET and `Tab_Next` RIGHT_BRACKET; Menu_Quick_Move Q goes with its comment; Menu_Quick_Move_Modifier LEFT_CONTROL becomes `Modifier_Five` under `// Held with Enter or a click: Left Control five (the quick move), Left Shift the most (the split).`
- Header, the shared controls sentence: E is Open_Inventory and Window_Next; on the inventory's strip the Open_Inventory press wins (`inventory_tabs`).

`src/input_actions.odin`: the `Action` change above, each new member commented; the comment of `Tab_Previous` (the tab step: `[` `]`, and the stick's flick without a binding).

`src/bindings.odin`

- `Retired_Action :: struct {name, replacement: string}` and `@(rodata) retired_actions := [?]Retired_Action{{"Menu_Secondary", "Modifier_Most"}, {"Menu_Quick_Move", "Modifier_Five"}, {"Menu_Quick_Move_Modifier", "Modifier_Five"}}`.
- `retired_action_replacement :: proc(name: string) -> (replacement: string, retired: bool)`: the table's lookup.
- `resolve_bindings`: before `resolve_binding`, a retired entry is skipped with `platform.log_printf("%s: %s.action: %s is no longer used and is ignored (%s took its place)", source, key_path, entry.action, replacement)`. Signature unchanged, so both `main.odin` callers and `parse_bindings_file` get it.

`src/ui_core.odin`

- `Ui_Input`: `secondary`, `quick_move`, `quick_move_down`, `quick_move_modifier` go; `window_previous`, `window_next` (edges) and `modifier_five`, `modifier_most` (held) come; `tab_previous`, `tab_next` are the tab step.
- `Confirm_Modifier :: enum u8 {None, Five, Most}`; `confirm_modifier_of :: proc(five, most: bool) -> Confirm_Modifier`: the one held, `None` for both or neither.
- `Ui_State`: `confirm_modifier: Confirm_Modifier` beside `confirm` and `click`; `pointer_split: bool`, the rest on a stack this frame.
- `ui_begin`: after `state.click`, `state.confirm_modifier = confirm_modifier_of(input.modifier_five, input.modifier_most)` and `state.pointer_split = false`, before `advance_slot_drag`.
- `advance_slot_drag`: its first case becomes `state.click && state.confirm_modifier != .None && !holding`, so with a stack held a modified click drags as a plain one.
- `step_slot_drag`: the rest case sets `state.focus, state.pointer_split = drag.slot, true`; the moved case also sets `state.confirm_modifier = .None`, so a drag's pick up never becomes a move.
- `ui_frame_sound_events`: `quick_moved` reads `state.confirm_modifier != .None`.

`src/ui_input.odin`

- `right_stick_tab_step :: proc(previous, current: [2]f32, wheel_open: bool) -> int`: 1 when `current.x > UI_STICK_NAVIGATION_THRESHOLD`, `abs(current.x) > abs(current.y)` and `previous.x <= UI_STICK_NAVIGATION_THRESHOLD`; -1 mirrored; 0 otherwise and while `wheel_open`.
- `make_ui_input`: `step := right_stick_tab_step(previous.look, current.look, .Hotbar_Radial in current.pressed)` (the letter wheel steers by the stick); `tab_previous = .Tab_Previous in just || step < 0`, `tab_next` mirrored; `window_*` from `just`, `modifier_*` from `current.pressed`. `scroll_stick` stays.

`src/ui_widgets.odin`

- `Ui_Tabs_Mode.Bumpers` becomes `.Stepped`, comment: the tab step cycles the tabs.
- `Glyph_Button`: `Tab_Previous`, `Tab_Next`, `Secondary`, `Quick_Move` go; `Tabs`, `Window_Previous`, `Window_Next`, `Five`, `Most` come; `glyph_button_actions` gives them `.Tab_Next`, `.Window_Previous`, `.Window_Next`, `.Modifier_Five`, `.Modifier_Most`.
- `glyph`: `.Tabs` returns `tabs_glyph(state)`. New `tabs_glyph :: proc(state: ^Ui_State) -> Glyph`: `{.Stick_Right, ""}` on the gamepad; on the keyboard one key cap `"<previous> <next>"` of the first keyboard bindings of `Tab_Previous` and `Tab_Next` (`control_label`, "[ ]"), `glyph_unbound` when either has none.
- `control_label_keys`: LEFT_BRACKET `glyph_keyboard_left_bracket`, RIGHT_BRACKET `glyph_keyboard_right_bracket`.
- A modifier's hint is the pair the tab hints use today, `{.Five, ""}` then `{.Confirm, label}`, which `glyph_hints_that_fit` drops together; `Glyph_Hint` unchanged.
- `Touch_Button.Craft_Most` after `Craft_Five`, key `touch_button_craft_most`.

`src/ui_inventory.odin`

- `inventory_screen`: the two `quick_move` lines at its top go; `modifiers := slot_modifier_input(state^, stack_is_empty(player.held.stack))` goes to `apply_inventory_quick_move_input`, and `Inventory_Slot_Input.secondary = modifiers.split_pressed`.
- `Slot_Act :: enum u8 {Primary, Quick_Move, Split}`; `slot_act :: proc(modifier: Confirm_Modifier, hand_empty: bool) -> Slot_Act`: Primary with a stack in hand or no modifier, else Quick_Move for Five, Split for Most.
- `Slot_Modifier_Input :: struct {quick_move_pressed, quick_move_down, split_pressed: bool}`; `slot_modifier_input :: proc(state: Ui_State, hand_empty: bool) -> Slot_Modifier_Input`: with `pressed := state.confirm || state.click` and `act := slot_act(state.confirm_modifier, hand_empty)`, `quick_move_pressed = pressed && act == .Quick_Move`, `quick_move_down = (state.input.confirm_down || state.pointer_held) && act == .Quick_Move`, `split_pressed = (pressed && act == .Split) || state.pointer_split`.
- `apply_inventory_quick_move_input :: proc(state: ^Ui_State, screen_context: Screen_Context, slots: Slot_Grid_Result, modifiers: Slot_Modifier_Input) -> (activated: int)`: `pressed` and `down` from `modifiers`; returns -1 when `quick_move_pressed || split_pressed`, so neither also picks up.
- `inventory_tabs`, interim until 0385: its `ui_tabs` call reads the window step as its tab step (`state.input.tab_previous, state.input.tab_next = input.window_previous, input.window_next`, both false on an `open_inventory` press as today, `state.input` restored after), so the flick and `[` `]` never step the strip. Its comment says so.
- `inventory_glyph_bar`: the quick move hint becomes `{.Five, ""}, {.Confirm, text("hint_quick_move")}`, the split `{.Most, ""}, {.Confirm, text("hint_split")}`.

`src/ui_machine.odin`

- `machine_screen`: the two `quick_move` lines go; it computes `modifiers` as the inventory does and passes it on.
- `apply_quick_move_input(state, screen_context, handle, slots, player_slots, machine_slots, modifiers: Slot_Modifier_Input) -> (player_activated, machine_activated: int, hand_activated: bool)`: `pressed`, `down` from `modifiers`; returns -1, -1, false when `quick_move_pressed || split_pressed`.
- `apply_machine_screen_input(state, screen_context, handle, kind, slots, player_slots, machine_slots, modifiers: Slot_Modifier_Input)`: both `secondary` fields are `modifiers.split_pressed`.

`src/ui_recipes.odin`

- `recipe_category_tabs`: `selected = step_tab_selection(selected, count, state.input.tab_previous, state.input.tab_next)` before the selection is written, so the flick steps the categories in every mode; left and right still step the focused row.
- `craft_count :: proc(modifier: Confirm_Modifier, most: int) -> int`: 1, `RECIPE_CRAFT_MANY_COUNT`, or `max(most, 1)`.
- `apply_recipe_craft_input :: proc(state: ^Ui_State, screen_context: Screen_Context, activated: int, selected_shown: bool, button: Touch_Button)`: the recipe is the activated one, or for Craft, Craft 5 and Craft max the selected one while shown; the modifier is `state.confirm_modifier`, or the button's (none, five, most); for most `planned_craft_count(player.crafting, player.inventory, recipes, screen_context.unlocks^, recipe, screen_craft_makers(screen_context), screen_context.free_crafting)`; `queue_checked_crafts` with `craft_count`. Cancel is `state.input.context_action || button == .Cancel_Craft`, the rest as today. `recipe_screen` drops `list_focused`, and `recipe_list`'s `focused` result goes with its one reader.
- `recipe_touch_buttons(false)`: `{.Craft, .Craft_Five, .Craft_Most, .Cancel_Craft, .Back}`.
- `recipe_glyph_bar :: proc(state: ^Ui_State, strip: bool)` (`strip` is `!at_station`) and `recipe_selection_glyph_bar`: Hints below.

Other files:

- `src/ui_screens.odin`: `settings_screen`'s hints, `{.Tabs, text("hint_tabs")}` in place of the Tab pair.
- `src/ui_technologies.odin`, `src/ui_journal.odin`, `src/ui_statistics.odin`, `src/ui_map.odin`: hints below; `map_zoom_step` keeps its code (the flick and `[` `]` arrive as the tab step), its comment changes.
- `src/ui_touch_layout_editor.odin`: `resize_selected_touch_element` reads `window_next` and `window_previous`; its comment names LT and RT, Q and E.
- `src/ui_launch_pad.odin`, `src/inventory_interaction.odin`, the comment of `step_slot_drag`: the comments naming the bumpers, L2 and `Menu_Secondary`.

### Strings

`data/strings/en.sjson`, new: `hint_craft_most = "Craft max"`, `touch_button_craft_most = "Craft max"`, `glyph_keyboard_left_bracket = "["`, `glyph_keyboard_right_bracket = "]"`. Changed: `touch_layout_element_tooltip` ends "LT and RT resize it". No data key beyond the bindings; the flick reuses `UI_STICK_NAVIGATION_THRESHOLD` (0.5).

### Hints

Gamepad glyph shown, keyboard key cap in its place (R1 Ctrl, L1 Shift, A Enter, LT RT Q E, RS "[ ]", RS click X).

| Screen | Glyph bar | Touch row |
| --- | --- | --- |
| Inventory, empty hand | A Pick up, R1 A Quick move (a stack focused), RS click Drop (a stack focused), L1 A Split (two or more), X Sort or Configure, B Close | same |
| Inventory and machine panel, stack in hand | same | same |
| Machine panel, empty hand | the inventory's without Drop | same |
| Recipes with the strip | A Craft, R1 A Craft 5, L1 A Craft max, X Cancel last, LT RT Tabs (the strip), B Close | Craft, Craft 5, Craft max, Cancel last, Back |
| Station browser | as Recipes with RS Tabs (the categories) in place of LT RT | as Recipes |
| Picker | A Choose, RS Tabs, B Back | same |
| Technologies | A Research, LT RT Tabs, B Close | same |
| Journal | RS Chapters, B Close | same (Back) |
| Statistics | RS Tabs, B Close | same (Back) |
| Map | RS Zoom, B Close | same |
| Settings | A Select, B Back, RS Tabs, Y Info | same (Back) |
| Touch layout editor | A Select, LT RT Size, B Back | same (none) |

### Tests

New:

- `src/ui_core_test.odin`, `test_confirm_modifier_takes_one_bumper`: the four combinations of `confirm_modifier_of`.
- `src/ui_input_test.odin` (new), `test_the_right_stick_steps_tabs_once_per_flick`: (0, 0) to (0.8, 0.1) gives 1; (0.8, 0.1) to (0.9, 0) gives 0; (0, 0) to (-0.8, 0) gives -1; (0, 0) to (0.6, 0.7) gives 0; (0, 0) to (0.8, 0) with the wheel open gives 0; `make_ui_input` with looks (0, 0) then (0.8, 0) sets `tab_next` alone.
- `src/ui_inventory_test.odin`:
  - `test_slot_act_follows_the_modifier_and_the_hand`: the six combinations.
  - `test_modifiers_with_a_on_a_slot` (audit harness, after `apply_player_commands`): coal 5 on the focused hotbar slot, `confirm` with `modifier_five` moves it to the backpack and the hand stays empty; stone 4 with `modifier_most` lifts 2; with both lifts 4; stone in hand, `modifier_five` on an empty slot places it; on a chest's slot `modifier_five` moves the stack into the inventory; the mouse: `mouse_pressed` with `modifier_most` on stone 4 lifts 2, with `modifier_five` quick moves.
- `src/ui_recipe_browser_test.odin`:
  - `test_craft_count_follows_the_modifier`: (None, 40) 1, (Five, 40) 5, (Most, 40) 40, (Most, 0) 1.
  - `test_modifiers_with_a_on_a_recipe`: a focused recipe with materials for N crafts, `confirm` queues a `Craft_Command` of 1, with `modifier_five` 5, with `modifier_most` N (the planner's count read first); without materials `modifier_most` queues nothing and toasts; `context_action` with a queued craft queues `Cancel_Craft_Command`; the station browser the same.
  - `test_modifiers_where_five_and_most_mean_nothing`: on a technology row `confirm` with `modifier_five` queues what `confirm` alone does; the picker's `confirm` with `modifier_most` chooses the recipe; Pause's Resume with `modifier_five` closes the menu.
  - `test_recipe_categories_follow_the_tab_step`: `tab_next` moves `filter.category` to the next shown category and clears the tags, in the picker too; `tab_previous` back; a `window_next` frame in the picker changes neither the screen nor the category.
- `src/bindings_test.odin`:
  - `test_a_retired_action_in_a_configuration_is_ignored`: the three retired actions and one Jump resolve with no problem to one binding, Jump; `retired_action_replacement` gives the table; "Menu_Secondar" still fails as an unknown action.
  - `test_no_menu_control_carries_two_menu_meanings`: in the shipped bindings each device and control carries at most one action of context menu or both, but {Open_Inventory, Context_Action} on gamepad WEST and {Open_Inventory, Window_Next} on keyboard E; no control of `Window_*` or `Modifier_*` carries Confirm.

Changed:

- `bindings_test.odin`: the raylib table loses LEFT_TRIGGER_2 Menu_Secondary, RIGHT_TRIGGER_2 Confirm and Menu_Quick_Move, LEFT_TRIGGER_1 Tab_Previous, RIGHT_TRIGGER_1 Tab_Next and gains LEFT_TRIGGER_2 Window_Previous, RIGHT_TRIGGER_2 Window_Next, LEFT_TRIGGER_1 Modifier_Most, RIGHT_TRIGGER_1 Modifier_Five; the keys swap LEFT_SHIFT Menu_Secondary, Q and E Tab_*, Q Menu_Quick_Move, LEFT_CONTROL Menu_Quick_Move_Modifier for LEFT_SHIFT Modifier_Most, LEFT_CONTROL Modifier_Five, Q Window_Previous, E Window_Next, LEFT_BRACKET Tab_Previous, RIGHT_BRACKET Tab_Next; the SDL shoulders carry Modifier_Most and Modifier_Five; the triggers `{.Right = {.Mine, .Window_Next}, .Left = {.Place, .Use_Item, .Window_Previous}}`; the raylib unsupported count stays 11.
- `ui_theme_test.odin`: the glyph tables lose the four rows and gain `.Tabs` Stick_Right "[ ]", `.Window_Previous` Trigger_Left "Q", `.Window_Next` Trigger_Right "E", `.Five` Bumper_Right "Ctrl", `.Most` Bumper_Left "Shift".
- `ui_core_test.odin`: `test_tabs_follow_bumpers` becomes `test_tabs_follow_the_tab_step`; in `test_focus_tabs_step_on_left_and_right` the comment reads that the tab step is not the row's.
- `ui_inventory_test.odin`: `test_bumpers_step_the_inventory_tab_strip` becomes `test_the_triggers_step_the_inventory_tab_strip` (`window_next`, `window_previous`; a `tab_next` frame leaves the tab); `test_open_inventory_closes_the_strip` presses `open_inventory` with `window_next`; `click.quick_move_modifier` becomes `click.modifier_five`.
- `ui_audit_test.odin`: `test_inventory_strip_pause_menu_and_initial_focus` and `test_the_configure_popup_picks_the_foundation_block` step with `window_next` (and `window_previous`); `test_inventory_screen_quick_move_and_drop` and `player_command_slots_test.odin` (two frames) press `{confirm = true, modifier_five = true}`.
- `ui_touch_layout_editor_test.odin`: `window_next` for `tab_next`.
- `ui_pointer_test.odin`: `test_touch_row_buttons_by_screen` expects Craft_Most; `test_a_tap_on_a_recipe_selects_it_and_the_row_crafts` taps Craft max too (the planner's count queued).

### UI audit

No case is added or made obsolete. Changed by the drawing alone, at every audit size and text scale (`audit_every_case`): "recipes touch row" and "crafting station touch row" show five buttons with Craft max, checked whole (`audit_touch_labels_whole`); the recipe and inventory glyph bars carry the modifier pairs, which the smallest sizes drop from the end with their partners; the Tabs hints show the right stick or "[ ]".

### Docs

- `doc/input.md`, Bindings: a bullet on the retired actions (`retired_actions`, the log line); the shared controls bullet adds E (Open_Inventory and Window_Next). Gamepad, the menus column: right stick (flick: the window's tabs; up and down: lists, the map's zoom; click `Menu_Drop`), R2 and L2 (the next and previous window: the inventory's strip), A (with R1 five, with L1 the most), L1 and R1 (held with A), X (cancel last in the recipe browser). Keyboard and mouse: the menus sentence (Q and E the strip, `[` `]` the tabs, Ctrl and Shift held with Enter or a click).
- `doc/ui.md`: Focus and navigation (the controls bullet); Pointer (Shift with a click); Item slots, Gamepad, Pointer and Active grid (L1 and R1 with A, a stack in hand ignores them, `Ui_State.pointer_split`); Touch button row (Craft max); Inventory tab strip (LT and RT step it, Q steps back from all three, E closes); Recipe browser (the categories' tab step in every mode, A with the modifiers, X); Other screens (the map's zoom); Touch layout editor (LT and RT, Q and E).
- `doc/hud.md`: no change; it names no screen control (checked).
- `doc/code_map.md`: `Ui_State`'s field count two more.

### Hand-back check

- Memory a frame draws from, file writes, parsed numbers, per tick rates, shared budgets: do not apply.
- A start-up load the game can make fail: an old configuration naming a retired action logs and loads (`resolve_bindings`), tested.
- Save layout: no save changes; `Action` renumbers inside 64 bits, covered by the build check. The log names it.
- Growing lists and long strings: the longer glyph bars drop from the end with their pairs, the five button recipe row is checked whole, at the smallest audit sizes.
- An audit case made obsolete: none.
- Tests and the state directory: the configuration tests resolve entries in memory.

### Main after this item

Every screen as today but its controls: the strip on the triggers, the tabs on the flick and `[` `]`, the modifiers on the bumpers and Ctrl, Shift, Craft max on touch. B, Menu and the taps unchanged. Gamepad, keyboard and touch play.

### Decisions (2026-11-13)

User: B pops one level (unchanged here); Craft max as a third button; Y keeps the info panel. Main agent: `[` and `]`; the right stick keeps scrolling; X cancels the last craft; LT and RT, Q and E resize. Design, approved: removed actions in an old configuration are skipped with a log line, not remapped; with a stack in hand the modifiers are ignored; Shift+click splits; a flick steps the map's zoom.

### Deviations (implementation, 2026-11-13)

- The bindings comment and header split the specification's semicolon sentences in two.
- `doc/code_map.md` counts its fields from its own baseline (`Ui_State` two more, `Viewport_Interaction` one more), which was behind the structs already.
- `craft_button_modifier(button)` maps the touch row's craft buttons to their modifier.
- `right_stick_tab_step :: proc(armed: bool, stick: [2]f32, wheel_open: bool) -> (step: int, armed_after: bool)` replaces the edge test on the previous look: a step needs the flick armed and |x| over `UI_STICK_NAVIGATION_THRESHOLD` with |x| > |y|, and disarms it. |x| at or under the new `UI_STICK_FLICK_REARM_THRESHOLD` (0.3, `ui_core.odin`) arms it. A flick while the letter wheel is open disarms without a step.
- `make_ui_input(previous, current, flick_armed) -> (input, flick_armed_after)`. The armed bool lives in `Viewport_Interaction.tab_flick_armed` beside `previous_input`, written back by `build_viewport_ui` and the two harnesses in `command_input_test.odin`.
- `map_zoom_step`: on a frame whose tab step comes with the stick mostly sideways (the flick) the stick's vertical part does not zoom, and the flick's step starts the held stick's repeat wait.
- `advance_slot_drag` takes the modified branch only on a widget with `.Item_Slot` (new `widget_is_item_slot`). Off the slots it clears `confirm_modifier` for the frame, so the click is a plain one and `slot_modifier_input` reports nothing.
- `ui_frame_sound_events`: `quick_moved` also needs `slot_drag.phase == .None`, which is how the hand shows there: with a stack held the modified press started a drag, which sounds on the drop.
