# 0078 Quick transfer in panels, number keys for the hotbar

Status: todo
Milestone: M11

## Goal

Couch request (2026-09-27): moving items between the inventory and a chest, furnace, drill or any other machine one stack at a time is too slow; a fast transfer is needed in every panel. Also from the same session: with keyboard and mouse the number keys must select the hotbar slots.

## Deliverables

- Quick move: a new menu action `Menu_Quick_Move`, gamepad right trigger (R2) and keyboard Q, plus Left Control with a click for the mouse. On a focused or hovered stack it moves the whole stack to the other side of the open panel: from the inventory into the machine (through `entity_accepts`, so fuel lands in the fuel slot, ore in the input, anything into a chest) and from a machine slot into the inventory; what does not fit stays. Holding the action for half a second (or a second press within half a second) moves every stack of that item on that side. A short toast or the slot flashing is not needed; the stacks moving is the feedback.
- Transfer buttons on machine panels where they make sense: "Take all" on chests and on furnace, crafting machine and recycler outputs (everything that fits into the inventory), "Store all" on chests (every inventory stack the chest takes, matching items first), "Fill" on fuel slots and lab pack slots (from the inventory, up to the insertion limit). Buttons are focusable and in the glyph bar's language; the glyph bar shows the quick move hint while a stack is focused.
- Hotbar keys: keyboard 1 to 8 select hotbar slots 1 to 8 directly in the world (actions `Hotbar_Slot_1` to `Hotbar_Slot_8`, bound in `data/bindings.sjson`; 9 and 0 stay free since the hotbar has eight slots). The bracket keys keep cycling.
- Tests: quick move to a chest, a furnace (fuel and ore go to their slots), a drill's fuel slot and a lab; move all of one item; Take all, Store all and Fill; a rejected move leaves the stack in place; the hotbar slot actions select the slot; the UI audit passes with the buttons.

## Verify

- Builds and tests pass.
- User: open a chest, press R2 on a stack and it jumps across; hold R2 and every stack of that item follows; press 3 and the third hotbar slot is selected.
