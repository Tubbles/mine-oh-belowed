# 0187: Playtest 1: the walk counter, placing without a foundation, the position readout

Status: todo (playtest 1 of the slice, 2026-10-03)

## Goal

Three findings of the first playtest of the slice, each small: the quest "walk ten blocks" cannot complete, Place with a machine held over bare ground does nothing visible, and the player cannot read their height.

## Change

- The walk counter: `record_walked` (`statistics.odin`) is fed by the block player's tick only (`player.odin`); the field player's tick records the feet's displacement per tick in millimetres (a flight does not count, as the block world's rule), so the walk objective of chapter 1 completes on the field.
- Placing without a foundation: `field_player_placement` (`entity_frames.odin`) returns nothing when a machine other than a foundation is held and no frame is targeted, so the press neither places nor refuses. It becomes a refusal (`Field_Edit_Refusal.Needs_Foundation`, the toast "Needs a foundation under it") raised on the press, and the HUD's tool line says what the held item needs; the ghost over bare ground draws red.
- The position readout: the diagnostics page's World page (`diagnostics.odin`, F3) prints the field player's feet as latitude, longitude and the height above the planet radius in metres, and the sample under the feet with its material; the block line stays for the block world's tests.
- `doc/hud.md` (the tool line), `doc/developer_tools.md` (the page) updated.

## Verify

- The build and check commands of 0168.
- Tests: ten metres walked on the field count ten blocks for the quest and a flight counts none; Place with a furnace held over the ground raises one `Needs_Foundation` event; the diagnostics page prints the field line in a field session (the draw list test).
- The couch: chapter 1's first quest completes; a furnace over the ground toasts; F3 shows the height.
