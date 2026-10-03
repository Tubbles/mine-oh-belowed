# 0202: The configure widget: a modal for the highlighted item

Status: todo (user, 2026-10-03, on 0193's rows: "That doesnt look like a widget, that is a permanent ui panel. A widget would be something that pops up as a modal interaction, lets say a 'configure' mode. Highlighting the foundation activates a new keybind -> configure widget pops up, the player can configure how all foundations work (not just the highlighted stack), close the widget and then use it in game"; after 0195, before 0201)

## Goal

Configuring an item is a modal moment, not a panel that lives on the inventory view. 0193 drew two permanent strips under the hotbar; they go. Highlighting a configurable item on the inventory view offers "Configure" in the hint row; the press opens a pop-up over the view with that item's settings, which apply to every item of its kind (the foundation block's size and height set the player's indices, as 0193's command does), and closing it returns to the view.

## Change

- A configurable item: the content says which (`configurable = "foundation_block"` on the item record, the one kind today; the pop-up's content is chosen by that key in Odin, the values stay in `game.sjson`), so a later item (a filter, a belt speed) reuses the mechanism.
- The pop-up is a screen pushed on the stack like the title's confirmation (`push_screen`): a small centred panel titled after the item ("Foundation blocks"), the size strip and the height strip from 0193 (`ui_tabs` in focus mode, the current choice marked, a pick queues `Foundation_Block_Command` and shows as pending until it applies), a Close button; Back closes it too; a tap or click off the panel closes it (`doc/ui.md`, Tap or click off a panel). Nothing on the view behind reacts while it is open.
- The highlighted slot is the focused one with a gamepad or the keyboard and the hovered one with the pointer, as the hint row already decides for Drop and Split; with touch the tapped slot. The hint row shows "Configure" with the Context_Action glyph when the highlighted item is configurable and "Sort" otherwise.
- The inventory view's foundation rows of 0193 are removed (`foundation_block_rows`, the compact layout, its audit case replaced by the pop-up's audit case at every size with the pop-up open over the inventory).
- `doc/ui.md` (the configure pop-up, the hint), `doc/content.md` (the item record's `configurable`), the log; `doc/architecture.md` if the command's description names the rows.

## Controls (the design pass, main agent, 2026-10-03)

- Layer: the menu context, inventory view. Context_Action (keyboard F, gamepad West) is the menu's smart action already: with a configurable item highlighted it is Configure and opens the pop-up, with anything else highlighted it stays Sort, and the hint row names which. No new binding.
- In the pop-up: Navigate moves the focus between the strips and the Close button, Navigate_Left and Navigate_Right step a strip, Confirm picks, Back closes; the pointer clicks; touch taps and the touch row's Back closes. The world's controls are untouched.
- The hint row of the pop-up: Confirm "Pick", Back "Close".

## Verify

- The build and check commands of 0168.
- Tests: with a foundation highlighted the hint reads Configure and Context_Action opens the pop-up; with a furnace highlighted it reads Sort and sorts; a pick in the pop-up queues the command; Back closes it and the view behind is unchanged; the UI audit draws the pop-up at every size; the 0193 rows are gone from the view's draw list.
- The couch: highlight the foundation, F, pick 5x5 and 2 high, close, build.
