# 0124: Drag to move items on a touch screen

Status: todo

## Goal

The user, playing the phone build (version code 222, 2026-09-30): drop the sequenced tapping (tap stack A, then tap empty slot B to move A to B) in favour of dragging only; a single tap selects the slot with the cursor; press and hold on a stack splits it in half and starts a drag; while dragging, the stack follows the finger with an offset to the north so the upper half of it stays visible; tapping outside a window (the inventory, a machine panel) closes it.

Assumptions (state them in the log): the drag scheme applies to every pointer source (mouse, trackpad, touch), so the couch trackpad behaves like the phone and the desktop with `--touch-overlay` tests it; the gamepad's focus path (A picks up, A puts down, L2 splits) is unchanged, since a gamepad cannot drag; the north offset applies to touch only, a mouse or trackpad pointer keeps the stack under the cursor.

## Change

- A pointer source `Touch` (`Pointer_Source`, `ui_core.odin`): the raylib backend's pointer counts as touch when it came from a touch point or when the touch overlay is on (`touch_overlay_on`), so the desktop with `--touch-overlay` behaves like the phone. `detect_input_device` keeps treating it as the pointer.
- Slots (`ui_item_slot`, `ui_slot_grid`, `apply_inventory_slot_input` and the machine panels' grids): a press on a stack with a pointer starts a drag (the stack becomes the held stack, `Held_Stack`, as a pick up does today); the release over a slot applies `apply_slot_primary` on that slot (drop, merge, swap); a release elsewhere returns the stack (`return_held_stack`). A press and release on the same slot without a drag is a tap: it focuses the slot and picks nothing up. A press held for the hold delay (`TOUCH_HOLD_SECONDS`, `touch_overlay.odin`, or a UI constant of the same value) on a stack of two or more splits it (`apply_slot_split`) and starts the drag with the half. The gamepad's activated path stays as it is.
- The dragged stack (`held_stack_rectangle`, `ui_inventory.odin`): with the `Touch` source its rectangle sits one slot height above the pointer; with the other sources under the pointer as today.
- Tap outside: a pointer press and release outside every panel rectangle of the screen (the screen's panels, the glyph bar or button row, the hotbar) with nothing held closes the top screen (`pop_screen`), as Back does. Not while dragging.
- `doc/ui.md` (the inventory and item handling sections) and `doc/input.md` (touch): the drag scheme, the tap, the hold split, the outside tap. `doc/log/<date>.md`: the decisions and assumptions.

## Verify

- `./build.sh check`, `./build.sh check-android`, `./build.sh test`. Tests through the screen frame helpers: a press, move and release moves a stack; a tap only focuses; a hold splits and drags the half; a release outside returns the stack; a tap outside the panel closes the screen; the gamepad path unchanged (existing tests keep passing); the touch rectangle offset.
- The user, on the phone.
