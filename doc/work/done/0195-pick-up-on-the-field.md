# 0195: Pick up machines and foundations on the field

Status: landed (2026-10-03, b4765d9; implemented user, 2026-10-03: "how do i remove foundations?"; after 0193, before 0194)

Note (implementation): a full inventory does not spill on the field; the pick up is refused with `Inventory_Full` and the entity stays, since the field has no loose items yet (`doc/log/2026-10-03.md`, Picking up on the field (0195)). This replaces "spilled as loose items" in Change and "a full inventory spills" in Verify.

## Goal

A placed machine or foundation can be taken back. Today the field's Dig acts on the terrain target only (`field_player_edit`, `field_mining.odin`: it needs `player.target.hit`, and a frame cell nearer than the terrain clears that target in `aim_field_player_at_frames`), and nothing on the field calls `pick_up_entity` (`entity_placement.odin`, the block world's hold Mine on a machine for `PICK_UP_SECONDS`). A foundation or machine placed on the field stays forever.

## Change

- Mine held on a frame cell in reach picks the entity up as the block world does: the same `PICK_UP_SECONDS`, the mining progress shown as for a block (the reticle's progress, `hud.odin`), the entity's stacks and the item itself into the inventory, what does not fit spilled as loose items at the cell, `Inventory_Full` toasted as today.
- A foundation is picked up only when nothing stands on it or hangs from it (a machine on the cell above, a belt or pipe through it, a torch on it); otherwise the refusal says what holds it (a new `Field_Edit_Refusal`, "Something stands on it"). A frame whose last cell goes is removed from the frame table, so a pad can be undone entirely; the pod and its pad (`machine_kind_is_placed_by_world`) refuse.
- A block placed by 0193 is picked up one cell at a time (one press per cell); a size cycle for picking up is not part of this item.
- Online every machine runs the pick up from the records, so the hash agrees; the prediction (0182) does not pick up.
- `doc/architecture.md` (Frames, the field player's edits), `doc/hud.md` (the hint beside a frame cell: "Pick up" with the Mine glyph) updated.

## Controls (the design pass, main agent, 2026-10-03)

- Mode: the world. Mine (mouse Left, gamepad Right trigger, the overlay's mining gesture) held on a frame cell in reach picks the entity up after `PICK_UP_SECONDS`, the same control and the same progress drawing as mining a block. No new control, no modifier.
- The aim decides: the nearer of the ground and a frame cell is the target as today, so Mine digs the ground when the ground is in front and picks up when a frame cell is. The hint beside a frame cell reads "Pick up" with the Mine glyph; the pod shows no hint and refuses.
- Place, Rotate, Sneak and Jump are untouched; a held tool does not change what Mine does to a frame cell (a pickaxe, a foundation, bare hands all pick up).

## Verify

- The build and check commands of 0168.
- Tests: Mine held on a lone foundation for `PICK_UP_SECONDS` removes it, returns the item and removes the empty frame; a foundation under a furnace refuses with the new refusal and the furnace is picked up first; the pod refuses; a full inventory spills; the hash matches on two sessions.
- The couch: the user places a foundation, picks it up, and the pad is gone.
