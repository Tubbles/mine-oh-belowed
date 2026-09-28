# 0090 Quick transfer inside the inventory, Drop as a shortcut only

Status: todo
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

Files a subagent may touch: `src/ui_inventory.odin`, `src/quick_transfer.odin`, `src/quick_transfer_test.odin`, `src/inventory.odin`, `src/inventory_test.odin`, `src/player_interaction_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, the docs above, this file.
