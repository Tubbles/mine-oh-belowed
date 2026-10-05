# 0279: The toolbar edit mode

Status: todo (2026-10-05)

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
