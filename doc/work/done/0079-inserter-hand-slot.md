# 0079 The inserter's hand in its panel

Status: implemented
Milestone: M11

## Goal

Couch request (2026-09-27): gravel from a coal vein ends up in the hand of an inserter feeding a coal line, the target never takes it, and the line is stuck until the inserter is picked up and placed again. The gravel stall is a kept early game mechanic (sorting is the answer), so the fix is a way out: the player takes the item from the inserter's panel. In the user's words: "maybe we should just be able to transfer the item from the inserter inventory UI?"

## Deliverables

- Hand slot: the inserter panel (`inserter_slot_region` in `src/ui_machine.odin`) gets a row under the fuel or filter row with one slot showing `Inserter.held` and the label "In hand" (new string `inserter_hand`), for burner, electric and filter inserters alike. The slot is always drawn, empty when the hand is empty, so the layout does not jump. `machine_area_height` for `.Inserter` grows by the row.
- Taking: the hand slot is focusable and clickable like a machine slot. Confirm or a click with an empty cursor lifts the stack onto the cursor. Quick move (R2, Q, Left Control with a click, `apply_quick_move_input` in `src/quick_transfer.odin`) moves it into the inventory; what does not fit stays in the hand. The slot takes nothing in: a stack on the cursor stays there, and the hand is not part of the distribute gesture. The hand is not one of `entity_slots`, so give it its own path the way the filter slot has (`filter_activated` and `inserter_filter_after_input`) rather than widening the slot arrays.
- Simulation: an inserter whose hand the player emptied finishes its swing on its own. Read `advance_inserter` and `drop_with_inserter` (`src/inserter.odin`): with an empty hand at the drop it swings back instead of retrying the drop or waiting for room, and its state text is no longer Waiting for room. Pin this in a test rather than relying on `entity_insert` of an empty stack.
- State text names the item: `Waiting_For_Room` reads "Waiting for room: Gravel" (new string `machine_state_waiting_for_room_item = "Waiting for room: {name}"`) in the panel's detail line and in the HUD target text (`entity_status_text`, the `.Inserter` case), the way `drill_state_text` does "Output refused: Gravel". The other inserter states keep their keys.
- Tests: taking the hand's stack empties it and the arm swings back and picks again; quick move of the hand into a full inventory leaves it in the hand; a cursor stack is not put into the hand; the state text names the held item; the UI audit (`src/ui_audit_test.odin`) passes with the new row.
- Docs: `doc/logistics.md` (Inserters section: the hand slot and the way out of the gravel stall), `doc/ui.md` (the machine panel paragraph), `doc/log/2026-09-27.md` (a short section), this item's Status and Notes.

## Verify

- `~/opt/odin/odin check src -vet -strict-style`, `./build.sh test`, `./build.sh release`.
- User: open an inserter stuck on gravel, press R2 on the hand slot, the gravel lands in the inventory and the inserter swings back and picks coal.

## Notes

Files a subagent may touch: `src/inserter.odin`, `src/ui_machine.odin`, `src/quick_transfer.odin`, `src/inserter_test.odin`, `src/quick_transfer_test.odin`, `src/ui_audit_test.odin`, `data/strings/en.sjson`, `doc/logistics.md`, `doc/ui.md`, `doc/log/2026-09-27.md`, this file. The `text()` calls in tests need `thread_string_table` set (see `test_drill_feeding_a_drill_stops_on_gravel_and_names_it` in `src/drill_test.odin`).

Implemented: `src/inserter.odin` (`inserter_state_text`, `drop_with_inserter` swings back with an empty hand), `src/ui_machine.odin` (the hand row, `inserter_hand_after_input`, the hand's activation through `apply_quick_move_input`, the quick move hint on a filled hand slot, the HUD text), `src/quick_transfer.odin` (`quick_move_targets_hand`, `take_inserter_hand`), `data/strings/en.sjson` (`inserter_hand`, `machine_state_waiting_for_room_item`), tests in `src/inserter_test.odin` and `src/quick_transfer_test.odin`, a UI audit case with a waiting inserter holding the longest item name in `src/ui_audit_test.odin`, and the docs. 699 tests pass.
