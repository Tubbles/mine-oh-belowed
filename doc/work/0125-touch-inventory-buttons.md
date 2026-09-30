# 0125: A tappable button row under the inventory screens

Status: todo

## Goal

The user, playing the phone build (2026-09-30): the bottom row of the inventory should be tappable buttons, "sort" sorting only the currently active inventory, not every open one; no key glyph next to them ("like 'E', there is no keyboard"); more functions in the row: transfer all, transfer all of type, split.

## Change

- Active inventory: the grid that holds the focused slot (the last tapped or focused one). `Inventory_Slot_Input.context_action` (sort) applies to that grid alone; a screen with two grids (a machine panel, a chest) sorts the one the focus is in. Today `apply_slot_context` sorts the grid it is called on; make sure only the active one is called.
- With the `Touch` pointer source (0124) the glyph bar of the inventory screens (`inventory_glyph_bar`, and the machine panels' equivalent) becomes a row of `ui_button`s without glyphs: Sort, Split (the focused stack of two or more, half into the held stack, as L2 does), Transfer all (every stack of the active grid into the other grid of the screen, what fits) and Transfer all of type (every stack of the focused slot's item from the active grid into the other grid). Transfer all and Transfer all of type show only on a screen with two grids; in the player's own inventory screen the row is Sort and Split. With a keyboard or a gamepad the glyph hints stay as they are. Reuse the machine panels' transfer code (`quick_transfer.odin`, `apply_transfer_button`); the existing Take all, Store all and Fill rows of the machine panels stay.
- Assumption to state in the log: the button row replaces the glyph bar for touch only, so the couch keeps its glyph hints unless `--touch-overlay` is on.
- Strings in `data/strings/en.sjson`. `doc/ui.md`: the row, the active inventory rule. `doc/log/<date>.md`: the decisions.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests: sort touches only the active grid in a two grid screen; each button's effect through the screen frame helpers; the row shows without glyphs for touch and the glyph bar shows for a gamepad; the transfer buttons hidden in the player's inventory screen.
- The user, on the phone.
