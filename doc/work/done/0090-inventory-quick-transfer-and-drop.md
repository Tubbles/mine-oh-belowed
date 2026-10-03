# 0090 Quick transfer inside the inventory, Drop as a shortcut only

Status: implemented
Milestone: M11

## Goal

Couch report (2026-09-28): the fast transfer should also work in the inventory screen, moving stacks between the hotbar and the backpack, and the Drop button should go, leaving Drop as a shortcut.

## Deliverables

- Quick move in the inventory screen (`src/ui_inventory.odin`, `src/quick_transfer.odin`): R2, Q or Left Control with a click on a focused stack moves it from the backpack grid to the hotbar or from the hotbar to the backpack (first free or matching slot, `inventory_add` restricted to the other section), a second press within half a second or a hold moves every stack of that item, as in the machine panel. The glyph bar shows the quick move hint on a focused stack.
- The Drop button row goes; Drop stays on the right stick click and X (`Menu_Drop`) and the glyph bar shows "Drop" on a focused or held stack. The inventory panel's height shrinks back.
- Tests (`src/quick_transfer_test.odin`, `src/player_interaction_test.odin`): moves in both directions, the matching slot first, the move all, the full section leaves the stack, the audit without the row.
- Docs: `doc/ui.md`, `doc/input.md` (Drop), `doc/log/2026-09-28.md`, this item.

## Verify

- Builds and tests pass.
- User: R2 on a backpack stack sends it to the hotbar and back; the right stick click drops; no Drop button.

## Notes

Implementation pointers, decisions taken so the item is unambiguous (main agent, 2026-09-28):

- The quick move reuses the machine panel's state machine (`advance_quick_move`, `Quick_Move_State` in `state.quick_move`, `src/quick_transfer.odin`) unchanged: `Quick_Move_Side` gains `Hotbar` and `Backpack`, the inventory screen's panel handle is `NO_ENTITY` (every machine panel has a real one, so a press in one never continues a move from the other), and `Quick_Move_Target.slot` is the inventory index. New pure procedures in `src/quick_transfer.odin`: `inventory_quick_move_target(focused: int) -> (Quick_Move_Target, bool)` (index below `HOTBAR_SLOT_COUNT` is `.Hotbar`, else `.Backpack`, -1 is none) and `apply_inventory_quick_move(inventory: Inventory, items: Item_Registry, step: Quick_Move_Step)`: `.Stack` moves the target slot's stack into the other section with `add_to_slots` on `inventory_hotbar` or `inventory_grid` (partial stacks of the item first, then empty slots, which is the "matching slot first" rule), what does not fit stays in the slot; `.All` does the same for every slot of the origin side holding the item. `apply_quick_move` and the machine panels are untouched.
- Input, in `src/ui_inventory.odin`: `apply_inventory_quick_move_input(state, screen_context, slots: Slot_Grid_Result) -> (activated: int)` mirrors `apply_quick_move_input` (`src/ui_machine.odin`): R2 or Q (`input.quick_move`, `quick_move_down`) or Left Control with a click (`quick_move_modifier`), the press takes the slot's activation so R2 (also Confirm) does not pick the stack up, and Q (also Tab_Previous on the keyboard) does not step the inventory tab strip while it quick moves, the rule `machine_screen` applies for the launch pad's tabs. Runs where `apply_inventory_slot_input` runs today, before it. `inventory_glyph_bar` gets `quick_move = true` from the inventory screen too, so a focused stack shows "Quick move".
- The Drop row goes: the button, `INVENTORY_DROP_ROW_HEIGHT` and its share of the panel height, so the inventory panel is `inventory_panel_height()` plus the strip, and the `inventory_drop` string goes. `state.input.drop` keeps calling `drop_player_stack` for the focused or held stack. The glyph bar shows Drop on a focused or held stack: `Glyph_Button` (`src/ui_widgets.odin`) gains `Drop` mapped to the right stick click on the gamepad (`glyph_key`, as the `Sprint` entry maps its stick click) and to the `Menu_Drop` key on the keyboard, string `hint_drop = "Drop"`; the held stack's bar shows Confirm, Drop, Back, the focused stack's bar adds Drop after Quick move.
- Tests: `src/quick_transfer_test.odin`: the target mapping; a backpack stack lands in the hotbar's partial stack of the item before its first empty slot and a hotbar stack lands in the backpack; `.All` moves every stack of the item from the origin side and none from the other; a full destination leaves the stack where it was; the machine panel's tests keep passing. The audit (`src/ui_audit_test.odin`) covers the inventory without the row; the drop by the action stays covered by whatever tests `drop_player_stack` today (`src/player_interaction_test.odin` or the loose items test), extended with a case that drops the focused stack through the input if none exists.
- Docs: `doc/ui.md` (the slot interaction paragraph: quick move between the hotbar and the backpack; the Drop paragraph: no button, the glyph bar hint), `doc/input.md` (the quick move sentence and the Drop sentence), `doc/log/2026-09-28.md`, this item's Status and an Implemented paragraph.

Files a subagent may touch: `src/ui_inventory.odin`, `src/ui_widgets.odin` (the Drop glyph only), `src/quick_transfer.odin`, `src/quick_transfer_test.odin`, `src/inventory.odin` (only if a helper is needed), `src/inventory_test.odin`, `src/player_interaction_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.

## Implemented

`inventory_quick_move_target`, `inventory_quick_move_destination`, `inventory_quick_move_origin`, `move_slot_to_section` and `apply_inventory_quick_move` in `src/quick_transfer.odin`; `apply_inventory_quick_move_input` in `src/ui_inventory.odin`, run before `apply_inventory_slot_input`, with `inventory_screen` clearing `tab_previous` on a quick move press. The Drop row, `INVENTORY_DROP_ROW_HEIGHT` and `inventory_drop` are gone; `Glyph_Button.Drop` (`glyph_gamepad_drop` R3, `glyph_keyboard_drop` X, icon `Stick_Right`) and `hint_drop` feed `inventory_glyph_bar`'s new `drop` flag. Tests: `test_inventory_quick_move_target`, `test_inventory_quick_move_between_hotbar_and_backpack`, `test_inventory_quick_move_all_of_one_item`, `test_inventory_quick_move_into_a_full_section_leaves_the_stack` (`src/quick_transfer_test.odin`) and `test_inventory_screen_quick_move_and_drop` (`src/ui_audit_test.odin`, the quick move and the drop through the screen's input, and the Drop hint).
