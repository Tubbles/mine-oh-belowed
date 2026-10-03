# 0078 Quick transfer in panels, number keys for the hotbar

Status: implemented
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

## Notes

Implemented by a subagent (2026-09-27). Verified headless only: `odin check src -vet -strict-style`, `./build.sh test` (690 tests, new ones in `src/quick_transfer_test.odin` and `src/player_interaction_test.odin`, the UI audit covers every panel with its buttons), `./build.sh`, `./build.sh release`. The look and feel is not verified.

Files: new `src/quick_transfer.odin` (quick move state, move, move all, Take all, Store all, Fill, the button rows), `src/quick_transfer_test.odin`; changes to `src/input_actions.odin`, `data/bindings.sjson`, `src/ui_input.odin`, `src/ui_core.odin`, `src/ui_machine.odin`, `src/ui_crafting_machines.odin`, `src/ui_fluid.odin`, `src/ui_inventory.odin`, `src/ui_widgets.odin`, `src/player_interaction.odin`, `src/bindings_test.odin`, `src/player_interaction_test.odin`, `data/strings/en.sjson`.

- Controls: `Menu_Quick_Move` on R2 and Q (menu), `Menu_Quick_Move_Modifier` on Left Control (menu), held with a left click. R2 stays Confirm: in a machine panel the quick move press takes a slot's activation, so R2 on a slot quick moves and on a button confirms; elsewhere R2 confirms as before. Q stays Tab_Previous; the machine panel drops the tab step on a quick move frame (the launch pad's tabs). `Hotbar_Slot_1` to `Hotbar_Slot_8` on keys 1 to 8 (world), handled in `cycle_hotbar_slot`, where a slot key wins over a cycle step.
- Quick move targets the clicked or confirmed slot, else the focused one. Into the machine it goes the way an inserter puts it: a chest or the capsule takes the stack at once, any other entity one item at a time while `entity_accepts` routes it, so the insertion limits hold (a lab or crafting machine input takes up to two crafts' worth). Out of any machine slot with `inventory_add`. A second press on the same side within 0.5 s, or holding for 0.5 s, moves every stack of the item on that side (the main grid before the hotbar going in). The state (`Quick_Move_State` in `Ui_State`) is tied to the open entity.
- Buttons, in one row under the machine's slots (stacked when narrower than 150 units per button): Take all on chests and the capsule (every slot) and on furnaces and crafting machines (their `giving_slots`, the outputs); Store all on chests and the capsule, in the order main grid stacks of items the container holds, other main grid stacks, then the hotbar in the same two groups; Fill on furnaces, burner crafting machines, burner drills, burner inserters, boilers, combustion generators (the fuel slot) and labs (every pack slot), from the inventory, main grid first, only into those slots and up to the insertion limit. The panel heights add `transfer_rows_height`, and the machine side already scrolls (0046).
- Slot edits go the same way as the panel's other slot edits: directly on the world's slots in the UI frame between ticks.
- The glyph bar shows "Quick move" (R2 or Q) while a stack is focused and nothing is held in a machine panel.
